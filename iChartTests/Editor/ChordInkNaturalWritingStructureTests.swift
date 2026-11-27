#if canImport(UIKit) && canImport(PencilKit)
import CoreGraphics
import PencilKit
import UIKit
import XCTest
@testable import iChart

/// Progressive source replays exercise structure/target ownership with the real
/// recognizer. They do not establish fresh-writer or physical-Pencil accuracy.
final class ChordInkNaturalWritingStructureTests: XCTestCase {
    func testLaneSpanningSlantedDividerStaysStructuralWhileNeighboringChordsArrive() throws {
        for style in styles {
            let fixture = try makeFixture(style)
            for gap in [0.06, 0.30] {
                for slope in [-0.32, 0.32] {
                    let g = try captured("GCaptured01", height: fixture.lane.height * 0.54,
                        left: fixture.lane.minX + fixture.lane.width * 0.12,
                        centerY: fixture.lane.midY, fixture: fixture, start: 0, gap: gap)
                    let divider = line(in: fixture, fraction: 0.40, slope: slope,
                        start: Double(g.count) * gap)
                    let c = try captured("CCaptured01", height: fixture.lane.height * 0.54,
                        left: fixture.lane.minX + fixture.lane.width * 0.62,
                        centerY: fixture.lane.midY, fixture: fixture,
                        start: Double(g.count + 1) * gap, gap: gap)
                    let sequence = g + [divider] + c
                    for count in g.count...sequence.count {
                        let drawing = PKDrawing(strokes: Array(sequence.prefix(count)))
                        let prepared = prepare(drawing, fixture: fixture)
                        let expectedBarIndices: Set<Int> = count > g.count ? [g.count] : []
                        XCTAssertEqual(Set(prepared.barlines.flatMap(\.ownedSourceStrokeIndices)),
                            expectedBarIndices, "\(style) gap=\(gap) slope=\(slope) prefix=\(count)")
                        if count == g.count || count == sequence.count {
                            try assertChordSources(prepared, expected: count == g.count ? [g] : [g, c],
                                texts: count == g.count ? ["G"] : ["G", "C"])
                        }
                    }
                }
            }
        }
    }

    func testWavyDividerDoesNotBecomeChordInkWhenASecondDistinctRootArrives() throws {
        for style in styles {
            let fixture = try makeFixture(style)
            let height = fixture.lane.height * 0.94
            let center = fixture.lane.minX + fixture.lane.width * 0.46
            let divider = stroke([
                CGPoint(x: center, y: fixture.lane.midY - height / 2),
                CGPoint(x: center + height * 0.09, y: fixture.lane.midY - height * 0.25),
                CGPoint(x: center - height * 0.09, y: fixture.lane.midY),
                CGPoint(x: center + height * 0.09, y: fixture.lane.midY + height * 0.25),
                CGPoint(x: center, y: fixture.lane.midY + height / 2)
            ], fixture: fixture, start: 0.20)
            let gap = height * 0.12
            let c = try captured("CCaptured01", height: height * 0.64,
                right: center - height * 0.09 - gap, centerY: fixture.lane.midY,
                fixture: fixture, start: 0, gap: 0.06)
            let g = try captured("GCaptured01", height: height * 0.64,
                left: center + height * 0.09 + gap, centerY: fixture.lane.midY,
                fixture: fixture, start: 0.30, gap: 0.06)
            let sequence = c + [divider] + g
            for count in (c.count + 1)...sequence.count {
                let prepared = prepare(PKDrawing(strokes: Array(sequence.prefix(count))), fixture: fixture)
                XCTAssertEqual(Set(prepared.barlines.flatMap(\.ownedSourceStrokeIndices)), [c.count],
                    "\(style) prefix=\(count): a separate later root must not reclaim the divider")
                if count == sequence.count {
                    try assertChordSources(prepared, expected: [c, g], texts: ["C", "G"])
                }
            }
        }
    }

    func testSmallCapturedRootsAroundTallDividerDoNotBecomeDotSlashDot() throws {
        for style in styles {
            let fixture = try makeFixture(style)
            let height = min(34, fixture.lane.height * 0.54)
            let c = try captured("CCaptured01", height: height,
                left: fixture.lane.minX + fixture.lane.width * 0.12,
                centerY: fixture.lane.midY, fixture: fixture, start: 0, gap: 0.06)
            let divider = line(in: fixture, fraction: 0.40, slope: 0.32, start: 0.10)
            let g = try captured("GCaptured01", height: height,
                left: fixture.lane.minX + fixture.lane.width * 0.65,
                centerY: fixture.lane.midY, fixture: fixture, start: 0.20, gap: 0.06)
            let prepared = prepare(PKDrawing(strokes: c + [divider] + g), fixture: fixture)
            XCTAssertEqual(Set(prepared.barlines.flatMap(\.ownedSourceStrokeIndices)), [c.count], style.rawValue)
            try assertChordSources(prepared, expected: [c, g], texts: ["C", "G"])
        }
    }

    func testTallCapturedChordStemsRemainWithTheirCompletedBodies() throws {
        for style in styles {
            let fixture = try makeFixture(style)
            for name in ["BCaptured01", "DCaptured01", "FCaptured01"] {
                let document = try InkFixtureLoader.load(name)
                let source = try captured(name, height: fixture.lane.height * 0.88,
                    left: fixture.lane.minX + fixture.lane.width * 0.32,
                    centerY: fixture.lane.midY, fixture: fixture, start: 0, gap: 0.06)
                // A first stem alone can be ambiguous; it must be reassigned
                // to its root when the later body/arms establish ownership.
                for count in 1...source.count {
                    _ = prepare(PKDrawing(strokes: Array(source.prefix(count))), fixture: fixture)
                }
                let prepared = prepare(PKDrawing(strokes: source), fixture: fixture)
                XCTAssertTrue(prepared.barlines.isEmpty, "\(style) \(name)")
                try assertChordSources(prepared, expected: [source], texts: [document.expectedDisplayText])
            }
        }
    }

    func testCapturedPercentAndSlashBassKeepTheirEntireSource() throws {
        for style in styles {
            let fixture = try makeFixture(style)
            for name in ["ChordRepeatCaptured01", "GSlashBCaptured01"] {
                let document = try InkFixtureLoader.load(name)
                let source = try captured(name, height: fixture.lane.height * 0.80,
                    left: fixture.lane.minX + fixture.lane.width * 0.30,
                    centerY: fixture.lane.midY, fixture: fixture, start: 0, gap: 0.06)
                let prepared = prepare(PKDrawing(strokes: source), fixture: fixture)
                XCTAssertTrue(prepared.barlines.isEmpty, "\(style) \(name)")
                try assertChordSources(prepared, expected: [source], texts: [document.expectedDisplayText])
            }
        }
    }

    func testSteepCapturedPercentKeepsItsSlashAndDotsDuringMixedWriting() throws {
        for style in styles {
            let fixture = try makeFixture(style)
            let percent = compactDots(try captured("ChordRepeatCaptured01", height: fixture.lane.height * 0.94,
                left: fixture.lane.minX + fixture.lane.width * 0.40,
                centerY: fixture.lane.midY, fixture: fixture, start: 0.12, gap: 0.06,
                horizontalScale: 0.73))
            let g = try captured("GCaptured01", height: fixture.lane.height * 0.54,
                left: fixture.lane.minX + fixture.lane.width * 0.10,
                centerY: fixture.lane.midY, fixture: fixture, start: 0, gap: 0.06)
            let c = try captured("CCaptured01", height: fixture.lane.height * 0.54,
                left: fixture.lane.minX + fixture.lane.width * 0.75,
                centerY: fixture.lane.midY, fixture: fixture, start: 0.35, gap: 0.06)
            let isolated = prepare(PKDrawing(strokes: percent), fixture: fixture)
            XCTAssertTrue(isolated.barlines.isEmpty, "\(style): compact dot/slash/dot remains a chord repeat")
            try assertChordSources(isolated, expected: [percent], texts: [ChordSymbol.chordRepeatDisplayText])
            let mixed = prepare(PKDrawing(strokes: g + percent + c), fixture: fixture)
            XCTAssertTrue(mixed.barlines.isEmpty, "\(style): neighboring roots do not change percent ownership")
            try assertChordSources(mixed, expected: [g, percent, c],
                texts: ["G", ChordSymbol.chordRepeatDisplayText, "C"])
        }
    }

    func testCompactDotsBesideADoubleBarlineDoNotTurnItIntoAChordRepeat() throws {
        for style in styles {
            let fixture = try makeFixture(style)
            let height = fixture.lane.height * 0.94
            let x = fixture.lane.minX + fixture.lane.width * 0.40
            let first = line(in: fixture, fraction: 0.40, slope: 0, start: 0)
            let second = line(in: fixture, fraction: (x + 7 - fixture.lane.minX) / fixture.lane.width,
                slope: 0, start: 0.06)
            let dots = [-0.16, 0.16].enumerated().map { index, offset in
                stroke([
                    CGPoint(x: x + 16, y: fixture.lane.midY + height * offset),
                    CGPoint(x: x + 21, y: fixture.lane.midY + height * offset + 3),
                    CGPoint(x: x + 17, y: fixture.lane.midY + height * offset + 5)
                ], fixture: fixture, start: 0.12 + Double(index) * 0.06)
            }
            let prepared = prepare(PKDrawing(strokes: [first, second] + dots), fixture: fixture)
            XCTAssertEqual(prepared.barlines.map(\.kind), [.double], style.rawValue)
            XCTAssertEqual(Set(prepared.barlines.flatMap(\.ownedSourceStrokeIndices)), [0, 1], style.rawValue)
        }
    }

    func testRetracedSteepPercentSourcesAreNeverClaimedAsBarlines() throws {
        for style in styles {
            let fixture = try makeFixture(style)
            let percent = compactDots(try captured("ChordRepeatCaptured01", height: fixture.lane.height * 0.94,
                left: fixture.lane.minX + fixture.lane.width * 0.40,
                centerY: fixture.lane.midY, fixture: fixture, start: 0, gap: 0.06,
                horizontalScale: 0.73))
            XCTAssertEqual(percent.count, 3)
            for sourceCount in [9, 18] {
                let leftCount = (sourceCount - 1) / 2
                let rightCount = sourceCount - leftCount - 1
                let dots: [(stroke: PKStroke, offset: CGFloat)] = (0..<leftCount).map {
                    (percent[0], CGFloat($0) * 0.08)
                } + (0..<rightCount).map { (percent[2], CGFloat($0) * 0.08) }
                for slashFirst in [true, false] {
                    // Neither order contains a consecutive three-source
                    // dot/slash/dot window. This exercises logical-dot
                    // ownership rather than the simple three-source guard.
                    let ordered = slashFirst ? [(percent[1], CGFloat(0))] + dots
                        : dots + [(percent[1], CGFloat(0))]
                    let source = ordered.enumerated().map {
                        retimedCopy($0.element.0, ordinal: $0.offset, offset: $0.element.1)
                    }
                    let prepared = prepare(PKDrawing(strokes: source), fixture: fixture)
                    XCTAssertTrue(prepared.barlines.isEmpty,
                        "\(style), \(sourceCount) sources, slashFirst=\(slashFirst)")
                    XCTAssertEqual(prepared.recognitionStrokeCount, sourceCount)
                    let ownership = try XCTUnwrap(prepared.ownershipSnapshot)
                    XCTAssertTrue(ownership.barlineVisibleFragmentIndices.isEmpty)
                    XCTAssertEqual(ownership.visibleFragmentSourceStrokeIndices, Array(source.indices))
                    XCTAssertEqual((ownership.targetGroups.flatMap(\.visibleFragmentIndices)
                        + ownership.unassignedVisibleFragmentIndices).sorted(), Array(source.indices))
                }
            }
        }
    }

    func testNewWideAllowanceRequiresUnmaskedSourceWhileStrictMaskedBarsRemainSupported() throws {
        for style in styles {
            let fixture = try makeFixture(style)
            for slope: CGFloat in [0, 0.32] {
                let original = line(in: fixture, fraction: 0.40, slope: slope, start: 0)
                let unmasked = prepare(PKDrawing(strokes: [original]), fixture: fixture)
                XCTAssertEqual(unmasked.barlines.count, 1, style.rawValue)
                XCTAssertEqual(unmasked.barlines.first?.requiresCompleteUnmaskedSource, slope != 0)
                let masked = PKStroke(ink: original.ink, path: original.path,
                    mask: UIBezierPath(rect: original.renderBounds.insetBy(dx: -4, dy: -4)))
                let prepared = prepare(PKDrawing(strokes: [masked]), fixture: fixture)
                XCTAssertEqual(prepared.visibleStrokeCount, 1, style.rawValue)
                XCTAssertEqual(prepared.barlines.count, slope == 0 ? 1 : 0, style.rawValue)
                XCTAssertEqual(prepared.recognitionStrokeCount, slope == 0 ? 0 : 1, style.rawValue)
            }
        }
    }

    private let styles: [ChartLayoutStyle] = [.simpleChordSheet, .rhythmSectionSheet]

    private struct Fixture {
        var style: ChartLayoutStyle
        var layout: LeadSheetPageLayout
        var chordFrame: CGRect
        var lane: CGRect
    }

    private func makeFixture(_ style: ChartLayoutStyle) throws -> Fixture {
        var chart = Chart.draft(title: "Natural mixed writing", layoutStyle: style)
        chart.completeInitialSetup(title: chart.title, key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4), staffStyle: .fiveLine,
            startingMeasureCount: 1)
        XCTAssertTrue(chart.initializePaperWritingRows(count: 3))
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart,
            pageSize: CGSize(width: 1_000, height: 1_400), includesChordInkContinuationLanes: true)
        let system = try XCTUnwrap(layout.systems.first)
        let lane = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingSystemLaneFrame(
            for: system, paperFrame: layout.paperFrame(for: system)))
        return Fixture(style: style, layout: layout,
            chordFrame: LeadSheetActiveInkScope.chordWritingFrame(for: layout), lane: lane)
    }

    private func prepare(_ drawing: PKDrawing, fixture: Fixture) -> ChordInkRecognitionPreparationResult {
        ChordInkRecognitionPreparation.prepare(.init(requestID: UUID(), scheduledAt: Date(),
            requestedDelay: 0, drawingData: drawing.dataRepresentation(), chordFrame: fixture.chordFrame,
            pageLayout: fixture.layout, flow: .draftPreview, options: .live, layoutStyle: fixture.style))
    }

    private func assertChordSources(_ prepared: ChordInkRecognitionPreparationResult,
        expected: [[PKStroke]], texts: [String], file: StaticString = #filePath, line: UInt = #line) throws {
        guard case .ready(let requests, _) = prepared.outcome else {
            XCTFail("Expected chord targets, got \(prepared.outcome)", file: file, line: line)
            return
        }
        XCTAssertEqual(requests.count, expected.count, file: file, line: line)
        guard requests.count == expected.count else { return }
        // The preparation API receives a serialized drawing. PencilKit can
        // canonicalize affine matrix storage during that first encoding, so
        // compare exact persisted source rather than prearchive CGFloat bits.
        let canonicalSource = try PKDrawing(data: PKDrawing(strokes: expected.flatMap { $0 }).dataRepresentation())
        XCTAssertEqual(canonicalSource.strokes.count, expected.reduce(0) { $0 + $1.count }, file: file, line: line)
        var sourceOffset = 0
        for (index, request) in requests.enumerated() {
            let end = sourceOffset + expected[index].count
            let source = PKDrawing(strokes: Array(canonicalSource.strokes[sourceOffset..<end]))
            sourceOffset = end
            let delivered = try PKDrawing(data: request.drawingData)
            XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(
                expected: source, current: delivered),
                "Each chord must own exactly its original strokes", file: file, line: line)
            let isolated = try XCTUnwrap(ChordInkRecognizer().recognize(strokes:
                PencilKitInkAdapter.inkStrokes(from: source)).match,
                "The isolated source must establish a real reader control", file: file, line: line)
            let read = try XCTUnwrap(ChordInkRecognizer().recognize(strokes: request.strokes).match,
                file: file, line: line)
            XCTAssertEqual(read, isolated, "Structure preparation must preserve the isolated reader answer",
                file: file, line: line)
            let expectedSymbol = try XCTUnwrap(ChordRecognitionCompendium.match(texts[index])?.symbol,
                file: file, line: line)
            XCTAssertEqual(read.symbol.kind, expectedSymbol.kind, file: file, line: line)
            XCTAssertEqual(ChordPitch(root: read.symbol.root, accidental: read.symbol.accidental).semitone,
                ChordPitch(root: expectedSymbol.root, accidental: expectedSymbol.accidental).semitone,
                file: file, line: line)
            XCTAssertEqual(read.symbol.quality, expectedSymbol.quality, file: file, line: line)
            XCTAssertEqual(read.symbol.extensions, expectedSymbol.extensions, file: file, line: line)
            XCTAssertEqual(read.symbol.alterations, expectedSymbol.alterations, file: file, line: line)
            XCTAssertEqual(read.symbol.slashBass.flatMap(ChordPitch.parse)?.semitone,
                expectedSymbol.slashBass.flatMap(ChordPitch.parse)?.semitone, file: file, line: line)
        }
        XCTAssertEqual(prepared.recognitionStrokeCount, expected.reduce(0) { $0 + $1.count },
            file: file, line: line)
    }

    private func captured(_ name: String, height: CGFloat, left: CGFloat? = nil,
        right: CGFloat? = nil, centerY: CGFloat, fixture: Fixture, start: Double,
        gap: Double, horizontalScale: CGFloat = 1) throws -> [PKStroke] {
        let captured = try InkFixtureLoader.load(name).strokes
        let bounds = InkBounds.enclosing(captured.map(\.bounds))
        let scale = height / CGFloat(bounds.height)
        let x = left ?? ((right ?? fixture.lane.midX) - CGFloat(bounds.width) * scale * horizontalScale)
        return captured.enumerated().map { index, part in
            stroke(part.points.map {
                CGPoint(x: x + CGFloat($0.x - bounds.minX) * scale * horizontalScale,
                    y: centerY + CGFloat($0.y - (bounds.minY + bounds.maxY) / 2) * scale)
            }, fixture: fixture, start: start + Double(index) * gap)
        }
    }

    private func line(in fixture: Fixture, fraction: CGFloat, slope: CGFloat, start: Double) -> PKStroke {
        let height = fixture.lane.height * 0.94
        let x = fixture.lane.minX + fixture.lane.width * fraction
        return stroke([
            CGPoint(x: x - slope * height / 2, y: fixture.lane.midY - height / 2),
            CGPoint(x: x + slope * height / 2, y: fixture.lane.midY + height / 2)
        ], fixture: fixture, start: start)
    }

    /// Preserve normal Pencil contact size while stretching the slash to a
    /// full lane. Uniformly enlarging the dots tests a separate raw-reader
    /// size limit rather than the structural ownership boundary.
    private func compactDots(_ percent: [PKStroke]) -> [PKStroke] {
        percent.enumerated().map { index, source in
            guard index != 1 else { return source }
            let bounds = PencilKitInkAdapter.inkStroke(from: source, timelineOrigin: nil).bounds
            let factor = min(1, 10 / max(1, max(bounds.width, bounds.height)))
            let centerX = CGFloat((bounds.minX + bounds.maxX) / 2)
            let centerY = CGFloat((bounds.minY + bounds.maxY) / 2)
            let transform = CGAffineTransform(translationX: centerX, y: centerY)
                .scaledBy(x: factor, y: factor).translatedBy(x: -centerX, y: -centerY)
            return PKStroke(ink: source.ink, path: source.path,
                transform: source.transform.concatenating(transform))
        }
    }

    private func retimedCopy(_ source: PKStroke, ordinal: Int, offset: CGFloat) -> PKStroke {
        PKStroke(ink: source.ink,
            path: PKStrokePath(controlPoints: Array(source.path),
                creationDate: Date(timeIntervalSinceReferenceDate: 10_000 + Double(ordinal) * 0.06)),
            transform: source.transform.concatenating(CGAffineTransform(translationX: offset, y: offset)))
    }

    private func stroke(_ locations: [CGPoint], fixture: Fixture, start: Double) -> PKStroke {
        let points = locations.enumerated().map { index, point in
            PKStrokePoint(location: CGPoint(x: point.x - fixture.chordFrame.minX,
                    y: point.y - fixture.chordFrame.minY),
                timeOffset: Double(index) * 0.04 / Double(max(1, locations.count - 1)),
                size: CGSize(width: 2, height: 2), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: LeadSheetPersistentInkColorPolicy.inkColor),
            path: PKStrokePath(controlPoints: points,
                creationDate: Date(timeIntervalSinceReferenceDate: 10_000 + start)))
    }
}
#endif
