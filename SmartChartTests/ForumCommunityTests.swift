import XCTest
@testable import SmartChart

final class ForumCommunityTests: XCTestCase {
    func testPublishDraftValidationRequiresChartAndPublicMetadata() {
        let chartID = UUID()
        var draft = ForumPublishDraft()

        XCTAssertEqual(
            draft.validationErrors(availableChartIDs: [chartID]),
            [.missingChart]
        )

        draft.selectedChartID = chartID
        draft.songTitle = "  Blue   Bossa "
        draft.artistName = " Kenny Dorham "
        draft.chartTitle = " Rhythm Section "
        draft.arrangerCredit = " Beni Rossman "
        draft.creatorDisplayName = " Beni "
        draft.tagsText = "standard, rhythm section, Standard, live"

        XCTAssertTrue(draft.validationErrors(availableChartIDs: [chartID]).isEmpty)
        XCTAssertEqual(draft.normalizedSongTitle, "blue bossa")
        XCTAssertEqual(draft.normalizedArtistName, "kenny dorham")
        XCTAssertEqual(draft.sanitizedTags, ["standard", "rhythm section", "live"])
    }

    func testForumQualityPolicyPromotesTopRatedAndFlagsWeakPosts() {
        XCTAssertEqual(
            ForumQualityPolicy.displayStatus(
                moderationStatus: .published,
                upVotes: 0,
                downVotes: 0,
                reports: 0
            ),
            .new
        )
        XCTAssertEqual(
            ForumQualityPolicy.displayStatus(
                moderationStatus: .published,
                upVotes: 8,
                downVotes: 1,
                reports: 0
            ),
            .topRated
        )
        XCTAssertEqual(
            ForumQualityPolicy.displayStatus(
                moderationStatus: .published,
                upVotes: 1,
                downVotes: 5,
                reports: 0
            ),
            .needsReview
        )
        XCTAssertEqual(
            ForumQualityPolicy.displayStatus(
                moderationStatus: .published,
                upVotes: 8,
                downVotes: 1,
                reports: 3
            ),
            .needsReview
        )
        XCTAssertEqual(
            ForumQualityPolicy.displayStatus(
                moderationStatus: .removed,
                upVotes: 20,
                downVotes: 0,
                reports: 0
            ),
            .removed
        )
        XCTAssertGreaterThan(
            ForumQualityPolicy.rankingScore(upVotes: 8, downVotes: 1, reports: 0),
            ForumQualityPolicy.rankingScore(upVotes: 2, downVotes: 6, reports: 1)
        )
    }

    func testForumStoragePathUsesOwnerFolderAndPostPDF() {
        let ownerID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let postID = UUID(uuidString: "40000000-0000-0000-0000-000000000001")!
        let draft = ForumPublishDraft()

        XCTAssertEqual(
            draft.storagePath(ownerID: ownerID, postID: postID),
            "00000000-0000-0000-0000-000000000001/40000000-0000-0000-0000-000000000001.pdf"
        )
    }
}
