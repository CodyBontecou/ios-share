import SwiftUI
import UIKit
import AVFoundation

struct ShareView: View {
    let extensionContext: NSExtensionContext?
    let loadImage: () async throws -> (Data, String)
    let loadFileURL: () async throws -> (URL, String, Int64)

    @State private var state: ShareState = .loading
    @State private var progress: Double = 0
    @State private var uploadedURL: String = ""
    @State private var errorMessage: String = ""
    @State private var previewImage: UIImage?
    @State private var pendingFileData: Data?
    @State private var pendingFilename: String?
    @State private var pendingFileURL: URL?  // For large file uploads
    @State private var fileSizeMB: Double = 0
    @State private var isMediaFile: Bool = true
    @State private var isLargeFile: Bool = false  // Use file-based upload for large files
    @State private var selectedQuality: UploadQuality = UploadQualityService.shared.currentQuality
    @State private var estimatedSize: String = ""
    @State private var currentUser: User?
    @State private var storageWarning: String?
    @State private var wouldExceedStorage: Bool = false
    @State private var compressionStatus: String = ""
    @State private var needsCompression: Bool = false  // File exceeds 100MB limit
    
    // Compression control sliders (images)
    @State private var compressionQuality: Double = 0.8  // 0.1 to 1.0
    @State private var maxDimensionIndex: Int = 0  // Index into dimensionOptions
    @State private var estimatedCompressedSize: Double = 0  // MB
    @State private var isCalculatingSize: Bool = false
    @State private var originalImageDimensions: CGSize = .zero
    
    // Video compression controls
    @State private var isVideoFile: Bool = false
    @State private var selectedVideoPreset: UploadQualityService.VideoQualityPreset = .medium
    @State private var videoDuration: Double = 0
    @State private var videoDimensions: CGSize = .zero
    
    // Dimension options for images (nil = original)
    private let dimensionOptions: [(label: String, value: CGFloat?)] = [
        ("Original", nil),
        ("8K (8192px)", 8192),
        ("6K (6144px)", 6144),
        ("4K (4096px)", 4096),
        ("3K (3072px)", 3072),
        ("2K (2048px)", 2048),
        ("1080p (1920px)", 1920),
        ("1K (1024px)", 1024),
    ]
    
    // Threshold for using file-based upload (50MB)
    private let largeFileThreshold: Int64 = 50 * 1024 * 1024
    // Maximum upload size (100MB backend limit)
    private var maxUploadSize: Int64 { Config.maxUploadSizeBytes }

    private enum ShareState {
        case loading
        case ready
        case compressing
        case uploading
        case success
        case error
        case notConfigured
        case storageFull
        case fileTooLarge  // File exceeds limit and can't be compressed
    }

    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            // Card
            VStack(spacing: 20) {
                switch state {
                case .loading:
                    loadingView

                case .ready:
                    readyView

                case .uploading:
                    uploadingView

                case .success:
                    successView

                case .error:
                    errorView

                case .notConfigured:
                    notConfiguredView

                case .storageFull:
                    storageFullView

                case .compressing:
                    compressingView

                case .fileTooLarge:
                    fileTooLargeView
                }
            }
            .padding(24)
            .frame(maxWidth: 320)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(radius: 20)
        }
        .onAppear {
            prepareUpload()
        }
    }

    // MARK: - State Views

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Preparing...")
                .font(.headline)
        }
        .padding(.vertical, 20)
    }

    private var readyView: some View {
        VStack(spacing: 16) {
            // Preview
            if let image = previewImage {
                ZStack {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                    // Video play indicator
                    if isVideoFile {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.white.opacity(0.9))
                            .shadow(radius: 2)
                    }
                }
            } else if let filename = pendingFilename {
                VStack(spacing: 8) {
                    Image(systemName: fileIcon(for: filename))
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text(filename)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            // File size info
            Text(String(format: "%.1f MB", fileSizeMB))
                .font(.caption)
                .foregroundStyle(.secondary)

            // Quality picker (only for small images - large files skip compression)
            if isMediaFile && previewImage != nil && !isLargeFile && !needsCompression {
                VStack(spacing: 8) {
                    Text("Quality")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("Quality", selection: $selectedQuality) {
                        ForEach(UploadQuality.allCases) { quality in
                            Text(quality.displayName).tag(quality)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedQuality) { _, newValue in
                        updateEstimatedSize()
                    }

                    Text(estimatedSize)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            
            // Compression controls for oversized files
            if needsCompression {
                compressionControlsView
            }

            // Storage warning
            if let warning = storageWarning {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                    Text(warning)
                        .font(.caption)
                }
                .foregroundStyle(.red)
            }

            // Upload button
            Button {
                startUpload()
            } label: {
                Text("Upload")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(wouldExceedStorage || (needsCompression && (estimatedCompressedSize > 100 || isCalculatingSize)))

            Button("Cancel") {
                dismiss()
            }
            .foregroundStyle(.secondary)
        }
        .onAppear {
            updateEstimatedSize()
        }
    }

    private var uploadingView: some View {
        VStack(spacing: 16) {
            // Preview (image or file icon)
            if let image = previewImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else if let filename = pendingFilename {
                VStack(spacing: 8) {
                    Image(systemName: fileIcon(for: filename))
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text(filename)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxHeight: 100)
            }

            Text("Uploading...")
                .font(.headline)

            // Progress bar
            VStack(spacing: 8) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)

                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Cancel") {
                UploadService.shared.cancelUpload()
                dismiss()
            }
            .foregroundStyle(.red)
        }
    }

    private var successView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 50))
                .foregroundStyle(.green)

            Text("Copied to clipboard")
                .font(.headline)

            Text(uploadedURL)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .onAppear {
            // Auto-dismiss after 1.5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                dismiss()
            }
        }
    }

    private var errorView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 50))
                .foregroundStyle(.orange)

            Text("Upload Failed")
                .font(.headline)

            Text(errorMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(spacing: 10) {
                Button("Try Again") {
                    state = .ready
                }
                .buttonStyle(.borderedProminent)

                Button("Done") {
                    dismiss()
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    private var notConfiguredView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 50))
                .foregroundStyle(.orange)

            Text("Not Logged In")
                .font(.headline)

            Text("Please log in via the imghost app to upload files.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var storageFullView: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.xmark")
                .font(.system(size: 50))
                .foregroundStyle(.red)

            Text("Storage Full")
                .font(.headline)

            if let user = currentUser {
                VStack(spacing: 4) {
                    Text("You've used \(user.storageUsedFormatted) of \(user.storageLimitFormatted)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("This file needs \(String(format: "%.1f MB", fileSizeMB))")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("Available: \(user.storageRemainingFormatted)")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            }

            Text("Delete some files or upgrade your plan to continue.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var compressionControlsView: some View {
        VStack(spacing: 12) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.caption)
                Text("Compression Required")
                    .font(.caption.bold())
            }
            .foregroundStyle(.orange)
            
            if isVideoFile {
                // Video compression controls
                videoCompressionControls
            } else {
                // Image compression controls
                imageCompressionControls
            }
            
            // Estimated size display
            HStack {
                if isCalculatingSize {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Calculating...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    let exceedsLimit = estimatedCompressedSize > 100
                    Image(systemName: exceedsLimit ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(exceedsLimit ? .red : .green)
                    Text(String(format: "Estimated: %.1f MB", estimatedCompressedSize))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(exceedsLimit ? .red : .primary)
                    
                    if exceedsLimit {
                        Text("(exceeds 100MB)")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onAppear {
            if isVideoFile {
                loadVideoInfo()
                calculateEstimatedVideoSize()
            } else {
                loadOriginalImageDimensions()
                calculateEstimatedSize()
            }
        }
    }
    
    private var imageCompressionControls: some View {
        VStack(spacing: 12) {
            // Original dimensions info
            if originalImageDimensions != .zero {
                Text("Original: \(Int(originalImageDimensions.width))×\(Int(originalImageDimensions.height))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            
            // Quality slider
            VStack(spacing: 4) {
                HStack {
                    Text("Quality")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(compressionQuality * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                
                Slider(value: $compressionQuality, in: 0.1...1.0, step: 0.05)
                    .onChange(of: compressionQuality) { _, _ in
                        calculateEstimatedSize()
                    }
                
                HStack {
                    Text("Smaller")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text("Better")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            
            // Dimension picker
            VStack(spacing: 4) {
                HStack {
                    Text("Max Size")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(dimensionOptions[maxDimensionIndex].label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Slider(
                    value: Binding(
                        get: { Double(maxDimensionIndex) },
                        set: { maxDimensionIndex = Int($0) }
                    ),
                    in: 0...Double(dimensionOptions.count - 1),
                    step: 1
                )
                .onChange(of: maxDimensionIndex) { _, _ in
                    calculateEstimatedSize()
                }
                
                HStack {
                    Text("Original")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Text("Smaller")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
    
    private var videoCompressionControls: some View {
        VStack(spacing: 12) {
            // Video info
            VStack(spacing: 4) {
                if videoDimensions != .zero {
                    Text("Original: \(Int(videoDimensions.width))×\(Int(videoDimensions.height))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if videoDuration > 0 {
                    Text("Duration: \(formatDuration(videoDuration))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            
            // Quality preset picker
            VStack(spacing: 8) {
                Text("Video Quality")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Picker("Quality", selection: $selectedVideoPreset) {
                    ForEach(UploadQualityService.VideoQualityPreset.allCases, id: \.self) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: selectedVideoPreset) { _, _ in
                    calculateEstimatedVideoSize()
                }
            }
            
            // Quality description
            Text(videoPresetDescription)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }
    
    private var videoPresetDescription: String {
        switch selectedVideoPreset {
        case .high:
            return "Best quality, larger file size"
        case .medium:
            return "Good balance of quality and size"
        case .low:
            return "Smaller file, reduced quality"
        case .veryLow:
            return "Smallest file, lowest quality"
        }
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        if mins > 0 {
            return "\(mins)m \(secs)s"
        } else {
            return "\(secs)s"
        }
    }

    private var compressingView: some View {
        VStack(spacing: 16) {
            // Preview (image or video thumbnail)
            if let image = previewImage {
                ZStack {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                    // Video indicator
                    if isVideoFile {
                        Image(systemName: "video.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                }
            }

            Text(isVideoFile ? "Compressing Video..." : "Compressing...")
                .font(.headline)
            
            // Progress bar for video compression
            if isVideoFile && progress > 0 {
                VStack(spacing: 8) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                    
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                ProgressView()
                    .scaleEffect(1.2)
            }

            Text(compressionStatus.isEmpty ? "Reducing file size to fit 100MB limit" : compressionStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Cancel") {
                dismiss()
            }
            .foregroundStyle(.red)
        }
    }

    private var fileTooLargeView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 50))
                .foregroundStyle(.red)

            Text("File Too Large")
                .font(.headline)

            VStack(spacing: 4) {
                Text("This file is \(String(format: "%.0f MB", fileSizeMB)) and exceeds the 100MB limit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let filename = pendingFilename {
                    let canCompress = UploadQualityService.shared.canCompress(filename: filename)
                    if !canCompress {
                        Text("This file type cannot be compressed.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Could not compress below the size limit.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal)

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Actions

    private func prepareUpload() {
        // Check if configured
        guard UploadService.shared.isConfigured else {
            state = .notConfigured
            return
        }

        state = .loading

        Task {
            do {
                // First, get user info
                let user = try await AuthService.shared.getCurrentUser()
                
                // Load file URL to check size first
                let (fileURL, filename, fileSize) = try await loadFileURL()
                
                await MainActor.run {
                    currentUser = user
                    pendingFilename = filename
                    pendingFileURL = fileURL
                    fileSizeMB = Double(fileSize) / (1024 * 1024)
                    isLargeFile = fileSize >= largeFileThreshold
                    needsCompression = fileSize > maxUploadSize

                    // Determine if this is a media file (image)
                    let lowercased = filename.lowercased()
                    isMediaFile = lowercased.hasSuffix(".jpg") || lowercased.hasSuffix(".jpeg") ||
                                  lowercased.hasSuffix(".png") || lowercased.hasSuffix(".gif") ||
                                  lowercased.hasSuffix(".heic") || lowercased.hasSuffix(".webp") ||
                                  lowercased.hasSuffix(".bmp") || lowercased.hasSuffix(".tiff")
                    
                    // Check if this is a video file
                    isVideoFile = UploadQualityService.shared.isVideo(filename: filename)
                }
                
                // Generate preview for media files
                let isVideo = UploadQualityService.shared.isVideo(filename: filename)
                
                if isVideo {
                    // Generate video thumbnail
                    let thumbnail = await generateVideoThumbnail(fileURL: fileURL)
                    await MainActor.run {
                        previewImage = thumbnail
                    }
                } else if !isLargeFile || isMediaFile {
                    // For small files or images that need preview, load into memory
                    // Only load data for preview/small files (up to 100MB for images to show preview)
                    if fileSize < 100 * 1024 * 1024 {
                        let fileData = try Data(contentsOf: fileURL)
                        
                        await MainActor.run {
                            pendingFileData = fileData
                            
                            // Create preview for images
                            if isMediaFile, let image = UIImage(data: fileData) {
                                previewImage = image
                            }
                        }
                    } else {
                        // For very large files, generate thumbnail without loading full file
                        await MainActor.run {
                            if isMediaFile {
                                previewImage = generateThumbnailFromURL(fileURL)
                            }
                        }
                    }
                }

                await MainActor.run {
                    // Check if file exceeds 100MB backend limit
                    if fileSize > maxUploadSize {
                        let canCompress = UploadQualityService.shared.canCompress(filename: filename)
                        if canCompress {
                            // Image can be compressed - go to ready state with compression notice
                            needsCompression = true
                            state = .ready
                        } else {
                            // Non-compressible file that's too large
                            state = .fileTooLarge
                        }
                        return
                    }
                    
                    // Check if file would exceed storage (at original size)
                    if !user.canUpload(bytes: Int(fileSize)) {
                        // Check if any quality setting could make it fit
                        if isMediaFile && previewImage != nil && !isLargeFile {
                            // Maybe compression will help - go to ready state
                            state = .ready
                        } else {
                            // Non-compressible file or large file that won't fit
                            state = .storageFull
                        }
                    } else {
                        // File is ready, show preview and quality options
                        state = .ready
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    state = .error
                }
            }
        }
    }
    
    /// Generate thumbnail from file URL without loading entire file
    private func generateThumbnailFromURL(_ url: URL) -> UIImage? {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 400,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            return nil
        }
        
        return UIImage(cgImage: thumbnail)
    }
    
    /// Generate thumbnail from video file
    private func generateVideoThumbnail(fileURL: URL) async -> UIImage? {
        let asset = AVURLAsset(url: fileURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 400, height: 400)
        
        do {
            let cgImage = try imageGenerator.copyCGImage(at: .zero, actualTime: nil)
            return UIImage(cgImage: cgImage)
        } catch {
            return nil
        }
    }
    
    /// Load original image dimensions for display
    private func loadOriginalImageDimensions() {
        guard let fileURL = pendingFileURL else { return }
        
        Task.detached {
            guard let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
                  let height = properties[kCGImagePropertyPixelHeight] as? CGFloat else {
                return
            }
            
            await MainActor.run {
                originalImageDimensions = CGSize(width: width, height: height)
            }
        }
    }
    
    /// Calculate estimated compressed size based on current slider settings
    private func calculateEstimatedSize() {
        guard let fileURL = pendingFileURL else { return }
        
        isCalculatingSize = true
        
        // Debounce the calculation
        Task {
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms debounce
            
            let quality = compressionQuality
            let maxDim = dimensionOptions[maxDimensionIndex].value
            
            let estimatedMB = await Task.detached { () -> Double in
                // Load image
                guard let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
                      let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                    return 0
                }
                
                var image = UIImage(cgImage: cgImage)
                
                // Resize if needed
                if let maxDimension = maxDim {
                    image = ImageProcessor.shared.resize(image: image, maxDimension: maxDimension)
                }
                
                // Compress and measure size
                if let data = image.jpegData(compressionQuality: quality) {
                    return Double(data.count) / (1024 * 1024)
                }
                
                return 0
            }.value
            
            await MainActor.run {
                estimatedCompressedSize = estimatedMB
                isCalculatingSize = false
            }
        }
    }
    
    /// Load video information
    private func loadVideoInfo() {
        guard let fileURL = pendingFileURL else { return }
        
        Task {
            if let info = await UploadQualityService.shared.getVideoInfo(fileURL: fileURL) {
                await MainActor.run {
                    videoDuration = info.duration
                    videoDimensions = info.dimensions
                }
            }
        }
    }
    
    /// Calculate estimated compressed video size based on selected preset
    private func calculateEstimatedVideoSize() {
        isCalculatingSize = true
        
        Task {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms debounce
            
            await MainActor.run {
                estimatedCompressedSize = UploadQualityService.shared.estimateCompressedVideoSize(
                    originalSizeMB: fileSizeMB,
                    preset: selectedVideoPreset
                )
                isCalculatingSize = false
            }
        }
    }

    private func startUpload() {
        guard let filename = pendingFilename else { return }

        // Handle files that need compression (exceed 100MB limit)
        if needsCompression, let fileURL = pendingFileURL {
            performCompressedUpload(fileURL: fileURL, filename: filename)
            return
        }
        
        // For large files (but under 100MB), use file-based upload
        if isLargeFile, let fileURL = pendingFileURL {
            performFileUpload(fileURL: fileURL, filename: filename)
            return
        }
        
        // For small files, use data-based upload with quality processing
        guard let data = pendingFileData else { return }

        // Apply selected quality settings
        let (processedData, processedFilename) = UploadQualityService.shared.processForUpload(
            data: data,
            filename: filename,
            quality: selectedQuality
        )
        performUpload(data: processedData, filename: processedFilename)
    }
    
    /// Compress and upload a file that exceeds the 100MB limit
    /// Uses the user-selected quality and dimension settings from sliders
    private func performCompressedUpload(fileURL: URL, filename: String) {
        state = .compressing
        compressionStatus = "Preparing..."
        
        if isVideoFile {
            performVideoCompressedUpload(fileURL: fileURL, filename: filename)
        } else {
            performImageCompressedUpload(fileURL: fileURL, filename: filename)
        }
    }
    
    /// Compress and upload an image file
    private func performImageCompressedUpload(fileURL: URL, filename: String) {
        compressionStatus = "Applying compression settings..."
        
        let quality = compressionQuality
        let maxDim = dimensionOptions[maxDimensionIndex].value
        
        Task {
            // Perform compression on background thread with user's settings
            let result = await Task.detached { () -> (Data, String)? in
                // Load image
                guard let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
                      let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                    return nil
                }
                
                var image = UIImage(cgImage: cgImage)
                
                // Resize if max dimension specified
                if let maxDimension = maxDim {
                    await MainActor.run {
                        self.compressionStatus = "Resizing image..."
                    }
                    image = ImageProcessor.shared.resize(image: image, maxDimension: maxDimension)
                }
                
                await MainActor.run {
                    self.compressionStatus = "Compressing..."
                }
                
                // Compress to JPEG with user-selected quality
                guard let compressedData = image.jpegData(compressionQuality: quality) else {
                    return nil
                }
                
                // Update filename to .jpg
                let newFilename = filename.replacingOccurrences(
                    of: "\\.[^.]+$",
                    with: ".jpg",
                    options: .regularExpression
                )
                
                let sizeMB = Double(compressedData.count) / (1024 * 1024)
                await MainActor.run {
                    self.compressionStatus = String(format: "Compressed to %.1f MB", sizeMB)
                }
                
                return (compressedData, newFilename)
            }.value
            
            await MainActor.run {
                if let (compressedData, compressedFilename) = result {
                    // Compression succeeded, now upload
                    performUpload(data: compressedData, filename: compressedFilename)
                } else {
                    // Compression failed
                    errorMessage = "Failed to compress image"
                    state = .error
                }
            }
        }
    }
    
    /// Compress and upload a video file
    private func performVideoCompressedUpload(fileURL: URL, filename: String) {
        compressionStatus = "Starting video compression..."
        progress = 0
        
        let preset = selectedVideoPreset
        
        Task {
            let compressedURL = await UploadQualityService.shared.compressVideo(
                fileURL: fileURL,
                preset: preset
            ) { status, progressValue in
                Task { @MainActor in
                    self.compressionStatus = status
                    if let p = progressValue {
                        self.progress = p * 0.5 // First half is compression
                    }
                }
            }
            
            await MainActor.run {
                if let outputURL = compressedURL {
                    // Update filename to .mp4
                    let newFilename = filename.replacingOccurrences(
                        of: "\\.[^.]+$",
                        with: ".mp4",
                        options: .regularExpression
                    )
                    
                    // Upload the compressed video file
                    performFileUploadWithCleanup(fileURL: outputURL, filename: newFilename)
                } else {
                    errorMessage = "Failed to compress video"
                    state = .error
                }
            }
        }
    }
    
    /// Upload a file and clean up after completion
    private func performFileUploadWithCleanup(fileURL: URL, filename: String) {
        state = .uploading
        compressionStatus = ""
        
        Task {
            do {
                let record = try await UploadService.shared.uploadFromFile(
                    fileURL: fileURL,
                    filename: filename
                ) { uploadProgress in
                    Task { @MainActor in
                        // Second half is upload (0.5 to 1.0)
                        self.progress = 0.5 + (uploadProgress * 0.5)
                    }
                }
                
                // Copy formatted URL to clipboard
                await MainActor.run {
                    let formattedLink = LinkFormatService.shared.format(
                        url: record.url,
                        filename: record.originalFilename
                    )
                    UIPasteboard.general.string = formattedLink
                }
                
                // Play haptic feedback
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
                
                // Save to history
                try? HistoryService.shared.save(record)
                
                await MainActor.run {
                    uploadedURL = record.url
                    state = .success
                }
                
                // Clean up temp file
                try? FileManager.default.removeItem(at: fileURL)
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    state = .error
                }
                
                // Clean up temp file on error too
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
    }

    private func updateEstimatedSize() {
        guard fileSizeMB > 0 else {
            estimatedSize = ""
            storageWarning = nil
            wouldExceedStorage = false
            return
        }

        // Files that need compression to fit under 100MB limit
        if needsCompression {
            estimatedSize = "Will be compressed to fit limit"
            // Can't accurately predict final size, assume it will fit
            wouldExceedStorage = false
            storageWarning = nil
            return
        }

        // Large files or non-image files don't get compression
        if isLargeFile || !isMediaFile || previewImage == nil {
            if isLargeFile {
                estimatedSize = "Large file - uploading original"
            } else {
                estimatedSize = "No compression for this file type"
            }
            // Check storage for non-compressible files
            if let user = currentUser {
                let fileBytes = Int(fileSizeMB * 1024 * 1024)
                wouldExceedStorage = !user.canUpload(bytes: fileBytes)
                if wouldExceedStorage {
                    storageWarning = "Exceeds storage limit (\(user.storageRemainingFormatted) available)"
                } else {
                    storageWarning = nil
                }
            }
            return
        }

        // Calculate estimated size based on quality
        let multiplier: Double
        switch selectedQuality {
        case .original:
            multiplier = 1.0
        case .high:
            multiplier = 0.7
        case .medium:
            multiplier = 0.4
        case .low:
            multiplier = 0.2
        }

        let estimatedMB = fileSizeMB * multiplier
        let estimatedBytes = Int(estimatedMB * 1024 * 1024)

        if selectedQuality == .original {
            estimatedSize = "No compression"
        } else {
            estimatedSize = String(format: "~%.1f MB after compression", estimatedMB)
        }

        // Check against storage limit
        if let user = currentUser {
            wouldExceedStorage = !user.canUpload(bytes: estimatedBytes)
            if wouldExceedStorage {
                storageWarning = "Exceeds storage limit (\(user.storageRemainingFormatted) available)"
            } else {
                storageWarning = nil
            }
        }
    }

    private func fileIcon(for filename: String) -> String {
        let lowercased = filename.lowercased()
        
        // Videos
        if lowercased.hasSuffix(".mp4") || lowercased.hasSuffix(".mov") ||
           lowercased.hasSuffix(".avi") || lowercased.hasSuffix(".mkv") ||
           lowercased.hasSuffix(".webm") {
            return "film"
        }
        
        // Audio
        if lowercased.hasSuffix(".mp3") || lowercased.hasSuffix(".wav") ||
           lowercased.hasSuffix(".m4a") || lowercased.hasSuffix(".aac") ||
           lowercased.hasSuffix(".flac") {
            return "waveform"
        }
        
        // Documents
        if lowercased.hasSuffix(".pdf") {
            return "doc.richtext"
        }
        if lowercased.hasSuffix(".doc") || lowercased.hasSuffix(".docx") {
            return "doc.text"
        }
        if lowercased.hasSuffix(".xls") || lowercased.hasSuffix(".xlsx") {
            return "tablecells"
        }
        if lowercased.hasSuffix(".ppt") || lowercased.hasSuffix(".pptx") {
            return "slider.horizontal.below.rectangle"
        }
        if lowercased.hasSuffix(".txt") || lowercased.hasSuffix(".md") {
            return "doc.plaintext"
        }
        
        // Archives
        if lowercased.hasSuffix(".zip") || lowercased.hasSuffix(".gz") ||
           lowercased.hasSuffix(".tar") || lowercased.hasSuffix(".rar") ||
           lowercased.hasSuffix(".7z") {
            return "doc.zipper"
        }
        
        // Code/Data
        if lowercased.hasSuffix(".json") || lowercased.hasSuffix(".xml") ||
           lowercased.hasSuffix(".html") || lowercased.hasSuffix(".css") ||
           lowercased.hasSuffix(".js") {
            return "curlybraces"
        }
        
        return "doc"
    }

    private func performUpload(data: Data, filename: String) {
        state = .uploading
        progress = 0

        Task {
            do {
                // Upload
                let record = try await UploadService.shared.upload(
                    imageData: data,
                    filename: filename
                ) { uploadProgress in
                    Task { @MainActor in
                        progress = uploadProgress
                    }
                }

                // Copy formatted URL to clipboard immediately
                await MainActor.run {
                    let formattedLink = LinkFormatService.shared.format(
                        url: record.url,
                        filename: record.originalFilename
                    )
                    UIPasteboard.general.string = formattedLink
                }

                // Play haptic feedback
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)

                // Save to history
                try? HistoryService.shared.save(record)

                await MainActor.run {
                    uploadedURL = record.url
                    state = .success
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    state = .error
                }
            }
        }
    }
    
    /// Upload using file URL (for large files to avoid memory issues)
    private func performFileUpload(fileURL: URL, filename: String) {
        state = .uploading
        progress = 0

        Task {
            do {
                // Upload using file-based method
                let record = try await UploadService.shared.uploadFromFile(
                    fileURL: fileURL,
                    filename: filename
                ) { uploadProgress in
                    Task { @MainActor in
                        progress = uploadProgress
                    }
                }

                // Copy formatted URL to clipboard immediately
                await MainActor.run {
                    let formattedLink = LinkFormatService.shared.format(
                        url: record.url,
                        filename: record.originalFilename
                    )
                    UIPasteboard.general.string = formattedLink
                }

                // Play haptic feedback
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)

                // Save to history
                try? HistoryService.shared.save(record)

                await MainActor.run {
                    uploadedURL = record.url
                    state = .success
                }
                
                // Clean up temp file
                try? FileManager.default.removeItem(at: fileURL)
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    state = .error
                }
                
                // Clean up temp file on error too
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
    }

    private func dismiss() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}

#Preview {
    ShareView(
        extensionContext: nil,
        loadImage: {
            // Return mock data for preview
            let image = UIImage(systemName: "photo")!
            return (image.pngData()!, "test.png")
        },
        loadFileURL: {
            // Return mock file URL for preview
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test.png")
            let image = UIImage(systemName: "photo")!
            try? image.pngData()?.write(to: tempURL)
            return (tempURL, "test.png", 1024)
        }
    )
}
