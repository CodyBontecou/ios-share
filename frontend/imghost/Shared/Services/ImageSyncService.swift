import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Service responsible for syncing images from the backend to local storage
final class ImageSyncService {
    static let shared = ImageSyncService()

    private let historyService = HistoryService.shared
    private let keychainService = KeychainService.shared

    private init() {}

    /// Sync images from backend to local storage
    /// This should be called after successful login or app launch when authenticated
    func syncImages() async throws {
        guard let accessToken = keychainService.loadAccessToken() else {
            throw SyncError.notAuthenticated
        }

        let backendUrl = Config.backendURL
        guard let url = URL(string: "\(backendUrl)/images") else {
            throw SyncError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SyncError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw SyncError.serverError(statusCode: httpResponse.statusCode)
        }

        let imagesResponse = try JSONDecoder().decode(ImagesResponse.self, from: data)

        // Load existing local records to preserve thumbnail data
        let existingRecords = (try? historyService.loadAll()) ?? []
        let existingById = Dictionary(uniqueKeysWithValues: existingRecords.map { ($0.id, $0) })

        // Convert backend images to UploadRecords, preserving existing thumbnails
        var syncedRecords: [UploadRecord] = []
        for image in imagesResponse.images {
            // Backend returns timestamps in milliseconds, divide by 1000 for seconds
            let createdAt = Date(timeIntervalSince1970: TimeInterval(image.createdAt) / 1000)
            let existingRecord = existingById[image.id]

            // Use existing thumbnail, or fetch and generate one if missing
            var thumbnailData = existingRecord?.thumbnailData
            if thumbnailData == nil {
                thumbnailData = await fetchAndGenerateThumbnail(from: image.url)
            }

            let record = UploadRecord(
                id: image.id,
                url: image.url,
                deleteUrl: image.deleteUrl,
                thumbnailData: thumbnailData,
                createdAt: createdAt,
                originalFilename: image.filename
            )
            syncedRecords.append(record)
        }

        // Sort by date descending (newest first)
        syncedRecords.sort { $0.createdAt > $1.createdAt }

        // Write all synced records
        try writeAll(syncedRecords)
    }

    /// Fetch image from URL and generate a thumbnail
    private func fetchAndGenerateThumbnail(from urlString: String) async -> Data? {
        #if canImport(UIKit)
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return nil
            }

            guard let image = UIImage(data: data) else { return nil }

            // Generate thumbnail using Config settings
            let maxSize = Config.thumbnailSize
            let scale = min(maxSize / image.size.width, maxSize / image.size.height, 1.0)
            let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)

            UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
            image.draw(in: CGRect(origin: .zero, size: newSize))
            let thumbnail = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()

            return thumbnail?.jpegData(compressionQuality: Config.thumbnailQuality)
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }

    /// Write all records at once, replacing existing history
    private func writeAll(_ records: [UploadRecord]) throws {
        // Use reflection to access private write method, or implement directly
        // Since HistoryService.write is private, we'll clear and re-add
        try historyService.clear()

        // Add in reverse order so newest ends up first
        for record in records.reversed() {
            try historyService.save(record)
        }
    }
}

// MARK: - Response Models

private struct ImagesResponse: Codable {
    let images: [ImageItem]
    let count: Int
}

private struct ImageItem: Codable {
    let id: String
    let filename: String
    let url: String
    let deleteUrl: String
    let sizeBytes: Int
    let contentType: String
    let createdAt: Int

    enum CodingKeys: String, CodingKey {
        case id, filename, url
        case deleteUrl = "delete_url"
        case sizeBytes = "size_bytes"
        case contentType = "content_type"
        case createdAt = "created_at"
    }
}

// MARK: - Errors

enum SyncError: LocalizedError {
    case notAuthenticated
    case invalidURL
    case invalidResponse
    case serverError(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated"
        case .invalidURL:
            return "Invalid backend URL"
        case .invalidResponse:
            return "Invalid server response"
        case .serverError(let statusCode):
            return "Server error: \(statusCode)"
        }
    }
}
