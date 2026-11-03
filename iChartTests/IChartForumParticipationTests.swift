#if canImport(UIKit)
import Foundation
import XCTest
@testable import iChart

@MainActor
final class IChartForumParticipationTests: XCTestCase {
    func testFailedCommentCanBeRetriedWithoutPostingTwice() async throws {
        let fixture = try makeFixture()
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

    func testAcknowledgedCommentRemainsPostedIfDiscussionRefreshFails() async throws {
        let fixture = try makeFixture()
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

    private func makeFixture() throws -> Fixture {
        let suite = "IChartForumParticipationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let song = ForumSong(id: UUID(), songTitle: "Test Song", artistName: "Test Artist")
        let post = ForumChartPost(
            id: UUID(), songID: song.id, ownerID: UUID(), chartTitle: "Test Chart", arrangerCredit: "Author",
            creatorDisplayName: "Author", tags: [], versionNote: nil, layoutStyle: .simpleChordSheet,
            pdfStoragePath: "test.pdf", status: .published, voteUpCount: 0, voteDownCount: 0, reportCount: 0,
            rankingScore: 0, publishedAt: Date(timeIntervalSinceReferenceDate: 10)
        )
        let detail = IChartForumPostDetail(song: song, post: post, comments: [], authorBadges: [], currentUserVote: nil)
        let service = ForumParticipationService(detail: detail)
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

    init(detail: IChartForumPostDetail) {
        self.detail = detail
    }

    func rejectNextComment() { rejectsNextComment = true }
    func rejectNextDetailLoad() { rejectsNextDetailLoad = true }

    func loadPostDetail(postID: UUID, song: ForumSong) async throws -> IChartForumPostDetail {
        if rejectsNextDetailLoad {
            rejectsNextDetailLoad = false
            throw Failure.refresh
        }
        return IChartForumPostDetail(
            song: song, post: detail.post, comments: comments,
            authorBadges: detail.authorBadges, currentUserVote: detail.currentUserVote
        )
    }

    func addComment(postID: UUID, body: String) async throws {
        if rejectsNextComment {
            rejectsNextComment = false
            throw Failure.send
        }
        comments.append(ForumComment(
            id: UUID(), postID: postID, ownerID: commenterID, creatorDisplayName: "Commenter",
            body: body, createdAt: Date(timeIntervalSinceReferenceDate: 20)
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
