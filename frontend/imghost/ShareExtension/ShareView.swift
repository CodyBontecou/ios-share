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
    @State private var pendingFileURL: URL?
    @State private var fileSizeMB: Double = 0
    @State private var isMediaFile: Bool = true
    @State private var isLargeFile: Bool = false
    @State private var selectedQuality: UploadQuality = UploadQualityService.shared.currentQuality
    @State private var estimatedSize: String = ""
    @State private var currentUser: User?
    @State private var storageWarning: String?
    @State private var wouldExceedStorage: Bool = false
    @State private var compressionStatus: String = ""
    @State private var needsCompression: Bool = false
    
    @State private var compressionQuality: Double = 0.8
    @State private var maxDimensionIndex: Int = 0
    @State private var estimatedCompressedSize: Double = 0
    @State private var isCalculatingSize: Bool = false
    @State private var originalImageDimensions: CGSize = .zero
    
    @State private var isVideoFile: Bool = false
    @State private var selectedVideoPreset: UploadQualityService.VideoQualityPreset = .medium
    @State private var videoDuration: Double = 0
    @State private var videoDimensions: CGSize = .zero
    
    private let dimensionOptions: [(label: String, value: CGFloat?)] = [
        ("ORIGINAL", nil),
        ("8K", 8192),
        ("6K", 6144),
        ("4K", 4096),
        ("3K", 3072),
        ("2K", 2048),
        ("1080P", 1920),
        ("1K", 1024),
    ]
    
    private let largeFileThreshold: Int64 = 50 * 1024 * 1024
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
        case fileTooLarge
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

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
        .onAppear {
            prepareUpload()
        }
    }

    // MARK: - State Views

    private var loadingView: some View {
        VStack {
            Spacer()
            Text("LOADING...")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
                .tracking(3)
            Spacer()
        }
    }

    private var readyView: some View {
        VStack(spacing: 0) {
            // Header
            header(title: pendingFilename ?? "FILE")
            
            // Preview area - takes up available space
            previewSection
            
            // Info & Controls
            VStack(spacing: 0) {
                // File info bar
                HStack {
                    Text(String(format: "%.1f MB", fileSizeMB))
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                    
                    Spacer()
                    
                    if isVideoFile && videoDuration > 0 {
                        Text(formatDuration(videoDuration))
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                    } else if originalImageDimensions != .zero {
                        Text("\(Int(originalImageDimensions.width))×\(Int(originalImageDimensions.height))")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                    }
                }
                .foregroundStyle(.white.opacity(0.4))
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .overlay(Rectangle().frame(height: 1).foregroundStyle(.white.opacity(0.1)), alignment: .top)
                
                // Quality picker or compression controls
                if needsCompression {
                    compressionControlsView
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                } else if isMediaFile && previewImage != nil && !isLargeFile {
                    qualitySection
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)
                }

                // Storage warning
                if let warning = storageWarning {
                    HStack(spacing: 12) {
                        Text("!")
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                        Text(warning.uppercased())
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .tracking(1)
                        Spacer()
                    }
                    .foregroundStyle(Color(hex: "FF453A"))
                    .padding(16)
                    .background(Color(hex: "FF453A").opacity(0.1))
                    .overlay(Rectangle().stroke(Color(hex: "FF453A").opacity(0.3), lineWidth: 1))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 16)
                }
            }
            
            // Action buttons
            actionButtons
        }
        .onAppear {
            updateEstimatedSize()
            if !isVideoFile && originalImageDimensions == .zero {
                loadOriginalImageDimensions()
            }
        }
    }
    
    private var header: some View {
        header(title: pendingFilename ?? "FILE")
    }
    
    private func header(title: String) -> some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Text("CANCEL")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                    .tracking(1)
            }
            
            Spacer()
            
            Text(title.uppercased())
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
                .tracking(1)
                .lineLimit(1)
            
            Spacer()
            
            // Invisible spacer to balance
            Text("CANCEL")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.clear)
                .tracking(1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(.white.opacity(0.1)), alignment: .bottom)
    }
    
    private var previewSection: some View {
        GeometryReader { geo in
            if let image = previewImage {
                ZStack {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: geo.size.width, maxHeight: geo.size.height)
                    
                    if isVideoFile {
                        // Play button overlay
                        Circle()
                            .fill(.black.opacity(0.5))
                            .frame(width: 72, height: 72)
                            .overlay(
                                Image(systemName: "play.fill")
                                    .font(.system(size: 28))
                                    .foregroundStyle(.white)
                                    .offset(x: 2)
                            )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let filename = pendingFilename {
                VStack(spacing: 16) {
                    Image(systemName: fileIcon(for: filename))
                        .font(.system(size: 64))
                        .foregroundStyle(.white.opacity(0.2))
                    
                    Text(filename.uppercased())
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.3))
                        .tracking(1)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Color.clear
            }
        }
    }
    
    private var qualitySection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("QUALITY")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                    .tracking(2)
                
                Spacer()
                
                Text(estimatedSize)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
            }

            qualityPicker
        }
    }
    
    private var qualityPicker: some View {
        HStack(spacing: 0) {
            ForEach(UploadQuality.allCases) { quality in
                qualityButton(for: quality)
            }
        }
        .overlay(Rectangle().stroke(Color.white.opacity(0.2), lineWidth: 1))
    }
    
    private func qualityButton(for quality: UploadQuality) -> some View {
        let isSelected = selectedQuality == quality
        
        return Button {
            selectedQuality = quality
            updateEstimatedSize()
        } label: {
            Text(quality.displayLabel.uppercased())
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .tracking(1)
                .foregroundStyle(isSelected ? .black : .white.opacity(0.5))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(isSelected ? Color.white : Color.clear)
        }
    }
    
    private var actionButtons: some View {
        VStack(spacing: 0) {
            Button {
                startUpload()
            } label: {
                Text("UPLOAD")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .tracking(3)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(wouldExceedStorage || (needsCompression && (estimatedCompressedSize > 100 || isCalculatingSize)) ? Color.white.opacity(0.3) : Color.white)
            }
            .disabled(wouldExceedStorage || (needsCompression && (estimatedCompressedSize > 100 || isCalculatingSize)))
        }
    }

    private var uploadingView: some View {
        VStack(spacing: 0) {
            header(title: "UPLOADING")
            
            // Preview
            GeometryReader { geo in
                if let image = previewImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: geo.size.width, maxHeight: geo.size.height)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .opacity(0.5)
                }
            }
            
            // Progress section
            VStack(spacing: 20) {
                // Progress bar
                VStack(spacing: 12) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(Color.white.opacity(0.1))
                            Rectangle()
                                .fill(Color.white)
                                .frame(width: geo.size.width * progress)
                        }
                    }
                    .frame(height: 4)
                    
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 20)
                
                Button {
                    UploadService.shared.cancelUpload()
                    dismiss()
                } label: {
                    Text("CANCEL")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(hex: "FF453A"))
                        .tracking(2)
                        .frame(height: 44)
                }
            }
            .padding(.bottom, 40)
        }
    }

    private var successView: some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 32) {
                Text("✓")
                    .font(.system(size: 72, weight: .light))
                    .foregroundStyle(Color(hex: "30D158"))
                
                VStack(spacing: 12) {
                    Text("COPIED TO CLIPBOARD")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .tracking(2)
                    
                    Text(uploadedURL)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            }
            
            Spacer()
            
            Button {
                dismiss()
            } label: {
                Text("DONE")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .tracking(3)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.white)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                dismiss()
            }
        }
    }

    private var errorView: some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 32) {
                Text("!")
                    .font(.system(size: 72, weight: .bold))
                    .foregroundStyle(Color(hex: "FFD60A"))
                
                VStack(spacing: 12) {
                    Text("UPLOAD FAILED")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .tracking(2)
                    
                    Text(errorMessage.uppercased())
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            }
            
            Spacer()
            
            VStack(spacing: 0) {
                Button {
                    state = .ready
                } label: {
                    Text("RETRY")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .tracking(3)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.white)
                }
                
                Button {
                    dismiss()
                } label: {
                    Text("CANCEL")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                        .tracking(2)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                }
            }
        }
    }

    private var notConfiguredView: some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 32) {
                Text("?")
                    .font(.system(size: 72, weight: .bold))
                    .foregroundStyle(Color(hex: "FFD60A"))
                
                VStack(spacing: 12) {
                    Text("NOT LOGGED IN")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .tracking(2)
                    
                    Text("OPEN THE IMGHOST APP TO LOG IN")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            }
            
            Spacer()
            
            Button {
                dismiss()
            } label: {
                Text("DONE")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .tracking(3)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.white)
            }
        }
    }

    private var storageFullView: some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 32) {
                Text("X")
                    .font(.system(size: 72, weight: .bold))
                    .foregroundStyle(Color(hex: "FF453A"))
                
                VStack(spacing: 16) {
                    Text("STORAGE FULL")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .tracking(2)
                    
                    if let user = currentUser {
                        VStack(spacing: 8) {
                            Text("\(user.storageUsedFormatted) / \(user.storageLimitFormatted)")
                                .font(.system(size: 16, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.6))
                            
                            Text("NEED \(String(format: "%.1f MB", fileSizeMB)) MORE")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }
                    
                    Text("DELETE FILES OR UPGRADE YOUR PLAN")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            }
            
            Spacer()
            
            Button {
                dismiss()
            } label: {
                Text("DONE")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .tracking(3)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.white)
            }
        }
    }

    private var compressionControlsView: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Text("↓")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                    Text("COMPRESSION")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .tracking(1)
                }
                .foregroundStyle(Color(hex: "FFD60A"))
                
                Spacer()
                
                // Estimated size
                if isCalculatingSize {
                    Text("...")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                } else {
                    let exceedsLimit = estimatedCompressedSize > 100
                    HStack(spacing: 6) {
                        Text(exceedsLimit ? "!" : "✓")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(exceedsLimit ? Color(hex: "FF453A") : Color(hex: "30D158"))
                        Text(String(format: "~%.1f MB", estimatedCompressedSize))
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(exceedsLimit ? Color(hex: "FF453A") : .white)
                    }
                }
            }
            
            if isVideoFile {
                videoQualityPicker
            } else {
                imageCompressionControls
            }
        }
        .padding(16)
        .overlay(Rectangle().stroke(Color.white.opacity(0.2), lineWidth: 1))
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
    
    private var videoQualityPicker: some View {
        VStack(spacing: 12) {
            HStack(spacing: 0) {
                ForEach(UploadQualityService.VideoQualityPreset.allCases, id: \.self) { preset in
                    videoPresetButton(for: preset)
                }
            }
            .overlay(Rectangle().stroke(Color.white.opacity(0.2), lineWidth: 1))
            
            Text(videoPresetDescription.uppercased())
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
                .tracking(1)
        }
    }
    
    private func videoPresetButton(for preset: UploadQualityService.VideoQualityPreset) -> some View {
        let isSelected = selectedVideoPreset == preset
        
        return Button {
            selectedVideoPreset = preset
            calculateEstimatedVideoSize()
        } label: {
            Text(preset.displayLabel.uppercased())
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .tracking(1)
                .foregroundStyle(isSelected ? .black : .white.opacity(0.5))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(isSelected ? Color.white : Color.clear)
        }
    }
    
    private var imageCompressionControls: some View {
        VStack(spacing: 20) {
            // Quality slider
            VStack(spacing: 10) {
                HStack {
                    Text("QUALITY")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                        .tracking(1)
                    Spacer()
                    Text("\(Int(compressionQuality * 100))%")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                }
                
                BrutalSlider(value: $compressionQuality, range: 0.1...1.0)
                    .onChange(of: compressionQuality) { _, _ in
                        calculateEstimatedSize()
                    }
            }
            
            // Dimension picker
            VStack(spacing: 10) {
                HStack {
                    Text("MAX SIZE")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                        .tracking(1)
                    Spacer()
                    Text(dimensionOptions[maxDimensionIndex].label)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                }
                
                BrutalSlider(
                    value: Binding(
                        get: { Double(maxDimensionIndex) },
                        set: { maxDimensionIndex = Int($0) }
                    ),
                    range: 0...Double(dimensionOptions.count - 1),
                    step: 1
                )
                .onChange(of: maxDimensionIndex) { _, _ in
                    calculateEstimatedSize()
                }
            }
        }
    }
    
    private var videoPresetDescription: String {
        switch selectedVideoPreset {
        case .high: return "Best quality, larger file"
        case .medium: return "Balanced quality and size"
        case .low: return "Smaller file, reduced quality"
        case .veryLow: return "Smallest file, lowest quality"
        }
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }

    private var compressingView: some View {
        VStack(spacing: 0) {
            header(title: isVideoFile ? "COMPRESSING VIDEO" : "COMPRESSING")
            
            // Preview
            GeometryReader { geo in
                if let image = previewImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: geo.size.width, maxHeight: geo.size.height)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .opacity(0.5)
                }
            }
            
            // Progress section
            VStack(spacing: 20) {
                if isVideoFile && progress > 0 {
                    VStack(spacing: 12) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(Color.white.opacity(0.1))
                                Rectangle()
                                    .fill(Color.white)
                                    .frame(width: geo.size.width * progress)
                            }
                        }
                        .frame(height: 4)
                        
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 32, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                } else {
                    Text(compressionStatus.isEmpty ? "REDUCING SIZE..." : compressionStatus.uppercased())
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                        .tracking(1)
                }
                
                Button {
                    dismiss()
                } label: {
                    Text("CANCEL")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(hex: "FF453A"))
                        .tracking(2)
                        .frame(height: 44)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }

    private var fileTooLargeView: some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 32) {
                Text("X")
                    .font(.system(size: 72, weight: .bold))
                    .foregroundStyle(Color(hex: "FF453A"))
                
                VStack(spacing: 12) {
                    Text("FILE TOO LARGE")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .tracking(2)
                    
                    VStack(spacing: 8) {
                        Text("\(String(format: "%.0f MB", fileSizeMB)) EXCEEDS 100 MB LIMIT")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.4))
                        
                        if let filename = pendingFilename {
                            let canCompress = UploadQualityService.shared.canCompress(filename: filename)
                            Text(canCompress ? "COMPRESSION FAILED" : "THIS FILE TYPE CAN'T BE COMPRESSED")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }
                }
            }
            
            Spacer()
            
            Button {
                dismiss()
            } label: {
                Text("DONE")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .tracking(3)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color.white)
            }
        }
    }

    // MARK: - Actions

    private func prepareUpload() {
        guard UploadService.shared.isConfigured else {
            state = .notConfigured
            return
        }

        state = .loading

        Task {
            do {
                let user = try await AuthService.shared.getCurrentUser()
                let (fileURL, filename, fileSize) = try await loadFileURL()
                
                await MainActor.run {
                    currentUser = user
                    pendingFilename = filename
                    pendingFileURL = fileURL
                    fileSizeMB = Double(fileSize) / (1024 * 1024)
                    isLargeFile = fileSize >= largeFileThreshold
                    needsCompression = fileSize > maxUploadSize

                    let lowercased = filename.lowercased()
                    isMediaFile = lowercased.hasSuffix(".jpg") || lowercased.hasSuffix(".jpeg") ||
                                  lowercased.hasSuffix(".png") || lowercased.hasSuffix(".gif") ||
                                  lowercased.hasSuffix(".heic") || lowercased.hasSuffix(".webp") ||
                                  lowercased.hasSuffix(".bmp") || lowercased.hasSuffix(".tiff")
                    
                    isVideoFile = UploadQualityService.shared.isVideo(filename: filename)
                }
                
                let isVideo = UploadQualityService.shared.isVideo(filename: filename)
                
                if isVideo {
                    let thumbnail = await generateVideoThumbnail(fileURL: fileURL)
                    await MainActor.run {
                        previewImage = thumbnail
                    }
                    // Load video info
                    if let info = await UploadQualityService.shared.getVideoInfo(fileURL: fileURL) {
                        await MainActor.run {
                            videoDuration = info.duration
                            videoDimensions = info.dimensions
                        }
                    }
                } else if !isLargeFile || isMediaFile {
                    if fileSize < 100 * 1024 * 1024 {
                        let fileData = try Data(contentsOf: fileURL)
                        
                        await MainActor.run {
                            pendingFileData = fileData
                            if isMediaFile, let image = UIImage(data: fileData) {
                                previewImage = image
                            }
                        }
                    } else {
                        await MainActor.run {
                            if isMediaFile {
                                previewImage = generateThumbnailFromURL(fileURL)
                            }
                        }
                    }
                }

                await MainActor.run {
                    if fileSize > maxUploadSize {
                        let canCompress = UploadQualityService.shared.canCompress(filename: filename)
                        if canCompress {
                            needsCompression = true
                            state = .ready
                        } else {
                            state = .fileTooLarge
                        }
                        return
                    }
                    
                    if !user.canUpload(bytes: Int(fileSize)) {
                        if isMediaFile && previewImage != nil && !isLargeFile {
                            state = .ready
                        } else {
                            state = .storageFull
                        }
                    } else {
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
    
    private func generateThumbnailFromURL(_ url: URL) -> UIImage? {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 800,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: thumbnail)
    }
    
    private func generateVideoThumbnail(fileURL: URL) async -> UIImage? {
        let asset = AVURLAsset(url: fileURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 800, height: 800)
        
        do {
            let cgImage = try imageGenerator.copyCGImage(at: .zero, actualTime: nil)
            return UIImage(cgImage: cgImage)
        } catch {
            return nil
        }
    }
    
    private func loadOriginalImageDimensions() {
        guard let fileURL = pendingFileURL else { return }
        
        Task.detached {
            guard let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
                  let height = properties[kCGImagePropertyPixelHeight] as? CGFloat else { return }
            
            await MainActor.run {
                originalImageDimensions = CGSize(width: width, height: height)
            }
        }
    }
    
    private func calculateEstimatedSize() {
        guard let fileURL = pendingFileURL else { return }
        
        isCalculatingSize = true
        
        Task {
            try? await Task.sleep(nanoseconds: 200_000_000)
            
            let quality = compressionQuality
            let maxDim = dimensionOptions[maxDimensionIndex].value
            
            let estimatedMB = await Task.detached { () -> Double in
                guard let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
                      let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else { return 0 }
                
                var image = UIImage(cgImage: cgImage)
                
                if let maxDimension = maxDim {
                    image = ImageProcessor.shared.resize(image: image, maxDimension: maxDimension)
                }
                
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
    
    private func calculateEstimatedVideoSize() {
        isCalculatingSize = true
        
        Task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            
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

        if needsCompression, let fileURL = pendingFileURL {
            performCompressedUpload(fileURL: fileURL, filename: filename)
            return
        }
        
        if isLargeFile, let fileURL = pendingFileURL {
            performFileUpload(fileURL: fileURL, filename: filename)
            return
        }
        
        guard let data = pendingFileData else { return }

        let (processedData, processedFilename) = UploadQualityService.shared.processForUpload(
            data: data,
            filename: filename,
            quality: selectedQuality
        )
        performUpload(data: processedData, filename: processedFilename)
    }
    
    private func performCompressedUpload(fileURL: URL, filename: String) {
        state = .compressing
        compressionStatus = "Preparing..."
        
        if isVideoFile {
            performVideoCompressedUpload(fileURL: fileURL, filename: filename)
        } else {
            performImageCompressedUpload(fileURL: fileURL, filename: filename)
        }
    }
    
    private func performImageCompressedUpload(fileURL: URL, filename: String) {
        compressionStatus = "Applying settings..."
        
        let quality = compressionQuality
        let maxDim = dimensionOptions[maxDimensionIndex].value
        
        Task {
            let result = await Task.detached { () -> (Data, String)? in
                guard let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
                      let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else { return nil }
                
                var image = UIImage(cgImage: cgImage)
                
                if let maxDimension = maxDim {
                    await MainActor.run { self.compressionStatus = "Resizing..." }
                    image = ImageProcessor.shared.resize(image: image, maxDimension: maxDimension)
                }
                
                await MainActor.run { self.compressionStatus = "Compressing..." }
                
                guard let compressedData = image.jpegData(compressionQuality: quality) else { return nil }
                
                let newFilename = filename.replacingOccurrences(of: "\\.[^.]+$", with: ".jpg", options: .regularExpression)
                
                return (compressedData, newFilename)
            }.value
            
            await MainActor.run {
                if let (compressedData, compressedFilename) = result {
                    performUpload(data: compressedData, filename: compressedFilename)
                } else {
                    errorMessage = "Failed to compress image"
                    state = .error
                }
            }
        }
    }
    
    private func performVideoCompressedUpload(fileURL: URL, filename: String) {
        compressionStatus = "Starting..."
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
                        self.progress = p * 0.5
                    }
                }
            }
            
            await MainActor.run {
                if let outputURL = compressedURL {
                    let newFilename = filename.replacingOccurrences(of: "\\.[^.]+$", with: ".mp4", options: .regularExpression)
                    performFileUploadWithCleanup(fileURL: outputURL, filename: newFilename)
                } else {
                    errorMessage = "Failed to compress video"
                    state = .error
                }
            }
        }
    }
    
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
                        self.progress = 0.5 + (uploadProgress * 0.5)
                    }
                }
                
                await MainActor.run {
                    let formattedLink = LinkFormatService.shared.format(url: record.url, filename: record.originalFilename)
                    UIPasteboard.general.string = formattedLink
                }
                
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
                
                try? HistoryService.shared.save(record)
                
                await MainActor.run {
                    uploadedURL = record.url
                    state = .success
                }
                
                try? FileManager.default.removeItem(at: fileURL)
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    state = .error
                }
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

        if needsCompression {
            estimatedSize = "WILL COMPRESS"
            wouldExceedStorage = false
            storageWarning = nil
            return
        }

        if isLargeFile || !isMediaFile || previewImage == nil {
            estimatedSize = isLargeFile ? "ORIGINAL" : "NO COMPRESSION"
            if let user = currentUser {
                let fileBytes = Int(fileSizeMB * 1024 * 1024)
                wouldExceedStorage = !user.canUpload(bytes: fileBytes)
                storageWarning = wouldExceedStorage ? "EXCEEDS STORAGE (\(user.storageRemainingFormatted))" : nil
            }
            return
        }

        let multiplier: Double
        switch selectedQuality {
        case .original: multiplier = 1.0
        case .high: multiplier = 0.7
        case .medium: multiplier = 0.4
        case .low: multiplier = 0.2
        }

        let estimatedMB = fileSizeMB * multiplier
        let estimatedBytes = Int(estimatedMB * 1024 * 1024)

        estimatedSize = selectedQuality == .original ? "ORIGINAL" : String(format: "~%.1f MB", estimatedMB)

        if let user = currentUser {
            wouldExceedStorage = !user.canUpload(bytes: estimatedBytes)
            storageWarning = wouldExceedStorage ? "EXCEEDS STORAGE (\(user.storageRemainingFormatted))" : nil
        }
    }

    private func fileIcon(for filename: String) -> String {
        let lowercased = filename.lowercased()
        
        if lowercased.hasSuffix(".mp4") || lowercased.hasSuffix(".mov") || lowercased.hasSuffix(".avi") || lowercased.hasSuffix(".mkv") || lowercased.hasSuffix(".webm") { return "film" }
        if lowercased.hasSuffix(".mp3") || lowercased.hasSuffix(".wav") || lowercased.hasSuffix(".m4a") || lowercased.hasSuffix(".aac") || lowercased.hasSuffix(".flac") { return "waveform" }
        if lowercased.hasSuffix(".pdf") { return "doc.richtext" }
        if lowercased.hasSuffix(".doc") || lowercased.hasSuffix(".docx") { return "doc.text" }
        if lowercased.hasSuffix(".xls") || lowercased.hasSuffix(".xlsx") { return "tablecells" }
        if lowercased.hasSuffix(".zip") || lowercased.hasSuffix(".gz") || lowercased.hasSuffix(".tar") || lowercased.hasSuffix(".rar") { return "doc.zipper" }
        if lowercased.hasSuffix(".json") || lowercased.hasSuffix(".xml") || lowercased.hasSuffix(".html") || lowercased.hasSuffix(".css") || lowercased.hasSuffix(".js") { return "curlybraces" }
        
        return "doc"
    }

    private func performUpload(data: Data, filename: String) {
        state = .uploading
        progress = 0

        Task {
            do {
                let record = try await UploadService.shared.upload(
                    imageData: data,
                    filename: filename
                ) { uploadProgress in
                    Task { @MainActor in
                        progress = uploadProgress
                    }
                }

                await MainActor.run {
                    let formattedLink = LinkFormatService.shared.format(url: record.url, filename: record.originalFilename)
                    UIPasteboard.general.string = formattedLink
                }

                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)

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
    
    private func performFileUpload(fileURL: URL, filename: String) {
        state = .uploading
        progress = 0

        Task {
            do {
                let record = try await UploadService.shared.uploadFromFile(
                    fileURL: fileURL,
                    filename: filename
                ) { uploadProgress in
                    Task { @MainActor in
                        progress = uploadProgress
                    }
                }

                await MainActor.run {
                    let formattedLink = LinkFormatService.shared.format(url: record.url, filename: record.originalFilename)
                    UIPasteboard.general.string = formattedLink
                }

                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)

                try? HistoryService.shared.save(record)

                await MainActor.run {
                    uploadedURL = record.url
                    state = .success
                }
                
                try? FileManager.default.removeItem(at: fileURL)
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    state = .error
                }
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
    }

    private func dismiss() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}

// MARK: - Brutal Slider

struct BrutalSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double? = nil
    
    var body: some View {
        GeometryReader { geo in
            let normalizedValue = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let thumbPosition = normalizedValue * geo.size.width
            
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 4)
                
                Rectangle()
                    .fill(Color.white)
                    .frame(width: thumbPosition, height: 4)
                
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 20, height: 20)
                    .offset(x: thumbPosition - 10)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let newValue = (gesture.location.x / geo.size.width) * (range.upperBound - range.lowerBound) + range.lowerBound
                        var clampedValue = min(max(newValue, range.lowerBound), range.upperBound)
                        
                        if let step = step {
                            clampedValue = (clampedValue / step).rounded() * step
                        }
                        
                        value = clampedValue
                    }
            )
        }
        .frame(height: 20)
    }
}

// MARK: - Extensions

extension UploadQuality {
    var displayLabel: String {
        switch self {
        case .original: return "Full"
        case .high: return "High"
        case .medium: return "Med"
        case .low: return "Low"
        }
    }
}

extension UploadQualityService.VideoQualityPreset {
    var displayLabel: String {
        switch self {
        case .high: return "High"
        case .medium: return "Med"
        case .low: return "Low"
        case .veryLow: return "Min"
        }
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

#Preview {
    ShareView(
        extensionContext: nil,
        loadImage: {
            let image = UIImage(systemName: "photo")!
            return (image.pngData()!, "test.png")
        },
        loadFileURL: {
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test.png")
            let image = UIImage(systemName: "photo")!
            try? image.pngData()?.write(to: tempURL)
            return (tempURL, "test.png", 1024)
        }
    )
}
