#if canImport(UIKit)
import Foundation

enum ChordInkCorrectionTelemetry {
    static func sourceProperties(
        hasSourceInk: Bool,
        sourceRecognitionPipelineVersion: String?
    ) -> IChartTelemetryProperties {
        var properties: IChartTelemetryProperties = [
            "source": .string(hasSourceInk ? "recognized_ink" : "manual_entry")
        ]
        // Attribute a correction to the pipeline that made the original read.
        // Legacy ink and manual entries have no known recognition version;
        // do not silently assign them to the currently installed pipeline.
        // Imported chart metadata is untrusted. Only our bounded version
        // format may cross this diagnostic boundary, never arbitrary content.
        if hasSourceInk, let version = sourceRecognitionPipelineVersion,
           version.utf8.count <= 64,
           version.range(
               of: #"\Amaximum-trust-v[1-9][0-9]{0,3}-[0-9]{4}-[0-9]{2}-[0-9]{2}\z"#,
               options: .regularExpression
           ) != nil {
            properties["recognition_pipeline_version"] = .string(version)
        }
        return properties
    }
}
#endif
