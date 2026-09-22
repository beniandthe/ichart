import Foundation

enum RecognitionStudyOutcomeContractError: Error, Equatable {
    case fixedValueMismatch(field: String, expected: String, actual: String)
    case invalidPromptID(String)
    case invalidCanonicalChord(String)
    case invalidCandidateText(String)
    case invalidBaseOutcome(String)
    case invalidAdaptedOutcome(String)
    case invalidCaptureBinding(String)
    case invalidTimestamp(Int64)
}

enum RecognitionStudyOutcomeArtifactKind: String, Encodable, Sendable {
    case localEngineeringSemanticOutcomeV1 =
        "local-engineering-semantic-outcome-v1"
}

/// This value is intentionally stronger than a comment: every decoded outcome
/// must carry it. A prompted chord and a writer self-report are not consent,
/// provenance, independent ground truth, or corpus adjudication.
enum RecognitionStudyOutcomeDataUse: String, Encodable, Sendable {
    case localEngineeringOnlyNotCorpusEligibleV1 =
        "local-engineering-only-not-corpus-eligible-v1"
}

enum RecognitionStudyOutcomeEvidenceStatus: String, Encodable, Sendable {
    case notEstablished = "not-established"
}

enum RecognitionStudyWriterConfirmationState: String, Encodable, Sendable {
    /// The writer reports that the visible ink was an attempt at the prompt.
    /// This is not an independently adjudicated chord label.
    case asPrompted = "as-prompted"
    case executionError = "execution-error"
    case humanAmbiguous = "human-ambiguous"
    /// The capture cannot support a recognition comparison because the study
    /// flow was interrupted before its exact recognizer observation was
    /// durably committed. The trajectory remains available for local
    /// diagnostics, but this state is never model supervision or accuracy
    /// evidence.
    case technicalFailure = "technical-failure"
}

enum RecognitionStudyBaseDisposition: String, Encodable, Sendable {
    case accepted
    case review
    case noRead = "no-read"
    case notRun = "not-run"
}

enum RecognitionStudyAdaptationState: String, Encodable, Sendable {
    case disabledForStudy = "disabled-for-study"
}

enum RecognitionStudyAdaptedDisposition: String, Encodable, Sendable {
    case notRun = "not-run"
}

struct RecognitionStudyCanonicalChord: Codable, Hashable, Sendable {
    let rawValue: String

    init(_ value: String) throws {
        guard let notation = try? ChordNotation.parseCanonical(value),
              notation.canonicalDisplay == value else {
            throw RecognitionStudyOutcomeContractError
                .invalidCanonicalChord(value)
        }
        rawValue = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Bounded, normalized recognizer text. It preserves an invalid raw candidate
/// without quietly repairing it into the chord grammar.
struct RecognitionStudyCandidateText: Codable, Hashable, Sendable {
    static let maximumUTF8ByteCount = 256

    let rawValue: String

    init(_ value: String) throws {
        let normalized = value.precomposedStringWithCanonicalMapping
        guard !value.isEmpty,
              value == normalized,
              value.utf8.count <= Self.maximumUTF8ByteCount,
              !value.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0)
              }) else {
            throw RecognitionStudyOutcomeContractError
                .invalidCandidateText(value)
        }
        rawValue = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct RecognitionStudyPromptOutcome:
    Encodable,
    Equatable,
    Sendable
{
    let promptID: RecognitionStudyPrintableASCII
    let intendedChord: RecognitionStudyCanonicalChord
    let writerConfirmationState: RecognitionStudyWriterConfirmationState

    init(
        promptID: String,
        intendedChord: String,
        writerConfirmationState: RecognitionStudyWriterConfirmationState
    ) throws {
        let identifier = try RecognitionStudyPrintableASCII(
            promptID,
            maximumUTF8ByteCount: 64
        )
        guard Self.isCanonicalPromptID(identifier.rawValue) else {
            throw RecognitionStudyOutcomeContractError.invalidPromptID(promptID)
        }
        self.promptID = identifier
        self.intendedChord = try RecognitionStudyCanonicalChord(intendedChord)
        self.writerConfirmationState = writerConfirmationState
    }

    fileprivate init(wire: RecognitionStudyOutcomeWire.PromptOutcome) throws {
        promptID = wire.promptID
        guard Self.isCanonicalPromptID(promptID.rawValue) else {
            throw RecognitionStudyOutcomeContractError
                .invalidPromptID(promptID.rawValue)
        }
        intendedChord = wire.intendedChord
        writerConfirmationState = try RecognitionStudyOutcomeWireDecoding
            .rawValue(
                RecognitionStudyWriterConfirmationState.self,
                from: wire.writerConfirmationState,
                field: "promptOutcome.writerConfirmationState"
            )
    }

    private static func isCanonicalPromptID(_ value: String) -> Bool {
        guard let first = value.unicodeScalars.first,
              let last = value.unicodeScalars.last,
              isLowercaseASCIIAlphanumeric(first),
              isLowercaseASCIIAlphanumeric(last) else {
            return false
        }
        var previousWasHyphen = false
        for scalar in value.unicodeScalars {
            if scalar.value == 45 {
                guard !previousWasHyphen else { return false }
                previousWasHyphen = true
                continue
            }
            guard isLowercaseASCIIAlphanumeric(scalar) else { return false }
            previousWasHyphen = false
        }
        return true
    }

    private static func isLowercaseASCIIAlphanumeric(
        _ scalar: Unicode.Scalar
    ) -> Bool {
        (48...57).contains(scalar.value) || (97...122).contains(scalar.value)
    }
}

struct RecognitionStudyBaseRecognizerOutcome:
    Encodable,
    Equatable,
    Sendable
{
    let recognizerID: RecognitionStudyPrintableASCII
    let recognizerVersion: RecognitionStudyPrintableASCII
    let disposition: RecognitionStudyBaseDisposition
    let candidate: RecognitionStudyCandidateText?
    /// Present only when the exact raw candidate is already in the strict
    /// grammar. No alias repair, fuzzy normalization, or prompt-assisted parse
    /// is permitted here.
    let canonicalCandidate: RecognitionStudyCanonicalChord?

    init(
        recognizerID: String,
        recognizerVersion: String,
        disposition: RecognitionStudyBaseDisposition,
        candidate: String?
    ) throws {
        self.recognizerID = try RecognitionStudyPrintableASCII(
            recognizerID,
            maximumUTF8ByteCount: 64
        )
        self.recognizerVersion = try RecognitionStudyPrintableASCII(
            recognizerVersion,
            maximumUTF8ByteCount: 64
        )
        self.disposition = disposition
        self.candidate = try candidate.map(RecognitionStudyCandidateText.init)
        canonicalCandidate = try candidate.flatMap { value in
            guard (try? ChordNotation.parseCanonical(value)) != nil else {
                return nil
            }
            return try RecognitionStudyCanonicalChord(value)
        }
        try validateContract()
    }

    fileprivate init(
        wire: RecognitionStudyOutcomeWire.BaseRecognizerOutcome
    ) throws {
        recognizerID = wire.recognizerID
        recognizerVersion = wire.recognizerVersion
        disposition = try RecognitionStudyOutcomeWireDecoding.rawValue(
            RecognitionStudyBaseDisposition.self,
            from: wire.disposition,
            field: "baseRecognizerOutcome.disposition"
        )
        candidate = wire.candidate
        canonicalCandidate = wire.canonicalCandidate
        try validateContract()
    }

    func validateContract() throws {
        try recognizerID.require(maximumUTF8ByteCount: 64)
        try recognizerVersion.require(maximumUTF8ByteCount: 64)
        if let canonicalCandidate {
            guard candidate?.rawValue == canonicalCandidate.rawValue else {
                throw RecognitionStudyOutcomeContractError.invalidBaseOutcome(
                    "canonicalCandidate must exactly equal candidate"
                )
            }
        }
        switch disposition {
        case .accepted:
            guard candidate != nil, canonicalCandidate != nil else {
                throw RecognitionStudyOutcomeContractError.invalidBaseOutcome(
                    "accepted requires a strict canonical candidate"
                )
            }
        case .review:
            break
        case .noRead, .notRun:
            guard candidate == nil, canonicalCandidate == nil else {
                throw RecognitionStudyOutcomeContractError.invalidBaseOutcome(
                    "no-read and not-run must not carry a candidate"
                )
            }
        }
    }
}

struct RecognitionStudyAdaptedRecognizerOutcome:
    Encodable,
    Equatable,
    Sendable
{
    let adaptationState: RecognitionStudyAdaptationState
    let correctionMemoryState: RecognitionStudyAdaptationState
    let disposition: RecognitionStudyAdaptedDisposition
    let candidate: RecognitionStudyCandidateText?
    let canonicalCandidate: RecognitionStudyCanonicalChord?

    static let disabled = Self(
        adaptationState: .disabledForStudy,
        correctionMemoryState: .disabledForStudy,
        disposition: .notRun,
        candidate: nil,
        canonicalCandidate: nil
    )

    fileprivate init(
        adaptationState: RecognitionStudyAdaptationState,
        correctionMemoryState: RecognitionStudyAdaptationState,
        disposition: RecognitionStudyAdaptedDisposition,
        candidate: RecognitionStudyCandidateText?,
        canonicalCandidate: RecognitionStudyCanonicalChord?
    ) {
        self.adaptationState = adaptationState
        self.correctionMemoryState = correctionMemoryState
        self.disposition = disposition
        self.candidate = candidate
        self.canonicalCandidate = canonicalCandidate
    }

    fileprivate init(
        wire: RecognitionStudyOutcomeWire.AdaptedRecognizerOutcome
    ) throws {
        adaptationState = try RecognitionStudyOutcomeWireDecoding.rawValue(
            RecognitionStudyAdaptationState.self,
            from: wire.adaptationState,
            field: "adaptedRecognizerOutcome.adaptationState"
        )
        correctionMemoryState = try RecognitionStudyOutcomeWireDecoding.rawValue(
            RecognitionStudyAdaptationState.self,
            from: wire.correctionMemoryState,
            field: "adaptedRecognizerOutcome.correctionMemoryState"
        )
        disposition = try RecognitionStudyOutcomeWireDecoding.rawValue(
            RecognitionStudyAdaptedDisposition.self,
            from: wire.disposition,
            field: "adaptedRecognizerOutcome.disposition"
        )
        candidate = wire.candidate
        canonicalCandidate = wire.canonicalCandidate
        try validateContract()
    }

    func validateContract() throws {
        guard self == .disabled else {
            throw RecognitionStudyOutcomeContractError.invalidAdaptedOutcome(
                "study adaptation and correction memory must remain disabled"
            )
        }
    }
}

struct RecognitionStudySemanticOutcomeArtifact:
    RecognitionStudyCanonicalJSONDocument,
    Equatable,
    Sendable
{
    static let currentSchemaVersion =
        "recognition-study-semantic-outcome-v1"
    static let maximumCanonicalJSONByteCount = 64 * 1024

    let schemaVersion: RecognitionStudyPrintableASCII
    let artifactKind: RecognitionStudyOutcomeArtifactKind
    let dataUse: RecognitionStudyOutcomeDataUse
    let consentProvenanceStatus: RecognitionStudyOutcomeEvidenceStatus
    let corpusAdjudicationStatus: RecognitionStudyOutcomeEvidenceStatus
    let localSessionID: RecognitionStudyCanonicalUUID
    let localCaptureID: RecognitionStudyCanonicalUUID
    let authorizationID: RecognitionStudyCanonicalUUID
    let trajectoryPacketSHA256: RecognitionStudySHA256
    let captureEnvelopeSHA256: RecognitionStudySHA256
    let promptOutcome: RecognitionStudyPromptOutcome
    let baseRecognizerOutcome: RecognitionStudyBaseRecognizerOutcome
    let adaptedRecognizerOutcome: RecognitionStudyAdaptedRecognizerOutcome
    let clientRecordedAtUnixMilliseconds: Int64

    init(
        packet: ChordInkCanonicalTrajectoryPacket,
        envelope: RecognitionStudyCaptureEnvelope,
        promptID: String,
        intendedChord: String,
        writerConfirmationState: RecognitionStudyWriterConfirmationState,
        baseRecognizerOutcome: RecognitionStudyBaseRecognizerOutcome,
        clientRecordedAtUnixMilliseconds: Int64
    ) throws {
        try envelope.validateContract()
        try envelope.trajectoryDescriptor.validateBinding(to: packet)
        guard envelope.authorizationBinding.kind == .localEngineeringDryRunV1,
              envelope.authorizationBinding.authorityArtifactSHA256 == nil else {
            throw RecognitionStudyOutcomeContractError.invalidCaptureBinding(
                "only a local engineering capture may receive a local outcome"
            )
        }
        guard clientRecordedAtUnixMilliseconds >= 0 else {
            throw RecognitionStudyOutcomeContractError
                .invalidTimestamp(clientRecordedAtUnixMilliseconds)
        }

        let packetData = try packet.canonicalData()
        let envelopeData = try envelope.canonicalData()
        schemaVersion = try RecognitionStudyPrintableASCII(
            Self.currentSchemaVersion,
            maximumUTF8ByteCount: 64
        )
        artifactKind = .localEngineeringSemanticOutcomeV1
        dataUse = .localEngineeringOnlyNotCorpusEligibleV1
        consentProvenanceStatus = .notEstablished
        corpusAdjudicationStatus = .notEstablished
        localSessionID = envelope.localSessionID
        localCaptureID = envelope.localCaptureID
        authorizationID = envelope.authorizationBinding.authorizationID
        trajectoryPacketSHA256 = RecognitionStudySHA256(digesting: packetData)
        captureEnvelopeSHA256 = RecognitionStudySHA256(digesting: envelopeData)
        promptOutcome = try RecognitionStudyPromptOutcome(
            promptID: promptID,
            intendedChord: intendedChord,
            writerConfirmationState: writerConfirmationState
        )
        self.baseRecognizerOutcome = baseRecognizerOutcome
        adaptedRecognizerOutcome = .disabled
        self.clientRecordedAtUnixMilliseconds =
            clientRecordedAtUnixMilliseconds
        try validateContract()
    }

    static func decodeCanonicalData(_ data: Data) throws -> Self {
        try RecognitionStudyStrictCanonicalJSON.decode(
            data,
            wireType: RecognitionStudyOutcomeWire.Artifact.self,
            construct: { try Self(wire: $0) }
        )
    }

    fileprivate init(wire: RecognitionStudyOutcomeWire.Artifact) throws {
        schemaVersion = wire.schemaVersion
        artifactKind = try RecognitionStudyOutcomeWireDecoding.rawValue(
            RecognitionStudyOutcomeArtifactKind.self,
            from: wire.artifactKind,
            field: "artifactKind"
        )
        dataUse = try RecognitionStudyOutcomeWireDecoding.rawValue(
            RecognitionStudyOutcomeDataUse.self,
            from: wire.dataUse,
            field: "dataUse"
        )
        consentProvenanceStatus = try RecognitionStudyOutcomeWireDecoding
            .rawValue(
                RecognitionStudyOutcomeEvidenceStatus.self,
                from: wire.consentProvenanceStatus,
                field: "consentProvenanceStatus"
            )
        corpusAdjudicationStatus = try RecognitionStudyOutcomeWireDecoding
            .rawValue(
                RecognitionStudyOutcomeEvidenceStatus.self,
                from: wire.corpusAdjudicationStatus,
                field: "corpusAdjudicationStatus"
            )
        localSessionID = wire.localSessionID
        localCaptureID = wire.localCaptureID
        authorizationID = wire.authorizationID
        trajectoryPacketSHA256 = wire.trajectoryPacketSHA256
        captureEnvelopeSHA256 = wire.captureEnvelopeSHA256
        promptOutcome = try RecognitionStudyPromptOutcome(
            wire: wire.promptOutcome
        )
        baseRecognizerOutcome = try RecognitionStudyBaseRecognizerOutcome(
            wire: wire.baseRecognizerOutcome
        )
        adaptedRecognizerOutcome = try RecognitionStudyAdaptedRecognizerOutcome(
            wire: wire.adaptedRecognizerOutcome
        )
        clientRecordedAtUnixMilliseconds =
            wire.clientRecordedAtUnixMilliseconds
        try validateContract()
    }

    func validateContract() throws {
        try requireFixed(
            schemaVersion.rawValue,
            expected: Self.currentSchemaVersion,
            field: "schemaVersion"
        )
        try requireFixed(
            artifactKind.rawValue,
            expected: RecognitionStudyOutcomeArtifactKind
                .localEngineeringSemanticOutcomeV1.rawValue,
            field: "artifactKind"
        )
        try requireFixed(
            dataUse.rawValue,
            expected: RecognitionStudyOutcomeDataUse
                .localEngineeringOnlyNotCorpusEligibleV1.rawValue,
            field: "dataUse"
        )
        try requireFixed(
            consentProvenanceStatus.rawValue,
            expected: RecognitionStudyOutcomeEvidenceStatus
                .notEstablished.rawValue,
            field: "consentProvenanceStatus"
        )
        try requireFixed(
            corpusAdjudicationStatus.rawValue,
            expected: RecognitionStudyOutcomeEvidenceStatus
                .notEstablished.rawValue,
            field: "corpusAdjudicationStatus"
        )
        guard clientRecordedAtUnixMilliseconds >= 0 else {
            throw RecognitionStudyOutcomeContractError
                .invalidTimestamp(clientRecordedAtUnixMilliseconds)
        }
        try baseRecognizerOutcome.validateContract()
        try adaptedRecognizerOutcome.validateContract()
    }

    func validateBindings(
        packet: ChordInkCanonicalTrajectoryPacket,
        envelope: RecognitionStudyCaptureEnvelope
    ) throws {
        try envelope.validateContract()
        try envelope.trajectoryDescriptor.validateBinding(to: packet)
        guard localSessionID == envelope.localSessionID,
              localCaptureID == envelope.localCaptureID,
              authorizationID
                == envelope.authorizationBinding.authorizationID,
              trajectoryPacketSHA256
                == RecognitionStudySHA256(
                    digesting: try packet.canonicalData()
                ),
              captureEnvelopeSHA256
                == RecognitionStudySHA256(
                    digesting: try envelope.canonicalData()
                ) else {
            throw RecognitionStudyOutcomeContractError.invalidCaptureBinding(
                "outcome identifiers or digests do not match the capture"
            )
        }
    }

    private func requireFixed(
        _ actual: String,
        expected: String,
        field: String
    ) throws {
        guard actual == expected else {
            throw RecognitionStudyOutcomeContractError.fixedValueMismatch(
                field: field,
                expected: expected,
                actual: actual
            )
        }
    }
}

fileprivate enum RecognitionStudyOutcomeWire {
    struct PromptOutcome: Decodable {
        let promptID: RecognitionStudyPrintableASCII
        let intendedChord: RecognitionStudyCanonicalChord
        let writerConfirmationState: String
    }

    struct BaseRecognizerOutcome: Decodable {
        let recognizerID: RecognitionStudyPrintableASCII
        let recognizerVersion: RecognitionStudyPrintableASCII
        let disposition: String
        let candidate: RecognitionStudyCandidateText?
        let canonicalCandidate: RecognitionStudyCanonicalChord?
    }

    struct AdaptedRecognizerOutcome: Decodable {
        let adaptationState: String
        let correctionMemoryState: String
        let disposition: String
        let candidate: RecognitionStudyCandidateText?
        let canonicalCandidate: RecognitionStudyCanonicalChord?
    }

    struct Artifact: Decodable {
        let schemaVersion: RecognitionStudyPrintableASCII
        let artifactKind: String
        let dataUse: String
        let consentProvenanceStatus: String
        let corpusAdjudicationStatus: String
        let localSessionID: RecognitionStudyCanonicalUUID
        let localCaptureID: RecognitionStudyCanonicalUUID
        let authorizationID: RecognitionStudyCanonicalUUID
        let trajectoryPacketSHA256: RecognitionStudySHA256
        let captureEnvelopeSHA256: RecognitionStudySHA256
        let promptOutcome: PromptOutcome
        let baseRecognizerOutcome: BaseRecognizerOutcome
        let adaptedRecognizerOutcome: AdaptedRecognizerOutcome
        let clientRecordedAtUnixMilliseconds: Int64
    }
}

private enum RecognitionStudyOutcomeWireDecoding {
    static func rawValue<Value>(
        _ type: Value.Type,
        from rawValue: String,
        field: String
    ) throws -> Value where Value: RawRepresentable, Value.RawValue == String {
        guard let value = Value(rawValue: rawValue) else {
            throw RecognitionStudyOutcomeContractError.fixedValueMismatch(
                field: field,
                expected: "a supported value",
                actual: rawValue
            )
        }
        return value
    }
}
