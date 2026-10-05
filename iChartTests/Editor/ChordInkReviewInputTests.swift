#if canImport(UIKit)
import SwiftUI
import UIKit
import XCTest
@testable import iChart

@MainActor
final class ChordInkReviewInputTests: XCTestCase {
    func testBatchFieldsKeepFocusAndEditedValuesWhenChangingRows() async throws {
        let confirmations = ["C", "A6(b5)", "D-7", "F", "G7"].enumerated().map { index, text in
            let result = ChordInkRecognitionResult(rawCandidates: [text], glyphCandidates: [],
                                                   match: ChordRecognitionCompendium.match(text), confidence: 1)
            let decision = ChordInkRecognitionPolicy.decision(for: result)
            return PendingChordInkConfirmation(measureID: UUID(), measureIndex: index, result: result,
                drawingData: Data(), targetFraction: 0, primaryDecision: decision, decision: decision)
        }
        var acceptedTexts: [UUID: String]?
        var rewriteCount = 0
        let root = ChordInkBatchConfirmationSheetView(batch: .init(confirmations: confirmations),
            onAcceptAll: { acceptedTexts = $0 }, onClearAndRewrite: { rewriteCount += 1 })
        let host = UIHostingController(rootView: root)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 820, height: 1180))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 100_000_000)
        let buttons = descendants(host.view).compactMap { $0 as? PencilOnlyUIButton }
        let footerButtons = buttons.filter { ["Render All", "Rewrite Ink"].contains($0.accessibilityLabel ?? "") }
        XCTAssertEqual(footerButtons.count, 2)
        for button in footerButtons {
            XCTAssertGreaterThanOrEqual(button.bounds.height, 44)
            XCTAssertLessThanOrEqual(button.bounds.height, 80, "Footer buttons must not consume the review area")
        }
        XCTAssertTrue(buttons.allSatisfy(\.acceptsDirectTouches), "Review must accept finger taps on a physical iPad")
        let editButtons = buttons.filter { $0.accessibilityLabel?.hasPrefix("Type chord for measure ") == true }
        XCTAssertEqual(editButtons.count, 5)
        let firstEdit = try XCTUnwrap(editButtons.first)
        let secondEdit = try XCTUnwrap(editButtons.dropFirst().first)
        let fields = descendants(host.view).compactMap { $0 as? UITextField }.filter { $0.placeholder == "Chord" }
        XCTAssertEqual(fields.count, 5)
        let first = try XCTUnwrap(fields.first)
        let second = try XCTUnwrap(fields.dropFirst().first)
        firstEdit.sendActions(for: .touchUpInside)
        try await waitForFocus(first)
        XCTAssertTrue(first.isFirstResponder, "Edit must focus its field and survive the SwiftUI state update")
        let scribble = try XCTUnwrap(first.interactions.compactMap { $0 as? UIScribbleInteraction }.first)
        XCTAssertEqual(scribble.delegate?.scribbleInteraction?(scribble, shouldBeginAt: CGPoint(x: 10, y: 10)), false,
                       "Explicit keyboard entry must not be intercepted by Scribble")
        first.text = "Ebmaj7"
        first.sendActions(for: .editingChanged)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(first.isFirstResponder, "Editing must not dismiss the keyboard")
        XCTAssertEqual(first.text, "Ebmaj7")
        secondEdit.sendActions(for: .touchUpInside)
        try await waitForFocus(second)
        XCTAssertTrue(second.isFirstResponder, "The previous row's end-edit callback must not steal focus")
        XCTAssertEqual(first.text, "Ebmaj7")
        second.text = "D7"
        second.sendActions(for: .editingChanged)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(second.isFirstResponder)
        XCTAssertEqual(second.text, "D7")
        firstEdit.sendActions(for: .touchUpInside)
        try await waitForFocus(first)
        XCTAssertTrue(first.isFirstResponder, "Switching backwards must also preserve focus")
        XCTAssertEqual(first.text, "Ebmaj7")
        XCTAssertEqual(second.text, "D7")
        XCTAssertNil(acceptedTexts, "Editing must not implicitly render or train")
        XCTAssertEqual(rewriteCount, 0)
        let render = try XCTUnwrap(footerButtons.first { $0.accessibilityLabel == "Render All" })
        render.sendActions(for: .touchUpInside)
        XCTAssertEqual(acceptedTexts?[confirmations[0].id], "Ebmaj7")
        XCTAssertEqual(acceptedTexts?[confirmations[1].id], "D7")
        XCTAssertEqual(acceptedTexts?.count, 5)
        first.resignFirstResponder()
        try await Task.sleep(nanoseconds: 300_000_000)
        let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        })
        attachment.name = "Compact five-chord review with corrected values"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func waitForFocus(_ field: UITextField) async throws {
        // Allow UIKit's keyboard/scroll animation, then assert focus stability.
        for _ in 0..<20 where !field.isFirstResponder {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        try await Task.sleep(nanoseconds: 100_000_000)
    }

    private func descendants(_ view: UIView) -> [UIView] { view.subviews.flatMap { [$0] + descendants($0) } }
}
#endif
