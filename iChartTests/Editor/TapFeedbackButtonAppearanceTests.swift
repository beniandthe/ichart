#if canImport(UIKit)
import SwiftUI
import UIKit
import XCTest
@testable import iChart

@MainActor
final class TapFeedbackButtonAppearanceTests: XCTestCase {
    func testAcknowledgedControlChangesAppearanceWithoutChangingItsSize() throws {
        for scheme in [ColorScheme.light, .dark] {
            let idle = try render(isAcknowledged: false, isEnabled: true, scheme: scheme)
            let active = try render(isAcknowledged: true, isEnabled: true, scheme: scheme)
            XCTAssertEqual(active.size, idle.size)
            XCTAssertEqual(active.size, CGSize(width: 164, height: 48))
            XCTAssertNotEqual(try png(active), try png(idle), "The acknowledgement must be visible in \(scheme)")
        }
    }

    func testDisabledControlDoesNotDisplayAcknowledgement() throws {
        let idle = try render(isAcknowledged: false, isEnabled: false, scheme: .light)
        let disabled = try render(isAcknowledged: true, isEnabled: false, scheme: .light)
        XCTAssertEqual(try png(disabled), try png(idle))
    }

    func testAcknowledgementReachesBothBlankEdgesOfWideTitleBox() throws {
        let idle = try render(isAcknowledged: false, isEnabled: true, scheme: .light, width: 260)
        let active = try render(isAcknowledged: true, isEnabled: true, scheme: .light, width: 260)
        let idleCG = try XCTUnwrap(idle.cgImage)
        let activeCG = try XCTUnwrap(active.cgImage)
        XCTAssertEqual(active.size, CGSize(width: 260, height: 48))
        for edge in [CGRect(x: 0, y: 16, width: 5, height: 16), CGRect(x: 255, y: 16, width: 5, height: 16)] {
            let idleEdge = try XCTUnwrap(idleCG.cropping(to: edge))
            let activeEdge = try XCTUnwrap(activeCG.cropping(to: edge))
            XCTAssertNotEqual(try png(UIImage(cgImage: idleEdge)), try png(UIImage(cgImage: activeEdge)))
        }
    }

    func testRaisedToolFaceRemainsVisibleOverAnOpaqueSelectedControl() throws {
        for scheme in [ColorScheme.light, .dark] {
            let flat = try render(isAcknowledged: false, isEnabled: true, scheme: scheme)
            let raised = try render(isAcknowledged: false, isEnabled: true, scheme: scheme, isRaised: true)
            let accepted = try render(isAcknowledged: true, isEnabled: true, scheme: scheme, isRaised: true)
            XCTAssertEqual(raised.size, flat.size)
            XCTAssertEqual(accepted.size, raised.size)
            XCTAssertNotEqual(try png(raised), try png(flat))
            XCTAssertNotEqual(try png(accepted), try png(raised))
        }
    }

    private func render(
        isAcknowledged: Bool,
        isEnabled: Bool,
        scheme: ColorScheme,
        width: CGFloat = 164,
        isRaised: Bool = false
    ) throws -> UIImage {
        let content = Button(action: {}) {
            Text("End Repeat")
                .frame(width: width, height: 48)
                .foregroundStyle(.white)
                .background(IChartInterfaceStyle.actionBlue, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(IChartTapFeedbackButtonStyle(isAcknowledged: isAcknowledged, isRaised: isRaised))
        .disabled(!isEnabled)
        .environment(\.colorScheme, scheme)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        return try XCTUnwrap(renderer.uiImage)
    }

    private func png(_ image: UIImage) throws -> Data {
        try XCTUnwrap(image.pngData())
    }
}
#endif
