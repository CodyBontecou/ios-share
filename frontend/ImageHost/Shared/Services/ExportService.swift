import Foundation

enum ExportStatus: Codable {
    case pending
    case processing(progress: Double)
    case completed(downloadUrl: String)
    case failed(error: String)

    enum CodingKeys: String, CodingKey {
        case status
        case progress
        case downloadUrl
        case error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let status = try container.decode(String.self, forKey: .status)

        switch status {
        case "pending":
            self = .pending
        case "processing":
            let progress = try container.decodeIfPresent(Double.self, forKey: .progress) ?? 0.0
            self = .processing(progress: progress)
        case "completed":
            let downloadUrl = try container.decode(String.self, forKey: .downloadUrl)
            self = .completed(downloadUrl: downloadUrl)
        case "failed":
            let error = try container.decode(String.self, forKey: .error)
            self = .failed(error: error)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .status,
                in: container,
                debugDescription: "Unknown export status: \(status)"
            )
        }
    }
}

enum ExportError: LocalizedError {
    case notConfigured
    case invalidURL
    case networkError(underlying: Error)
    case invalidResponse
    case exportFailed(statusCode: Int, message: String?)
    case cancelled
    case downloadFailed(underlying: Error)
    case exportJobFailed(message: String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "App not configured. Please set up the backend URL and token in settings."
        case .invalidURL:
            return "Invalid backend URL. Please check your settings."
        case .networkError(let underlying):
            return "Network error: \(underlying.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server"
        case .exportFailed(let statusCode, let message):
            if let message = message {
                return "Export failed (\(statusCode)): \(message)"
            }
            return "Export failed with status code \(statusCode)"
        case .cancelled:
            return "Export was cancelled"
        case .downloadFailed(let underlying):
            return "Download failed: \(underlying.localizedDescription)"
        case .exportJobFailed(let message):
            return "Export job failed: \(message)"
        }
    }
}

final class ExportService: NSObject {
    static let shared = ExportService()

    private let keychainService = KeychainService.shared
    private var downloadTask: URLSessionDownloadTask?
    private var statusCheckTimer: Timer?

    private override init() {
        super.init()
    }

    // MARK: - Public Methods

    /// Starts an export job on the backend
    /// - Returns: The job ID for tracking the export
    func startExport() async throws -> String {
        let backendUrl = Config.effectiveBackendURL
        guard !backendUrl.isEmpty else {
            throw ExportError.notConfigured
        }

        guard let token = try keychainService.loadUploadToken(),
              !token.isEmpty else {
            throw ExportError.notConfigured
        }

        guard let url = URL(string: "\(backendUrl)/api/export") else {
            throw ExportError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ExportError.invalidResponse
        }

        guard httpResponse.statusCode == 200 || httpResponse.statusCode == 201 else {
            let message = String(data: data, encoding: .utf8)
            throw ExportError.exportFailed(statusCode: httpResponse.statusCode, message: message)
        }

        // Parse response to get job ID
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let jobId = json["id"] as? String else {
            throw ExportError.invalidResponse
        }

        return jobId
    }

    /// Checks the status of an export job
    /// - Parameter jobId: The ID of the export job
    /// - Returns: The current status of the export
    func checkStatus(jobId: String) async throws -> ExportStatus {
        let backendUrl = Config.effectiveBackendURL
        guard !backendUrl.isEmpty else {
            throw ExportError.notConfigured
        }

        guard let token = try keychainService.loadUploadToken(),
              !token.isEmpty else {
            throw ExportError.notConfigured
        }

        guard let url = URL(string: "\(backendUrl)/api/export/\(jobId)/status") else {
            throw ExportError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ExportError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8)
            throw ExportError.exportFailed(statusCode: httpResponse.statusCode, message: message)
        }

        // Parse status response
        let decoder = JSONDecoder()
        let status = try decoder.decode(ExportStatus.self, from: data)

        return status
    }

    /// Downloads the completed export archive
    /// - Parameters:
    ///   - jobId: The ID of the completed export job
    ///   - progress: Progress callback that receives values from 0.0 to 1.0
    /// - Returns: URL to the downloaded archive file
    func downloadArchive(jobId: String, progress: @escaping (Double) -> Void) async throws -> URL {
        let backendUrl = Config.effectiveBackendURL
        guard !backendUrl.isEmpty else {
            throw ExportError.notConfigured
        }

        guard let token = try keychainService.loadUploadToken(),
              !token.isEmpty else {
            throw ExportError.notConfigured
        }

        guard let url = URL(string: "\(backendUrl)/api/export/\(jobId)/download") else {
            throw ExportError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        return try await withCheckedThrowingContinuation { continuation in
            let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
            let task = session.downloadTask(with: request) { [weak self] tempUrl, response, error in
                if let error = error {
                    if (error as NSError).code == NSURLErrorCancelled {
                        continuation.resume(throwing: ExportError.cancelled)
                    } else {
                        continuation.resume(throwing: ExportError.downloadFailed(underlying: error))
                    }
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    continuation.resume(throwing: ExportError.invalidResponse)
                    return
                }

                guard httpResponse.statusCode == 200 else {
                    let message = "Status code: \(httpResponse.statusCode)"
                    continuation.resume(throwing: ExportError.exportFailed(statusCode: httpResponse.statusCode, message: message))
                    return
                }

                guard let tempUrl = tempUrl else {
                    continuation.resume(throwing: ExportError.invalidResponse)
                    return
                }

                // Move the file to a permanent location in the app's documents directory
                do {
                    let fileManager = FileManager.default
                    let documentsUrl = try fileManager.url(
                        for: .documentDirectory,
                        in: .userDomainMask,
                        appropriateFor: nil,
                        create: true
                    )
                    let destinationUrl = documentsUrl
                        .appendingPathComponent("exports")
                        .appendingPathComponent("\(jobId).zip")

                    // Create exports directory if it doesn't exist
                    let exportsDir = documentsUrl.appendingPathComponent("exports")
                    if !fileManager.fileExists(atPath: exportsDir.path) {
                        try fileManager.createDirectory(at: exportsDir, withIntermediateDirectories: true)
                    }

                    // Remove existing file if it exists
                    if fileManager.fileExists(atPath: destinationUrl.path) {
                        try fileManager.removeItem(at: destinationUrl)
                    }

                    // Move the downloaded file
                    try fileManager.moveItem(at: tempUrl, to: destinationUrl)

                    continuation.resume(returning: destinationUrl)
                } catch {
                    continuation.resume(throwing: ExportError.downloadFailed(underlying: error))
                }

                self?.downloadTask = nil
            }

            self.downloadTask = task

            // Store progress handler for URLSessionDownloadDelegate
            objc_setAssociatedObject(
                task,
                &progressHandlerKey,
                progress,
                .OBJC_ASSOCIATION_COPY_NONATOMIC
            )

            task.resume()
        }
    }

    /// Cancels an ongoing export job
    /// - Parameter jobId: The ID of the export job to cancel
    func cancelExport(jobId: String) async throws {
        // Cancel any ongoing download
        downloadTask?.cancel()
        downloadTask = nil

        // Stop any status polling
        statusCheckTimer?.invalidate()
        statusCheckTimer = nil

        let backendUrl = Config.effectiveBackendURL
        guard !backendUrl.isEmpty else {
            throw ExportError.notConfigured
        }

        guard let token = try keychainService.loadUploadToken(),
              !token.isEmpty else {
            throw ExportError.notConfigured
        }

        guard let url = URL(string: "\(backendUrl)/api/export/\(jobId)") else {
            throw ExportError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ExportError.invalidResponse
        }

        guard httpResponse.statusCode == 200 || httpResponse.statusCode == 204 else {
            let message = String(data: data, encoding: .utf8)
            throw ExportError.exportFailed(statusCode: httpResponse.statusCode, message: message)
        }
    }

    /// Polls the export status until completion or failure
    /// - Parameters:
    ///   - jobId: The ID of the export job
    ///   - statusUpdate: Callback invoked with status updates
    /// - Returns: The final completed status with download URL
    func pollUntilComplete(
        jobId: String,
        statusUpdate: @escaping (ExportStatus) -> Void
    ) async throws -> ExportStatus {
        while true {
            let status = try await checkStatus(jobId: jobId)

            await MainActor.run {
                statusUpdate(status)
            }

            switch status {
            case .completed:
                return status
            case .failed(let error):
                throw ExportError.exportJobFailed(message: error)
            case .pending, .processing:
                // Wait 2 seconds before checking again
                try await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }
}

// MARK: - URLSessionDownloadDelegate

private var progressHandlerKey: UInt8 = 0

extension ExportService: URLSessionDownloadDelegate {
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // This is handled in the completion handler
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }

        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)

        if let progressHandler = objc_getAssociatedObject(
            downloadTask,
            &progressHandlerKey
        ) as? (Double) -> Void {
            DispatchQueue.main.async {
                progressHandler(progress)
            }
        }
    }
}
