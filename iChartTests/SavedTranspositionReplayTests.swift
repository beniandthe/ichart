import Foundation
import XCTest
@testable import iChart

/// Opt-in local replay. User chart contents remain outside the repository.
final class SavedTranspositionReplayTests: XCTestCase {
    func testSavedFlatKeyChartDisplaysAndTransposesWithoutChangingItsSources() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["ICHART_PRIVATE_LIBRARY_REPLAY"],
              let title = environment["ICHART_PRIVATE_CHART_TITLE"] else {
            throw XCTSkip("Private saved-chart replay is not configured")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let library = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let charts = try XCTUnwrap(library["charts"] as? [[String: Any]])
        let object = try XCTUnwrap(charts.first { ($0["title"] as? String) == title })
        let saved = try ChartPersistenceCoders.decoder.decode(Chart.self,
            from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(saved.documentKey, .dFlatMajor)
        XCTAssertEqual(saved.measures.count, 26)
        let flatRoots = [1: "Db", 3: "Eb", 6: "Gb", 8: "Ab", 10: "Bb"]
        let sharpRoots = [2: "D", 4: "E", 7: "G", 9: "A", 11: "B"]

        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            var chart = saved
            chart.layoutStyle = style
            let before = chart
            var counts: [String: Int] = [:]
            for measure in chart.measures {
                for event in measure.chordEvents where event.symbol.kind == .rooted {
                    let displayed = chart.displayedChordSymbol(for: event, in: measure.id)
                    let pitch = ChordPitch(root: displayed.root, accidental: displayed.accidental)
                    let name = displayed.root.rawValue + displayed.accidental.rawValue
                    XCTAssertEqual(name, flatRoots[pitch.semitone])
                    XCTAssertEqual(displayed.quality, event.symbol.quality)
                    XCTAssertEqual(displayed.extensions, event.symbol.extensions)
                    XCTAssertEqual(displayed.alterations, event.symbol.alterations)
                    counts[name, default: 0] += 1
                }
            }
            XCTAssertEqual(counts, ["Db": 3, "Bb": 3, "Gb": 6, "Eb": 3, "Ab": 1])
            XCTAssertEqual(chart, before, "Displaying a saved chart must not rewrite its sources")
            chart = try ChartPersistenceCoders.decoder.decode(Chart.self,
                from: ChartPersistenceCoders.encoder.encode(chart))
            XCTAssertEqual(chart, before)

            XCTAssertTrue(chart.setDocumentKey(.dMajor))
            for measure in chart.measures {
                for event in measure.chordEvents {
                    let source = try XCTUnwrap(before.chordEvent(id: event.id))
                    XCTAssertEqual(event.sourceInkData, source.sourceInkData)
                    XCTAssertEqual(event.sourceCandidateSignature, source.sourceCandidateSignature)
                    XCTAssertEqual(event.startPosition, source.startPosition)
                    XCTAssertEqual(event.symbol.quality, source.symbol.quality)
                    guard event.symbol.kind == .rooted else { continue }
                    let displayed = chart.displayedChordSymbol(for: event, in: measure.id)
                    let pitch = ChordPitch(root: displayed.root, accidental: displayed.accidental)
                    XCTAssertEqual(displayed.root.rawValue + displayed.accidental.rawValue,
                        sharpRoots[pitch.semitone])
                }
            }
            XCTAssertEqual(chart.measures.map(\.id), before.measures.map(\.id))
            XCTAssertEqual(chart.pageHandwrittenNotationData, before.pageHandwrittenNotationData)
            XCTAssertEqual(chart.pageHandwrittenNotationCoordinateSpace, before.pageHandwrittenNotationCoordinateSpace)
            XCTAssertEqual(try ChartPersistenceCoders.decoder.decode(Chart.self,
                from: ChartPersistenceCoders.encoder.encode(chart)), chart)
        }
    }
}
