import SwiftUI

struct PhotoGridView: View {
    let records: [UploadRecord]
    let onSelect: (UploadRecord) -> Void
    let onDelete: (UploadRecord) -> Void

    @State private var selectedIds: Set<String> = []
    @State private var isSelectionMode = false
    @State private var targetRowHeight: CGFloat = 220
    @State private var showDeleteConfirmation = false

    @GestureState private var magnification: CGFloat = 1.0

    private var groupedRecords: [(String, [UploadRecord])] {
        let grouped = Dictionary(grouping: records) { record in
            dateGroupKey(for: record.createdAt)
        }
        return grouped.sorted { $0.key > $1.key }
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(groupedRecords, id: \.0) { dateKey, sectionRecords in
                        Section {
                            JustifiedPhotoGrid(
                                records: sectionRecords,
                                containerWidth: geometry.size.width,
                                targetRowHeight: targetRowHeight,
                                spacing: 2,
                                selectedIds: selectedIds,
                                isSelectionMode: isSelectionMode,
                                onTap: { record in
                                    handleTap(record)
                                },
                                onLongPress: { record in
                                    handleLongPress(record)
                                }
                            )
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
                        updateRowHeight(with: value)
                    }
            )
        }
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

    private func updateRowHeight(with scale: CGFloat) {
        // Pinch in = smaller scale = smaller photos (lower row height)
        // Pinch out = larger scale = larger photos (higher row height)
        let newHeight = targetRowHeight * scale
        targetRowHeight = min(max(newHeight, 80), 300)
    }
}

// MARK: - Justified Photo Grid (Google Photos-like layout)

struct JustifiedPhotoGrid: View {
    let records: [UploadRecord]
    let containerWidth: CGFloat
    let targetRowHeight: CGFloat
    let spacing: CGFloat
    let selectedIds: Set<String>
    let isSelectionMode: Bool
    let onTap: (UploadRecord) -> Void
    let onLongPress: (UploadRecord) -> Void

    private struct LayoutRow {
        let records: [UploadRecord]
        let aspectRatios: [CGFloat]
        let height: CGFloat
    }

    private var rows: [LayoutRow] {
        calculateRows()
    }

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: spacing) {
                    ForEach(Array(zip(row.records, row.aspectRatios)), id: \.0.id) { record, aspectRatio in
                        JustifiedPhotoItem(
                            record: record,
                            width: row.height * aspectRatio,
                            height: row.height,
                            isSelected: selectedIds.contains(record.id),
                            isSelectionMode: isSelectionMode,
                            onTap: { onTap(record) },
                            onLongPress: { onLongPress(record) }
                        )
                    }
                }
            }
        }
    }

    private func calculateRows() -> [LayoutRow] {
        guard !records.isEmpty else { return [] }

        var result: [LayoutRow] = []
        var currentRowRecords: [UploadRecord] = []
        var currentRowAspectRatios: [CGFloat] = []
        var currentRowTotalAspect: CGFloat = 0

        for record in records {
            let aspectRatio = getAspectRatio(for: record)
            currentRowRecords.append(record)
            currentRowAspectRatios.append(aspectRatio)
            currentRowTotalAspect += aspectRatio

            // Calculate what row height would be if we finalized this row
            let totalSpacing = spacing * CGFloat(currentRowRecords.count - 1)
            let availableWidth = containerWidth - totalSpacing
            let rowHeight = availableWidth / currentRowTotalAspect

            // If row height is at or below target, finalize this row
            if rowHeight <= targetRowHeight {
                result.append(LayoutRow(
                    records: currentRowRecords,
                    aspectRatios: currentRowAspectRatios,
                    height: rowHeight
                ))
                currentRowRecords = []
                currentRowAspectRatios = []
                currentRowTotalAspect = 0
            }
        }

        // Handle remaining items in the last row
        if !currentRowRecords.isEmpty {
            let totalSpacing = spacing * CGFloat(currentRowRecords.count - 1)
            let availableWidth = containerWidth - totalSpacing
            let naturalHeight = availableWidth / currentRowTotalAspect
            // Cap the last row height at target to avoid huge single images
            let rowHeight = min(naturalHeight, targetRowHeight)

            result.append(LayoutRow(
                records: currentRowRecords,
                aspectRatios: currentRowAspectRatios,
                height: rowHeight
            ))
        }

        return result
    }

    private func getAspectRatio(for record: UploadRecord) -> CGFloat {
        if let thumbnailData = record.thumbnailData,
           let uiImage = UIImage(data: thumbnailData) {
            let size = uiImage.size
            if size.height > 0 {
                return size.width / size.height
            }
        }
        // Default to square if no thumbnail
        return 1.0
    }
}

// MARK: - Justified Photo Item

struct JustifiedPhotoItem: View {
    let record: UploadRecord
    let width: CGFloat
    let height: CGFloat
    let isSelected: Bool
    let isSelectionMode: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Thumbnail
            if let thumbnailData = record.thumbnailData,
               let uiImage = UIImage(data: thumbnailData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color.brutalSurface)
                    .frame(width: width, height: height)
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
        .frame(width: width, height: height)
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
