#if canImport(UIKit)
import XCTest
import PencilKit
@testable import iChart

final class PersonalInkEvaluationCaptureTests: XCTestCase {
    func testEmptySerializationKeepsEvaluationSourceSeparateFromChartPersistence() throws {
        for capture in [false, true] {
            let result = LeadSheetInkSerialization.serialize(.init(drawing: PKDrawing(),
                normalizesPersistentInk: true, capturesSnapshot: false,
                capturesEmptyDrawingForEvaluation: capture))
            XCTAssertNil(result.serialization.drawingData, "Empty chart ink must still persist as nil")
            XCTAssertEqual(result.strokeCount, 0)
            if capture {
                let data = try XCTUnwrap(result.emptyDrawingDataForEvaluation)
                XCTAssertTrue(try PKDrawing(data: data).strokes.isEmpty)
            } else {
                XCTAssertNil(result.emptyDrawingDataForEvaluation)
            }
        }
    }

    func testUnsupportedThumbnailStillPreservesDeliveredExactInput() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = PersonalInkEvaluationStore(url: folder.appendingPathComponent("evaluation.json"))
        var chart = Chart.draft(title: "Unsupported thumbnail")
        chart.completeInitialSetup(title: "Test", key: chart.documentKey, meter: chart.defaultMeter,
                                   staffStyle: chart.staffStyle, startingMeasureCount: 4)
        let started = expectation(description: "started")
        store.start(chartID: chart.id, style: chart.layoutStyle.rawValue, phase: .beforeCorrections,
            profile: .init(), pipeline: "test") { error in XCTAssertNil(error); started.fulfill() }
        wait(for: [started], timeout: 3)
        let runID = try XCTUnwrap(store.context(chartID: chart.id)?.runID)
        let strokes = [InkStroke(points: [InkPoint(x: 140, y: 190)], creationTimeOffset: 2)]
        XCTAssertNil(PersonalInkShape(strokes: strokes))
        let now = Date()
        var payload = ChordInkRecognitionProposalPayload(requestID: UUID(),
            result: .init(rawCandidates: [], glyphCandidates: [], match: nil, confidence: 0),
            strokes: strokes, drawingData: Data(),
            target: (measureID: try XCTUnwrap(chart.measures.first?.id), fraction: 0.25),
            timing: .init(scheduledAt: now, requestedDelay: 0, recognitionStartedAt: now,
                recognitionFinishedAt: now, strokeCount: 1))
        payload.evaluationPrediction = .init(runID: runID, baseline: nil, personalized: nil,
            baselineAction: "reject", personalizedAction: "reject", knownInk: false)
        PersonalInkEvaluationCapture.record([payload], chart: chart, store: store)
        let stopped = expectation(description: "stopped")
        store.stop(runID: runID) { error in XCTAssertNil(error); stopped.fulfill() }
        wait(for: [stopped], timeout: 3)
        let record = try XCTUnwrap(PersonalInkEvaluationStore(url: folder.appendingPathComponent("evaluation.json"))
            .snapshot().journal.runs.first?.records.first)
        XCTAssertEqual(record.recognitionStrokes, strokes)
        XCTAssertTrue(record.groupingIssue)
        XCTAssertTrue(record.strokes.isEmpty)
        XCTAssertEqual(record.fingerprint, PersonalInkEvaluationStore.fingerprint(strokes: strokes))
    }

    func testSourceAdapterBindsFullLayoutAndNoReadWithoutTrainingInBothStyles() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: folder) }
            let store = PersonalInkEvaluationStore(url: folder.appendingPathComponent("evaluation.json"))
            var chart = Chart.draft(title: "Source bridge")
            chart.layoutStyle = style
            chart.completeInitialSetup(title: "Test", key: chart.documentKey, meter: chart.defaultMeter,
                                       staffStyle: chart.staffStyle, startingMeasureCount: 4)
            let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: CGSize(width: 900, height: 1_200))
            let started = expectation(description: "started")
            store.start(chartID: chart.id, style: style.rawValue, phase: .beforeCorrections,
                profile: .init(), pipeline: "test") { error in XCTAssertNil(error); started.fulfill() }
            wait(for: [started], timeout: 3)
            let context = try XCTUnwrap(store.context(chartID: chart.id))
            let requestID = UUID()
            let strokes = [InkStroke(points: [InkPoint(x: 10, y: 10), InkPoint(x: 20, y: 30)])]
            let ownership = try XCTUnwrap(ChordInkTargetOwnershipSnapshot(sourcePencilStrokeCount: 1,
                visibleFragmentSourceStrokeIndices: [0], barlineVisibleFragmentIndices: [],
                targetVisibleFragmentIndices: [[0]]))
            let source = ChordInkRecognitionPreparedSource(normalizedDrawingData: PKDrawing().dataRepresentation(),
                chordFrame: CGRect(x: 0, y: 0, width: 900, height: 1_200), pageLayout: layout,
                visibleStrokes: strokes, recognitionVisibleFragmentIndices: [0], ownership: ownership, outcome: "ready")
            store.beginSourceCapture(runID: context.runID, requestID: requestID, inkRevision: 3)
            PersonalInkEvaluationCapture.recordSource(source, requestID: requestID, inkRevision: 3,
                runID: context.runID, store: store)
            let now = Date()
            var payload = ChordInkRecognitionProposalPayload(requestID: requestID,
                result: .init(rawCandidates: [], glyphCandidates: [], match: nil, confidence: 0),
                strokes: strokes, drawingData: Data(),
                target: (measureID: try XCTUnwrap(chart.measures.first?.id), fraction: 0.25),
                timing: .init(scheduledAt: now, requestedDelay: 0, recognitionStartedAt: now,
                    recognitionFinishedAt: now, strokeCount: 1))
            payload.evaluationPrediction = .init(runID: context.runID, baseline: nil, personalized: nil,
                baselineAction: "reject", personalizedAction: "reject", knownInk: false)
            PersonalInkEvaluationCapture.record([payload], chart: chart, bindsSource: true, store: store)
            let stopped = expectation(description: "source and prediction flush")
            store.stop(runID: context.runID) { error in XCTAssertNil(error); stopped.fulfill() }
            wait(for: [stopped], timeout: 3)
            let run = try XCTUnwrap(PersonalInkEvaluationStore(url: folder.appendingPathComponent("evaluation.json"))
                .snapshot().journal.runs.first)
            let savedSource = try XCTUnwrap(run.sourceSnapshot)
            XCTAssertEqual(savedSource.visibleStrokes, strokes)
            XCTAssertEqual(savedSource.recognitionStrokes, strokes)
            XCTAssertEqual(savedSource.pages.count, layout.pages.count)
            XCTAssertEqual(savedSource.measures.count, layout.systems.flatMap(\.measures).count)
            XCTAssertEqual(savedSource.measures.map(\.measureID), layout.systems.flatMap(\.measures).map(\.id))
            XCTAssertEqual(run.sourceCaptureState, .complete)
            XCTAssertEqual(run.records.first?.sourceRequestID, requestID)
            XCTAssertEqual(run.records.first?.targetOrdinal, 0)
            XCTAssertNil(run.records.first?.baseline)
            XCTAssertEqual(run.profile, context.profile.profile)
            XCTAssertTrue(run.profile.examples.isEmpty)
        }
    }

    func testBothChartStylesSaveDeliveredNoReadAndRejectPreTestPayload() throws {
        for style in ChartLayoutStyle.v1NewChartOptions {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: folder) }
            let store = PersonalInkEvaluationStore(url: folder.appendingPathComponent("evaluation.json"))
            var chart = Chart.draft(title: "Test only")
            chart.layoutStyle = style
            chart.completeInitialSetup(title: "Test only", key: chart.documentKey, meter: chart.defaultMeter,
                                       staffStyle: chart.staffStyle, startingMeasureCount: 4)
            let measureID = try XCTUnwrap(chart.measures.first?.id)
            let started = expectation(description: "started")
            store.start(chartID: chart.id, style: style.rawValue, phase: .beforeCorrections, profile: .init(), pipeline: "test") { error in
                XCTAssertNil(error); started.fulfill()
            }
            wait(for: [started], timeout: 3)
            let runID = try XCTUnwrap(store.context(chartID: chart.id)?.runID)
            let now = Date()
            var payload = ChordInkRecognitionProposalPayload(
                requestID: UUID(), result: .init(rawCandidates: [], glyphCandidates: [], match: nil, confidence: 0),
                strokes: [InkStroke(points: [InkPoint(x: 10, y: 10), InkPoint(x: 20, y: 30)])],
                drawingData: Data(), target: (measureID: measureID, fraction: 0.25),
                timing: .init(scheduledAt: now, requestedDelay: 0, recognitionStartedAt: now, recognitionFinishedAt: now, strokeCount: 1))
            payload.result.requiresEditReview = true
            PersonalInkEvaluationCapture.record([payload], chart: chart, store: store)
            payload.evaluationPrediction = .init(runID: runID, baseline: nil, personalized: nil,
                                                  baselineAction: "reject", personalizedAction: "reject", knownInk: false,
                                                  personalArbitration: "baselineOnly", baselineRecognitionAction: "confirm")
            PersonalInkEvaluationCapture.record([payload], chart: chart, store: store)
            let stopped = expectation(description: "stopped")
            store.stop(runID: runID) { error in XCTAssertNil(error); stopped.fulfill() }
            wait(for: [stopped], timeout: 3)
            let run = try XCTUnwrap(store.snapshot().journal.runs.first)
            XCTAssertEqual(run.style, style.rawValue)
            XCTAssertEqual(run.snapshotCount, 1)
            let record = try XCTUnwrap(run.records.first)
            XCTAssertNil(record.baseline); XCTAssertNil(record.personalized)
            XCTAssertNil(record.intended)
            XCTAssertFalse(record.strokes.isEmpty)
            XCTAssertEqual(record.recognitionStrokes, payload.strokes)
            XCTAssertNotEqual(record.strokes, record.recognitionStrokes)
            let reloaded = try XCTUnwrap(PersonalInkEvaluationStore(url: folder.appendingPathComponent("evaluation.json"))
                .snapshot().journal.runs.first?.records.first)
            XCTAssertEqual(reloaded.recognitionInput, payload.strokes)
            XCTAssertEqual(reloaded.requiresEditReview, true)
            XCTAssertEqual(reloaded.baselineRecognitionAction, "confirm")
            XCTAssertEqual(reloaded.baselineEvidenceIsTrusted, false)
            XCTAssertEqual(record.measureIndex, 1)
            XCTAssertEqual(record.measureID, measureID)
            XCTAssertEqual(record.personalArbitration, "baselineOnly")
            XCTAssertEqual(record.fingerprint.count, 64)
        }
    }

    func testDenseInputIsNotReplacedByThumbnailDecimation() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = PersonalInkEvaluationStore(url: folder.appendingPathComponent("evaluation.json"))
        var chart = Chart.draft(title: "Dense input test")
        chart.completeInitialSetup(title: "Dense input test", key: chart.documentKey, meter: chart.defaultMeter,
                                   staffStyle: chart.staffStyle, startingMeasureCount: 4)
        let started = expectation(description: "started")
        store.start(chartID: chart.id, style: chart.layoutStyle.rawValue, phase: .beforeCorrections,
                    profile: .init(), pipeline: "test") { error in XCTAssertNil(error); started.fulfill() }
        wait(for: [started], timeout: 3)
        let runID = try XCTUnwrap(store.context(chartID: chart.id)?.runID)
        let points = (0..<257).map { index in
            InkPoint(x: 100 + Double(index) * 0.5, y: 200 + sin(Double(index) / 4) * 12,
                     timeOffset: Double(index) * 0.01)
        }
        let strokes = [InkStroke(points: points, creationTimeOffset: 4)]
        let now = Date()
        var payload = ChordInkRecognitionProposalPayload(
            requestID: UUID(), result: .init(rawCandidates: [], glyphCandidates: [], match: nil, confidence: 0),
            strokes: strokes, drawingData: Data(),
            target: (measureID: try XCTUnwrap(chart.measures.first?.id), fraction: 0.25),
            timing: .init(scheduledAt: now, requestedDelay: 0, recognitionStartedAt: now,
                          recognitionFinishedAt: now, strokeCount: 1))
        payload.evaluationPrediction = .init(runID: runID, baseline: nil, personalized: nil,
            baselineAction: "reject", personalizedAction: "reject", knownInk: false)
        PersonalInkEvaluationCapture.record([payload], chart: chart, store: store)
        let stopped = expectation(description: "stopped")
        store.stop(runID: runID) { error in XCTAssertNil(error); stopped.fulfill() }
        wait(for: [stopped], timeout: 3)
        let record = try XCTUnwrap(PersonalInkEvaluationStore(url: folder.appendingPathComponent("evaluation.json"))
            .snapshot().journal.runs.first?.records.first)
        XCTAssertEqual(record.recognitionInput, strokes, "Every original point, scale, offset and time must survive")
        XCTAssertLessThan(record.strokes[0].points.count, points.count, "The preview remains bounded independently")
        XCTAssertEqual(record.strokes, PersonalInkShape(strokes: strokes)?.normalizedStrokes)
    }
}
#endif
