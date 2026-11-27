#if canImport(UIKit) && canImport(PencilKit)
import Foundation
import PencilKit
import SwiftUI
import UIKit
import XCTest
@testable import iChart

/// Drives the shipping Editor with real captured chord geometry and its real
/// reader. A worker gate controls preparation delivery only; it never supplies
/// a chord label, preview, census or render callback.
@MainActor
final class ChordInkNaturalWritingCadenceWorkflowTests: XCTestCase {
    private let styles: [ChartLayoutStyle] = [.simpleChordSheet, .rhythmSectionSheet]

    func testSlowPreparedPrefixRendersBeforeLaterWritingStopsInBothLayoutsAndStyles() async throws {
        for paper in [true, false] {
            for style in styles {
                let host = try await mount(style: style, paper: paper)
                defer { host.close() }
                let geometry = try firstLane(in: host)
                let c = try captured("CCaptured01", fraction: 0.12, in: geometry, seed: 101)
                let bar = divider(fraction: 0.40, in: geometry, seed: 120)
                let prefix = paper
                    ? [divider(fraction: 0.04, in: geometry, seed: 110)] + c + [bar]
                    : c + [bar]
                let gate = PreparationGate(sourceCount: prefix.count)
                host.view.chordInkPreparationTestHook = gate.receive
                defer { gate.release() }
                append(prefix, to: host)
                assertTrue(await eventually(timeout: 2) { gate.hasEntered },
                    "The immutable real preparation must be held before delivery: \(style) paper=\(paper)")

                let g = try captured("GCaptured01", fraction: 0.69, in: geometry, seed: 201)
                let completeG = try XCTUnwrap(g.first)
                XCTAssertEqual(g.count, 1, "The tail fixture deliberately updates one still-being-written root")
                let firstTail = prefixStroke(completeG, pointCount: 3)
                replaceTail(firstTail, seed: completeG.randomSeed, in: host)
                gate.releaseFirst()

                let stopAt = Date().addingTimeInterval(3.25)
                var renderedWhileWriting = false
                var updates = 0
                // Keep changing only the later root faster than a slow whole-
                // drawing preparation can finish. No await-reader or global
                // idle is supplied between these Pencil callbacks.
                while Date() < stopAt {
                    let count = min(completeG.path.count - 1, 3 + updates)
                    replaceTail(prefixStroke(completeG, pointCount: count), seed: completeG.randomSeed, in: host)
                    renderedWhileWriting = renderedWhileWriting || events(host.model.chart).contains {
                        $0.symbol.displayText == "C"
                    }
                    XCTAssertFalse(events(host.model.chart).contains { $0.symbol.displayText == "B" },
                        "The isolated divider must not become a B chord")
                    try await Task.sleep(nanoseconds: 45_000_000)
                    updates += 1
                }
                XCTAssertGreaterThan(updates, 20, "This must exercise continuous later input, not one idle read")
                diagnose("slow-prefix-before-writer-stops", host: host)
                XCTAssertTrue(renderedWhileWriting,
                    "An unchanged earlier chord and divider must progress before later writing stops: \(style) paper=\(paper)")
                let savedC = try XCTUnwrap(events(host.model.chart).first { $0.symbol.displayText == "C" })
                assertSameInk(PKDrawing(strokes: c), try PKDrawing(data: XCTUnwrap(savedC.sourceInkData)))
                XCTAssertTrue(host.ink.drawing.strokes.contains { $0.randomSeed == completeG.randomSeed },
                    "Rendering the old prefix must preserve the newer root")
                XCTAssertFalse(host.ink.drawing.strokes.contains { stroke in c.contains { $0.randomSeed == stroke.randomSeed } },
                    "Only the committed root's original source should clear")

                host.view.chordInkPreparationTestHook = nil
                gate.release()
                replaceTail(completeG, seed: completeG.randomSeed, in: host)
                assertTrue(await eventually(timeout: 5) {
                    self.events(host.model.chart).map(\.symbol.displayText) == ["C", "G"]
                        && host.ink.drawing.strokes.isEmpty
                }, "The final real chord must finish without another Pencil input or Render tap")
                try assertFinal(host, expected: [("C", c), ("G", g)])
            }
        }
    }

    func testRapidMixedRealChordsAndSingleDoubleBoundariesClearInBothStylesAndModes() async throws {
        try await driveRapidMixedWriting(heightRatio: 0.92)
    }

    func testRapidMixedRealChordsAndHalfHeightBoundariesClearInBothStylesAndModes() async throws {
        try await driveRapidMixedWriting(heightRatio: 0.50)
    }

    private func driveRapidMixedWriting(heightRatio: CGFloat) async throws {
        for style in styles {
            for manual in [false, true] {
                let host = try await mount(style: style, paper: true, manual: manual)
                defer { host.close() }
                let geometry = try firstLane(in: host)
                let c = try captured("CCaptured01", fraction: 0.13, in: geometry, seed: 301)
                let g = try captured("GCaptured01", fraction: 0.43, in: geometry, seed: 401)
                let repeatChord = try captured("ChordRepeatCaptured01", fraction: 0.73, in: geometry, seed: 501)
                let gap = min(7, geometry.lane.width * 0.008)
                let source = [divider(fraction: 0.04, heightRatio: heightRatio, in: geometry, seed: 310)] + c
                    + [divider(fraction: 0.34, heightRatio: heightRatio, in: geometry, seed: 410)] + g
                    + [divider(fraction: 0.64, heightRatio: heightRatio, in: geometry, seed: 510),
                       divider(fraction: 0.64, xOffset: gap, heightRatio: heightRatio, in: geometry, seed: 511)]
                    + repeatChord + [divider(fraction: 0.95, heightRatio: heightRatio, in: geometry, seed: 610)]
                for stroke in source {
                    append([stroke], to: host)
                    try await Task.sleep(nanoseconds: 55_000_000)
                }
                if manual {
                    XCTAssertTrue(events(host.model.chart).isEmpty, "Manual mode must not auto-commit")
                    assertSameInk(PKDrawing(strokes: source), host.ink.drawing)
                    assertTrue(await eventually(timeout: 5) {
                        host.view.chordPreviewState.draftChords.count == 3
                            && ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(
                                chart: host.model.chart, state: host.view.chordPreviewState)
                    }, "All three current chord previews must arrive before checking the full manual batch")
                    // Use the real Editor action and its current SwiftUI
                    // state. A representable's last projected preview can lag
                    // the parent's newly completed recognition callbacks.
                    // Render Chords can coexist as an independent structural
                    // action while a chord needs review. Prefer the full-batch
                    // Review action when both are present.
                    try await activateAction(["Review & Render", "Render Chords"], in: host)
                    assertTrue(await eventually(timeout: 5) {
                        self.events(host.model.chart).count == 3
                            || host.window.rootViewController?.presentedViewController != nil
                    }, "The manual action must render or open its existing chord review")
                    if host.window.rootViewController?.presentedViewController != nil {
                        try await activateAction(["Render All"], in: host)
                    }
                    assertTrue(await eventually(timeout: 5) {
                        self.events(host.model.chart).count == 3 && host.ink.drawing.strokes.isEmpty
                            && host.window.rootViewController?.presentedViewController == nil
                    }, "The normal manual Render action must finish without a separate source-recovery action")
                } else {
                    assertTrue(await eventually(timeout: 6) {
                        self.events(host.model.chart).count == 3 && host.ink.drawing.strokes.isEmpty
                    }, "Completed mixed ink must drain after the last pen-up in \(style)")
                }
                try assertFinal(host, expected: [("C", c), ("G", g), ("•/•", repeatChord)])
                let firstRow = host.model.chart.measures.filter { $0.paperLayout?.rowIndex == 0 }
                XCTAssertTrue(firstRow.contains { $0.barlineAfter == .double },
                    "The adjacent strokes must retain the user's double boundary")
            }
        }
    }

    func testLaterNearbySuffixPreventsOldPreparedRootFromBeingCommittedAlone() async throws {
        for style in styles {
            let host = try await mount(style: style, paper: true)
            defer { host.close() }
            let geometry = try firstLane(in: host)
            let c = try captured("CCaptured01", fraction: 0.20, in: geometry, seed: 701)
            let gate = PreparationGate(sourceCount: c.count)
            host.view.chordInkPreparationTestHook = gate.receive
            defer { gate.release() }
            append(c, to: host)
            assertTrue(await eventually(timeout: 2) { gate.hasEntered })
            let bounds = PKDrawing(strokes: c).bounds
            let seven = stroke([
                CGPoint(x: bounds.maxX + 4, y: bounds.minY + 2),
                CGPoint(x: bounds.maxX + 17, y: bounds.minY + 2),
                CGPoint(x: bounds.maxX + 8, y: bounds.minY + bounds.height * 0.60)
            ], seed: 702)
            append([seven], to: host)
            gate.release()
            let deadline = Date().addingTimeInterval(0.85)
            repeat {
                XCTAssertFalse(events(host.model.chart).contains { $0.symbol.displayText == "C" },
                    "An old valid C read must not consume the root after a nearby seven has arrived")
                try await Task.sleep(nanoseconds: 25_000_000)
            } while Date() < deadline
            let archived = events(host.model.chart).compactMap(\.sourceInkData).compactMap { try? PKDrawing(data: $0) }
            if !archived.isEmpty {
                XCTAssertTrue(archived.contains {
                    ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: PKDrawing(strokes: c + [seven]), current: $0)
                }, "Any accepted extended chord must own both the root and its new suffix")
            } else {
                assertSameInk(PKDrawing(strokes: c + [seven]), host.ink.drawing)
            }
        }
    }

    func testPreparedPrefixWaitsForOneHeldPencilSessionThenDrainsAtPenUp() async throws {
        for style in styles {
            let host = try await mount(style: style, paper: true)
            defer { host.close() }
            let geometry = try firstLane(in: host)
            let c = try captured("CCaptured01", fraction: 0.12, in: geometry, seed: 801)
            let prefix = [divider(fraction: 0.04, in: geometry, seed: 810)] + c
                + [divider(fraction: 0.40, in: geometry, seed: 820)]
            let gate = PreparationGate(sourceCount: prefix.count)
            host.view.chordInkPreparationTestHook = gate.receive
            defer { gate.release() }
            append(prefix, to: host)
            assertTrue(await eventually(timeout: 2) { gate.hasEntered })
            let g = try captured("GCaptured01", fraction: 0.69, in: geometry, seed: 901)
            let tail = try XCTUnwrap(g.first)
            let initialMeasureIDs = host.model.chart.measures.map(\.id)
            host.view.canvasViewDidBeginUsingTool(host.ink)
            gate.releaseFirst()
            let endAt = Date().addingTimeInterval(2.6)
            var updates = 0
            repeat {
                let partial = prefixStroke(tail, pointCount: min(tail.path.count - 1, 3 + updates))
                updateDrawing(prefix + [partial], in: host)
                let expected = host.ink.drawing
                try await Task.sleep(nanoseconds: 35_000_000)
                XCTAssertTrue(events(host.model.chart).isEmpty,
                    "A completed older read must not commit while this Pencil session is active")
                XCTAssertEqual(host.model.chart.measures.map(\.id), initialMeasureIDs,
                    "A mature older boundary must not change structure under an active Pencil")
                assertSameInk(expected, host.ink.drawing)
                updates += 1
            } while Date() < endAt
            XCTAssertGreaterThan(updates, 25)
            updateDrawing(prefix + [tail], in: host)
            host.view.canvasViewDidEndUsingTool(host.ink)
            diagnose("held-pencil-at-pen-up", host: host)
            let drained = await eventually(timeout: 1.1) {
                self.events(host.model.chart).contains { $0.symbol.displayText == "C" }
            }
            diagnose("held-pencil-after-prefix-deadline", host: host)
            assertTrue(drained, "The safe pen-up must drain the already-complete prefix without restarting its clocks")
            assertSameInk(PKDrawing(strokes: g), host.ink.drawing)
            host.view.chordInkPreparationTestHook = nil
            gate.release()
            assertTrue(await eventually(timeout: 5) {
                self.events(host.model.chart).map(\.symbol.displayText) == ["C", "G"]
                    && host.ink.drawing.strokes.isEmpty
            })
            try assertFinal(host, expected: [("C", c), ("G", g)])
        }
    }

    func testEditingMaskingOrErasingOlderSourceRejectsItsHeldCompletion() async throws {
        for style in styles {
            for edit in SourceEdit.allCases {
                let host = try await mount(style: style, paper: true)
                defer { host.close() }
                let geometry = try firstLane(in: host)
                let c = try captured("CCaptured01", fraction: 0.12, in: geometry, seed: 1_001)
                let root = try XCTUnwrap(c.first)
                XCTAssertEqual(c.count, 1)
                let gate = PreparationGate(sourceCount: 1)
                host.view.chordInkPreparationTestHook = gate.receive
                defer { gate.release() }
                append(c, to: host)
                assertTrue(await eventually(timeout: 2) { gate.hasEntered })
                let changed = try changedRoot(root, edit: edit)
                let g = try captured("GCaptured01", fraction: 0.69, in: geometry, seed: 1_101)
                let current = PKDrawing(strokes: changed + g)
                input(current.strokes, in: host)
                gate.releaseFirst()
                let deadline = Date().addingTimeInterval(0.85)
                repeat {
                    XCTAssertTrue(events(host.model.chart).isEmpty,
                        "An edited/masked/erased root must invalidate its prior preparation: \(style) \(edit)")
                    assertSameInk(current, host.ink.drawing)
                    try await Task.sleep(nanoseconds: 25_000_000)
                } while Date() < deadline
                host.view.chordInkPreparationTestHook = nil
                gate.release()
                assertTrue(await eventually(timeout: 5) {
                    host.view.hasCurrentAutomaticChordCensus || host.ink.drawing.strokes.isEmpty
                }, "After rejecting the obsolete result, the latest drawing still needs a fresh census")
                let receipts = try events(host.model.chart).compactMap(\.sourceInkData).map { try PKDrawing(data: $0) }
                XCTAssertFalse(receipts.contains {
                    ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: PKDrawing(strokes: c), current: $0)
                }, "The old source archive must not reappear after the edit")
                let represented = PKDrawing(strokes: receipts.flatMap(\.strokes) + host.ink.drawing.strokes)
                assertSameInk(current, represented)
                XCTAssertNil(host.window.rootViewController?.presentedViewController)
            }
        }
    }

    func testResidentAppendBeforeDrawingDelegateCallbackPreservesNewInkAndDrainsLatest() async throws {
        for style in styles {
            let host = try await mount(style: style, paper: true)
            defer { host.close() }
            let geometry = try firstLane(in: host)
            let c = try captured("CCaptured01", fraction: 0.12, in: geometry, seed: 1_201)
            let g = try captured("GCaptured01", fraction: 0.69, in: geometry, seed: 1_301)
            let gate = PreparationGate(sourceCount: c.count)
            host.view.chordInkPreparationTestHook = gate.receive
            defer { gate.release() }
            append(c, to: host)
            assertTrue(await eventually(timeout: 2) { gate.hasEntered })
            let previousDelegate = host.ink.delegate
            defer { host.ink.delegate = previousDelegate }
            host.ink.delegate = nil
            // Simulate PencilKit changing its actual drawing before the host
            // receives a delegate callback/revision. No host input method is
            // invoked for G, and the delegate remains absent during draining.
            host.ink.drawing = LeadSheetPersistentInkColorPolicy.normalizedDrawing(PKDrawing(strokes: c + g))
            gate.releaseFirst()
            assertTrue(await eventually(timeout: 2) {
                self.events(host.model.chart).contains { $0.symbol.displayText == "C" }
            }, "An actual appended drawing must be treated as a prefix even when the recorded revision is unchanged")
            assertSameInk(PKDrawing(strokes: g), host.ink.drawing)
            let savedC = try XCTUnwrap(events(host.model.chart).first { $0.symbol.displayText == "C" })
            assertSameInk(PKDrawing(strokes: c), try PKDrawing(data: XCTUnwrap(savedC.sourceInkData)))
            let pending = try PKDrawing(data: XCTUnwrap(host.model.chart.pageHandwrittenChordData))
            assertSameInk(PKDrawing(strokes: g), pending)

            host.view.chordInkPreparationTestHook = nil
            gate.release()
            assertTrue(await eventually(timeout: 5) {
                self.events(host.model.chart).map(\.symbol.displayText) == ["C", "G"]
                    && host.ink.drawing.strokes.isEmpty
            }, "The latest source must drain without needing the missing delegate callback or another stroke")
            try assertFinal(host, expected: [("C", c), ("G", g)])
        }
    }

    func testMatureLeadingAndClosingPairFinishesWhileLaterBoundaryKeepsItsOwnGrace() async throws {
        for style in styles {
            let host = try await mount(style: style, paper: true)
            defer { host.close() }
            let geometry = try firstLane(in: host)
            let c = try captured("CCaptured01", fraction: 0.12, in: geometry, seed: 1_401)
            let firstPair = [divider(fraction: 0.04, in: geometry, seed: 1_410)] + c
                + [divider(fraction: 0.40, in: geometry, seed: 1_420)]
            append(firstPair, to: host)
            assertTrue(await eventually(timeout: 1) {
                host.view.hasCurrentAutomaticChordCensus
                    && host.view.chordPreviewState.draftBarlines.count == 2
                    && host.view.chordPreviewState.draftChords.contains { $0.previewText == "C" }
                    && host.view.chordDraftRenderCoordinator?.structuralMaturity.nextDeadline != nil
            }, "The first actual census must establish both boundaries and their own maturity clock")
            let firstDeadline = try XCTUnwrap(host.view.chordDraftRenderCoordinator?.structuralMaturity.nextDeadline)
            XCTAssertGreaterThan(firstDeadline.timeIntervalSinceNow, 1,
                "The first pair needs enough observed grace left to write the next measure")
            let writeLaterAt = firstDeadline.addingTimeInterval(-0.8)
            if writeLaterAt.timeIntervalSinceNow > 0 {
                try await Task.sleep(nanoseconds: UInt64(writeLaterAt.timeIntervalSinceNow * 1_000_000_000))
            }
            XCTAssertTrue(events(host.model.chart).isEmpty,
                "The first boundaries must receive their full configured grace")
            let g = try captured("GCaptured01", fraction: 0.69, in: geometry, seed: 1_501)
            let last = divider(fraction: 0.95, in: geometry, seed: 1_510)
            let lastWrittenAt = Date()
            append(g, to: host)
            append([last], to: host)
            let earliestLastDeadline = lastWrittenAt.addingTimeInterval(ChordInkAutomaticRenderPolicy.structuralIdleDelay)
            assertTrue(await eventually(timeout: max(0.01, firstDeadline.timeIntervalSinceNow - 0.15)) {
                host.view.hasCurrentAutomaticChordCensus
                    && host.view.chordPreviewState.draftBarlines.count == 3
                    && host.view.chordPreviewState.draftChords.count == 2
            }, "A fresh complete census must contain the newer boundary before the older pair matures")
            XCTAssertLessThan(Date(), firstDeadline,
                "This is a mature-subset test, not a completed all-boundary idle batch")
            let firstCommitLimit = min(firstDeadline.addingTimeInterval(0.60), earliestLastDeadline.addingTimeInterval(-0.25))
            let completedFirst = await eventually(timeout: max(0.01, firstCommitLimit.timeIntervalSinceNow)) {
                self.events(host.model.chart).map(\.symbol.displayText) == ["C"]
            }
            diagnose("mature-pair-before-later-boundary", host: host)
            assertTrue(completedFirst,
                "The eligible leading/closing pair must render jointly while the third boundary is still immature")
            XCTAssertLessThan(Date(), earliestLastDeadline,
                "The later boundary must still be inside its own full two-second grace")
            let committed = try XCTUnwrap(host.model.chart.measures.first {
                $0.chordEvents.contains { $0.symbol.displayText == "C" }
            })
            XCTAssertEqual(try XCTUnwrap(committed.paperLayout).startFraction, 0.04, accuracy: 0.001)
            XCTAssertEqual(try XCTUnwrap(committed.paperLayout).endFraction, 0.40, accuracy: 0.001)
            assertSameInk(PKDrawing(strokes: c),
                try PKDrawing(data: XCTUnwrap(committed.chordEvents.first?.sourceInkData)))
            let retained = PKDrawing(strokes: g + [last])
            assertSameInk(retained, host.ink.drawing)
            assertSameInk(retained,
                try PKDrawing(data: XCTUnwrap(host.model.chart.pageHandwrittenChordData)))
            assertTrue(await eventually(timeout: 5) {
                self.events(host.model.chart).map(\.symbol.displayText) == ["C", "G"]
                    && host.ink.drawing.strokes.isEmpty
            }, "The remaining chord and its boundary must finish without another input or manual action")
            try assertFinal(host, expected: [("C", c), ("G", g)])
        }
    }

    func testMaturePairFinishesWhileOnlyAYoungerThirdBarlineRemains() async throws {
        for style in styles {
            let host = try await mount(style: style, paper: true)
            defer { host.close() }
            let geometry = try firstLane(in: host)
            let c = try captured("CCaptured01", fraction: 0.12, in: geometry, seed: 1_601)
            let firstPair = [divider(fraction: 0.04, in: geometry, seed: 1_610)] + c
                + [divider(fraction: 0.40, in: geometry, seed: 1_620)]
            append(firstPair, to: host)
            assertTrue(await eventually(timeout: 1) {
                host.view.hasCurrentAutomaticChordCensus
                    && host.view.chordPreviewState.draftBarlines.count == 2
                    && host.view.chordPreviewState.draftChords.contains { $0.previewText == "C" }
                    && host.view.chordDraftRenderCoordinator?.structuralMaturity.nextDeadline != nil
            })
            let firstDeadline = try XCTUnwrap(host.view.chordDraftRenderCoordinator?.structuralMaturity.nextDeadline)
            XCTAssertGreaterThan(firstDeadline.timeIntervalSinceNow, 1)
            let remaining = firstDeadline.addingTimeInterval(-0.8).timeIntervalSinceNow
            if remaining > 0 { try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) }
            XCTAssertTrue(events(host.model.chart).isEmpty)
            let last = divider(fraction: 0.95, in: geometry, seed: 1_710)
            let lastWrittenAt = Date()
            append([last], to: host)
            let earliestLastDeadline = lastWrittenAt.addingTimeInterval(ChordInkAutomaticRenderPolicy.structuralIdleDelay)
            assertTrue(await eventually(timeout: max(0.01, firstDeadline.timeIntervalSinceNow - 0.15)) {
                host.view.hasCurrentAutomaticChordCensus
                    && host.view.chordPreviewState.draftBarlines.count == 3
                    && host.view.chordPreviewState.draftChords.count == 1
            }, "The younger boundary must be observed in a fresh census before the older pair matures")
            XCTAssertLessThan(Date(), firstDeadline)
            let firstCommitLimit = min(firstDeadline.addingTimeInterval(0.60), earliestLastDeadline.addingTimeInterval(-0.25))
            let completedFirst = await eventually(timeout: max(0.01, firstCommitLimit.timeIntervalSinceNow)) {
                self.events(host.model.chart).map(\.symbol.displayText) == ["C"]
                    && host.ink.drawing.strokes.count == 1
            }
            diagnose("mature-pair-before-bar-only-tail", host: host)
            assertTrue(completedFirst,
                "An exact younger structural-only tail must not delay the eligible leading/closing pair")
            XCTAssertLessThan(Date(), earliestLastDeadline)
            let committed = try XCTUnwrap(host.model.chart.measures.first {
                $0.chordEvents.contains { $0.symbol.displayText == "C" }
            })
            XCTAssertEqual(try XCTUnwrap(committed.paperLayout).startFraction, 0.04, accuracy: 0.001)
            XCTAssertEqual(try XCTUnwrap(committed.paperLayout).endFraction, 0.40, accuracy: 0.001)
            assertSameInk(PKDrawing(strokes: c),
                try PKDrawing(data: XCTUnwrap(committed.chordEvents.first?.sourceInkData)))
            let retained = PKDrawing(strokes: [last])
            assertSameInk(retained, host.ink.drawing)
            assertSameInk(retained, try PKDrawing(data: XCTUnwrap(host.model.chart.pageHandwrittenChordData)))
            assertTrue(await eventually(timeout: 5) { host.ink.drawing.strokes.isEmpty },
                "The barline-only remainder must finish without another stroke or manual action")
            try assertFinal(host, expected: [("C", c)])
        }
    }

    private enum SourceEdit: CaseIterable { case interiorPath, bitmapMask, erase }

    private func changedRoot(_ source: PKStroke, edit: SourceEdit) throws -> [PKStroke] {
        if edit == .erase { return [] }
        if edit == .bitmapMask {
            let bounds = source.renderBounds
            let mask = UIBezierPath(rect: CGRect(x: bounds.minX - 10, y: bounds.minY - 10,
                width: bounds.width + 20, height: bounds.height * 0.40 + 10))
            mask.append(UIBezierPath(rect: CGRect(x: bounds.minX - 10, y: bounds.minY + bounds.height * 0.60,
                width: bounds.width + 20, height: bounds.height * 0.40 + 10)))
            let changed = PKStroke(ink: source.ink, path: source.path, transform: source.transform,
                mask: mask, randomSeed: source.randomSeed)
            XCTAssertEqual(changed.path.count, source.path.count)
            XCTAssertFalse(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(
                expected: PKDrawing(strokes: [source]), current: PKDrawing(strokes: [changed])))
            return [changed]
        }
        let sourcePoints = Array(source.path)
        let minX = try XCTUnwrap(sourcePoints.map { $0.location.x }.min())
        let maxX = try XCTUnwrap(sourcePoints.map { $0.location.x }.max())
        let minY = try XCTUnwrap(sourcePoints.map { $0.location.y }.min())
        let maxY = try XCTUnwrap(sourcePoints.map { $0.location.y }.max())
        let index = try XCTUnwrap(sourcePoints.indices.first {
            let point = sourcePoints[$0].location
            return point.x > minX + 2 && point.x < maxX - 2 && point.y > minY + 2 && point.y < maxY - 2
        })
        let points = sourcePoints.enumerated().map { offset, point in
            PKStrokePoint(location: offset == index
                ? CGPoint(x: point.location.x + 1, y: point.location.y) : point.location,
                timeOffset: point.timeOffset, size: point.size, opacity: point.opacity,
                force: point.force, azimuth: point.azimuth, altitude: point.altitude)
        }
        let changed = PKStroke(ink: source.ink,
            path: PKStrokePath(controlPoints: points, creationDate: source.path.creationDate),
            transform: source.transform, mask: source.mask, randomSeed: source.randomSeed)
        XCTAssertEqual(changed.path.count, source.path.count)
        XCTAssertEqual(changed.renderBounds, source.renderBounds,
            "This edit changes the path while keeping the old bounds and stroke count")
        XCTAssertFalse(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(
            expected: PKDrawing(strokes: [source]), current: PKDrawing(strokes: [changed])))
        return [changed]
    }

    private struct Geometry { let lane: CGRect; let frame: CGRect }
    private struct Host {
        let model: NaturalWritingChartModel
        let view: LeadSheetCanvasUIKitView
        let ink: PKCanvasView
        let window: UIWindow
        let close: @MainActor () -> Void
    }

    private func mount(style: ChartLayoutStyle, paper: Bool, manual: Bool = false) async throws -> Host {
        let key = ChordInkWorkflowSettings.manualRenderWithPreviewKey
        let previous = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.set(manual, forKey: key)
        var chart = Chart.draft(title: "Disposable natural-writing cadence", layoutStyle: style)
        chart.completeInitialSetup(title: chart.title, key: .cMajor,
            meter: .init(numerator: 4, denominator: 4), staffStyle: .fiveLine, startingMeasureCount: 1)
        if paper { XCTAssertTrue(chart.initializePaperWritingRows(count: 3)) }
        XCTAssertEqual(chart.usesPaperMeasureLayout, paper)
        let model = NaturalWritingChartModel(chart)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root = NavigationStack {
            EditorView(chart: Binding(get: { model.chart }, set: { model.chart = $0 }),
                chordInkUserCorrectionMemoryStore: .init(url: directory.appendingPathComponent("corrections.json")),
                initialCanvasMode: .chordEntry)
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
            guard !closed else { return }; closed = true
            for view in self.descendants(window).compactMap({ $0 as? LeadSheetCanvasUIKitView }) {
                view.chordInkPreparationTestHook = nil
                view.recognizesChordInk = false
                view.onChordInkDraftPreviewChanged = nil
                view.onChordInkDraftBarlinesChanged = nil
                view.onChordInkDraftEndingsChanged = nil
                view.onChordInkAutomaticActivityChanged = nil
            }
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKeyAndVisible()
            if let previous { UserDefaults.standard.set(previous, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
            try? FileManager.default.removeItem(at: directory)
        }
        addTeardownBlock { @MainActor in close() }
        for _ in 0..<100 {
            window.layoutIfNeeded()
            if let view = descendants(window).compactMap({ $0 as? LeadSheetCanvasUIKitView }).first,
               let ink = view.subviews.compactMap({ $0 as? PKCanvasView }).last,
               !ink.isHidden, ink.isUserInteractionEnabled, ink.isFirstResponder,
               view.recognizesChordInk, view.manualRenderWithPreview == manual,
               view.chordDraftRenderCoordinator != nil, view.bounds.width > 0 {
                return Host(model: model, view: view, ink: ink, window: window, close: close)
            }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        close()
        throw NSError(domain: "ChordInkNaturalWritingCadenceWorkflowTests", code: 1)
    }

    private func firstLane(in host: Host) throws -> Geometry {
        let layout = LeadSheetPageLayoutEngine.pageLayout(for: host.model.chart,
            pageSize: host.view.bounds.size, includesChordInkContinuationLanes: true)
        let system = try XCTUnwrap(layout.systems.first)
        let lane = try XCTUnwrap(LeadSheetActiveInkScope.chordWritingSystemLaneFrame(
            for: system, paperFrame: layout.paperFrame(for: system)))
        return Geometry(lane: lane, frame: LeadSheetActiveInkScope.chordWritingFrame(for: layout))
    }

    private func captured(_ name: String, fraction: CGFloat, in geometry: Geometry,
        seed: UInt32) throws -> [PKStroke] {
        let fixture = try InkFixtureLoader.load(name, file: #filePath)
        let bounds = InkBounds.enclosing(fixture.strokes.map(\.bounds))
        let scale = Double(geometry.lane.height * 0.60) / bounds.height
        let origin = CGPoint(x: geometry.lane.minX + geometry.lane.width * fraction - geometry.frame.minX,
            y: geometry.lane.midY - geometry.lane.height * 0.30 - geometry.frame.minY)
        return fixture.strokes.enumerated().map { index, source in
            stroke(source.points.map {
                CGPoint(x: origin.x + CGFloat(($0.x - bounds.minX) * scale),
                    y: origin.y + CGFloat(($0.y - bounds.minY) * scale))
            }, seed: seed + UInt32(index))
        }
    }

    private func divider(fraction: CGFloat, xOffset: CGFloat = 0, heightRatio: CGFloat = 0.92,
        in geometry: Geometry, seed: UInt32) -> PKStroke {
        let x = geometry.lane.minX + geometry.lane.width * fraction + xOffset - geometry.frame.minX
        let inset = (1 - heightRatio) / 2
        return stroke([
            CGPoint(x: x, y: geometry.lane.minY + geometry.lane.height * inset - geometry.frame.minY),
            CGPoint(x: x, y: geometry.lane.maxY - geometry.lane.height * inset - geometry.frame.minY)
        ], seed: seed)
    }

    private func stroke(_ locations: [CGPoint], seed: UInt32) -> PKStroke {
        let points = locations.enumerated().map { index, location in
            PKStrokePoint(location: location, timeOffset: Double(index) * 0.002,
                size: .init(width: 2.5, height: 2.5), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKStroke(ink: PKInk(.pen, color: LeadSheetPersistentInkColorPolicy.inkColor),
            path: PKStrokePath(controlPoints: points, creationDate: Date()),
            transform: .identity, mask: nil, randomSeed: seed)
    }

    private func prefixStroke(_ source: PKStroke, pointCount: Int) -> PKStroke {
        PKStroke(ink: source.ink,
            path: PKStrokePath(controlPoints: Array(source.path.prefix(max(2, pointCount))), creationDate: source.path.creationDate),
            transform: source.transform, mask: source.mask, randomSeed: source.randomSeed)
    }

    private func append(_ strokes: [PKStroke], to host: Host) {
        input(host.ink.drawing.strokes + strokes, in: host)
    }

    private func replaceTail(_ source: PKStroke, seed: UInt32, in host: Host) {
        input(host.ink.drawing.strokes.filter { $0.randomSeed != seed } + [source], in: host)
    }

    private func input(_ strokes: [PKStroke], in host: Host) {
        host.view.canvasViewDidBeginUsingTool(host.ink)
        updateDrawing(strokes, in: host)
        host.view.canvasViewDidEndUsingTool(host.ink)
    }

    private func updateDrawing(_ strokes: [PKStroke], in host: Host) {
        host.ink.drawing = LeadSheetPersistentInkColorPolicy.normalizedDrawing(PKDrawing(strokes: strokes))
        host.view.canvasViewDrawingDidChange(host.ink)
    }

    private func assertFinal(_ host: Host, expected: [(String, [PKStroke])],
        file: StaticString = #filePath, line: UInt = #line) throws {
        let actual = events(host.model.chart)
        XCTAssertEqual(actual.map(\.symbol.displayText), expected.map { $0.0 }, file: file, line: line)
        XCTAssertNil(host.model.chart.pageHandwrittenChordData, file: file, line: line)
        XCTAssertTrue(host.ink.drawing.strokes.isEmpty, file: file, line: line)
        XCTAssertNil(host.window.rootViewController?.presentedViewController,
            "Normal writing must not require another panel", file: file, line: line)
        for (event, source) in zip(actual, expected) {
            assertSameInk(PKDrawing(strokes: source.1), try PKDrawing(data: XCTUnwrap(event.sourceInkData)), file: file, line: line)
        }
        let reopened = try ChartPersistenceCoders.decoder.decode(Chart.self,
            from: ChartPersistenceCoders.encoder.encode(host.model.chart))
        XCTAssertEqual(reopened, host.model.chart, file: file, line: line)
    }

    private func events(_ chart: Chart) -> [ChordEvent] { chart.measures.flatMap(\.chordEvents) }

    private func diagnose(_ label: String, host: Host) {
        let preview = host.view.chordPreviewState
        let savedCount = host.model.chart.pageHandwrittenChordData.flatMap { try? PKDrawing(data: $0).strokes.count } ?? 0
        let chords = preview.draftChords.map { draft in
            "text=\(draft.previewText ?? "nil") best=\(draft.bestCandidateText ?? "nil")"
                + " stale=\(draft.isStale) lifecycle=\(String(describing: draft.targetLifecycle?.stage))"
                + " decision=\(String(describing: draft.recognitionDecision?.action)) strokes=\(draft.strokeCount)"
                + " measure=\(draft.measureIndex) fraction=\(String(describing: draft.targetFraction))"
        }
        let bars = preview.draftBarlines.map { bar in
            "kind=\(bar.kind) fraction=\(bar.fraction) lane=\(String(describing: bar.laneLocation))"
                + " renderable=\(bar.isRenderable) ambiguity=\(String(describing: bar.ambiguity))"
                + " sources=\(bar.ownedSourceStrokeIndices.sorted())"
        }
        print("NATURAL_DIAGNOSTIC", label, "style", host.model.chart.layoutStyle.rawValue,
            "paper", host.model.chart.usesPaperMeasureLayout, "manual", host.view.manualRenderWithPreview,
            "census", host.view.hasCurrentAutomaticChordCensus, "resident", host.ink.drawing.strokes.count,
            "saved", savedCount, "events", events(host.model.chart).map(\.symbol.displayText),
            "chords", chords, "bars", bars, "endings", preview.draftEndings.count,
            "inputAge", host.view.chordDraftRenderCoordinator?.lastInputAt.map { Date().timeIntervalSince($0) } ?? -1,
            "structuralDeadline", host.view.chordDraftRenderCoordinator?.structuralMaturity.nextDeadline?.timeIntervalSinceNow ?? -1,
            "feedback", String(describing: host.view.chordDraftRenderCoordinator?.lastAutomaticAttempt?.feedback),
            "sourceCoverage", ChordInkDraftSourceCoveragePolicy.hasCompleteCoverage(chart: host.model.chart, state: preview),
            "hostState", host.view.chordInkPreparationDebugState)
    }

    private func activateAction(_ labels: [String], in host: Host) async throws {
        var action: NativeAccessibilityLookup.Node?
        assertTrue(await eventually(timeout: 5) {
            host.window.layoutIfNeeded()
            let nodes = (try? NativeAccessibilityLookup.nodes(in: host.window)) ?? []
            action = labels.lazy.compactMap { label in
                nodes.first { $0.isButton && $0.isEnabled && $0.element.accessibilityLabel == label }
            }.first
            return action != nil
        }, "The shipping action must be reachable: \(labels)")
        guard let action else {
            diagnose("missing-manual-action-\(labels.joined(separator: "/"))", host: host)
            let available = try NativeAccessibilityLookup.nodes(in: host.window).compactMap { $0.element.accessibilityLabel }
            print("NATURAL_MANUAL_AVAILABLE_ACTIONS", available)
            throw NSError(domain: "ChordInkNaturalWritingCadenceWorkflowTests", code: 2)
        }
        print("NATURAL_MANUAL_ACTION", host.model.chart.layoutStyle.rawValue, action.element.accessibilityLabel ?? "nil")
        if let button = action.element as? UIButton { button.sendActions(for: .touchUpInside) }
        else { XCTAssertTrue(action.element.accessibilityActivate()) }
    }

    private func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
    private func assertSameInk(_ expected: PKDrawing, _ current: PKDrawing,
        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(ChordInkDraftSourceCoveragePolicy.hasIdenticalVisibleInk(expected: expected, current: current),
            "Source paths, order, transforms and seeds must remain exact", file: file, line: line)
    }
    private func assertTrue(_ value: Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(value, message, file: file, line: line)
    }
    private func eventually(timeout: TimeInterval, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        } while Date() < deadline
        return condition()
    }
}

@MainActor
private final class NaturalWritingChartModel: ObservableObject {
    @Published var chart: Chart
    init(_ chart: Chart) { self.chart = chart }
}

private final class PreparationGate {
    private let condition = NSCondition()
    private let sourceCount: Int
    private var entered = false
    private var firstReleased = false
    private var released = false
    init(sourceCount: Int) { self.sourceCount = sourceCount }
    var hasEntered: Bool { condition.lock(); defer { condition.unlock() }; return entered }
    func receive(_ result: ChordInkRecognitionPreparationResult) {
        condition.lock(); defer { condition.unlock() }
        let deadline = Date().addingTimeInterval(12)
        if !entered {
            guard result.sourceStrokeCount == sourceCount else { return }
            entered = true
            condition.broadcast()
            while !firstReleased && !released && condition.wait(until: deadline) {}
        } else {
            // A fast fresh census must not accidentally make the stale-prefix
            // test pass. Later preparation is held on its separate worker;
            // the actual chord reader and the main actor remain available.
            while !released && condition.wait(until: deadline) {}
        }
    }
    func releaseFirst() {
        condition.lock(); defer { condition.unlock() }
        firstReleased = true
        condition.broadcast()
    }
    func release() {
        condition.lock(); defer { condition.unlock() }
        released = true
        condition.broadcast()
    }
}
#endif
