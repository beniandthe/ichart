import XCTest
@testable import iChart

final class ChartLibraryStoreTests: XCTestCase {
    private enum RecordingRepositoryError: LocalizedError {
        case load
        case save

        var errorDescription: String? {
            switch self {
            case .load:
                "Could not read saved library."
            case .save:
                "Could not write saved library."
            }
        }
    }

    private final class RecordingChartRepository: ChartRepository {
        var savesSnapshotsOffMainThread = false
        var snapshotToLoad: ChartLibrarySnapshot?
        var loadError: Error?
        var saveError: Error?
        private(set) var savedSnapshots: [ChartLibrarySnapshot] = []

        func loadSnapshot() throws -> ChartLibrarySnapshot? {
            if let loadError {
                throw loadError
            }
            return snapshotToLoad
        }

        func saveSnapshot(_ snapshot: ChartLibrarySnapshot) throws {
            if let saveError {
                throw saveError
            }
            savedSnapshots.append(snapshot)
        }
    }

    private final class BlockingAsyncChartRepository: ChartRepository {
        var savesSnapshotsOffMainThread = true
        var onSaveStarted: (() -> Void)?
        var onSaveFinished: (() -> Void)?
        private let releaseSave = DispatchSemaphore(value: 0)
        private let stateLock = NSLock()
        private var savedSnapshotsStorage: [ChartLibrarySnapshot] = []
        private var saveStartedCountStorage = 0

        var savedSnapshots: [ChartLibrarySnapshot] {
            stateLock.lock()
            defer { stateLock.unlock() }
            return savedSnapshotsStorage
        }

        var saveStartedCount: Int {
            stateLock.lock()
            defer { stateLock.unlock() }
            return saveStartedCountStorage
        }

        func loadSnapshot() throws -> ChartLibrarySnapshot? {
            nil
        }

        func saveSnapshot(_ snapshot: ChartLibrarySnapshot) throws {
            stateLock.lock()
            saveStartedCountStorage += 1
            stateLock.unlock()
            onSaveStarted?()
            releaseSave.wait()
            stateLock.lock()
            savedSnapshotsStorage.append(snapshot)
            stateLock.unlock()
            onSaveFinished?()
        }

        func unblockSave() {
            releaseSave.signal()
        }
    }

    private func waitUntil(
        _ condition: @autoclosure () -> Bool,
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }

        XCTAssertTrue(condition(), "Timed out waiting for condition", file: file, line: line)
    }

    func testBasicAccountPreventsCreatingPastTheChartLimit() {
        let charts = (1...AppEntitlements.recommendedFreeChartLimit).map {
            Chart.blank(title: "Chart \($0)")
        }
        let store = ChartLibraryStore(charts: charts, entitlements: .free)

        let didCreateChart = store.createBlankChart()

        XCTAssertFalse(didCreateChart)
        XCTAssertEqual(store.charts.count, AppEntitlements.recommendedFreeChartLimit)
    }

    func testLegacyLocalProAllowsCreatingMoreCharts() {
        let charts = (1...AppEntitlements.recommendedFreeChartLimit).map {
            Chart.blank(title: "Chart \($0)")
        }
        let store = ChartLibraryStore(
            charts: charts,
            entitlements: AppEntitlements(activePlan: .proLifetime)
        )

        let didCreateChart = store.createBlankChart(in: .bFlatMajor)

        XCTAssertTrue(didCreateChart)
        XCTAssertEqual(store.charts.count, AppEntitlements.recommendedFreeChartLimit + 1)
        XCTAssertEqual(store.charts.first?.documentKey, .bFlatMajor)
    }

    func testSetPlanUpdatesActiveEntitlements() {
        let store = ChartLibraryStore(charts: ChartSamples.previewCharts, entitlements: .free)

        store.setPlan(.studioSubscription)

        XCTAssertEqual(store.entitlements.activePlan, .studioSubscription)
        XCTAssertEqual(store.entitlements.subscription.status, .proActive)
        XCTAssertTrue(store.canUse(.cloudBackup))
    }

    func testApplySubscriptionStatePersistsEntitlementsSnapshot() {
        let repository = RecordingChartRepository()
        let store = ChartLibraryStore(
            charts: ChartSamples.previewCharts,
            repository: repository
        )

        store.applySubscriptionState(.activePro(verifiedAt: Date(timeIntervalSinceReferenceDate: 42)))

        XCTAssertEqual(store.entitlements.activePlan, .studioSubscription)
        XCTAssertEqual(store.entitlements.subscription.status, .proActive)
        XCTAssertTrue(store.canUse(.cloudBackup))
        XCTAssertEqual(repository.savedSnapshots.last?.entitlements.subscription.status, .proActive)
    }

    func testExpiredSubscriptionRequiresBasicChartPruningWithoutCloudAccess() {
        let charts = (1...4).map {
            Chart.blank(title: "Chart \($0)")
        }
        let store = ChartLibraryStore(
            charts: charts,
            entitlements: AppEntitlements(subscription: .activePro())
        )

        store.applySubscriptionState(.proExpired(verifiedAt: Date(timeIntervalSinceReferenceDate: 42)))

        XCTAssertEqual(store.entitlements.activePlan, .free)
        XCTAssertEqual(store.localChartLimit, 3)
        XCTAssertEqual(store.localChartOverflowCount, 1)
        XCTAssertTrue(store.requiresLocalChartPruningForCurrentPlan)
        XCTAssertTrue(store.isChartEditingLockedByCurrentPlan)
        XCTAssertFalse(store.canOpenChartsForEditing)
        XCTAssertFalse(store.canUse(.cloudBackup))
        XCTAssertFalse(store.canUse(.forums))
    }

    func testChartEditingUnlocksAfterExpiredOverCapLibraryIsPrunedToBasicLimit() {
        let charts = (1...4).map {
            Chart.blank(title: "Chart \($0)")
        }
        let store = ChartLibraryStore(
            charts: charts,
            entitlements: AppEntitlements(subscription: .proExpired())
        )

        XCTAssertTrue(store.isChartEditingLockedByCurrentPlan)
        XCTAssertFalse(store.canOpenChartsForEditing)

        XCTAssertTrue(store.pruneLocalChartForCurrentPlan(id: charts[3].id))

        XCTAssertFalse(store.requiresLocalChartPruningForCurrentPlan)
        XCTAssertFalse(store.isChartEditingLockedByCurrentPlan)
        XCTAssertTrue(store.canOpenChartsForEditing)
        XCTAssertEqual(store.charts.count, AppEntitlements.recommendedBasicChartLimit)
    }

    func testBasicLibraryAtChartLimitCanStillOpenChartsForEditing() {
        let charts = (1...AppEntitlements.recommendedBasicChartLimit).map {
            Chart.blank(title: "Chart \($0)")
        }
        let store = ChartLibraryStore(charts: charts, entitlements: .free)

        XCTAssertFalse(store.requiresLocalChartPruningForCurrentPlan)
        XCTAssertFalse(store.isChartEditingLockedByCurrentPlan)
        XCTAssertTrue(store.canOpenChartsForEditing)
        XCTAssertFalse(store.canCreateChart)
    }

    func testProjectsRequireActiveProSubscription() {
        let store = ChartLibraryStore(charts: ChartSamples.previewCharts, entitlements: .free)

        XCTAssertNil(store.createProject(title: "Song Folder"))

        store.applySubscriptionState(.activePro(verifiedAt: Date(timeIntervalSinceReferenceDate: 42)))
        let projectID = store.createProject(title: "Song Folder")

        XCTAssertNotNil(projectID)
        XCTAssertEqual(store.projects.first?.title, "Song Folder")
    }

    func testProjectCanAddExistingChartAndCreateNewChartInsideProject() throws {
        let sourceChart = Chart.blank(title: "Song", key: .cMajor)
        let store = ChartLibraryStore(
            charts: [sourceChart],
            entitlements: AppEntitlements(subscription: .activePro())
        )
        let projectID = try XCTUnwrap(store.createProject(title: "Song"))

        XCTAssertTrue(store.addChartToProject(chartID: sourceChart.id, projectID: projectID))
        XCTAssertTrue(store.createBlankChart(in: .bFlatMajor, layoutStyle: .rhythmSectionSheet, projectID: projectID))

        let project = try XCTUnwrap(store.projects.first)
        XCTAssertEqual(project.chartIDs.count, 2)
        XCTAssertTrue(project.chartIDs.contains(sourceChart.id))
        XCTAssertEqual(store.charts(in: project).first?.documentKey, .bFlatMajor)
    }

    func testProjectDuplicateVariantCanChangeTitleAndInstrumentTransposition() throws {
        let sourceChart = Chart.blank(title: "Song Rhythm", key: .cMajor)
        let store = ChartLibraryStore(
            charts: [sourceChart],
            entitlements: AppEntitlements(subscription: .activePro())
        )
        let projectID = try XCTUnwrap(store.createProject(title: "Song", chartIDs: [sourceChart.id]))

        let duplicateID = try XCTUnwrap(
            store.duplicateChart(
                id: sourceChart.id,
                title: "Song Horns",
                transpositionView: .bb,
                projectID: projectID
            )
        )

        let duplicate = try XCTUnwrap(store.charts.first { $0.id == duplicateID })
        XCTAssertEqual(duplicate.title, "Song Horns")
        XCTAssertEqual(duplicate.documentKey, .cMajor)
        XCTAssertEqual(duplicate.defaultTranspositionView, .bb)
        XCTAssertEqual(duplicate.chordTranspositionSemitones, 0)
        XCTAssertEqual(store.projects.first?.chartIDs, [sourceChart.id, duplicateID])
    }

    func testDeletingChartRemovesItFromProjects() throws {
        let sourceChart = Chart.blank(title: "Song", key: .cMajor)
        let store = ChartLibraryStore(
            charts: [sourceChart],
            entitlements: AppEntitlements(subscription: .activePro())
        )
        let projectID = try XCTUnwrap(store.createProject(title: "Song", chartIDs: [sourceChart.id]))

        XCTAssertTrue(store.deleteChart(id: sourceChart.id))

        XCTAssertEqual(store.projects.first { $0.id == projectID }?.chartIDs, [])
    }

    func testCreateBlankChartPersistsUpdatedSnapshot() {
        let repository = RecordingChartRepository()
        let store = ChartLibraryStore(
            charts: ChartSamples.previewCharts,
            repository: repository
        )

        let didCreateChart = store.createBlankChart(in: .gMajor)

        XCTAssertTrue(didCreateChart)
        XCTAssertEqual(repository.savedSnapshots.last?.charts.first?.documentKey, .gMajor)
        XCTAssertEqual(repository.savedSnapshots.last?.selectedChartID, store.selectedChartID)
    }

    func testRepositoryBackedStoreStartsWithAutosaveReadyStatus() {
        let repository = RecordingChartRepository()
        let store = ChartLibraryStore(charts: [], repository: repository)

        XCTAssertEqual(store.persistenceStatus, .ready)
    }

    func testSuccessfulMutationMarksPersistenceStatusSaved() {
        let repository = RecordingChartRepository()
        let store = ChartLibraryStore(charts: [], repository: repository)

        XCTAssertTrue(store.createBlankChart(layoutStyle: .simpleChordSheet))

        guard case .saved(let savedAt) = store.persistenceStatus else {
            return XCTFail("Expected saved persistence status, got \(store.persistenceStatus)")
        }
        XCTAssertLessThan(Date().timeIntervalSince(savedAt), 5)
        XCTAssertEqual(repository.savedSnapshots.last?.selectedChartID, store.selectedChartID)
    }

    func testAsyncRepositoryDoesNotBlockChartCreation() {
        let repository = BlockingAsyncChartRepository()
        let store = ChartLibraryStore(charts: [], repository: repository)
        let asyncPersistenceTimeout: TimeInterval = 30
        let start = Date()

        XCTAssertTrue(store.createBlankChart(layoutStyle: .simpleChordSheet))

        XCTAssertLessThan(Date().timeIntervalSince(start), 0.2)
        XCTAssertEqual(store.charts.count, 1)
        XCTAssertEqual(store.selectedChartID, store.charts.first?.id)
        waitUntil(repository.saveStartedCount == 1, timeout: asyncPersistenceTimeout)
        XCTAssertTrue(repository.savedSnapshots.isEmpty)

        repository.unblockSave()
        waitUntil(repository.savedSnapshots.count == 1, timeout: asyncPersistenceTimeout)
        XCTAssertEqual(repository.savedSnapshots.last?.selectedChartID, store.selectedChartID)
    }

    func testAsyncRepositoryPersistsLatestSnapshotAfterBlockedSave() {
        let repository = BlockingAsyncChartRepository()
        let store = ChartLibraryStore(charts: [], repository: repository)
        let asyncPersistenceTimeout: TimeInterval = 30

        XCTAssertTrue(store.createBlankChart(layoutStyle: .simpleChordSheet))
        waitUntil(repository.saveStartedCount == 1, timeout: asyncPersistenceTimeout)
        XCTAssertTrue(store.createBlankChart(layoutStyle: .rhythmSectionSheet))
        let expectedSelectedChartID = store.selectedChartID

        repository.unblockSave()
        waitUntil(repository.saveStartedCount == 2, timeout: asyncPersistenceTimeout)
        repository.unblockSave()
        waitUntil(repository.savedSnapshots.count == 2, timeout: asyncPersistenceTimeout)

        XCTAssertEqual(repository.savedSnapshots.last?.charts.count, 2)
        XCTAssertEqual(repository.savedSnapshots.last?.selectedChartID, expectedSelectedChartID)
    }

    func testFailedSaveReportsPersistenceIssueWithoutDroppingInMemoryMutation() {
        let repository = RecordingChartRepository()
        repository.saveError = RecordingRepositoryError.save
        let store = ChartLibraryStore(charts: [], repository: repository)

        XCTAssertTrue(store.createBlankChart(layoutStyle: .rhythmSectionSheet))

        XCTAssertEqual(store.charts.count, 1)
        XCTAssertEqual(store.selectedChartID, store.charts.first?.id)
        XCTAssertTrue(repository.savedSnapshots.isEmpty)
        guard case .failed(let message) = store.persistenceStatus else {
            return XCTFail("Expected failed persistence status, got \(store.persistenceStatus)")
        }
        XCTAssertTrue(message.contains("Could not write saved library"))
    }

    func testLiveStoreMarksLoadedSnapshotAsSaved() {
        let chart = Chart.blank(title: "Saved Chart")
        let tombstone = ChartDeletionTombstone(chartID: UUID(), deletedAt: Date(timeIntervalSince1970: 100))
        let cloudMetadata = ChartCloudMetadata(
            lastSyncAt: Date(timeIntervalSince1970: 200),
            lastRemoteBackupAt: Date(timeIntervalSince1970: 300)
        )
        let snapshot = ChartLibrarySnapshot(
            charts: [chart],
            selectedChartID: chart.id,
            entitlements: AppEntitlements(activePlan: .proLifetime),
            deletionTombstones: [tombstone],
            cloudMetadata: cloudMetadata
        )
        let repository = RecordingChartRepository()
        repository.snapshotToLoad = snapshot

        let store = ChartLibraryStore.live(repository: repository)

        XCTAssertEqual(store.snapshot, snapshot)
        guard case .saved = store.persistenceStatus else {
            return XCTFail("Expected loaded live store to be marked saved, got \(store.persistenceStatus)")
        }
    }

    func testLiveStoreStartsEmptyWhenNoSavedSnapshotExists() {
        let repository = RecordingChartRepository()

        let store = ChartLibraryStore.live(repository: repository)

        XCTAssertTrue(store.charts.isEmpty)
        XCTAssertNil(store.selectedChartID)
        XCTAssertEqual(store.entitlements, .free)
        XCTAssertTrue(store.deletionTombstones.isEmpty)
        XCTAssertNil(store.cloudMetadata.ownerID)
        XCTAssertNil(store.cloudMetadata.lastSyncAt)
        XCTAssertNil(store.cloudMetadata.lastRemoteBackupAt)
        XCTAssertTrue(repository.savedSnapshots.isEmpty)
        XCTAssertEqual(store.persistenceStatus, .ready)
    }

    func testLiveStoreReportsLoadFailureWithoutPersistingPreviewFallback() {
        let repository = RecordingChartRepository()
        repository.loadError = RecordingRepositoryError.load

        let store = ChartLibraryStore.live(repository: repository)

        XCTAssertFalse(store.charts.isEmpty)
        XCTAssertTrue(repository.savedSnapshots.isEmpty)
        guard case .failed(let message) = store.persistenceStatus else {
            return XCTFail("Expected load failure status, got \(store.persistenceStatus)")
        }
        XCTAssertTrue(message.contains("Could not read saved library"))
    }

    func testMutatingChartElementPersistsEditedChartSnapshot() throws {
        let repository = RecordingChartRepository()
        let chart = Chart.blank(title: "Editor Binding", measureCount: 2, layoutStyle: .rhythmSectionSheet)
        let store = ChartLibraryStore(
            charts: [chart],
            selectedChartID: chart.id,
            repository: repository
        )
        let committedMeasureID = try XCTUnwrap(store.charts.first?.measures.first?.id)
        let unresolvedMeasureID = try XCTUnwrap(store.charts.first?.measures.dropFirst().first?.id)
        let pendingChordInk = Data("pending-editor-chord-ink".utf8)
        let committedRhythmInk = Data("committed-editor-rhythm-ink".utf8)
        let unresolvedRhythmInk = Data("unresolved-editor-rhythm-ink".utf8)
        let committedChordInk = Data("committed-editor-G-slash-B".utf8)

        store.charts[0].setPageHandwrittenChordDrawing(pendingChordInk)
        store.charts[0].setMeasureRhythmMap(
            [.quarter, .quarter, .quarter, .quarter],
            drawingData: committedRhythmInk,
            for: committedMeasureID
        )
        store.charts[0].setMeasureHandwrittenRhythmicNotationDrawing(
            unresolvedRhythmInk,
            for: unresolvedMeasureID
        )
        store.charts[0].appendRecognizedChord(
            try ChordSymbolParser.parse("G/B"),
            rawInput: "G/B",
            to: committedMeasureID,
            atFraction: 0.05,
            sourceInkData: committedChordInk,
            sourceCandidateSignature: ["G/B"]
        )

        let savedChart = try XCTUnwrap(repository.savedSnapshots.last?.charts.first)
        XCTAssertEqual(savedChart.id, chart.id)
        XCTAssertEqual(savedChart.pageHandwrittenChordData, pendingChordInk)
        XCTAssertEqual(
            savedChart.measure(id: committedMeasureID)?.rhythmMap?.values,
            [.quarter, .quarter, .quarter, .quarter]
        )
        XCTAssertEqual(savedChart.measure(id: committedMeasureID)?.rhythmMap?.drawingData, committedRhythmInk)
        XCTAssertEqual(
            savedChart.measure(id: unresolvedMeasureID)?.handwrittenRhythmicNotationData,
            unresolvedRhythmInk
        )
        XCTAssertNil(savedChart.measure(id: unresolvedMeasureID)?.rhythmMap)
        XCTAssertEqual(savedChart.measure(id: committedMeasureID)?.chordEvents.first?.rawInput, "G/B")
        XCTAssertEqual(savedChart.measure(id: committedMeasureID)?.chordEvents.first?.sourceInkData, committedChordInk)
        XCTAssertEqual(savedChart.measure(id: committedMeasureID)?.chordEvents.first?.sourceCandidateSignature, ["G/B"])
        XCTAssertEqual(repository.savedSnapshots.last?.selectedChartID, chart.id)
    }

    func testCreateBlankChartCreatesUnconfiguredDraftPage() {
        let store = ChartLibraryStore(charts: ChartSamples.previewCharts)

        let didCreateChart = store.createBlankChart()

        XCTAssertTrue(didCreateChart)
        XCTAssertEqual(store.charts.first?.measures.count, 0)
        XCTAssertEqual(store.charts.first?.systems.count, 0)
        XCTAssertEqual(store.charts.first?.hasCompletedInitialSetup, false)
    }

    func testCreateBlankChartUsesSelectedLayoutStyle() {
        let store = ChartLibraryStore(charts: ChartSamples.previewCharts)

        let didCreateChart = store.createBlankChart(layoutStyle: .rhythmSectionSheet)

        XCTAssertTrue(didCreateChart)
        XCTAssertEqual(store.charts.first?.layoutStyle, .rhythmSectionSheet)
        XCTAssertEqual(store.charts.first?.engravingPreset, .wide)
        XCTAssertEqual(store.charts.first?.stylePreset, .gigSheet)
    }

    func testRenameChartTrimsTitleAndPersistsSelection() throws {
        let repository = RecordingChartRepository()
        let chart = Chart.blank(title: "Original Title", measureCount: 4, layoutStyle: .simpleChordSheet)
        let store = ChartLibraryStore(
            charts: [chart],
            selectedChartID: chart.id,
            repository: repository
        )

        let didRename = store.renameChart(id: chart.id, to: "  New Title  ")

        XCTAssertTrue(didRename)
        XCTAssertEqual(store.charts.first?.title, "New Title")
        XCTAssertEqual(store.selectedChartID, chart.id)
        let savedSnapshot = try XCTUnwrap(repository.savedSnapshots.last)
        XCTAssertEqual(savedSnapshot.charts.first?.title, "New Title")
        XCTAssertEqual(savedSnapshot.selectedChartID, chart.id)
    }

    func testRenameChartRejectsEmptyTitle() {
        let repository = RecordingChartRepository()
        let chart = Chart.blank(title: "Original Title")
        let store = ChartLibraryStore(
            charts: [chart],
            selectedChartID: chart.id,
            repository: repository
        )

        let didRename = store.renameChart(id: chart.id, to: "   ")

        XCTAssertFalse(didRename)
        XCTAssertEqual(store.charts.first?.title, "Original Title")
        XCTAssertTrue(repository.savedSnapshots.isEmpty)
    }

    func testDuplicateChartCopiesContentWithFreshChartIdentityAndSelection() throws {
        let repository = RecordingChartRepository()
        var sourceChart = Chart.blank(
            title: "Gig Chart",
            measureCount: 2,
            layoutStyle: .rhythmSectionSheet
        )
        sourceChart.styleNote = "Medium Swing"
        sourceChart.chordTranspositionSemitones = 5
        let store = ChartLibraryStore(
            charts: [sourceChart],
            selectedChartID: sourceChart.id,
            repository: repository
        )

        let duplicateID = try XCTUnwrap(store.duplicateChart(id: sourceChart.id))
        let duplicate = try XCTUnwrap(store.charts.first { $0.id == duplicateID })

        XCTAssertNotEqual(duplicate.id, sourceChart.id)
        XCTAssertEqual(duplicate.title, "Gig Chart Copy")
        XCTAssertEqual(duplicate.layoutStyle, sourceChart.layoutStyle)
        XCTAssertEqual(duplicate.styleNote, sourceChart.styleNote)
        XCTAssertEqual(duplicate.chordTranspositionSemitones, sourceChart.chordTranspositionSemitones)
        XCTAssertEqual(duplicate.systems, sourceChart.systems)
        XCTAssertEqual(store.selectedChartID, duplicateID)
        let savedSnapshot = try XCTUnwrap(repository.savedSnapshots.last)
        XCTAssertEqual(savedSnapshot.selectedChartID, duplicateID)
        XCTAssertTrue(savedSnapshot.charts.contains { $0.id == sourceChart.id })
        XCTAssertTrue(savedSnapshot.charts.contains { $0.id == duplicateID })
    }

    func testDuplicateChartUsesNumberedCopyTitleWhenCopyAlreadyExists() throws {
        let sourceChart = Chart.blank(title: "Gig Chart")
        let firstCopy = Chart.blank(title: "Gig Chart Copy")
        let store = ChartLibraryStore(charts: [sourceChart, firstCopy])

        let duplicateID = try XCTUnwrap(store.duplicateChart(id: sourceChart.id))
        let duplicate = try XCTUnwrap(store.charts.first { $0.id == duplicateID })

        XCTAssertEqual(duplicate.title, "Gig Chart Copy 2")
    }

    func testDuplicateChartRespectsBasicAccountLimit() {
        let charts = (1...AppEntitlements.recommendedFreeChartLimit).map {
            Chart.blank(title: "Chart \($0)")
        }
        let store = ChartLibraryStore(charts: charts, entitlements: .free)

        let duplicateID = store.duplicateChart(id: charts[0].id)

        XCTAssertNil(duplicateID)
        XCTAssertEqual(store.charts.count, AppEntitlements.recommendedFreeChartLimit)
    }

    func testDeleteSelectedChartSelectsNeighborAndPersistsWithoutStaleSelection() throws {
        let repository = RecordingChartRepository()
        let charts = [
            Chart.blank(title: "First"),
            Chart.blank(title: "Second"),
            Chart.blank(title: "Third")
        ]
        let store = ChartLibraryStore(
            charts: charts,
            selectedChartID: charts[1].id,
            repository: repository
        )

        let didDelete = store.deleteChart(id: charts[1].id)

        XCTAssertTrue(didDelete)
        XCTAssertEqual(store.charts.map(\.id), [charts[0].id, charts[2].id])
        XCTAssertEqual(store.selectedChartID, charts[2].id)
        let savedSnapshot = try XCTUnwrap(repository.savedSnapshots.last)
        XCTAssertEqual(savedSnapshot.charts.map(\.id), [charts[0].id, charts[2].id])
        XCTAssertEqual(savedSnapshot.selectedChartID, charts[2].id)
        XCTAssertTrue(repository.savedSnapshots.allSatisfy { snapshot in
            snapshot.selectedChartID.map { selectedID in
                snapshot.charts.contains { $0.id == selectedID }
            } ?? true
        })
    }

    func testDeleteNonSelectedChartKeepsValidSelection() throws {
        let repository = RecordingChartRepository()
        let charts = [
            Chart.blank(title: "First"),
            Chart.blank(title: "Second")
        ]
        let store = ChartLibraryStore(
            charts: charts,
            selectedChartID: charts[1].id,
            repository: repository
        )

        let didDelete = store.deleteChart(id: charts[0].id)

        XCTAssertTrue(didDelete)
        XCTAssertEqual(store.charts.map(\.id), [charts[1].id])
        XCTAssertEqual(store.selectedChartID, charts[1].id)
        XCTAssertEqual(repository.savedSnapshots.last?.selectedChartID, charts[1].id)
    }

    func testDeleteLastChartClearsSelection() throws {
        let repository = RecordingChartRepository()
        let chart = Chart.blank(title: "Only Chart")
        let store = ChartLibraryStore(
            charts: [chart],
            selectedChartID: chart.id,
            repository: repository
        )

        let didDelete = store.deleteChart(id: chart.id)

        XCTAssertTrue(didDelete)
        XCTAssertTrue(store.charts.isEmpty)
        XCTAssertNil(store.selectedChartID)
        let savedSnapshot = try XCTUnwrap(repository.savedSnapshots.last)
        XCTAssertTrue(savedSnapshot.charts.isEmpty)
        XCTAssertNil(savedSnapshot.selectedChartID)
    }

    func testDeleteChartCreatesLocalTombstoneForCloudSync() throws {
        let repository = RecordingChartRepository()
        let chart = Chart.blank(title: "Cloud Delete")
        let store = ChartLibraryStore(
            charts: [chart],
            selectedChartID: chart.id,
            repository: repository
        )

        XCTAssertTrue(store.deleteChart(id: chart.id))

        let tombstone = try XCTUnwrap(store.deletionTombstones.first)
        XCTAssertEqual(tombstone.chartID, chart.id)
        let savedTombstone = try XCTUnwrap(repository.savedSnapshots.last?.deletionTombstones.first)
        XCTAssertEqual(savedTombstone.chartID, chart.id)
    }

    func testDowngradePruneRemovesSelectedLocalChartWithoutCloudTombstoneOrUpload() throws {
        let repository = RecordingChartRepository()
        let charts = (1...4).map {
            Chart.blank(title: "Chart \($0)")
        }
        let store = ChartLibraryStore(
            charts: charts,
            entitlements: .free,
            selectedChartID: charts[3].id,
            repository: repository
        )
        var scheduledUploadCount = 0
        store.onSnapshotSaved = { (_: ChartLibrarySnapshot) in
            scheduledUploadCount += 1
        }

        XCTAssertTrue(store.requiresLocalChartPruningForCurrentPlan)
        XCTAssertEqual(store.localChartOverflowCount, 1)

        let didPrune = store.pruneLocalChartForCurrentPlan(id: charts[3].id)

        XCTAssertTrue(didPrune)
        XCTAssertEqual(store.charts.map { $0.id }, [charts[0].id, charts[1].id, charts[2].id])
        XCTAssertEqual(store.selectedChartID, charts[0].id)
        XCTAssertFalse(store.requiresLocalChartPruningForCurrentPlan)
        XCTAssertTrue(store.deletionTombstones.isEmpty)
        XCTAssertEqual(repository.savedSnapshots.last?.charts.map { $0.id }, [charts[0].id, charts[1].id, charts[2].id])
        XCTAssertTrue(repository.savedSnapshots.last?.deletionTombstones.isEmpty ?? false)
        XCTAssertEqual(scheduledUploadCount, 0)
    }

    func testDowngradePruneIsUnavailableWhenLibraryIsAtBasicCap() {
        let charts = (1...AppEntitlements.recommendedBasicChartLimit).map {
            Chart.blank(title: "Chart \($0)")
        }
        let store = ChartLibraryStore(charts: charts, entitlements: .free)

        XCTAssertFalse(store.pruneLocalChartForCurrentPlan(id: charts[0].id))
        XCTAssertEqual(store.charts.map(\.id), charts.map(\.id))
        XCTAssertTrue(store.deletionTombstones.isEmpty)
    }

    func testSyncedSnapshotAppliesQuietlyWithoutSchedulingUpload() {
        let repository = RecordingChartRepository()
        let store = ChartLibraryStore(charts: [], repository: repository)
        var scheduledUploadCount = 0
        store.onSnapshotSaved = { _ in
            scheduledUploadCount += 1
        }
        let chart = Chart.blank(title: "Remote Chart")
        let snapshot = ChartLibrarySnapshot(
            charts: [chart],
            selectedChartID: chart.id,
            entitlements: .free,
            cloudMetadata: ChartCloudMetadata(lastSyncAt: Date(), lastRemoteBackupAt: Date())
        )

        store.applySyncedSnapshot(snapshot)

        XCTAssertEqual(store.charts.map(\.id), [chart.id])
        XCTAssertEqual(repository.savedSnapshots.last?.charts.map(\.id), [chart.id])
        XCTAssertEqual(scheduledUploadCount, 0)
    }

    func testCloudMetadataSyncUpdatePersistsOwnerWithoutSchedulingUpload() throws {
        let repository = RecordingChartRepository()
        let store = ChartLibraryStore(charts: [], repository: repository)
        var scheduledUploadCount = 0
        store.onSnapshotSaved = { _ in
            scheduledUploadCount += 1
        }
        let ownerID = UUID(uuidString: "00000000-0000-0000-0000-000000000301")!
        let syncDate = Date(timeIntervalSinceReferenceDate: 8_000)
        let backupDate = Date(timeIntervalSinceReferenceDate: 8_100)

        store.updateCloudMetadataFromSync(
            ownerID: ownerID,
            lastSyncAt: syncDate,
            lastRemoteBackupAt: backupDate
        )

        let savedSnapshot = try XCTUnwrap(repository.savedSnapshots.last)
        XCTAssertEqual(savedSnapshot.cloudMetadata.ownerID, ownerID)
        XCTAssertEqual(savedSnapshot.cloudMetadata.lastSyncAt, syncDate)
        XCTAssertEqual(savedSnapshot.cloudMetadata.lastRemoteBackupAt, backupDate)
        XCTAssertEqual(scheduledUploadCount, 0)
    }

    func testV1NewChartOptionsExposeOnlyActiveReleaseStyles() {
        XCTAssertEqual(ChartLayoutStyle.v1NewChartOptions, [.simpleChordSheet, .rhythmSectionSheet])
        XCTAssertTrue(ChartLayoutStyle.allCases.contains(.leadSheet))
        XCTAssertFalse(ChartLayoutStyle.v1NewChartOptions.contains(.leadSheet))
    }

    func testLibrarySummaryUsesInstrumentTranspositionInsteadOfDocumentKey() {
        var simpleChart = Chart.blank(
            title: "Simple",
            key: .bFlatMajor,
            measureCount: 4,
            layoutStyle: .simpleChordSheet
        )
        simpleChart.defaultMeter = Meter(numerator: 3, denominator: 4)
        var rhythmChart = Chart.blank(
            title: "Rhythm",
            key: .eFlatMajor,
            measureCount: 8,
            layoutStyle: .rhythmSectionSheet
        )
        rhythmChart.defaultMeter = Meter(numerator: 6, denominator: 8)
        let leadChart = Chart.blank(
            title: "Lead",
            key: .bFlatMajor,
            measureCount: 4,
            layoutStyle: .leadSheet
        )

        rhythmChart.setInstrumentTranspositionView(.bb)

        XCTAssertEqual(simpleChart.librarySummaryText, "Simple Chord Sheet · Concert · 3/4 · 4 measures")
        XCTAssertEqual(rhythmChart.librarySummaryText, "Rhythm Section Sheet · Bb Horn · 6/8 · 8 measures")
        XCTAssertEqual(leadChart.librarySummaryText, "Lead Sheet · Concert · 4/4 · 4 measures")
    }

    func testLibrarySummaryUsesSetupPendingForUnconfiguredDraft() {
        let draft = Chart.draft(title: "New Chart", layoutStyle: .rhythmSectionSheet)

        XCTAssertEqual(draft.librarySummaryText, "Rhythm Section Sheet · setup pending")
    }

    #if DEBUG
    func testCreateChordWritingTestChartResetsDisposablePreparedChart() throws {
        let existingTestChart = Chart.blank(title: "Chord Writing Test Chart", measureCount: 2)
        let charts = (1...AppEntitlements.recommendedFreeChartLimit).map {
            Chart.blank(title: "Chart \($0)")
        } + [existingTestChart]
        var didResetDiagnostics = false
        let store = ChartLibraryStore(
            charts: charts,
            entitlements: .free,
            chordDiagnosticsResetter: {
                didResetDiagnostics = true
            }
        )

        let chartID = store.createChordWritingTestChart()

        let testChart = try XCTUnwrap(store.charts.first)
        XCTAssertTrue(didResetDiagnostics)
        XCTAssertEqual(testChart.id, chartID)
        XCTAssertEqual(testChart.title, "Chord Writing Test Chart")
        XCTAssertEqual(testChart.styleNote, "CHORD TEST LOOP")
        XCTAssertTrue(testChart.hasCompletedInitialSetup)
        XCTAssertEqual(testChart.measures.count, 8)
        XCTAssertEqual(testChart.measures.last?.barlineAfter, .double)
        XCTAssertTrue(testChart.measures.allSatisfy { $0.chordEvents.isEmpty })
        XCTAssertEqual(store.selectedChartID, chartID)
        XCTAssertEqual(
            store.charts.filter { $0.title == "Chord Writing Test Chart" }.count,
            1
        )
    }
    #endif

    func testSetPlanPersistsEntitlementsSnapshot() {
        let repository = RecordingChartRepository()
        let store = ChartLibraryStore(
            charts: ChartSamples.previewCharts,
            repository: repository
        )

        store.setPlan(.proLifetime)

        XCTAssertEqual(repository.savedSnapshots.last?.entitlements.activePlan, .proLifetime)
        XCTAssertEqual(repository.savedSnapshots.last?.entitlements.subscription.status, .legacyLocalPro)
    }

    func testSnapshotInitializerPreservesValidSelection() {
        let charts = ChartSamples.previewCharts
        let snapshot = ChartLibrarySnapshot(
            charts: charts,
            selectedChartID: charts.last?.id,
            entitlements: .free
        )

        let store = ChartLibraryStore(snapshot: snapshot)

        XCTAssertEqual(store.selectedChartID, charts.last?.id)
    }

    func testLegacySnapshotDecodingDefaultsCloudSyncFields() throws {
        struct LegacySnapshot: Encodable {
            let charts: [Chart]
            let selectedChartID: Chart.ID?
            let entitlements: AppEntitlements
        }

        let chart = Chart.blank(title: "Legacy")
        let legacySnapshot = LegacySnapshot(
            charts: [chart],
            selectedChartID: chart.id,
            entitlements: .free
        )
        let data = try ChartPersistenceCoders.encoder.encode(legacySnapshot)

        let decoded = try ChartPersistenceCoders.decoder.decode(ChartLibrarySnapshot.self, from: data)

        XCTAssertEqual(decoded.charts.map(\.id), [chart.id])
        XCTAssertTrue(decoded.deletionTombstones.isEmpty)
        XCTAssertNil(decoded.cloudMetadata.ownerID)
        XCTAssertNil(decoded.cloudMetadata.lastSyncAt)
        XCTAssertNil(decoded.cloudMetadata.lastRemoteBackupAt)
        XCTAssertTrue(decoded.projects.isEmpty)
    }

    func testUniversalRhythmGuideSupportsExpectedReferenceSymbols() {
        XCTAssertEqual(
            Set(RhythmicNotationPrimitive.supportedUniversalGuidePrimitives),
            Set([
                .wholeNote,
                .halfNote,
                .dottedHalfNote,
                .quarterNote,
                .slash,
                .dottedQuarterNote,
                .dottedEighthNote,
                .sixteenthNote,
                .eighthNote,
                .wholeRest,
                .quarterRest,
                .halfRest,
                .sixteenthRest,
                .eighthRest
            ])
        )
        XCTAssertEqual(
            Set(RhythmicNotationPrimitive.pendingUniversalGuidePrimitives),
            Set([.tie])
        )
    }

    func testRhythmReferenceCompendiumCoversSupportedVisualValues() {
        XCTAssertEqual(
            RhythmicNotationReferenceCompendium.rhythm.map(\.value),
            [.slash]
        )
        XCTAssertEqual(
            RhythmicNotationReferenceCompendium.notes.map(\.value),
            [.whole, .dottedHalf, .half, .dottedQuarter, .quarter, .dottedEighth, .eighth, .sixteenth]
        )
        XCTAssertEqual(
            RhythmicNotationReferenceCompendium.rests.map(\.value),
            [.wholeRest, .halfRest, .quarterRest, .eighthRest, .sixteenthRest]
        )
        XCTAssertEqual(
            Set(RhythmicNotationReferenceCompendium.all.map(\.value)),
            Set(RhythmicNotationCompendium.supportedValues)
        )
        XCTAssertTrue(RhythmicNotationReferenceCompendium.all.allSatisfy { !$0.guide.mustContain.isEmpty })
        XCTAssertTrue(RhythmicNotationReferenceCompendium.all.allSatisfy { !$0.guide.rejectWhen.isEmpty })
    }
}
