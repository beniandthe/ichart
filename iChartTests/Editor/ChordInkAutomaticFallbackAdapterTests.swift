#if canImport(UIKit) && canImport(Vision)
import Foundation
import XCTest
@testable import iChart

final class ChordInkAutomaticFallbackAdapterTests: XCTestCase {
    func testNativeScaleUsesExistingTransformAndReturnsOnlyActualReviewCandidates() throws {
        let source = preparedInk()
        let originalSource = source
        let match = try XCTUnwrap(ChordRecognitionCompendium.match("D/F#"))
        let primary = ChordInkRecognitionResult(rawCandidates: ["D/F#"], glyphCandidates: [],
            match: match, confidence: 4.25,
            candidateScores: [.init(text: "D/F#", displayText: match.displayText, confidence: 4.25)])
        let reader = AdapterRecordingRecognizer(output: primary)
        let provider = ChordInkNativeScaleFallbackRecognizer(targetHeight: 32, recognizer: reader)

        let result = try XCTUnwrap(provider.recognize(strokes: source,
            options: .includingSymbolLedgerDiagnostics, isCurrent: { true }))

        XCTAssertEqual(reader.calls.count, 1)
        let read = try XCTUnwrap(reader.calls.first)
        XCTAssertEqual(read.strokes, ChordInkRecognitionScaleNormalizer.strokes(from: source, targetHeight: 32))
        XCTAssertEqual(InkBounds.enclosing(read.strokes.map(\.bounds)).height, 32, accuracy: 0.000_001)
        XCTAssertEqual(read.strokes.map(\.creationTimeOffset), source.map(\.creationTimeOffset))
        XCTAssertEqual(read.strokes.map { $0.points.map(\.timeOffset) }, source.map { $0.points.map(\.timeOffset) })
        XCTAssertEqual(read.options, .includingSymbolLedgerDiagnostics)
        XCTAssertEqual(source, originalSource, "Scaling is an internal reading variant, never new source ownership")
        XCTAssertEqual(reader.output, primary, "The existing primary recognizer result must remain unchanged")
        XCTAssertNil(result.match)
        XCTAssertEqual(result.confidence, 0)
        XCTAssertTrue(result.candidateScores.isEmpty)
        XCTAssertEqual(result.rawCandidates, ["D/F#"])
        XCTAssertEqual(result.reviewCandidateScores,
            [.init(text: "D/F#", displayText: match.displayText, confidence: 4.25)])
        XCTAssertEqual(result.metrics.strokeCount, source.count)
        XCTAssertEqual(ChordInkRecognitionPolicy.decision(for: result).action, .confirm)
    }

    func testNativeProviderRefusesObsoleteOversizedAndUnparseableInputs() {
        let reader = AdapterRecordingRecognizer(output: .init(rawCandidates: ["not chord"],
            glyphCandidates: [], match: nil, confidence: 0))
        let provider = ChordInkNativeScaleFallbackRecognizer(targetHeight: 39.5, recognizer: reader)
        let source = preparedInk()
        XCTAssertNil(provider.recognize(strokes: source, options: .live, isCurrent: { false }))
        XCTAssertTrue(reader.calls.isEmpty)
        XCTAssertNil(provider.recognize(strokes: Array(repeating: source[0], count: 17),
            options: .live, isCurrent: { true }))
        let tooManyPoints = InkStroke(points: Array(repeating: source[0].points[0], count: 16_385))
        XCTAssertNil(provider.recognize(strokes: [tooManyPoints], options: .live, isCurrent: { true }))
        XCTAssertTrue(reader.calls.isEmpty, "Bounded admission happens before the native reader")
        XCTAssertNil(provider.recognize(strokes: source, options: .live, isCurrent: { true }))
        XCTAssertEqual(reader.calls.count, 1)
        XCTAssertFalse(ChordInkAutomaticFallbackCandidatePolicy.hasCandidate(reader.output),
            "A no-read may not acquire an invented default root")
    }

    func testNativeReadWhichBecomesObsoleteIsDroppedAfterComputation() {
        let reader = AdapterRecordingRecognizer(output: .init(rawCandidates: ["G"],
            glyphCandidates: [], match: nil, confidence: 0))
        let current = AdapterCurrentFlag()
        reader.onRead = { current.invalidate() }
        let provider = ChordInkNativeScaleFallbackRecognizer(targetHeight: 48, recognizer: reader)
        XCTAssertNil(provider.recognize(strokes: preparedInk(), options: .live,
            isCurrent: { current.isCurrent }))
        XCTAssertEqual(reader.calls.count, 1)
    }

    func testExistingRawCandidateBeyondProviderReportCapAndPersonalRecoveryPreventFallback() {
        let existing = ChordInkRecognitionResult(rawCandidates: Array(repeating: "not chord", count: 80) + ["Bb"],
            glyphCandidates: [], match: nil, confidence: 0)
        XCTAssertTrue(ChordInkAutomaticFallbackCandidatePolicy.hasCandidate(existing),
            "Every existing bounded primary output must be checked before invoking another reader")
        XCTAssertEqual(ChordInkAutomaticFallbackCandidatePolicy.candidateTexts(for: existing),
            [ChordRecognitionCompendium.match("Bb")!.displayText])

        var personal = ChordInkRecognitionResult(rawCandidates: [], glyphCandidates: [], match: nil, confidence: 0)
        personal.personalSuggestion = .init(text: "A", source: .wholeChord, distance: 0.02,
            supportingExampleCount: 2)
        XCTAssertEqual(ChordInkRenderResolutionPolicy.candidateTexts(for: personal), ["A"])
        XCTAssertTrue(ChordInkAutomaticFallbackCandidatePolicy.hasCandidate(personal),
            "A legitimate existing profile choice is already a candidate")
        XCTAssertNil(personal.match)
        XCTAssertEqual(personal.confidence, 0)
    }

    func testVisionMappingUsesActualProductionGrammarReadAndUntouchedRawConfidenceWithoutTrust() throws {
        let invalid = RecognitionStudyVisionChordRecognizer.Candidate(rawText: "hello", rawConfidence: 0.99,
            normalizedChord: nil, passIndex: 0, rank: 0)
        let candidate = RecognitionStudyVisionChordRecognizer.Candidate(rawText: "Cmaj7",
            rawComponentConfidences: [0.36, 0.31], normalizedChord: nil, passIndex: 0, rank: 1)
        let secondPass = RecognitionStudyVisionChordRecognizer.Candidate(rawText: "Cmaj7", rawConfidence: 0.27,
            normalizedChord: nil, passIndex: 1, rank: 0)
        let output = RecognitionStudyVisionChordRecognizer.Result(decision: .review(.topCandidateOutsideGrammar),
            candidates: [invalid, candidate, secondPass])
        let original = output
        let mapped = try XCTUnwrap(ChordInkVisionAutomaticFallbackRecognizer.recognitionResult(
            from: output, sourceStrokeCount: 3, elapsedMilliseconds: 12.5))

        XCTAssertEqual(output, original)
        XCTAssertEqual(mapped.rawCandidates, ["hello", "Cmaj7", "Cmaj7"])
        XCTAssertNil(mapped.match)
        XCTAssertEqual(mapped.confidence, 0)
        XCTAssertTrue(mapped.candidateScores.isEmpty)
        let score = try XCTUnwrap(mapped.reviewCandidateScores.first)
        XCTAssertEqual(mapped.reviewCandidateScores.count, 1)
        XCTAssertEqual(score.text, "Cmaj7", "The score must retain the actual Vision string")
        XCTAssertEqual(score.displayText, ChordRecognitionCompendium.match("Cmaj7")?.displayText)
        XCTAssertEqual(score.confidence, Double(candidate.rawConfidenceFloor), accuracy: 0.000_001)
        XCTAssertEqual(mapped.metrics.totalMilliseconds, 12.5)
        XCTAssertEqual(mapped.metrics.strokeCount, 3)
        XCTAssertEqual(ChordInkRecognitionPolicy.decision(for: mapped).action, .confirm)
        XCTAssertNil(RecognitionStudyCanonicalChordNormalizer().normalizedChord(from: "Cmaj7"),
            "Production alias support must not change the study's strict default grammar")
        XCTAssertEqual(ChordInkAutomaticVisionCandidateNormalizer().normalizedChord(from: "Cmaj7"), score.displayText)

        let accepted = RecognitionStudyVisionChordRecognizer.Result(decision: .accepted(chord: "G", confidenceFloor: 0.99),
            candidates: [.init(rawText: "G", rawConfidence: 0.99, normalizedChord: "G", passIndex: 0, rank: 0)])
        let acceptedMapping = try XCTUnwrap(ChordInkVisionAutomaticFallbackRecognizer.recognitionResult(
            from: accepted, sourceStrokeCount: 1))
        XCTAssertNil(acceptedMapping.match, "The independent study consensus is never production trust")
        XCTAssertEqual(acceptedMapping.confidence, 0)
    }

    func testVisionUnsupportedOutputAndObsoleteSourceProduceNoFabricatedCandidate() throws {
        let unsupported = RecognitionStudyVisionChordRecognizer.Result(decision: .noRead(.noGrammarCandidate),
            candidates: [.init(rawText: "hello", rawConfidence: 0.99, normalizedChord: nil, passIndex: 0, rank: 0)])
        XCTAssertNil(ChordInkVisionAutomaticFallbackRecognizer.recognitionResult(from: unsupported, sourceStrokeCount: 3))
        let reader = RecognitionStudyVisionChordRecognizer()
        XCTAssertNil(try reader.recognize(strokes: preparedInk(), isCurrent: { false }))
        let provider = ChordInkVisionAutomaticFallbackRecognizer()
        XCTAssertNil(provider.recognize(strokes: preparedInk(), options: .live, isCurrent: { false }))
        XCTAssertNil(provider.recognize(strokes: Array(repeating: preparedInk()[0], count: 129),
            options: .live, isCurrent: { true }))
    }

    func testVisionTypedAttemptSeparatesTechnicalFailureFromSuccessfulExhaustion() {
        let source = preparedInk()
        var attemptedSource: [InkStroke]?
        let failed = ChordInkVisionAutomaticFallbackRecognizer(recognizeSource: { strokes, _ in
            attemptedSource = strokes
            throw AdapterVisionError.unavailable
        })
        guard case .technicalFailure = failed.recognizeAttempt(strokes: source,
            options: .live, isCurrent: { true }) else {
            return XCTFail("A current-source engine error must not become successful empty recognition")
        }
        XCTAssertEqual(attemptedSource, source)
        XCTAssertNil(failed.recognize(strokes: source, options: .live, isCurrent: { true }),
            "Existing optional callers retain their API without gaining an invented candidate")

        let exhausted = ChordInkVisionAutomaticFallbackRecognizer(recognizeSource: { strokes, _ in
            XCTAssertEqual(strokes, source)
            return .init(decision: .noRead(.noVisionText), candidates: [])
        })
        guard case .completed(let result) = exhausted.recognizeAttempt(strokes: source,
            options: .live, isCurrent: { true }) else {
            return XCTFail("Successful zero-candidate recognition is cacheable exhaustion")
        }
        XCTAssertNil(result)
    }

    func testVisionTypedAttemptKeepsObsoleteSourceCancellationSeparateFromTechnicalFailure() {
        let source = preparedInk()
        let current = AdapterCurrentFlag()
        let obsoleteDuringRead = ChordInkVisionAutomaticFallbackRecognizer(recognizeSource: { strokes, _ in
            XCTAssertEqual(strokes, source)
            current.invalidate()
            throw AdapterVisionError.unavailable
        })
        guard case .cancelled = obsoleteDuringRead.recognizeAttempt(strokes: source,
            options: .live, isCurrent: { current.isCurrent }) else {
            return XCTFail("A cancelled source may never enter technical retry")
        }
        var invoked = false
        let obsoleteBeforeRead = ChordInkVisionAutomaticFallbackRecognizer(recognizeSource: { _, _ in
            invoked = true
            throw AdapterVisionError.unavailable
        })
        guard case .cancelled = obsoleteBeforeRead.recognizeAttempt(strokes: source,
            options: .live, isCurrent: { false }) else {
            return XCTFail("Obsolete source must be rejected before calling Vision")
        }
        XCTAssertFalse(invoked)
    }

    func testLiveProviderChainIsExactlyThreeExistingScalesThenIndependentVision() {
        let providers = ChordInkAutomaticFallbackProviders.live
        XCTAssertEqual(providers.count, 4)
        XCTAssertEqual(providers.compactMap { ($0 as? ChordInkNativeScaleFallbackRecognizer)?.targetHeight }, [32, 39.5, 48])
        XCTAssertTrue(providers.last.map { $0 is ChordInkVisionAutomaticFallbackRecognizer } ?? false)
        XCTAssertEqual(Set(providers.map(\.identifier)).count, 4)
        XCTAssertTrue(providers.allSatisfy { !$0.version.isEmpty })
    }

    /// This smoke executes Apple's reader on bounded prepared ink. It checks
    /// the engine contract and grammar provenance, without asserting that this
    /// constructed shape is an accuracy benchmark or must be read as F.
    func testActualVisionOldAndCancellableEntryPointsKeepBoundedStrictStudyContract() throws {
        let source = preparedInk()
        let original = source
        let reader = RecognitionStudyVisionChordRecognizer()
        XCTAssertEqual(reader.configuration, .default)
        XCTAssertEqual(reader.configuration.strokeWidths, [7, 10])
        let raster = try RecognitionStudyVisionChordRecognizer.rasterize(strokes: source, strokeWidth: 7)
        XCTAssertEqual(raster.width, 512)
        XCTAssertEqual(raster.height, 256)
        XCTAssertEqual(raster.width, reader.configuration.canvasWidth)
        XCTAssertEqual(raster.height, reader.configuration.canvasHeight)
        XCTAssertEqual(raster.grayscalePixels.count, raster.bytesPerRow * raster.height)

        let oldEntry = try reader.recognize(strokes: source)
        let cancellableEntry = try XCTUnwrap(reader.recognize(strokes: source, isCurrent: { true }))
        for output in [oldEntry, cancellableEntry] {
            XCTAssertLessThanOrEqual(output.candidates.count,
                reader.configuration.strokeWidths.count * reader.configuration.maximumCombinedCandidates)
            for candidate in output.candidates {
                XCTAssertTrue(reader.configuration.strokeWidths.indices.contains(candidate.passIndex))
                XCTAssertFalse(candidate.rawText.isEmpty)
                XCTAssertTrue((0...1).contains(candidate.rawConfidenceFloor))
                XCTAssertEqual(candidate.normalizedChord,
                    RecognitionStudyCanonicalChordNormalizer().normalizedChord(from: candidate.rawText))
            }
        }
        XCTAssertEqual(source, original, "OCR raster variants must leave the prepared trajectories intact")
        XCTAssertEqual(try reader.recognize(strokes: []).decision, .noRead(.noInk),
            "The original study entry point retains its no-ink behavior")
    }

    private func preparedInk() -> [InkStroke] {
        [
            InkStroke(points: [.init(x: 30, y: 10, timeOffset: 0), .init(x: 30, y: 90, timeOffset: 0.2)],
                creationTimeOffset: 0),
            InkStroke(points: [.init(x: 30, y: 10, timeOffset: 0), .init(x: 75, y: 10, timeOffset: 0.1)],
                creationTimeOffset: 0.3),
            InkStroke(points: [.init(x: 30, y: 45, timeOffset: 0), .init(x: 60, y: 45, timeOffset: 0.1)],
                creationTimeOffset: 0.5)
        ]
    }
}

private enum AdapterVisionError: Error {
    case unavailable
}

private final class AdapterRecordingRecognizer: ChordInkRecognizing {
    struct Call { let strokes: [InkStroke]; let options: ChordInkRecognitionOptions }
    let output: ChordInkRecognitionResult
    var calls: [Call] = []
    var onRead: (() -> Void)?

    init(output: ChordInkRecognitionResult) { self.output = output }

    func recognize(strokes: [InkStroke], options: ChordInkRecognitionOptions) -> ChordInkRecognitionResult {
        calls.append(.init(strokes: strokes, options: options))
        onRead?()
        return output
    }
}

private final class AdapterCurrentFlag {
    private let lock = NSLock()
    private var current = true

    var isCurrent: Bool {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func invalidate() {
        lock.lock()
        current = false
        lock.unlock()
    }
}
#endif
