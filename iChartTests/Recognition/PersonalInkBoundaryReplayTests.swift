import XCTest
import CryptoKit
@testable import iChart

/// Local, label-blind feasibility check. The combined ink is only a boundary
/// hypothesis: a suggestion here is never permission to change chart ownership.
/// No captured handwriting or profile is bundled in the repository.
final class PersonalInkBoundaryReplayTests: XCTestCase {
    /// Enumerate stroke-contiguous glyph boundaries without intended labels.
    /// This probes whether a greedy glyph grouping hides existing personal
    /// evidence; it does not authorize new production segmentation or training.
    func testProvidedTraceChecksGlyphPartitionsWithoutLabels() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let tracePath = environment["ICHART_PERSONAL_BOUNDARY_TRACE_FILE"],
              let profilePath = environment["ICHART_PERSONAL_BOUNDARY_PROFILE_FILE"] else {
            throw XCTSkip("Provide an authorized local trace and frozen profile for boundary replay")
        }
        let traceURL = URL(fileURLWithPath: tracePath)
        let profileURL = URL(fileURLWithPath: profilePath)
        let originalTrace = try Data(contentsOf: traceURL)
        let originalProfile = try Data(contentsOf: profileURL)
        let profile = try JSONDecoder().decode(PersonalInkProfile.self, from: originalProfile)
        let snapshot = PersonalInkSnapshot(profile: profile)
        let recorder = ChordDraftPreviewDeviceDiagnosticRecorder(url: traceURL)
        let session = try XCTUnwrap(ChordInkRecognitionTrace(events: recorder.loadEvents()).latestNonemptySession)
        let finalPass = try XCTUnwrap(session.passes.last(where: { !$0.payloads.isEmpty }))
        let glyphExamples = profile.examples.filter { $0.kind == .glyph }.compactMap { example in
            PersonalInkShape(strokes: example.strokes).map { (label: example.label, shape: $0) }
        }
        XCTAssertFalse(glyphExamples.isEmpty)

        // Mirror the current glyph matcher for this diagnostic only. Every
        // group needs visual support before grammar is consulted; grammar may
        // reject a path but cannot rescue an unsupported or ambiguous group.
        let maximumDistance = 0.075
        let minimumMargin = 0.018
        func supportedGlyph(_ strokes: [InkStroke]) -> String? {
            guard let shape = PersonalInkShape(strokes: strokes) else { return nil }
            var byLabel: [String: Double] = [:]
            for example in glyphExamples {
                byLabel[example.label] = min(byLabel[example.label] ?? .infinity, shape.distance(to: example.shape))
            }
            let ranked = byLabel.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value < $1.value }
            guard let best = ranked.first, best.value <= maximumDistance else { return nil }
            if let runnerUp = ranked.dropFirst().first, runnerUp.value - best.value < minimumMargin { return nil }
            return best.key
        }

        var rows: [[String: Any]] = []
        for payload in finalPass.payloads {
            guard let ink = payload.inkStrokes, !ink.isEmpty else { continue }
            guard ink.count <= 10 else {
                rows.append(["targetIndex": payload.targetIndex, "strokeCount": ink.count,
                             "skipped": "More than ten strokes; bounded diagnostic does not enumerate"])
                continue
            }
            let ordered = ink.enumerated().sorted {
                let left = $0.element.creationTimeOffset ?? Double($0.offset)
                let right = $1.element.creationTimeOffset ?? Double($1.offset)
                return left == right ? $0.offset < $1.offset : left < right
            }.map(\.element)
            var supportedPaths: [[String: Any]] = []
            for mask in 0..<(1 << (ordered.count - 1)) {
                var groups: [[InkStroke]] = [[]]
                for (index, stroke) in ordered.enumerated() {
                    groups[groups.count - 1].append(stroke)
                    if index < ordered.count - 1, mask & (1 << index) != 0 { groups.append([]) }
                }
                XCTAssertEqual(groups.flatMap { $0 }, ordered, "Every hypothesis must use every point exactly once")
                let labels = groups.compactMap(supportedGlyph)
                guard labels.count == groups.count else { continue }
                supportedPaths.append(["glyphs": labels, "strokeCounts": groups.map(\.count),
                    "canonicalChord": ChordRecognitionCompendium.match(labels.joined())?.displayText ?? "invalid-grammar"])
            }
            let originalClusters = StrokeClusterer().cluster(ink.map { InkStroke(points: $0.points) })
            rows.append(["targetIndex": payload.targetIndex, "native": payload.acceptedText ?? "no-read",
                "currentPersonal": snapshot.suggestion(strokes: ink)?.text ?? "no-suggestion",
                "strokeCount": ink.count, "currentClusterCount": originalClusters.count,
                "currentClusterGlyphs": originalClusters.map { supportedGlyph($0.strokes) ?? "unsupported" },
                "hypothesisCount": 1 << (ordered.count - 1), "supportedPaths": supportedPaths])
        }
        XCTAssertEqual(rows.count, finalPass.payloads.count)
        XCTAssertFalse(rows.isEmpty)
        let report: [String: Any] = [
            "scope": "label-blind glyph-boundary feasibility; not recognition accuracy or a production change",
            "traceSHA256": SHA256.hash(data: originalTrace).map { String(format: "%02x", $0) }.joined(),
            "profileRevision": profile.revision.uuidString, "glyphExamples": glyphExamples.count,
            "maximumDistance": maximumDistance, "minimumMargin": minimumMargin, "targets": rows
        ]
        let encoded = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted])
        if let output = environment["ICHART_PERSONAL_GLYPH_BOUNDARY_REPORT"] {
            let outputURL = URL(fileURLWithPath: output).standardizedFileURL
            guard outputURL != traceURL.standardizedFileURL, outputURL != profileURL.standardizedFileURL else {
                XCTFail("Boundary report must not overwrite its source evidence")
                return
            }
            try encoded.write(to: outputURL, options: .atomic)
        }
        print("PERSONAL_GLYPH_BOUNDARY_REPORT\n\(String(decoding: encoded, as: UTF8.self))")
        XCTAssertEqual(try Data(contentsOf: traceURL), originalTrace)
        XCTAssertEqual(try Data(contentsOf: profileURL), originalProfile)
    }

    func testProvidedTraceChecksWholeChordEvidenceAcrossAdjacentBoundaries() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let tracePath = environment["ICHART_PERSONAL_BOUNDARY_TRACE_FILE"],
              let profilePath = environment["ICHART_PERSONAL_BOUNDARY_PROFILE_FILE"] else {
            throw XCTSkip("Provide an authorized local trace and frozen profile for boundary replay")
        }
        let traceURL = URL(fileURLWithPath: tracePath)
        let profileURL = URL(fileURLWithPath: profilePath)
        let originalTrace = try Data(contentsOf: traceURL)
        let originalProfile = try Data(contentsOf: profileURL)
        let profile = try JSONDecoder().decode(PersonalInkProfile.self, from: originalProfile)
        let snapshot = PersonalInkSnapshot(profile: profile)
        let recorder = ChordDraftPreviewDeviceDiagnosticRecorder(url: traceURL)
        let session = try XCTUnwrap(ChordInkRecognitionTrace(events: recorder.loadEvents()).latestNonemptySession)
        var seen = Set<[InkStroke]>()
        var rows: [[String: Any]] = []
        for (passIndex, pass) in session.passes.enumerated() {
            let targets = pass.payloads.sorted { ($0.visualOrder ?? .infinity) < ($1.visualOrder ?? .infinity) }
            for (left, right) in zip(targets, targets.dropFirst()) {
                guard let row = left.laneSystemIndex, row == right.laneSystemIndex,
                      let leftInk = left.inkStrokes, !leftInk.isEmpty,
                      let rightInk = right.inkStrokes, !rightInk.isEmpty else { continue }
                let ink = (leftInk + rightInk).sorted {
                    ($0.creationTimeOffset ?? 0) < ($1.creationTimeOffset ?? 0)
                }
                guard seen.insert(ink).inserted else { continue }
                let suggestion = snapshot.suggestion(strokes: ink)
                let native = ChordInkRecognizer(normalizesOversizedInput: false).recognize(strokes: ink)
                rows.append([
                    "passIndex": passIndex, "leftTarget": left.targetIndex, "rightTarget": right.targetIndex,
                    "leftNative": left.acceptedText ?? "no-read", "rightNative": right.acceptedText ?? "no-read",
                    "containsNoRead": left.acceptedText == nil || right.acceptedText == nil,
                    "combinedPortableNative": native.match?.displayText ?? "no-read",
                    "combinedPersonal": suggestion?.text ?? "no-suggestion",
                    "personalSource": suggestion?.source.rawValue ?? "none",
                    "correctionSupport": suggestion?.correctionSupportCount ?? 0,
                    "distance": suggestion.map { $0.distance as Any } ?? NSNull()
                ])
            }
        }
        XCTAssertFalse(rows.isEmpty, "The selected session must contain adjacent targets")
        let report: [String: Any] = [
            "scope": "label-blind local boundary experiment; not recognition accuracy or production grouping",
            "traceSHA256": SHA256.hash(data: originalTrace).map { String(format: "%02x", $0) }.joined(),
            "profileRevision": profile.revision.uuidString, "profileExamples": profile.examples.count,
            "hypotheses": rows
        ]
        let encoded = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted])
        if let output = environment["ICHART_PERSONAL_BOUNDARY_REPORT"] {
            let outputURL = URL(fileURLWithPath: output).standardizedFileURL
            guard outputURL != traceURL.standardizedFileURL, outputURL != profileURL.standardizedFileURL else {
                XCTFail("Boundary report must not overwrite its source evidence")
                return
            }
            try encoded.write(to: outputURL, options: .atomic)
        }
        print("PERSONAL_BOUNDARY_REPORT\n\(String(decoding: encoded, as: UTF8.self))")
        XCTAssertEqual(try Data(contentsOf: traceURL), originalTrace)
        XCTAssertEqual(try Data(contentsOf: profileURL), originalProfile)
    }
}
