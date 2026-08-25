import Foundation

enum ChordInkTheoryRole: String, Hashable {
    case rootBase
    case rootAccidental
    case quality
    case chordExtension
    case alterationAccidental
    case alterationDegree
    case slashSeparator
    case slashBassRoot
    case sixNineSeparator
    case parenthesis
    case chordRepeatDot
    case chordRepeatSlash
    case unknown
}

struct ChordInkTheoryRoleEvidence: Hashable {
    var index: Int
    var primaryRole: ChordInkTheoryRole
    var candidate: GlyphCandidate?

    var text: String? {
        candidate?.text
    }

    var confidence: Double {
        candidate?.confidence ?? 0
    }

    var opensChordGroup: Bool {
        primaryRole == .rootBase
    }
}

struct ChordInkTheoryRoleContext: Hashable {
    private static let rootTexts: Set<String> = ["A", "B", "C", "D", "E", "F", "G"]
    private static let suffixAndModifierTexts: Set<String> = [
        "#", "b", "△", "°", "ø", "•", "+", "m", "a", "l", "t",
        "-", "s", "u", "6", "7", "9", "(", ")", "1", "3", "5", "/"
    ]
    private static let directExtensionTexts: Set<String> = ["6", "7", "9"]
    private static let alterationDegreeTexts: Set<String> = ["5", "9", "1", "3"]
    private static let qualityTexts: Set<String> = ["-", "m", "△", "°", "ø", "+", "s", "u", "a", "l", "t"]

    var evidence: [ChordInkTheoryRoleEvidence]

    init(
        glyphCandidateGroups: [[GlyphCandidate]],
        clusters: [InkCluster]
    ) {
        evidence = Self.roleEvidence(
            glyphCandidateGroups: glyphCandidateGroups,
            clusters: clusters
        )
    }

    subscript(index: Int) -> ChordInkTheoryRoleEvidence? {
        guard evidence.indices.contains(index) else {
            return nil
        }

        return evidence[index]
    }

    static func rootBaseCandidate(
        in candidates: [GlyphCandidate],
        bounds: InkBounds?
    ) -> GlyphCandidate? {
        if let bounds,
           bounds.width < 8 || bounds.height < 16 || bounds.recognitionArea < 180 {
            return nil
        }

        guard let rootCandidate = candidates.first(where: { candidate in
            rootTexts.contains(candidate.text) && candidate.confidence >= 0.70
        }) else {
            return nil
        }

        if let bestCandidate = candidates.first,
           suffixAndModifierTexts.contains(bestCandidate.text) {
            return nil
        }

        let bestConfidence = candidates.first?.confidence ?? 0
        guard rootCandidate.confidence + 0.06 >= bestConfidence else {
            return nil
        }

        if let suffixCandidate = candidates.first(where: { candidate in
            suffixAndModifierTexts.contains(candidate.text)
        }),
           suffixCandidate.confidence >= rootCandidate.confidence + 0.10 {
            return nil
        }

        return rootCandidate
    }

    static func slashSeparatorCandidate(
        in candidates: [GlyphCandidate],
        cluster: InkCluster?
    ) -> GlyphCandidate? {
        if let candidate = candidates.first(where: { $0.text == "/" && $0.confidence >= 0.60 }) {
            return candidate
        }

        guard let cluster,
              cluster.strokes.count == 1,
              cluster.strokes.first?.isLooseSlashBassSeparatorCandidate == true else {
            return nil
        }

        return GlyphCandidate(text: "/", confidence: 0.60, source: .heuristic)
    }

    private static func roleEvidence(
        glyphCandidateGroups: [[GlyphCandidate]],
        clusters: [InkCluster]
    ) -> [ChordInkTheoryRoleEvidence] {
        let sortedGroups = glyphCandidateGroups.map { group in
            group.sorted { lhs, rhs in
                if lhs.confidence != rhs.confidence {
                    return lhs.confidence > rhs.confidence
                }

                return lhs.text < rhs.text
            }
        }

        if let repeatEvidence = chordRepeatEvidence(
            glyphCandidateGroups: sortedGroups,
            clusters: clusters
        ) {
            return repeatEvidence
        }

        var state = RoleScanState()
        var output: [ChordInkTheoryRoleEvidence] = []

        for index in sortedGroups.indices {
            let group = sortedGroups[index]
            let cluster = clusters.indices.contains(index) ? clusters[index] : nil

            if state.awaitingSlashBassRoot,
               let rootCandidate = rootBaseCandidate(in: group, bounds: cluster?.bounds) {
                output.append(evidence(index: index, role: .slashBassRoot, candidate: rootCandidate))
                state.awaitingSlashBassRoot = false
                state.lastRole = .slashBassRoot
                continue
            }
            state.awaitingSlashBassRoot = false

            if let rootCandidate = rootBaseCandidate(in: group, bounds: cluster?.bounds) {
                output.append(evidence(index: index, role: .rootBase, candidate: rootCandidate))
                state = RoleScanState(
                    hasActiveRoot: true,
                    rootBounds: cluster?.bounds,
                    lastRole: .rootBase
                )
                continue
            }

            guard state.hasActiveRoot else {
                output.append(evidence(index: index, role: .unknown, candidate: group.first))
                state.lastRole = .unknown
                continue
            }

            if let accidentalCandidate = rootAccidentalCandidate(
                in: group,
                cluster: cluster,
                state: state
            ) {
                output.append(evidence(index: index, role: .rootAccidental, candidate: accidentalCandidate))
                state.didConsumeRootAccidental = true
                state.lastRole = .rootAccidental
                continue
            }

            if let parenthesisCandidate = parenthesisCandidate(in: group) {
                output.append(evidence(index: index, role: .parenthesis, candidate: parenthesisCandidate))
                state.descriptorStarted = true
                state.lastRole = .parenthesis
                continue
            }

            if let accidentalCandidate = alterationAccidentalCandidate(in: group),
               state.hasExtension {
                output.append(evidence(index: index, role: .alterationAccidental, candidate: accidentalCandidate))
                state.awaitingAlterationDegree = true
                state.descriptorStarted = true
                state.lastRole = .alterationAccidental
                continue
            }

            if state.awaitingAlterationDegree,
               let degreeCandidate = alterationDegreeCandidate(in: group) {
                output.append(evidence(index: index, role: .alterationDegree, candidate: degreeCandidate))
                state.awaitingAlterationDegree = degreeCandidate.text == "1"
                state.descriptorStarted = true
                state.lastRole = .alterationDegree
                continue
            }
            state.awaitingAlterationDegree = false

            if let slashCandidate = slashSeparatorCandidate(in: group, cluster: cluster) {
                if isSixNineSeparator(
                    at: index,
                    groups: sortedGroups,
                    state: state
                ) {
                    output.append(evidence(index: index, role: .sixNineSeparator, candidate: slashCandidate))
                    state.lastRole = .sixNineSeparator
                    continue
                }

                output.append(evidence(index: index, role: .slashSeparator, candidate: slashCandidate))
                state.awaitingSlashBassRoot = true
                state.descriptorStarted = true
                state.lastRole = .slashSeparator
                continue
            }

            if let qualityCandidate = qualityCandidate(in: group) {
                output.append(evidence(index: index, role: .quality, candidate: qualityCandidate))
                state.descriptorStarted = true
                state.lastRole = .quality
                continue
            }

            if let extensionCandidate = extensionCandidate(
                in: group,
                index: index,
                groups: sortedGroups,
                previousRole: state.lastRole
            ) {
                output.append(evidence(index: index, role: .chordExtension, candidate: extensionCandidate))
                state.hasExtension = true
                state.descriptorStarted = true
                state.lastRole = .chordExtension
                continue
            }

            output.append(evidence(index: index, role: .unknown, candidate: group.first))
            state.lastRole = .unknown
        }

        return output
    }

    private static func evidence(
        index: Int,
        role: ChordInkTheoryRole,
        candidate: GlyphCandidate?
    ) -> ChordInkTheoryRoleEvidence {
        ChordInkTheoryRoleEvidence(
            index: index,
            primaryRole: role,
            candidate: candidate
        )
    }

    private static func chordRepeatEvidence(
        glyphCandidateGroups: [[GlyphCandidate]],
        clusters: [InkCluster]
    ) -> [ChordInkTheoryRoleEvidence]? {
        guard glyphCandidateGroups.count == 3,
              clusters.count == 3,
              let leadingDot = candidate("•", minimumConfidence: 0.50, in: glyphCandidateGroups[0]),
              let slash = candidate("/", minimumConfidence: 0.50, in: glyphCandidateGroups[1]),
              let trailingDot = candidate("•", minimumConfidence: 0.50, in: glyphCandidateGroups[2]),
              isChordRepeatClusterLayout(clusters) else {
            return nil
        }

        return [
            evidence(index: 0, role: .chordRepeatDot, candidate: leadingDot),
            evidence(index: 1, role: .chordRepeatSlash, candidate: slash),
            evidence(index: 2, role: .chordRepeatDot, candidate: trailingDot)
        ]
    }

    private static func isChordRepeatClusterLayout(_ clusters: [InkCluster]) -> Bool {
        let leading = clusters[0].bounds
        let slash = clusters[1].bounds
        let trailing = clusters[2].bounds
        let leadingDotCompact = leading.width <= 18 && leading.height <= 18
        let trailingDotCompact = trailing.width <= 18 && trailing.height <= 18
        let slashDominatesDots = slash.height >= max(leading.height, trailing.height) * 1.2
        let ordered = leading.recognitionMidX < slash.recognitionMidX
            && slash.recognitionMidX < trailing.recognitionMidX
        let dotVerticalSpread = abs(leading.recognitionMidY - trailing.recognitionMidY)

        return leadingDotCompact
            && trailingDotCompact
            && slashDominatesDots
            && ordered
            && dotVerticalSpread <= max(36, slash.height * 1.4)
    }

    private static func rootAccidentalCandidate(
        in group: [GlyphCandidate],
        cluster: InkCluster?,
        state: RoleScanState
    ) -> GlyphCandidate? {
        guard !state.didConsumeRootAccidental,
              !state.descriptorStarted,
              let candidate = accidentalCandidate(in: group) else {
            return nil
        }

        if candidate.text == "#", candidate.confidence >= 0.70 {
            return candidate
        }

        guard candidate.text == "b",
              candidate.confidence >= 0.60 else {
            return nil
        }

        guard let rootBounds = state.rootBounds,
              let cluster else {
            return candidate
        }

        let highModifierBottom = rootBounds.maxY - rootBounds.height * 0.32
        return cluster.bounds.maxY <= highModifierBottom ? candidate : nil
    }

    private static func parenthesisCandidate(in group: [GlyphCandidate]) -> GlyphCandidate? {
        candidate("(", minimumConfidence: 0.50, in: group)
            ?? candidate(")", minimumConfidence: 0.50, in: group)
    }

    private static func alterationAccidentalCandidate(in group: [GlyphCandidate]) -> GlyphCandidate? {
        accidentalCandidate(in: group, minimumConfidence: 0.50)
    }

    private static func alterationDegreeCandidate(in group: [GlyphCandidate]) -> GlyphCandidate? {
        group.first { candidate in
            alterationDegreeTexts.contains(candidate.text) && candidate.confidence >= 0.45
        }
    }

    private static func qualityCandidate(in group: [GlyphCandidate]) -> GlyphCandidate? {
        group.first { candidate in
            qualityTexts.contains(candidate.text) && candidate.confidence >= 0.45
        }
    }

    private static func extensionCandidate(
        in group: [GlyphCandidate],
        index: Int,
        groups: [[GlyphCandidate]],
        previousRole: ChordInkTheoryRole?
    ) -> GlyphCandidate? {
        if let candidate = group.first(where: { candidate in
            directExtensionTexts.contains(candidate.text) && candidate.confidence >= 0.45
        }) {
            return candidate
        }

        if let oneCandidate = candidate("1", minimumConfidence: 0.45, in: group) {
            return oneCandidate
        }

        if previousRole == .chordExtension,
           let compoundTail = group.first(where: { candidate in
               (candidate.text == "1" || candidate.text == "3") && candidate.confidence >= 0.45
           }) {
            return compoundTail
        }

        if index > 0,
           groups[index - 1].contains(where: { $0.text == "1" && $0.confidence >= 0.45 }),
           let compoundTail = group.first(where: { candidate in
               (candidate.text == "1" || candidate.text == "3") && candidate.confidence >= 0.45
           }) {
            return compoundTail
        }

        return nil
    }

    private static func isSixNineSeparator(
        at index: Int,
        groups: [[GlyphCandidate]],
        state: RoleScanState
    ) -> Bool {
        guard state.lastRole == .chordExtension,
              index > 0,
              groups[index - 1].contains(where: { $0.text == "6" && $0.confidence >= 0.45 }),
              groups.indices.contains(index + 1) else {
            return false
        }

        return groups[index + 1].contains { candidate in
            candidate.text == "9" && candidate.confidence >= 0.45
        }
    }

    private static func accidentalCandidate(
        in group: [GlyphCandidate],
        minimumConfidence: Double = 0.50
    ) -> GlyphCandidate? {
        group.first { candidate in
            (candidate.text == "b" || candidate.text == "#") && candidate.confidence >= minimumConfidence
        }
    }

    private static func candidate(
        _ text: String,
        minimumConfidence: Double,
        in group: [GlyphCandidate]
    ) -> GlyphCandidate? {
        group.first { candidate in
            candidate.text == text && candidate.confidence >= minimumConfidence
        }
    }
}

private struct RoleScanState: Hashable {
    var hasActiveRoot = false
    var rootBounds: InkBounds?
    var didConsumeRootAccidental = false
    var descriptorStarted = false
    var hasExtension = false
    var awaitingAlterationDegree = false
    var awaitingSlashBassRoot = false
    var lastRole: ChordInkTheoryRole?
}
