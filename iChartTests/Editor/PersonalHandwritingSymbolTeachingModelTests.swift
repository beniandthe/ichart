#if canImport(UIKit)
import SwiftUI
import XCTest
@testable import iChart

@MainActor
final class PersonalHandwritingSymbolTeachingModelTests: XCTestCase {
    private func ink() -> [InkStroke] {
        [.init(points: [.init(x: 0, y: 0), .init(x: 0, y: 20), .init(x: 10, y: 20),
                        .init(x: 12, y: 10), .init(x: 10, y: 0), .init(x: 0, y: 0)]),
         .init(points: [.init(x: 40, y: 0), .init(x: 52, y: 0), .init(x: 42, y: 20)])]
    }

    private func prepared(_ folder: URL) throws -> (PersonalInkProfileStore, PersonalInkSymbolTeachingReview) {
        let store = PersonalInkProfileStore(url: folder.appendingPathComponent("profile.json"))
        try store.update {
            $0.isEnabled = true
            try $0.learn(strokes: ink(), label: "D7", kind: .chord, source: .explicitCorrection)
        }
        let profile = store.snapshot().profile
        return (store, try .init(exampleID: XCTUnwrap(profile.examples.first?.id), profile: profile))
    }

    private func preparedSelection(_ folder: URL) throws -> (PersonalInkProfileStore, PersonalInkSymbolTeachingReview) {
        let store = PersonalInkProfileStore(url: folder.appendingPathComponent("profile.json"))
        let strokes = (0..<4).map { index in
            let x = Double((4 - index) * 25)
            return InkStroke(points: [.init(x: x, y: 0, timeOffset: 0),
                .init(x: x + Double(index + 1), y: 12, timeOffset: 0.1),
                .init(x: x + 8, y: 20, timeOffset: 0.3)], creationTimeOffset: Double(index) * 0.5)
        }
        var source = PersonalInkExample(kind: .chord, label: "D7", strokes: strokes, source: .explicitCorrection)
        let context = PersonalInkCaptureContext(
            sessionID: UUID(uuidString: "30000000-0000-0000-0000-000000000003")!,
            captureID: UUID(uuidString: "40000000-0000-0000-0000-000000000004")!,
            capturedAt: Date(timeIntervalSinceReferenceDate: 100), origin: .savedEvaluation,
            chartStyle: "rhythm-section-sheet")
        source.learningProvenance = try .make(context: context, taughtAt: Date(timeIntervalSinceReferenceDate: 101),
                                              originalInput: strokes, storedInput: strokes)
        try store.update { $0.isEnabled = true; $0.examples = [source] }
        let profile = store.snapshot().profile
        return (store, try .init(exampleID: source.id, profile: profile))
    }

    func testTeachingPersistsAndReloadsWithoutRewritingOriginalOrHistoricalTests() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let (store, review) = try prepared(folder)
        let before = store.snapshot().profile
        var run = PersonalInkEvaluationRun(chartID: UUID(), style: "simpleChordSheet", phase: .beforeCorrections,
                                          pipeline: "controlled-fixture", profile: before)
        run.status = .complete
        let journalData = try JSONEncoder().encode(PersonalInkEvaluationJournal(runs: [run]))
        let journalURL = folder.appendingPathComponent("evaluation.json")
        try journalData.write(to: journalURL)
        let model = PersonalHandwritingModel(store: store, evaluationStore: PersonalInkEvaluationStore(url: journalURL))
        let taught = expectation(description: "explicit symbols persisted")
        model.teachSymbols(review, labels: ["D", "7"]) { receipt in
            XCTAssertEqual(receipt.selectedSymbolCount, 2)
            XCTAssertEqual(receipt.changedSymbolCount, 2)
            XCTAssertEqual(receipt.previousExampleCount, 1)
            XCTAssertEqual(receipt.savedExampleCount, 3)
            taught.fulfill()
        }
        await fulfillment(of: [taught], timeout: 5)
        XCTAssertFalse(model.busy)
        XCTAssertNil(model.error)
        XCTAssertEqual(model.profile.examples.first, review.source)
        XCTAssertEqual(model.profile.examples.filter { $0.kind == .glyph }.map(\.label), ["D", "7"])
        XCTAssertEqual(model.profile.generation, before.generation)
        XCTAssertNotEqual(model.profile.revision, before.revision)
        let reloaded = PersonalInkProfileStore(url: folder.appendingPathComponent("profile.json"))
        XCTAssertNil(reloaded.loadError)
        XCTAssertEqual(reloaded.snapshot().profile, model.profile)
        XCTAssertEqual(try Data(contentsOf: journalURL), journalData)
        XCTAssertEqual(run.profile, before)
    }

    func testActiveCaptureBlocksTeachingAndLeavesBothStoresUnchanged() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let (store, review) = try prepared(folder)
        let before = store.snapshot().profile
        let journalURL = folder.appendingPathComponent("evaluation.json")
        let evaluation = PersonalInkEvaluationStore(url: journalURL)
        let started = expectation(description: "capture started")
        evaluation.start(chartID: UUID(), style: "rhythmSectionSheet", phase: .beforeCorrections,
                         profile: before, pipeline: "controlled-fixture") { error in
            XCTAssertNil(error); started.fulfill()
        }
        await fulfillment(of: [started], timeout: 5)
        let journalData = try Data(contentsOf: journalURL)
        let profileData = try Data(contentsOf: folder.appendingPathComponent("profile.json"))
        let model = PersonalHandwritingModel(store: store, evaluationStore: evaluation)
        model.teachSymbols(review, labels: ["D", "7"]) { _ in XCTFail("Capture must prevent teaching") }
        XCTAssertFalse(model.busy)
        XCTAssertEqual(model.error, PersonalInkEvaluationError.activeRun.localizedDescription)
        XCTAssertEqual(store.snapshot().profile, before)
        XCTAssertEqual(try Data(contentsOf: journalURL), journalData)
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("profile.json")), profileData)
    }

    func testRepairedSelectionsPersistExactOriginAndLeaveHistoricalJournalUnchanged() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let (store, review) = try preparedSelection(folder)
        let before = store.snapshot().profile
        var run = PersonalInkEvaluationRun(chartID: UUID(), style: "rhythmSectionSheet", phase: .beforeCorrections,
                                          pipeline: "controlled-selection-fixture", profile: before)
        run.status = .complete
        let journalData = try JSONEncoder().encode(PersonalInkEvaluationJournal(runs: [run]))
        let journalURL = folder.appendingPathComponent("evaluation.json")
        try journalData.write(to: journalURL)
        let model = PersonalHandwritingModel(store: store, evaluationStore: PersonalInkEvaluationStore(url: journalURL))
        var draft = PersonalInkSymbolSelectionDraft(review: try review.selectingOriginalGroups([]))
        try draft.replacePiece(at: nil, withStrokeIndexes: [2, 0])
        try draft.replacePiece(at: nil, withStrokeIndexes: [3])
        try draft.setLabel("D", forPiece: 0)
        try draft.setLabel("7", forPiece: 1)
        XCTAssertEqual(draft.unassignedStrokeIndexes, [1])
        let selected = try draft.makeReview()
        let taught = expectation(description: "repaired selected symbols persisted")
        model.teachSymbols(selected, labels: draft.labels) { receipt in
            XCTAssertEqual(receipt.selectedSymbolCount, 2)
            XCTAssertEqual(receipt.changedSymbolCount, 2)
            XCTAssertEqual(receipt.previousExampleCount, 1)
            XCTAssertEqual(receipt.savedExampleCount, 3)
            taught.fulfill()
        }
        await fulfillment(of: [taught], timeout: 5)
        XCTAssertFalse(model.busy)
        XCTAssertNil(model.error)
        XCTAssertEqual(model.profile.examples.first, review.source)
        XCTAssertEqual(model.profile.generation, before.generation)
        let glyphs = model.profile.examples.filter { $0.kind == .glyph }
        XCTAssertEqual(glyphs.map(\.label), ["D", "7"])
        XCTAssertEqual(glyphs.map { $0.verifiedSymbolOrigin?.originalStrokeIndexes }, [[0, 2], [3]])
        for (glyph, piece) in zip(glyphs, selected.pieces) {
            XCTAssertEqual(piece.strokes, piece.originalStrokeIndexes.map { review.source.recognitionInput[$0] })
            XCTAssertEqual(glyph.verifiedSymbolOrigin?.chordExampleID, review.source.id)
            XCTAssertEqual(glyph.verifiedSymbolOrigin?.chordLabel, review.source.label)
            XCTAssertEqual(glyph.strokes, try XCTUnwrap(PersonalInkShape(strokes: piece.strokes)).normalizedStrokes)
            XCTAssertEqual(glyph.recognitionStrokes, piece.strokes)
            let provenance = try XCTUnwrap(glyph.learningProvenance)
            let parentContext = try XCTUnwrap(review.source.learningProvenance).context
            XCTAssertEqual(provenance.context.sessionID, parentContext.sessionID)
            XCTAssertEqual(provenance.context.captureID, parentContext.captureID)
            XCTAssertEqual(provenance.context.capturedAt, parentContext.capturedAt)
            XCTAssertEqual(provenance.context.chartStyle, parentContext.chartStyle)
            XCTAssertEqual(provenance.context.origin, .selectedSavedSymbol)
            XCTAssertEqual(provenance.originalInputSHA256,
                           try PersonalInkLearningProvenance.inputSHA256(strokes: piece.strokes))
            XCTAssertNoThrow(try provenance.validate(storedInput: glyph.recognitionInput))
        }
        let reloaded = PersonalInkProfileStore(url: folder.appendingPathComponent("profile.json"))
        XCTAssertNil(reloaded.loadError)
        XCTAssertEqual(reloaded.snapshot().profile, model.profile)
        XCTAssertEqual(try Data(contentsOf: journalURL), journalData)
        XCTAssertEqual(run.profile, before)
    }

    func testOptOutOrResetAfterOpeningReviewCannotSaveThroughStaleUI() async throws {
        for reset in [false, true] {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: folder) }
            let (store, review) = try prepared(folder)
            let model = PersonalHandwritingModel(store: store,
                evaluationStore: PersonalInkEvaluationStore(url: folder.appendingPathComponent("evaluation.json")))
            if reset { try store.reset() } else { try store.update { $0.isEnabled = false } }
            let before = store.snapshot().profile
            let profileData = try Data(contentsOf: folder.appendingPathComponent("profile.json"))
            XCTAssertTrue(model.profile.isEnabled, "Exercise stale displayed state, not a disabled button")
            var draft = PersonalInkSymbolSelectionDraft(review: try review.selectingOriginalGroups([]))
            try draft.replacePiece(at: nil, withStrokeIndexes: [1, 0])
            try draft.setLabel("D", forPiece: 0)
            model.teachSymbols(try draft.makeReview(), labels: draft.labels) { _ in XCTFail("Stale UI must not save") }
            try await finish(model)
            XCTAssertNotNil(model.error)
            XCTAssertEqual(model.profile, before)
            XCTAssertEqual(store.snapshot().profile, before)
            XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("profile.json")), profileData)
        }
    }

    func testOpeningActualTeachingViewDoesNotLearnAndRendersAtBothOrientations() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let (store, review) = try prepared(folder)
        let before = store.snapshot().profile
        let model = PersonalHandwritingModel(store: store,
            evaluationStore: PersonalInkEvaluationStore(url: folder.appendingPathComponent("evaluation.json")))
        for (name, size) in [("portrait", CGSize(width: 820, height: 1180)),
                             ("landscape", CGSize(width: 1180, height: 820))] {
            let controller = UIHostingController(rootView: NavigationStack {
                PersonalHandwritingSymbolTeachingView(model: model, review: review)
            })
            let window = UIWindow(frame: CGRect(origin: .zero, size: size))
            window.rootViewController = controller
            window.isHidden = false
            controller.view.frame = window.bounds
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(150))
            let screenshot = UIGraphicsImageRenderer(size: size).image { _ in
                XCTAssertTrue(controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true))
            }
            let attachment = XCTAttachment(image: screenshot)
            attachment.name = "personal-symbol-teaching-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
            window.isHidden = true
            XCTAssertEqual(store.snapshot().profile, before)
        }
        // Attachments prove the actual view renders, not that recognition is accurate.
    }

    func testOpeningActualStrokeSelectionEditorDoesNotApplyOrLearnAndRendersAtBothOrientations() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let (store, review) = try preparedSelection(folder)
        let before = store.snapshot().profile
        for (name, size) in [("portrait", CGSize(width: 820, height: 1180)),
                             ("landscape", CGSize(width: 1180, height: 820))] {
            let controller = UIHostingController(rootView: NavigationStack {
                PersonalHandwritingStrokeSelectionView(strokes: review.source.strokes,
                    initialSelection: [0, 2], onApply: { _ in XCTFail("Opening an editor cannot apply a selection") })
            })
            let window = UIWindow(frame: CGRect(origin: .zero, size: size))
            window.rootViewController = controller
            window.isHidden = false
            controller.view.frame = window.bounds
            controller.view.setNeedsLayout()
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(150))
            let screenshot = UIGraphicsImageRenderer(size: size).image { _ in
                XCTAssertTrue(controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true))
            }
            let attachment = XCTAttachment(image: screenshot)
            attachment.name = "personal-stroke-selection-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
            window.isHidden = true
            XCTAssertEqual(store.snapshot().profile, before)
        }
        // Rendering attachments are UI evidence only, not Pencil interaction or handwriting accuracy.
    }

    func testStrokeSelectionGeometryHitsOriginalLineDotAndRepeatedPointAtBothOrientations() {
        let strokes: [InkStroke] = [
            .init(points: [.init(x: 40, y: 0), .init(x: 40, y: 20)], creationTimeOffset: 0),
            .init(points: [.init(x: 0, y: 0)], creationTimeOffset: 0.5),
            .init(points: [.init(x: 20, y: 20), .init(x: 20, y: 20), .init(x: 20, y: 20)], creationTimeOffset: 1)
        ]
        let geometry = PersonalHandwritingStrokeSelectionGeometry(strokes: strokes)
        for size in [CGSize(width: 200, height: 300), CGSize(width: 300, height: 200)] {
            XCTAssertEqual(geometry.hitTest(geometry.location(.init(x: 40, y: 10), in: size), in: size), .stroke(0))
            XCTAssertEqual(geometry.hitTest(geometry.location(.init(x: 0, y: 0), in: size), in: size), .stroke(1))
            XCTAssertEqual(geometry.hitTest(geometry.location(.init(x: 20, y: 20), in: size), in: size), .stroke(2))
            XCTAssertEqual(geometry.hitTest(.zero, in: size), .none)
        }
        XCTAssertEqual(geometry.strokes, strokes, "Display transforms must not reorder, normalize or alter source ink")
    }

    func testOverlappingStrokeSelectionRequiresExplicitIndexAndLeavesSourceUnchanged() {
        let strokes: [InkStroke] = [
            .init(points: [.init(x: 10, y: 0), .init(x: 10, y: 20)], creationTimeOffset: 0.5),
            .init(points: [.init(x: 0, y: 10), .init(x: 20, y: 10)], creationTimeOffset: 0)
        ]
        let geometry = PersonalHandwritingStrokeSelectionGeometry(strokes: strokes)
        for size in [CGSize(width: 200, height: 300), CGSize(width: 300, height: 200)] {
            XCTAssertEqual(geometry.hitTest(geometry.location(.init(x: 10, y: 10), in: size), in: size), .overlap)
            XCTAssertEqual(geometry.hitTest(geometry.location(.init(x: 10, y: 0), in: size), in: size), .stroke(0))
            XCTAssertEqual(geometry.hitTest(geometry.location(.init(x: 0, y: 10), in: size), in: size), .stroke(1))
        }
        XCTAssertEqual(geometry.strokes, strokes)
        XCTAssertEqual(geometry.strokes.map(\.creationTimeOffset), [0.5, 0])
    }

    private func finish(_ model: PersonalHandwritingModel) async throws {
        for _ in 0..<500 {
            if !model.busy { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Symbol teaching did not finish")
    }
}
#endif
