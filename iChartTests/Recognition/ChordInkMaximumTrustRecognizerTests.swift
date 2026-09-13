import XCTest
@testable import iChart

final class ChordInkMaximumTrustRecognizerTests: XCTestCase {
    func testCompactRootLedNoReadOffersBoundedReviewWithoutChangingPrimary() throws {
        for name in ["FSharp7Flat5Captured01", "GSharp7Flat5Captured01"] {
            let fixture = try InkFixtureLoader.load(name, file: #filePath)
            let bounds = InkBounds.enclosing(fixture.strokes.map(\.bounds))
            let strokes = fixture.strokes.map { stroke in
                InkStroke(
                    points: stroke.points.map {
                        InkPoint(
                            x: ($0.x - bounds.minX) * 0.90,
                            y: ($0.y - bounds.minY) * 0.90,
                            timeOffset: $0.timeOffset
                        )
                    },
                    creationTimeOffset: stroke.creationTimeOffset
                )
            }
            let native = ChordInkRecognizer(normalizesOversizedInput: false).recognize(strokes: strokes)
            let recovered = ChordInkMaximumTrustRecognizer().recognize(strokes: strokes)
            let decision = ChordInkRecognitionPolicy.decision(for: recovered)
            let details = "\(name) review=\(recovered.reviewCandidateScores)"
            XCTAssertNil(native.match, "This regression must exercise a real native no-read")
            XCTAssertEqual(recovered.match, native.match, details)
            XCTAssertEqual(recovered.candidateScores, native.candidateScores, details)
            XCTAssertEqual(recovered.confidence, native.confidence, details)
            XCTAssertEqual(decision.action, .confirm, details)
            XCTAssertNil(decision.acceptedText, details)
            XCTAssertLessThanOrEqual(recovered.reviewCandidateScores.count, 4, details)
            XCTAssertTrue(ChordInkRenderResolutionPolicy.candidateTexts(for: recovered).prefix(3).contains(fixture.expectedDisplayText), details)
        }
    }

    func testRootRelativeSuspendedMiddleDoesNotTrustRealFlatFiveAsSus() throws {
        let fixtures = try InkFixtureLoader.loadAll(file: #filePath)
            .filter { $0.expectedDisplayText.contains("(b5)") }
        XCTAssertFalse(fixtures.isEmpty)
        for fixture in fixtures {
            let bounds = InkBounds.enclosing(fixture.strokes.map(\.bounds))
            for scale in [0.90, 1.0, 1.45] {
                let strokes = fixture.strokes.map { stroke in
                    InkStroke(
                        points: stroke.points.map {
                            InkPoint(
                                x: ($0.x - bounds.minX) * scale,
                                y: ($0.y - bounds.minY) * scale,
                                timeOffset: $0.timeOffset
                            )
                        },
                        creationTimeOffset: stroke.creationTimeOffset
                    )
                }
                let result = ChordInkMaximumTrustRecognizer().recognize(strokes: strokes)
                let decision = ChordInkRecognitionPolicy.decision(for: result)
                let choices = ChordInkRenderResolutionPolicy.candidateTexts(for: result)
                let details = "\(fixture.name) scale=\(scale) primary=\(result.match?.displayText ?? "nil") action=\(decision.action) choices=\(choices)"
                XCTAssertFalse(decision.action == .trusted && decision.acceptedText != fixture.expectedDisplayText, details)
                XCTAssertTrue(choices.contains(fixture.expectedDisplayText), details)
                if scale == 1.0 {
                    XCTAssertEqual(result.match?.displayText, fixture.expectedDisplayText, details)
                }
            }
        }
    }

    func testCapturedFSharpSusKeepsPrimaryAcrossScaleAndTimingNormalization() throws {
        let fixture = try InkFixtureLoader.load("FSharpsus", file: #filePath)
        let bounds = InkBounds.enclosing(fixture.strokes.map(\.bounds))
        let variants: [(String, Double, Bool, Bool)] = [
            ("native", 1.0, false, false),
            ("scaled", 1.45, false, false),
            ("scaledLocalTimes", 1.45, true, false),
            ("scaledCapturedTimes", 1.45, true, true)
        ]
        for (name, scale, normalizesPointTimes, addsCreationTimes) in variants {
            var creationTime = 0.0
            let strokes = fixture.strokes.map { stroke -> InkStroke in
                let start = stroke.points.compactMap(\.timeOffset).min() ?? 0
                let end = stroke.points.compactMap(\.timeOffset).max() ?? start
                let transformed = InkStroke(
                    points: stroke.points.map {
                        InkPoint(
                            x: ($0.x - bounds.minX) * scale,
                            y: ($0.y - bounds.minY) * scale,
                            timeOffset: $0.timeOffset.map { normalizesPointTimes ? $0 - start : $0 }
                        )
                    },
                    creationTimeOffset: addsCreationTimes ? creationTime : stroke.creationTimeOffset
                )
                creationTime += max(end - start, 0.08) + 0.18
                return transformed
            }
            let result = ChordInkMaximumTrustRecognizer().recognize(
                strokes: strokes,
                options: .includingSymbolLedgerDiagnostics
            )
            let decision = ChordInkRecognitionPolicy.decision(for: result)
            let choices = ChordInkRenderResolutionPolicy.candidateTexts(for: result)
            let untimed = strokes.map { InkStroke(points: $0.points, creationTimeOffset: nil) }
            let clusters = StrokeClusterer().indexedClusters(untimed)
            let columns = result.glyphCandidates.map {
                $0.prefix(5).map { "\($0.text):\(String(format: "%.3f", $0.confidence)):\($0.source)" }.joined(separator: ",")
            }
            let details = "variant=\(name) match=\(result.match?.displayText ?? "nil") action=\(decision.action) choices=\(choices) clusters=\(clusters.map { $0.originalIndexes }) glyphs=\(columns) raw=\(Array(result.rawCandidates.prefix(8)))"
            print("fsharp_sus_scale_timing \(details)")
            XCTAssertEqual(result.match?.displayText, fixture.expectedDisplayText, details)
            XCTAssertTrue(choices.contains(fixture.expectedDisplayText), details)
            XCTAssertTrue(choices.prefix(3).contains(fixture.expectedDisplayText), "Expected recovery must be in the visible one-tap choices: \(details)")
            XCTAssertFalse(decision.action == .trusted && decision.acceptedText != fixture.expectedDisplayText, details)
        }
    }

    func testFreshSimpleDeviceShortStemDHasCorrectPrimaryAndReviewChoice() throws {
        let fixture = try InkFixtureLoader.load("DShortInsetStemSimpleDeviceCaptured04", file: #filePath)
        let result = ChordInkMaximumTrustRecognizer().recognize(
            strokes: fixture.strokes,
            options: .includingSymbolLedgerDiagnostics
        )
        let decision = ChordInkRecognitionPolicy.decision(for: result)
        let details = "match=\(result.match?.displayText ?? "nil") action=\(decision.action) glyphs=\(result.glyphCandidates)"
        XCTAssertEqual(result.match?.displayText, fixture.expectedDisplayText, details)
        XCTAssertTrue(ChordInkRenderResolutionPolicy.candidateTexts(for: result).contains(fixture.expectedDisplayText), details)
        XCTAssertFalse(decision.action == .trusted && decision.acceptedText != fixture.expectedDisplayText, details)
    }

    func testFreshFifthLineNarrowArcAndInsetLowerJoinDHaveCorrectPrimaryAndVisibleChoice() throws {
        for name in ["DNarrowConvexArcSimpleDeviceCaptured05", "DInsetLowerJoinSimpleDeviceCaptured06"] {
            let fixture = try InkFixtureLoader.load(name, file: #filePath)
            for scale in [0.90, 1.0, 1.10] {
                let strokes = fixture.strokes.map { stroke in
                    InkStroke(points: stroke.points.map {
                        InkPoint(x: $0.x * scale, y: $0.y * scale, timeOffset: $0.timeOffset)
                    }, creationTimeOffset: stroke.creationTimeOffset)
                }
                let result = ChordInkMaximumTrustRecognizer().recognize(
                    strokes: strokes,
                    options: .includingSymbolLedgerDiagnostics
                )
                let decision = ChordInkRecognitionPolicy.decision(for: result)
                let choices = ChordInkRenderResolutionPolicy.candidateTexts(for: result)
                let details = "\(name) scale=\(scale) primary=\(result.match?.displayText ?? "nil") action=\(decision.action) choices=\(choices)"
                XCTAssertEqual(result.match?.displayText, "D", details)
                XCTAssertTrue(choices.prefix(3).contains("D"), details)
                XCTAssertFalse(decision.action == .trusted && decision.acceptedText != "D", details)
            }
        }
    }

    func testFreshSimpleDeviceDMinorSevenAndRaisedSharpHaveCorrectPrimaryAndReviewChoice() throws {
        for name in ["DMinor7DetachedStemSimpleDeviceCaptured03", "FSharpRaisedBarsSimpleDeviceCaptured01"] {
            let fixture = try InkFixtureLoader.load(name, file: #filePath)
            let result = ChordInkMaximumTrustRecognizer().recognize(
                strokes: fixture.strokes,
                options: .includingSymbolLedgerDiagnostics
            )
            let decision = ChordInkRecognitionPolicy.decision(for: result)
            XCTAssertEqual(result.match?.displayText, fixture.expectedDisplayText, name)
            XCTAssertTrue(ChordInkRenderResolutionPolicy.candidateTexts(for: result).contains(fixture.expectedDisplayText), name)
            XCTAssertFalse(decision.action == .trusted && decision.acceptedText != fixture.expectedDisplayText, name)
        }
    }

    func testClosedDiminishedLoopsKeepTheirQualityAcrossPenStartAndDirection() throws {
        let root = try InkFixtureLoader.load("C", file: #filePath).strokes
        let rootBounds = InkBounds.enclosing(root.map(\.bounds))
        for size in [(9.0, 13.0), (14.0, 20.0), (21.0, 28.0)] {
            for direction in [-1.0, 1.0] {
                for phase in stride(from: 0.0, to: 360.0, by: 25.0) {
                    let points = (0..<48).map { index -> InkPoint in
                        let angle = (phase + direction * Double(index) / 47 * 348) * .pi / 180
                        return InkPoint(
                            x: rootBounds.maxX + 12 + size.0 / 2 * (1 + cos(angle)),
                            y: rootBounds.minY - 8 + size.1 / 2 * (1 + sin(angle)),
                            timeOffset: Double(index) * 0.008
                        )
                    }
                    let result = ChordInkMaximumTrustRecognizer().recognize(
                        strokes: root + [InkStroke(points: points)],
                        options: .includingSymbolLedgerDiagnostics
                    )
                    let decision = ChordInkRecognitionPolicy.decision(for: result)
                    let details = "size=\(size) direction=\(direction) phase=\(phase) primary=\(result.match?.displayText ?? "nil") action=\(decision.action) glyphs=\(result.glyphCandidates)"
                    XCTAssertFalse(decision.action == .trusted && decision.acceptedText != "C°", details)
                    XCTAssertEqual(result.match?.displayText, "C°", details)
                }
            }
        }
    }

    func testEnlargedCapturedDiminishedLoopCannotBecomeTrustedMajorTriangle() throws {
        for fixtureName in ["CDiminishedCaptured02", "CDiminished"] {
            let fixture = try InkFixtureLoader.load(fixtureName, file: #filePath)
            let bounds = InkBounds.enclosing(fixture.strokes.map(\.bounds))
            let rowScale = 54 / max(bounds.height, 1)
            for scale in [1.0, rowScale, 2.0] {
                let strokes = fixture.strokes.map { stroke in
                    InkStroke(points: stroke.points.map { point in
                        InkPoint(
                            x: (point.x - bounds.minX) * scale,
                            y: (point.y - bounds.minY) * scale,
                            timeOffset: point.timeOffset
                        )
                    }, creationTimeOffset: stroke.creationTimeOffset)
                }
                let result = ChordInkMaximumTrustRecognizer().recognize(
                    strokes: strokes,
                    options: .includingSymbolLedgerDiagnostics
                )
                let decision = ChordInkRecognitionPolicy.decision(for: result)
                let candidates = ChordInkRenderResolutionPolicy.candidateTexts(for: result)
                let details = "\(fixtureName) scale=\(scale) match=\(result.match?.displayText ?? "nil") action=\(decision.action) candidates=\(candidates) glyphs=\(result.glyphCandidates)"
                XCTAssertFalse(decision.action == .trusted && decision.acceptedText != "C°", details)
                XCTAssertEqual(result.match?.displayText, "C°", details)
                XCTAssertTrue(candidates.contains("C°"), details)
            }
        }
    }

    func testClearlyNonChordSketchesNeverBecomeTrustedReads() {
        let recognizer = ChordInkMaximumTrustRecognizer()

        for sketch in Self.clearlyNonChordSketches {
            let result = recognizer.recognize(
                strokes: sketch.strokes,
                options: .includingSymbolLedgerDiagnostics
            )
            let decision = ChordInkRecognitionPolicy.decision(for: result)
            let acceptedText = decision.acceptedText ?? "nil"
            let candidateTexts = ChordInkRenderResolutionPolicy.candidateTexts(for: result)
            let details = "\(sketch.name): accepted=\(acceptedText) action=\(decision.action.rawValue) candidates=\(candidateTexts) review=\(result.reviewCandidateScores) raw=\(Array(result.rawCandidates.prefix(8))) evidence=\(String(describing: result.trustEvidence)) ledger=\(String(describing: result.symbolLedgerAssessment))"

            XCTAssertEqual(
                decision.action,
                .confirm,
                "A clearly non-chord sketch must never be trusted. \(details)"
            )
            XCTAssertLessThanOrEqual(
                result.reviewCandidateScores.count,
                4,
                "Review-only fallback must stay bounded. \(details)"
            )

            if let expectedTrustOutcome = sketch.expectedTrustOutcome {
                XCTAssertEqual(
                    result.trustEvidence?.outcome,
                    expectedTrustOutcome,
                    "The targeted reject guard must explain this demotion. \(details)"
                )
            }
        }
    }

    func testCorroboratedReadRemainsTrusted() throws {
        let base = SequenceChordInkRecognizer(results: [
            result(for: "C", symbolSupportCount: 4),
            result(for: "C"),
            result(for: "C"),
            result(for: "C"),
            result(for: "C")
        ])
        let recognizer = ChordInkMaximumTrustRecognizer(baseRecognizer: base)

        let result = recognizer.recognize(strokes: Self.strokes)
        let evidence = try XCTUnwrap(result.trustEvidence)

        XCTAssertEqual(ChordInkRecognitionPolicy.decision(for: result).action, .trusted)
        XCTAssertEqual(evidence.outcome, .corroborated)
        XCTAssertEqual(evidence.completedProbeCount, 4)
        XCTAssertEqual(evidence.requiredProbeCount, 4)
        XCTAssertEqual(base.callCount, 5)
        XCTAssertNil(result.symbolLedgerAssessment)
    }

    func testInsufficientCorroboratingSymbolEvidenceRequiresConfirmationWithoutProbes() throws {
        let base = SequenceChordInkRecognizer(results: [
            result(for: "C", symbolSupportCount: 1)
        ])
        let recognizer = ChordInkMaximumTrustRecognizer(baseRecognizer: base)

        let result = recognizer.recognize(strokes: Self.strokes)
        let evidence = try XCTUnwrap(result.trustEvidence)

        XCTAssertEqual(ChordInkRecognitionPolicy.decision(for: result).action, .confirm)
        XCTAssertEqual(evidence.outcome, .insufficientSymbolEvidence)
        XCTAssertEqual(
            ChordInkRecognitionPolicy.decision(for: result).reason,
            "I couldn't verify every part of this chord. Choose a suggestion or type it in."
        )
        XCTAssertEqual(evidence.completedProbeCount, 0)
        XCTAssertEqual(base.callCount, 1)
    }

    func testUncapturedHandwritingFamiliesRequireConfirmationWithoutProbes() throws {
        for text in [
            "Cadd2",
            "F#add9",
            "Bbadd11",
            "C6/9",
            "C-6/9",
            "Csus2",
            "C9sus",
            "C-△9",
            "Db7(b9)/F"
        ] {
            let base = SequenceChordInkRecognizer(results: [
                result(for: text, symbolSupportCount: 8)
            ])
            let recognizer = ChordInkMaximumTrustRecognizer(baseRecognizer: base)

            let result = recognizer.recognize(strokes: Self.strokes)
            let evidence = try XCTUnwrap(result.trustEvidence, text)
            let decision = ChordInkRecognitionPolicy.decision(for: result)

            XCTAssertEqual(decision.action, .confirm, text)
            XCTAssertEqual(evidence.outcome, .insufficientCapturedFamilyEvidence, text)
            XCTAssertEqual(
                decision.reason,
                "This chord form still needs handwriting confirmation. Choose the suggestion or type it in.",
                text
            )
            XCTAssertEqual(evidence.completedProbeCount, 0, text)
            XCTAssertEqual(base.callCount, 1, text)
        }
    }

    func testCapturedNeighboringFamiliesRemainEligibleForTrustProbes() throws {
        for text in ["C6", "Csus4", "C7sus", "C-△7", "C/E"] {
            let base = SequenceChordInkRecognizer(results: [
                result(for: text, symbolSupportCount: 8),
                result(for: text),
                result(for: text),
                result(for: text),
                result(for: text)
            ])
            let recognizer = ChordInkMaximumTrustRecognizer(baseRecognizer: base)

            let result = recognizer.recognize(strokes: Self.strokes)
            let evidence = try XCTUnwrap(result.trustEvidence, text)

            XCTAssertEqual(evidence.outcome, .corroborated, text)
            XCTAssertEqual(evidence.completedProbeCount, 4, text)
            XCTAssertEqual(base.callCount, 5, text)
        }
    }

    func testFirstUnstableProbeRequiresConfirmationAndStopsEarly() throws {
        let base = SequenceChordInkRecognizer(results: [
            result(for: "C", symbolSupportCount: 4),
            result(for: "G")
        ])
        let recognizer = ChordInkMaximumTrustRecognizer(baseRecognizer: base)

        let result = recognizer.recognize(strokes: Self.strokes)
        let evidence = try XCTUnwrap(result.trustEvidence)

        XCTAssertEqual(ChordInkRecognitionPolicy.decision(for: result).action, .confirm)
        XCTAssertEqual(evidence.outcome, .unstableUnderPointDensity)
        XCTAssertEqual(evidence.completedProbeCount, 1)
        XCTAssertEqual(base.callCount, 2)
    }

    func testScaleInstabilityRequiresConfirmationAfterDensityProbe() throws {
        let base = SequenceChordInkRecognizer(results: [
            result(for: "C", symbolSupportCount: 4),
            result(for: "C"),
            result(for: "G")
        ])
        let recognizer = ChordInkMaximumTrustRecognizer(baseRecognizer: base)

        let result = recognizer.recognize(strokes: Self.strokes)
        let evidence = try XCTUnwrap(result.trustEvidence)

        XCTAssertEqual(ChordInkRecognitionPolicy.decision(for: result).action, .confirm)
        XCTAssertEqual(evidence.outcome, .unstableUnderScale)
        XCTAssertEqual(evidence.completedProbeCount, 2)
        XCTAssertEqual(base.callCount, 3)
    }

    func testSparseSevenNineAmbiguityRequiresConfirmationBeforeProbes() throws {
        var baseResult = result(for: "C7", symbolSupportCount: 4)
        baseResult.glyphCandidates = [
            [GlyphCandidate(text: "C", confidence: 0.985, source: .heuristic)],
            [
                GlyphCandidate(text: "7", confidence: 0.985, source: .heuristic),
                GlyphCandidate(text: "9", confidence: 0.58, source: .template)
            ]
        ]
        baseResult.acceptedGlyphCandidates = [
            baseResult.glyphCandidates[0][0],
            baseResult.glyphCandidates[1][0]
        ]
        let base = SequenceChordInkRecognizer(results: [baseResult])
        let recognizer = ChordInkMaximumTrustRecognizer(baseRecognizer: base)
        let strokes = [
            InkStroke(points: [
                InkPoint(x: 0, y: 0, timeOffset: 0),
                InkPoint(x: 2, y: 4, timeOffset: 0.02),
                InkPoint(x: 4, y: 8, timeOffset: 0.04),
                InkPoint(x: 6, y: 10, timeOffset: 0.06),
                InkPoint(x: 8, y: 8, timeOffset: 0.08),
                InkPoint(x: 10, y: 4, timeOffset: 0.1)
            ]),
            InkStroke(points: [
                InkPoint(x: 60, y: 0, timeOffset: 0.2),
                InkPoint(x: 72, y: 0, timeOffset: 0.3),
                InkPoint(x: 78, y: 12, timeOffset: 0.4)
            ])
        ]

        let result = recognizer.recognize(strokes: strokes)
        let evidence = try XCTUnwrap(result.trustEvidence)

        XCTAssertEqual(ChordInkRecognitionPolicy.decision(for: result).action, .confirm)
        XCTAssertEqual(evidence.outcome, .insufficientPointDensity)
        XCTAssertEqual(evidence.completedProbeCount, 0)
        XCTAssertEqual(base.callCount, 1)
    }

    func testSevenNineLoopConflictRequiresConfirmationBeforeProbes() throws {
        var baseResult = result(for: "C7", symbolSupportCount: 4)
        baseResult.glyphCandidates = [
            [GlyphCandidate(text: "C", confidence: 0.985, source: .heuristic)],
            [
                GlyphCandidate(text: "7", confidence: 0.985, source: .heuristic),
                GlyphCandidate(text: "9", confidence: 0.58, source: .template)
            ]
        ]
        baseResult.acceptedGlyphCandidates = [
            baseResult.glyphCandidates[0][0],
            baseResult.glyphCandidates[1][0]
        ]
        let base = SequenceChordInkRecognizer(results: [baseResult])
        let recognizer = ChordInkMaximumTrustRecognizer(baseRecognizer: base)
        let strokes = [
            InkStroke(points: [
                InkPoint(x: 0, y: 0, timeOffset: 0),
                InkPoint(x: 2, y: 4, timeOffset: 0.02),
                InkPoint(x: 4, y: 8, timeOffset: 0.04),
                InkPoint(x: 6, y: 10, timeOffset: 0.06),
                InkPoint(x: 8, y: 8, timeOffset: 0.08),
                InkPoint(x: 10, y: 4, timeOffset: 0.1)
            ]),
            InkStroke(points: [
                InkPoint(x: 60, y: 2, timeOffset: 0.2),
                InkPoint(x: 62, y: 5, timeOffset: 0.22),
                InkPoint(x: 64, y: 8, timeOffset: 0.24),
                InkPoint(x: 66, y: 5, timeOffset: 0.26),
                InkPoint(x: 68, y: 0, timeOffset: 0.28),
                InkPoint(x: 67, y: 3, timeOffset: 0.30),
                InkPoint(x: 66, y: 7, timeOffset: 0.32),
                InkPoint(x: 66, y: 12, timeOffset: 0.34),
                InkPoint(x: 66, y: 16, timeOffset: 0.36)
            ])
        ]

        let result = recognizer.recognize(strokes: strokes)
        let evidence = try XCTUnwrap(result.trustEvidence)

        XCTAssertEqual(ChordInkRecognitionPolicy.decision(for: result).action, .confirm)
        XCTAssertEqual(evidence.outcome, .conflictingExtensionEvidence)
        XCTAssertEqual(evidence.completedProbeCount, 0)
        XCTAssertEqual(base.callCount, 1)
    }

    func testMinorSevenNineLoopConflictRequiresConfirmationBeforeProbes() throws {
        var baseResult = result(for: "A-7", symbolSupportCount: 4)
        baseResult.glyphCandidates = [
            [GlyphCandidate(text: "A", confidence: 0.998, source: .heuristic)],
            [GlyphCandidate(text: "-", confidence: 0.995, source: .heuristic)],
            [
                GlyphCandidate(text: "7", confidence: 0.985, source: .heuristic),
                GlyphCandidate(text: "9", confidence: 0.59, source: .template)
            ]
        ]
        baseResult.acceptedGlyphCandidates = [
            baseResult.glyphCandidates[0][0],
            baseResult.glyphCandidates[1][0],
            baseResult.glyphCandidates[2][0]
        ]
        let base = SequenceChordInkRecognizer(results: [baseResult])
        let recognizer = ChordInkMaximumTrustRecognizer(baseRecognizer: base)
        let strokes = [
            InkStroke(points: [
                InkPoint(x: 0, y: 12, timeOffset: 0),
                InkPoint(x: 5, y: 0, timeOffset: 0.02),
                InkPoint(x: 10, y: 12, timeOffset: 0.04)
            ]),
            InkStroke(points: [
                InkPoint(x: 25, y: 8, timeOffset: 0.10),
                InkPoint(x: 36, y: 8, timeOffset: 0.12)
            ]),
            InkStroke(points: [
                InkPoint(x: 60, y: 2, timeOffset: 0.20),
                InkPoint(x: 62, y: 5, timeOffset: 0.22),
                InkPoint(x: 64, y: 8, timeOffset: 0.24),
                InkPoint(x: 66, y: 5, timeOffset: 0.26),
                InkPoint(x: 68, y: 0, timeOffset: 0.28),
                InkPoint(x: 67, y: 3, timeOffset: 0.30),
                InkPoint(x: 66, y: 7, timeOffset: 0.32),
                InkPoint(x: 66, y: 12, timeOffset: 0.34),
                InkPoint(x: 66, y: 16, timeOffset: 0.36)
            ])
        ]

        let result = recognizer.recognize(strokes: strokes)
        let evidence = try XCTUnwrap(result.trustEvidence)

        XCTAssertEqual(ChordInkRecognitionPolicy.decision(for: result).action, .confirm)
        XCTAssertEqual(evidence.outcome, .conflictingExtensionEvidence)
        XCTAssertEqual(evidence.completedProbeCount, 0)
        XCTAssertEqual(base.callCount, 1)
    }

    func testStrongCompetingAlterationRequiresConfirmationBeforeProbes() throws {
        var baseResult = result(for: "C7#11", symbolSupportCount: 4)
        baseResult.candidateScores.append(ChordInkCandidateScore(
            text: "C7#9",
            displayText: "C7(#9)",
            confidence: 4.2
        ))
        let base = SequenceChordInkRecognizer(results: [baseResult])
        let recognizer = ChordInkMaximumTrustRecognizer(baseRecognizer: base)

        let result = recognizer.recognize(strokes: Self.strokes)
        let evidence = try XCTUnwrap(result.trustEvidence)

        XCTAssertEqual(ChordInkRecognitionPolicy.decision(for: result).action, .confirm)
        XCTAssertEqual(evidence.outcome, .conflictingAlterationEvidence)
        XCTAssertEqual(
            ChordInkRecognitionPolicy.decision(for: result).reason,
            "The alteration could be read more than one way. Choose a suggestion or type it in."
        )
        XCTAssertEqual(evidence.completedProbeCount, 0)
        XCTAssertEqual(base.callCount, 1)
    }

    func testDirectSharpFiveEvidenceCannotBeSilentlyTrustedAsFlatThirteen() throws {
        var baseResult = result(for: "Bb7b13", symbolSupportCount: 6)
        baseResult.glyphCandidates = [
            [GlyphCandidate(text: "B", confidence: 0.987, source: .heuristic)],
            [GlyphCandidate(text: "b", confidence: 0.980, source: .heuristic)],
            [GlyphCandidate(text: "7", confidence: 0.985, source: .heuristic)],
            [
                GlyphCandidate(text: "1", confidence: 0.996, source: .heuristic),
                GlyphCandidate(text: "#", confidence: 0.990, source: .heuristic)
            ],
            [
                GlyphCandidate(text: "5", confidence: 0.992, source: .heuristic),
                GlyphCandidate(text: "3", confidence: 0.633, source: .template)
            ]
        ]
        baseResult.acceptedGlyphCandidates = [
            baseResult.glyphCandidates[0][0],
            baseResult.glyphCandidates[1][0],
            baseResult.glyphCandidates[2][0],
            GlyphCandidate(text: "1", confidence: 0.580, source: .composer),
            GlyphCandidate(text: "3", confidence: 0.840, source: .template)
        ]
        let base = SequenceChordInkRecognizer(results: [baseResult])
        let recognizer = ChordInkMaximumTrustRecognizer(baseRecognizer: base)

        let result = recognizer.recognize(strokes: Self.strokes)
        let evidence = try XCTUnwrap(result.trustEvidence)

        XCTAssertEqual(ChordInkRecognitionPolicy.decision(for: result).action, .confirm)
        XCTAssertEqual(evidence.outcome, .conflictingAlterationEvidence)
        XCTAssertEqual(evidence.completedProbeCount, 0)
        XCTAssertEqual(base.callCount, 1)
    }

    func testStrongRoundTriangleConflictRequiresConfirmationBeforeProbes() throws {
        var baseResult = result(for: "Db°7", symbolSupportCount: 4)
        baseResult.glyphCandidates = [
            [GlyphCandidate(text: "D", confidence: 0.985, source: .heuristic)],
            [GlyphCandidate(text: "b", confidence: 0.99, source: .heuristic)],
            [
                GlyphCandidate(text: "°", confidence: 0.965, source: .heuristic),
                GlyphCandidate(text: "△", confidence: 0.741, source: .template)
            ],
            [GlyphCandidate(text: "7", confidence: 0.985, source: .heuristic)]
        ]
        baseResult.acceptedGlyphCandidates = baseResult.glyphCandidates.map { $0[0] }
        let base = SequenceChordInkRecognizer(results: [baseResult])
        let recognizer = ChordInkMaximumTrustRecognizer(baseRecognizer: base)

        let result = recognizer.recognize(strokes: Self.strokes)
        let evidence = try XCTUnwrap(result.trustEvidence)

        XCTAssertEqual(ChordInkRecognitionPolicy.decision(for: result).action, .confirm)
        XCTAssertEqual(evidence.outcome, .conflictingQualityEvidence)
        XCTAssertEqual(evidence.completedProbeCount, 0)
        XCTAssertEqual(base.callCount, 1)
    }

    func testSyntheticHalfDiminishedLookalikeRequiresConfirmationBeforeProbes() throws {
        var baseResult = result(for: "Cø7", symbolSupportCount: 4)
        baseResult.glyphCandidates = [
            [GlyphCandidate(text: "C", confidence: 0.95, source: .heuristic)],
            [GlyphCandidate(text: "G", confidence: 0.97, source: .heuristic)],
            [GlyphCandidate(text: "7", confidence: 0.985, source: .heuristic)]
        ]
        baseResult.acceptedGlyphCandidates = [
            baseResult.glyphCandidates[0][0],
            GlyphCandidate(text: "ø", confidence: 0.76, source: .composer),
            baseResult.glyphCandidates[2][0]
        ]
        let base = SequenceChordInkRecognizer(results: [baseResult])
        let recognizer = ChordInkMaximumTrustRecognizer(baseRecognizer: base)

        let result = recognizer.recognize(strokes: Self.strokes)
        let evidence = try XCTUnwrap(result.trustEvidence)

        XCTAssertEqual(ChordInkRecognitionPolicy.decision(for: result).action, .confirm)
        XCTAssertEqual(evidence.outcome, .conflictingQualityEvidence)
        XCTAssertEqual(evidence.completedProbeCount, 0)
        XCTAssertEqual(base.callCount, 1)
    }

    func testSixthWithNearTiedFlatEvidenceRequiresConfirmationBeforeProbes() throws {
        var baseResult = result(for: "G6", symbolSupportCount: 4)
        baseResult.glyphCandidates = [
            [GlyphCandidate(text: "G", confidence: 0.97, source: .heuristic)],
            [
                GlyphCandidate(text: "6", confidence: 0.995, source: .heuristic),
                GlyphCandidate(text: "b", confidence: 0.98, source: .heuristic),
                GlyphCandidate(text: "D", confidence: 0.979, source: .heuristic)
            ]
        ]
        baseResult.acceptedGlyphCandidates = baseResult.glyphCandidates.map { $0[0] }
        let base = SequenceChordInkRecognizer(results: [baseResult])
        let recognizer = ChordInkMaximumTrustRecognizer(baseRecognizer: base)

        let result = recognizer.recognize(strokes: Self.strokes)
        let evidence = try XCTUnwrap(result.trustEvidence)

        XCTAssertEqual(ChordInkRecognitionPolicy.decision(for: result).action, .confirm)
        XCTAssertEqual(evidence.outcome, .conflictingExtensionEvidence)
        XCTAssertEqual(evidence.completedProbeCount, 0)
        XCTAssertEqual(base.callCount, 1)
    }

    func testPromotedSixthWithMuchStrongerRootEvidenceRequiresConfirmationBeforeProbes() throws {
        var baseResult = result(for: "C6", symbolSupportCount: 4)
        baseResult.glyphCandidates = [
            [GlyphCandidate(text: "C", confidence: 0.965, source: .heuristic)],
            [
                GlyphCandidate(text: "G", confidence: 0.97, source: .heuristic),
                GlyphCandidate(text: "6", confidence: 0.681, source: .template)
            ]
        ]
        baseResult.acceptedGlyphCandidates = [
            baseResult.glyphCandidates[0][0],
            GlyphCandidate(text: "6", confidence: 0.72, source: .template)
        ]
        let base = SequenceChordInkRecognizer(results: [baseResult])
        let recognizer = ChordInkMaximumTrustRecognizer(baseRecognizer: base)

        let result = recognizer.recognize(strokes: Self.strokes)
        let evidence = try XCTUnwrap(result.trustEvidence)

        XCTAssertEqual(ChordInkRecognitionPolicy.decision(for: result).action, .confirm)
        XCTAssertEqual(evidence.outcome, .conflictingExtensionEvidence)
        XCTAssertEqual(evidence.completedProbeCount, 0)
        XCTAssertEqual(base.callCount, 1)
    }

    func testRootAccidentalWithStrongerDigitLookalikeRequiresConfirmationBeforeProbes() throws {
        var baseResult = result(for: "Cb13", symbolSupportCount: 4)
        baseResult.glyphCandidates = [
            [GlyphCandidate(text: "C", confidence: 0.95, source: .heuristic)],
            [
                GlyphCandidate(text: "9", confidence: 0.997, source: .heuristic),
                GlyphCandidate(text: "b", confidence: 0.98, source: .heuristic),
                GlyphCandidate(text: "G", confidence: 0.97, source: .heuristic)
            ],
            [GlyphCandidate(text: "1", confidence: 0.996, source: .heuristic)],
            [GlyphCandidate(text: "3", confidence: 0.997, source: .heuristic)]
        ]
        baseResult.acceptedGlyphCandidates = [
            baseResult.glyphCandidates[0][0],
            baseResult.glyphCandidates[1][1],
            baseResult.glyphCandidates[2][0],
            baseResult.glyphCandidates[3][0]
        ]
        let base = SequenceChordInkRecognizer(results: [baseResult])
        let recognizer = ChordInkMaximumTrustRecognizer(baseRecognizer: base)

        let result = recognizer.recognize(strokes: Self.strokes)
        let evidence = try XCTUnwrap(result.trustEvidence)

        XCTAssertEqual(ChordInkRecognitionPolicy.decision(for: result).action, .confirm)
        XCTAssertEqual(evidence.outcome, .conflictingAccidentalEvidence)
        XCTAssertEqual(evidence.completedProbeCount, 0)
        XCTAssertEqual(base.callCount, 1)
    }

    func testNaturalMinorWithLostFlatEvidenceRequiresConfirmationBeforeProbes() throws {
        var baseResult = result(for: "D-7b9", symbolSupportCount: 4)
        baseResult.glyphCandidates = [
            [
                GlyphCandidate(text: "D", confidence: 0.985, source: .heuristic),
                GlyphCandidate(text: "b", confidence: 0.46, source: .heuristic)
            ],
            [
                GlyphCandidate(text: "m", confidence: 0.99, source: .heuristic),
                GlyphCandidate(text: "G", confidence: 0.97, source: .heuristic)
            ],
            [GlyphCandidate(text: "7", confidence: 0.985, source: .heuristic)],
            [GlyphCandidate(text: "b", confidence: 0.98, source: .heuristic)],
            [GlyphCandidate(text: "9", confidence: 0.999, source: .heuristic)]
        ]
        baseResult.acceptedGlyphCandidates = baseResult.glyphCandidates.map { $0[0] }
        let base = SequenceChordInkRecognizer(results: [baseResult])
        let recognizer = ChordInkMaximumTrustRecognizer(baseRecognizer: base)

        let result = recognizer.recognize(strokes: Self.strokes)
        let evidence = try XCTUnwrap(result.trustEvidence)

        XCTAssertEqual(ChordInkRecognitionPolicy.decision(for: result).action, .confirm)
        XCTAssertEqual(evidence.outcome, .conflictingAccidentalEvidence)
        XCTAssertEqual(evidence.completedProbeCount, 0)
        XCTAssertEqual(base.callCount, 1)
    }

    func testAlreadyUncertainReadDoesNotPayForTrustProbes() {
        let base = SequenceChordInkRecognizer(results: [
            result(for: "C", confidence: 3.5, symbolSupportCount: 4)
        ])
        let recognizer = ChordInkMaximumTrustRecognizer(baseRecognizer: base)

        let result = recognizer.recognize(strokes: Self.strokes)

        XCTAssertEqual(ChordInkRecognitionPolicy.decision(for: result).action, .confirm)
        XCTAssertNil(result.trustEvidence)
        XCTAssertEqual(base.callCount, 1)
    }

    func testDiagnosticOptionRetainsLedgerEvidence() {
        let base = SequenceChordInkRecognizer(results: [
            result(for: "C", symbolSupportCount: 1)
        ])
        let recognizer = ChordInkMaximumTrustRecognizer(baseRecognizer: base)

        let result = recognizer.recognize(
            strokes: Self.strokes,
            options: .includingSymbolLedgerDiagnostics
        )

        XCTAssertEqual(result.symbolLedgerAssessment?.supportCount, 1)
        XCTAssertEqual(result.trustEvidence?.symbolSupportCount, 1)
    }

    private static let strokes = [
        InkStroke(points: [
            InkPoint(x: 0, y: 0, timeOffset: 0),
            InkPoint(x: 8, y: 12, timeOffset: 0.1),
            InkPoint(x: 14, y: 4, timeOffset: 0.2)
        ])
    ]

    private struct AdversarialSketch {
        var name: String
        var strokes: [InkStroke]
        var expectedTrustOutcome: ChordInkTrustEvidenceOutcome? = nil
    }

    /// Intentionally excludes letter-like shapes: those could legitimately be
    /// a musician's terse root chord. These are unmistakable gestures that can
    /// land in a chord lane through an accidental touch, annotation, or target
    /// split and therefore exercise the recognizer's reject option.
    private static let clearlyNonChordSketches: [AdversarialSketch] = [
        AdversarialSketch(
            name: "long horizontal strike",
            strokes: [stroke([(0, 24), (30, 24), (70, 23), (115, 24), (165, 24)])]
        ),
        AdversarialSketch(
            name: "cross mark",
            strokes: [
                stroke([(0, 0), (18, 18), (36, 36)]),
                stroke([(36, 0), (18, 18), (0, 36)], start: 0.3)
            ]
        ),
        AdversarialSketch(
            name: "wide zigzag",
            strokes: [stroke([(0, 4), (24, 38), (48, 4), (72, 38), (96, 4), (120, 38)])],
            expectedTrustOutcome: .implausibleRootGeometry
        ),
        AdversarialSketch(
            name: "arrow",
            strokes: [
                stroke([(0, 20), (40, 20), (80, 20), (120, 20)]),
                stroke([(98, 2), (120, 20), (98, 38)], start: 0.4)
            ]
        ),
        AdversarialSketch(
            name: "parallel staff-like marks",
            strokes: [
                stroke([(0, 0), (100, 0)]),
                stroke([(0, 9), (100, 9)], start: 0.2),
                stroke([(0, 18), (100, 18)], start: 0.4),
                stroke([(0, 27), (100, 27)], start: 0.6),
                stroke([(0, 36), (100, 36)], start: 0.8)
            ]
        ),
        AdversarialSketch(
            name: "dense cancellation scribble",
            strokes: [stroke([
                (0, 0), (45, 38), (8, 5), (52, 32), (4, 12),
                (48, 26), (2, 19), (44, 20), (6, 27), (40, 13),
                (10, 35), (36, 6)
            ])],
            expectedTrustOutcome: .implausibleRootGeometry
        ),
        AdversarialSketch(
            name: "descending stair",
            strokes: [stroke([
                (0, 0), (22, 0), (22, 12), (44, 12),
                (44, 24), (66, 24), (66, 36), (88, 36)
            ])]
        ),
        AdversarialSketch(
            name: "isolated taps",
            strokes: [
                stroke([(0, 0), (0.5, 0.5)]),
                stroke([(30, 18), (30.5, 18.5)], start: 0.2),
                stroke([(62, 2), (62.5, 2.5)], start: 0.4),
                stroke([(95, 30), (95.5, 30.5)], start: 0.6)
            ]
        )
    ]

    private static func stroke(
        _ coordinates: [(Double, Double)],
        start: TimeInterval = 0
    ) -> InkStroke {
        InkStroke(
            points: coordinates.enumerated().map { index, coordinate in
                InkPoint(
                    x: coordinate.0,
                    y: coordinate.1,
                    timeOffset: start + Double(index) * 0.04
                )
            }
        )
    }

    private func result(
        for text: String,
        confidence: Double = 4.5,
        symbolSupportCount: Int? = nil
    ) -> ChordInkRecognitionResult {
        ChordInkRecognitionResult(
            rawCandidates: [text],
            glyphCandidates: [],
            match: ChordRecognitionCompendium.match(text),
            confidence: confidence,
            candidateScores: [
                ChordInkCandidateScore(
                    text: text,
                    displayText: ChordRecognitionCompendium.match(text)?.displayText,
                    confidence: confidence
                )
            ],
            symbolLedgerAssessment: symbolSupportCount.map { supportCount in
                ChordInkSymbolLedgerAssessment(
                    agreement: supportCount >= 2
                        ? .supportedPrefixMatchesPrimary
                        : .finalCandidateMatchesPrimary,
                    primaryDisplayText: text,
                    stableText: text,
                    normalizedStableText: text,
                    finalPrefixDisplayText: text,
                    finalPrefixSupportedDisplayTexts: [text],
                    finalCandidateDisplayText: text,
                    supportCount: supportCount,
                    supportingSignals: Array(repeating: "test", count: supportCount),
                    competingDisplayTexts: [],
                    unresolvedOverlapCount: 0
                )
            }
        )
    }
}

final class ChordInkRecognitionScaleNormalizerTests: XCTestCase {
    func testLeavesCorpusSizedInkUntouched() {
        let strokes = [InkStroke(
            points: [
                InkPoint(x: 12, y: 18, timeOffset: 0.1),
                InkPoint(x: 38, y: 66, timeOffset: 0.3)
            ],
            creationTimeOffset: 4.2
        )]

        XCTAssertEqual(
            ChordInkRecognitionScaleNormalizer.strokes(from: strokes),
            strokes
        )
    }

    func testUniformlyCapsOversizedInkAndPreservesTimeline() throws {
        let strokes = [
            InkStroke(
                points: [
                    InkPoint(x: 10, y: 20, timeOffset: 0.05),
                    InkPoint(x: 40, y: 80, timeOffset: 0.25)
                ],
                creationTimeOffset: 2.5
            ),
            InkStroke(
                points: [
                    InkPoint(x: 55, y: 35, timeOffset: 0.1),
                    InkPoint(x: 70, y: 65, timeOffset: 0.2)
                ],
                creationTimeOffset: 3.1
            )
        ]

        let normalized = ChordInkRecognitionScaleNormalizer.strokes(from: strokes)
        let bounds = InkBounds.enclosing(normalized.map(\.bounds))

        XCTAssertEqual(bounds.minX, 10, accuracy: 0.0001)
        XCTAssertEqual(bounds.minY, 20, accuracy: 0.0001)
        XCTAssertEqual(bounds.height, 40, accuracy: 0.0001)
        XCTAssertEqual(bounds.width, 40, accuracy: 0.0001)
        XCTAssertEqual(normalized.map(\.creationTimeOffset), [2.5, 3.1])
        XCTAssertEqual(normalized.map { $0.points.map(\.timeOffset) }, [
            [0.05, 0.25],
            [0.1, 0.2]
        ])
        XCTAssertEqual(try XCTUnwrap(normalized[0].timelineStartTimeOffset), 2.55, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(normalized[1].timelineEndTimeOffset), 3.3, accuracy: 0.0001)
    }
}

private final class SequenceChordInkRecognizer: ChordInkRecognizing {
    private let results: [ChordInkRecognitionResult]
    private(set) var callCount = 0

    init(results: [ChordInkRecognitionResult]) {
        self.results = results
    }

    func recognize(
        strokes _: [InkStroke],
        options _: ChordInkRecognitionOptions
    ) -> ChordInkRecognitionResult {
        defer { callCount += 1 }
        return results[min(callCount, results.count - 1)]
    }
}
