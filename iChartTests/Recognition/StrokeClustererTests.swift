import XCTest
@testable import iChart

final class StrokeClustererTests: XCTestCase {
    private let clusterer = StrokeClusterer()
    private let originalInkClusterer = StrokeClusterer(wrapperPolicy: .preserveOriginalInk)

    func testPreservingOriginalInkPartitionsEveryRetainedFixtureWithoutChangingSourceStrokes() throws {
        let fixtures = try InkFixtureLoader.loadAll(file: #filePath)
        XCTAssertFalse(fixtures.isEmpty)
        for fixture in fixtures {
            for reversesOrder in [false, true] {
                let strokes = reversesOrder ? Array(fixture.strokes.reversed()) : fixture.strokes
                assertOriginalInkPartition(strokes, context: "\(fixture.name) reversed=\(reversesOrder)")
            }
        }
    }

    func testPreservingOriginalInkRetainsRepeatedGeometryAndDrawingMetadata() {
        let repeatedStroke = InkStroke(
            points: [
                InkPoint(x: 10, y: 10, timeOffset: 0),
                InkPoint(x: 10, y: 30, timeOffset: 0.1)
            ],
            bounds: InkBounds(minX: 9, minY: 9, maxX: 11, maxY: 31),
            creationTimeOffset: 5
        )
        var laterStroke = repeatedStroke
        laterStroke.creationTimeOffset = 6
        let strokes = [repeatedStroke, laterStroke, repeatedStroke, repeatedStroke]
        assertOriginalInkPartition(strokes, context: "repeated geometry")
        assertOriginalInkPartition(Array(strokes.reversed()), context: "repeated geometry reversed")
    }

    func testPreservingOriginalInkRetainsDominantAndBareParenthesisWrappers() throws {
        let dominantStrokes = try InkFixtureLoader.load("C7Sharp9", file: #filePath).strokes
        let dominantClusters = clusterer.indexedClusters(dominantStrokes)
        let sevenIndexes = Set(try XCTUnwrap(dominantClusters.dropFirst().first).originalIndexes)
        let bareStrokes = dominantStrokes.enumerated().compactMap { index, stroke in
            sevenIndexes.contains(index) ? nil : stroke
        }

        for strokes in [dominantStrokes, bareStrokes] {
            let semanticClusters = clusterer.indexedClusters(strokes)
            XCTAssertEqual(
                semanticClusters,
                StrokeClusterer(wrapperPolicy: .semanticNormalization).indexedClusters(strokes)
            )
            let discardedIndexes = Set(strokes.indices)
                .subtracting(semanticClusters.flatMap(\.originalIndexes))
            XCTAssertEqual(discardedIndexes.count, 2)
            XCTAssertTrue(semanticClusters.contains {
                $0.cluster.hasRecognitionHint(.parenthesizedAlteration)
            })

            let originalClusters = originalInkClusterer.indexedClusters(strokes)
            assertOriginalInkPartition(strokes, context: "literal wrappers")
            XCTAssertTrue(discardedIndexes.isSubset(of: Set(originalClusters.flatMap(\.originalIndexes))))
            XCTAssertEqual(originalInkClusterer.cluster(strokes), originalClusters.map(\.cluster))
        }
    }

    private func assertOriginalInkPartition(
        _ strokes: [InkStroke],
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let clusters = originalInkClusterer.indexedClusters(strokes)
        XCTAssertEqual(clusters.flatMap(\.originalIndexes).sorted(), Array(strokes.indices), context, file: file, line: line)
        XCTAssertTrue(clusters.map(\.cluster).areSortedLeftToRight, context, file: file, line: line)
        for indexed in clusters {
            XCTAssertFalse(indexed.originalIndexes.isEmpty, context, file: file, line: line)
            XCTAssertEqual(indexed.originalIndexes.count, indexed.cluster.strokes.count, context, file: file, line: line)
            XCTAssertNil(indexed.cluster.recognitionHints, context, file: file, line: line)
            for (index, stroke) in zip(indexed.originalIndexes, indexed.cluster.strokes) {
                XCTAssertTrue(strokes.indices.contains(index), context, file: file, line: line)
                guard strokes.indices.contains(index) else { continue }
                XCTAssertEqual(stroke, strokes[index], context, file: file, line: line)
            }
        }
    }

    func testDetachedMinorSuffixDoesNotBecomeSharpConstructionWhenOwnedStrokeOrderChanges() throws {
        for name in ["CSharpMinorCaptured03", "CSharpmCaptured03", "ESharpmCaptured03", "FSharpMinorCaptured02"] {
            let fixture = try InkFixtureLoader.load(name, file: #filePath)
            for reversesOrder in [false, true] {
                let input = reversesOrder ? Array(fixture.strokes.reversed()) : fixture.strokes
                let strokes = input.map { InkStroke(points: $0.points, bounds: $0.bounds) }
                let clusters = clusterer.indexedClusters(strokes)
                let details = "\(name) reversed=\(reversesOrder) groups=\(clusters.map(\.originalIndexes))"
                XCTAssertEqual(clusters.count, 3, details)
                XCTAssertEqual(clusters.last?.originalIndexes, [reversesOrder ? 0 : strokes.count - 1], details)
                XCTAssertEqual(clusters.flatMap(\.originalIndexes).sorted(), Array(strokes.indices), details)
                let result = ChordInkMaximumTrustRecognizer().recognize(strokes: strokes)
                XCTAssertEqual(result.match?.displayText, fixture.expectedDisplayText, details)
            }
        }
    }

    func testRepeatedSharpCrossbarWithinStemBodyDoesNotBecomeMinorSuffix() throws {
        let templates = ChordGlyphTemplateLibrary.initialTemplates
        let root = try XCTUnwrap(templates.first { $0.text == "F" })
        let sharp = try XCTUnwrap(templates.first { $0.text == "#" })
        let repeatedBar = try XCTUnwrap(sharp.strokes.last)
        let input = root.strokes + sharp.strokes + [repeatedBar]
        for strokes in [input, Array(input.reversed())] {
            let clusters = clusterer.indexedClusters(strokes)
            XCTAssertEqual(clusters.map { $0.cluster.strokes.count }, [3, 5])
            XCTAssertEqual(clusters.flatMap(\.originalIndexes).sorted(), Array(strokes.indices))
            XCTAssertEqual(ChordInkRecognizer().recognize(strokes: strokes).match?.displayText, "F#")
        }
    }

    func testCompletedRaisedDeviceSharpKeepsBothStemsAndCrossbarsTogether() throws {
        let fixture = try InkFixtureLoader.load("FSharpRaisedBarsSimpleDeviceCaptured01", file: #filePath)
        for strokes in [fixture.strokes, Array(fixture.strokes.reversed())] {
            let clusters = clusterer.indexedClusters(strokes)
            XCTAssertEqual(clusters.map { $0.cluster.strokes.count }, [3, 4])
            XCTAssertEqual(Set(clusters.flatMap(\.originalIndexes)), Set(strokes.indices))
            let sharp = try XCTUnwrap(clusters.last?.cluster)
            let candidates = GestureTemplateRecognizer().rankedCandidates(
                for: sharp,
                templates: ChordGlyphTemplateLibrary.initialTemplates,
                limit: 8
            )
            XCTAssertEqual(candidates.first?.text, "#")
        }
    }

    func testIncompleteSharpCannotBorrowTheFRootsBars() throws {
        let fixture = try InkFixtureLoader.load("FSharpRaisedBarsSimpleDeviceCaptured01", file: #filePath)
        for missingBarIndex in [5, 6] {
            let strokes = fixture.strokes.enumerated().compactMap {
                $0.offset == missingBarIndex ? nil : $0.element
            }
            let clusters = clusterer.indexedClusters(strokes)
            XCTAssertEqual(clusters.first?.originalIndexes.sorted(), [0, 1, 2])
            XCTAssertEqual(Set(clusters.flatMap(\.originalIndexes)), Set(strokes.indices))
            XCTAssertFalse(clusters.contains { cluster in
                MutableInkCluster(strokes: cluster.cluster.strokes, originalIndexes: cluster.originalIndexes)
                    .hasTwoCrossingSharpBars
            })
        }
    }

    func testClustersDefaultRegressionFixturesIntoGlyphSizedGroups() throws {
        try assertClustersIntoExpectedGlyphGroups(
            fixtures: InkFixtureLoader.loadDefaultRegressionFixtures(file: #filePath)
        )
    }

    func testClustersFullInkFixtureArchiveWhenEnabled() throws {
        try XCTSkipUnless(
            InkFixtureLoader.shouldRunFullInkFixtureArchiveTests,
            "Set \(InkFixtureLoader.fullInkFixtureArchiveEnvironmentVariable)=1 to run the full ink fixture archive."
        )
        try assertClustersIntoExpectedGlyphGroups(fixtures: InkFixtureLoader.loadAll(file: #filePath))
    }

    private func assertClustersIntoExpectedGlyphGroups(fixtures: [InkFixture]) throws {
        for fixture in fixtures {
            guard let expectedClusterCount = fixture.expectedClusterCount else {
                continue
            }

            let clusters = clusterer.cluster(fixture.strokes)

            if fixture.allowsCompactSemanticClusters {
                XCTAssertGreaterThanOrEqual(
                    clusters.count,
                    max(1, expectedClusterCount - 2),
                    "Expected \(fixture.name) to keep enough clusters to resolve \(fixture.expectedTopGlyphs)"
                )
                XCTAssertLessThanOrEqual(
                    clusters.count,
                    expectedClusterCount + 1,
                    "Expected \(fixture.name) to avoid over-splitting \(fixture.expectedTopGlyphs)"
                )
                XCTAssertTrue(clusters.areSortedLeftToRight)
                continue
            }

            XCTAssertEqual(
                clusters.count,
                expectedClusterCount,
                "Expected \(fixture.name) to split into \(fixture.expectedTopGlyphs)"
            )
            XCTAssertEqual(clusters.count, fixture.expectedTopGlyphs.count)
            XCTAssertTrue(clusters.areSortedLeftToRight)
            let clusteredStrokeCount = clusters.reduce(0) { $0 + $1.strokes.count }
            if fixture.allowsDiscardingSemanticParenthesisWrappers {
                let discardedStrokeCount = fixture.strokes.count - clusteredStrokeCount
                XCTAssertGreaterThanOrEqual(discardedStrokeCount, 0)
                XCTAssertLessThanOrEqual(
                    discardedStrokeCount,
                    2,
                    "Only literal altered-extension wrapper strokes should be discarded for \(fixture.name)"
                )
            } else {
                XCTAssertEqual(clusteredStrokeCount, fixture.strokes.count)
            }
        }
    }

    func testClustererOutputIsDeterministicForReorderedInput() throws {
        let fixture = try InkFixtureLoader.load("Db7b9", file: #filePath)

        let forwardClusters = clusterer.cluster(fixture.strokes)
        let reversedClusters = clusterer.cluster(Array(fixture.strokes.reversed()))

        XCTAssertEqual(forwardClusters.map(\.bounds), reversedClusters.map(\.bounds))
        XCTAssertEqual(forwardClusters.map(\.strokes.count), reversedClusters.map(\.strokes.count))
    }

    func testSlashBassKeepsSlashAsSeparatorCluster() throws {
        for fixtureName in [
            "GSlashB",
            "GSlashBCaptured02",
            "FSlashA",
            "BFlatSlashDCaptured01",
            "DSlashFSharpCaptured02",
            "DSlashFSharpLooseDevice01",
            "FSharpSlashASharpCaptured01"
        ] {
            let fixture = try InkFixtureLoader.load(fixtureName, file: #filePath)
            let clusters = clusterer.cluster(fixture.strokes)
            let slashIndex = try XCTUnwrap(fixture.expectedTopGlyphs.firstIndex(of: "/"))

            XCTAssertEqual(clusters.count, fixture.expectedClusterCount, fixtureName)
            XCTAssertEqual(clusters.count, fixture.expectedTopGlyphs.count, fixtureName)
            XCTAssertEqual(clusters[slashIndex].strokes.count, 1, fixtureName)
            XCTAssertGreaterThan(clusters[slashIndex].bounds.height, clusters[slashIndex].bounds.width, fixtureName)
            XCTAssertTrue(clusters.areSortedLeftToRight, fixtureName)
        }
    }

    func testDeviceSplitTriangleMajorSevenClustersTriangleAsOneGlyph() throws {
        let fixture = try InkFixtureLoader.load("BFlatMajor7SplitTriangleDevice02", file: #filePath)
        let clusters = clusterer.cluster(fixture.strokes)
        let triangleIndex = try XCTUnwrap(fixture.expectedTopGlyphs.firstIndex(of: "△"))

        XCTAssertEqual(clusters.count, fixture.expectedClusterCount)
        XCTAssertEqual(clusters.map(\.strokes.count), [2, 2, 2, 1])
        XCTAssertEqual(clusters[triangleIndex].strokes.count, 2)
        XCTAssertTrue(clusters.areSortedLeftToRight)
    }

    func testHalfDiminishedConstructionSurvivesLiveWritingScale() throws {
        let fixture = try InkFixtureLoader.load("BFlatHalfDiminished7Captured01", file: #filePath)
        let fixtureBounds = InkBounds.enclosing(fixture.strokes.map(\.bounds))
        let scale = 58 / max(fixtureBounds.height, 1)
        let scaledStrokes = fixture.strokes.map { stroke in
            InkStroke(points: stroke.points.map { point in
                InkPoint(
                    x: (point.x - fixtureBounds.minX) * scale,
                    y: (point.y - fixtureBounds.minY) * scale,
                    timeOffset: point.timeOffset
                )
            })
        }

        let clusters = clusterer.cluster(scaledStrokes)

        XCTAssertEqual(clusters.count, fixture.expectedClusterCount)
        XCTAssertEqual(clusters.map(\.strokes.count), [2, 1, 2, 1])
        XCTAssertTrue(clusters.areSortedLeftToRight)
    }

    func testRootStemAndBodyCanMergeWhenTheyTouchAtTheEdge() throws {
        let fixture = try InkFixtureLoader.load("BSharpMinor11Captured01", file: #filePath)
        let clusters = clusterer.cluster(fixture.strokes)

        XCTAssertEqual(clusters.count, fixture.expectedClusterCount)
        XCTAssertEqual(clusters.first?.strokes.count, 2)
        XCTAssertTrue(clusters.areSortedLeftToRight)
    }

    func testRootCrossbarAndBodyCanMergeWhenCrossbarIsDrawnRightToLeft() throws {
        let fixture = try InkFixtureLoader.load("ASharpCaptured05", file: #filePath)
        let clusters = clusterer.cluster(fixture.strokes)

        XCTAssertEqual(clusters.count, fixture.expectedClusterCount)
        XCTAssertEqual(clusters.first?.strokes.count, 2)
        XCTAssertTrue(clusters.areSortedLeftToRight)
    }

    func testThreeStrokeRootACapturesLegsAndCrossbarAsOneGlyph() throws {
        let fixture = try InkFixtureLoader.load("ARootSplitDevice01", file: #filePath)
        let clusters = clusterer.cluster(fixture.strokes)

        XCTAssertEqual(clusters.count, fixture.expectedClusterCount)
        XCTAssertEqual(clusters.first?.strokes.count, 3)
        XCTAssertTrue(clusters.areSortedLeftToRight)
    }

    func testAttachedFlatModifierSplitsFromRootConstruction() {
        let stem = InkStroke(points: [
            InkPoint(x: 10, y: 20, timeOffset: 0.0),
            InkPoint(x: 10, y: 31, timeOffset: 0.03),
            InkPoint(x: 10, y: 42, timeOffset: 0.06),
            InkPoint(x: 10, y: 53, timeOffset: 0.09)
        ])
        let rootBody = InkStroke(points: [
            InkPoint(x: 11, y: 22, timeOffset: 0.12),
            InkPoint(x: 17, y: 22, timeOffset: 0.15),
            InkPoint(x: 23, y: 26, timeOffset: 0.18),
            InkPoint(x: 27, y: 33, timeOffset: 0.21),
            InkPoint(x: 27, y: 40, timeOffset: 0.24),
            InkPoint(x: 23, y: 48, timeOffset: 0.27),
            InkPoint(x: 16, y: 53, timeOffset: 0.30),
            InkPoint(x: 11, y: 53, timeOffset: 0.33)
        ])
        let flatModifier = InkStroke(points: [
            InkPoint(x: 25, y: 10, timeOffset: 0.36),
            InkPoint(x: 25, y: 18, timeOffset: 0.39),
            InkPoint(x: 25, y: 26, timeOffset: 0.42),
            InkPoint(x: 29, y: 22, timeOffset: 0.45),
            InkPoint(x: 35, y: 20, timeOffset: 0.48),
            InkPoint(x: 38, y: 24, timeOffset: 0.51),
            InkPoint(x: 34, y: 30, timeOffset: 0.54),
            InkPoint(x: 27, y: 32, timeOffset: 0.57)
        ])

        let clusters = clusterer.cluster([stem, rootBody, flatModifier])

        XCTAssertEqual(clusters.map(\.strokes.count), [2, 1])
        XCTAssertTrue(clusters.areSortedLeftToRight)
    }

    func testTallMinorMStaysSeparateFromFollowingSeven() throws {
        let fixture = try InkFixtureLoader.load("CSharpm7Captured02", file: #filePath)
        let clusters = clusterer.cluster(fixture.strokes)

        XCTAssertEqual(clusters.count, fixture.expectedClusterCount)
        XCTAssertEqual(clusters.suffix(2).map(\.strokes.count), [1, 1])
        XCTAssertTrue(clusters.areSortedLeftToRight)
    }

    func testBareParenthesizedAlterationRemovesOnlyWrappersAndTagsItsContent() throws {
        let dominantFixture = try InkFixtureLoader.load("C7Sharp9", file: #filePath)
        let dominantClusters = clusterer.indexedClusters(dominantFixture.strokes)
        XCTAssertEqual(dominantClusters.count, 4)

        let dominantSevenStrokeIndices = Set(dominantClusters[1].originalIndexes)
        let bareParenthesizedStrokes = dominantFixture.strokes.enumerated().compactMap { index, stroke in
            dominantSevenStrokeIndices.contains(index) ? nil : stroke
        }
        let bareClusters = clusterer.indexedClusters(bareParenthesizedStrokes)
        let retainedStrokeCount = bareClusters.reduce(0) { $0 + $1.originalIndexes.count }

        XCTAssertEqual(bareClusters.count, 3)
        XCTAssertEqual(retainedStrokeCount, bareParenthesizedStrokes.count - 2)
        XCTAssertTrue(
            bareClusters.suffix(2).allSatisfy {
                $0.cluster.hasRecognitionHint(.parenthesizedAlteration)
            }
        )
    }

    func testBareParenthesizedAlterationSplitsAFlatMergedWithItsNumber() throws {
        let openingWrapper = testStroke([
            (88, 20), (85, 23), (83, 27), (83, 31),
            (83, 35), (84, 39), (86, 41), (88, 42)
        ])
        let compactFlat = testStroke([
            (101, 24), (101, 30), (101, 36), (101, 40),
            (103, 34), (105, 35), (105, 40), (103, 42),
            (101, 39), (104, 35), (101, 40)
        ])
        let compactThree = testStroke([
            (105, 24), (118, 25), (112, 31), (119, 37), (105, 40)
        ])
        let closingWrapper = testStroke([
            (135, 20), (138, 23), (140, 27), (140, 31),
            (140, 35), (139, 39), (137, 41), (135, 42)
        ])
        let strokes = try templateStrokes("D", offsetX: 0)
            + templateStrokes("b", offsetX: 0)
            + [openingWrapper, compactFlat, compactThree, closingWrapper]

        let clusters = clusterer.indexedClusters(strokes)

        XCTAssertEqual(clusters.map(\.originalIndexes), [[0, 1], [2], [4], [5]])
        XCTAssertTrue(
            clusters.suffix(2).allSatisfy {
                $0.cluster.hasRecognitionHint(.parenthesizedAlteration)
            }
        )
    }

    func testCompactSharpInsideDominantAlterationStillRemovesLiteralWrappers() throws {
        let fixture = try InkFixtureLoader.load("C7Sharp11Captured01", file: #filePath)
        let expectedClusterCount = try XCTUnwrap(fixture.expectedClusterCount)
        let baselineClusters = clusterer.indexedClusters(fixture.strokes)
        let sharpGlyphIndex = try XCTUnwrap(fixture.expectedTopGlyphs.firstIndex(of: "#"))
        let sharpCluster = baselineClusters[sharpGlyphIndex]
        let sharpSourceIndexes = Set(sharpCluster.originalIndexes)
        let sharpCenterY = sharpCluster.bounds.recognitionMidY
        let compactHeight = 11.0
        let yScale = compactHeight / max(sharpCluster.bounds.height, 1)
        let compactStrokes = fixture.strokes.enumerated().map { index, stroke in
            guard sharpSourceIndexes.contains(index) else {
                return stroke
            }

            return InkStroke(
                points: stroke.points.map { point in
                    InkPoint(
                        x: point.x,
                        y: sharpCenterY + (point.y - sharpCenterY) * yScale,
                        timeOffset: point.timeOffset
                    )
                },
                creationTimeOffset: stroke.creationTimeOffset
            )
        }

        let clusters = clusterer.indexedClusters(compactStrokes)
        let retainedStrokeCount = clusters.reduce(0) { $0 + $1.originalIndexes.count }
        let result = ChordInkRecognizer().recognize(strokes: compactStrokes)

        XCTAssertGreaterThanOrEqual(clusters.count, expectedClusterCount - 1)
        XCTAssertLessThanOrEqual(clusters.count, expectedClusterCount)
        XCTAssertEqual(retainedStrokeCount, fixture.strokes.count - 2)
        XCTAssertEqual(result.match?.displayText, fixture.expectedDisplayText)
    }

    func testParenthesizedSharpArchiveNeverTrustsWrongAcrossCompactHeightBoundaryWhenEnabled() throws {
        try XCTSkipUnless(
            InkFixtureLoader.shouldRunFullInkFixtureArchiveTests,
            "Set \(InkFixtureLoader.fullInkFixtureArchiveEnvironmentVariable)=1 to audit compact sharps."
        )
        let compactHeights = [10.0, 10.5, 11.0, 11.5]
        let recognizer = ChordInkMaximumTrustRecognizer()
        var auditedVariantCount = 0
        var correctPrimaryCount = 0
        var correctVisibleCount = 0
        var hiddenCorrectCount = 0
        var manualOnlyCount = 0

        for fixture in try InkFixtureLoader.loadAll(file: #filePath) where fixture.expectedDisplayText.contains("(#") {
            let baselineClusters = clusterer.indexedClusters(fixture.strokes)
            guard baselineClusters.count == fixture.expectedTopGlyphs.count,
                  let sharpGlyphIndex = fixture.expectedTopGlyphs.lastIndex(of: "#") else {
                continue
            }

            let sharpCluster = baselineClusters[sharpGlyphIndex]
            let sharpSourceIndexes = Set(sharpCluster.originalIndexes)
            guard (4...6).contains(sharpCluster.strokes.count),
                  sharpCluster.bounds.width >= 8 else {
                continue
            }

            for compactHeight in compactHeights {
                let sharpCenterY = sharpCluster.bounds.recognitionMidY
                let yScale = compactHeight / max(sharpCluster.bounds.height, 1)
                let compactStrokes = fixture.strokes.enumerated().map { index, stroke in
                    guard sharpSourceIndexes.contains(index) else {
                        return stroke
                    }

                    return InkStroke(
                        points: stroke.points.map { point in
                            InkPoint(
                                x: point.x,
                                y: sharpCenterY + (point.y - sharpCenterY) * yScale,
                                timeOffset: point.timeOffset
                            )
                        },
                        creationTimeOffset: stroke.creationTimeOffset
                    )
                }
                let result = recognizer.recognize(strokes: compactStrokes)
                let decision = ChordInkRecognitionPolicy.decision(for: result)
                let allChoices = ChordInkRenderResolutionPolicy.candidateTexts(for: result)
                let visibleChoices = Array(allChoices.prefix(3))

                if result.match?.displayText == fixture.expectedDisplayText {
                    correctPrimaryCount += 1
                } else {
                    XCTAssertNotEqual(
                        decision.action,
                        .trusted,
                        "\(fixture.name) trusted \(decision.acceptedText ?? "nil") at compact sharp height \(compactHeight)"
                    )
                }
                if visibleChoices.contains(fixture.expectedDisplayText) {
                    correctVisibleCount += 1
                } else if allChoices.contains(fixture.expectedDisplayText) {
                    hiddenCorrectCount += 1
                } else {
                    manualOnlyCount += 1
                }
                auditedVariantCount += 1
            }
        }

        XCTAssertGreaterThan(
            auditedVariantCount,
            0,
            "The retained archive must exercise at least one constructed parenthesized sharp."
        )
        print(
            "compact_sharp_boundary_audit"
                + " variants=\(auditedVariantCount)"
                + " primary_correct=\(correctPrimaryCount)"
                + " visible_correct=\(correctVisibleCount)"
                + " hidden_correct=\(hiddenCorrectCount)"
                + " manual_only=\(manualOnlyCount)"
        )
    }

    func testLongTimeGapPreventsMergingEvenWhenGeometryIsNear() {
        let firstStroke = InkStroke(
            points: [
                InkPoint(x: 10, y: 10, timeOffset: 0.0),
                InkPoint(x: 10, y: 50, timeOffset: 0.1)
            ],
            creationTimeOffset: 100
        )
        let secondStroke = InkStroke(
            points: [
                InkPoint(x: 13, y: 10, timeOffset: 0.0),
                InkPoint(x: 13, y: 50, timeOffset: 0.1)
            ],
            creationTimeOffset: 101.2
        )

        let clusters = clusterer.cluster([firstStroke, secondStroke])

        XCTAssertEqual(clusters.count, 2)
    }

    func testRelativePathOffsetsAreNotComparedAcrossLegacyStrokes() {
        let firstStroke = InkStroke(
            points: [
                InkPoint(x: 10, y: 10, timeOffset: 0.0),
                InkPoint(x: 10, y: 50, timeOffset: 0.1)
            ]
        )
        let secondStroke = InkStroke(
            points: [
                InkPoint(x: 13, y: 10, timeOffset: 1.2),
                InkPoint(x: 13, y: 50, timeOffset: 1.3)
            ]
        )

        let clusters = clusterer.cluster([firstStroke, secondStroke])

        XCTAssertEqual(clusters.count, 1)
    }

    private func templateStrokes(_ text: String, offsetX: Double) throws -> [InkStroke] {
        let template = try XCTUnwrap(
            ChordGlyphTemplateLibrary.initialTemplates.first { $0.text == text },
            "Missing template \(text)"
        )

        return template.strokes.map { stroke in
            InkStroke(
                points: stroke.points.map { point in
                    InkPoint(
                        x: point.x + offsetX,
                        y: point.y,
                        timeOffset: point.timeOffset
                    )
                }
            )
        }
    }

    private func testStroke(_ points: [(Double, Double)]) -> InkStroke {
        InkStroke(
            points: points.map { x, y in
                InkPoint(x: x, y: y, timeOffset: nil)
            }
        )
    }
}

private extension InkFixture {
    var allowsDiscardingSemanticParenthesisWrappers: Bool {
        expectedDisplayText.contains("(#9)")
            || expectedDisplayText.contains("(b9)")
            || expectedDisplayText.contains("(#5)")
            || expectedDisplayText.contains("(b5)")
            || expectedDisplayText.contains("(b13)")
    }

    var allowsCompactSharpElevenClusters: Bool {
        expectedDisplayText.contains("(#11)")
    }

    var allowsCompactAlteredAltClusters: Bool {
        expectedDisplayText.contains("7alt")
    }

    var allowsCompactSemanticClusters: Bool {
        allowsCompactSharpElevenClusters || allowsCompactAlteredAltClusters
    }
}

private extension [InkCluster] {
    var areSortedLeftToRight: Bool {
        zip(self, dropFirst()).allSatisfy { lhs, rhs in
            lhs.bounds.minX <= rhs.bounds.minX
        }
    }
}
