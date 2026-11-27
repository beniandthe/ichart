#if canImport(UIKit) && canImport(PencilKit)
import Foundation
import PencilKit
import UIKit
import XCTest
@testable import iChart

/// Opt-in local diagnosis of the actual saved chart and pending source. This
/// supplies neither intended chord answers nor recorded ownership to inference.
@MainActor
final class ChordInkPartialHeightPrivateReplayTests: XCTestCase {
    func testActualSavedPendingSourceOwnershipAndReaderWithoutAnswerOracle() throws {
        guard let path = ProcessInfo.processInfo.environment["ICHART_PARTIAL_HEIGHT_REPLAY_DIR"],
              !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw XCTSkip("Supply the authorized private partial-height replay directory")
        }
        let root = URL(fileURLWithPath: path).standardizedFileURL
        let chartURL = root.appendingPathComponent("selected-chart.json")
        let pendingURL = root.appendingPathComponent("pending.pkdrawing")
        let eventURLs = try FileManager.default.contentsOfDirectory(at: root,
            includingPropertiesForKeys: nil).filter {
                $0.lastPathComponent.hasPrefix("b-event-") && $0.pathExtension == "pkdrawing"
            }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        let urls = [chartURL, pendingURL] + eventURLs
        let originalBytes = try urls.map { try Data(contentsOf: $0) }
        defer {
            for (url, bytes) in zip(urls, originalBytes) {
                XCTAssertEqual(try? Data(contentsOf: url), bytes, "Private input bytes must remain unchanged")
            }
        }
        let chart = try ChartPersistenceCoders.decoder.decode(Chart.self, from: originalBytes[0])
        let drawing = try PKDrawing(data: originalBytes[1])
        let space = try XCTUnwrap(chart.pageHandwrittenChordCoordinateSpace)
        let decodedSource = try PKDrawing(data: XCTUnwrap(chart.pageHandwrittenChordData))
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(
            expected: drawing, current: decodedSource))

        // Reconstruct the normal editor geometry, never resize the private
        // source to force a recognition or intended ownership result.
        let width = LeadSheetFreeInkDocumentLayoutPolicy.canvasWidthToRetain(
            for: chart, viewportWidth: LeadSheetFreeInkDocumentLayoutPolicy.portraitCanvasWidth)
        let logical = CGSize(width: width, height: LeadSheetFreeInkDocumentLayoutPolicy.portraitPageHeight)
        let pageSize = CGSize(width: width,
            height: EditorCanvasGeometryCache().canvasHeight(for: chart, pageSize: logical))
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize,
            includesChordInkContinuationLanes: true)
        let region = LeadSheetActiveInkScope.chordWritingRegion(for: layout)
        let geometryMatches = region.frame.size == space.size
        attach(drawing, name: "pending-original-source", rect: drawing.bounds.insetBy(dx: -12, dy: -12))
        attach(drawing, name: "pending-source-in-reconstructed-lanes",
            rect: CGRect(origin: .zero, size: space.size),
            lanes: region.inputFrames.map { $0.offsetBy(dx: -region.frame.minX, dy: -region.frame.minY) },
            labels: true)

        let prepared = ChordInkRecognitionPreparation.prepare(.init(requestID: UUID(),
            scheduledAt: .now, requestedDelay: 0, drawingData: originalBytes[1],
            chordFrame: region.frame, pageLayout: layout, flow: .draftPreview,
            options: .live, layoutStyle: chart.layoutStyle))
        let requests: [ChordInkRecognitionSessionRequest]
        let outcome: String
        switch prepared.outcome {
        case .ready(let values, _): requests = values; outcome = "ready"
        case .noRecognitionData: requests = []; outcome = "noRecognitionData"
        default: requests = []; outcome = String(describing: prepared.outcome)
        }
        let recognizer = ChordInkMaximumTrustRecognizer()
        var targetReports: [[String: Any]] = []
        for (ordinal, request) in requests.enumerated() {
            let targetDrawing = try PKDrawing(data: request.drawingData)
            let result = recognizer.recognize(strokes: request.strokes, options: .live)
            targetReports.append([
                "ordinal": ordinal, "sourceStrokeCount": targetDrawing.strokes.count,
                "readerStrokeCount": request.strokes.count, "measureID": request.target.measureID.uuidString,
                "fraction": request.target.fraction, "lane": request.laneLocation.map { $0.systemIndex } as Any? ?? NSNull(),
                "match": result.match?.displayText as Any? ?? NSNull(),
                "action": ChordInkRecognitionPolicy.decision(for: result).action.rawValue,
                "bounds": rect(targetDrawing.bounds),
                "sourceStrokeIndicesByExactVisibleIdentity": exactSourceIndices(of: targetDrawing, in: drawing)
            ])
            attach(targetDrawing, name: "pending-target-\(ordinal)-\(result.match?.displayText ?? "unread")",
                rect: targetDrawing.bounds.insetBy(dx: -12, dy: -12))
        }
        var historical: [[String: Any]] = []
        for (index, url) in eventURLs.enumerated() {
            let source = try PKDrawing(data: originalBytes[index + 2])
            let result = recognizer.recognize(strokes: PencilKitInkAdapter.inkStrokes(from: source), options: .live)
            historical.append(["file": url.lastPathComponent, "sourceStrokeCount": source.strokes.count,
                "match": result.match?.displayText as Any? ?? NSNull(),
                "action": ChordInkRecognitionPolicy.decision(for: result).action.rawValue,
                "bounds": rect(source.bounds), "expectedAnswerKnown": false])
            attach(source, name: url.deletingPathExtension().lastPathComponent,
                rect: source.bounds.insetBy(dx: -12, dy: -12))
        }
        let report: [String: Any] = [
            "scope": "actual-saved-source-local-diagnostic-not-fresh-Pencil-or-accuracy-proof",
            "pipeline": ChordInkRecognitionPipelineIdentity.version,
            "chartID": chart.id.uuidString, "layoutStyle": chart.layoutStyle.rawValue,
            "expectedAnswerKnown": false, "sourceBytesEdited": false,
            "sourceStrokeCount": drawing.strokes.count, "sourceBounds": rect(drawing.bounds),
            "savedSourceSize": [space.width, space.height], "pageSize": [pageSize.width, pageSize.height],
            "chordFrame": rect(region.frame), "geometryMatchesSavedRegistration": geometryMatches,
            "lanes": region.inputFrames.map(rect),
            "preparationOutcome": outcome, "recognitionStrokeCount": prepared.recognitionStrokeCount,
            "ownership": try prepared.ownershipSnapshot.map(jsonObject) as Any? ?? NSNull(),
            "barlines": prepared.barlines.map { bar in
                ["kind": String(describing: bar.kind), "sourceIndices": bar.ownedSourceStrokeIndices.sorted(),
                 "measureID": bar.measureID.uuidString, "fraction": bar.fraction,
                 "renderable": bar.isRenderable, "ambiguity": String(describing: bar.ambiguity)] as [String: Any]
            },
            "endingsCount": prepared.endings.count, "targets": targetReports,
            "sourceStrokes": drawing.strokes.enumerated().map { index, stroke in
                ["index": index, "pointCount": stroke.path.count, "bounds": rect(stroke.renderBounds)] as [String: Any]
            },
            "historicalRenderedSourceDiagnostics": historical
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
        print("PARTIAL_HEIGHT_PRIVATE_REPLAY \(String(decoding: data, as: UTF8.self))")
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "partial-height-private-replay-report"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertTrue(geometryMatches,
            "Ownership is actual-context evidence only if the normal editor layout exactly matches saved source registration")
    }

    /// The separate diagnostic above has no answer oracle. This regression
    /// records the source partition and labels reviewed after that inference;
    /// these expectations never enter preparation, recognition, or draft text.
    func testReviewedActualPendingSourceRendersClearsAndReopensWithoutChangingOriginalEvents() throws {
        guard let path = ProcessInfo.processInfo.environment["ICHART_PARTIAL_HEIGHT_REPLAY_DIR"],
              !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw XCTSkip("Supply the authorized private partial-height replay directory")
        }
        let root = URL(fileURLWithPath: path).standardizedFileURL
        let urls = [root.appendingPathComponent("selected-chart.json"), root.appendingPathComponent("pending.pkdrawing")]
        let originalBytes = try urls.map { try Data(contentsOf: $0) }
        defer {
            for (url, bytes) in zip(urls, originalBytes) {
                XCTAssertEqual(try? Data(contentsOf: url), bytes, "Reviewed private input must remain unchanged")
            }
        }
        let chart = try ChartPersistenceCoders.decoder.decode(Chart.self, from: originalBytes[0])
        let source = try PKDrawing(data: originalBytes[1])
        let sourceBytes = source.dataRepresentation()
        let space = try XCTUnwrap(chart.pageHandwrittenChordCoordinateSpace)
        let width = LeadSheetFreeInkDocumentLayoutPolicy.canvasWidthToRetain(
            for: chart, viewportWidth: LeadSheetFreeInkDocumentLayoutPolicy.portraitCanvasWidth)
        let logical = CGSize(width: width, height: LeadSheetFreeInkDocumentLayoutPolicy.portraitPageHeight)
        let size = CGSize(width: width,
            height: EditorCanvasGeometryCache().canvasHeight(for: chart, pageSize: logical))
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: size,
            includesChordInkContinuationLanes: true)
        let region = LeadSheetActiveInkScope.chordWritingRegion(for: layout)
        XCTAssertEqual(region.frame.size, space.size)
        let prepared = ChordInkRecognitionPreparation.prepare(.init(requestID: UUID(), scheduledAt: .now,
            requestedDelay: 0, drawingData: originalBytes[1], chordFrame: region.frame,
            pageLayout: layout, flow: .draftPreview, options: .live, layoutStyle: chart.layoutStyle))
        guard case .ready(let requests, _) = prepared.outcome else {
            XCTFail("The actual reviewed source must produce real chord targets")
            return
        }
        let recognizer = ChordInkMaximumTrustRecognizer()
        var labels: [String] = []
        var inputs: [ChordInkDraftInput] = []
        for request in requests {
            let result = recognizer.recognize(strokes: request.strokes, options: .live)
            labels.append(result.match?.displayText ?? "unread")
            let resolution = ChordInkRenderResolutionPolicy.resolution(for: result,
                drawingData: request.drawingData, correctionMemory: .init())
            inputs.append(ChordInkDraftInput(measureID: request.target.measureID,
                measureIndex: try XCTUnwrap(chart.measure(id: request.target.measureID)).index,
                targetFraction: request.target.fraction, visualOrder: request.visualOrder,
                laneLocation: request.laneLocation, layoutPageSize: request.layoutPageSize,
                drawingData: request.drawingData, candidateTexts: resolution.candidateTexts,
                bestCandidateText: resolution.bestCandidateText, confidence: result.confidence,
                strokeCount: request.strokes.count, recognitionResult: result,
                primaryDecision: resolution.primaryDecision, recognitionDecision: resolution.decision,
                targetLifecycle: try XCTUnwrap(request.collectingTargetLifecycle.advanced(to: .stable)),
                requiresManualReviewOnly: request.requiresManualReviewOnly))
        }
        // Reviewed expectations are checked only after all real inference and
        // source-owned inputs have been constructed without expected answers.
        XCTAssertEqual(labels, ["Db9", "E"])
        let actualSourceGroups = try requests.map {
            exactSourceIndices(of: try PKDrawing(data: $0.drawingData), in: source)
        }
        XCTAssertEqual(actualSourceGroups, [[1, 2, 3, 4], [6, 7, 8]])
        XCTAssertEqual(Set(prepared.barlines.flatMap(\.ownedSourceStrokeIndices)), [0, 5])
        XCTAssertEqual(prepared.barlines.map(\.kind), [.single, .single])
        XCTAssertTrue(prepared.endings.isEmpty)
        var state = ChordPreviewState(draftBarlines: prepared.barlines, layoutPageSize: size)
        state.replaceDraftChords(with: inputs)
        XCTAssertTrue(state.draftChords.allSatisfy { $0.selectedText == nil })
        XCTAssertEqual(state.draftChords.compactMap(ChordInkAutomaticRenderPolicy.automaticCandidateText), ["Db9", "E"])
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart, state: state),
            "All nine source strokes must be owned; no unrepresented ink may be cleared")
        let originalEvents = chart.measures.flatMap(\.chordEvents)
        XCTAssertEqual(originalEvents.count, 8)
        let originalIDs = Set(originalEvents.map(\.id))
        let structuralIndices = Set(prepared.barlines.flatMap(\.ownedSourceStrokeIndices))
        let chordIndices = Set(source.strokes.indices).subtracting(structuralIndices)
        let structuralSource = PKDrawing(strokes: structuralIndices.sorted().map { source.strokes[$0] })
        let structuralState = ChordPreviewState(draftBarlines:
            ChordDraftBarlineDeletionPolicy.remappingSourceIndices(prepared.barlines, afterRemoving: chordIndices),
            layoutPageSize: size)
        var reports: [[String: Any]] = []
        for automatic in [true, false] {
            // The accepted structural split/downbeat behavior is the control
            // for existing events; a requested split can legitimately change
            // their owning measure and timing without changing their music.
            let structureOnly = ChordInkDraftRenderCoordinator.prepare(chart: chart, state: structuralState,
                currentDrawing: structuralSource, coordinateSpace: space,
                automaticContinuationSourceLayout: automatic ? layout : nil)
            XCTAssertTrue(structureOnly.canConsumeSource)
            let outcome: ChordInkDraftRenderCoordinator.Outcome
            if automatic {
                let inputAt = Date(timeIntervalSinceReferenceDate: 1_000)
                let attempt = ChordInkDraftRenderCoordinator.prepareAutomaticAttempt(chart: chart, state: state,
                    currentDrawing: source, coordinateSpace: space, now: inputAt.addingTimeInterval(10),
                    lastInputAt: inputAt, isUsingTool: false,
                    sourcePageLayout: layout, sourceChordFrame: region.frame)
                let automaticOutcome = try XCTUnwrap(attempt.outcome, "Feedback: \(attempt.feedback)")
                XCTAssertTrue(automaticOutcome.drawing.strokes.isEmpty)
                XCTAssertTrue(automaticOutcome.remainingState.isEmpty)
                outcome = ChordInkDraftRenderCoordinator.explicitOutcome(automaticOutcome)
            } else {
                outcome = ChordInkDraftRenderCoordinator.prepareManual(chart: chart, state: state,
                    currentDrawing: source, coordinateSpace: space,
                    sourcePageLayout: layout, sourceChordFrame: region.frame)
            }
            XCTAssertTrue(outcome.canConsumeSource)
            XCTAssertEqual(outcome.result.renderedChordCount, 2)
            XCTAssertEqual(outcome.result.renderedBarlineCount, 2)
            XCTAssertFalse(outcome.result.didRejectIncompleteSourceCoverage)
            XCTAssertTrue(outcome.result.unresolvedDraftIDs.isEmpty)
            XCTAssertNil(outcome.retainedDraft)
            XCTAssertNil(outcome.chart.pageHandwrittenChordData)
            XCTAssertNil(outcome.chart.pageHandwrittenChordCoordinateSpace)
            let afterEvents = outcome.chart.measures.flatMap(\.chordEvents)
            XCTAssertEqual(afterEvents.count, originalEvents.count + 2)
            XCTAssertTrue(originalIDs.isSubset(of: Set(afterEvents.map(\.id))))
            for original in originalEvents {
                let event = try XCTUnwrap(outcome.chart.chordEvent(id: original.id))
                let splitControl = try XCTUnwrap(structureOnly.chart.chordEvent(id: original.id))
                XCTAssertEqual(event.symbol, original.symbol)
                XCTAssertEqual(event.rawInput, original.rawInput)
                XCTAssertEqual(event.sourceInkData, original.sourceInkData)
                XCTAssertEqual(event.sourceCandidateSignature, original.sourceCandidateSignature)
                XCTAssertEqual(event.sourceRecognitionPipelineVersion, original.sourceRecognitionPipelineVersion)
                XCTAssertEqual(event.spellingIntent, original.spellingIntent)
                XCTAssertEqual(event.spellingOverrideSource, original.spellingOverrideSource)
                XCTAssertEqual(event.spellingOverrideKey, original.spellingOverrideKey)
                XCTAssertEqual(event.startPosition, splitControl.startPosition)
                XCTAssertEqual(event.duration, splitControl.duration)
                XCTAssertEqual(event.rhythmPlacement, splitControl.rhythmPlacement)
                XCTAssertEqual(event.mappedRhythmSlotIndex, splitControl.mappedRhythmSlotIndex)
                XCTAssertEqual(event.anchorsToMeasureStart, splitControl.anchorsToMeasureStart)
                XCTAssertEqual(event.tieOut, original.tieOut)
                XCTAssertEqual(event.hitStyle, original.hitStyle)
                XCTAssertEqual(event.manualDisplayWidth, original.manualDisplayWidth)
                XCTAssertEqual(event.manualHorizontalScale, original.manualHorizontalScale)
            }
            XCTAssertEqual(outcome.chart.cueTexts, chart.cueTexts)
            XCTAssertEqual(outcome.chart.roadmapObjects, chart.roadmapObjects)
            XCTAssertEqual(outcome.chart.sectionLabels, chart.sectionLabels)
            XCTAssertEqual(outcome.chart.pageHandwrittenNotationData, chart.pageHandwrittenNotationData)
            XCTAssertEqual(outcome.chart.pageHandwrittenHeaderData, chart.pageHandwrittenHeaderData)
            XCTAssertEqual(outcome.chart.freeInkArticulations, chart.freeInkArticulations)
            var archivedSources: [PKStroke] = []
            var newEventReports: [[String: Any]] = []
            for (index, eventID) in outcome.result.renderedChordIDs.enumerated() {
                let event = try XCTUnwrap(outcome.chart.chordEvent(id: eventID))
                let archive = try PKDrawing(data: XCTUnwrap(event.sourceInkData))
                let requestSource = try PKDrawing(data: requests[index].drawingData)
                XCTAssertEqual(event.symbol.displayText, labels[index])
                XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: requestSource, current: archive))
                archivedSources += archive.strokes
                let owner = try XCTUnwrap(outcome.chart.measures.first { $0.chordEvents.contains { $0.id == eventID } })
                let paper = try XCTUnwrap(owner.paperLayout)
                let lane = try XCTUnwrap(requests[index].laneLocation)
                XCTAssertEqual(paper.rowIndex, lane.systemIndex)
                XCTAssertGreaterThanOrEqual(lane.fraction, paper.startFraction - 0.0001)
                XCTAssertLessThanOrEqual(lane.fraction, paper.endFraction + 0.0001)
                newEventReports.append(["id": eventID.uuidString, "label": event.symbol.displayText,
                    "measureID": owner.id.uuidString, "row": paper.rowIndex,
                    "measureStartFraction": paper.startFraction, "measureEndFraction": paper.endFraction,
                    "sourceFraction": lane.fraction, "archivedStrokeCount": archive.strokes.count])
            }
            let expectedChordSource = PKDrawing(strokes: chordIndices.sorted().map { source.strokes[$0] })
            XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(
                expected: expectedChordSource, current: PKDrawing(strokes: archivedSources)))
            for bar in prepared.barlines {
                let lane = try XCTUnwrap(bar.laneLocation)
                let measures = outcome.chart.measures.filter { $0.paperLayout?.rowIndex == lane.systemIndex }
                let sourceLane = try XCTUnwrap(layout.systems.first { $0.index == lane.systemIndex })
                let sourceLaneFrame = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingSystemLaneFrame(
                    for: sourceLane, paperFrame: layout.paperFrame(for: sourceLane)))
                let tolerance = (6 + bar.metrics.width / 2) / max(1, Double(sourceLaneFrame.width))
                XCTAssertTrue(measures.contains { measure in
                    guard let paper = measure.paperLayout else { return false }
                    return abs(paper.endFraction - lane.fraction) <= tolerance
                        || (paper.leadingBarline != nil && abs(paper.startFraction - lane.fraction) <= tolerance)
                }, "Each consumed source bar must have a rendered boundary at its source position")
            }
            let reopened = try ChartPersistenceCoders.decoder.decode(Chart.self,
                from: ChartPersistenceCoders.encoder.encode(outcome.chart))
            XCTAssertEqual(reopened, outcome.chart)
            XCTAssertNil(reopened.pageHandwrittenChordData)
            for eventID in outcome.result.renderedChordIDs {
                XCTAssertEqual(reopened.chordEvent(id: eventID)?.sourceInkData,
                    outcome.chart.chordEvent(id: eventID)?.sourceInkData)
            }
            reports.append(["mode": automatic ? "Automatic" : "Manual Render with Preview",
                "originalEventsPreserved": originalEvents.count, "newEvents": newEventReports,
                "renderedSeparators": outcome.result.renderedBarlineCount,
                "archivedChordStrokeCount": archivedSources.count,
                "structurallyConsumedBarStrokeCount": structuralIndices.count,
                "pendingCleared": reopened.pageHandwrittenChordData == nil,
                "scope": "component transaction and persistence, not physical gesture coverage"])
        }
        XCTAssertEqual(source.dataRepresentation(), sourceBytes)
        let reportData = try JSONSerialization.data(withJSONObject: reports, options: [.sortedKeys])
        print("PARTIAL_HEIGHT_REVIEWED_RENDER \(String(decoding: reportData, as: UTF8.self))")
        let attachment = XCTAttachment(data: reportData, uniformTypeIdentifier: "public.json")
        attachment.name = "partial-height-reviewed-render-preservation-report"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func exactSourceIndices(of target: PKDrawing, in drawing: PKDrawing) -> [Int] {
        drawing.strokes.indices.filter { index in
            let source = PKDrawing(strokes: [drawing.strokes[index]])
            return ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: source, current: target)
                || ChordInkDraftSourceCoveragePolicy.addedVisibleStrokes(in: target, after: source) != nil
        }
    }

    private func jsonObject<T: Encodable>(_ value: T) throws -> Any {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value))
    }

    private func rect(_ value: CGRect) -> [String: Double] {
        ["x": value.minX, "y": value.minY, "width": value.width, "height": value.height]
    }

    private func attach(_ drawing: PKDrawing, name: String, rect: CGRect,
        lanes: [CGRect] = [], labels: Bool = false) {
        guard !rect.isNull, rect.width > 0, rect.height > 0 else { return }
        let scale = min(2, 1_400 / max(rect.width, rect.height))
        let size = CGSize(width: rect.width * scale, height: rect.height * scale)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            context.cgContext.scaleBy(x: scale, y: scale)
            context.cgContext.translateBy(x: -rect.minX, y: -rect.minY)
            for lane in lanes {
                UIColor.systemBlue.withAlphaComponent(0.08).setFill()
                context.cgContext.fill(lane)
                UIColor.systemBlue.withAlphaComponent(0.35).setStroke()
                context.cgContext.stroke(lane)
            }
            drawing.image(from: rect, scale: 2).draw(in: rect)
            if labels {
                for (index, stroke) in drawing.strokes.enumerated() {
                    "\(index)".draw(at: CGPoint(x: stroke.renderBounds.minX, y: stroke.renderBounds.minY - 13),
                        withAttributes: [.font: UIFont.boldSystemFont(ofSize: 12), .foregroundColor: UIColor.systemRed])
                }
            }
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
#endif
