import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var authState: AuthState
    @State private var records: [UploadRecord] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var deletingIds: Set<String> = []
    @State private var selectedRecord: UploadRecord?
    @State private var showSettings = false

    // Export state
    @State private var showingExportSheet = false
    @State private var exportState: ExportState = .idle
    @State private var currentJobId: String?
    @State private var exportProgress: Double = 0.0
    @State private var exportError: String?
    @State private var exportedFileURL: URL?
    @State private var showingShareSheet = false

    enum ExportState {
        case idle
        case starting
        case exporting(progress: Double)
        case downloading(progress: Double)
        case complete
        case error(String)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.googleSurface.ignoresSafeArea()

                Group {
                    if isLoading {
                        VStack(spacing: GoogleSpacing.sm) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Loading photos...")
                                .googleTypography(.bodyMedium, color: .googleTextSecondary)
                        }
                    } else if let error = errorMessage {
                        VStack(spacing: GoogleSpacing.lg) {
                            ZStack {
                                Circle()
                                    .fill(Color.googleRed.opacity(0.1))
                                    .frame(width: 80, height: 80)

                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 36))
                                    .foregroundStyle(Color.googleRed)
                            }

                            Text("Something went wrong")
                                .googleTypography(.titleMedium)

                            Text(error)
                                .googleTypography(.bodyMedium, color: .googleTextSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, GoogleSpacing.xl)

                            GooglePrimaryButton(title: "Retry", action: loadHistory)
                                .frame(width: 120)
                        }
                    } else if records.isEmpty {
                        VStack(spacing: GoogleSpacing.lg) {
                            ZStack {
                                Circle()
                                    .fill(Color.googleBlue.opacity(0.1))
                                    .frame(width: 100, height: 100)

                                Image(systemName: "photo.on.rectangle.angled")
                                    .font(.system(size: 44))
                                    .foregroundStyle(Color.googleBlue)
                            }

                            Text("No photos yet")
                                .googleTypography(.titleLarge)

                            Text("Share an image from Photos to get started.\nYour uploads will appear here.")
                                .googleTypography(.bodyMedium, color: .googleTextSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, GoogleSpacing.xl)
                        }
                    } else {
                        PhotoGridView(
                            records: records,
                            onSelect: { record in
                                selectedRecord = record
                            },
                            onDelete: { record in
                                deleteRecord(record)
                            }
                        )
                        .refreshable {
                            loadHistory()
                        }
                    }
                }
            }
            .navigationTitle("Photos")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        if let user = authState.currentUser {
                            AvatarView(email: user.email, size: 32)
                        } else {
                            Image(systemName: "person.circle")
                                .font(.system(size: 24))
                        }
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showingExportSheet = true
                        } label: {
                            Label("Export All Images", systemImage: "square.and.arrow.down.on.square")
                        }
                        .disabled(records.isEmpty)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 20))
                    }
                }
            }
            .navigationDestination(item: $selectedRecord) { record in
                UploadDetailView(record: record, onDelete: {
                    deleteRecord(record)
                })
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    SettingsView()
                }
            }
            .sheet(isPresented: $showingExportSheet) {
                ExportSheetView(
                    exportState: $exportState,
                    exportProgress: $exportProgress,
                    exportError: $exportError,
                    exportedFileURL: exportedFileURL,
                    onStartExport: { startExport() },
                    onCancelExport: { cancelExport() },
                    onShare: { url in
                        exportedFileURL = url
                        showingShareSheet = true
                    },
                    onDismiss: { resetExportState() }
                )
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $showingShareSheet) {
                if let url = exportedFileURL {
                    ShareSheet(activityItems: [url])
                }
            }
            .onAppear {
                loadHistory()
            }
        }
    }

    private func loadHistory() {
        isLoading = true
        errorMessage = nil

        do {
            records = try HistoryService.shared.loadAll()
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func deleteRecord(_ record: UploadRecord) {
        deletingIds.insert(record.id)

        Task {
            // Try to delete from server
            do {
                try await UploadService.shared.delete(record: record)
            } catch {
                // Continue with local deletion even if server delete fails
                print("Server delete failed: \(error)")
            }

            // Delete from local history
            do {
                try HistoryService.shared.delete(id: record.id)
                await MainActor.run {
                    records.removeAll { $0.id == record.id }
                    deletingIds.remove(record.id)
                }
            } catch {
                await MainActor.run {
                    deletingIds.remove(record.id)
                }
            }
        }
    }

    private func startExport() {
        Task {
            do {
                exportState = .starting
                exportError = nil

                // Start the export job
                let jobId = try await ExportService.shared.startExport()
                currentJobId = jobId

                // Poll for status updates
                let finalStatus = try await ExportService.shared.pollUntilComplete(jobId: jobId) { status in
                    switch status {
                    case .pending:
                        exportState = .exporting(progress: 0.0)
                    case .processing(let progress):
                        exportState = .exporting(progress: progress)
                    case .completed:
                        // Will be handled after polling completes
                        break
                    case .failed(let error):
                        exportState = .error(error)
                    }
                }

                // Download the archive if completed
                if case .completed = finalStatus {
                    exportState = .downloading(progress: 0.0)

                    let fileURL = try await ExportService.shared.downloadArchive(jobId: jobId) { progress in
                        _ = Task { @MainActor in
                            exportState = .downloading(progress: progress)
                        }
                    }

                    await MainActor.run {
                        exportedFileURL = fileURL
                        exportState = .complete
                    }
                }
            } catch {
                await MainActor.run {
                    exportState = .error(error.localizedDescription)
                    exportError = error.localizedDescription
                }
            }
        }
    }

    private func cancelExport() {
        guard let jobId = currentJobId else { return }

        Task {
            do {
                try await ExportService.shared.cancelExport(jobId: jobId)
                await MainActor.run {
                    resetExportState()
                }
            } catch {
                print("Failed to cancel export: \(error)")
            }
        }
    }

    private func resetExportState() {
        exportState = .idle
        currentJobId = nil
        exportProgress = 0.0
        exportError = nil
        exportedFileURL = nil
    }
}

// MARK: - Export Sheet View

struct ExportSheetView: View {
    @Binding var exportState: HistoryView.ExportState
    @Binding var exportProgress: Double
    @Binding var exportError: String?
    let exportedFileURL: URL?
    let onStartExport: () -> Void
    let onCancelExport: () -> Void
    let onShare: (URL) -> Void
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: GoogleSpacing.lg) {
                switch exportState {
                case .idle:
                    VStack(spacing: GoogleSpacing.sm) {
                        ZStack {
                            Circle()
                                .fill(Color.googleBlue.opacity(0.1))
                                .frame(width: 80, height: 80)

                            Image(systemName: "square.and.arrow.down.on.square")
                                .font(.system(size: 36))
                                .foregroundStyle(Color.googleBlue)
                        }

                        Text("Export All Images")
                            .googleTypography(.titleLarge)

                        Text("This will create a ZIP archive of all your uploaded images.")
                            .googleTypography(.bodyMedium, color: .googleTextSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, GoogleSpacing.lg)

                        GooglePrimaryButton(
                            title: "Start Export",
                            action: onStartExport
                        )
                        .padding(.horizontal, GoogleSpacing.lg)
                        .padding(.top, GoogleSpacing.sm)
                    }

                case .starting:
                    VStack(spacing: GoogleSpacing.sm) {
                        ProgressView()
                            .scaleEffect(1.5)

                        Text("Starting export...")
                            .googleTypography(.titleMedium)
                    }

                case .exporting(let progress):
                    VStack(spacing: GoogleSpacing.sm) {
                        CircularProgressView(progress: progress)

                        Text("Exporting images...")
                            .googleTypography(.titleMedium)

                        Text("\(Int(progress * 100))% complete")
                            .googleTypography(.bodyMedium, color: .googleTextSecondary)

                        GoogleSecondaryButton(title: "Cancel", action: {
                            onCancelExport()
                            dismiss()
                        })
                        .frame(width: 120)
                    }

                case .downloading(let progress):
                    VStack(spacing: GoogleSpacing.sm) {
                        CircularProgressView(progress: progress)

                        Text("Downloading archive...")
                            .googleTypography(.titleMedium)

                        Text("\(Int(progress * 100))% complete")
                            .googleTypography(.bodyMedium, color: .googleTextSecondary)
                    }

                case .complete:
                    VStack(spacing: GoogleSpacing.sm) {
                        ZStack {
                            Circle()
                                .fill(Color.googleGreen.opacity(0.1))
                                .frame(width: 80, height: 80)

                            Image(systemName: "checkmark")
                                .font(.system(size: 36, weight: .medium))
                                .foregroundStyle(Color.googleGreen)
                        }

                        Text("Export Complete!")
                            .googleTypography(.titleLarge)

                        Text("Your images have been exported successfully.")
                            .googleTypography(.bodyMedium, color: .googleTextSecondary)

                        if let url = exportedFileURL {
                            GooglePrimaryButton(
                                title: "Share Archive",
                                action: { onShare(url) },
                                icon: "square.and.arrow.up"
                            )
                            .padding(.horizontal, GoogleSpacing.lg)
                        }

                        GoogleTextButton(title: "Done") {
                            onDismiss()
                            dismiss()
                        }
                    }

                case .error(let message):
                    VStack(spacing: GoogleSpacing.sm) {
                        ZStack {
                            Circle()
                                .fill(Color.googleRed.opacity(0.1))
                                .frame(width: 80, height: 80)

                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 36))
                                .foregroundStyle(Color.googleRed)
                        }

                        Text("Export Failed")
                            .googleTypography(.titleLarge)

                        Text(message)
                            .googleTypography(.bodyMedium, color: .googleTextSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, GoogleSpacing.lg)

                        GooglePrimaryButton(title: "Try Again", action: onStartExport)
                            .frame(width: 140)

                        GoogleTextButton(title: "Cancel") {
                            onDismiss()
                            dismiss()
                        }
                    }
                }

                Spacer()
            }
            .padding(.top, GoogleSpacing.lg)
            .background(Color.googleSurface)
            .navigationTitle("Export Images")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if case .idle = exportState {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Circular Progress View

struct CircularProgressView: View {
    let progress: Double
    var size: CGFloat = 80
    var lineWidth: CGFloat = 8

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.googleOutline.opacity(0.3), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(Color.googleBlue, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: progress)

            Text("\(Int(progress * 100))%")
                .googleTypography(.labelLarge)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    HistoryView()
        .environmentObject(AuthState.shared)
}
