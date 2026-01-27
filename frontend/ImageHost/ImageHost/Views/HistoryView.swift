import SwiftUI

struct HistoryView: View {
    @State private var records: [UploadRecord] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var deletingIds: Set<String> = []

    // Export state
    @State private var showingExportSheet = false
    @State private var exportState: ExportState = .idle
    @State private var currentJobId: String?
    @State private var exportProgress: Double = 0.0
    @State private var exportError: String?
    @State private var exportedFileURL: URL?
    @State private var showingShareSheet = false

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

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
            Group {
                if isLoading {
                    ProgressView("Loading...")
                } else if let error = errorMessage {
                    ContentUnavailableView {
                        Label("Error", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Retry") {
                            loadHistory()
                        }
                    }
                } else if records.isEmpty {
                    ContentUnavailableView {
                        Label("No Uploads", systemImage: "photo.on.rectangle.angled")
                    } description: {
                        Text("Your upload history will appear here.\n\nShare an image from Photos to get started.")
                    }
                } else {
                    List {
                        ForEach(records) { record in
                            NavigationLink(destination: UploadDetailView(record: record, onDelete: {
                                deleteRecord(record)
                            })) {
                                HistoryRow(record: record, dateFormatter: dateFormatter)
                            }
                            .disabled(deletingIds.contains(record.id))
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    deleteRecord(record)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .disabled(deletingIds.contains(record.id))
                            }
                        }
                    }
                    .refreshable {
                        loadHistory()
                    }
                }
            }
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingExportSheet = true
                    } label: {
                        Label("Export All Images", systemImage: "square.and.arrow.down")
                    }
                    .disabled(records.isEmpty || isLoading)
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

struct HistoryRow: View {
    let record: UploadRecord
    let dateFormatter: DateFormatter

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            if let thumbnailData = record.thumbnailData,
               let uiImage = UIImage(data: thumbnailData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 50, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 50, height: 50)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.gray)
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                // URL (truncated)
                Text(truncatedURL(record.url))
                    .font(.subheadline)
                    .lineLimit(1)

                // Date
                Text(dateFormatter.string(from: record.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func truncatedURL(_ url: String) -> String {
        guard let urlComponents = URLComponents(string: url) else {
            return url
        }

        let host = urlComponents.host ?? ""
        let path = urlComponents.path

        if path.count > 20 {
            return "\(host)/...\(path.suffix(15))"
        }
        return "\(host)\(path)"
    }
}

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
            VStack(spacing: 20) {
                switch exportState {
                case .idle:
                    VStack(spacing: 16) {
                        Image(systemName: "square.and.arrow.down.on.square")
                            .font(.system(size: 60))
                            .foregroundStyle(.blue)

                        Text("Export All Images")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text("This will create a ZIP archive of all your uploaded images. The process may take a few moments depending on the number of images.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        Button {
                            onStartExport()
                        } label: {
                            Text("Start Export")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.horizontal)
                        .padding(.top, 8)
                    }

                case .starting:
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)

                        Text("Starting export...")
                            .font(.headline)
                    }

                case .exporting(let progress):
                    VStack(spacing: 16) {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .padding(.horizontal)

                        Text("Exporting images: \(Int(progress * 100))%")
                            .font(.headline)

                        Button("Cancel", role: .cancel) {
                            onCancelExport()
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                    }

                case .downloading(let progress):
                    VStack(spacing: 16) {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .padding(.horizontal)

                        Text("Downloading archive: \(Int(progress * 100))%")
                            .font(.headline)

                        Button("Cancel", role: .cancel) {
                            onCancelExport()
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                    }

                case .complete:
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.green)

                        Text("Export Complete!")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text("Your images have been exported successfully.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        if let url = exportedFileURL {
                            Button {
                                onShare(url)
                            } label: {
                                Label("Share Archive", systemImage: "square.and.arrow.up")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .padding(.horizontal)
                        }

                        Button("Done") {
                            onDismiss()
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                    }

                case .error(let message):
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.red)

                        Text("Export Failed")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text(message)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        Button("Try Again") {
                            onStartExport()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Cancel") {
                            onDismiss()
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Spacer()
            }
            .padding()
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

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    HistoryView()
}
