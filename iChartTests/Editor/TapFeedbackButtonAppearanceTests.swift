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

    private func render(isAcknowledged: Bool, isEnabled: Bool, scheme: ColorScheme) throws -> UIImage {
        let content = Button(action: {}) {
            Text("End Repeat")
                .frame(width: 164, height: 48)
                .foregroundStyle(.white)
                .background(IChartInterfaceStyle.actionBlue, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(IChartTapFeedbackButtonStyle(isAcknowledged: isAcknowledged))
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
