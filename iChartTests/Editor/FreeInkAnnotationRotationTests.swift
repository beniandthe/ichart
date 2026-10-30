#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import UIKit
import XCTest
@testable import iChart

/// Rotation changes the viewport, not the Free Ink document. Every source
/// control point and nib must keep its absolute paper-local geometry.
@MainActor
final class FreeInkAnnotationRotationTests: XCTestCase {
    func testUnanchoredPhrasePreservesLetterSpacingInBothRotationDirections() throws {
        let spaces = try coordinateSpaces()
        for (source, target) in [(spaces.wide, spaces.narrow), (spaces.narrow, spaces.wide)] {
            let original = phrase(x: 220, y: 700)
            let sourceBytes = original.dataRepresentation()
            let rotated = project(original, from: source, to: target)

            assertSameGeometry(original, rotated)
            XCTAssertEqual(original.dataRepresentation(), sourceBytes,
                "Display reprojection must not mutate the stored source drawing.")
        }
    }

    func testPhraseAcrossNeighboringMeasureAndChordHitRegionsMovesAsOneAnnotation() throws {
        let spaces = try coordinateSpaces()
        // Some letters lie above the chord, some above its measure, and the
        // last letters cross into the neighboring measure. Those invisible
        // musical hit regions must not pull one handwritten phrase apart.
        let original = phrase(x: 250, y: 200, count: 5)
        let rotated = project(original, from: spaces.wide, to: spaces.narrow)
        assertSameGeometry(original, rotated)

        let returned = project(rotated, from: spaces.narrow, to: spaces.wide)
        assertSameGeometry(original, returned)
    }

    func testRepeatedRotationDoesNotAccumulateSpacingOrPositionChanges() throws {
        let spaces = try coordinateSpaces()
        let original = phrase(x: 220, y: 700)
        var drawing = original
        for _ in 0..<8 {
            drawing = project(drawing, from: spaces.wide, to: spaces.narrow)
            assertSameGeometry(original, drawing)
            drawing = project(drawing, from: spaces.narrow, to: spaces.wide)
            assertSameGeometry(original, drawing)
        }
    }

    func testWidelySpacedWordsKeepTheirWhitespaceInBothRotationDirections() throws {
        let spaces = try coordinateSpaces()
        var narrow = spaces.narrow
        narrow.width = 550
        for (source, target, counts) in [(spaces.wide, narrow, [6, 9]), (narrow, spaces.wide, [6])] {
            for count in counts {
                let firstWord = phrase(x: 100, y: 700, count: count)
                let secondWord = phrase(x: firstWord.bounds.maxX + 90, y: 700, count: count)
                let original = PKDrawing(strokes: firstWord.strokes + secondWord.strokes)
                XCTAssertLessThan(original.bounds.maxX, source.width,
                    "The test words must start fully inside their source paper.")
                XCTAssertGreaterThan(secondWord.bounds.minX - firstWord.bounds.maxX, 80,
                    "The words must start with substantial whitespace.")
                let rotated = project(original, from: source, to: target)
                XCTAssertEqual(rotated.strokes.count, original.strokes.count)
                guard rotated.strokes.count == original.strokes.count else { return }
                assertSameGeometry(original, rotated)
                let firstRotatedWord = PKDrawing(strokes: Array(rotated.strokes.prefix(count)))
                let secondRotatedWord = PKDrawing(strokes: Array(rotated.strokes.suffix(count)))
                XCTAssertLessThan(firstRotatedWord.bounds.maxX, secondRotatedWord.bounds.minX,
                    "Rotation must not introduce overlap between separate handwritten words.")
            }
        }
    }

    func testSeparateAnnotationsRetainAbsolutePositionsWhenMusicalAnchorsMove() throws {
        let measureID = UUID()
        let firstChordID = UUID()
        let secondChordID = UUID()
        let source = PersistentInkCoordinateSpace(width: 1_100, height: 1_200,
            chordAnchors: [
                try XCTUnwrap(PersistentInkChordAnchor(measureID: measureID, chordID: firstChordID,
                    frame: CGRect(x: 110, y: 200, width: 50, height: 40))),
                try XCTUnwrap(PersistentInkChordAnchor(measureID: measureID, chordID: secondChordID,
                    frame: CGRect(x: 510, y: 440, width: 50, height: 40)))
            ])
        let target = PersistentInkCoordinateSpace(width: 700, height: 1_400,
            chordAnchors: [
                try XCTUnwrap(PersistentInkChordAnchor(measureID: measureID, chordID: firstChordID,
                    frame: CGRect(x: 210, y: 260, width: 50, height: 40))),
                try XCTUnwrap(PersistentInkChordAnchor(measureID: measureID, chordID: secondChordID,
                    frame: CGRect(x: 310, y: 520, width: 50, height: 40)))
            ])
        let first = phrase(x: 110, y: 180, count: 2)
        let second = phrase(x: 510, y: 420, count: 2)
        let original = PKDrawing(strokes: first.strokes + second.strokes)
        let rotated = project(original, from: source, to: target)
        XCTAssertEqual(rotated.strokes.count, 4)
        guard rotated.strokes.count == 4 else { return }

        assertSameGeometry(first, PKDrawing(strokes: Array(rotated.strokes.prefix(2))))
        assertSameGeometry(second, PKDrawing(strokes: Array(rotated.strokes.suffix(2))))
    }

    func testDirtyFreeInkRotationSaveAndReopenKeepsPhraseGeometryAcrossV1Styles() throws {
        let portrait = CGSize(width: 800, height: 1_400)
        let landscape = CGSize(width: 1_200, height: 1_200)
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet, .leadSheet] {
            for (sourceSize, targetSize) in [(landscape, portrait), (portrait, landscape)] {
                let host = try makeHost(chart: makeChart(style), pageSize: sourceSize, mode: .freeHand)
                defer { host.window.isHidden = true }
                let original = phrase(x: 220, y: 700)
                host.authoring.drawing = original
                host.view.canvasViewDrawingDidChange(host.authoring)

                // Rotate while the normal persistence delay is still pending.
                resize(host, to: targetSize)
                XCTAssertEqual(host.view.bounds.size, targetSize)
                let visible = host.authoring.drawing
                assertSameGeometry(original, visible)

                // Exiting Free Ink flushes the actual production canvas owner.
                host.view.interactionMode = .browse
                let savedChart = host.view.chart
                let data = try XCTUnwrap(savedChart.pageHandwrittenNotationData)
                let savedSpace = try XCTUnwrap(savedChart.pageHandwrittenNotationCoordinateSpace)
                let visibleLayout = LeadSheetPageLayoutEngine.pageLayout(for: savedChart, pageSize: targetSize)
                let visibleFrame = LeadSheetActiveInkScope.pageWritingFrame(for: visibleLayout)
                let visibleSpace = try XCTUnwrap(LeadSheetPersistentInkCoordinateSpacePolicy.pageCoordinateSpace(
                    for: visibleLayout, relativeTo: visibleFrame))
                let savedVisibleDrawing = project(try PKDrawing(data: data), from: savedSpace, to: visibleSpace)
                assertSameGeometry(visible, savedVisibleDrawing)

                let decoded = try ChartPersistenceCoders.decoder.decode(Chart.self,
                    from: ChartPersistenceCoders.encoder.encode(savedChart))
                let reopened = try makeHost(chart: decoded, pageSize: targetSize, mode: .freeHand)
                defer { reopened.window.isHidden = true }
                assertSameGeometry(visible, reopened.authoring.drawing)
                XCTAssertEqual(decoded.measures, savedChart.measures,
                    "Free Ink persistence must not edit musical content: \(style.rawValue)")
                XCTAssertEqual(decoded.pageHandwrittenNotationData, data)
            }
        }
    }

    func testOverwidePhraseKeepsOriginalPositionAndSizeOnFirstRotationAndReopen() throws {
        let landscape = CGSize(width: 1_200, height: 1_200)
        let portrait = CGSize(width: 800, height: 1_400)
        let originalChart = makeChart(.simpleChordSheet)
        let host = try makeHost(chart: originalChart, pageSize: landscape, mode: .freeHand)
        defer { host.window.isHidden = true }
        let original = phrase(x: 30, y: 700, count: 32)
        XCTAssertLessThan(original.bounds.maxX, host.authoring.bounds.width,
            "The test phrase must start fully inside its source paper.")
        host.authoring.drawing = original
        host.view.canvasViewDrawingDidChange(host.authoring)

        resize(host, to: portrait)
        XCTAssertGreaterThan(original.bounds.width, portrait.width + 100,
            "This case must exercise writing wider than the portrait viewport.")
        let visible = host.authoring.drawing
        assertSameGeometry(original, visible)
        var staleModel = originalChart
        staleModel.updatedAt = Date(timeIntervalSinceReferenceDate: 20)
        host.view.chart = staleModel
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        assertSameGeometry(visible, host.authoring.drawing)

        // A smaller viewport must not change the document's saved geometry.
        host.view.interactionMode = .browse
        let savedChart = host.view.chart
        let decoded = try ChartPersistenceCoders.decoder.decode(Chart.self,
            from: ChartPersistenceCoders.encoder.encode(savedChart))
        let reopened = try makeHost(chart: decoded, pageSize: landscape, mode: .freeHand)
        defer { reopened.window.isHidden = true }
        assertSameGeometry(original, reopened.authoring.drawing)
    }

    func testNeighboringAnnotationsStayAtTheirOriginalPositionsThroughoutRotation() throws {
        let landscape = CGSize(width: 1_200, height: 1_200)
        let portrait = CGSize(width: 800, height: 1_400)
        let chart = makeChart(.simpleChordSheet)
        let sourceLayout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: landscape)
        let pageFrame = LeadSheetActiveInkScope.pageWritingFrame(for: sourceLayout)
        let measures = try XCTUnwrap(sourceLayout.systems.first?.measures)
        XCTAssertGreaterThanOrEqual(measures.count, 2)
        guard measures.count >= 2 else { return }
        let firstFrame = measures[0].chordWritingFrame.offsetBy(dx: -pageFrame.minX, dy: -pageFrame.minY)
        let secondFrame = measures[1].chordWritingFrame.offsetBy(dx: -pageFrame.minX, dy: -pageFrame.minY)
        let first = phrase(x: firstFrame.minX + 10, y: firstFrame.minY - 25)
        let second = phrase(x: secondFrame.minX + 10, y: secondFrame.minY - 25)
        let original = PKDrawing(strokes: first.strokes + second.strokes)
        let host = try makeHost(chart: chart, pageSize: landscape, mode: .freeHand)
        defer { host.window.isHidden = true }
        host.authoring.drawing = original
        host.view.canvasViewDrawingDidChange(host.authoring)

        for iteration in 0..<4 {
            resize(host, to: portrait)
            let compact = host.authoring.drawing
            XCTAssertEqual(compact.strokes.count, original.strokes.count)
            guard compact.strokes.count == original.strokes.count else { return }
            assertSameGeometry(first, PKDrawing(strokes: Array(compact.strokes.prefix(first.strokes.count))))
            assertSameGeometry(second, PKDrawing(strokes: Array(compact.strokes.suffix(second.strokes.count))))
            var staleModel = chart
            staleModel.updatedAt = Date(timeIntervalSinceReferenceDate: Double(20 + iteration))
            host.view.chart = staleModel
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            assertSameGeometry(compact, host.authoring.drawing)
            resize(host, to: landscape)
            assertSameGeometry(original, host.authoring.drawing)
        }

        resize(host, to: portrait)
        host.view.interactionMode = .browse
        let savedChart = host.view.chart
        let decoded = try ChartPersistenceCoders.decoder.decode(Chart.self,
            from: ChartPersistenceCoders.encoder.encode(savedChart))
        let reopened = try makeHost(chart: decoded, pageSize: landscape, mode: .freeHand)
        defer { reopened.window.isHidden = true }
        assertSameGeometry(original, reopened.authoring.drawing)
    }

    func testErasingAndAppendingAfterRotationPersistsTheActualEditWithoutResurrectingInk() throws {
        let landscape = CGSize(width: 1_200, height: 1_200)
        let portrait = CGSize(width: 800, height: 1_400)
        let host = try makeHost(chart: makeChart(.simpleChordSheet), pageSize: landscape, mode: .freeHand)
        defer { host.window.isHidden = true }
        let original = phrase(x: 30, y: 700, count: 32)
        host.authoring.drawing = original
        host.view.canvasViewDrawingDidChange(host.authoring)
        resize(host, to: portrait)
        let rotated = host.authoring.drawing
        assertSameGeometry(original, rotated)

        let erasedSeed = original.strokes[10].randomSeed
        host.authoring.drawing = PKDrawing(strokes: rotated.strokes.filter { $0.randomSeed != erasedSeed })
        host.view.canvasViewDrawingDidChange(host.authoring)
        let addedTemplate = try XCTUnwrap(phrase(x: 80, y: 900, count: 1).strokes.first)
        let addedSeed = UInt32(9_001)
        let added = PKStroke(ink: addedTemplate.ink, path: addedTemplate.path,
            transform: addedTemplate.transform, mask: nil, randomSeed: addedSeed)
        host.authoring.drawing = PKDrawing(strokes: host.authoring.drawing.strokes + [added])
        host.view.canvasViewDrawingDidChange(host.authoring)
        let editedVisibleDrawing = host.authoring.drawing
        let expectedSeeds = editedVisibleDrawing.strokes.map(\.randomSeed)
        XCTAssertEqual(expectedSeeds.count, original.strokes.count)
        XCTAssertFalse(expectedSeeds.contains(erasedSeed))
        XCTAssertTrue(expectedSeeds.contains(addedSeed))

        host.view.interactionMode = .browse
        let savedChart = host.view.chart
        let savedDrawing = try PKDrawing(data: XCTUnwrap(savedChart.pageHandwrittenNotationData))
        XCTAssertEqual(savedDrawing.strokes.map(\.randomSeed), expectedSeeds,
            "The retained pre-rotation source must never replace actual drawing edits.")
        let decoded = try ChartPersistenceCoders.decoder.decode(Chart.self,
            from: ChartPersistenceCoders.encoder.encode(savedChart))
        let reopened = try makeHost(chart: decoded, pageSize: portrait, mode: .freeHand)
        defer { reopened.window.isHidden = true }
        assertSameGeometry(editedVisibleDrawing, reopened.authoring.drawing)

        for size in [landscape, portrait, landscape] {
            resize(reopened, to: size)
            XCTAssertEqual(reopened.authoring.drawing.strokes.map(\.randomSeed), expectedSeeds,
                "Rotation after editing must preserve both the erase and the new stroke.")
            let newStroke = try XCTUnwrap(reopened.authoring.drawing.strokes.first { $0.randomSeed == addedSeed })
            assertSameGeometry(PKDrawing(strokes: [added]), PKDrawing(strokes: [newStroke]))
        }
        resize(reopened, to: portrait)
        assertSameGeometry(editedVisibleDrawing, reopened.authoring.drawing)
    }

    func testSavedPassiveInkAndExportRendererAgreeAfterRotationWithoutRewritingSource() throws {
        let sourceSize = CGSize(width: 1_200, height: 1_200)
        let targetSize = CGSize(width: 800, height: 1_400)
        var chart = makeChart(.simpleChordSheet)
        let sourceLayout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: sourceSize)
        let sourceFrame = LeadSheetActiveInkScope.pageWritingFrame(for: sourceLayout)
        let original = phrase(x: 220, y: 700)
        let sourceBytes = original.dataRepresentation()
        chart.pageHandwrittenNotationData = sourceBytes
        chart.pageHandwrittenNotationCoordinateSpace = LeadSheetPersistentInkCoordinateSpacePolicy.pageCoordinateSpace(
            for: sourceLayout, relativeTo: sourceFrame)

        let host = try makeHost(chart: chart, pageSize: targetSize, mode: .browse)
        defer { host.window.isHidden = true }
        XCTAssertTrue(waitForMainRunLoop {
            !host.passive.isHidden && host.passive.drawing.strokes.count == original.strokes.count
        }, "The saved vector canvas must complete its asynchronous load.")
        let passiveDrawing = host.passive.drawing
        assertSameGeometry(original, passiveDrawing)
        XCTAssertEqual(host.view.chart.pageHandwrittenNotationData, sourceBytes,
            "Passive rotation must preserve the original archive.")

        let targetLayout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: targetSize)
        let targetFrame = LeadSheetActiveInkScope.pageWritingFrame(for: targetLayout)
        let targetSpace = try XCTUnwrap(LeadSheetPersistentInkCoordinateSpacePolicy.pageCoordinateSpace(
            for: targetLayout, relativeTo: targetFrame))
        let exported = try XCTUnwrap(LeadSheetSavedInkRenderer.renderedInkImage(sourceBytes,
            size: targetFrame.size,
            sourceCoordinateSpace: chart.pageHandwrittenNotationCoordinateSpace,
            targetCoordinateSpace: targetSpace, scale: 1))
        let visible = try XCTUnwrap(LeadSheetSavedInkRenderer.renderedInkImage(passiveDrawing.dataRepresentation(),
            size: targetFrame.size, sourceCoordinateSpace: targetSpace,
            targetCoordinateSpace: targetSpace, scale: 1))
        XCTAssertEqual(exported.pngData(), visible.pngData(),
            "The shared PDF ink renderer must produce the same geometry as the passive canvas.")
        let sourcePreview = XCTAttachment(image: original.image(from: original.bounds.insetBy(dx: -10, dy: -10), scale: 2))
        sourcePreview.name = "Synthetic multi-stroke phrase before rotation"
        sourcePreview.lifetime = .keepAlways
        add(sourcePreview)
        let rotatedPreview = XCTAttachment(image: passiveDrawing.image(
            from: passiveDrawing.bounds.insetBy(dx: -10, dy: -10), scale: 2))
        rotatedPreview.name = "Synthetic multi-stroke phrase after rotation"
        rotatedPreview.lifetime = .keepAlways
        add(rotatedPreview)
    }

    func testOptionalCurrentLibraryAffectedChartKeepsSourceInkAcrossRotationAndReopen() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fixtureURL = root.appendingPathComponent(
            ".build/notation-preservation-fixtures/Library/Application Support/iChart/library-state.json")
        guard FileManager.default.fileExists(atPath: fixtureURL.path) else {
            throw XCTSkip("Optional current-device library fixture is not present.")
        }
        let originalFixtureBytes = try Data(contentsOf: fixtureURL)
        let snapshot = try XCTUnwrap(try FileChartRepository(url: fixtureURL).loadSnapshot())
        guard let chart = snapshot.charts.first(where: { $0.title == "Becoming" }) else {
            throw XCTSkip("The affected chart is not in the optional current-device fixture.")
        }
        let originalInkBytes = try XCTUnwrap(chart.pageHandwrittenNotationData)
        let originalSpace = try XCTUnwrap(chart.pageHandwrittenNotationCoordinateSpace)
        let sourceDrawing = try PKDrawing(data: originalInkBytes)
        XCTAssertFalse(sourceDrawing.strokes.isEmpty)
        let portrait = CGSize(width: 800, height: 1_400)
        let landscape = CGSize(width: 1_200, height: 1_200)
        let portraitHost = try makeHost(chart: chart, pageSize: portrait, mode: .freeHand)
        defer { portraitHost.window.isHidden = true }
        let portraitDrawing = portraitHost.authoring.drawing
        XCTAssertEqual(portraitDrawing.strokes.count, sourceDrawing.strokes.count)
        assertSameGeometry(sourceDrawing, portraitDrawing)
        portraitHost.view.interactionMode = .browse
        let savedChart = portraitHost.view.chart
        XCTAssertTrue(savedChart.pageHandwrittenNotationData == originalInkBytes,
            "Opening and leaving Free Ink in portrait must preserve the saved source archive.")
        XCTAssertTrue(savedChart.pageHandwrittenNotationCoordinateSpace == originalSpace,
            "Display-only rotation must retain the saved source coordinate space.")

        let reopenedChart = try ChartPersistenceCoders.decoder.decode(Chart.self,
            from: ChartPersistenceCoders.encoder.encode(savedChart))
        let reopened = try makeHost(chart: reopenedChart, pageSize: landscape, mode: .freeHand)
        defer { reopened.window.isHidden = true }
        let landscapeDrawing = reopened.authoring.drawing
        XCTAssertEqual(landscapeDrawing.strokes.count, sourceDrawing.strokes.count)
        assertSameGeometry(sourceDrawing, landscapeDrawing)
        for size in [portrait, landscape, portrait, landscape] {
            resize(reopened, to: size)
            assertSameGeometry(sourceDrawing,
                reopened.authoring.drawing)
            reopened.view.interactionMode = .browse
            XCTAssertTrue(reopened.view.chart.pageHandwrittenNotationData == originalInkBytes,
                "Repeated rotation and Free Ink exits must not rewrite source strokes.")
            XCTAssertTrue(reopened.view.chart.pageHandwrittenNotationCoordinateSpace == originalSpace,
                "Repeated rotation and Free Ink exits must retain source coordinates.")
            reopened.view.interactionMode = .freeHand
            assertSameGeometry(sourceDrawing,
                reopened.authoring.drawing)
        }
        XCTAssertTrue(try Data(contentsOf: fixtureURL) == originalFixtureBytes,
            "The current-device library fixture must remain read-only.")

        // Private evidence stays in ignored .build. Never attach this actual
        // user ink to the test result or add it to committed QA screenshots.
        let previewDirectory = root.appendingPathComponent(".build/free-ink-private-replay-becoming", isDirectory: true)
        try FileManager.default.createDirectory(at: previewDirectory, withIntermediateDirectories: true)
        try writePrivateReplayPreview(sourceDrawing, size: originalSpace.size,
            to: previewDirectory.appendingPathComponent("source-ink.png"))
        try writePrivateReplayPreview(portraitDrawing, size: portraitHost.authoring.bounds.size,
            to: previewDirectory.appendingPathComponent("portrait-ink.png"))
        try writePrivateReplayPreview(landscapeDrawing, size: reopened.authoring.bounds.size,
            to: previewDirectory.appendingPathComponent("landscape-ink.png"))
    }

    private func coordinateSpaces() throws -> (wide: PersistentInkCoordinateSpace, narrow: PersistentInkCoordinateSpace) {
        let firstMeasure = UUID()
        let secondMeasure = UUID()
        let chord = UUID()
        let wide = PersistentInkCoordinateSpace(width: 1_100, height: 1_200,
            measureAnchors: [
                try XCTUnwrap(PersistentInkMeasureAnchor(measureID: firstMeasure,
                    frame: CGRect(x: 80, y: 180, width: 240, height: 72))),
                try XCTUnwrap(PersistentInkMeasureAnchor(measureID: secondMeasure,
                    frame: CGRect(x: 320, y: 180, width: 240, height: 72)))
            ], chordAnchors: [
                try XCTUnwrap(PersistentInkChordAnchor(measureID: firstMeasure, chordID: chord,
                    frame: CGRect(x: 260, y: 220, width: 30, height: 40)))
            ])
        let narrow = PersistentInkCoordinateSpace(width: 700, height: 1_400,
            measureAnchors: [
                try XCTUnwrap(PersistentInkMeasureAnchor(measureID: firstMeasure,
                    frame: CGRect(x: 80, y: 180, width: 140, height: 72))),
                try XCTUnwrap(PersistentInkMeasureAnchor(measureID: secondMeasure,
                    frame: CGRect(x: 220, y: 180, width: 140, height: 72)))
            ], chordAnchors: [
                try XCTUnwrap(PersistentInkChordAnchor(measureID: firstMeasure, chordID: chord,
                    frame: CGRect(x: 170, y: 220, width: 30, height: 40)))
            ])
        return (wide, narrow)
    }

    private func project(_ drawing: PKDrawing, from source: PersistentInkCoordinateSpace,
        to target: PersistentInkCoordinateSpace) -> PKDrawing {
        LeadSheetPersistentInkCoordinateSpacePolicy.drawing(drawing,
            sourceCoordinateSpace: source, targetCoordinateSpace: target)
    }

    private func phrase(x: CGFloat, y: CGFloat, count: Int = 6) -> PKDrawing {
        PKDrawing(strokes: (0..<count).map { index in
            let origin = CGPoint(x: x + CGFloat(index) * 30, y: y)
            let points = [origin,
                CGPoint(x: origin.x + 15, y: origin.y + 28),
                CGPoint(x: origin.x + 20, y: origin.y + 2)]
            let path = points.enumerated().map { offset, point in
                PKStrokePoint(location: point, timeOffset: Double(offset) * 0.1,
                    size: CGSize(width: 3, height: 3), opacity: 1, force: 1,
                    azimuth: 0, altitude: .pi / 2)
            }
            return PKStroke(ink: PKInk(.pen, color: LeadSheetPersistentInkColorPolicy.inkColor),
                path: PKStrokePath(controlPoints: path,
                    creationDate: Date(timeIntervalSinceReferenceDate: Double(index + 1))),
                transform: .identity, mask: nil, randomSeed: UInt32(index + 1))
        })
    }

    private func assertSameGeometry(_ source: PKDrawing, _ actual: PKDrawing,
        file: StaticString = #filePath, line: UInt = #line) {
        assertTranslated(source, actual, dx: 0, dy: 0, file: file, line: line)
    }

    private func assertTranslated(_ source: PKDrawing, _ actual: PKDrawing, dx: CGFloat, dy: CGFloat,
        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(source.strokes.count, actual.strokes.count, file: file, line: line)
        for (index, pair) in zip(source.strokes, actual.strokes).enumerated() {
            let before = pair.0.renderBounds
            let after = pair.1.renderBounds
            let beforePoints = visiblePoints(pair.0)
            let afterPoints = visiblePoints(pair.1)
            XCTAssertEqual(beforePoints.count, afterPoints.count, file: file, line: line)
            for (beforePoint, afterPoint) in zip(beforePoints, afterPoints) {
                XCTAssertEqual(afterPoint.x, beforePoint.x + dx, accuracy: 0.01,
                    "Letter spacing changed at stroke \(index)", file: file, line: line)
                XCTAssertEqual(afterPoint.y, beforePoint.y + dy, accuracy: 0.01,
                    "Relative stroke height changed at stroke \(index)", file: file, line: line)
            }
            for (beforePoint, afterPoint) in zip(pair.0.path, pair.1.path) {
                let sourceXScale = hypot(pair.0.transform.a, pair.0.transform.b)
                let actualXScale = hypot(pair.1.transform.a, pair.1.transform.b)
                let sourceYScale = hypot(pair.0.transform.c, pair.0.transform.d)
                let actualYScale = hypot(pair.1.transform.c, pair.1.transform.d)
                XCTAssertEqual(afterPoint.size.width * actualXScale, beforePoint.size.width * sourceXScale,
                    accuracy: 0.01, "Nib width changed at stroke \(index)", file: file, line: line)
                XCTAssertEqual(afterPoint.size.height * actualYScale, beforePoint.size.height * sourceYScale,
                    accuracy: 0.01, "Nib height changed at stroke \(index)", file: file, line: line)
            }
            // PencilKit rounds raster renderBounds to pixel-sized rectangles;
            // transformed control points above carry the strict geometry check.
            XCTAssertEqual(after.minX, before.minX + dx, accuracy: 1.1,
                "Letter spacing changed at stroke \(index)", file: file, line: line)
            XCTAssertEqual(after.minY, before.minY + dy, accuracy: 1.1,
                "Relative stroke height changed at stroke \(index)", file: file, line: line)
            XCTAssertEqual(after.width, before.width, accuracy: 1.1,
                "Stroke width changed at stroke \(index)", file: file, line: line)
            XCTAssertEqual(after.height, before.height, accuracy: 1.1,
                "Stroke height changed at stroke \(index)", file: file, line: line)
        }
    }

    private func visiblePoints(_ stroke: PKStroke) -> [CGPoint] {
        stroke.path.map { $0.location.applying(stroke.transform) }
    }

    private func writePrivateReplayPreview(_ drawing: PKDrawing, size: CGSize, to url: URL) throws {
        let bounds = CGRect(origin: .zero, size: size)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(bounds)
            drawing.image(from: bounds, scale: 1).draw(in: bounds)
        }
        try XCTUnwrap(image.pngData()).write(to: url, options: .atomic)
    }

    private struct Host {
        let view: LeadSheetCanvasUIKitView
        let authoring: PKCanvasView
        let passive: PKCanvasView
        let window: UIWindow
    }

    private func makeHost(chart: Chart, pageSize: CGSize, mode: EditorCanvasMode) throws -> Host {
        let view = LeadSheetCanvasUIKitView(frame: CGRect(origin: .zero, size: pageSize))
        view.recognizesChordInk = false
        view.chart = chart
        view.interactionMode = mode
        let controller = UIViewController()
        controller.view = view
        let window = UIWindow(frame: CGRect(origin: .zero, size: pageSize))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        view.setNeedsLayout()
        view.layoutIfNeeded()
        let canvases = view.subviews.compactMap { $0 as? PKCanvasView }
        XCTAssertEqual(canvases.count, 3)
        let authoring = try XCTUnwrap(canvases.last)
        let passive = try XCTUnwrap(canvases.dropFirst().first)
        if mode == .freeHand {
            XCTAssertFalse(authoring.isHidden)
            XCTAssertGreaterThan(authoring.bounds.width, 0)
        }
        return Host(view: view, authoring: authoring, passive: passive, window: window)
    }

    private func resize(_ host: Host, to size: CGSize) {
        host.window.frame = CGRect(origin: .zero, size: size)
        host.view.frame = CGRect(origin: .zero, size: size)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
    }

    private func makeChart(_ style: ChartLayoutStyle) -> Chart {
        var chart = Chart.draft(title: "Free Ink phrase rotation", layoutStyle: style)
        chart.completeInitialSetup(title: "Free Ink phrase rotation", key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4), staffStyle: .fiveLine, startingMeasureCount: 4)
        return chart
    }

    private func waitForMainRunLoop(_ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(3)
        while !condition(), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        return condition()
    }
}
#endif
