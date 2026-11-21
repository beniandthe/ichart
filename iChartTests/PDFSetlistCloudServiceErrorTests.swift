#if canImport(Supabase)
import Foundation
import Supabase
import XCTest
@testable import iChart

final class PDFSetlistCloudServiceErrorTests: XCTestCase {
    func testHTTP409ApplicationConflictBecomesCloudChanged() async throws {
        let error = try await wireError(status: 409, code: "PT409")
        guard case .some(.cloudChanged) = IChartPDFSetlistCloudService.commitError(error) as? IChartPDFSetlistCloudError else {
            return XCTFail("A stale setlist revision must offer the existing cloud-change recovery")
        }
    }

    func testLegacyHTTP500SerializationConflictStillBecomesCloudChanged() async throws {
        let error = try await wireError(status: 500, code: "40001")
        guard case .some(.cloudChanged) = IChartPDFSetlistCloudService.commitError(error) as? IChartPDFSetlistCloudError else {
            return XCTFail("Older server deployments must retain the same recovery")
        }
    }

    func testOtherConflictAndPermissionErrorsRetainTheirFullPostgrestDetails() async throws {
        for (status, code) in [(409, "23505"), (403, "42501")] {
            let original = try await wireError(status: status, code: code)
            let mapped = try XCTUnwrap(IChartPDFSetlistCloudService.commitError(original) as? PostgrestError)
            XCTAssertEqual(mapped.code, original.code)
            XCTAssertEqual(mapped.message, original.message)
            XCTAssertEqual(mapped.details, original.details)
            XCTAssertEqual(mapped.hint, original.hint)
        }
    }

    func testTransportFailuresAndCancellationAreNotReclassified() {
        let original = NSError(domain: "Synthetic transport failure", code: 17)
        XCTAssertTrue((IChartPDFSetlistCloudService.commitError(original) as NSError) === original)
        XCTAssertTrue(IChartPDFSetlistCloudService.commitError(CancellationError()) is CancellationError)
        guard case .some(.invalidBackup) = IChartPDFSetlistCloudService.commitError(IChartPDFSetlistCloudError.invalidBackup)
            as? IChartPDFSetlistCloudError else {
            return XCTFail("Local validation errors must remain distinct from a cloud revision conflict")
        }
    }

    private func wireError(status: Int, code: String) async throws -> PostgrestError {
        let body = try JSONSerialization.data(withJSONObject: [
            "code": code, "message": "Synthetic stale revision", "details": "fixture detail", "hint": "fixture hint"
        ])
        let client = PostgrestClient(url: URL(string: "https://setlist-conflict.invalid/rest/v1")!, fetch: { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/rest/v1/rpc/commit_pdf_setlist_backup")
            return (body, try XCTUnwrap(HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: status,
                httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])))
        })
        do {
            let _: PostgrestResponse<Void> = try await client.rpc("commit_pdf_setlist_backup",
                params: ["expected_version": Int64(3)]).execute()
            XCTFail("The synthetic HTTP error must travel through the SDK's PostgrestError decoder")
            throw URLError(.badServerResponse)
        } catch let error as PostgrestError {
            XCTAssertEqual(error.code, code)
            return error
        }
    }
}
#endif
