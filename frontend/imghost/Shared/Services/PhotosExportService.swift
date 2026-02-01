import Foundation
import Photos
import UIKit

enum PhotosExportError: LocalizedError {
    case notAuthorized
    case noImages
    case saveFailed(underlying: Error)
    case albumCreationFailed

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Photo library access not authorized. Please enable in Settings."
        case .noImages:
            return "No images to save."
        case .saveFailed(let error):
            return "Failed to save images: \(error.localizedDescription)"
        case .albumCreationFailed:
            return "Failed to create photo album."
        }
    }
}

final class PhotosExportService {
    static let shared = PhotosExportService()

    private let albumName = "imghost"

    private init() {}

    /// Request photo library authorization
    func requestAuthorization() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return status == .authorized || status == .limited
    }

    /// Check current authorization status
    var isAuthorized: Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return status == .authorized || status == .limited
    }

    /// Save images from URLs to the photo library
    /// - Parameters:
    ///   - imageURLs: URLs of images to save (can be remote URLs)
    ///   - progress: Progress callback (0.0 to 1.0)
    /// - Returns: Number of images successfully saved
    func saveToPhotos(
        imageURLs: [URL],
        progress: @escaping (Double) -> Void
    ) async throws -> Int {
        if !isAuthorized {
            let authorized = await requestAuthorization()
            if !authorized {
                throw PhotosExportError.notAuthorized
            }
        }

        guard !imageURLs.isEmpty else {
            throw PhotosExportError.noImages
        }

        // Get or create album
        let album = try await getOrCreateAlbum()

        var savedCount = 0
        let total = imageURLs.count

        for (index, url) in imageURLs.enumerated() {
            do {
                // Download image data
                let (data, _) = try await URLSession.shared.data(from: url)

                // Save to photo library
                try await saveImageData(data, to: album)
                savedCount += 1
            } catch {
                print("Failed to save image \(url): \(error)")
            }

            let currentProgress = Double(index + 1) / Double(total)
            await MainActor.run {
                progress(currentProgress)
            }
        }

        return savedCount
    }

    /// Save images directly from image data
    func saveImagesToPhotos(
        images: [(data: Data, filename: String)],
        progress: @escaping (Double) -> Void
    ) async throws -> Int {
        if !isAuthorized {
            let authorized = await requestAuthorization()
            if !authorized {
                throw PhotosExportError.notAuthorized
            }
        }

        guard !images.isEmpty else {
            throw PhotosExportError.noImages
        }

        // Get or create album
        let album = try await getOrCreateAlbum()

        var savedCount = 0
        let total = images.count

        for (index, image) in images.enumerated() {
            do {
                try await saveImageData(image.data, to: album)
                savedCount += 1
            } catch {
                print("Failed to save image \(image.filename): \(error)")
            }

            let currentProgress = Double(index + 1) / Double(total)
            await MainActor.run {
                progress(currentProgress)
            }
        }

        return savedCount
    }

    // MARK: - Private Methods

    private func getOrCreateAlbum() async throws -> PHAssetCollection {
        // Check if album already exists
        let fetchOptions = PHFetchOptions()
        fetchOptions.predicate = NSPredicate(format: "title = %@", albumName)
        let collections = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .any,
            options: fetchOptions
        )

        if let existingAlbum = collections.firstObject {
            return existingAlbum
        }

        // Create new album
        var albumPlaceholder: PHObjectPlaceholder?

        try await PHPhotoLibrary.shared().performChanges {
            let createRequest = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: self.albumName)
            albumPlaceholder = createRequest.placeholderForCreatedAssetCollection
        }

        guard let placeholder = albumPlaceholder,
              let album = PHAssetCollection.fetchAssetCollections(
                withLocalIdentifiers: [placeholder.localIdentifier],
                options: nil
              ).firstObject else {
            throw PhotosExportError.albumCreationFailed
        }

        return album
    }

    private func saveImageData(_ data: Data, to album: PHAssetCollection) async throws {
        var assetPlaceholder: PHObjectPlaceholder?

        try await PHPhotoLibrary.shared().performChanges {
            let creationRequest = PHAssetCreationRequest.forAsset()
            creationRequest.addResource(with: .photo, data: data, options: nil)
            assetPlaceholder = creationRequest.placeholderForCreatedAsset

            // Add to album
            if let placeholder = assetPlaceholder,
               let albumChangeRequest = PHAssetCollectionChangeRequest(for: album) {
                albumChangeRequest.addAssets([placeholder] as NSFastEnumeration)
            }
        }
    }
}
