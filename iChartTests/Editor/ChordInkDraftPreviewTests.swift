#if canImport(UIKit)
import CoreGraphics
import PencilKit
import XCTest
@testable import iChart

final class ChordInkDraftPreviewTests: XCTestCase {
    func testDraftPreviewRecognitionLoadPolicyRejectsOversizedSingleDraftTarget() {
        XCTAssertTrue(
            ChordInkDraftPreviewRecognitionLoadPolicy.shouldRecognizeSingleTarget(
                strokeCount: ChordInkDraftPreviewPolicy.maximumSingleTargetStrokeCount,
                flow: .draftPreview
            )
        )
        XCTAssertFalse(
            ChordInkDraftPreviewRecognitionLoadPolicy.shouldRecognizeSingleTarget(
                strokeCount: ChordInkDraftPreviewPolicy.maximumSingleTargetStrokeCount + 1,
                flow: .draftPreview
            )
        )
        XCTAssertTrue(
            ChordInkDraftPreviewRecognitionLoadPolicy.shouldRecognizeSingleTarget(
                strokeCount: ChordInkDraftPreviewPolicy.maximumSingleTargetStrokeCount + 1,
                flow: .tapToConfirm
            )
        )
    }

    func testDraftPreviewRecognitionLoadPolicyRejectsWeakGeometryDraftTargets() {
        let chordLikeStrokes = [
            InkStroke(
                points: [
                    InkPoint(x: 0, y: 0, timeOffset: nil),
                    InkPoint(x: 26, y: 14, timeOffset: nil),
                    InkPoint(x: 4, y: 44, timeOffset: nil)
                ]
            )
        ]
        let verticalShardStrokes = [
            InkStroke(
                points: [
                    InkPoint(x: 4, y: 0, timeOffset: nil),
                    InkPoint(x: 5, y: 46, timeOffset: nil)
                ]
            )
        ]
        let dashOnlyStrokes = [
            InkStroke(
                points: [
                    InkPoint(x: 0, y: 3, timeOffset: nil),
                    InkPoint(x: 24, y: 4, timeOffset: nil)
                ]
            )
        ]

        XCTAssertTrue(
            ChordInkDraftPreviewRecognitionLoadPolicy.shouldRecognizeSingleTarget(
                strokes: chordLikeStrokes,
                flow: .draftPreview
            )
        )
        XCTAssertFalse(
            ChordInkDraftPreviewRecognitionLoadPolicy.shouldRecognizeSingleTarget(
                strokes: verticalShardStrokes,
                flow: .draftPreview
            )
        )
        XCTAssertFalse(
            ChordInkDraftPreviewRecognitionLoadPolicy.shouldRecognizeSingleTarget(
                strokes: dashOnlyStrokes,
                flow: .draftPreview
            )
        )
        XCTAssertTrue(
            ChordInkDraftPreviewRecognitionLoadPolicy.shouldRecognizeSingleTarget(
                strokes: verticalShardStrokes,
                flow: .tapToConfirm
            )
        )
    }

    func testVisibleStrokePolicyIgnoresTinyRenderedStrokeArtifactsAndRemapsIndices() {
        let visibleChordStroke = Self.pkStroke(
            points: [
                CGPoint(x: 140, y: 42),
                CGPoint(x: 172, y: 65)
            ]
        )
        let context = ChordInkDraftVisibleDrawingContext(
            drawing: PKDrawing(strokes: [visibleChordStroke]),
            originalStrokeIndices: [1],
            invisibleStrokeIndices: [0]
        )

        XCTAssertFalse(
            ChordInkDraftVisibleStrokePolicy.isVisible(
                renderBounds: CGRect(x: 123, y: 35, width: 1, height: 2)
            )
        )
        XCTAssertTrue(
            ChordInkDraftVisibleStrokePolicy.isVisible(
                renderBounds: CGRect(x: 140, y: 42, width: 32, height: 23)
            )
        )
        XCTAssertTrue(
            ChordInkDraftVisibleStrokePolicy.isVisible(
                renderBounds: CGRect(x: 140, y: 42, width: 7, height: 1)
            )
        )

        XCTAssertEqual(context.visibleStrokeCount, 1)
        XCTAssertEqual(context.originalStrokeIndices, [1])
        XCTAssertEqual(context.invisibleStrokeIndices, [0])

        let visibleBarline = draftBarline(
            measureID: UUID(),
            measureIndex: 0,
            fraction: 0.42,
            sourceStrokeIndex: 0
        )
        let remappedRecognition = context.remappedBarlineRecognition(
            ChordDraftBarlineRecognition(
                barlines: [visibleBarline],
                strokeIndices: [0]
            )
        )

        XCTAssertEqual(remappedRecognition.strokeIndices, [1])
        XCTAssertEqual(remappedRecognition.barlines.first?.sourceStrokeIndex, 1)
    }

    func testDraftPreviewRecognitionLoadPolicyFiltersOversizedBatchTargets() {
        let normalTarget = batchTarget(strokeCount: ChordInkDraftPreviewPolicy.maximumBatchTargetStrokeCount)
        let oversizedTarget = batchTarget(strokeCount: ChordInkDraftPreviewPolicy.maximumBatchTargetStrokeCount + 1)
        let weakTarget = batchTarget(strokes: [
            InkStroke(
                points: [
                    InkPoint(x: 4, y: 0, timeOffset: nil),
                    InkPoint(x: 5, y: 46, timeOffset: nil)
                ]
            )
        ])

        let draftTargets = ChordInkDraftPreviewRecognitionLoadPolicy.boundedBatchTargets(
            [normalTarget, oversizedTarget, weakTarget],
            flow: .draftPreview
        )
        XCTAssertEqual(draftTargets.map(\.strokes.count), [normalTarget.strokes.count])

        let tapToConfirmTargets = ChordInkDraftPreviewRecognitionLoadPolicy.boundedBatchTargets(
            [normalTarget, oversizedTarget, weakTarget],
            flow: .tapToConfirm
        )
        XCTAssertEqual(tapToConfirmTargets.count, 3)
    }

    func testDraftPreviewImplicitBarlinesIncludeRenderedLaneEndBarlinesForContentLanes() throws {
        var chart = Chart.draft(title: "Terminal Preview", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(
            title: "Terminal Preview",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 1
        )
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        let pageSize = CGSize(width: 900, height: 1400)

        var state = ChordPreviewState()
        state.replaceDraftChords(with: [
            draftInput(
                measureID: measureID,
                measureIndex: 1,
                fraction: 0.18,
                bestCandidateText: "D7",
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 0, fraction: 0.18),
                layoutPageSize: pageSize
            ),
            draftInput(
                measureID: measureID,
                measureIndex: 1,
                fraction: 0.28,
                bestCandidateText: "C#-Δ7",
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 1, fraction: 0.28),
                layoutPageSize: pageSize
            )
        ])

        let terminalBarlines = ChordDraftPreviewImplicitBarlinePolicy.terminalBarlines(
            for: state,
            chart: chart
        )

        XCTAssertEqual(terminalBarlines.map(\.laneLocation.systemIndex), [0, 1])
        XCTAssertEqual(terminalBarlines.map(\.laneLocation.fraction), [0.9999, 0.9999])
        XCTAssertEqual(terminalBarlines.map(\.visualOrder), [0.9999, 1.9999])
    }

    func testDraftPreviewImplicitBarlinesDoNotDuplicateTerminalDraftBarline() throws {
        var chart = Chart.draft(title: "Terminal Draft", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(
            title: "Terminal Draft",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 1
        )
        let measureID = try XCTUnwrap(chart.measures.first?.id)
        let pageSize = CGSize(width: 900, height: 1400)

        var state = ChordPreviewState()
        state.replaceDraftChords(with: [
            draftInput(
                measureID: measureID,
                measureIndex: 1,
                fraction: 0.18,
                bestCandidateText: "D7",
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 0, fraction: 0.18),
                layoutPageSize: pageSize
            )
        ])
        state.replaceDraftBarlines(with: [
            draftBarline(
                measureID: measureID,
                measureIndex: 1,
                fraction: 0.98,
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 0, fraction: 0.98),
                layoutPageSize: pageSize
            )
        ])

        let terminalBarlines = ChordDraftPreviewImplicitBarlinePolicy.terminalBarlines(
            for: state,
            chart: chart
        )

        XCTAssertTrue(terminalBarlines.isEmpty)
    }

    func testDraftStateReplacesBatchAndPreservesEditedTextByAnchor() {
        let measureID = UUID()
        var state = ChordPreviewState()
        state.replaceDraftChords(with: [
            draftInput(measureID: measureID, measureIndex: 0, fraction: 0.24, bestCandidateText: "C")
        ])

        let draftID = state.draftChords[0].id
        state.draftChords[0].selectedText = "Cmaj7"
        state.replaceDraftChords(with: [
            draftInput(measureID: measureID, measureIndex: 0, fraction: 0.245, bestCandidateText: "C6")
        ])

        XCTAssertEqual(state.draftChords.count, 1)
        XCTAssertEqual(state.draftChords[0].id, draftID)
        XCTAssertEqual(state.draftChords[0].previewText, "Cmaj7")
    }

    func testDraftStateKeepsLaneSpecificDraftIdentityWhenFractionsOverlap() {
        let measureID = UUID()
        var state = ChordPreviewState()
        state.replaceDraftChords(with: [
            draftInput(
                measureID: measureID,
                measureIndex: 0,
                fraction: 0.09,
                bestCandidateText: "Eb△7",
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 0, fraction: 0.09)
            )
        ])

        let firstLaneDraftID = state.draftChords[0].id
        state.replaceDraftChords(with: [
            draftInput(
                measureID: measureID,
                measureIndex: 0,
                fraction: 0.09,
                bestCandidateText: "Eb△7",
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 0, fraction: 0.09)
            ),
            draftInput(
                measureID: measureID,
                measureIndex: 0,
                fraction: 0.09,
                bestCandidateText: "C",
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 1, fraction: 0.09)
            )
        ])

        XCTAssertEqual(state.draftChords.count, 2)
        XCTAssertEqual(state.draftChords[0].id, firstLaneDraftID)
        XCTAssertEqual(state.draftChords[0].previewText, "Eb△7")
        XCTAssertNotEqual(state.draftChords[1].id, firstLaneDraftID)
        XCTAssertEqual(state.draftChords[1].previewText, "C")
    }

    func testDraftStateReplacesBatchWhenExistingStateHasDuplicateAnchors() {
        let measureID = UUID()
        let input = draftInput(measureID: measureID, measureIndex: 0, fraction: 0.24, bestCandidateText: "C")
        var state = ChordPreviewState()
        state.draftChords = [
            ChordInkDraft(id: UUID(), input: input, selectedText: "Cmaj7"),
            ChordInkDraft(id: UUID(), input: input, selectedText: "C6")
        ]

        state.replaceDraftChords(with: [
            draftInput(measureID: measureID, measureIndex: 0, fraction: 0.245, bestCandidateText: "C7")
        ])

        XCTAssertEqual(state.draftChords.count, 1)
        XCTAssertEqual(state.draftChords[0].previewText, "Cmaj7")
    }

    func testDraftStatePreservesReadableDraftWhenDetachedInkAbsorbsAndChangesRead() {
        let measureID = UUID()
        let rootStroke = Self.pkStroke(points: [
            CGPoint(x: 10, y: 20),
            CGPoint(x: 34, y: 44),
            CGPoint(x: 12, y: 68)
        ])
        let detachedStem = Self.pkStroke(points: [
            CGPoint(x: 96, y: 20),
            CGPoint(x: 96, y: 68)
        ])
        let detachedBowl = Self.pkStroke(points: [
            CGPoint(x: 96, y: 22),
            CGPoint(x: 124, y: 42),
            CGPoint(x: 98, y: 68)
        ])
        let rootDrawingData = Self.drawingData(strokes: [rootStroke])
        let absorbedDrawingData = Self.drawingData(strokes: [rootStroke, detachedStem, detachedBowl])
        var state = ChordPreviewState()
        state.replaceDraftChords(with: [
            draftInput(
                measureID: measureID,
                measureIndex: 0,
                fraction: 0.24,
                bestCandidateText: "C",
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 0, fraction: 0.24),
                drawingData: rootDrawingData,
                strokeCount: 1
            )
        ])
        let rootDraftID = state.draftChords[0].id

        state.replaceDraftChords(with: [
            draftInput(
                measureID: measureID,
                measureIndex: 0,
                fraction: 0.31,
                bestCandidateText: "Cb",
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 0, fraction: 0.31),
                drawingData: absorbedDrawingData,
                strokeCount: 3
            )
        ])

        XCTAssertEqual(state.draftChords.count, 2)
        XCTAssertEqual(state.draftChords[0].id, rootDraftID)
        XCTAssertEqual(state.draftChords[0].previewText, "C")
        XCTAssertEqual(state.draftChords[0].drawingData, rootDrawingData)
        XCTAssertNil(state.draftChords[1].previewText)
        XCTAssertEqual(state.draftChords[1].drawingData, absorbedDrawingData)
        XCTAssertEqual(state.renderableDraftChords.map(\.previewText), ["C"])
        XCTAssertEqual(state.unresolvedChordCount, 1)
        XCTAssertFalse(state.canRenderAllDraftChords)
    }

    func testDraftStatePreservesReadableDraftWhenExpandedInkBecomesNoRead() {
        let measureID = UUID()
        let previousStrokes = [
            Self.pkStroke(points: [CGPoint(x: 10, y: 20), CGPoint(x: 30, y: 42), CGPoint(x: 12, y: 66)]),
            Self.pkStroke(points: [CGPoint(x: 42, y: 18), CGPoint(x: 62, y: 18), CGPoint(x: 50, y: 66)]),
            Self.pkStroke(points: [CGPoint(x: 72, y: 16), CGPoint(x: 66, y: 38), CGPoint(x: 72, y: 66)]),
            Self.pkStroke(points: [CGPoint(x: 84, y: 16), CGPoint(x: 84, y: 66), CGPoint(x: 98, y: 52), CGPoint(x: 88, y: 42)]),
            Self.pkStroke(points: [CGPoint(x: 108, y: 24), CGPoint(x: 118, y: 18), CGPoint(x: 126, y: 32), CGPoint(x: 114, y: 44)]),
            Self.pkStroke(points: [CGPoint(x: 136, y: 16), CGPoint(x: 152, y: 18), CGPoint(x: 142, y: 66)])
        ]
        let nextChordStrokes = [
            Self.pkStroke(points: [CGPoint(x: 172, y: 20), CGPoint(x: 192, y: 42), CGPoint(x: 174, y: 66)]),
            Self.pkStroke(points: [CGPoint(x: 206, y: 24), CGPoint(x: 214, y: 16), CGPoint(x: 224, y: 24), CGPoint(x: 222, y: 34), CGPoint(x: 212, y: 40), CGPoint(x: 206, y: 34)]),
            Self.pkStroke(points: [CGPoint(x: 236, y: 18), CGPoint(x: 256, y: 18), CGPoint(x: 244, y: 66)])
        ]
        let previousDrawingData = Self.drawingData(strokes: previousStrokes)
        let absorbedDrawingData = Self.drawingData(strokes: previousStrokes + nextChordStrokes)
        var state = ChordPreviewState()
        state.replaceDraftChords(with: [
            draftInput(
                measureID: measureID,
                measureIndex: 0,
                fraction: 0.42,
                bestCandidateText: "C7(b9)",
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 0, fraction: 0.42),
                drawingData: previousDrawingData,
                strokeCount: previousStrokes.count
            )
        ])
        let readableDraftID = state.draftChords[0].id

        state.replaceDraftChords(with: [
            ChordInkDraftInput(
                measureID: measureID,
                measureIndex: 0,
                targetFraction: 0.51,
                visualOrder: nil,
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 0, fraction: 0.51),
                layoutPageSize: nil,
                drawingData: absorbedDrawingData,
                candidateTexts: [],
                bestCandidateText: nil,
                confidence: 0,
                strokeCount: previousStrokes.count + nextChordStrokes.count
            )
        ])

        XCTAssertEqual(state.draftChords.count, 2)
        XCTAssertEqual(state.draftChords[0].id, readableDraftID)
        XCTAssertEqual(state.draftChords[0].previewText, "C7(b9)")
        XCTAssertEqual(state.draftChords[0].drawingData, previousDrawingData)
        XCTAssertNil(state.draftChords[1].previewText)
        XCTAssertEqual(state.draftChords[1].drawingData, absorbedDrawingData)
        XCTAssertEqual(state.renderableDraftChords.map(\.previewText), ["C7(b9)"])
        XCTAssertEqual(state.unresolvedChordCount, 1)
        XCTAssertFalse(state.canRenderAllDraftChords)
    }

    func testDraftStateAllowsAttachedAccidentalToReplaceRootRead() {
        let measureID = UUID()
        let rootStroke = Self.pkStroke(points: [
            CGPoint(x: 10, y: 20),
            CGPoint(x: 34, y: 44),
            CGPoint(x: 12, y: 68)
        ])
        let attachedFlat = Self.pkStroke(points: [
            CGPoint(x: 38, y: 14),
            CGPoint(x: 38, y: 62),
            CGPoint(x: 48, y: 42),
            CGPoint(x: 38, y: 62)
        ])
        let rootDrawingData = Self.drawingData(strokes: [rootStroke])
        let flatDrawingData = Self.drawingData(strokes: [rootStroke, attachedFlat])
        var state = ChordPreviewState()
        state.replaceDraftChords(with: [
            draftInput(
                measureID: measureID,
                measureIndex: 0,
                fraction: 0.24,
                bestCandidateText: "C",
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 0, fraction: 0.24),
                drawingData: rootDrawingData,
                strokeCount: 1
            )
        ])
        let rootDraftID = state.draftChords[0].id

        state.replaceDraftChords(with: [
            draftInput(
                measureID: measureID,
                measureIndex: 0,
                fraction: 0.245,
                bestCandidateText: "Cb",
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 0, fraction: 0.245),
                drawingData: flatDrawingData,
                strokeCount: 2
            )
        ])

        XCTAssertEqual(state.draftChords.count, 1)
        XCTAssertEqual(state.draftChords[0].id, rootDraftID)
        XCTAssertEqual(state.draftChords[0].previewText, "Cb")
        XCTAssertEqual(state.unresolvedChordCount, 0)
        XCTAssertTrue(state.canRenderAllDraftChords)
    }

    func testDraftStateAllowsLegalSameChordSuffixContinuationWhenDetachedInkCompletesSuffix() {
        let measureID = UUID()
        let previousStrokes = (0..<6).map { index in
            Self.pkStroke(points: [
                CGPoint(x: 10 + CGFloat(index * 18), y: 20),
                CGPoint(x: 18 + CGFloat(index * 18), y: 68)
            ])
        }
        let detachedFourStroke = Self.pkStroke(points: [
            CGPoint(x: 170, y: 22),
            CGPoint(x: 158, y: 46),
            CGPoint(x: 184, y: 46),
            CGPoint(x: 184, y: 22),
            CGPoint(x: 184, y: 70)
        ])
        let previousDrawingData = Self.drawingData(strokes: previousStrokes)
        let completedDrawingData = Self.drawingData(strokes: previousStrokes + [detachedFourStroke])
        var state = ChordPreviewState()
        state.replaceDraftChords(with: [
            draftInput(
                measureID: measureID,
                measureIndex: 0,
                fraction: 0.34,
                bestCandidateText: "Absus",
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 0, fraction: 0.34),
                drawingData: previousDrawingData,
                strokeCount: previousStrokes.count
            )
        ])
        let draftID = state.draftChords[0].id

        state.replaceDraftChords(with: [
            draftInput(
                measureID: measureID,
                measureIndex: 0,
                fraction: 0.34,
                bestCandidateText: "Absus4",
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 0, fraction: 0.34),
                drawingData: completedDrawingData,
                strokeCount: previousStrokes.count + 1
            )
        ])

        XCTAssertEqual(state.draftChords.count, 1)
        XCTAssertEqual(state.draftChords[0].id, draftID)
        XCTAssertEqual(state.draftChords[0].previewText, "Absus4")
        XCTAssertEqual(state.draftChords[0].drawingData, completedDrawingData)
        XCTAssertEqual(state.unresolvedChordCount, 0)
        XCTAssertTrue(state.canRenderAllDraftChords)
    }

    func testDraftStateOrdersPreviewByVisualLanePlacement() {
        let leftMeasureID = UUID()
        let rightMeasureID = UUID()
        var state = ChordPreviewState()

        state.replaceDraftChords(with: [
            draftInput(
                measureID: rightMeasureID,
                measureIndex: 0,
                fraction: 0.1,
                bestCandidateText: "Cdim7",
                visualOrder: 0.72
            ),
            draftInput(
                measureID: leftMeasureID,
                measureIndex: 1,
                fraction: 0.9,
                bestCandidateText: "Bb-7",
                visualOrder: 0.55
            )
        ])

        XCTAssertEqual(state.draftChords.compactMap(\.previewText), ["Bb-7", "Cdim7"])
    }

    func testDraftStateCollapsesDuplicatePreviewInputsForSameVisibleChord() {
        let measureID = UUID()
        let sourceInk = Data("same-c-source".utf8)
        var state = ChordPreviewState()

        state.replaceDraftChords(with: [
            draftInput(
                measureID: measureID,
                measureIndex: 0,
                fraction: 0.3,
                bestCandidateText: "C",
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 0, fraction: 0.3),
                drawingData: sourceInk,
                confidence: 5,
                strokeCount: 1
            ),
            draftInput(
                measureID: measureID,
                measureIndex: 0,
                fraction: 0.34,
                bestCandidateText: "C",
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 0, fraction: 0.34),
                drawingData: sourceInk,
                confidence: 4,
                strokeCount: 3
            )
        ])

        XCTAssertEqual(state.draftChords.count, 1)
        XCTAssertEqual(state.draftChords[0].previewText, "C")
        XCTAssertEqual(state.draftChords[0].drawingData, sourceInk)
        XCTAssertEqual(state.draftChords[0].strokeCount, 3)
    }

    func testDraftStateLetsExpandedChordPreviewSupersedeNearbyRootOnlyPreview() {
        let measureID = UUID()
        let sourceInk = Data("same-c-minor-source".utf8)
        var state = ChordPreviewState()

        state.replaceDraftChords(with: [
            draftInput(
                measureID: measureID,
                measureIndex: 0,
                fraction: 0.3,
                bestCandidateText: "C-",
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 0, fraction: 0.3),
                drawingData: sourceInk,
                confidence: 4,
                strokeCount: 2
            ),
            draftInput(
                measureID: measureID,
                measureIndex: 0,
                fraction: 0.34,
                bestCandidateText: "C",
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 0, fraction: 0.34),
                drawingData: sourceInk,
                confidence: 5,
                strokeCount: 1
            )
        ])

        XCTAssertEqual(state.draftChords.count, 1)
        XCTAssertEqual(state.draftChords[0].previewText, "C-")
        XCTAssertEqual(state.draftChords[0].drawingData, sourceInk)
    }

    func testDraftStateKeepsNearbyRepeatedChordInputsFromDifferentSourceInk() {
        let measureID = UUID()
        var state = ChordPreviewState()

        state.replaceDraftChords(with: [
            draftInput(
                measureID: measureID,
                measureIndex: 0,
                fraction: 0.3,
                bestCandidateText: "C",
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 0, fraction: 0.3),
                drawingData: Data("first-c-source".utf8)
            ),
            draftInput(
                measureID: measureID,
                measureIndex: 0,
                fraction: 0.34,
                bestCandidateText: "C",
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 0, fraction: 0.34),
                drawingData: Data("second-c-source".utf8)
            ),
            draftInput(
                measureID: measureID,
                measureIndex: 0,
                fraction: 0.37,
                bestCandidateText: "C-",
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 0, fraction: 0.37),
                drawingData: Data("c-minor-source".utf8)
            )
        ])

        XCTAssertEqual(state.draftChords.count, 3)
        XCTAssertEqual(state.draftChords.compactMap(\.previewText), ["C", "C", "C-"])
    }

    func testDraftStateKeepsIntentionalNeighboringPreviewInputs() {
        let measureID = UUID()
        var state = ChordPreviewState()

        state.replaceDraftChords(with: [
            draftInput(
                measureID: measureID,
                measureIndex: 0,
                fraction: 0.1,
                bestCandidateText: "C",
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 0, fraction: 0.1),
                drawingData: Data("first-lane-c".utf8)
            ),
            draftInput(
                measureID: measureID,
                measureIndex: 0,
                fraction: 0.13,
                bestCandidateText: "D",
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 0, fraction: 0.13),
                drawingData: Data("first-lane-d".utf8)
            ),
            draftInput(
                measureID: measureID,
                measureIndex: 0,
                fraction: 0.22,
                bestCandidateText: "C",
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 0, fraction: 0.22),
                drawingData: Data("second-lane-c".utf8)
            ),
            draftInput(
                measureID: measureID,
                measureIndex: 0,
                fraction: 0.12,
                bestCandidateText: "C",
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 1, fraction: 0.12),
                drawingData: Data("other-lane-c".utf8)
            ),
            draftInput(
                measureID: measureID,
                measureIndex: 0,
                fraction: 0.36,
                bestCandidateText: "C-",
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 0, fraction: 0.36),
                drawingData: Data("first-lane-c-minor".utf8)
            )
        ])

        XCTAssertEqual(state.draftChords.count, 5)
        XCTAssertEqual(state.draftChords.compactMap(\.previewText), ["C", "D", "C", "C-", "C"])
    }

    func testDraftStateKeepsNearbyUnresolvedPreviewInputs() {
        let measureID = UUID()
        var state = ChordPreviewState()

        state.replaceDraftChords(with: [
            ChordInkDraftInput(
                measureID: measureID,
                measureIndex: 0,
                targetFraction: 0.3,
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 0, fraction: 0.3),
                drawingData: Data("first-unresolved".utf8),
                candidateTexts: [],
                bestCandidateText: nil,
                confidence: 0,
                strokeCount: 1
            ),
            ChordInkDraftInput(
                measureID: measureID,
                measureIndex: 0,
                targetFraction: 0.34,
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 0, fraction: 0.34),
                drawingData: Data("second-unresolved".utf8),
                candidateTexts: [],
                bestCandidateText: nil,
                confidence: 0,
                strokeCount: 1
            )
        ])

        XCTAssertEqual(state.draftChords.count, 2)
        XCTAssertTrue(state.draftChords.allSatisfy { $0.previewText == nil })
    }

    func testDraftBarlineRecognizerAcceptsTallStraightLaneStrokeAndRejectsSlashStroke() {
        let measureID = UUID()
        let pageLayout = Self.pageLayout(measureID: measureID)
        let verticalStroke = InkStroke(points: [
            InkPoint(x: 150, y: 94, timeOffset: 0),
            InkPoint(x: 151, y: 118, timeOffset: 0.1),
            InkPoint(x: 150, y: 141, timeOffset: 0.2)
        ])
        let slashStroke = InkStroke(points: [
            InkPoint(x: 190, y: 110, timeOffset: 0),
            InkPoint(x: 226, y: 160, timeOffset: 0.2)
        ])

        let recognition = ChordDraftBarlineRecognizer.recognize(
            strokes: [verticalStroke, slashStroke],
            chordFrame: .zero,
            pageLayout: pageLayout
        )

        XCTAssertEqual(recognition.barlines.count, 1)
        XCTAssertEqual(recognition.barlines[0].measureID, measureID)
        XCTAssertEqual(recognition.barlines[0].sourceStrokeIndex, 0)
        XCTAssertEqual(recognition.strokeIndices, [0])
        XCTAssertTrue(recognition.barlines[0].isRenderable)
    }

    func testDraftBarlineRecognizerAcceptsSloppyPartialHeightLaneStroke() {
        let measureID = UUID()
        let pageLayout = Self.pageLayout(measureID: measureID)
        let partialLaneStroke = InkStroke(points: [
            InkPoint(x: 150, y: 100, timeOffset: 0),
            InkPoint(x: 156, y: 116, timeOffset: 0.1),
            InkPoint(x: 160, y: 132, timeOffset: 0.2)
        ])

        let recognition = ChordDraftBarlineRecognizer.recognize(
            strokes: [partialLaneStroke],
            chordFrame: .zero,
            pageLayout: pageLayout
        )

        XCTAssertEqual(recognition.barlines.count, 1)
        XCTAssertEqual(recognition.barlines[0].measureID, measureID)
        XCTAssertEqual(recognition.barlines[0].sourceStrokeIndex, 0)
        XCTAssertGreaterThan(recognition.barlines[0].metrics.angleDegreesFromVertical, 10)
        XCTAssertLessThan(recognition.barlines[0].metrics.laneCoverage, 0.8)
        XCTAssertTrue(recognition.barlines[0].isRenderable)
    }

    func testDraftBarlineRecognizerRejectsOvertallOutOfBandLaneStroke() {
        let measureID = UUID()
        let pageLayout = Self.pageLayout(measureID: measureID)
        let overtallStroke = InkStroke(points: [
            InkPoint(x: 150, y: 60, timeOffset: 0),
            InkPoint(x: 151, y: 120, timeOffset: 0.1),
            InkPoint(x: 150, y: 180, timeOffset: 0.2)
        ])

        let recognition = ChordDraftBarlineRecognizer.recognize(
            strokes: [overtallStroke],
            chordFrame: .zero,
            pageLayout: pageLayout
        )

        XCTAssertTrue(recognition.barlines.isEmpty)
        XCTAssertTrue(recognition.strokeIndices.isEmpty)
    }

    func testDraftBarlineRecognizerAcceptsOpenLaneStrokeBeyondRenderedMeasureBox() {
        let measureID = UUID()
        let pageLayout = Self.pageLayout(measureID: measureID)
        let openLaneStroke = InkStroke(points: [
            InkPoint(x: 360, y: 94, timeOffset: 0),
            InkPoint(x: 361, y: 118, timeOffset: 0.1),
            InkPoint(x: 360, y: 141, timeOffset: 0.2)
        ])

        XCTAssertFalse(
            pageLayout.systems[0].measures[0].chordWritingFrame.contains(
                CGPoint(x: 360, y: 118)
            )
        )
        XCTAssertTrue(
            LeadSheetActiveInkScope.chordWritingInputFrames(for: pageLayout)[0].contains(
                CGPoint(x: 360, y: 118)
            )
        )

        let recognition = ChordDraftBarlineRecognizer.recognize(
            strokes: [openLaneStroke],
            chordFrame: .zero,
            pageLayout: pageLayout
        )

        XCTAssertEqual(recognition.barlines.count, 1)
        XCTAssertEqual(recognition.barlines[0].measureID, measureID)
        XCTAssertGreaterThan(recognition.barlines[0].fraction, 0.9)
    }

    func testDraftBarlineRecognizerTargetsOpenMeasureFromContinuationLane() throws {
        var chart = Chart.draft(title: "Continuation Lane", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(
            title: "Continuation Lane",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 1
        )
        let openMeasureID = try XCTUnwrap(chart.measures.first(where: { $0.authoringState == .open })?.id)
        let pageLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400),
            includesChordInkContinuationLanes: true
        )
        let continuationLane = try XCTUnwrap(
            LeadSheetActiveInkScope.chordWritingInputFrames(for: pageLayout).dropFirst().first
        )
        let stroke = InkStroke(points: [
            InkPoint(x: Double(continuationLane.midX), y: Double(continuationLane.minY + 2), timeOffset: 0),
            InkPoint(x: Double(continuationLane.midX + 1), y: Double(continuationLane.midY), timeOffset: 0.1),
            InkPoint(x: Double(continuationLane.midX), y: Double(continuationLane.maxY - 2), timeOffset: 0.2)
        ])

        let recognition = ChordDraftBarlineRecognizer.recognize(
            strokes: [stroke],
            chordFrame: .zero,
            pageLayout: pageLayout
        )

        XCTAssertEqual(recognition.barlines.count, 1)
        XCTAssertEqual(recognition.barlines.first?.measureID, openMeasureID)
        XCTAssertEqual(recognition.barlines.first?.measureIndex, 1)
        XCTAssertEqual(recognition.barlines.first?.laneLocation?.systemIndex, 1)
        XCTAssertEqual(recognition.barlines.first?.fraction ?? 0, 0.5, accuracy: 0.04)
        XCTAssertEqual(recognition.barlines.first?.laneLocation?.fraction ?? 0, 0.5, accuracy: 0.04)
        XCTAssertEqual(recognition.strokeIndices, [0])
    }

    func testChordBatchTargetingUsesDraftBarlineOnlyOnItsContinuationLane() throws {
        var chart = Chart.draft(title: "Lane Barline", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(
            title: "Lane Barline",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 1
        )
        let openMeasureID = try XCTUnwrap(chart.measures.first(where: { $0.authoringState == .open })?.id)
        let pageLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400),
            includesChordInkContinuationLanes: true
        )
        let chordRegion = LeadSheetActiveInkScope.chordWritingRegion(for: pageLayout)
        let firstLane = try XCTUnwrap(chordRegion.inputFrames.first)
        let continuationLane = try XCTUnwrap(chordRegion.inputFrames.dropFirst().first)
        let barlineFraction = 0.48
        let firstLaneChordX = firstLane.minX + firstLane.width * 0.34
        let secondLaneLeftX = continuationLane.minX + continuationLane.width * 0.22
        let secondLaneRightX = continuationLane.minX + continuationLane.width * 0.68
        let barlineX = continuationLane.minX + continuationLane.width * CGFloat(barlineFraction)
        let barlineStroke = InkStroke(points: [
            InkPoint(x: Double(barlineX), y: Double(continuationLane.minY + 2), timeOffset: 0),
            InkPoint(x: Double(barlineX + 1), y: Double(continuationLane.midY), timeOffset: 0.1),
            InkPoint(x: Double(barlineX), y: Double(continuationLane.maxY - 2), timeOffset: 0.2)
        ])
        let barlineRecognition = ChordDraftBarlineRecognizer.recognize(
            strokes: [barlineStroke],
            chordFrame: .zero,
            pageLayout: pageLayout
        )
        let barline = try XCTUnwrap(barlineRecognition.barlines.first)
        XCTAssertEqual(barline.measureID, openMeasureID)
        XCTAssertEqual(barline.laneLocation?.systemIndex, 1)

        let drawing = PKDrawing(strokes: [
            Self.pkStroke(points: [
                CGPoint(x: firstLaneChordX - chordRegion.frame.minX - 10, y: firstLane.midY - chordRegion.frame.minY - 10),
                CGPoint(x: firstLaneChordX - chordRegion.frame.minX + 10, y: firstLane.midY - chordRegion.frame.minY + 10)
            ]),
            Self.pkStroke(points: [
                CGPoint(x: secondLaneLeftX - chordRegion.frame.minX - 10, y: continuationLane.midY - chordRegion.frame.minY - 10),
                CGPoint(x: secondLaneLeftX - chordRegion.frame.minX + 10, y: continuationLane.midY - chordRegion.frame.minY + 10)
            ]),
            Self.pkStroke(points: [
                CGPoint(x: secondLaneRightX - chordRegion.frame.minX - 10, y: continuationLane.midY - chordRegion.frame.minY - 10),
                CGPoint(x: secondLaneRightX - chordRegion.frame.minX + 10, y: continuationLane.midY - chordRegion.frame.minY + 10)
            ])
        ])

        let targets = LeadSheetChordInkRecognitionTargeting.batchTargets(
            for: drawing,
            chordFrame: chordRegion.frame,
            pageLayout: pageLayout,
            draftBarlines: [barline]
        )

        XCTAssertEqual(targets.count, 3)
        XCTAssertEqual(targets.map(\.measureID), [openMeasureID, openMeasureID, openMeasureID])
        XCTAssertEqual(targets.map { $0.laneLocation?.systemIndex }, [0, 1, 1])
        XCTAssertLessThan(targets[1].laneLocation?.fraction ?? 0, barlineFraction)
        XCTAssertGreaterThan(targets[2].laneLocation?.fraction ?? 0, barlineFraction)
    }

    func testChordTargetingUsesContinuationLaneFromActiveScopeLocalCoordinates() throws {
        var chart = Chart.draft(title: "Continuation Chord", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(
            title: "Continuation Chord",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 1
        )
        let openMeasureID = try XCTUnwrap(chart.measures.first(where: { $0.authoringState == .open })?.id)
        let pageLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400),
            includesChordInkContinuationLanes: true
        )
        let chordRegion = LeadSheetActiveInkScope.chordWritingRegion(for: pageLayout)
        let continuationLane = try XCTUnwrap(chordRegion.inputFrames.dropFirst().first)
        let localCenter = CGPoint(
            x: continuationLane.midX - chordRegion.frame.minX,
            y: continuationLane.midY - chordRegion.frame.minY
        )
        let drawing = PKDrawing(strokes: [
            Self.pkStroke(points: [
                CGPoint(x: localCenter.x - 12, y: localCenter.y + 12),
                CGPoint(x: localCenter.x + 12, y: localCenter.y - 12)
            ])
        ])

        let target = try XCTUnwrap(
            LeadSheetChordInkRecognitionTargeting.target(
                for: drawing,
                chordFrame: chordRegion.frame,
                pageLayout: pageLayout
            )
        )
        let laneLocation = try XCTUnwrap(
            LeadSheetChordInkRecognitionTargeting.laneLocation(
                for: drawing,
                chordFrame: chordRegion.frame,
                pageLayout: pageLayout
            )
        )

        XCTAssertEqual(target.measureID, openMeasureID)
        XCTAssertEqual(laneLocation.systemIndex, 1)
        XCTAssertEqual(laneLocation.fraction, 0.5, accuracy: 0.04)
    }

    func testChordBatchTargetingSplitsSameOpenMeasureInkAcrossContinuationLanes() throws {
        var chart = Chart.draft(title: "Continuation Batch", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(
            title: "Continuation Batch",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 1
        )
        let openMeasureID = try XCTUnwrap(chart.measures.first(where: { $0.authoringState == .open })?.id)
        let pageLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400),
            includesChordInkContinuationLanes: true
        )
        let chordRegion = LeadSheetActiveInkScope.chordWritingRegion(for: pageLayout)
        let firstLane = try XCTUnwrap(chordRegion.inputFrames.first)
        let continuationLane = try XCTUnwrap(chordRegion.inputFrames.dropFirst().first)
        let firstLocalCenter = CGPoint(
            x: firstLane.midX - chordRegion.frame.minX,
            y: firstLane.midY - chordRegion.frame.minY
        )
        let continuationLocalCenter = CGPoint(
            x: continuationLane.midX - chordRegion.frame.minX,
            y: continuationLane.midY - chordRegion.frame.minY
        )
        let drawing = PKDrawing(strokes: [
            Self.pkStroke(points: [
                CGPoint(x: firstLocalCenter.x - 10, y: firstLocalCenter.y - 10),
                CGPoint(x: firstLocalCenter.x + 10, y: firstLocalCenter.y + 10)
            ]),
            Self.pkStroke(points: [
                CGPoint(x: continuationLocalCenter.x - 10, y: continuationLocalCenter.y - 10),
                CGPoint(x: continuationLocalCenter.x + 10, y: continuationLocalCenter.y + 10)
            ])
        ])

        let targets = LeadSheetChordInkRecognitionTargeting.batchTargets(
            for: drawing,
            chordFrame: chordRegion.frame,
            pageLayout: pageLayout
        )

        XCTAssertEqual(targets.count, 2)
        XCTAssertEqual(targets.map(\.measureID), [openMeasureID, openMeasureID])
        XCTAssertEqual(targets.map { $0.laneLocation?.systemIndex }, [0, 1])
        XCTAssertLessThan(targets[0].visualOrder, targets[1].visualOrder)
    }

    func testDraftBarlineRecognizerRejectsChordLikeVerticalStrokeInsideLane() {
        let measureID = UUID()
        let pageLayout = Self.pageLayout(measureID: measureID)
        let chordStemStroke = InkStroke(points: [
            InkPoint(x: 150, y: 108, timeOffset: 0),
            InkPoint(x: 151, y: 122, timeOffset: 0.1),
            InkPoint(x: 150, y: 136, timeOffset: 0.2)
        ])

        let recognition = ChordDraftBarlineRecognizer.recognize(
            strokes: [chordStemStroke],
            chordFrame: .zero,
            pageLayout: pageLayout
        )

        XCTAssertTrue(recognition.barlines.isEmpty)
        XCTAssertTrue(recognition.strokeIndices.isEmpty)
    }

    func testDraftStateRemovesSelectedBarlineAndPreservesBarlineIDAcrossRecognitionPasses() throws {
        let measureID = UUID()
        var state = ChordPreviewState()
        state.replaceDraftBarlines(with: [
            draftBarline(measureID: measureID, measureIndex: 1, fraction: 0.42, sourceStrokeIndex: 2)
        ])

        let stableID = try XCTUnwrap(state.draftBarlines.first?.id)
        state.replaceDraftBarlines(with: [
            draftBarline(measureID: measureID, measureIndex: 1, fraction: 0.421, sourceStrokeIndex: 2)
        ])

        XCTAssertEqual(state.draftBarlines.first?.id, stableID)
        let removedBarline = try XCTUnwrap(state.removeDraftBarline(id: stableID))
        XCTAssertEqual(removedBarline.sourceStrokeIndex, 2)
        XCTAssertTrue(state.draftBarlines.isEmpty)
    }

    func testDraftBarlineOverlaySelectsThenDeletesSelectedLine() throws {
        let measureID = UUID()
        let barline = draftBarline(measureID: measureID, measureIndex: 1, fraction: 0.5)
        let laneFrame = CGRect(x: 100, y: 80, width: 400, height: 50)
        let lineFrame = ChordDraftBarlineOverlayGeometry.lineFrame(for: barline, in: laneFrame)

        let selectTarget = ChordDraftBarlineOverlayGeometry.hitTarget(
            at: CGPoint(x: lineFrame.midX, y: lineFrame.midY),
            barlines: [barline],
            laneFrameForBarline: { _ in laneFrame },
            selectedBarlineID: nil
        )
        XCTAssertEqual(selectTarget, ChordDraftBarlineHitTarget(barlineID: barline.id, action: .select))

        let deleteByLineTarget = ChordDraftBarlineOverlayGeometry.hitTarget(
            at: CGPoint(x: lineFrame.midX, y: lineFrame.midY),
            barlines: [barline],
            laneFrameForBarline: { _ in laneFrame },
            selectedBarlineID: barline.id
        )
        XCTAssertEqual(deleteByLineTarget, ChordDraftBarlineHitTarget(barlineID: barline.id, action: .delete))

        let deleteFrame = ChordDraftBarlineOverlayGeometry.controlFrames(for: barline, in: laneFrame).delete
        let deleteByControlTarget = ChordDraftBarlineOverlayGeometry.hitTarget(
            at: CGPoint(x: deleteFrame.midX, y: deleteFrame.midY),
            barlines: [barline],
            laneFrameForBarline: { _ in laneFrame },
            selectedBarlineID: barline.id
        )
        XCTAssertEqual(deleteByControlTarget, ChordDraftBarlineHitTarget(barlineID: barline.id, action: .delete))
    }

    func testDraftBarlineOverlayUsesLaneSpecificFrame() throws {
        let measureID = UUID()
        let firstLaneFrame = CGRect(x: 100, y: 80, width: 400, height: 50)
        let secondLaneFrame = CGRect(x: 100, y: 170, width: 400, height: 50)
        let barline = draftBarline(
            measureID: measureID,
            measureIndex: 1,
            fraction: 0.5,
            laneLocation: ChordInkDraftLaneLocation(systemIndex: 1, fraction: 0.5)
        )
        let secondLineFrame = ChordDraftBarlineOverlayGeometry.lineFrame(for: barline, in: secondLaneFrame)

        let firstLaneTarget = ChordDraftBarlineOverlayGeometry.hitTarget(
            at: CGPoint(x: secondLineFrame.midX, y: firstLaneFrame.midY),
            barlines: [barline],
            laneFrameForBarline: { _ in secondLaneFrame },
            selectedBarlineID: nil
        )
        let secondLaneTarget = ChordDraftBarlineOverlayGeometry.hitTarget(
            at: CGPoint(x: secondLineFrame.midX, y: secondLineFrame.midY),
            barlines: [barline],
            laneFrameForBarline: { _ in secondLaneFrame },
            selectedBarlineID: nil
        )

        XCTAssertNil(firstLaneTarget)
        XCTAssertEqual(secondLaneTarget, ChordDraftBarlineHitTarget(barlineID: barline.id, action: .select))
    }

    func testDraftBatchRenderCommitsOnlyOnExplicitRender() throws {
        var chart = Chart.draft(title: "Draft Chords", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(
            title: "Draft Chords",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 2
        )
        let firstMeasureID = chart.measures[0].id
        let openMeasureID = chart.measures[1].id
        XCTAssertEqual(chart.measures[1].authoringState, .open)

        var state = ChordPreviewState()
        state.replaceDraftChords(with: [
            draftInput(
                measureID: firstMeasureID,
                measureIndex: 0,
                fraction: 0.1,
                bestCandidateText: "C",
                drawingData: Data("ink-C".utf8)
            )
        ])
        state.replaceDraftBarlines(with: [
            DraftBarline(
                measureID: openMeasureID,
                measureIndex: 1,
                fraction: 0.92,
                metrics: DraftBarlineGestureMetrics(
                    height: 54,
                    width: 2,
                    angleDegreesFromVertical: 2,
                    straightness: 0.98,
                    laneCoverage: 0.8
                )
            )
        ])

        XCTAssertTrue(chart.measures.allSatisfy(\.chordEvents.isEmpty))
        XCTAssertEqual(chart.measures.count, 2)

        XCTAssertTrue(chart.setPageHandwrittenChordDrawing(Data("full-draft-ink".utf8)))
        let result = chart.commitChordInkDraftBatch(state)

        XCTAssertEqual(result.renderedChordCount, 1)
        XCTAssertEqual(result.renderedBarlineCount, 1)
        XCTAssertTrue(result.unresolvedDraftIDs.isEmpty)
        XCTAssertEqual(chart.measures[0].chordEvents.first?.symbol.displayText, "C")
        XCTAssertEqual(chart.measures.count, 3)
        XCTAssertEqual(chart.measures[1].authoringState, .committed)
        XCTAssertEqual(chart.measures[2].authoringState, .open)
        XCTAssertNil(chart.pageHandwrittenChordData)
    }

    func testDraftBatchRenderUsesDrawnBarlineSpacingForCommittedMeasureWidths() throws {
        var chart = Chart.draft(title: "Drawn Spacing", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(
            title: "Drawn Spacing",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 1
        )
        let openMeasureID = try XCTUnwrap(chart.measures.first?.id)
        let pageSize = CGSize(width: 900, height: 1400)
        var state = ChordPreviewState()
        state.layoutPageSize = pageSize
        state.replaceDraftBarlines(with: [
            draftBarline(measureID: openMeasureID, measureIndex: 1, fraction: 0.25),
            draftBarline(measureID: openMeasureID, measureIndex: 1, fraction: 0.75)
        ])
        let sourceLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: pageSize,
            includesChordInkContinuationLanes: true
        )
        let sourceLane = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingInputFrames(for: sourceLayout).first)

        let result = chart.commitChordInkDraftBatch(state, barlineSpacingMode: .drawn)
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize)
        let measures = try XCTUnwrap(layout.systems.first?.measures)
        let widths = measures.map(\.frame.width)

        XCTAssertEqual(result.renderedBarlineCount, 2)
        XCTAssertEqual(widths.count, 3)
        XCTAssertGreaterThan(widths[1], widths[0] * 1.45)
        XCTAssertGreaterThan(widths[1], widths[2] * 1.45)
        XCTAssertEqual(
            measures[0].trailingBarlineFrame.midX,
            sourceLane.minX + sourceLane.width * 0.25,
            accuracy: 10
        )
        XCTAssertEqual(
            measures[1].trailingBarlineFrame.midX,
            sourceLane.minX + sourceLane.width * 0.75,
            accuracy: 10
        )
    }

    func testDraftBarlineAutoCommitPlacesSecondSameLaneBoundaryInCurrentOpenSpan() throws {
        var chart = Chart.draft(title: "Same Lane Sequential", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(
            title: "Same Lane Sequential",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 1
        )
        let pageSize = CGSize(width: 900, height: 1400)
        let firstOpenMeasureID = try XCTUnwrap(chart.measures.first(where: { $0.authoringState == .open })?.id)
        let initialLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: pageSize,
            includesChordInkContinuationLanes: true
        )
        let initialLane = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingInputFrames(for: initialLayout).first)
        let firstBoundaryX = initialLane.minX + initialLane.width * 0.32

        let firstRenderedIDs = chart.commitChordInkDraftBarlines(
            [draftBarline(measureID: firstOpenMeasureID, measureIndex: 1, fraction: 0.32)],
            layoutPageSize: pageSize,
            barlineSpacingMode: .drawn
        )
        XCTAssertEqual(firstRenderedIDs.count, 1)

        let currentOpenMeasureID = try XCTUnwrap(chart.measures.first(where: { $0.authoringState == .open })?.id)
        let afterFirstLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: pageSize,
            includesChordInkContinuationLanes: true
        )
        let currentOpenLayout = try XCTUnwrap(
            afterFirstLayout.systems.first?.measures.first(where: { $0.sourceMeasureID == currentOpenMeasureID })
        )
        let sameSystemLane = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingInputFrames(for: afterFirstLayout).first)
        let secondBoundaryX = currentOpenLayout.frame.minX + currentOpenLayout.frame.width * 0.45
        let secondLaneFraction = Double((secondBoundaryX - sameSystemLane.minX) / sameSystemLane.width)

        let secondRenderedIDs = chart.commitChordInkDraftBarlines(
            [
                draftBarline(
                    measureID: currentOpenMeasureID,
                    measureIndex: currentOpenLayout.index,
                    fraction: secondLaneFraction
                )
            ],
            layoutPageSize: pageSize,
            barlineSpacingMode: .drawn
        )
        XCTAssertEqual(secondRenderedIDs.count, 1)

        let finalLayout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize)
        let finalMeasures = try XCTUnwrap(finalLayout.systems.first?.measures)

        XCTAssertEqual(finalMeasures.count, 3)
        XCTAssertEqual(finalMeasures[0].trailingBarlineFrame.midX, firstBoundaryX, accuracy: 12)
        XCTAssertEqual(finalMeasures[1].trailingBarlineFrame.midX, secondBoundaryX, accuracy: 12)
    }

    func testDraftBarlineAutoCommitSplitsCommittedSameLaneSpan() throws {
        var chart = Chart.draft(title: "Committed Span Split", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(
            title: "Committed Span Split",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 1
        )
        let pageSize = CGSize(width: 900, height: 1400)
        let openMeasureID = try XCTUnwrap(chart.measures.first(where: { $0.authoringState == .open })?.id)
        let initialLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: pageSize,
            includesChordInkContinuationLanes: true
        )
        let initialLane = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingInputFrames(for: initialLayout).first)
        let firstBoundaryX = initialLane.minX + initialLane.width * 0.55

        let firstRenderedIDs = chart.commitChordInkDraftBarlines(
            [draftBarline(measureID: openMeasureID, measureIndex: 1, fraction: 0.55)],
            layoutPageSize: pageSize,
            barlineSpacingMode: .drawn
        )
        XCTAssertEqual(firstRenderedIDs.count, 1)

        let committedLeftMeasureID = try XCTUnwrap(chart.measures.first?.id)
        let afterFirstLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: pageSize,
            includesChordInkContinuationLanes: true
        )
        let committedLeftLayout = try XCTUnwrap(
            afterFirstLayout.systems.first?.measures.first(where: { $0.sourceMeasureID == committedLeftMeasureID })
        )
        let sameSystemLane = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingInputFrames(for: afterFirstLayout).first)
        let secondBoundaryX = committedLeftLayout.frame.minX + committedLeftLayout.frame.width * 0.36
        let secondLaneFraction = Double((secondBoundaryX - sameSystemLane.minX) / sameSystemLane.width)

        let secondRenderedIDs = chart.commitChordInkDraftBarlines(
            [
                draftBarline(
                    measureID: committedLeftMeasureID,
                    measureIndex: committedLeftLayout.index,
                    fraction: secondLaneFraction
                )
            ],
            layoutPageSize: pageSize,
            barlineSpacingMode: .drawn
        )
        XCTAssertEqual(secondRenderedIDs.count, 1)

        let finalLayout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize)
        let finalMeasures = try XCTUnwrap(finalLayout.systems.first?.measures)

        XCTAssertEqual(finalMeasures.count, 3)
        XCTAssertEqual(chart.measures.map(\.authoringState), [.committed, .committed, .open])
        XCTAssertEqual(finalMeasures[0].trailingBarlineFrame.midX, secondBoundaryX, accuracy: 12)
        XCTAssertEqual(finalMeasures[1].trailingBarlineFrame.midX, firstBoundaryX, accuracy: 12)
    }

    func testDraftBarlineOnlyCommitPreservesChordInkDrawing() throws {
        var chart = Chart.draft(title: "Auto Barline", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(
            title: "Auto Barline",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 1
        )
        let openMeasureID = try XCTUnwrap(chart.measures.first(where: { $0.authoringState == .open })?.id)
        XCTAssertTrue(chart.setPageHandwrittenChordDrawing(Data("draft-chord-ink".utf8)))

        let renderedBarlineIDs = chart.commitChordInkDraftBarlines(
            [draftBarline(measureID: openMeasureID, measureIndex: 1, fraction: 0.4)],
            layoutPageSize: CGSize(width: 900, height: 1400),
            barlineSpacingMode: .drawn
        )

        XCTAssertEqual(renderedBarlineIDs.count, 1)
        XCTAssertEqual(chart.measures.count, 2)
        XCTAssertEqual(chart.measures.map(\.authoringState), [.committed, .open])
        XCTAssertNotNil(chart.pageHandwrittenChordData)
    }

    func testRhythmDraftBarlineOnlyCommitPreservesChordInkDrawing() throws {
        var chart = Chart.draft(title: "Rhythm Auto Barline", layoutStyle: .rhythmSectionSheet)
        chart.completeInitialSetup(
            title: "Rhythm Auto Barline",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 1,
            clef: .bass
        )
        let openMeasureID = try XCTUnwrap(chart.measures.first(where: { $0.authoringState == .open })?.id)
        XCTAssertTrue(chart.setPageHandwrittenChordDrawing(Data("rhythm-draft-chord-ink".utf8)))

        let renderedBarlineIDs = chart.commitChordInkDraftBarlines(
            [draftBarline(measureID: openMeasureID, measureIndex: 1, fraction: 0.4)],
            layoutPageSize: CGSize(width: 900, height: 1400),
            barlineSpacingMode: .drawn
        )

        XCTAssertEqual(renderedBarlineIDs.count, 1)
        XCTAssertEqual(chart.measures.count, 2)
        XCTAssertEqual(chart.measures.map(\.authoringState), [.committed, .open])
        XCTAssertNotNil(chart.pageHandwrittenChordData)
    }

    func testDraftBatchRenderCanEvenlySpaceDraftBarlineMeasures() throws {
        var chart = Chart.draft(title: "Even Spacing", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(
            title: "Even Spacing",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 1
        )
        let openMeasureID = try XCTUnwrap(chart.measures.first?.id)
        let pageSize = CGSize(width: 900, height: 1400)
        var state = ChordPreviewState()
        state.layoutPageSize = pageSize
        state.replaceDraftBarlines(with: [
            draftBarline(measureID: openMeasureID, measureIndex: 1, fraction: 0.25),
            draftBarline(measureID: openMeasureID, measureIndex: 1, fraction: 0.75)
        ])

        let result = chart.commitChordInkDraftBatch(state, barlineSpacingMode: .even)
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize)
        let system = try XCTUnwrap(layout.systems.first)
        let widths = system.measures.map { measure in
            LeadSheetSimpleChordTerminalBarlineGeometry.displayMeasure(
                measure,
                in: system,
                paperFrame: layout.paperFrame,
                layoutStyle: chart.layoutStyle
            ).frame.width
        }

        XCTAssertEqual(result.renderedBarlineCount, 2)
        XCTAssertEqual(widths.count, 3)
        XCTAssertEqual(widths[0], widths[1], accuracy: 2.1)
        XCTAssertEqual(widths[1], widths[2], accuracy: 2.1)
    }

    func testDraftBatchRenderUsesDraftBarlineSegmentsForOpenLanePlacement() throws {
        var chart = Chart.draft(title: "Segmented Draft", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(
            title: "Segmented Draft",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 1
        )
        let openMeasureID = try XCTUnwrap(chart.measures.first?.id)
        XCTAssertEqual(chart.measures.first?.authoringState, .open)

        var state = ChordPreviewState()
        state.replaceDraftChords(with: [
            draftInput(
                measureID: openMeasureID,
                measureIndex: 1,
                fraction: 0.15,
                bestCandidateText: "C",
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 0, fraction: 0.15)
            ),
            draftInput(
                measureID: openMeasureID,
                measureIndex: 1,
                fraction: 0.5,
                bestCandidateText: "F",
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 0, fraction: 0.5)
            ),
            draftInput(
                measureID: openMeasureID,
                measureIndex: 1,
                fraction: 0.85,
                bestCandidateText: "G",
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 0, fraction: 0.85)
            )
        ])
        state.replaceDraftBarlines(with: [
            draftBarline(measureID: openMeasureID, measureIndex: 1, fraction: 0.33),
            draftBarline(measureID: openMeasureID, measureIndex: 1, fraction: 0.66)
        ])

        XCTAssertTrue(chart.setPageHandwrittenChordDrawing(Data("segmented-draft-ink".utf8)))
        let result = chart.commitChordInkDraftBatch(state)

        XCTAssertEqual(result.renderedChordCount, 3)
        XCTAssertEqual(result.renderedBarlineCount, 2)
        XCTAssertTrue(result.unresolvedDraftIDs.isEmpty)
        XCTAssertEqual(chart.measures.count, 3)
        XCTAssertEqual(chart.measures.map(\.authoringState), [.committed, .committed, .open])
        XCTAssertEqual(chart.measures[0].chordEvents.map { $0.symbol.displayText }, ["C"])
        XCTAssertEqual(chart.measures[1].chordEvents.map { $0.symbol.displayText }, ["F"])
        XCTAssertEqual(chart.measures[2].chordEvents.map { $0.symbol.displayText }, ["G"])
        XCTAssertNil(chart.pageHandwrittenChordData)
    }

    func testRhythmDraftBatchRenderUsesDraftBarlineSegmentsForBlankOpenMeasure() throws {
        var chart = Chart.draft(title: "Rhythm Segmented Draft", layoutStyle: .rhythmSectionSheet)
        chart.completeInitialSetup(
            title: "Rhythm Segmented Draft",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 1,
            clef: .bass
        )
        let openMeasureID = try XCTUnwrap(chart.measures.first?.id)
        let pageSize = CGSize(width: 900, height: 1400)
        let sourceLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: pageSize,
            includesChordInkContinuationLanes: true
        )
        let sourceMeasure = try XCTUnwrap(sourceLayout.systems.first?.measures.first)

        XCTAssertEqual(chart.measure(id: openMeasureID)?.authoringState, .open)
        XCTAssertLessThan(sourceMeasure.chordBandFrame.height, sourceMeasure.chordWritingFrame.height)
        XCTAssertTrue(sourceMeasure.chordWritingFrame.contains(sourceMeasure.chordBandFrame))
        XCTAssertGreaterThanOrEqual(sourceMeasure.chordWritingFrame.maxY, sourceMeasure.staffFrame.minY)

        var state = ChordPreviewState()
        state.layoutPageSize = pageSize
        state.replaceDraftChords(with: [
            draftInput(
                measureID: openMeasureID,
                measureIndex: sourceMeasure.index,
                fraction: 0.15,
                bestCandidateText: "C",
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 0, fraction: 0.15),
                layoutPageSize: pageSize
            ),
            draftInput(
                measureID: openMeasureID,
                measureIndex: sourceMeasure.index,
                fraction: 0.5,
                bestCandidateText: "F",
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 0, fraction: 0.5),
                layoutPageSize: pageSize
            ),
            draftInput(
                measureID: openMeasureID,
                measureIndex: sourceMeasure.index,
                fraction: 0.85,
                bestCandidateText: "G",
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 0, fraction: 0.85),
                layoutPageSize: pageSize
            )
        ])
        state.replaceDraftBarlines(with: [
            draftBarline(
                measureID: openMeasureID,
                measureIndex: sourceMeasure.index,
                fraction: 0.33,
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 0, fraction: 0.33),
                layoutPageSize: pageSize
            ),
            draftBarline(
                measureID: openMeasureID,
                measureIndex: sourceMeasure.index,
                fraction: 0.66,
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 0, fraction: 0.66),
                layoutPageSize: pageSize
            )
        ])

        XCTAssertTrue(chart.setPageHandwrittenChordDrawing(Data("rhythm-segmented-draft-ink".utf8)))
        let result = chart.commitChordInkDraftBatch(state)

        XCTAssertEqual(result.renderedChordCount, 3)
        XCTAssertEqual(result.renderedBarlineCount, 2)
        XCTAssertTrue(result.unresolvedDraftIDs.isEmpty)
        XCTAssertEqual(chart.measures.count, 3)
        XCTAssertEqual(chart.measures.map(\.authoringState), [.committed, .committed, .open])
        XCTAssertEqual(chart.measures.map { $0.chordEvents.map { $0.symbol.displayText } }, [["C"], ["F"], ["G"]])
        XCTAssertTrue(chart.measures.flatMap(\.chordEvents).allSatisfy { $0.manualLaneFraction == nil })
        XCTAssertNil(chart.pageHandwrittenChordData)

        let renderedLayout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize)
        let renderedMeasures = renderedLayout.systems.flatMap(\.measures)
        XCTAssertEqual(renderedMeasures.count, 3)
        XCTAssertTrue(renderedLayout.systems.allSatisfy { $0.staffLineYPositions.count == 5 })
        XCTAssertTrue(renderedMeasures.allSatisfy { $0.chordBandFrame.height < $0.chordWritingFrame.height })
    }

    func testRhythmDraftBatchRenderUsesMeasureLocalFirstMeasureSegmentFractions() throws {
        var chart = Chart.draft(title: "Rhythm First Segment", layoutStyle: .rhythmSectionSheet)
        chart.completeInitialSetup(
            title: "Rhythm First Segment",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 1,
            clef: .bass
        )
        let openMeasureID = try XCTUnwrap(chart.measures.first?.id)
        _ = chart.setMeasureManualLayoutWidth(240, for: openMeasureID)
        let pageSize = CGSize(width: 900, height: 1400)
        let sourceLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: pageSize,
            includesChordInkContinuationLanes: true
        )
        let sourceSystem = try XCTUnwrap(sourceLayout.systems.first)
        let sourceMeasure = try XCTUnwrap(sourceSystem.measures.first)
        let laneFrame = try XCTUnwrap(
            LeadSheetActiveInkScope.chordWritingSystemLaneFrame(
                for: sourceSystem,
                paperFrame: sourceLayout.paperFrame
            )
        )

        XCTAssertGreaterThan(sourceMeasure.frame.width, sourceMeasure.staffFrame.width)
        XCTAssertGreaterThan(laneFrame.width, sourceMeasure.staffFrame.width)

        let splitFraction = 0.4
        let rightChordFraction = 0.7
        let splitX = sourceMeasure.staffFrame.minX + sourceMeasure.staffFrame.width * CGFloat(splitFraction)
        let rightChordX = sourceMeasure.staffFrame.minX + sourceMeasure.staffFrame.width * CGFloat(rightChordFraction)
        let splitLaneFraction = Double((splitX - laneFrame.minX) / laneFrame.width)
        let rightChordLaneFraction = Double((rightChordX - laneFrame.minX) / laneFrame.width)
        XCTAssertLessThan(rightChordLaneFraction, splitFraction)

        var state = ChordPreviewState()
        state.layoutPageSize = pageSize
        state.replaceDraftChords(with: [
            draftInput(
                measureID: openMeasureID,
                measureIndex: sourceMeasure.index,
                fraction: rightChordFraction,
                bestCandidateText: "G",
                laneLocation: ChordInkDraftLaneLocation(systemIndex: sourceSystem.index, fraction: rightChordLaneFraction),
                layoutPageSize: pageSize
            )
        ])
        state.replaceDraftBarlines(with: [
            draftBarline(
                measureID: openMeasureID,
                measureIndex: sourceMeasure.index,
                fraction: splitFraction,
                laneLocation: ChordInkDraftLaneLocation(systemIndex: sourceSystem.index, fraction: splitLaneFraction),
                layoutPageSize: pageSize
            )
        ])

        let result = chart.commitChordInkDraftBatch(state)
        let leftMeasure = try XCTUnwrap(chart.measure(id: openMeasureID))
        let rightMeasureID = try XCTUnwrap(chart.measures.dropFirst().first?.id)
        let rightMeasure = try XCTUnwrap(chart.measure(id: rightMeasureID))

        XCTAssertEqual(result.renderedChordCount, 1)
        XCTAssertEqual(result.renderedBarlineCount, 1)
        XCTAssertEqual(chart.measures.count, 2)
        XCTAssertTrue(result.unresolvedDraftIDs.isEmpty)
        XCTAssertTrue(leftMeasure.chordEvents.isEmpty)
        XCTAssertEqual(rightMeasure.chordEvents.map { $0.symbol.displayText }, ["G"])
        XCTAssertEqual(
            try XCTUnwrap(leftMeasure.manualLayoutWidth),
            Double(sourceMeasure.staffFrame.width * CGFloat(splitFraction)),
            accuracy: 0.001
        )
        XCTAssertEqual(
            try XCTUnwrap(rightMeasure.manualLayoutWidth),
            Double(sourceMeasure.staffFrame.width * CGFloat(1 - splitFraction)),
            accuracy: 0.001
        )
    }

    func testRhythmDraftBatchRenderDefensivelyKeepsDraftInkWhenAnyDraftChordUnresolved() throws {
        var chart = Chart.draft(title: "Rhythm Unresolved Draft", layoutStyle: .rhythmSectionSheet)
        chart.completeInitialSetup(
            title: "Rhythm Unresolved Draft",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 1,
            clef: .bass
        )
        let openMeasureID = try XCTUnwrap(chart.measures.first?.id)
        let pageSize = CGSize(width: 900, height: 1400)
        let sourceLayout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: pageSize,
            includesChordInkContinuationLanes: true
        )
        let sourceMeasure = try XCTUnwrap(sourceLayout.systems.first?.measures.first)
        let unresolvedDrawingData = Data("rhythm-unresolved-target-ink".utf8)
        var state = ChordPreviewState()
        state.layoutPageSize = pageSize
        state.replaceDraftChords(with: [
            draftInput(
                measureID: openMeasureID,
                measureIndex: sourceMeasure.index,
                fraction: 0.2,
                bestCandidateText: "C",
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 0, fraction: 0.2),
                layoutPageSize: pageSize
            ),
            ChordInkDraftInput(
                measureID: openMeasureID,
                measureIndex: sourceMeasure.index,
                targetFraction: 0.6,
                visualOrder: nil,
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 0, fraction: 0.6),
                layoutPageSize: pageSize,
                drawingData: unresolvedDrawingData,
                candidateTexts: [],
                bestCandidateText: nil,
                confidence: 0,
                strokeCount: 2
            )
        ])

        XCTAssertTrue(chart.setPageHandwrittenChordDrawing(Data("rhythm-unresolved-draft-ink".utf8)))
        let result = chart.commitChordInkDraftBatch(state)

        XCTAssertEqual(result.renderedChordCount, 1)
        XCTAssertEqual(result.unresolvedDraftIDs.count, 1)
        XCTAssertEqual(chart.measures.first?.chordEvents.map { $0.symbol.displayText }, ["C"])
        XCTAssertNotNil(chart.pageHandwrittenChordData)
    }

    func testRhythmDraftBarlineDoesNotSplitCommittedMeasure() throws {
        var chart = Chart.draft(title: "Committed Rhythm Boundary", layoutStyle: .rhythmSectionSheet)
        chart.completeInitialSetup(
            title: "Committed Rhythm Boundary",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 2,
            clef: .bass
        )
        let committedMeasureID = try XCTUnwrap(chart.measures.first?.id)
        let originalIDs = chart.measures.map(\.id)
        let pageSize = CGSize(width: 900, height: 1400)
        var state = ChordPreviewState()
        state.layoutPageSize = pageSize
        state.replaceDraftBarlines(with: [
            draftBarline(
                measureID: committedMeasureID,
                measureIndex: 1,
                fraction: 0.52,
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 0, fraction: 0.26),
                layoutPageSize: pageSize
            )
        ])

        let result = chart.commitChordInkDraftBatch(state)

        XCTAssertEqual(result.renderedChordCount, 0)
        XCTAssertEqual(result.renderedBarlineCount, 0)
        XCTAssertTrue(result.unresolvedDraftIDs.isEmpty)
        XCTAssertEqual(chart.measures.map(\.id), originalIDs)
        XCTAssertEqual(chart.measure(id: committedMeasureID)?.authoringState, .committed)
    }

    func testDraftBatchRenderPreservesOpenLaneOrderWhenRightSideChordsShareMeasure() throws {
        var chart = Chart.draft(title: "Open Lane Order", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(
            title: "Open Lane Order",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 1
        )
        let openMeasureID = try XCTUnwrap(chart.measures.first?.id)

        var state = ChordPreviewState()
        state.replaceDraftChords(with: [
            draftInput(
                measureID: openMeasureID,
                measureIndex: 1,
                fraction: 0.12,
                bestCandidateText: "B-9",
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 0, fraction: 0.12)
            ),
            draftInput(
                measureID: openMeasureID,
                measureIndex: 1,
                fraction: 0.9999,
                bestCandidateText: "G7",
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 0, fraction: 0.72)
            ),
            draftInput(
                measureID: openMeasureID,
                measureIndex: 1,
                fraction: 0.9999,
                bestCandidateText: "A7sus",
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 0, fraction: 0.86)
            )
        ])

        let result = chart.commitChordInkDraftBatch(state)
        let renderedChords = chart.measures[0].chordEvents
        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: CGSize(width: 900, height: 1400)
        )
        let renderedLayouts = try XCTUnwrap(layout.systems.first?.measures.first?.chordLayouts)

        XCTAssertEqual(result.renderedChordCount, 3)
        XCTAssertEqual(renderedChords.map { $0.symbol.displayText }, ["B-9", "G7", "A7sus"])
        XCTAssertEqual(renderedChords.map { $0.manualLaneFraction ?? -1 }, [0.12, 0.72, 0.86])
        XCTAssertEqual(renderedLayouts.map(\.text), ["B-9", "G7", "A7sus"])
        XCTAssertLessThan(renderedLayouts[0].frame.minX, renderedLayouts[1].frame.minX)
        XCTAssertLessThan(renderedLayouts[1].frame.minX, renderedLayouts[2].frame.minX)
    }

    func testDraftBatchRenderMaterializesContinuationLaneForLowerLineChord() throws {
        var chart = Chart.draft(title: "Lower Lane Chord", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(
            title: "Lower Lane Chord",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 1
        )
        let openMeasureID = try XCTUnwrap(chart.measures.first(where: { $0.authoringState == .open })?.id)
        let pageSize = CGSize(width: 900, height: 1400)
        var state = ChordPreviewState()
        state.layoutPageSize = pageSize
        state.replaceDraftChords(with: [
            draftInput(
                measureID: openMeasureID,
                measureIndex: 1,
                fraction: 0.64,
                bestCandidateText: "D△7",
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 2, fraction: 0.64),
                layoutPageSize: pageSize
            )
        ])

        let result = chart.commitChordInkDraftBatch(state)
        let renderedLayout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize)
        let renderedChordSystemIndex = try XCTUnwrap(
            renderedLayout.systems.firstIndex { system in
                system.measures.contains { measure in
                    measure.chordLayouts.contains { $0.text == "D△7" }
                }
            }
        )

        XCTAssertEqual(result.renderedChordCount, 1)
        XCTAssertEqual(chart.systems.count, 3)
        XCTAssertEqual(renderedChordSystemIndex, 2)
        XCTAssertTrue(chart.systems[0].measures.allSatisfy(\.chordEvents.isEmpty))
        XCTAssertTrue(chart.systems[1].measures.allSatisfy(\.chordEvents.isEmpty))
        XCTAssertEqual(chart.systems[2].measures.first?.chordEvents.map { $0.symbol.displayText }, ["D△7"])
        let renderedLane = try XCTUnwrap(
            LeadSheetActiveInkScope.chordWritingSystemLaneFrame(
                for: renderedLayout.systems[2],
                paperFrame: renderedLayout.paperFrame
            )
        )
        let renderedChordLayout = try XCTUnwrap(renderedLayout.systems[2].measures.first?.chordLayouts.first)
        XCTAssertEqual(
            renderedChordLayout.frame.minX,
            renderedLane.minX + renderedLane.width * 0.64,
            accuracy: 8
        )
    }

    func testDraftBatchRenderKeepsDraftChordsOnSeparateContinuationLines() throws {
        var chart = Chart.draft(title: "Separate Lanes", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(
            title: "Separate Lanes",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 1
        )
        let openMeasureID = try XCTUnwrap(chart.measures.first(where: { $0.authoringState == .open })?.id)
        let pageSize = CGSize(width: 900, height: 1400)
        var state = ChordPreviewState()
        state.layoutPageSize = pageSize
        state.replaceDraftChords(with: [
            draftInput(
                measureID: openMeasureID,
                measureIndex: 1,
                fraction: 0.28,
                bestCandidateText: "C",
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 1, fraction: 0.28),
                layoutPageSize: pageSize
            ),
            draftInput(
                measureID: openMeasureID,
                measureIndex: 1,
                fraction: 0.72,
                bestCandidateText: "G7",
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 3, fraction: 0.72),
                layoutPageSize: pageSize
            )
        ])

        let result = chart.commitChordInkDraftBatch(state)

        XCTAssertEqual(result.renderedChordCount, 2)
        XCTAssertEqual(chart.systems.count, 4)
        XCTAssertEqual(chart.systems[1].measures.first?.chordEvents.map { $0.symbol.displayText }, ["C"])
        XCTAssertEqual(chart.systems[3].measures.first?.chordEvents.map { $0.symbol.displayText }, ["G7"])
        XCTAssertTrue(chart.systems[0].measures.allSatisfy(\.chordEvents.isEmpty))
        XCTAssertTrue(chart.systems[2].measures.allSatisfy(\.chordEvents.isEmpty))
    }

    func testDraftBatchRenderKeepsContinuationLaneBarlinesWithTheirLane() throws {
        var chart = Chart.draft(title: "Lane Barlines", layoutStyle: .simpleChordSheet)
        chart.completeInitialSetup(
            title: "Lane Barlines",
            key: .cMajor,
            meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine,
            startingMeasureCount: 1
        )
        let openMeasureID = try XCTUnwrap(chart.measures.first(where: { $0.authoringState == .open })?.id)
        let pageSize = CGSize(width: 900, height: 1400)
        var state = ChordPreviewState()
        state.layoutPageSize = pageSize
        state.replaceDraftChords(with: [
            draftInput(
                measureID: openMeasureID,
                measureIndex: 1,
                fraction: 0.12,
                bestCandidateText: "C",
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 0, fraction: 0.12),
                layoutPageSize: pageSize
            ),
            draftInput(
                measureID: openMeasureID,
                measureIndex: 1,
                fraction: 0.28,
                bestCandidateText: "D",
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 0, fraction: 0.28),
                layoutPageSize: pageSize
            ),
            draftInput(
                measureID: openMeasureID,
                measureIndex: 1,
                fraction: 0.42,
                bestCandidateText: "E",
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 0, fraction: 0.42),
                layoutPageSize: pageSize
            ),
            draftInput(
                measureID: openMeasureID,
                measureIndex: 1,
                fraction: 0.68,
                bestCandidateText: "F",
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 0, fraction: 0.68),
                layoutPageSize: pageSize
            ),
            draftInput(
                measureID: openMeasureID,
                measureIndex: 1,
                fraction: 0.20,
                bestCandidateText: "G",
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 1, fraction: 0.20),
                layoutPageSize: pageSize
            ),
            draftInput(
                measureID: openMeasureID,
                measureIndex: 1,
                fraction: 0.64,
                bestCandidateText: "A",
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 1, fraction: 0.64),
                layoutPageSize: pageSize
            )
        ])
        state.replaceDraftBarlines(with: [
            draftBarline(
                measureID: openMeasureID,
                measureIndex: 1,
                fraction: 0.50,
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 0, fraction: 0.50),
                layoutPageSize: pageSize
            ),
            draftBarline(
                measureID: openMeasureID,
                measureIndex: 1,
                fraction: 0.40,
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 1, fraction: 0.40),
                layoutPageSize: pageSize
            )
        ])

        let result = chart.commitChordInkDraftBatch(state)

        XCTAssertEqual(result.renderedChordCount, 6)
        XCTAssertEqual(result.renderedBarlineCount, 2)
        XCTAssertGreaterThanOrEqual(chart.systems.count, 2)
        XCTAssertEqual(
            chart.systems[0].measures.map { $0.chordEvents.map { $0.symbol.displayText } },
            [["C", "D", "E"], ["F"]]
        )
        XCTAssertEqual(
            chart.systems[1].measures.map { $0.chordEvents.map { $0.symbol.displayText } },
            [["G"], ["A"]]
        )
    }

    func testDraftBatchRenderResolvesLanePlacementAgainstCurrentMeasureGeometry() throws {
        var chart = Chart.blank(title: "Lane Insert", measureCount: 2, layoutStyle: .simpleChordSheet)
        let firstMeasureID = try XCTUnwrap(chart.measures.first?.id)
        let secondMeasureID = try XCTUnwrap(chart.measures.dropFirst().first?.id)
        _ = try XCTUnwrap(appendRecognizedChord("C", to: firstMeasureID, in: &chart))
        _ = try XCTUnwrap(appendRecognizedChord("G", to: secondMeasureID, in: &chart))

        let pageSize = CGSize(width: 900, height: 1400)
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: chart, pageSize: pageSize)
        let laneFrame = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingInputFrames(for: layout).first)
        let secondMeasureLayout = try XCTUnwrap(
            layout.systems.first?.measures.first(where: { $0.sourceMeasureID == secondMeasureID })
        )
        let laneFraction = Double((secondMeasureLayout.chordBandFrame.midX - laneFrame.minX) / laneFrame.width)

        var state = ChordPreviewState()
        state.replaceDraftChords(with: [
            draftInput(
                measureID: firstMeasureID,
                measureIndex: 1,
                fraction: 0.1,
                bestCandidateText: "F",
                laneLocation: ChordInkDraftLaneLocation(systemIndex: 0, fraction: laneFraction),
                layoutPageSize: pageSize
            )
        ])

        let result = chart.commitChordInkDraftBatch(state)

        XCTAssertEqual(result.renderedChordCount, 1)
        XCTAssertFalse(chart.measures[0].chordEvents.map { $0.symbol.displayText }.contains("F"))
        XCTAssertEqual(chart.measures[1].chordEvents.map { $0.symbol.displayText }, ["G", "F"])
    }

    func testDraftBatchRenderSplitsCommittedTerminalSpanBarline() throws {
        var chart = Chart.blank(title: "Terminal Span", measureCount: 6, layoutStyle: .simpleChordSheet)
        let measureIDs = chart.measures.map(\.id)
        XCTAssertTrue(chart.insertSimpleSystemBreak(before: measureIDs[4]))
        let pageSize = CGSize(width: 900, height: 1400)
        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: pageSize,
            includesChordInkContinuationLanes: true
        )
        let system = try XCTUnwrap(layout.systems.first)
        let rowEndMeasure = try XCTUnwrap(system.measures.last)
        let rowEndMeasureID = try XCTUnwrap(rowEndMeasure.sourceMeasureID)
        let laneFrame = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingInputFrames(for: layout).first)
        let terminalFrame = try XCTUnwrap(
            LeadSheetSimpleChordTerminalBarlineGeometry.barlineFrame(
                for: system,
                paperFrame: layout.paperFrame,
                layoutStyle: chart.layoutStyle
            )
        )
        let splitX = (rowEndMeasure.frame.maxX + terminalFrame.midX) / 2
        let splitFraction = Double((splitX - laneFrame.minX) / laneFrame.width)
        let laneLocation = ChordInkDraftLaneLocation(
            systemIndex: system.index,
            fraction: splitFraction
        )

        var state = ChordPreviewState()
        state.layoutPageSize = pageSize
        state.replaceDraftBarlines(with: [
            draftBarline(
                measureID: rowEndMeasureID,
                measureIndex: rowEndMeasure.index,
                fraction: splitFraction,
                laneLocation: laneLocation,
                layoutPageSize: pageSize
            )
        ])

        let result = chart.commitChordInkDraftBatch(state)

        XCTAssertEqual(result.renderedChordCount, 0)
        XCTAssertEqual(result.renderedBarlineCount, 1)
        XCTAssertTrue(result.unresolvedDraftIDs.isEmpty)
        XCTAssertEqual(chart.measures.count, 7)
        let leftMeasure = try XCTUnwrap(chart.measure(id: rowEndMeasureID))
        XCTAssertEqual(leftMeasure.barlineAfter, .single)
    }

    func testDraftBatchRenderSkipsTerminalBoundaryBarline() throws {
        var chart = Chart.blank(title: "Terminal Boundary", measureCount: 6, layoutStyle: .simpleChordSheet)
        let measureIDs = chart.measures.map(\.id)
        XCTAssertTrue(chart.insertSimpleSystemBreak(before: measureIDs[4]))
        let pageSize = CGSize(width: 900, height: 1400)
        let layout = LeadSheetPageLayoutEngine.pageLayout(
            for: chart,
            pageSize: pageSize,
            includesChordInkContinuationLanes: true
        )
        let system = try XCTUnwrap(layout.systems.first)
        let rowEndMeasure = try XCTUnwrap(system.measures.last)
        let rowEndMeasureID = try XCTUnwrap(rowEndMeasure.sourceMeasureID)
        let laneFrame = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingInputFrames(for: layout).first)
        let terminalFrame = try XCTUnwrap(
            LeadSheetSimpleChordTerminalBarlineGeometry.barlineFrame(
                for: system,
                paperFrame: layout.paperFrame,
                layoutStyle: chart.layoutStyle
            )
        )
        let terminalFraction = Double((terminalFrame.midX - laneFrame.minX) / laneFrame.width)
        let laneLocation = ChordInkDraftLaneLocation(
            systemIndex: system.index,
            fraction: terminalFraction
        )

        var state = ChordPreviewState()
        state.layoutPageSize = pageSize
        state.replaceDraftBarlines(with: [
            draftBarline(
                measureID: rowEndMeasureID,
                measureIndex: rowEndMeasure.index,
                fraction: terminalFraction,
                laneLocation: laneLocation,
                layoutPageSize: pageSize
            )
        ])

        let result = chart.commitChordInkDraftBatch(state)

        XCTAssertEqual(result.renderedChordCount, 0)
        XCTAssertEqual(result.renderedBarlineCount, 0)
        XCTAssertTrue(result.unresolvedDraftIDs.isEmpty)
        XCTAssertEqual(chart.measures.count, 6)
    }

    func testTelemetryAllowsOnlyAggregateDraftPreviewProperties() {
        let sanitized = IChartTelemetryPrivacy.sanitizedProperties([
            "draft_count": .int(2),
            "barline_count": .int(1),
            "rendered_count": .int(2),
            "unresolved_count": .int(0),
            "trusted_count": .int(1),
            "confirm_count": .int(1),
            "matched_count": .int(1),
            "no_read_count": .int(1),
            "close_race_count": .int(1),
            "generated_sequence_limit_count": .int(0),
            "raw_candidate_count": .int(4),
            "recognition_target_count": .int(2),
            "cluster_count": .int(3),
            "raw_chord_text": .string("Cmaj7"),
            "drawing_payload": .string("not allowed")
        ])

        XCTAssertEqual(sanitized["draft_count"], .int(2))
        XCTAssertEqual(sanitized["barline_count"], .int(1))
        XCTAssertEqual(sanitized["rendered_count"], .int(2))
        XCTAssertEqual(sanitized["unresolved_count"], .int(0))
        XCTAssertEqual(sanitized["trusted_count"], .int(1))
        XCTAssertEqual(sanitized["confirm_count"], .int(1))
        XCTAssertEqual(sanitized["matched_count"], .int(1))
        XCTAssertEqual(sanitized["no_read_count"], .int(1))
        XCTAssertEqual(sanitized["close_race_count"], .int(1))
        XCTAssertEqual(sanitized["generated_sequence_limit_count"], .int(0))
        XCTAssertEqual(sanitized["raw_candidate_count"], .int(4))
        XCTAssertEqual(sanitized["recognition_target_count"], .int(2))
        XCTAssertEqual(sanitized["cluster_count"], .int(3))
        XCTAssertNil(sanitized["raw_chord_text"])
        XCTAssertNil(sanitized["drawing_payload"])
        XCTAssertTrue(IChartTelemetryPrivacy.allowedEventNames.contains("chord.preview_updated"))
        XCTAssertTrue(IChartTelemetryPrivacy.allowedEventNames.contains("chord.preview_rendered"))
        XCTAssertTrue(IChartTelemetryPrivacy.allowedEventNames.contains("chord.preview_discarded"))
        XCTAssertTrue(IChartTelemetryPrivacy.allowedEventNames.contains("chord.draft_barline_added"))
    }

    private func draftInput(
        measureID: UUID,
        measureIndex: Int,
        fraction: Double,
        bestCandidateText: String,
        visualOrder: Double? = nil,
        laneLocation: ChordInkDraftLaneLocation? = nil,
        layoutPageSize: CGSize? = nil,
        drawingData: Data = Data("ink".utf8),
        confidence: Double = 4.2,
        strokeCount: Int = 2
    ) -> ChordInkDraftInput {
        ChordInkDraftInput(
            measureID: measureID,
            measureIndex: measureIndex,
            targetFraction: fraction,
            visualOrder: visualOrder,
            laneLocation: laneLocation,
            layoutPageSize: layoutPageSize,
            drawingData: drawingData,
            candidateTexts: [bestCandidateText],
            bestCandidateText: bestCandidateText,
            confidence: confidence,
            strokeCount: strokeCount
        )
    }

    private func draftBarline(
        measureID: UUID,
        measureIndex: Int,
        fraction: Double,
        laneLocation: ChordInkDraftLaneLocation? = nil,
        layoutPageSize: CGSize? = nil,
        sourceStrokeIndex: Int? = nil
    ) -> DraftBarline {
        DraftBarline(
            measureID: measureID,
            measureIndex: measureIndex,
            fraction: fraction,
            laneLocation: laneLocation,
            layoutPageSize: layoutPageSize,
            sourceStrokeIndex: sourceStrokeIndex,
            metrics: DraftBarlineGestureMetrics(
                height: 54,
                width: 2,
                angleDegreesFromVertical: 1,
                straightness: 0.98,
                laneCoverage: 0.9
            )
        )
    }

    private func appendRecognizedChord(_ text: String, to measureID: UUID, in chart: inout Chart) -> UUID? {
        guard let match = ChordRecognitionCompendium.match(text) else {
            return nil
        }

        return chart.appendRecognizedChordEvent(
            match.symbol,
            rawInput: text,
            to: measureID,
            atFraction: 0.1
        )
    }

    private func batchTarget(strokeCount: Int) -> LeadSheetChordInkRecognitionBatchTarget {
        let strokes = (0..<strokeCount).map { index in
            InkStroke(
                points: [
                    InkPoint(x: Double(index * 4), y: 0, timeOffset: nil),
                    InkPoint(x: Double(index * 4 + 12), y: 24, timeOffset: nil)
                ]
            )
        }
        return batchTarget(strokes: strokes)
    }

    private func batchTarget(strokes: [InkStroke]) -> LeadSheetChordInkRecognitionBatchTarget {
        return LeadSheetChordInkRecognitionBatchTarget(
            measureID: UUID(),
            fraction: 0.5,
            visualOrder: 0.5,
            laneLocation: nil,
            strokes: strokes,
            drawingData: Data(),
            drawing: PKDrawing()
        )
    }

    private static func pageLayout(measureID: UUID) -> LeadSheetPageLayout {
        let measure = LeadSheetMeasureLayout(
            id: measureID,
            sourceMeasureID: measureID,
            chordInkTargetMeasureID: measureID,
            index: 1,
            frame: CGRect(x: 90, y: 96, width: 220, height: 84),
            staffFrame: CGRect(x: 100, y: 112, width: 200, height: 56),
            chordBandFrame: CGRect(x: 104, y: 104, width: 192, height: 34),
            writableFrame: CGRect(x: 100, y: 104, width: 200, height: 64),
            chordLayouts: [],
            noteLayouts: [],
            repeatMarkerLayouts: [],
            cueTextLayouts: [],
            leadingBarline: nil,
            barlineAfter: .single,
            meterChange: nil,
            meterChangeFrame: nil,
            trailingBarlineFrame: CGRect(x: 300, y: 112, width: 1.6, height: 56),
            isOpen: false
        )
        let system = LeadSheetSystemLayout(
            id: UUID(),
            index: 0,
            frame: CGRect(x: 80, y: 90, width: 240, height: 100),
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
            measures: [measure]
        )
        return LeadSheetPageLayout(
            pageBounds: CGRect(x: 0, y: 0, width: 400, height: 400),
            paperFrame: CGRect(x: 20, y: 20, width: 360, height: 360),
            header: LeadSheetHeaderLayout(
                frame: CGRect(x: 40, y: 32, width: 320, height: 40),
                handwrittenFrame: CGRect(x: 40, y: 32, width: 320, height: 40),
                titleFrame: CGRect(x: 40, y: 32, width: 320, height: 40),
                composerFrame: nil,
                styleNoteFrame: nil,
                keyFrame: nil,
                meterFrame: nil
            ),
            systems: [system]
        )
    }

    private static func pkStroke(
        points: [CGPoint],
        pointSize: CGSize = CGSize(width: 3, height: 3)
    ) -> PKStroke {
        let controlPoints = points.enumerated().map { index, point in
            PKStrokePoint(
                location: point,
                timeOffset: TimeInterval(index) * 0.05,
                size: pointSize,
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        }
        return PKStroke(
            ink: PKInk(.pen, color: .black),
            path: PKStrokePath(controlPoints: controlPoints, creationDate: Date())
        )
    }

    private static func drawingData(strokes: [PKStroke]) -> Data {
        PKDrawing(strokes: strokes).dataRepresentation()
    }
}
#endif
