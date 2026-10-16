#if canImport(UIKit)
import Foundation
import XCTest
@testable import iChart

@MainActor
final class IChartForumBetaQueueTests: XCTestCase {
    func testBasicRelaunchPreservesQueueAndRejoinPublishesExactlyOnce() async throws {
        let fixture = try makeFixture()
        defer { fixture.clean() }
        fixture.store.applyAccess(entitlements: basic, charts: [fixture.chart], currentUserID: fixture.owner)
        fixture.store.resumePendingUploads(charts: [fixture.chart], currentUserID: fixture.owner)
        fixture.store.retryUpload(fixture.item, charts: [fixture.chart], currentUserID: fixture.owner)
        fixture.store.enqueuePublish(chart: fixture.chart, draft: fixture.item.draft, ownerID: fixture.owner)
        await Task.yield()
        let before = await fixture.service.publishOwners
        XCTAssertTrue(before.isEmpty)
        XCTAssertEqual(fixture.store.uploadQueue.map(\.id), [fixture.item.id])
        XCTAssertEqual(fixture.store.uploadQueue.first?.draft, fixture.item.draft)

        let reopened = IChartForumStore(service: fixture.service, defaults: fixture.defaults)
        reopened.applyAccess(entitlements: basic, charts: [fixture.chart], currentUserID: fixture.owner)
        XCTAssertEqual(reopened.uploadQueue.map(\.id), [fixture.item.id])
        for _ in 0..<3 {
            reopened.applyAccess(entitlements: pro, charts: [fixture.chart], currentUserID: fixture.owner)
        }
        try await waitUntil { reopened.uploadQueue.first?.stage == .published }
        let owners = await fixture.service.publishOwners
        let posts = await fixture.service.publishPostIDs
        let mutations = await fixture.service.publishMutations
        XCTAssertEqual(owners, [fixture.owner])
        XCTAssertEqual(posts, [fixture.item.postID])
        XCTAssertEqual(mutations, 1)
        XCTAssertEqual(reopened.uploadQueue.first?.id, fixture.item.id)
    }

    func testLeavingDuringPreparationCancelsLaterPublishAndRejoinResumesSamePostOnce() async throws {
        let fixture = try makeFixture(holdFirstPublish: true)
        defer { fixture.clean() }
        fixture.store.applyAccess(entitlements: pro, charts: [fixture.chart], currentUserID: fixture.owner)
        try await waitUntil { await fixture.service.isHoldingFirstPublish }
        fixture.store.applyAccess(entitlements: basic, charts: [fixture.chart], currentUserID: fixture.owner)
        await fixture.service.releaseFirstPublish()
        try await waitUntil { fixture.store.uploadQueue.first?.stage == .queued }

        let pausedOwners = await fixture.service.publishOwners
        let pausedMutations = await fixture.service.publishMutations
        XCTAssertEqual(pausedOwners, [fixture.owner])
        XCTAssertEqual(pausedMutations, 0)
        XCTAssertEqual(fixture.store.uploadQueue.first?.postID, fixture.item.postID)
        XCTAssertEqual(fixture.store.uploadQueue.first?.draft, fixture.item.draft)
        XCTAssertNil(fixture.store.uploadQueue.first?.errorMessage)

        for _ in 0..<3 {
            fixture.store.applyAccess(entitlements: pro, charts: [fixture.chart], currentUserID: fixture.owner)
        }
        try await waitUntil { fixture.store.uploadQueue.first?.stage == .published }
        let posts = await fixture.service.publishPostIDs
        let finalMutations = await fixture.service.publishMutations
        XCTAssertEqual(posts, [fixture.item.postID, fixture.item.postID])
        XCTAssertEqual(finalMutations, 1)
    }

    func testAccountSwitchKeepsOtherOwnersQueueAndDoesNotPublishIt() async throws {
        let fixture = try makeFixture()
        defer { fixture.clean() }
        let otherOwner = UUID()
        fixture.store.applyAccess(entitlements: basic, charts: [fixture.chart], currentUserID: fixture.owner)
        fixture.store.applyAccess(entitlements: pro, charts: [fixture.chart], currentUserID: otherOwner)
        fixture.store.resumePendingUploads(charts: [fixture.chart], currentUserID: otherOwner)
        fixture.store.retryUpload(fixture.item, charts: [fixture.chart], currentUserID: otherOwner)
        await Task.yield()
        let ownersBefore = await fixture.service.publishOwners
        XCTAssertTrue(ownersBefore.isEmpty)
        XCTAssertEqual(fixture.store.uploadQueue.map(\.id), [fixture.item.id])
        fixture.store.applyAccess(entitlements: pro, charts: [fixture.chart], currentUserID: fixture.owner)
        try await waitUntil { fixture.store.uploadQueue.first?.stage == .published }
        let ownersAfter = await fixture.service.publishOwners
        XCTAssertEqual(ownersAfter, [fixture.owner])
    }

    func testSuccessfulWithdrawalCannotBeResurrectedByLateCancelledPublish() async throws {
        let fixture = try makeFixture(holdFirstPublish: true)
        defer { fixture.clean() }
        fixture.store.applyAccess(entitlements: pro, charts: [fixture.chart], currentUserID: fixture.owner)
        try await waitUntil { await fixture.service.isHoldingFirstPublish }
        fixture.store.applyAccess(entitlements: basic, charts: [fixture.chart], currentUserID: fixture.owner)
        await fixture.store.withdrawUpload(fixture.item)
        XCTAssertEqual(fixture.store.uploadQueue.first?.stage, .withdrawn)
        await fixture.service.releaseFirstPublish()
        try await waitUntil { !fixture.store.hasUploadWorkInFlight }

        XCTAssertEqual(fixture.store.uploadQueue.first?.stage, .withdrawn)
        for _ in 0..<3 {
            fixture.store.applyAccess(entitlements: pro, charts: [fixture.chart], currentUserID: fixture.owner)
        }
        fixture.store.retryUpload(fixture.item, charts: [fixture.chart], currentUserID: fixture.owner)
        XCTAssertFalse(fixture.store.hasUploadWorkInFlight)
        let published = await fixture.service.publishOwners
        XCTAssertEqual(published, [fixture.owner])
        XCTAssertTrue(IChartForumStore(service: fixture.service, defaults: fixture.defaults).uploadQueue.isEmpty)
    }

    func testRemovedAndDismissedItemsIgnoreLatePublishCallbacksAndCannotResume() async throws {
        for removeRemotePost in [true, false] {
            let fixture = try makeFixture(holdFirstPublish: true)
            defer { fixture.clean() }
            fixture.store.applyAccess(entitlements: pro, charts: [fixture.chart], currentUserID: fixture.owner)
            try await waitUntil { await fixture.service.isHoldingFirstPublish }
            fixture.store.applyAccess(entitlements: basic, charts: [fixture.chart], currentUserID: fixture.owner)
            if removeRemotePost {
                await fixture.store.removePost(ownedDetail(fixture))
                XCTAssertEqual(fixture.store.uploadQueue.first?.stage, .removed)
            } else {
                fixture.store.clearUploadQueueItem(fixture.item)
                XCTAssertTrue(fixture.store.uploadQueue.isEmpty)
            }
            await fixture.service.releaseFirstPublish()
            try await waitUntil { !fixture.store.hasUploadWorkInFlight }
            if removeRemotePost {
                XCTAssertEqual(fixture.store.uploadQueue.first?.stage, .removed)
            } else {
                XCTAssertTrue(fixture.store.uploadQueue.isEmpty)
            }
            fixture.store.applyAccess(entitlements: pro, charts: [fixture.chart], currentUserID: fixture.owner)
            XCTAssertFalse(fixture.store.hasUploadWorkInFlight)
            let published = await fixture.service.publishOwners
            XCTAssertEqual(published, [fixture.owner])
        }
    }

    func testBasicOwnedCleanupSucceedsWithoutForbiddenHomeRefresh() async throws {
        let fixture = try makeFixture()
        defer { fixture.clean() }
        fixture.store.applyAccess(entitlements: basic, charts: [fixture.chart], currentUserID: fixture.owner)
        await fixture.service.rejectHomeReads()
        await fixture.store.withdrawUpload(fixture.item)
        XCTAssertNil(fixture.store.errorMessage)
        XCTAssertEqual(fixture.store.statusMessage, "Forum submission withdrawn.")
        XCTAssertEqual(fixture.store.state, .requiresPro)
        XCTAssertEqual(fixture.store.uploadQueue.first?.stage, .withdrawn)

        let detail = ownedDetail(fixture)
        await fixture.store.withdrawPost(detail)
        XCTAssertNil(fixture.store.errorMessage)
        XCTAssertEqual(fixture.store.statusMessage, "Forum submission withdrawn.")
        XCTAssertEqual(fixture.store.state, .requiresPro)
        XCTAssertEqual(fixture.store.uploadQueue.first?.stage, .withdrawn)
        await fixture.store.removePost(detail)
        XCTAssertNil(fixture.store.errorMessage)
        XCTAssertEqual(fixture.store.statusMessage, "Chart removed from Forums.")
        XCTAssertEqual(fixture.store.state, .requiresPro)

        let withdrawn = await fixture.service.withdrawnPostIDs
        let removed = await fixture.service.removedPostIDs
        let homeRequests = await fixture.service.loadHomeRequests
        let published = await fixture.service.publishOwners
        XCTAssertEqual(withdrawn, [fixture.item.postID, fixture.item.postID])
        XCTAssertEqual(removed, [fixture.item.postID])
        XCTAssertEqual(homeRequests, 0)
        XCTAssertTrue(published.isEmpty)
        XCTAssertEqual(fixture.store.uploadQueue.first?.stage, .removed)
    }

    private var basic: AppEntitlements { AppEntitlements(subscription: .activePro(), accessPolicy: .betaBasic) }
    private var pro: AppEntitlements { AppEntitlements(subscription: .basic, accessPolicy: .freeAllFeatures) }

    private func ownedDetail(_ fixture: Fixture) -> IChartForumPostDetail {
        let song = ForumSong(id: UUID(), songTitle: "Owned Song", artistName: "Owned Artist")
        let post = ForumChartPost(id: fixture.item.postID, songID: song.id, ownerID: fixture.owner,
            chartTitle: fixture.chart.title, arrangerCredit: "Owner", creatorDisplayName: "Owner",
            tags: [], versionNote: nil, layoutStyle: fixture.chart.layoutStyle, pdfStoragePath: "existing.pdf",
            status: .published, voteUpCount: 0, voteDownCount: 0, reportCount: 0, rankingScore: 0,
            publishedAt: Date(timeIntervalSinceReferenceDate: 10))
        return IChartForumPostDetail(song: song, post: post, comments: [], authorBadges: [], currentUserVote: nil)
    }

    private func makeFixture(holdFirstPublish: Bool = false) throws -> Fixture {
        let suite = "IChartForumBetaQueueTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let owner = UUID()
        let chart = Chart.blank(title: "Existing Queue Chart")
        var draft = ForumPublishDraft()
        draft.selectedChartID = chart.id
        draft.songTitle = "Existing Song"
        draft.artistName = "Existing Artist"
        draft.arrangerCredit = "Existing Arranger"
        let item = ForumUploadQueueItem(id: UUID(), postID: UUID(), ownerID: owner, chartID: chart.id,
            chartTitle: chart.title, songTitle: draft.songTitle, artistName: draft.artistName, draft: draft,
            stage: .queued, createdAt: Date(timeIntervalSinceReferenceDate: 10),
            updatedAt: Date(timeIntervalSinceReferenceDate: 10), errorMessage: nil)
        defaults.set(try JSONEncoder().encode([item]), forKey: "iChartForumUploadQueue")
        let service = BetaQueueForumService(holdFirstPublish: holdFirstPublish)
        return Fixture(store: IChartForumStore(service: service, defaults: defaults), service: service,
            defaults: defaults, suite: suite, owner: owner, chart: chart, item: item)
    }

    private func waitUntil(_ condition: () async -> Bool) async throws {
        for _ in 0..<100 {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("The scripted Forum queue did not reach the expected state.")
        throw FixtureFailure.timeout
    }

    private struct Fixture {
        let store: IChartForumStore
        let service: BetaQueueForumService
        let defaults: UserDefaults
        let suite: String
        let owner: UUID
        let chart: Chart
        let item: ForumUploadQueueItem
        func clean() { defaults.removePersistentDomain(forName: suite) }
    }

    private enum FixtureFailure: Error { case timeout }
}

private actor BetaQueueForumService: IChartForumServicing {
    nonisolated let isConfigured = true
    private let holdFirstPublish: Bool
    private var heldPublish: CheckedContinuation<Void, Never>?
    private(set) var publishOwners: [UUID] = []
    private(set) var publishPostIDs: [UUID] = []
    private(set) var publishMutations = 0
    private(set) var withdrawnPostIDs: [UUID] = []
    private(set) var removedPostIDs: [UUID] = []
    private(set) var loadHomeRequests = 0
    private var homeReadsDenied = false
    var isHoldingFirstPublish: Bool { heldPublish != nil }

    init(holdFirstPublish: Bool) { self.holdFirstPublish = holdFirstPublish }

    func publish(chart: Chart, draft: ForumPublishDraft, ownerID: UUID, postID: UUID, exportedAt: Date,
                 progress: @escaping (ForumUploadStage) async -> Void) async throws {
        publishOwners.append(ownerID)
        publishPostIDs.append(postID)
        await progress(.preparingPDF)
        if holdFirstPublish, publishOwners.count == 1 {
            await withCheckedContinuation { heldPublish = $0 }
        }
        await progress(.validating)
        try Task.checkCancellation()
        publishMutations += 1
    }

    func releaseFirstPublish() { heldPublish?.resume(); heldPublish = nil }
    func rejectHomeReads() { homeReadsDenied = true }
    func loadHome(query: String) async throws -> [IChartForumSongSummary] {
        loadHomeRequests += 1
        if homeReadsDenied { throw Failure.homeReadDenied }
        return []
    }
    func loadPostDetail(postID: UUID, song: ForumSong) async throws -> IChartForumPostDetail { throw Failure.unused }
    func withdrawPost(postID: UUID) async throws { withdrawnPostIDs.append(postID) }
    func removePost(postID: UUID) async throws { removedPostIDs.append(postID) }
    func vote(postID: UUID, vote: ForumVoteValue) async throws {}
    func addComment(postID: UUID, body: String) async throws {}
    func reportPost(postID: UUID, reason: ForumReportReason, detail: String?) async throws {}
    func reportComment(commentID: UUID, reason: ForumReportReason, detail: String?) async throws {}
    func blockUser(ownerID: UUID) async throws {}
    func downloadPDF(for post: ForumChartPost) async throws -> ExportedPDF { throw Failure.unused }
    private enum Failure: Error { case unused, homeReadDenied }
}
#endif
