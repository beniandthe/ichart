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
    @Published private(set) var isQASampleDataEnabled: Bool

    private let service: IChartForumServicing
    private let qaSampleService = IChartForumQASampleService()
    private var lastQuery = ""

    private init(service: IChartForumServicing) {
        self.service = service
        #if DEBUG && targetEnvironment(simulator)
        isQASampleDataEnabled = UserDefaults.standard.bool(forKey: Self.qaSampleDataStorageKey)
        #else
        isQASampleDataEnabled = false
        #endif
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

    static let qaSampleDataStorageKey = "iChartForumQASampleDataEnabled"

    func setQASampleDataEnabled(_ isEnabled: Bool) {
        #if DEBUG && targetEnvironment(simulator)
        guard isQASampleDataEnabled != isEnabled else {
            return
        }

        isQASampleDataEnabled = isEnabled
        UserDefaults.standard.set(isEnabled, forKey: Self.qaSampleDataStorageKey)
        selectedDetail = nil
        downloadedPDF = nil
        statusMessage = isEnabled ? "Sample forum charts loaded." : nil
        errorMessage = nil
        #else
        isQASampleDataEnabled = false
        #endif
    }

    func refresh(
        authState: IChartAuthState,
        entitlements: AppEntitlements,
        query: String? = nil
    ) async {
        guard let signedInSession = authState.signedInSession else {
            state = .signedOut
            selectedDetail = nil
            return
        }

        guard entitlements.includes(.forums) else {
            state = .requiresPro
            selectedDetail = nil
            return
        }

        if isQASampleDataEnabled {
            await qaSampleService.setCurrentUserID(signedInSession.id)
        }

        let requestService = activeService
        guard requestService.isConfigured else {
            state = .unconfigured
            selectedDetail = nil
            return
        }

        let nextQuery = query ?? lastQuery
        lastQuery = nextQuery
        state = .loading
        await run {
            let summaries = try await requestService.loadHome(query: nextQuery)
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
            let requestService = activeService
            let detail = try await requestService.publish(chart: chart, draft: draft)
            selectedDetail = detail
            statusMessage = "Forum chart submitted for review."
            let summaries = try await requestService.loadHome(query: lastQuery)
            state = .loaded(summaries)
        } catch {
            errorMessage = Self.displayText(for: error)
        }
        isWorking = false
    }

    func vote(_ vote: ForumVoteValue, on detail: IChartForumPostDetail) async {
        await run {
            let requestService = activeService
            try await requestService.vote(postID: detail.post.id, vote: vote)
            try await refreshSelectedDetail(postID: detail.post.id, song: detail.song)
            state = .loaded(try await requestService.loadHome(query: lastQuery))
        }
    }

    func addComment(_ body: String, to detail: IChartForumPostDetail) async {
        await run {
            try await activeService.addComment(postID: detail.post.id, body: body)
            try await refreshSelectedDetail(postID: detail.post.id, song: detail.song)
        }
    }

    func reportPost(_ reason: ForumReportReason, detailText: String?, detail: IChartForumPostDetail) async {
        await run(successMessage: "Report sent.") {
            try await activeService.reportPost(postID: detail.post.id, reason: reason, detail: detailText)
            try await refreshSelectedDetail(postID: detail.post.id, song: detail.song)
        }
    }

    func reportComment(_ comment: ForumComment, reason: ForumReportReason, detailText: String?, detail: IChartForumPostDetail) async {
        await run(successMessage: "Report sent.") {
            try await activeService.reportComment(commentID: comment.id, reason: reason, detail: detailText)
            try await refreshSelectedDetail(postID: detail.post.id, song: detail.song)
        }
    }

    @discardableResult
    func downloadPDF(for detail: IChartForumPostDetail) async -> ExportedPDF? {
        var downloadedPDF: ExportedPDF?
        await run {
            let pdf = try await activeService.downloadPDF(for: detail.post)
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
            selectedDetail = try await activeService.loadPostDetail(postID: postID, song: song)
        } catch IChartForumServiceError.missingForumPost {
            selectedDetail = nil
            downloadedPDF = nil
            if let summaries = try? await activeService.loadHome(query: lastQuery) {
                state = .loaded(summaries)
            }
            throw IChartForumServiceError.missingForumPost
        }
    }

    private var activeService: IChartForumServicing {
        isQASampleDataEnabled ? qaSampleService : service
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

private actor IChartForumQASampleService: IChartForumServicing {
    let isConfigured = true

    private var currentUserID = UUID(uuidString: "90000000-0000-0000-0000-000000000001")!
    private var submittedSongs: [ForumSong] = []
    private var submittedPosts: [UUID: ForumChartPost] = [:]
    private var addedCommentsByPostID: [UUID: [ForumComment]] = [:]
    private var voteOverridesByPostID: [UUID: ForumVoteValue] = [:]
    private var reportAdjustmentsByPostID: [UUID: Int] = [:]

    func setCurrentUserID(_ userID: UUID) {
        currentUserID = userID
    }

    func loadHome(query: String) async throws -> [IChartForumSongSummary] {
        let normalizedQuery = ForumPublishDraft.normalizedIdentityText(query)
        let songs = allSongs()
        let postsBySongID = Dictionary(
            grouping: allPosts().filter { $0.status != .pending },
            by: \.songID
        )

        return songs
            .compactMap { song in
                let topPosts = Array(
                    (postsBySongID[song.id] ?? [])
                        .sorted(by: Self.ranksBefore)
                        .prefix(3)
                )

                guard !topPosts.isEmpty else {
                    return nil
                }

                guard normalizedQuery.isEmpty || Self.matches(query: normalizedQuery, song: song, posts: topPosts) else {
                    return nil
                }

                return IChartForumSongSummary(song: song, topPosts: topPosts)
            }
            .sorted { lhs, rhs in
                let lhsTopScore = lhs.topPosts.first?.rankingScore ?? 0
                let rhsTopScore = rhs.topPosts.first?.rankingScore ?? 0
                if lhsTopScore == rhsTopScore {
                    return lhs.song.songTitle.localizedCaseInsensitiveCompare(rhs.song.songTitle) == .orderedAscending
                }
                return lhsTopScore > rhsTopScore
            }
    }

    func loadPostDetail(postID: UUID, song: ForumSong) async throws -> IChartForumPostDetail {
        guard let post = allPosts().first(where: { $0.id == postID }) else {
            throw IChartForumServiceError.missingForumPost
        }

        let resolvedSong = allSongs().first(where: { $0.id == post.songID }) ?? song
        return IChartForumPostDetail(
            song: resolvedSong,
            post: post,
            comments: comments(for: postID),
            authorBadges: badges(for: post.ownerID),
            currentUserVote: voteOverridesByPostID[postID]
        )
    }

    func publish(chart: Chart, draft: ForumPublishDraft) async throws -> IChartForumPostDetail {
        let validationErrors = draft.validationErrors(availableChartIDs: [chart.id])
        guard validationErrors.isEmpty else {
            throw IChartForumServiceError.invalidPublishDraft(
                validationErrors.map(\.message).joined(separator: " ")
            )
        }

        let song = resolvedSong(for: draft)
        let postID = UUID()
        let post = ForumChartPost(
            id: postID,
            songID: song.id,
            ownerID: currentUserID,
            chartTitle: draft.resolvedChartTitle,
            arrangerCredit: ForumPublishDraft.normalizedDisplayText(draft.arrangerCredit),
            creatorDisplayName: ForumPublishDraft.normalizedDisplayText(draft.creatorDisplayName),
            tags: draft.sanitizedTags,
            versionNote: ForumPublishDraft.normalizedDisplayText(draft.versionNote).nilIfEmpty,
            layoutStyle: chart.layoutStyle,
            pdfStoragePath: "qa-samples/\(postID.uuidString.lowercased()).pdf",
            status: .pending,
            voteUpCount: 0,
            voteDownCount: 0,
            reportCount: 0,
            rankingScore: 0,
            publishedAt: Date()
        )
        submittedPosts[post.id] = post

        return try await loadPostDetail(postID: post.id, song: song)
    }

    func vote(postID: UUID, vote: ForumVoteValue) async throws {
        guard allPosts().contains(where: { $0.id == postID }) else {
            throw IChartForumServiceError.missingForumPost
        }

        voteOverridesByPostID[postID] = vote
    }

    func addComment(postID: UUID, body: String) async throws {
        let sanitizedBody = ForumPublishDraft.normalizedDisplayText(body)
        guard !sanitizedBody.isEmpty else {
            return
        }

        guard allPosts().contains(where: { $0.id == postID }) else {
            throw IChartForumServiceError.missingForumPost
        }

        let comment = ForumComment(
            id: UUID(),
            postID: postID,
            ownerID: currentUserID,
            creatorDisplayName: "You",
            body: sanitizedBody,
            createdAt: Date()
        )
        addedCommentsByPostID[postID, default: []].append(comment)
    }

    func reportPost(postID: UUID, reason: ForumReportReason, detail: String?) async throws {
        guard allPosts().contains(where: { $0.id == postID }) else {
            throw IChartForumServiceError.missingForumPost
        }

        reportAdjustmentsByPostID[postID, default: 0] += 1
    }

    func reportComment(commentID: UUID, reason: ForumReportReason, detail: String?) async throws {
        guard commentsByID()[commentID] != nil else {
            throw IChartForumServiceError.missingForumPost
        }
    }

    func downloadPDF(for post: ForumChartPost) async throws -> ExportedPDF {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("iChartForumQASamplePDFs", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(
            "\(PDFChartExporter.sanitizedFileNameStem(from: post.chartTitle)) - Forum Sample.pdf"
        )
        let data = Self.samplePDFData(title: post.chartTitle, creator: post.creatorDisplayName)
        try data.write(to: url, options: .atomic)

        return ExportedPDF(
            url: url,
            chartTitle: post.chartTitle,
            layoutStyle: post.layoutStyle,
            transpositionView: .concert,
            chordTranspositionSemitones: 0,
            pageCount: 1,
            fileSizeBytes: data.count,
            exportedAt: Date()
        )
    }

    private func resolvedSong(for draft: ForumPublishDraft) -> ForumSong {
        let normalizedSongTitle = draft.normalizedSongTitle
        let normalizedArtistName = draft.normalizedArtistName

        if let existing = allSongs().first(where: {
            ForumPublishDraft.normalizedIdentityText($0.songTitle) == normalizedSongTitle
                && ForumPublishDraft.normalizedIdentityText($0.artistName) == normalizedArtistName
        }) {
            return existing
        }

        let song = ForumSong(
            id: UUID(),
            songTitle: ForumPublishDraft.normalizedDisplayText(draft.songTitle),
            artistName: ForumPublishDraft.normalizedDisplayText(draft.artistName)
        )
        submittedSongs.append(song)
        return song
    }

    private func allSongs() -> [ForumSong] {
        sampleSongs + submittedSongs
    }

    private var sampleSongs: [ForumSong] {
        [
            ForumSong(id: Self.blueBossaSongID, songTitle: "Blue Bossa", artistName: "Kenny Dorham"),
            ForumSong(id: Self.cantaloupeSongID, songTitle: "Cantaloupe Island", artistName: "Herbie Hancock"),
            ForumSong(id: Self.justFriendsSongID, songTitle: "Just Friends", artistName: "John Klenner"),
            ForumSong(id: Self.anotherYouSongID, songTitle: "There Will Never Be Another You", artistName: "Harry Warren"),
            ForumSong(id: Self.actualProofSongID, songTitle: "Actual Proof", artistName: "Herbie Hancock")
        ]
    }

    private func allPosts() -> [ForumChartPost] {
        (samplePosts + Array(submittedPosts.values))
            .map(applyingLocalAdjustments)
    }

    private var samplePosts: [ForumChartPost] {
        let now = Date()
        return [
            post(
                id: Self.blueBossaRhythmPostID,
                songID: Self.blueBossaSongID,
                ownerID: currentUserID,
                chartTitle: "Blue Bossa - Rhythm Section Roadmap",
                arrangerCredit: "iChart Samples",
                creatorDisplayName: "Beni R.",
                tags: ["standard", "bossa", "rhythm section"],
                versionNote: "Clean rehearsal map with hits, repeats, and a short tag.",
                layoutStyle: .rhythmSectionSheet,
                status: .published,
                upVotes: 24,
                downVotes: 2,
                reports: 0,
                publishedAt: now.addingTimeInterval(-2 * 60 * 60)
            ),
            post(
                id: Self.blueBossaHornsPostID,
                songID: Self.blueBossaSongID,
                ownerID: Self.mayaOwnerID,
                chartTitle: "Blue Bossa - Horn Friendly Changes",
                arrangerCredit: "Maya Torres",
                creatorDisplayName: "Maya T.",
                tags: ["horns", "concert", "standard"],
                versionNote: "Compact chart for horn players reading with rhythm section.",
                layoutStyle: .simpleChordSheet,
                status: .published,
                upVotes: 11,
                downVotes: 3,
                reports: 0,
                publishedAt: now.addingTimeInterval(-18 * 60 * 60)
            ),
            post(
                id: Self.cantaloupePostID,
                songID: Self.cantaloupeSongID,
                ownerID: Self.jamalOwnerID,
                chartTitle: "Cantaloupe Island - Pocket Hits",
                arrangerCredit: "Jamal Reed",
                creatorDisplayName: "Jamal R.",
                tags: ["funk", "hits", "rhythm section"],
                versionNote: "Big form markers and simple hit language for a fast rehearsal.",
                layoutStyle: .rhythmSectionSheet,
                status: .published,
                upVotes: 19,
                downVotes: 0,
                reports: 0,
                publishedAt: now.addingTimeInterval(-4 * 24 * 60 * 60)
            ),
            post(
                id: Self.justFriendsPostID,
                songID: Self.justFriendsSongID,
                ownerID: Self.sophieOwnerID,
                chartTitle: "Just Friends - Jam Session Form",
                arrangerCredit: "Sophie Lane",
                creatorDisplayName: "Sophie L.",
                tags: ["standard", "jam session", "medium swing"],
                versionNote: nil,
                layoutStyle: .simpleChordSheet,
                status: .published,
                upVotes: 8,
                downVotes: 1,
                reports: 0,
                publishedAt: now.addingTimeInterval(-11 * 24 * 60 * 60)
            ),
            post(
                id: Self.anotherYouPostID,
                songID: Self.anotherYouSongID,
                ownerID: Self.nateOwnerID,
                chartTitle: "Another You - Gig Roadmap",
                arrangerCredit: "Nate Coleman",
                creatorDisplayName: "Nate C.",
                tags: ["standard", "gig book"],
                versionNote: "Short and clean for a singer rehearsal packet.",
                layoutStyle: .simpleChordSheet,
                status: .published,
                upVotes: 4,
                downVotes: 0,
                reports: 0,
                publishedAt: now.addingTimeInterval(-45 * 24 * 60 * 60)
            ),
            post(
                id: Self.actualProofPostID,
                songID: Self.actualProofSongID,
                ownerID: Self.eliOwnerID,
                chartTitle: "Actual Proof - Alt Form Check",
                arrangerCredit: "Eli Park",
                creatorDisplayName: "Eli P.",
                tags: ["fusion", "needs check"],
                versionNote: "Community review example with reports already attached.",
                layoutStyle: .rhythmSectionSheet,
                status: .flagged,
                upVotes: 2,
                downVotes: 7,
                reports: 2,
                publishedAt: now.addingTimeInterval(-20 * 24 * 60 * 60)
            )
        ]
    }

    private func post(
        id: UUID,
        songID: UUID,
        ownerID: UUID,
        chartTitle: String,
        arrangerCredit: String,
        creatorDisplayName: String,
        tags: [String],
        versionNote: String?,
        layoutStyle: ChartLayoutStyle,
        status: ForumPostModerationStatus,
        upVotes: Int,
        downVotes: Int,
        reports: Int,
        publishedAt: Date
    ) -> ForumChartPost {
        ForumChartPost(
            id: id,
            songID: songID,
            ownerID: ownerID,
            chartTitle: chartTitle,
            arrangerCredit: arrangerCredit,
            creatorDisplayName: creatorDisplayName,
            tags: tags,
            versionNote: versionNote,
            layoutStyle: layoutStyle,
            pdfStoragePath: "qa-samples/\(id.uuidString.lowercased()).pdf",
            status: status,
            voteUpCount: upVotes,
            voteDownCount: downVotes,
            reportCount: reports,
            rankingScore: ForumQualityPolicy.rankingScore(upVotes: upVotes, downVotes: downVotes, reports: reports),
            publishedAt: publishedAt
        )
    }

    private func applyingLocalAdjustments(to post: ForumChartPost) -> ForumChartPost {
        var adjustedPost = post
        if let vote = voteOverridesByPostID[post.id] {
            switch vote {
            case .up:
                adjustedPost.voteUpCount += 1
            case .down:
                adjustedPost.voteDownCount += 1
            }
        }
        adjustedPost.reportCount += reportAdjustmentsByPostID[post.id, default: 0]
        adjustedPost.rankingScore = ForumQualityPolicy.rankingScore(
            upVotes: adjustedPost.voteUpCount,
            downVotes: adjustedPost.voteDownCount,
            reports: adjustedPost.reportCount
        )
        return adjustedPost
    }

    private func comments(for postID: UUID) -> [ForumComment] {
        (sampleCommentsByPostID[postID] ?? []) + addedCommentsByPostID[postID, default: []]
    }

    private func commentsByID() -> [UUID: ForumComment] {
        Dictionary(
            uniqueKeysWithValues: (sampleCommentsByPostID.values.flatMap { $0 } + addedCommentsByPostID.values.flatMap { $0 })
                .map { ($0.id, $0) }
        )
    }

    private var sampleCommentsByPostID: [UUID: [ForumComment]] {
        [
            Self.blueBossaRhythmPostID: [
                comment(id: Self.blueBossaCommentOneID, postID: Self.blueBossaRhythmPostID, ownerID: Self.mayaOwnerID, creator: "Maya T.", body: "This one reads clean on a loud stage. The ending is easy to catch."),
                comment(id: Self.blueBossaCommentTwoID, postID: Self.blueBossaRhythmPostID, ownerID: Self.jamalOwnerID, creator: "Jamal R.", body: "Good roadmap for rhythm section. I would keep the tag exactly like this.")
            ],
            Self.cantaloupePostID: [
                comment(id: Self.cantaloupeCommentOneID, postID: Self.cantaloupePostID, ownerID: Self.sophieOwnerID, creator: "Sophie L.", body: "The hit layout is quick to scan. Nice for rehearsal.")
            ],
            Self.actualProofPostID: [
                comment(id: Self.actualProofCommentOneID, postID: Self.actualProofPostID, ownerID: Self.nateOwnerID, creator: "Nate C.", body: "Form might need review around the bridge.")
            ]
        ]
    }

    private func comment(id: UUID, postID: UUID, ownerID: UUID, creator: String, body: String) -> ForumComment {
        ForumComment(
            id: id,
            postID: postID,
            ownerID: ownerID,
            creatorDisplayName: creator,
            body: body,
            createdAt: Date().addingTimeInterval(-24 * 60 * 60)
        )
    }

    private func badges(for ownerID: UUID) -> [ForumAuthorBadge] {
        let badgeType: ForumAuthorBadgeType?
        if ownerID == currentUserID {
            badgeType = .trustedArranger
        } else if ownerID == Self.jamalOwnerID {
            badgeType = .communityExpert
        } else if ownerID == Self.mayaOwnerID {
            badgeType = .verifiedContributor
        } else {
            badgeType = nil
        }

        guard let badgeType else {
            return []
        }

        return [
            ForumAuthorBadge(
                id: UUID(uuidString: "70000000-0000-0000-0000-\(ownerID.uuidString.suffix(12))") ?? UUID(),
                ownerID: ownerID,
                badgeType: badgeType,
                awardedAt: Date().addingTimeInterval(-30 * 24 * 60 * 60)
            )
        ]
    }

    private static func ranksBefore(lhs: ForumChartPost, rhs: ForumChartPost) -> Bool {
        if lhs.rankingScore == rhs.rankingScore {
            return lhs.publishedAt > rhs.publishedAt
        }

        return lhs.rankingScore > rhs.rankingScore
    }

    private static func matches(query: String, song: ForumSong, posts: [ForumChartPost]) -> Bool {
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

    private static func samplePDFData(title: String, creator: String) -> Data {
        let stream = "BT /F1 18 Tf 36 156 Td (\(escapedPDFText(title))) Tj 0 -28 Td /F1 12 Tf (iChart Forum Sample - \(escapedPDFText(creator))) Tj ET"
        let objects = [
            "<< /Type /Catalog /Pages 2 0 R >>",
            "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 420 240] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>",
            "<< /Length \(stream.utf8.count) >>\nstream\n\(stream)\nendstream",
            "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"
        ]
        var pdf = "%PDF-1.4\n"
        var offsets: [Int] = []
        for (index, object) in objects.enumerated() {
            offsets.append(pdf.utf8.count)
            pdf += "\(index + 1) 0 obj\n\(object)\nendobj\n"
        }
        let xrefOffset = pdf.utf8.count
        pdf += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for offset in offsets {
            pdf += String(format: "%010d 00000 n \n", offset)
        }
        pdf += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xrefOffset)\n%%EOF\n"
        return Data(pdf.utf8)
    }

    private static func escapedPDFText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "(", with: "\\(")
            .replacingOccurrences(of: ")", with: "\\)")
    }

    private static let blueBossaSongID = UUID(uuidString: "61000000-0000-0000-0000-000000000001")!
    private static let cantaloupeSongID = UUID(uuidString: "61000000-0000-0000-0000-000000000002")!
    private static let justFriendsSongID = UUID(uuidString: "61000000-0000-0000-0000-000000000003")!
    private static let anotherYouSongID = UUID(uuidString: "61000000-0000-0000-0000-000000000004")!
    private static let actualProofSongID = UUID(uuidString: "61000000-0000-0000-0000-000000000005")!

    private static let blueBossaRhythmPostID = UUID(uuidString: "62000000-0000-0000-0000-000000000001")!
    private static let blueBossaHornsPostID = UUID(uuidString: "62000000-0000-0000-0000-000000000002")!
    private static let cantaloupePostID = UUID(uuidString: "62000000-0000-0000-0000-000000000003")!
    private static let justFriendsPostID = UUID(uuidString: "62000000-0000-0000-0000-000000000004")!
    private static let anotherYouPostID = UUID(uuidString: "62000000-0000-0000-0000-000000000005")!
    private static let actualProofPostID = UUID(uuidString: "62000000-0000-0000-0000-000000000006")!

    private static let blueBossaCommentOneID = UUID(uuidString: "63000000-0000-0000-0000-000000000001")!
    private static let blueBossaCommentTwoID = UUID(uuidString: "63000000-0000-0000-0000-000000000002")!
    private static let cantaloupeCommentOneID = UUID(uuidString: "63000000-0000-0000-0000-000000000003")!
    private static let actualProofCommentOneID = UUID(uuidString: "63000000-0000-0000-0000-000000000004")!

    private static let mayaOwnerID = UUID(uuidString: "64000000-0000-0000-0000-000000000001")!
    private static let jamalOwnerID = UUID(uuidString: "64000000-0000-0000-0000-000000000002")!
    private static let sophieOwnerID = UUID(uuidString: "64000000-0000-0000-0000-000000000003")!
    private static let nateOwnerID = UUID(uuidString: "64000000-0000-0000-0000-000000000004")!
    private static let eliOwnerID = UUID(uuidString: "64000000-0000-0000-0000-000000000005")!
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
