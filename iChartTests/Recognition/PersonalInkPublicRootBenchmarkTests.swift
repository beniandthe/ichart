import XCTest
import CryptoKit
@testable import iChart

/// Public UJI v2 is a separate research dataset, never a personal profile or
/// production corpus. Only development writers are evaluated in this protocol.
final class PersonalInkPublicRootBenchmarkTests: XCTestCase {
    func testDevelopmentWritersPersonalizeFromFirstSessionOnly() throws {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["ICHART_PUBLIC_ROOT_DATASET"] else {
            throw XCTSkip("Supply the authorized public UJI v2 source for the fixed development protocol")
        }
        let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        let bytes = try Data(contentsOf: url)
        let all = try UJIPersonalRootInput.parse(String(decoding: bytes, as: UTF8.self))
        XCTAssertEqual(all.count, 11_640)
        let byWriter = Dictionary(grouping: all, by: \.writer)
        XCTAssertEqual(byWriter.count, 60)
        let trainingWriters = byWriter.keys.filter { $0.hasPrefix("trn_") }.sorted()
        let reservedWriters = byWriter.keys.filter { $0.hasPrefix("tst_") }.sorted()
        XCTAssertEqual(trainingWriters.count, 40)
        XCTAssertEqual(reservedWriters.count, 20)
        XCTAssertTrue(Set(trainingWriters).isDisjoint(with: reservedWriters))
        let vocabulary = Set(all.map(\.label))
        XCTAssertEqual(vocabulary.count, 97)
        for samples in byWriter.values {
            XCTAssertEqual(samples.count, 194)
            for session in [1, 2] {
                XCTAssertEqual(Set(samples.filter { $0.session == session }.map(\.label)), vocabulary)
            }
        }
        guard testRun?.failureCount == 0 else { return }
        var rows: [[String: Any]] = []
        var writerRows: [[String: Any]] = []
        let roots = "ABCDEFG".map(String.init)
        for writer in trainingWriters {
            let samples = try XCTUnwrap(byWriter[writer])
            var profile = PersonalInkProfile()
            profile.isEnabled = true
            let support = samples.filter { $0.session == 1 && roots.contains($0.label) }
            let queries = samples.filter { $0.session == 2 && roots.contains($0.label) }
            XCTAssertEqual(support.count, 7); XCTAssertEqual(queries.count, 7)
            XCTAssertTrue(Set(support.map(\.identity)).isDisjoint(with: queries.map(\.identity)))
            for sample in support {
                try profile.learn(strokes: sample.strokes, label: sample.label, kind: .glyph, source: .setup)
            }
            // Freeze before any query prediction or expected-label comparison.
            let head = try PersonalInkAdaptiveHead(profile: profile, kind: .glyph)
            let snapshot = PersonalInkSnapshot(profile: profile)
            let reference: [(String, PersonalInkShape)] = try profile.examples.map { example in
                (example.label, try XCTUnwrap(PersonalInkShape(strokes: example.strokes)))
            }
            var nearestCorrect = 0, learnedCorrect = 0, eligible = 0, gains = 0, harms = 0
            for query in queries {
                let shape = try XCTUnwrap(PersonalInkShape(strokes: query.strokes))
                let distances: [(label: String, distance: Double)] = reference.map { item in
                    (label: item.0, distance: shape.distance(to: item.1))
                }
                let nearest = distances.sorted {
                    $0.distance == $1.distance ? $0.label < $1.label : $0.distance < $1.distance
                }
                let learned = head.rankedCandidates(strokes: query.strokes)
                let first = try XCTUnwrap(nearest.first)
                let accepted = first.distance <= 0.075 && nearest[1].distance - first.distance >= 0.018
                let exactCopy = support.contains { sameTrajectory($0.strokes, query.strokes) }
                // Labels are consulted only after both predictions are fixed.
                let currentRight = first.label == query.label
                let learnedRight = learned.first?.label == query.label
                if !exactCopy {
                    eligible += 1
                    nearestCorrect += currentRight ? 1 : 0
                    learnedCorrect += learnedRight ? 1 : 0
                    gains += !currentRight && learnedRight ? 1 : 0
                    harms += currentRight && !learnedRight ? 1 : 0
                }
                rows.append(["writer": writer, "queryID": query.identity,
                    "supportIDs": support.map(\.identity).sorted(), "intended": query.label,
                    "exactNormalizedSupportCopy": exactCopy, "eligible": !exactCopy,
                    "nearest": first.label, "nearestDistance": first.distance,
                    "nearestAccepted": accepted, "nearestCorrect": currentRight,
                    "existingSymbolRoute": snapshot.suggestion(strokes: query.strokes)?.text ?? "no-read",
                    "learned": learned.first?.label ?? "no-rank", "learnedCorrect": learnedRight,
                    "learnedRankOnly": true, "learnedRanks": learned.map { ["label": $0.label, "score": $0.score] as [String: Any] }])
            }
            writerRows.append(["writer": writer, "eligible": eligible, "nearestCorrect": nearestCorrect,
                               "learnedCorrect": learnedCorrect, "gains": gains, "harms": harms])
        }
        XCTAssertEqual(rows.count, 280)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        let eligibleRows = rows.filter { $0["eligible"] as? Bool == true }
        let report: [String: Any] = [
            "scope": "public root-letter personalization development; not full chords or production accuracy",
            "modelVersion": PersonalInkAdaptiveHead.version,
            "sourceSHA256": SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
            "sourceRecords": all.count, "evaluatedWriters": trainingWriters.count,
            "reservedTestWriters": reservedWriters.count, "queries": rows.count,
            "eligibleQueries": eligibleRows.count,
            "nearestCorrect": eligibleRows.filter { $0["nearestCorrect"] as? Bool == true }.count,
            "learnedCorrect": eligibleRows.filter { $0["learnedCorrect"] as? Bool == true }.count,
            "nearestAccepted": eligibleRows.filter { $0["nearestAccepted"] as? Bool == true }.count,
            "nearestAcceptedWrong": eligibleRows.filter { $0["nearestAccepted"] as? Bool == true && $0["nearestCorrect"] as? Bool == false }.count,
            "writers": writerRows, "rows": rows]
        guard testRun?.failureCount == 0 else { return }
        if let reportPath = env["ICHART_PUBLIC_ROOT_REPORT"] {
            let output = URL(fileURLWithPath: reportPath).resolvingSymlinksInPath()
            XCTAssertNotEqual(output, url)
            guard output != url else { return }
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output, options: .atomic)
        }
        print("PUBLIC_ROOT_DEVELOPMENT writers=\(trainingWriters.count) queries=\(rows.count) eligible=\(eligibleRows.count)")
    }

    func testParserPreservesPointsSessionsAndRejectsDuplicateOrMalformedSamples() throws {
        let sample = "// source comment\nWORD A trn_UJI_W03-01\nNUMSTROKES 1\nPOINTS 3 # -1 0 -1 0 3 4\n"
        let parsed = try UJIPersonalRootInput.parse(sample)
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed[0].writer, "trn_UJI_W03")
        XCTAssertEqual(parsed[0].session, 1)
        XCTAssertEqual(parsed[0].strokes[0].points.count, 3)
        XCTAssertEqual(parsed[0].strokes[0].points[0].x, -1)
        XCTAssertNil(parsed[0].strokes[0].points[0].timeOffset)
        XCTAssertThrowsError(try UJIPersonalRootInput.parse(sample + sample))
        XCTAssertThrowsError(try UJIPersonalRootInput.parse(sample.replacingOccurrences(of: "POINTS 3", with: "POINTS 2")))
        XCTAssertThrowsError(try UJIPersonalRootInput.parse(sample.replacingOccurrences(of: "-01", with: "-03")))
        XCTAssertThrowsError(try UJIPersonalRootInput.parse("arbitrary text"))
    }

    private func sameTrajectory(_ lhs: [InkStroke], _ rhs: [InkStroke]) -> Bool {
        guard let a = PersonalInkShape(strokes: lhs)?.normalizedStrokes,
              let b = PersonalInkShape(strokes: rhs)?.normalizedStrokes, a.count == b.count else { return false }
        return zip(a, b).allSatisfy { x, y in
            x.points.count == y.points.count && zip(x.points, y.points).allSatisfy {
                abs($0.x - $1.x) < 1e-8 && abs($0.y - $1.y) < 1e-8
            }
        }
    }
}

struct UJIPersonalRootInput {
    let writer: String
    let session: Int
    let label: String
    let strokes: [InkStroke]
    var identity: String { "\(writer)-\(session)-\(label)" }
    enum Failure: Error { case malformed }

    static func parse(_ text: String) throws -> [Self] {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("//") }
        var index = 0, samples: [Self] = [], seen = Set<String>()
        func next() throws -> [String] {
            guard index < lines.count else { throw Failure.malformed }
            defer { index += 1 }
            return lines[index].split(whereSeparator: \.isWhitespace).map(String.init)
        }
        while index < lines.count {
            let header = try next()
            guard header.count == 3, header[0] == "WORD", header[1].count == 1 else { throw Failure.malformed }
            let session = header[2].split(separator: "-").map(String.init)
            guard session.count == 2, let repetition = Int(session[1]), [1, 2].contains(repetition),
                  session[0].range(of: #"^(trn|tst)_(UJI|UPV)_W[0-9]{2}$"#, options: .regularExpression) != nil else {
                throw Failure.malformed
            }
            let countLine = try next()
            guard countLine.count == 2, countLine[0] == "NUMSTROKES",
                  let count = Int(countLine[1]), (1...64).contains(count) else { throw Failure.malformed }
            var strokes: [InkStroke] = []
            for _ in 0..<count {
                let line = try next()
                guard line.count >= 3, line[0] == "POINTS", line[2] == "#",
                      let points = Int(line[1]), (1...32_768).contains(points), line.count == 3 + points * 2 else { throw Failure.malformed }
                var values: [InkPoint] = []
                for i in 0..<points {
                    guard let x = Int(line[3 + i * 2]), let y = Int(line[4 + i * 2]),
                          abs(Double(x)) < 1e8, abs(Double(y)) < 1e8 else { throw Failure.malformed }
                    values.append(InkPoint(x: Double(x), y: Double(y)))
                }
                strokes.append(InkStroke(points: values))
            }
            let sample = Self(writer: session[0], session: repetition, label: header[1], strokes: strokes)
            guard seen.insert(sample.identity).inserted else { throw Failure.malformed }
            samples.append(sample)
        }
        guard !samples.isEmpty else { throw Failure.malformed }
        return samples
    }
}
