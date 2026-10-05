import CryptoKit
import Foundation
import XCTest
@testable import iChart

/// Opt-in isolated public-character export. No truth DTO, scoring, live writes,
/// reserved writers, altered rank selection, or reconstructed Python encoder.
final class PersonalInkPublicLocalTransferTests: XCTestCase {
    private enum Failure: Error { case invalid(String) }
    private let sourceSHA = "cc56f72f8477e763dd06a44746ba05a679e9232468aac93b3a7aad46a0300d61"
    private let writers = ["trn_UJI_W04", "trn_UJI_W06", "trn_UJI_W08", "trn_UJI_W11",
        "trn_UPV_W35", "trn_UPV_W43", "trn_UPV_W47", "trn_UPV_W56"]
    private let core = ["A", "B", "C", "D", "E", "F", "G", "b", "-", "7"]
    private var catalog: [String] { core + ["m", "o", "6", "9", "2", "4", "5", "1", "3", "(", ")"] }

    private struct Fixture: Decodable {
        struct Sample: Decodable {
            struct Point: Decodable { let x: Double; let y: Double }
            let id: String
            let writerID: String
            let session: Int
            let strokes: [[Point]]
            var ink: [InkStroke] { strokes.map { InkStroke(points: $0.map { .init(x: $0.x, y: $0.y) }) } }
        }
        struct Task: Decodable {
            struct Lesson: Decodable { let sampleID: String; let label: String; let exampleID: UUID }
            let name: String
            let writerID: String
            let profileRevision: UUID
            let profileGeneration: UUID
            let lessons: [Lesson]
            let queryIDs: [String]
        }
        let version: String
        let protocolSHA256: String
        let sourceSHA256: String
        let writerIDs: [String]
        let vocabulary97: [String]
        let tasks: [Task]
        let samples: [Sample]
        let sessionOneByWriter: [String: [String]]
    }
    private struct InputCommitment: Codable {
        let version: String
        let sourceSHA256: String
        let protocolSHA256: String
        let fixtureSHA256: String
        let queryTruthSHA256: String
        let sourceCopyLedgerSHA256: String
        let developmentWriters: [String]
        let supportTasks: [String]
        let sampleCount: Int
        let queryCountPerTask: Int
        let rawSourceCopyQueries: Int
        let reservedWriterRasterCount: Int
        let inferencePerformed: Bool
    }
    private struct RawSample: Encodable {
        let id: String
        let writerID: String
        let session: Int
        let sourceCanonicalData: Data
        let sourcePacketSHA256: String
        let rawRasterSHA256: String?
        let failure: String?
        private enum CodingKeys: String, CodingKey {
            case id, writerID, session, sourceCanonicalData, sourcePacketSHA256, rawRasterSHA256, failure
        }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(id, forKey: .id); try c.encode(writerID, forKey: .writerID); try c.encode(session, forKey: .session)
            try c.encode(sourceCanonicalData, forKey: .sourceCanonicalData)
            try c.encode(sourcePacketSHA256, forKey: .sourcePacketSHA256)
            try c.encode(rawRasterSHA256, forKey: .rawRasterSHA256); try c.encode(failure, forKey: .failure)
        }
    }
    private struct StoredLesson: Encodable {
        let sampleID: String
        let label: String
        let exampleID: UUID
        let storedCanonicalData: Data
        let storedPacketSHA256: String
        let storedRasterSHA256: String
    }
    private struct PreparedProfile: Encodable {
        let task: String
        let writerID: String
        let profileCanonicalData: Data
        let profileSHA256: String
        let supportLessons: [StoredLesson]
    }
    private struct ProfileOutput: Encodable {
        let task: String
        let writerID: String
        let profileCanonicalData: Data
        let profileSHA256: String
        let supportLessons: [StoredLesson]
        let modelIdentity: PersonalInkLocalAnchoredComparison.ModelIdentity
        let support: PersonalInkLocalAnchoredComparison.SupportProjection
    }
    private struct Row: Encodable {
        let task: String
        let writerID: String
        let sampleID: String
        let outcome: String
        let reading: PersonalInkLocalAnchoredComparison.Reading?
        let failure: String?
        private enum CodingKeys: String, CodingKey { case task, writerID, sampleID, outcome, reading, failure }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(task, forKey: .task); try c.encode(writerID, forKey: .writerID)
            try c.encode(sampleID, forKey: .sampleID); try c.encode(outcome, forKey: .outcome)
            try c.encode(reading, forKey: .reading); try c.encode(failure, forKey: .failure)
        }
    }
    private struct Ledger: Encodable {
        let version = "public-app-local-transfer-pre-inference-ledger-v1"
        let sourceSHA256: String
        let fixtureSHA256: String
        let protocolSHA256: String
        let rawSamples: [RawSample]
        let preparedProfiles: [PreparedProfile]
    }
    private struct Report: Encodable {
        let version = "public-app-local-transfer-predictions-v1"
        let artifactKind = "engineering-only-public-isolated-character-comparison-v1"
        let liveRecognitionChanged = false
        let profileChanged = false
        let trainingEligible = false
        let naturalChordAccuracyMeasured = false
        let encoderConversionParityMeasured = false
        let reservedWriterInferencePerformed = false
        let reservedWriterRasterCount = 0
        let reservedWriterPersonalFitCount = 0
        let intendedQueryLabelsSupplied = false
        let ancillaryParserStringsUsedForSelection = false
        let trainingWriterMembershipVerified = false
        let sourceSHA256: String
        let fixtureSHA256: String
        let protocolSHA256: String
        let inputCommitmentCanonicalData: Data
        let inputCommitmentSHA256: String
        let queryTruthSHA256: String
        let sourceCopyLedgerSHA256: String
        let codeFilesSHA256: [String: String]
        let codeSHA256: String
        let runtimeFilesSHA256: [String: String]
        let runtimeSHA256: String
        let encoderIdentity: String
        let vocabulary: [String]
        let rasterSchemaVersion = ChordInkFeatureSchema.version
        let rasterWidth = ChordInkFeatureSchema.rasterWidth
        let rasterHeight = ChordInkFeatureSchema.rasterHeight
        let preInferenceLedgerCanonicalData: Data
        let preInferenceLedgerSHA256: String
        let rawSamples: [RawSample]
        let profiles: [ProfileOutput]
        let rows: [Row]
    }

    #if DEBUG && canImport(CoreML)
    func testProvidedPublicDevelopmentWritersExportLocalTransfer() throws {
        let env = ProcessInfo.processInfo.environment
        let keys = ["FIXTURE", "FIXTURE_SHA256", "PROTOCOL", "PROTOCOL_SHA256", "REPOSITORY_ROOT",
            "CODE_MAP", "CODE_SHA256", "RUNTIME_MAP", "RUNTIME_SHA256", "REPORT",
            "INPUT_COMMITMENT", "INPUT_COMMITMENT_SHA256"].map { "ICHART_PUBLIC_TRANSFER_" + $0 }
            + ["ICHART_PERSONAL_ML_RUNTIME_DIRECTORY"]
        guard keys.allSatisfy({ env[$0] != nil }) else { throw XCTSkip("Provide the frozen public transfer inputs, commitments, runtime and exclusive report") }
        guard keys.allSatisfy({ !(env[$0] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw Failure.invalid("Empty transfer environment value")
        }
        func path(_ index: Int) -> URL { URL(fileURLWithPath: env[keys[index]]!).standardizedFileURL.resolvingSymlinksInPath() }
        let fixtureURL = path(0), protocolURL = path(2), rootURL = path(4), codeURL = path(5)
        let runtimeMapURL = path(7), outputURL = path(9), commitmentURL = path(10), runtimeURL = path(12)
        let inputs = [fixtureURL, protocolURL, codeURL, runtimeMapURL, commitmentURL]
        guard !inputs.contains(outputURL), !outputURL.path.hasPrefix(rootURL.path + "/"),
              !outputURL.path.hasPrefix(runtimeURL.path + "/"), !FileManager.default.fileExists(atPath: outputURL.path) else {
            throw Failure.invalid("Report must be an exclusive nonalias file outside repository/runtime")
        }
        // Read/validate immutable input bytes and code/runtime maps before any
        // normalization, rasterization, model construction or inference.
        let fixtureData = try boundedRead(fixtureURL, maximum: 32 * 1_024 * 1_024)
        let protocolData = try boundedRead(protocolURL, maximum: 256 * 1_024)
        let codeData = try boundedRead(codeURL, maximum: 1_024 * 1_024)
        let runtimeMapData = try boundedRead(runtimeMapURL, maximum: 1_024 * 1_024)
        let commitmentData = try boundedRead(commitmentURL, maximum: 256 * 1_024)
        let codeFiles = try JSONDecoder().decode([String: String].self, from: codeData)
        let runtimeFiles = try JSONDecoder().decode([String: String].self, from: runtimeMapData)
        let commitment = try JSONDecoder().decode(InputCommitment.self, from: commitmentData)
        guard digest(fixtureData) == env[keys[1]], digest(protocolData) == env[keys[3]],
              digest(codeData) == env[keys[6]], digest(runtimeMapData) == env[keys[8]],
              digest(commitmentData) == env[keys[11]], try canonical(commitment) == commitmentData,
              try canonical(codeFiles) == codeData, try canonical(runtimeFiles) == runtimeMapData,
              requiredCodePaths.isSubset(of: Set(codeFiles.keys)),
              codeFiles["docs/personal-public-app-local-transfer-protocol-2026-10-01.md"] == digest(protocolData),
              try fileDigests(rootURL, paths: Set(codeFiles.keys)) == codeFiles,
              try runtimeDigests(runtimeURL) == runtimeFiles,
              runtimeFiles["manifest.json"] == PersonalInkVisualEncoder.anchoredManifestSHA256,
              runtimeFiles["public-anchors.json"] == PersonalInkVisualEncoder.anchorSHA256 else {
            throw Failure.invalid("Exact input/code/runtime commitments disagree")
        }
        try validateFixtureShape(fixtureData)
        let fixture = try JSONDecoder().decode(Fixture.self, from: fixtureData)
        try validate(fixture)
        guard commitment.version == "public-app-local-transfer-input-commitment-v1",
              commitment.sourceSHA256 == sourceSHA, commitment.protocolSHA256 == fixture.protocolSHA256,
              commitment.protocolSHA256 == digest(protocolData), commitment.fixtureSHA256 == digest(fixtureData),
              validDigest(commitment.queryTruthSHA256), validDigest(commitment.sourceCopyLedgerSHA256),
              commitment.developmentWriters == writers, commitment.supportTasks == ["core10", "catalog21"],
              commitment.sampleCount == 1_552, commitment.queryCountPerTask == 776,
              commitment.rawSourceCopyQueries == 4, commitment.reservedWriterRasterCount == 0,
              !commitment.inferencePerformed else { throw Failure.invalid("Pre-inference truth/copy commitments disagree") }

        let byID = Dictionary(uniqueKeysWithValues: fixture.samples.map { ($0.id, $0) })
        var raw: [RawSample] = []
        for sample in fixture.samples {
            let data = try ChordInkCanonicalTrajectoryPacket(strokes: sample.ink).canonicalData()
            _ = try PersonalInkBlindPredictionFreeze.decodeBoundedPacket(data)
            let hash: String?, failure: String?
            do { hash = try rasterDigest(sample.ink); failure = nil }
            catch is ChordInkFeatureEncodingError {
                guard sample.session == 2 else { throw Failure.invalid("Session-one source raster preparation failed") }
                hash = nil; failure = "invalid-ink"
            }
            raw.append(.init(id: sample.id, writerID: sample.writerID, session: sample.session,
                sourceCanonicalData: data, sourcePacketSHA256: digest(data), rawRasterSHA256: hash, failure: failure))
        }
        let rawByID = Dictionary(uniqueKeysWithValues: raw.map { ($0.id, $0) })
        var profiles: [PersonalInkProfile] = []
        var prepared: [PreparedProfile] = []
        for task in fixture.tasks {
            var profile = PersonalInkProfile(); profile.isEnabled = true
            var stored: [StoredLesson] = []
            for lesson in task.lessons {
                let ink = byID[lesson.sampleID]!.ink
                let before = profile.examples.count
                guard let expected = PersonalInkShape(strokes: ink)?.normalizedStrokes,
                      try profile.learn(strokes: ink, label: lesson.label, kind: .glyph, source: .setup, captureContext: nil),
                      profile.examples.count == before + 1,
                      profile.examples[before].strokes == expected,
                      profile.examples[before].label == lesson.label,
                      profile.examples[before].source == .setup,
                      profile.examples[before].learningProvenance == nil,
                      profile.examples[before].verifiedSymbolOrigin == nil else {
                    throw Failure.invalid("A fixed support lesson was invalid, deduplicated or altered")
                }
                profile.examples[before].id = lesson.exampleID
                let data = try ChordInkCanonicalTrajectoryPacket(strokes: profile.examples[before].strokes).canonicalData()
                stored.append(.init(sampleID: lesson.sampleID, label: lesson.label, exampleID: lesson.exampleID,
                    storedCanonicalData: data, storedPacketSHA256: digest(data),
                    storedRasterSHA256: try rasterDigest(profile.examples[before].strokes)))
            }
            profile.revision = task.profileRevision; profile.generation = task.profileGeneration
            guard profile.examples.count == task.lessons.count,
                  profile.examples.map(\.id) == task.lessons.map(\.exampleID),
                  profile.examples.map(\.label) == task.lessons.map(\.label) else { throw Failure.invalid("Prepared profile lost fixed lessons") }
            let data = try canonical(profile)
            profiles.append(profile)
            prepared.append(.init(task: task.name, writerID: task.writerID, profileCanonicalData: data,
                profileSHA256: digest(data), supportLessons: stored))
        }
        // All 16 app-normalized profiles and all raw/stored raster commitments
        // are frozen BEFORE constructing the encoder or fitting any model.
        let ledgerData = try canonical(Ledger(sourceSHA256: sourceSHA, fixtureSHA256: digest(fixtureData),
            protocolSHA256: digest(protocolData), rawSamples: raw, preparedProfiles: prepared))
        let encoder = try PersonalInkVisualEncoder(directory: runtimeURL)
        guard encoder.vocabulary.count == 97, Set(encoder.vocabulary) == Set(fixture.vocabulary97) else { throw Failure.invalid("Wrong 97-class encoder") }
        let models = try profiles.map { try PersonalInkLocalAnchoredComparison(profile: $0, encoder: encoder) }
        var profileOutputs: [ProfileOutput] = []
        for index in models.indices {
            guard models[index].vocabulary == encoder.vocabulary,
                  models[index].modelIdentity.runtimeKind == PersonalInkLocalAnchoredComparison.pinnedRuntimeKind,
                  models[index].support.profileSHA256 == prepared[index].profileSHA256,
                  models[index].support.supportExampleCount == fixture.tasks[index].lessons.count,
                  try models[index].support.recomputedSHA256() == models[index].support.sha256,
                  try canonical(models[index].profile) == prepared[index].profileCanonicalData else { throw Failure.invalid("Fit changed prepared support/profile") }
            profileOutputs.append(.init(task: prepared[index].task, writerID: prepared[index].writerID,
                profileCanonicalData: prepared[index].profileCanonicalData, profileSHA256: prepared[index].profileSHA256,
                supportLessons: prepared[index].supportLessons, modelIdentity: models[index].modelIdentity, support: models[index].support))
        }
        // Every fit is complete before the first scheduled query. Technical
        // failures abort; geometry no-reads remain explicit denominator rows.
        var rows: [Row] = []
        var sharedByID: [String: Data] = [:]
        for (index, task) in fixture.tasks.enumerated() {
            let model = models[index], profile = profiles[index]
            for id in task.queryIDs {
                let sample = byID[id]!, source = rawByID[id]!
                guard source.failure == nil else {
                    rows.append(.init(task: task.name, writerID: task.writerID, sampleID: id,
                        outcome: "invalid-ink", reading: nil, failure: "raw-raster-invalid-ink")); continue
                }
                let reading: PersonalInkLocalAnchoredComparison.Reading
                do {
                    reading = try model.readSuppliedOriginalGroups(sample.ink,
                        originalIndexGroups: [Array(sample.ink.indices)], currentProfile: { profile })
                } catch PersonalInkLearnedComparison.Failure.invalidInk {
                    rows.append(.init(task: task.name, writerID: task.writerID, sampleID: id,
                        outcome: "invalid-ink", reading: nil, failure: "reader-invalid-ink")); continue
                } catch is ChordInkFeatureEncodingError {
                    rows.append(.init(task: task.name, writerID: task.writerID, sampleID: id,
                        outcome: "invalid-ink", reading: nil, failure: "reader-geometry-no-read")); continue
                }
                try validateReading(reading, source: source, strokeCount: sample.ink.count, model: model)
                let shared = try canonical(SharedEvidence(embedding: reading.glyphs[0].embedding,
                    baseScores: reading.glyphs[0].baseScores, ranks: reading.glyphs[0].sharedRanks))
                if let prior = sharedByID[id], prior != shared { throw Failure.invalid("Shared evidence changed across tasks") }
                sharedByID[id] = shared
                rows.append(.init(task: task.name, writerID: task.writerID, sampleID: id,
                    outcome: "read", reading: reading, failure: nil))
            }
        }
        guard rows.count == 1_552, ["core10", "catalog21"].allSatisfy({ task in rows.filter { $0.task == task }.count == 776 }),
              rows.map({ $0.task + ":" + $0.sampleID }).count == Set(rows.map { $0.task + ":" + $0.sampleID }).count,
              try canonical(Ledger(sourceSHA256: sourceSHA, fixtureSHA256: digest(fixtureData),
                protocolSHA256: digest(protocolData), rawSamples: raw, preparedProfiles: prepared)) == ledgerData else {
            throw Failure.invalid("Scheduled query denominator or pre-inference ledger changed")
        }
        for index in profiles.indices {
            guard try canonical(profiles[index]) == prepared[index].profileCanonicalData,
                  try canonical(models[index].profile) == prepared[index].profileCanonicalData else { throw Failure.invalid("Frozen profile mutated") }
        }
        guard try Data(contentsOf: fixtureURL) == fixtureData, try Data(contentsOf: protocolURL) == protocolData,
              try Data(contentsOf: commitmentURL) == commitmentData, try Data(contentsOf: codeURL) == codeData,
              try Data(contentsOf: runtimeMapURL) == runtimeMapData,
              try fileDigests(rootURL, paths: Set(codeFiles.keys)) == codeFiles,
              try runtimeDigests(runtimeURL) == runtimeFiles else { throw Failure.invalid("Source/code/runtime bytes changed") }
        let report = Report(sourceSHA256: sourceSHA, fixtureSHA256: digest(fixtureData), protocolSHA256: digest(protocolData),
            inputCommitmentCanonicalData: commitmentData, inputCommitmentSHA256: digest(commitmentData),
            queryTruthSHA256: commitment.queryTruthSHA256, sourceCopyLedgerSHA256: commitment.sourceCopyLedgerSHA256,
            codeFilesSHA256: codeFiles, codeSHA256: digest(codeData), runtimeFilesSHA256: runtimeFiles,
            runtimeSHA256: digest(runtimeMapData), encoderIdentity: encoder.identity, vocabulary: encoder.vocabulary,
            preInferenceLedgerCanonicalData: ledgerData, preInferenceLedgerSHA256: digest(ledgerData),
            rawSamples: raw, profiles: profileOutputs, rows: rows)
        try canonical(report).write(to: outputURL, options: .withoutOverwriting)
        print("PERSONAL_PUBLIC_LOCAL_TRANSFER profiles=16 scheduledQueries=1552 read=\(rows.filter { $0.outcome == "read" }.count) invalid=\(rows.filter { $0.outcome == "invalid-ink" }.count) queryTruthOpened=false reservedWriterInference=false liveChanged=false")
    }
    #endif

    private struct SharedEvidence: Encodable { let embedding: [Double]; let baseScores: [Double]; let ranks: [PersonalInkLearnedComparison.Rank] }
    private func validate(_ fixture: Fixture) throws {
        guard fixture.version == "public-app-local-transfer-fixture-v1", fixture.sourceSHA256 == sourceSHA,
              validDigest(fixture.protocolSHA256), fixture.writerIDs == writers,
              fixture.vocabulary97.count == 97, Set(fixture.vocabulary97).count == 97,
              fixture.vocabulary97 == fixture.vocabulary97.sorted(), fixture.vocabulary97.allSatisfy({ $0.count == 1 }),
              Set(catalog).isSubset(of: Set(fixture.vocabulary97)), fixture.samples.count == 1_552,
              Set(fixture.samples.map(\.id)).count == 1_552, fixture.tasks.count == 16,
              Set(fixture.sessionOneByWriter.keys) == Set(writers) else { throw Failure.invalid("Wrong fixed public cohort") }
        let byID = Dictionary(uniqueKeysWithValues: fixture.samples.map { ($0.id, $0) })
        for sample in fixture.samples {
            guard validDigest(sample.id), writers.contains(sample.writerID), [1, 2].contains(sample.session),
                  sample.strokes.count <= PersonalInkBlindPredictionFreeze.maximumStrokeCount,
                  sample.strokes.allSatisfy({ $0.count <= PersonalInkBlindPredictionFreeze.maximumPointsPerStroke && $0.allSatisfy { $0.x.isFinite && $0.y.isFinite } }),
                  sample.strokes.reduce(0, { $0 + $1.count }) <= PersonalInkBlindPredictionFreeze.maximumTotalPointCount else { throw Failure.invalid("Malformed public source geometry") }
        }
        guard Set(fixture.tasks.map { $0.writerID + ":" + $0.name }) == Set(writers.flatMap { writer in [writer + ":core10", writer + ":catalog21"] }),
              Set(fixture.tasks.map(\.profileRevision)).count == 16, Set(fixture.tasks.map(\.profileGeneration)).count == 16,
              Set(fixture.tasks.flatMap { $0.lessons.map(\.exampleID) }).count == 248 else { throw Failure.invalid("Repeated profile/task IDs") }
        for writer in writers {
            let first = fixture.samples.filter { $0.writerID == writer && $0.session == 1 }.map(\.id)
            let second = fixture.samples.filter { $0.writerID == writer && $0.session == 2 }.map(\.id)
            guard first.count == 97, second.count == 97,
                  fixture.sessionOneByWriter[writer]?.count == 97,
                  Set(fixture.sessionOneByWriter[writer]!) == Set(first) else { throw Failure.invalid("Wrong writer/session source partition") }
            let tasks = fixture.tasks.filter { $0.writerID == writer }
            for task in tasks {
                let labels = task.name == "core10" ? core : catalog
                guard task.lessons.map(\.label) == labels, Set(task.lessons.map(\.sampleID)).count == labels.count,
                      task.lessons.allSatisfy({ byID[$0.sampleID]?.writerID == writer && byID[$0.sampleID]?.session == 1 }),
                      task.queryIDs.count == 97, Set(task.queryIDs) == Set(second) else { throw Failure.invalid("Changed support order or query cohort") }
            }
            guard tasks[0].queryIDs == tasks[1].queryIDs,
                  tasks.first(where: { $0.name == "catalog21" })!.lessons.prefix(core.count).map(\.sampleID)
                    == tasks.first(where: { $0.name == "core10" })!.lessons.map(\.sampleID) else { throw Failure.invalid("Tasks disagree on fixed source identities") }
        }
    }
    private func validateFixtureShape(_ data: Data) throws {
        func object(_ value: Any?, keys: Set<String>) throws -> [String: Any] {
            guard let value = value as? [String: Any], Set(value.keys) == keys else { throw Failure.invalid("Unexpected fixture fields; no query labels are accepted") }
            return value
        }
        let root = try object(JSONSerialization.jsonObject(with: data), keys: ["version", "protocolSHA256", "sourceSHA256", "writerIDs", "vocabulary97", "tasks", "samples", "sessionOneByWriter"])
        guard let samples = root["samples"] as? [Any], samples.count == 1_552,
              let tasks = root["tasks"] as? [Any], tasks.count == 16 else { throw Failure.invalid("Unexpected fixture size") }
        for value in samples {
            let sample = try object(value, keys: ["id", "writerID", "session", "strokes"])
            guard let strokes = sample["strokes"] as? [[Any]], strokes.count <= 256 else { throw Failure.invalid("Source stroke budget exceeded") }
            var points = 0
            for stroke in strokes {
                points += stroke.count
                guard stroke.count <= 8_192, points <= 32_768 else { throw Failure.invalid("Source point budget exceeded") }
                for point in stroke { _ = try object(point, keys: ["x", "y"]) }
            }
        }
        for value in tasks {
            let task = try object(value, keys: ["name", "writerID", "profileRevision", "profileGeneration", "lessons", "queryIDs"])
            guard let lessons = task["lessons"] as? [Any], lessons.count <= 21 else { throw Failure.invalid("Unexpected lesson count") }
            for lesson in lessons { _ = try object(lesson, keys: ["sampleID", "label", "exampleID"]) }
        }
    }
    private func validateReading(_ reading: PersonalInkLocalAnchoredComparison.Reading, source: RawSample,
                                 strokeCount: Int, model: PersonalInkLocalAnchoredComparison) throws {
        guard reading.version == PersonalInkLocalAnchoredComparison.version, reading.modelIdentity == model.modelIdentity,
              reading.encoderIdentity == model.encoderIdentity, reading.sourceStrokeCount == strokeCount,
              reading.sourceInkSHA256 == source.sourcePacketSHA256, reading.profileRevision == model.profile.revision,
              reading.profileGeneration == model.profile.generation, reading.support == model.support,
              reading.glyphs.count == 1, reading.glyphs[0].originalStrokeIndexes == Array(0..<strokeCount) else { throw Failure.invalid("Reading source/model binding mismatch") }
        let glyph = reading.glyphs[0]
        guard glyph.embedding.count == 128, glyph.embedding.allSatisfy(\.isFinite),
              abs(glyph.embedding.reduce(0) { $0 + $1 * $1 } - 1) <= 1e-3,
              glyph.embeddingSHA256 == vectorDigest(glyph.embedding), glyph.baseScoresSHA256 == vectorDigest(glyph.baseScores),
              glyph.baseScores.count == 97, glyph.baseScores.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 1 }),
              abs(glyph.baseScores.reduce(0, +) - 1) <= 1e-8 else { throw Failure.invalid("Invalid embedding/base numeric commitments") }
        for ranks in [glyph.sharedRanks, glyph.controlRanks, glyph.localRanks] {
            guard ranks.count == 97, Set(ranks.map(\.label)) == Set(model.vocabulary), ranks.allSatisfy({ $0.score.isFinite }),
                  zip(ranks, ranks.dropFirst()).allSatisfy({ $0.0.score > $0.1.score || ($0.0.score == $0.1.score && $0.0.label < $0.1.label) }) else { throw Failure.invalid("Incomplete or malformed full ranking") }
        }
        let base = Dictionary(uniqueKeysWithValues: zip(model.vocabulary, glyph.baseScores))
        guard glyph.sharedRanks.allSatisfy({ base[$0.label] == $0.score }) else { throw Failure.invalid("Shared scores changed from frozen base") }
    }
    private func boundedRead(_ url: URL, maximum: Int) throws -> Data {
        let p = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard p.isRegularFile == true, p.isSymbolicLink != true, (p.fileSize ?? Int.max) <= maximum else { throw Failure.invalid("Input file is not bounded/regular") }
        return try Data(contentsOf: url)
    }
    private func rasterDigest(_ strokes: [InkStroke]) throws -> String { digest(Data(try ChordInkRasterizer.rasterize(strokes: strokes).pixels)) }
    private func canonical<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
    private func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private func validDigest(_ value: String) -> Bool { value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } }
    private func vectorDigest(_ values: [Double]) -> String {
        var data = Data()
        for value in values { var bits = value.bitPattern.littleEndian; Swift.withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) } }
        return digest(data)
    }
    private func fileDigests(_ root: URL, paths: Set<String>) throws -> [String: String] {
        guard (1...1_024).contains(paths.count) else { throw Failure.invalid("Invalid commitment path count") }
        var hashes: [String: String] = [:]
        for path in paths {
            let parts = path.split(separator: "/", omittingEmptySubsequences: false)
            guard parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { throw Failure.invalid("Nonrelative commitment path") }
            let url = root.appendingPathComponent(path).standardizedFileURL
            guard url.path.hasPrefix(root.path + "/"), url.resolvingSymlinksInPath() == url else { throw Failure.invalid("Commitment path alias/escape") }
            hashes[path] = digest(try boundedRead(url, maximum: 4 * 1_024 * 1_024))
        }
        return hashes
    }
    private func runtimeDigests(_ root: URL) throws -> [String: String] {
        guard let e = FileManager.default.enumerator(atPath: root.path) else { throw Failure.invalid("Missing runtime directory") }
        var paths = Set<String>()
        for case let path as String in e {
            let p = try root.appendingPathComponent(path).resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard p.isSymbolicLink != true else { throw Failure.invalid("Runtime symlink") }
            if p.isRegularFile == true { paths.insert(path) }
        }
        return try fileDigests(root, paths: paths)
    }
    private var requiredCodePaths: Set<String> { [
        "iChartTests/Recognition/PersonalInkPublicLocalTransferTests.swift",
        "docs/personal-public-app-local-transfer-protocol-2026-10-01.md",
        "iChart/Recognition/PersonalInkLocalAnchoredComparison.swift",
        "iChart/Recognition/PersonalInkLocalAnchoredResidualHead.swift",
        "iChart/Recognition/PersonalInkAnchoredResidualHead.swift",
        "iChart/Recognition/PersonalInkResidualHead.swift",
        "iChart/Recognition/PersonalInkLearnedComparison.swift",
        "iChart/Recognition/PersonalInkVisualEncoder.swift",
        "iChart/Recognition/PersonalInkBlindPredictionFreeze.swift",
        "iChart/Recognition/ChordInkPersonalization.swift",
        "iChart/Recognition/PersonalInkLearningLineage.swift",
        "iChart/Recognition/ChordInkCanonicalTrajectoryPacket.swift",
        "iChart/Recognition/InkTrajectoryTypes.swift",
        "iChart/Recognition/Learned/ChordInkRasterizer.swift",
        "iChart/Recognition/Learned/ChordInkFeatureSchema.swift",
        "iChart/Services/ChordRecognitionCompendium.swift"
    ] }
}
