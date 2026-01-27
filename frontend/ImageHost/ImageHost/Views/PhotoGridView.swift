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
        Array(repeating: GridItem(.flexible(), spacing: 2), count: gridColumns)
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
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(sectionRecords) { record in
                                BrutalPhotoGridItem(
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
                    } header: {
                        BrutalDateSectionHeader(dateKey: dateKey)
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
                    Button {
                        exitSelectionMode()
                    } label: {
                        Text("CANCEL")
                            .brutalTypography(.monoSmall)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isSelectionMode && !selectedIds.isEmpty {
                BrutalSelectionActionBar(
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

// MARK: - Brutal Photo Grid Item

struct BrutalPhotoGridItem: View {
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
                        .fill(Color.brutalSurface)
                        .overlay {
                            Text("□")
                                .brutalTypography(.titleLarge, color: .brutalTextTertiary)
                        }
                }

                // Selection overlay
                if isSelectionMode {
                    Color.black.opacity(isSelected ? 0.4 : 0)

                    // Selection indicator
                    ZStack {
                        if isSelected {
                            Rectangle()
                                .fill(Color.white)
                                .frame(width: 24, height: 24)

                            Text("✓")
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundStyle(.black)
                        } else {
                            Rectangle()
                                .stroke(Color.white, lineWidth: 2)
                                .frame(width: 24, height: 24)
                                .background(Color.black.opacity(0.3))
                        }
                    }
                    .padding(8)
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

// MARK: - Brutal Date Section Header

struct BrutalDateSectionHeader: View {
    let dateKey: String

    var body: some View {
        HStack {
            Text(dateKey.uppercased())
                .brutalTypography(.monoSmall, color: .brutalTextSecondary)
                .tracking(2)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.brutalBackground.opacity(0.95))
    }
}

// MARK: - Brutal Selection Action Bar

struct BrutalSelectionActionBar: View {
    let selectedCount: Int
    let onDelete: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 24) {
            Text("\(selectedCount) SELECTED")
                .brutalTypography(.mono)
                .tracking(1)

            Spacer()

            Button(action: onDelete) {
                Text("DELETE")
                    .brutalTypography(.mono, color: .brutalError)
                    .tracking(1)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(Color.brutalSurface)
        .overlay(
            Rectangle()
                .stroke(Color.brutalBorder, lineWidth: 1)
                .padding(.bottom, -1)
            , alignment: .top
        )
    }
}
