import CryptoKit
import Foundation

enum ChordInkUserCorrectionMemoryPolicy {
    static let suggestionLimit = 3
    static let maximumAutomaticRewriteFailures = 2
    static let extremelyCloseRaceGap = ChordInkRecognitionPolicy.closeRaceConfidenceGap / 2

    static func inkDigest(for drawingData: Data) -> String {
        #if canImport(PencilKit)
        if let strokes = try? PencilKitInkAdapter.inkStrokes(from: drawingData),
           !strokes.isEmpty,
           let canonicalData = canonicalRecognitionData(for: strokes) {
            return "semantic-v1:\(sha256Hex(of: canonicalData))"
        }
        #endif

        return "archive-v1:\(sha256Hex(of: drawingData))"
    }

    /// Existing installs stored an unversioned SHA-256 of PencilKit's archive.
    /// Keep accepting that digest when the bytes are still identical, while new
    /// rules use recognition-semantic geometry that survives harmless PencilKit
    /// metadata reserialization.
    static func matchingInkDigests(for drawingData: Data) -> Set<String> {
        [inkDigest(for: drawingData), sha256Hex(of: drawingData)]
    }

    private static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    #if canImport(PencilKit)
    private static func canonicalRecognitionData(for strokes: [InkStroke]) -> Data? {
        var fields = ["chord-ink-semantic-v1", "strokes", String(strokes.count)]
        fields.reserveCapacity(
            3 + strokes.reduce(0) { $0 + 3 + ($1.points.count * 4) }
        )

        for stroke in strokes {
            fields.append("stroke")
            fields.append(String(stroke.points.count))
            fields.append(quantizedString(stroke.creationTimeOffset) ?? "nil")

            for point in stroke.points {
                guard let x = quantizedString(point.x),
                      let y = quantizedString(point.y) else {
                    return nil
                }

                fields.append(x)
                fields.append(y)
                fields.append(quantizedString(point.timeOffset) ?? "nil")
                fields.append("point")
            }
        }

        return Data(fields.joined(separator: "|").utf8)
    }

    private static func quantizedString(_ value: Double?) -> String? {
        guard let value,
              value.isFinite,
              abs(value) <= Double(Int64.max) / 1_000_000 else {
            return nil
        }

        return String(Int64((value * 1_000_000).rounded()))
    }
    #endif

    static func candidateSignature(from candidateTexts: [String]) -> [String] {
        candidateTexts.reduce(into: [String]()) { signature, candidateText in
            guard signature.count < suggestionLimit,
                  let match = ChordRecognitionCompendium.match(candidateText),
                  !signature.contains(match.displayText) else {
                return
            }

            signature.append(match.displayText)
        }
    }

    static func canUseRejectedTrustedCandidateSignature(_ signature: [String]) -> Bool {
        // A single-candidate deletion only proves that exact ink was wrong in that local moment.
        // Multi-candidate signatures describe a real recognizer race and are safe to block broadly.
        signature.count > 1
    }

    static func isCompleteFailure(
        result: ChordInkRecognitionResult,
        decision: ChordInkRecognitionDecision,
        candidateTexts: [String]
    ) -> Bool {
        decision.action == .confirm
            && decision.acceptedText == nil
            && result.match == nil
            && candidateSignature(from: candidateTexts).isEmpty
    }

    static func isExtremelyClose(_ decision: ChordInkRecognitionDecision) -> Bool {
        guard decision.isCloseRace,
              let confidenceGap = decision.confidenceGap else {
            return false
        }

        return confidenceGap <= extremelyCloseRaceGap
    }
}

struct ChordInkUserCorrectionRule: Codable, Equatable, Identifiable {
    var id: UUID
    var candidateSignature: [String]
    var acceptedText: String
    var competingCandidateTexts: [String]
    var inkDigests: [String]
    var sourceConfidenceGap: Double?
    var createdAt: Date
    var updatedAt: Date
    var useCount: Int
}

struct ChordInkUserCorrectionExclusion: Codable, Equatable, Identifiable {
    var id: UUID
    var candidateSignature: [String]
    var rejectedCandidateTexts: [String]
    var acceptedText: String
    var inkDigests: [String]
    var createdAt: Date
    var updatedAt: Date
    var count: Int
}

struct ChordInkRejectedTrustedCandidateRule: Codable, Equatable, Identifiable {
    var id: UUID
    var acceptedText: String
    var inkDigests: [String]
    var candidateSignatures: [[String]]? = nil
    var createdAt: Date
    var updatedAt: Date
    var count: Int
}

struct ChordInkUserCorrectionMemory: Codable, Equatable {
    var correctionRules: [ChordInkUserCorrectionRule] = []
    var suggestionExclusions: [ChordInkUserCorrectionExclusion] = []
    var rejectedTrustedCandidateRules: [ChordInkRejectedTrustedCandidateRule] = []

    private enum CodingKeys: String, CodingKey {
        case correctionRules
        case suggestionExclusions
        case explicitRejectedTrustedCandidateRules
    }

    init(
        correctionRules: [ChordInkUserCorrectionRule] = [],
        suggestionExclusions: [ChordInkUserCorrectionExclusion] = [],
        rejectedTrustedCandidateRules: [ChordInkRejectedTrustedCandidateRule] = []
    ) {
        self.correctionRules = correctionRules
        self.suggestionExclusions = suggestionExclusions
        self.rejectedTrustedCandidateRules = rejectedTrustedCandidateRules
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        correctionRules = try container.decodeIfPresent(
            [ChordInkUserCorrectionRule].self,
            forKey: .correctionRules
        ) ?? []
        suggestionExclusions = try container.decodeIfPresent(
            [ChordInkUserCorrectionExclusion].self,
            forKey: .suggestionExclusions
        ) ?? []
        rejectedTrustedCandidateRules = try container.decodeIfPresent(
            [ChordInkRejectedTrustedCandidateRule].self,
            forKey: .explicitRejectedTrustedCandidateRules
        ) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(correctionRules, forKey: .correctionRules)
        try container.encode(suggestionExclusions, forKey: .suggestionExclusions)
        try container.encode(
            rejectedTrustedCandidateRules,
            forKey: .explicitRejectedTrustedCandidateRules
        )
    }

    func preferredCandidate(
        for candidateTexts: [String],
        drawingData: Data,
        decision: ChordInkRecognitionDecision
    ) -> String? {
        guard decision.action == .confirm,
              decision.isCloseRace,
              !ChordInkUserCorrectionMemoryPolicy.isExtremelyClose(decision) else {
            return nil
        }

        let signature = ChordInkUserCorrectionMemoryPolicy.candidateSignature(from: candidateTexts)
        guard !signature.isEmpty,
              !hasSuggestionExclusion(for: signature) else {
            return nil
        }

        let applicableRules = correctionRules.filter {
            $0.candidateSignature == signature && signature.contains($0.acceptedText)
        }
        guard !applicableRules.isEmpty else {
            return nil
        }

        let matchingDigests = ChordInkUserCorrectionMemoryPolicy.matchingInkDigests(
            for: drawingData
        )
        return applicableRules
            .filter { rule in
                rule.inkDigests.contains(where: matchingDigests.contains)
            }
            .sorted { lhs, rhs in
                if lhs.useCount != rhs.useCount {
                    return lhs.useCount > rhs.useCount
                }

                return lhs.updatedAt > rhs.updatedAt
            }
            .first?
            .acceptedText
    }

    func shouldBlockTrustedCandidate(
        acceptedText: String,
        drawingData: Data,
        candidateTexts: [String] = []
    ) -> Bool {
        guard let match = ChordRecognitionCompendium.match(acceptedText) else {
            return false
        }

        let candidateSignature = ChordInkUserCorrectionMemoryPolicy.candidateSignature(from: candidateTexts)
        let applicableRules = rejectedTrustedCandidateRules.filter {
            $0.acceptedText == match.displayText
        }
        guard !applicableRules.isEmpty else {
            return false
        }

        let matchingDigests = ChordInkUserCorrectionMemoryPolicy.matchingInkDigests(
            for: drawingData
        )
        return applicableRules.contains { rule in
            if rule.inkDigests.contains(where: matchingDigests.contains) {
                return true
            }

            guard ChordInkUserCorrectionMemoryPolicy.canUseRejectedTrustedCandidateSignature(candidateSignature) else {
                return false
            }

            return rule.candidateSignatures?.contains(candidateSignature) == true
        }
    }

    @discardableResult
    mutating func recordConfirmedSuggestion(
        acceptedText: String,
        drawingData: Data,
        candidateTexts: [String],
        decision: ChordInkRecognitionDecision,
        now: Date = .now
    ) -> Bool {
        guard decision.isCloseRace,
              !ChordInkUserCorrectionMemoryPolicy.isExtremelyClose(decision),
              let match = ChordRecognitionCompendium.match(acceptedText) else {
            return false
        }

        let signature = ChordInkUserCorrectionMemoryPolicy.candidateSignature(from: candidateTexts)
        guard signature.contains(match.displayText),
              !hasSuggestionExclusion(for: signature) else {
            return false
        }

        let digest = ChordInkUserCorrectionMemoryPolicy.inkDigest(for: drawingData)
        let competingTexts = signature.filter { $0 != match.displayText }

        if let index = correctionRules.firstIndex(where: { $0.candidateSignature == signature }) {
            correctionRules[index].acceptedText = match.displayText
            correctionRules[index].competingCandidateTexts = competingTexts
            correctionRules[index].sourceConfidenceGap = decision.confidenceGap
            correctionRules[index].updatedAt = now
            correctionRules[index].useCount += 1
            appendDigest(digest, toRuleAt: index)
        } else {
            correctionRules.append(
                ChordInkUserCorrectionRule(
                    id: UUID(),
                    candidateSignature: signature,
                    acceptedText: match.displayText,
                    competingCandidateTexts: competingTexts,
                    inkDigests: [digest],
                    sourceConfidenceGap: decision.confidenceGap,
                    createdAt: now,
                    updatedAt: now,
                    useCount: 1
                )
            )
        }

        return true
    }

    @discardableResult
    mutating func recordManualCorrection(
        acceptedText: String,
        drawingData: Data,
        candidateTexts: [String],
        now: Date = .now
    ) -> Bool {
        guard let match = ChordRecognitionCompendium.match(acceptedText) else {
            return false
        }

        let signature = ChordInkUserCorrectionMemoryPolicy.candidateSignature(from: candidateTexts)
        guard !signature.isEmpty,
              !signature.contains(match.displayText) else {
            return false
        }

        let digest = ChordInkUserCorrectionMemoryPolicy.inkDigest(for: drawingData)
        if let index = suggestionExclusions.firstIndex(where: { $0.candidateSignature == signature }) {
            suggestionExclusions[index].acceptedText = match.displayText
            suggestionExclusions[index].rejectedCandidateTexts = signature
            suggestionExclusions[index].updatedAt = now
            suggestionExclusions[index].count += 1
            appendDigest(digest, toExclusionAt: index)
        } else {
            suggestionExclusions.append(
                ChordInkUserCorrectionExclusion(
                    id: UUID(),
                    candidateSignature: signature,
                    rejectedCandidateTexts: signature,
                    acceptedText: match.displayText,
                    inkDigests: [digest],
                    createdAt: now,
                    updatedAt: now,
                    count: 1
                )
            )
        }

        correctionRules.removeAll { $0.candidateSignature == signature }
        return true
    }

    /// Records a correction made to a chord that was already rendered from ink.
    /// Unlike deletion, this supplies an explicit wrong-read/right-read pair.
    @discardableResult
    mutating func recordRenderedChordCorrection(
        previousText: String,
        displayedPreviousText: String,
        acceptedText: String,
        drawingData: Data,
        candidateTexts: [String],
        now: Date = .now
    ) -> Bool {
        guard let previousMatch = ChordRecognitionCompendium.match(previousText),
              let displayedPreviousMatch = ChordRecognitionCompendium.match(displayedPreviousText),
              let acceptedMatch = ChordRecognitionCompendium.match(acceptedText),
              previousMatch.displayText == displayedPreviousMatch.displayText,
              previousMatch.displayText != acceptedMatch.displayText else {
            return false
        }

        let signature = ChordInkUserCorrectionMemoryPolicy.candidateSignature(from: candidateTexts)
        var didUpdate = recordRejectedTrustedCandidate(
            acceptedText: previousMatch.displayText,
            drawingData: drawingData,
            candidateSignature: signature,
            now: now
        )

        if signature.contains(acceptedMatch.displayText) {
            didUpdate = recordExplicitCandidateCorrection(
                acceptedText: acceptedMatch.displayText,
                drawingData: drawingData,
                candidateSignature: signature,
                now: now
            ) || didUpdate
        } else {
            didUpdate = recordManualCorrection(
                acceptedText: acceptedMatch.displayText,
                drawingData: drawingData,
                candidateTexts: signature,
                now: now
            ) || didUpdate
        }

        return didUpdate
    }

    @discardableResult
    mutating func recordRejectedTrustedCandidate(
        acceptedText: String,
        drawingData: Data,
        candidateSignature: [String] = [],
        now: Date = .now
    ) -> Bool {
        guard let match = ChordRecognitionCompendium.match(acceptedText) else {
            return false
        }

        let digest = ChordInkUserCorrectionMemoryPolicy.inkDigest(for: drawingData)
        if let index = rejectedTrustedCandidateRules.firstIndex(where: { $0.acceptedText == match.displayText }) {
            rejectedTrustedCandidateRules[index].updatedAt = now
            rejectedTrustedCandidateRules[index].count += 1
            appendDigest(digest, toRejectedTrustedCandidateAt: index)
            if ChordInkUserCorrectionMemoryPolicy.canUseRejectedTrustedCandidateSignature(candidateSignature) {
                appendCandidateSignature(candidateSignature, toRejectedTrustedCandidateAt: index)
            }
        } else {
            let candidateSignatures = ChordInkUserCorrectionMemoryPolicy
                .canUseRejectedTrustedCandidateSignature(candidateSignature)
                ? [candidateSignature]
                : nil
            rejectedTrustedCandidateRules.append(
                ChordInkRejectedTrustedCandidateRule(
                    id: UUID(),
                    acceptedText: match.displayText,
                    inkDigests: [digest],
                    candidateSignatures: candidateSignatures,
                    createdAt: now,
                    updatedAt: now,
                    count: 1
                )
            )
        }

        return true
    }

    mutating func recordRuleApplication(
        acceptedText: String,
        candidateTexts: [String],
        now: Date = .now
    ) {
        let signature = ChordInkUserCorrectionMemoryPolicy.candidateSignature(from: candidateTexts)
        guard let match = ChordRecognitionCompendium.match(acceptedText),
              let index = correctionRules.firstIndex(where: {
                  $0.candidateSignature == signature && $0.acceptedText == match.displayText
              }) else {
            return
        }

        correctionRules[index].useCount += 1
        correctionRules[index].updatedAt = now
    }

    @discardableResult
    private mutating func recordExplicitCandidateCorrection(
        acceptedText: String,
        drawingData: Data,
        candidateSignature: [String],
        now: Date
    ) -> Bool {
        guard candidateSignature.count > 1,
              candidateSignature.contains(acceptedText),
              !hasSuggestionExclusion(for: candidateSignature) else {
            return false
        }

        let digest = ChordInkUserCorrectionMemoryPolicy.inkDigest(for: drawingData)
        let competingTexts = candidateSignature.filter { $0 != acceptedText }

        if let index = correctionRules.firstIndex(where: { $0.candidateSignature == candidateSignature }) {
            correctionRules[index].acceptedText = acceptedText
            correctionRules[index].competingCandidateTexts = competingTexts
            correctionRules[index].sourceConfidenceGap = nil
            correctionRules[index].updatedAt = now
            correctionRules[index].useCount += 1
            appendDigest(digest, toRuleAt: index)
        } else {
            correctionRules.append(
                ChordInkUserCorrectionRule(
                    id: UUID(),
                    candidateSignature: candidateSignature,
                    acceptedText: acceptedText,
                    competingCandidateTexts: competingTexts,
                    inkDigests: [digest],
                    sourceConfidenceGap: nil,
                    createdAt: now,
                    updatedAt: now,
                    useCount: 1
                )
            )
        }

        return true
    }

    private func hasSuggestionExclusion(for signature: [String]) -> Bool {
        suggestionExclusions.contains { $0.candidateSignature == signature }
    }

    private mutating func appendDigest(_ digest: String, toRuleAt index: Int) {
        guard !correctionRules[index].inkDigests.contains(digest) else {
            return
        }

        correctionRules[index].inkDigests.append(digest)
    }

    private mutating func appendDigest(_ digest: String, toExclusionAt index: Int) {
        guard !suggestionExclusions[index].inkDigests.contains(digest) else {
            return
        }

        suggestionExclusions[index].inkDigests.append(digest)
    }

    private mutating func appendDigest(_ digest: String, toRejectedTrustedCandidateAt index: Int) {
        guard !rejectedTrustedCandidateRules[index].inkDigests.contains(digest) else {
            return
        }

        rejectedTrustedCandidateRules[index].inkDigests.append(digest)
    }

    private mutating func appendCandidateSignature(
        _ candidateSignature: [String],
        toRejectedTrustedCandidateAt index: Int
    ) {
        guard !candidateSignature.isEmpty else {
            return
        }

        if rejectedTrustedCandidateRules[index].candidateSignatures == nil {
            rejectedTrustedCandidateRules[index].candidateSignatures = []
        }

        guard rejectedTrustedCandidateRules[index].candidateSignatures?.contains(candidateSignature) == false else {
            return
        }

        rejectedTrustedCandidateRules[index].candidateSignatures?.append(candidateSignature)
    }
}

struct ChordInkAutomaticRewriteFailureKey: Hashable {
    var measureID: UUID
    var targetFractionBucket: Int?

    init(measureID: UUID, targetFraction: Double?) {
        self.measureID = measureID
        self.targetFractionBucket = targetFraction.map { Int(($0 * 100).rounded()) }
    }
}

struct ChordInkAutomaticRewriteFailureTracker: Equatable {
    private var currentKey: ChordInkAutomaticRewriteFailureKey?
    private var currentCount = 0

    mutating func recordFailure(measureID: UUID, targetFraction: Double?) -> Int {
        let key = ChordInkAutomaticRewriteFailureKey(
            measureID: measureID,
            targetFraction: targetFraction
        )

        if currentKey == key {
            currentCount += 1
        } else {
            currentKey = key
            currentCount = 1
        }

        return currentCount
    }

    mutating func reset() {
        currentKey = nil
        currentCount = 0
    }
}

struct ChordInkUserCorrectionMemoryStore {
    let url: URL
    private let fileManager: FileManager

    init(url: URL, fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
    }

    func load() throws -> ChordInkUserCorrectionMemory {
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else {
            return ChordInkUserCorrectionMemory()
        }

        let data = try Data(contentsOf: url)
        return try Self.decoder.decode(ChordInkUserCorrectionMemory.self, from: data)
    }

    func save(_ memory: ChordInkUserCorrectionMemory) throws {
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try Self.encoder.encode(memory)
        try data.write(to: url, options: .atomic)
    }
}

extension ChordInkUserCorrectionMemoryStore {
    static func live(fileManager: FileManager = .default) -> ChordInkUserCorrectionMemoryStore {
        let applicationSupportURL = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.temporaryDirectory

        let baseDirectory = applicationSupportURL.appendingPathComponent("iChart", isDirectory: true)
        return ChordInkUserCorrectionMemoryStore(
            url: baseDirectory.appendingPathComponent("chord-ink-user-correction-memory.json"),
            fileManager: fileManager
        )
    }
}

private extension ChordInkUserCorrectionMemoryStore {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
