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
                Color.brutalBackground.ignoresSafeArea()

                Group {
                    if isLoading {
                        BrutalLoading(text: "Loading")
                    } else if let error = errorMessage {
                        BrutalEmptyState(
                            title: "Something went wrong",
                            subtitle: error,
                            action: loadHistory,
                            actionTitle: "Retry"
                        )
                    } else if records.isEmpty {
                        VStack(spacing: 24) {
                            Text("NO\nPHOTOS\nYET")
                                .font(.system(size: 48, weight: .black))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)

                            VStack(spacing: 8) {
                                Text("Share an image from Photos to get started.")
                                    .brutalTypography(.bodyMedium, color: .brutalTextSecondary)
                                    .multilineTextAlignment(.center)

                                Text("Your uploads will appear here.")
                                    .brutalTypography(.bodyMedium, color: .brutalTextTertiary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .padding(32)
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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        if let user = authState.currentUser {
                            BrutalAvatar(text: user.email, size: 28)
                        } else {
                            Text("☰")
                                .brutalTypography(.titleMedium)
                        }
                    }
                }

                ToolbarItem(placement: .principal) {
                    Text("PHOTOS")
                        .brutalTypography(.mono)
                        .tracking(2)
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
                        Text("•••")
                            .brutalTypography(.titleMedium)
                    }
                }
            }
            .toolbarBackground(Color.brutalBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
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
                BrutalExportSheetView(
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
            .preferredColorScheme(.dark)
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

// MARK: - Brutal Export Sheet View

struct BrutalExportSheetView: View {
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
        ZStack {
            Color.brutalBackground.ignoresSafeArea()

            VStack(spacing: 24) {
                switch exportState {
                case .idle:
                    VStack(spacing: 24) {
                        Text("EXPORT")
                            .font(.system(size: 40, weight: .black))
                            .foregroundStyle(.white)

                        Text("Create a ZIP archive of all your uploaded images.")
                            .brutalTypography(.bodyMedium, color: .brutalTextSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)

                        BrutalPrimaryButton(
                            title: "Start Export",
                            action: onStartExport
                        )
                        .padding(.horizontal, 24)
                    }

                case .starting:
                    BrutalLoading(text: "Starting")

                case .exporting(let progress):
                    VStack(spacing: 24) {
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 56, weight: .black, design: .monospaced))
                            .foregroundStyle(.white)

                        BrutalProgressBar(progress: progress)
                            .padding(.horizontal, 48)

                        Text("EXPORTING IMAGES")
                            .brutalTypography(.monoSmall, color: .brutalTextSecondary)
                            .tracking(2)

                        BrutalSecondaryButton(title: "Cancel") {
                            onCancelExport()
                            dismiss()
                        }
                        .frame(width: 140)
                    }

                case .downloading(let progress):
                    VStack(spacing: 24) {
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 56, weight: .black, design: .monospaced))
                            .foregroundStyle(.white)

                        BrutalProgressBar(progress: progress)
                            .padding(.horizontal, 48)

                        Text("DOWNLOADING ARCHIVE")
                            .brutalTypography(.monoSmall, color: .brutalTextSecondary)
                            .tracking(2)
                    }

                case .complete:
                    VStack(spacing: 24) {
                        Text("✓")
                            .font(.system(size: 64, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.brutalSuccess)

                        Text("EXPORT COMPLETE")
                            .brutalTypography(.titleMedium)

                        if let url = exportedFileURL {
                            BrutalPrimaryButton(
                                title: "Share Archive",
                                action: { onShare(url) }
                            )
                            .padding(.horizontal, 24)
                        }

                        BrutalTextButton(title: "Done") {
                            onDismiss()
                            dismiss()
                        }
                    }

                case .error(let message):
                    VStack(spacing: 24) {
                        Text("✕")
                            .font(.system(size: 64, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.brutalError)

                        Text("EXPORT FAILED")
                            .brutalTypography(.titleMedium)

                        Text(message)
                            .brutalTypography(.bodySmall, color: .brutalTextSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)

                        BrutalPrimaryButton(title: "Try Again", action: onStartExport)
                            .frame(width: 160)

                        BrutalTextButton(title: "Cancel") {
                            onDismiss()
                            dismiss()
                        }
                    }
                }

                Spacer()
            }
            .padding(.top, 48)
        }
        .preferredColorScheme(.dark)
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
