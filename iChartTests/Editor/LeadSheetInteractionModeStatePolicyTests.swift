#if canImport(UIKit)
import PencilKit
import UIKit
import XCTest
@testable import iChart

final class LeadSheetInteractionModeStatePolicyTests: XCTestCase {
    func testEditorPerformanceMetricsCountsDragAndChartWriteBackSignals() {
        var metrics = LeadSheetEditorPerformanceMetrics()

        metrics.recordLayoutInvalidation()
        metrics.recordChartWriteBack()
        metrics.recordDragState(kind: .chordMove, state: .began)
        metrics.recordDragState(kind: .chordMove, state: .changed)
        metrics.recordDragState(kind: .chordMove, state: .changed)
        metrics.recordDragState(kind: .chordMove, state: .ended)

        let snapshot = metrics.testSnapshot
        XCTAssertEqual(snapshot["layout_invalidations"], 1)
        XCTAssertEqual(snapshot["chart_writebacks"], 1)
        XCTAssertEqual(snapshot["drag_begins"], 1)
        XCTAssertEqual(snapshot["drag_changes"], 2)
        XCTAssertEqual(snapshot["drag_commits"], 1)
        XCTAssertEqual(snapshot["drag_cancels"], 0)
        XCTAssertEqual(snapshot["chord_move_changes"], 2)
        XCTAssertEqual(snapshot["max_drag_changes"], 2)
    }

    func testEditorPerformanceMetricsCountsCancelledDragKinds() {
        var metrics = LeadSheetEditorPerformanceMetrics()

        metrics.recordDragState(kind: .measureResize, state: .began)
        metrics.recordDragState(kind: .measureResize, state: .changed)
        metrics.recordDragState(kind: .measureResize, state: .cancelled)
        metrics.recordDragState(kind: .roadmapMarkerMove, state: .began)
        metrics.recordDragState(kind: .roadmapMarkerMove, state: .changed)
        metrics.recordDragState(kind: .roadmapMarkerMove, state: .changed)
        metrics.recordDragState(kind: .roadmapMarkerMove, state: .failed)

        let snapshot = metrics.testSnapshot
        XCTAssertEqual(snapshot["drag_begins"], 2)
        XCTAssertEqual(snapshot["drag_changes"], 3)
        XCTAssertEqual(snapshot["drag_commits"], 0)
        XCTAssertEqual(snapshot["drag_cancels"], 2)
        XCTAssertEqual(snapshot["measure_resize_changes"], 1)
        XCTAssertEqual(snapshot["roadmap_marker_changes"], 2)
        XCTAssertEqual(snapshot["max_drag_changes"], 2)
    }

    func testEditorPerformanceMetricsPreservesActiveDragCountsAcrossFlush() {
        var metrics = LeadSheetEditorPerformanceMetrics()

        metrics.recordDragState(kind: .measureResize, state: .began)
        metrics.recordDragState(kind: .measureResize, state: .changed)
        metrics.recordDragState(kind: .measureResize, state: .changed)
        metrics.flush(reason: "test")
        metrics.recordDragState(kind: .measureResize, state: .changed)
        metrics.recordDragState(kind: .measureResize, state: .ended)

        let snapshot = metrics.testSnapshot
        XCTAssertEqual(snapshot["drag_changes"], 1)
        XCTAssertEqual(snapshot["drag_commits"], 1)
        XCTAssertEqual(snapshot["max_drag_changes"], 3)
    }

    func testChordEntryPreservesOriginalPenWeight() {
        let policy = LeadSheetInteractionModeStatePolicy.resolve(for: .chordEntry)

        XCTAssertEqual(policy.inkTool.inkType, .pen)
        XCTAssertEqual(policy.inkTool.width, 2.5, accuracy: 0.001)
    }

    func testPersistentInkToolsUseFixedVisibleInk() {
        let chordPolicy = LeadSheetInteractionModeStatePolicy.resolve(for: .chordEntry)
        let freeWritePolicy = LeadSheetInteractionModeStatePolicy.resolve(for: .freeHand)

        assertPersistentInkColor(chordPolicy.inkTool.color)
        assertPersistentInkColor(freeWritePolicy.inkTool.color)
    }

    func testLiveInkCanvasForcesLightTraitForPencilKitCompositing() {
        let canvasView = PKCanvasView()

        UITraitCollection(userInterfaceStyle: .dark).performAsCurrent {
            LeadSheetLiveInkCanvasAppearancePolicy.configure(canvasView)
        }

        XCTAssertEqual(canvasView.overrideUserInterfaceStyle, .light)
        XCTAssertEqual(canvasView.traitCollection.userInterfaceStyle, .light)
        XCTAssertEqual(canvasView.backgroundColor, .clear)
        XCTAssertFalse(canvasView.isOpaque)
    }

    func testInkTelemetryCapturesLiveCanvasCompositingState() throws {
        let canvasView = PKCanvasView(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
        canvasView.contentScaleFactor = 2
        canvasView.drawingPolicy = .anyInput
        canvasView.tool = LeadSheetPersistentInkColorPolicy.inkingTool(width: 3.5)
        let drawing = PKDrawing(strokes: [
            stroke(
                points: [
                    CGPoint(x: 8, y: 26),
                    CGPoint(x: 22, y: 8),
                    CGPoint(x: 38, y: 34)
                ],
                creationDate: Date(timeIntervalSince1970: 35),
                color: LeadSheetPersistentInkColorPolicy.inkColor
            )
        ])
        var snapshot: LeadSheetInkTelemetrySnapshot?

        UITraitCollection(userInterfaceStyle: .dark).performAsCurrent {
            LeadSheetLiveInkCanvasAppearancePolicy.configure(canvasView)
            snapshot = LeadSheetInkTelemetrySnapshot.capture(
                drawing: drawing,
                canvasView: canvasView
            )
        }

        let telemetrySnapshot = try XCTUnwrap(snapshot)
        XCTAssertEqual(telemetrySnapshot.canvasUserInterfaceStyle, "light")
        XCTAssertEqual(telemetrySnapshot.canvasOverrideUserInterfaceStyle, "light")
        XCTAssertEqual(telemetrySnapshot.canvasSuperviewUserInterfaceStyle, "unknown")
        XCTAssertEqual(telemetrySnapshot.canvasWindowUserInterfaceStyle, "unknown")
        XCTAssertEqual(telemetrySnapshot.canvasDrawingPolicy, "any_input")
        XCTAssertEqual(telemetrySnapshot.canvasAlpha, 1, accuracy: 0.001)
        XCTAssertEqual(telemetrySnapshot.canvasBackgroundAlpha, 0, accuracy: 0.001)
        XCTAssertFalse(telemetrySnapshot.canvasIsOpaque)
        XCTAssertFalse(telemetrySnapshot.canvasIsHidden)
        XCTAssertTrue(telemetrySnapshot.canvasUserInteractionEnabled)
        XCTAssertFalse(telemetrySnapshot.canvasIsFirstResponder)
        XCTAssertEqual(telemetrySnapshot.canvasContentScale, 2, accuracy: 0.001)
        XCTAssertEqual(telemetrySnapshot.canvasBoundsWidth, 320, accuracy: 0.001)
        XCTAssertEqual(telemetrySnapshot.canvasBoundsHeight, 240, accuracy: 0.001)
        XCTAssertTrue(telemetrySnapshot.liveCanvasLightTraitGuardEnabled)
        XCTAssertTrue(telemetrySnapshot.toolIsInking)
        XCTAssertTrue(telemetrySnapshot.toolMatchesPersistentInk)
        XCTAssertEqual(telemetrySnapshot.toolWidth, 3.5, accuracy: 0.001)
        XCTAssertLessThan(telemetrySnapshot.toolColorLuminance, 0.25)

        let properties = telemetrySnapshot.telemetryProperties(
            scope: .page(frame: CGRect(x: 0, y: 0, width: 320, height: 240)),
            normalizedBeforeSave: true
        )
        XCTAssertEqual(properties["canvas_override_user_interface_style"], .string("light"))
        XCTAssertEqual(properties["canvas_drawing_policy"], .string("any_input"))
        XCTAssertEqual(properties["live_canvas_light_trait_guard_enabled"], .bool(true))
        XCTAssertEqual(properties["tool_matches_persistent_ink"], .bool(true))
        XCTAssertEqual(properties["tool_width"], .double(3.5))
    }

    func testPersistentInkNormalizationRecolorsWhiteInkWithoutChangingGeometry() throws {
        let sourceDrawing = PKDrawing(strokes: [
            stroke(
                points: [
                    CGPoint(x: 2, y: 3),
                    CGPoint(x: 18, y: 14),
                    CGPoint(x: 25, y: 9)
                ],
                creationDate: Date(timeIntervalSince1970: 40),
                color: .white
            )
        ])
        let sourceSnapshot = try XCTUnwrap(LeadSheetInkDrawingSnapshot(drawing: sourceDrawing))

        XCTAssertTrue(LeadSheetPersistentInkColorPolicy.needsNormalization(sourceDrawing))

        let normalizedDrawing = LeadSheetPersistentInkColorPolicy.normalizedDrawing(sourceDrawing)
        let normalizedSnapshot = try XCTUnwrap(LeadSheetInkDrawingSnapshot(drawing: normalizedDrawing))

        XCTAssertEqual(sourceSnapshot, normalizedSnapshot)
        XCTAssertFalse(LeadSheetPersistentInkColorPolicy.needsNormalization(normalizedDrawing))
        XCTAssertEqual(normalizedDrawing.strokes.first?.ink.inkType, .pen)
        assertPersistentInkColor(try XCTUnwrap(normalizedDrawing.strokes.first?.ink.color))
    }

    func testPersistentInkNormalizationUpdatesSerializedWhiteInk() throws {
        let sourceDrawing = PKDrawing(strokes: [
            stroke(
                points: [
                    CGPoint(x: 4, y: 5),
                    CGPoint(x: 30, y: 18)
                ],
                creationDate: Date(timeIntervalSince1970: 50),
                color: .white
            )
        ])

        let normalizedData = try XCTUnwrap(
            LeadSheetPersistentInkColorPolicy.normalizedDrawingData(sourceDrawing.dataRepresentation())
        )
        let normalizedDrawing = try PKDrawing(data: normalizedData)

        XCTAssertFalse(LeadSheetPersistentInkColorPolicy.needsNormalization(normalizedDrawing))
        assertPersistentInkColor(try XCTUnwrap(normalizedDrawing.strokes.first?.ink.color))
    }

    func testPersistentInkCoordinateSpaceTransformsLandscapeDrawingIntoPortraitFrame() throws {
        let sourceDrawing = PKDrawing(strokes: [
            stroke(
                points: [
                    CGPoint(x: 200, y: 100),
                    CGPoint(x: 240, y: 120)
                ],
                creationDate: Date(timeIntervalSince1970: 55),
                color: LeadSheetPersistentInkColorPolicy.inkColor
            )
        ])

        let transformedDrawing = LeadSheetPersistentInkCoordinateSpacePolicy.drawing(
            sourceDrawing,
            sourceCoordinateSpace: PersistentInkCoordinateSpace(width: 1000, height: 500),
            targetCoordinateSpace: PersistentInkCoordinateSpace(width: 500, height: 1000)
        )
        let sourceBounds = sourceDrawing.strokes.reduce(CGRect.null) { $0.union($1.renderBounds) }
        let transformedBounds = transformedDrawing.strokes.reduce(CGRect.null) { $0.union($1.renderBounds) }

        XCTAssertEqual(transformedBounds.minX, sourceBounds.minX * 0.5, accuracy: 3)
        XCTAssertEqual(transformedBounds.minY, sourceBounds.minY * 2, accuracy: 3)
        XCTAssertEqual(transformedBounds.width, sourceBounds.width * 0.5, accuracy: 3)
        XCTAssertEqual(transformedBounds.height, sourceBounds.height * 2, accuracy: 3)
    }

    func testPersistentInkCoordinateSpaceAnchorsStrokesToMatchingMeasureAcrossLayouts() throws {
        let measureID = UUID()
        let sourceMeasureFrame = CGRect(x: 100, y: 40, width: 120, height: 80)
        let targetMeasureFrame = CGRect(x: 210, y: 52, width: 180, height: 96)
        let sourceCoordinateSpace = PersistentInkCoordinateSpace(
            width: 500,
            height: 300,
            measureAnchors: [
                try XCTUnwrap(PersistentInkMeasureAnchor(measureID: measureID, frame: sourceMeasureFrame))
            ]
        )
        let targetCoordinateSpace = PersistentInkCoordinateSpace(
            width: 700,
            height: 300,
            measureAnchors: [
                try XCTUnwrap(PersistentInkMeasureAnchor(measureID: measureID, frame: targetMeasureFrame))
            ]
        )
        let sourceDrawing = PKDrawing(strokes: [
            stroke(
                points: [
                    CGPoint(x: sourceMeasureFrame.minX + 38, y: sourceMeasureFrame.minY + 24),
                    CGPoint(x: sourceMeasureFrame.minX + 58, y: sourceMeasureFrame.minY + 34)
                ],
                creationDate: Date(timeIntervalSince1970: 56),
                color: LeadSheetPersistentInkColorPolicy.inkColor
            )
        ])

        let transformedDrawing = LeadSheetPersistentInkCoordinateSpacePolicy.drawing(
            sourceDrawing,
            sourceCoordinateSpace: sourceCoordinateSpace,
            targetCoordinateSpace: targetCoordinateSpace
        )
        let sourceBounds = sourceDrawing.strokes.reduce(CGRect.null) { $0.union($1.renderBounds) }
        let transformedBounds = transformedDrawing.strokes.reduce(CGRect.null) { $0.union($1.renderBounds) }
        let expectedMidX = targetMeasureFrame.minX
            + (sourceBounds.midX - sourceMeasureFrame.minX)
                * targetMeasureFrame.width / sourceMeasureFrame.width
        let expectedMidY = targetMeasureFrame.minY
            + (sourceBounds.midY - sourceMeasureFrame.minY)
                * targetMeasureFrame.height / sourceMeasureFrame.height
        let pageScaledMidX = sourceBounds.midX * targetCoordinateSpace.size.width / sourceCoordinateSpace.size.width

        XCTAssertEqual(transformedBounds.midX, expectedMidX, accuracy: 3)
        XCTAssertEqual(transformedBounds.midY, expectedMidY, accuracy: 3)
        XCTAssertGreaterThan(abs(transformedBounds.midX - pageScaledMidX), 20)
    }

    func testPersistentInkCoordinateSpaceAnchorsSimpleChordInkAboveMeasureFrame() throws {
        let measureID = UUID()
        let sourceMeasureFrame = CGRect(x: 250, y: 148, width: 186, height: 120)
        let targetMeasureFrame = CGRect(x: 310, y: 132, width: 240, height: 126)
        let sourceCoordinateSpace = PersistentInkCoordinateSpace(
            width: 724,
            height: 1120,
            measureAnchors: [
                try XCTUnwrap(PersistentInkMeasureAnchor(measureID: measureID, frame: sourceMeasureFrame))
            ]
        )
        let targetCoordinateSpace = PersistentInkCoordinateSpace(
            width: 1020,
            height: 724,
            measureAnchors: [
                try XCTUnwrap(PersistentInkMeasureAnchor(measureID: measureID, frame: targetMeasureFrame))
            ]
        )
        let sourceDrawing = PKDrawing(strokes: [
            stroke(
                points: [
                    CGPoint(x: sourceMeasureFrame.minX + 34, y: sourceMeasureFrame.minY - 31),
                    CGPoint(x: sourceMeasureFrame.minX + 38, y: sourceMeasureFrame.minY - 8)
                ],
                creationDate: Date(timeIntervalSince1970: 57),
                color: LeadSheetPersistentInkColorPolicy.inkColor
            )
        ])

        let transformedDrawing = LeadSheetPersistentInkCoordinateSpacePolicy.drawing(
            sourceDrawing,
            sourceCoordinateSpace: sourceCoordinateSpace,
            targetCoordinateSpace: targetCoordinateSpace
        )
        let sourceBounds = sourceDrawing.strokes.reduce(CGRect.null) { $0.union($1.renderBounds) }
        let transformedBounds = transformedDrawing.strokes.reduce(CGRect.null) { $0.union($1.renderBounds) }
        let expectedMidX = targetMeasureFrame.minX
            + (sourceBounds.midX - sourceMeasureFrame.minX)
                * targetMeasureFrame.width / sourceMeasureFrame.width
        let expectedMidY = targetMeasureFrame.minY
            + (sourceBounds.midY - sourceMeasureFrame.minY)
                * targetMeasureFrame.height / sourceMeasureFrame.height
        let pageScaledMidY = sourceBounds.midY * targetCoordinateSpace.size.height / sourceCoordinateSpace.size.height

        XCTAssertLessThan(sourceBounds.midY, sourceMeasureFrame.minY)
        XCTAssertEqual(transformedBounds.midX, expectedMidX, accuracy: 3)
        XCTAssertEqual(transformedBounds.midY, expectedMidY, accuracy: 3)
        XCTAssertGreaterThan(abs(transformedBounds.midY - pageScaledMidY), 20)
    }

    func testPageInkCoordinateSpaceCapturesChordAnchorsRelativeToPageFrame() throws {
        let chart = try simpleChordFreeWriteRotationReproChart()
        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 792, height: 1200)
        )
        let pageFrame = LeadSheetActiveInkScope.pageWritingFrame(for: layout)
        let coordinateSpace = try XCTUnwrap(
            LeadSheetPersistentInkCoordinateSpacePolicy.coordinateSpace(
                for: .page(frame: pageFrame),
                pageLayout: layout
            )
        )
        let measures = try XCTUnwrap(layout.systems.first?.measures)
        XCTAssertGreaterThan(measures.count, 1)
        let secondMeasure = measures[1]
        let firstChordLayout = try XCTUnwrap(secondMeasure.chordLayouts.first)
        let firstChordAnchor = try XCTUnwrap(
            coordinateSpace.chordAnchors?.first { $0.chordID == firstChordLayout.id }
        )
        let registrationPoint = try XCTUnwrap(firstChordAnchor.registrationPoint?.point)

        XCTAssertEqual(coordinateSpace.chordAnchors?.count, 2)
        XCTAssertGreaterThan(chart.measures.count, 1)
        XCTAssertEqual(firstChordAnchor.measureID, chart.measures[1].id)
        XCTAssertEqual(
            firstChordAnchor.frame.rect.minX,
            firstChordLayout.frame.minX - pageFrame.minX,
            accuracy: 0.001
        )
        XCTAssertEqual(
            firstChordAnchor.frame.rect.minY,
            firstChordLayout.frame.minY - pageFrame.minY,
            accuracy: 0.001
        )
        XCTAssertEqual(
            registrationPoint.x,
            firstChordLayout.snapGuideTarget.x - pageFrame.minX,
            accuracy: 0.001
        )
        XCTAssertEqual(
            registrationPoint.y,
            firstChordLayout.snapGuideTarget.y - pageFrame.minY,
            accuracy: 0.001
        )
    }

    func testChordAnchoredPageInkPreservesStrokeSizeWhenChordFrameWidens() throws {
        let measureID = UUID()
        let chordID = UUID()
        let sourceCoordinateSpace = try XCTUnwrap(
            PersistentInkCoordinateSpace(
                width: 320,
                height: 220,
                chordAnchors: [
                    try XCTUnwrap(
                        PersistentInkChordAnchor(
                            measureID: measureID,
                            chordID: chordID,
                            frame: CGRect(x: 100, y: 80, width: 40, height: 32),
                            registrationPoint: CGPoint(x: 100, y: 120)
                        )
                    )
                ]
            )
        )
        let targetCoordinateSpace = try XCTUnwrap(
            PersistentInkCoordinateSpace(
                width: 480,
                height: 220,
                chordAnchors: [
                    try XCTUnwrap(
                        PersistentInkChordAnchor(
                            measureID: measureID,
                            chordID: chordID,
                            frame: CGRect(x: 160, y: 80, width: 88, height: 32),
                            registrationPoint: CGPoint(x: 160, y: 120)
                        )
                    )
                ]
            )
        )
        let sourceDrawing = PKDrawing(strokes: [
            stroke(
                points: [
                    CGPoint(x: 148, y: 50),
                    CGPoint(x: 160, y: 62)
                ],
                creationDate: Date(timeIntervalSince1970: 59),
                color: LeadSheetPersistentInkColorPolicy.inkColor
            )
        ])

        let transformedDrawing = LeadSheetPersistentInkCoordinateSpacePolicy.drawing(
            sourceDrawing,
            sourceCoordinateSpace: sourceCoordinateSpace,
            targetCoordinateSpace: targetCoordinateSpace
        )
        let sourceBounds = sourceDrawing.strokes.reduce(CGRect.null) { $0.union($1.renderBounds) }
        let transformedBounds = transformedDrawing.strokes.reduce(CGRect.null) { $0.union($1.renderBounds) }
        let scaledMidX = 160 + (sourceBounds.midX - 100) * (88 / 40)

        XCTAssertEqual(transformedBounds.midX, sourceBounds.midX + 60, accuracy: 1)
        XCTAssertEqual(transformedBounds.width, sourceBounds.width, accuracy: 1)
        XCTAssertGreaterThan(abs(transformedBounds.midX - scaledMidX), 20)
    }

    func testLegacySimpleChordPageInkUsesInferredChordAnchorsAcrossRotation() throws {
        let chart = try simpleChordFreeWriteRotationReproChart()
        let sourceLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 792, height: 1200)
        )
        let targetLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 980, height: 1200)
        )
        let sourcePageFrame = LeadSheetActiveInkScope.pageWritingFrame(for: sourceLayout)
        let targetPageFrame = LeadSheetActiveInkScope.pageWritingFrame(for: targetLayout)
        let sourceMeasures = try XCTUnwrap(sourceLayout.systems.first?.measures)
        let targetMeasures = try XCTUnwrap(targetLayout.systems.first?.measures)
        XCTAssertGreaterThan(sourceMeasures.count, 1)
        XCTAssertGreaterThan(targetMeasures.count, 1)
        let sourceMeasure = sourceMeasures[1]
        let targetMeasure = targetMeasures[1]
        let sourceDMinor = try XCTUnwrap(sourceMeasure.chordLayouts.first { $0.text == "D-11" })
        let targetDMinor = try XCTUnwrap(targetMeasure.chordLayouts.first { $0.id == sourceDMinor.id })
        let sourceDMinorAnchorFrame = relativeFrame(sourceDMinor.frame, to: sourcePageFrame)
        let targetDMinorAnchorFrame = relativeFrame(targetDMinor.frame, to: targetPageFrame)
        let sourceMeasureAnchorFrame = relativeFrame(sourceMeasure.chordWritingFrame, to: sourcePageFrame)
        let targetMeasureAnchorFrame = relativeFrame(targetMeasure.chordWritingFrame, to: targetPageFrame)
        let legacySourceCoordinateSpace = try XCTUnwrap(
            PersistentInkCoordinateSpace(
                size: sourcePageFrame.size,
                measureAnchors: LeadSheetPersistentInkCoordinateSpacePolicy.measureAnchors(
                    in: sourceLayout,
                    relativeTo: sourcePageFrame
                )
            )
        )
        let sourceCoordinateSpace = try XCTUnwrap(
            LeadSheetPersistentInkCoordinateSpacePolicy.pageSourceCoordinateSpace(
                legacySourceCoordinateSpace,
                chart: chart
            )
        )
        let targetCoordinateSpace = try XCTUnwrap(
            LeadSheetPersistentInkCoordinateSpacePolicy.pageCoordinateSpace(
                for: targetLayout,
                relativeTo: targetPageFrame
            )
        )
        let sourceDMinorAnchor = try XCTUnwrap(
            sourceCoordinateSpace.chordAnchors?.first { $0.chordID == sourceDMinor.id }
        )
        let targetDMinorAnchor = try XCTUnwrap(
            targetCoordinateSpace.chordAnchors?.first { $0.chordID == sourceDMinor.id }
        )
        let sourceRegistrationPoint = sourceDMinorAnchor.registrationPoint?.point
            ?? sourceDMinorAnchorFrame.origin
        let targetRegistrationPoint = targetDMinorAnchor.registrationPoint?.point
            ?? targetDMinorAnchorFrame.origin
        let sourceDrawing = PKDrawing(strokes: [
            stroke(
                points: [
                    CGPoint(
                        x: sourceDMinorAnchorFrame.minX + 18,
                        y: sourceDMinorAnchorFrame.minY - 42
                    ),
                    CGPoint(
                        x: sourceDMinorAnchorFrame.minX + 26,
                        y: sourceDMinorAnchorFrame.minY - 8
                    )
                ],
                creationDate: Date(timeIntervalSince1970: 58),
                color: LeadSheetPersistentInkColorPolicy.inkColor
            )
        ])

        let transformedDrawing = LeadSheetPersistentInkCoordinateSpacePolicy.drawing(
            sourceDrawing,
            sourceCoordinateSpace: sourceCoordinateSpace,
            targetCoordinateSpace: targetCoordinateSpace
        )
        let sourceBounds = sourceDrawing.strokes.reduce(CGRect.null) { $0.union($1.renderBounds) }
        let transformedBounds = transformedDrawing.strokes.reduce(CGRect.null) { $0.union($1.renderBounds) }
        let expectedChordAnchoredMidX = targetRegistrationPoint.x
            + sourceBounds.midX - sourceRegistrationPoint.x
        let measureScaledMidX = targetMeasureAnchorFrame.minX
            + (sourceBounds.midX - sourceMeasureAnchorFrame.minX)
                * targetMeasureAnchorFrame.width / sourceMeasureAnchorFrame.width

        XCTAssertNil(legacySourceCoordinateSpace.chordAnchors)
        XCTAssertEqual(sourceCoordinateSpace.chordAnchors?.count, 2)
        XCTAssertLessThan(sourceBounds.midY, sourceDMinorAnchorFrame.minY)
        XCTAssertEqual(transformedBounds.midX, expectedChordAnchoredMidX, accuracy: 4)
        XCTAssertEqual(transformedBounds.width, sourceBounds.width, accuracy: 1)
        XCTAssertGreaterThan(abs(transformedBounds.midX - measureScaledMidX), 6)
    }

    func testPageInkCoordinateSpaceCapturesMeasureAnchorsRelativeToPageFrame() throws {
        let chart = Chart.blank(title: "Simple", measureCount: 3, layoutStyle: .simpleChordSheet)
        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 820, height: 1180)
        )
        let pageFrame = LeadSheetActiveInkScope.pageWritingFrame(for: layout)
        let coordinateSpace = try XCTUnwrap(
            LeadSheetPersistentInkCoordinateSpacePolicy.coordinateSpace(
                for: .page(frame: pageFrame),
                pageLayout: layout
            )
        )
        let firstMeasure = try XCTUnwrap(layout.systems.first?.measures.first)
        let firstAnchor = try XCTUnwrap(coordinateSpace.measureAnchors?.first)

        XCTAssertEqual(coordinateSpace.measureAnchors?.count, chart.measures.count)
        XCTAssertEqual(firstAnchor.measureID, try XCTUnwrap(chart.measures.first?.id))
        XCTAssertEqual(
            firstAnchor.frame.rect.minX,
            firstMeasure.chordWritingFrame.minX - pageFrame.minX,
            accuracy: 0.001
        )
        XCTAssertEqual(
            firstAnchor.frame.rect.minY,
            firstMeasure.chordWritingFrame.minY - pageFrame.minY,
            accuracy: 0.001
        )
    }

    func testInkScopeIdentitySeparatesFreeWriteFromOtherCanvasScopes() {
        let measureID = UUID()

        XCTAssertEqual(
            LeadSheetActiveInkScope.page(frame: CGRect(x: 0, y: 0, width: 700, height: 1000)).identity,
            .page
        )
        XCTAssertNotEqual(
            LeadSheetActiveInkScope.page(frame: CGRect(x: 0, y: 0, width: 700, height: 1000)).identity,
            LeadSheetActiveInkScope.chords(
                frame: CGRect(x: 10, y: 20, width: 500, height: 120),
                inputFrames: []
            ).identity
        )
        XCTAssertEqual(
            LeadSheetActiveInkScope.rhythmicMeasure(
                measureID: measureID,
                frame: CGRect(x: 20, y: 40, width: 180, height: 80)
            ).identity,
            .rhythmicMeasure(measureID)
        )
    }

    func testSavedInkRendererKeepsPersistentInkDarkWhenCurrentTraitIsDark() throws {
        let drawing = PKDrawing(strokes: [
            stroke(
                points: [
                    CGPoint(x: 4, y: 18),
                    CGPoint(x: 18, y: 4),
                    CGPoint(x: 34, y: 28)
                ],
                creationDate: Date(timeIntervalSince1970: 60),
                color: LeadSheetPersistentInkColorPolicy.inkColor
            )
        ])
        let drawingData = try XCTUnwrap(
            LeadSheetPersistentInkColorPolicy.persistentDrawingData(for: drawing)
        )
        var renderedImage: UIImage?

        UITraitCollection(userInterfaceStyle: .dark).performAsCurrent {
            renderedImage = LeadSheetSavedInkRenderer.renderedInkImage(
                drawingData,
                size: CGSize(width: 40, height: 40),
                scale: 1
            )
        }

        let medianLuminance = try XCTUnwrap(
            medianVisiblePixelLuminance(in: try XCTUnwrap(renderedImage).cgImage)
        )
        XCTAssertLessThan(medianLuminance, 0.25)
    }

    func testSavedInkRendererForcesAdaptiveWhitePixelsToPersistentInkColor() throws {
        let adaptiveWhiteImage = strokeImage(
            color: .white,
            size: CGSize(width: 40, height: 40),
            scale: 1
        )

        let forcedImage = LeadSheetSavedInkRenderer.imageByForcingPersistentInkColor(
            adaptiveWhiteImage,
            scale: 1
        )

        let medianLuminance = try XCTUnwrap(
            medianVisiblePixelLuminance(in: forcedImage.cgImage)
        )
        let pixelCoverage = try XCTUnwrap(visiblePixelCoverage(in: forcedImage.cgImage))
        XCTAssertLessThan(medianLuminance, 0.25)
        XCTAssertGreaterThan(pixelCoverage, 0)
        XCTAssertLessThan(pixelCoverage, 0.5)
    }

    func testInkTelemetryRenderDiagnosticsStayDarkWhenCurrentTraitIsDark() throws {
        let drawing = PKDrawing(strokes: [
            stroke(
                points: [
                    CGPoint(x: 8, y: 26),
                    CGPoint(x: 22, y: 8),
                    CGPoint(x: 38, y: 34)
                ],
                creationDate: Date(timeIntervalSince1970: 75),
                color: LeadSheetPersistentInkColorPolicy.inkColor
            )
        ])
        var snapshot: LeadSheetInkTelemetrySnapshot?

        UITraitCollection(userInterfaceStyle: .dark).performAsCurrent {
            snapshot = LeadSheetInkTelemetrySnapshot.capture(drawing: drawing)
        }

        let telemetrySnapshot = try XCTUnwrap(snapshot)
        XCTAssertGreaterThan(telemetrySnapshot.renderedInkSampleCount, 0)
        XCTAssertLessThan(telemetrySnapshot.renderedInkMedianLuminance, 0.25)
        XCTAssertLessThan(telemetrySnapshot.renderedInkLightPixelRatio, 0.1)
    }

    func testPersistentInkNormalizationPreservesUnrecognizedNonemptyData() {
        let sourceData = Data("ink-C".utf8)

        XCTAssertEqual(
            LeadSheetPersistentInkColorPolicy.normalizedDrawingData(sourceData),
            sourceData
        )
    }

    func testInkToolPolicyUsesEraserForFreeWriteEraseMode() {
        let policy = LeadSheetInteractionModeStatePolicy.resolve(
            for: .freeHand,
            inkToolMode: .erase
        )

        XCTAssertEqual(policy.inkToolMode, .erase)
        XCTAssertTrue(policy.canvasTool is PKEraserTool)
    }

    func testInkToolPolicyIgnoresEraseModeWhenCanvasIsNotInking() {
        let policy = LeadSheetInteractionModeStatePolicy.resolve(
            for: .browse,
            inkToolMode: .erase
        )

        XCTAssertEqual(policy.inkToolMode, .write)
        XCTAssertTrue(policy.canvasTool is PKInkingTool)
    }

    func testActiveInkErasePolicyRemovesIntersectedStrokeOnly() {
        let erasedStroke = stroke(
            points: [
                CGPoint(x: 12, y: 12),
                CGPoint(x: 42, y: 42)
            ],
            creationDate: Date(timeIntervalSince1970: 71)
        )
        let retainedStroke = stroke(
            points: [
                CGPoint(x: 180, y: 20),
                CGPoint(x: 220, y: 42)
            ],
            creationDate: Date(timeIntervalSince1970: 72)
        )
        let drawing = PKDrawing(strokes: [erasedStroke, retainedStroke])

        let indices = LeadSheetActiveInkErasePolicy.strokeIndicesToErase(
            in: drawing,
            from: CGPoint(x: 0, y: 30),
            to: CGPoint(x: 54, y: 30),
            radius: 16
        )

        XCTAssertEqual(indices, Set([0]))
    }

    func testActiveInkErasePolicyIgnoresDistantStroke() {
        let drawing = PKDrawing(strokes: [
            stroke(
                points: [
                    CGPoint(x: 90, y: 90),
                    CGPoint(x: 130, y: 132)
                ],
                creationDate: Date(timeIntervalSince1970: 73)
            )
        ])

        let indices = LeadSheetActiveInkErasePolicy.strokeIndicesToErase(
            in: drawing,
            from: CGPoint(x: 4, y: 4),
            to: CGPoint(x: 30, y: 4),
            radius: 12
        )

        XCTAssertTrue(indices.isEmpty)
    }

    func testChordEntryKeepsSimulatorPointerInputForAutomation() {
        let policy = LeadSheetInteractionModeStatePolicy.resolve(for: .chordEntry)

        #if targetEnvironment(simulator)
        XCTAssertEqual(policy.drawingPolicy, .anyInput)
        #else
        XCTAssertEqual(policy.drawingPolicy, .pencilOnly)
        #endif
    }

    func testDeviceLiveInkInputUsesPencilOnlyAcrossInkModes() {
        let liveInkModes: [EditorCanvasMode] = [
            .freeHand,
            .headerEntry,
            .chordEntry,
            .noteEdit
        ]

        for mode in liveInkModes {
            XCTAssertEqual(
                LeadSheetLiveInkInputPolicy.drawingPolicy(for: mode, environment: .device),
                .pencilOnly,
                "\(mode) should reject direct hand input on device"
            )
        }

        XCTAssertEqual(
            LeadSheetLiveInkInputPolicy.drawingPolicy(for: .browse, environment: .device),
            .anyInput
        )
        XCTAssertEqual(
            LeadSheetLiveInkInputPolicy.drawingPolicy(for: .textEdit, environment: .device),
            .anyInput
        )
    }

    func testSimulatorLiveInkInputKeepsDirectAutomationAvailable() {
        XCTAssertEqual(
            LeadSheetLiveInkInputPolicy.drawingPolicy(for: .chordEntry, environment: .simulator),
            .anyInput
        )
        XCTAssertTrue(
            LeadSheetLiveInkInputPolicy.allowsCanvasGestureTouch(
                touchType: .direct,
                interactionMode: .chordEntry,
                environment: .simulator
            )
        )
    }

    func testPencilOnlyActionButtonsKeepSimulatorDirectTouchAutomationAvailable() {
        XCTAssertTrue(
            PencilOnlyActionButtonInputPolicy.allowsButtonTouch(
                touchType: .direct,
                environment: .simulator
            )
        )
        XCTAssertTrue(
            PencilOnlyActionButtonInputPolicy.allowsButtonTouch(
                touchType: .pencil,
                environment: .simulator
            )
        )
        XCTAssertFalse(
            PencilOnlyActionButtonInputPolicy.allowsButtonTouch(
                touchType: .direct,
                environment: .device
            )
        )
        XCTAssertTrue(
            PencilOnlyActionButtonInputPolicy.allowsButtonTouch(
                touchType: .pencil,
                environment: .device
            )
        )
    }

    func testDeviceCanvasGesturesIgnoreDirectTouchInLiveInkModes() {
        XCTAssertFalse(
            LeadSheetLiveInkInputPolicy.allowsCanvasGestureTouch(
                touchType: .direct,
                interactionMode: .chordEntry,
                environment: .device
            )
        )
        XCTAssertFalse(
            LeadSheetLiveInkInputPolicy.allowsCanvasGestureTouch(
                touchType: .direct,
                interactionMode: .freeHand,
                environment: .device
            )
        )
        XCTAssertTrue(
            LeadSheetLiveInkInputPolicy.allowsCanvasGestureTouch(
                touchType: .pencil,
                interactionMode: .chordEntry,
                environment: .device
            )
        )
        XCTAssertTrue(
            LeadSheetLiveInkInputPolicy.allowsCanvasGestureTouch(
                touchType: .direct,
                interactionMode: .browse,
                environment: .device
            )
        )
    }

    func testDeviceParentScrollBlocksDirectTouchInLiveInkModes() {
        XCTAssertTrue(
            LeadSheetParentScrollTouchPolicy.blocksParentScrollStart(
                touchType: .direct,
                interactionMode: .chordEntry,
                environment: .device
            )
        )
        XCTAssertTrue(
            LeadSheetParentScrollTouchPolicy.blocksParentScrollStart(
                touchType: .direct,
                interactionMode: .freeHand,
                environment: .device
            )
        )
        XCTAssertFalse(
            LeadSheetParentScrollTouchPolicy.blocksParentScrollStart(
                touchType: .pencil,
                interactionMode: .chordEntry,
                environment: .device
            )
        )
        XCTAssertFalse(
            LeadSheetParentScrollTouchPolicy.blocksParentScrollStart(
                touchType: .direct,
                interactionMode: .browse,
                environment: .device
            )
        )
        XCTAssertFalse(
            LeadSheetParentScrollTouchPolicy.blocksParentScrollStart(
                touchType: .direct,
                interactionMode: .chordEntry,
                environment: .simulator
            )
        )
    }

    func testChordEntryKeepsInkCanvasAndEnablesRenderedChordObjects() {
        let policy = LeadSheetInteractionModeStatePolicy.resolve(for: .chordEntry)

        XCTAssertTrue(policy.pageInkCanvasInteractionEnabled)
        XCTAssertTrue(policy.renderedEditTapEnabled)
        XCTAssertTrue(policy.renderedObjectMovePanEnabled)
        XCTAssertFalse(policy.renderedEditOverlayHidden)
        XCTAssertTrue(EditorCanvasMode.chordEntry.allowsChordObjectEditing)
        XCTAssertTrue(EditorCanvasMode.chordEntry.requiresChordSelectionBeforeObjectActions)
        XCTAssertTrue(EditorCanvasMode.chordEntry.drawsAllChordObjectEditBoxes)
        XCTAssertFalse(EditorCanvasMode.chordEntry.drawsAllChordObjectEditControls)
    }

    func testTextEditModeKeepsCueTextEditableWithoutMeasureSelection() {
        let policy = LeadSheetInteractionModeStatePolicy.resolve(for: .textEdit)

        XCTAssertFalse(policy.selectionTapEnabled)
        XCTAssertTrue(policy.renderedEditTapEnabled)
        XCTAssertTrue(policy.renderedObjectMovePanEnabled)
        XCTAssertFalse(policy.renderedEditOverlayHidden)
        XCTAssertFalse(EditorCanvasMode.textEdit.allowsMeasureSelection)
        XCTAssertTrue(EditorCanvasMode.textEdit.allowsCueTextEditing)
        XCTAssertFalse(EditorCanvasMode.textEdit.allowsChordObjectEditing)
        XCTAssertEqual(EditorCanvasMode.textEdit.activeToolTitle, "Text")
    }

    func testPencilObjectMoveStartsOnlyOnMovableTargets() {
        XCTAssertFalse(
            LeadSheetObjectMoveTouchPolicy.allowsMovePan(
                touchType: .pencil,
                interactionMode: .browse,
                startsOnMoveTarget: false
            )
        )
        XCTAssertTrue(
            LeadSheetObjectMoveTouchPolicy.allowsMovePan(
                touchType: .pencil,
                interactionMode: .browse,
                startsOnMoveTarget: true
            )
        )
        XCTAssertTrue(
            LeadSheetObjectMoveTouchPolicy.allowsMovePan(
                touchType: .direct,
                interactionMode: .browse,
                startsOnMoveTarget: false
            )
        )
        XCTAssertFalse(
            LeadSheetObjectMoveTouchPolicy.allowsMovePan(
                touchType: .direct,
                interactionMode: .chordEntry,
                startsOnMoveTarget: true,
                environment: .device
            )
        )
    }

    func testChordMoveDragUsesFrozenLayoutTargetWhilePreviewMoves() throws {
        var chart = Chart.blank(title: "Drag Reflow", measureCount: 4, layoutStyle: .simpleChordSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        _ = try XCTUnwrap(
            chart.appendRecognizedChordEvent(
                try ChordSymbolParser.parse("C"),
                rawInput: "C",
                to: measureID,
                atFraction: 0.03
            )
        )
        let movedChordID = try XCTUnwrap(
            chart.appendRecognizedChordEvent(
                try ChordSymbolParser.parse("D"),
                rawInput: "D",
                to: measureID,
                atFraction: 0.30
            )
        )
        _ = try XCTUnwrap(
            chart.appendRecognizedChordEvent(
                try ChordSymbolParser.parse("A7"),
                rawInput: "A7",
                to: measureID,
                atFraction: 0.62
            )
        )
        _ = try XCTUnwrap(
            chart.appendRecognizedChordEvent(
                try ChordSymbolParser.parse("D-11"),
                rawInput: "D-11",
                to: measureID,
                atFraction: 0.86
            )
        )

        let sourceLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1200)
        )
        let sourceMeasure = try XCTUnwrap(sourceLayout.systems.first?.measures.first)
        let sourceChordLayout = try XCTUnwrap(sourceMeasure.chordLayouts.first { $0.id == movedChordID })
        let startLocation = CGPoint(x: sourceChordLayout.frame.midX, y: sourceChordLayout.frame.midY)
        let drag = ActiveChordMoveDrag(
            chordID: movedChordID,
            sourcePageLayout: sourceLayout,
            initialFrame: sourceChordLayout.frame,
            currentFrame: sourceChordLayout.frame,
            startLocation: startLocation
        )
        let movedLocation = CGPoint(
            x: startLocation.x + sourceMeasure.chordBandFrame.width * 0.18,
            y: startLocation.y
        )

        let previewFrame = LeadSheetChordMoveDragPolicy.previewFrame(
            for: drag,
            at: movedLocation,
            boundedBy: sourceLayout.paperFrame
        )
        var resolvedDrag = drag
        resolvedDrag.currentFrame = previewFrame
        let target = try XCTUnwrap(
            LeadSheetChordMoveDragPolicy.target(
                at: movedLocation,
                for: resolvedDrag
            )
        )
        let expectedFrozenFraction = (previewFrame.minX - sourceMeasure.chordBandFrame.minX)
            / max(1, sourceMeasure.chordBandFrame.width)

        XCTAssertEqual(previewFrame.minX, sourceChordLayout.frame.minX + sourceMeasure.chordBandFrame.width * 0.18, accuracy: 0.001)
        XCTAssertEqual(previewFrame.minY, sourceChordLayout.frame.minY, accuracy: 0.001)
        XCTAssertEqual(target.measureID, measureID)
        XCTAssertEqual(target.fraction, Double(min(max(expectedFrozenFraction, 0), 0.9999)), accuracy: 0.0001)
    }

    func testChordMoveDragUsesTouchLocationForNeighborMeasureWhenGrabbedOffCenter() throws {
        var chart = Chart.blank(title: "Off Center Cross Measure Drag", measureCount: 2, layoutStyle: .simpleChordSheet)
        let sourceMeasureID = try XCTUnwrap(chart.measures.first?.id)
        let targetMeasureID = try XCTUnwrap(chart.measures.dropFirst().first?.id)
        let chordID = try XCTUnwrap(
            chart.appendRecognizedChordEvent(
                try ChordSymbolParser.parse("Db7(b9)"),
                rawInput: "Db7(b9)",
                to: sourceMeasureID,
                atFraction: 0.18
            )
        )
        let sourceLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1200)
        )
        let sourceMeasure = try XCTUnwrap(sourceLayout.systems.first?.measures.first)
        let targetMeasure = try XCTUnwrap(sourceLayout.systems.first?.measures.dropFirst().first)
        let sourceChordLayout = try XCTUnwrap(sourceMeasure.chordLayouts.first { $0.id == chordID })
        let startLocation = CGPoint(
            x: sourceChordLayout.frame.maxX - 2,
            y: sourceChordLayout.frame.midY
        )
        let drag = ActiveChordMoveDrag(
            chordID: chordID,
            sourcePageLayout: sourceLayout,
            initialFrame: sourceChordLayout.frame,
            currentFrame: sourceChordLayout.frame,
            startLocation: startLocation
        )
        let movedLocation = CGPoint(
            x: targetMeasure.chordBandFrame.minX + 10,
            y: startLocation.y
        )

        let previewFrame = LeadSheetChordMoveDragPolicy.previewFrame(
            for: drag,
            at: movedLocation,
            boundedBy: sourceLayout.paperFrame
        )
        var resolvedDrag = drag
        resolvedDrag.currentFrame = previewFrame

        XCTAssertLessThan(previewFrame.midX, targetMeasure.chordBandFrame.minX)

        let target = try XCTUnwrap(
            LeadSheetChordMoveDragPolicy.target(
                at: movedLocation,
                for: resolvedDrag
            )
        )

        XCTAssertEqual(target.measureID, targetMeasureID)
        XCTAssertEqual(target.fraction, 0, accuracy: 0.0001)
    }

    func testChordMoveTargetPrefersVisibleChordBandSegmentOverOverlappingMeasureFrame() throws {
        let leftMeasureID = UUID()
        let rightMeasureID = UUID()
        let leftMeasure = LeadSheetMeasureLayout(
            id: leftMeasureID,
            sourceMeasureID: leftMeasureID,
            chordInkTargetMeasureID: leftMeasureID,
            index: 1,
            frame: CGRect(x: 100, y: 180, width: 300, height: 78),
            staffFrame: CGRect(x: 100, y: 188, width: 120, height: 58),
            chordBandFrame: CGRect(x: 104, y: 194, width: 112, height: 46),
            writableFrame: CGRect(x: 102, y: 182, width: 296, height: 74),
            chordLayouts: [],
            noteLayouts: [],
            repeatMarkerLayouts: [],
            cueTextLayouts: [],
            leadingBarline: .double,
            barlineAfter: .single,
            meterChange: nil,
            meterChangeFrame: nil,
            trailingBarlineFrame: CGRect(x: 220, y: 188, width: 1.6, height: 58),
            isOpen: false
        )
        let rightMeasure = LeadSheetMeasureLayout(
            id: rightMeasureID,
            sourceMeasureID: rightMeasureID,
            chordInkTargetMeasureID: rightMeasureID,
            index: 2,
            frame: CGRect(x: 220, y: 180, width: 126, height: 78),
            staffFrame: CGRect(x: 220, y: 188, width: 126, height: 58),
            chordBandFrame: CGRect(x: 224, y: 194, width: 118, height: 46),
            writableFrame: CGRect(x: 222, y: 182, width: 122, height: 74),
            chordLayouts: [],
            noteLayouts: [],
            repeatMarkerLayouts: [],
            cueTextLayouts: [],
            leadingBarline: nil,
            barlineAfter: .single,
            meterChange: nil,
            meterChangeFrame: nil,
            trailingBarlineFrame: CGRect(x: 346, y: 188, width: 1.6, height: 58),
            isOpen: false
        )
        let layout = LeadSheetPageLayout(
            pageBounds: CGRect(x: 0, y: 0, width: 500, height: 500),
            paperFrame: CGRect(x: 80, y: 80, width: 340, height: 340),
            header: LeadSheetHeaderLayout(
                frame: CGRect(x: 100, y: 90, width: 280, height: 40),
                handwrittenFrame: CGRect(x: 100, y: 90, width: 280, height: 40),
                titleFrame: CGRect(x: 100, y: 90, width: 280, height: 40),
                composerFrame: nil,
                styleNoteFrame: nil,
                keyFrame: nil,
                meterFrame: nil
            ),
            systems: [
                LeadSheetSystemLayout(
                    id: UUID(),
                    index: 0,
                    frame: CGRect(x: 100, y: 170, width: 260, height: 96),
                    staffLineYPositions: [],
                    clefFrame: nil,
                    keySignatureLayouts: [],
                    keyTextFrame: nil,
                    keyText: nil,
                    timeSignatureFrame: nil,
                    sectionTextFrame: nil,
                    sectionText: nil,
                    roadmapTextFrame: nil,
                    roadmapText: nil,
                    roadmapMarkerLayouts: [],
                    endingLayouts: [],
                    measures: [leftMeasure, rightMeasure]
                )
            ]
        )

        let target = try XCTUnwrap(
            LeadSheetCanvasInteractionTargeting.chordMoveTarget(
                measureAnchor: CGPoint(x: 236, y: 218),
                fractionAnchorX: 228,
                in: layout
            )
        )

        XCTAssertTrue(leftMeasure.frame.contains(CGPoint(x: 236, y: 218)))
        XCTAssertTrue(rightMeasure.chordBandFrame.contains(CGPoint(x: 236, y: 218)))
        XCTAssertEqual(target.measureID, rightMeasureID)
        XCTAssertEqual(target.fraction, (228 - 224) / 118.0, accuracy: 0.0001)
    }

    func testChordMoveTargetUsesMeasureLocalFractionInMultiMeasureLaneGap() throws {
        let leftMeasureID = UUID()
        let rightMeasureID = UUID()
        let leftMeasure = LeadSheetMeasureLayout(
            id: leftMeasureID,
            sourceMeasureID: leftMeasureID,
            chordInkTargetMeasureID: leftMeasureID,
            index: 1,
            frame: CGRect(x: 100, y: 180, width: 140, height: 78),
            staffFrame: CGRect(x: 100, y: 188, width: 140, height: 58),
            chordBandFrame: CGRect(x: 104, y: 194, width: 90, height: 46),
            writableFrame: CGRect(x: 102, y: 182, width: 136, height: 74),
            chordLayouts: [],
            noteLayouts: [],
            repeatMarkerLayouts: [],
            cueTextLayouts: [],
            leadingBarline: .double,
            barlineAfter: .single,
            meterChange: nil,
            meterChangeFrame: nil,
            trailingBarlineFrame: CGRect(x: 240, y: 188, width: 1.6, height: 58),
            isOpen: false
        )
        let rightMeasure = LeadSheetMeasureLayout(
            id: rightMeasureID,
            sourceMeasureID: rightMeasureID,
            chordInkTargetMeasureID: rightMeasureID,
            index: 2,
            frame: CGRect(x: 240, y: 180, width: 120, height: 78),
            staffFrame: CGRect(x: 240, y: 188, width: 120, height: 58),
            chordBandFrame: CGRect(x: 264, y: 194, width: 80, height: 46),
            writableFrame: CGRect(x: 242, y: 182, width: 116, height: 74),
            chordLayouts: [],
            noteLayouts: [],
            repeatMarkerLayouts: [],
            cueTextLayouts: [],
            leadingBarline: nil,
            barlineAfter: .single,
            meterChange: nil,
            meterChangeFrame: nil,
            trailingBarlineFrame: CGRect(x: 360, y: 188, width: 1.6, height: 58),
            isOpen: false
        )
        let layout = LeadSheetPageLayout(
            pageBounds: CGRect(x: 0, y: 0, width: 500, height: 500),
            paperFrame: CGRect(x: 80, y: 80, width: 340, height: 340),
            header: LeadSheetHeaderLayout(
                frame: CGRect(x: 100, y: 90, width: 280, height: 40),
                handwrittenFrame: CGRect(x: 100, y: 90, width: 280, height: 40),
                titleFrame: CGRect(x: 100, y: 90, width: 280, height: 40),
                composerFrame: nil,
                styleNoteFrame: nil,
                keyFrame: nil,
                meterFrame: nil
            ),
            systems: [
                LeadSheetSystemLayout(
                    id: UUID(),
                    index: 0,
                    frame: CGRect(x: 100, y: 170, width: 260, height: 96),
                    staffLineYPositions: [],
                    clefFrame: nil,
                    keySignatureLayouts: [],
                    keyTextFrame: nil,
                    keyText: nil,
                    timeSignatureFrame: nil,
                    sectionTextFrame: nil,
                    sectionText: nil,
                    roadmapTextFrame: nil,
                    roadmapText: nil,
                    roadmapMarkerLayouts: [],
                    endingLayouts: [],
                    measures: [leftMeasure, rightMeasure]
                )
            ]
        )

        let target = try XCTUnwrap(
            LeadSheetCanvasInteractionTargeting.chordMoveTarget(
                measureAnchor: CGPoint(x: 252, y: 218),
                fractionAnchorX: 270,
                in: layout
            )
        )

        XCTAssertFalse(rightMeasure.chordBandFrame.contains(CGPoint(x: 252, y: 218)))
        XCTAssertEqual(target.measureID, rightMeasureID)
        XCTAssertEqual(target.fraction, (270 - 264) / 80.0, accuracy: 0.0001)
    }

    func testChordMoveDragTargetsFullWidthOpenChordLane() throws {
        var chart = Chart.draft(title: "Open Lane Drag", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(
            title: "Open Lane Drag",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 1
        )
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        let chordID = try XCTUnwrap(
            chart.appendRecognizedChordEvent(
                try ChordSymbolParser.parse("C"),
                rawInput: "C",
                to: measureID,
                atFraction: 0.05
            )
        )
        let sourceLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1200)
        )
        let laneFrame = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingInputFrames(for: sourceLayout).first)
        let sourceMeasure = try XCTUnwrap(sourceLayout.systems.first?.measures.first)
        let sourceChordLayout = try XCTUnwrap(sourceMeasure.chordLayouts.first { $0.id == chordID })
        let startLocation = CGPoint(x: sourceChordLayout.frame.midX, y: sourceChordLayout.frame.midY)
        let drag = ActiveChordMoveDrag(
            chordID: chordID,
            sourcePageLayout: sourceLayout,
            initialFrame: sourceChordLayout.frame,
            currentFrame: sourceChordLayout.frame,
            startLocation: startLocation
        )
        let openLaneLocation = CGPoint(
            x: laneFrame.maxX - 28,
            y: laneFrame.midY
        )

        let target = try XCTUnwrap(
            LeadSheetChordMoveDragPolicy.target(
                at: openLaneLocation,
                for: drag
            )
        )

        XCTAssertEqual(target.measureID, measureID)
        XCTAssertGreaterThan(target.fraction, 0.85)
    }

    func testChordMoveTargetUsesCommittedSimpleTerminalSpan() throws {
        let fixture = try committedTerminalSpanFixture()
        let measureID = try XCTUnwrap(fixture.measure.sourceMeasureID)

        let target = try XCTUnwrap(
            LeadSheetCanvasInteractionTargeting.chordMoveTarget(
                measureAnchor: fixture.location,
                fractionAnchorX: fixture.location.x,
                in: fixture.layout
            )
        )
        XCTAssertEqual(target.measureID, measureID)
        XCTAssertGreaterThan(target.fraction, 0.8)
    }

    func testChordMoveTargetSnapsToBeatAnchorWhenChartProvided() throws {
        let chart = Chart.blank(title: "Chord Position Guides", measureCount: 1, layoutStyle: .simpleChordSheet)
        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1200)
        )
        let measure = try XCTUnwrap(layout.systems.first?.measures.first)
        let measureID = try XCTUnwrap(measure.sourceMeasureID)
        let seedPreview = try XCTUnwrap(
            LeadSheetCanvasInteractionTargeting.chordMovePositionPreview(
                measureAnchor: CGPoint(x: measure.chordBandFrame.midX, y: measure.chordBandFrame.midY),
                fractionAnchorX: measure.chordBandFrame.midX,
                in: layout,
                chart: chart
            )
        )
        let secondBeatGuideX = try XCTUnwrap(seedPreview.guideXs.dropFirst().first)
        let nearSecondBeatX = secondBeatGuideX + 6
        let location = CGPoint(x: nearSecondBeatX, y: measure.chordBandFrame.midY)

        let target = try XCTUnwrap(
            LeadSheetCanvasInteractionTargeting.chordMoveTarget(
                measureAnchor: location,
                fractionAnchorX: nearSecondBeatX,
                in: layout,
                chart: chart
            )
        )

        XCTAssertEqual(target.measureID, measureID)
        XCTAssertEqual(
            target.fraction,
            Double((secondBeatGuideX - measure.chordBandFrame.minX) / measure.chordBandFrame.width),
            accuracy: 0.0001
        )
    }

    func testChordMoveTargetKeepsRawFractionOutsideBeatAnchorTolerance() throws {
        let chart = Chart.blank(title: "Chord Raw Position", measureCount: 1, layoutStyle: .simpleChordSheet)
        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1200)
        )
        let measure = try XCTUnwrap(layout.systems.first?.measures.first)
        let measureID = try XCTUnwrap(measure.sourceMeasureID)
        let seedPreview = try XCTUnwrap(
            LeadSheetCanvasInteractionTargeting.chordMovePositionPreview(
                measureAnchor: CGPoint(x: measure.chordBandFrame.midX, y: measure.chordBandFrame.midY),
                fractionAnchorX: measure.chordBandFrame.midX,
                in: layout,
                chart: chart
            )
        )
        let secondBeatGuideX = try XCTUnwrap(seedPreview.guideXs.dropFirst().first)
        let thirdBeatGuideX = try XCTUnwrap(seedPreview.guideXs.dropFirst(2).first)
        XCTAssertGreaterThan(
            thirdBeatGuideX - secondBeatGuideX,
            LeadSheetChordMovePositionGuidePolicy.snapTolerance * 2
        )
        let targetX = (secondBeatGuideX + thirdBeatGuideX) / 2
        let rawFraction = (targetX - measure.chordBandFrame.minX) / measure.chordBandFrame.width
        let location = CGPoint(x: targetX, y: measure.chordBandFrame.midY)

        let target = try XCTUnwrap(
            LeadSheetCanvasInteractionTargeting.chordMoveTarget(
                measureAnchor: location,
                fractionAnchorX: targetX,
                in: layout,
                chart: chart
            )
        )

        XCTAssertEqual(target.measureID, measureID)
        XCTAssertEqual(target.fraction, Double(rawFraction), accuracy: 0.0001)
    }

    func testChordMovePositionPreviewReportsActiveBeatGuide() throws {
        let chart = Chart.blank(title: "Chord Guide Preview", measureCount: 1, layoutStyle: .simpleChordSheet)
        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1200)
        )
        let measure = try XCTUnwrap(layout.systems.first?.measures.first)
        let seedPreview = try XCTUnwrap(
            LeadSheetCanvasInteractionTargeting.chordMovePositionPreview(
                measureAnchor: CGPoint(x: measure.chordBandFrame.midX, y: measure.chordBandFrame.midY),
                fractionAnchorX: measure.chordBandFrame.midX,
                in: layout,
                chart: chart
            )
        )
        let thirdBeatGuideX = try XCTUnwrap(seedPreview.guideXs.dropFirst(2).first)
        let targetX = thirdBeatGuideX - 5
        let location = CGPoint(x: targetX, y: measure.chordBandFrame.midY)

        let preview = try XCTUnwrap(
            LeadSheetCanvasInteractionTargeting.chordMovePositionPreview(
                measureAnchor: location,
                fractionAnchorX: targetX,
                in: layout,
                chart: chart
            )
        )

        XCTAssertEqual(preview.guideXs.count, 4)
        XCTAssertEqual(preview.targetX, thirdBeatGuideX, accuracy: 0.0001)
        XCTAssertNotNil(preview.activeGuideX)
    }

    func testChordMovePositionGuideStartsPastLeadingRepeatMarker() throws {
        let chart = Chart.blank(title: "Chord Guide Repeat", measureCount: 1, layoutStyle: .simpleChordSheet)
        var layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1200)
        )
        var system = try XCTUnwrap(layout.systems.first)
        var measure = try XCTUnwrap(system.measures.first)
        let repeatMarker = LeadSheetRepeatMarkerLayout(
            roadmapObjectID: UUID(),
            edge: .leading,
            frame: CGRect(
                x: measure.chordBandFrame.minX + 4,
                y: measure.chordBandFrame.minY,
                width: 24,
                height: measure.chordBandFrame.height
            )
        )
        measure.repeatMarkerLayouts = [repeatMarker]
        system.measures[0] = measure
        layout.systems[0] = system

        let preview = try XCTUnwrap(
            LeadSheetCanvasInteractionTargeting.chordMovePositionPreview(
                measureAnchor: CGPoint(x: repeatMarker.frame.maxX + 4, y: measure.chordBandFrame.midY),
                fractionAnchorX: repeatMarker.frame.maxX + 4,
                in: layout,
                chart: chart
            )
        )

        XCTAssertGreaterThanOrEqual(
            preview.guideFrame.minX,
            repeatMarker.frame.maxX + LeadSheetChordMovePositionGuidePolicy.artifactGap - 0.001
        )
        XCTAssertEqual(try XCTUnwrap(preview.guideXs.first), preview.guideFrame.minX)
    }

    func testChordMovePositionGuideStartsPastInlineMeterChange() throws {
        let chart = Chart.blank(title: "Chord Guide Meter", measureCount: 1, layoutStyle: .simpleChordSheet)
        var layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1200)
        )
        var system = try XCTUnwrap(layout.systems.first)
        var measure = try XCTUnwrap(system.measures.first)
        let meterFrame = CGRect(
            x: measure.chordBandFrame.minX + 6,
            y: measure.chordBandFrame.minY,
            width: 28,
            height: measure.chordBandFrame.height
        )
        measure.meterChangeFrame = meterFrame
        system.measures[0] = measure
        layout.systems[0] = system

        let preview = try XCTUnwrap(
            LeadSheetCanvasInteractionTargeting.chordMovePositionPreview(
                measureAnchor: CGPoint(x: meterFrame.maxX + 4, y: measure.chordBandFrame.midY),
                fractionAnchorX: meterFrame.maxX + 4,
                in: layout,
                chart: chart
            )
        )

        XCTAssertGreaterThanOrEqual(
            preview.guideFrame.minX,
            meterFrame.maxX + LeadSheetChordMovePositionGuidePolicy.artifactGap - 0.001
        )
    }

    func testCommittedChordBarlineOverlayRequiresDeleteControlForDeletion() throws {
        let chart = Chart.blank(title: "Barline Delete", measureCount: 2, layoutStyle: .simpleChordSheet)
        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1200)
        )
        let measure = try XCTUnwrap(layout.systems.first?.measures.first)
        let measureID = try XCTUnwrap(measure.sourceMeasureID)
        let lineFrame = LeadSheetCommittedChordBarlineOverlayGeometry.lineFrame(for: measure)

        let selectTarget = LeadSheetCommittedChordBarlineOverlayGeometry.hitTarget(
            at: CGPoint(x: lineFrame.midX, y: lineFrame.midY),
            measures: [measure],
            selectedMeasureID: nil
        )
        XCTAssertEqual(selectTarget, CommittedChordBarlineHitTarget(measureID: measureID, action: .select))

        let selectedLineTarget = LeadSheetCommittedChordBarlineOverlayGeometry.hitTarget(
            at: CGPoint(x: lineFrame.midX, y: lineFrame.midY),
            measures: [measure],
            selectedMeasureID: measureID
        )
        XCTAssertEqual(selectedLineTarget, CommittedChordBarlineHitTarget(measureID: measureID, action: .select))

        let deleteFrame = LeadSheetCommittedChordBarlineOverlayGeometry.controlFrames(for: measure).delete
        let deleteByControlTarget = LeadSheetCommittedChordBarlineOverlayGeometry.hitTarget(
            at: CGPoint(x: deleteFrame.midX, y: deleteFrame.midY),
            measures: [measure],
            selectedMeasureID: measureID
        )
        XCTAssertEqual(deleteByControlTarget, CommittedChordBarlineHitTarget(measureID: measureID, action: .delete))
    }

    func testChordResizeHandlesRequireSelectedChordAndPreviewSideDrag() throws {
        var chart = Chart.blank(title: "Resize Chord", measureCount: 1, layoutStyle: .simpleChordSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        let chordID = try XCTUnwrap(
            chart.appendRecognizedChordEvent(
                try ChordSymbolParser.parse("Cmaj7"),
                rawInput: "Cmaj7",
                to: measureID,
                atFraction: 0.05
            )
        )
        let sourceLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1200)
        )
        let sourceMeasure = try XCTUnwrap(sourceLayout.systems.first?.measures.first)
        let sourceChordLayout = try XCTUnwrap(sourceMeasure.chordLayouts.first { $0.id == chordID })
        let controlFrames = LeadSheetChordEditOverlayGeometry.controlFrames(for: sourceChordLayout)

        XCTAssertNil(
            LeadSheetChordEditOverlayGeometry.resizeHitTarget(
                at: CGPoint(x: controlFrames.trailingResize.midX, y: controlFrames.trailingResize.midY),
                in: sourceLayout,
                selectedChordID: nil
            )
        )

        let trailingTarget = try XCTUnwrap(
            LeadSheetChordEditOverlayGeometry.resizeHitTarget(
                at: CGPoint(x: controlFrames.trailingResize.midX, y: controlFrames.trailingResize.midY),
                in: sourceLayout,
                selectedChordID: chordID
            )
        )
        XCTAssertEqual(trailingTarget.chordID, chordID)
        XCTAssertEqual(trailingTarget.action, .resizeTrailing)

        let trailingDrag = ActiveChordResizeDrag(
            chordID: chordID,
            sourcePageLayout: sourceLayout,
            edge: .trailing,
            initialFrame: sourceChordLayout.frame,
            currentFrame: sourceChordLayout.frame,
            startLocation: CGPoint(x: controlFrames.trailingResize.midX, y: controlFrames.trailingResize.midY)
        )
        let widenedFrame = LeadSheetChordResizeDragPolicy.previewFrame(
            for: trailingDrag,
            at: CGPoint(x: controlFrames.trailingResize.midX + 48, y: controlFrames.trailingResize.midY),
            boundedBy: sourceLayout.paperFrame
        )
        XCTAssertEqual(widenedFrame.minX, sourceChordLayout.frame.minX, accuracy: 0.001)
        XCTAssertEqual(widenedFrame.width, sourceChordLayout.frame.width + 48, accuracy: 0.001)

        XCTAssertNil(
            LeadSheetChordEditOverlayGeometry.resizeHitTarget(
                at: CGPoint(x: controlFrames.leadingResize.midX, y: controlFrames.leadingResize.midY),
                in: sourceLayout,
                selectedChordID: chordID
            )
        )
    }

    func testBrowseModeKeepsCueTextEditable() {
        XCTAssertTrue(EditorCanvasMode.browse.allowsCueTextEditing)
    }

    func testRhythmChordInkScopeKeepsThinLaneAboveStaff() throws {
        let chart = Chart.blank(title: "Top Lane Chord", measureCount: 4, layoutStyle: .rhythmSectionSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1200)
        )
        let measure = try XCTUnwrap(layout.systems.first?.measures.first)
        let laneFrame = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingInputFrames(for: layout).first)
        let chordFrame = LeadSheetActiveInkScope.chordWritingFrame(for: layout)
        let inkCenterX = measure.chordBandFrame.midX
        let inkStartInView = CGPoint(
            x: inkCenterX - 8,
            y: laneFrame.midY - 8
        )
        let inkEndInView = CGPoint(
            x: inkCenterX + 8,
            y: laneFrame.midY + 4
        )
        let localStart = CGPoint(
            x: inkStartInView.x - chordFrame.minX,
            y: inkStartInView.y - chordFrame.minY
        )
        let localEnd = CGPoint(
            x: inkEndInView.x - chordFrame.minX,
            y: inkEndInView.y - chordFrame.minY
        )

        XCTAssertLessThan(laneFrame.height, measure.chordWritingFrame.height)
        XCTAssertTrue(laneFrame.contains(CGPoint(x: measure.chordBandFrame.midX, y: measure.chordBandFrame.midY)))
        XCTAssertLessThan(laneFrame.maxY, measure.staffFrame.minY)
        XCTAssertFalse(laneFrame.contains(CGPoint(x: measure.staffFrame.midX, y: measure.staffFrame.minY + 4)))

        let drawing = PKDrawing(strokes: [
            stroke(points: [localStart, localEnd], creationDate: Date(timeIntervalSince1970: 30))
        ])
        let target = try XCTUnwrap(
            LeadSheetChordInkRecognitionTargeting.target(
                for: drawing,
                chordFrame: chordFrame,
                pageLayout: layout
            )
        )

        XCTAssertEqual(target.measureID, measureID)
        XCTAssertGreaterThanOrEqual(target.fraction, 0)
        XCTAssertLessThan(target.fraction, 1)
    }

    func testChordTargetingUsesRhythmFirstMeasureBodyAfterSetupExtension() throws {
        let chart = Chart.blank(title: "Top Lane Chord", measureCount: 4, layoutStyle: .rhythmSectionSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1200)
        )
        let measure = try XCTUnwrap(layout.systems.first?.measures.first)
        let chordFrame = LeadSheetActiveInkScope.chordWritingFrame(for: layout)
        let setupExtensionPoint = CGPoint(
            x: measure.frame.minX + 20,
            y: measure.chordWritingFrame.midY
        )
        let inkStartX = measure.staffFrame.minX + measure.staffFrame.width * 0.08
        let drawing = PKDrawing(strokes: [
            chordStroke(
                in: measure,
                fromX: inkStartX,
                toX: inkStartX + 16,
                chordFrame: chordFrame
            )
        ])

        XCTAssertGreaterThan(measure.staffFrame.minX, measure.frame.minX)
        XCTAssertEqual(measure.chordWritingFrame.minX, measure.staffFrame.minX + 2, accuracy: 0.001)
        XCTAssertLessThan(measure.chordWritingFrame.width, measure.frame.width)
        XCTAssertFalse(LeadSheetCanvasInteractionTargeting.chordWritingBandContains(setupExtensionPoint, in: layout))

        let target = try XCTUnwrap(
            LeadSheetChordInkRecognitionTargeting.target(
                for: drawing,
                chordFrame: chordFrame,
                pageLayout: layout
            )
        )

        XCTAssertEqual(target.measureID, measureID)
        XCTAssertGreaterThanOrEqual(target.fraction, 0)
        XCTAssertLessThan(target.fraction, 0.2)
    }

    func testRhythmChordBatchTargetingUsesDraftBarlineSegmentsInsideThinLane() throws {
        var chart = Chart.draft(title: "Rhythm Draft Boundary Chords", layoutStyle: .rhythmSectionSheet)
        chart.completeInitialSetup(
            title: "Rhythm Draft Boundary Chords",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 1,
            clef: .bass
        )
        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1200)
        )
        let measure = try XCTUnwrap(layout.systems.first?.measures.first)
        let measureID = try XCTUnwrap(measure.sourceMeasureID)
        let chordFrame = LeadSheetActiveInkScope.chordWritingFrame(for: layout)
        let laneFrame = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingInputFrames(for: layout).first)
        let barlineFraction = 0.52
        let barlineX = laneFrame.minX + laneFrame.width * CGFloat(barlineFraction)
        let y = laneFrame.midY
        let drawing = PKDrawing(strokes: [
            stroke(
                points: [
                    CGPoint(x: barlineX - 46 - chordFrame.minX, y: y - 14 - chordFrame.minY),
                    CGPoint(x: barlineX - 22 - chordFrame.minX, y: y + 12 - chordFrame.minY)
                ],
                creationDate: Date(timeIntervalSince1970: 40)
            ),
            stroke(
                points: [
                    CGPoint(x: barlineX + 22 - chordFrame.minX, y: y - 14 - chordFrame.minY),
                    CGPoint(x: barlineX + 46 - chordFrame.minX, y: y + 12 - chordFrame.minY)
                ],
                creationDate: Date(timeIntervalSince1970: 41)
            )
        ])

        XCTAssertLessThan(measure.chordBandFrame.height, measure.chordWritingFrame.height)
        XCTAssertTrue(measure.chordWritingFrame.contains(measure.chordBandFrame))

        let result = LeadSheetChordInkRecognitionTargeting.batchTargetingResult(
            for: drawing,
            chordFrame: chordFrame,
            pageLayout: layout,
            draftBarlines: [
                DraftBarline(
                    measureID: measureID,
                    measureIndex: measure.index,
                    fraction: barlineFraction,
                    laneLocation: ChordInkDraftLaneLocation(systemIndex: 0, fraction: barlineFraction),
                    metrics: DraftBarlineGestureMetrics(
                        height: Double(laneFrame.height),
                        width: 2,
                        angleDegreesFromVertical: 0,
                        straightness: 1,
                        laneCoverage: 1
                    )
                )
            ]
        )

        XCTAssertEqual(
            result.targets.count,
            2,
            "route=\(result.diagnostics.selectedRoute) draft=\(result.diagnostics.draftBarlineClusterCount) laneSequence=\(result.diagnostics.laneSequentialClusterCount) measure=\(result.diagnostics.measureLaneClusterCount) fallback=\(result.diagnostics.fallbackClusterCount) selected=\(result.diagnostics.selectedClusterCount)"
        )
        XCTAssertEqual(result.diagnostics.selectedRoute, "draft_barline_lane")
        XCTAssertEqual(result.targets.map(\.measureID), [measureID, measureID])
        XCTAssertLessThan(result.targets[0].laneLocation?.fraction ?? 1, barlineFraction)
        XCTAssertGreaterThan(result.targets[1].laneLocation?.fraction ?? 0, barlineFraction)
        XCTAssertLessThan(result.targets[0].visualOrder, result.targets[1].visualOrder)
    }

    func testChordTargetingUsesCommittedSimpleTerminalSpan() throws {
        let fixture = try committedTerminalSpanFixture()
        let measureID = try XCTUnwrap(fixture.measure.sourceMeasureID)
        let chordFrame = LeadSheetActiveInkScope.chordWritingFrame(for: fixture.layout)
        let localCenter = CGPoint(
            x: fixture.location.x - chordFrame.minX,
            y: fixture.location.y - chordFrame.minY
        )
        let drawing = PKDrawing(strokes: [
            stroke(
                points: [
                    CGPoint(x: localCenter.x - 9, y: localCenter.y - 9),
                    CGPoint(x: localCenter.x + 9, y: localCenter.y + 9)
                ],
                creationDate: Date(timeIntervalSince1970: 30)
            )
        ])

        let target = try XCTUnwrap(
            LeadSheetChordInkRecognitionTargeting.target(
                for: drawing,
                chordFrame: chordFrame,
                pageLayout: fixture.layout
            )
        )
        XCTAssertEqual(target.measureID, measureID)
        XCTAssertGreaterThan(target.fraction, 0.8)
    }

    func testChordBatchTargetingSplitsAdjacentMeasureChordGroups() throws {
        let chart = Chart.blank(title: "Batch Chords", measureCount: 4, layoutStyle: .simpleChordSheet)
        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1200)
        )
        let measures = Array(layout.systems.flatMap(\.measures).prefix(3))
        XCTAssertEqual(measures.count, 3)
        let measureIDs = try measures.map { measure in
            try XCTUnwrap(measure.sourceMeasureID)
        }
        let chordFrame = LeadSheetActiveInkScope.chordWritingFrame(for: layout)
        let drawing = PKDrawing(strokes: [
            chordStroke(in: measures[0], fromX: measures[0].chordWritingFrame.maxX - 24, toX: measures[0].chordWritingFrame.maxX - 10, chordFrame: chordFrame),
            chordStroke(in: measures[1], fromX: measures[1].chordWritingFrame.minX + 10, toX: measures[1].chordWritingFrame.minX + 24, chordFrame: chordFrame),
            chordStroke(in: measures[2], fromX: measures[2].chordWritingFrame.minX + 10, toX: measures[2].chordWritingFrame.minX + 24, chordFrame: chordFrame)
        ])

        let targets = LeadSheetChordInkRecognitionTargeting.batchTargets(
            for: drawing,
            chordFrame: chordFrame,
            pageLayout: layout
        )

        XCTAssertEqual(targets.count, 3)
        XCTAssertEqual(targets.map(\.measureID), measureIDs)
    }

    func testChordBatchTargetingDoesNotSplitSingleGlyphFragmentsIntoMultipleDraftTargets() throws {
        let chart = Chart.blank(title: "Single Glyph", measureCount: 1, layoutStyle: .simpleChordSheet)
        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1200)
        )
        let laneFrame = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingInputFrames(for: layout).first)
        let chordFrame = LeadSheetActiveInkScope.chordWritingFrame(for: layout)
        let baselineY = laneFrame.midY
        let stemX = laneFrame.minX + 72
        let bowlStartX = stemX + 45
        let drawing = PKDrawing(strokes: [
            stroke(
                points: [
                    CGPoint(x: stemX - chordFrame.minX, y: baselineY - 22 - chordFrame.minY),
                    CGPoint(x: stemX - chordFrame.minX, y: baselineY + 22 - chordFrame.minY)
                ],
                creationDate: Date(timeIntervalSince1970: 40)
            ),
            stroke(
                points: [
                    CGPoint(x: bowlStartX - chordFrame.minX, y: baselineY - 21 - chordFrame.minY),
                    CGPoint(x: bowlStartX + 24 - chordFrame.minX, y: baselineY - 2 - chordFrame.minY),
                    CGPoint(x: bowlStartX - chordFrame.minX, y: baselineY + 21 - chordFrame.minY)
                ],
                creationDate: Date(timeIntervalSince1970: 41)
            )
        ])

        XCTAssertEqual(ChordInkBatchClusterer.clusters(for: PencilKitInkAdapter.inkStrokes(from: drawing)).count, 2)
        XCTAssertTrue(
            LeadSheetChordInkRecognitionTargeting.batchTargets(
                for: drawing,
                chordFrame: chordFrame,
                pageLayout: layout
            ).isEmpty
        )
    }

    func testChordBatchTargetingSplitsClearlySeparatedOpenLaneChordGroups() throws {
        var chart = Chart.draft(title: "Open Lane Chords", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(
            title: "Open Lane Chords",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 1
        )
        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1200)
        )
        let laneFrame = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingInputFrames(for: layout).first)
        let chordFrame = LeadSheetActiveInkScope.chordWritingFrame(for: layout)
        let baselineY = laneFrame.midY
        let firstX = laneFrame.minX + 70
        let secondX = firstX + 130
        let drawing = PKDrawing(strokes: [
            stroke(
                points: [
                    CGPoint(x: firstX - chordFrame.minX, y: baselineY - 22 - chordFrame.minY),
                    CGPoint(x: firstX + 26 - chordFrame.minX, y: baselineY - 4 - chordFrame.minY),
                    CGPoint(x: firstX + 4 - chordFrame.minX, y: baselineY + 22 - chordFrame.minY)
                ],
                creationDate: Date(timeIntervalSince1970: 40)
            ),
            stroke(
                points: [
                    CGPoint(x: secondX - chordFrame.minX, y: baselineY - 22 - chordFrame.minY),
                    CGPoint(x: secondX + 26 - chordFrame.minX, y: baselineY - 4 - chordFrame.minY),
                    CGPoint(x: secondX + 4 - chordFrame.minX, y: baselineY + 22 - chordFrame.minY)
                ],
                creationDate: Date(timeIntervalSince1970: 41)
            )
        ])

        let targets = LeadSheetChordInkRecognitionTargeting.batchTargets(
            for: drawing,
            chordFrame: chordFrame,
            pageLayout: layout
        )

        XCTAssertEqual(targets.count, 2)
        XCTAssertLessThan(targets[0].visualOrder, targets[1].visualOrder)
    }

    func testChordBatchTargetingFallsBackWhenLaneRootSequenceWouldDropContinuationLaneStroke() throws {
        var chart = Chart.draft(title: "Partial Lane Root Sequence", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(
            title: "Partial Lane Root Sequence",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 1
        )
        let openMeasureID = try XCTUnwrap(chart.measures.first(where: { $0.authoringState == .open })?.id)
        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400),
            includesChordInkContinuationLanes: true
        )
        let chordRegion = LeadSheetActiveInkScope.chordWritingRegion(for: layout)
        let firstLane = try XCTUnwrap(chordRegion.inputFrames.first)
        let continuationLane = try XCTUnwrap(chordRegion.inputFrames.dropFirst().first)
        let firstBaselineY = firstLane.midY
        let continuationBaselineY = continuationLane.midY
        let firstX = firstLane.minX + 70
        let secondX = firstX + 130
        let continuationX = continuationLane.minX + 90
        let drawing = PKDrawing(strokes: [
            stroke(
                points: [
                    CGPoint(x: firstX - chordRegion.frame.minX, y: firstBaselineY - 22 - chordRegion.frame.minY),
                    CGPoint(x: firstX + 26 - chordRegion.frame.minX, y: firstBaselineY - 4 - chordRegion.frame.minY),
                    CGPoint(x: firstX + 4 - chordRegion.frame.minX, y: firstBaselineY + 22 - chordRegion.frame.minY)
                ],
                creationDate: Date(timeIntervalSince1970: 40)
            ),
            stroke(
                points: [
                    CGPoint(x: secondX - chordRegion.frame.minX, y: firstBaselineY - 22 - chordRegion.frame.minY),
                    CGPoint(x: secondX + 26 - chordRegion.frame.minX, y: firstBaselineY - 4 - chordRegion.frame.minY),
                    CGPoint(x: secondX + 4 - chordRegion.frame.minX, y: firstBaselineY + 22 - chordRegion.frame.minY)
                ],
                creationDate: Date(timeIntervalSince1970: 41)
            ),
            stroke(
                points: [
                    CGPoint(x: continuationX - chordRegion.frame.minX, y: continuationBaselineY - 22 - chordRegion.frame.minY),
                    CGPoint(x: continuationX + 26 - chordRegion.frame.minX, y: continuationBaselineY - 4 - chordRegion.frame.minY),
                    CGPoint(x: continuationX + 4 - chordRegion.frame.minX, y: continuationBaselineY + 22 - chordRegion.frame.minY)
                ],
                creationDate: Date(timeIntervalSince1970: 42)
            )
        ])

        let result = LeadSheetChordInkRecognitionTargeting.batchTargetingResult(
            for: drawing,
            chordFrame: chordRegion.frame,
            pageLayout: layout
        )

        XCTAssertEqual(result.diagnostics.selectedRoute, "measure_lane")
        XCTAssertEqual(result.diagnostics.laneSequentialClusterCount, 0)
        XCTAssertEqual(result.targets.count, 3)
        XCTAssertEqual(result.targets.map(\.measureID), [openMeasureID, openMeasureID, openMeasureID])
        XCTAssertEqual(result.targets.map { $0.laneLocation?.systemIndex }, [0, 0, 1])
        XCTAssertEqual(result.targets.flatMap(\.strokes).count, 3)
    }

    func testChordBatchTargetingDoesNotAbsorbDetachedDIntoPriorCOpenLaneRoot() throws {
        var chart = Chart.draft(title: "Open Lane C Then D", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(
            title: "Open Lane C Then D",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 1
        )
        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1200)
        )
        let laneFrame = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingInputFrames(for: layout).first)
        let chordFrame = LeadSheetActiveInkScope.chordWritingFrame(for: layout)
        let transformedStrokes = deviceCThenDetachedDPointSets(
            offsetX: laneFrame.minX + 64 - chordFrame.minX - 193.9,
            offsetY: laneFrame.midY - chordFrame.minY - 68
        )
        let drawing = PKDrawing(strokes: transformedStrokes.enumerated().map { index, points in
            stroke(
                points: points,
                creationDate: Date(timeIntervalSince1970: 80 + TimeInterval(index))
            )
        })

        let targets = LeadSheetChordInkRecognitionTargeting.batchTargets(
            for: drawing,
            chordFrame: chordFrame,
            pageLayout: layout
        )

        XCTAssertEqual(targets.count, 2)
        XCTAssertEqual(targets[0].strokes.count, 1)
        XCTAssertEqual(targets[1].strokes.count, 2)
        XCTAssertLessThan(targets[0].visualOrder, targets[1].visualOrder)
    }

    func testChordBatchTargetingDoesNotAbsorbRepeatDeviceDIntoPriorCOpenLaneRoot() throws {
        var chart = Chart.draft(title: "Open Lane C Then D Repeat", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(
            title: "Open Lane C Then D Repeat",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 1
        )
        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1200)
        )
        let laneFrame = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingInputFrames(for: layout).first)
        let chordFrame = LeadSheetActiveInkScope.chordWritingFrame(for: layout)
        let transformedStrokes = repeatDeviceCThenDetachedDPointSets(
            offsetX: laneFrame.minX + 120 - chordFrame.minX - 168.1,
            offsetY: laneFrame.midY - chordFrame.minY - 70
        )
        let drawing = PKDrawing(strokes: transformedStrokes.enumerated().map { index, points in
            stroke(
                points: points,
                creationDate: Date(timeIntervalSince1970: 90 + TimeInterval(index))
            )
        })

        let targets = LeadSheetChordInkRecognitionTargeting.batchTargets(
            for: drawing,
            chordFrame: chordFrame,
            pageLayout: layout
        )

        XCTAssertEqual(targets.count, 2)
        XCTAssertEqual(targets[0].strokes.count, 1)
        XCTAssertEqual(targets[1].strokes.count, 2)
        XCTAssertLessThan(targets[0].visualOrder, targets[1].visualOrder)
    }

    func testRhythmChordBatchTargetingDoesNotCollapseDeviceCThenDIntoSingleRead() throws {
        var chart = Chart.draft(title: "Rhythm C Then D", layoutStyle: .rhythmSectionSheet)
        chart.completeInitialSetup(
            title: "Rhythm C Then D",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 1,
            clef: .bass
        )
        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1200)
        )
        let measure = try XCTUnwrap(layout.systems.first?.measures.first)
        let laneFrame = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingInputFrames(for: layout).first)
        let chordFrame = LeadSheetActiveInkScope.chordWritingFrame(for: layout)
        let transformedStrokes = repeatDeviceCThenDetachedDPointSets(
            offsetX: measure.chordWritingFrame.minX + 60 - chordFrame.minX - 168.1,
            offsetY: laneFrame.midY - chordFrame.minY - 70
        )
        let drawing = PKDrawing(strokes: transformedStrokes.enumerated().map { index, points in
            stroke(
                points: points,
                creationDate: Date(timeIntervalSince1970: 110 + TimeInterval(index))
            )
        })

        let result = LeadSheetChordInkRecognitionTargeting.batchTargetingResult(
            for: drawing,
            chordFrame: chordFrame,
            pageLayout: layout
        )

        XCTAssertEqual(
            result.targets.count,
            2,
            "route=\(result.diagnostics.selectedRoute) draft=\(result.diagnostics.draftBarlineClusterCount) laneSequence=\(result.diagnostics.laneSequentialClusterCount) measure=\(result.diagnostics.measureLaneClusterCount) fallback=\(result.diagnostics.fallbackClusterCount) selected=\(result.diagnostics.selectedClusterCount)"
        )
        XCTAssertEqual(result.diagnostics.selectedRoute, "lane_root_sequence")
        XCTAssertEqual(result.diagnostics.laneSequentialClusterCount, 2)
        XCTAssertEqual(result.targets.map(\.strokes.count), [1, 2])
        XCTAssertLessThan(result.targets[0].visualOrder, result.targets[1].visualOrder)
    }

    func testRhythmChordBatchTargetingKeepsLatestLooseCThenFragmentedDSeparate() throws {
        var chart = Chart.draft(title: "Rhythm Current Device C Then D", layoutStyle: .rhythmSectionSheet)
        chart.completeInitialSetup(
            title: "Rhythm Current Device C Then D",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 1,
            clef: .bass
        )
        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1200)
        )
        let measure = try XCTUnwrap(layout.systems.first?.measures.first)
        let laneFrame = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingInputFrames(for: layout).first)
        let chordFrame = LeadSheetActiveInkScope.chordWritingFrame(for: layout)
        let transformedStrokes = latestRhythmLooseCThenFragmentedDPointSets(
            offsetX: measure.chordWritingFrame.minX + 50 - chordFrame.minX - 56.7126,
            offsetY: laneFrame.midY - chordFrame.minY - 34
        )
        let drawing = PKDrawing(strokes: transformedStrokes.enumerated().map { index, points in
            stroke(
                points: points,
                creationDate: Date(timeIntervalSince1970: 112 + TimeInterval(index))
            )
        })

        let result = LeadSheetChordInkRecognitionTargeting.batchTargetingResult(
            for: drawing,
            chordFrame: chordFrame,
            pageLayout: layout
        )

        XCTAssertEqual(
            result.targets.count,
            2,
            "route=\(result.diagnostics.selectedRoute) draft=\(result.diagnostics.draftBarlineClusterCount) laneSequence=\(result.diagnostics.laneSequentialClusterCount) measure=\(result.diagnostics.measureLaneClusterCount) fallback=\(result.diagnostics.fallbackClusterCount) selected=\(result.diagnostics.selectedClusterCount)"
        )
        XCTAssertNotEqual(result.diagnostics.selectedRoute, "measure_lane_collapsed")
        XCTAssertEqual(result.targets.map(\.strokes.count), [1, 3])
        XCTAssertLessThan(result.targets[0].visualOrder, result.targets[1].visualOrder)
    }

    func testRhythmChordBatchTargetingKeepsLatestCloseCThenFragmentedFSeparate() throws {
        var chart = Chart.draft(title: "Rhythm Current Device C Then F", layoutStyle: .rhythmSectionSheet)
        chart.completeInitialSetup(
            title: "Rhythm Current Device C Then F",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 1,
            clef: .bass
        )
        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1200)
        )
        let measure = try XCTUnwrap(layout.systems.first?.measures.first)
        let laneFrame = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingInputFrames(for: layout).first)
        let chordFrame = LeadSheetActiveInkScope.chordWritingFrame(for: layout)
        let transformedStrokes = latestRhythmCloseCThenFragmentedFPointSets(
            offsetX: measure.chordWritingFrame.minX + 48 - chordFrame.minX - 52.6261,
            offsetY: laneFrame.midY - chordFrame.minY - 30
        )
        let drawing = PKDrawing(strokes: transformedStrokes.enumerated().map { index, points in
            stroke(
                points: points,
                creationDate: Date(timeIntervalSince1970: 116 + TimeInterval(index))
            )
        })

        let result = LeadSheetChordInkRecognitionTargeting.batchTargetingResult(
            for: drawing,
            chordFrame: chordFrame,
            pageLayout: layout
        )

        XCTAssertEqual(
            result.targets.count,
            2,
            "route=\(result.diagnostics.selectedRoute) draft=\(result.diagnostics.draftBarlineClusterCount) laneSequence=\(result.diagnostics.laneSequentialClusterCount) measure=\(result.diagnostics.measureLaneClusterCount) fallback=\(result.diagnostics.fallbackClusterCount) selected=\(result.diagnostics.selectedClusterCount)"
        )
        XCTAssertNotEqual(result.diagnostics.selectedRoute, "measure_lane_collapsed")
        XCTAssertEqual(result.targets.map(\.strokes.count), [1, 3])
        XCTAssertLessThan(result.targets[0].visualOrder, result.targets[1].visualOrder)
    }

    func testRhythmChordBatchTargetingDoesNotSplitAttachedFlatAsDetachedRoot() throws {
        var chart = Chart.draft(title: "Rhythm C Flat Guard", layoutStyle: .rhythmSectionSheet)
        chart.completeInitialSetup(
            title: "Rhythm C Flat Guard",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 1,
            clef: .bass
        )
        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1200)
        )
        let measure = try XCTUnwrap(layout.systems.first?.measures.first)
        let laneFrame = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingInputFrames(for: layout).first)
        let chordFrame = LeadSheetActiveInkScope.chordWritingFrame(for: layout)
        let baseX = measure.chordWritingFrame.minX + 50 - chordFrame.minX
        let baseY = laneFrame.midY - chordFrame.minY - 34
        let transformedStrokes = try transformedTemplatePointSets(
            "C",
            offsetX: baseX,
            offsetY: baseY,
            scale: 0.72
        ) + transformedTemplatePointSets(
            "b",
            offsetX: baseX + 33,
            offsetY: baseY + 3,
            scale: 0.34
        )
        let drawing = PKDrawing(strokes: transformedStrokes.enumerated().map { index, points in
            stroke(
                points: points,
                creationDate: Date(timeIntervalSince1970: 120 + TimeInterval(index))
            )
        })

        let result = LeadSheetChordInkRecognitionTargeting.batchTargetingResult(
            for: drawing,
            chordFrame: chordFrame,
            pageLayout: layout
        )

        XCTAssertTrue(
            result.targets.isEmpty,
            "attached flat should remain a single recognition target route=\(result.diagnostics.selectedRoute) draft=\(result.diagnostics.draftBarlineClusterCount) laneSequence=\(result.diagnostics.laneSequentialClusterCount) measure=\(result.diagnostics.measureLaneClusterCount) fallback=\(result.diagnostics.fallbackClusterCount) selected=\(result.diagnostics.selectedClusterCount) strokeCounts=\(result.targets.map(\.strokes.count))"
        )
        XCTAssertNotEqual(result.diagnostics.selectedRoute, "lane_root_sequence")
        XCTAssertNotEqual(result.diagnostics.selectedRoute, "measure_lane_root_sequence")
    }

    func testChordBatchTargetingDoesNotAbsorbRepeatDeviceDIntoPriorCWithLeftNeighbors() throws {
        var chart = Chart.draft(title: "Open Lane A B C Then D Repeat", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(
            title: "Open Lane A B C Then D Repeat",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 1
        )
        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1200)
        )
        let laneFrame = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingInputFrames(for: layout).first)
        let chordFrame = LeadSheetActiveInkScope.chordWritingFrame(for: layout)
        let transformedStrokes = repeatDeviceABCDPointSets(
            offsetX: laneFrame.minX + 40 - chordFrame.minX - 21.9,
            offsetY: laneFrame.midY - chordFrame.minY - 75
        )
        let drawing = PKDrawing(strokes: transformedStrokes.enumerated().map { index, points in
            stroke(
                points: points,
                creationDate: Date(timeIntervalSince1970: 100 + TimeInterval(index))
            )
        })

        let result = LeadSheetChordInkRecognitionTargeting.batchTargetingResult(
            for: drawing,
            chordFrame: chordFrame,
            pageLayout: layout
        )

        XCTAssertEqual(
            result.targets.count,
            4,
            "route=\(result.diagnostics.selectedRoute) draft=\(result.diagnostics.draftBarlineClusterCount) laneSequence=\(result.diagnostics.laneSequentialClusterCount) measure=\(result.diagnostics.measureLaneClusterCount) fallback=\(result.diagnostics.fallbackClusterCount) selected=\(result.diagnostics.selectedClusterCount)"
        )
        XCTAssertEqual(result.diagnostics.selectedRoute, "lane_root_sequence")
        XCTAssertEqual(result.diagnostics.laneSequentialClusterCount, 4)
        XCTAssertEqual(result.targets.map(\.strokes.count), [3, 2, 1, 2])
        XCTAssertLessThan(result.targets[0].visualOrder, result.targets[1].visualOrder)
        XCTAssertLessThan(result.targets[1].visualOrder, result.targets[2].visualOrder)
        XCTAssertLessThan(result.targets[2].visualOrder, result.targets[3].visualOrder)
    }

    func testChordBatchTargetingPreservesOriginalStrokeOrderInsideTargets() throws {
        var chart = Chart.draft(title: "Batch Stroke Order", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(
            title: "Batch Stroke Order",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 1
        )
        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1200)
        )
        let laneFrame = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingInputFrames(for: layout).first)
        let chordFrame = LeadSheetActiveInkScope.chordWritingFrame(for: layout)
        let baselineY = laneFrame.midY
        let firstX = laneFrame.minX + 72
        let secondX = firstX + 128
        let firstBody = stroke(
            points: [
                CGPoint(x: firstX + 3 - chordFrame.minX, y: baselineY - 23 - chordFrame.minY),
                CGPoint(x: firstX + 21 - chordFrame.minX, y: baselineY - 21 - chordFrame.minY),
                CGPoint(x: firstX + 34 - chordFrame.minX, y: baselineY - 10 - chordFrame.minY),
                CGPoint(x: firstX + 39 - chordFrame.minX, y: baselineY + 4 - chordFrame.minY),
                CGPoint(x: firstX + 34 - chordFrame.minX, y: baselineY + 17 - chordFrame.minY),
                CGPoint(x: firstX + 20 - chordFrame.minX, y: baselineY + 23 - chordFrame.minY),
                CGPoint(x: firstX + 3 - chordFrame.minX, y: baselineY + 22 - chordFrame.minY)
            ],
            creationDate: Date(timeIntervalSince1970: 40)
        )
        let firstStem = stroke(
            points: [
                CGPoint(x: firstX - chordFrame.minX, y: baselineY - 24 - chordFrame.minY),
                CGPoint(x: firstX - chordFrame.minX, y: baselineY + 24 - chordFrame.minY)
            ],
            creationDate: Date(timeIntervalSince1970: 41)
        )
        let secondRoot = stroke(
            points: [
                CGPoint(x: secondX - chordFrame.minX, y: baselineY - 22 - chordFrame.minY),
                CGPoint(x: secondX + 26 - chordFrame.minX, y: baselineY - 4 - chordFrame.minY),
                CGPoint(x: secondX + 4 - chordFrame.minX, y: baselineY + 22 - chordFrame.minY)
            ],
            creationDate: Date(timeIntervalSince1970: 42)
        )
        let drawing = PKDrawing(strokes: [firstBody, firstStem, secondRoot])

        let targets = LeadSheetChordInkRecognitionTargeting.batchTargets(
            for: drawing,
            chordFrame: chordFrame,
            pageLayout: layout
        )

        XCTAssertEqual(targets.count, 2)
        XCTAssertEqual(targets[0].strokes.count, 2)
        XCTAssertGreaterThan(targets[0].strokes[0].bounds.minX, targets[0].strokes[1].bounds.minX)
        XCTAssertEqual(
            PencilKitInkAdapter.inkStrokes(from: targets[0].drawing).map(\.bounds.minX),
            targets[0].strokes.map(\.bounds.minX)
        )
    }

    func testChordBatchTargetingSplitsSameOpenLaneGroupsAtDraftBarline() throws {
        var chart = Chart.draft(title: "Draft Boundary Chords", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(
            title: "Draft Boundary Chords",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 1
        )
        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1200)
        )
        let measure = try XCTUnwrap(layout.systems.first?.measures.first)
        let measureID = try XCTUnwrap(measure.sourceMeasureID)
        let chordFrame = LeadSheetActiveInkScope.chordWritingFrame(for: layout)
        let laneFrame = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingInputFrames(for: layout).first)
        let barlineFraction = 0.54
        let barlineX = laneFrame.minX + laneFrame.width * CGFloat(barlineFraction)
        let y = laneFrame.midY
        let drawing = PKDrawing(strokes: [
            stroke(
                points: [
                    CGPoint(x: barlineX - 20 - chordFrame.minX, y: y - chordFrame.minY),
                    CGPoint(x: barlineX - 10 - chordFrame.minX, y: y + 5 - chordFrame.minY)
                ],
                creationDate: Date(timeIntervalSince1970: 40)
            ),
            stroke(
                points: [
                    CGPoint(x: barlineX + 10 - chordFrame.minX, y: y - chordFrame.minY),
                    CGPoint(x: barlineX + 20 - chordFrame.minX, y: y + 5 - chordFrame.minY)
                ],
                creationDate: Date(timeIntervalSince1970: 41)
            )
        ])

        XCTAssertTrue(
            LeadSheetChordInkRecognitionTargeting.batchTargets(
                for: drawing,
                chordFrame: chordFrame,
                pageLayout: layout
            ).isEmpty
        )

        let targets = LeadSheetChordInkRecognitionTargeting.batchTargets(
            for: drawing,
            chordFrame: chordFrame,
            pageLayout: layout,
            draftBarlines: [
                DraftBarline(
                    measureID: measureID,
                    measureIndex: measure.index,
                    fraction: barlineFraction,
                    metrics: DraftBarlineGestureMetrics(
                        height: Double(laneFrame.height),
                        width: 2,
                        angleDegreesFromVertical: 0,
                        straightness: 1,
                        laneCoverage: 1
                    )
                )
            ]
        )

        XCTAssertEqual(targets.count, 2)
        XCTAssertEqual(targets.map(\.measureID), [measureID, measureID])
        XCTAssertEqual(targets.map(\.strokes.count), [1, 1])
        XCTAssertLessThan(targets[0].fraction, targets[1].fraction)
        XCTAssertLessThan(targets[0].visualOrder, targets[1].visualOrder)
    }

    func testChordBatchTargetingKeepsMultipleChordGroupsInsideDraftBarlineSegments() throws {
        var chart = Chart.draft(title: "Draft Segment Groups", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(
            title: "Draft Segment Groups",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 1
        )
        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1200)
        )
        let measure = try XCTUnwrap(layout.systems.first?.measures.first)
        let measureID = try XCTUnwrap(measure.sourceMeasureID)
        let chordFrame = LeadSheetActiveInkScope.chordWritingFrame(for: layout)
        let laneFrame = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingInputFrames(for: layout).first)
        let barlineFraction = 0.52
        let y = laneFrame.midY
        let chordXs = [0.12, 0.30, 0.64, 0.82].map { fraction in
            laneFrame.minX + laneFrame.width * CGFloat(fraction)
        }
        let drawing = PKDrawing(strokes: chordXs.enumerated().map { index, x in
            stroke(
                points: [
                    CGPoint(x: x - chordFrame.minX, y: y - 22 - chordFrame.minY),
                    CGPoint(x: x + 24 - chordFrame.minX, y: y - 4 - chordFrame.minY),
                    CGPoint(x: x + 4 - chordFrame.minX, y: y + 22 - chordFrame.minY)
                ],
                creationDate: Date(timeIntervalSince1970: TimeInterval(40 + index))
            )
        })

        let targets = LeadSheetChordInkRecognitionTargeting.batchTargets(
            for: drawing,
            chordFrame: chordFrame,
            pageLayout: layout,
            draftBarlines: [
                DraftBarline(
                    measureID: measureID,
                    measureIndex: measure.index,
                    fraction: barlineFraction,
                    metrics: DraftBarlineGestureMetrics(
                        height: Double(laneFrame.height),
                        width: 2,
                        angleDegreesFromVertical: 0,
                        straightness: 1,
                        laneCoverage: 1
                    )
                )
            ]
        )

        XCTAssertEqual(targets.count, 4)
        XCTAssertEqual(targets.map(\.measureID), [measureID, measureID, measureID, measureID])
        XCTAssertEqual(targets.map(\.strokes.count), [1, 1, 1, 1])
        XCTAssertTrue(targets.prefix(2).allSatisfy { $0.laneLocation?.fraction ?? 1 < barlineFraction })
        XCTAssertTrue(targets.suffix(2).allSatisfy { $0.laneLocation?.fraction ?? 0 > barlineFraction })
        XCTAssertEqual(targets.map(\.visualOrder), targets.map(\.visualOrder).sorted())
    }

    func testChordBatchTargetingSplitsTightChordGroupsInsideDraftBarlineSegment() throws {
        let chart = Chart.blank(title: "Tight Draft Segment Groups", measureCount: 1, layoutStyle: .simpleChordSheet)
        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1200)
        )
        let measure = try XCTUnwrap(layout.systems.first?.measures.first)
        let measureID = try XCTUnwrap(measure.sourceMeasureID)
        let chordFrame = LeadSheetActiveInkScope.chordWritingFrame(for: layout)
        let laneFrame = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingInputFrames(for: layout).first)
        let barlineFraction = 0.52
        let y = laneFrame.midY
        let firstX = laneFrame.minX + 70
        let secondX = firstX + 78
        let strokes = [
            stroke(
                points: [
                    CGPoint(x: firstX - chordFrame.minX, y: y - 22 - chordFrame.minY),
                    CGPoint(x: firstX + 24 - chordFrame.minX, y: y - 4 - chordFrame.minY),
                    CGPoint(x: firstX + 4 - chordFrame.minX, y: y + 22 - chordFrame.minY)
                ],
                creationDate: Date(timeIntervalSince1970: 40)
            ),
            stroke(
                points: [
                    CGPoint(x: firstX + 30 - chordFrame.minX, y: y - 18 - chordFrame.minY),
                    CGPoint(x: firstX + 42 - chordFrame.minX, y: y - 2 - chordFrame.minY),
                    CGPoint(x: firstX + 32 - chordFrame.minX, y: y + 18 - chordFrame.minY)
                ],
                creationDate: Date(timeIntervalSince1970: 41)
            ),
            stroke(
                points: [
                    CGPoint(x: secondX - chordFrame.minX, y: y - 22 - chordFrame.minY),
                    CGPoint(x: secondX + 24 - chordFrame.minX, y: y - 4 - chordFrame.minY),
                    CGPoint(x: secondX + 4 - chordFrame.minX, y: y + 22 - chordFrame.minY)
                ],
                creationDate: Date(timeIntervalSince1970: 42)
            ),
            stroke(
                points: [
                    CGPoint(x: secondX + 30 - chordFrame.minX, y: y - 18 - chordFrame.minY),
                    CGPoint(x: secondX + 42 - chordFrame.minX, y: y - 2 - chordFrame.minY),
                    CGPoint(x: secondX + 32 - chordFrame.minX, y: y + 18 - chordFrame.minY)
                ],
                creationDate: Date(timeIntervalSince1970: 43)
            )
        ]
        let drawing = PKDrawing(strokes: strokes)

        let targets = LeadSheetChordInkRecognitionTargeting.batchTargets(
            for: drawing,
            chordFrame: chordFrame,
            pageLayout: layout,
            draftBarlines: [
                DraftBarline(
                    measureID: measureID,
                    measureIndex: measure.index,
                    fraction: barlineFraction,
                    metrics: DraftBarlineGestureMetrics(
                        height: Double(laneFrame.height),
                        width: 2,
                        angleDegreesFromVertical: 0,
                        straightness: 1,
                        laneCoverage: 1
                    )
                )
            ]
        )

        XCTAssertEqual(targets.count, 2)
        XCTAssertEqual(targets.map(\.measureID), [measureID, measureID])
        XCTAssertEqual(targets.map(\.strokes.count), [2, 2])
        XCTAssertTrue(targets.allSatisfy { $0.laneLocation?.fraction ?? 1 < barlineFraction })
        XCTAssertLessThan(targets[0].visualOrder, targets[1].visualOrder)
    }

    func testChordBatchTargetingCollapsesSingleGlyphFragmentsInsideDraftBarlineSegment() throws {
        let chart = Chart.blank(title: "Draft Fragment Collapse", measureCount: 1, layoutStyle: .simpleChordSheet)
        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1200)
        )
        let measure = try XCTUnwrap(layout.systems.first?.measures.first)
        let measureID = try XCTUnwrap(measure.sourceMeasureID)
        let chordFrame = LeadSheetActiveInkScope.chordWritingFrame(for: layout)
        let laneFrame = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingInputFrames(for: layout).first)
        let baselineY = laneFrame.midY
        let stemX = laneFrame.minX + 72
        let bowlStartX = stemX + 45
        let drawing = PKDrawing(strokes: [
            stroke(
                points: [
                    CGPoint(x: stemX - chordFrame.minX, y: baselineY - 22 - chordFrame.minY),
                    CGPoint(x: stemX - chordFrame.minX, y: baselineY + 22 - chordFrame.minY)
                ],
                creationDate: Date(timeIntervalSince1970: 40)
            ),
            stroke(
                points: [
                    CGPoint(x: bowlStartX - chordFrame.minX, y: baselineY - 21 - chordFrame.minY),
                    CGPoint(x: bowlStartX + 24 - chordFrame.minX, y: baselineY - 2 - chordFrame.minY),
                    CGPoint(x: bowlStartX - chordFrame.minX, y: baselineY + 21 - chordFrame.minY)
                ],
                creationDate: Date(timeIntervalSince1970: 41)
            )
        ])

        let targets = LeadSheetChordInkRecognitionTargeting.batchTargets(
            for: drawing,
            chordFrame: chordFrame,
            pageLayout: layout,
            draftBarlines: [
                DraftBarline(
                    measureID: measureID,
                    measureIndex: measure.index,
                    fraction: 0.54,
                    metrics: DraftBarlineGestureMetrics(
                        height: Double(laneFrame.height),
                        width: 2,
                        angleDegreesFromVertical: 0,
                        straightness: 1,
                        laneCoverage: 1
                    )
                )
            ]
        )

        XCTAssertTrue(targets.isEmpty)
    }

    func testChordActiveInkScopeUsesExpandedChordLanesInsteadOfWholePage() throws {
        let chart = Chart.blank(title: "Scoped Chord Lane", measureCount: 4, layoutStyle: .rhythmSectionSheet)
        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1200)
        )
        let firstMeasure = try XCTUnwrap(layout.systems.first?.measures.first)

        let scope = LeadSheetActiveInkScope.resolve(
            interactionMode: .chordEntry,
            chartLayoutStyle: chart.layoutStyle,
            selectedMeasureID: nil,
            selectedMeasureLayout: nil,
            pageLayout: layout
        )

        guard case .chords(let frame, let inputFrames) = scope else {
            XCTFail("Chord mode should resolve a scoped chord ink region.")
            return
        }

        XCTAssertNotEqual(frame, LeadSheetActiveInkScope.pageWritingFrame(for: layout))
        let firstInputFrame = try XCTUnwrap(inputFrames.first)
        XCTAssertLessThan(firstInputFrame.height, firstMeasure.chordWritingFrame.height)
        XCTAssertTrue(firstInputFrame.contains(CGPoint(x: firstMeasure.chordBandFrame.midX, y: firstMeasure.chordBandFrame.midY)))
        XCTAssertLessThan(firstInputFrame.maxY, firstMeasure.staffFrame.minY)
        XCTAssertEqual(try XCTUnwrap(inputFrames.first).maxX, layout.paperFrame.insetBy(dx: 14, dy: 0).maxX)
        XCTAssertFalse(
            inputFrames.contains {
                $0.contains(CGPoint(x: firstMeasure.frame.minX + 16, y: firstMeasure.chordWritingFrame.midY))
            }
        )
        XCTAssertFalse(inputFrames.contains { $0.contains(CGPoint(x: firstMeasure.staffFrame.midX, y: firstMeasure.frame.maxY - 2)) })
    }

    func testChordWritingBandContainsExpandedLaneOutsideRenderedBand() throws {
        let chart = Chart.blank(title: "Simple Lane", measureCount: 1, layoutStyle: .simpleChordSheet)
        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1200)
        )
        let measure = try XCTUnwrap(layout.systems.first?.measures.first)
        let expandedLanePoint = CGPoint(
            x: measure.chordWritingFrame.midX,
            y: (measure.chordWritingFrame.minY + measure.chordBandFrame.minY) / 2
        )

        XCTAssertTrue(measure.chordWritingFrame.contains(expandedLanePoint))
        XCTAssertFalse(measure.chordBandFrame.contains(expandedLanePoint))
        XCTAssertTrue(LeadSheetCanvasInteractionTargeting.chordWritingBandContains(expandedLanePoint, in: layout))
    }

    func testCueTextMoveTargetSnapsToPlacementSubdivision() throws {
        var chart = Chart.blank(title: "Cue Move", measureCount: 1, layoutStyle: .rhythmSectionSheet)
        chart.defaultMeter = Meter(numerator: 6, denominator: 8)
        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1200)
        )
        let measure = try XCTUnwrap(layout.systems.first?.measures.first)
        let targetPoint = CGPoint(
            x: measure.staffFrame.minX + measure.staffFrame.width * 0.10,
            y: measure.staffFrame.midY
        )

        let target = try XCTUnwrap(
            LeadSheetCanvasInteractionTargeting.cueTextMoveTarget(
                at: targetPoint,
                in: layout,
                chart: chart
            )
        )

        XCTAssertEqual(target.measureID, chart.measures.first?.id)
        XCTAssertEqual(target.fraction, 1.0 / 12.0, accuracy: 0.0001)
    }

    func testOnlyOutsideChordLaneTapConfirmsWaitingChordInk() {
        let chart = Chart.blank(title: "Confirm Drag", measureCount: 4, layoutStyle: .rhythmSectionSheet)
        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1200)
        )
        let outsideLaneStart = CGPoint(x: layout.paperFrame.midX, y: layout.paperFrame.maxY - 28)
        let insideLaneStart = CGPoint(
            x: layout.systems[0].measures[0].chordWritingFrame.midX,
            y: layout.systems[0].measures[0].chordWritingFrame.midY
        )

        XCTAssertTrue(
            ChordInkTapConfirmGesturePolicy.shouldConfirmOutsideLaneTap(
                location: outsideLaneStart,
                pageLayout: layout,
                hasChordInk: true
            )
        )
        XCTAssertFalse(
            ChordInkTapConfirmGesturePolicy.shouldConfirmOutsideLaneTap(
                location: insideLaneStart,
                pageLayout: layout,
                hasChordInk: true
            )
        )
        XCTAssertFalse(
            ChordInkTapConfirmGesturePolicy.shouldConfirmOutsideLaneTap(
                location: outsideLaneStart,
                pageLayout: layout,
                hasChordInk: false
            )
        )
    }

    func testBrowseEditModeEditsRenderedChordsWithoutInkCanvasOrIdleBoxes() {
        let policy = LeadSheetInteractionModeStatePolicy.resolve(for: .browse)

        XCTAssertFalse(policy.pageInkCanvasInteractionEnabled)
        XCTAssertTrue(policy.renderedEditTapEnabled)
        XCTAssertTrue(policy.renderedObjectMovePanEnabled)
        XCTAssertFalse(policy.renderedEditOverlayHidden)
        XCTAssertTrue(EditorCanvasMode.browse.allowsChordObjectEditing)
        XCTAssertTrue(EditorCanvasMode.browse.requiresChordSelectionBeforeObjectActions)
        XCTAssertFalse(EditorCanvasMode.browse.drawsAllChordObjectEditBoxes)
        XCTAssertFalse(EditorCanvasMode.browse.drawsAllChordObjectEditControls)
    }

    func testBrowseEditModeSupportsSelectedMeasureResizeWithoutActiveToolControls() {
        let policy = LeadSheetInteractionModeStatePolicy.resolve(for: .browse)

        XCTAssertTrue(policy.measureResizePanEnabled)
        XCTAssertFalse(policy.clearsMeasureResizeDrag)
        XCTAssertTrue(EditorCanvasMode.browse.showsMeasureResizeHandles)
        XCTAssertFalse(EditorCanvasMode.browse.showsActiveToolControls)
    }

    func testBrowseEditModeRoutesHeaderTapsToHeaderAuthoring() {
        let chart = Chart.blank(title: "Header Tap", measureCount: 4, layoutStyle: .rhythmSectionSheet)
        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1200)
        )
        let headerPoint = CGPoint(
            x: layout.header.handwrittenFrame.midX,
            y: layout.header.handwrittenFrame.midY
        )
        let measurePoint = CGPoint(
            x: layout.systems[0].measures[0].frame.midX,
            y: layout.systems[0].measures[0].frame.midY
        )

        XCTAssertTrue(EditorCanvasMode.browse.allowsHeaderAuthoringSelection)
        XCTAssertFalse(EditorCanvasMode.measureEdit.allowsHeaderAuthoringSelection)
        XCTAssertFalse(EditorCanvasMode.headerEntry.allowsHeaderAuthoringSelection)
        XCTAssertTrue(
            LeadSheetCanvasInteractionTargeting.headerAuthoringContains(headerPoint, in: layout)
        )
        XCTAssertFalse(
            LeadSheetCanvasInteractionTargeting.headerAuthoringContains(measurePoint, in: layout)
        )
    }

    func testOnlyInkModesRestrictPageScrollToOutsideMargins() {
        XCTAssertFalse(EditorCanvasMode.browse.restrictsPageScrollToOutsideMargins)
        XCTAssertFalse(EditorCanvasMode.measureEdit.restrictsPageScrollToOutsideMargins)
        XCTAssertFalse(EditorCanvasMode.repeatEdit.restrictsPageScrollToOutsideMargins)
        XCTAssertFalse(EditorCanvasMode.timeSignatureEdit.restrictsPageScrollToOutsideMargins)
        XCTAssertFalse(EditorCanvasMode.rhythmicNotationEdit.restrictsPageScrollToOutsideMargins)
        XCTAssertTrue(EditorCanvasMode.headerEntry.restrictsPageScrollToOutsideMargins)
        XCTAssertTrue(EditorCanvasMode.chordEntry.restrictsPageScrollToOutsideMargins)
        XCTAssertTrue(EditorCanvasMode.noteEdit.restrictsPageScrollToOutsideMargins)
        XCTAssertTrue(EditorCanvasMode.freeHand.restrictsPageScrollToOutsideMargins)
    }

    func testInkResponsivenessPolicyClampsValues() {
        XCTAssertEqual(LeadSheetInkResponsivenessPolicy.normalized(-0.4), 0)
        XCTAssertEqual(LeadSheetInkResponsivenessPolicy.normalized(1.4), 1)
        XCTAssertEqual(LeadSheetInkResponsivenessPolicy.normalized(0.65), 0.65)
    }

    func testInkResponsivenessPolicyMapsHigherValuesToMoreInputCoalescing() {
        let direct = LeadSheetInkResponsivenessPolicy.inputCoalescingDelay(for: 0)
        let balanced = LeadSheetInkResponsivenessPolicy.inputCoalescingDelay(
            for: LeadSheetInkResponsivenessPolicy.defaultValue
        )
        let smooth = LeadSheetInkResponsivenessPolicy.inputCoalescingDelay(for: 1)

        XCTAssertLessThan(direct, balanced)
        XCTAssertLessThan(balanced, smooth)
        XCTAssertEqual(direct, 0.004, accuracy: 0.001)
        XCTAssertEqual(smooth, 0.030, accuracy: 0.001)
    }

    func testFreehandTabTitleStaysStableWhenActive() {
        XCTAssertEqual(EditorCanvasMode.browse.freeHandTabTitle, "Free-Write")
        XCTAssertEqual(EditorCanvasMode.repeatEdit.freeHandTabTitle, "Free-Write")
        XCTAssertEqual(EditorCanvasMode.rhythmicNotationEdit.freeHandTabTitle, "Free-Write")
        XCTAssertEqual(EditorCanvasMode.headerEntry.freeHandTabTitle, "Free-Write")
        XCTAssertEqual(EditorCanvasMode.freeHand.freeHandTabTitle, "Free-Write")
        XCTAssertEqual(EditorCanvasMode.freeHand.freeHandTabSymbol, "pencil.and.scribble")
    }

    func testActiveToolControlsAreShownOutsideBrowseMode() {
        XCTAssertFalse(EditorCanvasMode.browse.showsActiveToolControls)
        XCTAssertTrue(EditorCanvasMode.measureEdit.showsActiveToolControls)
        XCTAssertTrue(EditorCanvasMode.repeatEdit.showsActiveToolControls)
        XCTAssertTrue(EditorCanvasMode.timeSignatureEdit.showsActiveToolControls)
        XCTAssertFalse(EditorCanvasMode.rhythmicNotationEdit.showsActiveToolControls)
        XCTAssertTrue(EditorCanvasMode.headerEntry.showsActiveToolControls)
        XCTAssertTrue(EditorCanvasMode.chordEntry.showsActiveToolControls)
        XCTAssertTrue(EditorCanvasMode.noteEdit.showsActiveToolControls)
        XCTAssertTrue(EditorCanvasMode.freeHand.showsActiveToolControls)
        XCTAssertTrue(EditorCanvasMode.textEdit.showsActiveToolControls)
    }

    func testActiveToolMetadataMatchesPrimaryEditorModes() {
        XCTAssertEqual(EditorCanvasMode.browse.activeToolTitle, "Edit")
        XCTAssertEqual(EditorCanvasMode.measureEdit.activeToolTitle, "Measures")
        XCTAssertEqual(EditorCanvasMode.repeatEdit.activeToolTitle, "Repeats")
        XCTAssertEqual(EditorCanvasMode.rhythmicNotationEdit.activeToolTitle, "Rhythm")
        XCTAssertEqual(EditorCanvasMode.headerEntry.activeToolTitle, "Header")
        XCTAssertEqual(EditorCanvasMode.chordEntry.activeToolTitle, "Chord")
        XCTAssertEqual(EditorCanvasMode.freeHand.activeToolTitle, "Free-Write")
        XCTAssertEqual(EditorCanvasMode.textEdit.activeToolTitle, "Text")
    }

    func testScrollMarginPolicyBlocksPaperGesturesOnlyWhenRestricted() {
        let paperFrame = CGRect(x: 100, y: 80, width: 300, height: 420)

        XCTAssertTrue(
            LeadSheetScrollMarginPolicy.allowsPageScrollStart(
                at: CGPoint(x: 180, y: 140),
                paperFrame: paperFrame,
                restrictsToOutsideMargins: false
            )
        )
        XCTAssertFalse(
            LeadSheetScrollMarginPolicy.allowsPageScrollStart(
                at: CGPoint(x: 180, y: 140),
                paperFrame: paperFrame,
                restrictsToOutsideMargins: true
            )
        )
        XCTAssertTrue(
            LeadSheetScrollMarginPolicy.allowsPageScrollStart(
                at: CGPoint(x: 70, y: 140),
                paperFrame: paperFrame,
                restrictsToOutsideMargins: true
            )
        )
        XCTAssertFalse(
            LeadSheetScrollMarginPolicy.allowsPageScrollStart(
                at: CGPoint(x: paperFrame.minX - LeadSheetScrollMarginPolicy.paperHitSlop / 2, y: 140),
                paperFrame: paperFrame,
                restrictsToOutsideMargins: true
            )
        )
    }

    func testScrollMarginPolicyExposesVisibleDragAreaFramesOutsidePaper() {
        let bounds = CGRect(x: 0, y: 0, width: 500, height: 600)
        let paperFrame = CGRect(x: 100, y: 80, width: 300, height: 420)

        let dragAreaFrames = LeadSheetScrollMarginPolicy.dragAreaFrames(
            in: bounds,
            paperFrame: paperFrame
        )

        XCTAssertTrue(dragAreaFrames.contains { $0.contains(CGPoint(x: 40, y: 300)) })
        XCTAssertTrue(dragAreaFrames.contains { $0.contains(CGPoint(x: 460, y: 300)) })
        XCTAssertTrue(dragAreaFrames.contains { $0.contains(CGPoint(x: 250, y: 40)) })
        XCTAssertTrue(dragAreaFrames.contains { $0.contains(CGPoint(x: 250, y: 560)) })
        XCTAssertFalse(dragAreaFrames.contains { $0.contains(CGPoint(x: 250, y: 300)) })
        XCTAssertFalse(dragAreaFrames.contains { $0.intersects(paperFrame) })
    }

    func testRenderedObjectMoveDoesNotRecognizeSimultaneouslyWithParentScroll() {
        XCTAssertFalse(
            LeadSheetRenderedObjectMoveScrollLockPolicy.allowsSimultaneousRecognition(
                involvesRenderedObjectMove: true,
                involvesParentScroll: true
            )
        )
        XCTAssertTrue(
            LeadSheetRenderedObjectMoveScrollLockPolicy.allowsSimultaneousRecognition(
                involvesRenderedObjectMove: true,
                involvesParentScroll: false
            )
        )
        XCTAssertTrue(
            LeadSheetRenderedObjectMoveScrollLockPolicy.allowsSimultaneousRecognition(
                involvesRenderedObjectMove: false,
                involvesParentScroll: true
            )
        )
    }

    func testMeasureResizePreviewPolicyComputesRightEdgeWidth() {
        XCTAssertEqual(
            LeadSheetMeasureResizePreviewPolicy.proposedModelWidth(
                initialWidth: 180,
                edge: .right,
                translationX: 32
            ),
            212
        )
    }

    func testMeasureResizePreviewPolicyComputesLeftEdgeWidth() {
        XCTAssertEqual(
            LeadSheetMeasureResizePreviewPolicy.proposedModelWidth(
                initialWidth: 180,
                edge: .left,
                translationX: -32
            ),
            212
        )
        XCTAssertEqual(
            LeadSheetMeasureResizePreviewPolicy.proposedModelWidth(
                initialWidth: 180,
                edge: .left,
                translationX: 32
            ),
            148
        )
    }

    func testMeasureResizePreviewPolicyClampsModelWidth() {
        XCTAssertEqual(
            LeadSheetMeasureResizePreviewPolicy.proposedModelWidth(
                initialWidth: 120,
                edge: .right,
                translationX: -200
            ),
            Measure.minimumManualLayoutWidth
        )
        XCTAssertEqual(
            LeadSheetMeasureResizePreviewPolicy.proposedModelWidth(
                initialWidth: 200,
                edge: .right,
                translationX: 1_200
            ),
            Measure.maximumManualLayoutWidth
        )
    }

    func testMeasureResizePreviewPolicyKeepsLeftEdgeStableForRightResize() {
        let initialFrame = CGRect(x: 100, y: 20, width: 180, height: 44)
        let previewFrame = LeadSheetMeasureResizePreviewPolicy.previewFrame(
            initialFrame: initialFrame,
            edge: .right,
            translationX: 40
        )

        XCTAssertEqual(previewFrame.minX, 100)
        XCTAssertEqual(previewFrame.width, 220)
    }

    func testMeasureResizePreviewPolicyKeepsRightEdgeStableForLeftResize() {
        let initialFrame = CGRect(x: 100, y: 20, width: 180, height: 44)
        let previewFrame = LeadSheetMeasureResizePreviewPolicy.previewFrame(
            initialFrame: initialFrame,
            edge: .left,
            translationX: -40
        )

        XCTAssertEqual(previewFrame.maxX, initialFrame.maxX)
        XCTAssertEqual(previewFrame.minX, 60)
        XCTAssertEqual(previewFrame.width, 220)
    }

    func testMeasureResizeTransactionBalancesRightEdgeWithNearestNeighbor() throws {
        let firstID = UUID()
        let secondID = UUID()
        let thirdID = UUID()
        let transaction = try XCTUnwrap(
            LeadSheetMeasureResizeTransaction(
                selectedMeasureID: firstID,
                edge: .right,
                rowMeasures: [
                    measureResizeSnapshot(firstID, x: 100, width: 180),
                    measureResizeSnapshot(secondID, x: 280, width: 180),
                    measureResizeSnapshot(thirdID, x: 460, width: 180)
                ],
                displayedToManualWidthScale: 1
            )
        )

        let preview = transaction.preview(for: 40)

        XCTAssertEqual(preview.frame(for: firstID)?.minX, 100)
        XCTAssertEqual(preview.frame(for: firstID)?.width, 220)
        XCTAssertEqual(preview.frame(for: secondID)?.minX, 320)
        XCTAssertEqual(preview.frame(for: secondID)?.width, 140)
        XCTAssertEqual(preview.frame(for: thirdID)?.minX, 460)
        XCTAssertEqual(preview.frame(for: thirdID)?.width, 180)
        XCTAssertEqual(preview.affectedMeasureIDs, [firstID, secondID])
        XCTAssertEqual(preview.committedManualWidths[firstID], 220)
        XCTAssertEqual(preview.committedManualWidths[secondID], 140)
        XCTAssertNil(preview.committedManualWidths[thirdID])
    }

    func testMeasureResizeTransactionHighlightsEvenDivisionGuideWhenActiveEdgeAligns() throws {
        let firstID = UUID()
        let secondID = UUID()
        let thirdID = UUID()
        let transaction = try XCTUnwrap(
            LeadSheetMeasureResizeTransaction(
                selectedMeasureID: firstID,
                edge: .right,
                rowMeasures: [
                    measureResizeSnapshot(firstID, x: 100, width: 180),
                    measureResizeSnapshot(secondID, x: 280, width: 180),
                    measureResizeSnapshot(thirdID, x: 460, width: 180)
                ],
                displayedToManualWidthScale: 1
            )
        )

        let alignedPreview = transaction.preview(for: 0)
        let unalignedPreview = transaction.preview(for: 40)

        XCTAssertEqual(alignedPreview.evenDivisionGuideXs.count, 2)
        XCTAssertEqual(alignedPreview.evenDivisionGuideXs[0], 280)
        XCTAssertEqual(alignedPreview.evenDivisionGuideXs[1], 460)
        XCTAssertEqual(alignedPreview.activeEvenDivisionGuideX, 280)
        XCTAssertNil(unalignedPreview.activeEvenDivisionGuideX)
        XCTAssertEqual(unalignedPreview.committedManualWidths[firstID], 220)
        XCTAssertEqual(unalignedPreview.committedManualWidths[secondID], 140)
    }

    func testMeasureResizeTransactionEvenDivisionGuideEqualizesWholeRow() throws {
        let firstID = UUID()
        let secondID = UUID()
        let thirdID = UUID()
        let transaction = try XCTUnwrap(
            LeadSheetMeasureResizeTransaction(
                selectedMeasureID: firstID,
                edge: .right,
                rowMeasures: [
                    measureResizeSnapshot(firstID, x: 100, width: 240),
                    measureResizeSnapshot(secondID, x: 340, width: 120),
                    measureResizeSnapshot(thirdID, x: 460, width: 240)
                ],
                displayedToManualWidthScale: 1,
                evenDivisionCommitManualWidths: [
                    firstID: 501,
                    secondID: 502,
                    thirdID: 490
                ]
            )
        )

        let preview = transaction.preview(for: -40)

        XCTAssertEqual(preview.activeEvenDivisionGuideX, 300)
        XCTAssertEqual(preview.affectedMeasureIDs, [firstID, secondID, thirdID])
        XCTAssertEqual(preview.frame(for: firstID)?.minX, 100)
        XCTAssertEqual(preview.frame(for: firstID)?.width, 200)
        XCTAssertEqual(preview.frame(for: secondID)?.minX, 300)
        XCTAssertEqual(preview.frame(for: secondID)?.width, 200)
        XCTAssertEqual(preview.frame(for: thirdID)?.minX, 500)
        XCTAssertEqual(preview.frame(for: thirdID)?.width, 200)
        XCTAssertEqual(preview.committedManualWidths[firstID], 501)
        XCTAssertEqual(preview.committedManualWidths[secondID], 502)
        XCTAssertEqual(preview.committedManualWidths[thirdID], 490)
    }

    func testMeasureResizeTransactionBalancesLeftEdgeWithNearestNeighbor() throws {
        let firstID = UUID()
        let secondID = UUID()
        let thirdID = UUID()
        let transaction = try XCTUnwrap(
            LeadSheetMeasureResizeTransaction(
                selectedMeasureID: secondID,
                edge: .left,
                rowMeasures: [
                    measureResizeSnapshot(firstID, x: 100, width: 180),
                    measureResizeSnapshot(secondID, x: 280, width: 180),
                    measureResizeSnapshot(thirdID, x: 460, width: 180)
                ],
                displayedToManualWidthScale: 1
            )
        )

        let preview = transaction.preview(for: -30)

        XCTAssertEqual(preview.frame(for: firstID)?.minX, 100)
        XCTAssertEqual(preview.frame(for: firstID)?.width, 150)
        XCTAssertEqual(preview.frame(for: secondID)?.minX, 250)
        XCTAssertEqual(preview.frame(for: secondID)?.width, 210)
        XCTAssertEqual(preview.frame(for: thirdID)?.minX, 460)
        XCTAssertEqual(preview.frame(for: thirdID)?.width, 180)
        XCTAssertEqual(preview.affectedMeasureIDs, [firstID, secondID])
        XCTAssertEqual(preview.committedManualWidths[firstID], 150)
        XCTAssertEqual(preview.committedManualWidths[secondID], 210)
        XCTAssertNil(preview.committedManualWidths[thirdID])
    }

    func testMeasureResizeTransactionClampsBeforeNeighborCollapses() throws {
        let firstID = UUID()
        let secondID = UUID()
        let transaction = try XCTUnwrap(
            LeadSheetMeasureResizeTransaction(
                selectedMeasureID: firstID,
                edge: .right,
                rowMeasures: [
                    measureResizeSnapshot(firstID, x: 100, width: 180),
                    measureResizeSnapshot(secondID, x: 280, width: 110)
                ],
                displayedToManualWidthScale: 1
            )
        )

        let preview = transaction.preview(for: 90)

        XCTAssertEqual(preview.frame(for: firstID)?.width, 194)
        XCTAssertEqual(preview.frame(for: secondID)?.minX, 294)
        XCTAssertEqual(preview.frame(for: secondID)?.width, Measure.minimumManualLayoutWidth)
        XCTAssertEqual(preview.committedManualWidths[firstID], 194)
        XCTAssertEqual(preview.committedManualWidths[secondID], Measure.minimumManualLayoutWidth)
    }

    func testInkCanvasSyncPolicyPreservesDirtyChordInkFromStaleModelReload() {
        XCTAssertTrue(
            LeadSheetInkCanvasSyncPolicy.shouldPreserveActiveCanvas(
                activeInkScope: .chords(
                    frame: CGRect(x: 0, y: 0, width: 100, height: 40),
                    inputFrames: [CGRect(x: 0, y: 0, width: 100, height: 40)]
                ),
                interactionMode: .chordEntry,
                sessionState: dirtyInkSessionState(.chord),
                currentDrawingData: Data([0x01]),
                desiredDrawingData: Data([0x02])
            )
        )
    }

    func testInkCanvasSyncPolicyPersistsOutgoingFreehandInkWhenEnteringEditInkScope() {
        XCTAssertTrue(
            LeadSheetInkCanvasSyncPolicy.shouldPersistOutgoingCanvas(
                previousActiveInkScope: .page(frame: CGRect(x: 0, y: 0, width: 320, height: 480)),
                nextActiveInkScope: .noteSelection(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
            )
        )
    }

    func testInkCanvasSyncPolicyDoesNotPersistOutgoingCanvasWhenScopeIdentityIsUnchanged() {
        XCTAssertFalse(
            LeadSheetInkCanvasSyncPolicy.shouldPersistOutgoingCanvas(
                previousActiveInkScope: .page(frame: CGRect(x: 0, y: 0, width: 320, height: 480)),
                nextActiveInkScope: .page(frame: CGRect(x: 4, y: 4, width: 320, height: 480))
            )
        )
    }

    func testInkCanvasSyncPolicyDoesNotPersistTemporaryNoteSelectionInkWhenChangingScopes() {
        XCTAssertFalse(
            LeadSheetInkCanvasSyncPolicy.shouldPersistOutgoingCanvas(
                previousActiveInkScope: .noteSelection(frame: CGRect(x: 0, y: 0, width: 320, height: 480)),
                nextActiveInkScope: .page(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
            )
        )
    }

    func testInkCanvasSyncPolicyPreservesDirtyFreehandInkBeforeDataComparison() {
        XCTAssertTrue(
            LeadSheetInkCanvasSyncPolicy.shouldPreserveDirtyActiveCanvas(
                activeInkScope: .page(frame: CGRect(x: 0, y: 0, width: 320, height: 480)),
                interactionMode: .freeHand,
                sessionState: dirtyInkSessionState(.passive)
            )
        )
    }

    func testInkCanvasSyncPolicyPreservesDirtyHeaderInkBeforeDataComparison() {
        XCTAssertTrue(
            LeadSheetInkCanvasSyncPolicy.shouldPreserveDirtyActiveCanvas(
                activeInkScope: .header(frame: CGRect(x: 0, y: 0, width: 320, height: 80)),
                interactionMode: .headerEntry,
                sessionState: dirtyInkSessionState(.passive)
            )
        )
    }

    func testInkCanvasSyncPolicyDoesNotPreserveDirtyCanvasBeforeDataComparisonAfterScopeSwitch() {
        XCTAssertFalse(
            LeadSheetInkCanvasSyncPolicy.shouldPreserveDirtyActiveCanvas(
                activeInkScope: .page(frame: CGRect(x: 0, y: 0, width: 320, height: 480)),
                interactionMode: .freeHand,
                sessionState: dirtyInkSessionState(.passive),
                didSwitchInkScope: true
            )
        )
    }

    func testInkCanvasSyncPolicyDoesNotPreserveCleanCanvasBeforeDataComparison() {
        XCTAssertFalse(
            LeadSheetInkCanvasSyncPolicy.shouldPreserveDirtyActiveCanvas(
                activeInkScope: .page(frame: CGRect(x: 0, y: 0, width: 320, height: 480)),
                interactionMode: .freeHand,
                sessionState: dirtyInkSessionState()
            )
        )
    }

    func testLiveInkNormalizationPolicyNeverNormalizesPassiveCanvas() {
        XCTAssertFalse(
            LeadSheetLiveInkNormalizationPolicy.shouldNormalizeLiveCanvas(
                activeInkRole: .passive,
                sessionState: dirtyInkSessionState()
            )
        )
        XCTAssertFalse(
            LeadSheetLiveInkNormalizationPolicy.shouldNormalizeLiveCanvas(
                activeInkRole: .passive,
                sessionState: dirtyInkSessionState(.passive)
            )
        )
    }

    func testLiveInkNormalizationPolicyOnlyNormalizesCleanSemanticCanvas() {
        XCTAssertTrue(
            LeadSheetLiveInkNormalizationPolicy.shouldNormalizeLiveCanvas(
                activeInkRole: .chord,
                sessionState: dirtyInkSessionState()
            )
        )
        XCTAssertFalse(
            LeadSheetLiveInkNormalizationPolicy.shouldNormalizeLiveCanvas(
                activeInkRole: .chord,
                sessionState: dirtyInkSessionState(.chord)
            )
        )
    }

    func testPendingPersistedInkPolicyAppliesStaleIncomingInk() {
        let pendingErase = LeadSheetPendingPersistedInk(
            drawingData: nil,
            coordinateSpace: nil
        )
        let staleIncomingInk = LeadSheetPendingPersistedInk(
            drawingData: Data([0x01]),
            coordinateSpace: PersistentInkCoordinateSpace(width: 320, height: 480)
        )

        XCTAssertTrue(
            LeadSheetPendingPersistedInkPolicy.shouldApplyPendingInk(
                incomingInk: staleIncomingInk,
                pendingInk: pendingErase
            )
        )
        XCTAssertTrue(
            LeadSheetPendingPersistedInkPolicy.shouldRetainPendingInk(
                incomingInk: staleIncomingInk,
                pendingInk: pendingErase
            )
        )
    }

    func testPendingPersistedInkPolicyRetiresWhenParentEchoesPendingInk() {
        let pendingErase = LeadSheetPendingPersistedInk(
            drawingData: nil,
            coordinateSpace: nil
        )

        XCTAssertFalse(
            LeadSheetPendingPersistedInkPolicy.shouldApplyPendingInk(
                incomingInk: pendingErase,
                pendingInk: pendingErase
            )
        )
        XCTAssertFalse(
            LeadSheetPendingPersistedInkPolicy.shouldRetainPendingInk(
                incomingInk: pendingErase,
                pendingInk: pendingErase
            )
        )
    }

    func testPendingPersistedInkPolicyRecordsDirtyPersistedEraseTombstone() {
        XCTAssertTrue(
            LeadSheetPendingPersistedInkPolicy.shouldRecordEraseTombstone(
                activeInkScope: .page(frame: CGRect(x: 0, y: 0, width: 320, height: 480)),
                drawingData: nil,
                isDirtyAuthoringRole: true
            )
        )
    }

    func testPendingPersistedInkPolicyDoesNotRecordCleanOrTemporaryEraseTombstone() {
        XCTAssertFalse(
            LeadSheetPendingPersistedInkPolicy.shouldRecordEraseTombstone(
                activeInkScope: .page(frame: CGRect(x: 0, y: 0, width: 320, height: 480)),
                drawingData: nil,
                isDirtyAuthoringRole: false
            )
        )
        XCTAssertFalse(
            LeadSheetPendingPersistedInkPolicy.shouldRecordEraseTombstone(
                activeInkScope: .noteSelection(frame: CGRect(x: 0, y: 0, width: 320, height: 480)),
                drawingData: nil,
                isDirtyAuthoringRole: true
            )
        )
        XCTAssertFalse(
            LeadSheetPendingPersistedInkPolicy.shouldRecordEraseTombstone(
                activeInkScope: .page(frame: CGRect(x: 0, y: 0, width: 320, height: 480)),
                drawingData: Data([0x01]),
                isDirtyAuthoringRole: true
            )
        )
    }

    func testInkPersistenceDedupePolicySkipsUnchangedPassiveInk() {
        let persistedSnapshot = LeadSheetPersistedInkSnapshot(
            inkSnapshot: LeadSheetInkDrawingSnapshot(testValues: [12, 24]),
            coordinateSpace: PersistentInkCoordinateSpace(width: 320, height: 480)
        )

        XCTAssertTrue(
            LeadSheetInkPersistenceDedupePolicy.shouldSkipPersistence(
                activeInkScope: .page(frame: CGRect(x: 0, y: 0, width: 320, height: 480)),
                currentSnapshot: persistedSnapshot,
                lastPersistedSnapshot: persistedSnapshot
            )
        )
    }

    func testInkPersistenceDedupePolicyDoesNotSkipChangedPassiveInk() {
        let lastPersistedSnapshot = LeadSheetPersistedInkSnapshot(
            inkSnapshot: LeadSheetInkDrawingSnapshot(testValues: [12]),
            coordinateSpace: PersistentInkCoordinateSpace(width: 320, height: 480)
        )
        let currentSnapshot = LeadSheetPersistedInkSnapshot(
            inkSnapshot: LeadSheetInkDrawingSnapshot(testValues: [12, 24]),
            coordinateSpace: PersistentInkCoordinateSpace(width: 320, height: 480)
        )

        XCTAssertFalse(
            LeadSheetInkPersistenceDedupePolicy.shouldSkipPersistence(
                activeInkScope: .page(frame: CGRect(x: 0, y: 0, width: 320, height: 480)),
                currentSnapshot: currentSnapshot,
                lastPersistedSnapshot: lastPersistedSnapshot
            )
        )
    }

    func testInkPersistenceDedupePolicyDoesNotSkipSemanticInk() {
        let persistedSnapshot = LeadSheetPersistedInkSnapshot(
            inkSnapshot: LeadSheetInkDrawingSnapshot(testValues: [12, 24]),
            coordinateSpace: PersistentInkCoordinateSpace(width: 320, height: 480)
        )

        XCTAssertFalse(
            LeadSheetInkPersistenceDedupePolicy.shouldSkipPersistence(
                activeInkScope: .chords(
                    frame: CGRect(x: 0, y: 0, width: 320, height: 80),
                    inputFrames: [CGRect(x: 0, y: 0, width: 320, height: 80)]
                ),
                currentSnapshot: persistedSnapshot,
                lastPersistedSnapshot: persistedSnapshot
            )
        )
    }

    func testActiveInkScopeIdentityAppliesPendingChordEraseOverStaleChart() throws {
        var staleChart = Chart.blank(title: "Erase Guard", measureCount: 1)
        staleChart.pageHandwrittenChordData = Data([0x01])
        staleChart.pageHandwrittenChordCoordinateSpace = PersistentInkCoordinateSpace(width: 320, height: 480)

        let updatedChart = try XCTUnwrap(
            LeadSheetActiveInkScope.Identity.chords.chartByPersistingDrawingData(
                nil,
                coordinateSpace: nil,
                in: staleChart
            )
        )

        XCTAssertNil(updatedChart.pageHandwrittenChordData)
        XCTAssertNil(updatedChart.pageHandwrittenChordCoordinateSpace)
    }

    func testInkCanvasSyncPolicyDoesNotPreserveDirtyRetiredRhythmInkFromStaleModelReload() {
        XCTAssertFalse(EditorCanvasMode.rhythmicNotationEdit.allowsDirectRhythmicNotationInk)
        XCTAssertFalse(
            LeadSheetInkCanvasSyncPolicy.shouldPreserveActiveCanvas(
                activeInkScope: .rhythmicMeasure(
                    measureID: UUID(),
                    frame: CGRect(x: 0, y: 0, width: 100, height: 40)
                ),
                interactionMode: .rhythmicNotationEdit,
                sessionState: dirtyInkSessionState(.rhythm),
                currentDrawingData: Data([0x01]),
                desiredDrawingData: Data([0x02])
            )
        )
    }

    func testInkCanvasSyncPolicyPreservesDirtyHeaderInkFromStaleModelReload() {
        XCTAssertTrue(
            LeadSheetInkCanvasSyncPolicy.shouldPreserveActiveCanvas(
                activeInkScope: .header(frame: CGRect(x: 0, y: 0, width: 320, height: 80)),
                interactionMode: .headerEntry,
                sessionState: dirtyInkSessionState(.passive),
                currentDrawingData: Data([0x01]),
                desiredDrawingData: Data([0x02])
            )
        )
    }

    func testInkCanvasSyncPolicyPreservesDirtyFreehandInkFromStaleModelReload() {
        XCTAssertTrue(
            LeadSheetInkCanvasSyncPolicy.shouldPreserveActiveCanvas(
                activeInkScope: .page(frame: CGRect(x: 0, y: 0, width: 320, height: 480)),
                interactionMode: .freeHand,
                sessionState: dirtyInkSessionState(.passive),
                currentDrawingData: Data([0x01]),
                desiredDrawingData: Data([0x02])
            )
        )
    }

    func testInkCanvasSyncPolicyDoesNotPreserveDirtyPassiveInkAfterScopeSwitch() {
        XCTAssertFalse(
            LeadSheetInkCanvasSyncPolicy.shouldPreserveActiveCanvas(
                activeInkScope: .header(frame: CGRect(x: 0, y: 0, width: 320, height: 80)),
                interactionMode: .headerEntry,
                sessionState: dirtyInkSessionState(.passive),
                currentDrawingData: Data([0x01]),
                desiredDrawingData: Data([0x02]),
                didSwitchInkScope: true
            )
        )
    }

    func testInkCanvasSyncPolicyAllowsPassiveInkReloadWhenCleanOrSynced() {
        XCTAssertFalse(
            LeadSheetInkCanvasSyncPolicy.shouldPreserveActiveCanvas(
                activeInkScope: .header(frame: CGRect(x: 0, y: 0, width: 320, height: 80)),
                interactionMode: .headerEntry,
                sessionState: dirtyInkSessionState(),
                currentDrawingData: Data([0x01]),
                desiredDrawingData: Data([0x02])
            )
        )
        XCTAssertFalse(
            LeadSheetInkCanvasSyncPolicy.shouldPreserveActiveCanvas(
                activeInkScope: .header(frame: CGRect(x: 0, y: 0, width: 320, height: 80)),
                interactionMode: .headerEntry,
                sessionState: dirtyInkSessionState(.passive),
                currentDrawingData: Data([0x01]),
                desiredDrawingData: Data([0x01])
            )
        )
    }

    func testInkCanvasSyncPolicyAllowsModelReloadWhenRhythmInkIsCleanOrAlreadySynced() {
        let activeScope = LeadSheetActiveInkScope.rhythmicMeasure(
            measureID: UUID(),
            frame: CGRect(x: 0, y: 0, width: 100, height: 40)
        )

        XCTAssertFalse(
            LeadSheetInkCanvasSyncPolicy.shouldPreserveActiveCanvas(
                activeInkScope: activeScope,
                interactionMode: .rhythmicNotationEdit,
                sessionState: dirtyInkSessionState(),
                currentDrawingData: Data([0x01]),
                desiredDrawingData: Data([0x02])
            )
        )
        XCTAssertFalse(
            LeadSheetInkCanvasSyncPolicy.shouldPreserveActiveCanvas(
                activeInkScope: activeScope,
                interactionMode: .rhythmicNotationEdit,
                sessionState: dirtyInkSessionState(.rhythm),
                currentDrawingData: Data([0x01]),
                desiredDrawingData: Data([0x01])
            )
        )
    }

    func testInkCanvasSyncPolicyTreatsEquivalentSerializedDrawingAsSynced() {
        let currentDrawing = PKDrawing(strokes: [snapshotStroke(creationDate: Date(timeIntervalSince1970: 10))])
        let desiredDrawing = PKDrawing(strokes: [snapshotStroke(creationDate: Date(timeIntervalSince1970: 20))])

        XCTAssertTrue(
            LeadSheetInkCanvasSyncPolicy.shouldTreatCanvasAsSynced(
                currentInkSnapshot: LeadSheetInkDrawingSnapshot(drawing: currentDrawing),
                desiredDrawingData: desiredDrawing.dataRepresentation()
            )
        )
        XCTAssertFalse(
            LeadSheetInkCanvasSyncPolicy.shouldTreatCanvasAsSynced(
                currentInkSnapshot: LeadSheetInkDrawingSnapshot(testValues: [99]),
                desiredDrawingData: desiredDrawing.dataRepresentation()
            )
        )
        XCTAssertFalse(
            LeadSheetInkCanvasSyncPolicy.shouldTreatCanvasAsSynced(
                currentInkSnapshot: LeadSheetInkDrawingSnapshot(drawing: currentDrawing),
                desiredDrawingData: nil
            )
        )
    }

    func testRestoredChordDraftPreviewPolicyBootstrapsCleanSavedChordInkInChordEntry() {
        let snapshot = LeadSheetInkDrawingSnapshot(testValues: [1, 2])

        XCTAssertTrue(
            ChordInkRestoredDraftPreviewPolicy.shouldBootstrap(
                interactionMode: .chordEntry,
                recognizesChordInk: true,
                previewState: ChordPreviewState(),
                restoredDrawingData: Data([0x01]),
                isDirtyChordInk: false,
                currentInkSnapshot: snapshot,
                lastBootstrappedSnapshot: nil
            )
        )
    }

    func testRestoredChordDraftPreviewPolicyRejectsUnavailableRestoreInputs() {
        let snapshot = LeadSheetInkDrawingSnapshot(testValues: [1, 2])

        XCTAssertFalse(
            ChordInkRestoredDraftPreviewPolicy.shouldBootstrap(
                interactionMode: .browse,
                recognizesChordInk: true,
                previewState: ChordPreviewState(),
                restoredDrawingData: Data([0x01]),
                isDirtyChordInk: false,
                currentInkSnapshot: snapshot,
                lastBootstrappedSnapshot: nil
            )
        )
        XCTAssertFalse(
            ChordInkRestoredDraftPreviewPolicy.shouldBootstrap(
                interactionMode: .chordEntry,
                recognizesChordInk: false,
                previewState: ChordPreviewState(),
                restoredDrawingData: Data([0x01]),
                isDirtyChordInk: false,
                currentInkSnapshot: snapshot,
                lastBootstrappedSnapshot: nil
            )
        )
        XCTAssertFalse(
            ChordInkRestoredDraftPreviewPolicy.shouldBootstrap(
                interactionMode: .chordEntry,
                recognizesChordInk: true,
                previewState: ChordPreviewState(),
                restoredDrawingData: nil,
                isDirtyChordInk: false,
                currentInkSnapshot: snapshot,
                lastBootstrappedSnapshot: nil
            )
        )
        XCTAssertFalse(
            ChordInkRestoredDraftPreviewPolicy.shouldBootstrap(
                interactionMode: .chordEntry,
                recognizesChordInk: true,
                previewState: ChordPreviewState(),
                restoredDrawingData: Data(),
                isDirtyChordInk: false,
                currentInkSnapshot: snapshot,
                lastBootstrappedSnapshot: nil
            )
        )
        XCTAssertFalse(
            ChordInkRestoredDraftPreviewPolicy.shouldBootstrap(
                interactionMode: .chordEntry,
                recognizesChordInk: true,
                previewState: ChordPreviewState(),
                restoredDrawingData: Data([0x01]),
                isDirtyChordInk: false,
                currentInkSnapshot: nil,
                lastBootstrappedSnapshot: nil
            )
        )
    }

    func testRestoredChordDraftPreviewPolicyRejectsDirtyExistingOrRepeatedPreviewWork() {
        let snapshot = LeadSheetInkDrawingSnapshot(testValues: [1, 2])
        var previewState = ChordPreviewState()
        previewState.replaceDraftBarlines(with: [
            DraftBarline(
                measureID: UUID(),
                measureIndex: 0,
                fraction: 0.5,
                metrics: DraftBarlineGestureMetrics(
                    height: 48,
                    width: 2,
                    angleDegreesFromVertical: 1,
                    straightness: 0.95,
                    laneCoverage: 0.8
                )
            )
        ])

        XCTAssertFalse(
            ChordInkRestoredDraftPreviewPolicy.shouldBootstrap(
                interactionMode: .chordEntry,
                recognizesChordInk: true,
                previewState: ChordPreviewState(),
                restoredDrawingData: Data([0x01]),
                isDirtyChordInk: true,
                currentInkSnapshot: snapshot,
                lastBootstrappedSnapshot: nil
            )
        )
        XCTAssertFalse(
            ChordInkRestoredDraftPreviewPolicy.shouldBootstrap(
                interactionMode: .chordEntry,
                recognizesChordInk: true,
                previewState: previewState,
                restoredDrawingData: Data([0x01]),
                isDirtyChordInk: false,
                currentInkSnapshot: snapshot,
                lastBootstrappedSnapshot: nil
            )
        )
        XCTAssertFalse(
            ChordInkRestoredDraftPreviewPolicy.shouldBootstrap(
                interactionMode: .chordEntry,
                recognizesChordInk: true,
                previewState: ChordPreviewState(),
                restoredDrawingData: Data([0x01]),
                isDirtyChordInk: false,
                currentInkSnapshot: snapshot,
                lastBootstrappedSnapshot: snapshot
            )
        )
        XCTAssertTrue(
            ChordInkRestoredDraftPreviewPolicy.shouldBootstrap(
                interactionMode: .chordEntry,
                recognizesChordInk: true,
                previewState: ChordPreviewState(),
                restoredDrawingData: Data([0x01]),
                isDirtyChordInk: false,
                currentInkSnapshot: snapshot,
                lastBootstrappedSnapshot: LeadSheetInkDrawingSnapshot(testValues: [3, 4])
            )
        )
    }

    func testChordEmptyDraftPreviewPolicyHandlesOnlyErasedChordInk() {
        XCTAssertTrue(
            ChordInkEmptyDraftPreviewPolicy.shouldHandleEmptyChordInk(
                interactionMode: .chordEntry,
                activeRole: .chord,
                strokeCount: 0
            )
        )
        XCTAssertFalse(
            ChordInkEmptyDraftPreviewPolicy.shouldHandleEmptyChordInk(
                interactionMode: .chordEntry,
                activeRole: .chord,
                strokeCount: 1
            )
        )
        XCTAssertFalse(
            ChordInkEmptyDraftPreviewPolicy.shouldHandleEmptyChordInk(
                interactionMode: .browse,
                activeRole: .chord,
                strokeCount: 0
            )
        )
        XCTAssertFalse(
            ChordInkEmptyDraftPreviewPolicy.shouldHandleEmptyChordInk(
                interactionMode: .chordEntry,
                activeRole: .passive,
                strokeCount: 0
            )
        )
        XCTAssertFalse(
            ChordInkEmptyDraftPreviewPolicy.shouldHandleEmptyChordInk(
                interactionMode: .chordEntry,
                activeRole: nil,
                strokeCount: 0
            )
        )
    }

    func testChordEmptyDraftPreviewPolicyDiscardsOnlyNonEmptyPreview() {
        var previewState = ChordPreviewState()

        XCTAssertFalse(ChordInkEmptyDraftPreviewPolicy.shouldDiscardDraftPreview(previewState))

        previewState.replaceDraftChords(with: [
            ChordInkDraftInput(
                measureID: UUID(),
                measureIndex: 0,
                targetFraction: 0.2,
                drawingData: Data([0x01]),
                candidateTexts: ["C"],
                bestCandidateText: "C",
                confidence: 0.8,
                strokeCount: 1
            )
        ])

        XCTAssertTrue(ChordInkEmptyDraftPreviewPolicy.shouldDiscardDraftPreview(previewState))
    }

    func testCanvasLayoutInvalidationPolicyRefreshesWhenChordLaneModeChanges() {
        XCTAssertTrue(
            LeadSheetCanvasLayoutInvalidationPolicy.requiresLayoutRefresh(
                previousMode: .browse,
                nextMode: .chordEntry
            )
        )
        XCTAssertTrue(
            LeadSheetCanvasLayoutInvalidationPolicy.requiresLayoutRefresh(
                previousMode: .chordEntry,
                nextMode: .browse
            )
        )
        XCTAssertFalse(
            LeadSheetCanvasLayoutInvalidationPolicy.requiresLayoutRefresh(
                previousMode: .browse,
                nextMode: .measureEdit
            )
        )
        XCTAssertFalse(
            LeadSheetCanvasLayoutInvalidationPolicy.requiresLayoutRefresh(
                previousMode: .freeHand,
                nextMode: .headerEntry
            )
        )
    }

    func testChordDiagnosticPreviewScrollAcceptsPencilInput() {
        XCTAssertFalse(ChordDiagnosticPreviewScrollPolicy.isScrollEnabled(itemCount: 0))
        XCTAssertTrue(ChordDiagnosticPreviewScrollPolicy.isScrollEnabled(itemCount: 1))

        let simulatorTouchTypes = Set(
            ChordDiagnosticPreviewScrollPolicy
                .allowedTouchTypes(environment: .simulator)
                .map { Int($0.intValue) }
        )

        XCTAssertEqual(
            simulatorTouchTypes,
            Set([
                UITouch.TouchType.direct.rawValue,
                UITouch.TouchType.pencil.rawValue
            ])
        )

        let deviceTouchTypes = Set(
            ChordDiagnosticPreviewScrollPolicy
                .allowedTouchTypes(environment: .device)
                .map { Int($0.intValue) }
        )
        XCTAssertEqual(
            deviceTouchTypes,
            Set([UITouch.TouchType.pencil.rawValue])
        )
    }

    func testFreehandActiveInkScopeUsesRawPageInkForAllV1Styles() {
        let simplePage = LeadSheetPageLayoutEngine.pageLayout(
            for: Chart.blank(title: "Simple", measureCount: 1, layoutStyle: .simpleChordSheet),
            pageSize: CGSize(width: 900, height: 1400)
        )
        let rhythmPage = LeadSheetPageLayoutEngine.pageLayout(
            for: Chart.blank(title: "Rhythm", measureCount: 1, layoutStyle: .rhythmSectionSheet),
            pageSize: CGSize(width: 900, height: 1400)
        )
        let leadPage = LeadSheetPageLayoutEngine.pageLayout(
            for: Chart.blank(title: "Lead", measureCount: 1, layoutStyle: .leadSheet),
            pageSize: CGSize(width: 900, height: 1400)
        )

        let simpleScope = LeadSheetActiveInkScope.resolve(
            interactionMode: .freeHand,
            chartLayoutStyle: .simpleChordSheet,
            selectedMeasureID: nil,
            selectedMeasureLayout: nil,
            pageLayout: simplePage
        )
        let rhythmScope = LeadSheetActiveInkScope.resolve(
            interactionMode: .freeHand,
            chartLayoutStyle: .rhythmSectionSheet,
            selectedMeasureID: nil,
            selectedMeasureLayout: nil,
            pageLayout: rhythmPage
        )
        let leadScope = LeadSheetActiveInkScope.resolve(
            interactionMode: .freeHand,
            chartLayoutStyle: .leadSheet,
            selectedMeasureID: nil,
            selectedMeasureLayout: nil,
            pageLayout: leadPage
        )

        guard case .page(let simpleFrame) = simpleScope,
              case .page(let rhythmFrame) = rhythmScope,
              case .page(let leadFrame) = leadScope else {
            XCTFail("Free-Write should resolve to raw page ink scopes")
            return
        }
        XCTAssertEqual(simpleFrame, LeadSheetActiveInkScope.pageWritingFrame(for: simplePage))
        XCTAssertEqual(rhythmFrame, LeadSheetActiveInkScope.pageWritingFrame(for: rhythmPage))
        XCTAssertEqual(leadFrame, LeadSheetActiveInkScope.pageWritingFrame(for: leadPage))
    }

    func testHeaderActiveInkScopeUsesHeaderFrameForAllV1Styles() {
        let simplePage = LeadSheetPageLayoutEngine.pageLayout(
            for: Chart.blank(title: "Simple", measureCount: 1, layoutStyle: .simpleChordSheet),
            pageSize: CGSize(width: 900, height: 1400)
        )
        let rhythmPage = LeadSheetPageLayoutEngine.pageLayout(
            for: Chart.blank(title: "Rhythm", measureCount: 1, layoutStyle: .rhythmSectionSheet),
            pageSize: CGSize(width: 900, height: 1400)
        )

        let simpleScope = LeadSheetActiveInkScope.resolve(
            interactionMode: .headerEntry,
            chartLayoutStyle: .simpleChordSheet,
            selectedMeasureID: nil,
            selectedMeasureLayout: nil,
            pageLayout: simplePage
        )
        let rhythmScope = LeadSheetActiveInkScope.resolve(
            interactionMode: .headerEntry,
            chartLayoutStyle: .rhythmSectionSheet,
            selectedMeasureID: nil,
            selectedMeasureLayout: nil,
            pageLayout: rhythmPage
        )

        guard case .header(let simpleFrame) = simpleScope,
              case .header(let rhythmFrame) = rhythmScope else {
            XCTFail("Header writing should resolve a header ink scope")
            return
        }

        XCTAssertEqual(simpleFrame, simplePage.header.handwrittenFrame)
        XCTAssertEqual(rhythmFrame, rhythmPage.header.handwrittenFrame)
    }

    func testRhythmicNotationActiveInkScopeIsRetiredEvenForRhythmCapableProfiles() throws {
        let simpleChart = Chart.blank(title: "Simple", measureCount: 1, layoutStyle: .simpleChordSheet)
        let rhythmChart = Chart.blank(title: "Rhythm", measureCount: 1, layoutStyle: .rhythmSectionSheet)
        let leadChart = Chart.blank(title: "Lead", measureCount: 1, layoutStyle: .leadSheet)
        let simplePage = LeadSheetPageLayoutEngine.pageLayout(
            for: simpleChart,
            pageSize: CGSize(width: 900, height: 1400)
        )
        let rhythmPage = LeadSheetPageLayoutEngine.pageLayout(
            for: rhythmChart,
            pageSize: CGSize(width: 900, height: 1400)
        )
        let leadPage = LeadSheetPageLayoutEngine.pageLayout(
            for: leadChart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let simpleMeasureLayout = try XCTUnwrap(simplePage.systems.first?.measures.first)
        let rhythmMeasureLayout = try XCTUnwrap(rhythmPage.systems.first?.measures.first)
        let leadMeasureLayout = try XCTUnwrap(leadPage.systems.first?.measures.first)
        let simpleMeasureID = try XCTUnwrap(simpleChart.measures.first?.id)
        let rhythmMeasureID = try XCTUnwrap(rhythmChart.measures.first?.id)
        let leadMeasureID = try XCTUnwrap(leadChart.measures.first?.id)

        let simpleScope = LeadSheetActiveInkScope.resolve(
            interactionMode: .rhythmicNotationEdit,
            chartLayoutStyle: .simpleChordSheet,
            selectedMeasureID: simpleMeasureID,
            selectedMeasureLayout: simpleMeasureLayout,
            pageLayout: simplePage
        )
        let rhythmScope = LeadSheetActiveInkScope.resolve(
            interactionMode: .rhythmicNotationEdit,
            chartLayoutStyle: .rhythmSectionSheet,
            selectedMeasureID: rhythmMeasureID,
            selectedMeasureLayout: rhythmMeasureLayout,
            pageLayout: rhythmPage
        )
        let leadScope = LeadSheetActiveInkScope.resolve(
            interactionMode: .rhythmicNotationEdit,
            chartLayoutStyle: .leadSheet,
            selectedMeasureID: leadMeasureID,
            selectedMeasureLayout: leadMeasureLayout,
            pageLayout: leadPage
        )

        XCTAssertNil(simpleScope)
        XCTAssertNil(rhythmScope)
        XCTAssertNil(leadScope)
    }

    func testParkedRhythmicNotationCapturePolicyUsesExpandedCaptureFrame() throws {
        let chart = Chart.blank(title: "Rhythm", measureCount: 1, layoutStyle: .rhythmSectionSheet)
        let page = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )
        let measureLayout = try XCTUnwrap(page.systems.first?.measures.first)

        let captureFrame = LeadSheetRhythmicNotationInkCapturePolicy.captureFrame(for: measureLayout)
        let legacyFrame = measureLayout.writableFrame.insetBy(dx: 2, dy: 2)
        XCTAssertEqual(
            captureFrame,
            LeadSheetRhythmicNotationInkCapturePolicy.captureFrame(for: measureLayout)
        )
        XCTAssertTrue(captureFrame.contains(measureLayout.writableFrame))
        XCTAssertLessThan(captureFrame.minX, legacyFrame.minX)
        XCTAssertLessThan(captureFrame.minY, legacyFrame.minY)
        XCTAssertGreaterThan(captureFrame.maxX, legacyFrame.maxX)
        XCTAssertGreaterThan(captureFrame.maxY, legacyFrame.maxY)
    }

    func testRhythmTapFinalizeUsesExpandedCaptureFrame() throws {
        let chart = Chart.blank(title: "Rhythm", measureCount: 1, layoutStyle: .rhythmSectionSheet)
        let page = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )
        let measureLayout = try XCTUnwrap(page.systems.first?.measures.first)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        let oldTapFrame = measureLayout.writableFrame.insetBy(dx: -8, dy: -8)
        let expandedTapFrame = LeadSheetRhythmicNotationInkCapturePolicy.tapFinalizeFrame(
            for: measureLayout
        )
        XCTAssertGreaterThan(expandedTapFrame.maxY, oldTapFrame.maxY)

        let stillWritingLocation = CGPoint(
            x: expandedTapFrame.midX,
            y: (oldTapFrame.maxY + expandedTapFrame.maxY) / 2
        )
        XCTAssertFalse(oldTapFrame.contains(stillWritingLocation))
        XCTAssertTrue(expandedTapFrame.contains(stillWritingLocation))
        XCTAssertFalse(
            LeadSheetRhythmicNotationFinalization.shouldFinalizeTap(
                interactionMode: .rhythmicNotationEdit,
                selectedMeasureID: measureID,
                activeMeasureLayout: measureLayout,
                location: stillWritingLocation,
                nextMeasureID: measureID
            )
        )
    }

    func testSimpleRowGroupAffordanceGroupsSelectedMeasureThroughCurrentRow() throws {
        var chart = Chart.blank(title: "Manual Rows", measureCount: 6, layoutStyle: .simpleChordSheet)
        let measureIDs = chart.measures.map(\.id)
        XCTAssertTrue(chart.insertSimpleSystemBreak(before: measureIDs[4]))
        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        let affordance = try XCTUnwrap(
            LeadSheetSimpleRowGroupAffordanceGeometry.affordance(
                for: measureIDs[1],
                in: layout,
                layoutStyle: chart.layoutStyle
            )
        )
        let selectedMeasure = try XCTUnwrap(
            layout.systems[0].measures.first { $0.sourceMeasureID == measureIDs[1] }
        )
        let lastGroupedMeasure = try XCTUnwrap(
            layout.systems[0].measures.first { $0.sourceMeasureID == measureIDs[3] }
        )
        let displayedLastGroupedMeasure = LeadSheetSimpleChordTerminalBarlineGeometry.displayMeasure(
            lastGroupedMeasure,
            in: layout.systems[0],
            paperFrame: layout.paperFrame,
            layoutStyle: chart.layoutStyle
        )

        XCTAssertEqual(affordance.selectedMeasureID, measureIDs[1])
        XCTAssertEqual(affordance.groupedMeasureIDs, Array(measureIDs[1..<4]))
        XCTAssertEqual(affordance.groupFrame.minX, selectedMeasure.frame.minX, accuracy: 0.001)
        XCTAssertEqual(affordance.groupFrame.maxX, displayedLastGroupedMeasure.frame.maxX, accuracy: 0.001)
        XCTAssertLessThan(affordance.guideY, affordance.groupFrame.midY)
    }

    func testSimpleRowGroupAffordanceIsSimpleOnly() throws {
        let chart = Chart.blank(title: "Pocket", measureCount: 4, layoutStyle: .rhythmSectionSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )

        XCTAssertNil(
            LeadSheetSimpleRowGroupAffordanceGeometry.affordance(
                for: measureID,
                in: layout,
                layoutStyle: chart.layoutStyle
            )
        )
        XCTAssertNil(
            LeadSheetSimpleRowGroupAffordanceGeometry.affordance(
                for: nil,
                in: layout,
                layoutStyle: .simpleChordSheet
            )
        )
    }

    func testRhythmAdvisoryRequiresStableNonEmptyScheduledSnapshot() {
        let snapshot = LeadSheetInkDrawingSnapshot(testValues: [1, 2])

        XCTAssertTrue(
            LeadSheetRhythmicNotationAdvisoryPolicy.canUseScheduledSnapshot(
                currentInkSnapshot: snapshot,
                scheduledInkSnapshot: snapshot
            )
        )
        XCTAssertFalse(
            LeadSheetRhythmicNotationAdvisoryPolicy.canUseScheduledSnapshot(
                currentInkSnapshot: LeadSheetInkDrawingSnapshot(testValues: [1, 3]),
                scheduledInkSnapshot: snapshot
            )
        )
        XCTAssertFalse(
            LeadSheetRhythmicNotationAdvisoryPolicy.canUseScheduledSnapshot(
                currentInkSnapshot: nil,
                scheduledInkSnapshot: snapshot
            )
        )
        XCTAssertFalse(
            LeadSheetRhythmicNotationAdvisoryPolicy.canUseScheduledSnapshot(
                currentInkSnapshot: nil,
                scheduledInkSnapshot: nil
            )
        )
    }

    func testInkAuthoringSessionPolicyRequiresStableSnapshotForScheduledRecognitionWork() {
        let snapshot = LeadSheetInkDrawingSnapshot(testValues: [1, 2])

        XCTAssertTrue(
            LeadSheetInkAuthoringSessionPolicy.canUseScheduledSnapshot(
                currentInkSnapshot: snapshot,
                scheduledInkSnapshot: snapshot
            )
        )
        XCTAssertFalse(
            LeadSheetInkAuthoringSessionPolicy.canUseScheduledSnapshot(
                currentInkSnapshot: LeadSheetInkDrawingSnapshot(testValues: [1, 3]),
                scheduledInkSnapshot: snapshot
            )
        )
        XCTAssertFalse(
            LeadSheetInkAuthoringSessionPolicy.canUseScheduledSnapshot(
                currentInkSnapshot: snapshot,
                scheduledInkSnapshot: nil
            )
        )
        XCTAssertTrue(
            LeadSheetInkAuthoringSessionPolicy.canUseScheduledSnapshot(
                currentInkSnapshot: nil,
                scheduledInkSnapshot: nil
            )
        )
    }

    func testRhythmLiveAdvisoryRecognitionStaysDisabledWhileToolIsRetired() {
        let measureID = UUID()
        let snapshot = LeadSheetInkDrawingSnapshot(testValues: [1, 2])

        XCTAssertFalse(LeadSheetRhythmicNotationLiveAdvisoryRecognitionPolicy.persistsLiveInkDuringAdvisory)
        XCTAssertFalse(
            LeadSheetRhythmicNotationLiveAdvisoryRecognitionPolicy.shouldAnalyzeStableInk(
                interactionMode: .rhythmicNotationEdit,
                selectedMeasureID: measureID,
                targetMeasureID: measureID,
                currentInkSnapshot: snapshot,
                scheduledInkSnapshot: snapshot
            )
        )
    }

    func testRhythmLiveAdvisoryRecognitionRejectsStaleOrUnselectedInk() {
        let measureID = UUID()
        let otherMeasureID = UUID()
        let snapshot = LeadSheetInkDrawingSnapshot(testValues: [1, 2])

        XCTAssertFalse(
            LeadSheetRhythmicNotationLiveAdvisoryRecognitionPolicy.shouldAnalyzeStableInk(
                interactionMode: .rhythmicNotationEdit,
                selectedMeasureID: measureID,
                targetMeasureID: measureID,
                currentInkSnapshot: LeadSheetInkDrawingSnapshot(testValues: [1, 3]),
                scheduledInkSnapshot: snapshot
            )
        )
        XCTAssertFalse(
            LeadSheetRhythmicNotationLiveAdvisoryRecognitionPolicy.shouldAnalyzeStableInk(
                interactionMode: .rhythmicNotationEdit,
                selectedMeasureID: otherMeasureID,
                targetMeasureID: measureID,
                currentInkSnapshot: snapshot,
                scheduledInkSnapshot: snapshot
            )
        )
        XCTAssertFalse(
            LeadSheetRhythmicNotationLiveAdvisoryRecognitionPolicy.shouldAnalyzeStableInk(
                interactionMode: .browse,
                selectedMeasureID: measureID,
                targetMeasureID: measureID,
                currentInkSnapshot: snapshot,
                scheduledInkSnapshot: snapshot
            )
        )
    }

    func testRhythmAdvisorySnapshotIgnoresSerializedDrawingMetadata() {
        let firstDrawing = PKDrawing(strokes: [snapshotStroke(creationDate: Date(timeIntervalSince1970: 10))])
        let secondDrawing = PKDrawing(strokes: [snapshotStroke(creationDate: Date(timeIntervalSince1970: 20))])
        let firstSnapshot = LeadSheetInkDrawingSnapshot(drawing: firstDrawing)
        let secondSnapshot = LeadSheetInkDrawingSnapshot(drawing: secondDrawing)

        XCTAssertNotNil(firstSnapshot)
        XCTAssertNotNil(secondSnapshot)
        XCTAssertTrue(
            LeadSheetRhythmicNotationAdvisoryPolicy.canUseScheduledSnapshot(
                currentInkSnapshot: firstSnapshot,
                scheduledInkSnapshot: secondSnapshot
            )
        )
    }

    func testRhythmReadyToRenderRequiresNaturalExactFitAfterErase() {
        let naturallyExactProposal = RhythmicNotationMeasureProposal(
            values: [.quarter, .quarter, .half],
            safety: .readyToRender,
            isNaturalExactFit: true
        )
        let stretchedProposal = RhythmicNotationMeasureProposal(
            values: [.quarter, .quarter, .half],
            safety: .readyToRender,
            isNaturalExactFit: false
        )

        XCTAssertFalse(
            LeadSheetRhythmicNotationAdvisoryPolicy.canRenderProposal(
                stretchedProposal,
                requiresNaturalExactFitAfterErase: true
            )
        )
        XCTAssertTrue(
            LeadSheetRhythmicNotationAdvisoryPolicy.canRenderProposal(
                naturallyExactProposal,
                requiresNaturalExactFitAfterErase: true
            )
        )
        XCTAssertFalse(
            LeadSheetRhythmicNotationAdvisoryPolicy.canRenderProposal(
                stretchedProposal,
                requiresNaturalExactFitAfterErase: false
            )
        )
    }

    func testRhythmTapToRenderAdvisoryUsesReadableDelay() {
        XCTAssertGreaterThanOrEqual(
            LeadSheetRhythmicNotationAdvisoryPolicy.tapToRenderAdvisoryDelay,
            0.5
        )
        XCTAssertLessThanOrEqual(
            LeadSheetRhythmicNotationAdvisoryPolicy.tapToRenderAdvisoryDelay,
            1.3
        )
    }

    func testRhythmLiveDecisionRouteMarksSafeProposalReadyUntilUserTap() {
        let proposal = RhythmicNotationMeasureProposal(
            values: [.quarter, .quarter, .quarter, .quarter],
            safety: .readyToRender,
            isNaturalExactFit: true
        )
        let decision = RhythmRecognitionDecision.commit(
            proposal,
            completedRhythmPhrase(values: proposal.values)
        )

        let route = LeadSheetRhythmicNotationLiveDecisionPolicy.route(
            for: decision,
            requiresNaturalExactFitAfterErase: false
        )

        guard case .readyToRender(let renderedProposal) = route else {
            return XCTFail("Expected a safe full-measure phrase to wait for tap-to-render.")
        }
        XCTAssertEqual(renderedProposal, proposal)
    }

    func testRhythmLiveDecisionRouteCommitsSafeProposalDuringTapFinalization() {
        let proposal = RhythmicNotationMeasureProposal(
            values: [.quarter, .quarter, .quarter, .quarter],
            safety: .readyToRender,
            isNaturalExactFit: true
        )
        let decision = RhythmRecognitionDecision.commit(
            proposal,
            completedRhythmPhrase(values: proposal.values)
        )

        let route = LeadSheetRhythmicNotationLiveDecisionPolicy.route(
            for: decision,
            requiresNaturalExactFitAfterErase: false,
            allowsCommit: true
        )

        guard case .commit(let renderedProposal) = route else {
            return XCTFail("Expected tap finalization to commit a safe full-measure phrase.")
        }
        XCTAssertEqual(renderedProposal, proposal)
    }

    func testRhythmLiveAdvisoryRecognitionNeverCommitsRenderedValues() {
        let proposal = RhythmicNotationMeasureProposal(
            values: [.quarter, .quarter, .quarter, .quarter],
            safety: .readyToRender,
            isNaturalExactFit: true
        )
        let decision = RhythmRecognitionDecision.commit(
            proposal,
            completedRhythmPhrase(values: proposal.values)
        )
        let route = LeadSheetRhythmicNotationLiveDecisionPolicy.route(
            for: decision,
            requiresNaturalExactFitAfterErase: false
        )

        XCTAssertEqual(route, .readyToRender(proposal: proposal))
        XCTAssertFalse(
            LeadSheetRhythmicNotationLiveAdvisoryRecognitionPolicy.shouldCommitFromAdvisoryRoute(route)
        )
    }

    func testRhythmLiveDecisionRoutePreservesManualReviewWithoutConfirmationFallback() {
        let proposal = RhythmicNotationMeasureProposal(
            values: [.quarter, .quarter, .quarter, .quarter],
            safety: .manualReview,
            isNaturalExactFit: true
        )
        let decision = RhythmRecognitionDecision.needsReview(
            .manualReview,
            completedRhythmPhrase(values: proposal.values),
            proposal
        )

        let route = LeadSheetRhythmicNotationLiveDecisionPolicy.route(
            for: decision,
            requiresNaturalExactFitAfterErase: false
        )

        XCTAssertEqual(route, .preserveInk(showsUnreadFeedback: true))
    }

    func testRhythmLiveDecisionRouteShowsUnderfilledFeedbackWhenInkWasRecognized() {
        let decision = RhythmRecognitionDecision.keepWriting(
            .underfilled,
            RhythmPhraseHypothesis(
                source: .gridFirst,
                symbols: [],
                uncoveredStrokeIndices: [],
                naturalValues: [.quarter, .quarter],
                naturalUnits: 4,
                targetUnits: 8,
                passesCompendium: false
            )
        )

        let route = LeadSheetRhythmicNotationLiveDecisionPolicy.route(
            for: decision,
            requiresNaturalExactFitAfterErase: false
        )

        XCTAssertEqual(route, .preserveInk(showsUnreadFeedback: true))
        XCTAssertEqual(
            LeadSheetRhythmicNotationFeedbackPolicy.feedbackMessage(for: decision),
            "Needs 2 more beats"
        )
    }

    func testRhythmUnderfilledFeedbackNamesSingleMissingBeat() {
        let decision = RhythmRecognitionDecision.keepWriting(
            .underfilled,
            RhythmPhraseHypothesis(
                source: .gridFirst,
                symbols: [
                    RhythmSymbolHypothesis(
                        coveredStrokeIndices: [0],
                        bounds: CGRect(x: 12, y: 48, width: 16, height: 22),
                        candidateValues: [.eighth],
                        selectedValue: .eighth
                    )
                ],
                uncoveredStrokeIndices: [],
                naturalValues: [.eighth, .eighth, .half],
                naturalUnits: 6,
                targetUnits: 8,
                passesCompendium: false
            )
        )

        let route = LeadSheetRhythmicNotationLiveDecisionPolicy.route(
            for: decision,
            requiresNaturalExactFitAfterErase: false
        )

        XCTAssertEqual(route, .preserveInk(showsUnreadFeedback: true))
        XCTAssertEqual(
            LeadSheetRhythmicNotationFeedbackPolicy.feedbackMessage(for: decision),
            "Needs 1 more beat"
        )
    }

    func testRhythmLiveDecisionRouteLocalizesUnreadFeedbackForCompleteFailedPhrase() {
        let decision = RhythmRecognitionDecision.keepWriting(
            .unsupported,
            RhythmPhraseHypothesis(
                source: .gridFirst,
                symbols: [
                    RhythmSymbolHypothesis(
                        coveredStrokeIndices: [0],
                        bounds: CGRect(x: 12, y: 48, width: 16, height: 22),
                        candidateValues: [.quarter],
                        selectedValue: .quarter
                    ),
                    RhythmSymbolHypothesis(
                        coveredStrokeIndices: [1],
                        bounds: CGRect(x: 46, y: 48, width: 16, height: 22),
                        candidateValues: [.quarter],
                        selectedValue: .quarter
                    ),
                    RhythmSymbolHypothesis(
                        coveredStrokeIndices: [2],
                        bounds: CGRect(x: 80, y: 48, width: 16, height: 22),
                        candidateValues: [.quarter],
                        selectedValue: .quarter
                    ),
                    RhythmSymbolHypothesis(
                        coveredStrokeIndices: [3],
                        bounds: CGRect(x: 114, y: 48, width: 16, height: 22),
                        candidateValues: [.quarter],
                        selectedValue: .quarter
                    ),
                    RhythmSymbolHypothesis(
                        coveredStrokeIndices: [4],
                        bounds: CGRect(x: 150, y: 18, width: 10, height: 30),
                        candidateValues: [],
                        selectedValue: nil
                    )
                ],
                uncoveredStrokeIndices: [],
                naturalValues: [.quarter, .quarter, .quarter, .quarter],
                naturalUnits: 8,
                targetUnits: 8,
                passesCompendium: true
            )
        )

        let route = LeadSheetRhythmicNotationLiveDecisionPolicy.route(
            for: decision,
            requiresNaturalExactFitAfterErase: false
        )

        XCTAssertEqual(route, .preserveInk(showsUnreadFeedback: true))
    }

    func testRhythmUnreadInkFeedbackWaitsForCompletedTargetedDecision() {
        XCTAssertFalse(
            LeadSheetRhythmicNotationFeedbackPolicy.shouldHighlightUnreadInk(
                for: .keepWriting(.unsupported, nil)
            )
        )
        XCTAssertFalse(
            LeadSheetRhythmicNotationFeedbackPolicy.shouldHighlightUnreadInk(
                for: .needsReview(.ambiguousPhrase, nil, nil)
            )
        )
        XCTAssertFalse(
            LeadSheetRhythmicNotationFeedbackPolicy.shouldHighlightUnreadInk(
                for: .keepWriting(.underfilled, nil)
            )
        )
        XCTAssertFalse(
            LeadSheetRhythmicNotationFeedbackPolicy.shouldHighlightUnreadInk(
                for: .keepWriting(.noInk, nil)
            )
        )
    }

    func testRhythmUnreadInkFeedbackDoesNotFallbackToWholeCanvasFrame() {
        let drawing = PKDrawing(strokes: [snapshotStroke(creationDate: Date(timeIntervalSince1970: 10))])
        let feedbackFrame = LeadSheetRhythmicNotationFeedbackPolicy.unreadInkFrame(
            for: drawing,
            decision: .keepWriting(.unsupported, nil),
            canvasFrame: CGRect(x: 30, y: 40, width: 120, height: 80)
        )

        XCTAssertNil(feedbackFrame)
    }

    func testRhythmUnreadInkFeedbackFramesUnderfilledInkImmediately() {
        let drawing = PKDrawing(strokes: [snapshotStroke(creationDate: Date(timeIntervalSince1970: 10))])
        let decision = RhythmRecognitionDecision.keepWriting(
            .underfilled,
            RhythmPhraseHypothesis(
                source: .gridFirst,
                symbols: [],
                uncoveredStrokeIndices: [],
                naturalValues: [.quarter, .quarter],
                naturalUnits: 4,
                targetUnits: 8,
                passesCompendium: false
            )
        )

        XCTAssertTrue(LeadSheetRhythmicNotationFeedbackPolicy.shouldHighlightUnreadInk(for: decision))

        let feedbackFrame = LeadSheetRhythmicNotationFeedbackPolicy.unreadInkFrame(
            for: drawing,
            decision: decision,
            canvasFrame: CGRect(x: 30, y: 40, width: 140, height: 90),
            padding: 4
        )

        XCTAssertNotNil(feedbackFrame)
        XCTAssertTrue(feedbackFrame?.contains(CGPoint(x: 38, y: 92)) ?? false)
        XCTAssertTrue(feedbackFrame?.contains(CGPoint(x: 50, y: 68)) ?? false)
        XCTAssertFalse(feedbackFrame?.contains(CGPoint(x: 160, y: 120)) ?? true)
    }

    func testRhythmUnreadInkFeedbackTargetsUncoveredStrokeFrameWhenAvailable() {
        let drawing = PKDrawing(strokes: [snapshotStroke(creationDate: Date(timeIntervalSince1970: 10))])
        let phrase = RhythmPhraseHypothesis(
            source: .gridFirst,
            glyphEvidence: [
                RhythmGlyphEvidence(
                    kind: .slash,
                    strokeIndices: [0],
                    bounds: CGRect(x: 8, y: 52, width: 12, height: 18),
                    confidence: 0.05
                ),
                RhythmGlyphEvidence(
                    kind: .unknownStroke,
                    strokeIndices: [1],
                    bounds: CGRect(x: 78, y: 20, width: 6, height: 24),
                    confidence: 1.0
                )
            ],
            symbols: [],
            uncoveredStrokeIndices: [1],
            naturalValues: [.slash, .slash, .slash, .slash],
            naturalUnits: 8,
            targetUnits: 8,
            passesCompendium: true
        )

        let feedbackFrame = LeadSheetRhythmicNotationFeedbackPolicy.unreadInkFrame(
            for: drawing,
            decision: .keepWriting(.uncoveredStrokes, phrase),
            canvasFrame: CGRect(x: 30, y: 40, width: 140, height: 90),
            padding: 4
        )

        XCTAssertNotNil(feedbackFrame)
        XCTAssertTrue(feedbackFrame?.contains(CGPoint(x: 111, y: 72)) ?? false)
        XCTAssertFalse(feedbackFrame?.contains(CGPoint(x: 44, y: 101)) ?? true)
    }

    func testRhythmUnreadInkFeedbackDoesNotTargetUnreadV4SymbolBeforeMeasureIsComplete() {
        let drawing = PKDrawing(strokes: [snapshotStroke(creationDate: Date(timeIntervalSince1970: 10))])
        let phrase = RhythmPhraseHypothesis(
            source: .gridFirst,
            symbols: [
                RhythmSymbolHypothesis(
                    coveredStrokeIndices: [0],
                    bounds: CGRect(x: 12, y: 48, width: 16, height: 22),
                    candidateValues: [.quarter],
                    selectedValue: .quarter
                ),
                RhythmSymbolHypothesis(
                    coveredStrokeIndices: [1],
                    bounds: CGRect(x: 86, y: 18, width: 10, height: 30),
                    candidateValues: [],
                    selectedValue: nil
                )
            ],
            uncoveredStrokeIndices: [],
            naturalValues: [.quarter],
            naturalUnits: 2,
            targetUnits: 8,
            passesCompendium: false
        )

        XCTAssertFalse(
            LeadSheetRhythmicNotationFeedbackPolicy.shouldHighlightUnreadInk(
                for: .keepWriting(.unsupported, phrase)
            )
        )
        let feedbackFrame = LeadSheetRhythmicNotationFeedbackPolicy.unreadInkFrame(
            for: drawing,
            decision: .keepWriting(.unsupported, phrase),
            canvasFrame: CGRect(x: 30, y: 40, width: 140, height: 90),
            padding: 4
        )

        XCTAssertNil(feedbackFrame)
    }

    func testRhythmUnreadInkFeedbackTargetsUnreadV4SymbolFrameWhenMeasureIsComplete() {
        let drawing = PKDrawing(strokes: [snapshotStroke(creationDate: Date(timeIntervalSince1970: 10))])
        let phrase = RhythmPhraseHypothesis(
            source: .gridFirst,
            symbols: [
                RhythmSymbolHypothesis(
                    coveredStrokeIndices: [0],
                    bounds: CGRect(x: 12, y: 48, width: 16, height: 22),
                    candidateValues: [.quarter],
                    selectedValue: .quarter
                ),
                RhythmSymbolHypothesis(
                    coveredStrokeIndices: [1],
                    bounds: CGRect(x: 46, y: 48, width: 16, height: 22),
                    candidateValues: [.quarter],
                    selectedValue: .quarter
                ),
                RhythmSymbolHypothesis(
                    coveredStrokeIndices: [2],
                    bounds: CGRect(x: 80, y: 48, width: 16, height: 22),
                    candidateValues: [.quarter],
                    selectedValue: .quarter
                ),
                RhythmSymbolHypothesis(
                    coveredStrokeIndices: [3],
                    bounds: CGRect(x: 114, y: 48, width: 16, height: 22),
                    candidateValues: [.quarter],
                    selectedValue: .quarter
                ),
                RhythmSymbolHypothesis(
                    coveredStrokeIndices: [4],
                    bounds: CGRect(x: 150, y: 18, width: 10, height: 30),
                    candidateValues: [],
                    selectedValue: nil
                )
            ],
            uncoveredStrokeIndices: [],
            naturalValues: [.quarter, .quarter, .quarter, .quarter],
            naturalUnits: 8,
            targetUnits: 8,
            passesCompendium: true
        )

        XCTAssertTrue(
            LeadSheetRhythmicNotationFeedbackPolicy.shouldHighlightUnreadInk(
                for: .keepWriting(.unsupported, phrase)
            )
        )
        let feedbackFrame = LeadSheetRhythmicNotationFeedbackPolicy.unreadInkFrame(
            for: drawing,
            decision: .keepWriting(.unsupported, phrase),
            canvasFrame: CGRect(x: 30, y: 40, width: 180, height: 90),
            padding: 4
        )

        XCTAssertNotNil(feedbackFrame)
        XCTAssertTrue(feedbackFrame?.contains(CGPoint(x: 184, y: 62)) ?? false)
        XCTAssertFalse(feedbackFrame?.contains(CGPoint(x: 45, y: 93)) ?? true)
    }

    private func completedRhythmPhrase(values: [RhythmValue]) -> RhythmPhraseHypothesis {
        RhythmPhraseHypothesis(
            source: .gridFirst,
            symbols: [],
            uncoveredStrokeIndices: [],
            naturalValues: values,
            naturalUnits: 8,
            targetUnits: 8,
            passesCompendium: true
        )
    }

    private func measureResizeSnapshot(
        _ measureID: UUID,
        x: CGFloat,
        width: CGFloat
    ) -> LeadSheetMeasureResizeMeasureSnapshot {
        LeadSheetMeasureResizeMeasureSnapshot(
            measureID: measureID,
            frame: CGRect(x: x, y: 120, width: width, height: 90)
        )
    }

    private func dirtyInkSessionState(
        _ roles: LeadSheetInkAuthoringSessionRole...
    ) -> LeadSheetInkAuthoringSessionState {
        var state = LeadSheetInkAuthoringSessionState()
        roles.forEach { state.markDirty($0) }
        return state
    }

    private func snapshotStroke(creationDate: Date) -> PKStroke {
        stroke(
            points: [
                CGPoint(x: 8, y: 52),
                CGPoint(x: 20, y: 28)
            ],
            creationDate: creationDate
        )
    }

    private func committedTerminalSpanFixture(
        pageSize: CGSize = CGSize(width: 900, height: 1400)
    ) throws -> (
        chart: Chart,
        layout: LeadSheetPageLayout,
        system: LeadSheetSystemLayout,
        measure: LeadSheetMeasureLayout,
        location: CGPoint
    ) {
        var chart = Chart.blank(title: "Committed Row End", measureCount: 6, layoutStyle: .simpleChordSheet)
        let measureIDs = chart.measures.map(\.id)
        XCTAssertTrue(chart.insertSimpleSystemBreak(before: measureIDs[4]))
        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: pageSize
        )
        let system = try XCTUnwrap(layout.systems.first)
        let measure = try XCTUnwrap(system.measures.last)
        let laneFrame = try XCTUnwrap(
            LeadSheetActiveInkScope.chordWritingSystemLaneFrame(
                for: system,
                paperFrame: layout.paperFrame
            )
        )
        let terminalFrame = try XCTUnwrap(
            LeadSheetSimpleChordTerminalBarlineGeometry.barlineFrame(
                for: system,
                paperFrame: layout.paperFrame,
                layoutStyle: chart.layoutStyle
            )
        )
        let location = CGPoint(
            x: (measure.frame.maxX + terminalFrame.midX) / 2,
            y: laneFrame.midY
        )

        XCTAssertFalse(measure.isOpen)
        XCTAssertFalse(
            LeadSheetSimpleChordTerminalBarlineGeometry.containsTerminalFiller(
                location,
                in: system,
                paperFrame: layout.paperFrame,
                layoutStyle: chart.layoutStyle
            )
        )

        return (chart, layout, system, measure, location)
    }

    private func chordStroke(
        in measure: LeadSheetMeasureLayout,
        fromX: CGFloat,
        toX: CGFloat,
        chordFrame: CGRect
    ) -> PKStroke {
        let start = CGPoint(
            x: fromX - chordFrame.minX,
            y: measure.chordWritingFrame.midY - chordFrame.minY
        )
        let end = CGPoint(
            x: toX - chordFrame.minX,
            y: measure.chordWritingFrame.midY + 8 - chordFrame.minY
        )
        return stroke(
            points: [start, end],
            creationDate: Date(timeIntervalSince1970: 30)
        )
    }

    private func assertPersistentInkColor(_ color: UIColor, file: StaticString = #filePath, line: UInt = #line) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        XCTAssertTrue(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha), file: file, line: line)
        XCTAssertEqual(red, 0.06, accuracy: 0.015, file: file, line: line)
        XCTAssertEqual(green, 0.06, accuracy: 0.015, file: file, line: line)
        XCTAssertEqual(blue, 0.06, accuracy: 0.015, file: file, line: line)
        XCTAssertGreaterThanOrEqual(alpha, 0.98, file: file, line: line)
    }

    private func medianVisiblePixelLuminance(in cgImage: CGImage?) -> Double? {
        guard let cgImage else {
            return nil
        }

        let width = max(1, cgImage.width)
        let height = max(1, cgImage.height)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let didDraw = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let baseAddress = buffer.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else {
                return false
            }

            context.clear(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard didDraw else {
            return nil
        }

        let luminances = stride(from: 0, to: pixels.count, by: 4).compactMap { index -> Double? in
            let alpha = Double(pixels[index + 3]) / 255.0
            guard alpha > 0.05 else {
                return nil
            }

            let red = min(1, Double(pixels[index]) / 255.0 / alpha)
            let green = min(1, Double(pixels[index + 1]) / 255.0 / alpha)
            let blue = min(1, Double(pixels[index + 2]) / 255.0 / alpha)
            return 0.2126 * red + 0.7152 * green + 0.0722 * blue
        }.sorted()

        guard !luminances.isEmpty else {
            return nil
        }

        return luminances[luminances.count / 2]
    }

    private func visiblePixelCoverage(in cgImage: CGImage?) -> Double? {
        guard let cgImage else {
            return nil
        }

        let width = max(1, cgImage.width)
        let height = max(1, cgImage.height)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let didDraw = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let baseAddress = buffer.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else {
                return false
            }

            context.clear(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard didDraw else {
            return nil
        }

        let visiblePixelCount = stride(from: 0, to: pixels.count, by: 4).filter { index in
            Double(pixels[index + 3]) / 255.0 > 0.05
        }.count
        return Double(visiblePixelCount) / Double(width * height)
    }

    private func darkPixelCoverage(in cgImage: CGImage?) -> Double? {
        guard let cgImage else {
            return nil
        }

        let width = max(1, cgImage.width)
        let height = max(1, cgImage.height)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let didDraw = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let baseAddress = buffer.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else {
                return false
            }

            context.clear(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard didDraw else {
            return nil
        }

        let darkPixelCount = stride(from: 0, to: pixels.count, by: 4).filter { index in
            let alpha = Double(pixels[index + 3]) / 255.0
            guard alpha > 0.05 else {
                return false
            }

            let red = min(1, Double(pixels[index]) / 255.0 / alpha)
            let green = min(1, Double(pixels[index + 1]) / 255.0 / alpha)
            let blue = min(1, Double(pixels[index + 2]) / 255.0 / alpha)
            let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
            return luminance < 0.25
        }.count
        return Double(darkPixelCount) / Double(width * height)
    }

    private func strokeImage(color: UIColor, size: CGSize, scale: CGFloat) -> UIImage {
        let rendererFormat = UIGraphicsImageRendererFormat()
        rendererFormat.scale = scale
        rendererFormat.opaque = false
        return UIGraphicsImageRenderer(size: size, format: rendererFormat).image { _ in
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 6, y: size.height - 8))
            path.addLine(to: CGPoint(x: size.width / 2, y: 6))
            path.addLine(to: CGPoint(x: size.width - 6, y: size.height - 10))
            path.lineWidth = 5
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            color.setStroke()
            path.stroke()
        }
    }

    private func simpleChordFreeWriteRotationReproChart() throws -> Chart {
        var chart = Chart.blank(title: "Free Write Rotation", measureCount: 3, layoutStyle: .simpleChordSheet)
        XCTAssertGreaterThanOrEqual(chart.systems.count, 1)
        XCTAssertGreaterThanOrEqual(chart.systems[0].measures.count, 2)
        let measureID = chart.systems[0].measures[1].id
        chart.systems[0].measures[1].chordEvents = [
            chordEvent(
                id: UUID(),
                symbol: ChordSymbol(
                    root: .a,
                    accidental: .natural,
                    quality: "",
                    extensions: ["7"],
                    alterations: [],
                    slashBass: nil
                ),
                rawInput: "A7",
                beat: 1,
                subdivision: 0,
                subdivisionsPerBeat: 1
            ),
            chordEvent(
                id: UUID(),
                symbol: ChordSymbol(
                    root: .d,
                    accidental: .natural,
                    quality: "-",
                    extensions: ["11"],
                    alterations: [],
                    slashBass: nil
                ),
                rawInput: "D-11",
                beat: 2,
                subdivision: 1,
                subdivisionsPerBeat: 2
            )
        ]
        XCTAssertEqual(chart.systems[0].measures[1].id, measureID)
        return chart
    }

    private func chordEvent(
        id: UUID,
        symbol: ChordSymbol,
        rawInput: String,
        beat: Int,
        subdivision: Int,
        subdivisionsPerBeat: Int
    ) -> ChordEvent {
        ChordEvent(
            id: id,
            symbol: symbol,
            spellingIntent: .explicit,
            spellingOverrideSource: .userSelection,
            startPosition: BeatPosition(
                beat: beat,
                subdivision: subdivision,
                subdivisionsPerBeat: subdivisionsPerBeat
            ),
            duration: .quarter,
            rhythmPlacement: .inline,
            tieOut: false,
            hitStyle: .none,
            rawInput: rawInput,
            sourceCandidateSignature: [rawInput]
        )
    }

    private func relativeFrame(_ frame: CGRect, to parentFrame: CGRect) -> CGRect {
        frame.offsetBy(dx: -parentFrame.minX, dy: -parentFrame.minY)
    }

    private func deviceCThenDetachedDPointSets(offsetX: CGFloat, offsetY: CGFloat) -> [[CGPoint]] {
        [
            [
                CGPoint(x: offsetX + 210.7413, y: offsetY + 54.4026),
                CGPoint(x: offsetX + 208.1048, y: offsetY + 54.9308),
                CGPoint(x: offsetX + 205.8639, y: offsetY + 57.1093),
                CGPoint(x: offsetX + 200.6568, y: offsetY + 63.1830),
                CGPoint(x: offsetX + 195.5157, y: offsetY + 71.2371),
                CGPoint(x: offsetX + 193.9339, y: offsetY + 77.4428),
                CGPoint(x: offsetX + 194.1316, y: offsetY + 80.3476),
                CGPoint(x: offsetX + 208.1707, y: offsetY + 81.7339),
                CGPoint(x: offsetX + 216.4097, y: offsetY + 79.2253),
                CGPoint(x: offsetX + 218.9802, y: offsetY + 78.3670)
            ],
            [
                CGPoint(x: offsetX + 281.7938, y: offsetY + 60.9384),
                CGPoint(x: offsetX + 281.2665, y: offsetY + 73.7458),
                CGPoint(x: offsetX + 281.2665, y: offsetY + 76.2545)
            ],
            [
                CGPoint(x: offsetX + 276.4550, y: offsetY + 64.1732),
                CGPoint(x: offsetX + 277.9050, y: offsetY + 56.7132),
                CGPoint(x: offsetX + 282.8484, y: offsetY + 54.6007),
                CGPoint(x: offsetX + 296.1624, y: offsetY + 55.9210),
                CGPoint(x: offsetX + 303.6764, y: offsetY + 61.1364),
                CGPoint(x: offsetX + 307.7629, y: offsetY + 73.4817),
                CGPoint(x: offsetX + 303.0832, y: offsetY + 79.0272),
                CGPoint(x: offsetX + 288.2531, y: offsetY + 85.3649),
                CGPoint(x: offsetX + 281.0028, y: offsetY + 84.7047)
            ]
        ]
    }

    private func repeatDeviceCThenDetachedDPointSets(offsetX: CGFloat, offsetY: CGFloat) -> [[CGPoint]] {
        [
            [
                CGPoint(x: offsetX + 188.1337, y: offsetY + 54.5346),
                CGPoint(x: offsetX + 188.1337, y: offsetY + 52.6201),
                CGPoint(x: offsetX + 186.42, y: offsetY + 52.6862),
                CGPoint(x: offsetX + 183.8494, y: offsetY + 54.9308),
                CGPoint(x: offsetX + 182.6631, y: offsetY + 56.0531),
                CGPoint(x: offsetX + 181.4107, y: offsetY + 57.3074),
                CGPoint(x: offsetX + 180.0925, y: offsetY + 58.7598),
                CGPoint(x: offsetX + 178.6425, y: offsetY + 60.2782),
                CGPoint(x: offsetX + 177.1924, y: offsetY + 61.9286),
                CGPoint(x: offsetX + 175.7423, y: offsetY + 63.6451),
                CGPoint(x: offsetX + 174.0946, y: offsetY + 65.6256),
                CGPoint(x: offsetX + 172.7763, y: offsetY + 67.4081),
                CGPoint(x: offsetX + 171.524, y: offsetY + 69.3226),
                CGPoint(x: offsetX + 170.4035, y: offsetY + 71.3691),
                CGPoint(x: offsetX + 169.4808, y: offsetY + 73.3497),
                CGPoint(x: offsetX + 168.7557, y: offsetY + 75.3302),
                CGPoint(x: offsetX + 168.1625, y: offsetY + 77.4428),
                CGPoint(x: offsetX + 168.0966, y: offsetY + 79.0272),
                CGPoint(x: offsetX + 168.1625, y: offsetY + 81.7339),
                CGPoint(x: offsetX + 169.6126, y: offsetY + 83.8465),
                CGPoint(x: offsetX + 171.6558, y: offsetY + 85.2329),
                CGPoint(x: offsetX + 174.1605, y: offsetY + 85.827),
                CGPoint(x: offsetX + 177.1265, y: offsetY + 86.0911),
                CGPoint(x: offsetX + 178.9061, y: offsetY + 86.1571),
                CGPoint(x: offsetX + 181.8721, y: offsetY + 86.1571),
                CGPoint(x: offsetX + 183.454, y: offsetY + 86.1571),
                CGPoint(x: offsetX + 184.9699, y: offsetY + 86.1571),
                CGPoint(x: offsetX + 186.4859, y: offsetY + 86.0251)
            ],
            [
                CGPoint(x: offsetX + 244.4879, y: offsetY + 59.2219),
                CGPoint(x: offsetX + 243.7629, y: offsetY + 63.7111),
                CGPoint(x: offsetX + 243.7629, y: offsetY + 70.4449),
                CGPoint(x: offsetX + 243.7629, y: offsetY + 78.0369),
                CGPoint(x: offsetX + 243.4993, y: offsetY + 86.7513)
            ],
            [
                CGPoint(x: offsetX + 233.283, y: offsetY + 57.0433),
                CGPoint(x: offsetX + 232.8216, y: offsetY + 54.9308),
                CGPoint(x: offsetX + 236.974, y: offsetY + 53.7424),
                CGPoint(x: offsetX + 245.7402, y: offsetY + 53.0823),
                CGPoint(x: offsetX + 257.5384, y: offsetY + 53.5444),
                CGPoint(x: offsetX + 266.766, y: offsetY + 57.5715),
                CGPoint(x: offsetX + 271.3798, y: offsetY + 63.249),
                CGPoint(x: offsetX + 271.2479, y: offsetY + 70.907),
                CGPoint(x: offsetX + 267.0296, y: offsetY + 77.4428),
                CGPoint(x: offsetX + 258.8566, y: offsetY + 83.6484),
                CGPoint(x: offsetX + 248.7722, y: offsetY + 87.2134),
                CGPoint(x: offsetX + 244.9493, y: offsetY + 87.3454)
            ]
        ]
    }

    private func latestRhythmLooseCThenFragmentedDPointSets(offsetX: CGFloat, offsetY: CGFloat) -> [[CGPoint]] {
        [
            [
                CGPoint(x: offsetX + 67.8516, y: offsetY + 23.5995),
                CGPoint(x: offsetX + 65.9402, y: offsetY + 24.3257),
                CGPoint(x: offsetX + 64.0287, y: offsetY + 26.3062),
                CGPoint(x: offsetX + 62.3150, y: offsetY + 28.2867),
                CGPoint(x: offsetX + 60.6013, y: offsetY + 30.5313),
                CGPoint(x: offsetX + 59.7445, y: offsetY + 31.8517),
                CGPoint(x: offsetX + 58.9536, y: offsetY + 33.3041),
                CGPoint(x: offsetX + 58.2285, y: offsetY + 34.6905),
                CGPoint(x: offsetX + 57.5035, y: offsetY + 36.2749),
                CGPoint(x: offsetX + 56.7785, y: offsetY + 38.9816),
                CGPoint(x: offsetX + 56.7126, y: offsetY + 41.3582),
                CGPoint(x: offsetX + 57.0421, y: offsetY + 43.4048),
                CGPoint(x: offsetX + 58.4263, y: offsetY + 44.7251),
                CGPoint(x: offsetX + 60.3377, y: offsetY + 45.5833),
                CGPoint(x: offsetX + 62.6446, y: offsetY + 46.1775),
                CGPoint(x: offsetX + 64.9515, y: offsetY + 46.3755),
                CGPoint(x: offsetX + 68.3789, y: offsetY + 46.3755),
                CGPoint(x: offsetX + 70.4880, y: offsetY + 45.9794)
            ],
            [
                CGPoint(x: offsetX + 113.9896, y: offsetY + 26.2402),
                CGPoint(x: offsetX + 114.4509, y: offsetY + 28.1547),
                CGPoint(x: offsetX + 114.4509, y: offsetY + 30.2012),
                CGPoint(x: offsetX + 114.4509, y: offsetY + 32.6439),
                CGPoint(x: offsetX + 114.2532, y: offsetY + 35.4166),
                CGPoint(x: offsetX + 114.1214, y: offsetY + 38.2554),
                CGPoint(x: offsetX + 114.0555, y: offsetY + 42.4145),
                CGPoint(x: offsetX + 114.0555, y: offsetY + 45.1872),
                CGPoint(x: offsetX + 114.0555, y: offsetY + 45.8474)
            ],
            [
                CGPoint(x: offsetX + 113.0668, y: offsetY + 25.9101),
                CGPoint(x: offsetX + 113.9896, y: offsetY + 24.5237),
                CGPoint(x: offsetX + 115.9010, y: offsetY + 23.7975),
                CGPoint(x: offsetX + 117.9442, y: offsetY + 23.1374),
                CGPoint(x: offsetX + 120.7125, y: offsetY + 22.3451),
                CGPoint(x: offsetX + 122.1626, y: offsetY + 21.8830),
                CGPoint(x: offsetX + 123.6126, y: offsetY + 21.4209),
                CGPoint(x: offsetX + 125.1286, y: offsetY + 20.9588),
                CGPoint(x: offsetX + 126.5786, y: offsetY + 20.4967),
                CGPoint(x: offsetX + 128.0287, y: offsetY + 19.9685)
            ],
            [
                CGPoint(x: offsetX + 115.2419, y: offsetY + 36.9350),
                CGPoint(x: offsetX + 116.9556, y: offsetY + 36.9350),
                CGPoint(x: offsetX + 119.3943, y: offsetY + 36.9350),
                CGPoint(x: offsetX + 121.4375, y: offsetY + 36.8690),
                CGPoint(x: offsetX + 123.6785, y: offsetY + 36.6050),
                CGPoint(x: offsetX + 126.2491, y: offsetY + 36.4069),
                CGPoint(x: offsetX + 128.8855, y: offsetY + 36.1428)
            ]
        ]
    }

    private func latestRhythmCloseCThenFragmentedFPointSets(offsetX: CGFloat, offsetY: CGFloat) -> [[CGPoint]] {
        [
            [
                CGPoint(x: offsetX + 65.4788, y: offsetY + 16.6676),
                CGPoint(x: offsetX + 64.5560, y: offsetY + 17.9220),
                CGPoint(x: offsetX + 62.7105, y: offsetY + 19.5724),
                CGPoint(x: offsetX + 60.9968, y: offsetY + 21.4869),
                CGPoint(x: offsetX + 59.9422, y: offsetY + 22.8073),
                CGPoint(x: offsetX + 58.8876, y: offsetY + 24.3917),
                CGPoint(x: offsetX + 57.7012, y: offsetY + 26.2402),
                CGPoint(x: offsetX + 56.5807, y: offsetY + 28.2867),
                CGPoint(x: offsetX + 55.4602, y: offsetY + 30.5313),
                CGPoint(x: offsetX + 54.3398, y: offsetY + 33.1060),
                CGPoint(x: offsetX + 53.5488, y: offsetY + 35.2846),
                CGPoint(x: offsetX + 52.9556, y: offsetY + 37.3972),
                CGPoint(x: offsetX + 52.6261, y: offsetY + 39.2456),
                CGPoint(x: offsetX + 52.6261, y: offsetY + 43.0747),
                CGPoint(x: offsetX + 53.9443, y: offsetY + 43.9329),
                CGPoint(x: offsetX + 56.0534, y: offsetY + 44.1310),
                CGPoint(x: offsetX + 58.9536, y: offsetY + 44.1310),
                CGPoint(x: offsetX + 60.4695, y: offsetY + 43.8669),
                CGPoint(x: offsetX + 62.0514, y: offsetY + 43.4048),
                CGPoint(x: offsetX + 63.6992, y: offsetY + 42.8766),
                CGPoint(x: offsetX + 65.2810, y: offsetY + 42.2825),
                CGPoint(x: offsetX + 66.9288, y: offsetY + 41.6223),
                CGPoint(x: offsetX + 68.6425, y: offsetY + 40.9621),
                CGPoint(x: offsetX + 70.0267, y: offsetY + 40.3679),
                CGPoint(x: offsetX + 72.3995, y: offsetY + 39.4437),
                CGPoint(x: offsetX + 74.1132, y: offsetY + 38.6515)
            ],
            [
                CGPoint(x: offsetX + 107.5302, y: offsetY + 23.7975),
                CGPoint(x: offsetX + 106.8711, y: offsetY + 20.7607),
                CGPoint(x: offsetX + 106.8052, y: offsetY + 22.5432),
                CGPoint(x: offsetX + 107.0689, y: offsetY + 24.5898),
                CGPoint(x: offsetX + 107.5302, y: offsetY + 27.0984),
                CGPoint(x: offsetX + 107.9916, y: offsetY + 29.8712),
                CGPoint(x: offsetX + 108.1894, y: offsetY + 31.5216),
                CGPoint(x: offsetX + 108.5848, y: offsetY + 34.1623),
                CGPoint(x: offsetX + 108.9803, y: offsetY + 36.6050),
                CGPoint(x: offsetX + 109.5076, y: offsetY + 39.5097),
                CGPoint(x: offsetX + 109.9031, y: offsetY + 41.2262)
            ],
            [
                CGPoint(x: offsetX + 109.2439, y: offsetY + 20.9588),
                CGPoint(x: offsetX + 108.7826, y: offsetY + 19.5064),
                CGPoint(x: offsetX + 111.6827, y: offsetY + 18.4501),
                CGPoint(x: offsetX + 113.7918, y: offsetY + 17.7899),
                CGPoint(x: offsetX + 117.2192, y: offsetY + 16.9317),
                CGPoint(x: offsetX + 119.6579, y: offsetY + 16.4696),
                CGPoint(x: offsetX + 121.6353, y: offsetY + 16.2715),
                CGPoint(x: offsetX + 123.2172, y: offsetY + 16.2715),
                CGPoint(x: offsetX + 124.4695, y: offsetY + 16.2055)
            ],
            [
                CGPoint(x: offsetX + 111.0235, y: offsetY + 30.4653),
                CGPoint(x: offsetX + 112.9350, y: offsetY + 30.4653),
                CGPoint(x: offsetX + 116.1646, y: offsetY + 29.2770),
                CGPoint(x: offsetX + 118.1420, y: offsetY + 28.6168),
                CGPoint(x: offsetX + 122.4921, y: offsetY + 27.2965)
            ]
        ]
    }

    private func repeatDeviceABCDPointSets(offsetX: CGFloat, offsetY: CGFloat) -> [[CGPoint]] {
        let aStrokes: [[CGPoint]] = [
            [
                CGPoint(x: offsetX + 34.4283, y: offsetY + 58.4297),
                CGPoint(x: offsetX + 31.5941, y: offsetY + 64.6353),
                CGPoint(x: offsetX + 28.5622, y: offsetY + 72.4915),
                CGPoint(x: offsetX + 25.1348, y: offsetY + 80.0175),
                CGPoint(x: offsetX + 21.9052, y: offsetY + 86.8173)
            ],
            [
                CGPoint(x: offsetX + 37.2625, y: offsetY + 53.4784),
                CGPoint(x: offsetX + 39.1739, y: offsetY + 60.2122),
                CGPoint(x: offsetX + 42.4036, y: offsetY + 68.2003),
                CGPoint(x: offsetX + 45.8969, y: offsetY + 77.1787),
                CGPoint(x: offsetX + 49.1925, y: offsetY + 86.2231),
                CGPoint(x: offsetX + 52.3562, y: offsetY + 98.7665)
            ],
            [
                CGPoint(x: offsetX + 29.0236, y: offsetY + 79.0932),
                CGPoint(x: offsetX + 35.2852, y: offsetY + 76.1224),
                CGPoint(x: offsetX + 42.9968, y: offsetY + 74.7360),
                CGPoint(x: offsetX + 48.6652, y: offsetY + 74.2079)
            ]
        ]
        let bStrokes: [[CGPoint]] = [
            [
                CGPoint(x: offsetX + 96.3850, y: offsetY + 69.5867),
                CGPoint(x: offsetX + 96.4509, y: offsetY + 75.0001),
                CGPoint(x: offsetX + 96.4509, y: offsetY + 82.0640),
                CGPoint(x: offsetX + 96.4509, y: offsetY + 88.9959),
                CGPoint(x: offsetX + 96.4509, y: offsetY + 93.7491)
            ],
            [
                CGPoint(x: offsetX + 90.3871, y: offsetY + 66.1538),
                CGPoint(x: offsetX + 94.6054, y: offsetY + 61.4005),
                CGPoint(x: offsetX + 108.1832, y: offsetY + 58.2317),
                CGPoint(x: offsetX + 118.3335, y: offsetY + 57.6375),
                CGPoint(x: offsetX + 112.1378, y: offsetY + 62.8529),
                CGPoint(x: offsetX + 99.0215, y: offsetY + 72.2274),
                CGPoint(x: offsetX + 108.5786, y: offsetY + 75.4622),
                CGPoint(x: offsetX + 119.7177, y: offsetY + 79.0272),
                CGPoint(x: offsetX + 122.2223, y: offsetY + 85.2989),
                CGPoint(x: offsetX + 114.4448, y: offsetY + 93.7491),
                CGPoint(x: offsetX + 104.0966, y: offsetY + 99.3606),
                CGPoint(x: offsetX + 94.9350, y: offsetY + 100.5490)
            ]
        ]

        return aStrokes + bStrokes + repeatDeviceCThenDetachedDPointSets(offsetX: offsetX, offsetY: offsetY)
    }

    private func transformedTemplatePointSets(
        _ text: String,
        offsetX: CGFloat,
        offsetY: CGFloat,
        scale: CGFloat
    ) throws -> [[CGPoint]] {
        let template = try XCTUnwrap(
            ChordGlyphTemplateLibrary.initialTemplates.first { $0.text == text },
            "Missing template \(text)"
        )

        return template.strokes.map { stroke in
            stroke.points.map { point in
                CGPoint(
                    x: offsetX + CGFloat(point.x) * scale,
                    y: offsetY + CGFloat(point.y) * scale
                )
            }
        }
    }

    private func stroke(
        points: [CGPoint],
        creationDate: Date,
        color: UIColor = .black,
        size: CGSize = CGSize(width: 2, height: 2)
    ) -> PKStroke {
        let controlPoints = points.enumerated().map { index, point in
            PKStrokePoint(
                location: point,
                timeOffset: TimeInterval(index) * 0.05,
                size: size,
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        }
        return PKStroke(
            ink: PKInk(.pen, color: color),
            path: PKStrokePath(controlPoints: controlPoints, creationDate: creationDate)
        )
    }
}
#endif
