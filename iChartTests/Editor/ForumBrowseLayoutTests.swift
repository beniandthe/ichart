#if canImport(UIKit)
import Combine
import SwiftUI
import UIKit
import XCTest
@testable import iChart

/// Mounted production views; no account, network, PDF upload or store mutation.
@MainActor
final class ForumBrowseLayoutTests: XCTestCase {
    private let helperText = "Search songs, artists, arrangers, or tags, then tap Search. Use Load More for more matches. Open a chart to preview its PDF or discuss it."

    func testTopChartsCardsAndSearchFitNarrowAndAvailableWidthsForBothStyles() async throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            for requestedWidth in [CGFloat(360), 568, 900] {
                let fixture = Fixture(style: style)
                let mounted = try await mount(fixture, width: requestedWidth, category: .large)
                let original = fixture.summaries
                let search = try await searchField(in: mounted)
                let helper = try await node(helperText, in: mounted)
                assertContained(search.convert(search.bounds, to: mounted.window), in: mounted.viewport)
                assertContained(helper.frame(in: mounted.window), in: mounted.viewport)
                let helperHeight = helper.frame(in: mounted.window).height
                if mounted.viewport.width <= 568 {
                    XCTAssertGreaterThan(helperHeight, 20,
                        "The narrow entry helper must wrap into readable lines")
                } else {
                    XCTAssertGreaterThanOrEqual(helperHeight,
                        UIFont.preferredFont(forTextStyle: .subheadline).lineHeight - 0.5,
                        "A wider pane may fit the complete helper on one readable line")
                }

                var observedPeriods = Set<String>()
                var observedCards = Set<UUID>()
                try await inspectEveryScrollPosition(mounted) { nodes in
                    for value in nodes {
                        let label = value.element.accessibilityLabel ?? ""
                        let frame = value.frame(in: mounted.window)
                        guard !frame.intersection(mounted.viewport).isEmpty else { continue }
                        if label.hasSuffix(" top charts") {
                            observedPeriods.insert(label)
                            assertHorizontallyContained(frame, in: mounted.viewport)
                        }
                        for post in fixture.summaries.flatMap(\.topPosts) where
                            label == "Open \(post.chartTitle)" || label == "Open lead chart \(post.chartTitle)" {
                            observedCards.insert(post.id)
                            assertHorizontallyContained(frame, in: mounted.viewport)
                            XCTAssertGreaterThan(frame.width, min(150, mounted.viewport.width - 90),
                                "A card must leave room for readable author badges")
                            XCTAssertLessThan(frame.height, 270,
                                "A two-badge card must not become a tower of individual letters")
                            let badgeValue = value.element.accessibilityValue ?? ""
                            XCTAssertTrue(badgeValue.contains("Verified Contributor"))
                            XCTAssertTrue(badgeValue.contains("Trusted Arranger"))
                        }
                    }
                }
                XCTAssertEqual(observedPeriods, Set(["Today", "This Week", "This Month", "All Time"].map { "\($0) top charts" }))
                XCTAssertEqual(observedCards, Set(fixture.summaries.flatMap(\.topPosts).map(\.id)))
                XCTAssertEqual(fixture.summaries, original)
                XCTAssertTrue(fixture.openedPosts.isEmpty)
                XCTAssertTrue(fixture.searchRequests.isEmpty)
                XCTAssertEqual(fixture.publishCount, 0)
                mounted.scroll.setContentOffset(.zero, animated: false)
                try await settle(mounted.window)
                attach(mounted, name: "Forum \(style.rawValue) readable cards width \(Int(mounted.viewport.width))")
                await mounted.close()
            }
        }
    }

    func testAccessibilityCardsAndWholeBadgeNamesRemainInsideTheForumPane() async throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            let fixture = Fixture(style: style)
            let mounted = try await mount(fixture, width: 360, category: .accessibilityExtraExtraLarge)
            let helper = try await node(helperText, in: mounted)
            assertContained(helper.frame(in: mounted.window), in: mounted.viewport)
            let field = try await searchField(in: mounted)
            assertContained(field.convert(field.bounds, to: mounted.window), in: mounted.viewport)
            var periodFrames: [String: CGRect] = [:]
            try await inspectEveryScrollPosition(mounted) { nodes in
                for value in nodes {
                    let label = value.element.accessibilityLabel ?? ""
                    let frame = value.frame(in: mounted.window)
                    guard !frame.intersection(mounted.viewport).isEmpty else { continue }
                    if label.hasSuffix(" top charts") {
                        periodFrames[label] = frame
                        assertHorizontallyContained(frame, in: mounted.viewport)
                        XCTAssertGreaterThan(frame.width, mounted.viewport.width * 0.65,
                            "Accessibility text needs one readable column in this narrow pane")
                    }
                    if label.hasPrefix("Open ") {
                        assertHorizontallyContained(frame, in: mounted.viewport)
                        XCTAssertGreaterThan(frame.width, mounted.viewport.width * 0.60)
                    }
                }
            }
            XCTAssertEqual(periodFrames.count, 4)
            XCTAssertTrue(fixture.openedPosts.isEmpty)
            XCTAssertEqual(fixture.publishCount, 0)
            mounted.scroll.setContentOffset(.zero, animated: false)
            try await settle(mounted.window)
            attach(mounted, name: "Forum \(style.rawValue) accessibility entry and cards")
            await mounted.close()
        }

        // Inspect the actual badge view outside an aggregating post button, so
        // the rendered preferred-size labels have their own measurable frames.
        for category in [ContentSizeCategory.large, .accessibilityExtraExtraLarge] {
            let mounted = try await mountContent(
                AnyView(IChartForumBadgeLabels(badges: [.verifiedContributor, .trustedArranger])),
                width: 284, category: category)
            let uiCategory: UIContentSizeCategory = category == .large ? .large : .accessibilityExtraExtraLarge
            let lineHeight = UIFont.preferredFont(forTextStyle: .caption2,
                compatibleWith: UITraitCollection(preferredContentSizeCategory: uiCategory)).lineHeight
            for name in ["Verified Contributor", "Trusted Arranger"] {
                let badge = try await node(name, in: mounted)
                let frame = badge.frame(in: mounted.window)
                assertContained(frame, in: mounted.viewport)
                XCTAssertGreaterThanOrEqual(frame.height, lineHeight * 0.75,
                    "Keep the preferred caption size rather than shrinking badge identity away")
                XCTAssertLessThan(frame.height, lineHeight * 3 + 6,
                    "The complete badge name must wrap as words, not individual letters")
            }
            attach(mounted, name: "Forum whole badge labels \(category)")
            await mounted.close()
        }
    }

    func testEditingSubmittedSearchKeepsItsFieldFocusAndQueryThroughRefreshAndRetry() async throws {
        let fixture = Fixture(style: .rhythmSectionSheet)
        fixture.searchText = "Dm7"
        let original = fixture.summaries
        let mounted = try await mount(fixture, width: 568, category: .large)
        defer { mounted.window.endEditing(true) }
        let field = try await searchField(in: mounted)
        try activate(try await node("Search", in: mounted, button: true))
        try await wait(mounted.window) { fixture.searchRequests == ["Dm7"] && fixture.state == .loading }
        let loadingField = try await searchField(in: mounted)
        XCTAssertTrue(loadingField === field)
        fixture.state = .loaded(fixture.summaries)
        try await settle(mounted.window)
        XCTAssertTrue(field.becomeFirstResponder())
        try await wait(mounted.window) { field.isFirstResponder }
        try await settle(mounted.window)
        let focusedFrame = field.convert(field.bounds, to: mounted.window)
        let focusedScrollOffset = mounted.scroll.contentOffset

        field.text = "Dm7 A"
        field.sendActions(for: .editingChanged)
        try await wait(mounted.window) { fixture.searchText == "Dm7 A" && fixture.searchRequests == ["Dm7", ""] }
        XCTAssertEqual(fixture.state, .loading,
            "The fixture must exercise the real first-edit default-catalog refresh")
        try await assertSameFocusedField(field, frame: focusedFrame, in: mounted)

        field.text = "Dm7 Am"
        field.sendActions(for: .editingChanged)
        try await wait(mounted.window) { fixture.searchText == "Dm7 Am" }
        XCTAssertEqual(fixture.searchRequests, ["Dm7", ""], "Typing must not add a request per character")
        for state in [IChartForumState.loaded(fixture.summaries), .failed("Disposable local retry fixture"), .loading] {
            fixture.state = state
            try await settle(mounted.window)
            try await assertSameFocusedField(field, frame: focusedFrame, in: mounted)
            XCTAssertEqual(field.text, "Dm7 Am")
            XCTAssertEqual(fixture.searchText, "Dm7 Am")
            XCTAssertEqual(mounted.scroll.contentOffset.y, focusedScrollOffset.y, accuracy: 1.5)
        }
        fixture.state = .failed("Disposable local retry fixture")
        try await settle(mounted.window)
        try activate(try await node("Retry", in: mounted, button: true))
        try await wait(mounted.window) { fixture.retryCount == 1 && fixture.state == .loading }
        try await assertSameFocusedField(field, frame: focusedFrame, in: mounted)
        XCTAssertEqual(fixture.searchRequests, ["Dm7", ""])
        XCTAssertEqual(fixture.searchText, "Dm7 Am")
        XCTAssertEqual(fixture.summaries, original)
        XCTAssertTrue(fixture.openedPosts.isEmpty)
        XCTAssertEqual(fixture.publishCount, 0)
        attach(mounted, name: "Forum focused search survives loading and retry")
        field.resignFirstResponder()
        await mounted.close()
    }

    func testSubmittedQuerySurvivesForumRecreationAndRetryUsesTheVisibleDraft() async throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            let fixture = Fixture(style: style)
            fixture.searchText = " Dm7 "
            let original = fixture.summaries
            let mounted = try await mount(fixture, width: 568, category: .large)
            let originalField = try await searchField(in: mounted)
            XCTAssertEqual(originalField.text, " Dm7 ")
            XCTAssertEqual(fixture.submittedSearchText, "")
            try await assertResultsMode(false, in: mounted)
            XCTAssertTrue(fixture.refreshQueries.isEmpty,
                "Appearing with a field draft must not invent a submitted query or request")

            try activate(try await node("Search", in: mounted, button: true))
            try await wait(mounted.window) {
                fixture.searchRequests == [" Dm7 "] && fixture.state == .loading
                    && fixture.submittedSearchText == "Dm7"
            }
            fixture.state = .loaded(fixture.summaries)
            try await assertResultsMode(true, in: mounted)

            // A library tab change destroys and recreates ForumHome while its
            // parent retains both the field draft and the actual request mode.
            fixture.recreateForum()
            try await settle(mounted.window)
            let returnedField = try await searchField(in: mounted)
            XCTAssertFalse(returnedField === originalField,
                "Exercise a new native control, not merely a loaded-state redraw")
            XCTAssertEqual(returnedField.text, " Dm7 ")
            XCTAssertEqual(fixture.submittedSearchText, "Dm7")
            XCTAssertEqual(fixture.refreshQueries, [" Dm7 ", " Dm7 "])
            fixture.state = .loaded(fixture.summaries)
            try await assertResultsMode(true, in: mounted)

            XCTAssertTrue(returnedField.becomeFirstResponder())
            try await wait(mounted.window) { returnedField.isFirstResponder }
            try await settle(mounted.window)
            let focusedFrame = returnedField.convert(returnedField.bounds, to: mounted.window)
            returnedField.text = "Dm7 A"
            returnedField.sendActions(for: .editingChanged)
            returnedField.sendActions(for: .editingChanged)
            try await wait(mounted.window) {
                fixture.searchText == "Dm7 A" && fixture.searchRequests == [" Dm7 ", ""]
                    && fixture.submittedSearchText == ""
            }
            try await assertSameFocusedField(returnedField, frame: focusedFrame, in: mounted)
            returnedField.text = "Dm7 Am"
            returnedField.sendActions(for: .editingChanged)
            try await wait(mounted.window) { fixture.searchText == "Dm7 Am" }
            XCTAssertEqual(fixture.searchRequests, [" Dm7 ", ""],
                "Only the original first-edit default reset may request a refresh")

            fixture.state = .failed("Disposable local retry fixture")
            try await settle(mounted.window)
            try activate(try await node("Retry", in: mounted, button: true))
            try await wait(mounted.window) {
                fixture.retryCount == 1 && fixture.state == .loading
                    && fixture.submittedSearchText == "Dm7 Am"
            }
            try await assertSameFocusedField(returnedField, frame: focusedFrame, in: mounted)
            XCTAssertEqual(fixture.refreshQueries, [" Dm7 ", " Dm7 ", "", "Dm7 Am"],
                "Retry must label the exact query it requests, not the earlier blank refresh")
            XCTAssertEqual(fixture.searchRequests, [" Dm7 ", ""],
                "Retry must use its existing refresh callback without inventing a Search action")
            returnedField.resignFirstResponder()
            fixture.state = .loaded(fixture.summaries)
            try await assertResultsMode(true, in: mounted)
            XCTAssertEqual(fixture.summaries, original)
            XCTAssertTrue(fixture.openedPosts.isEmpty)
            XCTAssertEqual(fixture.publishCount, 0)
            attach(mounted, name: "Forum \(style.rawValue) submitted query survives return and retry")
            await mounted.close()
        }
    }

    func testUnavailableAccountStatesDoNotExposeSearchOrPublicationActions() async throws {
        for state in [IChartForumState.unconfigured, .signedOut, .requiresPro] {
            let fixture = Fixture(style: .simpleChordSheet)
            fixture.state = state
            let mounted = try await mount(fixture, width: 360, category: .large)
            XCTAssertNil(findSearchField(in: mounted.host.view))
            let nodes = try NativeAccessibilityLookup.nodes(in: mounted.host.view)
            XCTAssertFalse(nodes.contains { $0.isButton && $0.element.accessibilityLabel == "Search" })
            XCTAssertFalse(nodes.contains { $0.element.accessibilityLabel == helperText })
            XCTAssertTrue(fixture.searchRequests.isEmpty)
            XCTAssertEqual(fixture.publishCount, 0)
            await mounted.close()
        }
    }

    func testSearchLoadMoreIsReachableThenDisabledWhileLoadingAndRemovedWhenExhausted() async throws {
        for style in [ChartLayoutStyle.simpleChordSheet, .rhythmSectionSheet] {
            let fixture = Fixture(style: style)
            fixture.searchText = "fixture"
            fixture.submittedSearchText = "fixture"
            fixture.hasMoreSearchResults = true
            let mounted = try await mount(fixture, width: 360, category: .large)
            var activated = false
            try await inspectEveryScrollPosition(mounted) { nodes in
                guard !activated, let control = nodes.first(where: {
                    $0.isButton && $0.element.accessibilityLabel == "Load More"
                        && !$0.frame(in: mounted.window).intersection(mounted.viewport).isEmpty
                }) else { return }
                assertHorizontallyContained(control.frame(in: mounted.window), in: mounted.viewport)
                try activate(control)
                activated = true
            }
            XCTAssertTrue(activated)
            XCTAssertEqual(fixture.loadMoreRequests, 1)
            let loading = try await node("Loading More…", in: mounted, button: true)
            XCTAssertFalse(loading.isEnabled)
            XCTAssertEqual(fixture.submittedSearchText, "fixture")
            fixture.isLoadingMoreSearchResults = false
            fixture.hasMoreSearchResults = false
            try await settle(mounted.window)
            try await inspectEveryScrollPosition(mounted) { nodes in
                XCTAssertFalse(nodes.contains { $0.isButton && $0.element.accessibilityLabel == "Load More" })
            }
            XCTAssertEqual(fixture.loadMoreRequests, 1)
            await mounted.close()
        }
    }

    private func assertSameFocusedField(_ original: UITextField, frame: CGRect, in mounted: Mounted) async throws {
        let current = try await searchField(in: mounted)
        XCTAssertTrue(current === original, "Refresh must retain the actual editing control")
        XCTAssertTrue(current.isFirstResponder, "Refresh must not dismiss the keyboard or end editing")
        let currentFrame = current.convert(current.bounds, to: mounted.window)
        XCTAssertEqual(currentFrame.minX, frame.minX, accuracy: 1.5)
        XCTAssertEqual(currentFrame.minY, frame.minY, accuracy: 1.5)
        XCTAssertEqual(currentFrame.width, frame.width, accuracy: 1.5)
        XCTAssertEqual(currentFrame.height, frame.height, accuracy: 1.5)
    }

    private func assertResultsMode(_ isSearching: Bool, in mounted: Mounted) async throws {
        var labels = Set<String>()
        try await inspectEveryScrollPosition(mounted) { nodes in
            for value in nodes {
                if let label = value.element.accessibilityLabel { labels.insert(label) }
            }
        }
        XCTAssertEqual(labels.contains("Search Results"), isSearching,
            "The rendered results section must follow the submitted parent query")
        XCTAssertEqual(labels.contains("Ranked charts matching this search."), isSearching)
        XCTAssertEqual(labels.contains("The charts players are backing right now."), !isSearching)
        mounted.scroll.setContentOffset(.zero, animated: false)
        try await settle(mounted.window)
    }

    private func mount(_ fixture: Fixture, width: CGFloat, category: ContentSizeCategory) async throws -> Mounted {
        try await mountContent(AnyView(ForumContent(fixture: fixture)), width: width, category: category)
    }

    private func mountContent(_ content: AnyView, width: CGFloat, category: ContentSizeCategory) async throws -> Mounted {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first(where: \.isKeyWindow)
        let container = UIViewController()
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.overrideUserInterfaceStyle = .light
        window.rootViewController = container
        let host = UIHostingController(rootView: AnyView(ScrollView { content.padding(12) }
            .environment(\.sizeCategory, category).environment(\.accessibilityEnabled, true)))
        container.addChild(host)
        let actualWidth = min(width, window.bounds.width - 36)
        host.view.frame = CGRect(x: 18, y: 54, width: actualWidth,
            height: max(300, window.bounds.height - 108))
        container.view.addSubview(host.view)
        host.didMove(toParent: container)
        window.makeKeyAndVisible()
        try await wait(window) {
            window.isKeyWindow && host.view.window === window
                && !self.descendants(host.view).compactMap { $0 as? UIScrollView }.isEmpty
        }
        try await settle(window)
        let scroll = try XCTUnwrap(descendants(host.view).compactMap { $0 as? UIScrollView }
            .max { $0.bounds.height < $1.bounds.height })
        let mounted = Mounted(window: window, host: host, scroll: scroll, previousWindow: previous)
        addTeardownBlock { @MainActor in await mounted.close() }
        return mounted
    }

    private func searchField(in mounted: Mounted) async throws -> UITextField {
        try await wait(mounted.window) { self.findSearchField(in: mounted.host.view) != nil }
        return try XCTUnwrap(findSearchField(in: mounted.host.view))
    }

    private func findSearchField(in root: UIView) -> UITextField? {
        descendants(root).compactMap { $0 as? UITextField }.first {
            $0.accessibilityIdentifier == "forum.search" || $0.placeholder?.contains("Search songs") == true
        }
    }

    private func node(_ label: String, in mounted: Mounted, button: Bool = false) async throws -> NativeAccessibilityLookup.Node {
        try await wait(mounted.window) {
            try NativeAccessibilityLookup.matching(label, in: mounted.host.view, buttonsOnly: button).first != nil
        }
        return try XCTUnwrap(try NativeAccessibilityLookup.matching(label, in: mounted.host.view, buttonsOnly: button).first)
    }

    private func activate(_ node: NativeAccessibilityLookup.Node) throws {
        XCTAssertTrue(node.isEnabled)
        if let control = node.element as? UIButton { control.sendActions(for: .touchUpInside) }
        else { XCTAssertTrue(node.element.accessibilityActivate()) }
    }

    private func inspectEveryScrollPosition(_ mounted: Mounted,
        inspect: ([NativeAccessibilityLookup.Node]) throws -> Void) async throws {
        mounted.scroll.setContentOffset(.zero, animated: false)
        for _ in 0..<32 {
            try await settle(mounted.window)
            try inspect(try NativeAccessibilityLookup.nodes(in: mounted.host.view))
            let maximum = max(0, mounted.scroll.contentSize.height - mounted.scroll.bounds.height)
            let next = min(maximum, mounted.scroll.contentOffset.y + mounted.scroll.bounds.height * 0.55)
            if next <= mounted.scroll.contentOffset.y + 0.5 { return }
            mounted.scroll.setContentOffset(CGPoint(x: 0, y: next), animated: false)
        }
        XCTFail("The four-period fixture must remain navigable by ordinary scrolling")
    }

    private func wait(_ window: UIWindow, until condition: () throws -> Bool) async throws {
        for _ in 0..<40 {
            window.layoutIfNeeded()
            if try condition() { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(try condition(), "The mounted production forum view did not reach its expected state")
    }

    private func settle(_ window: UIWindow) async throws {
        for _ in 0..<5 {
            window.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private func assertContained(_ frame: CGRect, in viewport: CGRect,
        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(frame.isEmpty, file: file, line: line)
        XCTAssertTrue(viewport.insetBy(dx: -1, dy: -1).contains(frame), "Control must be fully readable inside the forum pane: \(frame)", file: file, line: line)
    }

    private func assertHorizontallyContained(_ frame: CGRect, in viewport: CGRect,
        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThanOrEqual(frame.minX, viewport.minX - 1, file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxX, viewport.maxX + 1, file: file, line: line)
    }

    private func descendants(_ root: UIView) -> [UIView] { [root] + root.subviews.flatMap(descendants) }

    private func attach(_ mounted: Mounted, name: String) {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let screenshot = UIGraphicsImageRenderer(size: mounted.window.bounds.size, format: format).image { _ in
            mounted.window.drawHierarchy(in: mounted.window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private final class Mounted {
        let window: UIWindow
        let host: UIHostingController<AnyView>
        let scroll: UIScrollView
        let previousWindow: UIWindow?
        private var closed = false
        var viewport: CGRect { host.view.convert(host.view.bounds, to: window) }
        init(window: UIWindow, host: UIHostingController<AnyView>, scroll: UIScrollView, previousWindow: UIWindow?) {
            self.window = window; self.host = host; self.scroll = scroll; self.previousWindow = previousWindow
        }
        func close() async {
            guard !closed else { return }; closed = true
            window.endEditing(true)
            try? await Task.sleep(nanoseconds: 50_000_000)
            host.willMove(toParent: nil)
            host.view.removeFromSuperview()
            host.removeFromParent()
            window.isHidden = true
            window.rootViewController = nil
            previousWindow?.makeKey()
        }
    }

    @MainActor
    private final class Fixture: ObservableObject {
        @Published var state: IChartForumState
        @Published var searchText = ""
        @Published var submittedSearchText = ""
        @Published var forumGeneration = 0
        @Published var hasMoreSearchResults = false
        @Published var isLoadingMoreSearchResults = false
        let summaries: [IChartForumSongSummary]
        var searchRequests: [String] = []
        var refreshQueries: [String] = []
        var retryCount = 0
        var publishCount = 0
        var openedPosts: [UUID] = []
        var loadMoreRequests = 0
        init(style: ChartLayoutStyle) {
            let owner = UUID()
            summaries = (0..<2).map { index in
                let song = ForumSong(id: UUID(), songTitle: "Readable forum tune \(index + 1)", artistName: "Fixture ensemble")
                let post = ForumChartPost(id: UUID(), songID: song.id, ownerID: owner,
                    chartTitle: "Readable \(style.displayText) \(index + 1)", arrangerCredit: "Fixture arranger",
                    creatorDisplayName: "Fixture A.", tags: ["fixture"], versionNote: nil, layoutStyle: style,
                    pdfStoragePath: "fixture.pdf", status: .published, voteUpCount: 4 - index,
                    voteDownCount: 0, reportCount: 0, rankingScore: Double(4 - index), publishedAt: .now)
                return IChartForumSongSummary(song: song, topPosts: [post],
                    authorBadgesByOwner: [owner: [.verifiedContributor, .trustedArranger]])
            }
            state = .loaded(summaries)
        }
        func search(_ query: String) { searchRequests.append(query); request(query) }
        func retry() { retryCount += 1; request(searchText) }
        func recreateForum() { forumGeneration += 1; request(searchText) }
        func loadMore() { loadMoreRequests += 1; isLoadingMoreSearchResults = true }
        private func request(_ query: String) {
            submittedSearchText = query.trimmingCharacters(in: .whitespacesAndNewlines)
            refreshQueries.append(query)
            state = .loading
        }
    }

    private struct ForumContent: View {
        @ObservedObject var fixture: Fixture
        var body: some View {
            IChartForumHomeView(state: fixture.state, searchText: $fixture.searchText,
                submittedSearchText: $fixture.submittedSearchText, charts: [],
                currentUserID: nil, currentUserBadges: [], uploadQueue: [], statusMessage: nil,
                errorMessage: nil, theme: IChartHomeTheme(mode: .light), onSearch: fixture.search,
                onRefresh: fixture.retry, onPublishChart: { _ in fixture.publishCount += 1 },
                onRetryUpload: { _ in }, onWithdrawUpload: { _ in }, onDismissUpload: { _ in },
                onOpenPost: { _, post in fixture.openedPosts.append(post.id) },
                hasMoreSearchResults: fixture.hasMoreSearchResults,
                isLoadingMoreSearchResults: fixture.isLoadingMoreSearchResults,
                onLoadMoreSearchResults: fixture.loadMore)
                .id(fixture.forumGeneration)
        }
    }
}
#endif
