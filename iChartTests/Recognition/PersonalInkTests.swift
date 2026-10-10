import XCTest
@testable import iChart

final class PersonalInkTests: XCTestCase {
    private let baseline = ChordInkRecognitionResult(rawCandidates: [], glyphCandidates: [], match: nil, confidence: 0)

    func testProfileIsOptInAndEmptyProfileLeavesNativeEvidenceUntouched() throws {
        var profile = PersonalInkProfile()
        try profile.learn(strokes: a, label: "A", kind: .chord, source: .setup)
        let result = PersonalInkSnapshot(profile: profile).applying(to: baseline, strokes: a)
        XCTAssertNil(result.personalSuggestion)
        XCTAssertEqual(result.match, baseline.match)
        XCTAssertEqual(result.candidateScores, baseline.candidateScores)
        XCTAssertEqual(result.confidence, baseline.confidence)
    }

    func testWholeChordMatchesChangedScaleTranslationAndReversedStrokeOrder() throws {
        let profile = try learned(a, label: "Am7")
        let query = transformed(a, scale: 2.4, dx: 195, dy: -80, reverse: true)
        let result = PersonalInkSnapshot(profile: profile).applying(to: baseline, strokes: query)
        XCTAssertEqual(result.personalSuggestion?.text, ChordRecognitionCompendium.match("Am7")?.displayText)
        XCTAssertEqual(result.personalSuggestion?.source, .wholeChord)
        XCTAssertNil(result.match, "Personal matching must not impersonate the base model")
    }

    func testSmallGeometryVariationMatchesWithoutExactReplay() throws {
        let snapshot = PersonalInkSnapshot(profile: try learned(a, label: "A"))
        var fresh = a
        fresh[0].points[1].x += 1.5
        fresh[1].points[1].y += 0.8
        XCTAssertFalse(snapshot.wasAlreadyLearned(strokes: fresh))
        XCTAssertEqual(snapshot.applying(to: baseline, strokes: fresh).personalSuggestion?.text, "A")
    }

    func testDistantInkDoesNotForceNearestLabel() throws {
        let snapshot = PersonalInkSnapshot(profile: try learned(a, label: "A"))
        XCTAssertNil(snapshot.applying(to: baseline, strokes: horizontal).personalSuggestion)
    }

    func testConflictingLabelsAbstainEvenWithExactGeometry() throws {
        var profile = try learned(a, label: "A")
        try profile.learn(strokes: a, label: "B", kind: .chord, source: .setup)
        XCTAssertNil(PersonalInkSnapshot(profile: profile).applying(to: baseline, strokes: a).personalSuggestion)
    }

    func testSymbolsComposeAChordNeverStoredAsAWholeExample() throws {
        var profile = PersonalInkProfile()
        profile.isEnabled = true
        try profile.learn(strokes: a, label: "A", kind: .glyph, source: .setup)
        try profile.learn(strokes: seven, label: "7", kind: .glyph, source: .setup)
        let query = a + transformed(seven, scale: 0.8, dx: 32, dy: 1)
        let suggestion = PersonalInkSnapshot(profile: profile).applying(to: baseline, strokes: query).personalSuggestion
        XCTAssertEqual(suggestion?.text, "A7")
        XCTAssertEqual(suggestion?.source, .symbols)
        XCTAssertTrue(profile.examples.allSatisfy { $0.kind == .glyph })
    }

    func testExplicitCorrectionRepairsOnlyTheExactPreviouslyMislabeledInk() throws {
        var profile = try learned(a, label: "B")
        try profile.learn(strokes: a, label: "A", kind: .chord, source: .explicitCorrection)
        XCTAssertEqual(profile.examples.count, 1)
        XCTAssertEqual(PersonalInkSnapshot(profile: profile).applying(to: baseline, strokes: a).personalSuggestion?.text, "A")
    }

    func testUnknownSuffixCannotBecomeARecognizedPrefix() throws {
        var profile = PersonalInkProfile()
        profile.isEnabled = true
        try profile.learn(strokes: a, label: "A", kind: .glyph, source: .setup)
        let unknownSuffix = transformed(seven, scale: 0.8, dx: 32, dy: 1)
        XCTAssertNil(PersonalInkSnapshot(profile: profile).applying(to: baseline, strokes: a + unknownSuffix).personalSuggestion)
    }

    func testExplicitMissingMajorSymbolEnablesUnseenWholeChordComposition() throws {
        let root = [InkStroke(points: [InkPoint(x: 20, y: 0), InkPoint(x: 2, y: 4),
            InkPoint(x: 0, y: 20), InkPoint(x: 2, y: 36), InkPoint(x: 20, y: 40)])]
        let triangle = [InkStroke(points: [InkPoint(x: 0, y: 18), InkPoint(x: 9, y: 0),
            InkPoint(x: 18, y: 18), InkPoint(x: 0, y: 18)])]
        var profile = PersonalInkProfile()
        profile.isEnabled = true
        try profile.learn(strokes: root, label: "C", kind: .glyph, source: .setup)
        try profile.learn(strokes: seven, label: "7", kind: .glyph, source: .setup)
        let query = root + transformed(triangle, scale: 0.65, dx: 35, dy: 0)
            + transformed(seven, scale: 0.65, dx: 55, dy: 0)
        XCTAssertNil(PersonalInkSnapshot(profile: profile).suggestion(strokes: query))
        try profile.learn(strokes: triangle, label: "△", kind: .glyph, source: .setup)
        let suggestion = try XCTUnwrap(PersonalInkSnapshot(profile: profile).suggestion(strokes: query))
        XCTAssertEqual(suggestion.text, "C△7")
        XCTAssertEqual(suggestion.source, .symbols)
        XCTAssertTrue(profile.examples.allSatisfy { $0.kind == .glyph }, "No whole-chord memorization")
        XCTAssertEqual(suggestion.correctionSupportCount, 0)
    }

    func testTrustedNativeChoiceStaysFirstWithoutExtraReviewWhenPersonalChoiceDisagrees() throws {
        var native = baseline
        native.match = ChordRecognitionCompendium.match("C")
        native.confidence = 4.8
        let original = ChordInkRecognitionPolicy.decision(for: native)
        let result = PersonalInkSnapshot(profile: try learned(a, label: "A")).applying(to: native, strokes: a)
        let resolution = ChordInkRenderResolutionPolicy.resolution(for: result, drawingData: Data(), correctionMemory: .init())
        XCTAssertEqual(ChordInkRecognitionPolicy.decision(for: result), original)
        XCTAssertEqual(resolution.primaryDecision, original)
        XCTAssertEqual(original.action, .trusted)
        XCTAssertEqual(resolution.decision, original)
        XCTAssertEqual(Array(resolution.candidateTexts.prefix(2)), ["C", "A"])
        XCTAssertEqual(result.match?.displayText, "C")
    }

    func testUpgradingSetupMatchToCorrectionPreservesNativeDefaultAndSelectableAlternative() throws {
        var native = baseline
        native.match = ChordRecognitionCompendium.match("C")
        native.confidence = 1
        var profile = try learned(a, label: "A")
        let before = PersonalInkSnapshot(profile: profile).applying(to: native, strokes: a)
        XCTAssertEqual(ChordInkRenderResolutionPolicy.personalSelection(for: before).text, "C")
        XCTAssertEqual(before.personalSuggestion?.correctionSupportCount, 0)
        XCTAssertTrue(try profile.learn(strokes: a, label: "A", kind: .chord, source: .explicitCorrection))
        XCTAssertEqual(profile.examples.count, 1, "Explicit teaching upgrades provenance, not duplicate weight")
        let after = PersonalInkSnapshot(profile: profile).applying(to: native, strokes: a)
        let resolution = ChordInkRenderResolutionPolicy.resolution(for: after, drawingData: Data(), correctionMemory: .init())
        XCTAssertEqual(after.personalSuggestion?.correctionSupportCount, 1)
        XCTAssertEqual(resolution.decision.acceptedText, "C")
        XCTAssertEqual(resolution.decision.action, .confirm)
        let selection = ChordInkRenderResolutionPolicy.personalSelection(for: after)
        XCTAssertEqual(selection.disposition, .alternative)
        XCTAssertFalse(selection.prefersPersonal)
        XCTAssertEqual(Array(resolution.candidateTexts.prefix(2)), ["C", "A"])
        XCTAssertEqual(after.match, native.match)
        XCTAssertFalse(try profile.learn(strokes: a, label: "A", kind: .chord, source: .explicitCorrection))
    }

    func testDistantCorrectionDoesNotLendAuthorityToNearbySetupMatch() throws {
        var profile = try learned(a, label: "A")
        try profile.learn(strokes: horizontal, label: "A", kind: .chord, source: .explicitCorrection)
        let suggestion = try XCTUnwrap(PersonalInkSnapshot(profile: profile).suggestion(strokes: a))
        XCTAssertEqual(suggestion.supportingExampleCount, 1)
        XCTAssertEqual(suggestion.correctionSupportCount, 0)
    }

    func testDisablingProfileRemovesCorrectedSuggestionsWithoutErasingExamples() throws {
        var profile = try learned(a, label: "A")
        try profile.learn(strokes: a, label: "A", kind: .chord, source: .explicitCorrection)
        profile.isEnabled = false
        XCTAssertNil(PersonalInkSnapshot(profile: profile).suggestion(strokes: a))
        XCTAssertEqual(profile.examples.count, 1)
    }

    func testPersonalAgreementPreservesTrustedAndConfirmationDecisions() throws {
        for confidence in [1.0, 4.8] {
            var native = baseline
            native.match = ChordRecognitionCompendium.match("A")
            native.confidence = confidence
            let expected = ChordInkRecognitionPolicy.decision(for: native)
            let result = PersonalInkSnapshot(profile: try learned(a, label: "A")).applying(to: native, strokes: a)
            let resolution = ChordInkRenderResolutionPolicy.resolution(for: result, drawingData: Data(), correctionMemory: .init())
            XCTAssertEqual(resolution.decision, expected)
            XCTAssertEqual(resolution.candidateTexts.first, "A")
            XCTAssertEqual(resolution.candidateTexts.filter { $0 == "A" }.count, 1)
        }
    }

    func testPersonalRecoveryNeverCreatesTrustedNativeEvidence() throws {
        let result = PersonalInkSnapshot(profile: try learned(a, label: "A")).applying(to: baseline, strokes: a)
        let resolution = ChordInkRenderResolutionPolicy.resolution(for: result, drawingData: Data(), correctionMemory: .init())
        XCTAssertEqual(resolution.decision.acceptedText, "A")
        XCTAssertEqual(resolution.decision.action, .confirm)
        XCTAssertNil(result.match)
        XCTAssertEqual(result.confidence, 0)
    }

    func testPersonalAgreementDoesNotBypassPriorRejectedTrustedCandidate() throws {
        var native = baseline
        native.match = ChordRecognitionCompendium.match("A"); native.confidence = 4.8
        let result = PersonalInkSnapshot(profile: try learned(a, label: "A")).applying(to: native, strokes: a)
        let data = Data("previously rejected".utf8)
        var memory = ChordInkUserCorrectionMemory()
        memory.recordRejectedTrustedCandidate(acceptedText: "A", drawingData: data,
            candidateSignature: ChordInkUserCorrectionMemoryPolicy.candidateSignature(from: ChordInkRenderResolutionPolicy.candidateTexts(for: result)))
        let resolution = ChordInkRenderResolutionPolicy.resolution(for: result, drawingData: data, correctionMemory: memory)
        XCTAssertEqual(resolution.decision.action, .confirm)
        XCTAssertTrue(resolution.decision.reason.contains("previously corrected"))
    }

    func testInvalidInputAndUnsupportedLabelsCannotTrain() {
        var profile = PersonalInkProfile()
        XCTAssertThrowsError(try profile.learn(strokes: [], label: "A", kind: .chord, source: .setup))
        XCTAssertThrowsError(try profile.learn(strokes: a, label: "not a chord", kind: .chord, source: .practice))
        XCTAssertThrowsError(try profile.learn(strokes: a, label: "Z", kind: .glyph, source: .setup))
        XCTAssertNil(PersonalInkShape(strokes: [InkStroke(points: [InkPoint(x: .nan, y: 0), InkPoint(x: 2, y: 2)])]))
        XCTAssertNil(PersonalInkShape(strokes: Array(repeating: a[0], count: 65)))
        XCTAssertTrue(profile.examples.isEmpty)
    }

    func testExactRepeatedConfirmationDoesNotFillProfile() throws {
        var profile = try learned(a, label: "A")
        for _ in 0..<20 {
            XCTAssertFalse(try profile.learn(strokes: a, label: "A", kind: .chord, source: .confirmedReview))
        }
        XCTAssertEqual(profile.examples.count, 1)
    }

    func testReviewingTransformedCopiesDoesNotDuplicateOrDowngradeCorrectionEvidence() throws {
        var profile = try learned(a, label: "A")
        try profile.learn(strokes: a, label: "A", kind: .chord, source: .explicitCorrection)
        let revision = profile.revision
        let originalID = try XCTUnwrap(profile.examples.first?.id)
        for index in 1...12 {
            let sameInk = transformed(a, scale: 0.7 + Double(index) * 0.13,
                                      dx: 195 + Double(index) * 12.7, dy: -80 + Double(index) * 8.1)
            XCTAssertFalse(try profile.learn(strokes: sameInk, label: "A", kind: .chord, source: .confirmedReview))
        }
        XCTAssertEqual(profile.examples.count, 1)
        XCTAssertEqual(profile.examples.first?.id, originalID)
        XCTAssertEqual(profile.examples.first?.source, .explicitCorrection)
        XCTAssertEqual(profile.revision, revision)
        let suggestion = try XCTUnwrap(PersonalInkSnapshot(profile: profile).suggestion(strokes: a))
        XCTAssertEqual(suggestion.supportingExampleCount, 1)
        XCTAssertEqual(suggestion.correctionSupportCount, 1)
    }

    func testCorrectionRepairsTransformedCopyWithoutDeletingNearbyDifferentHandwriting() throws {
        var profile = try learned(a, label: "B")
        var differentInk = a
        differentInk[0].points[1].x += 0.5
        try profile.learn(strokes: differentInk, label: "B", kind: .chord, source: .setup)
        let differentID = try XCTUnwrap(profile.examples.last?.id)
        let sameInk = transformed(a, scale: 2.4, dx: 195, dy: -80)
        try profile.learn(strokes: sameInk, label: "A", kind: .chord, source: .explicitCorrection)
        XCTAssertEqual(profile.examples.count, 2)
        XCTAssertEqual(profile.examples.filter { $0.label == "B" }.map(\.id), [differentID])
        XCTAssertEqual(profile.examples.filter { $0.label == "A" }.first?.source, .explicitCorrection)
    }

    func testSubpixelGeometryChangesAreNotDeduplicatedByRasterSimilarity() throws {
        var profile = try learned(a, label: "A")
        var differentInk = a
        differentInk[0].points[1].x += 0.00001
        XCTAssertTrue(try profile.learn(strokes: differentInk, label: "A", kind: .chord, source: .confirmedReview))
        XCTAssertEqual(profile.examples.count, 2)
    }

    func testDuplicateReviewLeavesPersistedProfileAndRevisionUnchanged() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("profile.json")
        let store = PersonalInkProfileStore(url: url)
        try store.update {
            $0 = try learned(a, label: "A")
            try $0.learn(strokes: a, label: "A", kind: .chord, source: .explicitCorrection)
        }
        let before = store.snapshot().profile
        let savedBytes = try Data(contentsOf: url)
        try store.update {
            try $0.learn(strokes: transformed(a, scale: 2.4, dx: 195, dy: -80),
                         label: "A", kind: .chord, source: .confirmedReview)
        }
        XCTAssertEqual(store.snapshot().profile.revision, before.revision)
        XCTAssertEqual(try Data(contentsOf: url), savedBytes)
        try store.update { $0.isEnabled = false }
        XCTAssertNotEqual(store.snapshot().profile.revision, before.revision, "An actual opt-out must invalidate personal choices")
        XCTAssertFalse(PersonalInkProfileStore(url: url).snapshot().profile.isEnabled)
    }

    func testExamplesPerLabelAreBounded() throws {
        var profile = try learned(a, label: "A")
        for i in 1...12 {
            var variant = a
            variant[0].points[1].x += Double(i) / 4
            try profile.learn(strokes: variant, label: "A", kind: .chord, source: .confirmedReview)
        }
        XCTAssertEqual(profile.examples.count, PersonalInkProfile.maximumExamplesPerLabel)
    }

    func testProfilePersistsReloadsDisablesAndResetsWithoutChartAccess() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("profile.json")
        let store = PersonalInkProfileStore(url: url)
        try store.update { $0 = try learned(a, label: "A") }
        let restored = PersonalInkProfileStore(url: url)
        XCTAssertEqual(restored.snapshot().profile.examples.count, 1)
        XCTAssertEqual(restored.snapshot().applying(to: baseline, strokes: a).personalSuggestion?.text, "A")
        try restored.update { $0.isEnabled = false }
        XCTAssertNil(restored.snapshot().applying(to: baseline, strokes: a).personalSuggestion)
        XCTAssertEqual(restored.snapshot().profile.examples.count, 1)
        try restored.reset()
        XCTAssertTrue(PersonalInkProfileStore(url: url).snapshot().profile.examples.isEmpty)
        XCTAssertFalse(restored.snapshot().profile.isEnabled)
    }

    func testRemovingOneExamplePreservesSameLabelNeighborsAndFrozenProfile() throws {
        var profile = try learned(a, label: "A")
        try profile.learn(strokes: seven, label: "A", kind: .glyph, source: .setup)
        try profile.learn(strokes: horizontal, label: "A", kind: .glyph, source: .setup)
        profile.learnsFromReviews = false
        let frozen = profile
        let selected = try XCTUnwrap(profile.examples.dropFirst().first)
        XCTAssertTrue(profile.removeExample(id: selected.id))
        XCTAssertEqual(profile.examples, frozen.examples.filter { $0.id != selected.id })
        XCTAssertEqual(profile.examples.count, 2)
        XCTAssertEqual(frozen.examples.count, 3)
        XCTAssertEqual(profile.generation, frozen.generation)
        XCTAssertEqual(profile.isEnabled, frozen.isEnabled)
        XCTAssertEqual(profile.learnsFromReviews, frozen.learnsFromReviews)
        XCTAssertNotEqual(profile.revision, frozen.revision)
        let revision = profile.revision
        XCTAssertFalse(profile.removeExample(id: selected.id))
        XCTAssertFalse(profile.removeExample(id: UUID()))
        XCTAssertEqual(profile.revision, revision)
    }

    func testRemovedExampleIsNotSuggestedByNewSnapshotButFrozenSnapshotRemainsIntact() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("profile.json")
        let store = PersonalInkProfileStore(url: url)
        try store.update { $0 = try learned(a, label: "A") }
        let frozen = store.snapshot()
        let selected = try XCTUnwrap(frozen.profile.examples.first)
        try store.update { XCTAssertTrue($0.removeExample(id: selected.id)) }
        XCTAssertNil(store.snapshot().suggestion(strokes: a))
        XCTAssertEqual(frozen.suggestion(strokes: a)?.text, "A")
        XCTAssertTrue(PersonalInkProfileStore(url: url).snapshot().profile.examples.isEmpty)
        XCTAssertNotEqual(frozen.profile.revision, store.snapshot().profile.revision)
    }

    func testRecognitionDoesNotMutateTrainingDataAndOldSnapshotIsStable() throws {
        let profile = try learned(a, label: "A")
        let snapshot = PersonalInkSnapshot(profile: profile)
        for _ in 0..<10 { _ = snapshot.applying(to: baseline, strokes: a) }
        XCTAssertEqual(snapshot.profile.examples.count, 1)
        XCTAssertEqual(snapshot.profile.revision, profile.revision)
        XCTAssertTrue(snapshot.wasAlreadyLearned(strokes: a))
    }

    func testCorruptProfileIsDisabledAndReported() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("profile.json")
        try Data("invalid".utf8).write(to: url)
        let store = PersonalInkProfileStore(url: url)
        XCTAssertNotNil(store.loadError)
        XCTAssertFalse(store.snapshot().profile.isEnabled)
        try store.reset()
        XCTAssertNil(store.loadError)
    }

    func testFailedSaveDoesNotPublishUnpersistedProfile() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data().write(to: file)
        let store = PersonalInkProfileStore(url: file.appendingPathComponent("profile.json"))
        XCTAssertThrowsError(try store.update { $0 = try learned(a, label: "A") })
        XCTAssertTrue(store.snapshot().profile.examples.isEmpty)
    }

    func testFullProfileLookupRemainsBounded() throws {
        var profile = PersonalInkProfile()
        profile.isEnabled = true
        profile.examples = (0..<PersonalInkProfile.maximumExamples).map { index in
            PersonalInkExample(kind: .chord, label: ["A", "B", "C", "D", "E", "F", "G"][index % 7],
                               strokes: transformed(a, scale: 1 + Double(index) / 1000, dx: Double(index), dy: 0), source: .setup)
        }
        let snapshot = PersonalInkSnapshot(profile: profile)
        let start = Date()
        for _ in 0..<30 { _ = snapshot.applying(to: baseline, strokes: a) }
        let averageMilliseconds = Date().timeIntervalSince(start) * 1000 / 30
        print("PERSONAL_INK_FULL_PROFILE_MEAN_MS=\(averageMilliseconds)")
        XCTAssertLessThan(averageMilliseconds, 100, "Personal lookup is off-main but must still have a bounded per-target cost")
        XCTAssertEqual(snapshot.profile.examples.count, PersonalInkProfile.maximumExamples)
    }

    private func learned(_ strokes: [InkStroke], label: String) throws -> PersonalInkProfile {
        var profile = PersonalInkProfile()
        profile.isEnabled = true
        try profile.learn(strokes: strokes, label: label, kind: .chord, source: .setup)
        return profile
    }
    private var a: [InkStroke] { [stroke([(0, 28), (9, 0), (18, 28)]), stroke([(4, 18), (14, 18)])] }
    private var seven: [InkStroke] { [stroke([(0, 0), (16, 0), (3, 28)])] }
    private var horizontal: [InkStroke] { [stroke([(0, 0), (30, 0)])] }
    private func stroke(_ points: [(Double, Double)]) -> InkStroke {
        InkStroke(points: points.map { InkPoint(x: $0.0, y: $0.1) })
    }
    private func transformed(_ strokes: [InkStroke], scale: Double, dx: Double, dy: Double, reverse: Bool = false) -> [InkStroke] {
        let result = strokes.map { stroke in
            let points = stroke.points.map { InkPoint(x: $0.x * scale + dx, y: $0.y * scale + dy) }
            return InkStroke(points: reverse ? points.reversed() : points)
        }
        return reverse ? result.reversed() : result
    }
}
