import Foundation

/// App-only adapter. The service model remains usable by SwiftPM tests and
/// never imports the telemetry service or exposes local checkpoint digests.
enum ChartExperienceContractTelemetry {
    static func makeDiagnostics(repository: ChartRepository?) -> ChartPersistenceContractDiagnostics? {
        guard let repository = repository as? FileChartRepository else { return nil }
        let consentStore = IChartTelemetryConsentStore.shared
        consentStore.registerDiagnosticFile(ChartPersistenceContractDiagnostics.checkpointURL(for: repository.url))
        return ChartPersistenceContractDiagnostics(
            fileURL: repository.url,
            identity: "consent-required",
            currentAuthorization: {
                consentStore.checkpointAuthorization()
            },
            publishCheckpoint: { data, url, authorization in
                try consentStore.publishDiagnosticCheckpoint(data, to: url, authorization: authorization)
            },
            isEnabled: { IChartTelemetry.isRecordingEnabled && consentStore.snapshot.isGranted },
            record: record
        )
    }

    static func properties(_ check: ChartPersistenceContractCheck) -> IChartTelemetryProperties {
        var properties: IChartTelemetryProperties = [
            "contract_id": .string(check.contractID),
            "contract_version": .int(1),
            "operation_id": .string(check.operationID.uuidString.lowercased()),
            "operation": .string(check.operation),
            "outcome": .string(check.outcome),
            "reason": .string(check.reason),
            "scope": .string(check.scope),
            "expected_count": .int(check.expectedCount),
            "actual_count": .int(check.actualCount),
            "expected_bytes": .int(check.expectedBytes),
            "actual_bytes": .int(check.actualBytes)
        ]
        if let contentMatches = check.contentMatches {
            properties["content_matches"] = .bool(contentMatches)
        }
        if let duration = check.durationMilliseconds, duration.isFinite, duration >= 0 {
            properties["duration_ms"] = .double(min(duration, 86_400_000))
        }
        return properties
    }

    static func record(_ check: ChartPersistenceContractCheck) {
        IChartTelemetry.record("feature.contract_checked", properties: properties(check), chartID: check.chartID)
    }
}
