#if canImport(UIKit)
import CryptoKit
import PencilKit
import XCTest
@testable import iChart

/// Replays source ownership, not chord accuracy. Private ink is supplied locally
/// and never checked in. Intended chord answers are not read by this test.
final class ChordInkBarlineSourceReplayTests: XCTestCase {
    func testProvidedOriginalDrawingPreservesEmbeddedInkThroughPreparation() throws {
        let env = ProcessInfo.processInfo.environment
        let names = ["ICHART_BARLINE_REPLAY_LIBRARY", "ICHART_BARLINE_REPLAY_CHART_ID",
                     "ICHART_BARLINE_REPLAY_PAGE_WIDTH", "ICHART_BARLINE_REPLAY_SOURCE_COUNT",
                     "ICHART_BARLINE_REPLAY_TARGET_COUNT"]
        guard names.allSatisfy({ env[$0] != nil }) else {
            throw XCTSkip("Provide authorized saved library, chart ID, page width and structural expected counts")
        }
        guard names.allSatisfy({ !(env[$0]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) }) else {
            XCTFail("Supplied replay configuration must be nonempty"); return
        }
        let sourceURL = URL(fileURLWithPath: env[names[0]]!).standardizedFileURL.resolvingSymlinksInPath()
        let sourceBytes = try Data(contentsOf: sourceURL)
        defer { XCTAssertEqual(try? Data(contentsOf: sourceURL), sourceBytes, "Source library must remain unchanged") }
        let chartID = try XCTUnwrap(UUID(uuidString: env[names[1]]!))
        let width = try XCTUnwrap(Double(env[names[2]]!))
        let sourceCount = try XCTUnwrap(Int(env[names[3]]!))
        let targetCount = try XCTUnwrap(Int(env[names[4]]!))
        guard width.isFinite, width >= 720, sourceCount > 0, targetCount > 0 else {
            XCTFail("Invalid replay dimensions or counts"); return
        }
        struct Library: Decodable { var charts: [Chart] }
        // Read original bytes separately: Chart decoding may normalize pen color.
        struct RawChart: Decodable { var id: UUID; var pageHandwrittenChordData: Data? }
        struct RawLibrary: Decodable { var charts: [RawChart] }
        let library = try JSONDecoder().decode(Library.self, from: sourceBytes)
        let raw = try JSONDecoder().decode(RawLibrary.self, from: sourceBytes)
        let matches = library.charts.filter { $0.id == chartID }
        let chart = try XCTUnwrap(matches.count == 1 ? matches.first : nil)
        let rawMatches = raw.charts.filter { $0.id == chartID }
        let drawingData = try XCTUnwrap(rawMatches.count == 1 ? rawMatches.first?.pageHandwrittenChordData : nil)
        let savedSpace = try XCTUnwrap(chart.pageHandwrittenChordCoordinateSpace)
        let drawing = try PKDrawing(data: drawingData)
        XCTAssertEqual(drawing.strokes.count, sourceCount)
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart,
            pageSize: CGSize(width: width, height: 1_200), includesChordInkContinuationLanes: true)
        let region = LeadSheetActiveInkScope.chordWritingRegion(for: layout)
        // No scaling/reflow is permitted in this component replay. Fail if the
        // supplied layout cannot reproduce the source canvas coordinate space.
        XCTAssertEqual(Double(region.frame.width), savedSpace.width, accuracy: 0.001)
        XCTAssertEqual(Double(region.frame.height), savedSpace.height, accuracy: 0.001)
        guard testRun?.failureCount == 0 else { return }
        let result = ChordInkRecognitionPreparation.prepare(.init(requestID: UUID(), scheduledAt: Date(),
            requestedDelay: 0, drawingData: drawingData, chordFrame: region.frame,
            pageLayout: layout, flow: .draftPreview, options: .live, layoutStyle: chart.layoutStyle))
        XCTAssertEqual(result.sourceStrokeCount, sourceCount)
        XCTAssertEqual(result.visibleStrokeCount, sourceCount)
        XCTAssertEqual(result.ignoredInvisibleStrokeCount, 0)
        XCTAssertTrue(result.barlines.isEmpty, "Embedded mark must not become a hard separator")
        XCTAssertEqual(result.recognitionStrokeCount, sourceCount)
        guard case .ready(let requests, _) = result.outcome else {
            XCTFail("Expected prepared targets, not an unsupported/empty route"); return
        }
        XCTAssertEqual(requests.count, targetCount)
        let visible = ChordInkDraftVisibleStrokePolicy.visibleDrawingContext(from: drawing)
        let strokes = PencilKitInkAdapter.inkStrokes(from: visible.drawing)
        let delivered = requests.flatMap(\.strokes)
        XCTAssertEqual(delivered.count, strokes.count)
        // Match the complete InkStroke including points, bounds and creation
        // offsets; require one-to-one ownership rather than just equal counts.
        XCTAssertTrue(strokes.allSatisfy { stroke in delivered.filter { $0 == stroke }.count == 1 })
        // Prepared targets must also be compatible with exact destructive-clear
        // coverage. This reads no intended answer and does not run recognition:
        // the constant label is irrelevant to source ownership.
        let drafts = requests.map { request in
            ChordInkDraft(input: ChordInkDraftInput(
                measureID: request.target.measureID,
                measureIndex: chart.measure(id: request.target.measureID)?.index ?? 0,
                targetFraction: request.target.fraction,
                visualOrder: request.visualOrder,
                laneLocation: request.laneLocation,
                layoutPageSize: request.layoutPageSize,
                drawingData: request.drawingData,
                candidateTexts: ["C"], bestCandidateText: "C", confidence: 4,
                strokeCount: request.strokes.count
            ))
        }
        let state = ChordPreviewState(draftChords: drafts, layoutPageSize: layout.pageBounds.size)
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: chart, state: state),
            "Exact saved-input preparation must preserve every source fragment for clearing safety")
        let sourceSHA = SHA256.hash(data: sourceBytes).map { String(format: "%02x", $0) }.joined()
        print("BARLINE_SOURCE_REPLAY style=\(chart.layoutStyle.rawValue) source=\(sourceCount) recognition=\(result.recognitionStrokeCount) targets=\(requests.count) sourceSHA256=\(sourceSHA) scope=exact-source-component-replay-not-fresh-accuracy")
    }
}
#endif
