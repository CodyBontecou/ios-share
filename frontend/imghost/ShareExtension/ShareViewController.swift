import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// Represents a single shared item with its file info
struct SharedItem: Identifiable {
    let id = UUID()
    let fileURL: URL
    let filename: String
    let fileSize: Int64
    var thumbnail: UIImage?
    var isVideo: Bool
    var videoDuration: Double?
    var dimensions: CGSize?
    
    var fileSizeMB: Double {
        Double(fileSize) / (1024 * 1024)
    }
}

class ShareViewController: UIViewController {
    private var hostingController: UIHostingController<ShareView>?

    override func viewDidLoad() {
        super.viewDidLoad()

        let shareView = ShareView(
            extensionContext: extensionContext,
            loadAllItems: loadAllFileURLs
        )

        let hostingController = UIHostingController(rootView: shareView)
        self.hostingController = hostingController

        addChild(hostingController)
        view.addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        hostingController.didMove(toParent: self)
    }

    /// Load all shared items as file URLs
    private func loadAllFileURLs() async throws -> [SharedItem] {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            throw ImghostError.invalidResponse
        }

        var items: [SharedItem] = []
        
        for item in extensionItems {
            guard let attachments = item.attachments else { continue }

            for provider in attachments {
                // Try to load as file URL first (preserves original filename)
                if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    if let result = try? await loadFileURLOnly(from: provider) {
                        items.append(result)
                        continue
                    }
                }
                
                // For non-file URLs, we need to copy data to a temp file
                let supportedTypes: [UTType] = [
                    .image, .jpeg, .png, .heic, .gif, .webP, .bmp, .tiff,
                    .movie, .video, .mpeg4Movie, .quickTimeMovie, .avi,
                    .audio, .mp3, .wav, .mpeg4Audio,
                    .pdf, .plainText, .rtf, .html,
                    .zip, .gzip, .json, .xml, .data
                ]

                for type in supportedTypes {
                    if provider.hasItemConformingToTypeIdentifier(type.identifier) {
                        if let result = try? await loadDataToTempFile(from: provider, typeIdentifier: type.identifier) {
                            items.append(result)
                            break
                        }
                    }
                }
            }
        }
        
        guard !items.isEmpty else {
            throw ImghostError.invalidResponse
        }

        return items
    }
    
    private func loadFileURLOnly(from provider: NSItemProvider) async throws -> SharedItem {
        return try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                if let error = error {
                    continuation.resume(throwing: ImghostError.networkError(underlying: error))
                    return
                }
                
                guard let url = item as? URL else {
                    continuation.resume(throwing: ImghostError.invalidResponse)
                    return
                }
                
                // Copy to temp directory to ensure we have access throughout the upload
                let tempDir = FileManager.default.temporaryDirectory
                let tempURL = tempDir.appendingPathComponent(UUID().uuidString + "_" + url.lastPathComponent)
                
                do {
                    try FileManager.default.copyItem(at: url, to: tempURL)
                    let attributes = try FileManager.default.attributesOfItem(atPath: tempURL.path)
                    let fileSize = (attributes[.size] as? Int64) ?? 0
                    let filename = url.lastPathComponent
                    let isVideo = UploadQualityService.shared.isVideo(filename: filename)
                    
                    let item = SharedItem(
                        fileURL: tempURL,
                        filename: filename,
                        fileSize: fileSize,
                        thumbnail: nil,
                        isVideo: isVideo,
                        videoDuration: nil,
                        dimensions: nil
                    )
                    continuation.resume(returning: item)
                } catch {
                    continuation.resume(throwing: ImghostError.networkError(underlying: error))
                }
            }
        }
    }
    
    private func loadDataToTempFile(from provider: NSItemProvider, typeIdentifier: String) async throws -> SharedItem {
        return try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                if let error = error {
                    continuation.resume(throwing: ImghostError.networkError(underlying: error))
                    return
                }

                guard let data = data else {
                    continuation.resume(throwing: ImghostError.invalidResponse)
                    return
                }

                // Generate filename based on type
                let filename = self.generateFilename(for: typeIdentifier)
                let isVideo = UploadQualityService.shared.isVideo(filename: filename)
                
                // Write to temp file
                let tempDir = FileManager.default.temporaryDirectory
                let tempURL = tempDir.appendingPathComponent(UUID().uuidString + "_" + filename)
                
                do {
                    // Convert HEIC to JPEG for better compatibility
                    if typeIdentifier == UTType.heic.identifier {
                        if let image = UIImage(data: data),
                           let jpegData = image.jpegData(compressionQuality: Config.jpegQuality) {
                            try jpegData.write(to: tempURL)
                            let jpegFilename = filename.replacingOccurrences(of: ".heic", with: ".jpg")
                            let item = SharedItem(
                                fileURL: tempURL,
                                filename: jpegFilename,
                                fileSize: Int64(jpegData.count),
                                thumbnail: nil,
                                isVideo: false,
                                videoDuration: nil,
                                dimensions: nil
                            )
                            continuation.resume(returning: item)
                            return
                        }
                    }
                    
                    try data.write(to: tempURL)
                    let item = SharedItem(
                        fileURL: tempURL,
                        filename: filename,
                        fileSize: Int64(data.count),
                        thumbnail: nil,
                        isVideo: isVideo,
                        videoDuration: nil,
                        dimensions: nil
                    )
                    continuation.resume(returning: item)
                } catch {
                    continuation.resume(throwing: ImghostError.networkError(underlying: error))
                }
            }
        }
    }

    private func generateFilename(for typeIdentifier: String) -> String {
        let timestamp = Int(Date().timeIntervalSince1970)

        // Images
        if typeIdentifier == UTType.png.identifier { return "image_\(timestamp).png" }
        if typeIdentifier == UTType.gif.identifier { return "image_\(timestamp).gif" }
        if typeIdentifier == UTType.webP.identifier { return "image_\(timestamp).webp" }
        if typeIdentifier == UTType.heic.identifier { return "image_\(timestamp).heic" }
        if typeIdentifier == UTType.bmp.identifier { return "image_\(timestamp).bmp" }
        if typeIdentifier == UTType.tiff.identifier { return "image_\(timestamp).tiff" }
        if typeIdentifier == UTType.jpeg.identifier || typeIdentifier == UTType.image.identifier {
            return "image_\(timestamp).jpg"
        }
        
        // Videos
        if typeIdentifier == UTType.quickTimeMovie.identifier { return "video_\(timestamp).mov" }
        if typeIdentifier == UTType.mpeg4Movie.identifier || typeIdentifier == UTType.movie.identifier || typeIdentifier == UTType.video.identifier {
            return "video_\(timestamp).mp4"
        }
        if typeIdentifier == UTType.avi.identifier { return "video_\(timestamp).avi" }
        
        // Audio
        if typeIdentifier == UTType.mp3.identifier { return "audio_\(timestamp).mp3" }
        if typeIdentifier == UTType.wav.identifier { return "audio_\(timestamp).wav" }
        if typeIdentifier == UTType.mpeg4Audio.identifier || typeIdentifier == UTType.audio.identifier {
            return "audio_\(timestamp).m4a"
        }
        
        // Documents
        if typeIdentifier == UTType.pdf.identifier { return "document_\(timestamp).pdf" }
        if typeIdentifier == UTType.plainText.identifier { return "document_\(timestamp).txt" }
        if typeIdentifier == UTType.rtf.identifier { return "document_\(timestamp).rtf" }
        if typeIdentifier == UTType.html.identifier { return "document_\(timestamp).html" }
        
        // Archives
        if typeIdentifier == UTType.zip.identifier { return "archive_\(timestamp).zip" }
        if typeIdentifier == UTType.gzip.identifier { return "archive_\(timestamp).gz" }
        
        // Data formats
        if typeIdentifier == UTType.json.identifier { return "data_\(timestamp).json" }
        if typeIdentifier == UTType.xml.identifier { return "data_\(timestamp).xml" }
        
        // Default
        return "file_\(timestamp).bin"
    }
}
