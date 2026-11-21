import CoreGraphics
import Foundation
import PDFKit

struct PDFStaffSystemGeometry {
    let staffFrame: CGRect
    let barlineXs: [CGFloat]
}

/// Reads staff and barline geometry from rendered PDF rules. Coordinates
/// returned to text extraction use the PDF crop box's bottom-up space.
enum PDFStaffBarlineDetector {
    private struct StaffLine {
        var firstRow: Int
        var lastRow: Int
        var startX: Int
        var endX: Int
        var parallelRun: Range<Int>? = nil
        var hasConflictingParallelRuns = false

        var centerY: CGFloat { CGFloat(firstRow + lastRow) / 2 }
        var width: Int { endX - startX }
    }

    private struct Raster {
        let bounds: CGRect
        let scale: CGFloat
        let width: Int
        let height: Int
        let pixels: [UInt8]

        func isDark(x: Int, y: Int) -> Bool {
            pixels[y * width + x] < 150
        }

        func pdfX(_ x: CGFloat) -> CGFloat { bounds.minX + x / scale }
        func pdfY(_ y: CGFloat) -> CGFloat { bounds.maxY - y / scale }
    }

    enum DetectionError: LocalizedError {
        case unableToRender
        case unsupportedLayout

        var errorDescription: String? {
            switch self {
            case .unableToRender:
                "The staff lines could not be read from this PDF page."
            case .unsupportedLayout:
                "This PDF page has a short or side-by-side staff that cannot be converted completely."
            }
        }
    }

    static func detect(in page: PDFPage) throws -> [PDFStaffSystemGeometry] {
        let raster = try render(page)
        let candidates = try staffLines(in: raster)
        // Keep the original admission threshold. Shorter rules are retained
        // only to detect an unsupported staff instead of returning a partial draft.
        let minimumLength = Int(CGFloat(raster.width) * 0.35)
        let lines = candidates.filter { $0.width >= minimumLength }
        var systems: [PDFStaffSystemGeometry] = []
        var index = 0
        while index + 4 < lines.count {
            try Task.checkCancellation()
            let group = Array(lines[index..<(index + 5)])
            guard let spacing = staffSpacing(for: group, raster: raster) else {
                index += 1
                continue
            }
            let left = group.map(\.startX).max()!
            let right = group.map(\.endX).min()!
            let top = group.first!.centerY
            let bottom = group.last!.centerY
            let boundaries = barlinePositions(in: raster, lines: group,
                left: left, right: right, spacing: spacing)
            // A crop can cut through the middle of a measure. Do not turn
            // that clipped staff edge into an invented outside divider.
            let edgeTolerance = max(1, raster.scale)
            if (left <= 1 && !boundaries.contains(where: { abs($0 - CGFloat(left)) <= edgeTolerance }))
                || (right >= raster.width - 1
                    && !boundaries.contains(where: { abs($0 - CGFloat(right)) <= edgeTolerance })) {
                throw DetectionError.unableToRender
            }
            // A five-line group alone is insufficient. Require an interior
            // divider or a closing rule to establish a measurable system.
            if !boundaries.isEmpty {
                var xs = mergedBoundaries([CGFloat(left)] + boundaries + [CGFloat(right)],
                    tolerance: spacing * 0.85)
                if xs.count >= 2 {
                    xs[0] = CGFloat(left)
                    xs[xs.count - 1] = CGFloat(right)
                    systems.append(PDFStaffSystemGeometry(
                        staffFrame: CGRect(x: raster.pdfX(CGFloat(left)), y: raster.pdfY(bottom),
                            width: CGFloat(right - left) / raster.scale,
                            height: (bottom - top) / raster.scale),
                        barlineXs: xs.map(raster.pdfX)))
                }
            }
            index += 5
        }
        try rejectUnsupportedStaffGroups(candidates, coveredBy: systems, raster: raster)
        return systems
    }

    private static func render(_ page: PDFPage) throws -> Raster {
        let bounds = page.bounds(for: .cropBox)
        guard bounds.minX.isFinite, bounds.minY.isFinite,
              bounds.width.isFinite, bounds.height.isFinite,
              bounds.width > 0, bounds.height > 0,
              page.rotation.isMultiple(of: 360),
              let pageRef = page.pageRef else { throw DetectionError.unableToRender }
        let scale = min(2, 2_200 / max(bounds.width, bounds.height))
        guard scale >= 0.5 else { throw DetectionError.unableToRender }
        let width = Int(ceil(bounds.width * scale))
        let height = Int(ceil(bounds.height * scale))
        var pixels = [UInt8](repeating: 255, count: width * height)
        let rendered = pixels.withUnsafeMutableBytes { storage -> Bool in
            guard let context = CGContext(data: storage.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -bounds.minX, y: -bounds.minY)
            // Draw in original PDF coordinates. PDFPage.draw applies its own
            // crop-origin transform, which would shift a nonzero crop twice.
            context.drawPDFPage(pageRef)
            return true
        }
        guard rendered else { throw DetectionError.unableToRender }
        return Raster(bounds: bounds, scale: scale, width: width, height: height, pixels: pixels)
    }

    private static func staffLines(in raster: Raster) throws -> [StaffLine] {
        let minimumLength = min(Int(CGFloat(raster.width) * 0.35), Int(64 * raster.scale))
        var lines: [StaffLine] = []
        for y in 0..<raster.height {
            if y.isMultiple(of: 128) { try Task.checkCancellation() }
            var start = 0
            var runs: [Range<Int>] = []
            for x in 0...raster.width {
                if x < raster.width, raster.isDark(x: x, y: y) { continue }
                if x - start >= minimumLength { runs.append(start..<x) }
                start = x + 1
            }
            runs.sort {
                $0.count == $1.count ? $0.lowerBound < $1.lowerBound : $0.count > $1.count
            }
            guard let longest = runs.first else { continue }
            let parallel = runs.dropFirst().first
            if let last = lines.last, y == last.lastRow + 1,
               abs(longest.lowerBound - last.startX) <= 2,
               abs(longest.upperBound - last.endX) <= 2 {
                lines[lines.count - 1].lastRow = y
                if let parallel, !last.hasConflictingParallelRuns {
                    if let previous = last.parallelRun {
                        if abs(previous.lowerBound - parallel.lowerBound) <= 2,
                           abs(previous.upperBound - parallel.upperBound) <= 2 {
                            let lower = min(previous.lowerBound, parallel.lowerBound)
                            let upper = max(previous.upperBound, parallel.upperBound)
                            lines[lines.count - 1].parallelRun = lower..<upper
                        } else {
                            lines[lines.count - 1].parallelRun = nil
                            lines[lines.count - 1].hasConflictingParallelRuns = true
                        }
                    } else {
                        // The other column can use a thinner rule. Keep its
                        // coherent extent even if it occupies fewer raster rows.
                        lines[lines.count - 1].parallelRun = parallel
                    }
                }
            } else {
                lines.append(StaffLine(firstRow: y, lastRow: y,
                    startX: longest.lowerBound, endX: longest.upperBound, parallelRun: parallel))
            }
        }
        return lines
    }

    private static func rejectUnsupportedStaffGroups(
        _ lines: [StaffLine], coveredBy systems: [PDFStaffSystemGeometry], raster: Raster
    ) throws {
        // Guard-only evidence includes the other column's rules, even when it
        // starts at a different height. It never adds a measure to the draft.
        let evidence = lines.flatMap { line -> [StaffLine] in
            guard let run = line.parallelRun else { return [line] }
            return [line, StaffLine(firstRow: line.firstRow, lastRow: line.lastRow,
                startX: run.lowerBound, endX: run.upperBound)]
        }.sorted { $0.firstRow < $1.firstRow }
        var columns: [[StaffLine]] = []
        for line in evidence {
            try Task.checkCancellation()
            if let column = columns.firstIndex(where: { column in
                let reference = column[0]
                let shared = min(reference.endX, line.endX) - max(reference.startX, line.startX)
                return CGFloat(shared) >= CGFloat(max(reference.width, line.width)) * 0.85
            }) {
                if let last = columns[column].last, line.firstRow <= last.lastRow + 1,
                   abs(last.startX - line.startX) <= 2, abs(last.endX - line.endX) <= 2 {
                    columns[column][columns[column].count - 1].lastRow = max(last.lastRow, line.lastRow)
                } else {
                    columns[column].append(line)
                }
            } else {
                columns.append([line])
            }
        }
        for column in columns {
            var index = 0
            while index + 4 < column.count {
                try Task.checkCancellation()
                let group = Array(column[index..<(index + 5)])
                guard let spacing = staffSpacing(for: group, raster: raster) else {
                    index += 1
                    continue
                }
                let left = group.map(\.startX).max()!
                let right = group.map(\.endX).min()!
                let top = group.first!.centerY
                let bottom = group.last!.centerY
                let frame = CGRect(x: raster.pdfX(CGFloat(left)), y: raster.pdfY(bottom),
                    width: CGFloat(right - left) / raster.scale, height: (bottom - top) / raster.scale)
                let tolerance = max(1, spacing / raster.scale * 0.15)
                guard systems.contains(where: {
                    $0.staffFrame.insetBy(dx: -tolerance, dy: -tolerance).contains(frame)
                }) else { throw DetectionError.unsupportedLayout }
                index += 5
            }
        }
    }

    private static func staffSpacing(for lines: [StaffLine], raster: Raster) -> CGFloat? {
        let gaps = zip(lines, lines.dropFirst()).map { $1.centerY - $0.centerY }
        let spacing = gaps.reduce(0, +) / CGFloat(gaps.count)
        guard (2 * raster.scale...15 * raster.scale).contains(spacing),
              gaps.allSatisfy({ abs($0 - spacing) <= max(1, spacing * 0.12) }),
              lines.allSatisfy({ CGFloat($0.lastRow - $0.firstRow + 1) <= spacing * 0.35 }),
              let minimumWidth = lines.map(\.width).min(),
              let maximumWidth = lines.map(\.width).max(),
              CGFloat(minimumWidth) >= CGFloat(maximumWidth) * 0.85 else { return nil }
        let sharedWidth = lines.map(\.endX).min()! - lines.map(\.startX).max()!
        return CGFloat(sharedWidth) >= CGFloat(maximumWidth) * 0.85 ? spacing : nil
    }

    private static func barlinePositions(
        in raster: Raster, lines: [StaffLine], left: Int, right: Int, spacing: CGFloat
    ) -> [CGFloat] {
        let top = Int(ceil(lines.first!.centerY))
        let bottom = Int(floor(lines.last!.centerY))
        let height = bottom - top + 1
        var columns: [[Int]] = []
        for x in left..<right {
            let darkCount = (top...bottom).reduce(0) { $0 + (raster.isDark(x: x, y: $1) ? 1 : 0) }
            guard CGFloat(darkCount) >= CGFloat(height) * 0.90 else { continue }
            if let last = columns.last?.last, x <= last + 1 {
                columns[columns.count - 1].append(x)
            } else {
                columns.append([x])
            }
        }
        return columns.compactMap { columns in
            guard let first = columns.first, let last = columns.last,
                  CGFloat(last - first + 1) <= spacing * 0.60 else { return nil }
            let x = (first + last) / 2
            let outside = max(2, Int(spacing * 0.50))
            let upperRow = max(0, top - outside)
            let lowerRow = min(raster.height - 1, bottom + outside)
            // Stems and clef spines usually continue outside the staff;
            // a barline has its vertical endpoints at the outer staff lines.
            guard !raster.isDark(x: x, y: upperRow),
                  !raster.isDark(x: x, y: lowerRow),
                  !hasGlyphBody(around: columns, raster: raster, lines: lines, spacing: spacing)
            else { return nil }
            return CGFloat(first + last + 1) / 2
        }
    }

    private static func hasGlyphBody(
        around columns: [Int], raster: Raster, lines: [StaffLine], spacing: CGFloat
    ) -> Bool {
        let first = columns.first!
        let last = columns.last!
        let reach = max(4, Int(spacing * 0.8))
        let leftRange = max(0, first - reach)..<max(0, first - 1)
        let rightRange = min(raster.width, last + 2)..<min(raster.width, last + reach + 1)
        let bodyWidth = max(4, Int(spacing * 0.35))
        var examinedRows = 0
        var wideRows = 0
        for y in Int(ceil(lines.first!.centerY))...Int(floor(lines.last!.centerY)) {
            guard !lines.contains(where: { y >= $0.firstRow - 1 && y <= $0.lastRow + 1 }) else { continue }
            examinedRows += 1
            let darkSides = (leftRange.filter { raster.isDark(x: $0, y: y) }.count
                + rightRange.filter { raster.isDark(x: $0, y: y) }.count)
            if darkSides >= bodyWidth { wideRows += 1 }
        }
        return examinedRows > 0 && CGFloat(wideRows) > CGFloat(examinedRows) * 0.45
    }

    private static func mergedBoundaries(_ xs: [CGFloat], tolerance: CGFloat) -> [CGFloat] {
        var groups: [[CGFloat]] = []
        for x in xs.sorted() {
            if let previous = groups.last?.last, x - previous <= tolerance {
                groups[groups.count - 1].append(x)
            } else {
                groups.append([x])
            }
        }
        return groups.map { values in values.reduce(0, +) / CGFloat(values.count) }
    }
}
