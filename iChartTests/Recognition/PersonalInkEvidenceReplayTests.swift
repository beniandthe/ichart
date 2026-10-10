import XCTest
import CryptoKit
@testable import iChart

/// Read-only comparison of independent personal evidence routes. Intended
/// answers never enter this diagnostic, and no captured ink is bundled here.
final class PersonalInkEvidenceReplayTests: XCTestCase {
    func testProvidedTraceComparesWholeAndCompleteSymbolEvidence() throws {
        let env = ProcessInfo.processInfo.environment
        guard let tracePath = env["ICHART_PERSONAL_EVIDENCE_TRACE"],
              let profilePath = env["ICHART_PERSONAL_EVIDENCE_PROFILE"],
              let pipeline = env["ICHART_PERSONAL_EVIDENCE_PIPELINE"] else {
            throw XCTSkip("Provide an authorized trace, frozen profile, and exact source pipeline")
        }
        let traceURL = URL(fileURLWithPath: tracePath).resolvingSymlinksInPath()
        let profileURL = URL(fileURLWithPath: profilePath).resolvingSymlinksInPath()
        let traceData = try Data(contentsOf: traceURL), profileData = try Data(contentsOf: profileURL)
        let storedProfile = try JSONDecoder().decode(PersonalInkProfile.self, from: profileData)
        var profile = storedProfile
        if let excluded = env["ICHART_PERSONAL_EVIDENCE_EXCLUDING_EXAMPLE_ID"] {
            let id = try XCTUnwrap(UUID(uuidString: excluded))
            XCTAssertTrue(profile.removeExample(id: id), "The selected example must exist; this only changes a diagnostic copy")
        }
        let snapshot = PersonalInkSnapshot(profile: profile)
        var wholeProfile = profile, symbolProfile = profile
        wholeProfile.examples = profile.examples.filter { $0.kind == .chord }
        symbolProfile.examples = profile.examples.filter { $0.kind == .glyph }
        let wholeSnapshot = PersonalInkSnapshot(profile: wholeProfile)
        let symbolSnapshot = PersonalInkSnapshot(profile: symbolProfile)
        // Explicit developer comparison only, separate from live suggestions.
        let comparesAdaptive = env["ICHART_PERSONAL_EVIDENCE_ADAPTIVE"] == "1"
        let trainingStarted = ProcessInfo.processInfo.systemUptime
        let wholeHead = comparesAdaptive ? try PersonalInkAdaptiveHead(profile: profile, kind: .chord) : nil
        let symbolHead = comparesAdaptive ? try PersonalInkAdaptiveHead(profile: profile, kind: .glyph) : nil
        let trainingMilliseconds = (ProcessInfo.processInfo.systemUptime - trainingStarted) * 1_000
        let glyphExamples = symbolProfile.examples.compactMap { example in
            PersonalInkShape(strokes: example.strokes).map { (example.label, $0) }
        }
        let wholeExamples = wholeProfile.examples.compactMap { example in
            PersonalInkShape(strokes: example.strokes).map { (example, $0, visualParts(example.strokes)) }
        }
        let events = try ChordDraftPreviewDeviceDiagnosticRecorder(url: traceURL).loadEvents()
            .filter { $0.recognitionPipelineVersion == pipeline && ["finish_single", "finish_batch"].contains($0.stage) }
        var rows: [[String: Any]] = []
        var completeSymbols = 0, conflicts = 0, seen = Set<[InkStroke]>()
        for (pass, event) in events.enumerated() {
            for payload in event.payloads {
                let ink = try XCTUnwrap(payload.inkStrokes)
                XCTAssertFalse(ink.isEmpty)
                let whole = wholeSnapshot.suggestion(strokes: ink, previewEvenIfDisabled: true)
                let symbols = symbolSnapshot.suggestion(strokes: ink, previewEvenIfDisabled: true)
                let current = snapshot.suggestion(strokes: ink, previewEvenIfDisabled: true)
                let queryShape = try XCTUnwrap(PersonalInkShape(strokes: ink))
                let queryParts = visualParts(ink)
                // Diagnostic only: expose whether a low whole-image average
                // hides a distant separated part. No chord labels are used to
                // make boundaries, compare parts, or select these examples.
                let localSupport: [[String: Any]] = wholeExamples.compactMap { example, shape, parts in
                    let distance = queryShape.distance(to: shape)
                    guard distance <= 0.065 else { return nil }
                    let partDistances: [Double]? = queryParts.count == parts.count
                        && !queryParts.contains(where: { $0 == nil }) && !parts.contains(where: { $0 == nil })
                        ? zip(queryParts, parts).compactMap { left, right in
                            guard let left, let right else { return nil }
                            return left.distance(to: right)
                        } : nil
                    return ["label": example.label, "wholeDistance": distance,
                            "queryPartCount": queryParts.count, "examplePartCount": parts.count,
                            "partDistances": partDistances.map { $0 as Any } ?? NSNull(),
                            "allPartsSupported": partDistances.map { !$0.isEmpty && $0.allSatisfy { $0 <= 0.075 } } ?? false]
                }
                let clusters = StrokeClusterer().indexedClusters(ink.map { InkStroke(points: $0.points) })
                let glyphEvidence: [[String: Any]] = clusters.map { indexed in
                    let cluster = indexed.cluster
                    var nearestByLabel: [String: Double] = [:]
                    if let query = PersonalInkShape(strokes: cluster.strokes) {
                        for (label, shape) in glyphExamples {
                            nearestByLabel[label] = min(nearestByLabel[label] ?? .infinity, query.distance(to: shape))
                        }
                    }
                    let ranked = nearestByLabel.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value < $1.value }
                    return ["originalIndexes": indexed.originalIndexes,
                            "strokeCount": cluster.strokes.count,
                            "best": ranked.first?.key ?? "no-shape",
                            "bestDistance": ranked.first.map { $0.value as Any } ?? NSNull(),
                            "runnerUp": ranked.dropFirst().first?.key ?? "none",
                            "runnerUpDistance": ranked.dropFirst().first.map { $0.value as Any } ?? NSNull()]
                }
                if symbols != nil { completeSymbols += 1 }
                let conflict = whole != nil && symbols != nil && whole?.text != symbols?.text
                if conflict { conflicts += 1 }
                var row: [String: Any] = ["pass": pass, "style": event.layoutStyle ?? "unknown",
                    "targetIndex": payload.targetIndex, "uniqueInput": seen.insert(ink).inserted,
                    "inputFingerprint": PersonalInkEvaluationStore.fingerprint(strokes: ink),
                    "previewFingerprint": PersonalInkEvaluationStore.fingerprint(strokes: queryShape.normalizedStrokes),
                    "native": payload.matchText ?? "no-read", "whole": describe(whole),
                    "symbols": describe(symbols), "current": describe(current), "conflict": conflict,
                    "glyphEvidence": glyphEvidence, "inputStrokeCount": ink.count,
                    "wholeLocalSupportProbe": localSupport]
                if let wholeHead, let symbolHead {
                    let started = ProcessInfo.processInfo.systemUptime
                    let wholeRanks = wholeHead.rankedCandidates(strokes: ink)
                    let columns = clusters.map { symbolHead.rankedCandidates(strokes: $0.cluster.strokes) }
                    let tokens = columns.compactMap { $0.first?.label }
                    row["adaptive"] = [
                        "wholeRanks": wholeRanks.prefix(5).map { ["label": $0.label, "score": $0.score] as [String: Any] },
                        "glyphRanks": columns.map { $0.prefix(3).map { ["label": $0.label, "score": $0.score] as [String: Any] } },
                        "composedTop1Tokens": tokens.joined(),
                        "composedTop1Chord": tokens.count == clusters.count
                            ? (ChordRecognitionCompendium.match(tokens.joined())?.displayText ?? "invalid") : "incomplete",
                        "knownWholeInk": snapshot.wasAlreadyLearned(strokes: ink),
                        "rankOnlyNotAccepted": true,
                        "inferenceMilliseconds": (ProcessInfo.processInfo.systemUptime - started) * 1_000]
                }
                rows.append(row)
            }
        }
        XCTAssertFalse(rows.isEmpty, "An empty trace or wrong pipeline is not evidence")
        XCTAssertEqual(snapshot.profile, profile)
        XCTAssertEqual(try Data(contentsOf: traceURL), traceData)
        XCTAssertEqual(try Data(contentsOf: profileURL), profileData)
        guard testRun?.failureCount == 0 else { return }
        let report: [String: Any] = [
            "scope": "frozen exact-input evidence routes; no learning or accuracy claim",
            "sourcePipeline": pipeline, "profileExamples": profile.examples.count,
            "profileRevision": profile.revision.uuidString,
            "sourceProfileRevision": storedProfile.revision.uuidString,
            "sourceProfileExamples": storedProfile.examples.count,
            "excludedExampleCount": storedProfile.examples.count - profile.examples.count,
            "traceSHA256": SHA256.hash(data: traceData).map { String(format: "%02x", $0) }.joined(),
            "profileSHA256": SHA256.hash(data: profileData).map { String(format: "%02x", $0) }.joined(),
            "observations": rows.count, "uniqueInputs": seen.count,
            "adaptiveComparison": comparesAdaptive,
            "adaptiveVersion": comparesAdaptive ? PersonalInkAdaptiveHead.version : "not-run",
            "adaptiveTrainingMilliseconds": trainingMilliseconds,
            "completeSymbolObservations": completeSymbols, "conflictingObservations": conflicts, "rows": rows
        ]
        let encoded = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted])
        if let reportPath = env["ICHART_PERSONAL_EVIDENCE_REPORT"] {
            let output = URL(fileURLWithPath: reportPath).resolvingSymlinksInPath()
            guard output != traceURL, output != profileURL else {
                XCTFail("Report cannot overwrite either source"); return
            }
            try encoded.write(to: output, options: .atomic)
        }
        print("PERSONAL_EVIDENCE_REPLAY\n\(String(decoding: encoded, as: UTF8.self))")
    }

    /// Clear horizontal gaps only, not inferred glyph labels. A connected
    /// stroke cannot be split and every nonempty stroke belongs to one part.
    /// This deliberately does not reuse the scale-sensitive legacy clusterer.
    private func visualParts(_ strokes: [InkStroke]) -> [PersonalInkShape?] {
        let ordered = strokes.filter { !$0.points.isEmpty }.sorted { $0.bounds.minX < $1.bounds.minX }
        var groups: [[InkStroke]] = []
        var right = -Double.infinity
        for stroke in ordered {
            if groups.isEmpty || stroke.bounds.minX > right {
                groups.append([stroke]); right = stroke.bounds.maxX
            } else {
                groups[groups.count - 1].append(stroke)
                right = max(right, stroke.bounds.maxX)
            }
        }
        // An unsupported dot/tiny component remains visible as nil, so it
        // cannot disappear and turn an incomplete comparison into support.
        return groups.map { PersonalInkShape(strokes: $0) }
    }

    func testLocalSupportProbeIsOrderAndScaleIndependentAndRetainsUnsupportedParts() throws {
        let first = InkStroke(points: [InkPoint(x: 0, y: 0), InkPoint(x: 5, y: 20)])
        let second = InkStroke(points: [InkPoint(x: 30, y: 0), InkPoint(x: 40, y: 10)])
        let parts = visualParts([first, second])
        XCTAssertEqual(parts.count, 2)
        let transformed = [second, first].map { stroke in
            InkStroke(points: stroke.points.reversed().map { InkPoint(x: $0.x * 3 + 74, y: $0.y * 3 - 120) })
        }
        let changed = visualParts(transformed)
        XCTAssertEqual(changed.count, parts.count)
        for (left, right) in zip(parts, changed) {
            XCTAssertEqual(try XCTUnwrap(left).distance(to: XCTUnwrap(right)), 0, accuracy: 1e-10)
        }
        let withDot = visualParts([first, second, InkStroke(points: [InkPoint(x: 50, y: 5)])])
        XCTAssertEqual(withDot.count, 3)
        XCTAssertNil(withDot[2], "Unknown isolated ink cannot be dropped from the diagnostic")
    }

    private func describe(_ suggestion: ChordInkPersonalSuggestion?) -> [String: Any] {
        guard let suggestion else { return ["text": "no-suggestion"] }
        return ["text": suggestion.text, "source": suggestion.source.rawValue,
                "distance": suggestion.distance, "support": suggestion.supportingExampleCount,
                "correctionSupport": suggestion.correctionSupportCount]
    }
}
