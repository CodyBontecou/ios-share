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

    // Share extensions have ~120MB memory limit, warn at 80MB to be safe
    private let memorySafetyLimitMB: Double = 80
    private let memoryHardLimitMB: Double = 100

    private enum ShareState {
        case loading
        case uploading
        case success
        case error
        case notConfigured
        case fileTooLarge
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

                case .uploading:
                    uploadingView

                case .success:
                    successView

                case .error:
                    errorView

                case .notConfigured:
                    notConfiguredView

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
                Button("Retry") {
                    uploadOriginal()
                }
                .buttonStyle(.borderedProminent)

                // Only show resize option for large images
                if fileSizeMB > 10 && isMediaFile {
                    Button("Retry with Resize") {
                        uploadResized()
                    }
                    .buttonStyle(.bordered)
                }

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

    private var fileTooLargeView: some View {
        VStack(spacing: 16) {
            // Preview (image or file icon)
            if let image = previewImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 120)
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
            }

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)

            Text("Large File")
                .font(.headline)

            Text(String(format: "This file is %.1f MB. Files over %.0f MB may fail to upload due to memory limits.", fileSizeMB, memorySafetyLimitMB))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(spacing: 10) {
                // Only show resize option for images
                if isMediaFile, previewImage != nil {
                    Button {
                        uploadResized()
                    } label: {
                        Text("Resize & Upload")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }

                if fileSizeMB < memoryHardLimitMB {
                    if isMediaFile && previewImage != nil {
                        Button {
                            uploadOriginal()
                        } label: {
                            Text("Upload Original")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button {
                            uploadOriginal()
                        } label: {
                            Text("Upload Original")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                Button("Cancel") {
                    dismiss()
                }
                .foregroundStyle(.secondary)
            }
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
                // Load file
                let (fileData, filename) = try await loadImage()

                // Store for later use
                await MainActor.run {
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

                    // Check file size
                    if fileSizeMB >= memorySafetyLimitMB {
                        state = .fileTooLarge
                    } else {
                        // File is small enough, apply quality settings and proceed
                        let (processedData, processedFilename) = UploadQualityService.shared.processForUpload(
                            data: fileData,
                            filename: filename
                        )
                        performUpload(data: processedData, filename: processedFilename)
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

    private func uploadOriginal() {
        guard let data = pendingFileData, let filename = pendingFilename else { return }

        // Apply quality settings from user preferences
        let (processedData, processedFilename) = UploadQualityService.shared.processForUpload(
            data: data,
            filename: filename
        )
        performUpload(data: processedData, filename: processedFilename)
    }

    private func uploadResized() {
        guard let data = pendingFileData, let filename = pendingFilename else { return }

        // Resize only works for images
        if let image = UIImage(data: data),
           let resizedData = ImageProcessor.shared.prepareForUpload(image: image) {
            // Update filename to .jpg since we're converting
            let newFilename = filename.replacingOccurrences(
                of: "\\.[^.]+$",
                with: ".jpg",
                options: .regularExpression
            )
            performUpload(data: resizedData, filename: newFilename)
        } else {
            // Fallback to original if resize fails
            performUpload(data: data, filename: filename)
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
