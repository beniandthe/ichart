import XCTest
@testable import SmartChart

final class FileChartRepositoryTests: XCTestCase {
    func testLoadSnapshotReturnsNilWhenFileDoesNotExist() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repository = FileChartRepository(
            url: temporaryDirectory.appendingPathComponent("library-state.json")
        )

        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        XCTAssertNil(try repository.loadSnapshot())
    }

    func testRoundTripsSnapshotToDisk() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repository = FileChartRepository(
            url: temporaryDirectory.appendingPathComponent("library-state.json")
        )
        let snapshot = ChartLibrarySnapshot(
            charts: ChartSamples.previewCharts,
            selectedChartID: ChartSamples.previewCharts.last?.id,
            entitlements: AppEntitlements(activePlan: .proLifetime)
        )

        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        try repository.saveSnapshot(snapshot)
        let loadedSnapshot = try XCTUnwrap(repository.loadSnapshot())

        XCTAssertEqual(loadedSnapshot, snapshot)
    }

    func testRoundTripsSnapshotWhenPathContainsSpaces() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
        let repository = FileChartRepository(
            url: temporaryDirectory.appendingPathComponent("library-state.json")
        )
        let snapshot = ChartLibrarySnapshot(
            charts: [Chart.blank(title: "Chord Writing Test Chart", key: .cMajor)],
            selectedChartID: nil,
            entitlements: AppEntitlements(activePlan: .free)
        )

        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory.deletingLastPathComponent())
        }

        try repository.saveSnapshot(snapshot)
        let loadedSnapshot = try XCTUnwrap(repository.loadSnapshot())

        XCTAssertEqual(loadedSnapshot, snapshot)
    }

    func testRoundTripsV1SimpleChordSheetAuthoringStateToDisk() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repository = FileChartRepository(
            url: temporaryDirectory.appendingPathComponent("library-state.json")
        )
        var chart = Chart.blank(
            title: "Simple V1 Persistence",
            measureCount: 4,
            layoutStyle: .simpleChordSheet
        )
        chart.composerCredit = "Composer"
        chart.styleNote = "Medium Swing"
        chart.setMatchedFontFamily(.museJazz)
        chart.setChordFontOverride(.finaleJazz)
        chart.setHeaderFontOverride(.leland)
        chart.setTextFontOverride(.petaluma)
        let measureIDs = chart.measures.map(\.id)
        chart.addSectionLabel(text: "A")
        XCTAssertTrue(chart.insertSimpleSystemBreak(before: measureIDs[2]))
        XCTAssertEqual(chart.setMeasureManualLayoutWidth(180, for: measureIDs[0]), 180)
        _ = try XCTUnwrap(
            chart.addRepeatSpan(startMeasureID: measureIDs[0], endMeasureID: measureIDs[3])
        )
        _ = try XCTUnwrap(
            chart.addEndingSpan(.ending1, startMeasureID: measureIDs[0], endMeasureID: measureIDs[1])
        )
        _ = try XCTUnwrap(
            chart.addPointRoadmapMarker(.fine, anchorMeasureID: measureIDs[3])
        )
        _ = try XCTUnwrap(
            chart.addCueText("freely", anchorMeasureID: measureIDs[1], position: .above, emphasis: .subtle)
        )
        _ = try XCTUnwrap(
            chart.addFreehandSymbol(
                anchorMeasureID: measureIDs[1],
                lane: .chartArea,
                normalizedFrame: FreehandSymbolNormalizedFrame(x: 0.12, y: 0.18, width: 0.2, height: 0.1),
                measureRelativeFrame: FreehandSymbolMeasureFrame(offsetX: 12, offsetY: -18, width: 34, height: 16),
                drawingData: Data([9, 7, 5, 3])
            )
        )
        XCTAssertTrue(
            chart.appendRecognizedChord(
                try ChordSymbolParser.parse("Bb△7"),
                rawInput: "Bb△7",
                to: measureIDs[0],
                atFraction: 0.05
            )
        )
        XCTAssertTrue(
            chart.appendRecognizedChord(
                try ChordSymbolParser.parse("D-7"),
                rawInput: "D-7",
                to: measureIDs[0],
                atFraction: 0.86
            )
        )
        let snapshot = ChartLibrarySnapshot(
            charts: [chart],
            selectedChartID: chart.id,
            entitlements: AppEntitlements(activePlan: .proLifetime)
        )

        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        try repository.saveSnapshot(snapshot)
        let loadedSnapshot = try XCTUnwrap(repository.loadSnapshot())
        let loadedChart = try XCTUnwrap(loadedSnapshot.charts.first)

        XCTAssertEqual(loadedSnapshot, snapshot)
        XCTAssertEqual(loadedSnapshot.selectedChartID, chart.id)
        XCTAssertEqual(loadedChart.layoutStyle, .simpleChordSheet)
        XCTAssertEqual(loadedChart.typography.matchedSet, .museJazz)
        XCTAssertEqual(loadedChart.typography.chordOverride, .finaleJazz)
        XCTAssertEqual(loadedChart.typography.headerOverride, .leland)
        XCTAssertEqual(loadedChart.typography.textOverride, .petaluma)
        XCTAssertEqual(loadedChart.systems.count, 2)
        XCTAssertEqual(loadedChart.systems[1].lineBreakRule, .forced)
        XCTAssertEqual(loadedChart.measures.map(\.id), measureIDs)
        XCTAssertEqual(loadedChart.measure(id: measureIDs[0])?.manualLayoutWidth, 180)
        XCTAssertEqual(loadedChart.sectionLabels.first?.text, "A")
        XCTAssertEqual(loadedChart.cueTexts.first?.text, "freely")
        XCTAssertEqual(loadedChart.cueTexts.first?.position, .above)
        XCTAssertEqual(Set(loadedChart.roadmapObjects.map(\.type)), [.repeatSpan, .ending1, .fine])
        XCTAssertEqual(loadedChart.freehandSymbols.first?.lane, .chartArea)
        XCTAssertEqual(loadedChart.freehandSymbols.first?.anchorMeasureID, measureIDs[1])
        XCTAssertEqual(loadedChart.measure(id: measureIDs[0])?.chordEvents.map(\.rawInput), ["Bb△7", "D-7"])
    }

    func testRoundTripsV1RhythmSectionAuthoringStateToDisk() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repository = FileChartRepository(
            url: temporaryDirectory.appendingPathComponent("library-state.json")
        )
        var chart = Chart.blank(
            title: "Rhythm V1 Persistence",
            key: .bFlatMajor,
            measureCount: 4,
            layoutStyle: .rhythmSectionSheet
        )
        chart.defaultMeter = Meter(numerator: 4, denominator: 4)
        chart.setMatchedFontFamily(.petaluma)
        let measureIDs = chart.measures.map(\.id)
        chart.addSectionLabel(text: "B")
        _ = try XCTUnwrap(
            chart.addRepeatSpan(startMeasureID: measureIDs[0], endMeasureID: measureIDs[3])
        )
        _ = try XCTUnwrap(
            chart.addEndingSpan(.ending2, startMeasureID: measureIDs[2], endMeasureID: measureIDs[3])
        )
        _ = try XCTUnwrap(
            chart.addPointRoadmapMarker(.codaMarker, anchorMeasureID: measureIDs[3])
        )
        _ = try XCTUnwrap(
            chart.addCueText("hits", anchorMeasureID: measureIDs[1], position: .below, emphasis: .normal)
        )
        _ = try XCTUnwrap(
            chart.addFreehandSymbol(
                anchorMeasureID: measureIDs[1],
                lane: .belowMeasure,
                normalizedFrame: FreehandSymbolNormalizedFrame(x: 0.18, y: 0.62, width: 0.28, height: 0.2),
                measureRelativeFrame: FreehandSymbolMeasureFrame(offsetX: 18, offsetY: 82, width: 44, height: 28),
                drawingData: Data([1, 3, 5, 7])
            )
        )
        XCTAssertTrue(
            chart.setMeasureRhythmMap(
                [.quarter, .quarter, .quarter, .quarter],
                drawingData: Data([11, 22, 33]),
                for: measureIDs[0]
            )
        )
        XCTAssertTrue(
            chart.setMeasureHandwrittenRhythmicNotationDrawing(
                Data([44, 55, 66]),
                for: measureIDs[2]
            )
        )
        try appendChord("C7", to: measureIDs[0], in: &chart, atFraction: 0.05)
        try appendChord("G/B", to: measureIDs[1], in: &chart, atFraction: 0.05)

        let snapshot = ChartLibrarySnapshot(
            charts: [chart],
            selectedChartID: chart.id,
            entitlements: AppEntitlements(activePlan: .proLifetime)
        )

        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        try repository.saveSnapshot(snapshot)
        let loadedSnapshot = try XCTUnwrap(repository.loadSnapshot())
        let loadedChart = try XCTUnwrap(loadedSnapshot.charts.first)

        XCTAssertEqual(loadedSnapshot, snapshot)
        XCTAssertEqual(loadedSnapshot.selectedChartID, chart.id)
        XCTAssertEqual(loadedChart.layoutStyle, .rhythmSectionSheet)
        XCTAssertEqual(loadedChart.typography.matchedSet, .petaluma)
        XCTAssertEqual(loadedChart.measures.map(\.id), measureIDs)
        XCTAssertEqual(loadedChart.sectionLabels.first?.text, "B")
        XCTAssertEqual(loadedChart.cueTexts.first?.text, "hits")
        XCTAssertEqual(loadedChart.cueTexts.first?.position, .below)
        XCTAssertEqual(Set(loadedChart.roadmapObjects.map(\.type)), [.repeatSpan, .ending2, .codaMarker])
        XCTAssertEqual(loadedChart.freehandSymbols.first?.lane, .belowMeasure)
        XCTAssertEqual(loadedChart.freehandSymbols.first?.anchorMeasureID, measureIDs[1])
        XCTAssertEqual(
            loadedChart.measure(id: measureIDs[0])?.rhythmMap?.values,
            [.quarter, .quarter, .quarter, .quarter]
        )
        XCTAssertEqual(loadedChart.measure(id: measureIDs[0])?.rhythmMap?.drawingData, Data([11, 22, 33]))
        XCTAssertEqual(loadedChart.measure(id: measureIDs[2])?.handwrittenRhythmicNotationData, Data([44, 55, 66]))
        XCTAssertEqual(loadedChart.measure(id: measureIDs[0])?.chordEvents.map(\.rawInput), ["C7"])
        XCTAssertEqual(loadedChart.measure(id: measureIDs[1])?.chordEvents.map(\.rawInput), ["G/B"])
    }

    func testRoundTripsMixedV1AuthoringSnapshotWithoutDroppingLiveInkOrRenderedState() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repository = FileChartRepository(
            url: temporaryDirectory.appendingPathComponent("library-state.json")
        )
        var simpleChart = Chart.blank(
            title: "Simple Contract",
            measureCount: 4,
            layoutStyle: .simpleChordSheet
        )
        let simpleMeasureIDs = simpleChart.measures.map(\.id)
        let simplePendingChordInk = Data("simple-pending-chord-ink".utf8)
        let simpleHeaderInk = Data("simple-handwritten-header".utf8)
        let simpleCommittedChordInk = Data("simple-committed-Bbmaj7".utf8)
        simpleChart.styleNote = "Medium Swing"
        simpleChart.composerCredit = "Composer"
        simpleChart.setHeaderInputMode(.handwritten)
        simpleChart.setMatchedFontFamily(.museJazz)
        simpleChart.setChordFontOverride(.finaleJazz)
        XCTAssertTrue(simpleChart.setPageHandwrittenHeaderDrawing(simpleHeaderInk))
        XCTAssertTrue(simpleChart.setPageHandwrittenChordDrawing(simplePendingChordInk))
        XCTAssertTrue(simpleChart.insertSimpleSystemBreak(before: simpleMeasureIDs[2]))
        XCTAssertEqual(simpleChart.setMeasureManualLayoutWidth(192, for: simpleMeasureIDs[0]), 192)
        simpleChart.addSectionLabel(text: "A")
        _ = try XCTUnwrap(
            simpleChart.addCueText(
                "pocket",
                anchorMeasureID: simpleMeasureIDs[1],
                position: .above,
                emphasis: .subtle
            )
        )
        _ = try XCTUnwrap(
            simpleChart.addRepeatSpan(startMeasureID: simpleMeasureIDs[0], endMeasureID: simpleMeasureIDs[3])
        )
        _ = try XCTUnwrap(
            simpleChart.addEndingSpan(.ending1, startMeasureID: simpleMeasureIDs[2], endMeasureID: simpleMeasureIDs[3])
        )
        _ = try XCTUnwrap(
            simpleChart.addPointRoadmapMarker(.fine, anchorMeasureID: simpleMeasureIDs[3])
        )
        _ = try XCTUnwrap(
            simpleChart.addFreehandSymbol(
                anchorMeasureID: simpleMeasureIDs[1],
                lane: .chartArea,
                normalizedFrame: FreehandSymbolNormalizedFrame(x: 0.18, y: 0.24, width: 0.16, height: 0.12),
                measureRelativeFrame: FreehandSymbolMeasureFrame(offsetX: 14, offsetY: -22, width: 36, height: 18),
                drawingData: Data("simple-freehand".utf8)
            )
        )
        XCTAssertTrue(
            simpleChart.appendRecognizedChord(
                try ChordSymbolParser.parse("Bb△7"),
                rawInput: "Bbmaj7",
                to: simpleMeasureIDs[0],
                atFraction: 0.06,
                sourceInkData: simpleCommittedChordInk,
                sourceCandidateSignature: ["Bb△7", "Bb"]
            )
        )

        var rhythmChart = Chart.blank(
            title: "Rhythm Contract",
            measureCount: 4,
            layoutStyle: .rhythmSectionSheet
        )
        let rhythmMeasureIDs = rhythmChart.measures.map(\.id)
        let rhythmPendingChordInk = Data("rhythm-pending-chord-ink".utf8)
        let rhythmHeaderInk = Data("rhythm-handwritten-header".utf8)
        let committedRhythmInk = Data("rhythm-committed-slashes".utf8)
        let unresolvedRhythmInk = Data("rhythm-unresolved-quarter-pass".utf8)
        let rhythmCommittedChordInk = Data("rhythm-committed-G-slash-B".utf8)
        rhythmChart.setHeaderInputMode(.typed)
        XCTAssertTrue(rhythmChart.setPageHandwrittenHeaderDrawing(rhythmHeaderInk))
        rhythmChart.setMatchedFontFamily(.petaluma)
        XCTAssertTrue(rhythmChart.setPageHandwrittenChordDrawing(rhythmPendingChordInk))
        rhythmChart.addSectionLabel(text: "B")
        _ = try XCTUnwrap(
            rhythmChart.addCueText(
                "hits",
                anchorMeasureID: rhythmMeasureIDs[1],
                position: .below,
                emphasis: .normal
            )
        )
        _ = try XCTUnwrap(
            rhythmChart.addRepeatSpan(startMeasureID: rhythmMeasureIDs[0], endMeasureID: rhythmMeasureIDs[3])
        )
        _ = try XCTUnwrap(
            rhythmChart.addPointRoadmapMarker(.codaMarker, anchorMeasureID: rhythmMeasureIDs[2])
        )
        _ = try XCTUnwrap(
            rhythmChart.addFreehandSymbol(
                anchorMeasureID: rhythmMeasureIDs[1],
                lane: .belowMeasure,
                normalizedFrame: FreehandSymbolNormalizedFrame(x: 0.2, y: 0.56, width: 0.26, height: 0.18),
                drawingData: Data("rhythm-below-freehand".utf8)
            )
        )
        XCTAssertTrue(
            rhythmChart.setMeasureRhythmMap(
                [.slash, .slash, .slash, .slash],
                drawingData: committedRhythmInk,
                for: rhythmMeasureIDs[0]
            )
        )
        XCTAssertTrue(
            rhythmChart.setMeasureHandwrittenRhythmicNotationDrawing(
                unresolvedRhythmInk,
                for: rhythmMeasureIDs[2]
            )
        )
        XCTAssertTrue(
            rhythmChart.appendRecognizedChord(
                try ChordSymbolParser.parse("G/B"),
                rawInput: "G/B",
                to: rhythmMeasureIDs[0],
                atFraction: 0.08,
                sourceInkData: rhythmCommittedChordInk,
                sourceCandidateSignature: ["G/B"]
            )
        )

        let snapshot = ChartLibrarySnapshot(
            charts: [simpleChart, rhythmChart],
            selectedChartID: rhythmChart.id,
            entitlements: AppEntitlements(activePlan: .studioSubscription)
        )

        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        try repository.saveSnapshot(snapshot)
        let loadedSnapshot = try XCTUnwrap(repository.loadSnapshot())
        let loadedSimpleChart = try XCTUnwrap(loadedSnapshot.charts.first { $0.id == simpleChart.id })
        let loadedRhythmChart = try XCTUnwrap(loadedSnapshot.charts.first { $0.id == rhythmChart.id })
        let loadedSimpleChord = try XCTUnwrap(
            loadedSimpleChart.measure(id: simpleMeasureIDs[0])?.chordEvents.first
        )
        let loadedRhythmChord = try XCTUnwrap(
            loadedRhythmChart.measure(id: rhythmMeasureIDs[0])?.chordEvents.first
        )

        XCTAssertEqual(loadedSnapshot, snapshot)
        XCTAssertEqual(loadedSnapshot.selectedChartID, rhythmChart.id)
        XCTAssertEqual(loadedSnapshot.entitlements.activePlan, .studioSubscription)
        XCTAssertEqual(ChartLayoutStyle.v1NewChartOptions, [.simpleChordSheet, .rhythmSectionSheet])
        XCTAssertFalse(ChartLayoutStyle.v1NewChartOptions.contains(.leadSheet))

        XCTAssertEqual(loadedSimpleChart.layoutStyle, .simpleChordSheet)
        XCTAssertEqual(loadedSimpleChart.headerInputMode, .handwritten)
        XCTAssertEqual(loadedSimpleChart.pageHandwrittenHeaderData, simpleHeaderInk)
        XCTAssertEqual(loadedSimpleChart.pageHandwrittenChordData, simplePendingChordInk)
        XCTAssertEqual(loadedSimpleChart.typography.matchedSet, .museJazz)
        XCTAssertEqual(loadedSimpleChart.typography.chordOverride, .finaleJazz)
        XCTAssertEqual(loadedSimpleChart.systems.count, 2)
        XCTAssertEqual(loadedSimpleChart.measure(id: simpleMeasureIDs[0])?.manualLayoutWidth, 192)
        XCTAssertEqual(loadedSimpleChart.sectionLabels.first?.text, "A")
        XCTAssertEqual(loadedSimpleChart.cueTexts.first?.text, "pocket")
        XCTAssertEqual(Set(loadedSimpleChart.roadmapObjects.map(\.type)), [.repeatSpan, .ending1, .fine])
        XCTAssertEqual(loadedSimpleChart.freehandSymbols.first?.lane, .chartArea)
        XCTAssertEqual(loadedSimpleChart.freehandSymbols.first?.measureRelativeFrame?.width, 36)
        XCTAssertEqual(loadedSimpleChord.symbol.displayText, "Bb△7")
        XCTAssertEqual(loadedSimpleChord.rawInput, "Bbmaj7")
        XCTAssertEqual(loadedSimpleChord.sourceInkData, simpleCommittedChordInk)
        XCTAssertEqual(loadedSimpleChord.sourceCandidateSignature, ["Bb△7", "Bb"])

        XCTAssertEqual(loadedRhythmChart.layoutStyle, .rhythmSectionSheet)
        XCTAssertEqual(loadedRhythmChart.headerInputMode, .typed)
        XCTAssertEqual(loadedRhythmChart.pageHandwrittenHeaderData, rhythmHeaderInk)
        XCTAssertEqual(loadedRhythmChart.pageHandwrittenChordData, rhythmPendingChordInk)
        XCTAssertEqual(loadedRhythmChart.typography.matchedSet, .petaluma)
        XCTAssertEqual(loadedRhythmChart.sectionLabels.first?.text, "B")
        XCTAssertEqual(loadedRhythmChart.cueTexts.first?.text, "hits")
        XCTAssertEqual(Set(loadedRhythmChart.roadmapObjects.map(\.type)), [.repeatSpan, .codaMarker])
        XCTAssertEqual(loadedRhythmChart.freehandSymbols.first?.lane, .belowMeasure)
        XCTAssertEqual(
            loadedRhythmChart.measure(id: rhythmMeasureIDs[0])?.rhythmMap?.values,
            [.slash, .slash, .slash, .slash]
        )
        XCTAssertEqual(loadedRhythmChart.measure(id: rhythmMeasureIDs[0])?.rhythmMap?.drawingData, committedRhythmInk)
        XCTAssertEqual(
            loadedRhythmChart.measure(id: rhythmMeasureIDs[2])?.handwrittenRhythmicNotationData,
            unresolvedRhythmInk
        )
        XCTAssertNil(loadedRhythmChart.measure(id: rhythmMeasureIDs[2])?.rhythmMap)
        XCTAssertEqual(loadedRhythmChord.symbol.displayText, "G/B")
        XCTAssertEqual(loadedRhythmChord.rawInput, "G/B")
        XCTAssertEqual(loadedRhythmChord.sourceInkData, rhythmCommittedChordInk)
        XCTAssertEqual(loadedRhythmChord.sourceCandidateSignature, ["G/B"])
    }

    private func appendChord(
        _ text: String,
        to measureID: UUID,
        in chart: inout Chart,
        atFraction fraction: Double
    ) throws {
        XCTAssertTrue(
            chart.appendRecognizedChord(
                try ChordSymbolParser.parse(text),
                rawInput: text,
                to: measureID,
                atFraction: fraction
            )
        )
    }
}
