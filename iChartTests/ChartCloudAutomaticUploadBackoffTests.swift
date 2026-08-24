import XCTest
@testable import iChart

final class ChartCloudAutomaticUploadBackoffTests: XCTestCase {
    func testAllowsAutomaticUploadBeforeFailureAndAfterCooldown() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        var backoff = ChartCloudAutomaticUploadBackoff(cooldown: 30)

        XCTAssertTrue(backoff.allowsAutomaticUpload(at: start))

        backoff.recordFailure(at: start)

        XCTAssertFalse(backoff.allowsAutomaticUpload(at: start.addingTimeInterval(29.9)))
        XCTAssertTrue(backoff.allowsAutomaticUpload(at: start.addingTimeInterval(30)))
        XCTAssertEqual(backoff.remainingCooldown(at: start.addingTimeInterval(10)), 20, accuracy: 0.001)
    }

    func testSuccessAndResetClearCooldown() {
        let start = Date(timeIntervalSinceReferenceDate: 2_000)
        var backoff = ChartCloudAutomaticUploadBackoff(cooldown: 30)

        backoff.recordFailure(at: start)
        XCTAssertFalse(backoff.allowsAutomaticUpload(at: start.addingTimeInterval(1)))

        backoff.recordSuccess()
        XCTAssertTrue(backoff.allowsAutomaticUpload(at: start.addingTimeInterval(1)))

        backoff.recordFailure(at: start)
        backoff.reset()
        XCTAssertTrue(backoff.allowsAutomaticUpload(at: start.addingTimeInterval(1)))
    }
}
