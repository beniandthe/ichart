#if DEBUG && canImport(UIKit)
import XCTest
import SwiftUI
@testable import iChart

@MainActor
final class PersonalLearnedComparisonModelTests: XCTestCase {
    private final class Encoder: PersonalInkVisualEncoding {
        let identity = "fixture-encoder"
        let vocabulary = ["A", "B"]
        var anchorBank: PersonalInkAnchorBank? {
            let feature = [1.0] + Array(repeating: 0.0, count: 127)
            return .init(vocabulary: vocabulary, features: [feature, feature])
        }
        func encode(_ strokes: [InkStroke]) throws -> PersonalInkVisualFeatures {
            .init(embedding: [1] + Array(repeating: 0, count: 127), genericLogits: [3, 0])
        }
    }

    func testComparisonUsesPreTestProfileSavesSeparatelyAndNeverTeaches() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = PersonalInkProfileStore(url: folder.appendingPathComponent("profile.json"))
        let ink = [InkStroke(points: [.init(x: 0, y: 0), .init(x: 0, y: 20)])]
        try store.update { p in p.isEnabled = true; try p.learn(strokes: ink, label: "B", kind: .glyph, source: .setup) }
        let frozen = store.snapshot().profile
        var run = PersonalInkEvaluationRun(chartID: UUID(), style: "leadSheet", phase: .beforeCorrections,
                                           pipeline: "fixture", profile: frozen)
        run.status = .complete
        run.records = [.init(measureIndex: 1, fraction: 0, strokes: ink, fingerprint: "fixture",
            baseline: "A", personalized: "A", baselineAction: "confirm", personalizedAction: "confirm", knownInk: false,
            recognitionMilliseconds: 1, totalMilliseconds: 1, cacheHit: false, intended: "B", recognitionStrokes: ink)]
        run.profileLineage = .init(profile: frozen, querySessionID: run.id)
        // A later explicit correction must not leak back into this test.
        try store.update { try $0.learn(strokes: ink, label: "A", kind: .glyph, source: .explicitCorrection) }
        let current = store.snapshot().profile
        let dataBefore = try Data(contentsOf: folder.appendingPathComponent("profile.json"))
        let reportFolder = folder.appendingPathComponent("reports")
        let model = PersonalLearnedComparisonModel(profileStore: store, reportDirectory: reportFolder, encoderFactory: { Encoder() })
        model.compare(run)
        try await finish(model)
        XCTAssertNil(model.error)
        let report = try XCTUnwrap(model.report)
        XCTAssertEqual(report.profileRevision, frozen.revision)
        XCTAssertEqual(report.profileLineage, run.profileLineage)
        XCTAssertNotEqual(report.profileLineage,
                          PersonalInkProfileLineageSummary(profile: current, querySessionID: run.id))
        XCTAssertNotEqual(report.profileRevision, current.revision)
        XCTAssertEqual(report.rows.first?.prediction?.personalChord, "B")
        XCTAssertNotNil(report.rows.first?.prediction?.anchored)
        XCTAssertEqual(store.snapshot().profile, current)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("profile.json")), dataBefore)
        let saved = try JSONDecoder().decode(PersonalInkLearnedRunReport.self,
            from: Data(contentsOf: reportFolder.appendingPathComponent("\(report.id.uuidString).json")))
        XCTAssertEqual(saved.sourceRunSHA256, report.sourceRunSHA256)
        XCTAssertEqual(saved.profileLineage, run.profileLineage)
        XCTAssertThrowsError(try report.save(in: reportFolder), "An old comparison cannot be overwritten")
        // Render the actual comparison view with this controlled result. The
        // attachments support human layout inspection, not accuracy claims.
        for (name, size) in [("portrait", CGSize(width: 820, height: 1180)),
                             ("landscape", CGSize(width: 1180, height: 820))] {
            let controller = UIHostingController(rootView: NavigationStack {
                PersonalLearnedComparisonView(run: run, model: model)
            })
            let window = UIWindow(frame: CGRect(origin: .zero, size: size))
            window.rootViewController = controller
            window.isHidden = false
            controller.view.frame = window.bounds
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(120))
            let renderer = UIGraphicsImageRenderer(size: size)
            let screenshot = renderer.image { _ in
                XCTAssertTrue(controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true))
            }
            let attachment = XCTAttachment(image: screenshot)
            attachment.name = "personal-learned-comparison-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
            window.isHidden = true
        }
    }

    func testOptOutBeforeOrDuringWorkDoesNotPublishOrSave() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = PersonalInkProfileStore(url: folder.appendingPathComponent("profile.json"))
        var calls = 0
        let gate = DispatchSemaphore(value: 0)
        let model = PersonalLearnedComparisonModel(profileStore: store, reportDirectory: folder.appendingPathComponent("reports"),
            encoderFactory: { calls += 1; _ = gate.wait(timeout: .now() + 2); return Encoder() })
        var p = PersonalInkProfile(); p.isEnabled = true
        var run = PersonalInkEvaluationRun(chartID: UUID(), style: "simpleChordSheet", phase: .beforeCorrections,
                                           pipeline: "fixture", profile: p)
        run.status = .complete
        model.compare(run)
        XCTAssertEqual(calls, 0)
        XCTAssertNotNil(model.error)
        try store.update { $0.isEnabled = true }
        model.compare(run)
        try store.update { $0.isEnabled = false }
        gate.signal()
        try await finish(model)
        XCTAssertNil(model.report)
        XCTAssertNotNil(model.error)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("reports").path))
    }

    func testCompleteTokenComparisonSavesHypothesesWithoutTeachingOrChangingTopOneResults() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let profileURL = folder.appendingPathComponent("profile.json")
        let store = PersonalInkProfileStore(url: profileURL)
        try store.update { $0.isEnabled = true }
        let frozen = store.snapshot().profile
        let profileData = try Data(contentsOf: profileURL)
        let ink = [InkStroke(points: [.init(x: 0, y: 0), .init(x: 0, y: 20)])]
        var run = PersonalInkEvaluationRun(chartID: UUID(), style: "rhythmSectionSheet", phase: .beforeCorrections,
            pipeline: "synthetic", profile: frozen)
        run.status = .complete
        run.records = [.init(measureIndex: 1, fraction: 0, strokes: ink, fingerprint: "synthetic-only", baseline: "B",
            personalized: "B", baselineAction: "confirm", personalizedAction: "confirm", knownInk: false,
            recognitionMilliseconds: 1, totalMilliseconds: 1, cacheHit: false, intended: "B", recognitionStrokes: ink)]
        let reportDirectory = folder.appendingPathComponent("reports")
        let model = PersonalLearnedComparisonModel(profileStore: store, reportDirectory: reportDirectory, encoderFactory: { Encoder() })
        model.compareAlternatives(run)
        try await finish(model)
        XCTAssertNil(model.error)
        let report = try XCTUnwrap(model.report)
        XCTAssertNil(model.pair)
        XCTAssertEqual(report.groupingVersion, PersonalInkLearnedComparison.Grouping.losslessSourceV2.rawValue)
        XCTAssertEqual(report.rows[0].prediction?.genericChord, "A")
        let hypotheses = try XCTUnwrap(report.rows[0].completeTokenHypotheses)
        XCTAssertEqual(hypotheses.generic.candidates.map(\.text), ["A", "B"])
        XCTAssertNotNil(hypotheses.anchored)
        let saved = try JSONDecoder().decode(PersonalInkLearnedRunReport.self,
            from: Data(contentsOf: reportDirectory.appendingPathComponent("\(report.id.uuidString).json")))
        XCTAssertEqual(saved.rows[0].completeTokenHypotheses, hypotheses)
        XCTAssertEqual(try Data(contentsOf: profileURL), profileData)
        XCTAssertEqual(store.snapshot().profile, frozen)
    }

    func testAlternativeComparisonOptOutDuringQueuedFitPreventsPublicationAndSaving() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = PersonalInkProfileStore(url: folder.appendingPathComponent("profile.json"))
        try store.update { $0.isEnabled = true }
        var run = PersonalInkEvaluationRun(chartID: UUID(), style: "simpleChordSheet", phase: .beforeCorrections,
            pipeline: "synthetic", profile: store.snapshot().profile)
        run.status = .complete
        let gate = DispatchSemaphore(value: 0)
        let reportDirectory = folder.appendingPathComponent("reports")
        let model = PersonalLearnedComparisonModel(profileStore: store, reportDirectory: reportDirectory,
            encoderFactory: { _ = gate.wait(timeout: .now() + 2); return Encoder() })
        model.compareAlternatives(run)
        try store.update { $0.isEnabled = false }
        gate.signal()
        try await finish(model)
        XCTAssertNil(model.report)
        XCTAssertNotNil(model.error)
        XCTAssertFalse(FileManager.default.fileExists(atPath: reportDirectory.path))
    }

    func testFrozenLineagePresentationKeepsUnknownEmptyIncompleteOverlapAndDisjointStatesDistinct() throws {
        let query = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let support = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
        let ink = [InkStroke(points: [.init(x: 0, y: 0), .init(x: 0, y: 20)])]
        let legacy = PersonalInkFrozenLineagePresentation(lineage: nil)
        XCTAssertEqual(legacy.status, .legacyUnknown)
        XCTAssertEqual(legacy.summary, "Saved support intake: unknown (older test).")
        XCTAssertTrue(legacy.warnings.contains { $0.contains("not been backfilled") })
        XCTAssertTrue(legacy.assurance.contains("does not verify"))
        XCTAssertTrue(legacy.assurance.contains("fresh handwriting"))

        var profile = PersonalInkProfile(); profile.isEnabled = true
        let emptySummary = PersonalInkProfileLineageSummary(profile: profile, querySessionID: query)
        let empty = PersonalInkFrozenLineagePresentation(lineage: emptySummary)
        XCTAssertEqual(empty.status, .emptySupport)
        XCTAssertEqual(empty.summary, "Saved support intake: 0 tracked · 0 untracked · 0 mismatched · 0 overlapping")
        XCTAssertTrue(empty.statusText.contains("Empty support is not transfer evidence"))
        XCTAssertEqual(empty.assurance, emptySummary.assuranceNote)

        try profile.learn(strokes: ink, label: "A", kind: .glyph, source: .setup,
                          captureContext: .init(sessionID: support, origin: .setup))
        let disjointSummary = PersonalInkProfileLineageSummary(profile: profile, querySessionID: query)
        let disjoint = PersonalInkFrozenLineagePresentation(lineage: disjointSummary)
        XCTAssertEqual(disjoint.status, .disjoint)
        XCTAssertEqual(disjoint.summary, "Saved support intake: 1 tracked · 0 untracked · 0 mismatched · 0 overlapping")
        XCTAssertTrue(disjoint.warnings.isEmpty)
        XCTAssertTrue(disjoint.details.contains(query.uuidString))
        XCTAssertTrue(disjoint.details.contains(support.uuidString))
        XCTAssertTrue(disjoint.details.contains(profile.examples[0].id.uuidString))
        XCTAssertEqual(disjoint.assurance, disjointSummary.assuranceNote)
        XCTAssertTrue(disjoint.assurance.contains("not verified"))
        XCTAssertFalse(disjoint.statusText.localizedCaseInsensitiveContains("fresh"))

        let overlapSummary = PersonalInkProfileLineageSummary(profile: profile, querySessionID: support)
        let overlap = PersonalInkFrozenLineagePresentation(lineage: overlapSummary)
        XCTAssertEqual(overlap.status, .overlapping)
        XCTAssertEqual(overlap.summary, "Saved support intake: 1 tracked · 0 untracked · 0 mismatched · 1 overlapping")
        XCTAssertTrue(overlap.warnings.contains { $0.contains("share the query intake session") })

        try profile.learn(strokes: ink, label: "B", kind: .glyph, source: .practice)
        let incompleteSummary = PersonalInkProfileLineageSummary(profile: profile, querySessionID: query)
        let incomplete = PersonalInkFrozenLineagePresentation(lineage: incompleteSummary)
        XCTAssertEqual(incomplete.status, .incomplete)
        XCTAssertEqual(incomplete.summary, "Saved support intake: 1 tracked · 1 untracked · 0 mismatched · 0 overlapping")
        XCTAssertTrue(incomplete.warnings.contains { $0.contains("Missing or mismatched metadata") })
        XCTAssertTrue(incomplete.details.contains(profile.examples[1].id.uuidString))

        let both = PersonalInkFrozenLineagePresentation(lineage:
            .init(profile: profile, querySessionID: support))
        XCTAssertEqual(both.status, .overlapping)
        XCTAssertEqual(both.warnings.count, 2, "Missing metadata must not hide an observed overlap, or vice versa")
        XCTAssertTrue(both.warnings.contains { $0.contains("Missing or mismatched metadata") })
        XCTAssertTrue(both.warnings.contains { $0.contains("share the query intake session") })

        profile.examples[0].learningProvenance?.storedInputSHA256 = String(repeating: "0", count: 64)
        let mismatchSummary = PersonalInkProfileLineageSummary(profile: profile, querySessionID: query)
        let mismatch = PersonalInkFrozenLineagePresentation(lineage: mismatchSummary)
        XCTAssertEqual(mismatch.status, .incomplete)
        XCTAssertEqual(mismatch.summary, "Saved support intake: 0 tracked · 1 untracked · 1 mismatched · 0 overlapping")
        XCTAssertTrue(mismatch.details.contains("Mismatched lessons: \(profile.examples[0].id.uuidString)"))
        XCTAssertEqual(mismatch.assurance, mismatchSummary.assuranceNote)
    }

    private func finish(_ model: PersonalLearnedComparisonModel) async throws {
        for _ in 0..<500 {
            if !model.busy { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Learned comparison did not finish")
    }
}
#endif
