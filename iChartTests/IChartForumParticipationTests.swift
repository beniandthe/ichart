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

    func testVotingKeepsExpandedCommentHistoryAndCursorWithUpdatedVoteCounts() async throws {
        for style in chartStyles {
            let fixture = try makeFixture(commentCount: 177, layoutStyle: style)
            defer { fixture.clean() }
            await fixture.store.openPost(fixture.detail.post, song: fixture.detail.song)
            await fixture.store.loadEarlierComments()
            let expanded = try XCTUnwrap(fixture.store.selectedDetail)
            XCTAssertEqual(expanded.comments.map(\.body), (17..<177).map(String.init))
            let cursor = try XCTUnwrap(expanded.earlierCommentCursor)

            await fixture.store.vote(.up, on: expanded)

            let upvoted = try XCTUnwrap(fixture.store.selectedDetail)
            XCTAssertEqual(upvoted.currentUserVote, .up)
            XCTAssertEqual(upvoted.post.voteUpCount, 1)
            XCTAssertEqual(upvoted.post.voteDownCount, 0)
            XCTAssertEqual(upvoted.comments, expanded.comments)
            XCTAssertEqual(upvoted.earlierCommentCursor, cursor)
            XCTAssertEqual(Set(upvoted.comments.map(\.id)).count, 160)
            XCTAssertNil(fixture.store.errorMessage)

            await fixture.store.vote(.down, on: upvoted)

            let downvoted = try XCTUnwrap(fixture.store.selectedDetail)
            XCTAssertEqual(downvoted.currentUserVote, .down)
            XCTAssertEqual(downvoted.post.voteUpCount, 0)
            XCTAssertEqual(downvoted.post.voteDownCount, 1)
            XCTAssertEqual(downvoted.comments, expanded.comments)
            XCTAssertEqual(downvoted.earlierCommentCursor, cursor)
            XCTAssertEqual(Set(downvoted.comments.map(\.id)).count, 160)
            XCTAssertNil(fixture.store.errorMessage)

            await fixture.store.loadEarlierComments()

            let complete = try XCTUnwrap(fixture.store.selectedDetail)
            XCTAssertEqual(complete.comments.map(\.body), (0..<177).map(String.init))
            XCTAssertEqual(Set(complete.comments.map(\.id)).count, 177)
            XCTAssertNil(complete.earlierCommentCursor)
            XCTAssertEqual(complete.currentUserVote, .down)
            XCTAssertEqual(complete.post.voteUpCount, 0)
            XCTAssertEqual(complete.post.voteDownCount, 1)
            XCTAssertNil(fixture.store.errorMessage)
        }
    }

    func testOverlappingRefreshRemovesHiddenRecentCommentsAndKeepsExpandedHistory() async throws {
        for style in chartStyles {
            for addsReply in [false, true] {
                let fixture = try makeFixture(commentCount: 177, layoutStyle: style)
                defer { fixture.clean() }
                await fixture.store.openPost(fixture.detail.post, song: fixture.detail.song)
                await fixture.store.loadEarlierComments()
                let expanded = try XCTUnwrap(fixture.store.selectedDetail)
                let cursor = try XCTUnwrap(expanded.earlierCommentCursor)
                // Remove the old latest row too: interval reconnection must
                // use tuple positions rather than require a shared boundary ID.
                await fixture.service.setHiddenCommentBodies(["120", "176"])
                await fixture.service.appendComments(count: 20)

                try await refresh(fixture, addingReply: addsReply)

                let refreshed = try XCTUnwrap(fixture.store.selectedDetail)
                let expected = (17..<197).filter { $0 != 120 && $0 != 176 }.map(String.init)
                    + (addsReply ? ["A new reply"] : [])
                XCTAssertEqual(refreshed.comments.map(\.body), expected)
                XCTAssertTrue(refreshed.comments.contains { $0.body == "20" })
                XCTAssertEqual(refreshed.earlierCommentCursor, cursor)
                XCTAssertEqual(Set(refreshed.comments.map(\.id)).count, expected.count)
                await fixture.store.loadEarlierComments()
                let complete = try XCTUnwrap(fixture.store.selectedDetail)
                let allVisible = (0..<197).filter { $0 != 120 && $0 != 176 }.map(String.init)
                    + (addsReply ? ["A new reply"] : [])
                XCTAssertEqual(complete.comments.map(\.body), allVisible)
                XCTAssertEqual(Set(complete.comments.map(\.id)).count, allVisible.count)
                XCTAssertNil(complete.earlierCommentCursor)
                XCTAssertNil(fixture.store.errorMessage)
            }
        }
    }

    func testExhaustedRefreshReplacesCachedHistoryForEmptyPartialAndExactLimitResponses() async throws {
        for style in chartStyles {
            for visibleCount in [0, 10, 80] {
                let fixture = try makeFixture(commentCount: 177, layoutStyle: style)
                defer { fixture.clean() }
                await fixture.store.openPost(fixture.detail.post, song: fixture.detail.song)
                await fixture.store.loadEarlierComments()
                await fixture.store.loadEarlierComments()
                XCTAssertEqual(fixture.store.selectedDetail?.comments.count, 177)
                XCTAssertNil(fixture.store.selectedDetail?.earlierCommentCursor)
                await fixture.service.setHiddenCommentBodies(Set((0..<(177 - visibleCount)).map(String.init)))

                try await refresh(fixture, addingReply: false)

                let refreshed = try XCTUnwrap(fixture.store.selectedDetail)
                XCTAssertEqual(refreshed.comments.map(\.body), ((177 - visibleCount)..<177).map(String.init))
                XCTAssertEqual(Set(refreshed.comments.map(\.id)).count, visibleCount)
                XCTAssertNil(refreshed.earlierCommentCursor, "Exactly 80 rows can also be an exhausted response")
                XCTAssertNil(fixture.store.errorMessage)
            }
        }
    }

    func testDisjointRefreshKeepsAllGapsReachableWithPartialOrExhaustedOldHistory() async throws {
        for style in chartStyles {
            for (initialCount, loadAll) in [(177, false), (177, true), (40, false)] {
                for addsReply in [false, true] {
                    let fixture = try makeFixture(commentCount: initialCount, layoutStyle: style)
                    defer { fixture.clean() }
                    await fixture.store.openPost(fixture.detail.post, song: fixture.detail.song)
                    if initialCount > 80 { await fixture.store.loadEarlierComments() }
                    if loadAll { await fixture.store.loadEarlierComments() }
                    let previous = try XCTUnwrap(fixture.store.selectedDetail)
                    XCTAssertEqual(previous.earlierCommentCursor == nil, loadAll || initialCount < 80)
                    await fixture.service.appendComments(count: 200)

                    try await refresh(fixture, addingReply: addsReply)

                    let refreshed = try XCTUnwrap(fixture.store.selectedDetail)
                    let lowerIndex = initialCount + 200 - (addsReply ? 79 : 80)
                    let boundary = try XCTUnwrap(refreshed.comments.first { $0.body == String(lowerIndex) })
                    let refreshedCursor = try XCTUnwrap(refreshed.earlierCommentCursor)
                    XCTAssertEqual(refreshedCursor, ForumCommentCursor(boundary))
                    XCTAssertEqual(refreshedCursor.timestamp, boundary.paginationTimestamp)
                    XCTAssertTrue(refreshedCursor.timestamp.hasSuffix(".000000+00:00"))
                    XCTAssertNotEqual(refreshedCursor, previous.earlierCommentCursor)
                    XCTAssertTrue(Set(previous.comments.map(\.id)).isSubset(of: Set(refreshed.comments.map(\.id))))
                    await fixture.service.setHiddenCommentBodies(["20"])

                    try await loadAllEarlierComments(in: fixture)

                    let complete = try XCTUnwrap(fixture.store.selectedDetail)
                    let expected = (0..<(initialCount + 200)).filter { $0 != 20 }.map(String.init)
                        + (addsReply ? ["A new reply"] : [])
                    XCTAssertEqual(complete.comments.map(\.body), expected)
                    XCTAssertEqual(Set(complete.comments.map(\.id)).count, expected.count)
                    XCTAssertNil(complete.earlierCommentCursor)
                    XCTAssertNil(fixture.store.errorMessage)
                }
            }
        }
    }

    func testRefreshDoesNotReuseExhaustionWhenOlderVisibilityExtendsPastKnownHistory() async throws {
        for style in chartStyles {
            for (firstVisible, hidesLatest, addsNew) in [(137, true, false), (97, false, false), (97, false, true)] {
                let fixture = try makeFixture(commentCount: 177, layoutStyle: style)
                defer { fixture.clean() }
                await fixture.service.setHiddenCommentBodies(Set((0..<firstVisible).map(String.init)))
                await fixture.store.openPost(fixture.detail.post, song: fixture.detail.song)
                XCTAssertEqual(fixture.store.selectedDetail?.comments.map(\.body), (firstVisible..<177).map(String.init))
                XCTAssertNil(fixture.store.selectedDetail?.earlierCommentCursor)
                // Unhide older history with a lower, equal, or later fresh
                // boundary. None can reuse the cache's previous exhaustion.
                await fixture.service.setHiddenCommentBodies(hidesLatest ? ["176"] : [])
                if addsNew { await fixture.service.appendComments(count: 1) }

                try await refresh(fixture, addingReply: false)

                let refreshed = try XCTUnwrap(fixture.store.selectedDetail)
                let end = (hidesLatest ? 176 : 177) + (addsNew ? 1 : 0)
                let firstRetained = min(firstVisible, end - 80)
                XCTAssertEqual(refreshed.comments.map(\.body), (firstRetained..<end).map(String.init))
                let boundary = try XCTUnwrap(refreshed.comments.first { $0.body == String(end - 80) })
                let freshCursor = try XCTUnwrap(refreshed.earlierCommentCursor)
                XCTAssertEqual(freshCursor, ForumCommentCursor(boundary))
                XCTAssertEqual(freshCursor.timestamp, boundary.paginationTimestamp)
                try await loadAllEarlierComments(in: fixture)
                let complete = try XCTUnwrap(fixture.store.selectedDetail)
                XCTAssertEqual(complete.comments.map(\.body), (0..<end).map(String.init))
                XCTAssertEqual(Set(complete.comments.map(\.id)).count, end)
                XCTAssertNil(complete.earlierCommentCursor)
                XCTAssertNil(fixture.store.errorMessage)
            }
        }
    }

    func testRepeatedDisjointRefreshWalksPastOverlapUntilEveryEarlierGapIsFilled() async throws {
        for style in chartStyles {
            let fixture = try makeFixture(commentCount: 80, layoutStyle: style)
            defer { fixture.clean() }
            await fixture.store.openPost(fixture.detail.post, song: fixture.detail.song)
            XCTAssertNil(fixture.store.selectedDetail?.earlierCommentCursor)
            await fixture.service.appendComments(count: 90)
            try await refresh(fixture, addingReply: false)
            var detail = try XCTUnwrap(fixture.store.selectedDetail)
            XCTAssertEqual(detail.earlierCommentCursor?.id,
                try XCTUnwrap(detail.comments.first { $0.body == "90" }).id)
            await fixture.service.appendComments(count: 130)
            try await refresh(fixture, addingReply: false)
            detail = try XCTUnwrap(fixture.store.selectedDetail)
            XCTAssertEqual(detail.earlierCommentCursor?.id,
                try XCTUnwrap(detail.comments.first { $0.body == "220" }).id)

            await fixture.store.loadEarlierComments()

            detail = try XCTUnwrap(fixture.store.selectedDetail)
            XCTAssertEqual(detail.earlierCommentCursor?.id,
                try XCTUnwrap(detail.comments.first { $0.body == "140" }).id,
                "Overlap with 90...169 must not skip the unseen 80...89 gap")
            await fixture.store.loadEarlierComments()
            detail = try XCTUnwrap(fixture.store.selectedDetail)
            XCTAssertEqual(detail.earlierCommentCursor?.id,
                try XCTUnwrap(detail.comments.first { $0.body == "60" }).id)
            XCTAssertTrue((80..<90).allSatisfy { value in detail.comments.contains { $0.body == String(value) } })
            try await loadAllEarlierComments(in: fixture)
            let complete = try XCTUnwrap(fixture.store.selectedDetail)
            XCTAssertEqual(complete.comments.map(\.body), (0..<300).map(String.init))
            XCTAssertEqual(Set(complete.comments.map(\.id)).count, 300)
            XCTAssertNil(complete.earlierCommentCursor)
            XCTAssertNil(fixture.store.errorMessage)
        }
    }

    func testEarlierPagesReconcileTheirAuthoritativeIntervalsAndExhaustedHistory() async throws {
        for style in chartStyles {
            let fixture = try makeFixture(commentCount: 300, layoutStyle: style)
            defer { fixture.clean() }
            await fixture.store.openPost(fixture.detail.post, song: fixture.detail.song)
            await fixture.store.loadEarlierComments()
            XCTAssertEqual(fixture.store.selectedDetail?.comments.map(\.body), (140..<300).map(String.init))
            await fixture.service.appendComments(count: 200)
            try await refresh(fixture, addingReply: false)
            await fixture.store.loadEarlierComments()
            await fixture.service.setHiddenCommentBodies(["280"])

            await fixture.store.loadEarlierComments()

            let page = try XCTUnwrap(fixture.store.selectedDetail)
            let expected = (140..<500).filter { $0 != 280 }.map(String.init)
            XCTAssertEqual(page.comments.map(\.body), expected)
            XCTAssertEqual(Set(page.comments.map(\.id)).count, expected.count)
            XCTAssertEqual(page.earlierCommentCursor?.id,
                try XCTUnwrap(page.comments.first { $0.body == "259" }).id)
            XCTAssertTrue(page.comments.contains { $0.body == "140" })
            XCTAssertTrue(page.comments.contains { $0.body == "499" })
            // The remaining earlier response is complete, despite omitting
            // cached rows which became hidden outside the preceding page.
            await fixture.service.setHiddenCommentBodies(Set((0..<250).map(String.init)).union(["280"]))

            await fixture.store.loadEarlierComments()

            let complete = try XCTUnwrap(fixture.store.selectedDetail)
            let allVisible = (250..<500).filter { $0 != 280 }.map(String.init)
            XCTAssertEqual(complete.comments.map(\.body), allVisible)
            XCTAssertEqual(Set(complete.comments.map(\.id)).count, allVisible.count)
            XCTAssertNil(complete.earlierCommentCursor)
            XCTAssertNil(fixture.store.errorMessage)
        }
    }

    private func refresh(_ fixture: Fixture, addingReply: Bool) async throws {
        let detail = try XCTUnwrap(fixture.store.selectedDetail)
        if addingReply {
            let posted = await fixture.store.addComment("A new reply", to: detail)
            XCTAssertTrue(posted)
        } else {
            await fixture.store.vote(.up, on: detail)
        }
    }

    private func loadAllEarlierComments(in fixture: Fixture) async throws {
        for _ in 0..<8 {
            let detail = try XCTUnwrap(fixture.store.selectedDetail)
            guard detail.earlierCommentCursor != nil else { return }
            await fixture.store.loadEarlierComments()
            let next = try XCTUnwrap(fixture.store.selectedDetail)
            XCTAssertEqual(Set(next.comments.map(\.id)).count, next.comments.count)
        }
        XCTAssertNil(fixture.store.selectedDetail?.earlierCommentCursor, "Paging must finish within the fixture's bound")
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
        let comments: [ForumComment] = (0..<commentCount).map { index -> ForumComment in
            let idText = String(format: "00000000-0000-0000-0000-%012d", index + 1)
            let id = UUID(uuidString: idText)!
            let seconds = index / 4
            let createdAt = Date(timeIntervalSinceReferenceDate: Double(seconds))
            let timestamp = String(format: "2001-01-01T00:%02d:%02d.000000+00:00", seconds / 60, seconds % 60)
            return ForumComment(id: id, postID: post.id, ownerID: post.ownerID,
                creatorDisplayName: "Author", body: String(index), createdAt: createdAt,
                paginationTimestamp: timestamp)
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
    private var post: ForumChartPost
    private var currentUserVote: ForumVoteValue?
    private let commenterID = UUID()
    private var comments: [ForumComment] = []
    private var hiddenCommentBodies: Set<String> = []
    private var rejectsNextComment = false
    private var rejectsNextDetailLoad = false
    private var rejectsNextEarlierLoad = false
    private var holdsNextEarlierLoad = false
    private var earlierLoadContinuation: CheckedContinuation<Void, Never>?
    private(set) var earlierCursors: [ForumCommentCursor] = []

    init(detail: IChartForumPostDetail, comments: [ForumComment] = []) {
        self.detail = detail
        self.post = detail.post
        self.currentUserVote = detail.currentUserVote
        self.comments = comments
    }

    func setHiddenCommentBodies(_ bodies: Set<String>) { hiddenCommentBodies = bodies }

    func appendComments(count: Int) {
        let firstIndex = (comments.compactMap { Int($0.body) }.max() ?? -1) + 1
        for index in firstIndex..<(firstIndex + count) {
            comments.append(ForumComment(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!,
                postID: post.id, ownerID: commenterID, creatorDisplayName: "Peer", body: String(index),
                createdAt: Date(timeIntervalSinceReferenceDate: Double(index / 4)),
                paginationTimestamp: String(format: "2001-01-01T00:%02d:%02d.000000+00:00", index / 4 / 60, index / 4 % 60)))
        }
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
            song: song, post: post, comments: page.comments,
            authorBadges: detail.authorBadges, currentUserVote: currentUserVote,
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
        let selected = comments.filter {
            !hiddenCommentBodies.contains($0.body) && (cursor?.includesEarlier($0) ?? true)
        }.sorted {
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
    func vote(postID: UUID, vote: ForumVoteValue) async throws {
        guard postID == post.id else { throw Failure.unused }
        if currentUserVote == .up { post.voteUpCount -= 1 }
        if currentUserVote == .down { post.voteDownCount -= 1 }
        currentUserVote = vote
        if vote == .up { post.voteUpCount += 1 }
        if vote == .down { post.voteDownCount += 1 }
    }
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
