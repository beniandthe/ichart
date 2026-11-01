#if canImport(UIKit) && canImport(PencilKit)
import CoreGraphics
import Foundation
import PencilKit
import UIKit
import XCTest
@testable import iChart

/// An opt-in replay of authorized saved ink. Private chart data and diagnostic
/// geometry are supplied locally, never embedded in the repository fixtures.
@MainActor
final class ChordInkEndingFeedbackReplayTests: XCTestCase {
    private let pageSize = CGSize(width: 1180, height: 1500)

    func testProvidedLibraryPencilKitRoundTripRetainsExactStrokeSemantics() throws {
        guard let path = environment("ICHART_ENDING_FEEDBACK_LIBRARY_PATH") else {
            throw XCTSkip("Provide an authorized library snapshot through ICHART_ENDING_FEEDBACK_LIBRARY_PATH")
        }
        let sourceURL = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        let originalBytes = try Data(contentsOf: sourceURL)
        defer {
            XCTAssertEqual(try? Data(contentsOf: sourceURL), originalBytes,
                "PencilKit diagnosis must never modify the saved source library")
        }
        let before = try XCTUnwrap(JSONSerialization.jsonObject(with: originalBytes) as? [String: Any])
        let originalCharts = try XCTUnwrap(before["charts"] as? [[String: Any]])
        let snapshot = try XCTUnwrap(FileChartRepository(url: sourceURL).loadSnapshot())
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("library-state.json")
        try FileChartRepository(url: destination).saveSnapshot(snapshot)
        let resavedBytes = try Data(contentsOf: destination)
        let resaved = try XCTUnwrap(JSONSerialization.jsonObject(with: resavedBytes) as? [String: Any])
        let resavedCharts = try XCTUnwrap(resaved["charts"] as? [[String: Any]])
        XCTAssertEqual(originalCharts.count, resavedCharts.count)
        let output = environment("ICHART_ENDING_FEEDBACK_QA_OUTPUT").map { URL(fileURLWithPath: $0, isDirectory: true) }
        if let output { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
        var records = [[String: Any]]()
        var semanticChanges = 0
        var drawingsChecked = 0
        var drawingByteChanges = 0
        for (index, pair) in zip(originalCharts, resavedCharts).enumerated() {
            let (original, saved) = pair
            guard let encoded = original["pageHandwrittenChordData"] as? String,
                  let sourceDrawingBytes = Data(base64Encoded: encoded) else { continue }
            drawingsChecked += 1
            let storedDrawingBytes = try XCTUnwrap((saved["pageHandwrittenChordData"] as? String).flatMap { Data(base64Encoded: $0) })
            let sourceDrawing = try PKDrawing(data: sourceDrawingBytes)
            let storedDrawing = try PKDrawing(data: storedDrawingBytes)
            let sourceDescriptors = sourceDrawing.strokes.map(strokeSemantics)
            let storedDescriptors = storedDrawing.strokes.map(strokeSemantics)
            let sourceJSON = try JSONSerialization.data(withJSONObject: sourceDescriptors, options: [.sortedKeys])
            let storedJSON = try JSONSerialization.data(withJSONObject: storedDescriptors, options: [.sortedKeys])
            let exactSemantics = sourceJSON == storedJSON
            if !exactSemantics { semanticChanges += 1 }
            if sourceDrawingBytes != storedDrawingBytes { drawingByteChanges += 1 }
            var originalFields = original
            var savedFields = saved
            originalFields.removeValue(forKey: "pageHandwrittenChordData")
            savedFields.removeValue(forKey: "pageHandwrittenChordData")
            let otherFieldsExact = try JSONSerialization.data(withJSONObject: originalFields, options: [.sortedKeys])
                == JSONSerialization.data(withJSONObject: savedFields, options: [.sortedKeys])
            records.append([
                "chartPosition": index,
                "sourceByteCount": sourceDrawingBytes.count,
                "resavedByteCount": storedDrawingBytes.count,
                "bytesIdentical": sourceDrawingBytes == storedDrawingBytes,
                "rawDrawingReserializationEqualsResavedBytes": sourceDrawing.dataRepresentation() == storedDrawingBytes,
                "sourceNeedsInkNormalization": LeadSheetPersistentInkColorPolicy.needsNormalization(sourceDrawing),
                "resavedNeedsInkNormalization": LeadSheetPersistentInkColorPolicy.needsNormalization(storedDrawing),
                "sourceStrokeCount": sourceDrawing.strokes.count,
                "resavedStrokeCount": storedDrawing.strokes.count,
                "strokeSemanticsExactlyIdentical": exactSemantics,
                "allOtherChartFieldsIdentical": otherFieldsExact,
                "sourceStrokeSemantics": sourceDescriptors,
                "resavedStrokeSemantics": storedDescriptors
            ])
            XCTAssertTrue(exactSemantics,
                "Repository round trip must preserve every source point, timing, size, force, opacity, angle, threshold, creation date, random seed, transform, ink color/type, and mask")
            XCTAssertTrue(otherFieldsExact, "The PencilKit investigation must not hide another chart field change")
            if !LeadSheetPersistentInkColorPolicy.needsNormalization(sourceDrawing) {
                XCTAssertEqual(sourceDrawingBytes, storedDrawingBytes,
                    "Already-persistent source ink must retain its original archive bytes across repository load/save")
            }
            if let output {
                try sourceDrawingBytes.write(to: output.appendingPathComponent("chart-\(index)-source.drawing"))
                try storedDrawingBytes.write(to: output.appendingPathComponent("chart-\(index)-resaved.drawing"))
            }
        }
        XCTAssertGreaterThan(drawingsChecked, 0, "The authorized library must contain chord source ink")
        let diagnostics: [String: Any] = [
            "schemaVersion": 1,
            "chartCount": originalCharts.count,
            "drawingsChecked": drawingsChecked,
            "drawingByteChanges": drawingByteChanges,
            "semanticChanges": semanticChanges,
            "records": records
        ]
        let encoded = try JSONSerialization.data(withJSONObject: diagnostics, options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(data: encoded, uniformTypeIdentifier: "public.json")
        attachment.name = "provided-library-pencilkit-roundtrip-diagnostics"
        attachment.lifetime = .keepAlways
        add(attachment)
        if let output {
            try encoded.write(to: output.appendingPathComponent("provided-library-pencilkit-roundtrip.json"))
        }
    }

    func testWavyEndingRoofSnapsToVisibleTerminalRepeatAndKeepsFollowingOpenMeasureOutside() throws {
        for horizontalOffset in [CGFloat(-7), 0, 7] {
            var chart = Chart.blank(title: "Ending near a terminal repeat", measureCount: 6,
                layoutStyle: .simpleChordSheet)
            let widths: [Double] = [91, 120, 50, 92, 92, 64]
            let ids = chart.measures.map(\.id)
            for index in chart.systems[0].measures.indices {
                chart.systems[0].measures[index].manualLayoutWidth = widths[index]
                chart.systems[0].measures[index].authoringState = index == 5 ? .open : .committed
                chart.systems[0].measures[index].barlineAfter = .single
            }
            let firstEnding = try XCTUnwrap(chart.addEndingSpan(.ending1,
                startMeasureID: ids[1], endMeasureID: ids[1], displayText: "1.", endStyle: .open))
            let secondEnding = try XCTUnwrap(chart.addEndingSpan(.ending1,
                startMeasureID: ids[3], endMeasureID: ids[3], displayText: "1, 3", endStyle: .open))
            let repeatID = try XCTUnwrap(chart.addRepeatSpan(startMeasureID: ids[3], endMeasureID: ids[4]))
            let receipt = PKDrawing(strokes: [stroke([CGPoint(x: 1, y: 1), CGPoint(x: 3, y: 8)], origin: .zero)]).dataRepresentation()
            for id in [firstEnding, secondEnding, repeatID] {
                let index = try XCTUnwrap(chart.roadmapObjects.firstIndex { $0.id == id })
                chart.roadmapObjects[index].sourceInkData = receipt
            }
            let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize,
                includesChordInkContinuationLanes: true)
            let system = try XCTUnwrap(layout.systems.first)
            let lane = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingSystemLaneFrame(for: system,
                paperFrame: layout.paperFrame(for: system)))
            let chordFrame = LeadSheetActiveInkScope.chordWritingRegion(for: layout).frame
            let fifth = try XCTUnwrap(system.measures.first { $0.sourceMeasureID == ids[4] })
            let visibleClose = try XCTUnwrap(LeadSheetSimpleChordTerminalBarlineGeometry.terminalTrailingRepeatLineX(
                after: fifth, in: system, paperFrame: layout.paperFrame(for: system), layoutStyle: chart.layoutStyle))
            let splitX = fifth.frame.minX + fifth.frame.width * 0.60
            let left = splitX + horizontalOffset
            let right = visibleClose - 10 + horizontalOffset
            let roofY = lane.minY + 9
            let drawing = PKDrawing(strokes: [
                stroke([CGPoint(x: splitX, y: lane.minY + 27), CGPoint(x: splitX + 1.5, y: lane.maxY - 8)],
                    origin: chordFrame.origin),
                stroke([CGPoint(x: left - 1, y: roofY + 2), CGPoint(x: left - 0.5, y: roofY + 16)],
                    origin: chordFrame.origin),
                stroke([CGPoint(x: left + 1, y: roofY + 2), CGPoint(x: left + 35, y: roofY),
                    CGPoint(x: left + (right - left) * 0.48, y: roofY + 3),
                    CGPoint(x: right - 25, y: roofY - 1), CGPoint(x: right, y: roofY + 1)],
                    origin: chordFrame.origin)
            ])
            _ = chart.setPageHandwrittenChordDrawing(drawing.dataRepresentation(),
                coordinateSpace: PersistentInkCoordinateSpace(size: chordFrame.size))
            let preparation = prepare(drawing, chart: chart, layout: layout, chordFrame: chordFrame)
            let after = try assertReviewedBatch(chart: chart, drawing: drawing, preparation: preparation,
                expectedRange: 6...6, newLabel: "2.")
            XCTAssertEqual(after.measures.count, 7)
            XCTAssertEqual(after.measures.last?.id, ids[5], "The original empty open measure is continuation space")
            if let output = environment("ICHART_ENDING_FEEDBACK_QA_OUTPUT"), horizontalOffset == 0 {
                let directory = URL(fileURLWithPath: output, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try XCTUnwrap(nativeImage(chart: chart, drawing: drawing, chordFrame: chordFrame,
                    state: previewState(preparation)).pngData())
                    .write(to: directory.appendingPathComponent("synthetic-ending-before.png"))
                let afterLayout = LeadSheetPageLayoutEngine.pageLayout(for: after, pageSize: pageSize,
                    includesChordInkContinuationLanes: true)
                let afterFrame = LeadSheetActiveInkScope.chordWritingRegion(for: afterLayout).frame
                try XCTUnwrap(nativeImage(chart: after, drawing: PKDrawing(), chordFrame: afterFrame,
                    state: ChordPreviewState()).pngData())
                    .write(to: directory.appendingPathComponent("synthetic-ending-after.png"))
            }
        }
    }

    func testProvidedEndingInkReplaysAgainstItsActualMeasureAndRepeatGeometry() throws {
        guard let path = environment("ICHART_ENDING_FEEDBACK_CHART_PATH") else {
            throw XCTSkip("Provide an authorized saved chart through ICHART_ENDING_FEEDBACK_CHART_PATH")
        }
        let sourceURL = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        let originalBytes = try Data(contentsOf: sourceURL)
        defer {
            XCTAssertEqual(try? Data(contentsOf: sourceURL), originalBytes,
                "Replay must leave the authorized saved chart file immutable")
        }
        let chart = try ChartPersistenceCoders.decoder.decode(Chart.self, from: originalBytes)
        let originalChart = chart
        let savedDrawing = try PKDrawing(data: XCTUnwrap(chart.pageHandwrittenChordData))
        XCTAssertFalse(savedDrawing.strokes.isEmpty)
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize,
            includesChordInkContinuationLanes: true)
        let region = LeadSheetActiveInkScope.chordWritingRegion(for: layout)
        let projected = try XCTUnwrap(LeadSheetPersistentInkCoordinateSpacePolicy.drawing(
            from: chart.pageHandwrittenChordData,
            sourceCoordinateSpace: chart.pageHandwrittenChordCoordinateSpace,
            targetFrame: region.frame))
        let targetCoordinateSpace = try XCTUnwrap(PersistentInkCoordinateSpace(size: region.frame.size))
        var replayChart = chart
        _ = replayChart.setPageHandwrittenChordDrawing(projected.dataRepresentation(),
            coordinateSpace: targetCoordinateSpace, assumesNormalizedPersistentInk: true)
        let preparation = prepare(projected, chart: chart, layout: layout, chordFrame: region.frame)
        let rawGeometry = ChordDraftEndingRecognizer.recognize(
            strokes: PencilKitInkAdapter.inkStrokes(from: projected),
            chordFrame: region.frame, pageLayout: layout)
        var state = ChordPreviewState()
        state.replaceDraftBarlines(with: preparation.barlines)
        state.replaceDraftEndings(with: preparation.endings)
        state.layoutPageSize = pageSize
        let indices = Dictionary(uniqueKeysWithValues: chart.measures.map { ($0.id, $0.index) })
        let report: [String: Any] = [
            "schemaVersion": 1,
            "pageSize": size(pageSize),
            "sourceCoordinateSpace": chart.pageHandwrittenChordCoordinateSpace.map { size($0.size) } ?? [:],
            "targetCoordinateSpace": size(targetCoordinateSpace.size),
            "reprojectionRequired": chart.pageHandwrittenChordCoordinateSpace != targetCoordinateSpace,
            "chordFrame": rect(region.frame),
            "inputFrames": region.inputFrames.map(rect),
            "sourceStrokes": strokes(savedDrawing, pageOrigin: region.frame.origin),
            "projectedStrokes": strokes(projected, pageOrigin: region.frame.origin),
            "systems": layout.systems.map { system -> [String: Any] in
                [
                    "index": system.index,
                    "frame": rect(system.frame),
                    "lane": LeadSheetActiveInkScope.chordWritingSystemLaneFrame(for: system,
                        paperFrame: layout.paperFrame(for: system)).map(rect) ?? [:],
                    "measures": system.measures.map { measure -> [String: Any] in
                        [
                            "index": measure.index,
                            "isSynthetic": measure.sourceMeasureID == nil,
                            "isOpen": measure.isOpen,
                            "frame": rect(measure.frame),
                            "staffFrame": rect(measure.staffFrame),
                            "chordWritingFrame": rect(measure.chordWritingFrame),
                            "displayFrame": rect(LeadSheetSimpleChordTerminalBarlineGeometry.displayMeasure(measure,
                                in: system, paperFrame: layout.paperFrame(for: system), layoutStyle: chart.layoutStyle).frame),
                            "chords": measure.chordLayouts.map { rect($0.frame) },
                            "repeats": measure.repeatMarkerLayouts.map { marker -> [String: Any] in
                                ["edge": marker.edge.rawValue, "frame": rect(marker.frame), "occupiedFrame": rect(marker.occupiedFrame)]
                            }
                        ]
                    },
                    "endings": system.endingLayouts.map { ending -> [String: Any] in
                        ["frame": rect(ending.frame), "labelFrame": rect(ending.labelFrame),
                         "leadingHook": ending.showsLeadingHook, "trailingHook": ending.showsTrailingHook]
                    }
                ]
            },
            "existingRoadmaps": chart.roadmapObjects.map { object -> [String: Any] in
                ["type": object.type.rawValue,
                 "startMeasure": indices[object.startMeasureID] as Any? ?? NSNull(),
                 "endMeasure": object.endMeasureID.flatMap { indices[$0] } as Any? ?? NSNull()]
            },
            "rawEndingCount": rawGeometry.endings.count,
            "preparation": [
                "outcome": outcomeName(preparation.outcome),
                "sourceStrokeCount": preparation.sourceStrokeCount,
                "visibleStrokeCount": preparation.visibleStrokeCount,
                "recognitionStrokeCount": preparation.recognitionStrokeCount,
                "endingCount": preparation.endings.count,
                "barlineCount": preparation.barlines.count,
                "targetCount": requests(preparation.outcome).count,
                "targets": requests(preparation.outcome).map { request -> [String: Any] in
                    ["measure": indices[request.target.measureID] as Any? ?? NSNull(),
                     "fraction": request.target.fraction,
                     "strokeCount": request.strokes.count,
                     "laneSystem": request.laneLocation?.systemIndex as Any? ?? NSNull(),
                     "laneFraction": request.laneLocation?.fraction as Any? ?? NSNull()]
                },
                "endings": preparation.endings.map { ending -> [String: Any] in
                    let mapped = replayChart.draftEndingMeasureRange(for: ending, state: state)
                    return ["start": endpoint(ending.start), "end": endpoint(ending.end),
                        "sourceIndices": ending.sourceStrokeIndices.sorted(),
                        "endStyle": ending.endStyle.rawValue,
                        "mappedRange": mapped.map { [$0.lowerBound, $0.upperBound] } as Any? ?? NSNull()]
                },
                "barlines": preparation.barlines.map { barline -> [String: Any] in
                    ["measure": barline.measureIndex, "fraction": barline.fraction,
                     "laneSystem": barline.laneLocation?.systemIndex as Any? ?? NSNull(),
                     "laneFraction": barline.laneLocation?.fraction as Any? ?? NSNull(),
                     "sourceIndices": barline.ownedSourceStrokeIndices.sorted(), "kind": barline.kind.rawValue]
                }
            ]
        ]
        let encoded = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        let reportAttachment = XCTAttachment(data: encoded, uniformTypeIdentifier: "public.json")
        reportAttachment.name = "provided-ending-feedback-diagnostics"
        reportAttachment.lifetime = .keepAlways
        add(reportAttachment)
        if let output = environment("ICHART_ENDING_FEEDBACK_QA_OUTPUT") {
            let directory = URL(fileURLWithPath: output, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try encoded.write(to: directory.appendingPathComponent("provided-ending-diagnostics.json"))
            let native = nativeImage(chart: chart, drawing: projected, chordFrame: region.frame, state: state)
            try XCTUnwrap(native.pngData()).write(to: directory.appendingPathComponent("provided-ending-native.png"))
            let nativeAttachment = XCTAttachment(image: native)
            nativeAttachment.name = "provided-ending-feedback-native"
            nativeAttachment.lifetime = .keepAlways
            add(nativeAttachment)
        }
        XCTAssertEqual(projected.strokes.count, savedDrawing.strokes.count,
            "Coordinate reprojection changes positions, not source ownership")
        let after = try assertReviewedBatch(chart: replayChart, drawing: projected, preparation: preparation,
            expectedRange: 6...6, newLabel: "2.")
        XCTAssertEqual(after.measures.count, chart.measures.count + 1)
        XCTAssertEqual(after.measures.last?.id, chart.measures.last?.id)
        if let output = environment("ICHART_ENDING_FEEDBACK_QA_OUTPUT") {
            let afterLayout = LeadSheetPageLayoutEngine.pageLayout(for: after, pageSize: pageSize,
                includesChordInkContinuationLanes: true)
            let afterFrame = LeadSheetActiveInkScope.chordWritingRegion(for: afterLayout).frame
            let afterImage = nativeImage(chart: after, drawing: PKDrawing(), chordFrame: afterFrame,
                state: ChordPreviewState())
            try XCTUnwrap(afterImage.pngData()).write(to: URL(fileURLWithPath: output, isDirectory: true)
                .appendingPathComponent("provided-ending-after-render.png"))
        }
        XCTAssertEqual(chart, originalChart)
    }

    private func assertReviewedBatch(
        chart: Chart, drawing: PKDrawing, preparation: ChordInkRecognitionPreparationResult,
        expectedRange: ClosedRange<Int>, newLabel: String
    ) throws -> Chart {
        XCTAssertEqual(preparation.endings.count, 1)
        XCTAssertEqual(preparation.barlines.count, 1)
        XCTAssertEqual(preparation.recognitionStrokeCount, 0)
        let state = previewState(preparation)
        let draft = try XCTUnwrap(state.draftEndings.first)
        XCTAssertEqual(chart.draftEndingMeasureRange(for: draft, state: state), expectedRange,
            "Visible repeat bars identify the preceding musical boundary, including displaced terminal repeats")
        let before = chart
        let priorEndings = chart.roadmapObjects.filter { $0.type.isEnding }
        let priorRepeat = try XCTUnwrap(chart.roadmapObjects.first { $0.type == .repeatSpan })
        XCTAssertEqual(chart.measure(id: priorRepeat.startMeasureID)?.index, 4)
        XCTAssertEqual(priorRepeat.endMeasureID.flatMap { chart.measure(id: $0)?.index }, 5)
        let request = try XCTUnwrap(ChordDraftEndingReviewPolicy.request(for: chart, state: state))
        XCTAssertEqual(request.measureRange, expectedRange)
        let reviewed = try XCTUnwrap(ChordDraftEndingReviewPolicy.reviewedState(for: request,
            chart: chart, currentState: state, label: newLabel, endStyle: .open))
        let outcome = ChordInkDraftRenderCoordinator.prepare(chart: chart, state: reviewed,
            currentDrawing: drawing, coordinateSpace: chart.pageHandwrittenChordCoordinateSpace)
        XCTAssertTrue(outcome.canConsumeSource)
        XCTAssertFalse(outcome.result.didRejectIncompleteSourceCoverage)
        XCTAssertTrue(outcome.result.unresolvedDraftIDs.isEmpty)
        XCTAssertEqual(outcome.result.renderedEndingCount, 1)
        XCTAssertEqual(outcome.result.renderedBarlineCount, 1)
        XCTAssertEqual(outcome.result.renderedChordCount, 0)
        XCTAssertNil(outcome.chart.pageHandwrittenChordData)
        let newEnding = try XCTUnwrap(outcome.chart.roadmapObjects.first { object in
            object.type.isEnding && !priorEndings.contains(where: { old in old.id == object.id })
        })
        XCTAssertEqual(outcome.chart.measure(id: newEnding.startMeasureID)?.index, expectedRange.lowerBound)
        XCTAssertEqual(newEnding.endMeasureID.flatMap { outcome.chart.measure(id: $0)?.index }, expectedRange.upperBound)
        XCTAssertEqual(newEnding.resolvedEndingDisplayText, newLabel)
        XCTAssertNotNil(newEnding.sourceInkData)
        XCTAssertNotEqual(newEnding.endMeasureID, before.measures.last?.id,
            "The original following open measure remains outside the new ending")
        for existing in priorEndings {
            XCTAssertEqual(outcome.chart.roadmapObject(id: existing.id), existing,
                "Existing ending labels, ranges, right edges, and source provenance remain unchanged")
        }
        let movedRepeat = try XCTUnwrap(outcome.chart.roadmapObject(id: priorRepeat.id))
        XCTAssertEqual(outcome.chart.measure(id: movedRepeat.startMeasureID)?.index, 4)
        XCTAssertEqual(movedRepeat.endMeasureID.flatMap { outcome.chart.measure(id: $0)?.index }, 6,
            "Splitting the final repeated measure retains its original outer closing boundary")
        var expectedRepeat = priorRepeat
        expectedRepeat.endMeasureID = movedRepeat.endMeasureID
        XCTAssertEqual(movedRepeat, expectedRepeat, "Repeat identity and source provenance remain intact")
        XCTAssertEqual(chart, before, "Range review and atomic preparation work only on a value copy")
        return outcome.chart
    }

    private func previewState(_ preparation: ChordInkRecognitionPreparationResult) -> ChordPreviewState {
        var state = ChordPreviewState()
        state.replaceDraftBarlines(with: preparation.barlines)
        state.replaceDraftEndings(with: preparation.endings)
        state.layoutPageSize = pageSize
        return state
    }

    private func prepare(
        _ drawing: PKDrawing, chart: Chart, layout: LeadSheetPageLayout, chordFrame: CGRect
    ) -> ChordInkRecognitionPreparationResult {
        ChordInkRecognitionPreparation.prepare(ChordInkRecognitionPreparationRequest(
            requestID: UUID(), scheduledAt: Date(), requestedDelay: 0,
            drawingData: drawing.dataRepresentation(), chordFrame: chordFrame,
            pageLayout: layout, flow: .draftPreview, options: .live, layoutStyle: chart.layoutStyle))
    }

    private func stroke(_ points: [CGPoint], origin: CGPoint) -> PKStroke {
        PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points.enumerated().map { index, point in
            PKStrokePoint(location: CGPoint(x: point.x - origin.x, y: point.y - origin.y),
                timeOffset: Double(index) * 0.05, size: CGSize(width: 3, height: 3),
                opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }, creationDate: Date(timeIntervalSinceReferenceDate: 800_000_200)))
    }

    private func strokes(_ drawing: PKDrawing, pageOrigin: CGPoint) -> [[String: Any]] {
        PencilKitInkAdapter.inkStrokes(from: drawing).enumerated().map { index, stroke in
            let bounds = CGRect(x: stroke.bounds.minX, y: stroke.bounds.minY,
                width: stroke.bounds.width, height: stroke.bounds.height)
            return ["index": index, "bounds": rect(bounds),
             "pageBounds": rect(bounds.offsetBy(dx: pageOrigin.x, dy: pageOrigin.y)),
             "points": stroke.points.map { ["x": $0.x, "y": $0.y] }]
        }
    }

    private func strokeSemantics(_ stroke: PKStroke) -> [String: Any] {
        let transform = stroke.transform
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        let rgbResolved = stroke.ink.color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let mask: Any
        if let path = stroke.mask {
            var elements = [[String: Any]]()
            path.cgPath.applyWithBlock { pointer in
                let element = pointer.pointee
                let count: Int
                switch element.type {
                case .moveToPoint, .addLineToPoint: count = 1
                case .addQuadCurveToPoint: count = 2
                case .addCurveToPoint: count = 3
                case .closeSubpath: count = 0
                @unknown default: count = 0
                }
                elements.append(["type": element.type.rawValue,
                    "points": (0..<count).map { ["x": Double(element.points[$0].x), "y": Double(element.points[$0].y)] }])
            }
            mask = ["elements": elements, "usesEvenOddFillRule": path.usesEvenOddFillRule]
        } else { mask = NSNull() }
        let points: [[String: Any]] = stroke.path.map { point in
            var values: [String: Any] = [
                "x": Double(point.location.x), "y": Double(point.location.y),
                "timeOffset": point.timeOffset,
                "width": Double(point.size.width), "height": Double(point.size.height),
                "opacity": Double(point.opacity), "force": Double(point.force),
                "azimuth": Double(point.azimuth), "altitude": Double(point.altitude),
                "secondaryScale": Double(point.secondaryScale)
            ]
            if #available(iOS 26.0, *) { values["threshold"] = Double(point.threshold) }
            return values
        }
        return [
            "inkType": stroke.ink.inkType.rawValue,
            "colorResolvedAsRGB": rgbResolved,
            "rgba": [Double(red), Double(green), Double(blue), Double(alpha)],
            "colorSpace": stroke.ink.color.cgColor.colorSpace?.name as String? ?? "unknown",
            "colorComponents": stroke.ink.color.cgColor.components?.map(Double.init) ?? [],
            "transform": [Double(transform.a), Double(transform.b), Double(transform.c), Double(transform.d),
                Double(transform.tx), Double(transform.ty)],
            "randomSeed": stroke.randomSeed,
            "creationDate": stroke.path.creationDate.timeIntervalSinceReferenceDate,
            "points": points,
            "mask": mask
        ]
    }

    private func endpoint(_ endpoint: DraftEndingEndpoint) -> [String: Any] {
        ["measure": endpoint.measureIndex, "fraction": endpoint.fraction,
         "system": endpoint.laneLocation.systemIndex, "laneFraction": endpoint.laneLocation.fraction]
    }

    private func nativeImage(chart: Chart, drawing: PKDrawing, chordFrame: CGRect, state: ChordPreviewState) -> UIImage {
        NotationFontRegistrar.registerBundledFontsIfNeeded()
        var rendered = chart
        _ = rendered.setPageHandwrittenChordDrawing(nil)
        let canvas = LeadSheetCanvasUIKitView(frame: CGRect(origin: .zero, size: pageSize))
        canvas.recognizesChordInk = false
        canvas.chart = rendered
        canvas.interactionMode = .chordEntry
        canvas.chordPreviewState = state
        canvas.overrideUserInterfaceStyle = .light
        canvas.setNeedsLayout()
        canvas.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: pageSize, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: pageSize))
            canvas.draw(canvas.bounds)
            drawing.image(from: CGRect(origin: .zero, size: chordFrame.size), scale: 1).draw(in: chordFrame)
        }
    }

    private func requests(_ outcome: ChordInkRecognitionPreparationOutcome) -> [ChordInkRecognitionSessionRequest] {
        if case .ready(let requests, _) = outcome { return requests }
        return []
    }

    private func outcomeName(_ outcome: ChordInkRecognitionPreparationOutcome) -> String {
        switch outcome {
        case .ready: return "ready"
        case .cancelled: return "cancelled"
        case .invalidDrawingData: return "invalidDrawingData"
        case .noVisibleStrokes: return "noVisibleStrokes"
        case .noRecognitionData: return "noRecognitionData"
        case .skippedWeakBatchTargets: return "skippedWeakBatchTargets"
        case .skippedSingleTarget: return "skippedSingleTarget"
        case .noTarget: return "noTarget"
        }
    }

    private func rect(_ rect: CGRect) -> [String: Double] {
        ["x": Double(rect.minX), "y": Double(rect.minY), "width": Double(rect.width), "height": Double(rect.height)]
    }

    private func size(_ size: CGSize) -> [String: Double] {
        ["width": Double(size.width), "height": Double(size.height)]
    }

    private func environment(_ key: String) -> String? {
        let values = ProcessInfo.processInfo.environment
        return values[key] ?? values["TEST_RUNNER_\(key)"]
    }
}
#endif
