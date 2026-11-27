#if canImport(UIKit) && canImport(PencilKit)
import Foundation
import PencilKit
import UIKit
import XCTest
@testable import iChart

/// Opt-in retained handwriting replay. The barlines are reconstructed context,
/// not the erased failed drawing. Expected labels come from the screenshot;
/// no recorded label, ownership partition or profile is supplied to inference.
/// Source safety is asserted; raw-reader accuracy against that truth is reported
/// separately and must not be described as a passing accuracy check.
final class ChordInkNaturalWritingPrivateReplayTests: XCTestCase {
    func testRetainedRowPreservesCanonicalChordSourcesWithSyntheticDividers() throws {
        guard let path = ProcessInfo.processInfo.environment["ICHART_NATURAL_WRITING_REPLAY_DIR"],
              !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw XCTSkip("Supply the authorized private retained-handwriting replay directory")
        }
        let root = URL(fileURLWithPath: path).standardizedFileURL
        let urls = (16..<24).map { root.appendingPathComponent(String(format: "event-%02d.pkdrawing", $0)) }
        let bytes = try urls.map { try Data(contentsOf: $0) }
        defer {
            for (url, original) in zip(urls, bytes) {
                XCTAssertEqual(try? Data(contentsOf: url), original, "Private source must remain unchanged")
            }
        }
        let originals = try bytes.map { try PKDrawing(data: $0) }
        let expected = try ["G", "%", "%", "%", "A-", "B-", "C", "%"].map(ChordSymbolParser.parse)
        for paper in [true, false] {
            for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
                var chart = Chart.draft(title: "Private natural-writing replay", layoutStyle: style)
                chart.completeInitialSetup(title: chart.title, key: .cMajor,
                    meter: Meter(numerator: 4, denominator: 4), staffStyle: .fiveLine,
                    startingMeasureCount: 1)
                if paper { XCTAssertTrue(chart.initializePaperWritingRows(count: 3)) }
                let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart,
                    pageSize: CGSize(width: 1_100, height: 1_400), includesChordInkContinuationLanes: true)
                let system = try XCTUnwrap(layout.systems.first)
                let frame = LeadSheetActiveInkScope.chordWritingFrame(for: layout)
                let pageLane = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingSystemLaneFrame(
                    for: system, paperFrame: layout.paperFrame(for: system)))
                let lane = pageLane.offsetBy(dx: -frame.minX, dy: -frame.minY)
                let left = lane.minX + lane.width * 0.04
                let cellWidth = lane.width * 0.92 / CGFloat(expected.count)
                let relocated = originals.enumerated().map { index, drawing -> PKDrawing in
                    let bounds = drawing.bounds
                    XCTAssertGreaterThan(bounds.width, 0); XCTAssertGreaterThan(bounds.height, 0)
                    let scale = min(lane.height * 0.64 / bounds.height, cellWidth * 0.58 / bounds.width)
                    let centerX = left + cellWidth * (CGFloat(index) + 0.5)
                    return drawing.transformed(using: CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
                        tx: centerX - bounds.midX * scale, ty: lane.midY - bounds.midY * scale))
                }
                var strokes: [PKStroke] = []
                var dividerIndices = Set<Int>()
                var chordSourceIndices: [[Int]] = []
                for index in 0...relocated.count {
                    let prior = index == 0 ? relocated[0] : relocated[index - 1]
                    let time = index == 0
                        ? try XCTUnwrap(prior.strokes.map { $0.path.creationDate }.min()).addingTimeInterval(-0.08)
                        : try XCTUnwrap(prior.strokes.map {
                            $0.path.creationDate.addingTimeInterval($0.path.last?.timeOffset ?? 0)
                        }.max()).addingTimeInterval(0.05)
                    dividerIndices.insert(strokes.count)
                    strokes.append(divider(x: left + cellWidth * CGFloat(index), lane: lane, date: time))
                    if index < relocated.count {
                        let first = strokes.count
                        strokes += relocated[index].strokes
                        chordSourceIndices.append(Array(first..<strokes.count))
                    }
                }
                let sourceData = PKDrawing(strokes: strokes).dataRepresentation()
                let canonical = try PKDrawing(data: sourceData)
                let canonicalChords = chordSourceIndices.map { indices in
                    PKDrawing(strokes: indices.map { canonical.strokes[$0] })
                }
                let prepared = ChordInkRecognitionPreparation.prepare(.init(requestID: UUID(),
                    scheduledAt: Date(), requestedDelay: 0, drawingData: sourceData,
                    chordFrame: frame, pageLayout: layout, flow: .draftPreview, options: .live, layoutStyle: style))
                let ownership = try XCTUnwrap(prepared.ownershipSnapshot)
                let actualDividers = Set(ownership.barlineVisibleFragmentIndices.map {
                    ownership.visibleFragmentSourceStrokeIndices[$0]
                })
                let targetSourceIndices = ownership.targetGroups.flatMap(\.visibleFragmentIndices).map {
                    ownership.visibleFragmentSourceStrokeIndices[$0]
                }
                XCTAssertEqual(actualDividers, dividerIndices, "\(style) paper=\(paper)")
                XCTAssertTrue(dividerIndices.isDisjoint(with: Set(targetSourceIndices)))
                XCTAssertEqual(Set(targetSourceIndices), Set(strokes.indices).subtracting(dividerIndices))
                XCTAssertEqual(prepared.recognitionStrokeCount, relocated.reduce(0) { $0 + $1.strokes.count })
                guard case .ready(let requests, _) = prepared.outcome else {
                    XCTFail("Expected real prepared targets in \(style), paper=\(paper)"); continue
                }
                XCTAssertEqual(requests.count, expected.count)
                guard requests.count == expected.count else { continue }
                let recognizer = ChordInkMaximumTrustRecognizer()
                var wholeLabels: [String] = [], isolatedLabels: [String] = [], rawLabels: [String] = []
                var wholeMatchesTruth: [Bool] = [], isolatedMatchesTruth: [Bool] = [], rawMatchesTruth: [Bool] = []
                for (index, request) in requests.enumerated() {
                    let raw = recognizer.recognize(strokes: PencilKitInkAdapter.inkStrokes(from: originals[index]))
                    let isolated = recognizer.recognize(strokes: PencilKitInkAdapter.inkStrokes(from: canonicalChords[index]))
                    let whole = recognizer.recognize(strokes: request.strokes, options: .live)
                    rawLabels.append(raw.match?.displayText ?? "no match")
                    isolatedLabels.append(isolated.match?.displayText ?? "no match")
                    rawMatchesTruth.append(raw.match?.symbol == expected[index])
                    isolatedMatchesTruth.append(isolated.match?.symbol == expected[index])
                    wholeMatchesTruth.append(whole.match?.symbol == expected[index])
                    wholeLabels.append(whole.match?.displayText ?? "no match")
                    XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(
                        expected: canonicalChords[index], current: try PKDrawing(data: request.drawingData)),
                        "Every target must retain exactly its source from the same persisted drawing")
                    XCTAssertEqual(whole.match?.symbol, isolated.match?.symbol,
                        "Synthetic divider context must not change the isolated read at target \(index)")
                }
                let report: [String: Any] = ["scope": "retained-private-source-with-synthetic-dividers",
                    "layoutStyle": style.rawValue, "paper": paper, "wholeRowLabels": wholeLabels,
                    "isolatedLabels": isolatedLabels, "rawOriginalLabels": rawLabels,
                    "screenshotExpectedLabels": expected.map(\.displayText),
                    "wholeMatchesTruth": wholeMatchesTruth, "isolatedMatchesTruth": isolatedMatchesTruth,
                    "rawMatchesTruth": rawMatchesTruth, "accuracyIsDiagnosticOnly": true,
                    "sourceComparison": "canonical persisted drawing fragments, without fuzzy tolerances",
                    "sourceStrokeCount": strokes.count,
                    "syntheticDividerCount": dividerIndices.count, "sourceBytesEdited": false]
                let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
                print("NATURAL_PRIVATE_REPLAY \(String(decoding: data, as: UTF8.self))")
                let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
                attachment.name = "private-row-\(style.rawValue)-paper-\(paper)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    private func divider(x: CGFloat, lane: CGRect, date: Date) -> PKStroke {
        let points = [lane.minY + lane.height * 0.04, lane.maxY - lane.height * 0.04]
            .enumerated().map { index, y in
                PKStrokePoint(location: CGPoint(x: x, y: y), timeOffset: Double(index) * 0.035,
                    size: CGSize(width: 2.5, height: 2.5), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
            }
        return PKStroke(ink: PKInk(.pen, color: LeadSheetPersistentInkColorPolicy.inkColor),
            path: PKStrokePath(controlPoints: points, creationDate: date))
    }
}
#endif
