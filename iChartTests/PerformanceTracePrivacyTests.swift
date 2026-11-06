import Foundation
import XCTest
@testable import iChart

final class PerformanceTracePrivacyTests: XCTestCase {
    private let legacy = #"{"timestamp":"2026-10-07T18:00:00Z","processUptimeSeconds":98765,"name":"app.bootstrap.end","durationMilliseconds":42.5,"metadata":{"flow":"bootstrap","systemUptime":"98765","chartTitle":"Private synthetic title","reason":"Private synthetic error"},"appVersion":"1.2.1","buildNumber":"74","unexpectedPrivateField":"never export this"}"#

    func testLegacyExportKeepsBasicTimingAndDropsAllArbitraryContext() throws {
        let output = try IChartPerformanceTraceReportSanitizer.sanitize(Data((legacy + "\n").utf8))
        let object = try XCTUnwrap(objects(in: output).first)
        XCTAssertEqual(Set(object.keys), ["timestamp", "name", "durationMilliseconds", "metadata", "appVersion", "buildNumber"])
        XCTAssertEqual(object["name"] as? String, "app.bootstrap.end")
        XCTAssertEqual(object["durationMilliseconds"] as? Double, 42.5)
        XCTAssertEqual(object["metadata"] as? [String: String], [:])
        for forbidden in ["98765", "Private synthetic", "never export this", "flow", "processUptimeSeconds"] {
            XCTAssertFalse(String(decoding: output, as: UTF8.self).contains(forbidden))
        }
    }

    func testOnlyDefinedBasicOperationNamesAreEligible() throws {
        let names = ["app.init.end", "app.bootstrap.end", "library.load", "library.save", "ink.persistence.writeback", "chord.recognition.capture", "chord.recognition.prepare", "chord.preview.replace", "rhythm.recognition.capture", "rhythm.recognition.analyze", "pdf.export.end"]
        let unknown = ["synthetic.failure", "canvas.drawing.changed", "ink.authoring_integrity", "app.bootstrap.begin", "performance.report.created", "library.save.private"]
        let source = try encodedLines((names + unknown).map { event(name: $0) })
        let output = try IChartPerformanceTraceReportSanitizer.sanitize(source)
        XCTAssertEqual(try objects(in: output).compactMap { $0["name"] as? String }, names)
    }

    func testFixedResultAndErrorMetadataRejectArbitraryContext() throws {
        let categories: [IChartPerformanceTraceErrorCategory] = [.storageRead, .storageWrite, .serialization, .recognition, .export, .unknown]
        var input = categories.map { event(metadata: ["result": IChartPerformanceTraceResult.failed.rawValue, "error_category": $0.rawValue, "error_description": "Private synthetic error", "identifier": "synthetic-private-id"]) }
        input += [
            event(metadata: ["result": "succeeded", "error_category": "recognition"]),
            event(metadata: ["error_category": "storage_read"]),
            event(metadata: ["result": "Private result", "error_category": "storage_read"]),
            event(metadata: ["result": "failed", "error_category": "Private error"])
        ]
        let output = try IChartPerformanceTraceReportSanitizer.sanitize(encodedLines(input))
        let expected = categories.map { ["result": "failed", "error_category": $0.rawValue] } + [["result": "succeeded"], [:], [:], ["result": "failed"]]
        XCTAssertEqual(try objects(in: output).compactMap { $0["metadata"] as? [String: String] }, expected)
        XCTAssertFalse(String(decoding: output, as: UTF8.self).contains("Private"))
        XCTAssertFalse(String(decoding: output, as: UTF8.self).contains("synthetic-private"))
    }

    func testDurationIsRequiredFiniteNonnegativeAndBounded() throws {
        var source = try encodedLines([event(duration: 0), event(duration: 86_400_000), event(duration: nil)])
        for duration in ["null", "-0.1", "86400000.1", "1e309", #""NaN""#, "true"] {
            source.append(Data((legacy.replacingOccurrences(of: "42.5", with: duration) + "\n").utf8))
        }
        let output = try IChartPerformanceTraceReportSanitizer.sanitize(source)
        XCTAssertEqual(try objects(in: output).compactMap { $0["durationMilliseconds"] as? Double }, [0, 86_400_000])
    }

    func testVersionsKeepOnlyBoundedNumericDottedComponents() throws {
        let inputs = [
            event(appVersion: "1.2.4", buildNumber: "143.2"),
            event(appVersion: "Private version", buildNumber: "Private id"),
            event(appVersion: ".1", buildNumber: "1."),
            event(appVersion: "1..2", buildNumber: "1..2"),
            event(appVersion: String(repeating: "1", count: 33), buildNumber: String(repeating: "2", count: 13)),
            event(appVersion: "１.２", buildNumber: "-143"), event(appVersion: "", buildNumber: "")
        ]
        let output = try objects(in: IChartPerformanceTraceReportSanitizer.sanitize(encodedLines(inputs)))
        XCTAssertEqual(output.first?["appVersion"] as? String, "1.2.4")
        XCTAssertEqual(output.first?["buildNumber"] as? String, "143.2")
        for object in output.dropFirst() {
            XCTAssertEqual(object["appVersion"] as? String, "unknown")
            XCTAssertEqual(object["buildNumber"] as? String, "unknown")
        }
    }

    func testMalformedPartialAndOversizedLinesNeverForwardRawText() throws {
        let oversized = legacy.replacingOccurrences(of: "never export this", with: String(repeating: "x", count: 17 * 1024))
        let source = Data(("Private malformed text\n" + oversized + "\n" + legacy + "\n{partial\n").utf8)
        let output = try IChartPerformanceTraceReportSanitizer.sanitize(source)
        XCTAssertEqual(try objects(in: output).count, 1)
        XCTAssertFalse(String(decoding: output, as: UTF8.self).contains("Private"))
        XCTAssertTrue(try IChartPerformanceTraceReportSanitizer.sanitize(Data("bad".utf8)).isEmpty)
    }

    func testSourceAndOutputBoundsRetainOnlyWholeEligibleEvents() throws {
        let first = try encodedLines([event(name: "library.load")])
        let second = try encodedLines([event(name: "library.save")])
        let output = try IChartPerformanceTraceReportSanitizer.sanitize(first + second, maxSourceSizeBytes: first.count)
        XCTAssertEqual(try objects(in: output).compactMap { $0["name"] as? String }, ["library.load"])
        XCTAssertTrue(try IChartPerformanceTraceReportSanitizer.sanitize(first, maxSourceSizeBytes: first.count / 2).isEmpty)
        let oneLine = try IChartPerformanceTraceReportSanitizer.sanitize(first)
        XCTAssertEqual(try IChartPerformanceTraceReportSanitizer.sanitize(first + second, maxOutputSizeBytes: oneLine.count), oneLine)
        XCTAssertTrue(try IChartPerformanceTraceReportSanitizer.sanitize(first, maxOutputSizeBytes: oneLine.count - 1).isEmpty)
        for invalid in [0, -1] {
            XCTAssertTrue(try IChartPerformanceTraceReportSanitizer.sanitize(first, maxSourceSizeBytes: invalid).isEmpty)
            XCTAssertTrue(try IChartPerformanceTraceReportSanitizer.sanitize(first, maxOutputSizeBytes: invalid).isEmpty)
        }
    }

    func testCallerCannotRaiseHardSourceAndOutputLimits() throws {
        let line = try encodedLines([event()])
        var source = Data()
        while source.count <= 2 * 1024 * 1024 { source.append(line) }
        let defaultOutput = try IChartPerformanceTraceReportSanitizer.sanitize(source)
        let raisedOutput = try IChartPerformanceTraceReportSanitizer.sanitize(source, maxSourceSizeBytes: Int.max, maxOutputSizeBytes: Int.max)
        XCTAssertEqual(raisedOutput, defaultOutput)
        XCTAssertLessThanOrEqual(raisedOutput.count, 768 * 1024)
        XCTAssertFalse(try objects(in: raisedOutput).isEmpty)
    }

    func testUnknownStaticEventsNeverEvaluateLegacyMetadataOnAnyPlatform() {
        let probe = TraceMetadataProbe()
        IChartPerformanceTrace.record("canvas.synthetic.private", durationMilliseconds: 12, metadata: probe.metadata())
        let span = IChartPerformanceTrace.start("canvas.synthetic.private", metadata: probe.metadata())
        IChartPerformanceTrace.end(span, metadata: probe.metadata(), result: .failed, errorCategory: .unknown)
        XCTAssertEqual(probe.evaluationCount, 0)
    }

    #if !canImport(UIKit)
    func testPortableOffPathNeverEvaluatesEligibleLegacyMetadata() {
        let probe = TraceMetadataProbe()
        IChartPerformanceTrace.record("library.save", durationMilliseconds: 12, metadata: probe.metadata(), result: .succeeded)
        let span = IChartPerformanceTrace.start("app.bootstrap", metadata: probe.metadata())
        IChartPerformanceTrace.end(span, metadata: probe.metadata(), result: .failed, errorCategory: .storageRead)
        XCTAssertEqual(probe.evaluationCount, 0)
    }
    #endif

    func testInitializationNeverWaitsForUtilityProbeAndAvailabilityUsesOnlyMemory() async {
        let started = expectation(description: "readonly utility existence probe blocked")
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let fileManager = TraceFileManagerSpy(existsCheck: {
            started.fulfill()
            guard release.wait(timeout: .now() + 5) == .success else {
                XCTFail("Synthetic existence probe was not released")
                return false
            }
            return true
        })
        let recorder = IChartPerformanceTraceRecorder(url: unusedURL(), fileManager: fileManager, isRecordingEnabled: { false })
        await fulfillment(of: [started], timeout: 2)
        XCTAssertFalse(recorder.hasLogFile)
        XCTAssertEqual(recorder.pendingEventCount, 0)
        XCTAssertEqual(recorder.scheduledDrainCount, 0)
        XCTAssertFalse(recorder.hasLogFile)
        XCTAssertEqual(fileManager.operationCount, 1)
        XCTAssertEqual(fileManager.mutationCount, 0)
        release.signal()
        recorder.flush()
        XCTAssertTrue(recorder.hasLogFile, "Existing reports remain available with recording off")
        XCTAssertTrue(recorder.hasLogFile)
        XCTAssertEqual(fileManager.operationCount, 1, "Availability must not repeat filesystem probes")
        XCTAssertEqual(fileManager.mutationCount, 0)
    }

    func testIneligibleRecorderEventsDropBeforeConsentAndBufferAdmission() {
        let consent = TraceConsentProbe(enabled: true)
        let writes = TraceWriteProbe()
        let recorder = IChartPerformanceTraceRecorder(url: unusedURL(), isRecordingEnabled: { consent.check() }, writeBatch: { data, _, _ in
            writes.begin(data)
            writes.end()
            return true
        })
        recorder.append(event(name: "canvas.private.event"))
        recorder.append(event(duration: nil))
        for duration in [Double.nan, .infinity, -.infinity, -1, 86_400_000.1] { recorder.append(event(duration: duration)) }
        XCTAssertEqual(consent.checkCount, 0)
        XCTAssertEqual(recorder.pendingEventCount, 0)
        XCTAssertEqual(recorder.scheduledDrainCount, 0)
        XCTAssertFalse(recorder.hasLogFile)
        XCTAssertEqual(writes.snapshot.batches.count, 0)
    }

    func testDisabledRecorderNeverSchedulesStorageOrCreatesReport() {
        let fileManager = TraceFileManagerSpy()
        let writes = TraceWriteProbe()
        let recorder = IChartPerformanceTraceRecorder(url: unusedURL(), fileManager: fileManager, isRecordingEnabled: { false }, writeBatch: { data, _, _ in
            writes.begin(data)
            writes.end()
            return true
        })
        recorder.append(event())
        recorder.flush()
        XCTAssertFalse(recorder.hasLogFile)
        XCTAssertEqual(recorder.pendingEventCount, 0)
        XCTAssertEqual(recorder.scheduledDrainCount, 0)
        XCTAssertEqual(writes.snapshot.batches.count, 0)
        XCTAssertEqual(fileManager.operationCount, 1)
        XCTAssertEqual(fileManager.mutationCount, 0)
    }

    func testFreshRecorderEventsAreSanitizedBeforeWriterReceivesThem() throws {
        let writes = TraceWriteProbe()
        let recorder = IChartPerformanceTraceRecorder(url: unusedURL(), writeBatch: { data, _, _ in
            writes.begin(data)
            writes.end()
            return true
        })
        recorder.append(event(metadata: ["result": "failed", "error_category": "storage_write", "chartTitle": "Private synthetic title"], appVersion: "Private version"))
        recorder.flush()
        let output = writes.snapshot.batches.reduce(into: Data()) { $0.append($1) }
        let object = try XCTUnwrap(objects(in: output).first)
        XCTAssertEqual(object["metadata"] as? [String: String], ["result": "failed", "error_category": "storage_write"])
        XCTAssertEqual(object["appVersion"] as? String, "unknown")
        XCTAssertNil(object["processUptimeSeconds"])
        XCTAssertFalse(String(decoding: output, as: UTF8.self).contains("Private"))
        XCTAssertTrue(recorder.hasLogFile)
    }

    func testBlockedStorageCannotBlockAdmissionOrAvailabilityAndBurstStaysBounded() async throws {
        let started = expectation(description: "utility writer blocked")
        let producerFinished = expectation(description: "producer finished before writer release")
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let writes = TraceWriteProbe()
        let recorder = IChartPerformanceTraceRecorder(url: unusedURL(), writeBatch: { data, _, _ in
            let invocation = writes.begin(data)
            defer { writes.end() }
            if invocation == 1 {
                started.fulfill()
                guard release.wait(timeout: .now() + 5) == .success else {
                    XCTFail("Synthetic writer was not released")
                    return false
                }
            }
            return true
        })
        recorder.append(event(duration: 1))
        await fulfillment(of: [started], timeout: 2)
        let burst = (2...100).map { event(duration: Double($0)) }
        DispatchQueue.global(qos: .userInitiated).async {
            for event in burst { recorder.append(event) }
            XCTAssertTrue(recorder.hasLogFile)
            XCTAssertEqual(recorder.pendingEventCount, 64)
            XCTAssertEqual(recorder.scheduledDrainCount, 1)
            producerFinished.fulfill()
        }
        await fulfillment(of: [producerFinished], timeout: 2)
        XCTAssertEqual(writes.snapshot.batches.count, 1)
        release.signal()
        recorder.flush()
        let snapshot = writes.snapshot
        let output = snapshot.batches.reduce(into: Data()) { $0.append($1) }
        XCTAssertEqual(try objects(in: output).compactMap { $0["durationMilliseconds"] as? Double }, (1...65).map(Double.init))
        XCTAssertEqual(snapshot.maximumConcurrentWrites, 1)
        XCTAssertEqual(recorder.pendingEventCount, 0)
        XCTAssertEqual(recorder.scheduledDrainCount, 1)
    }

    func testQueuedEventsDropWhenRecordingDisabledBeforeTheirDrain() async {
        let started = expectation(description: "first write blocked")
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let consent = TraceConsentProbe(enabled: true)
        let writes = TraceWriteProbe()
        let recorder = IChartPerformanceTraceRecorder(url: unusedURL(), isRecordingEnabled: { consent.check() }, writeBatch: { data, _, _ in
            writes.begin(data)
            defer { writes.end() }
            started.fulfill()
            return release.wait(timeout: .now() + 5) == .success
        })
        recorder.append(event(duration: 1))
        await fulfillment(of: [started], timeout: 2)
        recorder.append(event(duration: 2))
        XCTAssertEqual(recorder.pendingEventCount, 1)
        consent.setEnabled(false)
        release.signal()
        recorder.flush()
        XCTAssertEqual(writes.snapshot.batches.count, 1)
        XCTAssertEqual(recorder.pendingEventCount, 0)
    }

    func testBufferedAuthorizationCannotReviveAfterWithdrawalAndNewGrant() async throws {
        let started = expectation(description: "authorized first write blocked")
        let release = DispatchSemaphore(value: 0)
        defer { release.signal() }
        let epochs = TraceAuthorizationEpochProbe()
        let writes = TraceWriteProbe()
        let recorder = IChartPerformanceTraceRecorder(url: unusedURL(), authorizationProvider: { epochs.authorization() }, writeBatch: { data, _, _ in
            let invocation = writes.begin(data)
            defer { writes.end() }
            if invocation == 1 {
                started.fulfill()
                guard release.wait(timeout: .now() + 5) == .success else { return false }
            }
            return true
        })
        recorder.append(event(duration: 1))
        await fulfillment(of: [started], timeout: 2)
        recorder.append(event(duration: 2))
        XCTAssertEqual(recorder.pendingEventCount, 1)
        epochs.setEpoch(nil)
        epochs.setEpoch(2)
        recorder.append(event(duration: 3))
        release.signal()
        recorder.flush()

        let output = writes.snapshot.batches.reduce(into: Data()) { $0.append($1) }
        XCTAssertEqual(try objects(in: output).compactMap { $0["durationMilliseconds"] as? Double }, [1, 3], "Grant B cannot authorize buffered grant-A work")
        XCTAssertEqual(recorder.pendingEventCount, 0)
    }

    func testExplicitlyCapturedAuthorizationIsNotReplacedByCurrentGrant() throws {
        let epochs = TraceAuthorizationEpochProbe()
        let oldAuthorization = try XCTUnwrap(epochs.authorization())
        epochs.setEpoch(nil)
        epochs.setEpoch(2)
        let writes = TraceWriteProbe()
        let recorder = IChartPerformanceTraceRecorder(url: unusedURL(), authorizationProvider: { epochs.authorization() }, writeBatch: { data, _, _ in
            writes.begin(data)
            writes.end()
            return true
        })
        recorder.append(event(duration: 1), authorization: oldAuthorization)
        recorder.append(event(duration: 2))
        recorder.flush()

        let output = writes.snapshot.batches.reduce(into: Data()) { $0.append($1) }
        XCTAssertEqual(try objects(in: output).compactMap { $0["durationMilliseconds"] as? Double }, [2])
    }

    func testDiskWriteFailureDropsBatchWithoutRetryOrFakeAvailability() {
        let writes = TraceWriteProbe()
        let recorder = IChartPerformanceTraceRecorder(url: unusedURL(), writeBatch: { data, _, _ in
            writes.begin(data)
            writes.end()
            throw TraceSyntheticError.storageFailure
        })
        recorder.append(event())
        recorder.flush()
        recorder.flush()
        XCTAssertEqual(writes.snapshot.batches.count, 1)
        XCTAssertEqual(recorder.pendingEventCount, 0)
        XCTAssertFalse(recorder.hasLogFile)
        XCTAssertEqual(recorder.scheduledDrainCount, 1)
    }

    func testRejectedWriteBatchDoesNotPretendReportWasPersisted() {
        let recorder = IChartPerformanceTraceRecorder(url: unusedURL(), writeBatch: { _, _, _ in false })
        recorder.append(event())
        recorder.flush()
        XCTAssertFalse(recorder.hasLogFile)
        XCTAssertEqual(recorder.pendingEventCount, 0)
    }

    func testFullLegacyFileIsPreservedWithoutAutomaticRotationOrDeletion() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceURL = directory.appendingPathComponent("performance-trace.jsonl")
        let original = Data((legacy + "\n").utf8)
        try original.write(to: sourceURL)
        let recorder = IChartPerformanceTraceRecorder(url: sourceURL, maxTraceSizeBytes: UInt64(original.count))
        recorder.append(event())
        recorder.flush()
        XCTAssertEqual(try Data(contentsOf: sourceURL), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["performance-trace.jsonl"])
    }

    func testBatchLargerThanFileBudgetDoesNotCreateFileOrDirectory() {
        let directory = unusedURL()
        let recorder = IChartPerformanceTraceRecorder(url: directory.appendingPathComponent("performance-trace.jsonl"), maxTraceSizeBytes: 1)
        recorder.append(event())
        recorder.flush()
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertFalse(recorder.hasLogFile)
    }

    func testExplicitExportCreatesSanitizedCopyAndLeavesLegacySourceIntact() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceURL = directory.appendingPathComponent("performance-trace.jsonl")
        let original = Data((legacy + "\n").utf8) + (try encodedLines([event(name: "canvas.private.event")]))
        try original.write(to: sourceURL)
        let recorder = IChartPerformanceTraceRecorder(url: sourceURL, isRecordingEnabled: { false })
        recorder.flush()
        XCTAssertTrue(recorder.hasLogFile)
        let exportURL = try recorder.exportReport()
        let exported = try Data(contentsOf: exportURL)
        XCTAssertNotEqual(exportURL, sourceURL)
        XCTAssertEqual(try Data(contentsOf: sourceURL), original)
        XCTAssertEqual(try objects(in: exported).count, 1)
        XCTAssertEqual(try objects(in: exported).first?["metadata"] as? [String: String], [:])
        XCTAssertFalse(String(decoding: exported, as: UTF8.self).contains("Private"))
        XCTAssertFalse(String(decoding: exported, as: UTF8.self).contains("canvas"))
        XCTAssertTrue(recorder.hasLogFile)
    }

    func testExplicitExportRejectsEmptyUnknownOnlyAndMalformedSources() throws {
        for original in [Data(), try encodedLines([event(name: "canvas.private.event")]), Data("Private malformed text\n".utf8)] {
            let directory = try temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let sourceURL = directory.appendingPathComponent("performance-trace.jsonl")
            try original.write(to: sourceURL)
            let recorder = IChartPerformanceTraceRecorder(url: sourceURL)
            XCTAssertThrowsError(try recorder.exportReport())
            XCTAssertEqual(try Data(contentsOf: sourceURL), original)
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("performance-report.jsonl").path))
        }
    }

    func testExplicitResetRemovesTraceAndExportWhilePreservingNeighboringLibraryAndInk() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceURL = directory.appendingPathComponent("performance-trace.jsonl")
        let libraryURL = directory.appendingPathComponent("library.json")
        let inkURL = directory.appendingPathComponent("source-ink.archive")
        let libraryBytes = Data("synthetic library sentinel".utf8)
        let inkBytes = Data("synthetic ink sentinel".utf8)
        let original = Data((legacy + "\n").utf8)
        try original.write(to: sourceURL)
        try libraryBytes.write(to: libraryURL)
        try inkBytes.write(to: inkURL)
        let recorder = IChartPerformanceTraceRecorder(url: sourceURL)
        recorder.flush()
        XCTAssertTrue(recorder.hasLogFile)
        let exportedURL = try recorder.exportReport()
        XCTAssertEqual(exportedURL, directory.appendingPathComponent("performance-report.jsonl"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: exportedURL.path))
        XCTAssertEqual(try Data(contentsOf: sourceURL), original)

        try recorder.reset()

        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: exportedURL.path))
        XCTAssertEqual(try Data(contentsOf: libraryURL), libraryBytes)
        XCTAssertEqual(try Data(contentsOf: inkURL), inkBytes)
        XCTAssertFalse(recorder.hasLogFile)
    }

    private func event(name: String = "library.save", duration: Double? = 17, metadata: [String: String] = [:], appVersion: String = "1.2.4", buildNumber: String = "143") -> IChartPerformanceTraceEvent {
        IChartPerformanceTraceEvent(timestamp: Date(timeIntervalSince1970: 1_791_396_000), name: name, durationMilliseconds: duration, metadata: metadata, appVersion: appVersion, buildNumber: buildNumber)
    }

    private func encodedLines(_ events: [IChartPerformanceTraceEvent]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        var result = Data()
        for event in events {
            result.append(try encoder.encode(event))
            result.append(0x0A)
        }
        return result
    }

    private func objects(in data: Data) throws -> [[String: Any]] {
        try data.split(separator: 0x0A).map { try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0)) as? [String: Any]) }
    }

    private func unusedURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("basic-trace-test-" + UUID().uuidString)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = unusedURL()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private enum TraceSyntheticError: Error { case storageFailure }

private final class TraceMetadataProbe {
    private(set) var evaluationCount = 0
    func metadata() -> [String: String] {
        evaluationCount += 1
        return ["chartTitle": "Private synthetic title"]
    }
}

private final class TraceConsentProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var enabled: Bool
    private var count = 0
    init(enabled: Bool) { self.enabled = enabled }
    func check() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return enabled
    }
    func setEnabled(_ value: Bool) {
        lock.lock()
        enabled = value
        lock.unlock()
    }
    var checkCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

private final class TraceAuthorizationEpochProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var epoch: Int? = 1

    func authorization() -> IChartPerformanceTraceAuthorization? {
        lock.lock()
        let capturedEpoch = epoch
        lock.unlock()
        guard let capturedEpoch else { return nil }
        return IChartPerformanceTraceAuthorization(isCurrent: { self.matches(capturedEpoch) })
    }

    func setEpoch(_ value: Int?) {
        lock.lock()
        epoch = value
        lock.unlock()
    }

    private func matches(_ expected: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return epoch == expected
    }
}

private final class TraceWriteProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var batches: [Data] = []
    private var active = 0
    private var maximumActive = 0
    @discardableResult func begin(_ data: Data) -> Int {
        lock.lock()
        defer { lock.unlock() }
        batches.append(data)
        active += 1
        maximumActive = max(maximumActive, active)
        return batches.count
    }
    func end() {
        lock.lock()
        active -= 1
        lock.unlock()
    }
    var snapshot: (batches: [Data], maximumConcurrentWrites: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (batches, maximumActive)
    }
}

private final class TraceFileManagerSpy: FileManager, @unchecked Sendable {
    private let lock = NSLock()
    private let existsCheck: @Sendable () -> Bool
    private var count = 0
    private var mutations = 0
    init(existsCheck: @escaping @Sendable () -> Bool = { false }) {
        self.existsCheck = existsCheck
        super.init()
    }
    private func recordOperation(isMutation: Bool = false) {
        lock.lock()
        count += 1
        if isMutation { mutations += 1 }
        lock.unlock()
    }
    var operationCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
    var mutationCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return mutations
    }
    override func fileExists(atPath path: String) -> Bool { recordOperation(); return existsCheck() }
    override func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] { recordOperation(); return [.size: UInt64(0)] }
    override func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool, attributes: [FileAttributeKey: Any]? = nil) throws { recordOperation(isMutation: true) }
    override func removeItem(at URL: URL) throws { recordOperation(isMutation: true) }
}
