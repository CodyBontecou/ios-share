import SwiftUI

struct PhotoGridView: View {
    let records: [UploadRecord]
    let onSelect: (UploadRecord) -> Void
    let onDelete: (UploadRecord) -> Void

    @State private var selectedIds: Set<String> = []
    @State private var isSelectionMode = false
    @State private var gridColumns = 3
    @State private var showDeleteConfirmation = false

    @GestureState private var magnification: CGFloat = 1.0

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: GoogleGridSpacing.itemSpacing), count: gridColumns)
    }

    private var groupedRecords: [(String, [UploadRecord])] {
        let grouped = Dictionary(grouping: records) { record in
            dateGroupKey(for: record.createdAt)
        }
        return grouped.sorted { $0.key > $1.key }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(groupedRecords, id: \.0) { dateKey, sectionRecords in
                    Section {
                        LazyVGrid(columns: columns, spacing: GoogleGridSpacing.itemSpacing) {
                            ForEach(sectionRecords) { record in
                                PhotoGridItem(
                                    record: record,
                                    isSelected: selectedIds.contains(record.id),
                                    isSelectionMode: isSelectionMode,
                                    onTap: {
                                        handleTap(record)
                                    },
                                    onLongPress: {
                                        handleLongPress(record)
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, GoogleGridSpacing.gridInsets)
                    } header: {
                        DateSectionHeader(dateKey: dateKey)
                    }
                }
            }
        }
        .gesture(
            MagnificationGesture()
                .updating($magnification) { value, state, _ in
                    state = value
                }
                .onEnded { value in
                    updateGridColumns(with: value)
                }
        )
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if isSelectionMode {
                    Button("Cancel") {
                        exitSelectionMode()
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isSelectionMode && !selectedIds.isEmpty {
                SelectionActionBar(
                    selectedCount: selectedIds.count,
                    onDelete: { showDeleteConfirmation = true },
                    onCancel: { exitSelectionMode() }
                )
            }
        }
        .confirmationDialog(
            "Delete \(selectedIds.count) image\(selectedIds.count == 1 ? "" : "s")?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteSelected()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete the selected images from the server.")
        }
    }

    private func dateGroupKey(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMMM d, yyyy"
            return formatter.string(from: date)
        }
    }

    private func handleTap(_ record: UploadRecord) {
        if isSelectionMode {
            toggleSelection(record)
        } else {
            onSelect(record)
        }
    }

    private func handleLongPress(_ record: UploadRecord) {
        if !isSelectionMode {
            isSelectionMode = true
            selectedIds.insert(record.id)
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        }
    }

    private func toggleSelection(_ record: UploadRecord) {
        if selectedIds.contains(record.id) {
            selectedIds.remove(record.id)
            if selectedIds.isEmpty {
                isSelectionMode = false
            }
        } else {
            selectedIds.insert(record.id)
        }
    }

    private func exitSelectionMode() {
        isSelectionMode = false
        selectedIds.removeAll()
    }

    private func deleteSelected() {
        for id in selectedIds {
            if let record = records.first(where: { $0.id == id }) {
                onDelete(record)
            }
        }
        exitSelectionMode()
    }

    private func updateGridColumns(with scale: CGFloat) {
        if scale < 0.8 && gridColumns < 5 {
            gridColumns += 1
        } else if scale > 1.2 && gridColumns > 2 {
            gridColumns -= 1
        }
    }
}

// MARK: - Photo Grid Item

struct PhotoGridItem: View {
    let record: UploadRecord
    let isSelected: Bool
    let isSelectionMode: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                // Thumbnail
                if let thumbnailData = record.thumbnailData,
                   let uiImage = UIImage(data: thumbnailData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.width)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(Color.googleSurfaceSecondary)
                        .overlay {
                            Image(systemName: "photo")
                                .font(.system(size: 24))
                                .foregroundStyle(Color.googleTextTertiary)
                        }
                }

                // Selection overlay
                if isSelectionMode {
                    Color.black.opacity(isSelected ? 0.3 : 0)

                    SelectionCheckmark(isSelected: isSelected)
                        .padding(GoogleSpacing.xxs)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.width)
        }
        .aspectRatio(1, contentMode: .fit)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            onLongPress()
        }
    }
}

// MARK: - Date Section Header

struct DateSectionHeader: View {
    let dateKey: String

    var body: some View {
        HStack {
            Text(dateKey)
                .googleTypography(.titleSmall)
            Spacer()
        }
        .padding(.horizontal, GoogleSpacing.sm)
        .padding(.vertical, GoogleSpacing.xs)
        .background(Color.googleSurface.opacity(0.95))
    }
}

// MARK: - Selection Action Bar

struct SelectionActionBar: View {
    let selectedCount: Int
    let onDelete: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: GoogleSpacing.lg) {
            Text("\(selectedCount) selected")
                .googleTypography(.labelLarge)

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: GoogleIconSize.md))
                    .foregroundStyle(Color.googleRed)
            }
        }
        .padding(.horizontal, GoogleSpacing.lg)
        .padding(.vertical, GoogleSpacing.sm)
        .background(
            Rectangle()
                .fill(Color.googleSurfaceSecondary)
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: -4)
        )
    }
}
