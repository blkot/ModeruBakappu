//
//  CatalogModelDetail.swift
//  ModeruBakappu
//

import SwiftUI

struct CatalogModelDetail: View {
    let item: HFModelCatalogItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerCard
                statsCard
                tagsSection
                Spacer(minLength: 20)
            }
            .padding(20)
        }
    }

    // MARK: - Header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.modelName)
                .font(.title2.weight(.bold))
            HStack(spacing: 8) {
                Text(item.author)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                if let libraryName = item.libraryName {
                    Text(libraryName)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
                if let pipelineTag = item.pipelineTag {
                    PipelineBadge(tag: pipelineTag)
                }
            }
            Text(item.id)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.accentColor.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.12))
        )
    }

    // MARK: - Stats

    private var statsCard: some View {
        HStack(spacing: 0) {
            StatCell(
                icon: "arrow.down.circle.fill",
                value: item.formattedDownloads,
                label: "Downloads",
                color: .blue
            )
            Divider().frame(height: 40)
            StatCell(
                icon: "heart.circle.fill",
                value: item.formattedLikes,
                label: "Likes",
                color: .pink
            )
            Divider().frame(height: 40)
            StatCell(
                icon: "clock",
                value: item.lastModified.formatted(date: .abbreviated, time: .omitted),
                label: "Updated",
                color: .secondary
            )
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    // MARK: - Tags

    @ViewBuilder
    private var tagsSection: some View {
        if !item.tags.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Tags")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                    ForEach(item.tags, id: \.self) { tag in
                        TagCapsule(tag: tag)
                    }
                }
            }
        }
    }

}

// MARK: - Stat Cell

private struct StatCell: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.subheadline.weight(.semibold))
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
    }
}

// MARK: - Pipeline Badge

private struct PipelineBadge: View {
    let tag: String

    var body: some View {
        Text(tag.replacingOccurrences(of: "-", with: " ").capitalized)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }

    var color: Color {
        switch tag {
        case "text-generation": return .blue
        case "image-generation", "text-to-image": return .purple
        case "automatic-speech-recognition": return .orange
        case "feature-extraction", "sentence-similarity": return .green
        case "image-classification", "object-detection": return .teal
        default: return .secondary
        }
    }
}

// MARK: - Tag Capsule

private struct TagCapsule: View {
    let tag: String

    var body: some View {
        Text(tag)
            .font(.caption2)
            .foregroundStyle(highlighted ? .white : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                highlighted
                    ? highlightColor
                    : Color.secondary.opacity(0.1)
            )
            .clipShape(Capsule())
    }

    private var highlighted: Bool {
        ["gguf", "mlx", "safetensors", "pytorch", "transformers", "onnx"].contains(tag)
    }

    private var highlightColor: Color {
        switch tag {
        case "gguf": return .blue
        case "mlx": return .orange
        case "safetensors": return .green
        case "pytorch": return .red
        case "transformers": return .purple
        case "onnx": return .teal
        default: return .secondary
        }
    }
}

// MARK: - Flow Layout

private struct FlowLayout: Layout {
    var horizontalSpacing: CGFloat = 6
    var verticalSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal: proposal, subviews: subviews)
        guard let lastRow = rows.last else { return .zero }
        return CGSize(
            width: proposal.width ?? rows.map(\.width).max() ?? 0,
            height: lastRow.maxY + verticalSpacing
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(proposal: proposal, subviews: subviews)
        for row in rows {
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: bounds.minX + item.x, y: bounds.minY + row.y),
                    proposal: ProposedViewSize(item.size)
                )
            }
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [Row] = []
        var currentRow = Row()

        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let itemWidth = size.width + horizontalSpacing
            if !currentRow.items.isEmpty, currentRow.width + itemWidth > maxWidth {
                rows.append(currentRow)
                currentRow = Row()
            }
            let x = currentRow.items.isEmpty ? 0 : currentRow.width
            currentRow.items.append(RowItem(index: index, size: size, x: x))
            currentRow.width = x + itemWidth
            currentRow.height = max(currentRow.height, size.height)
        }

        if !currentRow.items.isEmpty {
            rows.append(currentRow)
        }

        var y: CGFloat = 0
        for i in rows.indices {
            rows[i].y = y
            y += rows[i].height + verticalSpacing
        }

        return rows
    }

    private struct Row {
        var items: [RowItem] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
        var y: CGFloat = 0
        var maxY: CGFloat { y + height }
    }

    private struct RowItem {
        let index: Int
        let size: CGSize
        let x: CGFloat
    }
}
