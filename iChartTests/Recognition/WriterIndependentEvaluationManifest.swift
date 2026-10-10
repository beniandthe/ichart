import CryptoKit
import Foundation
@testable import iChart

/// Metadata for a consented recognition-study corpus.
///
/// Labels and raw strokes intentionally live outside this manifest. A sealed
/// evaluator can join them by opaque IDs without exposing either to product
/// code or pull-request CI.
struct WriterIndependentEvaluationManifest: Codable, Hashable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var evaluationProtocolVersion: String
    var datasetVersion: String
    /// Versioned registry spanning every cohort plus the legacy/template
    /// denylist. Cohorts may not be validated as unrelated standalone islands.
    var cohortRegistryVersion: String
    var cohortRegistryMerkleRootSHA256: String
    var consentLedgerSnapshotVersion: String
    var consentLedgerMerkleRootSHA256: String
    var samples: [WriterIndependentEvaluationSample]

    init(
        schemaVersion: Int = currentSchemaVersion,
        evaluationProtocolVersion: String = WriterIndependentEvaluationProtocolContract.currentVersion,
        datasetVersion: String,
        cohortRegistryVersion: String,
        cohortRegistryMerkleRootSHA256: String,
        consentLedgerSnapshotVersion: String,
        consentLedgerMerkleRootSHA256: String,
        samples: [WriterIndependentEvaluationSample]
    ) {
        self.schemaVersion = schemaVersion
        self.evaluationProtocolVersion = evaluationProtocolVersion
        self.datasetVersion = datasetVersion
        self.cohortRegistryVersion = cohortRegistryVersion
        self.cohortRegistryMerkleRootSHA256 = cohortRegistryMerkleRootSHA256
        self.consentLedgerSnapshotVersion = consentLedgerSnapshotVersion
        self.consentLedgerMerkleRootSHA256 = consentLedgerMerkleRootSHA256
        self.samples = samples
    }
}

struct WriterIndependentEvaluationSample: Codable, Hashable {
    var sampleID: UUID
    /// Lowercase HMAC-SHA-256 of a random research participant identifier using
    /// a dataset secret. Never an account, email, installation ID, handwriting
    /// digest, or other product identity.
    var writerIDHash: String
    var captureSessionID: UUID
    var sourceKind: WriterIndependentEvaluationSourceKind
    /// Every generated variant retains the source sample's writer and split.
    /// Derived samples are never additional independent observations.
    var parentSampleID: UUID?
    var split: WriterIndependentEvaluationSplit
    var captureProtocolVersion: String
    var chartStyle: ChartLayoutStyle
    var orientation: WriterIndependentEvaluationOrientation
    var pace: WriterIndependentEvaluationPace
    var sizeBucket: WriterIndependentEvaluationSizeBucket
    var handedness: WriterIndependentEvaluationHandedness
    var pencilExperience: WriterIndependentEvaluationPencilExperience
    var constructionVariation: WriterIndependentEvaluationConstructionVariation
    /// Coarse study bucket such as `oldest-supported`, not a device identifier.
    var deviceClass: String
    var appBuild: String
    var pipelineVersion: String
    /// SHA-256 of the isolated, normalized stroke payload used by the evaluator.
    var strokePayloadSHA256: String
    /// Output of the versioned exact/near-duplicate and legacy-leakage scan.
    /// Derivatives retain their source cluster and never create a new unit.
    var geometryLeakageClusterID: UUID
    var leakageCheckVersion: String
    /// Opaque key into the evaluator's separately protected ground-truth store.
    var labelRecordID: UUID
    /// Opaque key into the separately protected, revocable consent ledger.
    var consentRecordID: UUID
}

enum WriterIndependentResearchConsentScope: String, Codable, Hashable {
    case chordRecognitionEvaluation
}

struct WriterIndependentResearchConsentRecord: Codable, Hashable {
    var consentRecordID: UUID
    var writerIDHash: String
    /// Registry-scoped HMAC that remains stable across dataset versions. This is
    /// protected provenance, never an account identifier or receipt field.
    var personLinkageHMACSHA256: String
    var isActive: Bool
    var researchScopes: [WriterIndependentResearchConsentScope]
    var datasetVersions: [String]
}

enum WriterIndependentCohortRegistryEligibility: String, Codable, Hashable {
    case evaluationEligible
    case legacyOrTemplateDenylisted
    case quarantined
}

/// Critical identity and leakage assignments are repeated in this protected
/// registry so a manifest author cannot mint a new writer, split, or cluster.
struct WriterIndependentCohortRegistryRecord: Codable, Hashable {
    var sampleID: UUID
    var datasetVersion: String
    var strokePayloadSHA256: String
    var writerIDHash: String
    /// Service-stable protected linkage used to enforce writer-disjoint roles
    /// across every dataset represented by the registry.
    var personLinkageHMACSHA256: String
    var captureSessionID: UUID
    var sourceKind: WriterIndependentEvaluationSourceKind
    var parentSampleID: UUID?
    var split: WriterIndependentEvaluationSplit
    var captureProtocolVersion: String
    var chartStyle: ChartLayoutStyle
    var orientation: WriterIndependentEvaluationOrientation
    var pace: WriterIndependentEvaluationPace
    var sizeBucket: WriterIndependentEvaluationSizeBucket
    var handedness: WriterIndependentEvaluationHandedness
    var pencilExperience: WriterIndependentEvaluationPencilExperience
    var constructionVariation: WriterIndependentEvaluationConstructionVariation
    var deviceClass: String
    var appBuild: String
    var pipelineVersion: String
    var labelRecordID: UUID
    var consentRecordID: UUID
    var geometryLeakageClusterID: UUID
    var leakageCheckVersion: String
    var eligibility: WriterIndependentCohortRegistryEligibility
}

/// Authenticated, content-free provenance supplied by the collection service,
/// never authored by the manifest producer or recognition implementation.
struct WriterIndependentProvenanceSnapshotPayload: Codable, Hashable {
    var cohortRegistryVersion: String
    var cohortRegistryMerkleRootSHA256: String
    var cohortRegistryEpoch: UInt64
    var consentLedgerSnapshotVersion: String
    var consentLedgerMerkleRootSHA256: String
    var consentLedgerEpoch: UInt64
    var issuedAtUnixSeconds: Int64
    var expiresAtUnixSeconds: Int64
    var consentRecords: [WriterIndependentResearchConsentRecord]
    var cohortRecords: [WriterIndependentCohortRegistryRecord]

    func canonicalData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    func computedConsentLedgerMerkleRootSHA256() throws -> String {
        try WriterIndependentMerkleCommitment.root(
            records: consentRecords,
            sortedBy: { $0.consentRecordID.uuidString }
        )
    }

    func computedCohortRegistryMerkleRootSHA256() throws -> String {
        try WriterIndependentMerkleCommitment.root(
            records: cohortRecords,
            sortedBy: { "\($0.strokePayloadSHA256.lowercased())|\($0.sampleID.uuidString)" }
        )
    }
}

struct SignedWriterIndependentProvenanceSnapshot: Codable, Hashable {
    var payload: WriterIndependentProvenanceSnapshotPayload
    var signingKeyID: String
    var signatureBase64: String
}

/// Current checkpoint supplied out-of-band by the consent/registry service.
/// Exact roots plus monotonic epochs and expiry prevent replay of an older,
/// still-valid signature after withdrawal or a denylist update.
struct WriterIndependentProvenanceExpectation: Hashable {
    var cohortRegistryVersion: String
    var cohortRegistryMerkleRootSHA256: String
    var minimumCohortRegistryEpoch: UInt64
    var consentLedgerSnapshotVersion: String
    var consentLedgerMerkleRootSHA256: String
    var minimumConsentLedgerEpoch: UInt64
    var validationUnixSeconds: Int64
}

enum WriterIndependentGroundTruthLegibility: String, Codable, Hashable {
    case legibleValid
    case humanAmbiguousOrNegative
}

/// Protected label metadata. Chord text never appears here: labels and reader
/// transcriptions are separately salted content commitments.
struct WriterIndependentGroundTruthRecord: Codable, Hashable {
    var sampleID: UUID
    var labelRecordID: UUID
    var datasetVersion: String
    var isEvaluationEligible: Bool
    var promptedIntentCommitmentSHA256: String
    var writerConfirmedIntentCommitmentSHA256: String
    var firstReaderHMACSHA256: String
    var firstReaderLabelCommitmentSHA256: String
    var secondReaderHMACSHA256: String
    var secondReaderLabelCommitmentSHA256: String
    var adjudicatorHMACSHA256: String?
    var adjudicatedLabelCommitmentSHA256: String?
    var finalLabelCommitmentSHA256: String
    var legibility: WriterIndependentGroundTruthLegibility
    var isFrozen: Bool
}

struct WriterIndependentGroundTruthRegistryPayload: Codable, Hashable {
    var registryVersion: String
    var merkleRootSHA256: String
    var registryEpoch: UInt64
    var issuedAtUnixSeconds: Int64
    var expiresAtUnixSeconds: Int64
    var records: [WriterIndependentGroundTruthRecord]

    func canonicalData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    func computedMerkleRootSHA256() throws -> String {
        try WriterIndependentMerkleCommitment.root(
            records: records,
            sortedBy: { "\($0.datasetVersion)|\($0.sampleID.uuidString)|\($0.labelRecordID.uuidString)" }
        )
    }
}

struct SignedWriterIndependentGroundTruthRegistry: Codable, Hashable {
    var payload: WriterIndependentGroundTruthRegistryPayload
    var signingKeyID: String
    var signatureBase64: String
}

struct WriterIndependentGroundTruthExpectation: Hashable {
    var registryVersion: String
    var merkleRootSHA256: String
    var minimumRegistryEpoch: UInt64
    var validationUnixSeconds: Int64
}

struct WriterIndependentGroundTruthValidationIssue: Hashable {
    enum Code: String, Hashable {
        case invalidSignature
        case contentCommitmentMismatch
        case staleRegistry
        case duplicateRecord
        case completenessMismatch
        case sampleIdentityMismatch
        case invalidCommitment
        case readersNotIndependent
        case adjudicationRequired
        case invalidAdjudication
        case labelNotFrozen
    }

    var code: Code
    var sampleIDs: [UUID]
    var detail: String
}

enum WriterIndependentGroundTruthRegistryValidator {
    static func issues(
        in registry: SignedWriterIndependentGroundTruthRegistry,
        for manifest: WriterIndependentEvaluationManifest,
        trustedSigningPublicKeysByID: [String: Data],
        expected: WriterIndependentGroundTruthExpectation
    ) -> [WriterIndependentGroundTruthValidationIssue] {
        guard signatureIsValid(registry, trustedPublicKeysByID: trustedSigningPublicKeysByID) else {
            return [issue(.invalidSignature, detail: "Ground-truth registry signature is invalid or untrusted.")]
        }

        let payload = registry.payload
        var issues: [WriterIndependentGroundTruthValidationIssue] = []
        if (try? payload.computedMerkleRootSHA256()) != payload.merkleRootSHA256.lowercased() {
            issues.append(issue(
                .contentCommitmentMismatch,
                detail: "The ground-truth root must be recomputed from canonical protected label records."
            ))
        }
        if payload.registryVersion != expected.registryVersion
            || payload.merkleRootSHA256.lowercased() != expected.merkleRootSHA256.lowercased()
            || payload.registryEpoch < expected.minimumRegistryEpoch
            || payload.issuedAtUnixSeconds > expected.validationUnixSeconds
            || payload.expiresAtUnixSeconds <= expected.validationUnixSeconds {
            issues.append(issue(
                .staleRegistry,
                detail: "Ground truth must match the externally supplied current checkpoint and validity window."
            ))
        }

        let recordsBySample = Dictionary(grouping: payload.records, by: \.sampleID)
        let recordsByLabel = Dictionary(grouping: payload.records, by: \.labelRecordID)
        if recordsBySample.values.contains(where: { $0.count != 1 })
            || recordsByLabel.values.contains(where: { $0.count != 1 }) {
            issues.append(issue(
                .duplicateRecord,
                samples: payload.records,
                detail: "Ground-truth sample and label record IDs must each be unique."
            ))
        }

        let expectedMembership = Set(
            manifest.samples
                .filter { $0.sourceKind == .consentedHumanCapture }
                .map { "\($0.sampleID.uuidString)|\($0.labelRecordID.uuidString)" }
        )
        let eligibleDatasetRecords = payload.records.filter {
            $0.datasetVersion == manifest.datasetVersion && $0.isEvaluationEligible
        }
        let actualMembership = Set(
            eligibleDatasetRecords.map { "\($0.sampleID.uuidString)|\($0.labelRecordID.uuidString)" }
        )
        if expectedMembership != actualMembership {
            issues.append(issue(
                .completenessMismatch,
                samples: eligibleDatasetRecords,
                detail: "Ground truth must contain every and only eligible independent human capture in the manifest."
            ))
        }

        let manifestBySample = Dictionary(
            manifest.samples.map { ($0.sampleID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for record in eligibleDatasetRecords {
            guard let sample = manifestBySample[record.sampleID],
                  sample.sourceKind == .consentedHumanCapture,
                  sample.labelRecordID == record.labelRecordID else {
                issues.append(issue(
                    .sampleIdentityMismatch,
                    samples: [record],
                    detail: "Ground-truth sample and label IDs must match one independent human capture."
                ))
                continue
            }

            let requiredHashes = [
                record.promptedIntentCommitmentSHA256,
                record.writerConfirmedIntentCommitmentSHA256,
                record.firstReaderHMACSHA256,
                record.firstReaderLabelCommitmentSHA256,
                record.secondReaderHMACSHA256,
                record.secondReaderLabelCommitmentSHA256,
                record.finalLabelCommitmentSHA256
            ]
            if requiredHashes.contains(where: { !isCanonicalSHA256($0) })
                || record.adjudicatorHMACSHA256.map({ !isCanonicalSHA256($0) }) == true
                || record.adjudicatedLabelCommitmentSHA256.map({ !isCanonicalSHA256($0) }) == true {
                issues.append(issue(
                    .invalidCommitment,
                    samples: [record],
                    detail: "Ground-truth identities and label values must be canonical protected SHA-256 commitments."
                ))
            }
            if record.firstReaderHMACSHA256 == record.secondReaderHMACSHA256 {
                issues.append(issue(
                    .readersNotIndependent,
                    samples: [record],
                    detail: "Two distinct music-literate readers are required."
                ))
            }

            let readersAgree = record.firstReaderLabelCommitmentSHA256
                == record.secondReaderLabelCommitmentSHA256
            if readersAgree {
                if record.finalLabelCommitmentSHA256 != record.firstReaderLabelCommitmentSHA256 {
                    issues.append(issue(
                        .invalidAdjudication,
                        samples: [record],
                        detail: "When readers agree, their committed label must be the frozen final label."
                    ))
                }
            } else {
                if let adjudicator = record.adjudicatorHMACSHA256,
                   let adjudicated = record.adjudicatedLabelCommitmentSHA256 {
                    if adjudicator == record.firstReaderHMACSHA256
                        || adjudicator == record.secondReaderHMACSHA256
                        || record.finalLabelCommitmentSHA256 != adjudicated {
                        issues.append(issue(
                            .invalidAdjudication,
                            samples: [record],
                            detail: "Adjudication must be independent and must supply the frozen final label."
                        ))
                    }
                } else {
                    issues.append(issue(
                        .adjudicationRequired,
                        samples: [record],
                        detail: "Reader disagreement requires a distinct adjudicator and committed adjudicated result."
                    ))
                }
            }
            if !record.isFrozen {
                issues.append(issue(
                    .labelNotFrozen,
                    samples: [record],
                    detail: "Legibility and final-label adjudication must be frozen before sealed evaluation."
                ))
            }
        }

        return issues.sorted {
            if $0.code.rawValue != $1.code.rawValue { return $0.code.rawValue < $1.code.rawValue }
            return $0.sampleIDs.map(\.uuidString).joined() < $1.sampleIDs.map(\.uuidString).joined()
        }
    }

    private static func signatureIsValid(
        _ registry: SignedWriterIndependentGroundTruthRegistry,
        trustedPublicKeysByID: [String: Data]
    ) -> Bool {
        let keyID = registry.signingKeyID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyID.isEmpty,
              let signature = Data(base64Encoded: registry.signatureBase64),
              !signature.isEmpty,
              let rawKey = trustedPublicKeysByID[keyID],
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: rawKey),
              let payload = try? registry.payload.canonicalData() else { return false }
        return publicKey.isValidSignature(signature, for: payload)
    }

    private static func isCanonicalSHA256(_ value: String) -> Bool {
        value.count == 64 && value.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 48...57, 97...102: true
            default: false
            }
        }
    }

    private static func issue(
        _ code: WriterIndependentGroundTruthValidationIssue.Code,
        samples: [WriterIndependentGroundTruthRecord] = [],
        detail: String
    ) -> WriterIndependentGroundTruthValidationIssue {
        WriterIndependentGroundTruthValidationIssue(
            code: code,
            sampleIDs: samples.map(\.sampleID).sorted { $0.uuidString < $1.uuidString },
            detail: detail
        )
    }
}

enum WriterIndependentEvaluationSourceKind: String, Codable, Hashable {
    case consentedHumanCapture
    case syntheticDerivative
}

enum WriterIndependentEvaluationSplit: String, Codable, Hashable, CaseIterable {
    case development
    case calibration
    case sealedTest
}

enum WriterIndependentEvaluationOrientation: String, Codable, Hashable, CaseIterable {
    case portrait
    case landscape
}

enum WriterIndependentEvaluationPace: String, Codable, Hashable, CaseIterable {
    case natural
    case fast
    case careful
}

enum WriterIndependentEvaluationSizeBucket: String, Codable, Hashable, CaseIterable {
    case small
    case normal
    case large
}

enum WriterIndependentEvaluationHandedness: String, Codable, Hashable, CaseIterable {
    case left
    case right
}

enum WriterIndependentEvaluationPencilExperience: String, Codable, Hashable, CaseIterable {
    case novice
    case experienced
}

enum WriterIndependentEvaluationConstructionVariation: String, Codable, Hashable, CaseIterable {
    case rootFirst
    case modifierFirst
    case mixedOrRetraced
}

/// Versioned semantic coverage contract shared by the manifest and receipt.
/// These are mandatory slices, not suggestions a gate author may silently omit.
enum WriterIndependentEvaluationProtocolContract {
    static let currentVersion = "writer-independent-capture-v2"

    static let requiredStratumKeys: Set<WriterIndependentEvaluationStratumKey> = {
        func key(
            _ population: WriterIndependentEvaluationPopulation,
            _ dimension: WriterIndependentEvaluationStratumDimension,
            _ value: String
        ) -> WriterIndependentEvaluationStratumKey {
            WriterIndependentEvaluationStratumKey(
                population: population,
                dimension: dimension,
                value: value
            )
        }

        var values: Set<WriterIndependentEvaluationStratumKey> = [
            key(.naturalFrequency, .overall, "all"),
            key(.familyBalanced, .overall, "all")
        ]
        for value in ["major", "minor", "dominant", "altered", "slash-bass"] {
            values.insert(key(.familyBalanced, .chordFamily, value))
        }
        for value in ["root", "accidental", "quality", "extension", "alteration", "slash-bass", "repeat"] {
            values.insert(key(.familyBalanced, .component, value))
        }
        for value in ["simple-chord-sheet", "rhythm-section-sheet"] {
            values.insert(key(.naturalFrequency, .chartStyle, value))
        }
        for value in ["oldest-supported", "current-reference"] {
            values.insert(key(.naturalFrequency, .deviceClass, value))
        }
        for value in WriterIndependentEvaluationOrientation.allCases.map(\.rawValue) {
            values.insert(key(.naturalFrequency, .orientation, value))
        }
        for value in WriterIndependentEvaluationPace.allCases.map(\.rawValue) {
            values.insert(key(.naturalFrequency, .pace, value))
        }
        for value in WriterIndependentEvaluationSizeBucket.allCases.map(\.rawValue) {
            values.insert(key(.naturalFrequency, .sizeBucket, value))
        }
        for value in WriterIndependentEvaluationHandedness.allCases.map(\.rawValue) {
            values.insert(key(.naturalFrequency, .handedness, value))
        }
        for value in WriterIndependentEvaluationPencilExperience.allCases.map(\.rawValue) {
            values.insert(key(.naturalFrequency, .pencilExperience, value))
        }
        for value in WriterIndependentEvaluationConstructionVariation.allCases.map(\.rawValue) {
            values.insert(key(.naturalFrequency, .constructionVariation, value))
        }
        return values
    }()
}

struct WriterIndependentEvaluationValidationIssue: Hashable {
    enum Code: String, Hashable {
        case unsupportedSchemaVersion
        case unsupportedEvaluationProtocol
        case emptyDataset
        case missingDatasetVersion
        case missingRegistryIdentity
        case invalidProvenanceSnapshot
        case provenanceContentCommitmentMismatch
        case staleProvenanceSnapshot
        case provenanceIdentityMismatch
        case duplicateProvenanceRecord
        case inactiveConsent
        case consentWriterMismatch
        case consentScopeMismatch
        case consentDatasetMismatch
        case consentCrossesWriters
        case sampleMissingFromCohortRegistry
        case cohortRegistryRecordMismatch
        case cohortRegistryDenylisted
        case cohortRegistryCompletenessMismatch
        case cohortRegistryLeakageBoundary
        case duplicateSampleID
        case duplicateLabelRecordID
        case invalidWriterIDHash
        case invalidPersonLinkageHash
        case personIdentityMismatch
        case personCrossesGlobalSplits
        case sessionCrossesGlobalPersons
        case invalidStrokePayloadHash
        case missingMetadata
        case humanCaptureHasParent
        case derivativeMissingParent
        case derivativeParentMissing
        case derivativeLineageMismatch
        case derivativeCycle
        case writerCrossesSplits
        case sessionCrossesWriters
        case sessionCrossesSplits
        case duplicatePayload
        case duplicateHumanGeometryCluster
        case geometryClusterCrossesBoundary
    }

    var code: Code
    var sampleIDs: [UUID]
    var detail: String
}

enum WriterIndependentEvaluationManifestValidator {
    static func issues(
        in manifest: WriterIndependentEvaluationManifest,
        provenanceSnapshot: SignedWriterIndependentProvenanceSnapshot,
        trustedProvenancePublicKeysByID: [String: Data],
        expectedProvenance: WriterIndependentProvenanceExpectation
    ) -> [WriterIndependentEvaluationValidationIssue] {
        var issues: [WriterIndependentEvaluationValidationIssue] = []

        guard provenanceSignatureIsValid(
            provenanceSnapshot,
            trustedPublicKeysByID: trustedProvenancePublicKeysByID
        ) else {
            return [issue(
                .invalidProvenanceSnapshot,
                detail: "The provenance snapshot must carry a valid Ed25519 signature from the trusted collection-service keyring."
            )]
        }
        let provenance = provenanceSnapshot.payload

        let computedConsentRoot = try? provenance.computedConsentLedgerMerkleRootSHA256()
        let computedCohortRoot = try? provenance.computedCohortRegistryMerkleRootSHA256()
        if computedConsentRoot != provenance.consentLedgerMerkleRootSHA256
            || computedCohortRoot != provenance.cohortRegistryMerkleRootSHA256 {
            issues.append(issue(
                .provenanceContentCommitmentMismatch,
                detail: "Signed provenance roots must be recomputed from the canonical consent and cohort records."
            ))
        }
        if provenance.cohortRegistryVersion != expectedProvenance.cohortRegistryVersion
            || provenance.cohortRegistryMerkleRootSHA256 != expectedProvenance.cohortRegistryMerkleRootSHA256
            || provenance.cohortRegistryEpoch < expectedProvenance.minimumCohortRegistryEpoch
            || provenance.consentLedgerSnapshotVersion != expectedProvenance.consentLedgerSnapshotVersion
            || provenance.consentLedgerMerkleRootSHA256 != expectedProvenance.consentLedgerMerkleRootSHA256
            || provenance.consentLedgerEpoch < expectedProvenance.minimumConsentLedgerEpoch
            || provenance.issuedAtUnixSeconds > expectedProvenance.validationUnixSeconds
            || provenance.expiresAtUnixSeconds <= expectedProvenance.validationUnixSeconds {
            issues.append(issue(
                .staleProvenanceSnapshot,
                detail: "Provenance must match the externally supplied current roots/epochs and remain within its validity window."
            ))
        }

        if manifest.schemaVersion != WriterIndependentEvaluationManifest.currentSchemaVersion {
            issues.append(issue(
                .unsupportedSchemaVersion,
                detail: "Expected schema version \(WriterIndependentEvaluationManifest.currentSchemaVersion)."
            ))
        }
        if manifest.evaluationProtocolVersion != WriterIndependentEvaluationProtocolContract.currentVersion {
            issues.append(issue(
                .unsupportedEvaluationProtocol,
                detail: "The manifest must use the current preregistered writer-independent capture protocol."
            ))
        }
        if manifest.datasetVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(issue(.missingDatasetVersion, detail: "datasetVersion must be nonempty."))
        }
        if manifest.samples.isEmpty {
            issues.append(issue(.emptyDataset, detail: "A study manifest must contain at least one capture."))
        }
        let registryIdentity = [
            manifest.cohortRegistryVersion,
            manifest.consentLedgerSnapshotVersion
        ]
        if registryIdentity.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            || !isCanonicalSHA256(manifest.cohortRegistryMerkleRootSHA256)
            || !isCanonicalSHA256(manifest.consentLedgerMerkleRootSHA256) {
            issues.append(issue(
                .missingRegistryIdentity,
                detail: "Versioned cohort/leakage and consent-ledger registry roots are required."
            ))
        }
        if manifest.cohortRegistryVersion != provenance.cohortRegistryVersion
            || manifest.cohortRegistryMerkleRootSHA256 != provenance.cohortRegistryMerkleRootSHA256
            || manifest.consentLedgerSnapshotVersion != provenance.consentLedgerSnapshotVersion
            || manifest.consentLedgerMerkleRootSHA256 != provenance.consentLedgerMerkleRootSHA256 {
            issues.append(issue(
                .provenanceIdentityMismatch,
                detail: "The manifest must bind to the signed consent and cohort-registry snapshot supplied by the evaluator."
            ))
        }

        let consentGroups = Dictionary(grouping: provenance.consentRecords, by: \.consentRecordID)
        let cohortGroups = Dictionary(grouping: provenance.cohortRecords, by: { $0.strokePayloadSHA256.lowercased() })
        if consentGroups.values.contains(where: { $0.count != 1 })
            || cohortGroups.values.contains(where: { $0.count != 1 }) {
            issues.append(issue(
                .duplicateProvenanceRecord,
                detail: "Signed provenance may contain exactly one record per consent ID and stroke payload."
            ))
        }
        let consentByID = consentGroups.compactMapValues { $0.count == 1 ? $0[0] : nil }
        let cohortByPayload = cohortGroups.compactMapValues { $0.count == 1 ? $0[0] : nil }

        if provenance.consentRecords.contains(where: { !isCanonicalSHA256($0.personLinkageHMACSHA256) })
            || provenance.cohortRecords.contains(where: { !isCanonicalSHA256($0.personLinkageHMACSHA256) }) {
            issues.append(issue(
                .invalidPersonLinkageHash,
                detail: "Every protected consent and cohort row requires a canonical service-stable person-linkage HMAC."
            ))
        }
        if provenance.consentRecords.contains(where: { !isCanonicalSHA256($0.writerIDHash) })
            || provenance.cohortRecords.contains(where: { !isCanonicalSHA256($0.writerIDHash) }) {
            issues.append(issue(
                .invalidWriterIDHash,
                detail: "Every protected consent and cohort row requires a canonical dataset-scoped writer HMAC."
            ))
        }

        let globallyEligible = provenance.cohortRecords.filter { $0.eligibility == .evaluationEligible }
        let globalPeople = Dictionary(grouping: globallyEligible, by: { $0.personLinkageHMACSHA256.lowercased() })
        for records in globalPeople.values where Set(records.map(\.split)).count > 1 {
            issues.append(issue(
                .personCrossesGlobalSplits,
                detail: "One protected person linkage cannot occupy different development, calibration, or sealed roles anywhere in the all-cohort registry."
            ))
        }
        let globalSessions = Dictionary(grouping: globallyEligible, by: \.captureSessionID)
        for records in globalSessions.values where Set(records.map { $0.personLinkageHMACSHA256.lowercased() }).count > 1 {
            issues.append(issue(
                .sessionCrossesGlobalPersons,
                detail: "A protected capture session cannot identify multiple people anywhere in the all-cohort registry."
            ))
        }
        let datasetWriterMappings = Dictionary(
            grouping: globallyEligible,
            by: { "\($0.datasetVersion)|\($0.writerIDHash.lowercased())" }
        )
        let personDatasetMappings = Dictionary(
            grouping: globallyEligible,
            by: { "\($0.personLinkageHMACSHA256.lowercased())|\($0.datasetVersion)" }
        )
        if datasetWriterMappings.values.contains(where: {
            Set($0.map { $0.personLinkageHMACSHA256.lowercased() }).count > 1
        }) || personDatasetMappings.values.contains(where: {
            Set($0.map { $0.writerIDHash.lowercased() }).count > 1
        }) {
            issues.append(issue(
                .personIdentityMismatch,
                detail: "Dataset-scoped writer HMACs and service-stable person linkages must form a one-to-one mapping within each dataset."
            ))
        }

        let eligibleDatasetRecords = provenance.cohortRecords.filter {
            $0.datasetVersion == manifest.datasetVersion && $0.eligibility == .evaluationEligible
        }
        let manifestMembership = Set(manifest.samples.map { "\($0.sampleID.uuidString)|\($0.strokePayloadSHA256)" })
        let registryMembership = Set(eligibleDatasetRecords.map { "\($0.sampleID.uuidString)|\($0.strokePayloadSHA256)" })
        if manifestMembership != registryMembership {
            issues.append(issue(
                .cohortRegistryCompletenessMismatch,
                detail: "A dataset manifest must contain every and only evaluation-eligible record assigned to that dataset in signed provenance."
            ))
        }

        let protectedClusters = Dictionary(grouping: provenance.cohortRecords, by: \.geometryLeakageClusterID)
        for records in protectedClusters.values {
            let eligible = records.filter { $0.eligibility == .evaluationEligible }
            let humanEligible = eligible.filter { $0.sourceKind == .consentedHumanCapture }
            let touchesIneligibleRegistryRow = records.contains { $0.eligibility != .evaluationEligible }
            if humanEligible.count > 1
                || Set(eligible.map { $0.writerIDHash.lowercased() }).count > 1
                || Set(eligible.map(\.split)).count > 1
                || (!eligible.isEmpty && touchesIneligibleRegistryRow) {
                issues.append(issue(
                    .cohortRegistryLeakageBoundary,
                    detail: "The signed all-cohort registry cannot place multiple human captures, writers, splits, or any quarantined/denylisted ink in one eligible leakage cluster."
                ))
            }
        }

        issues += duplicateIssues(
            grouped: Dictionary(grouping: manifest.samples, by: \.sampleID),
            code: .duplicateSampleID,
            detail: "sampleID must be unique."
        )
        issues += duplicateIssues(
            grouped: Dictionary(
                grouping: manifest.samples.filter { $0.sourceKind == .consentedHumanCapture },
                by: \.labelRecordID
            ),
            code: .duplicateLabelRecordID,
            detail: "Independent human captures require distinct ground-truth records. Derivatives inherit their parent's record."
        )

        for sample in manifest.samples {
            if sample.captureProtocolVersion != manifest.evaluationProtocolVersion
                || sample.captureProtocolVersion != WriterIndependentEvaluationProtocolContract.currentVersion {
                issues.append(issue(
                    .unsupportedEvaluationProtocol,
                    samples: [sample],
                    detail: "Every sample must be captured under the manifest's current preregistered protocol version."
                ))
            }
            if !isCanonicalSHA256(sample.writerIDHash) {
                issues.append(issue(
                    .invalidWriterIDHash,
                    samples: [sample],
                    detail: "writerIDHash must be a canonical lowercase 64-character HMAC-SHA-256."
                ))
            }
            if !isCanonicalSHA256(sample.strokePayloadSHA256) {
                issues.append(issue(
                    .invalidStrokePayloadHash,
                    samples: [sample],
                    detail: "strokePayloadSHA256 must be a 64-character hexadecimal SHA-256."
                ))
            }

            let requiredMetadata = [
                sample.captureProtocolVersion,
                sample.deviceClass,
                sample.appBuild,
                sample.pipelineVersion,
                sample.leakageCheckVersion
            ]
            if requiredMetadata.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                issues.append(issue(
                    .missingMetadata,
                    samples: [sample],
                    detail: "Study provenance, build, pipeline, device bucket, and consent metadata are required."
                ))
            }
            if let consent = consentByID[sample.consentRecordID] {
                if !consent.isActive {
                    issues.append(issue(
                        .inactiveConsent,
                        samples: [sample],
                        detail: "The signed consent record is revoked or inactive."
                    ))
                }
                if consent.writerIDHash != sample.writerIDHash {
                    issues.append(issue(
                        .consentWriterMismatch,
                        samples: [sample],
                        detail: "The signed consent record must identify the sample's canonical writer HMAC."
                    ))
                }
                if !consent.researchScopes.contains(.chordRecognitionEvaluation) {
                    issues.append(issue(
                        .consentScopeMismatch,
                        samples: [sample],
                        detail: "Active consent must explicitly include chord-recognition evaluation."
                    ))
                }
                if !consent.datasetVersions.contains(manifest.datasetVersion) {
                    issues.append(issue(
                        .consentDatasetMismatch,
                        samples: [sample],
                        detail: "Active consent must cover the bound dataset version."
                    ))
                }
            } else {
                issues.append(issue(
                    .inactiveConsent,
                    samples: [sample],
                    detail: "The sample consent record is absent from signed provenance."
                ))
            }

            if let registry = cohortByPayload[sample.strokePayloadSHA256.lowercased()] {
                if registry.sampleID != sample.sampleID
                    || registry.datasetVersion != manifest.datasetVersion
                    || registry.strokePayloadSHA256 != sample.strokePayloadSHA256
                    || registry.writerIDHash != sample.writerIDHash
                    || registry.captureSessionID != sample.captureSessionID
                    || registry.sourceKind != sample.sourceKind
                    || registry.parentSampleID != sample.parentSampleID
                    || registry.split != sample.split
                    || registry.captureProtocolVersion != sample.captureProtocolVersion
                    || registry.chartStyle != sample.chartStyle
                    || registry.orientation != sample.orientation
                    || registry.pace != sample.pace
                    || registry.sizeBucket != sample.sizeBucket
                    || registry.handedness != sample.handedness
                    || registry.pencilExperience != sample.pencilExperience
                    || registry.constructionVariation != sample.constructionVariation
                    || registry.deviceClass != sample.deviceClass
                    || registry.appBuild != sample.appBuild
                    || registry.pipelineVersion != sample.pipelineVersion
                    || registry.labelRecordID != sample.labelRecordID
                    || registry.consentRecordID != sample.consentRecordID
                    || registry.geometryLeakageClusterID != sample.geometryLeakageClusterID
                    || registry.leakageCheckVersion != sample.leakageCheckVersion {
                    issues.append(issue(
                        .cohortRegistryRecordMismatch,
                        samples: [sample],
                        detail: "Manifest identity, lineage, split, consent, and leakage assignments must match signed registry provenance."
                    ))
                }
                if let consent = consentByID[sample.consentRecordID],
                   consent.personLinkageHMACSHA256 != registry.personLinkageHMACSHA256 {
                    issues.append(issue(
                        .personIdentityMismatch,
                        samples: [sample],
                        detail: "The consent and cohort records must identify the same service-stable protected person."
                    ))
                }
                if registry.eligibility != .evaluationEligible {
                    issues.append(issue(
                        .cohortRegistryDenylisted,
                        samples: [sample],
                        detail: "Legacy, template-derived, or quarantined ink cannot enter an evaluation denominator."
                    ))
                }
            } else {
                issues.append(issue(
                    .sampleMissingFromCohortRegistry,
                    samples: [sample],
                    detail: "Every sample payload must be present in the signed all-cohort/legacy registry."
                ))
            }

            switch (sample.sourceKind, sample.parentSampleID) {
            case (.consentedHumanCapture, .some):
                issues.append(issue(
                    .humanCaptureHasParent,
                    samples: [sample],
                    detail: "A human capture cannot be derived from another sample."
                ))
            case (.syntheticDerivative, .none):
                issues.append(issue(
                    .derivativeMissingParent,
                    samples: [sample],
                    detail: "Every synthetic derivative must name its source sample."
                ))
            default:
                break
            }
        }

        let writers = Dictionary(grouping: manifest.samples, by: { $0.writerIDHash.lowercased() })
        for samples in writers.values where Set(samples.map(\.split)).count > 1 {
            issues.append(issue(
                .writerCrossesSplits,
                samples: samples,
                detail: "All sessions and derivatives from one writer must remain in one split."
            ))
        }

        let consents = Dictionary(grouping: manifest.samples, by: \.consentRecordID)
        for samples in consents.values where Set(samples.map { $0.writerIDHash.lowercased() }).count > 1 {
            issues.append(issue(
                .consentCrossesWriters,
                samples: samples,
                detail: "One protected consent record cannot identify multiple writer pseudonyms."
            ))
        }

        let sessions = Dictionary(grouping: manifest.samples, by: \.captureSessionID)
        for samples in sessions.values {
            if Set(samples.map(\.writerIDHash)).count > 1 {
                issues.append(issue(
                    .sessionCrossesWriters,
                    samples: samples,
                    detail: "A capture session cannot contain more than one writer."
                ))
            }
            if Set(samples.map(\.split)).count > 1 {
                issues.append(issue(
                    .sessionCrossesSplits,
                    samples: samples,
                    detail: "A capture session cannot cross evaluation splits."
                ))
            }
        }

        let payloads = Dictionary(grouping: manifest.samples, by: { $0.strokePayloadSHA256.lowercased() })
        for samples in payloads.values where samples.count > 1 {
            issues.append(issue(
                .duplicatePayload,
                samples: samples,
                detail: "Exact stroke geometry may appear only once; derivatives require their own payload hash and lineage."
            ))
        }

        let geometryClusters = Dictionary(grouping: manifest.samples, by: \.geometryLeakageClusterID)
        for samples in geometryClusters.values {
            let humanCaptures = samples.filter { $0.sourceKind == .consentedHumanCapture }
            if humanCaptures.count > 1 {
                issues.append(issue(
                    .duplicateHumanGeometryCluster,
                    samples: humanCaptures,
                    detail: "A near-duplicate/legacy-leakage cluster may contribute at most one independent human capture."
                ))
            }
            if Set(samples.map { $0.writerIDHash.lowercased() }).count > 1
                || Set(samples.map(\.split)).count > 1 {
                issues.append(issue(
                    .geometryClusterCrossesBoundary,
                    samples: samples,
                    detail: "A geometry leakage cluster cannot cross writer or split boundaries."
                ))
            }
        }

        let uniqueSamplesByID = Dictionary(
            manifest.samples.map { ($0.sampleID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for sample in manifest.samples where sample.sourceKind == .syntheticDerivative {
            guard let parentID = sample.parentSampleID else { continue }
            guard let parent = uniqueSamplesByID[parentID] else {
                issues.append(issue(
                    .derivativeParentMissing,
                    samples: [sample],
                    detail: "The derivative parent must exist in the same versioned manifest."
                ))
                continue
            }
            if parent.writerIDHash != sample.writerIDHash
                || parent.captureSessionID != sample.captureSessionID
                || parent.split != sample.split
                || parent.labelRecordID != sample.labelRecordID
                || parent.consentRecordID != sample.consentRecordID
                || parent.geometryLeakageClusterID != sample.geometryLeakageClusterID
                || parent.leakageCheckVersion != sample.leakageCheckVersion {
                issues.append(issue(
                    .derivativeLineageMismatch,
                    samples: [parent, sample],
                    detail: "A derivative must retain its parent's writer, session, split, label, consent, and leakage lineage."
                ))
            }

            var visited: Set<UUID> = [sample.sampleID]
            var cursor: WriterIndependentEvaluationSample? = parent
            while let current = cursor {
                guard visited.insert(current.sampleID).inserted else {
                    issues.append(issue(
                        .derivativeCycle,
                        samples: [sample, current],
                        detail: "Derivative lineage cannot contain a cycle."
                    ))
                    break
                }
                cursor = current.parentSampleID.flatMap { uniqueSamplesByID[$0] }
            }
        }

        return issues.sorted {
            if $0.code.rawValue != $1.code.rawValue { return $0.code.rawValue < $1.code.rawValue }
            return $0.sampleIDs.map(\.uuidString).joined() < $1.sampleIDs.map(\.uuidString).joined()
        }
    }

    static func independentHumanCaptureCounts(
        in manifest: WriterIndependentEvaluationManifest
    ) -> [WriterIndependentEvaluationSplit: Int] {
        Dictionary(grouping: manifest.samples.filter { $0.sourceKind == .consentedHumanCapture }, by: \.split)
            .mapValues(\.count)
    }

    static func independentWriterCounts(
        in manifest: WriterIndependentEvaluationManifest
    ) -> [WriterIndependentEvaluationSplit: Int] {
        Dictionary(uniqueKeysWithValues: WriterIndependentEvaluationSplit.allCases.map { split in
            let writers = Set(manifest.samples.lazy.filter { $0.split == split }.map { $0.writerIDHash.lowercased() })
            return (split, writers.count)
        })
    }

    private static func isCanonicalSHA256(_ value: String) -> Bool {
        value.count == 64 && value.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 48...57, 97...102:
                true
            default:
                false
            }
        }
    }

    private static func provenanceSignatureIsValid(
        _ snapshot: SignedWriterIndependentProvenanceSnapshot,
        trustedPublicKeysByID: [String: Data]
    ) -> Bool {
        let keyID = snapshot.signingKeyID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyID.isEmpty,
              let signature = Data(base64Encoded: snapshot.signatureBase64),
              !signature.isEmpty,
              let rawPublicKey = trustedPublicKeysByID[keyID],
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: rawPublicKey),
              let canonicalPayload = try? snapshot.payload.canonicalData() else {
            return false
        }
        return publicKey.isValidSignature(signature, for: canonicalPayload)
    }

    private static func duplicateIssues<Key: Hashable>(
        grouped: [Key: [WriterIndependentEvaluationSample]],
        code: WriterIndependentEvaluationValidationIssue.Code,
        detail: String
    ) -> [WriterIndependentEvaluationValidationIssue] {
        grouped.values.compactMap { samples in
            guard samples.count > 1 else { return nil }
            return issue(code, samples: samples, detail: detail)
        }
    }

    private static func issue(
        _ code: WriterIndependentEvaluationValidationIssue.Code,
        samples: [WriterIndependentEvaluationSample] = [],
        detail: String
    ) -> WriterIndependentEvaluationValidationIssue {
        WriterIndependentEvaluationValidationIssue(
            code: code,
            sampleIDs: samples.map(\.sampleID).sorted { $0.uuidString < $1.uuidString },
            detail: detail
        )
    }
}

enum WriterIndependentMerkleCommitment {
    static func root<Record: Encodable>(
        records: [Record],
        sortedBy key: (Record) -> String
    ) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var level = try records
            .sorted { key($0) < key($1) }
            .map { Data(SHA256.hash(data: try encoder.encode($0))) }

        if level.isEmpty {
            return hex(Data(SHA256.hash(data: Data())))
        }
        while level.count > 1 {
            var next: [Data] = []
            var index = 0
            while index < level.count {
                let left = level[index]
                let right = index + 1 < level.count ? level[index + 1] : left
                next.append(Data(SHA256.hash(data: left + right)))
                index += 2
            }
            level = next
        }
        return hex(level[0])
    }

    static func root(strings: [String]) -> String {
        var level = strings.sorted().map { Data(SHA256.hash(data: Data($0.utf8))) }
        if level.isEmpty { return hex(Data(SHA256.hash(data: Data()))) }
        while level.count > 1 {
            var next: [Data] = []
            var index = 0
            while index < level.count {
                let left = level[index]
                let right = index + 1 < level.count ? level[index + 1] : left
                next.append(Data(SHA256.hash(data: left + right)))
                index += 2
            }
            level = next
        }
        return hex(level[0])
    }

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}

/// The existing JSON archive is deliberately and permanently excluded from
/// writer-independent denominators. It remains valuable as a regression floor.
enum LegacyInkFixtureCorpusPolicy {
    static let datasetVersion = "legacy-regression-v1"
    static let provenance = "unknown"
    static let evaluationEligible = false
}
