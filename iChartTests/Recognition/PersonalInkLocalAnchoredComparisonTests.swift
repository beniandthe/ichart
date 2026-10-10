import Foundation
import XCTest
@testable import iChart

/// Synthetic comparison-path contracts only. These tests do not measure
/// handwriting accuracy, ownership, confidence, or production eligibility.
final class PersonalInkLocalAnchoredComparisonTests: XCTestCase {
    private final class Encoder: PersonalInkVisualEncoding {
        var identity = "synthetic-local-comparison-encoder"
        var vocabulary = ["A", "B"]
        var anchorBank: PersonalInkAnchorBank?
        var inputs: [[InkStroke]] = []
        var onEncode: ((Encoder) -> Void)?
        var suppliedLogits: [Double]?

        init(anchorBank: PersonalInkAnchorBank? = nil) {
            self.anchorBank = anchorBank ?? .init(
                vocabulary: vocabulary,
                features: [Self.unit(0), Self.unit(1)]
            )
        }

        func encode(_ strokes: [InkStroke]) throws -> PersonalInkVisualFeatures {
            inputs.append(strokes)
            let signature = strokes.flatMap(\.points).reduce(0.0) { $0 + $1.x * 3 + $1.y * 5 }
            let featureIndex = Int(abs(signature.rounded())) % 4
            let offset = Double(Int(abs(signature.rounded())) % 5) * 0.1
            onEncode?(self)
            return .init(
                embedding: Self.unit(featureIndex),
                genericLogits: suppliedLogits ?? [2 - offset, -1 + offset]
            )
        }

        static func unit(_ index: Int) -> [Double] {
            (0..<128).map { $0 == index ? 1 : 0 }
        }
    }

    private enum ExpectedFailure { case disabled, staleProfile, invalidProfile, invalidEncoder, invalidInk }

    private var enabled: PersonalInkProfile {
        var profile = PersonalInkProfile()
        profile.isEnabled = true
        return profile
    }

    private func ink(_ x: Double) -> [InkStroke] {
        [.init(points: [.init(x: x, y: 2), .init(x: x + 7, y: 23)])]
    }

    private func source(_ count: Int) -> [InkStroke] {
        (0..<count).map { index in
            let x = Double(index * 40)
            return .init(
                points: [.init(x: x, y: 1, timeOffset: 0.1), .init(x: x + 8, y: 25, timeOffset: 0.2)],
                bounds: .init(minX: x - 0.25, minY: 0.75, maxX: x + 8.25, maxY: 25.25),
                creationTimeOffset: Double(index) + 0.5
            )
        }
    }

    private func example(_ id: String, kind: PersonalInkExampleKind, label: String,
                         strokes: [InkStroke], source: PersonalInkExampleSource = .setup) -> PersonalInkExample {
        PersonalInkExample(id: UUID(uuidString: id)!, kind: kind, label: label,
                           strokes: strokes, source: source)
    }

    func testGlyphOnlySortedSupportAndFullRanksMatchBothHeadsExactly() throws {
        var profile = enabled
        let firstID = "00000000-0000-0000-0000-000000000001"
        let secondID = "00000000-0000-0000-0000-000000000002"
        let thirdID = "00000000-0000-0000-0000-000000000003"
        profile.examples = (0..<18).map { index in
            PersonalInkExample(kind: .chord, label: "C", strokes: ink(Double(1_000 + index * 20)), source: .setup)
        } + [
            example(thirdID, kind: .glyph, label: "A", strokes: ink(31)),
            example(firstID, kind: .glyph, label: "△", strokes: ink(11)),
            example(secondID, kind: .glyph, label: "A", strokes: ink(21))
        ]
        let frozenProfile = profile
        let encoder = Encoder()
        let model = try PersonalInkLocalAnchoredComparison(profile: profile, encoder: encoder)

        XCTAssertEqual(model.support.lessons.map(\.exampleID.uuidString), [firstID, secondID, thirdID])
        XCTAssertEqual(model.support.lessons.map(\.label), ["△", "A", "A"])
        XCTAssertEqual(model.support.supportExampleCount, 3)
        XCTAssertEqual(model.support.distinctLabelCount, 2)
        XCTAssertEqual(model.support.labelCounts, ["A": 2, "△": 1])
        XCTAssertEqual(model.support.ignoredWholeChordCount, 18)
        XCTAssertEqual(encoder.inputs.count, 3)
        XCTAssertFalse(encoder.inputs.contains { input in
            input.flatMap(\.points).contains { $0.x >= 1_000 }
        }, "Whole-chord examples must never reach the encoder")
        XCTAssertEqual(try model.support.recomputedSHA256(), model.support.sha256)
        XCTAssertEqual(model.modelIdentity.runtimeKind, PersonalInkLocalAnchoredComparison.protocolRuntimeKind)
        XCTAssertNil(model.modelIdentity.pinnedAnchorArtifactSHA256)
        XCTAssertNil(model.modelIdentity.pinnedManifestArtifactSHA256)
        XCTAssertEqual(profile, frozenProfile)

        encoder.inputs.removeAll()
        let query = ink(71)
        let reading = try model.readSuppliedOriginalGroups(query, originalIndexGroups: [[0]],
                                                           currentProfile: { profile })
        let glyph = try XCTUnwrap(reading.glyphs.first)
        XCTAssertEqual(reading.support, model.support)
        XCTAssertEqual(reading.modelIdentity, model.modelIdentity)
        XCTAssertEqual(model.vocabulary, ["A", "B", "△"])
        for ranks in [glyph.sharedRanks, glyph.controlRanks, glyph.localRanks] {
            XCTAssertEqual(ranks.count, model.vocabulary.count)
            XCTAssertEqual(Set(ranks.map(\.label)), Set(model.vocabulary))
        }
        XCTAssertEqual(glyph.baseScores.count, model.vocabulary.count)
        XCTAssertEqual(glyph.baseScores.last, 0)

        let context = PersonalInkResidualHead.Context(
            isEnabled: true,
            profileRevision: profile.revision,
            encoderIdentity: encoder.identity
        )
        let lessons = model.support.lessons.map {
            PersonalInkResidualHead.Lesson(label: $0.label, features: $0.embedding,
                                           baseScores: $0.baseScores)
        }
        let bank = try XCTUnwrap(encoder.anchorBank)
        let directControl = try PersonalInkAnchoredResidualHead(
            context: context, vocabulary: model.vocabulary, featureCount: 128,
            lessons: lessons, bank: bank
        ).rankedCandidates(features: glyph.embedding, baseScores: glyph.baseScores,
                           currentContext: context).map {
            PersonalInkLocalAnchoredComparison.Rank(label: $0.label, score: $0.score)
        }
        let directLocal = try PersonalInkLocalAnchoredResidualHead(
            context: context, vocabulary: model.vocabulary, featureCount: 128,
            lessons: lessons, bank: bank
        ).rankedCandidates(features: glyph.embedding, baseScores: glyph.baseScores,
                           currentContext: context).map {
            PersonalInkLocalAnchoredComparison.Rank(label: $0.label, score: $0.score)
        }
        XCTAssertEqual(glyph.controlRanks, directControl)
        XCTAssertEqual(glyph.localRanks, directLocal)
        XCTAssertEqual(profile, frozenProfile)
        XCTAssertEqual(query, ink(71))
    }

    func testAllReaderArmsBlockIllegalWinnerWithoutChangingForensicRanks() throws {
        let profile = enabled
        let encoder = Encoder()
        encoder.vocabulary = ["ñ", "C", "J"]
        encoder.anchorBank = .init(
            vocabulary: encoder.vocabulary,
            features: [Encoder.unit(0), Encoder.unit(1), Encoder.unit(2)]
        )
        encoder.suppliedLogits = [4, 3, 2]
        let model = try PersonalInkLocalAnchoredComparison(profile: profile, encoder: encoder)
        let reading = try model.readSuppliedOriginalGroups(
            source(1), originalIndexGroups: [[0]], currentProfile: { profile }
        )
        let glyph = try XCTUnwrap(reading.glyphs.first)
        for raw in [glyph.sharedRanks, glyph.controlRanks, glyph.localRanks] {
            XCTAssertEqual(raw.map(\.label), ["ñ", "C", "J"])
            XCTAssertEqual(raw.count, model.vocabulary.count)
        }
        XCTAssertTrue(glyph.sharedChordDomainRanks.isEmpty)
        XCTAssertTrue(glyph.controlChordDomainRanks.isEmpty)
        XCTAssertTrue(glyph.localChordDomainRanks.isEmpty)
        XCTAssertNil(reading.sharedChord)
        XCTAssertNil(reading.controlChord)
        XCTAssertNil(reading.localChord)
        XCTAssertEqual(glyph.baseScores.count, model.vocabulary.count)
        XCTAssertEqual(glyph.embedding.count, 128)
    }

    func testEveryMalformedPartitionFailsBeforeQueryEncoding() throws {
        let profile = enabled
        let encoder = Encoder()
        let model = try PersonalInkLocalAnchoredComparison(profile: profile, encoder: encoder)
        let three = source(3)
        let seventeen = source(17)
        var invalidBounds = three
        invalidBounds[1].bounds.minX = invalidBounds[1].bounds.maxX + 1
        let cases: [(String, [InkStroke], [[Int]])] = [
            ("empty", [], []),
            ("no groups", three, []),
            ("empty group", three, [[0], [], [1, 2]]),
            ("incomplete", three, [[0, 1]]),
            ("duplicate", three, [[0, 0], [1]]),
            ("negative", three, [[0, 1, -1]]),
            ("out of range", three, [[0, 1, 3]]),
            ("too many groups", seventeen, seventeen.indices.map { [$0] }),
            ("invalid bounds", invalidBounds, [[0, 1, 2]])
        ]
        for item in cases {
            assertFailure(.invalidInk, item.0) {
                try model.readSuppliedOriginalGroups(item.1, originalIndexGroups: item.2,
                                                     currentProfile: { profile })
            }
            XCTAssertTrue(encoder.inputs.isEmpty, "\(item.0) encoded a query")
        }
    }

    func testDisabledStaleAndMidEncodeProfileChangesFailClosed() throws {
        let frozen = enabled
        let source = ink(80)
        do {
            let encoder = Encoder()
            let model = try PersonalInkLocalAnchoredComparison(profile: frozen, encoder: encoder)
            var stale = frozen
            stale.learnsFromReviews.toggle()
            XCTAssertEqual(stale.revision, frozen.revision)
            assertFailure(.staleProfile) {
                try model.readSuppliedOriginalGroups(source, originalIndexGroups: [[0]],
                                                     currentProfile: { stale })
            }
            var disabled = frozen
            disabled.isEnabled = false
            assertFailure(.disabled) {
                try model.readSuppliedOriginalGroups(source, originalIndexGroups: [[0]],
                                                     currentProfile: { disabled })
            }
            XCTAssertTrue(encoder.inputs.isEmpty)
        }
        for disables in [false, true] {
            var current = frozen
            let encoder = Encoder()
            let model = try PersonalInkLocalAnchoredComparison(profile: current, encoder: encoder)
            encoder.onEncode = { _ in
                if disables { current.isEnabled = false }
                else { current.learnsFromReviews.toggle() }
            }
            assertFailure(disables ? .disabled : .staleProfile) {
                try model.readSuppliedOriginalGroups(source, originalIndexGroups: [[0]],
                                                     currentProfile: { current })
            }
            XCTAssertEqual(encoder.inputs.count, 1)
        }
    }

    func testMissingMisorderedAndMalformedAnchorsFailBeforeSupportEncoding() throws {
        var profile = enabled
        profile.examples = [example("00000000-0000-0000-0000-000000000010",
                                    kind: .glyph, label: "A", strokes: ink(10))]
        let valid = [Encoder.unit(0), Encoder.unit(1)]
        let malformed: [PersonalInkAnchorBank?] = [
            nil,
            .init(vocabulary: ["B", "A"], features: Array(valid.reversed())),
            .init(vocabulary: ["A", "B"], features: [Encoder.unit(0)]),
            .init(vocabulary: ["A", "B"], features: [[1] + Array(repeating: 0, count: 126), Encoder.unit(1)]),
            .init(vocabulary: ["A", "B"], features: [Array(repeating: 0, count: 128), Encoder.unit(1)])
        ]
        for bank in malformed {
            let encoder = Encoder(anchorBank: bank)
            encoder.anchorBank = bank
            assertFailure(.invalidEncoder) {
                try PersonalInkLocalAnchoredComparison(profile: profile, encoder: encoder)
            }
            XCTAssertTrue(encoder.inputs.isEmpty)
        }
    }

    func testChangedEncoderIdentityAndBankFailImmediatelyAfterQueryEncode() throws {
        let profile = enabled
        for mutation in 0..<2 {
            let encoder = Encoder()
            let model = try PersonalInkLocalAnchoredComparison(profile: profile, encoder: encoder)
            encoder.onEncode = { value in
                if mutation == 0 { value.identity += "/changed" }
                else { value.anchorBank = .init(vocabulary: ["B", "A"],
                                                features: [Encoder.unit(1), Encoder.unit(0)]) }
            }
            assertFailure(.invalidEncoder) {
                try model.readSuppliedOriginalGroups(self.ink(90), originalIndexGroups: [[0]],
                                                     currentProfile: { profile })
            }
            XCTAssertEqual(encoder.inputs.count, 1)
        }
    }

    func testValidatedProvenanceIsRetainedAndMalformedProvenanceIsRejectedBeforeEncoding() throws {
        var profile = enabled
        let context = PersonalInkCaptureContext(
            sessionID: UUID(uuidString: "00000000-0000-0000-0000-000000000091")!,
            captureID: UUID(uuidString: "00000000-0000-0000-0000-000000000092")!,
            capturedAt: Date(timeIntervalSinceReferenceDate: 123),
            origin: .practice,
            chartStyle: "simple-chord-sheet"
        )
        try profile.learn(strokes: ink(12), label: "A", kind: .glyph,
                          source: .practice, captureContext: context)
        let encoder = Encoder()
        let model = try PersonalInkLocalAnchoredComparison(profile: profile, encoder: encoder)
        let lesson = try XCTUnwrap(model.support.lessons.first)
        let provenance = try XCTUnwrap(profile.examples.first?.learningProvenance)
        XCTAssertEqual(encoder.inputs, [profile.examples[0].recognitionInput])
        XCTAssertNotEqual(encoder.inputs, [profile.examples[0].strokes])
        XCTAssertEqual(lesson.storedInkSHA256, provenance.storedInputSHA256)
        XCTAssertEqual(lesson.originalInputSHA256, provenance.originalInputSHA256)
        XCTAssertEqual(lesson.intakeSessionID, context.sessionID)
        XCTAssertTrue(lesson.hasLearningProvenance)

        var malformed = profile
        var broken = try XCTUnwrap(malformed.examples[0].learningProvenance)
        broken.storedInputSHA256 = String(repeating: "0", count: 64)
        malformed.examples[0].learningProvenance = broken
        let rejectingEncoder = Encoder()
        assertFailure(.invalidProfile) {
            try PersonalInkLocalAnchoredComparison(profile: malformed, encoder: rejectingEncoder)
        }
        XCTAssertTrue(rejectingEncoder.inputs.isEmpty)
    }

    func testVerifiedSymbolOriginMustResolveToExactParentPiece() throws {
        let chordInk = [
            InkStroke(points: [.init(x: 0, y: 0), .init(x: 0, y: 20), .init(x: 10, y: 20),
                               .init(x: 12, y: 10), .init(x: 10, y: 0), .init(x: 0, y: 0)]),
            InkStroke(points: [.init(x: 40, y: 0), .init(x: 52, y: 0), .init(x: 42, y: 20)])
        ]
        var profile = enabled
        try profile.learn(strokes: chordInk, label: "D7", kind: .chord, source: .explicitCorrection)
        let review = try PersonalInkSymbolTeachingReview(
            exampleID: try XCTUnwrap(profile.examples.first?.id), profile: profile
        )
        XCTAssertEqual(review.pieces.count, 2)
        _ = try review.teach(labels: [nil, "7"], profile: &profile)
        let encoder = Encoder()
        let model = try PersonalInkLocalAnchoredComparison(profile: profile, encoder: encoder)
        XCTAssertEqual(model.support.supportExampleCount, 1)
        XCTAssertEqual(model.support.ignoredWholeChordCount, 1)
        XCTAssertTrue(model.support.lessons[0].hasVerifiedSymbolOrigin)
        XCTAssertEqual(encoder.inputs.count, 1)

        let symbolIndex = try XCTUnwrap(profile.examples.firstIndex { $0.kind == .glyph })
        let origin = try XCTUnwrap(profile.examples[symbolIndex].verifiedSymbolOrigin)
        var wrongLink = profile
        wrongLink.examples[symbolIndex].verifiedSymbolOrigin = .init(
            chordExampleID: origin.chordExampleID,
            chordLabel: "C7",
            originalStrokeIndexes: origin.originalStrokeIndexes
        )
        let wrongLinkEncoder = Encoder()
        assertFailure(.invalidProfile) {
            try PersonalInkLocalAnchoredComparison(profile: wrongLink, encoder: wrongLinkEncoder)
        }
        XCTAssertTrue(wrongLinkEncoder.inputs.isEmpty)

        var missingParent = profile
        missingParent.examples.removeAll { $0.kind == .chord }
        let missingParentEncoder = Encoder()
        assertFailure(.invalidProfile) {
            try PersonalInkLocalAnchoredComparison(profile: missingParent, encoder: missingParentEncoder)
        }
        XCTAssertTrue(missingParentEncoder.inputs.isEmpty)
    }

    private func assertFailure<T>(_ expected: ExpectedFailure, _ note: String = "",
                                  _ operation: () throws -> T) {
        XCTAssertThrowsError(try operation(), note) { error in
            guard let failure = error as? PersonalInkLocalAnchoredComparison.Failure else {
                return XCTFail("Unexpected error \(error)", file: #filePath, line: #line)
            }
            switch (expected, failure) {
            case (.disabled, .disabled), (.staleProfile, .staleProfile),
                 (.invalidProfile, .invalidProfile), (.invalidEncoder, .invalidEncoder),
                 (.invalidInk, .invalidInk): break
            default: XCTFail("Expected \(expected), got \(failure)", file: #filePath, line: #line)
            }
        }
    }
}
