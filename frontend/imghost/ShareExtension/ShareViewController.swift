import UIKit
import SwiftUI
import UniformTypeIdentifiers

class ShareViewController: UIViewController {
    private var hostingController: UIHostingController<ShareView>?

    override func viewDidLoad() {
        super.viewDidLoad()

        let shareView = ShareView(
            extensionContext: extensionContext,
            loadImage: loadImage,
            loadFileURL: loadFileURL
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

    /// Load file as URL for large file support (avoids memory issues)
    private func loadFileURL() async throws -> (URL, String, Int64) {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            throw ImghostError.invalidResponse
        }

        for item in extensionItems {
            guard let attachments = item.attachments else { continue }

            for provider in attachments {
                // Try to load as file URL first (preserves original filename)
                if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    if let result = try? await loadFileURLOnly(from: provider) {
                        return result
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
                            return result
                        }
                    }
                }
            }
        }

        throw ImghostError.invalidResponse
    }
    
    private func loadFileURLOnly(from provider: NSItemProvider) async throws -> (URL, String, Int64) {
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
                    continuation.resume(returning: (tempURL, filename, fileSize))
                } catch {
                    continuation.resume(throwing: ImghostError.networkError(underlying: error))
                }
            }
        }
    }
    
    private func loadDataToTempFile(from provider: NSItemProvider, typeIdentifier: String) async throws -> (URL, String, Int64) {
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
                            continuation.resume(returning: (tempURL, jpegFilename, Int64(jpegData.count)))
                            return
                        }
                    }
                    
                    try data.write(to: tempURL)
                    continuation.resume(returning: (tempURL, filename, Int64(data.count)))
                } catch {
                    continuation.resume(throwing: ImghostError.networkError(underlying: error))
                }
            }
        }
    }

    private func loadImage() async throws -> (Data, String) {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            throw ImghostError.invalidResponse
        }

        for item in extensionItems {
            guard let attachments = item.attachments else { continue }

            for provider in attachments {
                // Try to load as file URL first (preserves original filename)
                if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    if let result = try? await loadFileURL(from: provider) {
                        return result
                    }
                }
                
                // Try different content types in order of preference
                let supportedTypes: [UTType] = [
                    // Images
                    .image, .jpeg, .png, .heic, .gif, .webP, .bmp, .tiff,
                    // Videos
                    .movie, .video, .mpeg4Movie, .quickTimeMovie, .avi,
                    // Audio
                    .audio, .mp3, .wav, .mpeg4Audio,
                    // Documents
                    .pdf, .plainText, .rtf, .html,
                    // Archives
                    .zip, .gzip,
                    // Data
                    .json, .xml, .data
                ]

                for type in supportedTypes {
                    if provider.hasItemConformingToTypeIdentifier(type.identifier) {
                        let (data, filename) = try await loadData(from: provider, typeIdentifier: type.identifier)
                        return (data, filename)
                    }
                }
            }
        }

        throw ImghostError.invalidResponse
    }

    private func loadFileURL(from provider: NSItemProvider) async throws -> (Data, String) {
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
                
                do {
                    let data = try Data(contentsOf: url)
                    let filename = url.lastPathComponent
                    continuation.resume(returning: (data, filename))
                } catch {
                    continuation.resume(throwing: ImghostError.networkError(underlying: error))
                }
            }
        }
    }

    private func loadData(from provider: NSItemProvider, typeIdentifier: String) async throws -> (Data, String) {
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

                // Convert HEIC to JPEG for better compatibility
                if typeIdentifier == UTType.heic.identifier {
                    if let image = UIImage(data: data),
                       let jpegData = image.jpegData(compressionQuality: Config.jpegQuality) {
                        let jpegFilename = filename.replacingOccurrences(of: ".heic", with: ".jpg")
                        continuation.resume(returning: (jpegData, jpegFilename))
                        return
                    }
                }

                continuation.resume(returning: (data, filename))
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
