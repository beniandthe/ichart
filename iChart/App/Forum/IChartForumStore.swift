import Combine
import CryptoKit
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
    @Published private(set) var uploadQueue: [ForumUploadQueueItem]

    private let service: IChartForumServicing
    #if DEBUG
    private let qaSampleService = IChartForumQASampleService()
    #endif
    private var lastQuery = ""
    private var activeUploadIDs: Set<ForumUploadQueueItem.ID> = []

    private init(service: IChartForumServicing) {
        self.service = service
        #if DEBUG
        isQASampleDataEnabled = UserDefaults.standard.bool(forKey: Self.qaSampleDataStorageKey)
        #else
        isQASampleDataEnabled = false
        #endif
        uploadQueue = Self.loadUploadQueue()
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
    private static let uploadQueueStorageKey = "iChartForumUploadQueue"

    func setQASampleDataEnabled(_ isEnabled: Bool) {
        #if DEBUG
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

        #if DEBUG
        if isQASampleDataEnabled {
            await qaSampleService.setCurrentUserID(signedInSession.id)
        }
        #endif

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

    func enqueuePublish(chart: Chart, draft: ForumPublishDraft, ownerID: UUID?) {
        guard let ownerID else {
            errorMessage = "Sign in before posting to Forums."
            return
        }

        var publishDraft = draft
        publishDraft.selectedChartID = chart.id
        let validationErrors = publishDraft.validationErrors(availableChartIDs: [chart.id])
        guard validationErrors.isEmpty else {
            errorMessage = validationErrors.map(\.message).joined(separator: " ")
            return
        }

        let normalizedSongTitle = ForumPublishDraft.normalizedDisplayText(publishDraft.songTitle)
        let normalizedArtistName = ForumPublishDraft.normalizedDisplayText(publishDraft.artistName)
        let item = ForumUploadQueueItem(
            id: UUID(),
            postID: UUID(),
            ownerID: ownerID,
            chartID: chart.id,
            chartTitle: chart.title,
            songTitle: normalizedSongTitle.isEmpty ? publishDraft.resolvedChartTitle : normalizedSongTitle,
            artistName: normalizedArtistName,
            draft: publishDraft,
            stage: .queued,
            createdAt: Date(),
            updatedAt: Date(),
            errorMessage: nil
        )

        uploadQueue.insert(item, at: 0)
        persistUploadQueue()
        statusMessage = "Forum upload queued."
        errorMessage = nil

        Task {
            await processUpload(itemID: item.id, chart: chart, draft: publishDraft)
        }
    }

    func resumePendingUploads(charts: [Chart], currentUserID: UUID?) {
        guard let currentUserID else {
            return
        }

        for item in uploadQueue.filter({ $0.stage.isActive }) {
            guard !activeUploadIDs.contains(item.id) else {
                continue
            }

            guard let ownerID = item.ownerID, ownerID == currentUserID else {
                clearUploadQueueItem(item)
                continue
            }

            guard let chart = charts.first(where: { $0.id == item.chartID }) else {
                updateUploadQueueItem(
                    item.id,
                    stage: .failed,
                    errorMessage: "The local chart for this forum upload is no longer available."
                )
                continue
            }

            Task {
                await processUpload(itemID: item.id, chart: chart, draft: item.draft)
            }
        }
    }

    func retryUpload(_ item: ForumUploadQueueItem, charts: [Chart], currentUserID: UUID?) {
        guard let currentUserID, let ownerID = item.ownerID, ownerID == currentUserID else {
            clearUploadQueueItem(item)
            errorMessage = "This queued upload belongs to another signed-in account."
            return
        }

        guard let chart = charts.first(where: { $0.id == item.chartID }) else {
            updateUploadQueueItem(
                item.id,
                stage: .failed,
                errorMessage: "The local chart for this forum upload is no longer available."
            )
            return
        }

        updateUploadQueueItem(item.id, stage: .queued, errorMessage: nil)
        Task {
            await processUpload(itemID: item.id, chart: chart, draft: item.draft)
        }
    }

    func withdrawUpload(_ item: ForumUploadQueueItem) async {
        await run(successMessage: "Forum submission withdrawn.") {
            try await activeService.withdrawPost(postID: item.postID)
            updateUploadQueueItem(item.id, stage: .withdrawn, errorMessage: nil)
            state = .loaded(try await activeService.loadHome(query: lastQuery))
        }
    }

    func clearUploadQueueItem(_ item: ForumUploadQueueItem) {
        uploadQueue.removeAll { $0.id == item.id }
        persistUploadQueue()
    }

    func withdrawPost(_ detail: IChartForumPostDetail) async {
        await run(successMessage: "Forum submission withdrawn.") {
            try await activeService.withdrawPost(postID: detail.post.id)
            selectedDetail = nil
            downloadedPDF = nil
            state = .loaded(try await activeService.loadHome(query: lastQuery))
        }
    }

    func removePost(_ detail: IChartForumPostDetail) async {
        await run(successMessage: "Chart removed from Forums.") {
            try await activeService.removePost(postID: detail.post.id)
            selectedDetail = nil
            downloadedPDF = nil
            state = .loaded(try await activeService.loadHome(query: lastQuery))
        }
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

    private func processUpload(itemID: ForumUploadQueueItem.ID, chart: Chart, draft: ForumPublishDraft) async {
        guard !activeUploadIDs.contains(itemID) else {
            return
        }

        guard let queueItem = uploadQueue.first(where: { $0.id == itemID }) else {
            return
        }

        guard let ownerID = queueItem.ownerID else {
            clearUploadQueueItem(queueItem)
            return
        }

        activeUploadIDs.insert(itemID)
        defer {
            activeUploadIDs.remove(itemID)
        }

        do {
            try await activeService.publish(
                chart: chart,
                draft: draft,
                ownerID: ownerID,
                postID: queueItem.postID,
                exportedAt: queueItem.createdAt
            ) { [weak self] stage in
                await MainActor.run {
                    self?.updateUploadQueueItem(itemID, stage: stage, errorMessage: nil)
                }
            }

            updateUploadQueueItem(itemID, stage: .published, errorMessage: nil)
            statusMessage = "Forum chart published."
            errorMessage = nil
            if activeService.isConfigured {
                do {
                    state = .loaded(try await activeService.loadHome(query: lastQuery))
                } catch {
                    statusMessage = "Forum chart published. Refresh Forums to update the list."
                }
            }
        } catch {
            updateUploadQueueItem(itemID, stage: .failed, errorMessage: Self.displayText(for: error))
            errorMessage = Self.displayText(for: error)
        }
    }

    private func updateUploadQueueItem(
        _ itemID: ForumUploadQueueItem.ID,
        stage: ForumUploadStage,
        errorMessage: String?
    ) {
        guard let index = uploadQueue.firstIndex(where: { $0.id == itemID }) else {
            return
        }

        uploadQueue[index].stage = stage
        uploadQueue[index].updatedAt = Date()
        uploadQueue[index].errorMessage = errorMessage
        persistUploadQueue()
    }

    private func persistUploadQueue() {
        let persistedItems = uploadQueue.filter { $0.stage != .withdrawn && $0.stage != .removed }
        guard let data = try? JSONEncoder().encode(persistedItems) else {
            return
        }

        UserDefaults.standard.set(data, forKey: Self.uploadQueueStorageKey)
    }

    private static func loadUploadQueue() -> [ForumUploadQueueItem] {
        guard let data = UserDefaults.standard.data(forKey: uploadQueueStorageKey),
              var items = try? JSONDecoder().decode([ForumUploadQueueItem].self, from: data) else {
            return []
        }

        for index in items.indices where items[index].stage.isActive {
            items[index].stage = .queued
            items[index].updatedAt = Date()
            items[index].errorMessage = nil
        }

        return items
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
        #if DEBUG
        isQASampleDataEnabled ? qaSampleService : service
        #else
        service
        #endif
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
    func publish(
        chart: Chart,
        draft: ForumPublishDraft,
        ownerID: UUID,
        postID: UUID,
        exportedAt: Date,
        progress: @escaping (ForumUploadStage) async -> Void
    ) async throws
    func withdrawPost(postID: UUID) async throws
    func removePost(postID: UUID) async throws
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
    func publish(
        chart: Chart,
        draft: ForumPublishDraft,
        ownerID: UUID,
        postID: UUID,
        exportedAt: Date,
        progress: @escaping (ForumUploadStage) async -> Void
    ) async throws {
        throw IChartForumServiceError.unconfigured
    }
    func withdrawPost(postID: UUID) async throws {
        throw IChartForumServiceError.unconfigured
    }
    func removePost(postID: UUID) async throws {
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

#if DEBUG
private actor IChartForumQASampleService: IChartForumServicing {
    let isConfigured = true

    private static let currentUserDisplayName = "Beni R."

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
            grouping: allPosts().filter { $0.status == .published || $0.status == .flagged },
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

    func publish(
        chart: Chart,
        draft: ForumPublishDraft,
        ownerID: UUID,
        postID: UUID,
        exportedAt: Date,
        progress: @escaping (ForumUploadStage) async -> Void
    ) async throws {
        guard ownerID == currentUserID else {
            throw IChartForumServiceError.invalidPublishDraft(
                "This queued upload belongs to another signed-in account."
            )
        }

        let publishDraft = draft.withCreatorDisplayName(Self.currentUserDisplayName)
        let validationErrors = publishDraft.validationErrors(availableChartIDs: [chart.id])
        guard validationErrors.isEmpty else {
            throw IChartForumServiceError.invalidPublishDraft(
                validationErrors.map(\.message).joined(separator: " ")
            )
        }

        await progress(.preparingPDF)
        await progress(.uploadingPDF)
        await progress(.submittingMetadata)
        await progress(.validating)
        let song = resolvedSong(for: publishDraft)
        let post = ForumChartPost(
            id: postID,
            songID: song.id,
            ownerID: currentUserID,
            chartTitle: publishDraft.resolvedChartTitle,
            arrangerCredit: ForumPublishDraft.normalizedDisplayText(publishDraft.arrangerCredit),
            creatorDisplayName: ForumPublishDraft.normalizedDisplayText(publishDraft.creatorDisplayName),
            tags: publishDraft.sanitizedTags,
            versionNote: ForumPublishDraft.normalizedDisplayText(publishDraft.versionNote).nilIfEmpty,
            layoutStyle: chart.layoutStyle,
            pdfStoragePath: "qa-samples/\(postID.uuidString.lowercased()).pdf",
            status: .published,
            voteUpCount: 0,
            voteDownCount: 0,
            reportCount: 0,
            rankingScore: 0,
            publishedAt: Date()
        )
        submittedPosts[post.id] = post
    }

    func withdrawPost(postID: UUID) async throws {
        guard var post = submittedPosts[postID] else {
            throw IChartForumServiceError.missingForumPost
        }

        guard post.status == .pending else {
            throw IChartForumServiceError.invalidPublishDraft("Only pending forum submissions can be withdrawn.")
        }

        post.status = .removed
        submittedPosts[postID] = post
    }

    func removePost(postID: UUID) async throws {
        guard var post = submittedPosts[postID] else {
            throw IChartForumServiceError.missingForumPost
        }

        guard post.status == .published || post.status == .flagged else {
            throw IChartForumServiceError.invalidPublishDraft("Only published forum posts can be removed from Forums.")
        }

        post.status = .removed
        submittedPosts[postID] = post
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
            creatorDisplayName: Self.currentUserDisplayName,
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
            ForumSong(id: Self.lateNightPocketSongID, songTitle: "Late Night Pocket", artistName: "iChart Community"),
            ForumSong(id: Self.firstDanceSongID, songTitle: "First Dance", artistName: "Wedding Set"),
            ForumSong(id: Self.brassCityShuffleSongID, songTitle: "Brass City Shuffle", artistName: "Maya Torres"),
            ForumSong(id: Self.riverwalkBossaSongID, songTitle: "Riverwalk Bossa", artistName: "Jamal Reed"),
            ForumSong(id: Self.sundayProcessionalSongID, songTitle: "Sunday Processional", artistName: "Ceremony Band"),
            ForumSong(id: Self.comboClassWarmupSongID, songTitle: "Combo Class Warmup", artistName: "Studio Curriculum"),
            ForumSong(id: Self.uptownWalkSongID, songTitle: "Uptown Walk", artistName: "Nate Coleman"),
            ForumSong(id: Self.balladForLenaSongID, songTitle: "Ballad for Lena", artistName: "Sophie Lane"),
            ForumSong(id: Self.hornSectionStabsSongID, songTitle: "Horn Section Stabs", artistName: "Session Band"),
            ForumSong(id: Self.afterHoursWaltzSongID, songTitle: "After Hours Waltz", artistName: "Eli Park")
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
                id: Self.lateNightPocketRoadmapPostID,
                songID: Self.lateNightPocketSongID,
                ownerID: currentUserID,
                chartTitle: "Late Night Pocket - Rhythm Section Roadmap",
                arrangerCredit: "Beni Rossman",
                creatorDisplayName: "Beni R.",
                tags: ["funk", "rhythm section", "rehearsal"],
                versionNote: "One-page roadmap with repeats, section labels, and notes for the band.",
                layoutStyle: .rhythmSectionSheet,
                status: .published,
                upVotes: 62,
                downVotes: 1,
                reports: 0,
                publishedAt: now.addingTimeInterval(-35 * 60)
            ),
            post(
                id: Self.lateNightPocketHornPostID,
                songID: Self.lateNightPocketSongID,
                ownerID: Self.mayaOwnerID,
                chartTitle: "Late Night Pocket - Bb Horn Version",
                arrangerCredit: "Maya Torres",
                creatorDisplayName: "Maya T.",
                tags: ["horns", "Bb", "funk"],
                versionNote: "Transposed copy for the horn line with the same rehearsal form.",
                layoutStyle: .simpleChordSheet,
                status: .published,
                upVotes: 31,
                downVotes: 0,
                reports: 0,
                publishedAt: now.addingTimeInterval(-2 * 60 * 60)
            ),
            post(
                id: Self.firstDanceFPostID,
                songID: Self.firstDanceSongID,
                ownerID: currentUserID,
                chartTitle: "First Dance - Key of F",
                arrangerCredit: "Beni Rossman",
                creatorDisplayName: "Beni R.",
                tags: ["wedding", "singer key", "set list"],
                versionNote: "Last-minute singer key version, stored with the weekend wedding project.",
                layoutStyle: .simpleChordSheet,
                status: .published,
                upVotes: 48,
                downVotes: 1,
                reports: 0,
                publishedAt: now.addingTimeInterval(-75 * 60)
            ),
            post(
                id: Self.firstDanceCPostID,
                songID: Self.firstDanceSongID,
                ownerID: Self.sophieOwnerID,
                chartTitle: "First Dance - Original Key",
                arrangerCredit: "Sophie Lane",
                creatorDisplayName: "Sophie L.",
                tags: ["wedding", "original key", "piano"],
                versionNote: "Original chart kept alongside the transposed singer version.",
                layoutStyle: .simpleChordSheet,
                status: .published,
                upVotes: 18,
                downVotes: 0,
                reports: 0,
                publishedAt: now.addingTimeInterval(-8 * 60 * 60)
            ),
            post(
                id: Self.brassCityConcertPostID,
                songID: Self.brassCityShuffleSongID,
                ownerID: Self.mayaOwnerID,
                chartTitle: "Brass City Shuffle - Concert Chart",
                arrangerCredit: "Maya Torres",
                creatorDisplayName: "Maya T.",
                tags: ["horns", "concert", "shuffle"],
                versionNote: "Compact concert chart for bandleaders handing charts to a horn section.",
                layoutStyle: .simpleChordSheet,
                status: .published,
                upVotes: 36,
                downVotes: 2,
                reports: 0,
                publishedAt: now.addingTimeInterval(-18 * 60 * 60)
            ),
            post(
                id: Self.brassCityEbPostID,
                songID: Self.brassCityShuffleSongID,
                ownerID: Self.lenaOwnerID,
                chartTitle: "Brass City Shuffle - Eb Horn Copy",
                arrangerCredit: "Lena Ortiz",
                creatorDisplayName: "Lena O.",
                tags: ["horns", "Eb", "transposed"],
                versionNote: "Readable horn copy for alto players using the same roadmap.",
                layoutStyle: .simpleChordSheet,
                status: .published,
                upVotes: 22,
                downVotes: 1,
                reports: 0,
                publishedAt: now.addingTimeInterval(-25 * 60 * 60)
            ),
            post(
                id: Self.riverwalkBossaPostID,
                songID: Self.riverwalkBossaSongID,
                ownerID: Self.jamalOwnerID,
                chartTitle: "Riverwalk Bossa - Pocket Chart",
                arrangerCredit: "Jamal Reed",
                creatorDisplayName: "Jamal R.",
                tags: ["bossa", "gig book", "rhythm section"],
                versionNote: "Clean rhythm section chart with large section markers.",
                layoutStyle: .rhythmSectionSheet,
                status: .published,
                upVotes: 41,
                downVotes: 0,
                reports: 0,
                publishedAt: now.addingTimeInterval(-3 * 24 * 60 * 60)
            ),
            post(
                id: Self.sundayProcessionalPostID,
                songID: Self.sundayProcessionalSongID,
                ownerID: Self.averyOwnerID,
                chartTitle: "Sunday Processional - Ceremony Packet",
                arrangerCredit: "Avery Brooks",
                creatorDisplayName: "Avery B.",
                tags: ["ceremony", "wedding", "strings"],
                versionNote: "Simple form and cue notes for a ceremony ensemble.",
                layoutStyle: .simpleChordSheet,
                status: .published,
                upVotes: 16,
                downVotes: 1,
                reports: 0,
                publishedAt: now.addingTimeInterval(-4 * 24 * 60 * 60)
            ),
            post(
                id: Self.comboClassWarmupPostID,
                songID: Self.comboClassWarmupSongID,
                ownerID: Self.professorKimOwnerID,
                chartTitle: "Combo Class Warmup - Student Set",
                arrangerCredit: "Professor Kim",
                creatorDisplayName: "Prof. Kim",
                tags: ["teaching", "students", "warmup"],
                versionNote: "Reusable class chart so students can always find the current version.",
                layoutStyle: .simpleChordSheet,
                status: .published,
                upVotes: 27,
                downVotes: 0,
                reports: 0,
                publishedAt: now.addingTimeInterval(-5 * 24 * 60 * 60)
            ),
            post(
                id: Self.uptownWalkPostID,
                songID: Self.uptownWalkSongID,
                ownerID: Self.nateOwnerID,
                chartTitle: "Uptown Walk - Club Date Chart",
                arrangerCredit: "Nate Coleman",
                creatorDisplayName: "Nate C.",
                tags: ["club date", "walk", "set list"],
                versionNote: "Short roadmap for a one-rehearsal club date.",
                layoutStyle: .rhythmSectionSheet,
                status: .published,
                upVotes: 13,
                downVotes: 1,
                reports: 0,
                publishedAt: now.addingTimeInterval(-9 * 24 * 60 * 60)
            ),
            post(
                id: Self.balladForLenaPostID,
                songID: Self.balladForLenaSongID,
                ownerID: Self.sophieOwnerID,
                chartTitle: "Ballad for Lena - Singer Key",
                arrangerCredit: "Sophie Lane",
                creatorDisplayName: "Sophie L.",
                tags: ["ballad", "singer key", "piano trio"],
                versionNote: "A clean singer-key chart for a quiet cocktail set.",
                layoutStyle: .simpleChordSheet,
                status: .published,
                upVotes: 9,
                downVotes: 0,
                reports: 0,
                publishedAt: now.addingTimeInterval(-12 * 24 * 60 * 60)
            ),
            post(
                id: Self.hornSectionStabsPostID,
                songID: Self.hornSectionStabsSongID,
                ownerID: Self.mayaOwnerID,
                chartTitle: "Horn Section Stabs - Rehearsal Hits",
                arrangerCredit: "Maya Torres",
                creatorDisplayName: "Maya T.",
                tags: ["horns", "hits", "rehearsal"],
                versionNote: "Section hits and roadmap notes for a quick band rehearsal.",
                layoutStyle: .rhythmSectionSheet,
                status: .published,
                upVotes: 21,
                downVotes: 2,
                reports: 0,
                publishedAt: now.addingTimeInterval(-16 * 24 * 60 * 60)
            ),
            post(
                id: Self.afterHoursWaltzPostID,
                songID: Self.afterHoursWaltzSongID,
                ownerID: Self.eliOwnerID,
                chartTitle: "After Hours Waltz - New Chart",
                arrangerCredit: "Eli Park",
                creatorDisplayName: "Eli P.",
                tags: ["waltz", "new", "lead sheet"],
                versionNote: "Fresh upload for review before the weekend set.",
                layoutStyle: .simpleChordSheet,
                status: .published,
                upVotes: 2,
                downVotes: 0,
                reports: 0,
                publishedAt: now.addingTimeInterval(-20 * 60)
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
            Self.lateNightPocketRoadmapPostID: [
                comment(
                    id: Self.multiUserDemoCommentOneID,
                    postID: Self.lateNightPocketRoadmapPostID,
                    ownerID: Self.mayaOwnerID,
                    creator: "Maya T.",
                    body: "This is the kind of chart I would send before rehearsal. The form is clear and the hits are easy to catch.",
                    hoursAgo: 6
                ),
                comment(
                    id: Self.multiUserDemoCommentTwoID,
                    postID: Self.lateNightPocketRoadmapPostID,
                    ownerID: Self.jamalOwnerID,
                    creator: "Jamal R.",
                    body: "Upvoted. The roadmap works well for rhythm section, especially with the repeat labels up front.",
                    hoursAgo: 5
                ),
                comment(
                    id: Self.multiUserDemoCommentThreeID,
                    postID: Self.lateNightPocketRoadmapPostID,
                    ownerID: Self.sophieOwnerID,
                    creator: "Sophie L.",
                    body: "Downloaded the PDF preview. I would maybe add one cue before the tag, but this is readable as-is.",
                    hoursAgo: 3
                ),
                comment(
                    id: Self.multiUserDemoCommentFourID,
                    postID: Self.lateNightPocketRoadmapPostID,
                    ownerID: Self.nateOwnerID,
                    creator: "Nate C.",
                    body: "The public names are just enough attribution without exposing full account details. This feels right.",
                    hoursAgo: 1
                )
            ],
            Self.firstDanceFPostID: [
                comment(id: Self.firstDanceCommentOneID, postID: Self.firstDanceFPostID, ownerID: Self.averyOwnerID, creator: "Avery B.", body: "This solved a last-minute singer key change for me. Keeping the original and the new key together is huge.", hoursAgo: 4),
                comment(id: Self.firstDanceCommentTwoID, postID: Self.firstDanceFPostID, ownerID: Self.sophieOwnerID, creator: "Sophie L.", body: "Clean enough to send straight to the band. I like the simple project organization.", hoursAgo: 2)
            ],
            Self.brassCityConcertPostID: [
                comment(id: Self.brassCityCommentOneID, postID: Self.brassCityConcertPostID, ownerID: Self.lenaOwnerID, creator: "Lena O.", body: "The concert version plus horn copies make this easy to drop into a rehearsal packet.", hoursAgo: 12),
                comment(id: Self.brassCityCommentTwoID, postID: Self.brassCityConcertPostID, ownerID: Self.nateOwnerID, creator: "Nate C.", body: "Roadmap is clear and the section labels are easy to scan.", hoursAgo: 9)
            ],
            Self.riverwalkBossaPostID: [
                comment(id: Self.riverwalkCommentOneID, postID: Self.riverwalkBossaPostID, ownerID: Self.mayaOwnerID, creator: "Maya T.", body: "This one reads clean on a loud stage. The ending is easy to catch.", hoursAgo: 30),
                comment(id: Self.riverwalkCommentTwoID, postID: Self.riverwalkBossaPostID, ownerID: Self.jamalOwnerID, creator: "Jamal R.", body: "Good roadmap for rhythm section. I would keep the tag exactly like this.", hoursAgo: 28)
            ],
            Self.comboClassWarmupPostID: [
                comment(id: Self.comboClassCommentOneID, postID: Self.comboClassWarmupPostID, ownerID: Self.professorKimOwnerID, creator: "Prof. Kim", body: "Students losing the current chart used to be half the lesson. This keeps the set organized.", hoursAgo: 18),
                comment(id: Self.comboClassCommentTwoID, postID: Self.comboClassWarmupPostID, ownerID: Self.lenaOwnerID, creator: "Lena O.", body: "Great for weekly combo folders. I would use this for sight-reading packets.", hoursAgo: 11)
            ],
            Self.hornSectionStabsPostID: [
                comment(id: Self.hornSectionCommentOneID, postID: Self.hornSectionStabsPostID, ownerID: Self.jamalOwnerID, creator: "Jamal R.", body: "The hit layout is quick to scan. Nice for rehearsal.", hoursAgo: 42)
            ],
            Self.afterHoursWaltzPostID: [
                comment(id: Self.afterHoursCommentOneID, postID: Self.afterHoursWaltzPostID, ownerID: Self.eliOwnerID, creator: "Eli P.", body: "Posting this here before I send it to the trio. Feedback welcome.", hoursAgo: 1)
            ]
        ]
    }

    private func comment(
        id: UUID,
        postID: UUID,
        ownerID: UUID,
        creator: String,
        body: String,
        hoursAgo: Double = 24
    ) -> ForumComment {
        ForumComment(
            id: id,
            postID: postID,
            ownerID: ownerID,
            creatorDisplayName: creator,
            body: body,
            createdAt: Date().addingTimeInterval(-hoursAgo * 60 * 60)
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

    private static let lateNightPocketSongID = UUID(uuidString: "61000000-0000-0000-0000-000000000001")!
    private static let firstDanceSongID = UUID(uuidString: "61000000-0000-0000-0000-000000000002")!
    private static let brassCityShuffleSongID = UUID(uuidString: "61000000-0000-0000-0000-000000000003")!
    private static let riverwalkBossaSongID = UUID(uuidString: "61000000-0000-0000-0000-000000000004")!
    private static let sundayProcessionalSongID = UUID(uuidString: "61000000-0000-0000-0000-000000000005")!
    private static let comboClassWarmupSongID = UUID(uuidString: "61000000-0000-0000-0000-000000000006")!
    private static let uptownWalkSongID = UUID(uuidString: "61000000-0000-0000-0000-000000000007")!
    private static let balladForLenaSongID = UUID(uuidString: "61000000-0000-0000-0000-000000000008")!
    private static let hornSectionStabsSongID = UUID(uuidString: "61000000-0000-0000-0000-000000000009")!
    private static let afterHoursWaltzSongID = UUID(uuidString: "61000000-0000-0000-0000-000000000010")!

    private static let lateNightPocketRoadmapPostID = UUID(uuidString: "62000000-0000-0000-0000-000000000001")!
    private static let lateNightPocketHornPostID = UUID(uuidString: "62000000-0000-0000-0000-000000000002")!
    private static let firstDanceFPostID = UUID(uuidString: "62000000-0000-0000-0000-000000000003")!
    private static let firstDanceCPostID = UUID(uuidString: "62000000-0000-0000-0000-000000000004")!
    private static let brassCityConcertPostID = UUID(uuidString: "62000000-0000-0000-0000-000000000005")!
    private static let brassCityEbPostID = UUID(uuidString: "62000000-0000-0000-0000-000000000006")!
    private static let riverwalkBossaPostID = UUID(uuidString: "62000000-0000-0000-0000-000000000007")!
    private static let sundayProcessionalPostID = UUID(uuidString: "62000000-0000-0000-0000-000000000008")!
    private static let comboClassWarmupPostID = UUID(uuidString: "62000000-0000-0000-0000-000000000009")!
    private static let uptownWalkPostID = UUID(uuidString: "62000000-0000-0000-0000-000000000010")!
    private static let balladForLenaPostID = UUID(uuidString: "62000000-0000-0000-0000-000000000011")!
    private static let hornSectionStabsPostID = UUID(uuidString: "62000000-0000-0000-0000-000000000012")!
    private static let afterHoursWaltzPostID = UUID(uuidString: "62000000-0000-0000-0000-000000000013")!

    private static let multiUserDemoCommentOneID = UUID(uuidString: "63000000-0000-0000-0000-000000000005")!
    private static let multiUserDemoCommentTwoID = UUID(uuidString: "63000000-0000-0000-0000-000000000006")!
    private static let multiUserDemoCommentThreeID = UUID(uuidString: "63000000-0000-0000-0000-000000000007")!
    private static let multiUserDemoCommentFourID = UUID(uuidString: "63000000-0000-0000-0000-000000000008")!
    private static let firstDanceCommentOneID = UUID(uuidString: "63000000-0000-0000-0000-000000000009")!
    private static let firstDanceCommentTwoID = UUID(uuidString: "63000000-0000-0000-0000-000000000010")!
    private static let brassCityCommentOneID = UUID(uuidString: "63000000-0000-0000-0000-000000000011")!
    private static let brassCityCommentTwoID = UUID(uuidString: "63000000-0000-0000-0000-000000000012")!
    private static let riverwalkCommentOneID = UUID(uuidString: "63000000-0000-0000-0000-000000000013")!
    private static let riverwalkCommentTwoID = UUID(uuidString: "63000000-0000-0000-0000-000000000014")!
    private static let comboClassCommentOneID = UUID(uuidString: "63000000-0000-0000-0000-000000000015")!
    private static let comboClassCommentTwoID = UUID(uuidString: "63000000-0000-0000-0000-000000000016")!
    private static let hornSectionCommentOneID = UUID(uuidString: "63000000-0000-0000-0000-000000000017")!
    private static let afterHoursCommentOneID = UUID(uuidString: "63000000-0000-0000-0000-000000000018")!

    private static let mayaOwnerID = UUID(uuidString: "64000000-0000-0000-0000-000000000001")!
    private static let jamalOwnerID = UUID(uuidString: "64000000-0000-0000-0000-000000000002")!
    private static let sophieOwnerID = UUID(uuidString: "64000000-0000-0000-0000-000000000003")!
    private static let nateOwnerID = UUID(uuidString: "64000000-0000-0000-0000-000000000004")!
    private static let eliOwnerID = UUID(uuidString: "64000000-0000-0000-0000-000000000005")!
    private static let lenaOwnerID = UUID(uuidString: "64000000-0000-0000-0000-000000000006")!
    private static let averyOwnerID = UUID(uuidString: "64000000-0000-0000-0000-000000000007")!
    private static let professorKimOwnerID = UUID(uuidString: "64000000-0000-0000-0000-000000000008")!
}
#endif

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

    func publish(
        chart: Chart,
        draft: ForumPublishDraft,
        ownerID expectedOwnerID: UUID,
        postID: UUID,
        exportedAt: Date,
        progress: @escaping (ForumUploadStage) async -> Void
    ) async throws {
        let validationErrors = draft.validationErrors(availableChartIDs: [chart.id])
        guard validationErrors.isEmpty else {
            throw IChartForumServiceError.invalidPublishDraft(
                validationErrors.map(\.message).joined(separator: " ")
            )
        }

        let ownerID = try await currentUserIDForRequest()
        guard ownerID == expectedOwnerID else {
            throw IChartForumServiceError.invalidPublishDraft(
                "This queued upload belongs to another signed-in account."
            )
        }

        let publishDraft = draft.withCreatorDisplayName(
            try await publicAuthorDisplayName(for: ownerID)
        )
        let storagePath = publishDraft.storagePath(ownerID: ownerID, postID: postID)
        await progress(.preparingPDF)
        let exportedPDF = try await pdfExporter.exportPDF(
            for: chart,
            context: ChartPDFExportContext(
                forumCredit: ForumPDFCredit(
                    creatorDisplayName: ForumPublishDraft.normalizedDisplayText(publishDraft.creatorDisplayName),
                    forumPostID: postID,
                    exportedAt: exportedAt
                )
            )
        )
        let pdfData = try Data(contentsOf: exportedPDF.url)
        let pdfSHA256 = Self.sha256HexDigest(for: pdfData)
        await progress(.uploadingPDF)
        do {
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
        } catch {
            guard Self.isStorageObjectAlreadyExists(error) else {
                throw error
            }
        }

        let song: ForumSong
        var shouldRollbackUploadedPDF = true
        do {
            await progress(.submittingMetadata)
            song = try await resolvedSong(for: publishDraft, ownerID: ownerID)
            let postInsert = ForumChartPostInsert(
                id: postID,
                songID: song.id,
                ownerID: ownerID,
                localChartID: chart.id,
                chartTitle: publishDraft.resolvedChartTitle,
                arrangerCredit: ForumPublishDraft.normalizedDisplayText(publishDraft.arrangerCredit),
                creatorDisplayName: ForumPublishDraft.normalizedDisplayText(publishDraft.creatorDisplayName),
                tags: publishDraft.sanitizedTags,
                versionNote: ForumPublishDraft.normalizedDisplayText(publishDraft.versionNote).nilIfEmpty,
                layoutStyle: chart.layoutStyle.rawValue,
                pdfStoragePath: storagePath
            )
            do {
                try await client
                    .from("forum_chart_posts")
                    .insert(postInsert)
                    .execute()
            } catch {
                guard Self.isDuplicatePostInsert(error) else {
                    throw error
                }
            }
            shouldRollbackUploadedPDF = false
            await progress(.validating)
            try await forumPostAction(
                action: .publish,
                postID: postID,
                byteSize: pdfData.count,
                sha256: pdfSHA256
            )
        } catch {
            if shouldRollbackUploadedPDF {
                await rollbackUploadedForumPDF(at: storagePath)
            }
            throw error
        }

    }

    func withdrawPost(postID: UUID) async throws {
        try await forumPostAction(action: .withdraw, postID: postID)
    }

    func removePost(postID: UUID) async throws {
        try await forumPostAction(action: .remove, postID: postID)
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

    @discardableResult
    private func forumPostAction(
        action: ForumPostActionKind,
        postID: UUID,
        byteSize: Int? = nil,
        sha256: String? = nil
    ) async throws -> ForumPostActionResponse {
        let session = try await refreshedSessionForRequest()
        let response: ForumPostActionResponse = try await client.functions.invoke(
            "forum-post-actions",
            options: FunctionInvokeOptions(
                method: .post,
                headers: ["Authorization": "Bearer \(session.accessToken)"],
                body: ForumPostActionRequest(
                    action: action.rawValue,
                    postID: postID,
                    byteSize: byteSize,
                    sha256: sha256
                )
            )
        )

        guard response.accepted else {
            throw IChartForumServiceError.invalidPublishDraft(
                response.error ?? "Forum post action was rejected."
            )
        }

        return response
    }

    private func refreshedSessionForRequest() async throws -> Session {
        try await sessionRefresher.refreshIfNeeded()
    }

    private func currentUserIDForRequest() async throws -> UUID {
        let session = try await refreshedSessionForRequest()
        return session.user.id
    }

    private func publicAuthorDisplayName(for ownerID: UUID) async throws -> String {
        let profiles: [ForumProfileDisplayNameRow] = try await client
            .from("profiles")
            .select("first_name,last_name")
            .eq("id", value: ownerID)
            .limit(1)
            .execute()
            .value
        let displayName = profiles.first?.publicDisplayName ?? ""
        guard !displayName.isEmpty else {
            throw IChartForumServiceError.invalidPublishDraft(
                "Open Settings > Account to finish first and last name before posting."
            )
        }

        return displayName
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

    private static func sha256HexDigest(for data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func isStorageObjectAlreadyExists(_ error: Error) -> Bool {
        let text = "\(error) \(error.localizedDescription)".lowercased()
        return text.contains("already exists")
            || text.contains("duplicate")
            || text.contains("23505")
    }

    private static func isDuplicatePostInsert(_ error: Error) -> Bool {
        let text = "\(error) \(error.localizedDescription)".lowercased()
        return text.contains("duplicate")
            || text.contains("23505")
            || text.contains("already exists")
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

private struct ForumProfileDisplayNameRow: Decodable {
    let firstName: String?
    let lastName: String?

    var publicDisplayName: String {
        ForumAuthorDisplayNamePolicy.displayName(firstName: firstName, lastName: lastName)
    }

    enum CodingKeys: String, CodingKey {
        case firstName = "first_name"
        case lastName = "last_name"
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
    let creatorDisplayName: String?
    let body: String
    let createdAt: String?

    var forumComment: ForumComment {
        ForumComment(
            id: id,
            postID: postID,
            ownerID: ownerID,
            creatorDisplayName: creatorDisplayName,
            body: body,
            createdAt: IChartForumDateParser.date(from: createdAt)
        )
    }

    enum CodingKeys: String, CodingKey {
        case id
        case postID = "post_id"
        case ownerID = "owner_id"
        case creatorDisplayName = "creator_display_name"
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

private enum ForumPostActionKind: String {
    case publish
    case withdraw
    case remove
}

private struct ForumPostActionRequest: Encodable {
    let action: String
    let postID: UUID
    let byteSize: Int?
    let sha256: String?

    enum CodingKeys: String, CodingKey {
        case action
        case postID = "post_id"
        case byteSize = "byte_size"
        case sha256
    }
}

private struct ForumPostActionResponse: Decodable {
    let accepted: Bool
    let state: String?
    let error: String?
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
