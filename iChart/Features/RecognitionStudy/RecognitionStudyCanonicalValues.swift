import CryptoKit
import Foundation

enum RecognitionStudyCanonicalValueError: Error, Equatable {
    case invalidCanonicalUUID(String)
    case invalidSHA256(String)
    case emptyPrintableASCII
    case nonPrintableASCII(String)
    case printableASCIITooLong(maximumUTF8ByteCount: Int, actualUTF8ByteCount: Int)
    case nonFiniteDouble
    case nonCanonicalJSON
    case canonicalJSONTooLarge(maximumByteCount: Int, actualByteCount: Int)
}

/// A document with one accepted byte representation. Strict decoding rejects
/// alternate whitespace, key ordering, escaped slashes, unknown keys, explicit
/// nulls for omitted optionals, and any non-canonical nested value.
protocol RecognitionStudyCanonicalJSONDocument: Encodable {
    static var maximumCanonicalJSONByteCount: Int { get }
    static func decodeCanonicalData(_ data: Data) throws -> Self
    func validateContract() throws
}

extension RecognitionStudyCanonicalJSONDocument {
    func canonicalData() throws -> Data {
        try validateContract()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        try Self.validateCanonicalJSONByteCount(data.count)
        return data
    }

    fileprivate static func validateCanonicalJSONByteCount(_ actual: Int) throws {
        guard actual <= maximumCanonicalJSONByteCount else {
            throw RecognitionStudyCanonicalValueError.canonicalJSONTooLarge(
                maximumByteCount: maximumCanonicalJSONByteCount,
                actualByteCount: actual
            )
        }
    }
}

/// The only generic JSON decode path for canonical study documents. A decoded
/// wire can never escape this helper without contract validation and exact
/// canonical-byte verification.
enum RecognitionStudyStrictCanonicalJSON {
    static func decode<Document, Wire>(
        _ data: Data,
        wireType: Wire.Type,
        construct: (Wire) throws -> Document
    ) throws -> Document
    where Document: RecognitionStudyCanonicalJSONDocument, Wire: Decodable {
        try Document.validateCanonicalJSONByteCount(data.count)
        let wire = try JSONDecoder().decode(wireType, from: data)
        let document = try construct(wire)
        try document.validateContract()
        guard try document.canonicalData() == data else {
            throw RecognitionStudyCanonicalValueError.nonCanonicalJSON
        }
        return document
    }
}

struct RecognitionStudyCanonicalUUID: Codable, Hashable, Sendable {
    let rawValue: String

    var uuid: UUID {
        // Construction and decoding both validate the round trip.
        UUID(uuidString: rawValue)!
    }

    init(_ uuid: UUID) {
        rawValue = uuid.uuidString.lowercased()
    }

    init(canonicalString: String) throws {
        guard let uuid = UUID(uuidString: canonicalString),
              canonicalString == uuid.uuidString.lowercased() else {
            throw RecognitionStudyCanonicalValueError.invalidCanonicalUUID(
                canonicalString
            )
        }
        rawValue = canonicalString
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(canonicalString: container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct RecognitionStudySHA256: Codable, Hashable, Sendable {
    let rawValue: String

    init(canonicalString: String) throws {
        let isCanonical = canonicalString.utf8.count == 64
            && canonicalString.unicodeScalars.allSatisfy { scalar in
                switch scalar.value {
                case 48...57, 97...102:
                    true
                default:
                    false
                }
            }
        guard isCanonical else {
            throw RecognitionStudyCanonicalValueError.invalidSHA256(
                canonicalString
            )
        }
        rawValue = canonicalString
    }

    init(digesting data: Data) {
        rawValue = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(canonicalString: container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct RecognitionStudyPrintableASCII: Codable, Hashable, Sendable {
    static let absoluteMaximumUTF8ByteCount = 128

    let rawValue: String

    init(
        _ rawValue: String,
        maximumUTF8ByteCount: Int = absoluteMaximumUTF8ByteCount,
        allowEmpty: Bool = false
    ) throws {
        try Self.validate(
            rawValue,
            maximumUTF8ByteCount: maximumUTF8ByteCount,
            allowEmpty: allowEmpty
        )
        self.rawValue = rawValue
    }

    func require(
        maximumUTF8ByteCount: Int,
        allowEmpty: Bool = false
    ) throws {
        try Self.validate(
            rawValue,
            maximumUTF8ByteCount: maximumUTF8ByteCount,
            allowEmpty: allowEmpty
        )
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    private static func validate(
        _ value: String,
        maximumUTF8ByteCount: Int,
        allowEmpty: Bool
    ) throws {
        guard allowEmpty || !value.isEmpty else {
            throw RecognitionStudyCanonicalValueError.emptyPrintableASCII
        }
        guard value.unicodeScalars.allSatisfy({ (32...126).contains($0.value) }) else {
            throw RecognitionStudyCanonicalValueError.nonPrintableASCII(value)
        }
        let actualByteCount = value.utf8.count
        guard actualByteCount <= maximumUTF8ByteCount else {
            throw RecognitionStudyCanonicalValueError.printableASCIITooLong(
                maximumUTF8ByteCount: maximumUTF8ByteCount,
                actualUTF8ByteCount: actualByteCount
            )
        }
    }
}

struct RecognitionStudyFiniteDouble: Codable, Hashable, Sendable {
    let bitPattern: UInt64

    var value: Double {
        Double(bitPattern: bitPattern)
    }

    init(_ value: Double) throws {
        guard value.isFinite else {
            throw RecognitionStudyCanonicalValueError.nonFiniteDouble
        }
        bitPattern = value.bitPattern
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let encoded = try container.decode(String.self)
        let isCanonical = encoded.utf8.count == 16
            && encoded.unicodeScalars.allSatisfy { scalar in
                switch scalar.value {
                case 48...57, 97...102:
                    true
                default:
                    false
                }
            }
        guard isCanonical,
              let decodedBitPattern = UInt64(encoded, radix: 16),
              Double(bitPattern: decodedBitPattern).isFinite else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected a finite 16-digit lowercase IEEE-754 bit pattern."
            )
        }
        bitPattern = decodedBitPattern
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(String(format: "%016llx", bitPattern))
    }
}
