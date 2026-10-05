import CryptoKit
import Foundation
import XCTest
@testable import iChart

/// Opt-in, read-only compatibility check against a locally preserved profile.
/// No labels, ink, or private file path are printed; nothing is taught or saved.
final class PersonalInkProvidedProfileCompatibilityTests: XCTestCase {
    func testProvidedProfileLoadsWithoutChangingSourceOrLessonInputs() throws {
        guard let path = ProcessInfo.processInfo.environment["ICHART_PERSONAL_PROFILE_COMPATIBILITY_FILE"] else {
            throw XCTSkip("Requires an explicitly provided local profile copy")
        }
        let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        let before = try Data(contentsOf: url)
        defer { XCTAssertEqual(try? Data(contentsOf: url), before, "The provided evidence must remain unchanged") }
        let decoded = try JSONDecoder().decode(PersonalInkProfile.self, from: before)
        XCTAssertFalse(decoded.examples.isEmpty, "An empty profile is not a compatibility check")
        XCTAssertTrue(decoded.examples.allSatisfy(\.hasValidRecognitionInput))

        let store = PersonalInkProfileStore(url: url)
        XCTAssertNil(store.loadError)
        let loaded = store.snapshot().profile
        XCTAssertEqual(loaded, decoded)
        XCTAssertEqual(loaded.examples.map(\.recognitionInput), decoded.examples.map(\.recognitionInput))
        XCTAssertEqual(loaded.examples.map(\.learningProvenance), decoded.examples.map(\.learningProvenance))
        XCTAssertEqual(loaded.revision, decoded.revision)
        XCTAssertEqual(loaded.generation, decoded.generation)
        let legacyCount = loaded.examples.filter { $0.recognitionStrokes == nil }.count
        let digest = SHA256.hash(data: before).map { String(format: "%02x", $0) }.joined()
        print("PERSONAL_PROFILE_COMPATIBILITY sha256=\(digest) examples=\(loaded.examples.count) legacy=\(legacyCount) fullInput=\(loaded.examples.count - legacyCount) sourceUnchanged=true noTeaching=true")
    }
}
