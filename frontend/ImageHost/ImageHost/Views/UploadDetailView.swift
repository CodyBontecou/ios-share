import SwiftUI

struct UploadDetailView: View {
    let record: UploadRecord
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirmation = false
    @State private var copiedField: CopiedField?
    @State private var isDeleting = false

    private enum CopiedField {
        case url, deleteUrl
    }

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .medium
        return formatter
    }()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    // Full-bleed image preview
                    Group {
                        if let thumbnailData = record.thumbnailData,
                           let uiImage = UIImage(data: thumbnailData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity)
                        } else {
                            Rectangle()
                                .fill(Color.googleSurfaceSecondary)
                                .aspectRatio(4/3, contentMode: .fit)
                                .overlay {
                                    VStack(spacing: GoogleSpacing.sm) {
                                        Image(systemName: "photo")
                                            .font(.system(size: 48))
                                        Text("No preview available")
                                            .googleTypography(.bodyMedium, color: .googleTextSecondary)
                                    }
                                    .foregroundStyle(Color.googleTextTertiary)
                                }
                        }
                    }

                    // Action bar
                    ActionBar(
                        onShare: { shareImage() },
                        onCopy: {
                            copyToClipboard(record.url)
                            copiedField = .url
                        },
                        onOpen: { openInBrowser() },
                        onDelete: { showDeleteConfirmation = true },
                        isCopied: copiedField == .url,
                        isDeleting: isDeleting
                    )

                    // Details section
                    VStack(spacing: 0) {
                        DetailSection(title: "Image URL") {
                            CopyableRow(
                                text: record.url,
                                isCopied: copiedField == .url,
                                onCopy: {
                                    copyToClipboard(record.url)
                                    copiedField = .url
                                }
                            )
                        }

                        Divider().background(Color.googleOutline)

                        DetailSection(title: "Delete URL") {
                            CopyableRow(
                                text: record.deleteUrl,
                                isCopied: copiedField == .deleteUrl,
                                onCopy: {
                                    copyToClipboard(record.deleteUrl)
                                    copiedField = .deleteUrl
                                }
                            )
                        }

                        Divider().background(Color.googleOutline)

                        DetailSection(title: "Details") {
                            VStack(spacing: 0) {
                                InfoRow(label: "Uploaded", value: dateFormatter.string(from: record.createdAt))

                                if let filename = record.originalFilename {
                                    Divider().background(Color.googleOutline.opacity(0.5))
                                    InfoRow(label: "Original File", value: filename)
                                }

                                Divider().background(Color.googleOutline.opacity(0.5))
                                InfoRow(label: "ID", value: record.id)
                            }
                        }
                    }
                    .background(Color.googleSurface)
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .confirmationDialog(
            "Delete Image",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete from Server", role: .destructive) {
                deleteFromServer()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete the image from the server. This action cannot be undone.")
        }
        .onChange(of: copiedField) { _, newValue in
            if newValue != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    copiedField = nil
                }
            }
        }
    }

    private func copyToClipboard(_ text: String) {
        UIPasteboard.general.string = text
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    private func shareImage() {
        guard let url = URL(string: record.url) else { return }
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }

    private func openInBrowser() {
        guard let url = URL(string: record.url) else { return }
        UIApplication.shared.open(url)
    }

    private func deleteFromServer() {
        isDeleting = true

        Task {
            do {
                try await UploadService.shared.delete(record: record)
                try HistoryService.shared.delete(id: record.id)
                await MainActor.run {
                    onDelete()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isDeleting = false
                }
            }
        }
    }
}

// MARK: - Action Bar

struct ActionBar: View {
    let onShare: () -> Void
    let onCopy: () -> Void
    let onOpen: () -> Void
    let onDelete: () -> Void
    let isCopied: Bool
    let isDeleting: Bool

    var body: some View {
        HStack(spacing: 0) {
            ActionButton(icon: "square.and.arrow.up", label: "Share", action: onShare)
            ActionButton(
                icon: isCopied ? "checkmark" : "doc.on.doc",
                label: isCopied ? "Copied" : "Copy",
                iconColor: isCopied ? .googleGreen : .white,
                action: onCopy
            )
            ActionButton(icon: "safari", label: "Open", action: onOpen)
            ActionButton(
                icon: isDeleting ? "ellipsis" : "trash",
                label: "Delete",
                iconColor: .googleRed,
                action: onDelete
            )
            .disabled(isDeleting)
        }
        .padding(.vertical, GoogleSpacing.sm)
        .background(Color.black)
    }
}

// MARK: - Action Button

struct ActionButton: View {
    let icon: String
    let label: String
    var iconColor: Color = .white
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: GoogleSpacing.xxxs) {
                Image(systemName: icon)
                    .font(.system(size: GoogleIconSize.md))
                    .foregroundStyle(iconColor)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Detail Section

struct DetailSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: GoogleSpacing.xxs) {
            Text(title)
                .googleTypography(.labelMedium, color: .googleTextSecondary)
                .padding(.horizontal, GoogleSpacing.sm)
                .padding(.top, GoogleSpacing.sm)

            content
                .padding(.horizontal, GoogleSpacing.sm)
                .padding(.bottom, GoogleSpacing.sm)
        }
    }
}

// MARK: - Copyable Row

struct CopyableRow: View {
    let text: String
    let isCopied: Bool
    let onCopy: () -> Void

    var body: some View {
        HStack {
            Text(text)
                .googleTypography(.bodySmall, color: .googleTextPrimary)
                .lineLimit(2)
                .font(.system(.caption, design: .monospaced))

            Spacer()

            Button(action: onCopy) {
                Image(systemName: isCopied ? "checkmark.circle.fill" : "doc.on.doc")
                    .font(.system(size: GoogleIconSize.sm))
                    .foregroundStyle(isCopied ? Color.googleGreen : Color.googleBlue)
            }
        }
        .padding(GoogleSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: GoogleCornerRadius.sm)
                .fill(Color.googleSurfaceSecondary)
        )
    }
}

// MARK: - Info Row

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .googleTypography(.bodyMedium, color: .googleTextSecondary)
            Spacer()
            Text(value)
                .googleTypography(.bodyMedium)
                .lineLimit(1)
        }
        .padding(.horizontal, GoogleSpacing.sm)
        .padding(.vertical, GoogleSpacing.xs)
    }
}

#Preview {
    NavigationStack {
        UploadDetailView(record: .preview) {}
    }
}
