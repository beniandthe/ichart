import CoreGraphics
import CryptoKit
import Foundation
#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import UIKit

private final class PaperMeasureInkDrawing {
    let drawing: PKDrawing

    init(_ drawing: PKDrawing) { self.drawing = drawing }
}

private enum PaperMeasureInkOwnership {
    static let cache: NSCache<NSData, PaperMeasureInkDrawing> = {
        let cache = NSCache<NSData, PaperMeasureInkDrawing>()
        cache.countLimit = 8
        cache.totalCostLimit = 16 * 1_024 * 1_024
        return cache
    }()

    static func drawing(in data: Data) -> PKDrawing? {
        let key = data as NSData
        if let cached = cache.object(forKey: key) { return cached.drawing }
        guard let drawing = try? PKDrawing(data: data) else { return nil }
        cache.setObject(PaperMeasureInkDrawing(drawing), forKey: key, cost: data.count)
        return drawing
    }
}
#endif

/// Horizontal intent within one writable system, independent of paper size.
struct PaperMeasureLayout: Codable, Hashable {
    var rowIndex: Int = 0
    var startFraction: Double
    var endFraction: Double
    var leadingBarline: BarlineType? = nil
    var needsSystemFit: Bool = false

    var widthFraction: Double { endFraction - startFraction }

    var isValid: Bool {
        rowIndex >= 0 && startFraction.isFinite && endFraction.isFinite
            && startFraction >= 0 && endFraction <= 1
            && widthFraction > 0
    }
}

/// A frozen row can be previewed without copying charts or decoding saved ink.
enum PaperMeasureMoveProposal {
    static func positions(
        moving measureID: UUID, toStartFraction start: Double,
        among positions: [UUID: PaperMeasureLayout]
    ) -> [UUID: PaperMeasureLayout]? {
        guard start.isFinite, let source = positions[measureID], source.isValid,
              positions.values.allSatisfy(\.isValid) else { return nil }
        let width = source.widthFraction
        let x = min(max(start, 0), max(0, 1 - width))
        let peers = positions.filter { $0.key != measureID }
        let collides = peers.values.contains {
            x < $0.endFraction - 0.0001 && x + width > $0.startFraction + 0.0001
        }
        var moved = source
        moved.startFraction = x
        moved.endFraction = x + width
        moved.needsSystemFit = false
        guard collides else {
            var result = positions
            result[measureID] = moved
            return result
        }
        var ordered = peers.sorted { $0.value.startFraction < $1.value.startFraction }
        let destination: Int
        if x <= 0.0001 {
            destination = 0
        } else if x + width >= 0.9999 {
            destination = ordered.count
        } else {
            destination = ordered.firstIndex {
                x < ($0.value.startFraction + $0.value.endFraction) / 2
            } ?? ordered.count
        }
        ordered.insert((key: measureID, value: moved), at: destination)
        let total = max(0.0001, ordered.reduce(0) { $0 + $1.value.widthFraction })
        var result: [UUID: PaperMeasureLayout] = [:]
        var nextStart = 0.0
        for (id, placement) in ordered {
            var fitted = placement
            fitted.startFraction = nextStart
            fitted.endFraction = min(1, nextStart + placement.widthFraction / total)
            fitted.needsSystemFit = false
            nextStart = fitted.endFraction
            result[id] = fitted
        }
        return result
    }
}

extension Chart {
    /// New paper charts retain real row targets so writing in a lower row
    /// never redirects the mark to an earlier row's open measure.
    @discardableResult
    mutating func initializePaperWritingRows(count: Int = 8) -> Bool {
        guard measures.allSatisfy({ !paperMeasureHasContent($0) }),
              cueTexts.isEmpty, roadmapObjects.isEmpty, sectionLabels.isEmpty,
              freeInkArticulations.isEmpty, pageHandwrittenChordData == nil,
              pageHandwrittenNotationData == nil else { return false }
        usesPaperMeasureLayout = true
        systems = (0..<max(1, count)).map { row in
            ChartSystem(id: row < systems.count ? systems[row].id : UUID(), index: row,
                spacingMode: .automatic, lineBreakRule: row == 0 ? .automatic : .forced,
                measures: [paperOpenMeasure(inRow: row, start: 0, end: 1)])
        }
        renumberPaperMeasures()
        updatedAt = .now
        return true
    }

    /// Capture existing displayed rows before the first free measure move.
    @discardableResult
    mutating func adoptPaperMeasureLayout(_ rows: [[UUID: ClosedRange<Double>]]) -> Bool {
        guard !rows.isEmpty else { return false }
        let source = Dictionary(uniqueKeysWithValues: measures.map { ($0.id, $0) })
        let supplied = rows.flatMap { $0.keys }
        guard supplied.count == source.count, Set(supplied).count == source.count,
              Set(supplied) == Set(source.keys),
              rows.allSatisfy({ !$0.isEmpty && $0.values.allSatisfy {
                  $0.lowerBound.isFinite && $0.upperBound.isFinite
                      && $0.lowerBound >= 0 && $0.upperBound <= 1
                      && $0.upperBound - $0.lowerBound >= 0.0001
              } }) else { return false }
        let previousSystems = systems
        usesPaperMeasureLayout = true
        var assignedSystemIDs = Set<UUID>()
        systems = rows.enumerated().map { rowIndex, positions in
            let ordered = positions.sorted { $0.value.lowerBound < $1.value.lowerBound }
            let rowMeasures = ordered.map { id, range in
                var measure = source[id]!
                measure.paperLayout = PaperMeasureLayout(rowIndex: rowIndex,
                    startFraction: range.lowerBound, endFraction: range.upperBound,
                    leadingBarline: measure.index == 1 ? .double : .single)
                return measure
            }
            let template = previousSystems.first { system in
                system.measures.contains { $0.id == rowMeasures.first?.id }
            }
            let systemID = template.flatMap { assignedSystemIDs.insert($0.id).inserted ? $0.id : nil } ?? UUID()
            return ChartSystem(id: systemID, index: rowIndex,
                spacingMode: template?.spacingMode ?? .automatic,
                lineBreakRule: rowIndex == 0 ? .automatic : .forced,
                startsNewPage: systemID == template?.id && template?.startsNewPage == true,
                measures: rowMeasures)
        }
        renumberPaperMeasures()
        updatedAt = .now
        return true
    }

    @discardableResult
    mutating func ensurePaperWritingRow(_ rowIndex: Int) -> UUID? {
        guard usesPaperMeasureLayout, rowIndex >= 0 else { return nil }
        while systems.count <= rowIndex + 1 {
            let index = systems.count
            systems.append(ChartSystem(id: UUID(), index: index, spacingMode: .automatic,
                lineBreakRule: .forced,
                measures: [paperOpenMeasure(inRow: index, start: 0, end: 1)]))
        }
        if systems[rowIndex].measures.isEmpty {
            systems[rowIndex].measures = [paperOpenMeasure(inRow: rowIndex, start: 0, end: 1)]
        }
        renumberPaperMeasures()
        return systems[rowIndex].measures.last(where: { $0.authoringState == .open })?.id
            ?? systems[rowIndex].measures.last?.id
    }

    func paperMeasureTarget(inRow rowIndex: Int, at fraction: Double) -> (measureID: UUID, fraction: Double)? {
        guard usesPaperMeasureLayout, systems.indices.contains(rowIndex), fraction.isFinite else { return nil }
        let x = min(max(fraction, 0), 1)
        let ordered = systems[rowIndex].measures.sorted {
            ($0.paperLayout?.startFraction ?? 0) < ($1.paperLayout?.startFraction ?? 0)
        }
        guard let measure = ordered.first(where: { measure in
            guard let placement = measure.paperLayout else { return false }
            return x >= placement.startFraction && (x < placement.endFraction
                || placement.endFraction == 1 && x == 1)
        }), let placement = measure.paperLayout else { return nil }
        return (measure.id, min(max((x - placement.startFraction) / placement.widthFraction, 0), 0.9999))
    }

    /// A writer can fill a previously empty gap after placing a floating bar.
    mutating func ensurePaperChordTarget(inRow rowIndex: Int, at fraction: Double) -> (measureID: UUID, fraction: Double)? {
        guard fraction.isFinite, (0...1).contains(fraction),
              ensurePaperWritingRow(rowIndex) != nil else { return nil }
        _ = repairEnclosedPaperMeasures()
        if let target = paperMeasureTarget(inRow: rowIndex, at: fraction) { return target }
        let placements = systems[rowIndex].measures.compactMap(\.paperLayout)
        let start = placements.filter { $0.endFraction <= fraction }.map(\.endFraction).max() ?? 0
        let end = placements.filter { $0.startFraction > fraction }.map(\.startFraction).min() ?? 1
        guard end - start >= 0.0001 else { return nil }
        let measure = paperOpenMeasure(inRow: rowIndex, start: start, end: end)
        systems[rowIndex].measures.append(measure)
        sortPaperRow(rowIndex)
        updatedAt = .now
        return paperMeasureTarget(inRow: rowIndex, at: fraction)
    }

    /// The first line on an empty row establishes its beginning. A later
    /// line closes the interval where the writer actually placed it.
    @discardableResult
    mutating func placePaperBarline(
        inRow rowIndex: Int, at fraction: Double, kind: BarlineType,
        normalizeSingleChords: Bool = true, allowsOpeningBoundary: Bool = true
    ) -> UUID? {
        guard fraction.isFinite, (0...1).contains(fraction),
              ensurePaperWritingRow(rowIndex) != nil else { return nil }
        let tolerance = 0.002
        for index in systems[rowIndex].measures.indices {
            guard let placement = systems[rowIndex].measures[index].paperLayout else { continue }
            if abs(placement.startFraction - fraction) <= tolerance {
                let resolvedKind = paperBoundaryKind(kind, preserving: placement.leadingBarline)
                systems[rowIndex].measures[index].paperLayout?.leadingBarline = resolvedKind
                if index > 0, let previous = systems[rowIndex].measures[index - 1].paperLayout,
                   abs(previous.endFraction - fraction) <= tolerance {
                    systems[rowIndex].measures[index - 1].barlineAfter = resolvedKind
                }
                let measureID = systems[rowIndex].measures[index].id
                updatedAt = .now
                _ = repairEnclosedPaperMeasures()
                return measureID
            }
            if abs(placement.endFraction - fraction) <= tolerance {
                let wasOpen = systems[rowIndex].measures[index].authoringState == .open
                let resolvedKind = paperBoundaryKind(kind,
                    preserving: systems[rowIndex].measures[index].barlineAfter)
                systems[rowIndex].measures[index].barlineAfter = resolvedKind
                if systems[rowIndex].measures.indices.contains(index + 1),
                   let next = systems[rowIndex].measures[index + 1].paperLayout,
                   abs(next.startFraction - fraction) <= tolerance {
                    systems[rowIndex].measures[index + 1].paperLayout?.leadingBarline = resolvedKind
                }
                if wasOpen {
                    systems[rowIndex].measures[index].paperLayout?.needsSystemFit = true
                }
                systems[rowIndex].measures[index].authoringState = .committed
                if wasOpen && normalizeSingleChords {
                    anchorLoneChordsToMeasureStart(in: [systems[rowIndex].measures[index].id])
                }
                updatedAt = .now
                let measureID = systems[rowIndex].measures[index].id
                _ = repairEnclosedPaperMeasures()
                return measureID
            }
        }
        guard let target = ensurePaperChordTarget(inRow: rowIndex, at: fraction),
              let location = measureLocation(id: target.measureID),
              let placement = systems[location.systemIndex].measures[location.measureIndex].paperLayout
        else { return nil }
        let original = systems[location.systemIndex].measures[location.measureIndex]
        let hasContentBefore = original.chordEvents.contains {
            paperChordFraction($0, in: original) < target.fraction
        } || original.rhythmMap != nil || !original.pitchedNoteEvents.isEmpty
            || original.handwrittenRhythmicNotationData != nil
            || !original.cueTextIDs.isEmpty || !original.roadmapObjectIDs.isEmpty
        if original.authoringState == .open, placement.leadingBarline == nil,
           allowsOpeningBoundary, !hasContentBefore {
            var moved = original
            for index in moved.chordEvents.indices {
                let oldFraction = paperChordFraction(moved.chordEvents[index], in: original)
                let newFraction = (oldFraction - target.fraction) / max(0.0001, 1 - target.fraction)
                moved.chordEvents[index].manualVisualLaneFraction =
                    ChordEvent.clampedManualLaneFraction(newFraction)
            }
            moved.paperLayout?.startFraction = fraction
            moved.paperLayout?.leadingBarline = kind
            moved.paperLayout?.needsSystemFit = true
            systems[location.systemIndex].measures[location.measureIndex] = moved
            updatedAt = .now
            _ = repairEnclosedPaperMeasures()
            return moved.id
        }

        let rightID: UUID?
        if layoutStyle == .simpleChordSheet {
            rightID = splitSimpleChordMeasure(original.id, atFraction: target.fraction,
                barlineAfter: kind, normalizeSingleChordToMeasureStart: normalizeSingleChords)
        } else if original.authoringState == .open {
            var candidate = self
            candidate.systems[location.systemIndex].measures[location.measureIndex].authoringState = .committed
            rightID = candidate.splitCommittedRhythmSectionMeasure(original.id, atFraction: target.fraction,
                barlineAfter: kind, normalizeSingleChordToMeasureStart: normalizeSingleChords)
            if let rightID, let rightLocation = candidate.measureLocation(id: rightID) {
                candidate.systems[rightLocation.systemIndex].measures[rightLocation.measureIndex].authoringState = .open
                self = candidate
            }
        } else {
            rightID = splitCommittedRhythmSectionMeasure(original.id, atFraction: target.fraction,
                barlineAfter: kind, normalizeSingleChordToMeasureStart: normalizeSingleChords)
        }
        if rightID != nil { _ = repairEnclosedPaperMeasures() }
        return rightID
    }

    @discardableResult
    mutating func finishPaperWritingRows() -> Bool {
        guard usesPaperMeasureLayout else { return false }
        var changed = repairEnclosedPaperMeasures()
        for row in systems.indices {
            guard systems[row].measures.contains(where: { $0.paperLayout?.needsSystemFit == true }) else { continue }
            let complete = systems[row].measures.filter {
                $0.authoringState == .committed || paperMeasureHasContent($0)
            }
            if !complete.isEmpty {
                systems[row].measures = complete
                for index in systems[row].measures.indices {
                    systems[row].measures[index].authoringState = .committed
                    if complete.count > 1 {
                        systems[row].measures[index].paperLayout?.startFraction = Double(index) / Double(complete.count)
                        systems[row].measures[index].paperLayout?.endFraction = Double(index + 1) / Double(complete.count)
                    }
                    systems[row].measures[index].paperLayout?.needsSystemFit = false
                }
            } else {
                for index in systems[row].measures.indices {
                    systems[row].measures[index].paperLayout?.needsSystemFit = false
                }
            }
            changed = true
        }
        changed = repairEnclosedPaperMeasures() || changed
        if changed {
            renumberPaperMeasures()
            updatedAt = .now
        }
        return changed
    }

    @discardableResult
    mutating func movePaperMeasure(_ id: UUID, toStartFraction start: Double) -> Bool {
        guard let location = measureLocation(id: id),
              let sourcePositions = paperMeasureMovePositions(for: id),
              let proposal = PaperMeasureMoveProposal.positions(moving: id,
                toStartFraction: start, among: sourcePositions) else { return false }
        let row = location.systemIndex
        systems[row].measures = systems[row].measures.compactMap { measure in
            guard let placement = proposal[measure.id] else { return nil }
            var moved = measure
            moved.paperLayout = placement
            return moved
        }
        sortPaperRow(row)
        _ = repairEnclosedPaperMeasures()
        renumberPaperMeasures()
        updatedAt = .now
        return true
    }

    func paperMeasureMovePositions(for measureID: UUID) -> [UUID: PaperMeasureLayout]? {
        guard usesPaperMeasureLayout, let location = measureLocation(id: measureID),
              systems[location.systemIndex].measures[location.measureIndex].paperLayout != nil else { return nil }
        return Dictionary(uniqueKeysWithValues: systems[location.systemIndex].measures.compactMap { measure in
            guard measure.id == measureID || measure.authoringState == .committed || paperMeasureHasContent(measure),
                  let placement = measure.paperLayout else { return nil }
            return (measure.id, placement)
        })
    }

    @discardableResult
    mutating func resizePaperMeasure(_ id: UUID, startFraction start: Double, endFraction end: Double) -> Bool {
        guard usesPaperMeasureLayout, start.isFinite, end.isFinite,
              let location = measureLocation(id: id),
              start >= 0, end <= 1, end - start >= 0.0001 else { return false }
        let row = location.systemIndex
        var measure = systems[row].measures[location.measureIndex]
        guard measure.paperLayout != nil else { return false }
        measure.paperLayout?.startFraction = start
        measure.paperLayout?.endFraction = end
        measure.paperLayout?.needsSystemFit = false
        let peers = systems[row].measures.filter {
            $0.id != id && ($0.authoringState == .committed || paperMeasureHasContent($0))
        }
        let overlaps = peers.contains {
            guard let placement = $0.paperLayout else { return false }
            return start < placement.endFraction - 0.0001 && end > placement.startFraction + 0.0001
        }
        if overlaps {
            var ordered = peers + [measure]
            ordered.sort { ($0.paperLayout?.startFraction ?? 0) < ($1.paperLayout?.startFraction ?? 0) }
            let minimumPeerWidth = 0.0001
            let selectedWidth = min(end - start, 1 - Double(peers.count) * minimumPeerWidth)
            let remaining = max(Double(peers.count) * minimumPeerWidth, 1 - selectedWidth)
            let peerTotal = max(0.0001, peers.compactMap(\.paperLayout).map(\.widthFraction).reduce(0, +))
            let extraPeerSpace = max(0, remaining - Double(peers.count) * minimumPeerWidth)
            let widths = ordered.map { $0.id == id ? selectedWidth
                : minimumPeerWidth + ($0.paperLayout?.widthFraction ?? 0) * extraPeerSpace / peerTotal }
            systems[row].measures = packedPaperMeasures(ordered, row: row, widths: widths)
        } else {
            systems[row].measures = peers + [measure]
            sortPaperRow(row)
        }
        renumberPaperMeasures()
        _ = repairEnclosedPaperMeasures()
        updatedAt = .now
        return true
    }

    /// Build 201 could leave an interval between two authored boundaries
    /// without a selectable measure. Restore only those enclosed intervals.
    /// Decode uses this without turning a layout repair into a new chart edit.
    @discardableResult
    mutating func repairEnclosedPaperMeasures() -> Bool {
        guard usesPaperMeasureLayout else { return false }
        var changed = false
        let tolerance = 0.0001
        for row in systems.indices {
            let ordered = systems[row].measures.sorted {
                ($0.paperLayout?.startFraction ?? 0) < ($1.paperLayout?.startFraction ?? 0)
            }
            var repaired: [Measure] = []
            for source in ordered {
                if let previous = repaired.last, previous.authoringState == .committed,
                   let left = previous.paperLayout, let right = source.paperLayout,
                   let closingBoundary = right.leadingBarline,
                   right.startFraction - left.endFraction > tolerance {
                    var enclosed = paperOpenMeasure(inRow: row,
                        start: left.endFraction, end: right.startFraction)
                    enclosed.id = paperEnclosedMeasureID(in: systems[row].id,
                        after: previous.id, before: source.id)
                    enclosed.authoringState = .committed
                    enclosed.meterOverride = previous.meterOverride
                    enclosed.beatGridPreset = previous.beatGridPreset
                    enclosed.paperLayout?.leadingBarline = previous.barlineAfter
                    enclosed.barlineAfter = closingBoundary
                    repaired.append(enclosed)
                    changed = true
                }
                repaired.append(source)
            }
            if repaired.count != systems[row].measures.count { systems[row].measures = repaired }
        }
        if changed { renumberPaperMeasures() }
        return changed
    }

    private func paperEnclosedMeasureID(in systemID: UUID, after leftID: UUID, before rightID: UUID) -> UUID {
        let identity = ["paper-gap-v1", id.uuidString, systemID.uuidString,
            leftID.uuidString, rightID.uuidString].joined(separator: "|")
        let bytes = Array(SHA256.hash(data: Data(identity.utf8)).prefix(16))
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    /// Preserve row identity when ordinary notation edits rebuild the chart.
    mutating func rebuildPaperMeasureSystems(using measures: [Measure]) {
        let templates = systems
        var grouped: [Int: [Measure]] = [:]
        var row = 0
        for measure in measures {
            row = measure.paperLayout?.rowIndex ?? row
            grouped[row, default: []].append(measure)
        }
        let rowCount = max(templates.count, (grouped.keys.max() ?? -1) + 1)
        systems = (0..<max(1, rowCount)).map { row in
            var rowMeasures = grouped[row] ?? []
            if rowMeasures.contains(where: { $0.paperLayout == nil }) {
                for index in rowMeasures.indices {
                    rowMeasures[index].paperLayout = PaperMeasureLayout(rowIndex: row,
                        startFraction: Double(index) / Double(rowMeasures.count),
                        endFraction: Double(index + 1) / Double(rowMeasures.count),
                        leadingBarline: rowMeasures[index].paperLayout?.leadingBarline,
                        needsSystemFit: false)
                }
            }
            let template = templates.indices.contains(row) ? templates[row] : nil
            return ChartSystem(id: template?.id ?? UUID(), index: row,
                spacingMode: template?.spacingMode ?? .automatic,
                lineBreakRule: row == 0 ? .automatic : .forced,
                startsNewPage: template?.startsNewPage ?? false,
                measures: rowMeasures.isEmpty ? [paperOpenMeasure(inRow: row, start: 0, end: 1)] : rowMeasures)
        }
        renumberPaperMeasures()
    }

    func splitPaperLayout(
        _ original: PaperMeasureLayout?, fraction: Double, barlineAfter: BarlineType,
        left: inout Measure, right: inout Measure
    ) {
        guard let original else { return }
        let boundary = original.startFraction + original.widthFraction * fraction
        left.paperLayout = PaperMeasureLayout(rowIndex: original.rowIndex,
            startFraction: original.startFraction, endFraction: boundary,
            leadingBarline: original.leadingBarline, needsSystemFit: true)
        right.paperLayout = PaperMeasureLayout(rowIndex: original.rowIndex,
            startFraction: boundary, endFraction: original.endFraction,
            leadingBarline: barlineAfter, needsSystemFit: true)
    }

    @discardableResult
    mutating func equalizePaperRow(containing measureID: UUID) -> Bool {
        guard usesPaperMeasureLayout, let location = measureLocation(id: measureID) else { return false }
        let row = location.systemIndex
        systems[row].measures = packedPaperMeasures(systems[row].measures, row: row,
            widths: Array(repeating: 1, count: systems[row].measures.count))
        updatedAt = .now
        return true
    }

    @discardableResult
    mutating func insertPaperMeasures(
        after measureID: UUID, count: Int, barlineAfter: BarlineType
    ) -> [UUID]? {
        guard usesPaperMeasureLayout, count > 0,
              let location = measureLocation(id: measureID) else { return nil }
        let row = location.systemIndex
        systems[row].measures[location.measureIndex].authoringState = .committed
        let newMeasures = (0..<count).map { _ -> Measure in
            var measure = paperOpenMeasure(inRow: row, start: 0, end: 1)
            measure.authoringState = .committed
            measure.barlineAfter = barlineAfter
            measure.paperLayout?.leadingBarline = .single
            return measure
        }
        systems[row].measures.insert(contentsOf: newMeasures, at: location.measureIndex + 1)
        _ = equalizePaperRow(containing: measureID)
        renumberPaperMeasures()
        updatedAt = .now
        return newMeasures.map(\.id)
    }

    @discardableResult
    mutating func reflowPaperMeasureRows(_ originalRows: [[UUID]], into rows: [[UUID]]) -> Bool {
        guard let first = originalRows.first?.first,
              let last = originalRows.last?.last,
              let firstLocation = measureLocation(id: first),
              let lastLocation = measureLocation(id: last),
              firstLocation.systemIndex < lastLocation.systemIndex,
              rows.flatMap({ $0 }) == originalRows.flatMap({ $0 }) else { return false }
        let oldSystems = systems
        let source = Dictionary(uniqueKeysWithValues: measures.map { ($0.id, $0) })
        let lower = firstLocation.systemIndex
        let upper = lastLocation.systemIndex
        guard systems[lower...upper].flatMap(\.measures).map(\.id) == originalRows.flatMap({ $0 }) else { return false }
        let replacement = rows.enumerated().map { offset, ids in
            let row = lower + offset
            return ChartSystem(id: offset == 0 ? oldSystems[lower].id : UUID(),
                index: row, spacingMode: .automatic, lineBreakRule: row == 0 ? .automatic : .forced,
                startsNewPage: offset == 0 && oldSystems[lower].startsNewPage,
                measures: packedPaperMeasures(ids.compactMap { source[$0] }, row: row,
                    widths: Array(repeating: 1, count: ids.count)))
        }
        systems.replaceSubrange(lower...upper, with: replacement)
        renumberPaperMeasures()
        updatedAt = .now
        return true
    }

    @discardableResult
    mutating func appendPaperWritingRows(count: Int) -> UUID? {
        guard usesPaperMeasureLayout, count > 0 else { return nil }
        let firstRow = systems.count
        for row in firstRow..<(firstRow + count) {
            systems.append(ChartSystem(id: UUID(), index: row, spacingMode: .automatic,
                lineBreakRule: .forced, startsNewPage: row == firstRow,
                measures: [paperOpenMeasure(inRow: row, start: 0, end: 1)]))
        }
        renumberPaperMeasures()
        updatedAt = .now
        return systems[firstRow].measures.first?.id
    }

    @discardableResult
    mutating func insertPaperSystemBreak(before measureID: UUID) -> Bool {
        guard let location = measureLocation(id: measureID), location.measureIndex > 0 else { return false }
        let row = location.systemIndex
        let split = location.measureIndex
        let left = Array(systems[row].measures[..<split])
        let right = Array(systems[row].measures[split...])
        systems[row].measures = packedPaperMeasures(left, row: row,
            widths: Array(repeating: 1, count: left.count))
        systems.insert(ChartSystem(id: UUID(), index: row + 1, spacingMode: .automatic,
            lineBreakRule: .forced, measures: packedPaperMeasures(right, row: row + 1,
                widths: Array(repeating: 1, count: right.count))), at: row + 1)
        renumberPaperMeasures()
        updatedAt = .now
        return true
    }

    @discardableResult
    mutating func removePaperSystemBreak(before measureID: UUID) -> Bool {
        guard let location = measureLocation(id: measureID), location.systemIndex > 0,
              location.measureIndex == 0 else { return false }
        let row = location.systemIndex
        let joined = systems[row - 1].measures + systems[row].measures
        systems[row - 1].measures = packedPaperMeasures(joined, row: row - 1,
            widths: Array(repeating: 1, count: joined.count))
        systems.remove(at: row)
        renumberPaperMeasures()
        updatedAt = .now
        return true
    }

    private func paperOpenMeasure(inRow row: Int, start: Double, end: Double) -> Measure {
        var measure = Measure(id: UUID(), index: 1, meterOverride: nil,
            beatGridPreset: layoutStyle.profile.measureDefaults.beatGridPreset,
            barlineAfter: .single, chordEvents: [], cueTextIDs: [], roadmapObjectIDs: [], authoringState: .open)
        measure.paperLayout = PaperMeasureLayout(rowIndex: row, startFraction: start,
            endFraction: end, leadingBarline: nil)
        return measure
    }

    private func paperMeasureHasContent(_ measure: Measure) -> Bool {
        !measure.chordEvents.isEmpty || measure.rhythmMap != nil || !measure.pitchedNoteEvents.isEmpty
            || measure.handwrittenRhythmicNotationData != nil || !measure.cueTextIDs.isEmpty
            || !measure.roadmapObjectIDs.isEmpty
            || freeInkArticulations.contains { $0.measureID == measure.id }
            || freehandSymbols.contains { $0.anchorMeasureID == measure.id }
            || sectionLabels.contains { $0.anchorMeasureID == measure.id }
            || paperMeasureHasPageInk(measure.id)
    }

    private func paperMeasureHasPageInk(_ measureID: UUID) -> Bool {
        #if canImport(UIKit) && canImport(PencilKit)
        guard let data = pageHandwrittenNotationData,
              let source = pageHandwrittenNotationCoordinateSpace,
              source.measureAnchors?.contains(where: { $0.measureID == measureID }) == true,
              let drawing = PaperMeasureInkOwnership.drawing(in: data) else { return false }
        var probe = source
        probe.measureAnchors = source.measureAnchors?.map { anchor in
            var moved = anchor
            if anchor.measureID == measureID {
                moved.frame.x += 1
                moved.staffFrame?.x += 1
            }
            return moved
        }
        probe.chordAnchors = source.chordAnchors?.map { anchor in
            var moved = anchor
            if anchor.measureID == measureID {
                moved.frame.x += 1
                moved.registrationPoint?.x += 1
            }
            return moved
        }
        let projected = LeadSheetPersistentInkCoordinateSpacePolicy.drawing(drawing,
            sourceCoordinateSpace: source, targetCoordinateSpace: probe)
        return zip(drawing.strokes, projected.strokes).contains {
            $0.renderBounds != $1.renderBounds
        }
        #else
        return false
        #endif
    }

    private func paperChordFraction(_ event: ChordEvent, in measure: Measure) -> Double {
        if let visual = event.manualVisualLaneFraction { return ChordEvent.clampedManualLaneFraction(visual) }
        if let manual = event.manualLaneFraction { return ChordEvent.clampedManualLaneFraction(manual) }
        let meter = measure.resolvedMeter(defaultMeter: defaultMeter)
        return (event.startPosition.startOffset(in: meter) ?? 0) / max(0.0001, meter.measureLengthInWholeNotes)
    }

    private func paperBoundaryKind(_ proposed: BarlineType, preserving existing: BarlineType?) -> BarlineType {
        if existing == .final { return .final }
        if existing == .double && proposed == .single { return .double }
        return proposed
    }

    private func packedPaperMeasures(_ measures: [Measure], row: Int, widths: [Double]? = nil) -> [Measure] {
        let proposed = widths ?? measures.map { $0.paperLayout?.widthFraction ?? 1 }
        let total = max(0.0001, proposed.reduce(0, +))
        var start = 0.0
        return zip(measures, proposed).map { source, width in
            var measure = source
            let end = min(1, start + width / total)
            measure.paperLayout = PaperMeasureLayout(rowIndex: row, startFraction: start,
                endFraction: end, leadingBarline: source.paperLayout?.leadingBarline,
                needsSystemFit: false)
            start = end
            return measure
        }
    }

    private mutating func sortPaperRow(_ row: Int) {
        systems[row].measures.sort { ($0.paperLayout?.startFraction ?? 0) < ($1.paperLayout?.startFraction ?? 0) }
        renumberPaperMeasures()
    }

    private mutating func renumberPaperMeasures() {
        var measureIndex = 1
        for row in systems.indices {
            systems[row].index = row
            for column in systems[row].measures.indices {
                systems[row].measures[column].index = measureIndex
                systems[row].measures[column].paperLayout?.rowIndex = row
                measureIndex += 1
            }
        }
        normalizePaperRangeEndpoints()
        normalizeAnchorsToSystems()
    }

    private mutating func normalizePaperRangeEndpoints() {
        let indices = Dictionary(uniqueKeysWithValues: measures.enumerated().map { ($0.element.id, $0.offset) })
        let rangeIDs = Set(roadmapObjects.filter { $0.type == .repeatSpan || $0.type.isEnding }.map(\.id))
        for index in roadmapObjects.indices where rangeIDs.contains(roadmapObjects[index].id) {
            guard let end = roadmapObjects[index].endMeasureID,
                  let first = indices[roadmapObjects[index].startMeasureID], let last = indices[end] else { continue }
            if first > last {
                roadmapObjects[index].endMeasureID = roadmapObjects[index].startMeasureID
                roadmapObjects[index].startMeasureID = end
            }
        }
        for row in systems.indices {
            for column in systems[row].measures.indices {
                let id = systems[row].measures[column].id
                systems[row].measures[column].roadmapObjectIDs.removeAll { rangeIDs.contains($0) }
                let references = roadmapObjects.filter {
                    rangeIDs.contains($0.id) && ($0.startMeasureID == id || $0.endMeasureID == id)
                }.map(\.id)
                systems[row].measures[column].roadmapObjectIDs.append(contentsOf: references)
            }
        }
    }
}
