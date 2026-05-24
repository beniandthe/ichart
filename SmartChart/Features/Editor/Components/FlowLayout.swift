import SwiftUI

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 8

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) -> CGSize {
        layout(in: proposal.replacingUnspecifiedDimensions().width, subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        let rows = layout(in: bounds.width, subviews: subviews).rows
        var y = bounds.minY

        for row in rows {
            var x = bounds.minX
            for item in row.items {
                item.subview.place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + spacing
            }
            y += row.height + rowSpacing
        }
    }

    private func layout(in availableWidth: CGFloat, subviews: Subviews) -> FlowLayoutResult {
        let safeWidth = max(1, availableWidth)
        var rows: [FlowRow] = []
        var currentItems: [FlowItem] = []
        var currentWidth: CGFloat = 0
        var currentHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let proposedWidth = currentItems.isEmpty ? size.width : currentWidth + spacing + size.width

            if proposedWidth > safeWidth, !currentItems.isEmpty {
                rows.append(FlowRow(items: currentItems, height: currentHeight, width: currentWidth))
                currentItems = [FlowItem(subview: subview, size: size)]
                currentWidth = size.width
                currentHeight = size.height
            } else {
                currentItems.append(FlowItem(subview: subview, size: size))
                currentWidth = proposedWidth
                currentHeight = max(currentHeight, size.height)
            }
        }

        if !currentItems.isEmpty {
            rows.append(FlowRow(items: currentItems, height: currentHeight, width: currentWidth))
        }

        let height = rows.reduce(CGFloat.zero) { partialResult, row in
            partialResult + row.height
        } + max(0, CGFloat(rows.count - 1)) * rowSpacing
        let width = rows.reduce(CGFloat.zero) { partialResult, row in
            max(partialResult, row.width)
        }

        return FlowLayoutResult(size: CGSize(width: width, height: height), rows: rows)
    }
}

private struct FlowLayoutResult {
    let size: CGSize
    let rows: [FlowRow]
}

private struct FlowRow {
    let items: [FlowItem]
    let height: CGFloat
    let width: CGFloat
}

private struct FlowItem {
    let subview: LayoutSubview
    let size: CGSize
}
