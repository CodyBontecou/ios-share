import Foundation
import UIKit

/// Quality presets for media uploads
enum UploadQuality: String, CaseIterable, Identifiable {
    case original = "original"
    case high = "high"
    case medium = "medium"
    case low = "low"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .original: return "Original"
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        }
    }

    var description: String {
        switch self {
        case .original: return "No compression"
        case .high: return "Slight compression"
        case .medium: return "Balanced quality/size"
        case .low: return "Smallest file size"
        }
    }

    var jpegQuality: CGFloat {
        switch self {
        case .original: return 1.0
        case .high: return 0.9
        case .medium: return 0.7
        case .low: return 0.5
        }
    }

    var maxDimension: CGFloat? {
        switch self {
        case .original: return nil // No resize
        case .high: return 4096
        case .medium: return 2048
        case .low: return 1024
        }
    }

    /// Estimated size reduction compared to original
    var estimatedReduction: String {
        switch self {
        case .original: return "100%"
        case .high: return "~70%"
        case .medium: return "~40%"
        case .low: return "~20%"
        }
    }
}

/// Service for managing upload quality preferences
final class UploadQualityService {
    static let shared = UploadQualityService()

    private init() {}

    /// The currently selected upload quality
    var currentQuality: UploadQuality {
        get {
            guard let rawValue = Config.sharedDefaults?.string(forKey: Config.uploadQualityKey),
                  let quality = UploadQuality(rawValue: rawValue) else {
                return .high // Default to high quality
            }
            return quality
        }
        set {
            Config.sharedDefaults?.set(newValue.rawValue, forKey: Config.uploadQualityKey)
        }
    }

    /// Process image data according to current quality settings
    /// - Parameters:
    ///   - data: Original image data
    ///   - filename: Original filename
    /// - Returns: Processed data and possibly updated filename, or original if not an image
    func processForUpload(data: Data, filename: String) -> (Data, String) {
        let quality = currentQuality

        // If original quality, return data as-is
        if quality == .original {
            return (data, filename)
        }

        // Check if this is an image we can process
        guard let image = UIImage(data: data) else {
            return (data, filename)
        }

        // Check if it's a format we should compress (skip GIFs to preserve animation)
        let lowercased = filename.lowercased()
        if lowercased.hasSuffix(".gif") {
            return (data, filename)
        }

        // Resize if needed
        var processedImage = image
        if let maxDim = quality.maxDimension {
            processedImage = ImageProcessor.shared.resize(image: image, maxDimension: maxDim)
        }

        // Compress to JPEG
        if let compressedData = processedImage.jpegData(compressionQuality: quality.jpegQuality) {
            // Update filename to .jpg since we're converting
            let newFilename: String
            if lowercased.hasSuffix(".png") || lowercased.hasSuffix(".heic") ||
               lowercased.hasSuffix(".heif") || lowercased.hasSuffix(".webp") ||
               lowercased.hasSuffix(".bmp") || lowercased.hasSuffix(".tiff") {
                newFilename = filename.replacingOccurrences(
                    of: "\\.[^.]+$",
                    with: ".jpg",
                    options: .regularExpression
                )
            } else {
                newFilename = filename
            }
            return (compressedData, newFilename)
        }

        // Fallback to original if compression fails
        return (data, filename)
    }

    /// Process a UIImage according to current quality settings
    /// - Parameter image: The image to process
    /// - Returns: Processed image data
    func processForUpload(image: UIImage) -> Data? {
        let quality = currentQuality

        if quality == .original {
            // Return highest quality JPEG for original
            return image.jpegData(compressionQuality: 1.0)
        }

        var processedImage = image
        if let maxDim = quality.maxDimension {
            processedImage = ImageProcessor.shared.resize(image: image, maxDimension: maxDim)
        }

        return processedImage.jpegData(compressionQuality: quality.jpegQuality)
    }
}
