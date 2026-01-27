import SwiftUI
import PhotosUI

struct UploadView: View {
    @State private var selectedItem: PhotosPickerItem?
    @State private var isUploading = false
    @State private var uploadProgress: Double = 0
    @State private var uploadState: UploadState = .idle
    @State private var errorMessage: String?
    @State private var uploadedRecord: UploadRecord?

    private enum UploadState {
        case idle
        case loading
        case uploading
        case success
        case error
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.brutalBackground.ignoresSafeArea()

                VStack(spacing: 32) {
                    switch uploadState {
                    case .idle:
                        idleView

                    case .loading:
                        loadingView

                    case .uploading:
                        uploadingView

                    case .success:
                        successView

                    case .error:
                        errorView
                    }
                }
                .padding(24)
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("UPLOAD")
                        .brutalTypography(.mono)
                        .tracking(2)
                }
            }
            .toolbarBackground(Color.brutalBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - State Views

    private var idleView: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "arrow.up.circle")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(.white)

                Text("UPLOAD\nPHOTO")
                    .font(.system(size: 36, weight: .black))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("Select a photo from your library to upload")
                    .brutalTypography(.bodyMedium, color: .brutalTextSecondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            PhotosPicker(
                selection: $selectedItem,
                matching: .images,
                photoLibrary: .shared()
            ) {
                HStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 20, weight: .semibold))
                    Text("Choose Photo")
                        .font(.system(size: 18, weight: .bold))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .onChange(of: selectedItem) { _, newItem in
                if let item = newItem {
                    processSelectedItem(item)
                }
            }

            Spacer()
        }
    }

    private var loadingView: some View {
        VStack(spacing: 24) {
            Spacer()
            BrutalLoading(text: "Preparing")
            Spacer()
        }
    }

    private var uploadingView: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 16) {
                // Circular progress
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 8)
                        .frame(width: 100, height: 100)

                    Circle()
                        .trim(from: 0, to: uploadProgress)
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .frame(width: 100, height: 100)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.2), value: uploadProgress)

                    Text("\(Int(uploadProgress * 100))%")
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                }

                Text("UPLOADING")
                    .font(.system(size: 24, weight: .black))
                    .foregroundStyle(.white)
                    .tracking(2)
            }

            Spacer()

            Button {
                cancelUpload()
            } label: {
                Text("Cancel")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.brutalTextSecondary)
            }

            Spacer()
        }
    }

    private var successView: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)

                Text("UPLOADED")
                    .font(.system(size: 24, weight: .black))
                    .foregroundStyle(.white)
                    .tracking(2)

                Text("Link copied to clipboard")
                    .brutalTypography(.bodyMedium, color: .brutalTextSecondary)
            }

            if let record = uploadedRecord {
                Text(record.url)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Color.brutalTextTertiary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Button {
                reset()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .semibold))
                    Text("Upload Another")
                        .font(.system(size: 18, weight: .bold))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Spacer()
        }
    }

    private var errorView: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.orange)

                Text("UPLOAD FAILED")
                    .font(.system(size: 24, weight: .black))
                    .foregroundStyle(.white)
                    .tracking(2)

                if let error = errorMessage {
                    Text(error)
                        .brutalTypography(.bodyMedium, color: .brutalTextSecondary)
                        .multilineTextAlignment(.center)
                }
            }

            Spacer()

            VStack(spacing: 12) {
                Button {
                    if let item = selectedItem {
                        processSelectedItem(item)
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 20, weight: .semibold))
                        Text("Retry")
                            .font(.system(size: 18, weight: .bold))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Button {
                    reset()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.brutalTextSecondary)
                }
            }

            Spacer()
        }
    }

    // MARK: - Actions

    private func processSelectedItem(_ item: PhotosPickerItem) {
        uploadState = .loading

        Task {
            do {
                // Load the image data
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw ImageHostError.imageProcessingFailed
                }

                // Determine filename
                let filename = generateFilename(for: data)

                // Start upload
                await MainActor.run {
                    uploadState = .uploading
                    uploadProgress = 0
                }

                let record = try await UploadService.shared.upload(
                    imageData: data,
                    filename: filename
                ) { progress in
                    Task { @MainActor in
                        uploadProgress = progress
                    }
                }

                // Copy formatted URL to clipboard
                let formattedLink = LinkFormatService.shared.format(
                    url: record.url,
                    filename: record.originalFilename
                )
                await MainActor.run {
                    UIPasteboard.general.string = formattedLink
                }

                // Play haptic feedback
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)

                // Save to history
                try? HistoryService.shared.save(record)

                await MainActor.run {
                    uploadedRecord = record
                    uploadState = .success
                }

            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    uploadState = .error
                }
            }
        }
    }

    private func generateFilename(for data: Data) -> String {
        // Try to detect image type from data
        let bytes = [UInt8](data.prefix(12))

        let ext: String
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            ext = "png"
        } else if bytes.starts(with: [0x47, 0x49, 0x46]) {
            ext = "gif"
        } else if bytes.count >= 12 && bytes[4...11] == [0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63] {
            ext = "heic"
        } else if data.prefix(4).starts(with: [0x52, 0x49, 0x46, 0x46]) && data.count > 12 {
            let webpBytes = [UInt8](data[8..<12])
            if webpBytes == [0x57, 0x45, 0x42, 0x50] {
                ext = "webp"
            } else {
                ext = "jpg"
            }
        } else {
            ext = "jpg"
        }

        let timestamp = Int(Date().timeIntervalSince1970)
        return "upload_\(timestamp).\(ext)"
    }

    private func cancelUpload() {
        UploadService.shared.cancelUpload()
        reset()
    }

    private func reset() {
        selectedItem = nil
        uploadState = .idle
        uploadProgress = 0
        errorMessage = nil
        uploadedRecord = nil
    }
}

#Preview {
    UploadView()
}
