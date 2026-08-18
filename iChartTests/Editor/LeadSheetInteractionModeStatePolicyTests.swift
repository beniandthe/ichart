#if canImport(UIKit)
import PencilKit
import UIKit
import XCTest
@testable import iChart

final class LeadSheetInteractionModeStatePolicyTests: XCTestCase {
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

    func testChordOCRImageKeepsPersistentInkDarkWhenCurrentTraitIsDark() throws {
        let drawing = PKDrawing(strokes: [
            stroke(
                points: [
                    CGPoint(x: 8, y: 34),
                    CGPoint(x: 22, y: 8),
                    CGPoint(x: 40, y: 34)
                ],
                creationDate: Date(timeIntervalSince1970: 80),
                color: LeadSheetPersistentInkColorPolicy.inkColor,
                size: CGSize(width: 8, height: 8)
            )
        ])
        var ocrImage: CGImage?

        UITraitCollection(userInterfaceStyle: .dark).performAsCurrent {
            ocrImage = LeadSheetChordInkImageRenderer.ocrImage(for: drawing)
        }

        let darkCoverage = try XCTUnwrap(darkPixelCoverage(in: ocrImage))
        XCTAssertGreaterThan(darkCoverage, 0)
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

    func testChordEntryKeepsSimulatorPointerInputForAutomation() {
        let policy = LeadSheetInteractionModeStatePolicy.resolve(for: .chordEntry)

        #if targetEnvironment(simulator)
        XCTAssertEqual(policy.drawingPolicy, .anyInput)
        #else
        XCTAssertEqual(policy.drawingPolicy, .pencilOnly)
        #endif
    }

    func testChordEntryKeepsInkCanvasAndEnablesRenderedChordObjects() {
        let policy = LeadSheetInteractionModeStatePolicy.resolve(for: .chordEntry)

        XCTAssertTrue(policy.pageInkCanvasInteractionEnabled)
        XCTAssertTrue(policy.chordEditTapEnabled)
        XCTAssertTrue(policy.chordMovePanEnabled)
        XCTAssertFalse(policy.chordEditOverlayHidden)
        XCTAssertTrue(EditorCanvasMode.chordEntry.allowsChordObjectEditing)
        XCTAssertTrue(EditorCanvasMode.chordEntry.requiresChordSelectionBeforeObjectActions)
        XCTAssertTrue(EditorCanvasMode.chordEntry.drawsAllChordObjectEditBoxes)
        XCTAssertFalse(EditorCanvasMode.chordEntry.drawsAllChordObjectEditControls)
    }

    func testTextEditModeKeepsCueTextEditableWithoutMeasureSelection() {
        let policy = LeadSheetInteractionModeStatePolicy.resolve(for: .textEdit)

        XCTAssertFalse(policy.selectionTapEnabled)
        XCTAssertTrue(policy.chordEditTapEnabled)
        XCTAssertTrue(policy.chordMovePanEnabled)
        XCTAssertFalse(policy.chordEditOverlayHidden)
        XCTAssertFalse(EditorCanvasMode.textEdit.allowsMeasureSelection)
        XCTAssertTrue(EditorCanvasMode.textEdit.allowsCueTextEditing)
        XCTAssertFalse(EditorCanvasMode.textEdit.allowsChordObjectEditing)
        XCTAssertEqual(EditorCanvasMode.textEdit.activeToolTitle, "Text")
    }

    func testPencilObjectMoveStartsOnlyOnMovableTargets() {
        XCTAssertFalse(
            LeadSheetObjectMoveTouchPolicy.allowsMovePan(
                touchType: .pencil,
                startsOnMoveTarget: false
            )
        )
        XCTAssertTrue(
            LeadSheetObjectMoveTouchPolicy.allowsMovePan(
                touchType: .pencil,
                startsOnMoveTarget: true
            )
        )
        XCTAssertTrue(
            LeadSheetObjectMoveTouchPolicy.allowsMovePan(
                touchType: .direct,
                startsOnMoveTarget: false
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
        let target = try XCTUnwrap(
            LeadSheetChordMoveDragPolicy.target(
                at: movedLocation,
                for: drag
            )
        )
        let expectedFrozenFraction = (movedLocation.x - sourceMeasure.chordBandFrame.minX)
            / max(1, sourceMeasure.chordBandFrame.width)

        XCTAssertEqual(previewFrame.minX, sourceChordLayout.frame.minX + sourceMeasure.chordBandFrame.width * 0.18, accuracy: 0.001)
        XCTAssertEqual(previewFrame.minY, sourceChordLayout.frame.minY, accuracy: 0.001)
        XCTAssertEqual(target.measureID, measureID)
        XCTAssertEqual(target.fraction, Double(min(max(expectedFrozenFraction, 0), 0.9999)), accuracy: 0.0001)
    }

    func testBrowseModeKeepsCueTextEditable() {
        XCTAssertTrue(EditorCanvasMode.browse.allowsCueTextEditing)
    }

    func testChordTargetingAcceptsInkAcrossFullRhythmSectionChordLane() throws {
        let chart = Chart.blank(title: "Top Lane Chord", measureCount: 4, layoutStyle: .rhythmSectionSheet)
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1200)
        )
        let measure = try XCTUnwrap(layout.systems.first?.measures.first)
        let chordFrame = LeadSheetActiveInkScope.chordWritingFrame(for: layout)
        let inkStartInView = CGPoint(
            x: measure.chordWritingFrame.midX - 8,
            y: measure.chordWritingFrame.maxY - 8
        )
        let inkEndInView = CGPoint(
            x: measure.chordWritingFrame.midX + 8,
            y: measure.chordWritingFrame.maxY - 4
        )
        let localStart = CGPoint(
            x: inkStartInView.x - chordFrame.minX,
            y: inkStartInView.y - chordFrame.minY
        )
        let localEnd = CGPoint(
            x: inkEndInView.x - chordFrame.minX,
            y: inkEndInView.y - chordFrame.minY
        )

        XCTAssertTrue(measure.chordWritingFrame.contains(inkStartInView))
        XCTAssertFalse(measure.chordBandFrame.contains(inkStartInView))

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
        XCTAssertTrue(frame.contains(firstMeasure.chordWritingFrame))
        XCTAssertTrue(inputFrames.contains { $0.contains(firstMeasure.chordWritingFrame) })
        XCTAssertTrue(inputFrames.contains { $0.maxX > firstMeasure.chordWritingFrame.maxX })
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

    func testBrowseSelectModeEditsRenderedChordsWithoutInkCanvasOrIdleBoxes() {
        let policy = LeadSheetInteractionModeStatePolicy.resolve(for: .browse)

        XCTAssertFalse(policy.pageInkCanvasInteractionEnabled)
        XCTAssertTrue(policy.chordEditTapEnabled)
        XCTAssertTrue(policy.chordMovePanEnabled)
        XCTAssertFalse(policy.chordEditOverlayHidden)
        XCTAssertTrue(EditorCanvasMode.browse.allowsChordObjectEditing)
        XCTAssertTrue(EditorCanvasMode.browse.requiresChordSelectionBeforeObjectActions)
        XCTAssertFalse(EditorCanvasMode.browse.drawsAllChordObjectEditBoxes)
        XCTAssertFalse(EditorCanvasMode.browse.drawsAllChordObjectEditControls)
    }

    func testBrowseSelectModeRoutesHeaderTapsToHeaderAuthoring() {
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
        XCTAssertEqual(EditorCanvasMode.browse.activeToolTitle, "Select")
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

    func testChordMoveDoesNotRecognizeSimultaneouslyWithParentScroll() {
        XCTAssertFalse(
            LeadSheetChordMoveScrollLockPolicy.allowsSimultaneousRecognition(
                involvesChordMove: true,
                involvesParentScroll: true
            )
        )
        XCTAssertTrue(
            LeadSheetChordMoveScrollLockPolicy.allowsSimultaneousRecognition(
                involvesChordMove: true,
                involvesParentScroll: false
            )
        )
        XCTAssertTrue(
            LeadSheetChordMoveScrollLockPolicy.allowsSimultaneousRecognition(
                involvesChordMove: false,
                involvesParentScroll: true
            )
        )
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

        XCTAssertEqual(affordance.selectedMeasureID, measureIDs[1])
        XCTAssertEqual(affordance.groupedMeasureIDs, Array(measureIDs[1..<4]))
        XCTAssertEqual(affordance.groupFrame.minX, selectedMeasure.frame.minX, accuracy: 0.001)
        XCTAssertEqual(affordance.groupFrame.maxX, lastGroupedMeasure.frame.maxX, accuracy: 0.001)
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
