import SwiftUI

struct HistoryView: View {
    @State private var records: [UploadRecord] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var deletingIds: Set<String> = []
    @State private var selectedRecord: UploadRecord?

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
                            Text("NO\nMEDIA\nYET")
                                .font(.system(size: 48, weight: .black))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)

                            VStack(spacing: 8) {
                                Text("Upload files to get started.")
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
                ToolbarItem(placement: .principal) {
                    Text("MEDIA")
                        .brutalTypography(.mono)
                        .tracking(2)
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
}

#Preview {
    HistoryView()
}
