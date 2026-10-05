#if DEBUG && canImport(UIKit)
import XCTest
import SwiftUI
import UIKit
@testable import iChart

@MainActor
final class PersonalOwnershipComparisonModelTests: XCTestCase {
    private final class Encoder: PersonalInkVisualEncoding {
        let identity = "synthetic-paired-ui-contract-only"
        let vocabulary = ["A", "B"]
        func encode(_ strokes: [InkStroke]) throws -> PersonalInkVisualFeatures {
            .init(embedding: [1] + Array(repeating: 0, count: 127), genericLogits: [3, 0])
        }
    }
    private final class TransactionEvents: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String] = []
        func append(_ event: String) { lock.lock(); defer { lock.unlock() }; values.append(event) }
        var snapshot: [String] { lock.lock(); defer { lock.unlock() }; return values }
    }

    func testPrimaryPairedEntrySavesBothOutcomesWithoutTeachingAndRendersActualView() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = PersonalInkProfileStore(url: folder.appendingPathComponent("profile.json"))
        try store.update { $0.isEnabled = true }
        let frozen = store.snapshot().profile
        let run = makeRun(profile: frozen)
        let sourceURL = folder.appendingPathComponent("source-run.json"), sourceBytes = try JSONEncoder().encode(run)
        try sourceBytes.write(to: sourceURL)
        // Explicit later activity stays separate from the run's frozen fit.
        try store.update { try $0.learn(strokes: run.records[0].recognitionInput, label: "B", kind: .glyph, source: .setup) }
        let current = store.snapshot().profile, profileBytes = try Data(contentsOf: folder.appendingPathComponent("profile.json"))
        let reports = folder.appendingPathComponent("reports")
        let model = PersonalLearnedComparisonModel(profileStore: store, reportDirectory: reports, encoderFactory: { Encoder() })
        model.comparePair(run)
        try await finish(model)
        XCTAssertNil(model.error)
        let pair = try XCTUnwrap(model.pair)
        XCTAssertEqual(pair.legacy.profileRevision, frozen.revision)
        XCTAssertEqual(pair.selective.profileRevision, frozen.revision)
        XCTAssertNotEqual(pair.selective.profileRevision, current.revision)
        XCTAssertNotNil(pair.legacy.rows[0].prediction?.genericChord)
        XCTAssertEqual(pair.selective.rows[0].prediction?.ownership?.disposition, .unresolved)
        XCTAssertNil(pair.selective.rows[0].prediction?.personalChord)
        let files = jsonFiles(in: reports)
        XCTAssertEqual(files.count, 1, "The actual model saves one complete paired file")
        let file = try XCTUnwrap(files.first), savedBytes = try Data(contentsOf: file)
        let saved = try JSONDecoder().decode(PersonalInkOwnershipComparisonReport.self, from: savedBytes)
        XCTAssertEqual(saved.id, pair.id)
        XCTAssertEqual(saved.legacy.evaluationSourceSHA256, saved.selective.evaluationSourceSHA256)
        XCTAssertEqual(store.snapshot().profile, current)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("profile.json")), profileBytes)
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceBytes)
        try await attachViews(run: run, model: model)
        model.comparePair(run)
        try await finish(model)
        XCTAssertNil(model.error)
        XCTAssertNotEqual(model.pair?.id, pair.id)
        XCTAssertEqual(jsonFiles(in: reports).count, 2)
        XCTAssertEqual(try Data(contentsOf: file), savedBytes)
    }

    func testOptOutBeforePairedWorkDoesNotLoadEncoderPublishOrSave() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = PersonalInkProfileStore(url: folder.appendingPathComponent("profile.json"))
        var calls = 0
        let reports = folder.appendingPathComponent("reports")
        let model = PersonalLearnedComparisonModel(profileStore: store, reportDirectory: reports,
            encoderFactory: { calls += 1; return Encoder() })
        var profile = PersonalInkProfile(); profile.isEnabled = true
        model.comparePair(makeRun(profile: profile))
        XCTAssertEqual(calls, 0); XCTAssertFalse(model.busy)
        XCTAssertNil(model.pair); XCTAssertNil(model.report); XCTAssertNotNil(model.error)
        XCTAssertFalse(FileManager.default.fileExists(atPath: reports.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("profile.json").path))
    }

    func testOptOutOrUnversionedProfileChangeDuringWorkPublishesNeitherReport() async throws {
        for disable in [true, false] {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: folder) }
            let store = PersonalInkProfileStore(url: folder.appendingPathComponent("profile.json"))
            try store.update { $0.isEnabled = true }
            let run = makeRun(profile: store.snapshot().profile)
            let source = folder.appendingPathComponent("source-run.json"), original = try JSONEncoder().encode(run)
            try original.write(to: source)
            let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
            defer { release.signal() }
            let reports = folder.appendingPathComponent("reports")
            let model = PersonalLearnedComparisonModel(profileStore: store, reportDirectory: reports, encoderFactory: {
                entered.signal(); _ = release.wait(timeout: .now() + 3); return Encoder()
            })
            model.comparePair(run)
            try await factoryEntered(entered)
            try store.update { profile in
                if disable { profile.isEnabled = false } else { profile.learnsFromReviews.toggle() }
            }
            let changed = store.snapshot().profile, changedBytes = try Data(contentsOf: folder.appendingPathComponent("profile.json"))
            release.signal()
            try await finish(model)
            XCTAssertNil(model.pair); XCTAssertNil(model.report); XCTAssertNotNil(model.error)
            XCTAssertTrue(jsonFiles(in: reports).isEmpty)
            XCTAssertEqual(store.snapshot().profile, changed)
            XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("profile.json")), changedBytes)
            XCTAssertEqual(try Data(contentsOf: source), original)
        }
    }

    func testPairSaveFailurePublishesNeitherOutcomeAndPreservesAllOriginalFiles() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = PersonalInkProfileStore(url: folder.appendingPathComponent("profile.json"))
        try store.update { $0.isEnabled = true }
        let run = makeRun(profile: store.snapshot().profile)
        let source = folder.appendingPathComponent("source-run.json"), bytes = try JSONEncoder().encode(run)
        try bytes.write(to: source)
        let profileBytes = try Data(contentsOf: folder.appendingPathComponent("profile.json"))
        let obstruction = folder.appendingPathComponent("reports"); try Data("preserve this file".utf8).write(to: obstruction)
        let model = PersonalLearnedComparisonModel(profileStore: store, reportDirectory: obstruction, encoderFactory: { Encoder() })
        model.comparePair(run)
        try await finish(model)
        XCTAssertNil(model.pair); XCTAssertNil(model.report); XCTAssertNotNil(model.error)
        XCTAssertEqual(try Data(contentsOf: obstruction), Data("preserve this file".utf8))
        XCTAssertEqual(try Data(contentsOf: source), bytes)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("profile.json")), profileBytes)
    }

    func testProfileTransactionSerializesUpdateAndRefusesStaleOrDisabledProfile() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let profileURL = folder.appendingPathComponent("profile.json")
        let store = PersonalInkProfileStore(url: profileURL)
        try store.update { $0.isEnabled = true }
        let expected = store.snapshot().profile, bytes = try Data(contentsOf: profileURL)
        let held = expectation(description: "Transaction closure holds the profile lock")
        let attempted = expectation(description: "Background update attempts the same store")
        let completed = expectation(description: "Update finishes after the transaction")
        let transactionEnded = expectation(description: "Guarded transaction returns")
        let premature = XCTestExpectation(description: "Update cannot finish while transaction closure is held")
        premature.isInverted = true
        let release = DispatchSemaphore(value: 0), events = TransactionEvents()
        defer { release.signal() }
        DispatchQueue.global().async {
            defer { transactionEnded.fulfill() }
            do {
                let result = try store.withUnchangedProfile(expected: expected) {
                    events.append("operation-enter"); held.fulfill()
                    XCTAssertEqual(release.wait(timeout: .now() + 5), .success)
                    XCTAssertEqual(try Data(contentsOf: profileURL), bytes)
                    events.append("operation-exit")
                    return "saved"
                }
                XCTAssertEqual(result, "saved")
            } catch { XCTFail("Guarded transaction failed: \(error)") }
        }
        await fulfillment(of: [held], timeout: 2)
        DispatchQueue.global().async {
            attempted.fulfill()
            do {
                try store.update { $0.learnsFromReviews.toggle() }
                if !events.snapshot.contains("operation-exit") { premature.fulfill() }
                events.append("update")
            } catch { XCTFail("Competing profile update failed: \(error)") }
            completed.fulfill()
        }
        await fulfillment(of: [attempted], timeout: 2)
        await fulfillment(of: [premature], timeout: 0.1)
        release.signal()
        await fulfillment(of: [transactionEnded, completed], timeout: 2)
        XCTAssertEqual(events.snapshot, ["operation-enter", "operation-exit", "update"])

        var called = false
        let changedBytes = try Data(contentsOf: profileURL)
        let stale: Int? = try store.withUnchangedProfile(expected: expected) { called = true; return 1 }
        XCTAssertNil(stale); XCTAssertFalse(called)
        XCTAssertEqual(try Data(contentsOf: profileURL), changedBytes)
        try store.update { $0.isEnabled = false }
        let disabled = store.snapshot().profile, disabledBytes = try Data(contentsOf: profileURL)
        let optedOut: Int? = try store.withUnchangedProfile(expected: disabled) { called = true; return 1 }
        XCTAssertNil(optedOut); XCTAssertFalse(called)
        XCTAssertEqual(try Data(contentsOf: profileURL), disabledBytes)
    }

    private func makeRun(profile: PersonalInkProfile) -> PersonalInkEvaluationRun {
        let ink = [InkStroke(points: [.init(x: 100, y: 100), .init(x: 100, y: 120), .init(x: 113, y: 116)])]
        var run = PersonalInkEvaluationRun(chartID: UUID(), style: "simpleChordSheet", phase: .beforeCorrections,
            pipeline: "synthetic-paired-ui-contract", profile: profile)
        run.status = .complete; run.expectedChordCount = 1
        run.records = [.init(measureIndex: 1, fraction: 0, strokes: ink, fingerprint: "synthetic", baseline: "A", personalized: "A",
            baselineAction: "confirm", personalizedAction: "confirm", knownInk: false, recognitionMilliseconds: 1,
            totalMilliseconds: 1, cacheHit: false, intended: "A", recognitionStrokes: ink)]
        return run
    }
    private func jsonFiles(in directory: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "json" }
    }
    private func finish(_ model: PersonalLearnedComparisonModel) async throws {
        for _ in 0..<500 {
            if !model.busy { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Paired comparison did not finish")
    }
    private func factoryEntered(_ semaphore: DispatchSemaphore) async throws {
        for _ in 0..<200 {
            if hasFactoryEntered(semaphore) { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Controlled encoder factory did not start")
    }
    private func hasFactoryEntered(_ semaphore: DispatchSemaphore) -> Bool {
        semaphore.wait(timeout: .now()) == .success
    }
    private func attachViews(run: PersonalInkEvaluationRun, model: PersonalLearnedComparisonModel) async throws {
        for (name, size) in [("portrait", CGSize(width: 820, height: 1180)), ("landscape", CGSize(width: 1180, height: 820))] {
            let controller = UIHostingController(rootView: NavigationStack { PersonalLearnedComparisonView(run: run, model: model) })
            let window = UIWindow(frame: CGRect(origin: .zero, size: size)); window.rootViewController = controller
            window.isHidden = false; controller.view.frame = window.bounds
            controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(120))
            let scroll = try XCTUnwrap(scrollView(in: controller.view))
            let bottom = max(0, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
            XCTAssertGreaterThan(bottom, 0, "The selective section follows the legacy report")
            scroll.setContentOffset(CGPoint(x: 0, y: bottom), animated: false)
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(120))
            // The final card contains unresolved ownership and the original-ink
            // proposal preview. Capture it, not just the legacy report's top.
            let image = UIGraphicsImageRenderer(size: size).image { _ in
                XCTAssertTrue(controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true))
            }
            let attachment = XCTAttachment(image: image); attachment.name = "selective-ownership-comparison-\(name)"
            attachment.lifetime = .keepAlways; add(attachment); window.isHidden = true
        }
    }
    private func scrollView(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView { return scroll }
        return view.subviews.lazy.compactMap { self.scrollView(in: $0) }.first
    }
}
#endif
