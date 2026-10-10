import XCTest
#if canImport(PencilKit) && canImport(UIKit)
import PencilKit
import UIKit
#endif
@testable import iChart

final class ChordInkUserCorrectionMemoryTests: XCTestCase {
    func testCompleteFailuresAutoRewriteOnlyTwicePerSlot() {
        let result = ChordInkRecognitionResult(
            rawCandidates: ["scribble"],
            glyphCandidates: [],
            match: nil,
            confidence: 0
        )
        let decision = ChordInkRecognitionDecision(
            action: .confirm,
            acceptedText: nil,
            reason: "No reliable read yet.",
            isCloseRace: false,
            competingCandidateText: nil,
            confidenceGap: nil
        )

        XCTAssertTrue(
            ChordInkUserCorrectionMemoryPolicy.isCompleteFailure(
                result: result,
                decision: decision,
                candidateTexts: []
            )
        )

        var tracker = ChordInkAutomaticRewriteFailureTracker()
        let measureID = UUID()

        XCTAssertEqual(tracker.recordFailure(measureID: measureID, targetFraction: 0.51), 1)
        XCTAssertEqual(tracker.recordFailure(measureID: measureID, targetFraction: 0.51), 2)
        XCTAssertEqual(tracker.recordFailure(measureID: measureID, targetFraction: 0.51), 3)

        tracker.reset()

        XCTAssertEqual(tracker.recordFailure(measureID: measureID, targetFraction: 0.51), 1)
    }

    func testConfirmedSuggestionCreatesRuleForCloseRaceThatIsNotExtremelyClose() {
        var memory = ChordInkUserCorrectionMemory()
        let created = memory.recordConfirmedSuggestion(
            acceptedText: "G/B",
            drawingData: Data("first pass".utf8),
            candidateTexts: ["C", "G/B", "Db7(b9)", "F#"],
            decision: closeRaceDecision(gap: 0.03),
            now: Date(timeIntervalSinceReferenceDate: 10)
        )

        XCTAssertTrue(created)
        XCTAssertEqual(memory.correctionRules.count, 1)
        XCTAssertEqual(memory.correctionRules.first?.candidateSignature, ["C", "G/B", "Db7(b9)"])
        XCTAssertEqual(memory.correctionRules.first?.acceptedText, "G/B")
        XCTAssertEqual(
            memory.preferredCandidate(
                for: ["C", "G/B", "Db7(b9)"],
                drawingData: Data("first pass".utf8),
                decision: closeRaceDecision(gap: 0.03)
            ),
            "G/B"
        )
    }

    func testConfirmedSuggestionDoesNotCreateRuleForExtremelyTightRace() {
        var memory = ChordInkUserCorrectionMemory()
        let created = memory.recordConfirmedSuggestion(
            acceptedText: "Db7(b9)",
            drawingData: Data("very tight".utf8),
            candidateTexts: ["Db7/Gb", "Db7(b9)", "Db7"],
            decision: closeRaceDecision(gap: 0.01)
        )

        XCTAssertFalse(created)
        XCTAssertTrue(memory.correctionRules.isEmpty)
        XCTAssertNil(
            memory.preferredCandidate(
                for: ["Db7/Gb", "Db7(b9)", "Db7"],
                drawingData: Data("very tight".utf8),
                decision: closeRaceDecision(gap: 0.01)
            )
        )
    }

    func testManualCorrectionCreatesExclusionAndRemovesMatchingRule() {
        var memory = ChordInkUserCorrectionMemory()
        XCTAssertTrue(
            memory.recordConfirmedSuggestion(
                acceptedText: "C",
                drawingData: Data("rule".utf8),
                candidateTexts: ["C", "G/B", "Db7(b9)"],
                decision: closeRaceDecision(gap: 0.03)
            )
        )

        let excluded = memory.recordManualCorrection(
            acceptedText: "F#",
            drawingData: Data("manual".utf8),
            candidateTexts: ["C", "G/B", "Db7(b9)"],
            now: Date(timeIntervalSinceReferenceDate: 20)
        )

        XCTAssertTrue(excluded)
        XCTAssertTrue(memory.correctionRules.isEmpty)
        XCTAssertEqual(memory.suggestionExclusions.count, 1)
        XCTAssertEqual(memory.suggestionExclusions.first?.rejectedCandidateTexts, ["C", "G/B", "Db7(b9)"])
        XCTAssertEqual(memory.suggestionExclusions.first?.acceptedText, "F#")
        XCTAssertNil(
            memory.preferredCandidate(
                for: ["C", "G/B", "Db7(b9)"],
                drawingData: Data("manual".utf8),
                decision: closeRaceDecision(gap: 0.03)
            )
        )
    }

    func testRenderedChordCorrectionLearnsWrongReadAndSupportedReplacement() {
        var memory = ChordInkUserCorrectionMemory()
        let drawingData = Data("handwritten C intended as G".utf8)
        let candidateTexts = ["C", "G", "B"]

        XCTAssertTrue(
            memory.recordRenderedChordCorrection(
                previousText: "C",
                displayedPreviousText: "C",
                acceptedText: "G",
                drawingData: drawingData,
                candidateTexts: candidateTexts,
                now: Date(timeIntervalSinceReferenceDate: 24)
            )
        )

        XCTAssertTrue(
            memory.shouldBlockTrustedCandidate(
                acceptedText: "C",
                drawingData: drawingData,
                candidateTexts: candidateTexts
            )
        )
        XCTAssertEqual(memory.correctionRules.first?.acceptedText, "G")
        XCTAssertEqual(memory.correctionRules.first?.candidateSignature, candidateTexts)
        XCTAssertEqual(
            memory.preferredCandidate(
                for: candidateTexts,
                drawingData: drawingData,
                decision: closeRaceDecision(gap: 0.03)
            ),
            "G"
        )
    }

    func testConfirmedSuggestionDoesNotAutoApplyToDifferentInkWithSameCandidateSignature() {
        var memory = ChordInkUserCorrectionMemory()
        let candidateTexts = ["C", "G/B", "Db7(b9)"]

        XCTAssertTrue(
            memory.recordConfirmedSuggestion(
                acceptedText: "G/B",
                drawingData: Data("corrected ink".utf8),
                candidateTexts: candidateTexts,
                decision: closeRaceDecision(gap: 0.03)
            )
        )

        XCTAssertNil(
            memory.preferredCandidate(
                for: candidateTexts,
                drawingData: Data("different fresh ink".utf8),
                decision: closeRaceDecision(gap: 0.03)
            )
        )
    }

    func testLegacyUnversionedArchiveDigestStillMatchesIdenticalInk() {
        let drawingData = Data("legacy corrected ink".utf8)
        let candidateTexts = ["C", "G", "B"]
        let memory = ChordInkUserCorrectionMemory(correctionRules: [
            ChordInkUserCorrectionRule(
                id: UUID(),
                candidateSignature: candidateTexts,
                acceptedText: "G",
                competingCandidateTexts: ["C", "B"],
                inkDigests: ["6936d60c1ff254c034e699b356c3751429ae54c515297091b71fa24c14a87126"],
                sourceConfidenceGap: 0.03,
                createdAt: Date(timeIntervalSinceReferenceDate: 1),
                updatedAt: Date(timeIntervalSinceReferenceDate: 1),
                useCount: 1
            )
        ])

        XCTAssertEqual(
            memory.preferredCandidate(
                for: candidateTexts,
                drawingData: drawingData,
                decision: closeRaceDecision(gap: 0.03)
            ),
            "G"
        )
    }

    #if canImport(PencilKit) && canImport(UIKit)
    func testConfirmedSuggestionSurvivesPencilKitMetadataReserialization() {
        var memory = ChordInkUserCorrectionMemory()
        let candidateTexts = ["C", "G", "B"]
        let blackInk = drawingData(
            color: .black,
            points: [
                CGPoint(x: 10, y: 12),
                CGPoint(x: 20, y: 28),
                CGPoint(x: 30, y: 44)
            ]
        )
        let blueInkWithSameRecognitionGeometry = drawingData(
            color: .blue,
            points: [
                CGPoint(x: 10, y: 12),
                CGPoint(x: 20, y: 28),
                CGPoint(x: 30, y: 44)
            ]
        )

        XCTAssertNotEqual(blackInk, blueInkWithSameRecognitionGeometry)
        XCTAssertEqual(
            ChordInkUserCorrectionMemoryPolicy.inkDigest(for: blackInk),
            ChordInkUserCorrectionMemoryPolicy.inkDigest(for: blueInkWithSameRecognitionGeometry)
        )
        XCTAssertTrue(
            memory.recordConfirmedSuggestion(
                acceptedText: "G",
                drawingData: blackInk,
                candidateTexts: candidateTexts,
                decision: closeRaceDecision(gap: 0.03)
            )
        )
        XCTAssertEqual(
            memory.preferredCandidate(
                for: candidateTexts,
                drawingData: blueInkWithSameRecognitionGeometry,
                decision: closeRaceDecision(gap: 0.03)
            ),
            "G"
        )
    }

    func testSemanticInkDigestStillRejectsDifferentGeometryWithSameCandidates() {
        var memory = ChordInkUserCorrectionMemory()
        let candidateTexts = ["C", "G", "B"]
        let correctedInk = drawingData(
            color: .black,
            points: [
                CGPoint(x: 10, y: 12),
                CGPoint(x: 20, y: 28),
                CGPoint(x: 30, y: 44)
            ]
        )
        let differentInk = drawingData(
            color: .black,
            points: [
                CGPoint(x: 10, y: 12),
                CGPoint(x: 24, y: 24),
                CGPoint(x: 34, y: 48)
            ]
        )

        XCTAssertTrue(
            memory.recordConfirmedSuggestion(
                acceptedText: "G",
                drawingData: correctedInk,
                candidateTexts: candidateTexts,
                decision: closeRaceDecision(gap: 0.03)
            )
        )
        XCTAssertNil(
            memory.preferredCandidate(
                for: candidateTexts,
                drawingData: differentInk,
                decision: closeRaceDecision(gap: 0.03)
            )
        )
    }

    func testSemanticInkDigestTracksVisibleBitmapMaskGeometryInsteadOfHiddenPath() {
        let points = [
            CGPoint(x: 0, y: 20),
            CGPoint(x: 10, y: 20),
            CGPoint(x: 20, y: 20),
            CGPoint(x: 30, y: 20),
            CGPoint(x: 40, y: 20),
            CGPoint(x: 50, y: 20)
        ]
        let leftMask = UIBezierPath(rect: CGRect(x: -2, y: 10, width: 18, height: 20))
        let rightMask = UIBezierPath(rect: CGRect(x: 34, y: 10, width: 18, height: 20))
        let blackLeftInk = drawingData(color: .black, points: points, mask: leftMask)
        let blueLeftInk = drawingData(color: .blue, points: points, mask: leftMask)
        let blackRightInk = drawingData(color: .black, points: points, mask: rightMask)

        let blackLeftDigest = ChordInkUserCorrectionMemoryPolicy.inkDigest(
            for: blackLeftInk
        )

        XCTAssertTrue(blackLeftDigest.hasPrefix("semantic-v1:"))
        XCTAssertEqual(
            blackLeftDigest,
            ChordInkUserCorrectionMemoryPolicy.inkDigest(for: blueLeftInk)
        )
        XCTAssertNotEqual(
            blackLeftDigest,
            ChordInkUserCorrectionMemoryPolicy.inkDigest(for: blackRightInk)
        )
    }

    func testSemanticInkDigestIgnoresFullyMaskedEarlierStrokeTiming() throws {
        let hiddenStroke = pencilStroke(
            color: .black,
            points: [
                CGPoint(x: 0, y: 0),
                CGPoint(x: 10, y: 10)
            ],
            creationDate: Date(timeIntervalSinceReferenceDate: 1_000),
            mask: UIBezierPath(rect: CGRect(x: 200, y: 200, width: 20, height: 20))
        )
        let visibleStroke = pencilStroke(
            color: .black,
            points: [
                CGPoint(x: 40, y: 20),
                CGPoint(x: 60, y: 30)
            ],
            creationDate: Date(timeIntervalSinceReferenceDate: 1_005)
        )
        let visibleOnlyInk = PKDrawing(strokes: [visibleStroke]).dataRepresentation()
        let inkWithHiddenEarlierStroke = PKDrawing(
            strokes: [hiddenStroke, visibleStroke]
        ).dataRepresentation()

        XCTAssertTrue(hiddenStroke.maskedPathRanges.isEmpty)
        XCTAssertNotEqual(visibleOnlyInk, inkWithHiddenEarlierStroke)
        XCTAssertEqual(
            ChordInkUserCorrectionMemoryPolicy.inkDigest(for: visibleOnlyInk),
            ChordInkUserCorrectionMemoryPolicy.inkDigest(for: inkWithHiddenEarlierStroke)
        )
    }
    #endif

    func testRenderedChordCorrectionOutsideSuggestionsCreatesExclusion() {
        var memory = ChordInkUserCorrectionMemory()
        let drawingData = Data("handwritten C intended as F sharp".utf8)
        let candidateTexts = ["C", "G", "B"]

        XCTAssertTrue(
            memory.recordRenderedChordCorrection(
                previousText: "C",
                displayedPreviousText: "C",
                acceptedText: "F#",
                drawingData: drawingData,
                candidateTexts: candidateTexts,
                now: Date(timeIntervalSinceReferenceDate: 24)
            )
        )

        XCTAssertTrue(memory.correctionRules.isEmpty)
        XCTAssertEqual(memory.suggestionExclusions.first?.candidateSignature, candidateTexts)
        XCTAssertEqual(memory.suggestionExclusions.first?.acceptedText, "F#")
        XCTAssertNil(
            memory.preferredCandidate(
                for: candidateTexts,
                drawingData: drawingData,
                decision: closeRaceDecision(gap: 0.03)
            )
        )
    }

    func testRenderedChordCorrectionDoesNotLearnAcrossTransposedDisplaySpace() {
        var memory = ChordInkUserCorrectionMemory()

        XCTAssertFalse(
            memory.recordRenderedChordCorrection(
                previousText: "C",
                displayedPreviousText: "D",
                acceptedText: "G",
                drawingData: Data("transposed chart".utf8),
                candidateTexts: ["C", "G", "B"]
            )
        )
        XCTAssertEqual(memory, ChordInkUserCorrectionMemory())
    }

    func testRenderedChordCorrectionDoesNotLearnEquivalentChordSpelling() {
        var memory = ChordInkUserCorrectionMemory()

        XCTAssertFalse(
            memory.recordRenderedChordCorrection(
                previousText: "Cmaj7",
                displayedPreviousText: "C△7",
                acceptedText: "C△7",
                drawingData: Data("same chord".utf8),
                candidateTexts: ["C△7", "C7", "C-7"]
            )
        )
        XCTAssertEqual(memory, ChordInkUserCorrectionMemory())
    }

    func testExplicitlyRejectedInkChordBlocksSameTrustedCandidateByDigestOrCandidateSignature() {
        var memory = ChordInkUserCorrectionMemory()
        let rejectedDrawing = Data("wrong trusted read".utf8)
        let differentDrawing = Data("different drawing".utf8)
        let rejectedSignature = ["Db7(b9)", "Db7", "G/B"]

        XCTAssertFalse(
            memory.shouldBlockTrustedCandidate(
                acceptedText: "Db7(b9)",
                drawingData: rejectedDrawing,
                candidateTexts: rejectedSignature
            )
        )

        XCTAssertTrue(
            memory.recordRejectedTrustedCandidate(
                acceptedText: "Db7(b9)",
                drawingData: rejectedDrawing,
                candidateSignature: rejectedSignature,
                now: Date(timeIntervalSinceReferenceDate: 25)
            )
        )

        XCTAssertTrue(
            memory.shouldBlockTrustedCandidate(
                acceptedText: "Db7(b9)",
                drawingData: rejectedDrawing
            )
        )
        XCTAssertTrue(
            memory.shouldBlockTrustedCandidate(
                acceptedText: "Db7(b9)",
                drawingData: differentDrawing,
                candidateTexts: rejectedSignature
            )
        )
        XCTAssertFalse(
            memory.shouldBlockTrustedCandidate(
                acceptedText: "Db7(b9)",
                drawingData: differentDrawing,
                candidateTexts: ["C", "G/B", "F#"]
            )
        )
        XCTAssertFalse(
            memory.shouldBlockTrustedCandidate(
                acceptedText: "G/B",
                drawingData: rejectedDrawing,
                candidateTexts: rejectedSignature
            )
        )
    }

    func testExplicitlyRejectedSingleCandidateChordOnlyBlocksExactInkDigest() {
        var memory = ChordInkUserCorrectionMemory()
        let rejectedDrawing = Data("deleted c ink".utf8)
        let differentDrawing = Data("fresh c ink".utf8)

        XCTAssertTrue(
            memory.recordRejectedTrustedCandidate(
                acceptedText: "C",
                drawingData: rejectedDrawing,
                candidateSignature: ["C"],
                now: Date(timeIntervalSinceReferenceDate: 26)
            )
        )

        XCTAssertTrue(
            memory.shouldBlockTrustedCandidate(
                acceptedText: "C",
                drawingData: rejectedDrawing,
                candidateTexts: ["C"]
            )
        )
        XCTAssertFalse(
            memory.shouldBlockTrustedCandidate(
                acceptedText: "C",
                drawingData: differentDrawing,
                candidateTexts: ["C"]
            )
        )
        XCTAssertNil(memory.rejectedTrustedCandidateRules.first?.candidateSignatures)
    }

    func testStoreLoadsOlderCorrectionMemoryWithoutRejectedTrustedCandidateRules() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ChordInkUserCorrectionMemoryStore(
            url: temporaryDirectory.appendingPathComponent("chord-ink-user-correction-memory.json")
        )
        let legacyJSON = #"{"correctionRules":[],"suggestionExclusions":[]}"#

        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        try Data(legacyJSON.utf8).write(to: store.url)

        XCTAssertEqual(try store.load(), ChordInkUserCorrectionMemory())
    }

    func testStoreIgnoresLegacyDeletionDerivedRejectedCandidateRules() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = ChordInkUserCorrectionMemoryStore(
            url: temporaryDirectory.appendingPathComponent("chord-ink-user-correction-memory.json")
        )
        var memory = ChordInkUserCorrectionMemory()
        XCTAssertTrue(
            memory.recordRejectedTrustedCandidate(
                acceptedText: "C",
                drawingData: Data("ambiguous deletion".utf8),
                candidateSignature: ["C", "G", "B"]
            )
        )

        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        try store.save(memory)
        let currentJSON = try XCTUnwrap(String(contentsOf: store.url, encoding: .utf8))
        let legacyJSON = currentJSON.replacingOccurrences(
            of: "explicitRejectedTrustedCandidateRules",
            with: "rejectedAutoRenderRules"
        )
        try Data(legacyJSON.utf8).write(to: store.url)

        XCTAssertTrue(try store.load().rejectedTrustedCandidateRules.isEmpty)
    }

    func testStorePersistsUserCorrectionMemoryWhenPathContainsSpaces() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
        let store = ChordInkUserCorrectionMemoryStore(
            url: temporaryDirectory.appendingPathComponent("chord-ink-user-correction-memory.json")
        )
        var memory = ChordInkUserCorrectionMemory()
        XCTAssertTrue(
            memory.recordConfirmedSuggestion(
                acceptedText: "G/B",
                drawingData: Data("stored".utf8),
                candidateTexts: ["C", "G/B", "Db7(b9)"],
                decision: closeRaceDecision(gap: 0.03),
                now: Date(timeIntervalSinceReferenceDate: 30)
            )
        )
        XCTAssertTrue(
            memory.recordRejectedTrustedCandidate(
                acceptedText: "Db7(b9)",
                drawingData: Data("stored rejection".utf8),
                now: Date(timeIntervalSinceReferenceDate: 31)
            )
        )

        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory.deletingLastPathComponent())
        }

        try store.save(memory)

        XCTAssertEqual(try store.load(), memory)
        let storedJSON = try XCTUnwrap(String(contentsOf: store.url, encoding: .utf8))
        XCTAssertTrue(storedJSON.contains("explicitRejectedTrustedCandidateRules"))
        XCTAssertFalse(storedJSON.contains("rejectedAutoRenderRules"))
    }

    private func closeRaceDecision(gap: Double) -> ChordInkRecognitionDecision {
        ChordInkRecognitionDecision(
            action: .confirm,
            acceptedText: "G/B",
            reason: "Close race. Choose the chord you meant, or type it in.",
            isCloseRace: true,
            competingCandidateText: "C",
            confidenceGap: gap
        )
    }

    #if canImport(PencilKit) && canImport(UIKit)
    private func drawingData(
        color: UIColor,
        points: [CGPoint],
        mask: UIBezierPath? = nil
    ) -> Data {
        PKDrawing(strokes: [
            pencilStroke(color: color, points: points, mask: mask)
        ]).dataRepresentation()
    }

    private func pencilStroke(
        color: UIColor,
        points: [CGPoint],
        creationDate: Date = Date(timeIntervalSinceReferenceDate: 1_000),
        mask: UIBezierPath? = nil
    ) -> PKStroke {
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
        let path = PKStrokePath(
            controlPoints: controlPoints,
            creationDate: creationDate
        )
        return PKStroke(ink: PKInk(.pen, color: color), path: path, mask: mask)
    }
    #endif
}
