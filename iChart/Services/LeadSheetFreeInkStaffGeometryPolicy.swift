import CoreGraphics
import Foundation

/// Recovers authored staff geometry only when saved layout frames identify one
/// engraving preset. The drawing and its persisted metadata remain untouched.
enum LeadSheetFreeInkStaffGeometryPolicy {
    static func sourceCoordinateSpace(
        _ space: PersistentInkCoordinateSpace?,
        chart: Chart
    ) -> PersistentInkCoordinateSpace? {
        guard var space,
              chart.layoutStyle != .simpleChordSheet,
              let sourceAnchors = space.measureAnchors,
              !sourceAnchors.isEmpty,
              !(space.engravingPreset != nil && sourceAnchors.allSatisfy { $0.staffFrame != nil }),
              space.width.isFinite,
              space.height.isFinite,
              space.width > 0,
              space.height > 0,
              let canvasWidth = LeadSheetPageLayoutEngine.canvasWidth(
                forPageWritingWidth: CGFloat(space.width),
                layoutStyle: chart.layoutStyle
              ) else {
            return space
        }

        var matches = [(preset: EngravingPreset, anchors: [PersistentInkMeasureAnchor])]()
        for preset in EngravingPreset.allCases {
            if let authoredPreset = space.engravingPreset, authoredPreset != preset {
                continue
            }
            var candidateChart = chart
            candidateChart.engravingPreset = preset
            let layout = LeadSheetPageLayoutEngine.pageLayout(
                for: candidateChart,
                pageSize: CGSize(
                    width: canvasWidth,
                    height: LeadSheetFreeInkDocumentLayoutPolicy.portraitPageHeight
                )
            )
            let inset = LeadSheetPageLayoutEngine.pageInkWritingInset
            let writingFrame = layout.paperEnvelope.insetBy(dx: inset, dy: inset)
            let candidateAnchors = layout.systems.flatMap { system -> [PersistentInkMeasureAnchor] in
                guard system.staffLineYPositions.count == 5 else {
                    return []
                }
                return system.measures.compactMap { measure in
                    guard let measureID = measure.sourceMeasureID else {
                        return nil
                    }
                    return PersistentInkMeasureAnchor(
                        measureID: measureID,
                        frame: measure.chordWritingFrame.offsetBy(
                            dx: -writingFrame.minX,
                            dy: -writingFrame.minY
                        ),
                        staffFrame: measure.staffFrame.insetBy(dx: 0, dy: 2).offsetBy(
                            dx: -writingFrame.minX,
                            dy: -writingFrame.minY
                        )
                    )
                }
            }

            // Every saved frame must agree. A partial nearest-layout match can
            // move handwriting to a different pitch or a different system.
            let matchingAnchors = sourceAnchors.compactMap { source in
                candidateAnchors.first { candidate in
                    candidate.measureID == source.measureID
                        && framesMatch(candidate.frame.rect, source.frame.rect)
                        && (source.staffFrame.map { savedStaff in
                            candidate.staffFrame.map { framesMatch($0.rect, savedStaff.rect) } ?? false
                        } ?? true)
                }
            }
            if matchingAnchors.count == sourceAnchors.count {
                matches.append((preset, matchingAnchors))
            }
        }

        // Current-style legacy spaces keep the established paper-coordinate
        // behavior. Missing or ambiguous evidence never authorizes a guess.
        guard matches.count == 1,
              let match = matches.first,
              match.preset != chart.engravingPreset else {
            return space
        }

        space.engravingPreset = match.preset
        space.measureAnchors = zip(sourceAnchors, match.anchors).map { source, candidate in
            var enriched = source
            enriched.staffFrame = candidate.staffFrame
            return enriched
        }
        return space
    }

    private static func framesMatch(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        let tolerance: CGFloat = 0.01
        return abs(lhs.minX - rhs.minX) <= tolerance
            && abs(lhs.minY - rhs.minY) <= tolerance
            && abs(lhs.width - rhs.width) <= tolerance
            && abs(lhs.height - rhs.height) <= tolerance
    }
}
