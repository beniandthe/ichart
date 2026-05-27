#if canImport(UIKit)
import PencilKit
import XCTest
@testable import SmartChart

final class LeadSheetInteractionModeStatePolicyTests: XCTestCase {
    func testChordEntryPreservesOriginalPenWeight() {
        let policy = LeadSheetInteractionModeStatePolicy.resolve(for: .chordEntry)

        XCTAssertEqual(policy.inkTool.inkType, .pen)
        XCTAssertEqual(policy.inkTool.width, 2.5, accuracy: 0.001)
    }

    func testChordEntryKeepsSimulatorPointerInputForAutomation() {
        let policy = LeadSheetInteractionModeStatePolicy.resolve(for: .chordEntry)

        #if targetEnvironment(simulator)
        XCTAssertEqual(policy.drawingPolicy, .anyInput)
        #else
        XCTAssertEqual(policy.drawingPolicy, .pencilOnly)
        #endif
    }
}
#endif
