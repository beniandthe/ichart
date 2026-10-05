import XCTest
@testable import iChart

/// Synthetic contracts for explicit source-stroke selection and lesson wiring.
/// These fixtures do not measure handwriting recognition accuracy.
final class PersonalInkSymbolSelectionDraftTests: XCTestCase {
    private func ink(count: Int = 6) -> [InkStroke] {
        (0..<count).map { index in
            // Acquisition order deliberately differs from horizontal order.
            let x = Double((count - index) * 25)
            let bend = Double(index + 1)
            return InkStroke(points: [
                .init(x: x, y: 0, timeOffset: 0),
                .init(x: x + bend, y: 12, timeOffset: 0.13),
                .init(x: x + 8, y: 20, timeOffset: 0.31)
            ], creationTimeOffset: Double(index) * 0.5)
        }
    }

    private func prepared(count: Int = 6, tracked: Bool = false)
        throws -> (PersonalInkProfile, PersonalInkSymbolTeachingReview) {
        var profile = PersonalInkProfile()
        profile.isEnabled = true
        var example = PersonalInkExample(kind: .chord, label: "D7", strokes: ink(count: count),
                                         source: .explicitCorrection)
        if tracked {
            let context = PersonalInkCaptureContext(
                sessionID: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
                captureID: UUID(uuidString: "20000000-0000-0000-0000-000000000002")!,
                capturedAt: Date(timeIntervalSinceReferenceDate: 100), origin: .savedEvaluation,
                chartStyle: "simple-chord-sheet")
            example.learningProvenance = try .make(context: context,
                taughtAt: Date(timeIntervalSinceReferenceDate: 101),
                originalInput: example.strokes, storedInput: example.strokes)
        }
        profile.examples = [example]
        return (profile, try .init(exampleID: example.id, profile: profile))
    }

    private func preparedDraft() throws -> PersonalInkSymbolSelectionDraft {
        let (_, review) = try prepared()
        return .init(review: try review.selectingOriginalGroups([[0, 1], [2, 3], [4, 5]]))
    }

    private func assertCoverage(_ draft: PersonalInkSymbolSelectionDraft,
                                file: StaticString = #filePath, line: UInt = #line) {
        let assigned = draft.groups.flatMap { $0 }
        XCTAssertEqual(Set(assigned).count, assigned.count, file: file, line: line)
        XCTAssertTrue(Set(assigned).isDisjoint(with: draft.unassignedStrokeIndexes), file: file, line: line)
        XCTAssertEqual((assigned + draft.unassignedStrokeIndexes).sorted(),
                       Array(draft.review.source.strokes.indices), file: file, line: line)
    }

    func testOpeningDraftIsLabelBlindAndKeepsAllOriginalInkAvailable() throws {
        let (profile, review) = try prepared()
        let before = profile
        let draft = PersonalInkSymbolSelectionDraft(review: review)
        XCTAssertEqual(draft.labels, Array(repeating: nil, count: draft.groups.count))
        XCTAssertEqual(draft.selectedSymbolCount, 0)
        XCTAssertEqual(draft.review.source, before.examples[0])
        XCTAssertEqual(profile, before)
        assertCoverage(draft)
        for piece in review.pieces {
            XCTAssertEqual(piece.strokes, piece.originalStrokeIndexes.map { review.source.strokes[$0] })
        }
    }

    func testExplicitPartialSelectionKeepsSourceOrderTimingBoundsAndComplement() throws {
        let (profile, review) = try prepared()
        let selected = try review.selectingOriginalGroups([[5, 2, 0], [4]])
        XCTAssertEqual(selected.source, review.source)
        XCTAssertEqual(selected.profileGeneration, review.profileGeneration)
        XCTAssertEqual(selected.pieces.map(\.originalStrokeIndexes), [[0, 2, 5], [4]])
        XCTAssertEqual(selected.pieces[0].strokes, [0, 2, 5].map { review.source.strokes[$0] })
        XCTAssertEqual(selected.pieces[0].strokes.map(\.bounds),
                       [0, 2, 5].map { review.source.strokes[$0].bounds })
        XCTAssertEqual(selected.pieces[0].strokes.map(\.creationTimeOffset), [0, 1, 2.5])
        XCTAssertEqual(selected.pieces[0].strokes.map { $0.points.map(\.timeOffset) },
                       Array(repeating: [0, 0.13, 0.31], count: 3))
        let draft = PersonalInkSymbolSelectionDraft(review: selected)
        XCTAssertEqual(draft.unassignedStrokeIndexes, [1, 3])
        assertCoverage(draft)
        XCTAssertEqual(profile.examples, [review.source])
    }

    func testTransferSplitMergeAndRemoveClearOnlyAffectedLabels() throws {
        var draft = try preparedDraft()
        try draft.setLabel("D", forPiece: 0)
        try draft.setLabel("#", forPiece: 1)
        try draft.setLabel("7", forPiece: 2)
        XCTAssertEqual(draft.selectedSymbolCount, 3)

        try draft.replacePiece(at: 0, withStrokeIndexes: [2, 0])
        XCTAssertEqual(draft.groups, [[0, 2], [3], [4, 5]])
        XCTAssertEqual(draft.labels, [nil, nil, "7"])
        XCTAssertEqual(draft.unassignedStrokeIndexes, [1])
        assertCoverage(draft)

        try draft.setLabel("D", forPiece: 0)
        try draft.setLabel("b", forPiece: 1)
        try draft.replacePiece(at: 0, withStrokeIndexes: [0])
        XCTAssertEqual(draft.groups, [[0], [3], [4, 5]])
        XCTAssertEqual(draft.labels, [nil, "b", "7"])
        XCTAssertEqual(draft.unassignedStrokeIndexes, [1, 2])
        assertCoverage(draft)

        try draft.replacePiece(at: nil, withStrokeIndexes: [2, 1])
        XCTAssertEqual(draft.groups, [[0], [3], [4, 5], [1, 2]])
        XCTAssertEqual(draft.labels, [nil, "b", "7", nil])
        XCTAssertTrue(draft.unassignedStrokeIndexes.isEmpty)
        try draft.setLabel("D", forPiece: 0)
        try draft.setLabel("#", forPiece: 3)
        try draft.replacePiece(at: 0, withStrokeIndexes: [3, 0])
        XCTAssertEqual(draft.groups, [[0, 3], [4, 5], [1, 2]])
        XCTAssertEqual(draft.labels, [nil, "7", "#"])
        assertCoverage(draft)

        try draft.removePiece(at: 0)
        XCTAssertEqual(draft.groups, [[4, 5], [1, 2]])
        XCTAssertEqual(draft.labels, ["7", "#"])
        XCTAssertEqual(draft.unassignedStrokeIndexes, [0, 3])
        XCTAssertEqual(draft.selectedSymbolCount, 2)
        assertCoverage(draft)
    }

    func testNoOpReplacementPreservesExplicitLabelAndOtherGroups() throws {
        var draft = try preparedDraft()
        try draft.setLabel("D", forPiece: 0)
        try draft.setLabel("7", forPiece: 2)
        let groups = draft.groups, labels = draft.labels
        try draft.replacePiece(at: 0, withStrokeIndexes: [1, 0])
        XCTAssertEqual(draft.groups, groups)
        XCTAssertEqual(draft.labels, labels)
        try draft.setLabel(nil, forPiece: 0)
        XCTAssertEqual(draft.groups, groups)
        XCTAssertEqual(draft.labels, [nil, nil, "7"])
    }

    func testInvalidDraftEditsAreAtomic() throws {
        var draft = try preparedDraft()
        try draft.setLabel("D", forPiece: 0)
        try draft.setLabel("7", forPiece: 2)
        let groups = draft.groups, labels = draft.labels
        for indexes in [[], [0, 0], [-1], [6], [0, 6]] {
            XCTAssertThrowsError(try draft.replacePiece(at: 0, withStrokeIndexes: indexes))
            XCTAssertEqual(draft.groups, groups)
            XCTAssertEqual(draft.labels, labels)
        }
        for index in [-1, 3] {
            XCTAssertThrowsError(try draft.replacePiece(at: index, withStrokeIndexes: [0]))
            XCTAssertThrowsError(try draft.removePiece(at: index))
            XCTAssertThrowsError(try draft.setLabel("D", forPiece: index))
            XCTAssertEqual(draft.groups, groups)
            XCTAssertEqual(draft.labels, labels)
        }
        for label in ["", "H", "D7"] {
            XCTAssertThrowsError(try draft.setLabel(label, forPiece: 0))
            XCTAssertEqual(draft.groups, groups)
            XCTAssertEqual(draft.labels, labels)
        }
        assertCoverage(draft)
    }

    func testReviewRejectsDuplicateRangeEmptyAndTooManyGroupsWithoutChangingSource() throws {
        let (profile, review) = try prepared(count: 17)
        let before = profile
        XCTAssertTrue(review.pieces.isEmpty, "An oversized automatic proposal must leave the source available for manual selection")
        XCTAssertEqual(review.unassignedStrokeIndexes, Array(0..<17))
        let manuallySelected = try review.selectingOriginalGroups([[16, 0]])
        XCTAssertEqual(manuallySelected.pieces.map(\.originalStrokeIndexes), [[0, 16]])
        XCTAssertEqual(manuallySelected.pieces[0].strokes, [review.source.strokes[0], review.source.strokes[16]])
        XCTAssertEqual(manuallySelected.source, review.source)
        for groups in [[[0, 0]], [[0], [0]], [[-1]], [[17]], [[]],
                       (0..<17).map { [$0] }] {
            XCTAssertThrowsError(try review.selectingOriginalGroups(groups))
            XCTAssertEqual(review.source, before.examples[0])
            XCTAssertEqual(profile, before)
        }
        let empty = try review.selectingOriginalGroups([])
        XCTAssertTrue(empty.pieces.isEmpty)
        let draft = PersonalInkSymbolSelectionDraft(review: empty)
        XCTAssertEqual(draft.unassignedStrokeIndexes, Array(0..<17))
        assertCoverage(draft)
    }

    func testSeventeenthPieceFailsAtomicallyAndAllRemainingInkStaysAvailable() throws {
        let (_, review) = try prepared(count: 17)
        var draft = PersonalInkSymbolSelectionDraft(review: try review.selectingOriginalGroups([]))
        for index in 0..<16 { try draft.replacePiece(at: nil, withStrokeIndexes: [index]) }
        try draft.setLabel("D", forPiece: 0)
        let groups = draft.groups, labels = draft.labels
        XCTAssertThrowsError(try draft.replacePiece(at: nil, withStrokeIndexes: [16]))
        XCTAssertEqual(draft.groups, groups)
        XCTAssertEqual(draft.labels, labels)
        XCTAssertEqual(draft.unassignedStrokeIndexes, [16])
        assertCoverage(draft)
    }

    func testNoLabelsAndInvalidLaterLabelCannotPartiallyTeachRepairedSelections() throws {
        var (profile, review) = try prepared()
        let selected = try review.selectingOriginalGroups([[0, 3], [2, 5]])
        let before = profile
        for labels: [String?] in [[nil, nil], ["D", "invalid"], ["D"], []] {
            XCTAssertThrowsError(try selected.teach(labels: labels, profile: &profile))
            XCTAssertEqual(profile, before)
        }
    }

    func testRepairedSelectionCannotTeachAfterResetOptOutDeletionOrSourceEdit() throws {
        let (original, review) = try prepared()
        var draft = PersonalInkSymbolSelectionDraft(review: try review.selectingOriginalGroups([[3, 0]]))
        try draft.setLabel("D", forPiece: 0)
        let selected = try draft.makeReview()
        for variation in 0..<5 {
            var profile = original
            switch variation {
            case 0: profile.generation = UUID()
            case 1: profile.isEnabled = false
            case 2: profile.examples.removeAll()
            case 3: profile.examples[0].label = "C7"
            default: profile.examples[0].strokes[0].points[0].x += 1
            }
            let before = profile
            XCTAssertThrowsError(try selected.teach(labels: draft.labels, profile: &profile))
            XCTAssertEqual(profile, before)
        }
    }

    func testSelectedIndicesAndExactInputProvenancePersistWithoutChangingSavedChord() throws {
        var (profile, review) = try prepared(tracked: true)
        let parent = review.source
        var draft = PersonalInkSymbolSelectionDraft(review: try review.selectingOriginalGroups([[3, 0], [5, 2]]))
        try draft.setLabel("D", forPiece: 0)
        try draft.setLabel("7", forPiece: 1)
        let selected = try draft.makeReview()
        let receipt = try selected.teach(labels: draft.labels, profile: &profile)
        XCTAssertEqual(receipt.selectedSymbolCount, 2)
        XCTAssertEqual(receipt.changedSymbolCount, 2)
        XCTAssertEqual(profile.examples.first, parent)
        XCTAssertEqual(profile.generation, review.profileGeneration)
        let glyphs = profile.examples.filter { $0.kind == .glyph }
        XCTAssertEqual(glyphs.map(\.label), ["D", "7"])
        for (glyph, piece) in zip(glyphs, selected.pieces) {
            XCTAssertEqual(glyph.verifiedSymbolOrigin, .init(chordExampleID: parent.id,
                chordLabel: parent.label, originalStrokeIndexes: piece.originalStrokeIndexes))
            XCTAssertEqual(glyph.strokes, try XCTUnwrap(PersonalInkShape(strokes: piece.strokes)).normalizedStrokes)
            XCTAssertEqual(glyph.recognitionStrokes, piece.strokes)
            XCTAssertEqual(glyph.recognitionInput, piece.strokes)
            let provenance = try XCTUnwrap(glyph.learningProvenance)
            let parentContext = try XCTUnwrap(parent.learningProvenance).context
            XCTAssertEqual(provenance.context.sessionID, parentContext.sessionID)
            XCTAssertEqual(provenance.context.captureID, parentContext.captureID)
            XCTAssertEqual(provenance.context.capturedAt, parentContext.capturedAt)
            XCTAssertEqual(provenance.context.chartStyle, parentContext.chartStyle)
            XCTAssertEqual(provenance.context.origin, .selectedSavedSymbol)
            XCTAssertEqual(provenance.originalInputSHA256,
                           try PersonalInkLearningProvenance.inputSHA256(strokes: piece.strokes))
            XCTAssertEqual(provenance.storedInputSHA256,
                           try PersonalInkLearningProvenance.inputSHA256(strokes: piece.strokes))
            XCTAssertEqual(provenance.version, PersonalInkLearningProvenance.currentVersion)
            XCTAssertEqual(provenance.storedInputRole, .recognitionInput)
            XCTAssertNoThrow(try provenance.validate(example: glyph))
        }
        XCTAssertEqual(try JSONDecoder().decode(PersonalInkProfile.self, from: JSONEncoder().encode(profile)), profile)
    }

    func testFullProfileRejectsRepairedLessonAtomicallyWithoutEvictingSource() throws {
        var (profile, review) = try prepared()
        profile.examples += (1..<PersonalInkProfile.maximumExamples).map { _ in
            PersonalInkExample(kind: .chord, label: "C", strokes: ink(), source: .setup)
        }
        let before = profile
        let selected = try review.selectingOriginalGroups([[3, 0]])
        XCTAssertThrowsError(try selected.teach(labels: ["D"], profile: &profile))
        XCTAssertEqual(profile, before)
    }

    func testConflictingLabelsForNormalizedIdenticalSelectionsFailAtomically() throws {
        var profile = PersonalInkProfile()
        profile.isEnabled = true
        let strokes = [0.0, 50.0].map { x in
            InkStroke(points: [.init(x: x, y: 0), .init(x: x + 3, y: 12), .init(x: x + 8, y: 20)])
        }
        let parent = PersonalInkExample(kind: .chord, label: "D7", strokes: strokes, source: .explicitCorrection)
        profile.examples = [parent]
        let review = try PersonalInkSymbolTeachingReview(exampleID: parent.id, profile: profile)
            .selectingOriginalGroups([[0], [1]])
        let before = profile
        XCTAssertThrowsError(try review.teach(labels: ["D", "7"], profile: &profile)) { error in
            guard let failure = error as? PersonalInkSymbolTeachingReview.Failure,
                  case .conflictingSelections = failure else {
                return XCTFail("Conflicting explicit labels must report conflictingSelections, got \(error)")
            }
        }
        XCTAssertEqual(profile, before)
    }

    func testIdenticalSelectionsWithSameLabelMayDeduplicateWithoutLosingLesson() throws {
        var profile = PersonalInkProfile()
        profile.isEnabled = true
        let strokes = [0.0, 50.0].map { x in
            InkStroke(points: [.init(x: x, y: 0), .init(x: x + 3, y: 12), .init(x: x + 8, y: 20)])
        }
        let parent = PersonalInkExample(kind: .chord, label: "D7", strokes: strokes, source: .explicitCorrection)
        profile.examples = [parent]
        let review = try PersonalInkSymbolTeachingReview(exampleID: parent.id, profile: profile)
            .selectingOriginalGroups([[0], [1]])
        let receipt = try review.teach(labels: ["D", "D"], profile: &profile)
        XCTAssertEqual(receipt.selectedSymbolCount, 2)
        XCTAssertEqual(receipt.changedSymbolCount, 1)
        XCTAssertEqual(profile.examples.first, parent)
        XCTAssertEqual(profile.examples.filter { $0.kind == .glyph }.map(\.label), ["D"])
    }

    func testPerLabelBatchCapCannotSilentlyEvictAnEarlierSelectedLesson() throws {
        var (profile, review) = try prepared(count: PersonalInkProfile.maximumExamplesPerLabel + 1)
        // The source is not the oldest example; rejecting this batch must be
        // driven by a missing selected glyph, not only source-preservation.
        profile.examples.insert(PersonalInkExample(kind: .chord, label: "C", strokes: ink(), source: .setup), at: 0)
        let before = profile
        let groups = review.source.strokes.indices.map { [$0] }
        let selected = try review.selectingOriginalGroups(groups)
        XCTAssertThrowsError(try selected.teach(labels: Array(repeating: "7", count: groups.count), profile: &profile)) { error in
            guard let failure = error as? PersonalInkSymbolTeachingReview.Failure,
                  case .capacity = failure else {
                return XCTFail("A batch that loses a selected lesson must report capacity, got \(error)")
            }
        }
        XCTAssertEqual(profile, before)
    }

    private struct Encoder: PersonalInkVisualEncoding {
        let identity = "controlled-explicit-selection-fixture"
        let vocabulary = ["D", "7", "T"]
        func encode(_ strokes: [InkStroke]) throws -> PersonalInkVisualFeatures {
            let features = strokes.count == 2 ? [1.0, 0.0] : [0.0, 1.0]
            return .init(embedding: features + Array(repeating: 0, count: 126),
                         genericLogits: [0, 1, 1.1])
        }
    }

    func testRepairedMultiStrokeGlyphReachesLearnedComparatorWhileGenericRanksStayFixed() throws {
        var (profile, review) = try prepared()
        let frozen = profile
        var draft = PersonalInkSymbolSelectionDraft(review: try review.selectingOriginalGroups([[3, 0]]))
        try draft.setLabel("7", forPiece: 0)
        let selected = try draft.makeReview()
        let query = selected.pieces[0].strokes
        let beforeFit = try PersonalInkLearnedComparison(profile: profile, encoder: Encoder())
        let before = try beforeFit.readSuppliedOriginalGroups(query, originalIndexGroups: [[1, 0]], currentProfile: profile)
        XCTAssertEqual(beforeFit.glyphLessonCount, 0)
        XCTAssertEqual(before.glyphs[0].generic.first?.label, "T")
        _ = try selected.teach(labels: draft.labels, profile: &profile)
        let afterFit = try PersonalInkLearnedComparison(profile: profile, encoder: Encoder())
        let after = try afterFit.readSuppliedOriginalGroups(query, originalIndexGroups: [[1, 0]], currentProfile: profile)
        XCTAssertEqual(afterFit.glyphLessonCount, 1)
        XCTAssertEqual(after.glyphs[0].personal.first?.label, "7")
        XCTAssertEqual(after.glyphs.map(\.generic), before.glyphs.map(\.generic))
        XCTAssertEqual(after.glyphs[0].originalStrokeIndexes, [0, 1])
        XCTAssertEqual(frozen.examples, [review.source])
        // Controlled features prove that selected ink becomes a lesson; they do not prove transfer accuracy.
    }
}
