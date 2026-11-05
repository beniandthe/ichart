#if canImport(UIKit)
import Foundation
import XCTest
@testable import iChart

final class ChordInkReaderRetryDiagnosticsTests: XCTestCase {
    func testReceiptEncodingContainsOnlyAllowlistedMetadata() throws {
        let (store, _) = try makeStore()
        store.setConsentGranted(true)
        let proof = makeProof(consent: store.snapshot)
        let receipt = try XCTUnwrap(makeReceipt(proof))
        let data = try JSONEncoder().encode(receipt)
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(Set(fields.keys), [
            "schemaVersion", "build", "episodeID", "provider",
            "firstAttemptOutcome", "retryOutcome", "attemptCount",
            "failedAttemptMilliseconds", "recoveredAttemptMilliseconds",
            "supportedCandidateCount", "commitOutcome", "committedAtEpochSeconds",
            "sourceStrokeCount", "consumedStrokeCount", "retainedStrokeCount",
            "sourceStillCurrent", "sourcePreserved"
        ])
        XCTAssertEqual(fields["episodeID"] as? String, proof.episodeID.uuidString)
        XCTAssertEqual(fields["firstAttemptOutcome"] as? String, "technical_failure")
        XCTAssertEqual(fields["retryOutcome"] as? String, "completed_supported")
        XCTAssertEqual(fields["attemptCount"] as? Int, 2)
        XCTAssertEqual(fields["commitOutcome"] as? String, "automatic_render_complete")
        XCTAssertEqual(fields["sourcePreserved"] as? Bool, true)
        XCTAssertLessThan(data.count, 2_048)
    }

    func testReceiptRejectsMissingConsentAndInvalidSourceAccounting() throws {
        let (store, _) = try makeStore()
        XCTAssertNil(makeReceipt(makeProof(consent: store.snapshot)))

        store.setConsentGranted(true)
        let proof = makeProof(consent: store.snapshot)
        XCTAssertNil(makeReceipt(proof, consumed: 0, retained: 6))
        XCTAssertNil(makeReceipt(proof, consumed: 3, retained: 2))
        XCTAssertNil(makeReceipt(proof, consumed: 7, retained: -1))
        XCTAssertNil(makeReceipt(makeProof(consent: store.snapshot, failedMilliseconds: .infinity)))
        XCTAssertNil(makeReceipt(makeProof(consent: store.snapshot, candidateCount: 0)))
    }

    func testWithdrawalRemovesReceiptAndOldProofCannotWriteAfterRegrant() throws {
        let (store, url) = try makeStore()
        store.setConsentGranted(true)
        let oldProof = makeProof(consent: store.snapshot)
        let data = try JSONEncoder().encode(XCTUnwrap(makeReceipt(oldProof)))
        XCTAssertTrue(try store.publishLocalDiagnosticReceipt(data, to: url, matching: oldProof.consent))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))

        store.setConsentGranted(false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        store.setConsentGranted(true)

        XCTAssertFalse(try store.publishLocalDiagnosticReceipt(data, to: url, matching: oldProof.consent))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        let freshProof = makeProof(consent: store.snapshot)
        let freshData = try JSONEncoder().encode(XCTUnwrap(makeReceipt(freshProof)))
        let otherURL = url.deletingLastPathComponent().appendingPathComponent("unregistered.json")
        XCTAssertFalse(try store.publishLocalDiagnosticReceipt(freshData, to: otherURL, matching: freshProof.consent))
        XCTAssertTrue(try store.publishLocalDiagnosticReceipt(freshData, to: url, matching: freshProof.consent))
    }

    private func makeStore() throws -> (IChartTelemetryConsentStore, URL) {
        let name = "ReaderRetryDiagnosticsTests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: name)
            try FileManager.default.removeItem(at: directory)
        }
        let url = directory.appendingPathComponent("receipt.json")
        return (IChartTelemetryConsentStore(defaults: defaults, diagnosticFileURLs: [url]), url)
    }

    private func makeProof(
        consent: IChartTelemetryConsentSnapshot,
        failedMilliseconds: Double = 4,
        candidateCount: Int = 2
    ) -> ChordInkReaderRetryProof {
        ChordInkReaderRetryProof(
            episodeID: UUID(), failedAttemptMilliseconds: failedMilliseconds,
            recoveredAttemptMilliseconds: 7, supportedCandidateCount: candidateCount,
            consent: consent
        )
    }

    private func makeReceipt(
        _ proof: ChordInkReaderRetryProof, consumed: Int = 4, retained: Int = 2
    ) -> ChordInkReaderRetryDiagnostics.Receipt? {
        ChordInkReaderRetryDiagnostics.Receipt(
            proof: proof, build: 109, committedAt: Date(timeIntervalSince1970: 1_800_000_000),
            sourceStrokeCount: 6, consumedStrokeCount: consumed, retainedStrokeCount: retained
        )
    }
}
#endif
