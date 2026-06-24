#if canImport(UIKit) && canImport(PencilKit)
import CoreGraphics
import PencilKit
import UIKit
import XCTest
@testable import iChart

final class RhythmicNotationQuantizerTests: XCTestCase {
    private static let capturedHandwrittenHalfNotesInkBase64 = """
    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
    """

    private static let capturedDenseEighthRunWithRestInkBase64 = """
    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
    """

    private static let capturedEighthRestMisrenderedAsEighthInkBase64 = """
    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
    """

    func testQuantizerExpandsConnectedBeamedEighthPairs() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 280, height: 88)
        let drawing = PKDrawing(strokes: [
            beamedEighthPair(startX: 22),
            beamedEighthPair(startX: 92),
            dottedQuarter(x: 164),
            singleEighth(x: 220)
        ].flatMap { $0 })

        let values = try RhythmicNotationQuantizer.quantize(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        XCTAssertEqual(values, [.eighth, .eighth, .eighth, .eighth, .dottedQuarter, .eighth])
    }

    func testQuantizerReadsDirectBeamStrokeAcrossSeparateEighthStems() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 260, height: 88)
        let drawing = PKDrawing(strokes: [
            directBeamedEighthPair(startX: 22),
            directBeamedEighthPair(startX: 92),
            halfNote(x: 172)
        ].flatMap { $0 })

        let values = try RhythmicNotationQuantizer.quantize(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        XCTAssertEqual(values, [.eighth, .eighth, .eighth, .eighth, .half])
    }

    func testQuantizerReadsLooseFloatingBeamAcrossSeparateEighthStems() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 260, height: 88)
        let drawing = PKDrawing(strokes: [
            looselyBeamedEighthPair(startX: 22),
            looselyBeamedEighthPair(startX: 92),
            halfNote(x: 172)
        ].flatMap { $0 })

        let values = try RhythmicNotationQuantizer.quantize(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        XCTAssertEqual(values, [.eighth, .eighth, .eighth, .eighth, .half])
    }

    func testQuantizerReadsSlopedLooseBeamAcrossSeparateEighthStems() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 260, height: 88)
        let drawing = PKDrawing(strokes: [
            slopedLooseBeamedEighthPair(startX: 22, direction: .downward),
            slopedLooseBeamedEighthPair(startX: 92, direction: .upward),
            halfNote(x: 172)
        ].flatMap { $0 })

        let values = try RhythmicNotationQuantizer.quantize(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        XCTAssertEqual(values, [.eighth, .eighth, .eighth, .eighth, .half])
    }

    func testQuantizerDoesNotStretchFoldedBeamedPairIntoDottedHalfForExactFit() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 260, height: 88)
        let drawing = PKDrawing(strokes: [
            foldedRightStemBeamedEighthPair(startX: 22),
            quarterNote(x: 92)
        ].flatMap { $0 })

        do {
            _ = try RhythmicNotationQuantizer.quantize(
                drawing: drawing,
                meter: Meter(numerator: 4, denominator: 4),
                drawingFrame: drawingFrame
            )
            XCTFail("Expected folded beamed eighth pair plus quarter to remain underfilled")
        } catch let error as RhythmicNotationQuantizationError {
            XCTAssertEqual(error, .underfilled(expectedBeats: 4, actualBeats: 2))
        }
    }

    func testQuantizerReadsFoldedRightStemBeamedEighthPairs() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 260, height: 88)
        let drawing = PKDrawing(strokes: [
            foldedRightStemBeamedEighthPair(startX: 22),
            foldedRightStemBeamedEighthPair(startX: 92),
            halfNote(x: 172)
        ].flatMap { $0 })

        let values = try RhythmicNotationQuantizer.quantize(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        XCTAssertEqual(values, [.eighth, .eighth, .eighth, .eighth, .half])
    }

    func testQuantizerReadsDottedHalfWithTouchedUpTrailingBeamedEighths() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 260, height: 88)
        let drawing = PKDrawing(strokes: [
            dottedHalfNote(x: 18),
            touchedUpBeamedEighthPair(startX: 100)
        ].flatMap { $0 })

        let proposal = try RhythmicNotationQuantizer.autoApplyProposal(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        XCTAssertEqual(proposal.values, [.dottedHalf, .eighth, .eighth])
        XCTAssertEqual(proposal.safety, .autoApply)
        XCTAssertTrue(proposal.isNaturalExactFit)
    }

    func testV3DecisionCommitsNaturalVisualPhrase() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 260, height: 88)
        let drawing = PKDrawing(strokes: [
            dottedHalfNote(x: 18),
            touchedUpBeamedEighthPair(startX: 100)
        ].flatMap { $0 })

        let decision = RhythmicNotationQuantizer.recognitionDecision(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        guard case .commit(let proposal, let phrase) = decision else {
            XCTFail("Expected V3 to commit a natural visual phrase, got \(decision)")
            return
        }
        XCTAssertEqual(proposal.values, [.dottedHalf, .eighth, .eighth])
        XCTAssertTrue([RhythmPhraseSource.rasterTemplate, .visual].contains(phrase.source))
        XCTAssertEqual(phrase.naturalValues, [.dottedHalf, .eighth, .eighth])
        XCTAssertTrue(phrase.isNaturalExactFit)
        XCTAssertTrue(phrase.primitives.contains { $0.kind == .notehead })
        XCTAssertFalse(phrase.symbols.isEmpty)
    }

    func testV4DecisionCommitsNaturalSlashPhraseThroughRasterTemplateGate() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 280, height: 88)
        let drawing = PKDrawing(strokes: [
            rhythmSlash(x: 24),
            rhythmSlash(x: 84),
            rhythmSlash(x: 144),
            rhythmSlash(x: 204)
        ].flatMap { $0 })

        let decision = RhythmicNotationQuantizer.recognitionDecision(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        guard case .commit(let proposal, let phrase) = decision else {
            XCTFail("Expected V3 to commit a natural slash phrase, got \(decision)")
            return
        }
        XCTAssertEqual(proposal.values, [.slash, .slash, .slash, .slash])
        XCTAssertEqual(proposal.safety, .autoApply)
        XCTAssertEqual(phrase.source, .rasterTemplate)
        XCTAssertEqual(phrase.naturalValues, [.slash, .slash, .slash, .slash])
        XCTAssertTrue(phrase.isNaturalExactFit)
    }

    func testRecognitionDecisionCarriesMultipleReasoningPaths() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 280, height: 88)
        let drawing = PKDrawing(strokes: [
            rhythmSlash(x: 24),
            rhythmSlash(x: 84),
            rhythmSlash(x: 144),
            rhythmSlash(x: 204)
        ].flatMap { $0 })

        let decision = RhythmicNotationQuantizer.recognitionDecision(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        guard case .commit(_, let phrase) = decision else {
            XCTFail("Expected slash phrase to be a commit candidate, got \(decision)")
            return
        }

        let pathKinds = Set(phrase.reasoningPaths.map(\.kind))
        XCTAssertTrue(pathKinds.contains(.rasterTemplate))
        XCTAssertTrue(pathKinds.contains(.legacyFallback))
        XCTAssertTrue(pathKinds.contains(.contextRules))
        XCTAssertTrue(phrase.reasoningPaths.contains { path in
            path.kind == .contextRules && path.outcome == .commitCandidate
        })
    }

    func testV4DecisionCommitsSlashCountToMeterNumeratorInThreeEight() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 220, height: 88)
        let drawing = PKDrawing(strokes: [
            rhythmSlash(x: 24),
            rhythmSlash(x: 84),
            rhythmSlash(x: 144)
        ].flatMap { $0 })

        let decision = RhythmicNotationQuantizer.recognitionDecision(
            drawing: drawing,
            meter: Meter(numerator: 3, denominator: 8),
            drawingFrame: drawingFrame
        )

        guard case .commit(let proposal, let phrase) = decision else {
            XCTFail("Expected three slashes to commit in 3/8, got \(decision)")
            return
        }
        XCTAssertEqual(proposal.values, [.slash, .slash, .slash])
        XCTAssertEqual(proposal.safety, .autoApply)
        XCTAssertEqual(phrase.naturalValues, [.slash, .slash, .slash])
        XCTAssertTrue(phrase.isNaturalExactFit)
    }

    func testV4DecisionCommitsLooseAndShortSlashPhraseThroughRasterTemplateGate() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 280, height: 88)
        let drawing = PKDrawing(strokes: [
            looseRhythmSlash(x: 24, shape: .short),
            looseRhythmSlash(x: 84, shape: .shallow),
            looseRhythmSlash(x: 144, shape: .steep),
            looseRhythmSlash(x: 204, shape: .wobbly)
        ].flatMap { $0 })

        let decision = RhythmicNotationQuantizer.recognitionDecision(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        guard case .commit(let proposal, let phrase) = decision else {
            XCTFail("Expected V3 to commit loose/short slash ink, got \(decision)")
            return
        }
        XCTAssertEqual(proposal.values, [.slash, .slash, .slash, .slash])
        XCTAssertEqual(proposal.safety, .autoApply)
        XCTAssertEqual(phrase.source, .rasterTemplate)
        XCTAssertTrue(phrase.isNaturalExactFit)
    }

    func testV4DecisionKeepsExactSlashPhraseWithUnsupportedCropLocal() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 320, height: 88)
        let drawing = PKDrawing(strokes: [
            rhythmSlash(x: 24),
            rhythmSlash(x: 84),
            rhythmSlash(x: 144),
            rhythmSlash(x: 204),
            unrecognizedRhythmMark(x: 270)
        ].flatMap { $0 })

        let decision = RhythmicNotationQuantizer.recognitionDecision(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        guard case .keepWriting(let reason, let phrase?) = decision else {
            XCTFail("Expected V4 to keep unsupported ink local, got \(decision)")
            return
        }
        XCTAssertEqual(reason, .unsupported)
        XCTAssertEqual(phrase.source, .rasterTemplate)
        XCTAssertEqual(phrase.naturalValues, [.slash, .slash, .slash, .slash])
        XCTAssertTrue(phrase.isNaturalExactFit)
        XCTAssertEqual(phrase.uncoveredStrokeIndices.count, 1)
    }

    func testV3ReviewPolicyFlagsCloseCompetingExactPhrases() {
        let reason = RhythmicNotationQuantizer.exactFitReviewReasonForTesting(
            exactValues: [.half, .half],
            candidateScores: [
                [.half: 0.0, .quarter: 0.2],
                [.half: 0.0, .dottedHalf: 0.2]
            ],
            meter: Meter(numerator: 4, denominator: 4)
        )

        XCTAssertEqual(reason, .competingExactPhrases)
    }

    func testV4ExactFitRankingPrefersCleanMeterGroupingOverProtectedBeamBoundary() {
        let values = RhythmicNotationQuantizer.bestExactValuesForTesting(
            candidateScores: [
                [.dottedQuarter: 0.0],
                [.eighth: 0.0],
                [.eighth: 0.0, .quarter: 0.2],
                [.dottedQuarter: 0.0, .quarter: 0.2]
            ],
            meter: Meter(numerator: 4, denominator: 4)
        )

        XCTAssertEqual(values, [.dottedQuarter, .eighth, .quarter, .quarter])
    }

    func testV4CrossPathReviewFlagsExactRestNoteDisagreement() {
        let reason = RhythmicNotationQuantizer.crossPathReviewReasonForTesting(
            selectedValues: [.eighth, .eighth, .quarter, .half],
            alternateValues: [.eighthRest, .eighth, .quarter, .half],
            meter: Meter(numerator: 4, denominator: 4)
        )

        XCTAssertEqual(reason, .competingExactPhrases)
    }

    func testV4CrossPathReviewIgnoresDifferentDurationDisagreement() {
        let reason = RhythmicNotationQuantizer.crossPathReviewReasonForTesting(
            selectedValues: [.eighth, .eighth, .quarter, .half],
            alternateValues: [.quarterRest, .quarter, .half],
            meter: Meter(numerator: 4, denominator: 4)
        )

        XCTAssertNil(reason)
    }

    func testV3ReviewPolicyKeepsWholeMeasureMarksAsManualReview() {
        let reason = RhythmicNotationQuantizer.exactFitReviewReasonForTesting(
            exactValues: [.whole],
            candidateScores: [
                [.whole: 0.0, .half: 0.2]
            ],
            meter: Meter(numerator: 4, denominator: 4)
        )

        XCTAssertEqual(reason, .manualReview)
    }

    func testV4RasterNormalizationOrdersCropsByMeasurePositionIndependentOfStrokeOrder() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 280, height: 88)
        let drawing = PKDrawing(strokes: [
            Array(quarterNote(x: 144).reversed()),
            Array(quarterNote(x: 24).reversed()),
            Array(quarterNote(x: 204).reversed()),
            Array(quarterNote(x: 84).reversed())
        ].flatMap { $0 })

        let crops = RhythmicNotationQuantizer.v4SymbolCropsForTesting(
            drawing: drawing,
            drawingFrame: drawingFrame
        )

        XCTAssertEqual(crops.count, 4)
        XCTAssertEqual(crops.map(\.index), [0, 1, 2, 3])
        XCTAssertEqual(crops.map(\.normalizedBounds.minX), crops.map(\.normalizedBounds.minX).sorted())
        XCTAssertTrue(crops.allSatisfy { !$0.rasterCells.isEmpty })
    }

    func testV4RasterNormalizationRejectsTinyIsolatedNoiseWithoutBlockingCommit() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 300, height: 88)
        let drawing = PKDrawing(strokes: [
            quarterNote(x: 24),
            quarterNote(x: 84),
            quarterNote(x: 144),
            quarterNote(x: 204),
            tinyNoiseTap(x: 274, y: 8)
        ].flatMap { $0 })

        let crops = RhythmicNotationQuantizer.v4SymbolCropsForTesting(
            drawing: drawing,
            drawingFrame: drawingFrame
        )
        let decision = RhythmicNotationQuantizer.recognitionDecision(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        XCTAssertEqual(crops.count, 4)
        guard case .commit(let proposal, let phrase) = decision else {
            XCTFail("Expected V4 to ignore tiny isolated noise and commit clear quarters, got \(decision)")
            return
        }
        XCTAssertEqual(proposal.values, [.quarter, .quarter, .quarter, .quarter])
        XCTAssertEqual(phrase.source, .rasterTemplate)
    }

    func testV4VisualCompendiumCoversSupportedRhythmVocabulary() {
        XCTAssertEqual(
            RhythmicNotationQuantizer.v4SupportedTemplateValuesForTesting(),
            RhythmicNotationCompendium.supportedValues
        )
    }

    func testV4TemplateRejectsBackslashAsSlashPlaceholder() {
        let drawingFrame = CGRect(x: 0, y: 0, width: 280, height: 88)
        let drawing = PKDrawing(strokes: rhythmSlash(x: 24, direction: .backslash))

        let templateValues = RhythmicNotationQuantizer.v4TemplateValuesForTesting(
            drawing: drawing,
            drawingFrame: drawingFrame
        )

        XCTAssertFalse(templateValues.flatMap { $0 }.contains(.slash))
    }

    func testV4TemplateDoesNotClassifyStemmedNoteheadAsSlash() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 280, height: 88)
        let drawing = PKDrawing(strokes: quarterNote(x: 24))

        let templateValues = RhythmicNotationQuantizer.v4TemplateValuesForTesting(
            drawing: drawing,
            drawingFrame: drawingFrame
        )
        let templateMatches = RhythmicNotationQuantizer.v4TemplateMatchesForTesting(
            drawing: drawing,
            drawingFrame: drawingFrame
        )

        XCTAssertEqual(templateValues.count, 1)
        XCTAssertTrue(templateValues[0].contains(.quarter))
        XCTAssertFalse(templateValues[0].contains(.slash))
        XCTAssertFalse(templateValues[0].contains(.eighth))
        XCTAssertFalse(templateMatches[0].contains { $0.values == [.eighth] })
    }

    func testV4DecisionCommitsTightlySpacedSlashPhraseThroughRasterTemplateGate() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 150, height: 110)
        let drawing = PKDrawing(strokes: [
            compactRhythmSlash(x: 11, width: 21, height: 27),
            compactRhythmSlash(x: 36, width: 19, height: 26),
            compactRhythmSlash(x: 69, width: 19, height: 30),
            compactRhythmSlash(x: 102, width: 21, height: 35)
        ].flatMap { $0 })

        let decision = RhythmicNotationQuantizer.recognitionDecision(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        guard case .commit(let proposal, let phrase) = decision else {
            XCTFail("Expected V4 to own tightly spaced slash ink, got \(decision)")
            return
        }
        XCTAssertEqual(proposal.values, [.slash, .slash, .slash, .slash])
        XCTAssertEqual(phrase.source, .rasterTemplate)
        XCTAssertEqual(phrase.naturalValues, [.slash, .slash, .slash, .slash])
        XCTAssertTrue(phrase.isNaturalExactFit)
    }

    func testV4DecisionCommitsClearQuarterPhraseThroughRasterTemplateGate() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 320, height: 88)
        let drawing = PKDrawing(strokes: [
            quarterNote(x: 24),
            quarterNote(x: 84),
            quarterNote(x: 144),
            quarterNote(x: 204)
        ].flatMap { $0 })

        let decision = RhythmicNotationQuantizer.recognitionDecision(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        guard case .commit(let proposal, let phrase) = decision else {
            XCTFail("Expected V4 to commit a clear quarter phrase, got \(decision)")
            return
        }
        XCTAssertEqual(proposal.values, [.quarter, .quarter, .quarter, .quarter])
        XCTAssertEqual(phrase.source, .rasterTemplate)
        XCTAssertTrue(phrase.isNaturalExactFit)
    }

    func testV4DecisionPromotesAlignedAmbiguousHalfNotesBeforeReturningUnderfilled() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 320, height: 88)
        let meter = Meter(numerator: 4, denominator: 4)
        let expectedHalfNotePositions = RhythmicNotationQuantizer.v4RenderComparisonForTesting(
            values: [.half, .half],
            observedXPositions: [40, 200],
            meter: meter,
            drawingFrame: drawingFrame
        ).expectedXPositions

        let decision = RhythmicNotationQuantizer.v4UnderfilledExactFitPromotionDecisionForTesting(
            candidateScores: [
                [.quarter: 0.0, .half: 0.15],
                [.quarter: 0.0, .half: 0.15]
            ],
            observedXPositions: expectedHalfNotePositions,
            meter: meter,
            drawingFrame: drawingFrame
        )

        guard case .commit(let proposal, let phrase)? = decision else {
            XCTFail("Expected V4 to promote aligned ambiguous half notes to commit, got \(String(describing: decision))")
            return
        }
        XCTAssertEqual(proposal.values, [.half, .half])
        XCTAssertEqual(proposal.safety, .autoApply)
        XCTAssertEqual(phrase.source, .rasterTemplate)
        XCTAssertEqual(phrase.naturalValues, [.half, .half])
        XCTAssertEqual(phrase.symbols.map(\.selectedValue), [.half, .half])
    }

    func testV4DecisionDoesNotTreatWideQuarterStemAsEighthFlag() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 320, height: 88)
        let drawing = PKDrawing(strokes: [
            quarterNoteWithWideStem(x: 24),
            quarterNoteWithWideStem(x: 84),
            quarterNoteWithWideStem(x: 144),
            quarterNoteWithWideStem(x: 204)
        ].flatMap { $0 })

        let decision = RhythmicNotationQuantizer.recognitionDecision(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        guard case .commit(let proposal, let phrase) = decision else {
            XCTFail("Expected V4 to read wide-stem quarters as quarters, got \(decision)")
            return
        }
        XCTAssertEqual(proposal.values, [.quarter, .quarter, .quarter, .quarter])
        XCTAssertEqual(phrase.naturalValues, [.quarter, .quarter, .quarter, .quarter])
    }

    func testV4DecisionCommitsBeamedEighthsInFirstMiddleAndFinalBeatPositions() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 320, height: 88)
        let cases: [([PKStroke], [RhythmValue])] = [
            (
                [
                    foldedRightStemBeamedEighthPair(startX: 24),
                    quarterNote(x: 104),
                    quarterNote(x: 174),
                    quarterNote(x: 244)
                ].flatMap { $0 },
                [.eighth, .eighth, .quarter, .quarter, .quarter]
            ),
            (
                [
                    quarterNote(x: 24),
                    foldedRightStemBeamedEighthPair(startX: 104),
                    quarterNote(x: 174),
                    quarterNote(x: 244)
                ].flatMap { $0 },
                [.quarter, .eighth, .eighth, .quarter, .quarter]
            ),
            (
                [
                    quarterNote(x: 24),
                    quarterNote(x: 94),
                    quarterNote(x: 164),
                    foldedRightStemBeamedEighthPair(startX: 224)
                ].flatMap { $0 },
                [.quarter, .quarter, .quarter, .eighth, .eighth]
            )
        ]

        for (strokes, expectedValues) in cases {
            let decision = RhythmicNotationQuantizer.recognitionDecision(
                drawing: PKDrawing(strokes: strokes),
                meter: Meter(numerator: 4, denominator: 4),
                drawingFrame: drawingFrame
            )

            guard case .commit(let proposal, let phrase) = decision else {
                XCTFail("Expected V4 to commit beamed eighth case \(expectedValues), got \(decision)")
                continue
            }
            XCTAssertEqual(proposal.values, expectedValues)
            XCTAssertTrue(
                [RhythmPhraseSource.rasterTemplate, .visual].contains(phrase.source),
                "Expected V4 source for \(expectedValues)"
            )
            XCTAssertTrue(phrase.isNaturalExactFit)
        }
    }

    func testV4DecisionKeepsTightBeamedMiddlePhraseAsTwoEighthsThenQuarters() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 220, height: 88)
        let drawing = PKDrawing(strokes: [
            quarterNote(x: 10),
            foldedRightStemBeamedEighthPair(startX: 52),
            quarterNote(x: 118),
            quarterNote(x: 166)
        ].flatMap { $0 })

        let decision = RhythmicNotationQuantizer.recognitionDecision(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        guard case .commit(let proposal, let phrase) = decision else {
            XCTFail("Expected V4 to commit tight beamed middle phrase, got \(decision)")
            return
        }
        XCTAssertEqual(proposal.values, [.quarter, .eighth, .eighth, .quarter, .quarter])
        XCTAssertTrue([RhythmPhraseSource.rasterTemplate, .visual].contains(phrase.source))
        XCTAssertTrue(phrase.isNaturalExactFit)
    }

    func testV4DecisionCommitsDottedAndLongValuePhrasesThroughRasterTemplateGate() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 300, height: 88)
        let cases: [([PKStroke], [RhythmValue])] = [
            (
                [
                    dottedHalfNote(x: 24),
                    quarterNote(x: 190)
                ].flatMap { $0 },
                [.dottedHalf, .quarter]
            ),
            (
                [
                    halfNote(x: 24),
                    halfNote(x: 164)
                ].flatMap { $0 },
                [.half, .half]
            ),
            (
                [
                    dottedQuarter(x: 24),
                    singleEighth(x: 104),
                    halfNote(x: 190)
                ].flatMap { $0 },
                [.dottedQuarter, .eighth, .half]
            )
        ]

        for (strokes, expectedValues) in cases {
            let decision = RhythmicNotationQuantizer.recognitionDecision(
                drawing: PKDrawing(strokes: strokes),
                meter: Meter(numerator: 4, denominator: 4),
                drawingFrame: drawingFrame
            )

            guard case .commit(let proposal, let phrase) = decision else {
                XCTFail("Expected V4 to commit dotted/long phrase \(expectedValues), got \(decision)")
                continue
            }
            XCTAssertEqual(proposal.values, expectedValues)
            XCTAssertEqual(phrase.source, .rasterTemplate)
            XCTAssertTrue(phrase.isNaturalExactFit)
        }
    }

    func testV4DecisionCommitsCapturedHandwrittenHalfNotes() throws {
        var chart = Chart.blank(title: "Captured Half Notes", measureCount: 1, layoutStyle: .rhythmSectionSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        _ = chart.setMeasureManualLayoutWidth(339.5, for: measureID)
        let measure = try XCTUnwrap(chart.measure(id: measureID))
        let pageLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 1024, height: 1200)
        )
        let measureLayout = try XCTUnwrap(
            pageLayout.systems.flatMap(\.measures).first { $0.sourceMeasureID == measureID }
        )
        let drawingData = try XCTUnwrap(Data(base64Encoded: Self.capturedHandwrittenHalfNotesInkBase64))

        let decision = try LeadSheetRhythmicNotationFinalization.recognitionDecision(
            drawingData: drawingData,
            measure: measure,
            defaultMeter: chart.defaultMeter,
            measureLayout: measureLayout
        )

        guard case .commit(let proposal, let phrase) = decision else {
            XCTFail("Expected captured handwritten half notes to commit, got \(decision)")
            return
        }
        XCTAssertEqual(proposal.values, [.half, .half])
        XCTAssertEqual(phrase.source, .rasterTemplate)
        XCTAssertEqual(phrase.naturalValues, [.half, .half])

        let route = LeadSheetRhythmicNotationLiveDecisionPolicy.route(
            for: decision,
            requiresNaturalExactFitAfterErase: false
        )
        guard case .readyToRender(let values) = route else {
            XCTFail("Expected captured handwritten half notes to wait for tap-to-render, got \(route)")
            return
        }
        XCTAssertEqual(values, [.half, .half])
    }

    func testV4DecisionKeepsCapturedDenseEighthRunWithRestAcrossMeterBoundaryLocal() throws {
        var chart = Chart.blank(title: "Captured Dense Eighth Run", measureCount: 4, layoutStyle: .rhythmSectionSheet)
        let measureID = try XCTUnwrap(chart.measures.last?.id)
        _ = chart.setMeasureManualLayoutWidth(193.28571428571428, for: measureID)
        let measure = try XCTUnwrap(chart.measure(id: measureID))
        let pageLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 1024, height: 1200)
        )
        let measureLayout = try XCTUnwrap(
            pageLayout.systems.flatMap(\.measures).first { $0.sourceMeasureID == measureID }
        )
        let drawingData = try XCTUnwrap(Data(base64Encoded: Self.capturedDenseEighthRunWithRestInkBase64))

        let decision = try LeadSheetRhythmicNotationFinalization.recognitionDecision(
            drawingData: drawingData,
            measure: measure,
            defaultMeter: chart.defaultMeter,
            measureLayout: measureLayout
        )

        guard case .keepWriting(let reason, let phrase?) = decision else {
            XCTFail("Expected captured dense eighth/rest phrase to stay local, got \(decision)")
            return
        }
        let expectedValues: [RhythmValue] = [.quarter, .eighth, .eighth, .eighth, .eighth, .eighthRest]
        XCTAssertEqual(reason, .underfilled)
        XCTAssertEqual(phrase.source, .rasterTemplate)
        XCTAssertEqual(phrase.naturalValues, expectedValues)
        XCTAssertEqual(phrase.naturalUnits, 14)
        XCTAssertEqual(phrase.targetUnits, 16)
        XCTAssertTrue(phrase.primitives.contains { $0.kind == .restShape })

        let route = LeadSheetRhythmicNotationLiveDecisionPolicy.route(
            for: decision,
            requiresNaturalExactFitAfterErase: false
        )
        XCTAssertEqual(route, .preserveInk(showsUnreadFeedback: true))
    }

    func testV4DecisionKeepsCapturedEighthRestBeforeEighthNoteConflictLocal() throws {
        let chart = Chart.blank(title: "Captured Eighth Rest", measureCount: 8, layoutStyle: .rhythmSectionSheet)
        let measureID = try XCTUnwrap(chart.measures.dropFirst(2).first?.id)
        let measure = try XCTUnwrap(chart.measure(id: measureID))
        let pageLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 1024, height: 1200)
        )
        let measureLayout = try XCTUnwrap(
            pageLayout.systems.flatMap(\.measures).first { $0.sourceMeasureID == measureID }
        )
        let drawingData = try XCTUnwrap(Data(base64Encoded: Self.capturedEighthRestMisrenderedAsEighthInkBase64))

        let decision = try LeadSheetRhythmicNotationFinalization.recognitionDecision(
            drawingData: drawingData,
            measure: measure,
            defaultMeter: chart.defaultMeter,
            measureLayout: measureLayout
        )

        guard case .keepWriting(let reason, let phrase?) = decision else {
            XCTFail("Expected captured eighth-rest phrase to stay local, got \(decision)")
            return
        }
        XCTAssertEqual(reason, .overflow)
        XCTAssertEqual(phrase.source, .rasterTemplate)
        XCTAssertEqual(phrase.naturalValues, [.eighthRest, .dottedQuarter, .half, .quarter])
        XCTAssertEqual(phrase.naturalUnits, 20)
        XCTAssertEqual(phrase.targetUnits, 16)
        XCTAssertTrue(phrase.primitives.contains { $0.kind == .restShape })

        let route = LeadSheetRhythmicNotationLiveDecisionPolicy.route(
            for: decision,
            requiresNaturalExactFitAfterErase: false
        )
        XCTAssertEqual(route, .preserveInk(showsUnreadFeedback: true))
    }

    func testV4DecisionCommitsCapturedRestNoteExactAgreement() throws {
        let capturedCompetingRestNotePhraseInkBase64 = """
        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
        """
        let chart = Chart.blank(title: "Captured Rest/Note Conflict", measureCount: 8, layoutStyle: .rhythmSectionSheet)
        let measureID = try XCTUnwrap(chart.measures.dropFirst(2).first?.id)
        let measure = try XCTUnwrap(chart.measure(id: measureID))
        let pageLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 1024, height: 1200)
        )
        let measureLayout = try XCTUnwrap(
            pageLayout.systems.flatMap(\.measures).first { $0.sourceMeasureID == measureID }
        )
        let drawingData = try XCTUnwrap(Data(base64Encoded: capturedCompetingRestNotePhraseInkBase64))

        let decision = try LeadSheetRhythmicNotationFinalization.recognitionDecision(
            drawingData: drawingData,
            measure: measure,
            defaultMeter: chart.defaultMeter,
            measureLayout: measureLayout
        )

        guard case .commit(let proposal, let phrase) = decision else {
            XCTFail("Expected captured rest/note agreement to commit, got \(decision)")
            return
        }
        XCTAssertEqual(proposal.values, [.eighthRest, .eighth, .quarter, .half])
        XCTAssertEqual(proposal.safety, .autoApply)
        XCTAssertTrue(proposal.isNaturalExactFit)
        XCTAssertEqual(phrase.source, .rasterTemplate)
        XCTAssertTrue(
            phrase.reasoningPaths.contains { path in
                path.kind == .visualShape
                    && path.outcome == .commitCandidate
                    && path.values == [.eighthRest, .eighth, .quarter, .half]
            }
        )

        let route = LeadSheetRhythmicNotationLiveDecisionPolicy.route(
            for: decision,
            requiresNaturalExactFitAfterErase: false
        )
        XCTAssertEqual(route, .readyToRender(values: [.eighthRest, .eighth, .quarter, .half]))
    }

    func testV4DecisionCoversRestPhrasesThroughRasterTemplateGate() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 300, height: 88)
        let commitCases: [([PKStroke], [RhythmValue])] = [
            (
                [
                    singleStrokeQuarterRest(x: 24),
                    quarterNote(x: 92),
                    quarterNote(x: 154),
                    quarterNote(x: 216)
                ].flatMap { $0 },
                [.quarterRest, .quarter, .quarter, .quarter]
            ),
            (
                [
                    halfRest(x: 24),
                    quarterNote(x: 144),
                    quarterNote(x: 218)
                ].flatMap { $0 },
                [.halfRest, .quarter, .quarter]
            ),
            (
                [
                    eighthRest(x: 18),
                    eighthRest(x: 64),
                    quarterNote(x: 124),
                    quarterNote(x: 184),
                    quarterNote(x: 244)
                ].flatMap { $0 },
                [.eighthRest, .eighthRest, .quarter, .quarter, .quarter]
            )
        ]

        for (strokes, expectedValues) in commitCases {
            let decision = RhythmicNotationQuantizer.recognitionDecision(
                drawing: PKDrawing(strokes: strokes),
                meter: Meter(numerator: 4, denominator: 4),
                drawingFrame: drawingFrame
            )

            guard case .commit(let proposal, let phrase) = decision else {
                XCTFail("Expected V4 to commit rest phrase \(expectedValues), got \(decision)")
                continue
            }
            XCTAssertEqual(proposal.values, expectedValues)
            XCTAssertEqual(phrase.source, .rasterTemplate)
            XCTAssertTrue(phrase.isNaturalExactFit)
        }

        let wholeRestDecision = RhythmicNotationQuantizer.recognitionDecision(
            drawing: PKDrawing(strokes: wholeRest(x: 116)),
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )
        guard case .needsReview(let reason, let phrase?, let proposal?) = wholeRestDecision else {
            XCTFail("Expected V4 to require review for a whole-rest measure, got \(wholeRestDecision)")
            return
        }
        XCTAssertEqual(reason, .manualReview)
        XCTAssertEqual(proposal.values, [.wholeRest])
        XCTAssertEqual(phrase.source, .rasterTemplate)
        XCTAssertTrue(phrase.isNaturalExactFit)
    }

    func testV4DecisionRejectsUnflaggedEighthAlternativeFromRasterAuthority() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 280, height: 88)
        let drawing = PKDrawing(strokes: [
            halfNote(x: 18),
            dottedQuarter(x: 104),
            quarterNote(x: 196)
        ].flatMap { $0 })

        let decision = RhythmicNotationQuantizer.recognitionDecision(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        guard case .keepWriting(let reason, let phrase?) = decision else {
            XCTFail("Expected V4 to reject the unflagged eighth exact-fit alternative, got \(decision)")
            return
        }
        XCTAssertEqual(reason, .overflow)
        XCTAssertEqual(phrase.source, .rasterTemplate)
        XCTAssertEqual(phrase.naturalValues, [.half, .dottedQuarter, .quarter])
        XCTAssertFalse(phrase.symbols.flatMap(\.candidateValues).contains(.eighth))
        XCTAssertFalse(phrase.isNaturalExactFit)
    }

    func testV4DecisionKeepsUnderfilledTemplatePhraseLocalWithoutStretching() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 280, height: 88)
        let drawing = PKDrawing(strokes: [
            quarterNote(x: 24),
            quarterNote(x: 84),
            quarterNote(x: 144)
        ].flatMap { $0 })

        let decision = RhythmicNotationQuantizer.recognitionDecision(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        guard case .keepWriting(let reason, let phrase?) = decision else {
            XCTFail("Expected V4 to keep underfilled template ink local, got \(decision)")
            return
        }
        XCTAssertEqual(reason, .underfilled)
        XCTAssertEqual(phrase.source, .rasterTemplate)
        XCTAssertEqual(phrase.naturalValues, [.quarter, .quarter, .quarter])
        XCTAssertEqual(phrase.naturalUnits, 12)
        XCTAssertEqual(phrase.targetUnits, 16)
        XCTAssertFalse(phrase.isNaturalExactFit)
    }

    func testV4DecisionKeepsOverflowTemplatePhraseLocalWithoutExactRewrite() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 360, height: 88)
        let drawing = PKDrawing(strokes: [
            quarterNote(x: 24),
            quarterNote(x: 84),
            quarterNote(x: 144),
            quarterNote(x: 204),
            quarterNote(x: 264)
        ].flatMap { $0 })

        let decision = RhythmicNotationQuantizer.recognitionDecision(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        guard case .keepWriting(let reason, let phrase?) = decision else {
            XCTFail("Expected V4 to keep overflow template ink local, got \(decision)")
            return
        }
        XCTAssertEqual(reason, .overflow)
        XCTAssertEqual(phrase.source, .rasterTemplate)
        XCTAssertEqual(phrase.naturalValues, [.quarter, .quarter, .quarter, .quarter, .quarter])
        XCTAssertEqual(phrase.naturalUnits, 20)
        XCTAssertEqual(phrase.targetUnits, 16)
        XCTAssertFalse(phrase.isNaturalExactFit)
    }

    func testV4DecisionKeepsCompletedPhraseWithUnsupportedCropLocal() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 340, height: 88)
        let drawing = PKDrawing(strokes: [
            quarterNote(x: 24),
            quarterNote(x: 84),
            quarterNote(x: 144),
            quarterNote(x: 204),
            unrecognizedRhythmMark(x: 286)
        ].flatMap { $0 })

        let decision = RhythmicNotationQuantizer.recognitionDecision(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        guard case .keepWriting(let reason, let phrase?) = decision else {
            XCTFail("Expected V4 to keep unsupported crop local, got \(decision)")
            return
        }
        XCTAssertEqual(reason, .unsupported)
        XCTAssertEqual(phrase.source, .rasterTemplate)
        XCTAssertEqual(phrase.naturalValues, [.quarter, .quarter, .quarter, .quarter])
        XCTAssertTrue(phrase.isNaturalExactFit)
        XCTAssertEqual(phrase.uncoveredStrokeIndices.count, 1)
        XCTAssertTrue(phrase.symbols.contains { $0.selectedValue == nil && $0.candidateValues.isEmpty })
    }

    func testV4RenderComparisonRejectsExactValuesWithBadSpacing() {
        let comparison = RhythmicNotationQuantizer.v4RenderComparisonForTesting(
            values: [.quarter, .quarter, .quarter, .quarter],
            observedXPositions: [24, 34, 44, 54],
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: CGRect(x: 0, y: 0, width: 280, height: 88)
        )

        XCTAssertFalse(comparison.aligned)
    }

    func testV4RenderComparisonAcceptsAlignedExactValues() {
        let comparison = RhythmicNotationQuantizer.v4RenderComparisonForTesting(
            values: [.quarter, .quarter, .quarter, .quarter],
            observedXPositions: [35, 105, 175, 245],
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: CGRect(x: 0, y: 0, width: 280, height: 88)
        )

        XCTAssertTrue(comparison.aligned)
    }

    func testV4DecisionKeepsUnderfilledBeamedTemplatePhraseLocal() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 260, height: 88)
        let drawing = PKDrawing(strokes: [
            foldedRightStemBeamedEighthPair(startX: 22),
            quarterNote(x: 92)
        ].flatMap { $0 })

        let decision = RhythmicNotationQuantizer.recognitionDecision(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        guard case .keepWriting(let reason, let phrase?) = decision else {
            XCTFail("Expected V4 to keep underfilled template ink local, got \(decision)")
            return
        }
        XCTAssertEqual(reason, .underfilled)
        XCTAssertEqual(phrase.source, .rasterTemplate)
        XCTAssertEqual(phrase.naturalValues.prefix(2), [.eighth, .eighth])
        XCTAssertFalse(phrase.isNaturalExactFit)
    }

    func testV4DecisionCommitsQuarterRestPhraseBeforeVisualFallback() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 260, height: 88)
        let drawing = PKDrawing(strokes: [
            singleStrokeQuarterRest(x: 24),
            quarterNote(x: 86),
            quarterNote(x: 142),
            quarterNote(x: 198)
        ].flatMap { $0 })

        let decision = RhythmicNotationQuantizer.recognitionDecision(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        guard case .commit(let proposal, let phrase) = decision else {
            XCTFail("Expected V4 to commit a natural quarter-rest phrase, got \(decision)")
            return
        }
        XCTAssertEqual(proposal.values, [.quarterRest, .quarter, .quarter, .quarter])
        XCTAssertEqual(phrase.source, .rasterTemplate)
        XCTAssertEqual(phrase.naturalValues, [.quarterRest, .quarter, .quarter, .quarter])
        XCTAssertTrue(phrase.isNaturalExactFit)
        XCTAssertTrue(phrase.primitives.contains { $0.kind == .restShape })
    }

    func testV4DecisionCommitsHalfRestPhraseBeforeVisualFallback() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 260, height: 88)
        let drawing = PKDrawing(strokes: [
            halfRest(x: 24),
            quarterNote(x: 118),
            quarterNote(x: 178)
        ].flatMap { $0 })

        let decision = RhythmicNotationQuantizer.recognitionDecision(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        guard case .commit(let proposal, let phrase) = decision else {
            XCTFail("Expected V4 to commit a natural half-rest phrase, got \(decision)")
            return
        }
        XCTAssertEqual(proposal.values, [.halfRest, .quarter, .quarter])
        XCTAssertEqual(phrase.source, .rasterTemplate)
        XCTAssertEqual(phrase.naturalValues, [.halfRest, .quarter, .quarter])
        XCTAssertTrue(phrase.isNaturalExactFit)
    }

    func testV4DecisionRequiresReviewForWholeRestMeasure() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 220, height: 88)
        let drawing = PKDrawing(strokes: wholeRest(x: 72))

        let decision = RhythmicNotationQuantizer.recognitionDecision(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        guard case .needsReview(let reason, let phrase?, let proposal?) = decision else {
            XCTFail("Expected V4 to require review for a single whole-rest measure, got \(decision)")
            return
        }
        XCTAssertEqual(reason, .manualReview)
        XCTAssertEqual(proposal.values, [.wholeRest])
        XCTAssertEqual(proposal.safety, .manualReview)
        XCTAssertFalse(proposal.canAutoApply)
        XCTAssertEqual(phrase.source, .rasterTemplate)
        XCTAssertEqual(phrase.naturalValues, [.wholeRest])
        XCTAssertTrue(phrase.isNaturalExactFit)
    }

    func testV4DecisionCommitsClearMixedRestNoteCluster() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 260, height: 88)
        let drawing = PKDrawing(strokes: [
            oneTakeDotHookTailEighthRest(x: 18),
            singleEighth(x: 58),
            dottedHalfNote(x: 124)
        ].flatMap { $0 })

        let values = try RhythmicNotationQuantizer.quantize(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )
        let decision = RhythmicNotationQuantizer.recognitionDecision(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )
        let proposal = try RhythmicNotationQuantizer.autoApplyProposal(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        XCTAssertEqual(values, [.eighthRest, .eighth, .dottedHalf])
        guard case .commit(let decisionProposal, let phrase) = decision else {
            XCTFail("Expected V4 to commit a clear mixed rest/note cluster, got \(decision)")
            return
        }
        XCTAssertEqual(phrase.source, .rasterTemplate)
        XCTAssertEqual(phrase.naturalValues, [.eighthRest, .eighth, .dottedHalf])
        XCTAssertTrue(phrase.isNaturalExactFit)
        XCTAssertEqual(decisionProposal.values, [.eighthRest, .eighth, .dottedHalf])
        XCTAssertEqual(decisionProposal.safety, .autoApply)
        XCTAssertTrue(decisionProposal.canAutoApply)
        XCTAssertEqual(proposal.values, [.eighthRest, .eighth, .dottedHalf])
        XCTAssertTrue(proposal.canAutoApply)
    }

    func testV4DecisionKeepsUnderfilledRestNotePhraseReadable() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 260, height: 88)
        let drawing = PKDrawing(strokes: [
            sevenLikeEighthRest(x: 20),
            singleEighth(x: 64)
        ].flatMap { $0 })

        let decision = RhythmicNotationQuantizer.recognitionDecision(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        guard case .keepWriting(let reason, let phrase?) = decision else {
            XCTFail("Expected V4 to keep an underfilled rest/note phrase local, got \(decision)")
            return
        }
        XCTAssertEqual(reason, .underfilled)
        XCTAssertEqual(phrase.source, .rasterTemplate)
        XCTAssertEqual(phrase.naturalValues, [.eighthRest, .eighth])
        XCTAssertEqual(phrase.naturalUnits, 4)
        XCTAssertEqual(phrase.targetUnits, 16)
        XCTAssertFalse(phrase.isNaturalExactFit)
    }

    func testAutoApplyProposalCommitsCompletedQuarterPhraseWithoutFakeEighthGrace() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 320, height: 88)
        let drawing = PKDrawing(strokes: [
            quarterNote(x: 24),
            quarterNote(x: 84),
            quarterNote(x: 144),
            quarterNote(x: 204)
        ].flatMap { $0 })

        let proposal = try RhythmicNotationQuantizer.autoApplyProposal(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        XCTAssertEqual(proposal.values, [.quarter, .quarter, .quarter, .quarter])
        XCTAssertEqual(proposal.safety, .autoApply)
        XCTAssertTrue(proposal.canAutoApply)
        XCTAssertFalse(proposal.requiresExtendedStability)
    }

    func testAutoApplyProposalCommitsStrongRasterWholeNote() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 220, height: 88)
        let drawing = PKDrawing(strokes: wholeNote(x: 72))

        let values = try RhythmicNotationQuantizer.quantize(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )
        let proposal = try RhythmicNotationQuantizer.autoApplyProposal(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )
        let decision = RhythmicNotationQuantizer.recognitionDecision(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        XCTAssertEqual(values, [.whole])
        XCTAssertEqual(proposal.values, [.whole])
        XCTAssertEqual(proposal.safety, .autoApply)
        XCTAssertTrue(proposal.canAutoApply)
        guard case .commit(let committedProposal, let phrase) = decision else {
            XCTFail("Expected V4 to commit a clear whole note, got \(decision)")
            return
        }
        XCTAssertEqual(committedProposal.values, [.whole])
        XCTAssertEqual(phrase.source, .rasterTemplate)
        XCTAssertEqual(phrase.naturalValues, [.whole])
        XCTAssertTrue(phrase.isNaturalExactFit)
    }

    func testAutoApplyProposalCommitsCompactRasterWholeNote() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 220, height: 88)
        let drawing = PKDrawing(strokes: compactWholeNote(x: 72))

        let decision = RhythmicNotationQuantizer.recognitionDecision(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        guard case .commit(let proposal, let phrase) = decision else {
            XCTFail("Expected V4 to commit a compact whole-note oval, got \(decision)")
            return
        }
        XCTAssertEqual(proposal.values, [.whole])
        XCTAssertEqual(proposal.safety, .autoApply)
        XCTAssertEqual(phrase.source, .rasterTemplate)
        XCTAssertEqual(phrase.naturalValues, [.whole])
        XCTAssertTrue(phrase.isNaturalExactFit)
    }

    func testAutoApplyProposalCommitsLiteralClosedCircleAsWholeNote() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 220, height: 88)
        let drawing = PKDrawing(strokes: handDrawnCircleWholeNote(x: 72))

        let decision = RhythmicNotationQuantizer.recognitionDecision(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        guard case .commit(let proposal, let phrase) = decision else {
            XCTFail("Expected V4 to commit a literal closed circle as a whole note, got \(decision)")
            return
        }
        XCTAssertEqual(proposal.values, [.whole])
        XCTAssertEqual(proposal.safety, .autoApply)
        XCTAssertEqual(phrase.source, .rasterTemplate)
        XCTAssertEqual(phrase.naturalValues, [.whole])
        XCTAssertTrue(phrase.isNaturalExactFit)
    }

    func testAutoApplyProposalDoesNotAutoApplyTinyLowInformationWholeLikeMark() {
        let drawingFrame = CGRect(x: 0, y: 0, width: 220, height: 88)
        let drawing = PKDrawing(strokes: tinyWholeLikeMark(x: 72))

        do {
            let proposal = try RhythmicNotationQuantizer.autoApplyProposal(
                drawing: drawing,
                meter: Meter(numerator: 4, denominator: 4),
                drawingFrame: drawingFrame
            )

            XCTAssertFalse(proposal.canAutoApply)
        } catch {
            return
        }
    }

    func testAutoApplyProposalDoesNotExtendGraceForCompletedLastBeatBeam() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 340, height: 88)
        let drawing = PKDrawing(strokes: [
            quarterNote(x: 24),
            quarterNote(x: 84),
            quarterNote(x: 144),
            foldedRightStemBeamedEighthPair(startX: 204)
        ].flatMap { $0 })

        let proposal = try RhythmicNotationQuantizer.autoApplyProposal(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        XCTAssertEqual(proposal.values, [.quarter, .quarter, .quarter, .eighth, .eighth])
        XCTAssertEqual(proposal.safety, .autoApply)
        XCTAssertTrue(proposal.canAutoApply)
        XCTAssertFalse(proposal.requiresExtendedStability)
    }

    func testQuantizerKeepsAdjacentDirectBeamGroupsAsEighths() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 220, height: 88)
        let drawing = PKDrawing(strokes: [
            directBeamedEighthPair(startX: 22),
            directBeamedEighthPair(startX: 68),
            halfNote(x: 146)
        ].flatMap { $0 })

        let values = try RhythmicNotationQuantizer.quantize(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        XCTAssertEqual(values, [.eighth, .eighth, .eighth, .eighth, .half])
    }

    func testQuantizerKeepsAdjacentLooseFloatingBeamGroupsAsEighths() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 220, height: 88)
        let drawing = PKDrawing(strokes: [
            looselyBeamedEighthPair(startX: 22),
            looselyBeamedEighthPair(startX: 68),
            halfNote(x: 146)
        ].flatMap { $0 })

        let values = try RhythmicNotationQuantizer.quantize(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        XCTAssertEqual(values, [.eighth, .eighth, .eighth, .eighth, .half])
    }

    func testQuantizerReadsLooseBeamsRegardlessOfStrokeOrder() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 260, height: 88)
        let drawing = PKDrawing(strokes: [
            looselyBeamedEighthPairDrawnOutOfOrder(startX: 22),
            looselyBeamedEighthPairDrawnOutOfOrder(startX: 92),
            halfNote(x: 172)
        ].flatMap { $0 })

        let values = try RhythmicNotationQuantizer.quantize(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        XCTAssertEqual(values, [.eighth, .eighth, .eighth, .eighth, .half])
    }

    func testQuantizerKeepsAdjacentStemAndBeamShorthandGroupsAsEighths() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 220, height: 88)
        let drawing = PKDrawing(strokes: [
            stemAndBeamOnlyPair(startX: 22),
            stemAndBeamOnlyPair(startX: 68),
            halfNote(x: 146)
        ].flatMap { $0 })

        let values = try RhythmicNotationQuantizer.quantize(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        XCTAssertEqual(values, [.eighth, .eighth, .eighth, .eighth, .half])
    }

    func testQuantizerReadsStemAndBeamShorthandAsEighths() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 220, height: 88)
        let drawing = PKDrawing(strokes: [
            stemAndBeamOnlyPair(startX: 22),
            stemAndBeamOnlyPair(startX: 92),
            halfNote(x: 164)
        ].flatMap { $0 })

        let values = try RhythmicNotationQuantizer.quantize(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        XCTAssertEqual(values, [.eighth, .eighth, .eighth, .eighth, .half])
    }

    func testQuantizerReadsSimpleSlashesAsQuarterBeatPlaceholders() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 280, height: 88)
        let drawing = PKDrawing(strokes: [
            rhythmSlash(x: 24),
            rhythmSlash(x: 84),
            rhythmSlash(x: 144),
            rhythmSlash(x: 204)
        ].flatMap { $0 })

        let values = try RhythmicNotationQuantizer.quantize(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        XCTAssertEqual(values, [.slash, .slash, .slash, .slash])
    }

    func testQuantizerDoesNotTreatBackslashesAsSlashPlaceholders() {
        let drawingFrame = CGRect(x: 0, y: 0, width: 280, height: 88)
        let drawing = PKDrawing(strokes: [
            rhythmSlash(x: 24, direction: .backslash),
            rhythmSlash(x: 84, direction: .backslash),
            rhythmSlash(x: 144, direction: .backslash),
            rhythmSlash(x: 204, direction: .backslash)
        ].flatMap { $0 })

        do {
            let values = try RhythmicNotationQuantizer.quantize(
                drawing: drawing,
                meter: Meter(numerator: 4, denominator: 4),
                drawingFrame: drawingFrame
            )

            XCTAssertFalse(values.contains(.slash))
        } catch {
            return
        }
    }

    func testQuantizerReadsLooseForwardDiagonalSlashesAsPlaceholders() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 280, height: 88)
        let drawing = PKDrawing(strokes: [
            looseRhythmSlash(x: 24, shape: .shallow),
            looseRhythmSlash(x: 84, shape: .steep),
            looseRhythmSlash(x: 144, shape: .wobbly),
            looseRhythmSlash(x: 204, shape: .veryWobbly)
        ].flatMap { $0 })

        let values = try RhythmicNotationQuantizer.quantize(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        XCTAssertEqual(values, [.slash, .slash, .slash, .slash])
    }

    func testQuantizerReadsTightlySpacedForwardSlashesAsSeparatePlaceholders() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 180, height: 88)
        let drawing = PKDrawing(strokes: [
            rhythmSlash(x: 24),
            rhythmSlash(x: 50),
            rhythmSlash(x: 76),
            rhythmSlash(x: 102)
        ].flatMap { $0 })

        let values = try RhythmicNotationQuantizer.quantize(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        XCTAssertEqual(values, [.slash, .slash, .slash, .slash])
    }

    func testQuantizerMixesSlashesWithWrittenRhythms() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 280, height: 88)
        let drawing = PKDrawing(strokes: [
            rhythmSlash(x: 24),
            directBeamedEighthPair(startX: 88),
            halfNote(x: 202)
        ].flatMap { $0 })

        let values = try RhythmicNotationQuantizer.quantize(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        XCTAssertEqual(values, [.slash, .eighth, .eighth, .half])
    }

    func testQuantizerReadsSingleStrokeQuarterRest() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 260, height: 88)
        let drawing = PKDrawing(strokes: [
            singleStrokeQuarterRest(x: 24),
            quarterNote(x: 86),
            quarterNote(x: 142),
            quarterNote(x: 198)
        ].flatMap { $0 })

        let values = try RhythmicNotationQuantizer.quantize(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        XCTAssertEqual(values, [.quarterRest, .quarter, .quarter, .quarter])
    }

    func testQuantizerReadsLooseTwoStrokeQuarterRests() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 240, height: 88)
        let drawing = PKDrawing(strokes: [
            looseTwoStrokeQuarterRest(x: 24),
            looseTwoStrokeQuarterRest(x: 82),
            halfNote(x: 156)
        ].flatMap { $0 })

        let values = try RhythmicNotationQuantizer.quantize(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        XCTAssertEqual(values, [.quarterRest, .quarterRest, .half])
    }

    func testQuantizerKeepsEighthRestsDistinctFromQuarterRests() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 260, height: 88)
        let drawing = PKDrawing(strokes: [
            eighthRest(x: 24),
            eighthRest(x: 72),
            quarterNote(x: 126),
            quarterNote(x: 174),
            quarterNote(x: 222)
        ].flatMap { $0 })

        let values = try RhythmicNotationQuantizer.quantize(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        XCTAssertEqual(values, [.eighthRest, .eighthRest, .quarter, .quarter, .quarter])
    }

    func testQuantizerReadsDotTailEighthRestsWithWobblyTails() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 270, height: 88)
        let drawing = PKDrawing(strokes: [
            dotTailEighthRest(x: 24, tail: .vertical),
            dotTailEighthRest(x: 74, tail: .wobbly),
            quarterNote(x: 130),
            quarterNote(x: 180),
            quarterNote(x: 230)
        ].flatMap { $0 })

        let values = try RhythmicNotationQuantizer.quantize(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        XCTAssertEqual(values, [.eighthRest, .eighthRest, .quarter, .quarter, .quarter])
    }

    func testQuantizerReadsNoNoteheadOneZigEighthRestVariants() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 270, height: 88)
        let restVariants: [(name: String, make: (CGFloat) -> [PKStroke])] = [
            ("small zig", smallOneZigEighthRest),
            ("compact curl", compactOneZigEighthRest),
            ("vertical flick", verticalOneZigEighthRest),
            ("angled notch", angledOneZigEighthRest)
        ]

        for variant in restVariants {
            let drawing = PKDrawing(strokes: [
                variant.make(24),
                variant.make(74),
                quarterNote(x: 130),
                quarterNote(x: 180),
                quarterNote(x: 230)
            ].flatMap { $0 })

            let values = try RhythmicNotationQuantizer.quantize(
                drawing: drawing,
                meter: Meter(numerator: 4, denominator: 4),
                drawingFrame: drawingFrame
            )

            XCTAssertEqual(values, [.eighthRest, .eighthRest, .quarter, .quarter, .quarter], variant.name)
        }
    }

    func testQuantizerDoesNotPromoteNoNoteheadEighthRestGesturesToEighthNotes() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 270, height: 88)
        let drawing = PKDrawing(strokes: [
            flagLikeNoNoteheadEighthRest(x: 24),
            softHookNoNoteheadEighthRest(x: 74),
            quarterNote(x: 130),
            quarterNote(x: 180),
            quarterNote(x: 230)
        ].flatMap { $0 })

        let values = try RhythmicNotationQuantizer.quantize(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        XCTAssertEqual(values, [.eighthRest, .eighthRest, .quarter, .quarter, .quarter])
    }

    func testV4TemplateDoesNotExposeEighthNoteForNoNoteheadEighthRestGestures() {
        let drawingFrame = CGRect(x: 0, y: 0, width: 120, height: 88)
        let restVariants: [(name: String, make: (CGFloat) -> [PKStroke])] = [
            ("one zig", smallOneZigEighthRest),
            ("flag-like", flagLikeNoNoteheadEighthRest),
            ("soft hook", softHookNoNoteheadEighthRest)
        ]

        for variant in restVariants {
            let templateValues = RhythmicNotationQuantizer.v4TemplateValuesForTesting(
                drawing: PKDrawing(strokes: variant.make(24)),
                drawingFrame: drawingFrame
            ).flatMap { $0 }

            XCTAssertTrue(templateValues.contains(.eighthRest), variant.name)
            XCTAssertFalse(templateValues.contains(.eighth), variant.name)
        }
    }

    func testV4TemplateStillAllowsRealSingleEighthNotesWithLowerNoteheads() {
        let drawingFrame = CGRect(x: 0, y: 0, width: 120, height: 88)

        let templateValues = RhythmicNotationQuantizer.v4TemplateValuesForTesting(
            drawing: PKDrawing(strokes: singleEighth(x: 24)),
            drawingFrame: drawingFrame
        ).flatMap { $0 }

        XCTAssertTrue(templateValues.contains(.eighth))
        XCTAssertFalse(templateValues.contains(.eighthRest))
    }

    func testV4TemplateDoesNotExposeLongRestForStemmedNoteCluster() {
        let drawingFrame = CGRect(x: 0, y: 0, width: 140, height: 88)

        let templateValues = RhythmicNotationQuantizer.v4TemplateValuesForTesting(
            drawing: PKDrawing(strokes: stemmedWholeRestLikeCluster(x: 32)),
            drawingFrame: drawingFrame
        ).flatMap { $0 }

        XCTAssertFalse(templateValues.contains(.wholeRest))
        XCTAssertFalse(templateValues.contains(.halfRest))
    }

    func testQuantizerReadsDotTailRestDottedQuarterHalfFromSparseLiveInk() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 244, height: 78)
        let drawing = PKDrawing(strokes: [
            sparseDotTailEighthRest(x: 24),
            sparseDottedQuarterWithTapDot(x: 50),
            sparseHalfNote(x: 109)
        ].flatMap { $0 })

        let values = try RhythmicNotationQuantizer.quantize(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        XCTAssertEqual(values, [.eighthRest, .dottedQuarter, .half])
    }

    func testQuantizerReadsMessyZigZagQuarterRests() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 240, height: 88)
        let drawing = PKDrawing(strokes: [
            denseZigZagQuarterRest(x: 24),
            wideZigZagQuarterRest(x: 82),
            halfNote(x: 156)
        ].flatMap { $0 })

        let values = try RhythmicNotationQuantizer.quantize(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        XCTAssertEqual(values, [.quarterRest, .quarterRest, .half])
    }

    func testQuantizerReadsHumanOneStrokeQuarterRestVariants() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 260, height: 88)
        let restVariants: [(name: String, strokes: [PKStroke])] = [
            ("s-curve", sCurveQuarterRest(x: 24)),
            ("shallow wiggle", shallowWiggleQuarterRest(x: 24)),
            ("vertical squiggle", verticalSquiggleQuarterRest(x: 24)),
            ("narrow curl", narrowCurlQuarterRest(x: 24))
        ]

        for variant in restVariants {
            let drawing = PKDrawing(strokes: [
                variant.strokes,
                quarterNote(x: 86),
                quarterNote(x: 142),
                quarterNote(x: 198)
            ].flatMap { $0 })

            let values = try RhythmicNotationQuantizer.quantize(
                drawing: drawing,
                meter: Meter(numerator: 4, denominator: 4),
                drawingFrame: drawingFrame
            )

            XCTAssertEqual(values, [.quarterRest, .quarter, .quarter, .quarter], variant.name)
        }
    }

    func testQuantizerDoesNotReadNotesAsQuarterRests() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 260, height: 88)
        let drawing = PKDrawing(strokes: [
            quarterNote(x: 24),
            quarterNoteWithWideStem(x: 86),
            touchedUpQuarterNote(x: 142),
            quarterNote(x: 198)
        ].flatMap { $0 })

        let values = try RhythmicNotationQuantizer.quantize(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        XCTAssertEqual(values, [.quarter, .quarter, .quarter, .quarter])
    }

    func testQuantizerReadsLeftHookSevenMarksAsEighthRests() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 270, height: 88)
        let drawing = PKDrawing(strokes: [
            leftHookEighthRest(x: 24),
            leftHookEighthRest(x: 74),
            quarterNote(x: 130),
            quarterNote(x: 180),
            quarterNote(x: 230)
        ].flatMap { $0 })

        let values = try RhythmicNotationQuantizer.quantize(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        XCTAssertEqual(values, [.eighthRest, .eighthRest, .quarter, .quarter, .quarter])
    }

    func testQuantizerReadsOneStrokeSevenMarksAsEighthRests() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 270, height: 88)
        let drawing = PKDrawing(strokes: [
            singleStrokeHookedEighthRest(x: 24),
            singleStrokeHookedEighthRest(x: 74),
            quarterNote(x: 130),
            quarterNote(x: 180),
            quarterNote(x: 230)
        ].flatMap { $0 })

        let values = try RhythmicNotationQuantizer.quantize(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        XCTAssertEqual(values, [.eighthRest, .eighthRest, .quarter, .quarter, .quarter])
    }

    func testQuantizerReadsTailFirstSevenMarksAsEighthRests() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 270, height: 88)
        let drawing = PKDrawing(strokes: [
            tailFirstEighthRest(x: 24),
            tailFirstEighthRest(x: 74),
            quarterNote(x: 130),
            quarterNote(x: 180),
            quarterNote(x: 230)
        ].flatMap { $0 })

        let values = try RhythmicNotationQuantizer.quantize(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        XCTAssertEqual(values, [.eighthRest, .eighthRest, .quarter, .quarter, .quarter])
    }

    func testQuantizerReadsTwoStrokeSevenMarksAsEighthRests() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 270, height: 88)
        let drawing = PKDrawing(strokes: [
            rightwardHookEighthRest(x: 24),
            leftHookEighthRest(x: 74),
            quarterNote(x: 130),
            quarterNote(x: 180),
            quarterNote(x: 230)
        ].flatMap { $0 })

        let values = try RhythmicNotationQuantizer.quantize(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        XCTAssertEqual(values, [.eighthRest, .eighthRest, .quarter, .quarter, .quarter])
    }

    func testQuantizerReadsThreePartVisualEighthRestSymbol() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 270, height: 88)
        let drawing = PKDrawing(strokes: [
            standardEighthRest(x: 24),
            standardEighthRest(x: 74),
            quarterNote(x: 130),
            quarterNote(x: 180),
            quarterNote(x: 230)
        ].flatMap { $0 })

        let values = try RhythmicNotationQuantizer.quantize(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        XCTAssertEqual(values, [.eighthRest, .eighthRest, .quarter, .quarter, .quarter])
    }

    func testQuantizerReadsVisualSymbolsRegardlessOfStrokeOrder() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 244, height: 78)
        let drawing = PKDrawing(strokes: [
            sparseDottedQuarterWithTapDot(x: 50).reversed(),
            sparseHalfNote(x: 109).reversed(),
            sparseDotTailEighthRest(x: 24).reversed()
        ].flatMap { $0 })

        let values = try RhythmicNotationQuantizer.quantize(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        XCTAssertEqual(values, [.eighthRest, .dottedQuarter, .half])
    }

    func testQuantizerSplitsLoopedDotHookTailEighthRestSymbolFromDottedQuarterAndHalf() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 244, height: 78)
        let drawing = PKDrawing(strokes: [
            loopedDotHookTailEighthRestSymbol(x: 13),
            sparseDottedQuarterWithTapDot(x: 48),
            sparseHalfNote(x: 114)
        ].flatMap { $0 })

        let values = try RhythmicNotationQuantizer.quantize(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        XCTAssertEqual(values, [.eighthRest, .dottedQuarter, .half])
    }

    func testQuantizerReadsOneTakeDotHookTailAsEighthRestSymbol() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 260, height: 88)
        let drawing = PKDrawing(strokes: [
            oneTakeDotHookTailEighthRest(x: 18),
            singleEighth(x: 58),
            dottedHalfNote(x: 124)
        ].flatMap { $0 })

        let values = try RhythmicNotationQuantizer.quantize(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        XCTAssertEqual(values, [.eighthRest, .eighth, .dottedHalf])
    }

    func testQuantizerReadsSevenLikeMarkAsEighthRestSymbol() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 260, height: 88)
        let drawing = PKDrawing(strokes: [
            sevenLikeEighthRest(x: 20),
            singleEighth(x: 64),
            dottedHalfNote(x: 126)
        ].flatMap { $0 })

        let values = try RhythmicNotationQuantizer.quantize(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        XCTAssertEqual(values, [.eighthRest, .eighth, .dottedHalf])
    }

    func testQuantizerReadsWideSevenLikeMarkAsEighthRestSymbol() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 260, height: 88)
        let drawing = PKDrawing(strokes: [
            wideSevenLikeEighthRest(x: 18),
            singleEighth(x: 62),
            dottedHalfNote(x: 124)
        ].flatMap { $0 })

        let values = try RhythmicNotationQuantizer.quantize(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        XCTAssertEqual(values, [.eighthRest, .eighth, .dottedHalf])
    }

    func testQuantizerReadsWobblySevenLikeMarkAsEighthRestSymbol() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 260, height: 88)
        let drawing = PKDrawing(strokes: [
            wobblySevenLikeEighthRest(x: 18),
            singleEighth(x: 62),
            dottedHalfNote(x: 124)
        ].flatMap { $0 })

        let values = try RhythmicNotationQuantizer.quantize(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        XCTAssertEqual(values, [.eighthRest, .eighth, .dottedHalf])
    }

    func testQuantizerReadsLiveWobblySevenLikeMarkAsEighthRestSymbol() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 260, height: 88)
        let drawing = PKDrawing(strokes: [
            liveWobblySevenLikeEighthRest(),
            singleEighth(x: 64),
            dottedHalfNote(x: 126)
        ].flatMap { $0 })

        let values = try RhythmicNotationQuantizer.quantize(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        XCTAssertEqual(values, [.eighthRest, .eighth, .dottedHalf])
    }

    func testQuantizerReadsCurrentOneStrokeSevenLikeMarkAsEighthRestSymbol() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 260, height: 88)
        let drawing = PKDrawing(strokes: [
            currentOneStrokeSevenLikeEighthRest(),
            singleEighth(x: 72),
            dottedHalfNote(x: 132)
        ].flatMap { $0 })

        let values = try RhythmicNotationQuantizer.quantize(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        XCTAssertEqual(values, [.eighthRest, .eighth, .dottedHalf])
    }

    func testQuantizerReadsCurrentScreenEighthRestEighthDottedHalf() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 260, height: 88)
        let drawing = PKDrawing(strokes: currentScreenEighthRestEighthDottedHalf())

        let values = try RhythmicNotationQuantizer.quantize(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        XCTAssertEqual(values, [.eighthRest, .eighth, .dottedHalf])
    }

    func testV3DecisionKeepsNonVisualFallbackExactFitLocalWithoutProposal() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 260, height: 88)
        let drawing = PKDrawing(strokes: fallbackStemOnlyQuarterMarks())

        let values = try RhythmicNotationQuantizer.quantize(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )
        let decision = RhythmicNotationQuantizer.recognitionDecision(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        XCTAssertEqual(values, [.quarter, .quarter, .quarter, .quarter])
        guard case .keepWriting(let reason, let phrase?) = decision else {
            XCTFail("Expected V3 to keep non-visual fallback ink local, got \(decision)")
            return
        }
        XCTAssertEqual(reason, .nonVisualFallback)
        XCTAssertEqual(phrase.source, .legacyFallback)
        XCTAssertEqual(phrase.naturalValues, [.quarter, .quarter, .quarter, .quarter])
    }

    func testQuantizerDoesNotStealOneTakeEighthRestAsEighthNote() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 300, height: 88)
        let drawing = PKDrawing(strokes: [
            oneTakeDotHookTailEighthRest(x: 24),
            singleEighth(x: 72),
            quarterNote(x: 132),
            halfNote(x: 210)
        ].flatMap { $0 })

        let values = try RhythmicNotationQuantizer.quantize(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        XCTAssertEqual(values, [.eighthRest, .eighth, .quarter, .half])
    }

    func testQuantizerDoesNotReadLowerEighthNoteHeadAsTopDotEighthRest() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 300, height: 88)
        let drawing = PKDrawing(strokes: [
            singleEighth(x: 24),
            singleEighth(x: 72),
            quarterNote(x: 132),
            halfNote(x: 210)
        ].flatMap { $0 })

        let values = try RhythmicNotationQuantizer.quantize(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        XCTAssertEqual(values, [.eighth, .eighth, .quarter, .half])
    }

    func testQuantizerCollapsesTouchedUpNoteheadInkIntoOneVisualQuarter() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 260, height: 88)
        let drawing = PKDrawing(strokes: [
            touchedUpQuarterNote(x: 24),
            touchedUpQuarterNote(x: 84),
            touchedUpQuarterNote(x: 144),
            touchedUpQuarterNote(x: 204)
        ].flatMap { $0 })

        let values = try RhythmicNotationQuantizer.quantize(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        XCTAssertEqual(values, [.quarter, .quarter, .quarter, .quarter])
    }

    func testQuantizerKeepsEighthRestBeforeNearbyEighthNote() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 260, height: 88)
        let drawing = PKDrawing(strokes: [
            eighthRest(x: 24),
            singleEighth(x: 56),
            quarterNote(x: 122),
            halfNote(x: 190)
        ].flatMap { $0 })

        let values = try RhythmicNotationQuantizer.quantize(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        XCTAssertEqual(values, [.eighthRest, .eighth, .quarter, .half])
    }

    func testQuantizerReadsTouchedUpQuarterRestSquiggles() throws {
        let drawingFrame = CGRect(x: 0, y: 0, width: 240, height: 88)
        let drawing = PKDrawing(strokes: [
            touchedUpQuarterRest(x: 24),
            wideZigZagQuarterRest(x: 82),
            halfNote(x: 156)
        ].flatMap { $0 })

        let values = try RhythmicNotationQuantizer.quantize(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        XCTAssertEqual(values, [.quarterRest, .quarterRest, .half])
    }

    func testLeadSheetRhythmCommitStoresPitchedNotesFromStaffInkAnchors() throws {
        let chart = Chart.blank(title: "Lead", measureCount: 1, layoutStyle: .leadSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        let measureLayout = try firstLeadSheetMeasureLayout(in: chart)
        let xPositions = leadSheetBeatXPositions(in: measureLayout)
        let drawing = PKDrawing(strokes: [
            leadSheetQuarterNote(x: xPositions[0], y: leadSheetStaffY(step: 0, in: measureLayout), stemUp: false),
            leadSheetQuarterNote(x: xPositions[1], y: leadSheetStaffY(step: 2, in: measureLayout), stemUp: false),
            leadSheetQuarterNote(x: xPositions[2], y: leadSheetStaffY(step: 4, in: measureLayout), stemUp: true),
            leadSheetQuarterNote(x: xPositions[3], y: leadSheetStaffY(step: 8, in: measureLayout), stemUp: true)
        ].flatMap { $0 })
        let drawingFrame = CGRect(
            origin: .zero,
            size: LeadSheetRhythmicNotationInkCapturePolicy.analysisFrame(for: measureLayout).size
        )
        let anchors = RhythmicNotationQuantizer.visualNoteAnchors(
            drawing: drawing,
            drawingFrame: drawingFrame
        )
        let decision = RhythmicNotationQuantizer.recognitionDecision(
            drawing: drawing,
            meter: Meter(numerator: 4, denominator: 4),
            drawingFrame: drawingFrame
        )

        XCTAssertEqual(anchors.count, 4, "\(anchors)")
        guard case .commit(let proposal, _) = decision else {
            XCTFail("Expected staff-position quarter notes to commit, got \(decision)")
            return
        }
        XCTAssertEqual(proposal.values, [.quarter, .quarter, .quarter, .quarter])

        let updatedChart = try XCTUnwrap(
            LeadSheetRhythmicNotationFinalization.chartByApplyingQuantizedRhythmMap(
                proposal.values,
                drawingData: drawing.dataRepresentation(),
                for: measureID,
                measureLayout: measureLayout,
                in: chart
            )
        )
        let updatedMeasure = try XCTUnwrap(updatedChart.measure(id: measureID))

        XCTAssertEqual(updatedMeasure.rhythmMap?.values, [.quarter, .quarter, .quarter, .quarter])
        XCTAssertEqual(updatedMeasure.pitchedNoteEvents.map(\.rhythmSlotIndex), [0, 1, 2, 3])
        XCTAssertEqual(updatedMeasure.pitchedNoteEvents.map(\.staffPosition.staffStep), [0, 2, 4, 8])
        XCTAssertNil(updatedMeasure.handwrittenRhythmicNotationData)
    }

    func testLeadSheetRhythmCommitRequiresPitchAnchorsForPitchedValues() throws {
        let chart = Chart.blank(title: "Lead", measureCount: 1, layoutStyle: .leadSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        let measureLayout = try firstLeadSheetMeasureLayout(in: chart)
        let xPositions = leadSheetBeatXPositions(in: measureLayout)
        let drawing = PKDrawing(strokes: [
            leadSheetQuarterNote(x: xPositions[0], y: leadSheetStaffY(step: 4, in: measureLayout), stemUp: true),
            leadSheetQuarterNote(x: xPositions[1], y: leadSheetStaffY(step: 4, in: measureLayout), stemUp: true),
            leadSheetQuarterNote(x: xPositions[2], y: leadSheetStaffY(step: 4, in: measureLayout), stemUp: true)
        ].flatMap { $0 })

        let updatedChart = LeadSheetRhythmicNotationFinalization.chartByApplyingQuantizedRhythmMap(
            [.quarter, .quarter, .quarter, .quarter],
            drawingData: drawing.dataRepresentation(),
            for: measureID,
            measureLayout: measureLayout,
            in: chart
        )

        XCTAssertNil(updatedChart)
    }

    func testLeadSheetRhythmCommitStoresMixedNotesAndRestsWithPitchAnchors() throws {
        let chart = Chart.blank(title: "Lead", measureCount: 1, layoutStyle: .leadSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        let measureLayout = try firstLeadSheetMeasureLayout(in: chart)
        let xPositions = leadSheetBeatXPositions(in: measureLayout)
        let drawing = PKDrawing(strokes: [
            leadSheetQuarterNote(x: xPositions[0], y: leadSheetStaffY(step: 3, in: measureLayout), stemUp: false),
            leadSheetQuarterNote(x: xPositions[2], y: leadSheetStaffY(step: 6, in: measureLayout), stemUp: true)
        ].flatMap { $0 })

        let updatedChart = try XCTUnwrap(
            LeadSheetRhythmicNotationFinalization.chartByApplyingQuantizedRhythmMap(
                [.quarter, .quarterRest, .quarter, .quarterRest],
                drawingData: drawing.dataRepresentation(),
                for: measureID,
                measureLayout: measureLayout,
                in: chart
            )
        )
        let updatedMeasure = try XCTUnwrap(updatedChart.measure(id: measureID))

        XCTAssertEqual(updatedMeasure.rhythmMap?.values, [.quarter, .quarterRest, .quarter, .quarterRest])
        XCTAssertEqual(updatedMeasure.pitchedNoteEvents.map(\.rhythmSlotIndex), [0, 2])
        XCTAssertEqual(updatedMeasure.pitchedNoteEvents.map(\.staffPosition.staffStep), [3, 6])
    }

    func testLeadSheetRhythmCommitStoresBeamedEighthPitchAnchors() throws {
        let chart = Chart.blank(title: "Lead", measureCount: 1, layoutStyle: .leadSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        let measureLayout = try firstLeadSheetMeasureLayout(in: chart)
        let xPositions = leadSheetBeatXPositions(in: measureLayout)
        let drawing = PKDrawing(strokes: [
            leadSheetBeamedEighthPair(
                leftX: xPositions[0] - 12,
                rightX: xPositions[0] + 22,
                leftY: leadSheetStaffY(step: 2, in: measureLayout),
                rightY: leadSheetStaffY(step: 5, in: measureLayout),
                stemUp: true
            ),
            leadSheetDottedQuarterNote(
                x: xPositions[2],
                y: leadSheetStaffY(step: 7, in: measureLayout),
                stemUp: true
            ),
            leadSheetDottedQuarterNote(
                x: xPositions[3],
                y: leadSheetStaffY(step: 1, in: measureLayout),
                stemUp: true
            )
        ].flatMap { $0 })
        let drawingFrame = CGRect(
            origin: .zero,
            size: LeadSheetRhythmicNotationInkCapturePolicy.analysisFrame(for: measureLayout).size
        )
        let anchors = RhythmicNotationQuantizer.visualNoteAnchors(
            drawing: drawing,
            drawingFrame: drawingFrame
        )

        XCTAssertEqual(anchors.count, 4, "\(anchors)")

        let updatedChart = try XCTUnwrap(
            LeadSheetRhythmicNotationFinalization.chartByApplyingQuantizedRhythmMap(
                [.eighth, .eighth, .dottedQuarter, .dottedQuarter],
                drawingData: drawing.dataRepresentation(),
                for: measureID,
                measureLayout: measureLayout,
                in: chart
            )
        )
        let updatedMeasure = try XCTUnwrap(updatedChart.measure(id: measureID))

        XCTAssertEqual(updatedMeasure.rhythmMap?.values, [.eighth, .eighth, .dottedQuarter, .dottedQuarter])
        XCTAssertEqual(updatedMeasure.pitchedNoteEvents.map(\.rhythmSlotIndex), [0, 1, 2, 3])
        XCTAssertEqual(updatedMeasure.pitchedNoteEvents.map(\.staffPosition.staffStep), [2, 5, 7, 1])
    }

    func testReplayExternalRhythmSectionInkThroughLiveDecisionRouteWhenProvided() throws {
        let snapshot: ChartLibrarySnapshot
        if let stateBase64 = replayEnvironmentValue("ICHART_RHYTHM_STATE_BASE64"),
           let stateData = Data(base64Encoded: stateBase64) {
            let stateURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("ichart-rhythm-replay-\(UUID().uuidString).json")
            try stateData.write(to: stateURL)
            snapshot = try XCTUnwrap(try FileChartRepository(url: stateURL).loadSnapshot())
        } else if let statePath = replayEnvironmentValue("ICHART_RHYTHM_STATE") {
            let repository = FileChartRepository(url: URL(fileURLWithPath: statePath))
            guard let loadedSnapshot = try repository.loadSnapshot() else {
                throw XCTSkip("Rhythm replay state was not readable from this test runner: \(statePath)")
            }
            snapshot = loadedSnapshot
        } else if replayEnvironmentValue("ICHART_RHYTHM_STATE_LIVE") == "1" {
            guard let loadedSnapshot = try FileChartRepository.live().loadSnapshot() else {
                throw XCTSkip("Live Rhythm Section replay state was not available in this test runner.")
            }
            snapshot = loadedSnapshot
        } else {
            throw XCTSkip(
                "Set ICHART_RHYTHM_STATE, ICHART_RHYTHM_STATE_BASE64, or ICHART_RHYTHM_STATE_LIVE to replay saved rhythm ink."
            )
        }
        let chart = try XCTUnwrap(selectedReplayChart(in: snapshot))
        XCTAssertEqual(chart.layoutStyle, .rhythmSectionSheet)

        let replayMeasure = chart.measures.first { measure in
            if let measureIDText = replayEnvironmentValue("ICHART_RHYTHM_REPLAY_MEASURE_ID"),
               let measureID = UUID(uuidString: measureIDText),
               measure.id != measureID {
                return false
            }
            guard let data = measure.handwrittenRhythmicNotationData else {
                return false
            }
            return !data.isEmpty && measure.rhythmMap == nil
        }
        guard let measure = replayMeasure else {
            if replayEnvironmentValue("ICHART_RHYTHM_STATE_LIVE") == "1",
               replayEnvironmentValue("ICHART_RHYTHM_STATE") == nil,
               replayEnvironmentValue("ICHART_RHYTHM_STATE_BASE64") == nil {
                throw XCTSkip("Live Rhythm Section replay state has no saved raw rhythm ink awaiting render.")
            }
            return XCTFail("Expected a Rhythm Section measure with saved raw rhythm ink and no rhythm map.")
        }
        let drawingData = try XCTUnwrap(measure.handwrittenRhythmicNotationData)
        let pageLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 1024, height: 1200)
        )
        let measureLayout = try XCTUnwrap(
            pageLayout.systems.flatMap(\.measures).first { $0.sourceMeasureID == measure.id }
        )

        let decision = try LeadSheetRhythmicNotationFinalization.recognitionDecision(
            drawingData: drawingData,
            measure: measure,
            defaultMeter: chart.defaultMeter,
            measureLayout: measureLayout
        )
        let route = LeadSheetRhythmicNotationLiveDecisionPolicy.route(
            for: decision,
            requiresNaturalExactFitAfterErase: false
        )

        print(
            [
                "rhythmReplay",
                "chart=\(chart.id.uuidString)",
                "measure=\(measure.index)",
                "decision=\(decision)",
                "route=\(route)"
            ].joined(separator: " ")
        )

        guard case .commit(let values, _) = route else {
            return XCTFail("Expected saved full-measure rhythm ink to route to commit, got \(route).")
        }

        let updatedChart = try XCTUnwrap(
            LeadSheetRhythmicNotationFinalization.chartByApplyingQuantizedRhythmMap(
                values,
                drawingData: drawingData,
                for: measure.id,
                measureLayout: measureLayout,
                in: chart
            )
        )
        let updatedMeasure = try XCTUnwrap(updatedChart.measure(id: measure.id))
        XCTAssertEqual(updatedMeasure.rhythmMap?.values, values)
        XCTAssertNil(updatedMeasure.handwrittenRhythmicNotationData)
    }

    func testPipelinePreviewReportsStagesForActualPencilInk() {
        let meter = Meter(numerator: 4, denominator: 4)
        let drawingFrame = CGRect(x: 0, y: 0, width: 220, height: 88)
        let drawing = PKDrawing(strokes: eighthRest(x: 26) + singleEighth(x: 74))
        let decision = RhythmicNotationQuantizer.recognitionDecision(
            drawing: drawing,
            meter: meter,
            drawingFrame: drawingFrame
        )

        let preview = RhythmRecognitionPipelinePreview.make(
            drawing: drawing,
            meter: meter,
            drawingFrame: drawingFrame,
            decision: decision,
            decisionText: "preview",
            routeText: "preview"
        )

        XCTAssertEqual(preview.strokeCount, drawing.strokes.count)
        XCTAssertFalse(preview.primitives.isEmpty)
        XCTAssertFalse(preview.symbolGroups.isEmpty)
        XCTAssertFalse(preview.reasoningPaths.isEmpty)
        XCTAssertTrue(preview.statusText.contains("strokes"))
        XCTAssertTrue(preview.notes.contains("multiple reasoning paths available"))
    }

    private func firstLeadSheetMeasureLayout(in chart: Chart) throws -> LeadSheetMeasureLayout {
        let pageLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 1024, height: 1200)
        )
        return try XCTUnwrap(pageLayout.systems.first?.measures.first)
    }

    private func selectedReplayChart(in snapshot: ChartLibrarySnapshot) -> Chart? {
        if let chartIDText = replayEnvironmentValue("ICHART_RHYTHM_REPLAY_CHART_ID"),
           let chartID = UUID(uuidString: chartIDText),
           let chart = snapshot.charts.first(where: { $0.id == chartID }) {
            return chart
        }

        if let selectedChartID = snapshot.selectedChartID,
           let chart = snapshot.charts.first(where: { $0.id == selectedChartID }) {
            return chart
        }

        return snapshot.charts.first { $0.layoutStyle == .rhythmSectionSheet }
    }

    private func replayEnvironmentValue(_ key: String) -> String? {
        ProcessInfo.processInfo.environment[key]
            ?? ProcessInfo.processInfo.environment["TEST_RUNNER_\(key)"]
    }

    private func leadSheetStaffY(step: Int, in measureLayout: LeadSheetMeasureLayout) -> CGFloat {
        let activeFrame = LeadSheetRhythmicNotationInkCapturePolicy.analysisFrame(for: measureLayout)
        let staffLineSpacing = max(CGFloat(1), (measureLayout.staffFrame.height - 4) / 4)
        let topStaffLineY = measureLayout.staffFrame.minY + 2 - activeFrame.minY
        return topStaffLineY + CGFloat(step) * staffLineSpacing / 2
    }

    private func leadSheetBeatXPositions(in measureLayout: LeadSheetMeasureLayout) -> [CGFloat] {
        let width = LeadSheetRhythmicNotationInkCapturePolicy.analysisFrame(for: measureLayout).width
        return [0.17, 0.38, 0.59, 0.80].map { width * CGFloat($0) }
    }

    private func leadSheetQuarterNote(x: CGFloat, y: CGFloat, stemUp: Bool) -> [PKStroke] {
        let stemX = stemUp ? x + 4 : x - 4
        let stemEndY = stemUp ? y - 34 : y + 34
        return [
            filledNotehead(center: CGPoint(x: x, y: y)),
            stroke([
                CGPoint(x: stemX, y: y - 2),
                CGPoint(x: stemX, y: stemEndY)
            ])
        ]
    }

    private func leadSheetDottedQuarterNote(x: CGFloat, y: CGFloat, stemUp: Bool) -> [PKStroke] {
        leadSheetQuarterNote(x: x, y: y, stemUp: stemUp) + [
            filledNotehead(center: CGPoint(x: x + 18, y: y + 1), radius: 2.2)
        ]
    }

    private func leadSheetBeamedEighthPair(
        leftX: CGFloat,
        rightX: CGFloat,
        leftY: CGFloat,
        rightY: CGFloat,
        stemUp: Bool
    ) -> [PKStroke] {
        let leftStemX = stemUp ? leftX + 4 : leftX - 4
        let rightStemX = stemUp ? rightX + 4 : rightX - 4
        let beamY = stemUp
            ? min(leftY, rightY) - 34
            : max(leftY, rightY) + 34
        return [
            filledNotehead(center: CGPoint(x: leftX, y: leftY)),
            stroke([
                CGPoint(x: leftStemX, y: leftY - 2),
                CGPoint(x: leftStemX, y: beamY)
            ]),
            filledNotehead(center: CGPoint(x: rightX, y: rightY)),
            stroke([
                CGPoint(x: rightStemX, y: rightY - 2),
                CGPoint(x: rightStemX, y: beamY)
            ]),
            stroke([
                CGPoint(x: leftStemX, y: beamY),
                CGPoint(x: rightStemX, y: beamY)
            ])
        ]
    }

    private func beamedEighthPair(startX: CGFloat) -> [PKStroke] {
        [
            stroke([
                CGPoint(x: startX + 4, y: 60),
                CGPoint(x: startX + 4, y: 22),
                CGPoint(x: startX + 38, y: 22),
                CGPoint(x: startX + 38, y: 60)
            ]),
            filledNotehead(center: CGPoint(x: startX + 4, y: 60)),
            filledNotehead(center: CGPoint(x: startX + 38, y: 60))
        ]
    }

    private func directBeamedEighthPair(startX: CGFloat) -> [PKStroke] {
        [
            filledNotehead(center: CGPoint(x: startX + 4, y: 60)),
            stroke([
                CGPoint(x: startX + 8, y: 58),
                CGPoint(x: startX + 8, y: 22)
            ]),
            filledNotehead(center: CGPoint(x: startX + 38, y: 60)),
            stroke([
                CGPoint(x: startX + 42, y: 58),
                CGPoint(x: startX + 42, y: 22)
            ]),
            stroke([
                CGPoint(x: startX + 8, y: 22),
                CGPoint(x: startX + 42, y: 22)
            ])
        ]
    }

    private func looselyBeamedEighthPair(startX: CGFloat) -> [PKStroke] {
        [
            filledNotehead(center: CGPoint(x: startX + 4, y: 60)),
            stroke([
                CGPoint(x: startX + 8, y: 58),
                CGPoint(x: startX + 8, y: 22)
            ]),
            filledNotehead(center: CGPoint(x: startX + 38, y: 60)),
            stroke([
                CGPoint(x: startX + 42, y: 58),
                CGPoint(x: startX + 42, y: 22)
            ]),
            stroke([
                CGPoint(x: startX + 15, y: 20),
                CGPoint(x: startX + 35, y: 21)
            ])
        ]
    }

    private func looselyBeamedEighthPairDrawnOutOfOrder(startX: CGFloat) -> [PKStroke] {
        let leftHead = filledNotehead(center: CGPoint(x: startX + 4, y: 60))
        let leftStem = stroke([
            CGPoint(x: startX + 8, y: 58),
            CGPoint(x: startX + 8, y: 22)
        ])
        let rightHead = filledNotehead(center: CGPoint(x: startX + 38, y: 60))
        let rightStem = stroke([
            CGPoint(x: startX + 42, y: 58),
            CGPoint(x: startX + 42, y: 22)
        ])
        let beam = stroke([
            CGPoint(x: startX + 15, y: 20),
            CGPoint(x: startX + 35, y: 21)
        ])

        return [beam, rightStem, rightHead, leftStem, leftHead]
    }

    private enum BeamSlopeDirection {
        case downward
        case upward
    }

    private func slopedLooseBeamedEighthPair(
        startX: CGFloat,
        direction: BeamSlopeDirection
    ) -> [PKStroke] {
        let beamPoints: [CGPoint]
        switch direction {
        case .downward:
            beamPoints = [
                CGPoint(x: startX + 13, y: 19),
                CGPoint(x: startX + 36, y: 32)
            ]
        case .upward:
            beamPoints = [
                CGPoint(x: startX + 13, y: 32),
                CGPoint(x: startX + 36, y: 19)
            ]
        }

        return [
            filledNotehead(center: CGPoint(x: startX + 4, y: 60)),
            stroke([
                CGPoint(x: startX + 8, y: 58),
                CGPoint(x: startX + 8, y: 22)
            ]),
            filledNotehead(center: CGPoint(x: startX + 38, y: 60)),
            stroke([
                CGPoint(x: startX + 42, y: 58),
                CGPoint(x: startX + 42, y: 22)
            ]),
            stroke(beamPoints)
        ]
    }

    private func foldedRightStemBeamedEighthPair(startX: CGFloat) -> [PKStroke] {
        [
            filledNotehead(center: CGPoint(x: startX + 4, y: 60)),
            stroke([
                CGPoint(x: startX + 8, y: 58),
                CGPoint(x: startX + 8, y: 22)
            ]),
            stroke([
                CGPoint(x: startX + 15, y: 22),
                CGPoint(x: startX + 38, y: 20),
                CGPoint(x: startX + 38, y: 58)
            ]),
            filledNotehead(center: CGPoint(x: startX + 38, y: 60))
        ]
    }

    private func stemAndBeamOnlyPair(startX: CGFloat) -> [PKStroke] {
        [
            stroke([
                CGPoint(x: startX + 8, y: 60),
                CGPoint(x: startX + 8, y: 22)
            ]),
            stroke([
                CGPoint(x: startX + 42, y: 60),
                CGPoint(x: startX + 42, y: 22)
            ]),
            stroke([
                CGPoint(x: startX + 8, y: 22),
                CGPoint(x: startX + 42, y: 22)
            ])
        ]
    }

    private func dottedQuarter(x: CGFloat) -> [PKStroke] {
        [
            filledNotehead(center: CGPoint(x: x, y: 60)),
            stroke([
                CGPoint(x: x + 5, y: 58),
                CGPoint(x: x + 5, y: 22)
            ]),
            filledNotehead(center: CGPoint(x: x + 18, y: 61), radius: 2.2)
        ]
    }

    private func wholeNote(x: CGFloat) -> [PKStroke] {
        [
            hollowNotehead(center: CGPoint(x: x + 9, y: 60), radius: 8.2)
        ]
    }

    private func compactWholeNote(x: CGFloat) -> [PKStroke] {
        [
            hollowNotehead(center: CGPoint(x: x + 6, y: 60), radius: 5.0)
        ]
    }

    private func handDrawnCircleWholeNote(x: CGFloat) -> [PKStroke] {
        let center = CGPoint(x: x + 8, y: 60)
        let radius = CGFloat(6.2)
        let points = (0...22).map { index in
            let angle = CGFloat(index) / 22 * .pi * 2
            let wobble = index.isMultiple(of: 2) ? CGFloat(0.8) : CGFloat(-0.35)
            return CGPoint(
                x: center.x + cos(angle) * (radius + wobble),
                y: center.y + sin(angle) * (radius * 0.78 - wobble * 0.2)
            )
        }
        return [stroke(points)]
    }

    private func tinyWholeLikeMark(x: CGFloat) -> [PKStroke] {
        [
            hollowNotehead(center: CGPoint(x: x + 5, y: 55), radius: 2.3)
        ]
    }

    private func singleEighth(x: CGFloat) -> [PKStroke] {
        [
            filledNotehead(center: CGPoint(x: x, y: 60)),
            stroke([
                CGPoint(x: x + 5, y: 58),
                CGPoint(x: x + 5, y: 22)
            ]),
            stroke([
                CGPoint(x: x + 5, y: 22),
                CGPoint(x: x + 18, y: 31),
                CGPoint(x: x + 13, y: 38)
            ])
        ]
    }

    private func halfNote(x: CGFloat) -> [PKStroke] {
        [
            hollowNotehead(center: CGPoint(x: x, y: 60)),
            stroke([
                CGPoint(x: x + 5, y: 58),
                CGPoint(x: x + 5, y: 22)
            ])
        ]
    }

    private func dottedHalfNote(x: CGFloat) -> [PKStroke] {
        halfNote(x: x) + [
            filledNotehead(center: CGPoint(x: x + 24, y: 61), radius: 2.2)
        ]
    }

    private func touchedUpBeamedEighthPair(startX: CGFloat) -> [PKStroke] {
        [
            filledNotehead(center: CGPoint(x: startX + 4, y: 60)),
            stroke([
                CGPoint(x: startX + 8, y: 58),
                CGPoint(x: startX + 8, y: 25)
            ]),
            stroke([
                CGPoint(x: startX + 11, y: 29),
                CGPoint(x: startX + 36, y: 23),
                CGPoint(x: startX + 42, y: 58)
            ]),
            stroke([
                CGPoint(x: startX + 42, y: 34),
                CGPoint(x: startX + 42, y: 60)
            ]),
            filledNotehead(center: CGPoint(x: startX + 38, y: 60)),
            stroke([
                CGPoint(x: startX + 10, y: 31),
                CGPoint(x: startX + 28, y: 26)
            ])
        ]
    }

    private func quarterNote(x: CGFloat) -> [PKStroke] {
        [
            filledNotehead(center: CGPoint(x: x, y: 60)),
            stroke([
                CGPoint(x: x + 5, y: 58),
                CGPoint(x: x + 5, y: 22)
            ])
        ]
    }

    private func quarterNoteWithWideStem(x: CGFloat) -> [PKStroke] {
        [
            filledNotehead(center: CGPoint(x: x, y: 60)),
            stroke([
                CGPoint(x: x + 5, y: 58),
                CGPoint(x: x + 9, y: 42),
                CGPoint(x: x + 12, y: 22)
            ])
        ]
    }

    private func touchedUpQuarterNote(x: CGFloat) -> [PKStroke] {
        [
            filledNotehead(center: CGPoint(x: x, y: 60)),
            filledNotehead(center: CGPoint(x: x + 1.5, y: 60.5), radius: 3.0),
            stroke([
                CGPoint(x: x + 5, y: 58),
                CGPoint(x: x + 5, y: 22)
            ])
        ]
    }

    private enum SlashDirection {
        case slash
        case backslash
    }

    private enum LooseSlashShape {
        case shallow
        case steep
        case wobbly
        case veryWobbly
        case short
    }

    private enum EighthRestTailShape {
        case vertical
        case wobbly
    }

    private func rhythmSlash(x: CGFloat, direction: SlashDirection = .slash) -> [PKStroke] {
        switch direction {
        case .slash:
            return [
                stroke([
                    CGPoint(x: x + 4, y: 64),
                    CGPoint(x: x + 14, y: 47),
                    CGPoint(x: x + 28, y: 28)
                ])
            ]
        case .backslash:
            return [
                stroke([
                    CGPoint(x: x + 4, y: 28),
                    CGPoint(x: x + 15, y: 47),
                    CGPoint(x: x + 28, y: 64)
                ])
            ]
        }
    }

    private func compactRhythmSlash(x: CGFloat, width: CGFloat, height: CGFloat) -> [PKStroke] {
        [
            stroke([
                CGPoint(x: x, y: 69 + height),
                CGPoint(x: x + width * 0.48, y: 69 + height * 0.48),
                CGPoint(x: x + width, y: 69)
            ])
        ]
    }

    private func unrecognizedRhythmMark(x: CGFloat) -> [PKStroke] {
        [
            stroke([
                CGPoint(x: x, y: 40),
                CGPoint(x: x, y: 48)
            ])
        ]
    }

    private func tinyNoiseTap(x: CGFloat, y: CGFloat) -> [PKStroke] {
        [
            stroke([
                CGPoint(x: x, y: y)
            ])
        ]
    }

    private func looseRhythmSlash(x: CGFloat, shape: LooseSlashShape) -> [PKStroke] {
        let points: [CGPoint]
        switch shape {
        case .shallow:
            points = [
                CGPoint(x: x + 3, y: 58),
                CGPoint(x: x + 15, y: 51),
                CGPoint(x: x + 31, y: 44)
            ]
        case .steep:
            points = [
                CGPoint(x: x + 12, y: 64),
                CGPoint(x: x + 17, y: 50),
                CGPoint(x: x + 22, y: 36)
            ]
        case .wobbly:
            points = [
                CGPoint(x: x + 4, y: 66),
                CGPoint(x: x + 11, y: 55),
                CGPoint(x: x + 9, y: 49),
                CGPoint(x: x + 18, y: 40),
                CGPoint(x: x + 24, y: 29)
            ]
        case .veryWobbly:
            points = [
                CGPoint(x: x + 3, y: 68),
                CGPoint(x: x + 12, y: 54),
                CGPoint(x: x + 7, y: 60),
                CGPoint(x: x + 18, y: 40),
                CGPoint(x: x + 15, y: 46),
                CGPoint(x: x + 28, y: 22)
            ]
        case .short:
            points = [
                CGPoint(x: x + 8, y: 57),
                CGPoint(x: x + 15, y: 48),
                CGPoint(x: x + 23, y: 39)
            ]
        }

        return [stroke(points)]
    }

    private func singleStrokeQuarterRest(x: CGFloat) -> [PKStroke] {
        [
            stroke([
                CGPoint(x: x + 8, y: 22),
                CGPoint(x: x + 2, y: 34),
                CGPoint(x: x + 11, y: 45),
                CGPoint(x: x + 4, y: 56),
                CGPoint(x: x + 10, y: 68)
            ])
        ]
    }

    private func looseTwoStrokeQuarterRest(x: CGFloat) -> [PKStroke] {
        [
            stroke([
                CGPoint(x: x + 8, y: 23),
                CGPoint(x: x + 2, y: 36),
                CGPoint(x: x + 10, y: 46)
            ]),
            stroke([
                CGPoint(x: x + 9, y: 45),
                CGPoint(x: x + 3, y: 56),
                CGPoint(x: x + 10, y: 67)
            ])
        ]
    }

    private func halfRest(x: CGFloat) -> [PKStroke] {
        [
            stroke([
                CGPoint(x: x + 2, y: 50),
                CGPoint(x: x + 28, y: 50)
            ]),
            stroke([
                CGPoint(x: x + 6, y: 42),
                CGPoint(x: x + 24, y: 42)
            ])
        ]
    }

    private func wholeRest(x: CGFloat) -> [PKStroke] {
        [
            stroke([
                CGPoint(x: x + 2, y: 34),
                CGPoint(x: x + 30, y: 34)
            ]),
            stroke([
                CGPoint(x: x + 8, y: 40),
                CGPoint(x: x + 24, y: 40),
                CGPoint(x: x + 24, y: 47),
                CGPoint(x: x + 8, y: 47),
                CGPoint(x: x + 8, y: 40),
                CGPoint(x: x + 23, y: 46),
                CGPoint(x: x + 9, y: 46),
                CGPoint(x: x + 23, y: 41)
            ])
        ]
    }

    private func stemmedWholeRestLikeCluster(x: CGFloat) -> [PKStroke] {
        wholeRest(x: x) + [
            stroke([
                CGPoint(x: x + 24, y: 58),
                CGPoint(x: x + 24, y: 22)
            ])
        ]
    }

    private func eighthRest(x: CGFloat) -> [PKStroke] {
        [
            filledNotehead(center: CGPoint(x: x + 4, y: 28), radius: 2.8),
            stroke([
                CGPoint(x: x + 8, y: 28),
                CGPoint(x: x + 4, y: 40),
                CGPoint(x: x + 12, y: 61)
            ])
        ]
    }

    private func dotTailEighthRest(x: CGFloat, tail: EighthRestTailShape) -> [PKStroke] {
        let tailPoints: [CGPoint]
        switch tail {
        case .vertical:
            tailPoints = [
                CGPoint(x: x + 8, y: 29),
                CGPoint(x: x + 8, y: 44),
                CGPoint(x: x + 9, y: 64)
            ]
        case .wobbly:
            tailPoints = [
                CGPoint(x: x + 8, y: 28),
                CGPoint(x: x + 4, y: 40),
                CGPoint(x: x + 11, y: 50),
                CGPoint(x: x + 9, y: 66)
            ]
        }

        return [
            filledNotehead(center: CGPoint(x: x + 4, y: 28), radius: 2.8),
            stroke(tailPoints)
        ]
    }

    private func smallOneZigEighthRest(x: CGFloat) -> [PKStroke] {
        [
            stroke([
                CGPoint(x: x + 9, y: 31),
                CGPoint(x: x + 4, y: 40),
                CGPoint(x: x + 12, y: 49),
                CGPoint(x: x + 8, y: 59)
            ])
        ]
    }

    private func compactOneZigEighthRest(x: CGFloat) -> [PKStroke] {
        [
            stroke([
                CGPoint(x: x + 8, y: 33),
                CGPoint(x: x + 13, y: 40),
                CGPoint(x: x + 6, y: 48),
                CGPoint(x: x + 10, y: 58)
            ])
        ]
    }

    private func verticalOneZigEighthRest(x: CGFloat) -> [PKStroke] {
        [
            stroke([
                CGPoint(x: x + 8, y: 30),
                CGPoint(x: x + 6, y: 40),
                CGPoint(x: x + 10, y: 49),
                CGPoint(x: x + 7, y: 59)
            ])
        ]
    }

    private func angledOneZigEighthRest(x: CGFloat) -> [PKStroke] {
        [
            stroke([
                CGPoint(x: x + 6, y: 32),
                CGPoint(x: x + 12, y: 40),
                CGPoint(x: x + 5, y: 50),
                CGPoint(x: x + 9, y: 60)
            ])
        ]
    }

    private func flagLikeNoNoteheadEighthRest(x: CGFloat) -> [PKStroke] {
        [
            stroke([
                CGPoint(x: x + 13, y: 27),
                CGPoint(x: x + 4, y: 28),
                CGPoint(x: x + 8, y: 36),
                CGPoint(x: x + 9, y: 48),
                CGPoint(x: x + 14, y: 62)
            ])
        ]
    }

    private func softHookNoNoteheadEighthRest(x: CGFloat) -> [PKStroke] {
        [
            stroke([
                CGPoint(x: x + 4, y: 31),
                CGPoint(x: x + 11, y: 32),
                CGPoint(x: x + 8, y: 39),
                CGPoint(x: x + 5, y: 49),
                CGPoint(x: x + 9, y: 61)
            ])
        ]
    }

    private func sparseDotTailEighthRest(x: CGFloat) -> [PKStroke] {
        [
            stroke([
                CGPoint(x: x + 1, y: 38),
                CGPoint(x: x + 4, y: 36),
                CGPoint(x: x + 7, y: 40),
                CGPoint(x: x + 3, y: 42)
            ]),
            stroke([
                CGPoint(x: x + 7, y: 38),
                CGPoint(x: x + 4, y: 47),
                CGPoint(x: x + 11, y: 55),
                CGPoint(x: x + 9, y: 62)
            ])
        ]
    }

    private func sparseDottedQuarterWithTapDot(x: CGFloat) -> [PKStroke] {
        [
            filledNotehead(center: CGPoint(x: x + 3, y: 54), radius: 3.2),
            stroke([
                CGPoint(x: x + 5, y: 50),
                CGPoint(x: x + 5, y: 26)
            ]),
            stroke([
                CGPoint(x: x + 13, y: 55)
            ])
        ]
    }

    private func sparseHalfNote(x: CGFloat) -> [PKStroke] {
        [
            hollowNotehead(center: CGPoint(x: x + 9, y: 53), radius: 8.2),
            stroke([
                CGPoint(x: x + 17, y: 44),
                CGPoint(x: x + 17, y: 17)
            ])
        ]
    }

    private func loopedDotHookTailEighthRestSymbol(x: CGFloat) -> [PKStroke] {
        [
            stroke([
                CGPoint(x: x + 4.5, y: 40.6),
                CGPoint(x: x + 6.7, y: 40.9),
                CGPoint(x: x + 8.5, y: 42.0),
                CGPoint(x: x + 8.5, y: 44.0),
                CGPoint(x: x + 8.0, y: 46.3),
                CGPoint(x: x + 7.0, y: 48.5),
                CGPoint(x: x + 4.5, y: 48.8),
                CGPoint(x: x + 1.5, y: 48.8),
                CGPoint(x: x + 1.5, y: 46.5),
                CGPoint(x: x + 2.5, y: 45.0),
                CGPoint(x: x + 4.0, y: 44.2),
                CGPoint(x: x + 5.9, y: 43.8),
                CGPoint(x: x + 8.5, y: 44.0),
                CGPoint(x: x + 6.9, y: 46.9),
                CGPoint(x: x + 5.5, y: 48.1),
                CGPoint(x: x + 4.0, y: 49.0),
                CGPoint(x: x + 1.5, y: 48.3),
                CGPoint(x: x + 2.7, y: 46.8),
                CGPoint(x: x + 4.0, y: 45.0),
                CGPoint(x: x + 5.5, y: 43.7),
                CGPoint(x: x + 8.1, y: 42.8),
                CGPoint(x: x + 7.0, y: 44.0),
                CGPoint(x: x + 4.5, y: 45.5),
                CGPoint(x: x + 3.6, y: 46.7),
                CGPoint(x: x + 1.0, y: 47.0),
                CGPoint(x: x + 4.0, y: 47.0),
                CGPoint(x: x + 6.0, y: 47.0),
                CGPoint(x: x + 8.2, y: 46.8),
                CGPoint(x: x + 10.0, y: 46.5),
                CGPoint(x: x + 12.7, y: 46.5),
                CGPoint(x: x + 15.9, y: 46.2),
                CGPoint(x: x + 20.0, y: 45.5),
                CGPoint(x: x + 23.5, y: 44.8),
                CGPoint(x: x + 25.5, y: 43.5),
                CGPoint(x: x + 24.0, y: 48.0),
                CGPoint(x: x + 20.0, y: 53.5),
                CGPoint(x: x + 18.2, y: 56.9),
                CGPoint(x: x + 15.5, y: 61.5),
                CGPoint(x: x + 10.0, y: 70.0)
            ])
        ]
    }

    private func oneTakeDotHookTailEighthRest(x: CGFloat) -> [PKStroke] {
        [
            stroke([
                CGPoint(x: x + 2.0, y: 41.0),
                CGPoint(x: x + 3.1, y: 42.2),
                CGPoint(x: x + 3.5, y: 45.0),
                CGPoint(x: x + 1.3, y: 44.6),
                CGPoint(x: x + 2.0, y: 41.0),
                CGPoint(x: x + 3.4, y: 42.4),
                CGPoint(x: x + 3.5, y: 44.0),
                CGPoint(x: x + 3.5, y: 45.5),
                CGPoint(x: x + 1.4, y: 46.2),
                CGPoint(x: x + 1.0, y: 44.0),
                CGPoint(x: x + 4.0, y: 44.0),
                CGPoint(x: x + 6.5, y: 45.0),
                CGPoint(x: x + 3.5, y: 45.5),
                CGPoint(x: x + 1.0, y: 45.5),
                CGPoint(x: x + 2.3, y: 43.1),
                CGPoint(x: x + 3.9, y: 41.3),
                CGPoint(x: x + 7.7, y: 40.9),
                CGPoint(x: x + 7.6, y: 42.8),
                CGPoint(x: x + 6.5, y: 45.5),
                CGPoint(x: x + 5.0, y: 48.0),
                CGPoint(x: x + 3.5, y: 49.5),
                CGPoint(x: x + 2.0, y: 50.0),
                CGPoint(x: x + 1.3, y: 47.2),
                CGPoint(x: x + 1.0, y: 44.0),
                CGPoint(x: x + 1.4, y: 40.3),
                CGPoint(x: x + 3.5, y: 40.0),
                CGPoint(x: x + 5.1, y: 43.5),
                CGPoint(x: x + 6.5, y: 45.5),
                CGPoint(x: x + 5.0, y: 47.2),
                CGPoint(x: x + 2.1, y: 48.0),
                CGPoint(x: x + 1.0, y: 47.0),
                CGPoint(x: x + 1.0, y: 45.3),
                CGPoint(x: x + 1.3, y: 43.8),
                CGPoint(x: x + 3.5, y: 42.5),
                CGPoint(x: x + 3.5, y: 45.3),
                CGPoint(x: x + 2.5, y: 46.5),
                CGPoint(x: x + 6.5, y: 45.5),
                CGPoint(x: x + 8.4, y: 44.7),
                CGPoint(x: x + 10.7, y: 43.9),
                CGPoint(x: x + 12.5, y: 43.5),
                CGPoint(x: x + 12.7, y: 45.5),
                CGPoint(x: x + 14.0, y: 50.0),
                CGPoint(x: x + 12.5, y: 56.5),
                CGPoint(x: x + 9.5, y: 63.0),
                CGPoint(x: x + 8.5, y: 65.2),
                CGPoint(x: x + 6.5, y: 67.5)
            ])
        ]
    }

    private func standardEighthRest(x: CGFloat) -> [PKStroke] {
        [
            filledNotehead(center: CGPoint(x: x + 4, y: 28), radius: 2.8),
            stroke([
                CGPoint(x: x + 7, y: 30),
                CGPoint(x: x + 14, y: 38)
            ]),
            stroke([
                CGPoint(x: x + 13, y: 38),
                CGPoint(x: x + 8, y: 64)
            ])
        ]
    }

    private func sevenLikeEighthRest(x: CGFloat) -> [PKStroke] {
        [
            stroke([
                CGPoint(x: x + 4, y: 28),
                CGPoint(x: x + 15, y: 28),
                CGPoint(x: x + 12, y: 35),
                CGPoint(x: x + 9, y: 46),
                CGPoint(x: x + 6, y: 63)
            ])
        ]
    }

    private func wideSevenLikeEighthRest(x: CGFloat) -> [PKStroke] {
        [
            stroke([
                CGPoint(x: x + 3, y: 32),
                CGPoint(x: x + 29, y: 30),
                CGPoint(x: x + 22, y: 37),
                CGPoint(x: x + 14, y: 49),
                CGPoint(x: x + 8, y: 64)
            ])
        ]
    }

    private func wobblySevenLikeEighthRest(x: CGFloat) -> [PKStroke] {
        [
            stroke([
                CGPoint(x: x + 4, y: 29),
                CGPoint(x: x + 17, y: 28),
                CGPoint(x: x + 27, y: 31),
                CGPoint(x: x + 22, y: 36),
                CGPoint(x: x + 16, y: 42),
                CGPoint(x: x + 18, y: 47),
                CGPoint(x: x + 12, y: 55),
                CGPoint(x: x + 9, y: 66)
            ])
        ]
    }

    private func liveWobblySevenLikeEighthRest() -> [PKStroke] {
        [
            stroke([
                CGPoint(x: 11.0, y: 38.5),
                CGPoint(x: 13.3, y: 38.5),
                CGPoint(x: 13.7, y: 40.0),
                CGPoint(x: 12.5, y: 41.0),
                CGPoint(x: 14.8, y: 40.7),
                CGPoint(x: 12.5, y: 41.5),
                CGPoint(x: 11.0, y: 41.5),
                CGPoint(x: 9.1, y: 41.3),
                CGPoint(x: 9.2, y: 39.3),
                CGPoint(x: 11.7, y: 38.6),
                CGPoint(x: 13.2, y: 38.5),
                CGPoint(x: 15.2, y: 38.5),
                CGPoint(x: 13.5, y: 38.5),
                CGPoint(x: 14.9, y: 40.0),
                CGPoint(x: 12.0, y: 41.0),
                CGPoint(x: 10.5, y: 40.0),
                CGPoint(x: 12.5, y: 40.2),
                CGPoint(x: 14.0, y: 41.0),
                CGPoint(x: 17.2, y: 41.0),
                CGPoint(x: 18.7, y: 40.8),
                CGPoint(x: 20.5, y: 40.5),
                CGPoint(x: 22.3, y: 40.0),
                CGPoint(x: 23.9, y: 39.5),
                CGPoint(x: 27.3, y: 38.5),
                CGPoint(x: 28.5, y: 37.5),
                CGPoint(x: 28.8, y: 39.3),
                CGPoint(x: 29.6, y: 41.6),
                CGPoint(x: 30.5, y: 44.0),
                CGPoint(x: 31.0, y: 45.8),
                CGPoint(x: 31.8, y: 48.4),
                CGPoint(x: 32.0, y: 50.0),
                CGPoint(x: 32.0, y: 52.5),
                CGPoint(x: 32.0, y: 54.1),
                CGPoint(x: 32.0, y: 56.0),
                CGPoint(x: 31.6, y: 57.6),
                CGPoint(x: 31.5, y: 60.5),
                CGPoint(x: 31.0, y: 62.5),
                CGPoint(x: 31.0, y: 64.5)
            ])
        ]
    }

    private func currentOneStrokeSevenLikeEighthRest() -> [PKStroke] {
        [
            stroke([
                CGPoint(x: 22.5, y: 50.0),
                CGPoint(x: 19.0, y: 50.0),
                CGPoint(x: 19.0, y: 47.7),
                CGPoint(x: 19.5, y: 46.1),
                CGPoint(x: 21.0, y: 45.4),
                CGPoint(x: 23.6, y: 44.9),
                CGPoint(x: 23.6, y: 46.7),
                CGPoint(x: 22.6, y: 45.5),
                CGPoint(x: 24.0, y: 43.5),
                CGPoint(x: 24.0, y: 46.0),
                CGPoint(x: 22.8, y: 47.3),
                CGPoint(x: 24.0, y: 45.0),
                CGPoint(x: 24.0, y: 47.0),
                CGPoint(x: 26.3, y: 45.1),
                CGPoint(x: 29.3, y: 43.9),
                CGPoint(x: 32.5, y: 43.0),
                CGPoint(x: 35.1, y: 41.4),
                CGPoint(x: 37.5, y: 40.5),
                CGPoint(x: 41.6, y: 39.8),
                CGPoint(x: 40.5, y: 43.5),
                CGPoint(x: 38.8, y: 48.2),
                CGPoint(x: 37.0, y: 52.5),
                CGPoint(x: 34.0, y: 61.0),
                CGPoint(x: 32.9, y: 64.6),
                CGPoint(x: 32.5, y: 67.5)
            ])
        ]
    }

    private func currentScreenEighthRestEighthDottedHalf() -> [PKStroke] {
        [
            stroke([
                CGPoint(x: 22.5, y: 50.0),
                CGPoint(x: 19.0, y: 50.0),
                CGPoint(x: 19.0, y: 47.7),
                CGPoint(x: 19.5, y: 46.1),
                CGPoint(x: 21.0, y: 45.4),
                CGPoint(x: 23.6, y: 44.9),
                CGPoint(x: 23.6, y: 46.7),
                CGPoint(x: 22.6, y: 45.5),
                CGPoint(x: 24.0, y: 43.5),
                CGPoint(x: 24.0, y: 46.0),
                CGPoint(x: 22.8, y: 47.3),
                CGPoint(x: 24.0, y: 45.0),
                CGPoint(x: 24.0, y: 47.0),
                CGPoint(x: 26.3, y: 45.1),
                CGPoint(x: 29.3, y: 43.9),
                CGPoint(x: 32.5, y: 43.0),
                CGPoint(x: 35.1, y: 41.4),
                CGPoint(x: 37.5, y: 40.5),
                CGPoint(x: 41.6, y: 39.8),
                CGPoint(x: 40.5, y: 43.5),
                CGPoint(x: 38.8, y: 48.2),
                CGPoint(x: 37.0, y: 52.5),
                CGPoint(x: 34.0, y: 61.0),
                CGPoint(x: 32.9, y: 64.6),
                CGPoint(x: 32.5, y: 67.5)
            ]),
            stroke([
                CGPoint(x: 70.0, y: 57.5),
                CGPoint(x: 72.5, y: 57.3),
                CGPoint(x: 75.0, y: 56.5),
                CGPoint(x: 75.0, y: 58.3),
                CGPoint(x: 74.5, y: 60.2),
                CGPoint(x: 73.0, y: 62.5),
                CGPoint(x: 70.5, y: 63.8),
                CGPoint(x: 68.5, y: 65.0),
                CGPoint(x: 68.5, y: 63.5),
                CGPoint(x: 68.5, y: 61.2),
                CGPoint(x: 68.5, y: 59.0),
                CGPoint(x: 70.4, y: 57.9),
                CGPoint(x: 73.0, y: 57.5),
                CGPoint(x: 74.5, y: 58.6),
                CGPoint(x: 74.9, y: 61.7),
                CGPoint(x: 75.0, y: 63.5),
                CGPoint(x: 72.7, y: 63.8),
                CGPoint(x: 70.0, y: 64.0),
                CGPoint(x: 70.0, y: 61.8),
                CGPoint(x: 70.4, y: 58.7),
                CGPoint(x: 73.0, y: 58.5),
                CGPoint(x: 74.8, y: 59.8),
                CGPoint(x: 76.5, y: 61.0),
                CGPoint(x: 76.1, y: 63.2),
                CGPoint(x: 74.7, y: 64.6),
                CGPoint(x: 73.0, y: 65.5),
                CGPoint(x: 70.5, y: 65.3),
                CGPoint(x: 68.8, y: 64.6),
                CGPoint(x: 68.5, y: 61.5),
                CGPoint(x: 69.0, y: 60.0),
                CGPoint(x: 70.2, y: 58.7),
                CGPoint(x: 71.5, y: 58.0),
                CGPoint(x: 73.0, y: 58.5),
                CGPoint(x: 74.6, y: 59.3),
                CGPoint(x: 75.4, y: 60.9),
                CGPoint(x: 76.5, y: 62.5),
                CGPoint(x: 74.5, y: 64.0),
                CGPoint(x: 71.5, y: 65.3),
                CGPoint(x: 68.5, y: 66.5)
            ]),
            stroke([
                CGPoint(x: 76.5, y: 34.0),
                CGPoint(x: 76.5, y: 37.0),
                CGPoint(x: 76.5, y: 43.0),
                CGPoint(x: 77.6, y: 47.4),
                CGPoint(x: 78.0, y: 52.5),
                CGPoint(x: 78.0, y: 56.0),
                CGPoint(x: 78.0, y: 60.0)
            ]),
            stroke([
                CGPoint(x: 81.5, y: 34.0),
                CGPoint(x: 79.5, y: 32.0),
                CGPoint(x: 79.5, y: 30.5),
                CGPoint(x: 82.5, y: 31.6),
                CGPoint(x: 84.3, y: 33.0),
                CGPoint(x: 86.0, y: 34.5),
                CGPoint(x: 90.5, y: 37.0)
            ]),
            stroke([
                CGPoint(x: 124.0, y: 49.5),
                CGPoint(x: 124.0, y: 52.2),
                CGPoint(x: 124.0, y: 55.5),
                CGPoint(x: 124.0, y: 60.0),
                CGPoint(x: 126.8, y: 63.1),
                CGPoint(x: 128.5, y: 64.0),
                CGPoint(x: 131.6, y: 64.6),
                CGPoint(x: 133.9, y: 63.8),
                CGPoint(x: 137.0, y: 62.5),
                CGPoint(x: 137.5, y: 59.2),
                CGPoint(x: 138.5, y: 56.0),
                CGPoint(x: 138.5, y: 50.0),
                CGPoint(x: 137.0, y: 47.2),
                CGPoint(x: 135.5, y: 44.5),
                CGPoint(x: 131.8, y: 44.0),
                CGPoint(x: 127.0, y: 46.0)
            ]),
            stroke([
                CGPoint(x: 137.0, y: 25.5),
                CGPoint(x: 137.0, y: 27.0),
                CGPoint(x: 137.0, y: 29.5),
                CGPoint(x: 137.0, y: 34.5),
                CGPoint(x: 137.0, y: 40.5),
                CGPoint(x: 138.5, y: 43.2),
                CGPoint(x: 140.0, y: 47.0)
            ]),
            stroke([
                CGPoint(x: 161.5, y: 58.5),
                CGPoint(x: 160.0, y: 58.5),
                CGPoint(x: 158.0, y: 57.5)
            ])
        ]
    }

    private func denseZigZagQuarterRest(x: CGFloat) -> [PKStroke] {
        [
            stroke([
                CGPoint(x: x + 9, y: 20),
                CGPoint(x: x + 2, y: 31),
                CGPoint(x: x + 12, y: 38),
                CGPoint(x: x + 3, y: 48),
                CGPoint(x: x + 11, y: 55),
                CGPoint(x: x + 5, y: 68)
            ])
        ]
    }

    private func wideZigZagQuarterRest(x: CGFloat) -> [PKStroke] {
        [
            stroke([
                CGPoint(x: x + 13, y: 22),
                CGPoint(x: x + 1, y: 34),
                CGPoint(x: x + 17, y: 46),
                CGPoint(x: x + 6, y: 58),
                CGPoint(x: x + 14, y: 69)
            ])
        ]
    }

    private func sCurveQuarterRest(x: CGFloat) -> [PKStroke] {
        [
            stroke([
                CGPoint(x: x + 11, y: 20),
                CGPoint(x: x + 4, y: 28),
                CGPoint(x: x + 12, y: 36),
                CGPoint(x: x + 7, y: 46),
                CGPoint(x: x + 15, y: 56),
                CGPoint(x: x + 8, y: 69)
            ])
        ]
    }

    private func shallowWiggleQuarterRest(x: CGFloat) -> [PKStroke] {
        [
            stroke([
                CGPoint(x: x + 9, y: 21),
                CGPoint(x: x + 4, y: 34),
                CGPoint(x: x + 10, y: 43),
                CGPoint(x: x + 6, y: 54),
                CGPoint(x: x + 11, y: 69)
            ])
        ]
    }

    private func verticalSquiggleQuarterRest(x: CGFloat) -> [PKStroke] {
        [
            stroke([
                CGPoint(x: x + 8, y: 20),
                CGPoint(x: x + 6, y: 31),
                CGPoint(x: x + 10, y: 41),
                CGPoint(x: x + 7, y: 52),
                CGPoint(x: x + 10, y: 68)
            ])
        ]
    }

    private func narrowCurlQuarterRest(x: CGFloat) -> [PKStroke] {
        [
            stroke([
                CGPoint(x: x + 8, y: 20),
                CGPoint(x: x + 5, y: 29),
                CGPoint(x: x + 10, y: 38),
                CGPoint(x: x + 6, y: 47),
                CGPoint(x: x + 11, y: 56),
                CGPoint(x: x + 6, y: 69)
            ])
        ]
    }

    private func leftHookEighthRest(x: CGFloat) -> [PKStroke] {
        [
            stroke([
                CGPoint(x: x + 9, y: 25),
                CGPoint(x: x + 2, y: 25),
                CGPoint(x: x + 5, y: 31)
            ]),
            stroke([
                CGPoint(x: x + 8, y: 27),
                CGPoint(x: x + 5, y: 42),
                CGPoint(x: x + 12, y: 63)
            ])
        ]
    }

    private func singleStrokeHookedEighthRest(x: CGFloat) -> [PKStroke] {
        [
            stroke([
                CGPoint(x: x + 11, y: 24),
                CGPoint(x: x + 3, y: 25),
                CGPoint(x: x + 6, y: 31),
                CGPoint(x: x + 8, y: 44),
                CGPoint(x: x + 14, y: 65)
            ])
        ]
    }

    private func tailFirstEighthRest(x: CGFloat) -> [PKStroke] {
        [
            stroke([
                CGPoint(x: x + 13, y: 65),
                CGPoint(x: x + 8, y: 44),
                CGPoint(x: x + 6, y: 31),
                CGPoint(x: x + 3, y: 25),
                CGPoint(x: x + 11, y: 24)
            ])
        ]
    }

    private func rightwardHookEighthRest(x: CGFloat) -> [PKStroke] {
        [
            stroke([
                CGPoint(x: x + 2, y: 25),
                CGPoint(x: x + 10, y: 25),
                CGPoint(x: x + 7, y: 33)
            ]),
            stroke([
                CGPoint(x: x + 8, y: 28),
                CGPoint(x: x + 5, y: 43),
                CGPoint(x: x + 12, y: 64)
            ])
        ]
    }

    private func compactEighthRest(x: CGFloat) -> [PKStroke] {
        [
            stroke([
                CGPoint(x: x + 2, y: 38),
                CGPoint(x: x + 12, y: 38),
                CGPoint(x: x + 9, y: 44)
            ]),
            stroke([
                CGPoint(x: x + 11, y: 40),
                CGPoint(x: x + 8, y: 54),
                CGPoint(x: x + 13, y: 68)
            ])
        ]
    }

    private func touchedUpQuarterRest(x: CGFloat) -> [PKStroke] {
        [
            stroke([
                CGPoint(x: x + 11, y: 21),
                CGPoint(x: x + 3, y: 33)
            ]),
            stroke([
                CGPoint(x: x + 3, y: 33),
                CGPoint(x: x + 18, y: 44)
            ]),
            stroke([
                CGPoint(x: x + 18, y: 44),
                CGPoint(x: x + 5, y: 58),
                CGPoint(x: x + 13, y: 69)
            ]),
            stroke([
                CGPoint(x: x + 7, y: 37),
                CGPoint(x: x + 14, y: 44),
                CGPoint(x: x + 8, y: 53)
            ])
        ]
    }

    private func fallbackStemOnlyQuarterMarks() -> [PKStroke] {
        [24, 84, 144, 204].map { x in
            stroke([
                CGPoint(x: CGFloat(x), y: 26),
                CGPoint(x: CGFloat(x), y: 62)
            ])
        }
    }

    private func filledNotehead(center: CGPoint, radius: CGFloat = 4.4) -> PKStroke {
        var points: [CGPoint] = []
        for index in 0...12 {
            let angle = CGFloat(index) / 12 * .pi * 2
            points.append(
                CGPoint(
                    x: center.x + cos(angle) * radius,
                    y: center.y + sin(angle) * radius * 0.78
                )
            )
        }
        points.append(center)
        points.append(CGPoint(x: center.x - radius * 0.65, y: center.y))
        points.append(CGPoint(x: center.x + radius * 0.65, y: center.y))
        return stroke(points)
    }

    private func hollowNotehead(center: CGPoint, radius: CGFloat = 5.0) -> PKStroke {
        var points: [CGPoint] = []
        for index in 0...14 {
            let angle = CGFloat(index) / 14 * .pi * 2
            points.append(
                CGPoint(
                    x: center.x + cos(angle) * radius,
                    y: center.y + sin(angle) * radius * 0.72
                )
            )
        }
        return stroke(points)
    }

    private func stroke(_ points: [CGPoint]) -> PKStroke {
        let controlPoints = points.enumerated().map { index, point in
            PKStrokePoint(
                location: point,
                timeOffset: TimeInterval(index) * 0.01,
                size: CGSize(width: 3, height: 3),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        }
        let path = PKStrokePath(controlPoints: controlPoints, creationDate: Date())
        return PKStroke(ink: PKInk(.pen, color: .black), path: path)
    }

}
#endif
