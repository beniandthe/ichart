import XCTest
@testable import iChart

final class PersonalInkAfterLearningEligibilityTests: XCTestCase {
    private func stroke(_ x: Double = 0, _ y: Double = 0) -> InkStroke {
        InkStroke(points: [
            InkPoint(x: x, y: y),
            InkPoint(x: x + 4, y: y + 14),
            InkPoint(x: x + 10, y: y + 20)
        ])
    }

    private var chordInk: [InkStroke] {
        [stroke(), stroke(30)]
    }

    private func affine(_ strokes: [InkStroke]) -> [InkStroke] {
        strokes.map { source in
            InkStroke(points: source.points.map { point in
                InkPoint(x: point.x * 2 + 100, y: point.y * 2 - 40, timeOffset: point.timeOffset)
            }, creationTimeOffset: source.creationTimeOffset)
        }
    }

    private func completedBeforeJournal(profile: PersonalInkProfile) -> PersonalInkEvaluationJournal {
        var run = PersonalInkEvaluationRun(
            chartID: UUID(), style: "simpleChordSheet", phase: .beforeCorrections,
            pipeline: "after-learning-eligibility-test", profile: profile
        )
        run.status = .complete
        return PersonalInkEvaluationJournal(runs: [run])
    }

    func testNewGlyphSetupLessonUnlocksAfterLearning() throws {
        var baseline = PersonalInkProfile()
        baseline.isEnabled = true
        let journal = completedBeforeJournal(profile: baseline)

        var candidate = baseline
        XCTAssertTrue(try candidate.learn(
            strokes: [stroke()], label: "m", kind: .glyph, source: .setup
        ))

        XCTAssertTrue(journal.hasCorrectionsSinceBaseline(profile: candidate))
    }

    func testSelectedSavedSymbolLessonUnlocksAfterLearning() throws {
        var baseline = PersonalInkProfile()
        baseline.isEnabled = true
        XCTAssertTrue(try baseline.learn(
            strokes: chordInk, label: "D7", kind: .chord, source: .setup
        ))
        let journal = completedBeforeJournal(profile: baseline)

        var candidate = baseline
        let parent = try XCTUnwrap(candidate.examples.first)
        let review = try PersonalInkSymbolTeachingReview(exampleID: parent.id, profile: candidate)
            .selectingOriginalGroups([[1]])
        let receipt = try review.teach(labels: ["7"], profile: &candidate)
        XCTAssertEqual(receipt.changedSymbolCount, 1)
        let symbol = try XCTUnwrap(candidate.examples.last)
        XCTAssertEqual(symbol.kind, .glyph)
        XCTAssertEqual(symbol.source, .explicitCorrection)
        XCTAssertNotNil(symbol.verifiedSymbolOrigin)

        XCTAssertTrue(journal.hasCorrectionsSinceBaseline(profile: candidate))
    }

    func testDuplicateAdministrativeRemovalAndConfirmedReviewDoNotUnlockAfterLearning() throws {
        var baseline = PersonalInkProfile()
        baseline.isEnabled = true
        XCTAssertTrue(try baseline.learn(
            strokes: [stroke()], label: "m", kind: .glyph, source: .setup
        ))
        XCTAssertTrue(try baseline.learn(
            strokes: [stroke(30)], label: "9", kind: .glyph, source: .setup
        ))
        let journal = completedBeforeJournal(profile: baseline)

        var duplicate = baseline
        XCTAssertFalse(try duplicate.learn(
            strokes: [stroke()], label: "m", kind: .glyph, source: .setup
        ))
        XCTAssertFalse(journal.hasCorrectionsSinceBaseline(profile: duplicate))

        var revisionOnly = baseline
        revisionOnly.revision = UUID()
        XCTAssertFalse(journal.hasCorrectionsSinceBaseline(profile: revisionOnly))

        var toggled = baseline
        toggled.learnsFromReviews.toggle()
        XCTAssertFalse(journal.hasCorrectionsSinceBaseline(profile: toggled))

        var reordered = baseline
        reordered.examples.reverse()
        XCTAssertFalse(journal.hasCorrectionsSinceBaseline(profile: reordered))

        var removed = baseline
        XCTAssertTrue(removed.removeExample(id: try XCTUnwrap(removed.examples.first?.id)))
        XCTAssertFalse(journal.hasCorrectionsSinceBaseline(profile: removed))

        var confirmed = baseline
        XCTAssertTrue(try confirmed.learn(
            strokes: [stroke(60)], label: "7", kind: .glyph, source: .confirmedReview
        ))
        XCTAssertFalse(journal.hasCorrectionsSinceBaseline(profile: confirmed))

        var disabled = baseline
        disabled.isEnabled = false
        XCTAssertFalse(journal.hasCorrectionsSinceBaseline(profile: disabled))
    }

    func testSourceOnlyUpgradeDoesNotUnlockButActualRelabelDoes() throws {
        var baseline = PersonalInkProfile()
        baseline.isEnabled = true
        XCTAssertTrue(try baseline.learn(
            strokes: chordInk, label: "C", kind: .chord, source: .setup
        ))
        let journal = completedBeforeJournal(profile: baseline)
        let baselineID = try XCTUnwrap(baseline.examples.first?.id)

        var sourceOnly = baseline
        XCTAssertTrue(try sourceOnly.learn(
            strokes: chordInk, label: "C", kind: .chord, source: .explicitCorrection
        ))
        XCTAssertEqual(sourceOnly.examples.first?.id, baselineID)
        XCTAssertFalse(journal.hasCorrectionsSinceBaseline(profile: sourceOnly))

        var relabeled = baseline
        XCTAssertTrue(try relabeled.learn(
            strokes: chordInk, label: "D", kind: .chord, source: .explicitCorrection
        ))
        XCTAssertFalse(relabeled.examples.contains { $0.id == baselineID })
        XCTAssertTrue(journal.hasCorrectionsSinceBaseline(profile: relabeled))
    }

    func testResetGenerationRejectsOtherwiseEligibleNewGlyphLesson() throws {
        var baseline = PersonalInkProfile()
        baseline.isEnabled = true
        let journal = completedBeforeJournal(profile: baseline)

        var candidate = baseline
        XCTAssertTrue(try candidate.learn(
            strokes: [stroke()], label: "m", kind: .glyph, source: .setup
        ))
        candidate.generation = UUID()

        XCTAssertFalse(journal.hasCorrectionsSinceBaseline(profile: candidate))
    }

    func testMalformedRecognitionInputAndForbiddenLabelsDoNotUnlockAfterLearning() throws {
        var baseline = PersonalInkProfile()
        baseline.isEnabled = true
        let journal = completedBeforeJournal(profile: baseline)

        var malformed = PersonalInkExample(
            kind: .glyph, label: "m", strokes: [stroke()], source: .setup
        )
        malformed.recognitionStrokes = [InkStroke(points: [
            InkPoint(x: .nan, y: 0), InkPoint(x: 1, y: 2)
        ])]
        XCTAssertFalse(malformed.hasValidRecognitionInput)
        var malformedCandidate = baseline
        malformedCandidate.examples.append(malformed)
        XCTAssertFalse(journal.hasCorrectionsSinceBaseline(profile: malformedCandidate))

        var forbiddenGlyph = baseline
        forbiddenGlyph.examples.append(PersonalInkExample(
            kind: .glyph, label: "ñ", strokes: [stroke()], source: .setup
        ))
        XCTAssertTrue(try XCTUnwrap(forbiddenGlyph.examples.last).hasValidRecognitionInput)
        XCTAssertFalse(journal.hasCorrectionsSinceBaseline(profile: forbiddenGlyph))

        var forbiddenChord = baseline
        forbiddenChord.examples.append(PersonalInkExample(
            kind: .chord, label: "J", strokes: chordInk, source: .explicitCorrection
        ))
        XCTAssertTrue(try XCTUnwrap(forbiddenChord.examples.last).hasValidRecognitionInput)
        XCTAssertFalse(journal.hasCorrectionsSinceBaseline(profile: forbiddenChord))
    }

    func testAffineEquivalentGlyphWithNewIDDoesNotUnlockAfterLearning() throws {
        var baseline = PersonalInkProfile()
        baseline.isEnabled = true
        let original = [stroke()]
        XCTAssertTrue(try baseline.learn(
            strokes: original, label: "m", kind: .glyph, source: .setup
        ))
        let journal = completedBeforeJournal(profile: baseline)

        let transformed = affine(original)
        let transformedShape = try XCTUnwrap(PersonalInkShape(strokes: transformed))
        var duplicate = PersonalInkExample(
            kind: .glyph, label: "m", strokes: transformedShape.normalizedStrokes, source: .setup
        )
        duplicate.recognitionStrokes = transformed
        XCTAssertTrue(duplicate.hasValidRecognitionInput)
        XCTAssertNotEqual(duplicate.id, baseline.examples[0].id)

        var candidate = baseline
        candidate.examples.append(duplicate)
        XCTAssertFalse(journal.hasCorrectionsSinceBaseline(profile: candidate))
    }

    func testPersistedGlyphLessonCanStartAndReloadAfterLearningRun() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let profileURL = folder.appendingPathComponent("profile.json")
        let journalURL = folder.appendingPathComponent("evaluation.json")
        let profileStore = PersonalInkProfileStore(url: profileURL)
        try profileStore.update { $0.isEnabled = true }
        let baseline = profileStore.snapshot().profile

        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(completedBeforeJournal(profile: baseline)).write(to: journalURL)
        try profileStore.update {
            try $0.learn(strokes: [stroke()], label: "m", kind: .glyph, source: .setup)
        }
        let persistedCandidate = PersonalInkProfileStore(url: profileURL).snapshot().profile
        XCTAssertEqual(persistedCandidate.examples.count, 1)
        XCTAssertEqual(persistedCandidate.examples.first?.kind, .glyph)
        XCTAssertEqual(persistedCandidate.examples.first?.source, .setup)

        let store = PersonalInkEvaluationStore(url: journalURL)
        let saved = expectation(description: "after-learning run saved")
        store.start(
            chartID: UUID(), style: "rhythmSectionSheet", phase: .afterCorrections,
            profile: persistedCandidate, pipeline: "after-learning-eligibility-test"
        ) { error in
            XCTAssertNil(error)
            saved.fulfill()
        }
        wait(for: [saved], timeout: 3)

        let reloaded = PersonalInkEvaluationStore(url: journalURL).snapshot()
        XCTAssertNil(reloaded.error)
        let active = try XCTUnwrap(reloaded.journal.activeRun)
        XCTAssertEqual(active.phase, .afterCorrections)
        XCTAssertEqual(active.profile, persistedCandidate)
        XCTAssertEqual(active.profile.examples.first?.recognitionInput, [stroke()])
    }
}
