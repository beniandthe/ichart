import CryptoKit
import Foundation

/// Identifies the exact chart payload acknowledged by cloud backup. Backup
/// bookkeeping is excluded so acknowledging a chart does not dirty it again.
enum ChartCloudContentIdentity {
    static func sha256(for chart: Chart) throws -> String {
        try sha256(for: IChartJSONValue.chartPayload(for: chart))
    }

    static func sha256(for payload: IChartJSONValue) throws -> String {
        guard case .object(var fields) = payload else {
            throw EncodingError.invalidValue(payload, .init(codingPath: [], debugDescription: "Chart cloud payload must be an object."))
        }
        fields.removeValue(forKey: "cloudBackupStatus")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(IChartJSONValue.object(fields))
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func matchesContent(_ lhs: Chart, _ rhs: Chart) -> Bool {
        var left = lhs
        var right = rhs
        left.cloudBackupStatus = .included
        right.cloudBackupStatus = .included
        return left == right
    }

    static func isValidSHA256(_ value: String?) -> Bool {
        guard let value, value.utf8.count == 64 else { return false }
        return value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}
