import Foundation
import Supabase

struct IChartPDFSetlistCloudEnvelope: Codable {
    var version: Int64
    var manifest: IChartPDFSetlistCloudDocument?

    private enum CodingKeys: String, CodingKey { case version, manifest }

    init(version: Int64, manifest: IChartPDFSetlistCloudDocument?) {
        self.version = version
        self.manifest = manifest
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int64.self, forKey: .version)
        if let payload = try values.decodeIfPresent(IChartJSONValue.self, forKey: .manifest) {
            manifest = try ChartPersistenceCoders.decoder.decode(IChartPDFSetlistCloudDocument.self,
                from: JSONEncoder().encode(payload))
        }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(version, forKey: .version)
        if let manifest {
            try values.encode(IChartPDFSetlistCloudValidation.payload(manifest), forKey: .manifest)
        } else { try values.encodeNil(forKey: .manifest) }
    }
}

protocol IChartPDFSetlistCloudServicing: Sendable {
    func fetch(ownerID: UUID) async throws -> IChartPDFSetlistCloudEnvelope
    func download(_ pdf: IChartPDFSetlistCloudPDF, ownerID: UUID) async throws -> Data
    func upload(_ pdf: IChartPDFSetlistCloudPDF, data: Data, ownerID: UUID) async throws
    func commit(_ document: IChartPDFSetlistCloudDocument, expectedVersion: Int64,
        ownerID: UUID) async throws -> IChartPDFSetlistCloudEnvelope
}

actor IChartPDFSetlistCloudService: IChartPDFSetlistCloudServicing {
    private let client: SupabaseClient
    private let sessionRefresher: IChartSupabaseSessionRefresher
    private let bucket = "setlist-pdfs"

    init(client: SupabaseClient, sessionRefresher: IChartSupabaseSessionRefresher) {
        self.client = client
        self.sessionRefresher = sessionRefresher
    }

    private func verifyOwner(_ ownerID: UUID) async throws {
        try Task.checkCancellation()
        guard try await sessionRefresher.refreshIfNeeded().user.id == ownerID else {
            throw IChartPDFSetlistCloudError.accountChanged
        }
    }

    private func path(for pdf: IChartPDFSetlistCloudPDF, ownerID: UUID) -> String {
        "\(ownerID.uuidString.lowercased())/\(pdf.sha256).pdf"
    }

    func fetch(ownerID: UUID) async throws -> IChartPDFSetlistCloudEnvelope {
        try await verifyOwner(ownerID)
        struct Parameters: Encodable { let expected_owner_id: UUID }
        let result: IChartPDFSetlistCloudEnvelope = try await client.rpc("get_pdf_setlist_backup",
            params: Parameters(expected_owner_id: ownerID)).execute().value
        try await verifyOwner(ownerID)
        if let document = result.manifest { try IChartPDFSetlistCloudValidation.validate(document) }
        guard result.version >= 0, (result.version == 0) == (result.manifest == nil) else {
            throw IChartPDFSetlistCloudError.invalidBackup
        }
        return result
    }

    func download(_ pdf: IChartPDFSetlistCloudPDF, ownerID: UUID) async throws -> Data {
        try await verifyOwner(ownerID)
        let data = try await client.storage.from(bucket).download(path: path(for: pdf, ownerID: ownerID))
        try await verifyOwner(ownerID)
        try IChartPDFSetlistCloudValidation.validate(data, for: pdf)
        return data
    }

    func upload(_ pdf: IChartPDFSetlistCloudPDF, data: Data, ownerID: UUID) async throws {
        try IChartPDFSetlistCloudValidation.validate(data, for: pdf)
        try await verifyOwner(ownerID)
        do {
            try await client.storage.from(bucket).upload(path(for: pdf, ownerID: ownerID), data: data,
                options: FileOptions(contentType: "application/pdf", upsert: false))
        } catch {
            // A previous attempt may have stored these immutable bytes before
            // its manifest commit was interrupted. Only equal bytes can retry.
            let existing = try await download(pdf, ownerID: ownerID)
            guard existing == data else { throw IChartPDFSetlistCloudError.invalidBackup }
        }
        try await verifyOwner(ownerID)
    }

    func commit(_ document: IChartPDFSetlistCloudDocument, expectedVersion: Int64,
        ownerID: UUID) async throws -> IChartPDFSetlistCloudEnvelope {
        struct Parameters: Encodable {
            let expected_version: Int64
            let expected_owner_id: UUID
            let manifest: IChartJSONValue
        }
        try IChartPDFSetlistCloudValidation.validate(document)
        try await verifyOwner(ownerID)
        let payload = try IChartPDFSetlistCloudValidation.payload(document)
        do {
            let result: IChartPDFSetlistCloudEnvelope = try await client.rpc("commit_pdf_setlist_backup",
                params: Parameters(expected_version: expectedVersion, expected_owner_id: ownerID, manifest: payload)).execute().value
            try await verifyOwner(ownerID)
            guard result.manifest == document, result.version > expectedVersion else {
                throw IChartPDFSetlistCloudError.invalidBackup
            }
            return result
        } catch let error as PostgrestError where error.code == "40001" {
            throw IChartPDFSetlistCloudError.cloudChanged
        }
    }
}
