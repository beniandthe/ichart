#if canImport(UIKit)
import Foundation
import XCTest
@testable import iChart

@MainActor
final class IChartForumParticipationTests: XCTestCase {
    private let chartStyles: [ChartLayoutStyle] = [.simpleChordSheet, .rhythmSectionSheet]
    func testFailedCommentCanBeRetriedWithoutPostingTwice() async throws {
        for style in chartStyles {
            let fixture = try makeFixture(layoutStyle: style)
            defer { fixture.clean() }
            await fixture.store.openPost(fixture.detail.post, song: fixture.detail.song)
            await fixture.service.rejectNextComment()

            let failed = await fixture.store.addComment("Check the ending.", to: fixture.detail)

            XCTAssertFalse(failed)
            XCTAssertEqual(fixture.store.errorMessage, "Couldn’t post the comment.")
            XCTAssertEqual(fixture.store.selectedDetail?.comments, [])

            let posted = await fixture.store.addComment("Check the ending.", to: fixture.detail)

            XCTAssertTrue(posted)
            XCTAssertNil(fixture.store.errorMessage)
            XCTAssertEqual(fixture.store.selectedDetail?.comments.map(\.body), ["Check the ending."])
        }
    }

    func testAcknowledgedCommentRemainsPostedIfDiscussionRefreshFails() async throws {
        for style in chartStyles {
            let fixture = try makeFixture(layoutStyle: style)
            defer { fixture.clean() }
            await fixture.store.openPost(fixture.detail.post, song: fixture.detail.song)
            await fixture.service.rejectNextDetailLoad()

            let posted = await fixture.store.addComment("Check the ending.", to: fixture.detail)

            XCTAssertTrue(posted)
            XCTAssertEqual(fixture.store.errorMessage,
                           "Comment posted, but the discussion couldn’t refresh. Reopen it to load the latest comments.")
            XCTAssertEqual(fixture.store.selectedDetail?.comments, [])

            fixture.store.clearSelectedDetail()
            await fixture.store.openPost(fixture.detail.post, song: fixture.detail.song)

            XCTAssertNil(fixture.store.errorMessage)
            XCTAssertEqual(fixture.store.selectedDetail?.comments.map(\.body), ["Check the ending."])
        }
    }

    func testEarlierCommentsKeepHistoryAndNewestReplyInChronologicalOrder() async throws {
        for style in chartStyles {
            let fixture = try makeFixture(commentCount: 177, layoutStyle: style)
            defer { fixture.clean() }
            await fixture.store.openPost(fixture.detail.post, song: fixture.detail.song)
            XCTAssertEqual(fixture.store.selectedDetail?.comments.map(\.body), (97..<177).map(String.init))
            XCTAssertNotNil(fixture.store.selectedDetail?.earlierCommentCursor)

            await fixture.store.loadEarlierComments()
            XCTAssertEqual(fixture.store.selectedDetail?.comments.map(\.body), (17..<177).map(String.init))
            let posted = await fixture.store.addComment("A new reply", to: fixture.detail)
            XCTAssertTrue(posted)
            XCTAssertEqual(fixture.store.selectedDetail?.comments.map(\.body), (17..<177).map(String.init) + ["A new reply"])

            await fixture.store.loadEarlierComments()
            let detail = try XCTUnwrap(fixture.store.selectedDetail)
            XCTAssertEqual(detail.comments.map(\.body), (0..<177).map(String.init) + ["A new reply"])
            XCTAssertEqual(Set(detail.comments.map(\.id)).count, 178)
            XCTAssertNil(detail.earlierCommentCursor)
            XCTAssertNil(fixture.store.errorMessage)
        }
    }

    func testEarlierCommentFailureKeepsTheSameCursorForRetry() async throws {
        for style in chartStyles {
            let fixture = try makeFixture(commentCount: 161, layoutStyle: style)
            defer { fixture.clean() }
            await fixture.store.openPost(fixture.detail.post, song: fixture.detail.song)
            let before = try XCTUnwrap(fixture.store.selectedDetail)
            await fixture.service.rejectNextEarlierLoad()

            await fixture.store.loadEarlierComments()
            XCTAssertEqual(fixture.store.selectedDetail, before)
            XCTAssertFalse(fixture.store.isLoadingEarlierComments)
            XCTAssertEqual(fixture.store.errorMessage, "Couldn’t load earlier comments. Tap Load Earlier Comments to try again.")

            await fixture.store.loadEarlierComments()
            XCTAssertEqual(fixture.store.selectedDetail?.comments.count, 160)
            let cursors = await fixture.service.earlierCursors
            XCTAssertEqual(cursors, [before.earlierCommentCursor, before.earlierCommentCursor].compactMap { $0 })
            XCTAssertNil(fixture.store.errorMessage)
        }
    }

    func testEarlierCommentResponseCannotChangeAReopenedDiscussion() async throws {
        for style in chartStyles {
            let fixture = try makeFixture(commentCount: 161, layoutStyle: style)
            defer { fixture.clean() }
            await fixture.store.openPost(fixture.detail.post, song: fixture.detail.song)
            await fixture.service.holdNextEarlierLoad()
            let pending = Task { await fixture.store.loadEarlierComments() }
            for _ in 0..<100 {
                if await fixture.service.isEarlierLoadHeld { break }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            let pageIsHeld = await fixture.service.isEarlierLoadHeld
            XCTAssertTrue(pageIsHeld)
            XCTAssertTrue(fixture.store.isLoadingEarlierComments)
            fixture.store.clearSelectedDetail()
            await fixture.store.openPost(fixture.detail.post, song: fixture.detail.song)
            let reopened = fixture.store.selectedDetail
            await fixture.service.releaseEarlierLoad()
            await pending.value
            XCTAssertEqual(fixture.store.selectedDetail, reopened)
            XCTAssertEqual(fixture.store.selectedDetail?.comments.count, 80)
            XCTAssertFalse(fixture.store.isLoadingEarlierComments)
        }
    }

    func testAccountBadgesLoadEvenWhenNoAuthoredChartAppearsInTheFeed() async throws {
        for style in chartStyles {
            let fixture = try makeFixture(layoutStyle: style)
            defer { fixture.clean() }
            await fixture.store.refresh(
                authState: .signedIn(.init(id: fixture.detail.post.ownerID, email: nil, phone: nil, isEmailVerified: true)),
                entitlements: AppEntitlements(subscription: .basic, accessPolicy: .freeAllFeatures))
            XCTAssertEqual(fixture.store.state, .loaded([]))
            XCTAssertEqual(fixture.store.currentUserBadges, [.communityExpert])
        }
    }

    func testCommentCursorKeepsDatabaseMicrosecondsAndUsesIDForTimestampTies() throws {
        let firstTimestamp = "2026-11-03T10:00:00.123456+00:00"
        let secondTimestamp = "2026-11-03T10:00:00.123457+00:00"
        let firstDate = IChartForumDateParser.date(from: firstTimestamp)
        let secondDate = IChartForumDateParser.date(from: secondTimestamp)
        XCTAssertLessThan(firstDate, secondDate)
        let comment = ForumComment(id: UUID(), postID: UUID(), ownerID: UUID(), creatorDisplayName: "Author",
            body: "Exact boundary", createdAt: firstDate, paginationTimestamp: firstTimestamp)
        let cursor = ForumCommentCursor(comment)
        XCTAssertEqual(cursor.timestamp, firstTimestamp)
        XCTAssertEqual(cursor.postgrestFilter,
            "created_at.lt.\(firstTimestamp),and(created_at.eq.\(firstTimestamp),id.lt.\(comment.id.uuidString))")
    }

    private func makeFixture(commentCount: Int = 0, layoutStyle: ChartLayoutStyle = .simpleChordSheet) throws -> Fixture {
        let suite = "IChartForumParticipationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let song = ForumSong(id: UUID(), songTitle: "Test Song", artistName: "Test Artist")
        let post = ForumChartPost(
            id: UUID(), songID: song.id, ownerID: UUID(), chartTitle: "Test Chart", arrangerCredit: "Author",
            creatorDisplayName: "Author", tags: [], versionNote: nil, layoutStyle: layoutStyle,
            pdfStoragePath: "test.pdf", status: .published, voteUpCount: 0, voteDownCount: 0, reportCount: 0,
            rankingScore: 0, publishedAt: Date(timeIntervalSinceReferenceDate: 10)
        )
        let detail = IChartForumPostDetail(song: song, post: post, comments: [], authorBadges: [], currentUserVote: nil)
        let comments = (0..<commentCount).map { index in
            ForumComment(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!,
                postID: post.id, ownerID: post.ownerID, creatorDisplayName: "Author", body: String(index),
                createdAt: Date(timeIntervalSinceReferenceDate: Double(index / 4)))
        }
        let service = ForumParticipationService(detail: detail, comments: comments)
        return Fixture(
            store: IChartForumStore(service: service, defaults: defaults),
            service: service, detail: detail, defaults: defaults, suite: suite
        )
    }

    private struct Fixture {
        let store: IChartForumStore
        let service: ForumParticipationService
        let detail: IChartForumPostDetail
        let defaults: UserDefaults
        let suite: String

        func clean() { defaults.removePersistentDomain(forName: suite) }
    }
}

private actor ForumParticipationService: IChartForumServicing {
    nonisolated let isConfigured = true
    private let detail: IChartForumPostDetail
    private let commenterID = UUID()
    private var comments: [ForumComment] = []
    private var rejectsNextComment = false
    private var rejectsNextDetailLoad = false
    private var rejectsNextEarlierLoad = false
    private var holdsNextEarlierLoad = false
    private var earlierLoadContinuation: CheckedContinuation<Void, Never>?
    private(set) var earlierCursors: [ForumCommentCursor] = []

    init(detail: IChartForumPostDetail, comments: [ForumComment] = []) {
        self.detail = detail
        self.comments = comments
    }

    func rejectNextComment() { rejectsNextComment = true }
    func rejectNextDetailLoad() { rejectsNextDetailLoad = true }
    func rejectNextEarlierLoad() { rejectsNextEarlierLoad = true }
    func holdNextEarlierLoad() { holdsNextEarlierLoad = true }
    var isEarlierLoadHeld: Bool { earlierLoadContinuation != nil }
    func releaseEarlierLoad() {
        holdsNextEarlierLoad = false
        earlierLoadContinuation?.resume()
        earlierLoadContinuation = nil
    }

    func loadPostDetail(postID: UUID, song: ForumSong) async throws -> IChartForumPostDetail {
        if rejectsNextDetailLoad {
            rejectsNextDetailLoad = false
            throw Failure.refresh
        }
        let page = commentPage()
        return IChartForumPostDetail(
            song: song, post: detail.post, comments: page.comments,
            authorBadges: detail.authorBadges, currentUserVote: detail.currentUserVote,
            earlierCommentCursor: page.earlierCursor
        )
    }

    func loadEarlierComments(postID: UUID, before cursor: ForumCommentCursor) async throws -> ForumCommentPage {
        earlierCursors.append(cursor)
        if rejectsNextEarlierLoad {
            rejectsNextEarlierLoad = false
            throw Failure.refresh
        }
        let page = commentPage(before: cursor)
        if holdsNextEarlierLoad {
            holdsNextEarlierLoad = false
            await withCheckedContinuation { earlierLoadContinuation = $0 }
        }
        return page
    }

    func loadCurrentUserBadges() async throws -> [ForumAuthorBadgeType] { [.communityExpert] }

    private func commentPage(before cursor: ForumCommentCursor? = nil) -> ForumCommentPage {
        let selected = comments.filter { cursor?.includesEarlier($0) ?? true }.sorted {
            $0.createdAt == $1.createdAt ? $0.id.uuidString > $1.id.uuidString : $0.createdAt > $1.createdAt
        }
        return ForumCommentPage(descendingComments: selected)
    }

    func addComment(postID: UUID, body: String) async throws {
        if rejectsNextComment {
            rejectsNextComment = false
            throw Failure.send
        }
        comments.append(ForumComment(
            id: UUID(), postID: postID, ownerID: commenterID, creatorDisplayName: "Commenter",
            body: body, createdAt: Date(timeIntervalSinceReferenceDate: 10_000)
        ))
    }

    func loadHome(query: String) async throws -> [IChartForumSongSummary] { [] }
    func publish(chart: Chart, draft: ForumPublishDraft, ownerID: UUID, postID: UUID, exportedAt: Date,
                 progress: @escaping (ForumUploadStage) async -> Void) async throws { throw Failure.unused }
    func withdrawPost(postID: UUID) async throws { throw Failure.unused }
    func removePost(postID: UUID) async throws { throw Failure.unused }
    func vote(postID: UUID, vote: ForumVoteValue) async throws { throw Failure.unused }
    func reportPost(postID: UUID, reason: ForumReportReason, detail: String?) async throws { throw Failure.unused }
    func reportComment(commentID: UUID, reason: ForumReportReason, detail: String?) async throws { throw Failure.unused }
    func blockUser(ownerID: UUID) async throws { throw Failure.unused }
    func downloadPDF(for post: ForumChartPost) async throws -> ExportedPDF { throw Failure.unused }

    private enum Failure: LocalizedError {
        case send, refresh, unused

        var errorDescription: String? {
            switch self {
            case .send: return "Couldn’t post the comment."
            case .refresh: return "Couldn’t refresh the discussion."
            case .unused: return nil
            }
        }
    }
}
#endif
