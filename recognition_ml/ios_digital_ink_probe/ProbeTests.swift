import XCTest
import MLKitDigitalInkRecognition
import MLKitCommon
import CryptoKit

private struct ProbePoint: Decodable { let x: Double; let y: Double; let timeOffset: Double? }
private struct ProbeStroke: Decodable { let points: [ProbePoint]; let creationTimeOffset: Double? }
private struct ProbeInput: Decodable { let id: String; let strokes: [ProbeStroke] }

final class ProbeTests: XCTestCase {
    func testSDKCanConstructEnglishModel() throws {
        let identifier = try XCTUnwrap(DigitalInkRecognitionModelIdentifier(forLanguageTag: "en-US"))
        let model = DigitalInkRecognitionModel(modelIdentifier: identifier)
        XCTAssertNotNil(DigitalInkRecognizer.digitalInkRecognizer(options: DigitalInkRecognizerOptions(model: model)))
    }

    /// Private local inputs deliberately contain no expected text or training profile.
    @MainActor
    func testCapturedInkAgainstFixedEnglishModel() async throws {
        let folder = try XCTUnwrap(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
        let inputURL = folder.appendingPathComponent("probe-input.json")
        let outputURL = folder.appendingPathComponent("probe-report.json")
        let bytes = try Data(contentsOf: inputURL)
        defer { XCTAssertEqual(try? Data(contentsOf: inputURL), bytes) }
        XCTAssertLessThan(bytes.count, 8_000_000)
        let inputs = try JSONDecoder().decode([ProbeInput].self, from: bytes)
        XCTAssertFalse(inputs.isEmpty)
        XCTAssertLessThanOrEqual(inputs.count, 128)
        XCTAssertEqual(Set(inputs.map(\.id)).count, inputs.count)
        // Validate all inputs before invoking any recognizer.
        let inks = try inputs.map { try makeInk($0) }
        guard testRun?.failureCount == 0 else { return }
        let identifier = try XCTUnwrap(DigitalInkRecognitionModelIdentifier(forLanguageTag: "en-US"))
        let model = DigitalInkRecognitionModel(modelIdentifier: identifier)
        let manager = ModelManager.modelManager()
        if !manager.isModelDownloaded(model) {
            let ready = expectation(description: "English handwriting model downloaded")
            var downloadError: Error?
            let success = NotificationCenter.default.addObserver(forName: .mlkitModelDownloadDidSucceed,
                object: nil, queue: .main) { notification in
                guard let remote = notification.userInfo?[ModelDownloadUserInfoKey.remoteModel.rawValue] as? RemoteModel,
                      remote == model else { return }
                ready.fulfill()
            }
            let failure = NotificationCenter.default.addObserver(forName: .mlkitModelDownloadDidFail,
                object: nil, queue: .main) { notification in
                guard let remote = notification.userInfo?[ModelDownloadUserInfoKey.remoteModel.rawValue] as? RemoteModel,
                      remote == model else { return }
                downloadError = notification.userInfo?[ModelDownloadUserInfoKey.error.rawValue] as? Error
                ready.fulfill()
            }
            defer {
                NotificationCenter.default.removeObserver(success)
                NotificationCenter.default.removeObserver(failure)
            }
            manager.download(model, conditions: ModelDownloadConditions(allowsCellularAccess: false, allowsBackgroundDownloading: false))
            await fulfillment(of: [ready], timeout: 55)
            if let downloadError { throw downloadError }
        }
        guard manager.isModelDownloaded(model) else { XCTFail("No downloaded model; no comparison was run"); return }
        let recognizer = DigitalInkRecognizer.digitalInkRecognizer(options: DigitalInkRecognizerOptions(model: model))
        var rows: [[String: Any]] = []
        for (input, ink) in zip(inputs, inks) {
            let all = input.strokes.flatMap(\.points)
            let width = try XCTUnwrap(all.map(\.x).max()) - XCTUnwrap(all.map(\.x).min())
            let height = try XCTUnwrap(all.map(\.y).max()) - XCTUnwrap(all.map(\.y).min())
            // Primary: no context. Secondary: unpadded bounds-sized area.
            // Both are fixed before viewing output, with no preceding words.
            for useArea in [false, true] {
                let started = ProcessInfo.processInfo.systemUptime
                let result: DigitalInkRecognitionResult = try await withCheckedThrowingContinuation { continuation in
                    let completion: DigitalInkRecognizerCallback = { result, error in
                        if let error { continuation.resume(throwing: error) }
                        else if let result { continuation.resume(returning: result) }
                        else { continuation.resume(throwing: NSError(domain: "ProbeMissingResult", code: 1)) }
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
        XCTAssertEqual(rows.count, inputs.count * 2)
        guard testRun?.failureCount == 0 else { return }
        let report: [String: Any] = ["scope": "untrained alternative-engine replay; no accuracy claim",
            "sdk": "GoogleMLKit 8.0.0 / DigitalInkRecognition 7.0.0", "language": "en-US",
            "inputSHA256": SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
            "inputCount": inputs.count, "rows": rows]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: outputURL, options: [.atomic, .completeFileProtectionUnlessOpen])
        print("DIGITAL_INK_PROBE_COMPLETE inputs=\(inputs.count) results=\(rows.count)")
    }

    private func makeInk(_ input: ProbeInput) throws -> Ink {
        guard !input.strokes.isEmpty, input.strokes.count <= 64,
              input.strokes.reduce(0, { $0 + $1.points.count }) <= 32_768,
              input.strokes.allSatisfy({ !$0.points.isEmpty }) else {
            throw NSError(domain: "InvalidInkSize", code: 1)
        }
        let points = input.strokes.flatMap(\.points)
        let minX = try XCTUnwrap(points.map(\.x).min())
        let minY = try XCTUnwrap(points.map(\.y).min())
        let origin = input.strokes.compactMap(\.creationTimeOffset).min() ?? 0
        return Ink(strokes: try input.strokes.map { stroke in
            return Stroke(points: try stroke.points.map { p in
                guard p.x.isFinite, p.y.isFinite, abs(p.x) < 1e8, abs(p.y) < 1e8 else {
                    throw NSError(domain: "InvalidInkCoordinate", code: 1)
                }
                if let start = stroke.creationTimeOffset, let t = p.timeOffset {
                    let milliseconds = (start - origin + t) * 1000
                    guard milliseconds.isFinite, abs(milliseconds) < 1e12 else {
                        throw NSError(domain: "InvalidInkTimestamp", code: 1)
                    }
                    return StrokePoint(x: Float(p.x - minX), y: Float(p.y - minY), t: Int(milliseconds.rounded()))
                }
                return StrokePoint(x: Float(p.x - minX), y: Float(p.y - minY))
            })
        })
    }

    func testAdapterPreservesStrokeOrderRelativeGeometryAndElapsedTime() throws {
        let input = ProbeInput(id: "synthetic", strokes: [
            ProbeStroke(points: [ProbePoint(x: 30, y: 15, timeOffset: 0),
                                 ProbePoint(x: 50, y: 45, timeOffset: 0.125)], creationTimeOffset: 4),
            ProbeStroke(points: [ProbePoint(x: 80, y: 55, timeOffset: 0)], creationTimeOffset: 5.5)
        ])
        let ink = try makeInk(input)
        XCTAssertEqual(ink.strokes.count, 2)
        XCTAssertEqual(ink.strokes.map { $0.points.count }, [2, 1])
        XCTAssertEqual(ink.strokes[0].points.map(\.x), [0, 20])
        XCTAssertEqual(ink.strokes[0].points.map(\.y), [0, 30])
        XCTAssertEqual(ink.strokes[0].points.map { $0.t?.intValue }, [0, 125])
        XCTAssertEqual(ink.strokes[1].points[0].t?.intValue, 1500)
        XCTAssertEqual(ink.strokes[1].points[0].x, 50)
    }

    func testAdapterRejectsInvalidInkAndDoesNotInventMissingTime() throws {
        XCTAssertThrowsError(try makeInk(ProbeInput(id: "empty", strokes: [])))
        XCTAssertThrowsError(try makeInk(ProbeInput(id: "nan", strokes: [
            ProbeStroke(points: [ProbePoint(x: .nan, y: 2, timeOffset: 0)], creationTimeOffset: 0)
        ])))
        let noClock = try makeInk(ProbeInput(id: "untimed", strokes: [
            ProbeStroke(points: [ProbePoint(x: 3, y: 2, timeOffset: 0)], creationTimeOffset: nil)
        ]))
        XCTAssertNil(noClock.strokes[0].points[0].t)
    }
}
