#if canImport(UIKit) && canImport(PencilKit)
import PencilKit
import SwiftUI
import UIKit
import XCTest
@testable import iChart

@MainActor
final class ChordInkQualityRecoveryTests: XCTestCase {
    func testMajorSeventhIsAnExplicitQualityChoiceWithoutRecognitionAlternatives() {
        for candidates in [[], ["Cø7", "Dbø7", "Bbø7"]] {
            let correction = makeCorrection("Cø7", candidates: candidates)
            XCTAssertTrue(correction.qualityChoiceTexts.contains("C△7"))
            XCTAssertFalse(correction.visibleAlternativeTexts.contains("C△7"),
                "A common edit choice must not become a saved recognition alternative")
            XCTAssertEqual(correction.candidateTexts, candidates)
            XCTAssertEqual(correction.currentText, "Cø7")
            XCTAssertEqual(correction.rawInput, "Cø7")
        }
    }

    func testQualityChoicesPreserveAccidentalsExtensionsAlterationsAndSlashBass() throws {
        for text in ["Bbø7/F", "Eb-9/Bb", "Db7(b9)/F", "F#7(#11)/C#"] {
            let source = try XCTUnwrap(ChordRecognitionCompendium.match(text), text).symbol
            let choices = ChordInkCorrectionQualityPolicy.choiceTexts(for: text)
            XCTAssertFalse(choices.isEmpty, "The supported source must retain supported quality alternatives: \(text)")
            XCTAssertEqual(Set(choices).count, choices.count)
            for choice in choices {
                let match = try XCTUnwrap(ChordRecognitionCompendium.match(choice), choice)
                XCTAssertEqual(match.displayText, choice)
                XCTAssertEqual(match.symbol.kind, .rooted)
                XCTAssertEqual(match.symbol.root, source.root)
                XCTAssertEqual(match.symbol.accidental, source.accidental)
                XCTAssertEqual(match.symbol.extensions, source.extensions)
                XCTAssertEqual(match.symbol.alterations, source.alterations)
                XCTAssertEqual(match.symbol.slashBass, source.slashBass)
                XCTAssertNotEqual(match.symbol.quality, source.quality)
                XCTAssertTrue(Set(["△", "", "-", "ø", "°", "-△"]).contains(match.symbol.quality))
            }
        }
        XCTAssertTrue(ChordInkCorrectionQualityPolicy.choiceTexts(for: "Bbø7/F").contains("Bb△7/F"))
        XCTAssertTrue(ChordInkCorrectionQualityPolicy.choiceTexts(for: "Eb-9/Bb").contains("Eb△9/Bb"))
    }

    func testUnsupportedAndNonRootedInputsNeverReceiveInventedQualityChoices() {
        for text in ["", "not a chord", "Cmaj", ChordSymbol.chordRepeatDisplayText] {
            XCTAssertTrue(ChordInkCorrectionQualityPolicy.choiceTexts(for: text).isEmpty, text)
        }
        let choices = ChordInkCorrectionQualityPolicy.choiceTexts(for: "Cø7",
            excluding: ["C△7", "C7"])
        XCTAssertFalse(choices.contains("C△7"))
        XCTAssertFalse(choices.contains("C7"))
        XCTAssertFalse(choices.contains("Cø7"))
        XCTAssertTrue(choices.allSatisfy { ChordRecognitionCompendium.match($0) != nil })
    }

    func testSavedAlternativesBeyondThreeStayVisibleWithoutRewritingTheirEvidence() {
        let source = ["Cø7", "Dbø7", "Dø7", "Cmaj7", "F7", "G7", "A7", "unsupported", "CM7"]
        let correction = makeCorrection("Cø7", candidates: source)
        XCTAssertEqual(correction.candidateTexts, source)
        XCTAssertEqual(correction.visibleAlternativeTexts,
            ["Dbø7", "Dø7", "C△7", "F7", "G7", "A7"])
        XCTAssertFalse(correction.qualityChoiceTexts.contains("C△7"),
            "An already-visible saved alternative need not be repeated as a generic edit shortcut")
        XCTAssertEqual(correction.candidateTexts, source,
            "Accessing the choices cannot truncate, expand, normalize or replace saved recognition evidence")
    }

    func testMajorQualityShortcutClearsTeachingAndSavesExactSourceInSimple() async throws {
        try await assertNativeQualityRecovery(style: .simpleChordSheet)
    }

    func testMajorQualityShortcutClearsTeachingAndSavesExactSourceInRhythm() async throws {
        try await assertNativeQualityRecovery(style: .rhythmSectionSheet)
    }

    private func assertNativeQualityRecovery(style: ChartLayoutStyle) async throws {
        var chart = Chart.blank(title: "Quality recovery", measureCount: 2, layoutStyle: style)
        let measureID = chart.measures[0].id
        let drawing = sourceDrawing()
        let signature = ["Cø7", "Dbø7", "Bbø7"]
        let chordID = try XCTUnwrap(chart.appendRecognizedChordEvent(try ChordSymbolParser.parse("Cø7"),
            rawInput: "Cø7", to: measureID, atFraction: 0.4,
            sourceInkData: drawing.dataRepresentation(), sourceCandidateSignature: signature,
            sourceRecognitionPipelineVersion: "quality-recovery-test"))
        let before = try XCTUnwrap(chart.chordEvent(id: chordID))
        let untouched = chart.measures[1]
        let correction = PendingChordCorrection(chordEventID: chordID, measureID: measureID,
            measureIndex: 0, currentText: "Cø7", rawInput: before.rawInput,
            candidateTexts: before.sourceCandidateSignature, enharmonicChoiceTexts: [],
            sourceInkData: before.sourceInkData)
        var accepted: (text: String, teaches: Bool)?
        var cancelled = false
        let root = ChordCorrectionSheetView(correction: correction, canTeachHandwriting: true,
            onAcceptCandidate: { accepted = ($0, $1) }, onCancel: { cancelled = true })
        let host = QualityRecoveryHostingController(rootView: root)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = host
        window.makeKeyAndVisible()
        addTeardownBlock { @MainActor in
            window.endEditing(true)
            try? await Task.sleep(nanoseconds: 50_000_000)
            window.isHidden = true
            window.rootViewController = nil
            try? await Task.sleep(nanoseconds: 50_000_000)
            previousWindow?.makeKey()
        }
        for _ in 0..<40 {
            window.layoutIfNeeded()
            host.view.layoutIfNeeded()
            if host.hasAppeared, window.isKeyWindow,
               host.view.bounds.size == window.bounds.size { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(host.hasAppeared && window.isKeyWindow,
            "The correction sheet must own an appeared native window before checking controls")
        XCTAssertEqual(host.view.bounds, window.bounds)

        let guide = try await visibleNode(in: window, named: "Edit Chord guidance") {
            $0.element.accessibilityLabel?.contains("Save applies the chord shown in Change to.") == true
        }
        XCTAssertTrue(window.bounds.insetBy(dx: -1, dy: -1).contains(guide.frame(in: window)))
        XCTAssertNil(accepted)
        let teach = try await visibleNode(in: window, named: "Teach handwriting toggle") {
            $0.element.accessibilityLabel == "Teach this handwriting correction"
        }
        if let toggle = teach.element as? UISwitch {
            toggle.setOn(true, animated: false)
            toggle.sendActions(for: .valueChanged)
        } else {
            XCTAssertTrue(teach.element.accessibilityActivate())
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        let enabledTeach = try await visibleNode(in: window, named: "Enabled Teach handwriting toggle") {
            $0.element.accessibilityLabel == "Teach this handwriting correction"
        }
        XCTAssertEqual(enabledTeach.element.accessibilityValue, "1")

        let major = try await visibleNode(in: window, named: "Change quality to C△7") {
            $0.isButton && $0.element.accessibilityLabel == "Change quality to C△7"
        }
        XCTAssertEqual(major.element.accessibilityHint, "Sets Change to. Tap Save to apply this edit.")
        try activate(major)
        try await Task.sleep(nanoseconds: 100_000_000)
        let field = try XCTUnwrap(descendants(host.view).compactMap { $0 as? IChartTypedUITextField }
            .first { $0.placeholder == "Type chord" })
        XCTAssertEqual(field.text, "C△7")
        XCTAssertNil(accepted, "A quality shortcut changes the proposed edit; it must not save automatically")
        let disabledTeach = try await visibleNode(in: window, named: "Cleared Teach handwriting toggle") {
            $0.element.accessibilityLabel == "Teach this handwriting correction"
        }
        XCTAssertEqual(disabledTeach.element.accessibilityValue, "0")

        let save = try await visibleNode(in: window, named: "Save") {
            $0.isButton && $0.element.accessibilityLabel == "Save"
        }
        XCTAssertTrue(save.isEnabled)
        XCTAssertTrue(window.bounds.insetBy(dx: -1, dy: -1).contains(save.frame(in: window)),
            "Save must remain reachable through the correction sheet's normal scroll")
        try activate(save)
        let value = try XCTUnwrap(accepted)
        XCTAssertEqual(value.text, "C△7")
        XCTAssertFalse(value.teaches, "Generic quality recovery is an edit choice, never handwriting-label evidence")
        XCTAssertFalse(cancelled)
        let match = try XCTUnwrap(ChordRecognitionCompendium.match(value.text))
        XCTAssertTrue(chart.replaceChordEvent(chordID, with: match.symbol, rawInput: value.text))
        let saved = try reopen(chart)
        let after = try XCTUnwrap(saved.chordEvent(id: chordID))
        var expected = before
        expected.symbol = match.symbol
        expected.rawInput = value.text
        expected.spellingIntent = .explicit
        expected.spellingOverrideSource = .userSelection
        XCTAssertEqual(after, expected)
        XCTAssertEqual(after.sourceInkData, before.sourceInkData)
        XCTAssertEqual(after.sourceCandidateSignature, signature)
        XCTAssertFalse(after.sourceCandidateSignature.contains("C△7"))
        XCTAssertEqual(saved.measures.map(\.id), chart.measures.map(\.id))
        XCTAssertEqual(saved.measures[1], untouched)
        XCTAssertEqual(saved.layoutStyle, style)
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "\(style.rawValue) explicit quality recovery and reachable Save"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func visibleNode(in window: UIWindow, named name: String,
        matching predicate: (NativeAccessibilityLookup.Node) -> Bool
    ) async throws -> NativeAccessibilityLookup.Node {
        for _ in 0..<3 {
            window.layoutIfNeeded()
            let scrolls = descendants(window).compactMap { $0 as? UIScrollView }
                .filter { $0.bounds.width > 300 && $0.bounds.height > 100 }
                .sorted { $0.bounds.height > $1.bounds.height }
            let scroll = scrolls.first
            let maxY = scroll.map { max(-$0.adjustedContentInset.top,
                $0.contentSize.height - $0.bounds.height + $0.adjustedContentInset.bottom) } ?? 0
            let minY = scroll.map { -$0.adjustedContentInset.top } ?? 0
            let stride = max(80, (scroll?.bounds.height ?? window.bounds.height) * 0.55)
            let steps = max(1, Int(ceil(max(0, maxY - minY) / stride)))
            for step in 0...steps {
                if let scroll {
                    scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x,
                        y: min(maxY, minY + CGFloat(step) * stride)), animated: false)
                }
                try await Task.sleep(nanoseconds: 50_000_000)
                window.layoutIfNeeded()
                if let node = try NativeAccessibilityLookup.nodes(in: window).first(where: {
                    predicate($0) && window.bounds.insetBy(dx: -1, dy: -1).contains($0.frame(in: window))
                        && !$0.frame(in: window).isEmpty
                }) { return node }
            }
        }
        let nodes = try NativeAccessibilityLookup.nodes(in: window)
        let details = nodes.compactMap { node -> String? in
            guard let label = node.element.accessibilityLabel, !label.isEmpty else { return nil }
            return "\(String(label.prefix(180))) | \(node.frame(in: window))"
        }.prefix(120).joined(separator: "\n")
        let diagnostic = XCTAttachment(string: "Missing: \(name)\nWindow: \(window.bounds)\n\(details)")
        diagnostic.name = "Correction reachability - \(name)"
        diagnostic.lifetime = .keepAlways
        add(diagnostic)
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let screenshot = XCTAttachment(image: image)
        screenshot.name = "Correction reachability failure - \(name)"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTFail("The correction control or guidance must be visible and reachable: \(name)")
        throw Failure.missingControl
    }

    private func activate(_ node: NativeAccessibilityLookup.Node) throws {
        XCTAssertTrue(node.isEnabled)
        if let button = node.element as? UIButton { button.sendActions(for: .touchUpInside) }
        else { XCTAssertTrue(node.element.accessibilityActivate()) }
    }

    private func descendants(_ view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap(descendants)
    }

    private func makeCorrection(_ text: String, candidates: [String]) -> PendingChordCorrection {
        .init(chordEventID: UUID(), measureID: UUID(), measureIndex: 0,
            currentText: text, rawInput: text, candidateTexts: candidates, enharmonicChoiceTexts: [])
    }

    private func sourceDrawing() -> PKDrawing {
        let path = PKStrokePath(controlPoints: [CGPoint(x: 30, y: 20), CGPoint(x: 45, y: 42),
            CGPoint(x: 30, y: 60)].enumerated().map { index, point in
                PKStrokePoint(location: point, timeOffset: Double(index) * 0.1,
                    size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
            }, creationDate: Date(timeIntervalSinceReferenceDate: 100))
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: LeadSheetPersistentInkColorPolicy.inkColor),
            path: path, transform: .identity, mask: nil, randomSeed: 10)])
    }

    private func reopen(_ chart: Chart) throws -> Chart {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileChartRepository(url: directory.appendingPathComponent("library-state.json"))
        try repository.saveSnapshot(.init(charts: [chart], selectedChartID: chart.id, entitlements: .free))
        return try XCTUnwrap(try repository.loadSnapshot()?.charts.first)
    }

    private enum Failure: Error { case missingControl }
}

@MainActor
private final class QualityRecoveryHostingController<Content: View>: UIHostingController<Content> {
    private(set) var hasAppeared = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        hasAppeared = true
    }
}
#endif
