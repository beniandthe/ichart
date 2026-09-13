#if canImport(PencilKit) && canImport(UIKit)
import Foundation
import PencilKit
import UIKit
import XCTest
@testable import iChart

final class ChordEntryPassReplayTests: XCTestCase {
    func testStoredChordOnlyLayoutInferencePreservesCanvasSizeInBothStyles() throws {
        for style in [ChartLayoutStyle.rhythmSectionSheet, .simpleChordSheet] {
            for width in [760.0, 800.0, 852.0] {
                var chart = Chart.blank(title: "Layout inference", measureCount: 8, layoutStyle: style)
                let original = LeadSheetPageLayoutEngine.pageLayout(
                    for: chart,
                    pageSize: CGSize(width: width, height: 1200),
                    includesChordInkContinuationLanes: true
                )
                let size = LeadSheetActiveInkScope.chordWritingFrame(for: original).size
                chart.pageHandwrittenChordCoordinateSpace = PersistentInkCoordinateSpace(size: size)
                let replay = try XCTUnwrap(inferredStoredPageLayout(for: chart))
                let replaySize = LeadSheetActiveInkScope.chordWritingFrame(for: replay).size
                XCTAssertEqual(replaySize.width, size.width, accuracy: 0.001, "\(style) at \(width)")
                XCTAssertEqual(replaySize.height, size.height, accuracy: 0.001, "\(style) at \(width)")
            }
        }
    }

    func testRenderPendingChordInkFromSavedStateWhenEnabled() throws {
        guard let outputPath = ProcessInfo.processInfo.environment[
            "ICHART_REPLAY_PENDING_RENDER_OUTPUT"
        ] else {
            throw XCTSkip("Set ICHART_REPLAY_PENDING_RENDER_OUTPUT to render pending page chord ink.")
        }
        guard let statePath = ProcessInfo.processInfo.environment["ICHART_STATE"] else {
            throw XCTSkip("Set ICHART_STATE to a device or simulator library-state.json.")
        }

        let repository = FileChartRepository(url: URL(fileURLWithPath: statePath))
        let snapshot = try XCTUnwrap(try repository.loadSnapshot())
        let chart = try XCTUnwrap(selectedChart(in: snapshot))
        let drawingData = try XCTUnwrap(chart.pageHandwrittenChordData)
        let coordinateSpace = try XCTUnwrap(chart.pageHandwrittenChordCoordinateSpace)
        let inkImage = try XCTUnwrap(
            LeadSheetSavedInkRenderer.renderedInkImage(
                drawingData,
                size: coordinateSpace.size,
                sourceCoordinateSpace: coordinateSpace,
                targetCoordinateSpace: coordinateSpace,
                scale: 2
            )
        )
        let rendererFormat = UIGraphicsImageRendererFormat()
        rendererFormat.scale = 2
        rendererFormat.opaque = true
        let image = UIGraphicsImageRenderer(
            size: coordinateSpace.size,
            format: rendererFormat
        ).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: coordinateSpace.size))
            inkImage.draw(in: CGRect(origin: .zero, size: coordinateSpace.size))
        }
        let imageData = try XCTUnwrap(image.pngData())
        try imageData.write(to: URL(fileURLWithPath: outputPath), options: .atomic)

        print(
            "pending_chord_render chart=\(chart.id.uuidString)"
                + " layout=\(chart.layoutStyle.rawValue)"
                + " size=\(coordinateSpace.width)x\(coordinateSpace.height)"
                + " strokes=\((try? PKDrawing(data: drawingData).strokes.count) ?? -1)"
                + " output=\(outputPath)"
        )
        XCTAssertGreaterThan(imageData.count, 0)
    }

    func testReplayCommittedSystemSourceInkFromSavedState() throws {
        guard let systemIndexText = ProcessInfo.processInfo.environment[
            "ICHART_REPLAY_COMMITTED_SYSTEM_INDEX"
        ],
        let systemIndex = Int(systemIndexText) else {
            throw XCTSkip("Set ICHART_REPLAY_COMMITTED_SYSTEM_INDEX with ICHART_STATE.")
        }
        guard let statePath = ProcessInfo.processInfo.environment["ICHART_STATE"] else {
            throw XCTSkip("Set ICHART_STATE to a device or simulator library-state.json.")
        }

        let repository = FileChartRepository(url: URL(fileURLWithPath: statePath))
        let snapshot = try XCTUnwrap(try repository.loadSnapshot())
        let chart = try XCTUnwrap(selectedChart(in: snapshot))
        let system = try XCTUnwrap(
            chart.systems.first(where: { $0.index == systemIndex }),
            "Missing system index \(systemIndex)."
        )
        let sourceEvents = system.measures
            .flatMap(\.chordEvents)
            .filter { $0.sourceInkData != nil }
        XCTAssertFalse(sourceEvents.isEmpty)

        let recognizer = ChordInkMaximumTrustRecognizer()
        let results = try sourceEvents.enumerated().map { eventIndex, event in
            let drawingData = try XCTUnwrap(event.sourceInkData)
            let strokes = try PencilKitInkAdapter.inkStrokes(from: drawingData)
            XCTAssertFalse(strokes.isEmpty, "Event \(eventIndex) has no visible source ink.")
            let result = recognizer.recognize(
                strokes: strokes,
                options: .includingSymbolLedgerDiagnostics
            )
            let decision = ChordInkRecognitionPolicy.decision(for: result)
            let candidateTexts = ChordInkRenderResolutionPolicy.candidateTexts(for: result)
            print(
                "committed_system_event_\(eventIndex)"
                    + " saved=\(event.rawInput ?? event.symbol.displayText)"
                    + " strokes=\(strokes.count)"
                    + " match=\(result.match?.displayText ?? "nil")"
                    + " action=\(decision.action)"
                    + " choices=\(Array(candidateTexts.prefix(3)))"
            )
            return result
        }

        print(
            "committed_system_source_ink system=\(systemIndex) "
                + "events=\(sourceEvents.count)"
        )

        if let expectedSequence = ProcessInfo.processInfo.environment[
            "ICHART_REPLAY_EXPECTED_SEQUENCE"
        ]?
            .split(separator: ",")
            .map(String.init),
           !expectedSequence.isEmpty {
            XCTAssertEqual(
                sourceEvents.map { $0.rawInput ?? $0.symbol.displayText },
                expectedSequence,
                "The saved event semantics must match the requested device row."
            )
            XCTAssertEqual(
                results.map { $0.match?.displayText },
                expectedSequence.map(Optional.some),
                "Every committed source drawing must replay independently without a dropped chord."
            )
        }
    }

    func testReplayChordWritingTestChartFromSavedState() throws {
        guard let statePath = ProcessInfo.processInfo.environment["ICHART_STATE"] else {
            throw XCTSkip("Set ICHART_STATE to a simulator library-state.json to replay saved chord ink.")
        }

        let repository = FileChartRepository(url: URL(fileURLWithPath: statePath))
        let snapshot = try XCTUnwrap(try repository.loadSnapshot())
        let chart = try XCTUnwrap(
            selectedChart(in: snapshot),
            "Expected a matching chart in \(statePath)."
        )
        let recognizer = ChordInkRecognizer()
        let environment = ProcessInfo.processInfo.environment
        let requestedMeasureIndex = environment["ICHART_REPLAY_MEASURE_INDEX"]
            .flatMap(Int.init)
        let requestedEventIndex = environment["ICHART_REPLAY_EVENT_INDEX"]
            .flatMap(Int.init)
        var replayedEventCount = 0

        for measure in chart.measures where requestedMeasureIndex == nil
            || measure.index == requestedMeasureIndex {
            for (eventIndex, chordEvent) in measure.chordEvents.enumerated()
                where requestedEventIndex == nil || eventIndex == requestedEventIndex {
                guard let sourceInkData = chordEvent.sourceInkData else {
                    XCTFail("Missing source ink for \(chordEvent.symbol.displayText) in measure \(measure.index).")
                    continue
                }
                replayedEventCount += 1

                let strokes = try PencilKitInkAdapter.inkStrokes(from: sourceInkData)
                let result = recognizer.recognize(strokes: strokes)
                let decision = ChordInkRecognitionPolicy.decision(for: result)
                let savedText = chordEvent.rawInput ?? chordEvent.symbol.displayText
                let matchText = result.match?.displayText ?? "nil"
                let scores = result.candidateScores
                    .prefix(6)
                    .map { score in
                        let display = score.displayText ?? score.text
                        return "\(display):\(String(format: "%.3f", score.confidence))"
                    }
                    .joined(separator: ",")

                print(
                    [
                        "measure=\(measure.index)",
                        "event=\(eventIndex)",
                        "saved=\(savedText)",
                        "match=\(matchText)",
                        "confidence=\(String(format: "%.3f", result.confidence))",
                        "action=\(decision.action)",
                        "gap=\(decision.confidenceGap.map { String(format: "%.3f", $0) } ?? "nil")",
                        "scores=[\(scores)]"
                    ].joined(separator: " ")
                )

                if environment["ICHART_REPLAY_GLYPHS"] == "1" {
                    let clusters = StrokeClusterer().cluster(strokes)
                    for (index, group) in result.glyphCandidates.enumerated() {
                        let glyphSummary = group
                            .prefix(8)
                            .map { candidate in
                                "\(candidate.text):\(String(format: "%.3f", candidate.confidence))"
                            }
                            .joined(separator: ",")
                        let cluster = clusters.indices.contains(index) ? clusters[index] : nil
                        let bounds = cluster.map {
                            " x=\(String(format: "%.1f", $0.bounds.minX))-\(String(format: "%.1f", $0.bounds.maxX)) y=\(String(format: "%.1f", $0.bounds.minY))-\(String(format: "%.1f", $0.bounds.maxY)) strokes=\($0.strokes.count)"
                        } ?? ""
                        print("  glyph[\(index)]\(bounds)=[\(glyphSummary)]")
                        if environment["ICHART_REPLAY_STROKES"] == "1",
                           let cluster {
                            let clusterEvidence = MutableInkCluster(
                                strokes: cluster.strokes,
                                originalIndexes: []
                            )
                            print(
                                "    cluster root=\(clusterEvidence.isRootBodyCandidate)"
                                    + " root_body=\(clusterEvidence.hasRootConstructionBody)"
                                    + " root_stem=\(clusterEvidence.hasRootConstructionVerticalStem)"
                                    + " seven=\(clusterEvidence.isDominantSevenInkAnchor)"
                                    + " seven_suffix=\(clusterEvidence.isDominantSevenSuffixAnchor)"
                                    + " seven_alteration=\(clusterEvidence.isDominantSevenAlterationAnchor)"
                                    + " accidental=\(clusterEvidence.isWrittenAlterationAccidentalCandidate)"
                                    + " sus_s=\(clusterEvidence.isSuspendedSLikeContextCandidate)"
                                    + " sus_u=\(clusterEvidence.isSuspendedULikeContextCandidate)"
                            )
                            for (strokeIndex, stroke) in cluster.strokes.enumerated() {
                                let geometry = "    stroke[\(strokeIndex)] x=\(String(format: "%.1f", stroke.bounds.minX))-\(String(format: "%.1f", stroke.bounds.maxX)) y=\(String(format: "%.1f", stroke.bounds.minY))-\(String(format: "%.1f", stroke.bounds.maxY)) points=\(stroke.points.count) straight=\(String(format: "%.2f", stroke.straightness)) hdir=\(stroke.horizontalDirectionChangeCount)"
                                let wrapperEvidence = " open=\(stroke.isOpeningParenthesizedAlterationWrapperCandidate) loose_open=\(stroke.isLooseOpeningParenthesizedAlterationWrapperCandidate) close=\(stroke.isClosingParenthesizedAlterationWrapperCandidate) loose_close=\(stroke.isLooseClosingParenthesizedAlterationWrapperCandidate) trailing=\(stroke.isTrailingParenthesizedAlterationWrapperCandidate)"
                                print(geometry + wrapperEvidence)
                            }
                        }
                    }
                }
            }
        }
        XCTAssertGreaterThan(
            replayedEventCount,
            0,
            "The requested saved-state replay filter matched no chord events."
        )
    }

    func testReplayPendingChordInkFromSavedState() throws {
        guard ProcessInfo.processInfo.environment["ICHART_REPLAY_PENDING_CHORD_INK"] == "1" else {
            throw XCTSkip("Set ICHART_REPLAY_PENDING_CHORD_INK=1 to replay pending page chord ink.")
        }
        guard let statePath = ProcessInfo.processInfo.environment["ICHART_STATE"] else {
            throw XCTSkip("Set ICHART_STATE to a device or simulator library-state.json.")
        }

        let repository = FileChartRepository(url: URL(fileURLWithPath: statePath))
        let snapshot = try XCTUnwrap(try repository.loadSnapshot())
        let chart = try XCTUnwrap(selectedChart(in: snapshot))
        let drawingData = try XCTUnwrap(chart.pageHandwrittenChordData)
        let allStrokes = try PencilKitInkAdapter.inkStrokes(from: drawingData)
        let environment = ProcessInfo.processInfo.environment
        let minimumY = environment["ICHART_REPLAY_PENDING_MIN_Y"].flatMap(Double.init)
        let maximumY = environment["ICHART_REPLAY_PENDING_MAX_Y"].flatMap(Double.init)
        let pointDumpIndexes = Set(
            environment["ICHART_REPLAY_POINT_INDEXES"]?
                .split(separator: ",")
                .compactMap { Int($0) } ?? []
        )
        let strokes = allStrokes.filter { stroke in
            let centerY = stroke.bounds.recognitionMidY
            return minimumY.map { centerY >= $0 } ?? true
                && maximumY.map { centerY <= $0 } ?? true
        }
        XCTAssertFalse(strokes.isEmpty)

        let firstStrokeResult = ChordInkRecognizer().recognize(strokes: [strokes[0]])
        printRecognition(label: "first_stroke", result: firstStrokeResult)
        if environment["ICHART_REPLAY_STROKES"] == "1" {
            for (index, stroke) in strokes.enumerated() {
                let minX = String(format: "%.1f", stroke.bounds.minX)
                let maxX = String(format: "%.1f", stroke.bounds.maxX)
                let minY = String(format: "%.1f", stroke.bounds.minY)
                let maxY = String(format: "%.1f", stroke.bounds.maxY)
                let timelineStart = stroke.timelineStartTimeOffset
                    .map { String(format: "%.3f", $0) } ?? "nil"
                let timelineEnd = stroke.timelineEndTimeOffset
                    .map { String(format: "%.3f", $0) } ?? "nil"
                print(
                    "raw_stroke_\(index)"
                        + " x=\(minX)-\(maxX)"
                        + " y=\(minY)-\(maxY)"
                        + " timeline=\(timelineStart)-\(timelineEnd)"
                        + " points=\(stroke.points.count)"
                        + " straightness=\(String(format: "%.3f", stroke.straightness))"
                        + " angle=\(String(format: "%.1f", stroke.angleDegrees))"
                        + " hdc=\(stroke.horizontalDirectionChangeCount)"
                        + " top_run=\(stroke.hasEarlyTopHorizontalRun)"
                        + " one=\(stroke.isOneGlyphCandidate)"
                        + " three=\(stroke.isThreeGlyphCandidate)"
                        + " five=\(stroke.isFiveGlyphCandidate)"
                        + " nine=\(stroke.isNineGlyphCandidate)"
                        + " open=\(stroke.isOpeningParenthesizedAlterationWrapperCandidate)"
                        + " loose_open=\(stroke.isLooseOpeningParenthesizedAlterationWrapperCandidate)"
                        + " close=\(stroke.isClosingParenthesizedAlterationWrapperCandidate)"
                        + " loose_close=\(stroke.isLooseClosingParenthesizedAlterationWrapperCandidate)"
                )
                if pointDumpIndexes.contains(index) {
                    let points = stroke.points.map { point in
                        "(\(String(format: "%.1f", point.x)),\(String(format: "%.1f", point.y)))"
                    }.joined(separator: ",")
                    print("raw_stroke_\(index)_points=[\(points)]")
                }
            }
        }

        let indexedStrokes = strokes.enumerated().map { (index: $0.offset, stroke: $0.element) }
        let localClusters = StrokeClusterer().indexedClusters(strokes)
        let glyphRecognizer = GestureTemplateRecognizer()
        for (index, localCluster) in localClusters.enumerated() {
            let candidates = glyphRecognizer.rankedCandidates(
                for: localCluster.cluster,
                templates: ChordGlyphTemplateLibrary.initialTemplates,
                limit: 8
            )
            let candidateText = candidates.map {
                "\($0.text):\(String(format: "%.3f", $0.confidence))"
            }.joined(separator: ",")
            let minX = String(format: "%.1f", localCluster.bounds.minX)
            let maxX = String(format: "%.1f", localCluster.bounds.maxX)
            let minY = String(format: "%.1f", localCluster.bounds.minY)
            let maxY = String(format: "%.1f", localCluster.bounds.maxY)
            print(
                "local_cluster_\(index)"
                    + " x=\(minX)-\(maxX)"
                    + " y=\(minY)-\(maxY)"
                    + " strokes=\(localCluster.originalIndexes.count)"
                    + " source_indexes=\(localCluster.originalIndexes.sorted())"
                    + " candidates=[\(candidateText)]"
            )
        }
        let sequentialGroups = ChordInkSequentialGrouper().groups(for: indexedStrokes)
        let maximumReplayStrokeCount = environment["ICHART_REPLAY_PENDING_MAX_STROKES_PER_GROUP"]
            .flatMap(Int.init) ?? 24
        for (index, group) in sequentialGroups.enumerated() {
            let minX = String(format: "%.1f", group.bounds.minX)
            let maxX = String(format: "%.1f", group.bounds.maxX)
            let minY = String(format: "%.1f", group.bounds.minY)
            let maxY = String(format: "%.1f", group.bounds.maxY)
            let rootText = group.rootText ?? "nil"
            print(
                "sequential_group_\(index)"
                    + " x=\(minX)-\(maxX)"
                    + " y=\(minY)-\(maxY)"
                    + " strokes=\(group.strokeIndices.count)"
                    + " root=\(rootText)"
            )
        }
        let replayableSequentialGroups = sequentialGroups.filter {
            $0.strokeIndices.count <= maximumReplayStrokeCount
        }
        let productionRecognizer = ChordInkMaximumTrustRecognizer()
        let sequentialResults = replayableSequentialGroups.map { group in
            let groupStrokes = group.strokeIndices.map { strokes[$0] }
            if environment["ICHART_REPLAY_SEMANTIC_CANDIDATES"] == "1" {
                let clusters = StrokeClusterer().cluster(groupStrokes)
                let rawGlyphGroups = clusters.map { cluster in
                    GestureTemplateRecognizer().rankedCandidates(
                        for: cluster,
                        templates: ChordGlyphTemplateLibrary.initialTemplates,
                        limit: 8
                    )
                }
                let glyphGroups = ChordInkSemanticGlyphContextualizer()
                    .contextualizedGlyphCandidateGroups(rawGlyphGroups, clusters: clusters)
                let semanticCandidates = ChordInkSemanticCandidateComposer()
                    .candidates(from: glyphGroups, clusters: clusters)
                    .map { "\($0.text):\(String(format: "%.3f", $0.confidence))" }
                let clusterFeatures = clusters.enumerated().map { clusterIndex, cluster in
                    let stroke = cluster.strokes.count == 1 ? cluster.strokes[0] : nil
                    let threeConfidence = glyphGroups[clusterIndex]
                        .first { $0.text == "3" }?.confidence ?? 0
                    return "\(clusterIndex):s\(cluster.strokes.count)"
                        + "/3c\(String(format: "%.3f", threeConfidence))"
                        + "/3g\(stroke?.isThreeGlyphCandidate == true)"
                        + "/1g\(stroke?.isOneGlyphCandidate == true)"
                }.joined(separator: ",")
                print(
                    "semantic_candidates_root_\(group.rootText ?? "nil")="
                        + "[\(semanticCandidates.joined(separator: ","))]"
                        + " cluster_features=[\(clusterFeatures)]"
                )
            }
            return productionRecognizer.recognize(
                strokes: groupStrokes,
                options: .includingSymbolLedgerDiagnostics
            )
        }
        for (index, result) in sequentialResults.enumerated() {
            printRecognition(label: "sequential_group_\(index)", result: result)
        }
        let skippedSequentialGroupCount = sequentialGroups.count - replayableSequentialGroups.count

        let gapClusters = ChordInkBatchClusterer.clusters(for: strokes)
        for (index, cluster) in gapClusters.enumerated() {
            let minX = String(format: "%.1f", cluster.bounds.minX)
            let maxX = String(format: "%.1f", cluster.bounds.maxX)
            let minY = String(format: "%.1f", cluster.bounds.minY)
            let maxY = String(format: "%.1f", cluster.bounds.maxY)
            print(
                "gap_group_\(index)"
                    + " x=\(minX)-\(maxX)"
                    + " y=\(minY)-\(maxY)"
                    + " strokes=\(cluster.strokeIndices.count)"
            )
        }
        let replayableGapClusters = gapClusters.filter {
            $0.strokeIndices.count <= maximumReplayStrokeCount
        }
        let gapResults = replayableGapClusters.map { cluster in
            ChordInkRecognizer().recognize(strokes: cluster.strokeIndices.map { strokes[$0] })
        }
        for (index, result) in gapResults.enumerated() {
            printRecognition(label: "gap_group_\(index)", result: result)
        }
        let skippedGapGroupCount = gapClusters.count - replayableGapClusters.count

        let minimumYText = minimumY.map { String($0) } ?? "nil"
        let maximumYText = maximumY.map { String($0) } ?? "nil"
        print(
            "pending_chord_ink all_strokes=\(allStrokes.count) selected_strokes=\(strokes.count) "
                + "y_range=\(minimumYText)...\(maximumYText) "
                + "sequential_groups=\(sequentialGroups.count) "
                + "gap_groups=\(gapClusters.count) "
                + "max_strokes_per_group=\(maximumReplayStrokeCount) "
                + "skipped_sequential_groups=\(skippedSequentialGroupCount) "
                + "skipped_gap_groups=\(skippedGapGroupCount)"
        )

        if let expectedRootSequence = environment["ICHART_REPLAY_EXPECTED_ROOT_SEQUENCE"]?
            .split(separator: ",")
            .map(String.init),
           !expectedRootSequence.isEmpty {
            XCTAssertEqual(
                sequentialGroups.map(\.rootText),
                expectedRootSequence.map(Optional.some),
                "Every handwritten root must start an independent recognition target."
            )
            XCTAssertEqual(
                skippedSequentialGroupCount,
                0,
                "Root-sequence replay must not silently omit oversized sequential groups."
            )
        }

        if let expectedSequence = ProcessInfo.processInfo.environment["ICHART_REPLAY_EXPECTED_SEQUENCE"]?
            .split(separator: ",")
            .map(String.init),
           !expectedSequence.isEmpty {
            XCTAssertEqual(
                Set(sequentialGroups.flatMap(\.strokeIndices)),
                Set(strokes.indices),
                "Expected-sequence replay must preserve every handwritten stroke through row targeting."
            )
            XCTAssertEqual(
                skippedSequentialGroupCount,
                0,
                "Expected-sequence replay must not silently omit oversized sequential groups."
            )
            XCTAssertTrue(
                sequentialGroups.allSatisfy {
                    $0.strokeIndices.count <= ChordInkDraftPreviewPolicy.maximumBatchTargetStrokeCount
                },
                "Expected-sequence replay must fit the live draft-preview target limit."
            )
            XCTAssertEqual(sequentialResults.compactMap { $0.match?.displayText }, expectedSequence)

            if environment["ICHART_REPLAY_PRODUCTION_PREPARATION"] == "1" {
                auditProductionPreparation(
                    chart: chart,
                    drawingData: drawingData,
                    expectedSequence: expectedSequence,
                    minimumY: minimumY,
                    maximumY: maximumY
                )
            }

            if environment["ICHART_REPLAY_PREFIX_AUDIT"] == "1" {
                auditSequentialPrefixes(
                    strokes: strokes,
                    finalGroups: sequentialGroups,
                    expectedSequence: expectedSequence
                )
            }
        }
    }

    /// Exercises the same serialization -> preparation -> lane targeting ->
    /// bounded-target -> maximum-trust path used by the live editor. Directly
    /// replaying final sequential groups proves recognition, but cannot prove
    /// that the production preparation layer will actually deliver each group.
    private func auditProductionPreparation(
        chart: Chart,
        drawingData: Data,
        expectedSequence: [String],
        minimumY: Double?,
        maximumY: Double?
    ) {
        guard let pageLayout = inferredStoredPageLayout(for: chart) else {
            XCTFail("Production preparation replay requires a stored page coordinate space.")
            return
        }

        let chordRegion = LeadSheetActiveInkScope.chordWritingRegion(for: pageLayout)
        let activeInkScope = LeadSheetActiveInkScope.chords(
            frame: chordRegion.frame,
            inputFrames: chordRegion.inputFrames
        )
        let sourceCoordinateSpace = LeadSheetPersistentInkCoordinateSpacePolicy.sourceCoordinateSpace(
            chart.pageHandwrittenChordCoordinateSpace,
            for: activeInkScope,
            chart: chart
        )
        let targetCoordinateSpace = LeadSheetPersistentInkCoordinateSpacePolicy.coordinateSpace(
            for: activeInkScope,
            pageLayout: pageLayout
        )
        let sourceStrokes = (try? PencilKitInkAdapter.inkStrokes(from: drawingData)) ?? []
        let selectedSourceStrokeIndexes = sourceStrokes.indices.filter { index in
            let centerY = sourceStrokes[index].bounds.recognitionMidY
            return minimumY.map { centerY >= $0 } ?? true
                && maximumY.map { centerY <= $0 } ?? true
        }
        let loadedDrawing = LeadSheetPersistentInkCoordinateSpacePolicy.drawing(
            from: drawingData,
            sourceCoordinateSpace: sourceCoordinateSpace,
            targetCoordinateSpace: targetCoordinateSpace
        ) ?? PKDrawing()
        let loadedDrawingData = loadedDrawing.dataRepresentation()
        let loadedStrokes = (try? PencilKitInkAdapter.inkStrokes(from: loadedDrawingData)) ?? []
        XCTAssertEqual(loadedStrokes.count, sourceStrokes.count)
        let selectedLoadedStrokes = Set(
            selectedSourceStrokeIndexes.compactMap { index in
                loadedStrokes.indices.contains(index) ? loadedStrokes[index] : nil
            }
        )
        XCTAssertFalse(selectedLoadedStrokes.isEmpty)
        let selectedLoadedBounds = InkBounds.enclosing(selectedLoadedStrokes.map(\.bounds))
        print(
            "production_preparation_geometry"
                + " source_size=\(String(describing: sourceCoordinateSpace?.size))"
                + " target_size=\(String(describing: targetCoordinateSpace?.size))"
                + " chord_frame=\(chordRegion.frame)"
                + " selected_loaded_bounds=\(selectedLoadedBounds)"
        )
        for (index, inputFrame) in chordRegion.inputFrames.enumerated() {
            print(
                "production_preparation_lane_\(index)"
                    + " view=\(inputFrame)"
                    + " local=\(inputFrame.offsetBy(dx: -chordRegion.frame.minX, dy: -chordRegion.frame.minY))"
            )
        }

        let preparation = ChordInkRecognitionPreparation.prepare(
            ChordInkRecognitionPreparationRequest(
                requestID: UUID(),
                scheduledAt: Date(),
                requestedDelay: 0,
                drawingData: loadedDrawingData,
                chordFrame: chordRegion.frame,
                pageLayout: pageLayout,
                flow: .draftPreview,
                options: .includingSymbolLedgerDiagnostics,
                layoutStyle: chart.layoutStyle
            )
        )
        guard case .ready(let requests, let usesBatch) = preparation.outcome else {
            XCTFail("Live production preparation did not produce recognition targets: \(preparation.outcome)")
            return
        }

        XCTAssertTrue(usesBatch)
        XCTAssertEqual(preparation.rawBatchTargetCount, preparation.boundedBatchTargetCount)

        let selectedRequests = requests.filter { request in
            !Set(request.strokes).isDisjoint(with: selectedLoadedStrokes)
        }
        XCTAssertTrue(
            selectedRequests.allSatisfy { request in
                Set(request.strokes).isSubset(of: selectedLoadedStrokes)
            },
            "Production grouping must not merge the captured row with ink from another system."
        )
        let recognizer = ChordInkMaximumTrustRecognizer()
        let results = selectedRequests.map { request in
            recognizer.recognize(strokes: request.strokes, options: request.options)
        }
        let visibleChoices = results.map { result in
            Array(ChordInkRenderResolutionPolicy.candidateTexts(for: result).prefix(3))
        }

        print(
            "production_preparation route_targets=\(preparation.rawBatchTargetCount) "
                + "bounded_targets=\(preparation.boundedBatchTargetCount) "
                + "selected_targets=\(selectedRequests.count)"
        )
        XCTAssertEqual(
            results.compactMap { $0.match?.displayText },
            expectedSequence,
            "The live preparation path must deliver every captured row chord to the recognizer."
        )
        XCTAssertEqual(visibleChoices.count, expectedSequence.count)
        for (expectedText, choices) in zip(expectedSequence, visibleChoices) {
            XCTAssertTrue(
                choices.contains(expectedText),
                "The live confirmation UI hid \(expectedText) behind choices \(choices)."
            )
        }
    }

    private func inferredStoredPageLayout(for chart: Chart) -> LeadSheetPageLayout? {
        let pageWritingSize = chart.pageHandwrittenNotationCoordinateSpace?.size
        let storedChordSize = chart.pageHandwrittenChordCoordinateSpace?.size
        guard let referenceSize = pageWritingSize ?? storedChordSize,
              referenceSize.width > 0,
              referenceSize.height > 0 else {
            return nil
        }

        let pageWidthCandidates = [
            referenceSize.width + 68,
            referenceSize.width + 56,
            referenceSize.width + 160,
            referenceSize.width
        ]
        let pageHeightCandidates = [
            referenceSize.height + 80,
            referenceSize.height + 60,
            referenceSize.height
        ]

        let candidates = pageWidthCandidates
            .flatMap { pageWidth in
                pageHeightCandidates.map { pageHeight in
                    LeadSheetPageLayoutEngine.pageLayout(
                        for: chart,
                        pageSize: CGSize(width: pageWidth, height: pageHeight),
                        includesChordInkContinuationLanes: true
                    )
                }
            }

        // Stored chord coordinates are not a page size. The old fixed margin
        // guesses missed Rhythm Section's 130-point margin, turning a saved
        // 670-point canvas into 700 points and distorting the recognition
        // evidence. Refine by each measured frame-size residual instead of
        // adding another hardcoded style-specific page margin.
        let refinedCandidates = candidates.flatMap { layout in
            var widthAdjustments: [CGFloat] = [0]
            var heightAdjustments: [CGFloat] = [0]
            if let pageWritingSize {
                let size = LeadSheetActiveInkScope.pageWritingFrame(for: layout).size
                widthAdjustments.append(pageWritingSize.width - size.width)
                heightAdjustments.append(pageWritingSize.height - size.height)
            }
            if let storedChordSize {
                let size = LeadSheetActiveInkScope.chordWritingFrame(for: layout).size
                widthAdjustments.append(storedChordSize.width - size.width)
                heightAdjustments.append(storedChordSize.height - size.height)
            }
            return widthAdjustments.flatMap { widthAdjustment in
                heightAdjustments.compactMap { heightAdjustment -> LeadSheetPageLayout? in
                    let size = CGSize(
                        width: layout.pageBounds.width + widthAdjustment,
                        height: layout.pageBounds.height + heightAdjustment
                    )
                    guard size.width > 0, size.height > 0 else { return nil }
                    return LeadSheetPageLayoutEngine.pageLayout(
                        for: chart,
                        pageSize: size,
                        includesChordInkContinuationLanes: true
                    )
                }
            }
        }
        return (candidates + refinedCandidates)
            .min { lhs, rhs in
                storedLayoutDistance(
                    lhs,
                    pageWritingSize: pageWritingSize,
                    chordSize: storedChordSize
                ) < storedLayoutDistance(
                    rhs,
                    pageWritingSize: pageWritingSize,
                    chordSize: storedChordSize
                )
            }
    }

    private func storedLayoutDistance(
        _ layout: LeadSheetPageLayout,
        pageWritingSize: CGSize?,
        chordSize: CGSize?
    ) -> CGFloat {
        var distance: CGFloat = 0
        if let pageWritingSize {
            let inferredPageSize = LeadSheetActiveInkScope.pageWritingFrame(for: layout).size
            distance += abs(inferredPageSize.width - pageWritingSize.width)
                + abs(inferredPageSize.height - pageWritingSize.height)
        }
        if let chordSize {
            let inferredChordSize = LeadSheetActiveInkScope.chordWritingFrame(for: layout).size
            distance += abs(inferredChordSize.width - chordSize.width)
                + abs(inferredChordSize.height - chordSize.height)
        }
        return distance
    }

    /// Replays the drawing after every newly-created Pencil stroke. A finished
    /// row can group correctly even when an earlier live preview temporarily
    /// absorbs the first strokes of the next chord, so the final-row assertion
    /// above is not sufficient evidence for the authoring path.
    private func auditSequentialPrefixes(
        strokes: [InkStroke],
        finalGroups: [ChordInkSequentialGroup],
        expectedSequence: [String]
    ) {
        guard !strokes.isEmpty,
              finalGroups.count == expectedSequence.count else {
            XCTFail("Prefix audit requires one final group per expected chord.")
            return
        }

        let completionStrokeIndexes = finalGroups.map { group in
            group.strokeIndices.max() ?? -1
        }
        XCTAssertEqual(
            completionStrokeIndexes,
            completionStrokeIndexes.sorted(),
            "Expected row groups to finish in Pencil creation order."
        )

        let grouper = ChordInkSequentialGrouper()
        let recognizer = ChordInkMaximumTrustRecognizer()
        var previousSignature: String?

        for prefixCount in 1...strokes.count {
            let prefixStrokes = Array(strokes.prefix(prefixCount))
            let prefixGroups = grouper.groups(
                for: prefixStrokes.enumerated().map { (index: $0.offset, stroke: $0.element) }
            )
            let prefixResults = prefixGroups.map { group in
                recognizer.recognize(
                    strokes: group.strokeIndices.map { prefixStrokes[$0] },
                    options: .includingSymbolLedgerDiagnostics
                )
            }
            let decisions = prefixResults.map(ChordInkRecognitionPolicy.decision(for:))
            let signature = prefixGroups.enumerated().map { index, group in
                let result = prefixResults[index]
                let decision = decisions[index]
                return "\(group.strokeIndices):\(group.rootText ?? "nil")"
                    + ":\(result.match?.displayText ?? "nil")"
                    + ":\(decision.action.rawValue)"
            }.joined(separator: " | ")
            if signature != previousSignature {
                print("prefix_\(prefixCount)=\(signature)")
                previousSignature = signature
            }

            let completedChordCount = completionStrokeIndexes.prefix {
                $0 < prefixCount
            }.count
            guard completedChordCount > 0 else {
                continue
            }

            for completedIndex in 0..<completedChordCount {
                let expectedText = expectedSequence[completedIndex]
                let finalIndexes = Set(finalGroups[completedIndex].strokeIndices)
                guard let firstIndex = finalGroups[completedIndex].strokeIndices.min(),
                      let owningGroupIndex = prefixGroups.firstIndex(where: {
                        $0.strokeIndices.contains(firstIndex)
                      }) else {
                    XCTFail("Prefix \(prefixCount) lost completed chord \(expectedText). groups=\(signature)")
                    continue
                }
                XCTAssertEqual(
                    Set(prefixGroups[owningGroupIndex].strokeIndices),
                    finalIndexes,
                    "Prefix \(prefixCount) changed completed ink ownership for \(expectedText). groups=\(signature)"
                )
                let result = prefixResults[owningGroupIndex]
                let decision = decisions[owningGroupIndex]
                XCTAssertEqual(
                    result.match?.displayText,
                    expectedText,
                    "Prefix \(prefixCount) retroactively changed or lost the read of \(expectedText). groups=\(signature)"
                )
                if result.match?.displayText != expectedText {
                    XCTAssertNotEqual(
                        decision.action,
                        .trusted,
                        "Prefix \(prefixCount) trusted \(decision.acceptedText ?? "nil") "
                            + "after completed chord \(expectedText). groups=\(signature)"
                    )
                }
            }

            if let completedGroupIndex = completionStrokeIndexes.firstIndex(of: prefixCount - 1) {
                XCTAssertGreaterThanOrEqual(
                    prefixResults.count,
                    completedGroupIndex + 1,
                    "Prefix \(prefixCount) lost a completed chord target. groups=\(signature)"
                )
                guard prefixResults.indices.contains(completedGroupIndex) else {
                    continue
                }
                XCTAssertEqual(
                    prefixResults[completedGroupIndex].match?.displayText,
                    expectedSequence[completedGroupIndex],
                    "Prefix \(prefixCount) did not read the just-completed chord. groups=\(signature)"
                )
            }
        }
    }

    private func selectedChart(in snapshot: ChartLibrarySnapshot) -> Chart? {
        if let chartIDText = ProcessInfo.processInfo.environment["ICHART_REPLAY_CHART_ID"],
           let chartID = UUID(uuidString: chartIDText),
           let chart = snapshot.charts.first(where: { $0.id == chartID }) {
            return chart
        }

        let title = ProcessInfo.processInfo.environment["ICHART_REPLAY_CHART_TITLE"]
            ?? "Chord Writing Test Chart"
        return snapshot.charts.first { $0.title == title }
    }

    private func printRecognition(label: String, result: ChordInkRecognitionResult) {
        let decision = ChordInkRecognitionPolicy.decision(for: result)
        let scores = result.candidateScores
            .prefix(8)
            .map { score in
                let display = score.displayText ?? score.text
                return "\(display):\(String(format: "%.3f", score.confidence))"
            }
            .joined(separator: ",")
        let glyphs = result.glyphCandidates.enumerated().map { index, candidates in
            let summary = candidates.prefix(6).map {
                "\($0.text):\(String(format: "%.3f", $0.confidence))"
            }.joined(separator: ",")
            return "glyph[\(index)]=[\(summary)]"
        }.joined(separator: " ")

        print(
            "\(label) match=\(result.match?.displayText ?? "nil") "
                + "confidence=\(String(format: "%.3f", result.confidence)) "
                + "action=\(decision.action.rawValue) "
                + "trust=\(result.trustEvidence?.outcome.rawValue ?? "none") "
                + "gap=\(decision.confidenceGap.map { String(format: "%.3f", $0) } ?? "nil") "
                + "scores=[\(scores)] "
                + "raw=\(Array(result.rawCandidates.prefix(12))) \(glyphs)"
        )
    }
}
#endif
