import XCTest
@testable import SmartChart

final class ChordInkSymbolLedgerTests: XCTestCase {
    func testLedgerRecordsStableSymbolsAndRunningPrefixesWithoutChangingRecognition() throws {
        let strokes = try templateStrokes("C", offsetX: 0)
            + templateStrokes("7", offsetX: 80)
        let recognizer = ChordInkRecognizer()

        let result = recognizer.recognize(strokes: strokes)
        let ledger = try XCTUnwrap(result.symbolLedger)

        XCTAssertEqual(result.match?.displayText, "C7")
        XCTAssertEqual(ledger.stableSymbols.compactMap(\.bestText), ["C", "7"])
        XCTAssertEqual(ledger.stableText, "C7")
        XCTAssertEqual(ledger.runningPrefixes.map(\.text), ["C", "C7"])
        XCTAssertEqual(ledger.runningPrefixes.map(\.displayText), ["C", "C7"])
        XCTAssertTrue(ledger.runningPrefixes[0].supportedDisplayTexts.contains("C"))
        XCTAssertTrue(ledger.runningPrefixes[1].supportedDisplayTexts.contains("C7"))
        XCTAssertEqual(ledger.finalCandidateText, result.rawCandidates.first)
        XCTAssertEqual(ledger.finalCandidateDisplayText, "C7")
    }

    func testLedgerRunningPrefixesUseColumnCandidatesInsteadOfOnlyTopGlyphs() {
        let clusters = [
            cluster(minX: 0, maxX: 20),
            cluster(minX: 30, maxX: 42),
            cluster(minX: 54, maxX: 66),
            cluster(minX: 82, maxX: 104)
        ]
        let glyphs = [
            [GlyphCandidate(text: "B", confidence: 0.97, source: .template)],
            [GlyphCandidate(text: "b", confidence: 0.98, source: .template)],
            [
                GlyphCandidate(text: "1", confidence: 1.00, source: .template),
                GlyphCandidate(text: "/", confidence: 0.72, source: .template)
            ],
            [GlyphCandidate(text: "D", confidence: 0.98, source: .template)]
        ]

        let snapshot = ChordInkSymbolLedger().snapshot(
            glyphCandidateGroups: glyphs,
            clusters: clusters,
            chordCandidates: []
        )

        XCTAssertEqual(snapshot.stableText, "Bb1D")
        XCTAssertTrue(snapshot.runningPrefixes.last?.supportedDisplayTexts.contains("Bb/D") == true)
    }

    func testLedgerMarksSymbolsStableWhenNextInkIsClearlyToTheRight() {
        let clusters = [
            cluster(minX: 0, maxX: 20),
            cluster(minX: 36, maxX: 50)
        ]
        let glyphs = [
            [GlyphCandidate(text: "C", confidence: 0.95, source: .template)],
            [GlyphCandidate(text: "7", confidence: 0.90, source: .template)]
        ]

        let snapshot = ChordInkSymbolLedger().snapshot(
            glyphCandidateGroups: glyphs,
            clusters: clusters,
            chordCandidates: []
        )

        XCTAssertEqual(snapshot.stableSymbols.map(\.stabilityReason), [.nextInkToRight, .idleSettled])
    }

    func testLedgerKeepsOverlappingSymbolsDiagnosticOnly() {
        let clusters = [
            cluster(minX: 0, maxX: 40),
            cluster(minX: 24, maxX: 52)
        ]
        let glyphs = [
            [GlyphCandidate(text: "B", confidence: 0.86, source: .template)],
            [GlyphCandidate(text: "b", confidence: 0.84, source: .template)]
        ]

        let snapshot = ChordInkSymbolLedger().snapshot(
            glyphCandidateGroups: glyphs,
            clusters: clusters,
            chordCandidates: []
        )

        XCTAssertEqual(snapshot.stableSymbols.first?.stabilityReason, .unresolvedOverlap)
        XCTAssertEqual(snapshot.stableText, "Bb")
    }

    private func templateStrokes(_ text: String, offsetX: Double) throws -> [InkStroke] {
        let template = try XCTUnwrap(ChordGlyphTemplateLibrary.initialTemplates.first { $0.text == text })
        return template.strokes.map { stroke in
            InkStroke(
                points: stroke.points.map { point in
                    InkPoint(
                        x: point.x + offsetX,
                        y: point.y,
                        timeOffset: point.timeOffset
                    )
                }
            )
        }
    }

    private func cluster(minX: Double, maxX: Double) -> InkCluster {
        InkCluster(
            strokes: [
                InkStroke(points: [
                    InkPoint(x: minX, y: 0, timeOffset: nil),
                    InkPoint(x: maxX, y: 20, timeOffset: nil)
                ])
            ]
        )
    }
}
