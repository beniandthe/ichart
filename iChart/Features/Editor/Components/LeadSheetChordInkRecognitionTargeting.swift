#if canImport(UIKit)
import Foundation
import PencilKit
import UIKit

struct LeadSheetChordInkRecognitionBatchTarget {
    var measureID: UUID
    var fraction: Double
    var visualOrder: Double
    var laneLocation: ChordInkDraftLaneLocation?
    var recognitionStrokeIndices: [Int] = []
    var strokes: [InkStroke]
    var drawingData: Data
    var drawing: PKDrawing
    var requiresEditReview: Bool = false
}

struct LeadSheetChordInkRecognitionBatchTargetingResult {
    var targets: [LeadSheetChordInkRecognitionBatchTarget]
    var diagnostics: LeadSheetChordInkRecognitionBatchTargetingDiagnostics
    /// Alternative ownership partitions are observational data only. The
    /// `targets` above remain the sole production authority.
    var boundaryHypothesisSet: LeadSheetChordInkBoundaryHypothesisSet? = nil
    var isCancelled: Bool = false
}

enum LeadSheetChordInkBoundaryHypothesisRoute: String, Hashable {
    case editContinuity = "edit_continuity"
    case draftBarlineLane = "draft_barline_lane"
    case laneRootSequence = "lane_root_sequence"
    case measureLaneRootSequence = "measure_lane_root_sequence"
    case measureLaneMixed = "measure_lane_mixed"
    case measureLane = "measure_lane"
    case gapFallback = "gap_fallback"
    case wholeRecognitionInk = "whole_recognition_ink"
}

struct LeadSheetChordInkBoundaryPartitionSignature: Hashable {
    let targetRecognitionStrokeIndices: [[Int]]
    let unassignedRecognitionStrokeIndices: [Int]
}

/// A compact, label-free ownership hypothesis in the recognition-stroke index
/// space after barline filtering. It cannot alter preview or persistence.
struct LeadSheetChordInkBoundaryHypothesis: Hashable {
    static let currentSchemaVersion = 1
    static let maximumTargetCount = 64

    let schemaVersion: Int
    let route: LeadSheetChordInkBoundaryHypothesisRoute
    let recognitionStrokeCount: Int
    let targetRecognitionStrokeIndices: [[Int]]
    let unassignedRecognitionStrokeIndices: [Int]

    var canonicalPartitionSignature: LeadSheetChordInkBoundaryPartitionSignature {
        LeadSheetChordInkBoundaryPartitionSignature(
            targetRecognitionStrokeIndices: targetRecognitionStrokeIndices.sorted(
                by: Self.lexicographicallyPrecedes
            ),
            unassignedRecognitionStrokeIndices: unassignedRecognitionStrokeIndices
        )
    }

    init?(
        route: LeadSheetChordInkBoundaryHypothesisRoute,
        recognitionStrokeCount: Int,
        targetRecognitionStrokeIndices: [[Int]]
    ) {
        guard recognitionStrokeCount > 0,
              !targetRecognitionStrokeIndices.isEmpty,
              targetRecognitionStrokeIndices.count <= Self.maximumTargetCount else {
            return nil
        }

        let domain = Set(0..<recognitionStrokeCount)
        var claimedIndices = Set<Int>()
        var canonicalTargetGroups = [[Int]]()
        canonicalTargetGroups.reserveCapacity(targetRecognitionStrokeIndices.count)
        for rawGroup in targetRecognitionStrokeIndices {
            let canonicalGroup = rawGroup.sorted()
            let groupSet = Set(canonicalGroup)
            guard !canonicalGroup.isEmpty,
                  groupSet.count == canonicalGroup.count,
                  groupSet.isSubset(of: domain),
                  claimedIndices.isDisjoint(with: groupSet) else {
                return nil
            }
            claimedIndices.formUnion(groupSet)
            canonicalTargetGroups.append(canonicalGroup)
        }

        self.schemaVersion = Self.currentSchemaVersion
        self.route = route
        self.recognitionStrokeCount = recognitionStrokeCount
        self.targetRecognitionStrokeIndices = canonicalTargetGroups
        self.unassignedRecognitionStrokeIndices = Array(
            domain.subtracting(claimedIndices)
        ).sorted()
    }

    private static func lexicographicallyPrecedes(_ lhs: [Int], _ rhs: [Int]) -> Bool {
        for (left, right) in zip(lhs, rhs) where left != right {
            return left < right
        }
        return lhs.count < rhs.count
    }
}

struct LeadSheetChordInkBoundaryHypothesisSet: Hashable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let recognitionStrokeCount: Int
    let hypotheses: [LeadSheetChordInkBoundaryHypothesis]

    init?(
        recognitionStrokeCount: Int,
        candidates: [LeadSheetChordInkBoundaryHypothesis]
    ) {
        guard recognitionStrokeCount > 0 else {
            return nil
        }

        var seenPartitions = Set<LeadSheetChordInkBoundaryPartitionSignature>()
        let deduplicated = candidates.filter { candidate in
            guard candidate.schemaVersion == LeadSheetChordInkBoundaryHypothesis.currentSchemaVersion,
                  candidate.recognitionStrokeCount == recognitionStrokeCount else {
                return false
            }
            return seenPartitions.insert(candidate.canonicalPartitionSignature).inserted
        }
        guard !deduplicated.isEmpty else {
            return nil
        }

        self.schemaVersion = Self.currentSchemaVersion
        self.recognitionStrokeCount = recognitionStrokeCount
        self.hypotheses = deduplicated
    }
}

private struct DraftBarlineLaneClusterKey: Hashable {
    var systemIndex: Int
    var segmentIndex: Int
}

private struct MeasureLaneClusterKey: Hashable {
    var systemIndex: Int
    var measureID: UUID
}

private struct MeasureLaneStrokeTarget {
    var originalIndex: Int
    var stroke: InkStroke
    var key: MeasureLaneClusterKey
}

private struct MeasureLaneClusterResult {
    var clusters: [ChordInkBatchCluster]
    var usedRootLedGrouping: Bool
    var allSelectedClustersUseRootLedGrouping: Bool
}

private struct MeasureLaneClusterGroupResult {
    var key: MeasureLaneClusterKey
    var clusters: [ChordInkBatchCluster]
    var usedRootLedGrouping: Bool
}

private struct SystemLaneStrokeTarget {
    var originalIndex: Int
    var stroke: InkStroke
    var systemIndex: Int
}

private struct ChordInkTargetingSystemLane {
    var systemIndex: Int
    var frame: CGRect
    var targetMeasureIDs: Set<UUID>
    var terminalTargetMeasureID: UUID?
}

private struct ChordInkTargetingContext {
    var chordFrame: CGRect
    var candidateMeasures: [LeadSheetMeasureLayout]
    var systemLanes: [ChordInkTargetingSystemLane]

    init(chordFrame: CGRect, pageLayout: LeadSheetPageLayout) {
        self.chordFrame = chordFrame
        candidateMeasures = pageLayout.systems.flatMap(\.measures).filter { measure in
            measure.chordInkTargetMeasureID != nil
        }
        systemLanes = pageLayout.systems.compactMap { system in
            guard let frame = LeadSheetActiveInkScope.chordWritingSystemLaneFrame(
                for: system,
                paperFrame: pageLayout.paperFrame(for: system)
            ) else {
                return nil
            }

            let orderedTargetMeasureIDs = system.measures.compactMap(\.chordInkTargetMeasureID)
            return ChordInkTargetingSystemLane(
                systemIndex: system.index,
                frame: frame,
                targetMeasureIDs: Set(orderedTargetMeasureIDs),
                terminalTargetMeasureID: orderedTargetMeasureIDs.last
            )
        }
    }
}

enum LeadSheetChordInkRecognitionTargeting {
    private static let maximumBatchTargetCount = 64

    static func target(
        for drawing: PKDrawing,
        chordFrame: CGRect,
        pageLayout: LeadSheetPageLayout?
    ) -> (measureID: UUID, fraction: Double)? {
        guard let pageLayout else {
            return nil
        }

        let inkBounds = LeadSheetChordInkImageRenderer.renderBounds(for: drawing)
        guard !inkBounds.isNull,
              inkBounds.width >= 4 || inkBounds.height >= 4 else {
            return nil
        }

        let context = ChordInkTargetingContext(
            chordFrame: chordFrame,
            pageLayout: pageLayout
        )
        return target(forInkBounds: inkBounds, context: context)
    }

    static func batchTargets(
        for drawing: PKDrawing,
        chordFrame: CGRect,
        pageLayout: LeadSheetPageLayout?,
        draftBarlines: [DraftBarline] = []
    ) -> [LeadSheetChordInkRecognitionBatchTarget] {
        batchTargetingResult(
            for: drawing,
            chordFrame: chordFrame,
            pageLayout: pageLayout,
            draftBarlines: draftBarlines
        ).targets
    }

    static func batchTargetingResult(
        for drawing: PKDrawing,
        chordFrame: CGRect,
        pageLayout: LeadSheetPageLayout?,
        draftBarlines: [DraftBarline] = [],
        preparedInkStrokes: [InkStroke]? = nil,
        shouldContinue: () -> Bool = { true }
    ) -> LeadSheetChordInkRecognitionBatchTargetingResult {
        guard shouldContinue() else {
            return cancelledResult()
        }
        guard let pageLayout else {
            return LeadSheetChordInkRecognitionBatchTargetingResult(
                targets: [],
                diagnostics: LeadSheetChordInkRecognitionBatchTargetingDiagnostics(
                    selectedRoute: "no_page_layout",
                    draftBarlineClusterCount: 0,
                    laneSequentialClusterCount: 0,
                    measureLaneClusterCount: 0,
                    fallbackClusterCount: 0,
                    selectedClusterCount: 0
                )
            )
        }

        let targetingContext = ChordInkTargetingContext(
            chordFrame: chordFrame,
            pageLayout: pageLayout
        )
        let targetingDrawing: PKDrawing
        let inkStrokes: [InkStroke]
        if let preparedInkStrokes {
            targetingDrawing = drawing
            inkStrokes = preparedInkStrokes
        } else {
            targetingDrawing = PKDrawing(
                strokes: drawing.strokes.flatMap(
                    PencilKitInkAdapter.visibleStrokeFragments(from:)
                )
            )
            inkStrokes = PencilKitInkAdapter.inkStrokes(from: targetingDrawing)
        }
        let draftBarlineClusters = draftBarlineLaneClusters(
            for: inkStrokes,
            context: targetingContext,
            draftBarlines: draftBarlines
        )
        guard shouldContinue() else {
            return cancelledResult(
                draftBarlineClusterCount: draftBarlineClusters.count
            )
        }
        let laneSequentialClusters = systemLaneSequentialClusters(
            for: inkStrokes,
            context: targetingContext
        )
        guard shouldContinue() else {
            return cancelledResult(
                draftBarlineClusterCount: draftBarlineClusters.count,
                laneSequentialClusterCount: laneSequentialClusters.count
            )
        }
        let measureLaneResult = measureLaneClusters(
            for: inkStrokes,
            context: targetingContext
        )
        let measureLaneClusters = measureLaneResult.clusters
        guard shouldContinue() else {
            return cancelledResult(
                draftBarlineClusterCount: draftBarlineClusters.count,
                laneSequentialClusterCount: laneSequentialClusters.count,
                measureLaneClusterCount: measureLaneClusters.count
            )
        }
        let fallbackClusters = ChordInkBatchClusterer.clusters(for: inkStrokes)
        guard shouldContinue() else {
            return cancelledResult(
                draftBarlineClusterCount: draftBarlineClusters.count,
                laneSequentialClusterCount: laneSequentialClusters.count,
                measureLaneClusterCount: measureLaneClusters.count,
                fallbackClusterCount: fallbackClusters.count
            )
        }
        let clusters: [ChordInkBatchCluster]
        let requiresFragmentCollapseCheck: Bool
        let selectedRoute: String
        if draftBarlineClusters.count > 1,
           draftBarlineClusters.count <= maximumBatchTargetCount {
            clusters = draftBarlineClusters
            requiresFragmentCollapseCheck = false
            selectedRoute = "draft_barline_lane"
        } else if laneSequentialClusters.count > 1,
                  laneSequentialClusters.count <= maximumBatchTargetCount {
            clusters = laneSequentialClusters
            requiresFragmentCollapseCheck = false
            selectedRoute = "lane_root_sequence"
        } else if measureLaneClusters.count > 1,
                  measureLaneClusters.count <= maximumBatchTargetCount {
            clusters = measureLaneClusters
            requiresFragmentCollapseCheck = !measureLaneResult.allSelectedClustersUseRootLedGrouping
            if measureLaneResult.allSelectedClustersUseRootLedGrouping {
                selectedRoute = "measure_lane_root_sequence"
            } else if measureLaneResult.usedRootLedGrouping {
                selectedRoute = "measure_lane_mixed"
            } else {
                selectedRoute = "measure_lane"
            }
        } else {
            clusters = fallbackClusters
            requiresFragmentCollapseCheck = true
            selectedRoute = "gap_fallback"
        }
        let boundaryHypothesisSet = boundaryHypothesisSet(
            recognitionStrokeCount: inkStrokes.count,
            selectedRoute: selectedRoute,
            selectedClusters: clusters,
            draftBarlineClusters: draftBarlineClusters,
            laneSequentialClusters: laneSequentialClusters,
            measureLaneClusters: measureLaneClusters,
            measureLaneResult: measureLaneResult,
            fallbackClusters: fallbackClusters
        )
        let emptyResult = LeadSheetChordInkRecognitionBatchTargetingResult(
            targets: [],
            diagnostics: LeadSheetChordInkRecognitionBatchTargetingDiagnostics(
                selectedRoute: selectedRoute,
                draftBarlineClusterCount: draftBarlineClusters.count,
                laneSequentialClusterCount: laneSequentialClusters.count,
                measureLaneClusterCount: measureLaneClusters.count,
                fallbackClusterCount: fallbackClusters.count,
                selectedClusterCount: clusters.count
            ),
            boundaryHypothesisSet: boundaryHypothesisSet
        )
        guard clusters.count > 1,
              clusters.count <= maximumBatchTargetCount else {
            return emptyResult
        }

        var targets: [LeadSheetChordInkRecognitionBatchTarget] = []
        targets.reserveCapacity(clusters.count)
        let drawingStrokes = targetingDrawing.strokes
        for cluster in clusters {
            guard shouldContinue() else {
                return cancelledResult(
                    draftBarlineClusterCount: draftBarlineClusters.count,
                    laneSequentialClusterCount: laneSequentialClusters.count,
                    measureLaneClusterCount: measureLaneClusters.count,
                    fallbackClusterCount: fallbackClusters.count,
                    selectedClusterCount: clusters.count
                )
            }
            guard let target = target(
                forInkBounds: cluster.bounds.cgRect,
                context: targetingContext
            ) else {
                continue
            }

            var strokePairs: [(index: Int, pencilStroke: PKStroke, inkStroke: InkStroke)] = []
            strokePairs.reserveCapacity(cluster.strokeIndices.count)
            for index in cluster.strokeIndices.sorted() {
                guard shouldContinue() else {
                    return cancelledResult(
                        draftBarlineClusterCount: draftBarlineClusters.count,
                        laneSequentialClusterCount: laneSequentialClusters.count,
                        measureLaneClusterCount: measureLaneClusters.count,
                        fallbackClusterCount: fallbackClusters.count,
                        selectedClusterCount: clusters.count
                    )
                }
                guard drawingStrokes.indices.contains(index),
                      inkStrokes.indices.contains(index) else {
                    continue
                }
                strokePairs.append((index, drawingStrokes[index], inkStrokes[index]))
            }
            guard !strokePairs.isEmpty else {
                continue
            }

            let clusterDrawing = LeadSheetPersistentInkColorPolicy.normalizedDrawing(
                PKDrawing(strokes: strokePairs.map { $0.pencilStroke })
            )
            let laneLocation = laneLocation(
                forInkBounds: cluster.bounds.cgRect,
                context: targetingContext
            )
            targets.append(LeadSheetChordInkRecognitionBatchTarget(
                measureID: target.measureID,
                fraction: target.fraction,
                visualOrder: laneLocation?.visualOrder
                    ?? visualOrder(
                        forInkBounds: cluster.bounds.cgRect,
                        context: targetingContext
                    ),
                laneLocation: laneLocation,
                recognitionStrokeIndices: strokePairs.map { $0.index },
                strokes: strokePairs.map { $0.inkStroke },
                drawingData: clusterDrawing.dataRepresentation(),
                drawing: clusterDrawing
            ))
        }
        if requiresFragmentCollapseCheck,
           ChordLaneRawBatchSplitPolicy.shouldCollapseNonBarlinedSplit(
            clusters: clusters,
            targets: targets
           ) {
            return LeadSheetChordInkRecognitionBatchTargetingResult(
                targets: [],
                diagnostics: LeadSheetChordInkRecognitionBatchTargetingDiagnostics(
                    selectedRoute: selectedRoute + "_collapsed",
                    draftBarlineClusterCount: draftBarlineClusters.count,
                    laneSequentialClusterCount: laneSequentialClusters.count,
                    measureLaneClusterCount: measureLaneClusters.count,
                    fallbackClusterCount: fallbackClusters.count,
                    selectedClusterCount: clusters.count
                ),
                boundaryHypothesisSet: boundaryHypothesisSet
            )
        }

        return LeadSheetChordInkRecognitionBatchTargetingResult(
            targets: targets,
            diagnostics: LeadSheetChordInkRecognitionBatchTargetingDiagnostics(
                selectedRoute: selectedRoute,
                draftBarlineClusterCount: draftBarlineClusters.count,
                laneSequentialClusterCount: laneSequentialClusters.count,
                measureLaneClusterCount: measureLaneClusters.count,
                fallbackClusterCount: fallbackClusters.count,
                selectedClusterCount: clusters.count
            ),
            boundaryHypothesisSet: boundaryHypothesisSet
        )
    }

    private static func boundaryHypothesisSet(
        recognitionStrokeCount: Int,
        selectedRoute: String,
        selectedClusters: [ChordInkBatchCluster],
        draftBarlineClusters: [ChordInkBatchCluster],
        laneSequentialClusters: [ChordInkBatchCluster],
        measureLaneClusters: [ChordInkBatchCluster],
        measureLaneResult: MeasureLaneClusterResult,
        fallbackClusters: [ChordInkBatchCluster]
    ) -> LeadSheetChordInkBoundaryHypothesisSet? {
        let measureRoute: LeadSheetChordInkBoundaryHypothesisRoute
        if measureLaneResult.allSelectedClustersUseRootLedGrouping {
            measureRoute = .measureLaneRootSequence
        } else if measureLaneResult.usedRootLedGrouping {
            measureRoute = .measureLaneMixed
        } else {
            measureRoute = .measureLane
        }

        var candidates = [LeadSheetChordInkBoundaryHypothesis]()
        func append(
            route: LeadSheetChordInkBoundaryHypothesisRoute,
            clusters: [ChordInkBatchCluster]
        ) {
            guard let hypothesis = LeadSheetChordInkBoundaryHypothesis(
                route: route,
                recognitionStrokeCount: recognitionStrokeCount,
                targetRecognitionStrokeIndices: clusters.map(\.strokeIndices)
            ) else {
                return
            }
            candidates.append(hypothesis)
        }

        // Put the production-selected partition first so deduplication retains
        // its route label when another strategy produced identical ownership.
        if let route = LeadSheetChordInkBoundaryHypothesisRoute(rawValue: selectedRoute) {
            append(route: route, clusters: selectedClusters)
        }
        append(route: .draftBarlineLane, clusters: draftBarlineClusters)
        append(route: .laneRootSequence, clusters: laneSequentialClusters)
        append(route: measureRoute, clusters: measureLaneClusters)
        append(route: .gapFallback, clusters: fallbackClusters)

        if recognitionStrokeCount > 0,
           let wholeInkHypothesis = LeadSheetChordInkBoundaryHypothesis(
            route: .wholeRecognitionInk,
            recognitionStrokeCount: recognitionStrokeCount,
            targetRecognitionStrokeIndices: [Array(0..<recognitionStrokeCount)]
           ) {
            candidates.append(wholeInkHypothesis)
        }

        return LeadSheetChordInkBoundaryHypothesisSet(
            recognitionStrokeCount: recognitionStrokeCount,
            candidates: candidates
        )
    }

    private static func cancelledResult(
        draftBarlineClusterCount: Int = 0,
        laneSequentialClusterCount: Int = 0,
        measureLaneClusterCount: Int = 0,
        fallbackClusterCount: Int = 0,
        selectedClusterCount: Int = 0
    ) -> LeadSheetChordInkRecognitionBatchTargetingResult {
        LeadSheetChordInkRecognitionBatchTargetingResult(
            targets: [],
            diagnostics: LeadSheetChordInkRecognitionBatchTargetingDiagnostics(
                selectedRoute: "cancelled",
                draftBarlineClusterCount: draftBarlineClusterCount,
                laneSequentialClusterCount: laneSequentialClusterCount,
                measureLaneClusterCount: measureLaneClusterCount,
                fallbackClusterCount: fallbackClusterCount,
                selectedClusterCount: selectedClusterCount
            ),
            isCancelled: true
        )
    }

    private static func draftBarlineLaneClusters(
        for strokes: [InkStroke],
        context: ChordInkTargetingContext,
        draftBarlines: [DraftBarline]
    ) -> [ChordInkBatchCluster] {
        guard !draftBarlines.isEmpty else {
            return []
        }

        let lanePositions = draftBarlineLanePositions(
            for: draftBarlines,
            context: context
        )
        guard !lanePositions.isEmpty else {
            return []
        }

        let indexedStrokes = strokes.enumerated()
            .filter { _, stroke in
                !stroke.points.isEmpty
            }
            .sorted { lhs, rhs in
                if lhs.element.bounds.minX == rhs.element.bounds.minX {
                    return lhs.offset < rhs.offset
                }

                return lhs.element.bounds.minX < rhs.element.bounds.minX
            }
        guard indexedStrokes.count > 1 else {
            return []
        }

        var bucketByKey = [DraftBarlineLaneClusterKey: [(index: Int, stroke: InkStroke)]]()
        for indexedStroke in indexedStrokes {
            let strokeBoundsInView = indexedStroke.element.bounds.cgRect
                .offsetBy(dx: context.chordFrame.minX, dy: context.chordFrame.minY)
            guard let laneMatch = laneMatch(
                for: strokeBoundsInView,
                in: context
            ) else {
                return []
            }

            let positions = lanePositions[laneMatch.systemIndex] ?? []

            let centerX = strokeBoundsInView.midX
            let segmentIndex = positions.firstIndex { centerX < $0 } ?? positions.count
            let key = DraftBarlineLaneClusterKey(
                systemIndex: laneMatch.systemIndex,
                segmentIndex: segmentIndex
            )
            bucketByKey[key, default: []].append((index: indexedStroke.offset, stroke: indexedStroke.element))
        }

        return bucketByKey
            .sorted { lhs, rhs in
                if lhs.key.systemIndex == rhs.key.systemIndex {
                    return lhs.key.segmentIndex < rhs.key.segmentIndex
                }

                return lhs.key.systemIndex < rhs.key.systemIndex
            }
            .flatMap { _, bucketStrokes in
                let orderedBucketStrokes = bucketStrokes.sorted { lhs, rhs in
                    if lhs.stroke.bounds.minX == rhs.stroke.bounds.minX {
                        return lhs.index < rhs.index
                    }

                    return lhs.stroke.bounds.minX < rhs.stroke.bounds.minX
                }

                return laneSegmentClusters(for: orderedBucketStrokes)
            }
            .filter(\.isUsable)
    }

    private static func laneSegmentClusters(
        for orderedStrokes: [(index: Int, stroke: InkStroke)]
    ) -> [ChordInkBatchCluster] {
        guard !orderedStrokes.isEmpty else {
            return []
        }

        let wholeBucketCluster = ChordInkBatchCluster(
            strokeIndices: orderedStrokes.map(\.index),
            bounds: InkBounds.enclosing(orderedStrokes.map(\.stroke.bounds))
        )
        let sequentialClusters = rootLedSequentialClusters(for: orderedStrokes)
        if sequentialClusters.count > 1 {
            return sequentialClusters
        }

        let clusters = ChordLaneDraftSegmentClusterer.clusters(for: orderedStrokes.map(\.stroke))
            .compactMap { localCluster -> ChordInkBatchCluster? in
                let originalIndices = localCluster.strokeIndices.compactMap { localIndex -> Int? in
                    guard orderedStrokes.indices.contains(localIndex) else {
                        return nil
                    }

                    return orderedStrokes[localIndex].index
                }
                guard !originalIndices.isEmpty else {
                    return nil
                }

                return ChordInkBatchCluster(
                    strokeIndices: originalIndices,
                    bounds: localCluster.bounds
                )
            }

        guard clusters.count > 1 else {
            return clusters
        }

        return ChordLaneRawBatchSplitPolicy.shouldCollapseLaneSegmentSplit(clusters: clusters)
            ? [wholeBucketCluster]
            : clusters
    }

    private static func draftBarlineLanePositions(
        for draftBarlines: [DraftBarline],
        context: ChordInkTargetingContext
    ) -> [Int: [CGFloat]] {
        var positionsBySystemIndex = [Int: [CGFloat]]()

        for barline in draftBarlines where barline.isRenderable {
            guard let match = systemLaneMatch(
                for: barline,
                in: context
            ) else {
                continue
            }

            let xPosition = match.laneFrame.minX + match.laneFrame.width * CGFloat(barline.laneFraction)
            positionsBySystemIndex[match.systemIndex, default: []].append(xPosition)
        }

        return positionsBySystemIndex.mapValues { positions in
            Array(Set(positions.map { ($0 * 10).rounded() / 10 })).sorted()
        }
    }

    private static func systemLaneMatch(
        containing measureID: UUID,
        in context: ChordInkTargetingContext
    ) -> (systemIndex: Int, laneFrame: CGRect)? {
        for lane in context.systemLanes {
            guard lane.targetMeasureIDs.contains(measureID) else {
                continue
            }

            return (lane.systemIndex, lane.frame)
        }

        return nil
    }

    private static func systemLaneMatch(
        for barline: DraftBarline,
        in context: ChordInkTargetingContext
    ) -> (systemIndex: Int, laneFrame: CGRect)? {
        if let laneLocation = barline.laneLocation,
           let lane = context.systemLanes.first(where: { $0.systemIndex == laneLocation.systemIndex }) {
            return (lane.systemIndex, lane.frame)
        }

        return systemLaneMatch(containing: barline.measureID, in: context)
    }

    private static func laneMatch(
        for boundsInView: CGRect,
        in context: ChordInkTargetingContext
    ) -> (systemIndex: Int, laneFrame: CGRect)? {
        context.systemLanes
            .compactMap { lane -> (systemIndex: Int, laneFrame: CGRect, area: CGFloat)? in
                let expandedLaneFrame = lane.frame.insetBy(dx: -8, dy: -10)
                let intersection = expandedLaneFrame.intersection(boundsInView)
                let area = intersection.isNull ? 0 : intersection.width * intersection.height
                guard area > 0 || expandedLaneFrame.contains(CGPoint(x: boundsInView.midX, y: boundsInView.midY)) else {
                    return nil
                }

                return (lane.systemIndex, lane.frame, area)
            }
            .max { lhs, rhs in
                lhs.area < rhs.area
            }
            .map { match in
                (match.systemIndex, match.laneFrame)
            }
    }

    static func visualOrder(
        for drawing: PKDrawing,
        chordFrame: CGRect,
        pageLayout: LeadSheetPageLayout?
    ) -> Double? {
        laneLocation(
            for: drawing,
            chordFrame: chordFrame,
            pageLayout: pageLayout
        )?.visualOrder
    }

    static func laneLocation(
        for drawing: PKDrawing,
        chordFrame: CGRect,
        pageLayout: LeadSheetPageLayout?
    ) -> ChordInkDraftLaneLocation? {
        guard let pageLayout else {
            return nil
        }

        let inkBounds = LeadSheetChordInkImageRenderer.renderBounds(for: drawing)
        guard !inkBounds.isNull,
              inkBounds.width >= 4 || inkBounds.height >= 4 else {
            return nil
        }

        let context = ChordInkTargetingContext(
            chordFrame: chordFrame,
            pageLayout: pageLayout
        )
        return laneLocation(
            forInkBounds: inkBounds,
            context: context
        )
    }

    private static func visualOrder(
        forInkBounds inkBounds: CGRect,
        context: ChordInkTargetingContext
    ) -> Double {
        laneLocation(
            forInkBounds: inkBounds,
            context: context
        )?.visualOrder ?? {
            let boundsInView = inkBounds.offsetBy(
                dx: context.chordFrame.minX,
                dy: context.chordFrame.minY
            )
            return Double(boundsInView.midY * 10_000 + boundsInView.midX)
        }()
    }

    private static func laneLocation(
        forInkBounds inkBounds: CGRect,
        context: ChordInkTargetingContext
    ) -> ChordInkDraftLaneLocation? {
        let boundsInView = inkBounds.offsetBy(
            dx: context.chordFrame.minX,
            dy: context.chordFrame.minY
        )
        if let match = laneMatch(for: boundsInView, in: context) {
            let normalizedX = (boundsInView.midX - match.laneFrame.minX) / max(1, match.laneFrame.width)
            return ChordInkDraftLaneLocation(
                systemIndex: match.systemIndex,
                fraction: Double(normalizedX)
            )
        }

        return nil
    }

    private static func target(
        forInkBounds inkBounds: CGRect,
        context: ChordInkTargetingContext
    ) -> (measureID: UUID, fraction: Double)? {
        guard !inkBounds.isNull,
              inkBounds.width >= 4 || inkBounds.height >= 4 else {
            return nil
        }

        let inkBoundsInView = inkBounds.offsetBy(
            dx: context.chordFrame.minX,
            dy: context.chordFrame.minY
        )
        let inkCenter = CGPoint(x: inkBoundsInView.midX, y: inkBoundsInView.midY)

        let targetMeasure = context.candidateMeasures.max { lhs, rhs in
            score(inkBoundsInView, center: inkCenter, for: lhs)
                < score(inkBoundsInView, center: inkCenter, for: rhs)
        }
        if let targetMeasure,
           let measureID = targetMeasure.chordInkTargetMeasureID,
           score(inkBoundsInView, center: inkCenter, for: targetMeasure) > 0 {
            let fraction = (inkCenter.x - targetMeasure.chordBandFrame.minX)
                / max(1, targetMeasure.chordBandFrame.width)
            return (measureID, Double(min(max(fraction, 0), 0.9999)))
        }

        return openLaneFallbackTarget(at: inkCenter, in: context)
    }

    private static func score(
        _ inkBounds: CGRect,
        center: CGPoint,
        for measure: LeadSheetMeasureLayout
    ) -> CGFloat {
        let generousBandFrame = measure.chordWritingFrame.insetBy(dx: -14, dy: -18)
        let intersection = generousBandFrame.intersection(inkBounds)
        let intersectionArea = intersection.isNull ? 0 : intersection.width * intersection.height
        let centerBonus: CGFloat = generousBandFrame.contains(center) ? 10_000 : 0

        return intersectionArea + centerBonus
    }

    private static func openLaneFallbackTarget(
        at center: CGPoint,
        in context: ChordInkTargetingContext
    ) -> (measureID: UUID, fraction: Double)? {
        for lane in context.systemLanes {
            guard let measureID = lane.terminalTargetMeasureID,
                  lane.frame.insetBy(dx: -8, dy: -8).contains(center) else {
                continue
            }

            let fraction = (center.x - lane.frame.minX) / max(1, lane.frame.width)
            return (measureID, Double(min(max(fraction, 0), 0.9999)))
        }

        return nil
    }

    private static func measureLaneClusters(
        for strokes: [InkStroke],
        context: ChordInkTargetingContext
    ) -> MeasureLaneClusterResult {
        let usableStrokes = strokes.enumerated()
            .filter { _, stroke in
                !stroke.points.isEmpty
            }
        let strokeTargets = usableStrokes
            .compactMap { index, stroke -> MeasureLaneStrokeTarget? in
                guard let target = target(
                    forInkBounds: stroke.bounds.cgRect,
                    context: context
                ),
                      let laneLocation = laneLocation(
                        forInkBounds: stroke.bounds.cgRect,
                        context: context
                      ) else {
                    return nil
                }

                return MeasureLaneStrokeTarget(
                    originalIndex: index,
                    stroke: stroke,
                    key: MeasureLaneClusterKey(
                        systemIndex: laneLocation.systemIndex,
                        measureID: target.measureID
                    )
                )
            }

        guard strokeTargets.count == usableStrokes.count,
              strokeTargets.count > 1 else {
            return MeasureLaneClusterResult(
                clusters: [],
                usedRootLedGrouping: false,
                allSelectedClustersUseRootLedGrouping: false
            )
        }

        let groupedTargets = Dictionary(grouping: strokeTargets, by: \.key)
        let groupResults = groupedTargets.map { key, group -> MeasureLaneClusterGroupResult in
            let orderedGroup = group.sorted { lhs, rhs in
                if lhs.stroke.bounds.minX == rhs.stroke.bounds.minX {
                    return lhs.originalIndex < rhs.originalIndex
                }

                return lhs.stroke.bounds.minX < rhs.stroke.bounds.minX
            }
            let orderedStrokes = orderedGroup.map { target in
                (index: target.originalIndex, stroke: target.stroke)
            }
            let sequentialClusters = rootLedSequentialClusters(for: orderedStrokes)
            if sequentialClusters.count > 1 {
                return MeasureLaneClusterGroupResult(
                    key: key,
                    clusters: sequentialClusters,
                    usedRootLedGrouping: true
                )
            }

            let fallbackClusters = ChordInkBatchClusterer.clusters(for: orderedGroup.map(\.stroke))
                .compactMap { localCluster -> (key: MeasureLaneClusterKey, cluster: ChordInkBatchCluster)? in
                    let originalIndices = localCluster.strokeIndices.compactMap { localIndex -> Int? in
                        guard orderedGroup.indices.contains(localIndex) else {
                            return nil
                        }

                        return orderedGroup[localIndex].originalIndex
                    }
                    guard !originalIndices.isEmpty else {
                        return nil
                    }

                    return (
                        key: key,
                        cluster: ChordInkBatchCluster(
                            strokeIndices: originalIndices,
                            bounds: localCluster.bounds
                        )
                    )
                }
                .map(\.cluster)

            return MeasureLaneClusterGroupResult(
                key: key,
                clusters: fallbackClusters,
                usedRootLedGrouping: false
            )
        }

        let resolvedClusterPairs = groupResults.flatMap { result in
            result.clusters.map { cluster in
                (key: result.key, cluster: cluster, usedRootLedGrouping: result.usedRootLedGrouping)
            }
        }
        let resolvedClusters = resolvedClusterPairs
            .sorted { lhs, rhs in
                if lhs.key.systemIndex == rhs.key.systemIndex {
                    return lhs.cluster.bounds.minX < rhs.cluster.bounds.minX
                }

                return lhs.key.systemIndex < rhs.key.systemIndex
            }
            .map(\.cluster)
            .filter(\.isUsable)
        let selectedStrokeIndices = Set(resolvedClusters.flatMap(\.strokeIndices))
        let selectedGroupUsesRootLed = groupResults
            .filter { result in
                result.clusters.contains { cluster in
                    !selectedStrokeIndices.isDisjoint(with: Set(cluster.strokeIndices))
                }
            }
            .map(\.usedRootLedGrouping)
        return MeasureLaneClusterResult(
            clusters: resolvedClusters,
            usedRootLedGrouping: selectedGroupUsesRootLed.contains(true),
            allSelectedClustersUseRootLedGrouping: !selectedGroupUsesRootLed.isEmpty
                && selectedGroupUsesRootLed.allSatisfy { $0 }
        )
    }

    private static func systemLaneSequentialClusters(
        for strokes: [InkStroke],
        context: ChordInkTargetingContext
    ) -> [ChordInkBatchCluster] {
        let usableStrokes = strokes.enumerated()
            .filter { _, stroke in
                !stroke.points.isEmpty
            }
        let laneStrokeTargets = usableStrokes.compactMap { index, stroke -> SystemLaneStrokeTarget? in
            let strokeBoundsInView = stroke.bounds.cgRect.offsetBy(
                dx: context.chordFrame.minX,
                dy: context.chordFrame.minY
            )
            guard let laneMatch = laneMatch(
                for: strokeBoundsInView,
                in: context
            ) else {
                return nil
            }

            return SystemLaneStrokeTarget(
                originalIndex: index,
                stroke: stroke,
                systemIndex: laneMatch.systemIndex
            )
        }

        guard laneStrokeTargets.count == usableStrokes.count,
              laneStrokeTargets.count > 1 else {
            return []
        }

        let groupedTargets = Dictionary(grouping: laneStrokeTargets, by: \.systemIndex)
        let clusters = groupedTargets.flatMap { systemIndex, group -> [(systemIndex: Int, cluster: ChordInkBatchCluster)] in
            let orderedStrokes = group
                .sorted { lhs, rhs in
                    if lhs.stroke.bounds.minX == rhs.stroke.bounds.minX {
                        return lhs.originalIndex < rhs.originalIndex
                    }

                    return lhs.stroke.bounds.minX < rhs.stroke.bounds.minX
                }
                .map { target in
                    (index: target.originalIndex, stroke: target.stroke)
                }
            // A row with one complete root is still a valid row partition.
            // Requiring two groups in EVERY row discarded all row ownership
            // when writing the first chord on the next system, sending the
            // entire page through gap clustering again.
            let sequentialClusters = rootLedSequentialClusters(for: orderedStrokes, allowsSingleRoot: true)
            guard !sequentialClusters.isEmpty else {
                return []
            }

            return sequentialClusters.map { cluster in
                (systemIndex: systemIndex, cluster: cluster)
            }
        }

        let sortedClusters = clusters
            .sorted { lhs, rhs in
                if lhs.systemIndex == rhs.systemIndex {
                    return lhs.cluster.bounds.minX < rhs.cluster.bounds.minX
                }

                return lhs.systemIndex < rhs.systemIndex
            }
            .map(\.cluster)
            .filter(\.isUsable)

        let coveredStrokeIndices = Set(sortedClusters.flatMap(\.strokeIndices))
        let expectedStrokeIndices = Set(laneStrokeTargets.map(\.originalIndex))
        guard coveredStrokeIndices == expectedStrokeIndices else {
            return []
        }

        return sortedClusters
    }

    private static func rootLedSequentialClusters(
        for orderedStrokes: [(index: Int, stroke: InkStroke)],
        allowsSingleRoot: Bool = false
    ) -> [ChordInkBatchCluster] {
        let groups = ChordInkSequentialGrouper().groups(for: orderedStrokes)
        guard !groups.isEmpty, (allowsSingleRoot || groups.count > 1),
              groups.first?.rootConfidence != nil else {
            return []
        }

        // Construction ownership can retain explicit no-read buckets. Those
        // buckets alone are not a root-led split and must not bypass the raw
        // fragment-collapse guards. A supported leading root still keeps its
        // later detached construction separate, including pending no-reads.
        return groups.map { group in
            ChordInkBatchCluster(
                strokeIndices: group.strokeIndices,
                bounds: group.bounds
            )
        }
    }
}

private extension InkBounds {
    var cgRect: CGRect {
        CGRect(
            x: minX,
            y: minY,
            width: width,
            height: height
        )
    }
}

private enum ChordLaneRawBatchSplitPolicy {
    private static let minimumStandaloneWidth = 16.0
    private static let minimumStandaloneHeight = 18.0
    private static let minimumWidthToHeightRatio = 0.28
    private static let probableRootTexts: Set<String> = ["A", "B", "C", "D", "E", "F", "G"]
    private static let suffixAndModifierTexts: Set<String> = [
        "#", "b", "△", "°", "ø", "•", "+", "m", "a", "l", "t",
        "-", "s", "u", "6", "7", "9", "(", ")", "1", "3", "5", "/"
    ]
    private static let probableRootMinimumConfidence = 0.46
    private static let probableRootMaximumLagBehindBest = 0.45

    static func hasStandaloneChordEvidence(in clusters: [ChordInkBatchCluster]) -> Bool {
        guard clusters.count > 1 else {
            return false
        }

        return clusters.allSatisfy(isStandaloneChordSized)
    }

    static func shouldCollapseNonBarlinedSplit(
        clusters: [ChordInkBatchCluster],
        targets: [LeadSheetChordInkRecognitionBatchTarget]
    ) -> Bool {
        guard clusters.count == targets.count,
              targets.count > 1,
              targetsShareSingleLaneAnchor(targets) else {
            return false
        }

        if hasDetachedRootTargetSequence(in: targets) {
            return false
        }

        return !hasStandaloneChordEvidence(in: clusters)
    }

    static func shouldCollapseLaneSegmentSplit(clusters: [ChordInkBatchCluster]) -> Bool {
        guard clusters.count > 1 else {
            return false
        }

        return !hasStandaloneChordEvidence(in: clusters)
    }

    private static func targetsShareSingleLaneAnchor(
        _ targets: [LeadSheetChordInkRecognitionBatchTarget]
    ) -> Bool {
        guard Set(targets.map(\.measureID)).count == 1 else {
            return false
        }

        let laneIndexes = targets.compactMap(\.laneLocation?.systemIndex)
        guard laneIndexes.count == targets.count else {
            return true
        }

        return Set(laneIndexes).count == 1
    }

    private static func hasDetachedRootTargetSequence(
        in targets: [LeadSheetChordInkRecognitionBatchTarget]
    ) -> Bool {
        let orderedTargets = targets
            .map { target in
                (target: target, bounds: InkBounds.enclosing(target.strokes.map(\.bounds)))
            }
            .sorted { lhs, rhs in
                if lhs.bounds.minX == rhs.bounds.minX {
                    return lhs.target.visualOrder < rhs.target.visualOrder
                }

                return lhs.bounds.minX < rhs.bounds.minX
            }
        guard orderedTargets.count > 1,
              orderedTargets.allSatisfy({ hasProbableRootEvidence(in: $0.target) }) else {
            return false
        }

        return zip(orderedTargets, orderedTargets.dropFirst()).allSatisfy { leading, trailing in
            ChordInkSequentialRootStartDetector.isRootSequenceBoundarySizedGlyph(
                trailing.bounds,
                from: leading.bounds
            )
        }
    }

    private static func hasProbableRootEvidence(
        in target: LeadSheetChordInkRecognitionBatchTarget
    ) -> Bool {
        let cluster = InkCluster(strokes: target.strokes)
        let mutableCluster = MutableInkCluster(
            strokes: target.strokes,
            originalIndexes: Array(target.strokes.indices)
        )
        guard mutableCluster.hasRootConstructionBody
                || mutableCluster.hasRootConstructionVerticalStem && mutableCluster.hasRootConstructionBar else {
            return false
        }

        let candidates = GestureTemplateRecognizer().rankedCandidates(
            for: cluster,
            templates: ChordGlyphTemplateLibrary.initialTemplates,
            limit: 8
        )
        guard let bestCandidate = candidates.first,
              let rootCandidate = candidates.first(where: { candidate in
                probableRootTexts.contains(candidate.text)
                    && candidate.confidence >= probableRootMinimumConfidence
              }) else {
            return false
        }

        if suffixAndModifierTexts.contains(bestCandidate.text),
           bestCandidate.text != rootCandidate.text,
           rootCandidate.source != .heuristic,
           rootCandidate.confidence + 0.08 < bestCandidate.confidence {
            return false
        }

        return rootCandidate.confidence + probableRootMaximumLagBehindBest >= bestCandidate.confidence
    }

    private static func isStandaloneChordSized(_ cluster: ChordInkBatchCluster) -> Bool {
        let bounds = cluster.bounds
        guard bounds.width >= minimumStandaloneWidth,
              bounds.height >= minimumStandaloneHeight else {
            return false
        }

        return bounds.width / max(1, bounds.height) >= minimumWidthToHeightRatio
    }
}

private enum ChordLaneDraftSegmentClusterer {
    private static let maximumClusterCount = 12

    static func clusters(for strokes: [InkStroke]) -> [ChordInkBatchCluster] {
        let indexedStrokes = strokes.enumerated()
            .filter { _, stroke in
                !stroke.points.isEmpty
            }
            .sorted { lhs, rhs in
                if lhs.element.bounds.minX == rhs.element.bounds.minX {
                    return lhs.offset < rhs.offset
                }

                return lhs.element.bounds.minX < rhs.element.bounds.minX
            }

        guard indexedStrokes.count > 1 else {
            return indexedStrokes.map { indexedStroke in
                ChordInkBatchCluster(
                    strokeIndices: [indexedStroke.offset],
                    bounds: indexedStroke.element.bounds
                )
            }
        }

        let splitGap = horizontalSplitGap(for: indexedStrokes.map(\.element))
        var clusters = [ChordInkBatchCluster]()
        var currentIndices = [Int]()
        var currentBounds: InkBounds?

        for indexedStroke in indexedStrokes {
            let stroke = indexedStroke.element
            if let bounds = currentBounds {
                let gap = stroke.bounds.minX - bounds.maxX
                if gap > splitGap {
                    clusters.append(
                        ChordInkBatchCluster(
                            strokeIndices: currentIndices,
                            bounds: bounds
                        )
                    )
                    currentIndices = [indexedStroke.offset]
                    currentBounds = stroke.bounds
                } else {
                    currentIndices.append(indexedStroke.offset)
                    currentBounds = bounds.union(stroke.bounds)
                }
            } else {
                currentIndices = [indexedStroke.offset]
                currentBounds = stroke.bounds
            }
        }

        if let currentBounds {
            clusters.append(
                ChordInkBatchCluster(
                    strokeIndices: currentIndices,
                    bounds: currentBounds
                )
            )
        }

        let usableClusters = clusters.filter(\.isUsable)
        guard usableClusters.count <= maximumClusterCount else {
            return [
                ChordInkBatchCluster(
                    strokeIndices: indexedStrokes.map(\.offset),
                    bounds: InkBounds.enclosing(indexedStrokes.map(\.element.bounds))
                )
            ]
        }

        return usableClusters
    }

    private static func horizontalSplitGap(for strokes: [InkStroke]) -> Double {
        let heights = strokes
            .map(\.bounds.height)
            .filter { $0 > 0 }
            .sorted()
        let medianHeight = heights.isEmpty ? 0 : heights[heights.count / 2]
        return max(28, min(44, medianHeight * 0.7))
    }
}
#endif
