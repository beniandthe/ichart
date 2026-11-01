#if canImport(UIKit) && canImport(PencilKit)
import CoreGraphics
import XCTest
@testable import iChart

@MainActor
final class ChordInkRenderGeometryTelemetryTests: XCTestCase {
    private typealias Telemetry = ChordInkRenderGeometryTelemetry
    private let measureID = UUID()
    private let existingChordID = UUID()
    private let newChordID = UUID()

    func testCommittedGeometryPreservesTheOutgoingRowAndCreatesCoverage() throws {
        let before = snapshot()
        var after = before
        after.glyphs.append(glyph(newChordID, x: 300))
        let check = try XCTUnwrap(assess(before, after))
        XCTAssertEqual(check.outcome, "passed")
        XCTAssertEqual(check.reason, "render_geometry_preserved")
        XCTAssertEqual(check.expectedCount, 1)
        XCTAssertEqual(check.actualCount, 1)
        XCTAssertEqual(check.contentMatches, true)
    }

    func testOutgoingPaperFrameCompressionIsACommittedGeometryViolation() throws {
        let before = snapshot()
        var after = before
        after.measures[0].paperFrame.size.width /= 4
        let check = try XCTUnwrap(assess(before, after))
        XCTAssertEqual(check.reason, "render_prior_geometry_changed")
        XCTAssertEqual(check.outcome, "violated")
        XCTAssertEqual(check.expectedCount, 1)
        XCTAssertEqual(check.actualCount, 0)
        XCTAssertEqual(check.contentMatches, false)
    }

    func testChordBandShiftIsDetectedEvenWhenThePaperFrameIsUnchanged() throws {
        let before = snapshot()
        var after = before
        after.measures[0].chordBandFrame.origin.x += 8
        XCTAssertEqual(try XCTUnwrap(assess(before, after)).reason, "render_prior_geometry_changed")
    }

    func testFrameToleranceMatchesTheProductionPlacementAndContinuationGuards() throws {
        let before = snapshot()
        var tolerated = before
        tolerated.measures[0].paperFrame.origin.x += 0.009
        tolerated.measures[0].chordBandFrame.size.width += 0.009
        XCTAssertEqual(try XCTUnwrap(assess(before, tolerated)).outcome, "passed")
        var changed = before
        changed.measures[0].paperFrame.size.width += 0.011
        XCTAssertEqual(try XCTUnwrap(assess(before, changed)).reason, "render_prior_geometry_changed")
    }

    func testCoordinateConfigurationPageAndStructuralChangesAreUnknownRatherThanFailures() {
        let before = snapshot()
        var changed = before
        changed.coordinateEpoch += 1
        XCTAssertNil(assess(before, changed))
        changed = before; changed.configurationEpoch += 1
        XCTAssertNil(assess(before, changed))
        changed = before; changed.pageSize.width += 1
        XCTAssertNil(assess(before, changed))
        XCTAssertNil(Telemetry.assessment(before: before, after: before,
            preservedMeasureIDs: [measureID], renderedChordIDs: [], isCommitted: false))
        XCTAssertNil(Telemetry.assessment(before: before, after: before,
            preservedMeasureIDs: [measureID], renderedChordIDs: [], isCommitted: true,
            hasIntentionalStructuralChange: true))
    }

    func testDeletedOrDuplicateRequiredMeasureIdentityCannotBecomeInventedZeroGeometry() {
        let before = snapshot()
        var missing = before; missing.measures = []
        XCTAssertNil(assess(before, missing))
        var duplicate = before; duplicate.measures.append(duplicate.measures[0])
        XCTAssertNil(assess(before, duplicate))
        XCTAssertNil(Telemetry.assessment(before: before, after: before,
            preservedMeasureIDs: [], renderedChordIDs: [], isCommitted: true))
    }

    func testMissingOrDuplicateRenderedGlyphIdentityIsUnknown() {
        let before = snapshot()
        XCTAssertNil(Telemetry.assessment(before: before, after: before,
            preservedMeasureIDs: [measureID], renderedChordIDs: [newChordID], isCommitted: true))
        var duplicate = before; duplicate.glyphs.append(duplicate.glyphs[0])
        XCTAssertNil(assess(before, duplicate))
    }

    func testInvalidGeometryIsUnknownAndNeverProducesAFalseOverlap() {
        let before = snapshot()
        var changed = before; changed.pageSize.width = .infinity
        XCTAssertNil(assess(before, changed))
        changed = before; changed.measures[0].paperFrame = .null
        XCTAssertNil(assess(before, changed))
        changed = before; changed.glyphs[0].naturalFrame = .infinite
        XCTAssertNil(assess(before, changed))
        changed = before; changed.retainedInkFrames = [.zero]
        XCTAssertNil(assess(before, changed))
        XCTAssertFalse(Telemetry.overlaps(.null, CGRect(x: 0, y: 0, width: 20, height: 20)))
    }

    func testNewGlyphCollisionWithRetainedInkIsAnObservedGeometryViolation() throws {
        let before = snapshot()
        var after = before
        after.glyphs.append(glyph(newChordID, x: 300))
        after.retainedInkFrames = [CGRect(x: 305, y: 40, width: 20, height: 20)]
        let check = try XCTUnwrap(assess(before, after))
        XCTAssertEqual(check.reason, "render_new_overlap")
        XCTAssertEqual(check.outcome, "violated")
        XCTAssertEqual(check.expectedCount, 0)
        XCTAssertEqual(check.actualCount, 1)
        XCTAssertEqual(check.contentMatches, false)
    }

    func testChangedExistingGlyphCollisionWithRetainedInkIsDetected() throws {
        let before = snapshot()
        var after = before
        after.glyphs[0] = glyph(existingChordID, x: 300)
        after.retainedInkFrames = [CGRect(x: 305, y: 40, width: 20, height: 20)]
        XCTAssertEqual(try XCTUnwrap(assess(before, after)).reason, "render_new_overlap")
    }

    func testUnchangedPreexistingGlyphAndInkOverlapsDoNotBecomeANewOperationFailure() throws {
        var before = snapshot()
        before.retainedInkFrames = [CGRect(x: 105, y: 40, width: 20, height: 20)]
        before.glyphs.append(glyph(UUID(), x: 105))
        var after = before
        after.glyphs.append(glyph(newChordID, x: 500))
        XCTAssertEqual(try XCTUnwrap(assess(before, after)).outcome, "passed")
    }

    func testNewGlyphPairCollisionIsCountedOnceRatherThanTwice() throws {
        let before = snapshot()
        let otherNewID = UUID()
        var after = before
        after.glyphs += [glyph(newChordID, x: 300), glyph(otherNewID, x: 310)]
        let check = try XCTUnwrap(Telemetry.assessment(before: before, after: after,
            preservedMeasureIDs: [measureID], renderedChordIDs: [newChordID, otherNewID], isCommitted: true))
        XCTAssertEqual(check.reason, "render_new_overlap")
        XCTAssertEqual(check.actualCount, 1)
    }

    func testChangedExistingGlyphCannotOverlapAnotherUnchangedExistingGlyph() throws {
        var before = snapshot()
        let neighbor = UUID()
        before.glyphs.append(glyph(neighbor, x: 400))
        var after = before; after.glyphs[0] = glyph(existingChordID, x: 405)
        XCTAssertEqual(try XCTUnwrap(assess(before, after)).reason, "render_new_overlap")
    }

    func testOverlapToleranceMatchesTheProductionGuard() {
        let frame = CGRect(x: 0, y: 0, width: 10, height: 10)
        XCTAssertTrue(Telemetry.overlaps(frame, CGRect(x: 10.4, y: 0, width: 10, height: 10)))
        XCTAssertFalse(Telemetry.overlaps(frame, CGRect(x: 10.5, y: 0, width: 10, height: 10)))
        XCTAssertFalse(Telemetry.overlaps(frame, CGRect(x: 0, y: 10.5, width: 10, height: 10)))
    }

    func testOneCommittedOperationCanExposeRowContinuityAndOverlapSeparately() throws {
        let before = snapshot()
        var after = before
        after.measures[0].paperFrame.size.width = 180
        after.glyphs.append(glyph(newChordID, x: 300))
        after.retainedInkFrames = [CGRect(x: 305, y: 40, width: 20, height: 20)]
        let checks = try XCTUnwrap(Telemetry.assessments(before: before, after: after,
            preservedMeasureIDs: [measureID], renderedChordIDs: [newChordID], isCommitted: true))
        XCTAssertEqual(checks.map(\.reason), ["render_prior_geometry_changed", "render_new_overlap"])
        XCTAssertTrue(checks.allSatisfy { $0.contentMatches == false })
    }

    func testEnvelopeContainsOnlyCountsAndComparisonResultsNeverFramesOrLocalIdentities() throws {
        let before = snapshot()
        var after = before; after.measures[0].paperFrame.size.width = 180
        let check = try XCTUnwrap(assess(before, after))
        let chart = Chart.draft(title: "PRIVATE GEOMETRY TITLE", layoutStyle: .simpleChordSheet)
        let operationID = UUID()
        let values = Telemetry.properties(for: check, chart: chart, mode: .automatic, operationID: operationID)
        XCTAssertEqual(values["contract_id"], .string("ink.render_geometry"))
        XCTAssertEqual(values["operation"], .string("render"))
        XCTAssertEqual(values["render_mode"], .string("automatic"))
        XCTAssertEqual(values["operation_id"], .string(operationID.uuidString.lowercased()))
        XCTAssertEqual(Set(values.keys), ["contract_id", "contract_version", "operation_id", "operation",
            "outcome", "reason", "scope", "layout_style", "render_mode", "expected_count", "actual_count", "content_matches"])
        let text = String(decoding: try JSONEncoder().encode(values), as: UTF8.self)
        for secret in [chart.title, chart.id.uuidString.lowercased(), measureID.uuidString.lowercased(),
                       existingChordID.uuidString.lowercased(), newChordID.uuidString.lowercased(),
                       "paperFrame", "chordBandFrame", "retainedInkFrames", "naturalFrame"] {
            XCTAssertFalse(text.contains(secret))
        }
    }

    func testSnapshotUsesAlreadyComputedLayoutFramesWithoutChangingTheChart() {
        var chart = Chart.draft(title: "Synthetic geometry capture", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(title: "Synthetic geometry capture", key: .cMajor,
            meter: .init(numerator: 4, denominator: 4), staffStyle: .fiveLine, startingMeasureCount: 1)
        let original = chart
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: CGSize(width: 932, height: 1_200),
            includesChordInkContinuationLanes: true)
        let retained = CGRect(x: 321, y: 234, width: 14, height: 29)
        let captured = Telemetry.snapshot(layout: layout, coordinateEpoch: 12,
            configurationEpoch: 34, retainedInkFrames: [retained])
        XCTAssertEqual(captured.pageSize, layout.pageBounds.size)
        XCTAssertEqual(captured.coordinateEpoch, 12)
        XCTAssertEqual(captured.configurationEpoch, 34)
        XCTAssertEqual(captured.retainedInkFrames, [retained])
        XCTAssertEqual(captured.measures.first?.paperFrame, layout.systems.first?.measures.first?.frame)
        XCTAssertEqual(chart, original)
    }

    func testGeometryComparisonRunsOnAUtilityQueueWithoutMainActorWork() async {
        let before = snapshot()
        var changed = before; changed.measures[0].paperFrame.size.width = 180
        let after = changed
        let ids: Set<UUID> = [measureID]
        let result: (Bool, String?) = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let check = Telemetry.assessment(before: before, after: after,
                    preservedMeasureIDs: ids, renderedChordIDs: [], isCommitted: true)
                continuation.resume(returning: (Thread.isMainThread, check?.reason))
            }
        }
        XCTAssertFalse(result.0)
        XCTAssertEqual(result.1, "render_prior_geometry_changed")
    }

    func testNativeGeometryEnvelopesProvideContentFreeEndToEndFixtures() throws {
        let before = snapshot()
        var compressed = before; compressed.measures[0].paperFrame.size.width = 180
        var colliding = before
        colliding.glyphs.append(glyph(newChordID, x: 300))
        colliding.retainedInkFrames = [CGRect(x: 305, y: 40, width: 20, height: 20)]
        let chart = Chart.draft(title: "PRIVATE GEOMETRY TITLE", layoutStyle: .simpleChordSheet)
        let installationID = UUID().uuidString.lowercased()
        let sessionID = UUID().uuidString.lowercased()
        let observations: [(String, LeadSheetInkFeatureContract.Assessment?, Bool)] = [
            ("geometry_pass", assess(before, before), false),
            ("outgoing_row_compressed", assess(before, compressed), true),
            ("new_glyph_overlap", assess(before, colliding), true),
            ("staged_refusal", Telemetry.assessment(before: before, after: compressed,
                preservedMeasureIDs: [measureID], renderedChordIDs: [], isCommitted: false), false)
        ]
        var cases: [[String: Any]] = []
        for (name, check, createsTask) in observations {
            guard let check else {
                cases.append(["fixture": name, "event_emitted": false, "creates_task": false])
                continue
            }
            var values = Telemetry.properties(for: check, chart: chart, mode: .automatic)
            values["build_source"] = .string("debug_build")
            let scalar = try JSONSerialization.jsonObject(with: JSONEncoder().encode(values))
            cases.append(["fixture": name, "event_emitted": true, "creates_task": createsTask,
                "event": ["client_event_id": UUID().uuidString.lowercased(),
                    "event_name": "feature.contract_checked", "installation_id": installationID,
                    "session_id": sessionID, "platform": "iPadOS", "app_version": "internal-verification",
                    "build_number": "0", "properties": scalar]])
        }
        let data = try JSONSerialization.data(withJSONObject: ["schema_version": 1,
            "scope": "Native synthetic geometry comparisons; frames remain local", "cases": cases],
            options: [.prettyPrinted, .sortedKeys])
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains(chart.title))
        XCTAssertFalse(text.contains(measureID.uuidString.lowercased()))
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "render-geometry-telemetry-native-e2e-fixtures"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func assess(_ before: Telemetry.Snapshot, _ after: Telemetry.Snapshot) -> LeadSheetInkFeatureContract.Assessment? {
        Telemetry.assessment(before: before, after: after, preservedMeasureIDs: [measureID],
            renderedChordIDs: Set(after.glyphs.filter { $0.id == newChordID }.map(\.id)), isCommitted: true)
    }

    private func snapshot() -> Telemetry.Snapshot {
        .init(pageSize: CGSize(width: 932, height: 1_200), coordinateEpoch: 5, configurationEpoch: 6,
            measures: [.init(id: measureID, paperFrame: CGRect(x: 80, y: 30, width: 752, height: 100),
                chordBandFrame: CGRect(x: 90, y: 40, width: 732, height: 35))],
            glyphs: [glyph(existingChordID, x: 100)], retainedInkFrames: [])
    }

    private func glyph(_ id: UUID, x: CGFloat) -> Telemetry.GlyphGeometry {
        .init(id: id, naturalFrame: CGRect(x: x, y: 40, width: 30, height: 25),
            frame: CGRect(x: x, y: 40, width: 30, height: 25))
    }
}
#endif
