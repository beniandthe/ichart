import Foundation

enum ForumPostModerationStatus: String, Codable, CaseIterable, Hashable, Identifiable {
    case published
    case flagged
    case hidden
    case removed

    var id: String { rawValue }
}

enum ForumPostQualityStatus: String, Codable, CaseIterable, Hashable, Identifiable {
    case new
    case topRated
    case active
    case needsReview
    case hidden
    case removed

    var id: String { rawValue }

    var displayText: String {
        switch self {
        case .new:
            return "New"
        case .topRated:
            return "Top Rated"
        case .active:
            return "Community Rated"
        case .needsReview:
            return "Needs Review"
        case .hidden:
            return "Hidden"
        case .removed:
            return "Removed"
        }
    }
}

enum ForumVoteValue: Int, Codable, CaseIterable, Hashable, Identifiable {
    case down = -1
    case up = 1

    var id: Int { rawValue }
}

enum ForumReportReason: String, Codable, CaseIterable, Hashable, Identifiable {
    case wrongChords
    case wrongForm
    case badFormatting
    case spam
    case abuse
    case copyrightConcern
    case other

    var id: String { rawValue }

    var displayText: String {
        switch self {
        case .wrongChords:
            return "Wrong Chords"
        case .wrongForm:
            return "Wrong Form"
        case .badFormatting:
            return "Bad Formatting"
        case .spam:
            return "Spam"
        case .abuse:
            return "Abuse"
        case .copyrightConcern:
            return "Copyright Concern"
        case .other:
            return "Other"
        }
    }
}

enum ForumAuthorBadgeType: String, Codable, CaseIterable, Hashable, Identifiable {
    case verifiedContributor
    case trustedArranger
    case communityExpert

    var id: String { rawValue }

    var displayText: String {
        switch self {
        case .verifiedContributor:
            return "Verified Contributor"
        case .trustedArranger:
            return "Trusted Arranger"
        case .communityExpert:
            return "Community Expert"
        }
    }
}

struct ForumSong: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var songTitle: String
    var artistName: String
}

struct ForumChartPost: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var songID: UUID
    var ownerID: UUID
    var chartTitle: String
    var arrangerCredit: String
    var creatorDisplayName: String
    var tags: [String]
    var versionNote: String?
    var layoutStyle: ChartLayoutStyle
    var pdfStoragePath: String
    var status: ForumPostModerationStatus
    var voteUpCount: Int
    var voteDownCount: Int
    var reportCount: Int
    var rankingScore: Double
    var publishedAt: Date

    var qualityStatus: ForumPostQualityStatus {
        ForumQualityPolicy.displayStatus(
            moderationStatus: status,
            upVotes: voteUpCount,
            downVotes: voteDownCount,
            reports: reportCount
        )
    }

    var voteSummaryText: String {
        ForumQualityPolicy.voteSummaryText(upVotes: voteUpCount, downVotes: voteDownCount)
    }
}

struct ForumComment: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var postID: UUID
    var ownerID: UUID
    var creatorDisplayName: String?
    var body: String
    var createdAt: Date
}

struct ForumAuthorBadge: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var ownerID: UUID
    var badgeType: ForumAuthorBadgeType
    var awardedAt: Date
}

struct ForumPublishDraft: Equatable, Hashable {
    var selectedChartID: Chart.ID?
    var songTitle = ""
    var artistName = ""
    var chartTitle = ""
    var arrangerCredit = ""
    var creatorDisplayName = ""
    var tagsText = ""
    var versionNote = ""

    var normalizedSongTitle: String {
        Self.normalizedIdentityText(songTitle)
    }

    var normalizedArtistName: String {
        Self.normalizedIdentityText(artistName)
    }

    var sanitizedTags: [String] {
        tagsText
            .split(separator: ",")
            .map { Self.normalizedDisplayText(String($0)) }
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { tags, tag in
                if !tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
                    tags.append(tag)
                }
            }
            .prefix(8)
            .map { String($0) }
    }

    func validationErrors(availableChartIDs: Set<Chart.ID>) -> [ForumPublishValidationError] {
        var errors: [ForumPublishValidationError] = []

        guard let selectedChartID, availableChartIDs.contains(selectedChartID) else {
            errors.append(.missingChart)
            return errors
        }

        if Self.normalizedDisplayText(songTitle).isEmpty {
            errors.append(.missingSongTitle)
        }

        if Self.normalizedDisplayText(artistName).isEmpty {
            errors.append(.missingArtistName)
        }

        if Self.normalizedDisplayText(chartTitle).isEmpty {
            errors.append(.missingChartTitle)
        }

        if Self.normalizedDisplayText(arrangerCredit).isEmpty {
            errors.append(.missingArrangerCredit)
        }

        if Self.normalizedDisplayText(creatorDisplayName).isEmpty {
            errors.append(.missingCreatorDisplayName)
        }

        return errors
    }

    func storagePath(ownerID: UUID, postID: UUID) -> String {
        "\(ownerID.uuidString.lowercased())/\(postID.uuidString.lowercased()).pdf"
    }

    static func normalizedDisplayText(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizedIdentityText(_ text: String) -> String {
        normalizedDisplayText(text).lowercased()
    }
}

enum ForumPublishValidationError: String, Codable, CaseIterable, Hashable, Identifiable {
    case missingChart
    case missingSongTitle
    case missingArtistName
    case missingChartTitle
    case missingArrangerCredit
    case missingCreatorDisplayName

    var id: String { rawValue }

    var message: String {
        switch self {
        case .missingChart:
            return "Choose a chart to publish."
        case .missingSongTitle:
            return "Add the song title."
        case .missingArtistName:
            return "Add the artist."
        case .missingChartTitle:
            return "Add the chart title."
        case .missingArrangerCredit:
            return "Add arranger credit."
        case .missingCreatorDisplayName:
            return "Add your display name."
        }
    }
}

enum ForumQualityPolicy {
    static let topRatedMinimumVotes = 5
    static let topRatedPositiveRatio = 0.80
    static let downvoteReviewMinimumVotes = 5
    static let downvoteReviewRatio = 0.70
    static let reportReviewThreshold = 3

    static func rankingScore(upVotes: Int, downVotes: Int, reports: Int) -> Double {
        let totalVotes = max(0, upVotes) + max(0, downVotes)
        guard totalVotes > 0 else {
            return 0
        }

        let positiveRatio = Double(max(0, upVotes)) / Double(totalVotes)
        return (positiveRatio * log(Double(totalVotes) + 1))
            - (Double(max(0, downVotes)) * 0.18)
            - (Double(max(0, reports)) * 0.35)
    }

    static func displayStatus(
        moderationStatus: ForumPostModerationStatus,
        upVotes: Int,
        downVotes: Int,
        reports: Int
    ) -> ForumPostQualityStatus {
        switch moderationStatus {
        case .hidden:
            return .hidden
        case .removed:
            return .removed
        case .flagged:
            return .needsReview
        case .published:
            break
        }

        let totalVotes = max(0, upVotes) + max(0, downVotes)
        guard totalVotes > 0 else {
            return .new
        }

        if reports >= reportReviewThreshold {
            return .needsReview
        }

        if totalVotes >= downvoteReviewMinimumVotes,
           Double(max(0, downVotes)) / Double(totalVotes) >= downvoteReviewRatio {
            return .needsReview
        }

        if totalVotes >= topRatedMinimumVotes,
           Double(max(0, upVotes)) / Double(totalVotes) >= topRatedPositiveRatio {
            return .topRated
        }

        return .active
    }

    static func voteSummaryText(upVotes: Int, downVotes: Int) -> String {
        "\(max(0, upVotes)) up / \(max(0, downVotes)) down"
    }
}
