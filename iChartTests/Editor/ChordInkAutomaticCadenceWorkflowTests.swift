#if canImport(UIKit) && canImport(PencilKit)
import Foundation
import PencilKit
import SwiftUI
import UIKit
import XCTest
@testable import iChart

/// Mounts the shipping Editor, including its real preview/activity callbacks
/// and automatic work items. The reader is deterministic, but no test callback
/// invokes rendering or fabricates a preview/census.
@MainActor
final class ChordInkAutomaticCadenceWorkflowTests: XCTestCase {
    func testNormalFThenGThenARendersEarlierChordsBeforeLaterReadersFinishInBothStyles() async throws {
        for style in supportedStyles {
            let host = try await mount(style: style, measureCount: 4)
            defer { host.close() }
            let positions = try targetOrigins(in: host, indices: [0, 1, 2])
            try await driveThreeChordCadence(host, positions: positions)
        }
    }

    func testWritingAcrossARowKeepsEarlierCadenceAndRetainedSourceInBothStyles() async throws {
        for style in supportedStyles {
            let host = try await mount(style: style, measureCount: 8, startsSecondRow: true)
            defer { host.close() }
            let positions = try targetOrigins(in: host, indices: [2, 3, 4])
            XCTAssertGreaterThan(positions[.a]!.y, positions[.g]!.y,
                "The last chord must actually enter the next writing row")
            try await driveThreeChordCadence(host, positions: positions)
        }
    }

    func testBarlineInsideOriginalOpenMeasureMaturesWhileLaterChordInkContinuesInBothStyles() async throws {
        for style in supportedStyles {
            let host = try await mount(style: style, measureCount: 1, commitsMeasures: false)
            defer { host.close() }
            let originalID = try XCTUnwrap(host.model.chart.measures.first?.id)
            let geometry = try firstLane(in: host)
            let y = geometry.lane.minY + max(5, (geometry.lane.height - 34) / 2) - geometry.region.minY
            let x = geometry.lane.minX - geometry.region.minX
            let positions: [CadenceReader.Symbol: CGPoint] = [
                .f: CGPoint(x: x + geometry.lane.width * 0.08, y: y),
                .g: CGPoint(x: x + geometry.lane.width * 0.56, y: y),
                .a: CGPoint(x: x + geometry.lane.width * 0.80, y: y)
            ]
            host.reader.setOrigins(positions)
            let f = letter(.f, at: positions[.f]!, seed: 71)
            append(f, to: host)
            assertTrue(await eventually(timeout: 0.8) { host.reader.hasCompleted(.f) })

            let barX = x + geometry.lane.width * 0.37
            let bar = stroke([
                CGPoint(x: barX, y: geometry.lane.minY + geometry.lane.height * 0.06 - geometry.region.minY),
                CGPoint(x: barX, y: geometry.lane.maxY - geometry.lane.height * 0.06 - geometry.region.minY)
            ], seed: 72)
            let barEndedAt = append(bar, to: host)
            assertTrue(await eventually(timeout: 0.8) {
                host.view.hasCurrentAutomaticChordCensus && host.view.chordPreviewState.draftBarlines.count == 1
            }, "The normal preparation path must recognize the internal barline")
            XCTAssertEqual(host.model.chart.measures.count, 1,
                "A newly drawn structural mark still needs its own configured grace")

            let g = letter(.g, at: positions[.g]!, seed: 73)
            let heldChart = host.model.chart
            let retainedBeforeG = host.ink.drawing.strokes
            host.view.canvasViewDidBeginUsingTool(host.ink)
            var step = 0
            // The structural stroke is old enough to complete while the user
            // keeps adding points to the next chord. No long global idle is
            // provided, and the active Pencil stroke must never be replaced.
            repeat {
                let portion = prefix(of: .g, at: positions[.g]!, count: min(2 + step, 8), seed: 73)
                setActiveStroke(portion, after: retainedBeforeG, in: host)
                let expected = host.ink.drawing
                try await Task.sleep(nanoseconds: 80_000_000)
                XCTAssertEqual(host.model.chart.measures.map(\.id), heldChart.measures.map(\.id))
                XCTAssertEqual(events(host.model.chart).map(\.id), events(heldChart).map(\.id))
                assertSameInk(expected, host.ink.drawing)
                step += 1
            } while Date() < barEndedAt.addingTimeInterval(ChordInkAutomaticRenderPolicy.structuralIdleDelay + 0.12)
            setActiveStroke(g, after: retainedBeforeG, in: host)
            host.view.canvasViewDidEndUsingTool(host.ink)
            let nextChordUp = try XCTUnwrap(host.view.chordDraftRenderCoordinator?.lastInputAt)
            print("CADENCE_PEN_UP", style.rawValue, "census", host.view.hasCurrentAutomaticChordCensus,
                "clock", host.view.chordDraftRenderCoordinator?.structuralMaturity.nextDeadline?.timeIntervalSinceNow ?? -1)
            assertTrue(await eventually(until: nextChordUp.addingTimeInterval(0.85)) {
                host.model.chart.measures.count == 2 && self.texts(host.model.chart).contains("F")
            }, "An aged barline and the earlier chord must not restart a shared two-second wait after the later stroke")
            print("CADENCE_PROGRESS", style.rawValue, "measures", host.model.chart.measures.count,
                "rendered", events(host.model.chart).count, "census", host.view.hasCurrentAutomaticChordCensus,
                "barlines", host.view.chordPreviewState.draftBarlines.count,
                "clock", host.view.chordDraftRenderCoordinator?.structuralMaturity.nextDeadline?.timeIntervalSinceNow ?? -1,
                "reason", String(describing: host.view.chordDraftRenderCoordinator?.lastAutomaticAttempt?.feedback.globalReason))
            XCTAssertEqual(host.model.chart.measures.first?.id, originalID)
            XCTAssertTrue(host.reader.isHeld(.g))
            assertSameInk(PKDrawing(strokes: [g]), host.ink.drawing)

            // Continue writing after that safe pen-up; this must not depend on
            // ending the entire passage and then batch-rendering all input.
            let a = letter(.a, at: positions[.a]!, seed: 74)
            try await drawActiveA(a, origin: positions[.a]!, seed: 74, after: host.ink.drawing.strokes, in: host,
                releasingG: true)
            let aUp = try XCTUnwrap(host.view.chordDraftRenderCoordinator?.lastInputAt)
            assertTrue(await eventually(until: aUp.addingTimeInterval(0.95)) {
                self.texts(host.model.chart).contains("G")
            }, "G should render while A's reader remains unfinished")
            XCTAssertTrue(host.reader.isHeld(.a))
            assertSameInk(PKDrawing(strokes: [a]), host.ink.drawing)
            host.reader.release(.a)
            assertTrue(await eventually(timeout: 3.2) { self.texts(host.model.chart) == ["F", "G", "A"] })
            assertFinalReceipts(host, expected: [.f: f, .g: g, .a: a])
            XCTAssertEqual(host.model.chart.measures.count, 2)
        }
    }

    func testUnchangedBarlineWakesAtItsOwnDeadlineAfterLaterPenUpInBothStyles() async throws {
        for style in supportedStyles {
            let host = try await mount(style: style, measureCount: 1, commitsMeasures: false)
            defer { host.close() }
            let geometry = try firstLane(in: host)
            let y = geometry.lane.minY + max(5, (geometry.lane.height - 34) / 2) - geometry.region.minY
            let x = geometry.lane.minX - geometry.region.minX
            let positions: [CadenceReader.Symbol: CGPoint] = [
                .f: CGPoint(x: x + geometry.lane.width * 0.08, y: y),
                .g: CGPoint(x: x + geometry.lane.width * 0.56, y: y),
                .a: CGPoint(x: x + geometry.lane.width * 0.80, y: y)
            ]
            host.reader.setOrigins(positions)
            let f = letter(.f, at: positions[.f]!, seed: 81)
            append(f, to: host)
            assertTrue(await eventually(timeout: 0.8) { host.reader.hasCompleted(.f) })
            let barX = x + geometry.lane.width * 0.37
            let bar = stroke([
                CGPoint(x: barX, y: geometry.lane.minY + geometry.lane.height * 0.06 - geometry.region.minY),
                CGPoint(x: barX, y: geometry.lane.maxY - geometry.lane.height * 0.06 - geometry.region.minY)
            ], seed: 82)
            append(bar, to: host)
            assertTrue(await eventually(timeout: 0.8) {
                host.view.hasCurrentAutomaticChordCensus
                    && host.view.chordPreviewState.draftBarlines.count == 1
                    && host.view.chordDraftRenderCoordinator?.structuralMaturity.nextDeadline != nil
            }, "The real scheduler must observe the unchanged structural source")
            let ownDeadline = try XCTUnwrap(host.view.chordDraftRenderCoordinator?.structuralMaturity.nextDeadline)
            // Use the scheduler's absolute observed deadline, not an assumed
            // recognition duration or a tiny timing window between callbacks.
            XCTAssertGreaterThan(ownDeadline.timeIntervalSinceNow, 1.1,
                "The fixture needs time to finish the later stroke before structural maturity")
            let g = letter(.g, at: positions[.g]!, seed: 83)
            let retained = host.ink.drawing.strokes
            let before = host.model.chart
            host.view.canvasViewDidBeginUsingTool(host.ink)
            var step = 0
            repeat {
                setActiveStroke(prefix(of: .g, at: positions[.g]!, count: min(2 + step, 8), seed: 83),
                    after: retained, in: host)
                let expected = host.ink.drawing
                try await Task.sleep(nanoseconds: 60_000_000)
                XCTAssertEqual(host.model.chart.measures.map(\.id), before.measures.map(\.id))
                XCTAssertEqual(events(host.model.chart).map(\.id), events(before).map(\.id))
                assertSameInk(expected, host.ink.drawing)
                step += 1
            } while Date() < ownDeadline.addingTimeInterval(-0.8)
            setActiveStroke(g, after: retained, in: host)
            host.view.canvasViewDidEndUsingTool(host.ink)
            let gUp = try XCTUnwrap(host.view.chordDraftRenderCoordinator?.lastInputAt)
            let globalDeadline = gUp.addingTimeInterval(ChordInkAutomaticRenderPolicy.structuralIdleDelay)
            XCTAssertLessThan(gUp, ownDeadline.addingTimeInterval(-0.6),
                "G must finish before the barline's own deadline")
            XCTAssertGreaterThan(globalDeadline.timeIntervalSince(ownDeadline), 1,
                "The expected own wake and the old global wake need a generous separation")
            assertTrue(await eventually(until: ownDeadline.addingTimeInterval(-0.2)) {
                host.reader.hasStarted(.g) && host.view.hasCurrentAutomaticChordCensus
            })
            XCTAssertTrue(host.reader.isHeld(.g))
            XCTAssertEqual(host.model.chart.measures.count, 1,
                "The structure cannot render before its full existing grace")
            assertSameInk(PKDrawing(strokes: [f, bar, g]), host.ink.drawing)

            // No new Pencil callback, recognition completion, or manual
            // render follows G's pen-up. The scheduled structural deadline
            // must itself wake the shipping workflow while G's reader waits.
            assertTrue(await eventually(until: ownDeadline.addingTimeInterval(0.65)) {
                host.model.chart.measures.count == 2 && self.texts(host.model.chart) == ["F"]
            }, "The barline must wake at its own deadline without waiting for the later global idle")
            XCTAssertLessThan(Date(), globalDeadline.addingTimeInterval(-0.3))
            XCTAssertTrue(host.reader.isHeld(.g))
            assertSameInk(PKDrawing(strokes: [g]), host.ink.drawing)
            let savedG = try PKDrawing(data: XCTUnwrap(host.model.chart.pageHandwrittenChordData))
            assertSameInk(PKDrawing(strokes: [g]), savedG)
            let fEvent = try XCTUnwrap(events(host.model.chart).first { $0.rawInput == "F" })
            let savedF = try PKDrawing(data: XCTUnwrap(fEvent.sourceInkData))
            assertSameInk(PKDrawing(strokes: [f]), savedF)
            let reopened = try JSONDecoder().decode(Chart.self, from: JSONEncoder().encode(host.model.chart))
            XCTAssertEqual(events(reopened).map(\.sourceInkData), events(host.model.chart).map(\.sourceInkData))
            let reopenedG = try PKDrawing(data: XCTUnwrap(reopened.pageHandwrittenChordData))
            assertSameInk(PKDrawing(strokes: [g]), reopenedG)
            XCTAssertNil(host.window.rootViewController?.presentedViewController)
        }
    }

    private var supportedStyles: [ChartLayoutStyle] { [.simpleChordSheet, .rhythmSectionSheet] }

    private func driveThreeChordCadence(_ host: Mounted,
        positions: [CadenceReader.Symbol: CGPoint]) async throws {
        host.reader.setOrigins(positions)
        let f = letter(.f, at: positions[.f]!, seed: 31)
        let g = letter(.g, at: positions[.g]!, seed: 32)
        let a = letter(.a, at: positions[.a]!, seed: 33)
        append(f, to: host)
        assertTrue(await eventually(timeout: 0.8) { host.reader.hasCompleted(.f) })
        try await Task.sleep(nanoseconds: 70_000_000)
        let gUp = append(g, to: host)
        assertTrue(await eventually(until: gUp.addingTimeInterval(0.95)) {
            self.texts(host.model.chart).contains("F") && host.reader.hasStarted(.g)
        }, "The completed F must appear before G finishes, without waiting the passage-wide idle deadline")
        XCTAssertTrue(host.reader.isHeld(.g))
        XCTAssertEqual(texts(host.model.chart), ["F"])
        assertSameInk(PKDrawing(strokes: [g]), host.ink.drawing)

        try await drawActiveA(a, origin: positions[.a]!, seed: 33, after: host.ink.drawing.strokes, in: host,
            releasingG: true)
        let aUp = try XCTUnwrap(host.view.chordDraftRenderCoordinator?.lastInputAt)
        assertTrue(await eventually(until: aUp.addingTimeInterval(0.95)) {
            self.texts(host.model.chart) == ["F", "G"] && host.reader.hasStarted(.a)
        }, "G must appear at a safe pen-up while A is still being read")
        XCTAssertTrue(host.reader.isHeld(.a))
        assertSameInk(PKDrawing(strokes: [a]), host.ink.drawing)
        let savedA = try PKDrawing(data: XCTUnwrap(host.model.chart.pageHandwrittenChordData))
        assertSameInk(PKDrawing(strokes: [a]), savedA)
        host.reader.release(.a)
        assertTrue(await eventually(timeout: 3) {
            self.texts(host.model.chart) == ["F", "G", "A"] && host.ink.drawing.strokes.isEmpty
        })
        assertFinalReceipts(host, expected: [.f: f, .g: g, .a: a])
    }

    private func drawActiveA(_ complete: PKStroke, origin: CGPoint, seed: UInt32,
        after retained: [PKStroke], in host: Mounted, releasingG: Bool) async throws {
        let before = events(host.model.chart).map(\.id)
        host.view.canvasViewDidBeginUsingTool(host.ink)
        for pointCount in 2...5 {
            setActiveStroke(prefix(of: .a, at: origin, count: pointCount, seed: seed), after: retained, in: host)
            let expected = host.ink.drawing
            if pointCount == 2 && releasingG { host.reader.release(.g) }
            try await Task.sleep(nanoseconds: 45_000_000)
            XCTAssertEqual(events(host.model.chart).map(\.id), before,
                "A completed older read must wait for pen-up instead of replacing an active Pencil stroke")
            assertSameInk(expected, host.ink.drawing)
        }
        setActiveStroke(complete, after: retained, in: host)
        host.view.canvasViewDidEndUsingTool(host.ink)
    }

    private func assertFinalReceipts(_ host: Mounted, expected: [CadenceReader.Symbol: PKStroke],
        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(texts(host.model.chart), ["F", "G", "A"], file: file, line: line)
        XCTAssertNil(host.model.chart.pageHandwrittenChordData, file: file, line: line)
        XCTAssertTrue(host.ink.drawing.strokes.isEmpty, file: file, line: line)
        XCTAssertNil(host.window.rootViewController?.presentedViewController,
            "Incremental rendering must not require a review panel", file: file, line: line)
        for (symbol, original) in expected {
            do {
                let event = try XCTUnwrap(events(host.model.chart).first { $0.rawInput == symbol.rawValue }, file: file, line: line)
                let saved = try PKDrawing(data: XCTUnwrap(event.sourceInkData, file: file, line: line))
                assertSameInk(PKDrawing(strokes: [original]), saved, file: file, line: line)
            } catch { XCTFail("A rendered chord lost its exact original source receipt", file: file, line: line) }
        }
        do {
            let reopened = try JSONDecoder().decode(Chart.self, from: JSONEncoder().encode(host.model.chart))
            XCTAssertEqual(events(reopened).map(\.id), events(host.model.chart).map(\.id), file: file, line: line)
            XCTAssertEqual(events(reopened).map(\.sourceInkData), events(host.model.chart).map(\.sourceInkData), file: file, line: line)
            XCTAssertNil(reopened.pageHandwrittenChordData, file: file, line: line)
        } catch { XCTFail("The incrementally rendered chart must survive a coder reopen", file: file, line: line) }
    }

    private func events(_ chart: Chart) -> [ChordEvent] { chart.measures.flatMap(\.chordEvents) }
    private func texts(_ chart: Chart) -> [String] { events(chart).compactMap(\.rawInput) }

    @discardableResult
    private func append(_ source: PKStroke, to host: Mounted) -> Date {
        host.view.canvasViewDidBeginUsingTool(host.ink)
        setActiveStroke(source, after: host.ink.drawing.strokes, in: host)
        host.view.canvasViewDidEndUsingTool(host.ink)
        return host.view.chordDraftRenderCoordinator?.lastInputAt ?? Date()
    }

    private func setActiveStroke(_ source: PKStroke, after retained: [PKStroke], in host: Mounted) {
        host.ink.drawing = LeadSheetPersistentInkColorPolicy.normalizedDrawing(PKDrawing(strokes: retained + [source]))
        host.view.canvasViewDrawingDidChange(host.ink)
    }

    // Unlike XCTest's autoclosure, this value parameter may receive an awaited
    // condition from the shipping workflow without blocking its main run loop.
    private func assertTrue(_ result: Bool, _ message: String = "",
        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(result, message, file: file, line: line)
    }

    private func assertSameInk(_ expected: PKDrawing, _ current: PKDrawing,
        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: expected, current: current),
            "Unfinished ink must retain exact paths, transforms, chronology and seeds", file: file, line: line)
    }

    private func eventually(timeout: TimeInterval, _ condition: () -> Bool) async -> Bool {
        await eventually(until: Date().addingTimeInterval(timeout), condition)
    }

    private func eventually(until deadline: Date, _ condition: () -> Bool) async -> Bool {
        repeat {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        } while Date() < deadline
        return condition()
    }

    private func targetOrigins(in host: Mounted, indices: [Int]) throws -> [CadenceReader.Symbol: CGPoint] {
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: host.model.chart,
            pageSize: host.view.bounds.size, includesChordInkContinuationLanes: true)
        let region = LeadSheetActiveInkScope.chordWritingRegion(for: layout).frame
        var result: [CadenceReader.Symbol: CGPoint] = [:]
        for (symbol, index) in zip([CadenceReader.Symbol.f, .g, .a], indices) {
            let id = host.model.chart.measures[index].id
            let measure = try XCTUnwrap(layout.systems.flatMap(\.measures).first { $0.sourceMeasureID == id })
            let frame = measure.chordWritingFrame
            XCTAssertGreaterThan(frame.width, 55)
            result[symbol] = CGPoint(x: frame.minX + 16 - region.minX,
                y: frame.minY + max(5, (frame.height - 34) / 2) - region.minY)
        }
        return result
    }

    private func firstLane(in host: Mounted) throws -> (lane: CGRect, region: CGRect) {
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: host.model.chart,
            pageSize: host.view.bounds.size, includesChordInkContinuationLanes: true)
        let region = LeadSheetActiveInkScope.chordWritingRegion(for: layout)
        return (try XCTUnwrap(region.inputFrames.first), region.frame)
    }

    private func letter(_ symbol: CadenceReader.Symbol, at origin: CGPoint, seed: UInt32) -> PKStroke {
        prefix(of: symbol, at: origin, count: 100, seed: seed)
    }

    private func prefix(of symbol: CadenceReader.Symbol, at origin: CGPoint,
        count: Int, seed: UInt32) -> PKStroke {
        let points: [CGPoint]
        switch symbol {
        case .f: points = [CGPoint(x: 0, y: 32), .zero, CGPoint(x: 22, y: 0), .zero,
                          CGPoint(x: 0, y: 15), CGPoint(x: 17, y: 15)]
        case .g: points = [CGPoint(x: 22, y: 2), CGPoint(x: 6, y: 0), CGPoint(x: 0, y: 8),
                          CGPoint(x: 0, y: 25), CGPoint(x: 6, y: 32), CGPoint(x: 22, y: 29),
                          CGPoint(x: 22, y: 16), CGPoint(x: 12, y: 16)]
        case .a: points = [CGPoint(x: 0, y: 32), CGPoint(x: 11, y: 0), CGPoint(x: 22, y: 32),
                          CGPoint(x: 17, y: 20), CGPoint(x: 5, y: 20)]
        }
        return stroke(points.prefix(count).map { CGPoint(x: $0.x + origin.x, y: $0.y + origin.y) }, seed: seed)
    }

    private func stroke(_ locations: [CGPoint], seed: UInt32) -> PKStroke {
        let points = locations.enumerated().map { index, point in
            PKStrokePoint(location: point, timeOffset: Double(index) * 0.01,
                size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: LeadSheetPersistentInkColorPolicy.inkColor),
            path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSinceReferenceDate: Double(seed))),
            transform: .identity, mask: nil, randomSeed: seed)
    }

    private struct Mounted {
        let model: CadenceChartModel
        let reader: CadenceReader
        let view: LeadSheetCanvasUIKitView
        let ink: PKCanvasView
        let window: UIWindow
        let close: @MainActor () -> Void
    }

    private func mount(style: ChartLayoutStyle, measureCount: Int, startsSecondRow: Bool = false,
        commitsMeasures: Bool = true) async throws -> Mounted {
        let key = ChordInkWorkflowSettings.manualRenderWithPreviewKey
        let previousPreference = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.set(false, forKey: key)
        var chart = Chart.draft(title: "Disposable automatic cadence", layoutStyle: style)
        chart.completeInitialSetup(title: chart.title, key: .cMajor, meter: Meter(numerator: 4, denominator: 4),
            staffStyle: .fiveLine, startingMeasureCount: measureCount)
        if commitsMeasures {
            for systemIndex in chart.systems.indices {
                for measureIndex in chart.systems[systemIndex].measures.indices {
                    chart.systems[systemIndex].measures[measureIndex].authoringState = .committed
                    chart.systems[systemIndex].measures[measureIndex].manualLayoutWidth = 180
                }
            }
        }
        if startsSecondRow { XCTAssertTrue(chart.insertSystemBreak(before: chart.measures[4].id)) }
        let model = CadenceChartModel(chart)
        let reader = CadenceReader()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root = NavigationStack {
            EditorView(chart: Binding(get: { model.chart }, set: { model.chart = $0 }),
                chordInkUserCorrectionMemoryStore: .init(url: directory.appendingPathComponent("corrections.json")),
                initialCanvasMode: .chordEntry, chordInkRecognizer: reader)
        }
        .environmentObject(ChartLibraryStore(charts: [chart], selectedChartID: chart.id))
        .environmentObject(IChartPDFLibraryStore(baseDirectory: directory.appendingPathComponent("PDF Library")))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previousWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = UIHostingController(rootView: root)
        window.makeKeyAndVisible()
        var closed = false
        let close: @MainActor () -> Void = {
            guard !closed else { return }
            closed = true
            reader.releaseAll()
            for canvas in self.descendants(window).compactMap({ $0 as? LeadSheetCanvasUIKitView }) {
                canvas.recognizesChordInk = false
                canvas.onChordInkDraftPreviewChanged = nil
                canvas.onChordInkDraftBarlinesChanged = nil
                canvas.onChordInkDraftEndingsChanged = nil
                canvas.onChordInkAutomaticActivityChanged = nil
            }
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKeyAndVisible()
            if let previousPreference { UserDefaults.standard.set(previousPreference, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
            try? FileManager.default.removeItem(at: directory)
        }
        addTeardownBlock { @MainActor in close() }
        for _ in 0..<80 {
            window.layoutIfNeeded()
            if let view = descendants(window).compactMap({ $0 as? LeadSheetCanvasUIKitView }).first,
               let ink = view.subviews.compactMap({ $0 as? PKCanvasView }).last,
               !ink.isHidden, view.recognizesChordInk, view.chordDraftRenderCoordinator != nil,
               view.bounds.width > 0, view.bounds.height > 0 {
                XCTAssertTrue(ink.drawing.strokes.isEmpty)
                return Mounted(model: model, reader: reader, view: view, ink: ink, window: window, close: close)
            }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        close()
        throw NSError(domain: "ChordInkAutomaticCadenceWorkflowTests", code: 1)
    }

    private func descendants(_ view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap(descendants)
    }
}

@MainActor
private final class CadenceChartModel: ObservableObject {
    @Published var chart: Chart
    init(_ chart: Chart) { self.chart = chart }
}

private final class CadenceReader: ChordInkRecognizing {
    enum Symbol: String, CaseIterable, Hashable { case f = "F", g = "G", a = "A" }
    private let condition = NSCondition()
    private var origins: [Symbol: CGPoint] = [:]
    private var started = Set<Symbol>()
    private var completed = Set<Symbol>()
    private var released = Set<Symbol>([.f])

    func setOrigins(_ origins: [Symbol: CGPoint]) {
        condition.lock(); defer { condition.unlock() }
        self.origins = origins
    }
    func hasStarted(_ symbol: Symbol) -> Bool {
        condition.lock(); defer { condition.unlock() }; return started.contains(symbol)
    }
    func hasCompleted(_ symbol: Symbol) -> Bool {
        condition.lock(); defer { condition.unlock() }; return completed.contains(symbol)
    }
    func isHeld(_ symbol: Symbol) -> Bool {
        condition.lock(); defer { condition.unlock() }; return started.contains(symbol) && !released.contains(symbol)
    }
    func release(_ symbol: Symbol) {
        condition.lock(); defer { condition.unlock() }; released.insert(symbol); condition.broadcast()
    }
    func releaseAll() {
        condition.lock(); defer { condition.unlock() }; released.formUnion(Symbol.allCases); condition.broadcast()
    }
    func recognize(strokes: [InkStroke], options: ChordInkRecognitionOptions) -> ChordInkRecognitionResult {
        let bounds = InkBounds.enclosing(strokes.map(\.bounds))
        condition.lock()
        let symbol = origins.min { lhs, rhs in
            let leftX = abs(Double(lhs.value.x) - bounds.minX)
            let leftY = abs(Double(lhs.value.y) - bounds.minY)
            let rightX = abs(Double(rhs.value.x) - bounds.minX)
            let rightY = abs(Double(rhs.value.y) - bounds.minY)
            return leftX + leftY < rightX + rightY
        }?.key ?? .f
        started.insert(symbol)
        let limit = Date().addingTimeInterval(12)
        while !released.contains(symbol) && condition.wait(until: limit) {}
        completed.insert(symbol)
        condition.unlock()
        let text = symbol.rawValue
        return ChordInkRecognitionResult(rawCandidates: [text], glyphCandidates: [],
            match: ChordRecognitionCompendium.match(text), confidence: 4.5,
            candidateScores: [ChordInkCandidateScore(text: text, displayText: text, confidence: 4.5)])
    }
}
#endif
