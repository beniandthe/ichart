#if canImport(UIKit)
import CoreGraphics
import Foundation

struct LeadSheetFreeInkChordAttachmentPolicy {
    private let sourceChords: [PersistentInkChordAnchor]
    private let sourceMeasures: [UUID: PersistentInkMeasureAnchor]
    private let targetChords: [UUID: PersistentInkChordAnchor]
    private let engravingChanged: Bool
    private let usesStafflessTargetGeometry: Bool

    init(source: PersistentInkCoordinateSpace, target: PersistentInkCoordinateSpace) {
        engravingChanged = LeadSheetPersistentInkCoordinateSpacePolicy.changesStaffEngraving(
            from: source, to: target
        )
        sourceChords = source.chordAnchors ?? []
        sourceMeasures = Dictionary((source.measureAnchors ?? []).map { ($0.measureID, $0) },
            uniquingKeysWith: { first, _ in first })
        targetChords = Dictionary((target.chordAnchors ?? []).map { ($0.chordID, $0) },
            uniquingKeysWith: { first, _ in first })
        let targetMeasures = target.measureAnchors ?? []
        usesStafflessTargetGeometry = !targetMeasures.isEmpty && targetMeasures.allSatisfy { $0.staffFrame == nil }
    }

    var hasMovedChords: Bool {
        sourceChords.contains { chord in
            guard let target = targetChords[chord.chordID] else { return false }
            return movement(from: chord, to: target) != .identity
        }
    }

    func transform(for bounds: CGRect) -> CGAffineTransform? {
        let horizontalAllowance: CGFloat = 6
        let aligned = sourceChords.filter { chord in
            let frame = chord.frame.rect
            return isDirectlyBelow(bounds, chord: chord)
                && bounds.midX >= frame.minX - horizontalAllowance
                && bounds.midX <= frame.maxX + horizontalAllowance
        }
        guard let chord = aligned.min(by: { first, second in
            let firstFrame = first.frame.rect
            let secondFrame = second.frame.rect
            if abs(firstFrame.maxY - secondFrame.maxY) > 4 {
                return firstFrame.maxY > secondFrame.maxY
            }
            return abs(bounds.midX - firstFrame.midX) < abs(bounds.midX - secondFrame.midX)
        }), let target = targetChords[chord.chordID] else { return nil }

        if let measure = sourceMeasures[chord.measureID] {
            let frame = measure.staffFrame?.rect ?? measure.frame.rect
            // A connected phrase spanning a barline stays with the measure mapping.
            guard bounds.minX >= frame.minX - horizontalAllowance,
                  bounds.maxX <= frame.maxX + horizontalAllowance else { return nil }
            // A staff spacing change must retain the pitch of handwriting on the staff.
            if engravingChanged, let staff = measure.staffFrame?.rect, bounds.intersects(staff) {
                return nil
            }
        }

        let sourceFrame = chord.frame.rect
        let crossesAnotherChord = sourceChords.contains { neighbor in
            let frame = neighbor.frame.rect
            guard neighbor.chordID != chord.chordID,
                  bounds.maxX > frame.minX, bounds.minX < frame.maxX else { return false }
            return bounds.intersects(frame)
                || (abs(frame.maxY - sourceFrame.maxY) <= 4 && isDirectlyBelow(bounds, chord: neighbor))
        }
        guard !crossesAnotherChord else { return nil }
        return movement(from: chord, to: target)
    }

    func rhythmMeasureForInkBelowChord(
        _ bounds: CGRect
    ) -> (id: UUID, staffFrame: CGRect)? {
        var owner: (id: UUID, staffFrame: CGRect)?
        for chord in sourceChords {
            guard let staff = sourceMeasures[chord.measureID]?.staffFrame?.rect,
                  bounds.maxY <= staff.minY,
                  bounds.minX >= staff.minX - 6, bounds.maxX <= staff.maxX + 6 else { continue }

            let frame = chord.frame.rect
            let horizontalReach = min(36, staff.height * 0.8)
            // An adjacent mark can belong to the measure without aligning
            // closely enough with the chord to follow an independent drag.
            guard bounds.minY >= frame.midY - 4, bounds.maxY >= frame.maxY - 2,
                  bounds.midX >= frame.minX - horizontalReach,
                  bounds.midX <= frame.maxX + horizontalReach else { continue }
            if let owner, owner.id != chord.measureID { return nil }
            owner = (chord.measureID, staff)
        }
        return owner
    }

    private func isDirectlyBelow(_ bounds: CGRect, chord: PersistentInkChordAnchor) -> Bool {
        let frame = chord.frame.rect
        let measure = sourceMeasures[chord.measureID]
        let staff = measure?.staffFrame?.rect
        let reach = max(frame.maxY + max(24, frame.height), (staff?.maxY ?? frame.maxY) + 24)
        guard bounds.midY <= reach else { return false }
        if bounds.minY >= frame.maxY - 2 { return true }

        guard bounds.midY >= frame.maxY else { return false }
        if let staff, bounds.maxY <= staff.minY {
            return bounds.minY >= frame.maxY - min(12, frame.height * 0.45)
        }

        // Simple centers the glyphs inside a taller chord band. Ink under the
        // glyphs can reach into the bottom padding while sitting below the band.
        guard usesStafflessTargetGeometry, measure != nil, staff == nil else { return false }
        let bottomBandPadding = min(16, frame.height / 5)
        return bounds.minY >= frame.maxY - bottomBandPadding
    }

    private func movement(
        from source: PersistentInkChordAnchor, to target: PersistentInkChordAnchor
    ) -> CGAffineTransform {
        let oldFrame = source.frame.rect
        let newFrame = target.frame.rect
        // Use the placement registration to distinguish a move from a text-width
        // change. Apply the visible origin delta because a Rhythm drag can switch
        // the snap guide from the beat center to the symbol's leading edge.
        guard source.measureID != target.measureID
                || (source.registrationPoint != nil && target.registrationPoint != nil
                    && source.registrationPoint != target.registrationPoint)
                || (oldFrame.size == newFrame.size && oldFrame.origin != newFrame.origin) else {
            return .identity
        }
        let dx = newFrame.minX - oldFrame.minX
        let dy = newFrame.minY - oldFrame.minY
        guard dx.isFinite, dy.isFinite, abs(dx) >= 0.01 || abs(dy) >= 0.01 else { return .identity }
        return CGAffineTransform(translationX: dx, y: dy)
    }
}
#endif
