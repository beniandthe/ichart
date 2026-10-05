#if canImport(UIKit)
import XCTest
@testable import iChart

@MainActor
final class PersonalHandwritingEvaluationModelTests: XCTestCase {
    func testTeachingAcknowledgementUsesSavedProfileAndSurvivesReopening() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let (evaluation, runID) = try fixture(folder)
        let profileURL = folder.appendingPathComponent("profile.json")
        let model = PersonalHandwritingEvaluationModel(store: evaluation, profileStore: PersonalInkProfileStore(url: profileURL))
        model.teach(runID: runID)
        try await finish(model)
        XCTAssertNil(model.error)
        XCTAssertNil(model.teachingFailure)
        XCTAssertEqual(model.profile.examples.count, 1)
        let receipt = try XCTUnwrap(model.journal.runs.first?.teachingReceipt)
        XCTAssertEqual(receipt.savedExampleCount, 1)
        let reopened = PersonalHandwritingEvaluationModel(
            store: PersonalInkEvaluationStore(url: folder.appendingPathComponent("evaluation.json")),
            profileStore: PersonalInkProfileStore(url: profileURL))
        XCTAssertEqual(reopened.profile.revision, receipt.profileRevision)
        XCTAssertEqual(reopened.journal.runs.first?.teachingReceipt, receipt)
        XCTAssertEqual(reopened.journal.runs.first?.records.first?.taught, true)
    }

    func testTeachingFailureIsVisibleAndDoesNotShowSuccess() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let (evaluation, runID) = try fixture(folder)
        let notFolder = folder.appendingPathComponent("not-a-folder")
        try Data("test fixture".utf8).write(to: notFolder)
        let model = PersonalHandwritingEvaluationModel(store: evaluation,
            profileStore: PersonalInkProfileStore(url: notFolder.appendingPathComponent("profile.json")))
        model.teach(runID: runID)
        try await finish(model)
        XCTAssertNotNil(model.teachingFailure)
        XCTAssertEqual(model.error, model.teachingFailure)
        XCTAssertNil(model.journal.runs.first?.teachingReceipt)
        XCTAssertEqual(model.journal.runs.first?.records.first?.taught, false)
    }

    private func fixture(_ folder: URL) throws -> (PersonalInkEvaluationStore, UUID) {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var run = PersonalInkEvaluationRun(chartID: UUID(), style: "simpleChordSheet", phase: .beforeCorrections,
                                           pipeline: "test", profile: .init())
        run.status = .complete; run.expectedChordCount = 1
        run.records = [.init(measureIndex: 1, fraction: 0,
            strokes: [InkStroke(points: [InkPoint(x: 0, y: 0), InkPoint(x: 10, y: 20)])],
            fingerprint: "fixture", baseline: "C", personalized: "C", baselineAction: "confirm", personalizedAction: "confirm",
            knownInk: false, recognitionMilliseconds: 1, totalMilliseconds: 1, cacheHit: false, intended: "A")]
        let url = folder.appendingPathComponent("evaluation.json")
        try JSONEncoder().encode(PersonalInkEvaluationJournal(runs: [run])).write(to: url)
        return (PersonalInkEvaluationStore(url: url), run.id)
    }

    private func finish(_ model: PersonalHandwritingEvaluationModel) async throws {
        for _ in 0..<500 {
            if !model.busy { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Evaluation save did not finish")
    }
}
#endif
