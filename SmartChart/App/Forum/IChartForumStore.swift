import Combine
import Foundation
import Supabase

struct IChartForumSongSummary: Identifiable, Equatable {
    let song: ForumSong
    let topPosts: [ForumChartPost]

    var id: UUID { song.id }
}

struct IChartForumPostDetail: Equatable {
    let song: ForumSong
    let post: ForumChartPost
    let comments: [ForumComment]
    let authorBadges: [ForumAuthorBadge]
    let currentUserVote: ForumVoteValue?
}

enum IChartForumState: Equatable {
    case unconfigured
    case signedOut
    case requiresPro
    case loading
    case loaded([IChartForumSongSummary])
    case failed(String)

    var isLoaded: Bool {
        guard case .loaded = self else {
            return false
        }

        return true
    }
}

@MainActor
final class IChartForumStore: ObservableObject {
    @Published private(set) var state: IChartForumState
    @Published private(set) var selectedDetail: IChartForumPostDetail?
    @Published private(set) var isWorking = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var downloadedPDF: ExportedPDF?

    private let service: IChartForumServicing
    private var lastQuery = ""

    private init(service: IChartForumServicing) {
        self.service = service
        state = service.isConfigured ? .signedOut : .unconfigured
    }

    static func live(clients: IChartSupabaseClients?) -> IChartForumStore {
        guard let clients else {
            return IChartForumStore(service: IChartUnconfiguredForumService())
        }

        return IChartForumStore(
            service: IChartSupabaseForumService(
                client: clients.dataClient,
                sessionRefresher: IChartSupabaseSessionRefresher(
                    authClient: clients.authClient,
                    sessionStore: clients.sessionStore
                ),
                pdfExporter: PDFChartExporter.live()
            )
        )
    }

    func refresh(
        authState: IChartAuthState,
        entitlements: AppEntitlements,
        query: String? = nil
    ) async {
        guard service.isConfigured else {
            state = .unconfigured
            selectedDetail = nil
            return
        }

        guard authState.signedInSession != nil else {
            state = .signedOut
            selectedDetail = nil
            return
        }

        guard entitlements.includes(.forums) else {
            state = .requiresPro
            selectedDetail = nil
            return
        }

        let nextQuery = query ?? lastQuery
        lastQuery = nextQuery
        state = .loading
        await run {
            let summaries = try await service.loadHome(query: nextQuery)
            state = .loaded(summaries)
        }
    }

    func openPost(_ post: ForumChartPost, song: ForumSong) async {
        selectedDetail = nil
        await run {
            try await refreshSelectedDetail(postID: post.id, song: song)
        }
    }

    func publish(chart: Chart, draft: ForumPublishDraft) async {
        isWorking = true
        statusMessage = nil
        errorMessage = nil
        do {
            let detail = try await service.publish(chart: chart, draft: draft)
            selectedDetail = detail
            statusMessage = "Forum chart submitted for review."
            let summaries = try await service.loadHome(query: lastQuery)
            state = .loaded(summaries)
        } catch {
            errorMessage = Self.displayText(for: error)
        }
        isWorking = false
    }

    func vote(_ vote: ForumVoteValue, on detail: IChartForumPostDetail) async {
        await run {
            try await service.vote(postID: detail.post.id, vote: vote)
            try await refreshSelectedDetail(postID: detail.post.id, song: detail.song)
            state = .loaded(try await service.loadHome(query: lastQuery))
        }
    }

    func addComment(_ body: String, to detail: IChartForumPostDetail) async {
        await run {
            try await service.addComment(postID: detail.post.id, body: body)
            try await refreshSelectedDetail(postID: detail.post.id, song: detail.song)
        }
    }

    func reportPost(_ reason: ForumReportReason, detailText: String?, detail: IChartForumPostDetail) async {
        await run(successMessage: "Report sent.") {
            try await service.reportPost(postID: detail.post.id, reason: reason, detail: detailText)
            try await refreshSelectedDetail(postID: detail.post.id, song: detail.song)
        }
    }

    func reportComment(_ comment: ForumComment, reason: ForumReportReason, detailText: String?, detail: IChartForumPostDetail) async {
        await run(successMessage: "Report sent.") {
            try await service.reportComment(commentID: comment.id, reason: reason, detail: detailText)
            try await refreshSelectedDetail(postID: detail.post.id, song: detail.song)
        }
    }

    @discardableResult
    func downloadPDF(for detail: IChartForumPostDetail) async -> ExportedPDF? {
        var downloadedPDF: ExportedPDF?
        await run {
            let pdf = try await service.downloadPDF(for: detail.post)
            self.downloadedPDF = pdf
            downloadedPDF = pdf
        }
        return downloadedPDF
    }

    func presentDownloadedPDF(_ pdf: ExportedPDF) {
        downloadedPDF = pdf
    }

    func showDownloadStorageError(_ message: String) {
        errorMessage = message
    }

    func clearDownloadedPDF() {
        downloadedPDF = nil
    }

    func clearSelectedDetail() {
        selectedDetail = nil
    }

    private func run(
        successMessage: String? = nil,
        operation: () async throws -> Void
    ) async {
        isWorking = true
        statusMessage = nil
        errorMessage = nil
        do {
            try await operation()
            statusMessage = successMessage
        } catch {
            let text = Self.displayText(for: error)
            errorMessage = text
            if case .loading = state {
                state = .failed(text)
            }
        }
        isWorking = false
    }

    private func refreshSelectedDetail(postID: UUID, song: ForumSong) async throws {
        do {
            selectedDetail = try await service.loadPostDetail(postID: postID, song: song)
        } catch IChartForumServiceError.missingForumPost {
            selectedDetail = nil
            downloadedPDF = nil
            if let summaries = try? await service.loadHome(query: lastQuery) {
                state = .loaded(summaries)
            }
            throw IChartForumServiceError.missingForumPost
        }
    }

    private static func displayText(for error: Error) -> String {
        if let urlError = error as? URLError,
           [.notConnectedToInternet, .timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost].contains(urlError.code) {
            return temporaryServiceInterruptionText
        }

        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }

        return error.localizedDescription
    }

    private static var temporaryServiceInterruptionText: String {
        "We can’t reach community charts right now. Your local charts are safe, and this page will work again when service returns."
    }
}

private protocol IChartForumServicing: Sendable {
    var isConfigured: Bool { get }
    func loadHome(query: String) async throws -> [IChartForumSongSummary]
    func loadPostDetail(postID: UUID, song: ForumSong) async throws -> IChartForumPostDetail
    func publish(chart: Chart, draft: ForumPublishDraft) async throws -> IChartForumPostDetail
    func vote(postID: UUID, vote: ForumVoteValue) async throws
    func addComment(postID: UUID, body: String) async throws
    func reportPost(postID: UUID, reason: ForumReportReason, detail: String?) async throws
    func reportComment(commentID: UUID, reason: ForumReportReason, detail: String?) async throws
    func downloadPDF(for post: ForumChartPost) async throws -> ExportedPDF
}

private struct IChartUnconfiguredForumService: IChartForumServicing {
    let isConfigured = false

    func loadHome(query: String) async throws -> [IChartForumSongSummary] { [] }
    func loadPostDetail(postID: UUID, song: ForumSong) async throws -> IChartForumPostDetail {
        throw IChartForumServiceError.unconfigured
    }
    func publish(chart: Chart, draft: ForumPublishDraft) async throws -> IChartForumPostDetail {
        throw IChartForumServiceError.unconfigured
    }
    func vote(postID: UUID, vote: ForumVoteValue) async throws {
        throw IChartForumServiceError.unconfigured
    }
    func addComment(postID: UUID, body: String) async throws {
        throw IChartForumServiceError.unconfigured
    }
    func reportPost(postID: UUID, reason: ForumReportReason, detail: String?) async throws {
        throw IChartForumServiceError.unconfigured
    }
    func reportComment(commentID: UUID, reason: ForumReportReason, detail: String?) async throws {
        throw IChartForumServiceError.unconfigured
    }
    func downloadPDF(for post: ForumChartPost) async throws -> ExportedPDF {
        throw IChartForumServiceError.unconfigured
    }
}

private enum IChartForumServiceError: LocalizedError {
    case unconfigured
    case missingChart
    case invalidPublishDraft(String)
    case missingForumPost

    var errorDescription: String? {
        switch self {
        case .unconfigured:
            return "We can’t reach community charts right now. Your local charts are safe, and this page will work again when service returns."
        case .missingChart:
            return "Choose a local iChart chart before publishing."
        case .invalidPublishDraft(let message):
            return message
        case .missingForumPost:
            return "This forum chart is no longer available."
        }
    }
}

private actor IChartSupabaseForumService: IChartForumServicing {
    let isConfigured = true

    private let client: SupabaseClient
    private let sessionRefresher: IChartSupabaseSessionRefresher
    private let pdfExporter: PDFChartExporter
    private let bucketID = "forum_chart_pdfs"

    init(
        client: SupabaseClient,
        sessionRefresher: IChartSupabaseSessionRefresher,
        pdfExporter: PDFChartExporter
    ) {
        self.client = client
        self.sessionRefresher = sessionRefresher
        self.pdfExporter = pdfExporter
    }

    func loadHome(query: String) async throws -> [IChartForumSongSummary] {
        _ = try await refreshedSessionForRequest()
        let songs: [ForumSongRow] = try await client
            .from("forum_songs")
            .select()
            .order("updated_at", ascending: false)
            .limit(80)
            .execute()
            .value
        let posts: [ForumChartPostRow] = try await client
            .from("forum_chart_posts")
            .select()
            .order("ranking_score", ascending: false)
            .order("published_at", ascending: false)
            .limit(160)
            .execute()
            .value

        let mappedSongs = songs.map(\.forumSong)
        let mappedPosts = posts
            .map(\.forumChartPost)
            .filter { $0.status != .pending }
        let normalizedQuery = ForumPublishDraft.normalizedIdentityText(query)
        let postsBySongID = Dictionary(grouping: mappedPosts, by: \.songID)

        return mappedSongs
            .compactMap { song in
                let topPosts = Array(
                    (postsBySongID[song.id] ?? [])
                        .sorted { lhs, rhs in
                            if lhs.rankingScore == rhs.rankingScore {
                                return lhs.publishedAt > rhs.publishedAt
                            }
                            return lhs.rankingScore > rhs.rankingScore
                        }
                        .prefix(3)
                )
                guard !topPosts.isEmpty else {
                    return nil
                }

                guard normalizedQuery.isEmpty
                    || Self.matches(query: normalizedQuery, song: song, posts: topPosts) else {
                    return nil
                }

                return IChartForumSongSummary(song: song, topPosts: topPosts)
            }
    }

    func loadPostDetail(postID: UUID, song: ForumSong) async throws -> IChartForumPostDetail {
        let currentUserID = try await currentUserIDForRequest()
        let postRows: [ForumChartPostRow] = try await client
            .from("forum_chart_posts")
            .select()
            .eq("id", value: postID)
            .limit(1)
            .execute()
            .value
        guard let post = postRows.first?.forumChartPost else {
            throw IChartForumServiceError.missingForumPost
        }

        let comments: [ForumCommentRow] = try await client
            .from("forum_comments")
            .select()
            .eq("post_id", value: postID)
            .order("created_at", ascending: true)
            .limit(80)
            .execute()
            .value
        let badges: [ForumAuthorBadgeRow] = try await client
            .from("forum_author_badges")
            .select()
            .eq("owner_id", value: post.ownerID)
            .execute()
            .value
        let votes: [ForumVoteRow] = try await client
            .from("forum_votes")
            .select()
            .eq("post_id", value: postID)
            .eq("owner_id", value: currentUserID)
            .limit(1)
            .execute()
            .value

        return IChartForumPostDetail(
            song: song,
            post: post,
            comments: comments.map(\.forumComment),
            authorBadges: badges.map(\.forumAuthorBadge),
            currentUserVote: votes.first?.forumVoteValue
        )
    }

    func publish(chart: Chart, draft: ForumPublishDraft) async throws -> IChartForumPostDetail {
        let validationErrors = draft.validationErrors(availableChartIDs: [chart.id])
        guard validationErrors.isEmpty else {
            throw IChartForumServiceError.invalidPublishDraft(
                validationErrors.map(\.message).joined(separator: " ")
            )
        }

        let ownerID = try await currentUserIDForRequest()
        let postID = UUID()
        let storagePath = draft.storagePath(ownerID: ownerID, postID: postID)
        let exportedPDF = try await pdfExporter.exportPDF(
            for: chart,
            context: ChartPDFExportContext(
                forumCredit: ForumPDFCredit(
                    creatorDisplayName: ForumPublishDraft.normalizedDisplayText(draft.creatorDisplayName),
                    forumPostID: postID,
                    exportedAt: Date()
                )
            )
        )
        let pdfData = try Data(contentsOf: exportedPDF.url)
        try await client.storage
            .from(bucketID)
            .upload(
                storagePath,
                data: pdfData,
                options: FileOptions(
                    cacheControl: "3600",
                    contentType: "application/pdf",
                    upsert: false
                )
            )

        let song: ForumSong
        var shouldRollbackUploadedPDF = true
        do {
            song = try await resolvedSong(for: draft, ownerID: ownerID)
            let postInsert = ForumChartPostInsert(
                id: postID,
                songID: song.id,
                ownerID: ownerID,
                localChartID: chart.id,
                chartTitle: draft.resolvedChartTitle,
                arrangerCredit: ForumPublishDraft.normalizedDisplayText(draft.arrangerCredit),
                creatorDisplayName: ForumPublishDraft.normalizedDisplayText(draft.creatorDisplayName),
                tags: draft.sanitizedTags,
                versionNote: ForumPublishDraft.normalizedDisplayText(draft.versionNote).nilIfEmpty,
                layoutStyle: chart.layoutStyle.rawValue,
                pdfStoragePath: storagePath
            )
            try await client
                .from("forum_chart_posts")
                .insert(postInsert)
                .execute()
            shouldRollbackUploadedPDF = false
        } catch {
            if shouldRollbackUploadedPDF {
                await rollbackUploadedForumPDF(at: storagePath)
            }
            throw error
        }

        return try await loadPostDetail(postID: postID, song: song)
    }

    func vote(postID: UUID, vote: ForumVoteValue) async throws {
        let ownerID = try await currentUserIDForRequest()
        let existingVotes: [ForumVoteRow] = try await client
            .from("forum_votes")
            .select()
            .eq("post_id", value: postID)
            .eq("owner_id", value: ownerID)
            .limit(1)
            .execute()
            .value

        if let existingVote = existingVotes.first {
            try await client
                .from("forum_votes")
                .update(ForumVoteUpdate(voteValue: vote.rawValue))
                .eq("id", value: existingVote.id)
                .execute()
        } else {
            try await client
                .from("forum_votes")
                .insert(ForumVoteInsert(postID: postID, ownerID: ownerID, voteValue: vote.rawValue))
                .execute()
        }
    }

    func addComment(postID: UUID, body: String) async throws {
        let sanitizedBody = ForumPublishDraft.normalizedDisplayText(body)
        guard !sanitizedBody.isEmpty else {
            return
        }

        let ownerID = try await currentUserIDForRequest()
        try await client
            .from("forum_comments")
            .insert(ForumCommentInsert(postID: postID, ownerID: ownerID, body: sanitizedBody))
            .execute()
    }

    func reportPost(postID: UUID, reason: ForumReportReason, detail: String?) async throws {
        let ownerID = try await currentUserIDForRequest()
        try await client
            .from("forum_reports")
            .insert(
                ForumReportInsert(
                    ownerID: ownerID,
                    targetType: "post",
                    postID: postID,
                    commentID: nil,
                    reason: reason.rawValue,
                    detail: ForumPublishDraft.normalizedDisplayText(detail ?? "").nilIfEmpty
                )
            )
            .execute()
    }

    func reportComment(commentID: UUID, reason: ForumReportReason, detail: String?) async throws {
        let ownerID = try await currentUserIDForRequest()
        try await client
            .from("forum_reports")
            .insert(
                ForumReportInsert(
                    ownerID: ownerID,
                    targetType: "comment",
                    postID: nil,
                    commentID: commentID,
                    reason: reason.rawValue,
                    detail: ForumPublishDraft.normalizedDisplayText(detail ?? "").nilIfEmpty
                )
            )
            .execute()
    }

    func downloadPDF(for post: ForumChartPost) async throws -> ExportedPDF {
        _ = try await refreshedSessionForRequest()
        let data = try await client.storage
            .from(bucketID)
            .download(path: post.pdfStoragePath)
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("iChartForumPDFs", isDirectory: true)
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("iChartForumPDFs", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let outputURL = directory.appendingPathComponent(
            PDFChartExporter.sanitizedFileNameStem(from: post.chartTitle) + " - Forum.pdf"
        )
        try data.write(to: outputURL, options: .atomic)

        return ExportedPDF(
            url: outputURL,
            chartTitle: post.chartTitle,
            layoutStyle: post.layoutStyle,
            transpositionView: .concert,
            chordTranspositionSemitones: 0,
            pageCount: 1,
            fileSizeBytes: data.count,
            exportedAt: Date()
        )
    }

    private func refreshedSessionForRequest() async throws -> Session {
        try await sessionRefresher.refreshIfNeeded()
    }

    private func currentUserIDForRequest() async throws -> UUID {
        let session = try await refreshedSessionForRequest()
        return session.user.id
    }

    private func rollbackUploadedForumPDF(at path: String) async {
        do {
            try await client.storage
                .from(bucketID)
                .remove(paths: [path])
        } catch {
            // Keep the original publish error visible; cleanup can also fail if the object was already attached.
        }
    }

    private func resolvedSong(for draft: ForumPublishDraft, ownerID: UUID) async throws -> ForumSong {
        let existingRows = try await songRows(
            normalizedSongTitle: draft.normalizedSongTitle,
            normalizedArtistName: draft.normalizedArtistName
        )
        if let existing = existingRows.first?.forumSong {
            return existing
        }

        let insert = ForumSongInsert(
            id: UUID(),
            songTitle: ForumPublishDraft.normalizedDisplayText(draft.songTitle),
            artistName: ForumPublishDraft.normalizedDisplayText(draft.artistName),
            normalizedSongTitle: draft.normalizedSongTitle,
            normalizedArtistName: draft.normalizedArtistName,
            createdBy: ownerID
        )

        do {
            try await client
                .from("forum_songs")
                .insert(insert)
                .execute()
        } catch {
            let rows = try await songRows(
                normalizedSongTitle: draft.normalizedSongTitle,
                normalizedArtistName: draft.normalizedArtistName
            )
            if let existing = rows.first?.forumSong {
                return existing
            }
            throw error
        }

        return insert.forumSong
    }

    private func songRows(
        normalizedSongTitle: String,
        normalizedArtistName: String
    ) async throws -> [ForumSongRow] {
        try await client
            .from("forum_songs")
            .select()
            .eq("normalized_song_title", value: normalizedSongTitle)
            .eq("normalized_artist_name", value: normalizedArtistName)
            .limit(1)
            .execute()
            .value
    }

    private static func matches(
        query: String,
        song: ForumSong,
        posts: [ForumChartPost]
    ) -> Bool {
        let searchable = (
            [
                song.songTitle,
                song.artistName
            ]
            + posts.flatMap { post in
                [post.chartTitle, post.arrangerCredit, post.creatorDisplayName] + post.tags
            }
        )
        .map(ForumPublishDraft.normalizedIdentityText)
        .joined(separator: " ")

        return searchable.contains(query)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private enum IChartForumDateParser {
    static func date(from value: String?) -> Date {
        guard let value,
              let date = fractionalFormatter.date(from: value) ?? wholeSecondFormatter.date(from: value) else {
            return Date(timeIntervalSince1970: 0)
        }

        return date
    }

    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let wholeSecondFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

private struct ForumSongRow: Decodable {
    let id: UUID
    let songTitle: String
    let artistName: String

    var forumSong: ForumSong {
        ForumSong(id: id, songTitle: songTitle, artistName: artistName)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case songTitle = "song_title"
        case artistName = "artist_name"
    }
}

private struct ForumSongInsert: Encodable {
    let id: UUID
    let songTitle: String
    let artistName: String
    let normalizedSongTitle: String
    let normalizedArtistName: String
    let createdBy: UUID

    var forumSong: ForumSong {
        ForumSong(id: id, songTitle: songTitle, artistName: artistName)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case songTitle = "song_title"
        case artistName = "artist_name"
        case normalizedSongTitle = "normalized_song_title"
        case normalizedArtistName = "normalized_artist_name"
        case createdBy = "created_by"
    }
}

private struct ForumChartPostRow: Decodable {
    let id: UUID
    let songID: UUID
    let ownerID: UUID
    let chartTitle: String
    let arrangerCredit: String
    let creatorDisplayName: String
    let tags: [String]
    let versionNote: String?
    let layoutStyle: String
    let pdfStoragePath: String
    let status: String
    let voteUpCount: Int
    let voteDownCount: Int
    let reportCount: Int
    let rankingScore: Double
    let publishedAt: String?

    var forumChartPost: ForumChartPost {
        ForumChartPost(
            id: id,
            songID: songID,
            ownerID: ownerID,
            chartTitle: chartTitle,
            arrangerCredit: arrangerCredit,
            creatorDisplayName: creatorDisplayName,
            tags: tags,
            versionNote: versionNote,
            layoutStyle: ChartLayoutStyle(rawValue: layoutStyle) ?? .leadSheet,
            pdfStoragePath: pdfStoragePath,
            status: ForumPostModerationStatus(rawValue: status) ?? .pending,
            voteUpCount: voteUpCount,
            voteDownCount: voteDownCount,
            reportCount: reportCount,
            rankingScore: rankingScore,
            publishedAt: IChartForumDateParser.date(from: publishedAt)
        )
    }

    enum CodingKeys: String, CodingKey {
        case id
        case songID = "song_id"
        case ownerID = "owner_id"
        case chartTitle = "chart_title"
        case arrangerCredit = "arranger_credit"
        case creatorDisplayName = "creator_display_name"
        case tags
        case versionNote = "version_note"
        case layoutStyle = "layout_style"
        case pdfStoragePath = "pdf_storage_path"
        case status
        case voteUpCount = "vote_up_count"
        case voteDownCount = "vote_down_count"
        case reportCount = "report_count"
        case rankingScore = "ranking_score"
        case publishedAt = "published_at"
    }
}

private struct ForumChartPostInsert: Encodable {
    let id: UUID
    let songID: UUID
    let ownerID: UUID
    let localChartID: UUID
    let chartTitle: String
    let arrangerCredit: String
    let creatorDisplayName: String
    let tags: [String]
    let versionNote: String?
    let layoutStyle: String
    let pdfStoragePath: String
    let status: String = ForumPostModerationStatus.pending.rawValue

    enum CodingKeys: String, CodingKey {
        case id
        case songID = "song_id"
        case ownerID = "owner_id"
        case localChartID = "local_chart_id"
        case chartTitle = "chart_title"
        case arrangerCredit = "arranger_credit"
        case creatorDisplayName = "creator_display_name"
        case tags
        case versionNote = "version_note"
        case layoutStyle = "layout_style"
        case pdfStoragePath = "pdf_storage_path"
        case status
    }
}

private struct ForumCommentRow: Decodable {
    let id: UUID
    let postID: UUID
    let ownerID: UUID
    let body: String
    let createdAt: String?

    var forumComment: ForumComment {
        ForumComment(
            id: id,
            postID: postID,
            ownerID: ownerID,
            creatorDisplayName: nil,
            body: body,
            createdAt: IChartForumDateParser.date(from: createdAt)
        )
    }

    enum CodingKeys: String, CodingKey {
        case id
        case postID = "post_id"
        case ownerID = "owner_id"
        case body
        case createdAt = "created_at"
    }
}

private struct ForumCommentInsert: Encodable {
    let postID: UUID
    let ownerID: UUID
    let body: String

    enum CodingKeys: String, CodingKey {
        case postID = "post_id"
        case ownerID = "owner_id"
        case body
    }
}

private struct ForumVoteRow: Decodable {
    let id: UUID
    let voteValue: Int

    var forumVoteValue: ForumVoteValue? {
        ForumVoteValue(rawValue: voteValue)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case voteValue = "vote_value"
    }
}

private struct ForumVoteInsert: Encodable {
    let postID: UUID
    let ownerID: UUID
    let voteValue: Int

    enum CodingKeys: String, CodingKey {
        case postID = "post_id"
        case ownerID = "owner_id"
        case voteValue = "vote_value"
    }
}

private struct ForumVoteUpdate: Encodable {
    let voteValue: Int

    enum CodingKeys: String, CodingKey {
        case voteValue = "vote_value"
    }
}

private struct ForumReportInsert: Encodable {
    let ownerID: UUID
    let targetType: String
    let postID: UUID?
    let commentID: UUID?
    let reason: String
    let detail: String?

    enum CodingKeys: String, CodingKey {
        case ownerID = "owner_id"
        case targetType = "target_type"
        case postID = "post_id"
        case commentID = "comment_id"
        case reason
        case detail
    }
}

private struct ForumAuthorBadgeRow: Decodable {
    let id: UUID
    let ownerID: UUID
    let badgeType: String
    let awardedAt: String?

    var forumAuthorBadge: ForumAuthorBadge {
        ForumAuthorBadge(
            id: id,
            ownerID: ownerID,
            badgeType: ForumAuthorBadgeType(rawValue: badgeType) ?? .verifiedContributor,
            awardedAt: IChartForumDateParser.date(from: awardedAt)
        )
    }

    enum CodingKeys: String, CodingKey {
        case id
        case ownerID = "owner_id"
        case badgeType = "badge_type"
        case awardedAt = "awarded_at"
    }
}
