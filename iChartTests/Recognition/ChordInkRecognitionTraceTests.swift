import XCTest
@testable import iChart

final class ChordInkRecognitionTraceTests: XCTestCase {
    func testProvidedDeviceTraceHasNoStabilityIssues() throws {
        guard let tracePath = ProcessInfo.processInfo.environment["ICHART_CHORD_DRAFT_TRACE_FILE"],
              !tracePath.isEmpty else {
            throw XCTSkip("Set ICHART_CHORD_DRAFT_TRACE_FILE to run a pulled iPad draft-recognition trace.")
        }

        let recorder = ChordDraftPreviewDeviceDiagnosticRecorder(
            url: URL(fileURLWithPath: tracePath)
        )
        let events = try recorder.loadEvents()
        let trace = ChordInkRecognitionTrace(events: events)

        XCTAssertFalse(events.isEmpty)
        XCTAssertFalse(trace.passes.isEmpty)
        XCTAssertEqual(trace.stabilityIssues, [])
    }

    func testProvidedDeviceTraceSurfacesExpectedCloseRaceObservations() throws {
        guard ProcessInfo.processInfo.environment["ICHART_CHORD_DRAFT_TRACE_EXPECT_CLOSE_RACE_OBSERVATION"] == "1" else {
            throw XCTSkip("Set ICHART_CHORD_DRAFT_TRACE_EXPECT_CLOSE_RACE_OBSERVATION=1 for a trace with known close-race volatility.")
        }
        guard let tracePath = ProcessInfo.processInfo.environment["ICHART_CHORD_DRAFT_TRACE_FILE"],
              !tracePath.isEmpty else {
            throw XCTSkip("Set ICHART_CHORD_DRAFT_TRACE_FILE to run a pulled iPad draft-recognition trace.")
        }

        let recorder = ChordDraftPreviewDeviceDiagnosticRecorder(
            url: URL(fileURLWithPath: tracePath)
        )
        let trace = ChordInkRecognitionTrace(events: try recorder.loadEvents())
        let closeRaceObservations = trace.observations.filter { observation in
            observation.kind == .closeRacePrimaryCandidateChanged
        }

        XCTAssertFalse(closeRaceObservations.isEmpty)
    }

    func testProvidedDeviceTraceExportsFixtureWhenConfigured() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let tracePath = environment["ICHART_CHORD_DRAFT_TRACE_FILE"],
              !tracePath.isEmpty else {
            throw XCTSkip("Set ICHART_CHORD_DRAFT_TRACE_FILE to run a pulled iPad draft-recognition trace.")
        }
        guard let expectedDisplayText = environment["ICHART_CHORD_DRAFT_TRACE_EXPORT_EXPECTED"],
              !expectedDisplayText.isEmpty,
              let passIndexText = environment["ICHART_CHORD_DRAFT_TRACE_EXPORT_PASS_INDEX"],
              let passIndex = Int(passIndexText),
              let targetIndexText = environment["ICHART_CHORD_DRAFT_TRACE_EXPORT_TARGET_INDEX"],
              let targetIndex = Int(targetIndexText) else {
            throw XCTSkip("Set trace fixture export expected text, pass index, and target index to export a replayable fixture.")
        }

        let recorder = ChordDraftPreviewDeviceDiagnosticRecorder(
            url: URL(fileURLWithPath: tracePath)
        )
        let trace = ChordInkRecognitionTrace(events: try recorder.loadEvents())
        let json = try XCTUnwrap(
            try trace.fixtureJSONString(
                passIndex: passIndex,
                targetIndex: targetIndex,
                expectedDisplayText: expectedDisplayText,
                name: environment["ICHART_CHORD_DRAFT_TRACE_EXPORT_NAME"]
            )
        )
        let decoded = try JSONDecoder().decode(InkFixtureDocument.self, from: Data(json.utf8))

        if let outputPath = environment["ICHART_CHORD_DRAFT_TRACE_EXPORT_OUTPUT"],
           !outputPath.isEmpty {
            try json.write(
                to: URL(fileURLWithPath: outputPath),
                atomically: true,
                encoding: .utf8
            )
        } else {
            print("ICHART_TRACE_FIXTURE_JSON_BEGIN\n\(json)\nICHART_TRACE_FIXTURE_JSON_END")
        }

        XCTAssertEqual(
            decoded.expectedDisplayText,
            ChordRecognitionCompendium.match(expectedDisplayText)?.displayText
        )
        XCTAssertFalse(decoded.strokes.isEmpty)
    }

    func testBuildsPassesFromDeviceDiagnosticEvents() {
        let dTarget = target(index: 0, fraction: 0.08, strokeBounds: dStrokeBounds)
        let dMinorTarget = target(index: 1, fraction: 0.22, strokeBounds: dMinor7StrokeBounds)
        let events = [
            event(stage: "single_target", targets: [dTarget]),
            event(stage: "finish_single", payloads: [
                payload(index: 0, raw: ["D"], supported: ["D"], match: "D", accepted: nil)
            ]),
            event(stage: "preview_replace", replacements: [
                replacement(index: 0, previousText: nil, newText: "D", previousRenderable: nil, newRenderable: true)
            ]),
            event(stage: "targeting", boundedBatchTargetCount: 2, targets: [dTarget, dMinorTarget]),
            event(stage: "finish_batch", payloads: [
                payload(index: 0, raw: ["D"], supported: ["D"], match: "D", accepted: nil),
                payload(index: 1, raw: ["D-7"], supported: ["D-7"], match: "D-7", accepted: nil)
            ]),
            event(stage: "preview_replace", replacements: [
                replacement(index: 0, previousText: "D", newText: "D", previousRenderable: true, newRenderable: true),
                replacement(index: 1, previousText: nil, newText: "D-7", previousRenderable: nil, newRenderable: true)
            ])
        ]

        let passes = ChordInkRecognitionTrace(events: events).passes

        XCTAssertEqual(passes.map(\.kind), [.singleTarget, .batch])
        XCTAssertEqual(passes[0].targets.map(\.targetIndex), [0])
        XCTAssertEqual(passes[0].payloads.map(\.matchText), ["D"])
        XCTAssertEqual(passes[0].replacements.map(\.newPreviewText), ["D"])
        XCTAssertEqual(passes[1].targets.map(\.targetIndex), [0, 1])
        XCTAssertEqual(passes[1].payloads.map(\.matchText), ["D", "D-7"])
        XCTAssertEqual(passes[1].replacements.map(\.newPreviewText), ["D", "D-7"])
    }

    func testDetectsBatchReplayDroppingPreviouslyReadableTarget() {
        let dTarget = target(index: 0, fraction: 0.08, strokeBounds: dStrokeBounds)
        let dMinorTarget = target(index: 1, fraction: 0.22, strokeBounds: dMinor7StrokeBounds)
        let trace = ChordInkRecognitionTrace(events: [
            event(stage: "single_target", targets: [dTarget]),
            event(stage: "finish_single", payloads: [
                payload(index: 0, raw: ["D"], supported: ["D"], match: "D", accepted: nil)
            ]),
            event(stage: "preview_replace", replacements: [
                replacement(index: 0, previousText: nil, newText: "D", previousRenderable: nil, newRenderable: true)
            ]),
            event(stage: "targeting", boundedBatchTargetCount: 2, targets: [dTarget, dMinorTarget]),
            event(stage: "finish_batch", payloads: [
                payload(index: 0, raw: ["B", "+", "9"], supported: [], match: nil, accepted: nil),
                payload(index: 1, raw: ["D-7"], supported: ["D-7"], match: "D-7", accepted: nil)
            ]),
            event(stage: "preview_replace", replacements: [
                replacement(index: 0, previousText: "D", newText: nil, previousRenderable: true, newRenderable: false),
                replacement(index: 1, previousText: nil, newText: "D-7", previousRenderable: nil, newRenderable: true)
            ])
        ])

        let issues = trace.stabilityIssues

        XCTAssertEqual(
            issues.map(\.kind),
            [.previewDroppedRenderableRead, .batchTargetLostSupportedRead]
        )
        XCTAssertEqual(issues.map(\.passIndex), [1, 1])
        XCTAssertEqual(issues.map(\.targetIndex), [0, 0])
        XCTAssertEqual(issues.map(\.previousText), ["D", "D"])
    }

    func testAcceptsStableBatchReplayForPreviouslyReadableTarget() {
        let dTarget = target(index: 0, fraction: 0.08, strokeBounds: dStrokeBounds)
        let dMinorTarget = target(index: 1, fraction: 0.22, strokeBounds: dMinor7StrokeBounds)
        let trace = ChordInkRecognitionTrace(events: [
            event(stage: "single_target", targets: [dTarget]),
            event(stage: "finish_single", payloads: [
                payload(index: 0, raw: ["D"], supported: ["D"], match: "D", accepted: nil)
            ]),
            event(stage: "preview_replace", replacements: [
                replacement(index: 0, previousText: nil, newText: "D", previousRenderable: nil, newRenderable: true)
            ]),
            event(stage: "targeting", boundedBatchTargetCount: 2, targets: [dTarget, dMinorTarget]),
            event(stage: "finish_batch", payloads: [
                payload(index: 0, raw: ["D", "B", "F"], supported: ["D"], match: "D", accepted: nil),
                payload(index: 1, raw: ["D-7", "B-7"], supported: ["D-7", "B-7"], match: "D-7", accepted: nil)
            ]),
            event(stage: "preview_replace", replacements: [
                replacement(index: 0, previousText: "D", newText: "D", previousRenderable: true, newRenderable: true),
                replacement(index: 1, previousText: nil, newText: "D-7", previousRenderable: nil, newRenderable: true)
            ])
        ])

        XCTAssertEqual(trace.stabilityIssues, [])
    }

    func testDetectsDetachedTargetAbsorbingPreviouslyReadableTarget() {
        let cBounds = [
            bounds(minX: 193.9, minY: 52.1, width: 25.1, height: 30.9)
        ]
        let cPlusDetachedD = cBounds + [
            bounds(minX: 281.3, minY: 60.9, width: 0.7, height: 19.2),
            bounds(minX: 275.5, minY: 54.0, width: 32.8, height: 31.6)
        ]
        let trace = ChordInkRecognitionTrace(events: [
            event(
                stage: "targeting",
                boundedBatchTargetCount: 3,
                targets: [target(index: 2, fraction: 0.33, strokeBounds: cBounds)],
                timestampOffset: 10
            ),
            event(stage: "finish_batch", payloads: [
                payload(
                    index: 2,
                    fraction: 0.33,
                    strokeCount: cBounds.count,
                    raw: ["C"],
                    supported: ["C"],
                    match: "C",
                    accepted: "C"
                )
            ], timestampOffset: 11),
            event(stage: "preview_replace", replacements: [
                replacement(index: 2, previousText: nil, newText: "C", previousRenderable: nil, newRenderable: true)
            ], timestampOffset: 12),
            event(
                stage: "targeting",
                boundedBatchTargetCount: 3,
                targets: [target(index: 2, fraction: 0.40, strokeBounds: cPlusDetachedD)],
                timestampOffset: 13
            ),
            event(stage: "finish_batch", payloads: [
                payload(
                    index: 2,
                    fraction: 0.40,
                    strokeCount: cPlusDetachedD.count,
                    raw: ["CB", "C△", "GB", "G△"],
                    supported: ["Cb", "C△", "Gb", "G△"],
                    match: "Cb",
                    accepted: "Cb",
                    action: "confirm",
                    reason: "Low-confidence read. Choose a suggestion or type the chord you meant.",
                    confidence: 3.86
                )
            ], timestampOffset: 14),
            event(stage: "preview_replace", replacements: [
                replacement(index: 2, previousText: nil, newText: "Cb", previousRenderable: nil, newRenderable: true)
            ], timestampOffset: 15)
        ])

        let issues = trace.stabilityIssues

        XCTAssertEqual(issues.map(\.kind), [.targetAbsorbedPreviouslyReadableRead])
        XCTAssertEqual(issues.map(\.passIndex), [1])
        XCTAssertEqual(issues.map(\.targetIndex), [2])
        XCTAssertEqual(issues.map(\.previousText), ["C"])
        XCTAssertEqual(issues.map(\.newText), ["Cb"])
    }

    func testAllowsAttachedAccidentalToExtendPreviousRootTarget() {
        let cBounds = [
            bounds(minX: 10, minY: 20, width: 24, height: 32)
        ]
        let cWithAttachedFlat = cBounds + [
            bounds(minX: 39, minY: 12, width: 10, height: 30)
        ]
        let trace = ChordInkRecognitionTrace(events: [
            event(
                stage: "targeting",
                boundedBatchTargetCount: 1,
                targets: [target(index: 0, fraction: 0.08, strokeBounds: cBounds)],
                timestampOffset: 10
            ),
            event(stage: "finish_batch", payloads: [
                payload(
                    index: 0,
                    fraction: 0.08,
                    strokeCount: cBounds.count,
                    raw: ["C"],
                    supported: ["C"],
                    match: "C",
                    accepted: "C"
                )
            ], timestampOffset: 11),
            event(
                stage: "targeting",
                boundedBatchTargetCount: 1,
                targets: [target(index: 0, fraction: 0.08, strokeBounds: cWithAttachedFlat)],
                timestampOffset: 12
            ),
            event(stage: "finish_batch", payloads: [
                payload(
                    index: 0,
                    fraction: 0.08,
                    strokeCount: cWithAttachedFlat.count,
                    raw: ["CB"],
                    supported: ["Cb"],
                    match: "Cb",
                    accepted: "Cb"
                )
            ], timestampOffset: 13)
        ])

        XCTAssertEqual(trace.stabilityIssues, [])
    }

    func testAllowsDetachedTargetAbsorptionWhenInkCompletesLegalSameChordSuffix() {
        let abSusBounds = [
            bounds(minX: 10, minY: 20, width: 18, height: 42),
            bounds(minX: 34, minY: 28, width: 16, height: 34),
            bounds(minX: 58, minY: 30, width: 18, height: 32),
            bounds(minX: 82, minY: 26, width: 18, height: 36),
            bounds(minX: 106, minY: 26, width: 18, height: 36),
            bounds(minX: 130, minY: 30, width: 18, height: 32)
        ]
        let abSus4Bounds = abSusBounds + [
            bounds(minX: 190, minY: 18, width: 24, height: 48)
        ]
        let trace = ChordInkRecognitionTrace(events: [
            event(
                stage: "targeting",
                boundedBatchTargetCount: 1,
                targets: [target(index: 0, fraction: 0.32, strokeBounds: abSusBounds)],
                timestampOffset: 10
            ),
            event(stage: "finish_batch", payloads: [
                payload(
                    index: 0,
                    fraction: 0.32,
                    strokeCount: abSusBounds.count,
                    raw: ["Absus", "Bbsus"],
                    supported: ["Absus", "Bbsus"],
                    match: "Absus",
                    accepted: "Absus"
                )
            ], timestampOffset: 11),
            event(
                stage: "targeting",
                boundedBatchTargetCount: 1,
                targets: [target(index: 0, fraction: 0.32, strokeBounds: abSus4Bounds)],
                timestampOffset: 12
            ),
            event(stage: "finish_batch", payloads: [
                payload(
                    index: 0,
                    fraction: 0.32,
                    strokeCount: abSus4Bounds.count,
                    raw: ["Absus4"],
                    supported: ["Absus4"],
                    match: "Absus4",
                    accepted: "Absus4"
                )
            ], timestampOffset: 13)
        ])

        XCTAssertEqual(trace.stabilityIssues, [])
    }

    func testObservesCloseRacePrimaryCandidateChangeForSameBatchTargetSlot() {
        let firstSlashTarget = target(index: 3, fraction: 0.696, strokeBounds: dSlashFSharpStrokeBounds)
        let secondSlashTarget = target(index: 3, fraction: 0.689, strokeBounds: dSlashFSharpStrokeBounds)
        let trace = ChordInkRecognitionTrace(events: [
            event(stage: "targeting", boundedBatchTargetCount: 4, targets: [firstSlashTarget]),
            event(stage: "finish_batch", payloads: [
                payload(
                    index: 3,
                    fraction: 0.696,
                    strokeCount: dSlashFSharpStrokeBounds.count,
                    raw: ["B/F#", "D/F#", "B/B#", "D/B#"],
                    supported: ["B/F#", "D/F#", "B/B#", "D/B#"],
                    match: "B/F#",
                    accepted: "B/F#",
                    action: "confirm",
                    reason: "Close race. Choose the chord you meant, or type it in.",
                    confidence: 4.94,
                    closeRace: true,
                    confidenceGap: 0.007
                )
            ]),
            event(stage: "preview_replace", replacements: [
                replacement(index: 3, previousText: nil, newText: "B/F#", previousRenderable: nil, newRenderable: true)
            ]),
            event(stage: "targeting", boundedBatchTargetCount: 4, targets: [secondSlashTarget]),
            event(stage: "finish_batch", payloads: [
                payload(
                    index: 3,
                    fraction: 0.689,
                    strokeCount: dSlashFSharpStrokeBounds.count,
                    raw: ["D/F#", "B/F#", "D/B#", "B/B#"],
                    supported: ["D/F#", "B/F#", "D/B#", "B/B#"],
                    match: "D/F#",
                    accepted: "D/F#",
                    action: "confirm",
                    reason: "Close race. Choose the chord you meant, or type it in.",
                    confidence: 4.93,
                    closeRace: true,
                    confidenceGap: 0.009
                )
            ]),
            event(stage: "preview_replace", replacements: [
                replacement(index: 3, previousText: "B/F#", newText: "D/F#", previousRenderable: true, newRenderable: true)
            ])
        ])

        let observations = trace.observations

        XCTAssertEqual(trace.stabilityIssues, [])
        XCTAssertEqual(observations.map(\.kind), [.closeRacePrimaryCandidateChanged])
        XCTAssertEqual(observations.map(\.passIndex), [1])
        XCTAssertEqual(observations.map(\.targetIndex), [3])
        XCTAssertEqual(observations.map(\.previousText), ["B/F#"])
        XCTAssertEqual(observations.map(\.newText), ["D/F#"])
        XCTAssertTrue(observations[0].details.contains("root descriptor B -> D"))
    }

    func testDoesNotObserveStableCloseRaceCandidate() {
        let target = target(index: 1, fraction: 0.22, strokeBounds: dMinor7StrokeBounds)
        let trace = ChordInkRecognitionTrace(events: [
            event(stage: "targeting", boundedBatchTargetCount: 2, targets: [target]),
            event(stage: "finish_batch", payloads: [
                payload(
                    index: 1,
                    raw: ["D-7", "B-7"],
                    supported: ["D-7", "B-7"],
                    match: "D-7",
                    accepted: "D-7",
                    action: "confirm",
                    reason: "Close race. Choose the chord you meant, or type it in.",
                    confidence: 4.18,
                    closeRace: true,
                    confidenceGap: 0.02
                )
            ]),
            event(stage: "preview_replace", replacements: [
                replacement(index: 1, previousText: nil, newText: "D-7", previousRenderable: nil, newRenderable: true)
            ]),
            event(stage: "targeting", boundedBatchTargetCount: 2, targets: [target]),
            event(stage: "finish_batch", payloads: [
                payload(
                    index: 1,
                    raw: ["D-7", "B-7"],
                    supported: ["D-7", "B-7"],
                    match: "D-7",
                    accepted: "D-7",
                    action: "confirm",
                    reason: "Close race. Choose the chord you meant, or type it in.",
                    confidence: 4.18,
                    closeRace: true,
                    confidenceGap: 0.02
                )
            ]),
            event(stage: "preview_replace", replacements: [
                replacement(index: 1, previousText: "D-7", newText: "D-7", previousRenderable: true, newRenderable: true)
            ])
        ])

        XCTAssertEqual(trace.observations, [])
        XCTAssertEqual(trace.stabilityIssues, [])
    }

    func testDoesNotCompareCloseRaceCandidatesAcrossReset() {
        let target = target(index: 3, fraction: 0.69, strokeBounds: dSlashFSharpStrokeBounds)
        let trace = ChordInkRecognitionTrace(events: [
            event(stage: "targeting", boundedBatchTargetCount: 4, targets: [target], timestampOffset: 10),
            event(stage: "finish_batch", payloads: [
                payload(
                    index: 3,
                    fraction: 0.69,
                    strokeCount: dSlashFSharpStrokeBounds.count,
                    raw: ["B/F#", "D/F#"],
                    supported: ["B/F#", "D/F#"],
                    match: "B/F#",
                    accepted: "B/F#",
                    action: "confirm",
                    reason: "Close race. Choose the chord you meant, or type it in.",
                    closeRace: true,
                    confidenceGap: 0.007
                )
            ], timestampOffset: 11),
            event(stage: "preview_replace", replacements: [
                replacement(index: 3, previousText: nil, newText: "B/F#", previousRenderable: nil, newRenderable: true)
            ], timestampOffset: 12),
            event(stage: "reset", timestampOffset: 13),
            event(stage: "targeting", boundedBatchTargetCount: 4, targets: [target], timestampOffset: 14),
            event(stage: "finish_batch", payloads: [
                payload(
                    index: 3,
                    fraction: 0.69,
                    strokeCount: dSlashFSharpStrokeBounds.count,
                    raw: ["D/F#", "B/F#"],
                    supported: ["D/F#", "B/F#"],
                    match: "D/F#",
                    accepted: "D/F#",
                    action: "confirm",
                    reason: "Close race. Choose the chord you meant, or type it in.",
                    closeRace: true,
                    confidenceGap: 0.009
                )
            ], timestampOffset: 15),
            event(stage: "preview_replace", replacements: [
                replacement(index: 3, previousText: nil, newText: "D/F#", previousRenderable: nil, newRenderable: true)
            ], timestampOffset: 16)
        ])

        XCTAssertEqual(trace.observations, [])
        XCTAssertEqual(trace.stabilityIssues, [])
    }

    func testBuildsReplayableTargetsFromDiagnosticInkStrokes() throws {
        let targetStroke = InkStroke(points: [
            InkPoint(x: 10, y: 20, timeOffset: 0),
            InkPoint(x: 20, y: 30, timeOffset: 0.1)
        ])
        let payloadStroke = InkStroke(points: [
            InkPoint(x: 230, y: 32, timeOffset: 0),
            InkPoint(x: 247, y: 88, timeOffset: 0.1),
            InkPoint(x: 262, y: 34, timeOffset: 0.2)
        ])
        let trace = ChordInkRecognitionTrace(events: [
            event(
                stage: "targeting",
                boundedBatchTargetCount: 3,
                targets: [
                    target(
                        index: 2,
                        fraction: 0.43,
                        strokeBounds: dSlashFSharpStrokeBounds,
                        inkStrokes: [targetStroke]
                    )
                ]
            ),
            event(stage: "finish_batch", payloads: [
                payload(
                    index: 2,
                    fraction: 0.43,
                    strokeCount: dSlashFSharpStrokeBounds.count,
                    raw: ["B/F#", "D/F#"],
                    supported: ["B/F#", "D/F#"],
                    match: "B/F#",
                    accepted: "B/F#",
                    action: "confirm",
                    reason: "Ambiguous root read. Choose a suggestion or type the chord you meant.",
                    closeRace: true,
                    confidenceGap: 0.011,
                    inkStrokes: [payloadStroke]
                )
            ])
        ])

        let replayable = try XCTUnwrap(trace.replayableTargets.first)

        XCTAssertEqual(replayable.passIndex, 0)
        XCTAssertEqual(replayable.passKind, .batch)
        XCTAssertEqual(replayable.targetIndex, 2)
        XCTAssertEqual(replayable.recognizedDisplayText, "B/F#")
        XCTAssertEqual(replayable.action, "confirm")
        XCTAssertEqual(replayable.supportedCandidates, ["B/F#", "D/F#"])
        XCTAssertEqual(replayable.strokes, [payloadStroke])
    }

    func testReplayableTargetFixtureExportUsesSuppliedIntendedChord() throws {
        let stroke = InkStroke(points: [
            InkPoint(x: 230, y: 32, timeOffset: 0),
            InkPoint(x: 247, y: 88, timeOffset: 0.1),
            InkPoint(x: 262, y: 34, timeOffset: 0.2)
        ])
        let trace = ChordInkRecognitionTrace(events: [
            event(
                stage: "targeting",
                boundedBatchTargetCount: 3,
                targets: [
                    target(
                        index: 2,
                        fraction: 0.43,
                        strokeBounds: dSlashFSharpStrokeBounds,
                        inkStrokes: [stroke]
                    )
                ]
            ),
            event(stage: "finish_batch", payloads: [
                payload(
                    index: 2,
                    fraction: 0.43,
                    strokeCount: dSlashFSharpStrokeBounds.count,
                    raw: ["B/F#", "D/F#"],
                    supported: ["B/F#", "D/F#"],
                    match: "B/F#",
                    accepted: "B/F#",
                    action: "confirm",
                    reason: "Ambiguous root read. Choose a suggestion or type the chord you meant.",
                    closeRace: true,
                    confidenceGap: 0.011,
                    inkStrokes: [stroke]
                )
            ])
        ])

        let document = try XCTUnwrap(
            try trace.fixtureDocument(
                passIndex: 0,
                targetIndex: 2,
                expectedDisplayText: "D/F#",
                name: "DSlashFSharpLooseDevice01"
            )
        )
        let json = try XCTUnwrap(
            try trace.fixtureJSONString(
                passIndex: 0,
                targetIndex: 2,
                expectedDisplayText: "D/F#",
                name: "DSlashFSharpLooseDevice01"
            )
        )

        XCTAssertEqual(document.name, "DSlashFSharpLooseDevice01")
        XCTAssertEqual(document.expectedDisplayText, "D/F#")
        XCTAssertEqual(document.expectedTopGlyphs, ["D", "/", "F", "#"])
        XCTAssertEqual(document.strokes, [stroke])

        let decoded = try JSONDecoder().decode(InkFixtureDocument.self, from: Data(json.utf8))
        XCTAssertEqual(decoded, document)
    }

    func testTraceWithoutInkStrokesHasNoReplayableTargets() {
        let trace = ChordInkRecognitionTrace(events: [
            event(stage: "targeting", boundedBatchTargetCount: 1, targets: [
                target(index: 0, fraction: 0.08, strokeBounds: dStrokeBounds)
            ]),
            event(stage: "finish_batch", payloads: [
                payload(index: 0, raw: ["D"], supported: ["D"], match: "D", accepted: "D")
            ])
        ])

        XCTAssertEqual(trace.replayableTargets, [])
        XCTAssertNil(
            try trace.fixtureDocument(
                passIndex: 0,
                targetIndex: 0,
                expectedDisplayText: "D"
            )
        )
    }

    private var measureID: UUID {
        UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    }

    private var dStrokeBounds: [ChordDraftPreviewDeviceDiagnosticBounds] {
        [
            bounds(minX: 10, minY: 20, width: 18, height: 42)
        ]
    }

    private var dMinor7StrokeBounds: [ChordDraftPreviewDeviceDiagnosticBounds] {
        [
            bounds(minX: 70, minY: 20, width: 18, height: 42),
            bounds(minX: 96, minY: 34, width: 18, height: 2),
            bounds(minX: 120, minY: 12, width: 8, height: 16)
        ]
    }

    private var dSlashFSharpStrokeBounds: [ChordDraftPreviewDeviceDiagnosticBounds] {
        [
            bounds(minX: 386, minY: 30, width: 16, height: 66),
            bounds(minX: 400, minY: 31, width: 24, height: 64),
            bounds(minX: 432, minY: 38, width: 3, height: 48),
            bounds(minX: 446, minY: 61, width: 10, height: 2),
            bounds(minX: 462, minY: 44, width: 20, height: 2),
            bounds(minX: 465, minY: 35, width: 2, height: 28),
            bounds(minX: 475, minY: 34, width: 2, height: 28),
            bounds(minX: 486, minY: 42, width: 20, height: 2),
            bounds(minX: 492, minY: 33, width: 2, height: 28),
            bounds(minX: 501, minY: 33, width: 2, height: 28)
        ]
    }

    private func event(
        stage: String,
        boundedBatchTargetCount: Int? = nil,
        targets: [ChordDraftPreviewDeviceDiagnosticTarget] = [],
        payloads: [ChordDraftPreviewDeviceDiagnosticPayload] = [],
        replacements: [ChordDraftPreviewDeviceDiagnosticReplacement] = [],
        timestampOffset: TimeInterval = 10
    ) -> ChordDraftPreviewDeviceDiagnosticEvent {
        ChordDraftPreviewDeviceDiagnosticEvent(
            timestamp: Date(timeIntervalSinceReferenceDate: timestampOffset),
            stage: stage,
            flow: "draft_preview",
            boundedBatchTargetCount: boundedBatchTargetCount,
            payloadCount: payloads.isEmpty ? nil : payloads.count,
            candidatePayloadCount: payloads.filter { !$0.supportedCandidates.isEmpty }.count,
            draftCount: replacements.isEmpty ? nil : replacements.count,
            unresolvedDraftCount: replacements.filter { $0.newRenderable != true }.count,
            targets: targets,
            payloads: payloads,
            replacements: replacements
        )
    }

    private func target(
        index: Int,
        fraction: Double,
        strokeBounds: [ChordDraftPreviewDeviceDiagnosticBounds],
        inkStrokes: [InkStroke]? = nil
    ) -> ChordDraftPreviewDeviceDiagnosticTarget {
        ChordDraftPreviewDeviceDiagnosticTarget(
            targetIndex: index,
            measureID: measureID,
            fraction: fraction,
            visualOrder: fraction,
            laneSystemIndex: 0,
            laneFraction: fraction,
            strokeCount: strokeBounds.count,
            bounds: strokeBounds.first,
            strokeBounds: strokeBounds,
            inkStrokes: inkStrokes
        )
    }

    private func payload(
        index: Int,
        fraction: Double? = nil,
        strokeCount: Int? = nil,
        raw: [String],
        supported: [String],
        match: String?,
        accepted: String?,
        action: String? = nil,
        reason: String? = nil,
        confidence: Double? = nil,
        closeRace: Bool = false,
        confidenceGap: Double? = nil,
        inkStrokes: [InkStroke]? = nil
    ) -> ChordDraftPreviewDeviceDiagnosticPayload {
        let resolvedFraction = fraction ?? (index == 0 ? 0.08 : 0.22)
        let resolvedStrokeCount = strokeCount ?? (index == 0 ? dStrokeBounds.count : dMinor7StrokeBounds.count)
        let resolvedConfidence = confidence ?? (supported.isEmpty ? 0.25 : 4.5)
        let resolvedAction = action ?? (accepted == nil ? "confirm" : "trusted")
        let resolvedReason = reason ?? (accepted == nil ? "Needs confirmation." : "Trusted read.")

        return ChordDraftPreviewDeviceDiagnosticPayload(
            targetIndex: index,
            measureID: measureID,
            fraction: resolvedFraction,
            visualOrder: resolvedFraction,
            laneSystemIndex: 0,
            laneFraction: resolvedFraction,
            strokeCount: resolvedStrokeCount,
            rawCandidates: raw,
            supportedCandidates: supported,
            matchText: match,
            acceptedText: accepted,
            action: resolvedAction,
            reason: resolvedReason,
            confidence: resolvedConfidence,
            closeRace: closeRace,
            confidenceGap: confidenceGap,
            topScores: raw.map { text in
                ChordInkCandidateScore(text: text, displayText: text, confidence: resolvedConfidence)
            },
            glyphCandidateColumns: raw.map { text in
                [
                    ChordDraftPreviewDeviceDiagnosticGlyphCandidate(
                        text: text,
                        confidence: resolvedConfidence,
                        source: "template"
                    )
                ]
            },
            inkStrokes: inkStrokes
        )
    }

    private func replacement(
        index: Int,
        previousText: String?,
        newText: String?,
        previousRenderable: Bool?,
        newRenderable: Bool?
    ) -> ChordDraftPreviewDeviceDiagnosticReplacement {
        ChordDraftPreviewDeviceDiagnosticReplacement(
            draftIndex: index,
            anchorMeasureID: measureID,
            anchorFractionBucket: index == 0 ? 8 : 22,
            previousDraftID: previousText == nil ? nil : UUID(),
            newDraftID: newText == nil ? nil : UUID(),
            targetFraction: index == 0 ? 0.08 : 0.22,
            laneSystemIndex: 0,
            laneFraction: index == 0 ? 0.08 : 0.22,
            previousPreviewText: previousText,
            newPreviewText: newText,
            previousRenderable: previousRenderable,
            newRenderable: newRenderable,
            bestCandidateText: newText,
            candidateTexts: newText.map { [$0] } ?? [],
            strokeCount: index == 0 ? dStrokeBounds.count : dMinor7StrokeBounds.count,
            confidence: newRenderable == true ? 4.5 : 0
        )
    }

    private func bounds(
        minX: Double,
        minY: Double,
        width: Double,
        height: Double
    ) -> ChordDraftPreviewDeviceDiagnosticBounds {
        ChordDraftPreviewDeviceDiagnosticBounds(
            minX: minX,
            minY: minY,
            width: width,
            height: height
        )
    }
}
