import SwiftUI
import UIKit

struct ShareView: View {
    let extensionContext: NSExtensionContext?
    let loadImage: () async throws -> (Data, String)

    @State private var state: ShareState = .loading
    @State private var progress: Double = 0
    @State private var uploadedURL: String = ""
    @State private var errorMessage: String = ""
    @State private var previewImage: UIImage?
    @State private var pendingFileData: Data?
    @State private var pendingFilename: String?
    @State private var fileSizeMB: Double = 0
    @State private var isMediaFile: Bool = true
    @State private var selectedQuality: UploadQuality = UploadQualityService.shared.currentQuality
    @State private var estimatedSize: String = ""
    @State private var currentUser: User?
    @State private var storageWarning: String?
    @State private var wouldExceedStorage: Bool = false

    private enum ShareState {
        case loading
        case ready
        case uploading
        case success
        case error
        case notConfigured
        case storageFull
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
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
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

            // Quality picker (only for images)
            if isMediaFile && previewImage != nil {
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
            .disabled(wouldExceedStorage)

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
                // Fetch user info and file data concurrently
                async let userTask = AuthService.shared.getCurrentUser()
                async let fileTask = loadImage()

                let (user, (fileData, filename)) = try await (userTask, fileTask)

                // Store for later use
                await MainActor.run {
                    currentUser = user
                    pendingFileData = fileData
                    pendingFilename = filename
                    fileSizeMB = Double(fileData.count) / (1024 * 1024)

                    // Determine if this is a media file (image)
                    let lowercased = filename.lowercased()
                    isMediaFile = lowercased.hasSuffix(".jpg") || lowercased.hasSuffix(".jpeg") ||
                                  lowercased.hasSuffix(".png") || lowercased.hasSuffix(".gif") ||
                                  lowercased.hasSuffix(".heic") || lowercased.hasSuffix(".webp") ||
                                  lowercased.hasSuffix(".bmp") || lowercased.hasSuffix(".tiff")

                    // Create preview for images
                    if isMediaFile, let image = UIImage(data: fileData) {
                        previewImage = image
                    }

                    // Check if file would exceed storage (at original size)
                    if !user.canUpload(bytes: fileData.count) {
                        // Check if any quality setting could make it fit
                        if isMediaFile && previewImage != nil {
                            // Maybe compression will help - go to ready state
                            state = .ready
                        } else {
                            // Non-compressible file that won't fit
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

    private func startUpload() {
        guard let data = pendingFileData, let filename = pendingFilename else { return }

        // Apply selected quality settings
        let (processedData, processedFilename) = UploadQualityService.shared.processForUpload(
            data: data,
            filename: filename,
            quality: selectedQuality
        )
        performUpload(data: processedData, filename: processedFilename)
    }

    private func updateEstimatedSize() {
        guard fileSizeMB > 0 else {
            estimatedSize = ""
            storageWarning = nil
            wouldExceedStorage = false
            return
        }

        if !isMediaFile || previewImage == nil {
            estimatedSize = "No compression for this file type"
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
        }
    )
}
