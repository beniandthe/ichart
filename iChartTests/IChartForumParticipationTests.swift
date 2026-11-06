#if canImport(UIKit)
import Foundation
import UIKit
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

    func testLateForumPDFCompletionCannotReopenClosedDetail() async throws {
        for style in chartStyles {
            for fails in [false, true] {
                let fixture = try makeFixture(layoutStyle: style)
                defer { fixture.clean() }
                authorizeForumAccess(fixture)
                await fixture.store.openPost(fixture.detail.post, song: fixture.detail.song)
                let pending = Task { await fixture.store.downloadPDF(for: fixture.detail) }
                try await waitForDownload(fixture, postID: fixture.detail.post.id)

                fixture.store.clearSelectedDetail()
                let pdf = sampleDownloadedPDF(for: fixture.detail.post)
                await fixture.service.releaseDownload(postID: fixture.detail.post.id, pdf: pdf, fails: fails)
                let result = await pending.value

                XCTAssertNil(result, "A dismissed request must not reach LibraryView's automatic PDF save")
                XCTAssertNil(fixture.store.selectedDetail)
                XCTAssertNil(fixture.store.downloadedPDF)
                XCTAssertNil(fixture.store.errorMessage, "An obsolete failure must not affect the next discussion")
                XCTAssertFalse(fixture.store.isWorking)
            }
        }
    }

    func testPreviousForumPDFCannotReplaceNewPostOrClearItsBusyState() async throws {
        for style in chartStyles {
            for oldRequestFails in [false, true] {
                let fixture = try makeFixture(layoutStyle: style)
                defer { fixture.clean() }
                authorizeForumAccess(fixture)
                await fixture.store.openPost(fixture.detail.post, song: fixture.detail.song)
                let oldDownload = Task { await fixture.store.downloadPDF(for: fixture.detail) }
                try await waitForDownload(fixture, postID: fixture.detail.post.id)

                let nextPost = otherPost(from: fixture.detail.post)
                await fixture.service.setPost(nextPost)
                await fixture.store.openPost(nextPost, song: fixture.detail.song)
                let nextDetail = try XCTUnwrap(fixture.store.selectedDetail)
                let nextDownload = Task { await fixture.store.downloadPDF(for: nextDetail) }
                try await waitForDownload(fixture, postID: nextPost.id)

                await fixture.service.releaseDownload(postID: fixture.detail.post.id,
                    pdf: sampleDownloadedPDF(for: fixture.detail.post), fails: oldRequestFails)
                let oldResult = await oldDownload.value
                XCTAssertNil(oldResult)
                XCTAssertEqual(fixture.store.selectedDetail?.post.id, nextPost.id)
                XCTAssertNil(fixture.store.downloadedPDF)
                XCTAssertNil(fixture.store.errorMessage)
                XCTAssertTrue(fixture.store.isWorking, "An old completion cannot finish the new post's request")

                let nextPDF = sampleDownloadedPDF(for: nextPost)
                await fixture.service.releaseDownload(postID: nextPost.id, pdf: nextPDF)
                let nextResult = await nextDownload.value
                XCTAssertEqual(nextResult?.url, nextPDF.url)
                XCTAssertEqual(fixture.store.downloadedPDF?.url, nextPDF.url)
                XCTAssertFalse(fixture.store.isWorking)

                await fixture.store.openPost(nextPost, song: fixture.detail.song)
                XCTAssertNil(fixture.store.downloadedPDF, "A reopened detail starts without the previous preview")
            }
        }
    }

    func testCancelledForumPDFRequestCannotPresentLateResult() async throws {
        for style in chartStyles {
            let fixture = try makeFixture(layoutStyle: style)
            defer { fixture.clean() }
            authorizeForumAccess(fixture)
            await fixture.store.openPost(fixture.detail.post, song: fixture.detail.song)
            let pending = Task { await fixture.store.downloadPDF(for: fixture.detail) }
            try await waitForDownload(fixture, postID: fixture.detail.post.id)

            pending.cancel()
            await fixture.service.releaseDownload(postID: fixture.detail.post.id,
                pdf: sampleDownloadedPDF(for: fixture.detail.post))
            let result = await pending.value
            let serviceWasCancelled = await fixture.service.cancelledDownloadIDs.contains(fixture.detail.post.id)

            XCTAssertNil(result)
            XCTAssertTrue(serviceWasCancelled, "Cancellation must reach the download task even if its provider completes late")
            XCTAssertNil(fixture.store.downloadedPDF)
            XCTAssertNil(fixture.store.errorMessage)
            XCTAssertFalse(fixture.store.isWorking)
        }
    }

    func testForumPDFCompletionIsIgnoredAfterMembershipOrAccountChanges() async throws {
        for style in chartStyles {
            for accessChange in 0..<3 {
                let fixture = try makeFixture(layoutStyle: style)
                defer { fixture.clean() }
                authorizeForumAccess(fixture)
                await fixture.store.openPost(fixture.detail.post, song: fixture.detail.song)
                let pending = Task { await fixture.store.downloadPDF(for: fixture.detail) }
                try await waitForDownload(fixture, postID: fixture.detail.post.id)

                let entitlements = accessChange == 1
                    ? AppEntitlements(subscription: .basic, accessPolicy: .betaBasic)
                    : AppEntitlements(subscription: .basic, accessPolicy: .freeAllFeatures)
                let ownerID: UUID? = accessChange == 0 ? nil
                    : accessChange == 1 ? fixture.detail.post.ownerID : UUID()
                fixture.store.applyAccess(entitlements: entitlements, charts: [], currentUserID: ownerID)
                await fixture.service.releaseDownload(postID: fixture.detail.post.id,
                    pdf: sampleDownloadedPDF(for: fixture.detail.post))
                let result = await pending.value

                XCTAssertNil(result)
                XCTAssertNil(fixture.store.selectedDetail)
                XCTAssertNil(fixture.store.downloadedPDF)
                XCTAssertNil(fixture.store.errorMessage)
                XCTAssertFalse(fixture.store.isWorking)
            }
        }
    }

    func testForumPDFCacheKeepsSameTitlePostsAndRetriesIndependent() throws {
        for style in chartStyles {
            let fixture = try makeFixture(layoutStyle: style)
            defer { fixture.clean() }
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("ForumPDFCacheTests-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let firstPost = fixture.detail.post
            let secondPost = otherPost(from: firstPost)
            let firstData = samplePDFData(label: "First chart", post: firstPost)
            let secondData = samplePDFData(label: "Different chart", post: secondPost)
            let retryData = samplePDFData(label: "Retry snapshot", post: firstPost)

            let first = try IChartForumPDFMetadata.cacheDownloadedPDF(data: firstData, post: firstPost, in: directory)
            let second = try IChartForumPDFMetadata.cacheDownloadedPDF(data: secondData, post: secondPost, in: directory)
            let retry = try IChartForumPDFMetadata.cacheDownloadedPDF(data: retryData, post: firstPost, in: directory)

            XCTAssertEqual(firstPost.chartTitle, secondPost.chartTitle)
            XCTAssertEqual(Set([first.url, second.url, retry.url]).count, 3)
            XCTAssertEqual(first.url.lastPathComponent, second.url.lastPathComponent,
                "The public filename stays readable while its private request directory carries identity")
            XCTAssertEqual(try Data(contentsOf: first.url), firstData)
            XCTAssertEqual(try Data(contentsOf: second.url), secondData)
            XCTAssertEqual(try Data(contentsOf: retry.url), retryData)
            for pdf in [first, second, retry] {
                XCTAssertEqual(pdf.layoutStyle, style)
                XCTAssertEqual(pdf.transpositionView, .eb)
                XCTAssertEqual(pdf.chordTranspositionSemitones, 3)
                XCTAssertEqual(pdf.pageCount, 1)
            }
        }
    }

    func testSearchPaginationAppendsOnceAndKeepsDuplicateSongPositionsStable() async throws {
        for style in chartStyles {
            let fixture = try makeFixture(layoutStyle: style)
            defer { fixture.clean() }
            authorizeForumAccess(fixture)
            let first = searchSummary(title: "First", style: style, ownerID: fixture.detail.post.ownerID)
            let second = searchSummary(title: "Second", style: style, ownerID: fixture.detail.post.ownerID)
            let cursor = IChartForumHomeCursor(updatedAt: "2026-11-05T12:13:14.123456+00:00", songID: first.id)
            await fixture.service.setFirstHomePage(query: "literal%_", page: .init(summaries: [first], nextCursor: cursor))
            await refreshSearch("literal%_", fixture: fixture)
            let next = Task { await fixture.store.loadMoreHome() }
            try await waitForHomePage(fixture, cursor: cursor)
            await fixture.service.releaseHomePage(cursor: cursor, page: .init(summaries: [first, second], nextCursor: nil))
            await next.value
            guard case .loaded(let summaries) = fixture.store.state else { return XCTFail("Expected loaded search results") }
            XCTAssertEqual(summaries, [first, second])
            XCTAssertEqual(summaries.flatMap(\.topPosts).map(\.layoutStyle), [style, style])
            XCTAssertNil(fixture.store.homeNextCursor)
            XCTAssertFalse(fixture.store.isLoadingMoreHome)
            await fixture.store.loadMoreHome()
            let requests = await fixture.service.homePageRequests
            XCTAssertEqual(requests.count, 2, "Each action fetches at most one bounded page; exhaustion does not fetch again")
            XCTAssertEqual(requests.last?.query, "literal%_")
            XCTAssertEqual(requests.last?.cursor, cursor)
        }
    }

    func testLateSearchPageCannotReplaceNewQueryOrClearItsLoadingState() async throws {
        for style in chartStyles {
            for oldPageFails in [false, true] {
                let fixture = try makeFixture(layoutStyle: style)
                defer { fixture.clean() }
                authorizeForumAccess(fixture)
                let first = searchSummary(title: "Old query", style: style, ownerID: fixture.detail.post.ownerID)
                let replacement = searchSummary(title: "New query", style: style, ownerID: fixture.detail.post.ownerID)
                let extra = searchSummary(title: "New next page", style: style, ownerID: fixture.detail.post.ownerID)
                let oldCursor = IChartForumHomeCursor(updatedAt: "2026-11-05T12:00:00.123456+00:00", songID: first.id)
                let newCursor = IChartForumHomeCursor(updatedAt: "2026-11-05T11:00:00.123456+00:00", songID: replacement.id)
                await fixture.service.setFirstHomePage(query: "old", page: .init(summaries: [first], nextCursor: oldCursor))
                await fixture.service.setFirstHomePage(query: "new", page: .init(summaries: [replacement], nextCursor: newCursor))
                await refreshSearch("old", fixture: fixture)
                let oldRequest = Task { await fixture.store.loadMoreHome() }
                try await waitForHomePage(fixture, cursor: oldCursor)
                await refreshSearch("new", fixture: fixture)
                let newRequest = Task { await fixture.store.loadMoreHome() }
                try await waitForHomePage(fixture, cursor: newCursor)

                await fixture.service.releaseHomePage(cursor: oldCursor,
                    page: .init(summaries: [first], nextCursor: nil), fails: oldPageFails)
                await oldRequest.value
                XCTAssertEqual(fixture.store.state, .loaded([replacement]))
                XCTAssertEqual(fixture.store.homeNextCursor, newCursor)
                XCTAssertTrue(fixture.store.isLoadingMoreHome)
                XCTAssertNil(fixture.store.errorMessage)

                await fixture.service.releaseHomePage(cursor: newCursor, page: .init(summaries: [extra], nextCursor: nil))
                await newRequest.value
                XCTAssertEqual(fixture.store.state, .loaded([replacement, extra]))
                XCTAssertFalse(fixture.store.isLoadingMoreHome)
            }
        }
    }

    func testFailedSearchPageKeepsResultsAndCursorForRetry() async throws {
        let fixture = try makeFixture()
        defer { fixture.clean() }
        authorizeForumAccess(fixture)
        let first = searchSummary(title: "Kept", style: .simpleChordSheet, ownerID: fixture.detail.post.ownerID)
        let cursor = IChartForumHomeCursor(updatedAt: "2026-11-05T12:13:14.123456+00:00", songID: first.id)
        await fixture.service.setFirstHomePage(query: "kept", page: .init(summaries: [first], nextCursor: cursor))
        await refreshSearch("kept", fixture: fixture)
        let failed = Task { await fixture.store.loadMoreHome() }
        try await waitForHomePage(fixture, cursor: cursor)
        await fixture.service.releaseHomePage(cursor: cursor, page: .init(summaries: [], nextCursor: nil), fails: true)
        await failed.value
        XCTAssertEqual(fixture.store.state, .loaded([first]))
        XCTAssertEqual(fixture.store.homeNextCursor, cursor)
        XCTAssertNotNil(fixture.store.errorMessage)
        XCTAssertFalse(fixture.store.isLoadingMoreHome)
        let retried = Task { await fixture.store.loadMoreHome() }
        try await waitForHomePage(fixture, cursor: cursor)
        await fixture.service.releaseHomePage(cursor: cursor, page: .init(summaries: [], nextCursor: nil))
        await retried.value
        XCTAssertEqual(fixture.store.state, .loaded([first]))
        XCTAssertNil(fixture.store.homeNextCursor)
        XCTAssertNil(fixture.store.errorMessage)
    }

    func testSearchPageIsRejectedAfterAccountOrAccessChange() async throws {
        for change in 0..<3 {
            let fixture = try makeFixture()
            defer { fixture.clean() }
            authorizeForumAccess(fixture)
            let first = searchSummary(title: "First", style: .simpleChordSheet, ownerID: fixture.detail.post.ownerID)
            let extra = searchSummary(title: "Obsolete", style: .simpleChordSheet, ownerID: fixture.detail.post.ownerID)
            let cursor = IChartForumHomeCursor(updatedAt: "2026-11-05T12:13:14.123456+00:00", songID: first.id)
            await fixture.service.setFirstHomePage(query: "first", page: .init(summaries: [first], nextCursor: cursor))
            await refreshSearch("first", fixture: fixture)
            let pending = Task { await fixture.store.loadMoreHome() }
            try await waitForHomePage(fixture, cursor: cursor)
            fixture.store.applyAccess(entitlements: AppEntitlements(subscription: .basic,
                accessPolicy: change == 1 ? .betaBasic : .freeAllFeatures), charts: [],
                currentUserID: change == 0 ? nil : change == 1 ? fixture.detail.post.ownerID : UUID())
            await fixture.service.releaseHomePage(cursor: cursor, page: .init(summaries: [extra], nextCursor: nil))
            await pending.value
            XCTAssertNil(fixture.store.homeNextCursor)
            XCTAssertFalse(fixture.store.isLoadingMoreHome)
            XCTAssertNil(fixture.store.errorMessage)
            if case .loaded(let summaries) = fixture.store.state { XCTAssertFalse(summaries.contains { $0.id == extra.id }) }
        }
    }

    func testAbandonedFirstSearchDoesNotLeaveBusyOrClearANewerRequest() async throws {
        for oldRequestFails in [false, true] {
            let fixture = try makeFixture()
            defer { fixture.clean() }
            authorizeForumAccess(fixture)
            await fixture.service.holdFirstHomePage(query: "old")
            await fixture.service.holdFirstHomePage(query: "new")
            let oldRequest = Task { await refreshSearch("old", fixture: fixture) }
            try await waitForFirstHomePage(fixture, query: "old")
            let newRequest = Task { await refreshSearch("new", fixture: fixture) }
            try await waitForFirstHomePage(fixture, query: "new")
            XCTAssertTrue(fixture.store.isWorking)
            await fixture.service.releaseFirstHomePage(query: "old", page: .init(summaries: [], nextCursor: nil), fails: oldRequestFails)
            await oldRequest.value
            XCTAssertTrue(fixture.store.isWorking, "An abandoned first-page completion cannot finish the newer operation")
            XCTAssertEqual(fixture.store.state, .loading)
            await fixture.service.releaseFirstHomePage(query: "new", page: .init(summaries: [], nextCursor: nil))
            await newRequest.value
            XCTAssertFalse(fixture.store.isWorking)
            XCTAssertEqual(fixture.store.state, .loaded([]))

            await fixture.service.holdFirstHomePage(query: "signed out")
            let signedOut = Task { await refreshSearch("signed out", fixture: fixture) }
            try await waitForFirstHomePage(fixture, query: "signed out")
            fixture.store.applyAccess(entitlements: AppEntitlements(subscription: .basic, accessPolicy: .freeAllFeatures),
                charts: [], currentUserID: nil)
            XCTAssertFalse(fixture.store.isWorking, "Invalidating the owned home request must not orphan its busy state")
            await fixture.service.releaseFirstHomePage(query: "signed out", page: .init(summaries: [], nextCursor: nil))
            await signedOut.value
            XCTAssertEqual(fixture.store.state, .signedOut)
            XCTAssertFalse(fixture.store.isWorking)
        }
    }

    func testSearchWireParametersKeepLiteralTextAndMicrosecondCursor() throws {
        let query = "50%_O'Reilly,(score.gt.0) \\\"São\\\""
        let cursor = IChartForumHomeCursor(updatedAt: "2026-11-05T12:13:14.123456+00:00", songID: UUID())
        let data = try JSONEncoder().encode(ForumHomeSearchParameters(searchQuery: query,
            afterUpdatedAt: cursor.updatedAt, afterSongID: cursor.songID))
        let value = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(value["search_query"] as? String, query)
        XCTAssertEqual(value["page_size"] as? Int, 20)
        XCTAssertEqual(value["after_updated_at"] as? String, cursor.updatedAt)
        XCTAssertEqual(value["after_song_id"] as? String, cursor.songID.uuidString)
        XCTAssertThrowsError(try ForumHomeSearchParameters(searchQuery: String(repeating: "é", count: 201),
            afterUpdatedAt: nil, afterSongID: nil))
        XCTAssertThrowsError(try ForumHomeSearchParameters(searchQuery: "literal", afterUpdatedAt: cursor.updatedAt, afterSongID: nil))
        let normalized = try ForumHomeSearchParameters(searchQuery: "  SÃO\t Paulo  ", afterUpdatedAt: nil, afterSongID: nil)
        XCTAssertEqual(normalized.searchQuery, "SÃO Paulo")
    }

    func testSearchWireLeavesUnicodeCaseNormalizationToDatabase() throws {
        let cases: [(input: String, expectedScalars: [UInt32])] = [
            ("  İSTANBUL\t", [0x0130, 0x0053, 0x0054, 0x0041, 0x004E, 0x0042, 0x0055, 0x004C]),
            ("  ΟΣ  ", [0x039F, 0x03A3]),
            ("  Cafe\u{0301}\t", [0x0043, 0x0061, 0x0066, 0x00E9])
        ]
        for entry in cases {
            let parameters = try ForumHomeSearchParameters(searchQuery: entry.input,
                afterUpdatedAt: nil, afterSongID: nil)
            let data = try JSONEncoder().encode(parameters)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let query = try XCTUnwrap(object["search_query"] as? String)
            XCTAssertEqual(query.unicodeScalars.map(\.value), entry.expectedScalars,
                "Only whitespace and canonical composition may change before the SQL engine normalizes case for both sides.")
        }
    }

    func testSearchResponseRejectsOversizedDuplicateOrNonPublicPages() throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet, .leadSheet] {
            let valid = searchResponse(songCount: 20, style: style)
            let page = try IChartForumSearchResponseDecoder.decode(JSONSerialization.data(withJSONObject: valid))
            XCTAssertEqual(page.summaries.count, 20)
            XCTAssertEqual(page.summaries.flatMap(\.topPosts).count, 60)
            XCTAssertEqual(page.summaries.flatMap(\.topPosts).map(\.layoutStyle), Array(repeating: style, count: 60))
            XCTAssertEqual(page.nextCursor?.updatedAt, "2026-11-05T12:13:14.123456+00:00")
        }
        for mutation in 0..<5 {
            var response = searchResponse(songCount: mutation == 0 ? 21 : 1, style: .simpleChordSheet)
            var songs = try XCTUnwrap(response["songs"] as? [[String: Any]])
            if mutation == 1 { songs.append(songs[0]) }
            if mutation == 2 || mutation == 3 {
                var posts = try XCTUnwrap(songs[0]["posts"] as? [[String: Any]])
                if mutation == 2 { posts.append(posts[0]) }
                else { posts[0]["status"] = "pending" }
                songs[0]["posts"] = posts
            }
            response["songs"] = songs
            if mutation == 4 { response["next_cursor"] = ["updated_at": "2026-11-05T12:13:14.123457+00:00", "id": UUID().uuidString] }
            XCTAssertThrowsError(try IChartForumSearchResponseDecoder.decode(JSONSerialization.data(withJSONObject: response)))
        }
    }

    private func searchResponse(songCount: Int, style: ChartLayoutStyle) -> [String: Any] {
        let timestamp = "2026-11-05T12:13:14.123456+00:00"
        let songs: [[String: Any]] = (0..<songCount).map { index in
            let songID = UUID()
            let posts: [[String: Any]] = (0..<3).map { rank in
                ["id": UUID().uuidString, "song_id": songID.uuidString, "owner_id": UUID().uuidString,
                 "chart_title": "Chart \(index)", "arranger_credit": "Arranger", "creator_display_name": "Creator",
                 "tags": ["literal%_"], "layout_style": style.rawValue, "pdf_storage_path": "fixture.pdf",
                 "status": "published", "vote_up_count": 0, "vote_down_count": 0, "report_count": 0,
                 "ranking_score": 3 - rank, "published_at": timestamp]
            }
            return ["song": ["id": songID.uuidString, "song_title": "Song \(index)", "artist_name": "Artist", "updated_at": timestamp], "posts": posts]
        }
        let lastSong = songs.last?["song"] as? [String: Any]
        var response: [String: Any] = ["songs": songs]
        if let lastSong { response["next_cursor"] = ["updated_at": timestamp, "id": lastSong["id"]!] }
        else { response["next_cursor"] = NSNull() }
        return response
    }

    private func searchSummary(title: String, style: ChartLayoutStyle, ownerID: UUID) -> IChartForumSongSummary {
        let song = ForumSong(id: UUID(), songTitle: title, artistName: "Paging artist")
        let post = ForumChartPost(id: UUID(), songID: song.id, ownerID: ownerID,
            chartTitle: title, arrangerCredit: "Paging arranger", creatorDisplayName: "Paging creator",
            tags: ["literal%_"], versionNote: nil, layoutStyle: style, pdfStoragePath: "fixture.pdf",
            status: .published, voteUpCount: 0, voteDownCount: 0, reportCount: 0, rankingScore: 1, publishedAt: .now)
        return IChartForumSongSummary(song: song, topPosts: [post])
    }

    private func refreshSearch(_ query: String, fixture: Fixture) async {
        await fixture.store.refresh(authState: .signedIn(.init(id: fixture.detail.post.ownerID, email: nil,
            phone: nil, isEmailVerified: true)), entitlements: AppEntitlements(subscription: .basic,
            accessPolicy: .freeAllFeatures), query: query)
    }

    private func waitForHomePage(_ fixture: Fixture, cursor: IChartForumHomeCursor) async throws {
        for _ in 0..<100 {
            if await fixture.service.hasPendingHomePage(cursor: cursor) { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Expected one controlled search-page request")
        throw NSError(domain: "ForumSearchPageTests", code: 1)
    }

    private func waitForFirstHomePage(_ fixture: Fixture, query: String) async throws {
        for _ in 0..<100 {
            if await fixture.service.hasPendingFirstHomePage(query: query) { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Expected one controlled first search page")
        throw NSError(domain: "ForumSearchPageTests", code: 2)
    }

    private func authorizeForumAccess(_ fixture: Fixture) {
        fixture.store.applyAccess(entitlements: AppEntitlements(subscription: .basic, accessPolicy: .freeAllFeatures),
            charts: [], currentUserID: fixture.detail.post.ownerID)
    }

    private func waitForDownload(_ fixture: Fixture, postID: UUID) async throws {
        for _ in 0..<100 {
            if await fixture.service.hasPendingDownload(postID: postID) { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Expected the controlled forum download to start")
        throw NSError(domain: "ForumDownloadTests", code: 1)
    }

    private func otherPost(from post: ForumChartPost) -> ForumChartPost {
        ForumChartPost(id: UUID(), songID: post.songID, ownerID: post.ownerID,
            chartTitle: post.chartTitle, arrangerCredit: post.arrangerCredit,
            creatorDisplayName: post.creatorDisplayName, tags: post.tags, versionNote: post.versionNote,
            layoutStyle: post.layoutStyle, pdfStoragePath: "another.pdf", status: post.status,
            voteUpCount: 0, voteDownCount: 0, reportCount: 0, rankingScore: 0, publishedAt: post.publishedAt)
    }

    private func sampleDownloadedPDF(for post: ForumChartPost) -> ExportedPDF {
        ExportedPDF(url: FileManager.default.temporaryDirectory.appendingPathComponent("\(post.id).pdf"),
            chartTitle: post.chartTitle, layoutStyle: post.layoutStyle,
            transpositionView: .concert, chordTranspositionSemitones: 0,
            pageCount: 1, fileSizeBytes: 100, exportedAt: Date())
    }

    private func samplePDFData(label: String, post: ForumChartPost) -> Data {
        var chart = Chart.blank(title: post.chartTitle, measureCount: 1, layoutStyle: post.layoutStyle)
        chart.defaultTranspositionView = .eb
        chart.chordTranspositionSemitones = 3
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextSubject as String:
            ForumPDFInstrumentSnapshot(chart: chart, forumPostID: post.id).subjectText]
        return UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 120, height: 120), format: format).pdfData { context in
            context.beginPage()
            (label as NSString).draw(at: CGPoint(x: 10, y: 10), withAttributes: [.font: UIFont.systemFont(ofSize: 12)])
        }
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
    private var downloadContinuations: [UUID: CheckedContinuation<ExportedPDF, Error>] = [:]
    private(set) var cancelledDownloadIDs: Set<UUID> = []
    private(set) var earlierCursors: [ForumCommentCursor] = []
    struct HomePageRequest { let query: String; let cursor: IChartForumHomeCursor? }
    private(set) var homePageRequests: [HomePageRequest] = []
    private var firstHomePages: [String: IChartForumHomePage] = [:]
    private var homePageContinuations: [UUID: CheckedContinuation<IChartForumHomePage, Error>] = [:]
    private var heldFirstHomeQueries: Set<String> = []
    private var firstHomeContinuations: [String: CheckedContinuation<IChartForumHomePage, Error>] = [:]

    init(detail: IChartForumPostDetail, comments: [ForumComment] = []) {
        self.detail = detail
        self.post = detail.post
        self.currentUserVote = detail.currentUserVote
        self.comments = comments
    }

    func setHiddenCommentBodies(_ bodies: Set<String>) { hiddenCommentBodies = bodies }
    func setPost(_ post: ForumChartPost) { self.post = post }
    func setFirstHomePage(query: String, page: IChartForumHomePage) { firstHomePages[query] = page }
    func holdFirstHomePage(query: String) { heldFirstHomeQueries.insert(query) }
    func hasPendingFirstHomePage(query: String) -> Bool { firstHomeContinuations[query] != nil }
    func releaseFirstHomePage(query: String, page: IChartForumHomePage, fails: Bool = false) {
        heldFirstHomeQueries.remove(query)
        let continuation = firstHomeContinuations.removeValue(forKey: query)
        if fails { continuation?.resume(throwing: Failure.refresh) }
        else { continuation?.resume(returning: page) }
    }
    func hasPendingHomePage(cursor: IChartForumHomeCursor) -> Bool { homePageContinuations[cursor.songID] != nil }
    func releaseHomePage(cursor: IChartForumHomeCursor, page: IChartForumHomePage, fails: Bool = false) {
        let continuation = homePageContinuations.removeValue(forKey: cursor.songID)
        if fails { continuation?.resume(throwing: Failure.refresh) }
        else { continuation?.resume(returning: page) }
    }
    func hasPendingDownload(postID: UUID) -> Bool { downloadContinuations[postID] != nil }
    func releaseDownload(postID: UUID, pdf: ExportedPDF, fails: Bool = false) {
        let continuation = downloadContinuations.removeValue(forKey: postID)
        if fails { continuation?.resume(throwing: Failure.refresh) }
        else { continuation?.resume(returning: pdf) }
    }

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
    func loadHomePage(query: String, after cursor: IChartForumHomeCursor?) async throws -> IChartForumHomePage {
        homePageRequests.append(.init(query: query, cursor: cursor))
        guard let cursor else {
            if heldFirstHomeQueries.contains(query) {
                return try await withCheckedThrowingContinuation { firstHomeContinuations[query] = $0 }
            }
            return firstHomePages[query] ?? .init(summaries: [], nextCursor: nil)
        }
        // Deliberately resume even after cancellation so store generation and
        // account guards must reject obsolete results independently.
        return try await withCheckedThrowingContinuation { homePageContinuations[cursor.songID] = $0 }
    }
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
    func downloadPDF(for post: ForumChartPost) async throws -> ExportedPDF {
        // A provider can finish after cancellation. Hold it until the test
        // releases success/error so session guards, not cancellation alone,
        // must prevent stale presentation and automatic library saving.
        defer { if Task.isCancelled { cancelledDownloadIDs.insert(post.id) } }
        return try await withCheckedThrowingContinuation { downloadContinuations[post.id] = $0 }
    }

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
