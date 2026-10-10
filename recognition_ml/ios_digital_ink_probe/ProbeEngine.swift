import Foundation
import CryptoKit
import MLKitDigitalInkRecognition
import MLKitCommon

private struct LocalPoint: Decodable { let x: Double; let y: Double; let timeOffset: Double? }
private struct LocalStroke: Decodable { let points: [LocalPoint]; let creationTimeOffset: Double? }
private struct LocalInput: Decodable { let id: String; let strokes: [LocalStroke] }

/// No expected labels, profile, app storage, or network input upload path.
@MainActor
enum ProbeEngine {
    nonisolated private static func error(_ reason: String) -> Error {
        NSError(domain: "LocalInkProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: reason])
    }

    static func run(folder: URL, progress: (String) -> Void) async throws {
        let inputURL = folder.appendingPathComponent("probe-input.json")
        let bytes = try Data(contentsOf: inputURL)
        guard bytes.count <= 8_000_000 else { throw error("Packet exceeds 8 MB") }
        let inputs = try JSONDecoder().decode([LocalInput].self, from: bytes)
        guard !inputs.isEmpty, inputs.count <= 128, Set(inputs.map(\.id)).count == inputs.count else {
            throw error("Input count or identities are invalid")
        }
        // Validate every input before downloading/loading a model.
        let prepared = try inputs.map { input -> (Ink, Double, Double) in
            guard !input.strokes.isEmpty, input.strokes.count <= 64,
                  input.strokes.allSatisfy({ !$0.points.isEmpty }),
                  input.strokes.reduce(0, { $0 + $1.points.count }) <= 32_768 else {
                throw error("Invalid stroke or point count")
            }
            let all = input.strokes.flatMap(\.points)
            guard all.allSatisfy({ $0.x.isFinite && $0.y.isFinite && abs($0.x) < 1e8 && abs($0.y) < 1e8 }),
                  let minX = all.map(\.x).min(), let maxX = all.map(\.x).max(),
                  let minY = all.map(\.y).min(), let maxY = all.map(\.y).max(),
                  maxX > minX, maxY > minY else { throw error("Invalid or degenerate writing area") }
            let origin = input.strokes.compactMap(\.creationTimeOffset).min() ?? 0
            let strokes = try input.strokes.map { stroke in
                Stroke(points: try stroke.points.map { point in
                    if let start = stroke.creationTimeOffset, let t = point.timeOffset {
                        let ms = (start - origin + t) * 1000
                        guard ms.isFinite, abs(ms) < 1e12 else { throw error("Invalid timestamp") }
                        return StrokePoint(x: Float(point.x - minX), y: Float(point.y - minY), t: Int(ms.rounded()))
                    }
                    return StrokePoint(x: Float(point.x - minX), y: Float(point.y - minY))
                })
            }
            return (Ink(strokes: strokes), maxX - minX, maxY - minY)
        }
        guard let identifier = DigitalInkRecognitionModelIdentifier(forLanguageTag: "en-US") else {
            throw error("English model is unavailable")
        }
        let model = DigitalInkRecognitionModel(modelIdentifier: identifier)
        let manager = ModelManager.modelManager()
        if !manager.isModelDownloaded(model) {
            progress("Downloading the English model. No handwriting is uploaded.")
            var downloadError: Error?
            let observer = NotificationCenter.default.addObserver(forName: .mlkitModelDownloadDidFail,
                object: nil, queue: .main) { notification in
                guard let remote = notification.userInfo?[ModelDownloadUserInfoKey.remoteModel.rawValue] as? RemoteModel,
                      remote == model else { return }
                downloadError = notification.userInfo?[ModelDownloadUserInfoKey.error.rawValue] as? Error
                    ?? error("Model download failed")
            }
            defer { NotificationCenter.default.removeObserver(observer) }
            manager.download(model, conditions: ModelDownloadConditions(allowsCellularAccess: false, allowsBackgroundDownloading: false))
            let deadline = ProcessInfo.processInfo.systemUptime + 55
            while !manager.isModelDownloaded(model), downloadError == nil,
                  ProcessInfo.processInfo.systemUptime < deadline {
                try await Task.sleep(nanoseconds: 500_000_000)
            }
            if let downloadError { throw downloadError }
        }
        guard manager.isModelDownloaded(model) else { throw error("Model download timed out; no comparison ran") }
        let recognizer = DigitalInkRecognizer.digitalInkRecognizer(options: DigitalInkRecognizerOptions(model: model))
        var rows: [[String: Any]] = []
        for (index, item) in zip(inputs, prepared).enumerated() {
            let (input, (ink, width, height)) = item
            progress("Comparing input \(index + 1) of \(inputs.count)…")
            for useArea in [false, true] {
                let started = ProcessInfo.processInfo.systemUptime
                let result: DigitalInkRecognitionResult = try await withCheckedThrowingContinuation { continuation in
                    let completion: DigitalInkRecognizerCallback = { result, failure in
                        if let failure { continuation.resume(throwing: failure) }
                        else if let result { continuation.resume(returning: result) }
                        else { continuation.resume(throwing: error("Missing recognition response")) }
                    }
                    if useArea {
                        recognizer.recognize(ink: ink, context: DigitalInkRecognitionContext(preContext: "",
                            writingArea: WritingArea(width: Float(width), height: Float(height))), completion: completion)
                    } else { recognizer.recognize(ink: ink, completion: completion) }
                }
                rows.append(["id": input.id, "context": useArea ? "bounds" : "none",
                    "milliseconds": (ProcessInfo.processInfo.systemUptime - started) * 1000,
                    "candidates": result.candidates.map { ["text": $0.text, "score": $0.score as Any? ?? NSNull()] }])
            }
        }
        guard try Data(contentsOf: inputURL) == bytes, rows.count == inputs.count * 2 else {
            throw error("Input changed or comparison is incomplete")
        }
        let report: [String: Any] = ["scope": "untrained alternative-engine replay; no accuracy claim",
            "complete": true, "sdk": "GoogleMLKit 8.0.0 / DigitalInkRecognition 7.0.0", "language": "en-US",
            "inputSHA256": SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
            "inputCount": inputs.count, "rows": rows]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: folder.appendingPathComponent("probe-report.json"), options: [.atomic, .completeFileProtectionUnlessOpen])
        progress("Comparison complete: \(inputs.count) inputs. Your iChart data is unchanged.")
    }
}
