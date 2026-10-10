import Foundation

enum RecognitionStudyCaptureContractError: Error, Equatable {
    case fixedValueMismatch(field: String, expected: String, actual: String)
    case localAuthorizationMustNotHaveAuthorityArtifact
    case externalAuthorizationRequiresAuthorityArtifact
    case unsupportedAuthorizationKind(RecognitionStudyAuthorizationKind)
    case limitExceeded(field: String, maximum: UInt64, actual: UInt64)
    case invariantViolation(String)
    case trajectoryDescriptorDoesNotMatchPacket
    case envelopeDoesNotMatchSession
}

enum RecognitionStudyArtifactKind: String, Encodable, Hashable, Sendable {
    case engineeringDryRunSessionV1 = "engineering-dry-run-session-v1"
    case engineeringDryRunTrajectoryV1 = "engineering-dry-run-trajectory-v1"
    case externallyAuthorizedTrajectoryV1 = "externally-authorized-trajectory-v1"
}

enum RecognitionStudyAuthorizationKind: String, Encodable, Hashable, Sendable {
    case localEngineeringDryRunV1 = "local-engineering-dry-run-v1"
    case externalOneUseV1 = "external-one-use-v1"
}

/// This legacy generic envelope remains local-engineering-only. Externally
/// authorized collection uses `RecognitionStudyAuthorizedCaptureEnvelope`,
/// whose dedicated contract binds the signed grant to the captured artifact.
struct RecognitionStudyAuthorizationBinding:
    RecognitionStudyCanonicalJSONDocument,
    Hashable,
    Sendable
{
    static let currentSchemaVersion = "recognition-study-authorization-binding-v1"
    static let maximumCanonicalJSONByteCount: Int =
        RecognitionStudyCaptureLimits
            .maximumAuthorizationBindingV1CanonicalJSONByteCount

    let schemaVersion: RecognitionStudyPrintableASCII
    let kind: RecognitionStudyAuthorizationKind
    let authorizationID: RecognitionStudyCanonicalUUID
    let authorityArtifactSHA256: RecognitionStudySHA256?

    var isSupportedForCapture: Bool {
        kind == .localEngineeringDryRunV1
    }

    private init(
        schemaVersion: RecognitionStudyPrintableASCII,
        kind: RecognitionStudyAuthorizationKind,
        authorizationID: RecognitionStudyCanonicalUUID,
        authorityArtifactSHA256: RecognitionStudySHA256?
    ) {
        self.schemaVersion = schemaVersion
        self.kind = kind
        self.authorizationID = authorizationID
        self.authorityArtifactSHA256 = authorityArtifactSHA256
    }

    static func localEngineeringDryRun(
        authorizationID: UUID
    ) throws -> Self {
        let value = Self(
            schemaVersion: try RecognitionStudyPrintableASCII(
                currentSchemaVersion,
                maximumUTF8ByteCount: 64
            ),
            kind: .localEngineeringDryRunV1,
            authorizationID: RecognitionStudyCanonicalUUID(authorizationID),
            authorityArtifactSHA256: nil
        )
        try value.validateContract()
        return value
    }

    static func reservedExternalOneUse(
        authorizationID: UUID,
        authorityArtifactSHA256: RecognitionStudySHA256
    ) throws -> Self {
        let value = Self(
            schemaVersion: try RecognitionStudyPrintableASCII(
                currentSchemaVersion,
                maximumUTF8ByteCount: 64
            ),
            kind: .externalOneUseV1,
            authorizationID: RecognitionStudyCanonicalUUID(authorizationID),
            authorityArtifactSHA256: authorityArtifactSHA256
        )
        try value.validateContract()
        return value
    }

    static func decodeCanonicalData(_ data: Data) throws -> Self {
        try RecognitionStudyStrictCanonicalJSON.decode(
            data,
            wireType: RecognitionStudyCaptureWire.AuthorizationBinding.self,
            construct: { try Self(wire: $0) }
        )
    }

    fileprivate init(
        wire: RecognitionStudyCaptureWire.AuthorizationBinding
    ) throws {
        schemaVersion = wire.schemaVersion
        kind = try RecognitionStudyCaptureWireDecoding.rawValue(
            RecognitionStudyAuthorizationKind.self,
            from: wire.kind,
            field: "authorizationBinding.kind"
        )
        authorizationID = wire.authorizationID
        authorityArtifactSHA256 = wire.authorityArtifactSHA256
    }

    func validateContract() throws {
        try RecognitionStudyCaptureValidation.requireFixed(
            schemaVersion,
            expected: Self.currentSchemaVersion,
            field: "schemaVersion"
        )
        switch kind {
        case .localEngineeringDryRunV1:
            guard authorityArtifactSHA256 == nil else {
                throw RecognitionStudyCaptureContractError
                    .localAuthorizationMustNotHaveAuthorityArtifact
            }
        case .externalOneUseV1:
            guard authorityArtifactSHA256 != nil else {
                throw RecognitionStudyCaptureContractError
                    .externalAuthorizationRequiresAuthorityArtifact
            }
        }
    }
}

struct RecognitionStudyClientAppContext:
    RecognitionStudyCanonicalJSONDocument,
    Hashable,
    Sendable
{
    static let expectedBundleIdentifier = "com.ichart.recognitionstudy"
    static let maximumCanonicalJSONByteCount: Int =
        RecognitionStudyCaptureLimits
            .maximumClientAppContextV1CanonicalJSONByteCount

    let bundleIdentifier: RecognitionStudyPrintableASCII
    let appVersion: RecognitionStudyPrintableASCII
    let buildNumber: RecognitionStudyPrintableASCII
    let operatingSystemMajorVersion: UInt16
    let operatingSystemMinorVersion: UInt16

    init(
        appVersion: String,
        buildNumber: String,
        operatingSystemMajorVersion: UInt16,
        operatingSystemMinorVersion: UInt16
    ) throws {
        bundleIdentifier = try RecognitionStudyPrintableASCII(
            Self.expectedBundleIdentifier,
            maximumUTF8ByteCount: 64
        )
        self.appVersion = try RecognitionStudyPrintableASCII(
            appVersion,
            maximumUTF8ByteCount: 32
        )
        self.buildNumber = try RecognitionStudyPrintableASCII(
            buildNumber,
            maximumUTF8ByteCount: 32
        )
        self.operatingSystemMajorVersion = operatingSystemMajorVersion
        self.operatingSystemMinorVersion = operatingSystemMinorVersion
        try validateContract()
    }

    static func decodeCanonicalData(_ data: Data) throws -> Self {
        try RecognitionStudyStrictCanonicalJSON.decode(
            data,
            wireType: RecognitionStudyCaptureWire.ClientAppContext.self,
            construct: { try Self(wire: $0) }
        )
    }

    fileprivate init(
        wire: RecognitionStudyCaptureWire.ClientAppContext
    ) throws {
        bundleIdentifier = wire.bundleIdentifier
        appVersion = wire.appVersion
        buildNumber = wire.buildNumber
        operatingSystemMajorVersion = wire.operatingSystemMajorVersion
        operatingSystemMinorVersion = wire.operatingSystemMinorVersion
    }

    func validateContract() throws {
        try RecognitionStudyCaptureValidation.requireFixed(
            bundleIdentifier,
            expected: Self.expectedBundleIdentifier,
            field: "bundleIdentifier"
        )
        try appVersion.require(maximumUTF8ByteCount: 32)
        try buildNumber.require(maximumUTF8ByteCount: 32)
        guard operatingSystemMajorVersion > 0 else {
            throw RecognitionStudyCaptureContractError.invariantViolation(
                "operatingSystemMajorVersion must be positive"
            )
        }
    }
}

struct RecognitionStudySessionManifest:
    RecognitionStudyCanonicalJSONDocument,
    Hashable,
    Sendable
{
    static let currentSchemaVersion = "recognition-study-session-manifest-v1"
    static let currentCollectionProtocolVersion = "engineering-dry-run-v1"
    static let maximumCanonicalJSONByteCount: Int =
        RecognitionStudyCaptureLimits
            .maximumSessionManifestV1CanonicalJSONByteCount

    let schemaVersion: RecognitionStudyPrintableASCII
    let artifactKind: RecognitionStudyArtifactKind
    let localSessionID: RecognitionStudyCanonicalUUID
    let collectionProtocolVersion: RecognitionStudyPrintableASCII
    let limitsVersion: RecognitionStudyPrintableASCII
    /// A client clock value for diagnostics, not authoritative provenance.
    let clientCreatedAtUnixMilliseconds: Int64
    let clientAppContext: RecognitionStudyClientAppContext

    init(
        localSessionID: UUID,
        clientCreatedAtUnixMilliseconds: Int64,
        clientAppContext: RecognitionStudyClientAppContext
    ) throws {
        schemaVersion = try RecognitionStudyPrintableASCII(
            Self.currentSchemaVersion,
            maximumUTF8ByteCount: 64
        )
        artifactKind = .engineeringDryRunSessionV1
        self.localSessionID = RecognitionStudyCanonicalUUID(localSessionID)
        collectionProtocolVersion = try RecognitionStudyPrintableASCII(
            Self.currentCollectionProtocolVersion,
            maximumUTF8ByteCount: 64
        )
        limitsVersion = try RecognitionStudyPrintableASCII(
            RecognitionStudyCaptureLimits.currentVersion,
            maximumUTF8ByteCount: 64
        )
        self.clientCreatedAtUnixMilliseconds = clientCreatedAtUnixMilliseconds
        self.clientAppContext = clientAppContext
        try validateContract()
    }

    static func decodeCanonicalData(_ data: Data) throws -> Self {
        try RecognitionStudyStrictCanonicalJSON.decode(
            data,
            wireType: RecognitionStudyCaptureWire.SessionManifest.self,
            construct: { try Self(wire: $0) }
        )
    }

    fileprivate init(
        wire: RecognitionStudyCaptureWire.SessionManifest
    ) throws {
        schemaVersion = wire.schemaVersion
        artifactKind = try RecognitionStudyCaptureWireDecoding.rawValue(
            RecognitionStudyArtifactKind.self,
            from: wire.artifactKind,
            field: "sessionManifest.artifactKind"
        )
        localSessionID = wire.localSessionID
        collectionProtocolVersion = wire.collectionProtocolVersion
        limitsVersion = wire.limitsVersion
        clientCreatedAtUnixMilliseconds = wire.clientCreatedAtUnixMilliseconds
        clientAppContext = try RecognitionStudyClientAppContext(
            wire: wire.clientAppContext
        )
    }

    func validateContract() throws {
        try RecognitionStudyCaptureValidation.requireFixed(
            schemaVersion,
            expected: Self.currentSchemaVersion,
            field: "schemaVersion"
        )
        guard artifactKind == .engineeringDryRunSessionV1 else {
            throw RecognitionStudyCaptureContractError.fixedValueMismatch(
                field: "artifactKind",
                expected: RecognitionStudyArtifactKind.engineeringDryRunSessionV1.rawValue,
                actual: artifactKind.rawValue
            )
        }
        try RecognitionStudyCaptureValidation.requireFixed(
            collectionProtocolVersion,
            expected: Self.currentCollectionProtocolVersion,
            field: "collectionProtocolVersion"
        )
        try RecognitionStudyCaptureValidation.requireFixed(
            limitsVersion,
            expected: RecognitionStudyCaptureLimits.currentVersion,
            field: "limitsVersion"
        )
        try clientAppContext.validateContract()
    }
}

enum RecognitionStudyPresentedChartStyle: String, Encodable, Hashable, Sendable {
    case simpleChordSheet = "simple-chord-sheet"
    case rhythmSectionSheet = "rhythm-section-sheet"
}

enum RecognitionStudyObservedOrientation: String, Encodable, Hashable, Sendable {
    case portrait
    case landscape
}

enum RecognitionStudyPresentedPaceInstruction: String, Encodable, Hashable, Sendable {
    case natural
    case fast
    case careful
}

enum RecognitionStudyPresentedSizeInstruction: String, Encodable, Hashable, Sendable {
    case small
    case normal
    case large
}

enum RecognitionStudyPresentedConstructionInstruction:
    String,
    Encodable,
    Hashable,
    Sendable
{
    case rootFirst = "root-first"
    case modifierFirst = "modifier-first"
    case mixedOrRetraced = "mixed-or-retraced"
}

/// Only the orientation is device-observed. Pace, size, construction, and chart
/// style record what the dry-run surface presented; they do not assert what the
/// person actually did.
struct RecognitionStudyPresentedSurface:
    RecognitionStudyCanonicalJSONDocument,
    Hashable,
    Sendable
{
    static let currentSurfaceVersion = "recognition-study-presented-surface-v1"
    static let maximumCanonicalJSONByteCount: Int =
        RecognitionStudyCaptureLimits
            .maximumPresentedSurfaceV1CanonicalJSONByteCount

    let surfaceVersion: RecognitionStudyPrintableASCII
    let presentedChartStyle: RecognitionStudyPresentedChartStyle
    let clientObservedOrientation: RecognitionStudyObservedOrientation
    let canvasWidth: RecognitionStudyFiniteDouble
    let canvasHeight: RecognitionStudyFiniteDouble
    let presentedPaceInstruction: RecognitionStudyPresentedPaceInstruction
    let presentedSizeInstruction: RecognitionStudyPresentedSizeInstruction
    let presentedConstructionInstruction:
        RecognitionStudyPresentedConstructionInstruction

    init(
        presentedChartStyle: RecognitionStudyPresentedChartStyle,
        clientObservedOrientation: RecognitionStudyObservedOrientation,
        canvasWidth: Double,
        canvasHeight: Double,
        presentedPaceInstruction: RecognitionStudyPresentedPaceInstruction,
        presentedSizeInstruction: RecognitionStudyPresentedSizeInstruction,
        presentedConstructionInstruction:
            RecognitionStudyPresentedConstructionInstruction
    ) throws {
        surfaceVersion = try RecognitionStudyPrintableASCII(
            Self.currentSurfaceVersion,
            maximumUTF8ByteCount: 64
        )
        self.presentedChartStyle = presentedChartStyle
        self.clientObservedOrientation = clientObservedOrientation
        self.canvasWidth = try RecognitionStudyFiniteDouble(canvasWidth)
        self.canvasHeight = try RecognitionStudyFiniteDouble(canvasHeight)
        self.presentedPaceInstruction = presentedPaceInstruction
        self.presentedSizeInstruction = presentedSizeInstruction
        self.presentedConstructionInstruction = presentedConstructionInstruction
        try validateContract()
    }

    static func decodeCanonicalData(_ data: Data) throws -> Self {
        try RecognitionStudyStrictCanonicalJSON.decode(
            data,
            wireType: RecognitionStudyCaptureWire.PresentedSurface.self,
            construct: { try Self(wire: $0) }
        )
    }

    fileprivate init(
        wire: RecognitionStudyCaptureWire.PresentedSurface
    ) throws {
        surfaceVersion = wire.surfaceVersion
        presentedChartStyle = try RecognitionStudyCaptureWireDecoding.rawValue(
            RecognitionStudyPresentedChartStyle.self,
            from: wire.presentedChartStyle,
            field: "presentedSurface.presentedChartStyle"
        )
        clientObservedOrientation = try RecognitionStudyCaptureWireDecoding.rawValue(
            RecognitionStudyObservedOrientation.self,
            from: wire.clientObservedOrientation,
            field: "presentedSurface.clientObservedOrientation"
        )
        canvasWidth = wire.canvasWidth
        canvasHeight = wire.canvasHeight
        presentedPaceInstruction = try RecognitionStudyCaptureWireDecoding.rawValue(
            RecognitionStudyPresentedPaceInstruction.self,
            from: wire.presentedPaceInstruction,
            field: "presentedSurface.presentedPaceInstruction"
        )
        presentedSizeInstruction = try RecognitionStudyCaptureWireDecoding.rawValue(
            RecognitionStudyPresentedSizeInstruction.self,
            from: wire.presentedSizeInstruction,
            field: "presentedSurface.presentedSizeInstruction"
        )
        presentedConstructionInstruction = try RecognitionStudyCaptureWireDecoding.rawValue(
            RecognitionStudyPresentedConstructionInstruction.self,
            from: wire.presentedConstructionInstruction,
            field: "presentedSurface.presentedConstructionInstruction"
        )
    }

    func validateContract() throws {
        try RecognitionStudyCaptureValidation.requireFixed(
            surfaceVersion,
            expected: Self.currentSurfaceVersion,
            field: "surfaceVersion"
        )
        guard canvasWidth.value > 0, canvasHeight.value > 0 else {
            throw RecognitionStudyCaptureContractError.invariantViolation(
                "canvas dimensions must be finite and positive"
            )
        }
    }
}

/// Engineering ceilings only. They are not recognition thresholds, study
/// eligibility rules, or evidence that a capture is representative.
enum RecognitionStudyCaptureLimits {
    static let currentVersion = "capture-limits-v1"

    static let maximumCanonicalPacketByteCount = 4 * 1024 * 1024
    static let maximumAuthorizationBindingV1CanonicalJSONByteCount = 8 * 1024
    static let maximumClientAppContextV1CanonicalJSONByteCount = 8 * 1024
    static let maximumSessionManifestV1CanonicalJSONByteCount = 32 * 1024
    static let maximumPresentedSurfaceV1CanonicalJSONByteCount = 8 * 1024
    static let maximumTrajectoryDescriptorV1CanonicalJSONByteCount = 8 * 1024
    static let maximumCaptureEnvelopeV1CanonicalJSONByteCount = 64 * 1024
    static let maximumCommitMarkerByteCount = 8 * 1024
    static let maximumStrokeCount: UInt32 = 256
    static let maximumPointCountPerStroke: UInt32 = 8_192
    static let maximumTotalPointCount: UInt32 = 32_768
    static let maximumCapturesPerSession: UInt32 = 256
    static let maximumSessionByteCount: UInt64 = 256 * 1024 * 1024
    static let maximumStoreByteCount: UInt64 = 512 * 1024 * 1024
    static let maximumSessionCount: UInt32 = 32

    /// A future store must call this before decoding untrusted packet bytes.
    static func validateCanonicalPacketByteCountBeforeDecoding(
        _ actualByteCount: Int
    ) throws {
        guard actualByteCount >= 0 else {
            throw RecognitionStudyCaptureContractError.invariantViolation(
                "canonicalPacketByteCount must not be negative"
            )
        }
        guard actualByteCount <= maximumCanonicalPacketByteCount else {
            throw RecognitionStudyCaptureContractError.limitExceeded(
                field: "canonicalPacketByteCount",
                maximum: UInt64(maximumCanonicalPacketByteCount),
                actual: UInt64(actualByteCount)
            )
        }
    }
}

/// Every field is derived from canonical packet bytes or the decoded packet.
/// A decoded descriptor is not provenance by itself; consumers must bind it
/// back to the packet with `validateBinding(to:)`.
struct RecognitionStudyTrajectoryDescriptor:
    RecognitionStudyCanonicalJSONDocument,
    Hashable,
    Sendable
{
    static let currentSchemaVersion = "recognition-study-trajectory-descriptor-v1"
    static let maximumCanonicalJSONByteCount: Int =
        RecognitionStudyCaptureLimits
            .maximumTrajectoryDescriptorV1CanonicalJSONByteCount

    let schemaVersion: RecognitionStudyPrintableASCII
    let packetFormatVersion: RecognitionStudyPrintableASCII
    let coordinateSpace: ChordInkCanonicalTrajectoryPacket.CoordinateSpace
    let canonicalPacketSHA256: RecognitionStudySHA256
    let canonicalPacketByteCount: UInt64
    let strokeCount: UInt32
    let emptyStrokeCount: UInt32
    let pointCount: UInt32
    let pointTimingCoverage: ChordInkCanonicalTrajectoryPacket.TimingCoverage
    let creationTimingCoverage: ChordInkCanonicalTrajectoryPacket.TimingCoverage
    let overallTimingCoverage: ChordInkCanonicalTrajectoryPacket.TimingCoverage
    let containsNonFiniteTiming: Bool

    init(derivingFrom packet: ChordInkCanonicalTrajectoryPacket) throws {
        let canonicalPacketData = try packet.canonicalData()
        try RecognitionStudyCaptureLimits
            .validateCanonicalPacketByteCountBeforeDecoding(
                canonicalPacketData.count
            )

        guard packet.strokes.count <= Int(RecognitionStudyCaptureLimits.maximumStrokeCount) else {
            throw RecognitionStudyCaptureContractError.limitExceeded(
                field: "strokeCount",
                maximum: UInt64(RecognitionStudyCaptureLimits.maximumStrokeCount),
                actual: UInt64(packet.strokes.count)
            )
        }

        var derivedPointCount: UInt32 = 0
        var derivedEmptyStrokeCount: UInt32 = 0
        for stroke in packet.strokes {
            guard stroke.points.count <= Int(
                RecognitionStudyCaptureLimits.maximumPointCountPerStroke
            ) else {
                throw RecognitionStudyCaptureContractError.limitExceeded(
                    field: "pointCountPerStroke",
                    maximum: UInt64(
                        RecognitionStudyCaptureLimits.maximumPointCountPerStroke
                    ),
                    actual: UInt64(stroke.points.count)
                )
            }
            if stroke.points.isEmpty {
                derivedEmptyStrokeCount += 1
            }
            let (nextPointCount, overflowed) = derivedPointCount
                .addingReportingOverflow(UInt32(stroke.points.count))
            guard !overflowed,
                  nextPointCount <= RecognitionStudyCaptureLimits.maximumTotalPointCount else {
                throw RecognitionStudyCaptureContractError.limitExceeded(
                    field: "pointCount",
                    maximum: UInt64(
                        RecognitionStudyCaptureLimits.maximumTotalPointCount
                    ),
                    actual: UInt64(derivedPointCount) + UInt64(stroke.points.count)
                )
            }
            derivedPointCount = nextPointCount
        }
        guard derivedPointCount > 0 else {
            throw RecognitionStudyCaptureContractError.invariantViolation(
                "a capture must contain at least one prepared point"
            )
        }

        schemaVersion = try RecognitionStudyPrintableASCII(
            Self.currentSchemaVersion,
            maximumUTF8ByteCount: 64
        )
        packetFormatVersion = try RecognitionStudyPrintableASCII(
            packet.formatVersion,
            maximumUTF8ByteCount: 64
        )
        coordinateSpace = packet.coordinateSpace
        canonicalPacketSHA256 = RecognitionStudySHA256(
            digesting: canonicalPacketData
        )
        canonicalPacketByteCount = UInt64(canonicalPacketData.count)
        strokeCount = UInt32(packet.strokes.count)
        emptyStrokeCount = derivedEmptyStrokeCount
        pointCount = derivedPointCount
        pointTimingCoverage = packet.pointTimingCoverage
        creationTimingCoverage = packet.creationTimingCoverage
        overallTimingCoverage = packet.timingCoverage
        containsNonFiniteTiming = packet.containsNonFiniteTiming
        try validateContract()
    }

    static func decodeCanonicalData(_ data: Data) throws -> Self {
        try RecognitionStudyStrictCanonicalJSON.decode(
            data,
            wireType: RecognitionStudyCaptureWire.TrajectoryDescriptor.self,
            construct: { try Self(wire: $0) }
        )
    }

    fileprivate init(
        wire: RecognitionStudyCaptureWire.TrajectoryDescriptor
    ) throws {
        schemaVersion = wire.schemaVersion
        packetFormatVersion = wire.packetFormatVersion
        coordinateSpace = try RecognitionStudyCaptureWireDecoding.rawValue(
            ChordInkCanonicalTrajectoryPacket.CoordinateSpace.self,
            from: wire.coordinateSpace,
            field: "trajectoryDescriptor.coordinateSpace"
        )
        canonicalPacketSHA256 = wire.canonicalPacketSHA256
        canonicalPacketByteCount = wire.canonicalPacketByteCount
        strokeCount = wire.strokeCount
        emptyStrokeCount = wire.emptyStrokeCount
        pointCount = wire.pointCount
        pointTimingCoverage = try RecognitionStudyCaptureWireDecoding.rawValue(
            ChordInkCanonicalTrajectoryPacket.TimingCoverage.self,
            from: wire.pointTimingCoverage,
            field: "trajectoryDescriptor.pointTimingCoverage"
        )
        creationTimingCoverage = try RecognitionStudyCaptureWireDecoding.rawValue(
            ChordInkCanonicalTrajectoryPacket.TimingCoverage.self,
            from: wire.creationTimingCoverage,
            field: "trajectoryDescriptor.creationTimingCoverage"
        )
        overallTimingCoverage = try RecognitionStudyCaptureWireDecoding.rawValue(
            ChordInkCanonicalTrajectoryPacket.TimingCoverage.self,
            from: wire.overallTimingCoverage,
            field: "trajectoryDescriptor.overallTimingCoverage"
        )
        containsNonFiniteTiming = wire.containsNonFiniteTiming
    }

    func validateContract() throws {
        try RecognitionStudyCaptureValidation.requireFixed(
            schemaVersion,
            expected: Self.currentSchemaVersion,
            field: "schemaVersion"
        )
        try RecognitionStudyCaptureValidation.requireFixed(
            packetFormatVersion,
            expected: ChordInkCanonicalTrajectoryPacket.currentFormatVersion,
            field: "packetFormatVersion"
        )
        guard coordinateSpace == .transformedPreparedDrawing else {
            throw RecognitionStudyCaptureContractError.fixedValueMismatch(
                field: "coordinateSpace",
                expected: ChordInkCanonicalTrajectoryPacket.CoordinateSpace
                    .transformedPreparedDrawing.rawValue,
                actual: coordinateSpace.rawValue
            )
        }
        try RecognitionStudyCaptureValidation.requireMaximum(
            canonicalPacketByteCount,
            maximum: UInt64(
                RecognitionStudyCaptureLimits.maximumCanonicalPacketByteCount
            ),
            field: "canonicalPacketByteCount"
        )
        try RecognitionStudyCaptureValidation.requireMaximum(
            UInt64(strokeCount),
            maximum: UInt64(RecognitionStudyCaptureLimits.maximumStrokeCount),
            field: "strokeCount"
        )
        try RecognitionStudyCaptureValidation.requireMaximum(
            UInt64(pointCount),
            maximum: UInt64(RecognitionStudyCaptureLimits.maximumTotalPointCount),
            field: "pointCount"
        )
        guard canonicalPacketByteCount > 0 else {
            throw RecognitionStudyCaptureContractError.invariantViolation(
                "canonicalPacketByteCount must be positive"
            )
        }
        guard pointCount > 0 else {
            throw RecognitionStudyCaptureContractError.invariantViolation(
                "pointCount must be positive"
            )
        }
        guard emptyStrokeCount <= strokeCount else {
            throw RecognitionStudyCaptureContractError.invariantViolation(
                "emptyStrokeCount must not exceed strokeCount"
            )
        }
    }

    func validateBinding(
        to packet: ChordInkCanonicalTrajectoryPacket
    ) throws {
        let derived = try Self(derivingFrom: packet)
        guard derived == self else {
            throw RecognitionStudyCaptureContractError
                .trajectoryDescriptorDoesNotMatchPacket
        }
    }
}

/// A dry-run capture envelope contains mechanics only. It carries no semantic
/// assignment, participant identity, eligibility assertion, or evaluation role.
struct RecognitionStudyCaptureEnvelope:
    RecognitionStudyCanonicalJSONDocument,
    Hashable,
    Sendable
{
    static let currentSchemaVersion = "recognition-study-capture-envelope-v1"
    static let maximumCanonicalJSONByteCount: Int =
        RecognitionStudyCaptureLimits
            .maximumCaptureEnvelopeV1CanonicalJSONByteCount

    let schemaVersion: RecognitionStudyPrintableASCII
    let artifactKind: RecognitionStudyArtifactKind
    /// Local transaction scope only. It must never be interpreted as a person,
    /// writer, account, or cross-session linkage identifier.
    let localCaptureID: RecognitionStudyCanonicalUUID
    let localSessionID: RecognitionStudyCanonicalUUID
    /// Zero-based within a local dry-run session.
    let captureOrdinal: UInt32
    let collectionProtocolVersion: RecognitionStudyPrintableASCII
    let authorizationBinding: RecognitionStudyAuthorizationBinding
    let sessionManifestSHA256: RecognitionStudySHA256
    /// A client clock value for diagnostics, not authoritative provenance.
    let clientCapturedAtUnixMilliseconds: Int64
    let presentedSurface: RecognitionStudyPresentedSurface
    let trajectoryDescriptor: RecognitionStudyTrajectoryDescriptor

    init(
        localCaptureID: UUID,
        captureOrdinal: UInt32,
        authorizationBinding: RecognitionStudyAuthorizationBinding,
        sessionManifest: RecognitionStudySessionManifest,
        clientCapturedAtUnixMilliseconds: Int64,
        presentedSurface: RecognitionStudyPresentedSurface,
        trajectoryDescriptor: RecognitionStudyTrajectoryDescriptor
    ) throws {
        schemaVersion = try RecognitionStudyPrintableASCII(
            Self.currentSchemaVersion,
            maximumUTF8ByteCount: 64
        )
        artifactKind = .engineeringDryRunTrajectoryV1
        self.localCaptureID = RecognitionStudyCanonicalUUID(localCaptureID)
        localSessionID = sessionManifest.localSessionID
        self.captureOrdinal = captureOrdinal
        collectionProtocolVersion = sessionManifest.collectionProtocolVersion
        self.authorizationBinding = authorizationBinding
        sessionManifestSHA256 = RecognitionStudySHA256(
            digesting: try sessionManifest.canonicalData()
        )
        self.clientCapturedAtUnixMilliseconds = clientCapturedAtUnixMilliseconds
        self.presentedSurface = presentedSurface
        self.trajectoryDescriptor = trajectoryDescriptor
        try validateContract()
    }

    static func decodeCanonicalData(_ data: Data) throws -> Self {
        try RecognitionStudyStrictCanonicalJSON.decode(
            data,
            wireType: RecognitionStudyCaptureWire.CaptureEnvelope.self,
            construct: { try Self(wire: $0) }
        )
    }

    fileprivate init(
        wire: RecognitionStudyCaptureWire.CaptureEnvelope
    ) throws {
        schemaVersion = wire.schemaVersion
        artifactKind = try RecognitionStudyCaptureWireDecoding.rawValue(
            RecognitionStudyArtifactKind.self,
            from: wire.artifactKind,
            field: "captureEnvelope.artifactKind"
        )
        localCaptureID = wire.localCaptureID
        localSessionID = wire.localSessionID
        captureOrdinal = wire.captureOrdinal
        collectionProtocolVersion = wire.collectionProtocolVersion
        authorizationBinding = try RecognitionStudyAuthorizationBinding(
            wire: wire.authorizationBinding
        )
        sessionManifestSHA256 = wire.sessionManifestSHA256
        clientCapturedAtUnixMilliseconds = wire.clientCapturedAtUnixMilliseconds
        presentedSurface = try RecognitionStudyPresentedSurface(
            wire: wire.presentedSurface
        )
        trajectoryDescriptor = try RecognitionStudyTrajectoryDescriptor(
            wire: wire.trajectoryDescriptor
        )
    }

    func validateContract() throws {
        try RecognitionStudyCaptureValidation.requireFixed(
            schemaVersion,
            expected: Self.currentSchemaVersion,
            field: "schemaVersion"
        )
        guard artifactKind == .engineeringDryRunTrajectoryV1 else {
            throw RecognitionStudyCaptureContractError.fixedValueMismatch(
                field: "artifactKind",
                expected: RecognitionStudyArtifactKind
                    .engineeringDryRunTrajectoryV1.rawValue,
                actual: artifactKind.rawValue
            )
        }
        try RecognitionStudyCaptureValidation.requireFixed(
            collectionProtocolVersion,
            expected: RecognitionStudySessionManifest
                .currentCollectionProtocolVersion,
            field: "collectionProtocolVersion"
        )
        try authorizationBinding.validateContract()
        guard authorizationBinding.isSupportedForCapture else {
            throw RecognitionStudyCaptureContractError
                .unsupportedAuthorizationKind(authorizationBinding.kind)
        }
        guard captureOrdinal < RecognitionStudyCaptureLimits.maximumCapturesPerSession else {
            throw RecognitionStudyCaptureContractError.limitExceeded(
                field: "captureOrdinal",
                maximum: UInt64(
                    RecognitionStudyCaptureLimits.maximumCapturesPerSession - 1
                ),
                actual: UInt64(captureOrdinal)
            )
        }
        try presentedSurface.validateContract()
        try trajectoryDescriptor.validateContract()
    }

    func validateBindings(
        to sessionManifest: RecognitionStudySessionManifest,
        packet: ChordInkCanonicalTrajectoryPacket
    ) throws {
        try validateContract()
        try sessionManifest.validateContract()
        let expectedSessionDigest = RecognitionStudySHA256(
            digesting: try sessionManifest.canonicalData()
        )
        guard localSessionID == sessionManifest.localSessionID,
              collectionProtocolVersion == sessionManifest.collectionProtocolVersion,
              sessionManifestSHA256 == expectedSessionDigest else {
            throw RecognitionStudyCaptureContractError.envelopeDoesNotMatchSession
        }
        try trajectoryDescriptor.validateBinding(to: packet)
    }
}

fileprivate enum RecognitionStudyCaptureWire {
    struct AuthorizationBinding: Decodable {
        let schemaVersion: RecognitionStudyPrintableASCII
        let kind: String
        let authorizationID: RecognitionStudyCanonicalUUID
        let authorityArtifactSHA256: RecognitionStudySHA256?
    }

    struct ClientAppContext: Decodable {
        let bundleIdentifier: RecognitionStudyPrintableASCII
        let appVersion: RecognitionStudyPrintableASCII
        let buildNumber: RecognitionStudyPrintableASCII
        let operatingSystemMajorVersion: UInt16
        let operatingSystemMinorVersion: UInt16
    }

    struct SessionManifest: Decodable {
        let schemaVersion: RecognitionStudyPrintableASCII
        let artifactKind: String
        let localSessionID: RecognitionStudyCanonicalUUID
        let collectionProtocolVersion: RecognitionStudyPrintableASCII
        let limitsVersion: RecognitionStudyPrintableASCII
        let clientCreatedAtUnixMilliseconds: Int64
        let clientAppContext: ClientAppContext
    }

    struct PresentedSurface: Decodable {
        let surfaceVersion: RecognitionStudyPrintableASCII
        let presentedChartStyle: String
        let clientObservedOrientation: String
        let canvasWidth: RecognitionStudyFiniteDouble
        let canvasHeight: RecognitionStudyFiniteDouble
        let presentedPaceInstruction: String
        let presentedSizeInstruction: String
        let presentedConstructionInstruction: String
    }

    struct TrajectoryDescriptor: Decodable {
        let schemaVersion: RecognitionStudyPrintableASCII
        let packetFormatVersion: RecognitionStudyPrintableASCII
        let coordinateSpace: String
        let canonicalPacketSHA256: RecognitionStudySHA256
        let canonicalPacketByteCount: UInt64
        let strokeCount: UInt32
        let emptyStrokeCount: UInt32
        let pointCount: UInt32
        let pointTimingCoverage: String
        let creationTimingCoverage: String
        let overallTimingCoverage: String
        let containsNonFiniteTiming: Bool
    }

    struct CaptureEnvelope: Decodable {
        let schemaVersion: RecognitionStudyPrintableASCII
        let artifactKind: String
        let localCaptureID: RecognitionStudyCanonicalUUID
        let localSessionID: RecognitionStudyCanonicalUUID
        let captureOrdinal: UInt32
        let collectionProtocolVersion: RecognitionStudyPrintableASCII
        let authorizationBinding: AuthorizationBinding
        let sessionManifestSHA256: RecognitionStudySHA256
        let clientCapturedAtUnixMilliseconds: Int64
        let presentedSurface: PresentedSurface
        let trajectoryDescriptor: TrajectoryDescriptor
    }
}

private enum RecognitionStudyCaptureWireDecoding {
    static func rawValue<Value>(
        _ type: Value.Type,
        from rawValue: String,
        field: String
    ) throws -> Value where Value: RawRepresentable, Value.RawValue == String {
        guard let value = Value(rawValue: rawValue) else {
            throw RecognitionStudyCaptureContractError.invariantViolation(
                "Unknown value for \(field): \(rawValue)"
            )
        }
        return value
    }
}

private enum RecognitionStudyCaptureValidation {
    static func requireFixed(
        _ value: RecognitionStudyPrintableASCII,
        expected: String,
        field: String
    ) throws {
        guard value.rawValue == expected else {
            throw RecognitionStudyCaptureContractError.fixedValueMismatch(
                field: field,
                expected: expected,
                actual: value.rawValue
            )
        }
    }

    static func requireMaximum(
        _ value: UInt64,
        maximum: UInt64,
        field: String
    ) throws {
        guard value <= maximum else {
            throw RecognitionStudyCaptureContractError.limitExceeded(
                field: field,
                maximum: maximum,
                actual: value
            )
        }
    }
}
