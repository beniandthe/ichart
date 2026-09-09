#if canImport(PencilKit)
import Foundation
import XCTest
@testable import iChart

final class ChordEntryPassReplayTests: XCTestCase {
    func testReplayChordWritingTestChartFromSavedState() throws {
        guard let statePath = ProcessInfo.processInfo.environment["ICHART_STATE"] else {
            throw XCTSkip("Set ICHART_STATE to a simulator library-state.json to replay saved chord ink.")
        }

        let repository = FileChartRepository(url: URL(fileURLWithPath: statePath))
        let snapshot = try XCTUnwrap(try repository.loadSnapshot())
        let chart = try XCTUnwrap(
            selectedChart(in: snapshot),
            "Expected a matching chart in \(statePath)."
        )
        let recognizer = ChordInkRecognizer()

        for measure in chart.measures {
            for chordEvent in measure.chordEvents {
                guard let sourceInkData = chordEvent.sourceInkData else {
                    XCTFail("Missing source ink for \(chordEvent.symbol.displayText) in measure \(measure.index).")
                    continue
                }

                let strokes = try PencilKitInkAdapter.inkStrokes(from: sourceInkData)
                let result = recognizer.recognize(strokes: strokes)
                let decision = ChordInkRecognitionPolicy.decision(for: result)
                let savedText = chordEvent.rawInput ?? chordEvent.symbol.displayText
                let matchText = result.match?.displayText ?? "nil"
                let scores = result.candidateScores
                    .prefix(6)
                    .map { score in
                        let display = score.displayText ?? score.text
                        return "\(display):\(String(format: "%.3f", score.confidence))"
                    }
                    .joined(separator: ",")

                print(
                    [
                        "measure=\(measure.index)",
                        "saved=\(savedText)",
                        "match=\(matchText)",
                        "confidence=\(String(format: "%.3f", result.confidence))",
                        "action=\(decision.action)",
                        "gap=\(decision.confidenceGap.map { String(format: "%.3f", $0) } ?? "nil")",
                        "scores=[\(scores)]"
                    ].joined(separator: " ")
                )

                if ProcessInfo.processInfo.environment["ICHART_REPLAY_GLYPHS"] == "1" {
                    let clusters = StrokeClusterer().cluster(strokes)
                    for (index, group) in result.glyphCandidates.enumerated() {
                        let glyphSummary = group
                            .prefix(8)
                            .map { candidate in
                                "\(candidate.text):\(String(format: "%.3f", candidate.confidence))"
                            }
                            .joined(separator: ",")
                        let cluster = clusters.indices.contains(index) ? clusters[index] : nil
                        let bounds = cluster.map {
                            " x=\(String(format: "%.1f", $0.bounds.minX))-\(String(format: "%.1f", $0.bounds.maxX)) y=\(String(format: "%.1f", $0.bounds.minY))-\(String(format: "%.1f", $0.bounds.maxY)) strokes=\($0.strokes.count)"
                        } ?? ""
                        print("  glyph[\(index)]\(bounds)=[\(glyphSummary)]")
                        if ProcessInfo.processInfo.environment["ICHART_REPLAY_STROKES"] == "1",
                           let cluster {
                            for (strokeIndex, stroke) in cluster.strokes.enumerated() {
                                print(
                                    "    stroke[\(strokeIndex)] x=\(String(format: "%.1f", stroke.bounds.minX))-\(String(format: "%.1f", stroke.bounds.maxX)) y=\(String(format: "%.1f", stroke.bounds.minY))-\(String(format: "%.1f", stroke.bounds.maxY)) points=\(stroke.points.count) straight=\(String(format: "%.2f", stroke.straightness)) hdir=\(stroke.horizontalDirectionChangeCount)"
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    func testReplayPendingChordInkFromSavedState() throws {
        guard ProcessInfo.processInfo.environment["ICHART_REPLAY_PENDING_CHORD_INK"] == "1" else {
            throw XCTSkip("Set ICHART_REPLAY_PENDING_CHORD_INK=1 to replay pending page chord ink.")
        }
        guard let statePath = ProcessInfo.processInfo.environment["ICHART_STATE"] else {
            throw XCTSkip("Set ICHART_STATE to a device or simulator library-state.json.")
        }

        let repository = FileChartRepository(url: URL(fileURLWithPath: statePath))
        let snapshot = try XCTUnwrap(try repository.loadSnapshot())
        let chart = try XCTUnwrap(selectedChart(in: snapshot))
        let drawingData = try XCTUnwrap(chart.pageHandwrittenChordData)
        let strokes = try PencilKitInkAdapter.inkStrokes(from: drawingData)
        XCTAssertFalse(strokes.isEmpty)

        let firstStrokeResult = ChordInkRecognizer().recognize(strokes: [strokes[0]])
        printRecognition(label: "first_stroke", result: firstStrokeResult)

        let indexedStrokes = strokes.enumerated().map { (index: $0.offset, stroke: $0.element) }
        let sequentialGroups = ChordInkSequentialGrouper().groups(for: indexedStrokes)
        let sequentialResults = sequentialGroups.map { group in
            ChordInkRecognizer().recognize(strokes: group.strokeIndices.map { strokes[$0] })
        }
        for (index, result) in sequentialResults.enumerated() {
            printRecognition(label: "sequential_group_\(index)", result: result)
        }

        let gapClusters = ChordInkBatchClusterer.clusters(for: strokes)
        let gapResults = gapClusters.map { cluster in
            ChordInkRecognizer().recognize(strokes: cluster.strokeIndices.map { strokes[$0] })
        }
        for (index, result) in gapResults.enumerated() {
            printRecognition(label: "gap_group_\(index)", result: result)
        }

        print(
            "pending_chord_ink strokes=\(strokes.count) sequential_groups=\(sequentialGroups.count) "
                + "gap_groups=\(gapClusters.count)"
        )

        if let expectedSequence = ProcessInfo.processInfo.environment["ICHART_REPLAY_EXPECTED_SEQUENCE"]?
            .split(separator: ",")
            .map(String.init),
           !expectedSequence.isEmpty {
            XCTAssertEqual(sequentialResults.compactMap { $0.match?.displayText }, expectedSequence)
        }
    }

    private func selectedChart(in snapshot: ChartLibrarySnapshot) -> Chart? {
        if let chartIDText = ProcessInfo.processInfo.environment["ICHART_REPLAY_CHART_ID"],
           let chartID = UUID(uuidString: chartIDText),
           let chart = snapshot.charts.first(where: { $0.id == chartID }) {
            return chart
        }

        let title = ProcessInfo.processInfo.environment["ICHART_REPLAY_CHART_TITLE"]
            ?? "Chord Writing Test Chart"
        return snapshot.charts.first { $0.title == title }
    }

    private func printRecognition(label: String, result: ChordInkRecognitionResult) {
        let decision = ChordInkRecognitionPolicy.decision(for: result)
        let scores = result.candidateScores
            .prefix(8)
            .map { score in
                let display = score.displayText ?? score.text
                return "\(display):\(String(format: "%.3f", score.confidence))"
            }
            .joined(separator: ",")
        let glyphs = result.glyphCandidates.enumerated().map { index, candidates in
            let summary = candidates.prefix(6).map {
                "\($0.text):\(String(format: "%.3f", $0.confidence))"
            }.joined(separator: ",")
            return "glyph[\(index)]=[\(summary)]"
        }.joined(separator: " ")

        print(
            "\(label) match=\(result.match?.displayText ?? "nil") "
                + "confidence=\(String(format: "%.3f", result.confidence)) "
                + "action=\(decision.action.rawValue) "
                + "gap=\(decision.confidenceGap.map { String(format: "%.3f", $0) } ?? "nil") "
                + "scores=[\(scores)] \(glyphs)"
        )
    }
}
#endif
