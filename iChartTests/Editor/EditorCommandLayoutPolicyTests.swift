import XCTest
@testable import iChart

final class EditorCommandLayoutPolicyTests: XCTestCase {
    func testQuickStartPreparesEnoughMeasuresForItsChordExercise() {
        XCTAssertEqual(IChartQuickStartSetupPolicy.minimumStartingMeasureCount, 4)
        XCTAssertEqual(
            IChartQuickStartSetupPolicy.initialMeasureCount(
                profileDefault: 1,
                isGuidedSimpleChart: true
            ),
            4
        )
        XCTAssertEqual(
            IChartQuickStartSetupPolicy.initialMeasureCount(
                profileDefault: 8,
                isGuidedSimpleChart: true
            ),
            8
        )
        XCTAssertEqual(
            IChartQuickStartSetupPolicy.initialMeasureCount(
                profileDefault: 1,
                isGuidedSimpleChart: false
            ),
            1
        )
    }

    func testQuickStartUsesEightOutcomeStepsInOneLinearPath() {
        let steps = IChartEditorGuidedTourStep.quickStartSteps

        XCTAssertEqual(
            steps,
            [
                .setup,
                .writeChords,
                .renderChords,
                .shapeForm,
                .addCue,
                .review,
                .export,
                .finish
            ]
        )
        XCTAssertEqual(steps.first?.progressText, "1 of 8")
        XCTAssertEqual(steps.last?.progressText, "8 of 8")

        for (step, nextStep) in zip(steps.dropLast(), steps.dropFirst()) {
            XCTAssertEqual(step.nextStep, nextStep)
        }
        XCTAssertNil(steps.last?.nextStep)
    }

    func testQuickStartKeepsOptionalExitAndCoreTargetsClear() {
        XCTAssertNil(IChartEditorGuidedTourStep.setup.forwardActionTitle)
        XCTAssertEqual(IChartEditorGuidedTourStep.writeChords.targetText, "Chords • write C, F, G, C")
        XCTAssertEqual(IChartEditorGuidedTourStep.shapeForm.targetText, "Measures • Add / Layout / Delete")
        XCTAssertEqual(IChartEditorGuidedTourStep.addCue.targetText, "Tools > Text")
        XCTAssertEqual(IChartEditorGuidedTourStep.export.forwardActionTitle, "Skip Export")
        XCTAssertEqual(IChartEditorGuidedTourStep.finish.forwardActionTitle, "Done")
    }

    func testNavigationUsesSymmetricColumnsSoTitleSharesTheToolStripAxis() {
        let availableWidth: CGFloat = 984
        let columnWidth = EditorCommandLayoutPolicy.navigationColumnWidth(
            for: availableWidth
        )

        XCTAssertEqual(EditorCommandLayoutPolicy.navigationColumnCount, 3)
        XCTAssertEqual(columnWidth, 328, accuracy: 0.001)
        XCTAssertEqual(columnWidth * 3, availableWidth, accuracy: 0.001)
        XCTAssertEqual(
            columnWidth + columnWidth / 2,
            availableWidth / 2,
            accuracy: 0.001
        )
        XCTAssertEqual(EditorCommandLayoutPolicy.navigationColumnWidth(for: -1), 0)
    }

    func testHeaderFieldReturnSequenceAdvancesThroughTheForm() {
        XCTAssertEqual(ChartHeaderTextInputField.allCases, [.title, .composerCredit, .styleNote])
        XCTAssertEqual(ChartHeaderTextInputField.title.next, .composerCredit)
        XCTAssertEqual(ChartHeaderTextInputField.composerCredit.next, .styleNote)
        XCTAssertNil(ChartHeaderTextInputField.styleNote.next)
    }

    func testPrimaryBarKeepsFrequentCommandsVisibleWithoutCrowding() {
        XCTAssertEqual(
            EditorCommandLayoutPolicy.primaryDestinations,
            [.select, .chords, .ink, .measures]
        )
        XCTAssertEqual(EditorCommandLayoutPolicy.primaryControlCount, 5)
        XCTAssertLessThanOrEqual(
            EditorCommandLayoutPolicy.primaryControlCount,
            EditorCommandLayoutPolicy.maximumPrimaryControlCount
        )
        XCTAssertGreaterThanOrEqual(EditorCommandLayoutPolicy.minimumTapTarget, 44)
    }

    func testEveryEditorSystemHasOneTopLevelPlacement() {
        let placements = Dictionary(
            uniqueKeysWithValues: EditorCommandDestination.allCases.map {
                ($0, EditorCommandLayoutPolicy.placement(of: $0))
            }
        )

        XCTAssertEqual(Set(placements.keys), Set(EditorCommandDestination.allCases))
        XCTAssertEqual(placements[.documentSettings], .documentMenu)
        XCTAssertEqual(placements[.select], .primaryBar)
        XCTAssertEqual(placements[.chords], .primaryBar)
        XCTAssertEqual(placements[.ink], .primaryBar)
        XCTAssertEqual(placements[.measures], .primaryBar)
        XCTAssertEqual(placements[.repeats], .toolsMenu)
        XCTAssertEqual(placements[.timeSignature], .toolsMenu)
        XCTAssertEqual(placements[.rhythm], .toolsMenu)
        XCTAssertEqual(placements[.text], .toolsMenu)
        XCTAssertEqual(placements[.formMarkers], .toolsMenu)
    }

    func testToolsMenuOnlyAddsRhythmWhenThatSystemShipsIt() {
        XCTAssertEqual(
            EditorCommandLayoutPolicy.toolsDestinations(includesDedicatedRhythmTool: false),
            [.repeats, .timeSignature, .text, .formMarkers]
        )
        XCTAssertEqual(
            EditorCommandLayoutPolicy.toolsDestinations(includesDedicatedRhythmTool: true),
            [.repeats, .timeSignature, .rhythm, .text, .formMarkers]
        )
    }

    func testFormMarkerMenuPreservesEveryShippedMarker() {
        XCTAssertEqual(
            RoadmapType.navigationPointMarkerTypes,
            [
                .codaMarker,
                .toCoda,
                .segno,
                .ds,
                .dsAlCoda,
                .dc,
                .dcAlFine,
                .fine,
                .noChord
            ]
        )
    }

    func testPrimaryModeSelectionAndToolsActivityAreUnambiguous() {
        XCTAssertEqual(EditorCommandLayoutPolicy.primaryDestination(for: .browse), .select)
        XCTAssertEqual(EditorCommandLayoutPolicy.primaryDestination(for: .noteEdit), .select)
        XCTAssertEqual(EditorCommandLayoutPolicy.primaryDestination(for: .measureEdit), .measures)
        XCTAssertEqual(EditorCommandLayoutPolicy.primaryDestination(for: .chordEntry), .chords)
        XCTAssertEqual(EditorCommandLayoutPolicy.primaryDestination(for: .freeHand), .ink)

        XCTAssertTrue(EditorCommandLayoutPolicy.isToolsMenuActive(for: .repeatEdit))
        XCTAssertTrue(EditorCommandLayoutPolicy.isToolsMenuActive(for: .timeSignatureEdit))
        XCTAssertTrue(EditorCommandLayoutPolicy.isToolsMenuActive(for: .rhythmicNotationEdit))
        XCTAssertTrue(EditorCommandLayoutPolicy.isToolsMenuActive(for: .textEdit))
        XCTAssertFalse(EditorCommandLayoutPolicy.isToolsMenuActive(for: .browse))
        XCTAssertFalse(EditorCommandLayoutPolicy.isToolsMenuActive(for: .chordEntry))
    }

    func testReadyChartAllowsOneTapSwitchingFromEveryMode() {
        let editorDestinations: [EditorCommandDestination] = [
            .select,
            .chords,
            .ink,
            .measures,
            .repeats,
            .timeSignature,
            .rhythm,
            .text,
            .formMarkers
        ]

        for mode in EditorCanvasMode.allUITestCases {
            for destination in editorDestinations {
                XCTAssertTrue(
                    EditorCommandLayoutPolicy.canActivate(
                        destination,
                        chartIsReady: true,
                        from: mode
                    ),
                    "Expected one-tap switch from \(mode) to \(destination)"
                )
            }
        }
    }

    func testDocumentSettingsStayLockedOnlyDuringInkCriticalModes() {
        XCTAssertFalse(
            EditorCommandLayoutPolicy.canActivate(
                .documentSettings,
                chartIsReady: true,
                from: .chordEntry
            )
        )
        XCTAssertFalse(
            EditorCommandLayoutPolicy.canActivate(
                .documentSettings,
                chartIsReady: true,
                from: .freeHand
            )
        )
        XCTAssertTrue(
            EditorCommandLayoutPolicy.canActivate(
                .documentSettings,
                chartIsReady: true,
                from: .browse
            )
        )
    }
}

private extension EditorCanvasMode {
    static let allUITestCases: [EditorCanvasMode] = [
        .browse,
        .measureEdit,
        .repeatEdit,
        .timeSignatureEdit,
        .rhythmicNotationEdit,
        .headerEntry,
        .chordEntry,
        .noteEdit,
        .freeHand,
        .textEdit
    ]
}
