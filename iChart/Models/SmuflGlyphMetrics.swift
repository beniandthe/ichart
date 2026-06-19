import CoreGraphics
import Foundation

struct SmuflPoint: Codable, Hashable {
    var x: Double
    var y: Double

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let x = try container.decode(Double.self)
        let y = try container.decode(Double.self)
        self.init(x: x, y: y)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(x)
        try container.encode(y)
    }

    func scaled(by staffSpace: CGFloat) -> CGPoint {
        CGPoint(x: CGFloat(x) * staffSpace, y: CGFloat(y) * staffSpace)
    }
}

struct SmuflGlyphBoundingBox: Codable, Hashable {
    var southWest: SmuflPoint
    var northEast: SmuflPoint

    var width: Double {
        northEast.x - southWest.x
    }

    var height: Double {
        northEast.y - southWest.y
    }

    var center: SmuflPoint {
        SmuflPoint(
            x: (southWest.x + northEast.x) / 2,
            y: (southWest.y + northEast.y) / 2
        )
    }

    init(southWest: SmuflPoint, northEast: SmuflPoint) {
        self.southWest = southWest
        self.northEast = northEast
    }

    enum CodingKeys: String, CodingKey {
        case southWest = "bBoxSW"
        case northEast = "bBoxNE"
    }

    func rectInStaffSpace() -> CGRect {
        CGRect(
            x: southWest.x,
            y: southWest.y,
            width: width,
            height: height
        )
    }

    func rect(staffSpace: CGFloat) -> CGRect {
        CGRect(
            x: CGFloat(southWest.x) * staffSpace,
            y: CGFloat(southWest.y) * staffSpace,
            width: CGFloat(width) * staffSpace,
            height: CGFloat(height) * staffSpace
        )
    }
}

struct SmuflGlyphMetrics: Hashable {
    var name: String
    var boundingBox: SmuflGlyphBoundingBox?
    var advanceWidth: Double?
    var anchors: [String: SmuflPoint]

    func anchor(named name: String) -> SmuflPoint? {
        anchors[name]
    }
}

struct SmuflFontMetadata: Decodable, Hashable {
    var fontName: String
    var fontVersion: String?
    var engravingDefaults: SmuflEngravingDefaults?
    var glyphBoundingBoxes: [String: SmuflGlyphBoundingBox]
    var glyphAdvanceWidths: [String: Double]
    var glyphAnchors: [String: [String: SmuflPoint]]

    enum CodingKeys: String, CodingKey {
        case fontName
        case fontVersion
        case engravingDefaults
        case glyphBoundingBoxes = "glyphBBoxes"
        case glyphAdvanceWidths
        case glyphAnchors = "glyphsWithAnchors"
    }

    init(
        fontName: String,
        fontVersion: String? = nil,
        engravingDefaults: SmuflEngravingDefaults? = nil,
        glyphBoundingBoxes: [String: SmuflGlyphBoundingBox] = [:],
        glyphAdvanceWidths: [String: Double] = [:],
        glyphAnchors: [String: [String: SmuflPoint]] = [:]
    ) {
        self.fontName = fontName
        self.fontVersion = fontVersion
        self.engravingDefaults = engravingDefaults
        self.glyphBoundingBoxes = glyphBoundingBoxes
        self.glyphAdvanceWidths = glyphAdvanceWidths
        self.glyphAnchors = glyphAnchors
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fontName = try container.decode(String.self, forKey: .fontName)
        fontVersion = Self.decodeFlexibleStringIfPresent(from: container, forKey: .fontVersion)
        engravingDefaults = try container.decodeIfPresent(SmuflEngravingDefaults.self, forKey: .engravingDefaults)
        glyphBoundingBoxes = try container.decodeIfPresent([String: SmuflGlyphBoundingBox].self, forKey: .glyphBoundingBoxes) ?? [:]
        glyphAdvanceWidths = try container.decodeIfPresent([String: Double].self, forKey: .glyphAdvanceWidths) ?? [:]
        glyphAnchors = try container.decodeIfPresent([String: [String: SmuflPoint]].self, forKey: .glyphAnchors) ?? [:]
    }

    private static func decodeFlexibleStringIfPresent(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) -> String? {
        if let stringValue = try? container.decodeIfPresent(String.self, forKey: key) {
            return stringValue
        }

        if let doubleValue = try? container.decodeIfPresent(Double.self, forKey: key) {
            return String(doubleValue)
        }

        return nil
    }

    func metrics(forGlyphNamed glyphName: String) -> SmuflGlyphMetrics? {
        let boundingBox = glyphBoundingBoxes[glyphName]
        let advanceWidth = glyphAdvanceWidths[glyphName]
        let anchors = glyphAnchors[glyphName] ?? [:]

        guard boundingBox != nil || advanceWidth != nil || !anchors.isEmpty else {
            return nil
        }

        return SmuflGlyphMetrics(
            name: glyphName,
            boundingBox: boundingBox,
            advanceWidth: advanceWidth,
            anchors: anchors
        )
    }
}

enum SmuflFontMetadataStore {
    private static var cache: [NotationFontPreset: SmuflFontMetadata] = [:]
    private static let cacheLock = NSLock()

    static func metadata(for preset: NotationFontPreset) -> SmuflFontMetadata? {
        cacheLock.lock()
        if let cachedMetadata = cache[preset] {
            cacheLock.unlock()
            return cachedMetadata
        }
        cacheLock.unlock()

        let runtimeResourceURLs = [
            Bundle.main.resourceURL,
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        ]

        guard let metadata = runtimeResourceURLs.compactMap({ resourceURL in
            loadMetadata(for: preset, fromRuntimeResources: resourceURL)
        }).first else {
            return nil
        }

        cacheLock.lock()
        cache[preset] = metadata
        cacheLock.unlock()

        return metadata
    }

    static func metrics(
        for symbol: NotationGlyphCatalog.Symbol,
        in preset: NotationFontPreset
    ) -> SmuflGlyphMetrics? {
        guard let glyphName = symbol.smuflGlyphName else {
            return nil
        }

        return metadata(for: preset)?.metrics(forGlyphNamed: glyphName)
            ?? metadata(for: .bravura)?.metrics(forGlyphNamed: glyphName)
    }

    static func decodeMetadata(from data: Data) -> SmuflFontMetadata? {
        try? JSONDecoder().decode(SmuflFontMetadata.self, from: data)
    }

    static func loadMetadata(
        for preset: NotationFontPreset,
        fromResourceBaseURL resourceBaseURL: URL?
    ) -> SmuflFontMetadata? {
        guard let resourceBaseURL,
              let metadataURL = metadataURL(for: preset, relativeTo: resourceBaseURL),
              let data = try? Data(contentsOf: metadataURL) else {
            return nil
        }

        return decodeMetadata(from: data)
    }

    private static func loadMetadata(
        for preset: NotationFontPreset,
        fromRuntimeResources resourceURL: URL?
    ) -> SmuflFontMetadata? {
        loadMetadata(for: preset, fromResourceBaseURL: resourceURL)
    }

    private static func metadataURL(
        for preset: NotationFontPreset,
        relativeTo baseURL: URL
    ) -> URL? {
        let fileName = preset.smuflMetadataFileName
        let directoryName = preset.smuflMetadataDirectoryName
        let candidateURLs = [
            baseURL.appendingPathComponent(directoryName).appendingPathComponent(fileName),
            baseURL.appendingPathComponent(fileName),
            baseURL.appendingPathComponent("SMuFL").appendingPathComponent(directoryName).appendingPathComponent(fileName),
            baseURL.appendingPathComponent("NotationFonts").appendingPathComponent("SMuFL").appendingPathComponent(directoryName).appendingPathComponent(fileName),
            baseURL.appendingPathComponent("ThirdParty").appendingPathComponent("NotationFonts").appendingPathComponent("SMuFL").appendingPathComponent(directoryName).appendingPathComponent(fileName)
        ]

        if let directMatch = candidateURLs.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            return directMatch
        }

        guard let enumerator = FileManager.default.enumerator(
            at: baseURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        for case let candidateURL as URL in enumerator {
            guard candidateURL.lastPathComponent == fileName,
                  candidateURL.deletingLastPathComponent().lastPathComponent == directoryName else {
                continue
            }

            return candidateURL
        }

        return nil
    }
}
