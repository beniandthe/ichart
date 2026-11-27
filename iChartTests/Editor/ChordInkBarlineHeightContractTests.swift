#if canImport(UIKit) && canImport(PencilKit)
import CoreGraphics
import PencilKit
import UIKit
import XCTest
@testable import iChart

/// Component-level mixed-ink preparation and real-reader checks. The requested
/// half-lane behavior is distinct from the diagnostic matrix of the baseline
/// 0.62 ordinary / 0.88 wider-stroke coverage contract. These are controlled
/// source replays, not a claim about fresh physical handwriting accuracy.
final class ChordInkBarlineHeightContractTests: XCTestCase {
    func testHalfLaneDividersSeparateRealChordsInBothDirectionsPositionsKindsAndStyles() throws {
        for style in styles {
            let fixture = try makeFixture(style)
            for position in Position.allCases {
                for upward in [false, true] {
                    for kind in [DraftBarlineKind.single, .double] {
                        let sample = try mixedSample(height: 0.50, position: position,
                            upward: upward, kind: kind, fixture: fixture)
                        let prepared = prepare(sample.drawing, fixture: fixture)
                        let context = "\(style) half-lane \(position) upward=\(upward) \(kind)"
                        XCTAssertEqual(prepared.barlines.count, 1, context)
                        XCTAssertEqual(prepared.barlines.first?.kind, kind, context)
                        XCTAssertEqual(Set(prepared.barlines.flatMap(\.ownedSourceStrokeIndices)), sample.barIndices, context)
                        try assertChordTargets(prepared, sample: sample, context: context)
                        try assertExactPartition(prepared, drawing: sample.drawing, context: context)
                    }
                }
            }
        }
    }

    func testPartialHeightMatrixReportsAcceptanceWithoutPromisingEveryLength() throws {
        for style in styles {
            let fixture = try makeFixture(style)
            for height: CGFloat in [0.35, 0.50, 0.65, 0.90] {
                for position in Position.allCases {
                    for upward in [false, true] {
                        for kind in [DraftBarlineKind.single, .double] {
                            let sample = try mixedSample(height: height, position: position,
                                upward: upward, kind: kind, fixture: fixture)
                            let prepared = prepare(sample.drawing, fixture: fixture)
                            let targetCount: Int
                            if case .ready(let targets, _) = prepared.outcome { targetCount = targets.count }
                            else { targetCount = 0 }
                            print("BARLINE_HEIGHT_MATRIX", style.rawValue, "requestedHeight", height,
                                "laneHeight", fixture.lane.height, "position", position,
                                "upward", upward, "kind", kind, "bars", prepared.barlines.count,
                                "coverage", prepared.barlines.map(\.metrics.laneCoverage),
                                "owners", prepared.barlines.map { $0.ownedSourceStrokeIndices.sorted() },
                                "chordTargets", targetCount)
                            // Preserve the previously supported ordinary-height
                            // band. The shorter rows are observations; the
                            // separate half-lane test specifies the new goal.
                            if height >= 0.65 {
                                XCTAssertEqual(prepared.barlines.count, 1)
                                XCTAssertEqual(prepared.barlines.first?.kind, kind)
                                XCTAssertEqual(Set(prepared.barlines.flatMap(\.ownedSourceStrokeIndices)), sample.barIndices)
                                try assertChordTargets(prepared, sample: sample,
                                    context: "\(style) existing ordinary coverage \(height) \(position) \(upward) \(kind)")
                            }
                            try assertExactPartition(prepared, drawing: sample.drawing,
                                context: "\(style) \(height) \(position) \(upward) \(kind)")
                        }
                    }
                }
            }
        }
    }

    func testFullLaneWideDividersRetainTheirExistingAllowanceInEitherDirection() throws {
        for style in styles {
            let fixture = try makeFixture(style)
            for upward in [false, true] {
                for slope: CGFloat in [-0.32, 0.32] {
                    let sample = try mixedSample(height: 0.90, position: .centered,
                        upward: upward, kind: .single, slope: slope, fixture: fixture)
                    let prepared = prepare(sample.drawing, fixture: fixture)
                    let context = "\(style) full-lane wide upward=\(upward) slope=\(slope)"
                    XCTAssertEqual(prepared.barlines.count, 1, context)
                    XCTAssertEqual(Set(prepared.barlines.flatMap(\.ownedSourceStrokeIndices)), sample.barIndices, context)
                    try assertChordTargets(prepared, sample: sample, context: context)
                    try assertExactPartition(prepared, drawing: sample.drawing, context: context)
                }
            }
        }
    }

    func testChordBodiesPercentAndSlashBassKeepTheirSourcesAtNormalWritingHeight() throws {
        for style in styles {
            let fixture = try makeFixture(style)
            for name in ["BCaptured01", "DCaptured01", "FCaptured01", "FSharpCaptured01", "BFlatCaptured01",
                         "ChordRepeatCaptured01", "GSlashBCaptured01"] {
                let document = try InkFixtureLoader.load(name, file: #filePath)
                let source = try captured(name, fraction: 0.38, fixture: fixture, start: 0)
                let drawing = try canonical(PKDrawing(strokes: source))
                let prepared = prepare(drawing, fixture: fixture)
                let sample = Sample(drawing: drawing, barIndices: [],
                    chords: [(Set(drawing.strokes.indices), document.expectedDisplayText)])
                let context = "\(style) normal-height genuine \(name)"
                XCTAssertTrue(prepared.barlines.isEmpty, context)
                try assertChordTargets(prepared, sample: sample, context: context, requiresExpectedRead: false)
                try assertExactPartition(prepared, drawing: drawing, context: context)
            }
        }
    }

    func testMaskedPartialChordStemsRemainChordSourceRatherThanShortBoundaries() throws {
        for style in styles {
            let fixture = try makeFixture(style)
            for name in ["BCaptured01", "FSharpCaptured01"] {
                let document = try InkFixtureLoader.load(name, file: #filePath)
                let source = try captured(name, fraction: 0.38, fixture: fixture, start: 0)
                let original = try XCTUnwrap(source.first)
                let visibleBand = CGRect(x: fixture.lane.minX - fixture.frame.minX - 10,
                    y: fixture.lane.midY - fixture.lane.height * 0.25 - fixture.frame.minY,
                    width: fixture.lane.width + 20, height: fixture.lane.height * 0.50)
                let clipped = PKStroke(ink: original.ink, path: original.path,
                    transform: original.transform, mask: UIBezierPath(rect: visibleBand))
                let drawing = try canonical(PKDrawing(strokes: [clipped] + Array(source.dropFirst())))
                let prepared = prepare(drawing, fixture: fixture)
                let sample = Sample(drawing: drawing, barIndices: [],
                    chords: [(Set(drawing.strokes.indices), document.expectedDisplayText)])
                let context = "\(style) bitmap-clipped \(name)"
                XCTAssertTrue(prepared.barlines.isEmpty,
                    "\(context): shortening a root stem with the eraser cannot turn it into a divider")
                try assertChordTargets(prepared, sample: sample, context: context, requiresExpectedRead: false)
                try assertExactPartition(prepared, drawing: drawing, context: context)
            }
        }
    }

    func testCompactFlaggedSevenRemainsChordSourceRatherThanBecomingShortDivider() throws {
        for style in styles {
            let fixture = try makeFixture(style)
            let c = try captured("CCaptured01", fraction: 0.38, fixture: fixture, start: 0, height: 26)
            let bounds = PKDrawing(strokes: c).bounds.offsetBy(dx: fixture.frame.minX, dy: fixture.frame.minY)
            let left = bounds.maxX + 5
            let top = bounds.midY - 12
            // This ordinary narrow handwritten seven has a short top flag
            // followed by its descending diagonal. Its endpoints share x,
            // so endpoint angle alone misleadingly calls it vertical.
            let seven = stroke([CGPoint(x: left, y: top), CGPoint(x: left + 8, y: top),
                CGPoint(x: left, y: top + 24)], fixture: fixture, start: 0.06)
            let drawing = try canonical(PKDrawing(strokes: c + [seven]))
            let prepared = prepare(drawing, fixture: fixture)
            let context = "\(style) compact C plus flagged seven"
            print("BARLINE_HEIGHT_SEVEN_CONTROL", style.rawValue, "laneHeight", fixture.lane.height,
                "bars", prepared.barlines.map { "\($0.metrics):\($0.ownedSourceStrokeIndices.sorted())" })
            XCTAssertTrue(prepared.barlines.isEmpty,
                "\(context): a suffix flag must not be consumed as a new short measure boundary")
            let sample = Sample(drawing: drawing, barIndices: [],
                chords: [(Set(drawing.strokes.indices), "C7")])
            try assertChordTargets(prepared, sample: sample, context: context, requiresExpectedRead: false)
            try assertExactPartition(prepared, drawing: drawing, context: context)
        }
    }

    func testGentlyWavyHalfLaneSeparatorsKeepTheirOwnSourcesInEitherDirection() throws {
        for style in styles {
            let fixture = try makeFixture(style)
            for upward in [false, true] {
                let c = try captured("CCaptured01", fraction: 0.12, fixture: fixture, start: 0)
                let g = try captured("GCaptured01", fraction: 0.67, fixture: fixture, start: 0.12)
                let height = fixture.lane.height * 0.50
                let center = fixture.lane.minX + fixture.lane.width * 0.45
                let top = fixture.lane.midY - height / 2
                let points = [CGPoint(x: center, y: top),
                    CGPoint(x: center + 1.2, y: top + height * 0.25),
                    CGPoint(x: center - 1.2, y: top + height * 0.50),
                    CGPoint(x: center + 1.2, y: top + height * 0.75),
                    CGPoint(x: center, y: top + height)]
                let bar = stroke(upward ? Array(points.reversed()) : points, fixture: fixture, start: 0.06)
                let drawing = try canonical(PKDrawing(strokes: c + [bar] + g))
                let prepared = prepare(drawing, fixture: fixture)
                let sample = Sample(drawing: drawing, barIndices: [c.count],
                    chords: [(Set(0..<c.count), "C"), (Set((c.count + 1)..<drawing.strokes.count), "G")])
                let context = "\(style) gently wavy half-lane upward=\(upward)"
                XCTAssertEqual(prepared.barlines.count, 1, context)
                XCTAssertEqual(Set(prepared.barlines.flatMap(\.ownedSourceStrokeIndices)), sample.barIndices, context)
                try assertChordTargets(prepared, sample: sample, context: context)
                try assertExactPartition(prepared, drawing: drawing, context: context)
            }
        }
    }

    func testHalfLaneOpeningAndClosingBarsCreateOneBlankMeasureWithoutChordInk() throws {
        for style in styles {
            let fixture = try makeFixture(style)
            for upward in [false, true] {
                for kind in [DraftBarlineKind.single, .double] {
                    var strokes: [PKStroke] = []
                    for (index, fraction) in [CGFloat(0.20), 0.75].enumerated() {
                        strokes.append(divider(height: 0.50, position: .centered, upward: upward,
                            slope: 0, fixture: fixture, fraction: fraction, offset: 0,
                            start: Double(index) * 0.12))
                        if kind == .double {
                            strokes.append(divider(height: 0.50, position: .centered, upward: upward,
                                slope: 0, fixture: fixture, fraction: fraction, offset: 7,
                                start: Double(index) * 0.12 + 0.06))
                        }
                    }
                    let drawing = try canonical(PKDrawing(strokes: strokes))
                    let prepared = prepare(drawing, fixture: fixture)
                    let context = "\(style) blank half-lane \(kind) upward=\(upward)"
                    XCTAssertEqual(prepared.barlines.map(\.kind), [kind, kind], context)
                    XCTAssertEqual(prepared.recognitionStrokeCount, 0, context)
                    XCTAssertEqual(Set(prepared.barlines.flatMap(\.ownedSourceStrokeIndices)), Set(strokes.indices), context)
                    try assertExactPartition(prepared, drawing: drawing, context: context)
                    var chart = fixture.chart
                    _ = chart.setPageHandwrittenChordDrawing(drawing.dataRepresentation(),
                        coordinateSpace: .init(size: fixture.frame.size))
                    let state = ChordPreviewState(draftBarlines: prepared.barlines,
                        layoutPageSize: fixture.layout.pageBounds.size)
                    let result = chart.commitChordInkDraftBatch(state)
                    XCTAssertFalse(result.didRejectIncompleteSourceCoverage, context)
                    XCTAssertTrue(result.unresolvedDraftIDs.isEmpty, context)
                    XCTAssertEqual(result.renderedBarlineCount, 2, context)
                    XCTAssertEqual(result.renderedChordCount, 0, context)
                    XCTAssertNil(chart.pageHandwrittenChordData, context)
                    // Done finishes the writing row and removes its still-
                    // open tail placeholder; committing the two boundaries
                    // alone deliberately leaves that writing continuation.
                    XCTAssertTrue(chart.finishPaperWritingRows(), context)
                    let row = chart.measures.filter { $0.paperLayout?.rowIndex == 0 }
                    XCTAssertEqual(row.count, 1, context)
                    XCTAssertEqual(row.first?.paperLayout?.leadingBarline, kind == .double ? .double : .single, context)
                    XCTAssertEqual(row.first?.barlineAfter, kind == .double ? .double : .single, context)
                    let expectedOffset = kind == .double ? 3.5 / fixture.lane.width : 0
                    XCTAssertEqual(try XCTUnwrap(row.first?.paperLayout).startFraction,
                        Double(0.20 + expectedOffset), accuracy: 0.001, context)
                    XCTAssertEqual(try XCTUnwrap(row.first?.paperLayout).endFraction,
                        Double(0.75 + expectedOffset), accuracy: 0.001, context)
                    let reopened = try ChartPersistenceCoders.decoder.decode(Chart.self,
                        from: ChartPersistenceCoders.encoder.encode(chart))
                    XCTAssertEqual(reopened, chart, context)
                }
            }
        }
    }

    private let styles: [ChartLayoutStyle] = [.simpleChordSheet, .rhythmSectionSheet]
    private enum Position: CaseIterable { case centered, upper, lower }
    private struct Fixture {
        let chart: Chart
        let style: ChartLayoutStyle
        let layout: LeadSheetPageLayout
        let frame: CGRect
        let lane: CGRect
    }
    private struct Sample {
        let drawing: PKDrawing
        let barIndices: Set<Int>
        let chords: [(indices: Set<Int>, text: String)]
    }

    private func makeFixture(_ style: ChartLayoutStyle) throws -> Fixture {
        var chart = Chart.draft(title: "Barline height contract", layoutStyle: style)
        chart.completeInitialSetup(title: chart.title, key: .cMajor,
            meter: .init(numerator: 4, denominator: 4), staffStyle: .fiveLine, startingMeasureCount: 1)
        XCTAssertTrue(chart.initializePaperWritingRows(count: 3))
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart,
            pageSize: .init(width: 1_000, height: 1_400), includesChordInkContinuationLanes: true)
        let system = try XCTUnwrap(layout.systems.first)
        let lane = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingSystemLaneFrame(
            for: system, paperFrame: layout.paperFrame(for: system)))
        return Fixture(chart: chart, style: style, layout: layout,
            frame: LeadSheetActiveInkScope.chordWritingFrame(for: layout), lane: lane)
    }

    private func mixedSample(height: CGFloat, position: Position, upward: Bool,
        kind: DraftBarlineKind, slope: CGFloat = 0, fixture: Fixture) throws -> Sample {
        let c = try captured("CCaptured01", fraction: 0.12, fixture: fixture, start: 0)
        let first = divider(height: height, position: position, upward: upward,
            slope: slope, fixture: fixture, offset: 0, start: 0.06)
        let bars = kind == .double ? [first, divider(height: height, position: position,
            upward: upward, slope: slope, fixture: fixture, offset: 7, start: 0.12)] : [first]
        let g = try captured("GCaptured01", fraction: 0.67, fixture: fixture, start: 0.24)
        let drawing = try canonical(PKDrawing(strokes: c + bars + g))
        return Sample(drawing: drawing, barIndices: Set(c.count..<(c.count + bars.count)),
            chords: [(Set(0..<c.count), "C"),
                     (Set((c.count + bars.count)..<drawing.strokes.count), "G")])
    }

    private func divider(height ratio: CGFloat, position: Position, upward: Bool,
        slope: CGFloat, fixture: Fixture, fraction: CGFloat = 0.45, offset: CGFloat, start: Double) -> PKStroke {
        let height = fixture.lane.height * ratio
        let top: CGFloat
        switch position {
        case .centered: top = fixture.lane.midY - height / 2
        case .upper: top = fixture.lane.minY + fixture.lane.height * 0.02
        case .lower: top = fixture.lane.maxY - fixture.lane.height * 0.02 - height
        }
        let centerX = fixture.lane.minX + fixture.lane.width * fraction + offset
        let points = [CGPoint(x: centerX - slope * height / 2, y: top),
                      CGPoint(x: centerX + slope * height / 2, y: top + height)]
        return stroke(upward ? Array(points.reversed()) : points, fixture: fixture, start: start)
    }

    private func captured(_ name: String, fraction: CGFloat, fixture: Fixture, start: Double,
        height: CGFloat? = nil) throws -> [PKStroke] {
        let source = try InkFixtureLoader.load(name, file: #filePath).strokes
        let bounds = InkBounds.enclosing(source.map(\.bounds))
        let scale = (height ?? fixture.lane.height * 0.54) / CGFloat(bounds.height)
        let left = fixture.lane.minX + fixture.lane.width * fraction
        return source.enumerated().map { index, part in
            stroke(part.points.map {
                CGPoint(x: left + CGFloat($0.x - bounds.minX) * scale,
                    y: fixture.lane.midY + CGFloat($0.y - (bounds.minY + bounds.maxY) / 2) * scale)
            }, fixture: fixture, start: start + Double(index) * 0.06)
        }
    }

    private func stroke(_ locations: [CGPoint], fixture: Fixture, start: Double) -> PKStroke {
        let points = locations.enumerated().map { index, point in
            PKStrokePoint(location: .init(x: point.x - fixture.frame.minX, y: point.y - fixture.frame.minY),
                timeOffset: Double(index) * 0.04 / Double(max(1, locations.count - 1)),
                size: .init(width: 2, height: 2), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: LeadSheetPersistentInkColorPolicy.inkColor),
            path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSinceReferenceDate: 10_000 + start)))
    }

    private func canonical(_ drawing: PKDrawing) throws -> PKDrawing {
        try PKDrawing(data: drawing.dataRepresentation())
    }

    private func prepare(_ drawing: PKDrawing, fixture: Fixture) -> ChordInkRecognitionPreparationResult {
        ChordInkRecognitionPreparation.prepare(.init(requestID: UUID(), scheduledAt: Date(), requestedDelay: 0,
            drawingData: drawing.dataRepresentation(), chordFrame: fixture.frame, pageLayout: fixture.layout,
            flow: .draftPreview, options: .live, layoutStyle: fixture.style))
    }

    private func assertChordTargets(_ prepared: ChordInkRecognitionPreparationResult, sample: Sample,
        context: String, requiresExpectedRead: Bool = true,
        file: StaticString = #filePath, line: UInt = #line) throws {
        guard case .ready(let requests, _) = prepared.outcome else {
            return XCTFail("\(context): expected chord targets, got \(prepared.outcome)", file: file, line: line)
        }
        XCTAssertEqual(requests.count, sample.chords.count, context, file: file, line: line)
        guard requests.count == sample.chords.count else { return }
        for (request, expected) in zip(requests, sample.chords) {
            let source = PKDrawing(strokes: expected.indices.sorted().map { sample.drawing.strokes[$0] })
            let delivered = try PKDrawing(data: request.drawingData)
            XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: source, current: delivered),
                "\(context): target must retain exactly its source strokes", file: file, line: line)
            let result = ChordInkMaximumTrustRecognizer().recognize(strokes: request.strokes, options: .live)
            if requiresExpectedRead {
                XCTAssertEqual(result.match?.displayText, expected.text,
                    "\(context): actual reader must match the written chord", file: file, line: line)
            } else {
                let isolated = ChordInkMaximumTrustRecognizer().recognize(
                    strokes: PencilKitInkAdapter.inkStrokes(from: source), options: .live)
                XCTAssertEqual(result.match, isolated.match,
                    "\(context): structural routing must preserve the isolated reader result", file: file, line: line)
                if isolated.match?.displayText != expected.text {
                    print("BARLINE_HEIGHT_NEGATIVE_READER_LIMITATION", context,
                        "expected", expected.text, "isolated", isolated.match?.displayText ?? "nil",
                        "prepared", result.match?.displayText ?? "nil")
                }
            }
        }
        let expectedVisibleCount = sample.chords.reduce(0) { count, expected in
            count + expected.indices.reduce(0) {
                $0 + PencilKitInkAdapter.visibleStrokeFragments(from: sample.drawing.strokes[$1]).count
            }
        }
        XCTAssertEqual(prepared.recognitionStrokeCount, expectedVisibleCount,
            context, file: file, line: line)
    }

    private func assertExactPartition(_ prepared: ChordInkRecognitionPreparationResult, drawing: PKDrawing,
        context: String, file: StaticString = #filePath, line: UInt = #line) throws {
        var represented: [PKStroke] = []
        if case .ready(let requests, _) = prepared.outcome {
            for request in requests { represented.append(contentsOf: try PKDrawing(data: request.drawingData).strokes) }
        }
        let indices = prepared.barlines.flatMap { $0.ownedSourceStrokeIndices.sorted() }
        XCTAssertEqual(indices.count, Set(indices).count,
            "\(context): structural source ownership must be unique", file: file, line: line)
        XCTAssertTrue(indices.allSatisfy(drawing.strokes.indices.contains), context, file: file, line: line)
        if indices.allSatisfy(drawing.strokes.indices.contains) {
            represented.append(contentsOf: indices.map { drawing.strokes[$0] })
        }
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(
            expected: drawing, current: PKDrawing(strokes: represented)),
            "\(context): every visible stroke must remain represented exactly once", file: file, line: line)
    }
}
#endif
