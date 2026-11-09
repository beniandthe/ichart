#if canImport(UIKit) && canImport(PencilKit)
import Foundation
import PencilKit
import UIKit
import XCTest
@testable import iChart

/// Measures the real whole-drawing work upstream of incremental recognition.
/// These synthetic timings are diagnostics, not physical writing cadence or
/// recognizer-accuracy acceptance, and no wall-clock threshold gates the test.
@MainActor
final class ChordInkPreparationCadenceTests: XCTestCase {
    func testGrowingSimpleDrawingSerializationAndPreparationCost() throws {
        try recordGrowingDrawingCost(style: .simpleChordSheet)
    }

    func testGrowingRhythmDrawingSerializationAndPreparationCost() throws {
        try recordGrowingDrawingCost(style: .rhythmSectionSheet)
    }

    func testCancelledWholeDrawingCensusesNeedAFreshRevisionAfterBlockedWorkerResumes() async throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            let fixture = try makeFixture(style: style)
            let queue = DispatchQueue(label: "ichart.tests.preparation-cadence.contention")
            let session = ChordInkRecognitionPreparationSession(queue: queue)
            let obsolete = expectation(description: "Obsolete whole-drawing census is never published")
            obsolete.isInverted = true

            // Inject worker contention deterministically. This models a stage
            // whose work cannot finish before another input revision replaces
            // it; it does not assert that ordinary preparation is this slow.
            queue.suspend()
            var remainsSuspended = true
            defer { if remainsSuspended { queue.resume() } }
            for targetCount in 1...3 {
                let request = try preparationRequest(fixture, targetCount: targetCount)
                session.start(request: request) { _ in obsolete.fulfill() }
                session.cancelPendingWork()
            }
            queue.resume()
            remainsSuspended = false
            await fulfillment(of: [obsolete], timeout: 0.15)

            let current = try preparationRequest(fixture, targetCount: 3)
            let delivered = expectation(description: "Fresh current whole-drawing census publishes after contention")
            var deliveries = 0
            session.start(request: current) { result in
                XCTAssertTrue(Thread.isMainThread)
                XCTAssertEqual(result.requestID, current.requestID)
                XCTAssertEqual(result.sourceStrokeCount, 9)
                XCTAssertGreaterThan(result.visibleStrokeCount, 0)
                deliveries += 1
                delivered.fulfill()
            }
            await fulfillment(of: [delivered], timeout: 5)
            XCTAssertEqual(deliveries, 1)
            try record([
                "layoutStyle": style.rawValue,
                "injectedWorkerContention": true,
                "cancelledWholeDrawingRequests": 3,
                "stalePublications": 0,
                "freshPublications": deliveries
            ], name: "preparation-contention-\(style.rawValue)")
        }
    }

    private struct Fixture {
        let style: ChartLayoutStyle
        let layout: LeadSheetPageLayout
        let chordFrame: CGRect
        let targetStrokes: [[PKStroke]]
    }

    private func recordGrowingDrawingCost(style: ChartLayoutStyle) throws {
        let fixture = try makeFixture(style: style)
        for targetCount in [1, 2, 4, 8, 16, 32] {
            let drawing = PKDrawing(strokes: fixture.targetStrokes.prefix(targetCount).flatMap { $0 })
            var serializationTimes: [Double] = []
            var preparationTimes: [Double] = []
            var totalTimes: [Double] = []
            var archiveByteCount = 0
            var targetCounts: [Int] = []
            var visibleCounts: [Int] = []
            var outcomes: [String] = []

            for _ in 0..<3 {
                let startedAt = ProcessInfo.processInfo.systemUptime
                let serialized = LeadSheetInkSerialization.serialize(.init(
                    drawing: drawing, normalizesPersistentInk: true,
                    capturesSnapshot: false, knownStrokeCount: drawing.strokes.count))
                let data = try XCTUnwrap(serialized.serialization.drawingData)
                let request = request(fixture, data: data)
                let prepared = ChordInkRecognitionPreparation.prepare(request)
                totalTimes.append((ProcessInfo.processInfo.systemUptime - startedAt) * 1_000)
                serializationTimes.append(serialized.durationMilliseconds)
                preparationTimes.append(prepared.durationMilliseconds)
                archiveByteCount = data.count
                XCTAssertEqual(serialized.strokeCount, targetCount * 3)
                XCTAssertEqual(prepared.sourceStrokeCount, targetCount * 3)
                XCTAssertGreaterThan(prepared.visibleStrokeCount, 0)
                XCTAssertTrue(serialized.durationMilliseconds.isFinite)
                XCTAssertTrue(prepared.durationMilliseconds.isFinite)
                visibleCounts.append(prepared.visibleStrokeCount)
                switch prepared.outcome {
                case .ready(let targets, _):
                    targetCounts.append(targets.count)
                    outcomes.append("ready")
                case .cancelled: XCTFail("Synchronous diagnostic preparation was not cancelled")
                case .invalidDrawingData: XCTFail("The actual serialized fixture must decode")
                case .noVisibleStrokes: XCTFail("Fixture strokes must remain inside actual writing lanes")
                case .noRecognitionData: outcomes.append("noRecognitionData")
                case .skippedWeakBatchTargets: outcomes.append("skippedWeakBatchTargets")
                case .skippedSingleTarget: outcomes.append("skippedSingleTarget")
                case .noTarget: outcomes.append("noTarget")
                }
            }
            let sortedTotals = totalTimes.sorted()
            try record([
                "layoutStyle": style.rawValue,
                "syntheticTargetCount": targetCount,
                "strokeCount": targetCount * 3,
                "archiveByteCount": archiveByteCount,
                "sampleCount": totalTimes.count,
                "serializationMedianMilliseconds": serializationTimes.sorted()[1],
                "preparationMedianMilliseconds": preparationTimes.sorted()[1],
                "combinedMedianMilliseconds": sortedTotals[1],
                "combinedMaximumMilliseconds": sortedTotals.last!,
                "samplesExceeding50Milliseconds": totalTimes.filter { $0 > 50 }.count,
                "samplesExceeding100Milliseconds": totalTimes.filter { $0 > 100 }.count,
                "samplesExceeding200Milliseconds": totalTimes.filter { $0 > 200 }.count,
                "preparedTargetCounts": targetCounts,
                "visibleStrokeCounts": visibleCounts,
                "preparationOutcomes": outcomes
            ], name: "preparation-cost-\(style.rawValue)-\(targetCount)")
        }
    }

    private func preparationRequest(_ fixture: Fixture, targetCount: Int) throws -> ChordInkRecognitionPreparationRequest {
        let drawing = PKDrawing(strokes: fixture.targetStrokes.prefix(targetCount).flatMap { $0 })
        let serialized = LeadSheetInkSerialization.serialize(.init(drawing: drawing,
            normalizesPersistentInk: true, capturesSnapshot: false,
            knownStrokeCount: drawing.strokes.count))
        return request(fixture, data: try XCTUnwrap(serialized.serialization.drawingData))
    }

    private func request(_ fixture: Fixture, data: Data) -> ChordInkRecognitionPreparationRequest {
        .init(requestID: UUID(), scheduledAt: Date(), requestedDelay: 0,
            drawingData: data, chordFrame: fixture.chordFrame, pageLayout: fixture.layout,
            flow: .draftPreview, options: .live, layoutStyle: fixture.style)
    }

    private func makeFixture(style: ChartLayoutStyle) throws -> Fixture {
        var chart = Chart.blank(title: "Preparation cadence diagnostic", measureCount: 32, layoutStyle: style)
        for systemIndex in chart.systems.indices {
            for measureIndex in chart.systems[systemIndex].measures.indices {
                chart.systems[systemIndex].measures[measureIndex].authoringState = .committed
            }
        }
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart,
            pageSize: CGSize(width: 932, height: 2_600))
        let frame = LeadSheetActiveInkScope.chordWritingFrame(for: layout)
        var targets: [[PKStroke]] = []
        for system in layout.systems {
            let lane = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingSystemLaneFrame(
                for: system, paperFrame: layout.paperFrame(for: system)))
            for measure in system.measures where measure.sourceMeasureID != nil {
                let height = min(26, lane.height - 8)
                let width = min(20, measure.chordWritingFrame.width - 12)
                XCTAssertGreaterThan(height, 8)
                XCTAssertGreaterThan(width, 6)
                let origin = CGPoint(x: measure.chordWritingFrame.minX + 7 - frame.minX,
                    y: lane.midY - height / 2 - frame.minY)
                let seed = targets.count * 3
                targets.append([
                    stroke([origin, CGPoint(x: origin.x, y: origin.y + height)], seed: seed),
                    stroke([origin, CGPoint(x: origin.x + width, y: origin.y)], seed: seed + 1),
                    stroke([CGPoint(x: origin.x, y: origin.y + height / 2),
                            CGPoint(x: origin.x + width * 0.75, y: origin.y + height / 2)], seed: seed + 2)
                ])
            }
        }
        XCTAssertEqual(targets.count, 32)
        return Fixture(style: style, layout: layout, chordFrame: frame, targetStrokes: targets)
    }

    private func stroke(_ locations: [CGPoint], seed: Int) -> PKStroke {
        let points = locations.enumerated().map { index, location in
            PKStrokePoint(location: location, timeOffset: Double(index) * 0.06,
                size: CGSize(width: 3, height: 3), opacity: 1, force: 0.5, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: .black),
            path: PKStrokePath(controlPoints: points,
                creationDate: Date(timeIntervalSinceReferenceDate: Double(seed))),
            transform: .identity, mask: nil, randomSeed: UInt32(seed))
    }

    private func record(_ value: [String: Any], name: String) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        print("chord_preparation_cadence_diagnostic \(String(decoding: data, as: UTF8.self))")
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
#endif
