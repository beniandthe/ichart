import Foundation

struct ChordInkSequentialGroup: Hashable {
    var strokeIndices: [Int]
    var bounds: InkBounds
    var rootBounds: InkBounds
    var anchorReason: ChordInkSequentialGroupAnchorReason
    var rootText: String?
    var rootConfidence: Double?
    var rootWasModifierLed: Bool
}

enum ChordInkSequentialGroupAnchorReason: Hashable {
    case rootStart
    case chordRepeat
    case fallbackGap
}

struct ChordInkSequentialGrouper {
    var clusterer: StrokeClusterer
    var glyphRecognizer: GestureTemplateRecognizer
    var templates: [GestureTemplate]

    init(
        clusterer: StrokeClusterer = StrokeClusterer(),
        glyphRecognizer: GestureTemplateRecognizer = GestureTemplateRecognizer(),
        templates: [GestureTemplate] = ChordGlyphTemplateLibrary.initialTemplates
    ) {
        self.clusterer = clusterer
        self.glyphRecognizer = glyphRecognizer
        self.templates = templates
    }

    func groups(for indexedStrokes: [(index: Int, stroke: InkStroke)]) -> [ChordInkSequentialGroup] {
        let temporalRuns = ownershipTemporalRuns(for: indexedStrokes)
        guard temporalRuns.count > 1,
              temporalRunsAdvanceAcrossRow(temporalRuns) else {
            return restoringOriginalStrokeOrder(
                in: splittingDetachedTrailingConstruction(
                    in: reconcilingTightTemporalFragments(
                        in: spatialGroups(for: indexedStrokes),
                        from: indexedStrokes,
                        hasHardTemporalOwnership: false
                    ),
                    from: indexedStrokes
                )
            )
        }

        var resolvedGroups = [ChordInkSequentialGroup]()
        let sourceStrokesByIndex = Dictionary(uniqueKeysWithValues: indexedStrokes.map { ($0.index, $0.stroke) })
        for temporalRun in temporalRuns {
            let precedingGroup = resolvedGroups.last
            let precedingTimelineEnd = precedingGroup?.strokeIndices.compactMap {
                sourceStrokesByIndex[$0]?.timelineEndTimeOffset
            }.max()
            let runGroups = reconcilingTightTemporalFragments(
                in: spatialGroups(
                    for: temporalRun,
                    precedingRootContext: precedingGroup,
                    precedingTimelineEnd: precedingTimelineEnd
                ),
                from: temporalRun,
                hasHardTemporalOwnership: true
            )
            if !runGroups.isEmpty {
                if runGroups.count == 1,
                   runGroups[0].rootWasModifierLed,
                   let previousGroupIndex = resolvedGroups.indices.last,
                   canReattachModifierLedTemporalRun(
                       temporalRun,
                       to: resolvedGroups[previousGroupIndex],
                       from: indexedStrokes,
                       strokesByIndex: sourceStrokesByIndex
                   ) {
                    let reconciledGroups = mergingModifierLedContinuations(
                        in: [resolvedGroups[previousGroupIndex], runGroups[0]],
                        from: indexedStrokes
                    )
                    if reconciledGroups.count == 1 {
                        // A soft construction boundary may have isolated a
                        // raised alteration whose digit looked like a root.
                        // Reuse the established subordinate/independent-root
                        // and semantic-continuation gates. Pending fallback
                        // construction is not eligible for this reattachment.
                        resolvedGroups[previousGroupIndex] = reconciledGroups[0]
                        continue
                    }
                }
                resolvedGroups.append(contentsOf: runGroups)
                continue
            }

            if let previousGroupIndex = resolvedGroups.indices.last,
               shouldAttachUnrecognizedTemporalRun(
                    temporalRun,
                    to: resolvedGroups[previousGroupIndex],
                    from: indexedStrokes
               ) {
                append(temporalRun, to: &resolvedGroups[previousGroupIndex])
            } else {
                // A hard pause followed by a left-to-right advance is strong
                // ownership evidence even when the glyph pipeline cannot find
                // a root. Preserve that ink as one explicit no-read target
                // instead of dropping timing for the entire row and allowing
                // neighboring chords to consume it.
                resolvedGroups.append(fallbackGroup(for: temporalRun))
            }
        }

        return restoringOriginalStrokeOrder(
            in: splittingDetachedTrailingConstruction(
                in: resolvedGroups,
                from: indexedStrokes
            )
        )
    }

    /// Spatial glyph discovery is intentionally free to visit marks in layout
    /// order, but the recognizer's multi-stroke templates are defined in Pencil
    /// creation order. Restore that order at the ownership boundary so writing a
    /// chord inside a row is equivalent to recognizing the same chord alone.
    private func restoringOriginalStrokeOrder(
        in groups: [ChordInkSequentialGroup]
    ) -> [ChordInkSequentialGroup] {
        groups.map { group in
            var orderedGroup = group
            orderedGroup.strokeIndices.sort()
            return orderedGroup
        }
    }

    private func spatialGroups(
        for indexedStrokes: [(index: Int, stroke: InkStroke)],
        precedingRootContext: ChordInkSequentialGroup? = nil,
        precedingTimelineEnd: TimeInterval? = nil
    ) -> [ChordInkSequentialGroup] {
        let orderedStrokes = Self.orderedStrokesForRecognition(indexedStrokes)
        guard !orderedStrokes.isEmpty else {
            return []
        }

        let clusteredStrokes = clusterer.indexedClusters(orderedStrokes.map(\.stroke))
        let localClusters = splitFusedSequentialRootClusters(
            clusteredStrokes,
            orderedStrokes: orderedStrokes
        )
        let glyphs = localClusters.compactMap { localCluster -> SequentialGlyph? in
            sequentialGlyph(for: localCluster, orderedStrokes: orderedStrokes)
        }
        var groups = [WorkingGroup]()
        var currentGroup: WorkingGroup?
        var previousGlyphWasSlashSeparator = false

        var glyphIndex = glyphs.startIndex
        while glyphIndex < glyphs.endIndex {
            if let repeatStart = chordRepeatStart(at: glyphIndex, in: glyphs) {
                if let currentGroup {
                    groups.append(currentGroup)
                }
                currentGroup = WorkingGroup(
                    glyph: repeatStart.glyph,
                    anchorReason: .chordRepeat,
                    rootText: nil,
                    rootConfidence: nil,
                    rootWasModifierLed: false
                )
                previousGlyphWasSlashSeparator = false
                glyphIndex = repeatStart.nextIndex
                continue
            }

            let glyph = glyphs[glyphIndex]
            let rootStartEvidence = glyph.isSlashSeparator
                ? nil
                : ChordInkSequentialRootStartDetector.evidence(
                    in: glyph.candidates,
                    cluster: glyph.cluster,
                    currentGroupBounds: currentGroup?.rootBounds ?? precedingRootContext?.rootBounds,
                    previousGlyphWasSlashSeparator: previousGlyphWasSlashSeparator,
                    currentGroupContentBounds: currentGroup?.bounds ?? precedingRootContext?.bounds,
                    timeGapFromCurrentGroup: currentGroup?.timeGap(before: glyph)
                        ?? Self.timelineGap(after: precedingTimelineEnd, before: glyph.timelineStartTimeOffset)
                )

            if let rootStartEvidence,
               currentGroup != nil {
                groups.append(currentGroup!)
                currentGroup = WorkingGroup(
                    glyph: glyph,
                    anchorReason: .rootStart,
                    rootText: rootStartEvidence.text,
                    rootConfidence: rootStartEvidence.confidence,
                    rootWasModifierLed: rootStartEvidence.wasModifierLed
                )
            } else if currentGroup != nil {
                if let group = currentGroup,
                   let constructionStart = rootConstructionStart(
                    at: glyphIndex,
                    in: glyphs,
                    currentGroupBounds: group.rootBounds,
                    currentGroupContentBounds: group.bounds,
                    currentGroupTimelineEndTimeOffset: group.timelineEndTimeOffset,
                    previousGlyphWasSlashSeparator: previousGlyphWasSlashSeparator
                   ) {
                    groups.append(group)
                    currentGroup = WorkingGroup(
                        glyph: constructionStart.glyph,
                        anchorReason: .rootStart,
                        rootText: constructionStart.evidence.text,
                        rootConfidence: constructionStart.evidence.confidence,
                        rootWasModifierLed: constructionStart.evidence.wasModifierLed
                    )
                    previousGlyphWasSlashSeparator = constructionStart.glyph.isSlashSeparator
                    glyphIndex = constructionStart.nextIndex
                    continue
                } else {
                    currentGroup?.append(glyph)
                }
            } else if let rootStartEvidence {
                currentGroup = WorkingGroup(
                    glyph: glyph,
                    anchorReason: .rootStart,
                    rootText: rootStartEvidence.text,
                    rootConfidence: rootStartEvidence.confidence,
                    rootWasModifierLed: rootStartEvidence.wasModifierLed
                )
            } else if let precedingRootContext,
                      let constructionStart = rootConstructionStart(
                        at: glyphIndex,
                        in: glyphs,
                        currentGroupBounds: precedingRootContext.rootBounds,
                        currentGroupContentBounds: precedingRootContext.bounds,
                        currentGroupTimelineEndTimeOffset: precedingTimelineEnd,
                        previousGlyphWasSlashSeparator: previousGlyphWasSlashSeparator
                      ) {
                currentGroup = WorkingGroup(
                    glyph: constructionStart.glyph,
                    anchorReason: .rootStart,
                    rootText: constructionStart.evidence.text,
                    rootConfidence: constructionStart.evidence.confidence,
                    rootWasModifierLed: constructionStart.evidence.wasModifierLed
                )
                previousGlyphWasSlashSeparator = constructionStart.glyph.isSlashSeparator
                glyphIndex = constructionStart.nextIndex
                continue
            } else if let constructionStart = initialRootConstructionStart(
                at: glyphIndex,
                in: glyphs
            ) {
                currentGroup = WorkingGroup(
                    glyph: constructionStart.glyph,
                    anchorReason: .rootStart,
                    rootText: constructionStart.evidence.text,
                    rootConfidence: constructionStart.evidence.confidence,
                    rootWasModifierLed: constructionStart.evidence.wasModifierLed
                )
                previousGlyphWasSlashSeparator = constructionStart.glyph.isSlashSeparator
                glyphIndex = constructionStart.nextIndex
                continue
            }

            previousGlyphWasSlashSeparator = glyph.isSlashSeparator
            glyphIndex = glyphs.index(after: glyphIndex)
        }

        if let currentGroup {
            groups.append(currentGroup)
        }

        let recognizedGroups = groups
            .map { group in
                ChordInkSequentialGroup(
                    strokeIndices: group.strokeIndices,
                    bounds: group.bounds,
                    rootBounds: group.rootBounds,
                    anchorReason: group.anchorReason,
                    rootText: group.rootText,
                    rootConfidence: group.rootConfidence,
                    rootWasModifierLed: group.rootWasModifierLed
                )
            }
            .filter { group in
                !group.strokeIndices.isEmpty
                    && (group.bounds.width >= 4 || group.bounds.height >= 4)
            }
        let ownershipAdjustedGroups = reassignLeadingWrapperOverhangs(
            in: recognizedGroups,
            from: orderedStrokes
        )
        let completedGroups = reattachingUnclusteredStrokes(
            to: ownershipAdjustedGroups,
            from: indexedStrokes
        )
        let mergedGroups = mergingModifierLedContinuations(
            in: completedGroups,
            from: indexedStrokes
        )
        guard mergedGroups.isEmpty,
              indexedStrokes.count > 1,
              indexedStrokes.count <= 24 else {
            return mergedGroups
        }

        let singleResult = ChordInkRecognizer(
            normalizesOversizedInput: false
        ).recognize(strokes: indexedStrokes.sorted { $0.index < $1.index }.map(\.stroke))
        guard let symbol = singleResult.match?.symbol,
              symbol.kind == .rooted,
              let rootCandidate = singleResult.acceptedGlyphCandidates.first,
              rootCandidate.text == symbol.root.rawValue,
              rootCandidate.confidence >= 0.50 else {
            return mergedGroups
        }

        // Initial spatial-root discovery can fail even when the complete
        // primary pipeline has a supported rooted read. Preserve that target
        // and its full source ink; this does not grant it automatic trust.
        var singleGroup = fallbackGroup(for: indexedStrokes)
        singleGroup.rootConfidence = rootCandidate.confidence
        return [singleGroup]
    }

    private func reconcilingTightTemporalFragments(
        in groups: [ChordInkSequentialGroup],
        from indexedStrokes: [(index: Int, stroke: InkStroke)],
        hasHardTemporalOwnership: Bool
    ) -> [ChordInkSequentialGroup] {
        guard groups.count > 1,
              indexedStrokes.count <= 24,
              !groups.contains(where: { $0.anchorReason == .chordRepeat }) else {
            return groups
        }

        let strokesByIndex = Dictionary(
            uniqueKeysWithValues: indexedStrokes.map { ($0.index, $0.stroke) }
        )
        let chronologicallyOrderedGroups = groups.sorted { lhs, rhs in
            let lhsStart = lhs.strokeIndices.compactMap {
                strokesByIndex[$0]?.timelineStartTimeOffset
            }.min() ?? .greatestFiniteMagnitude
            let rhsStart = rhs.strokeIndices.compactMap {
                strokesByIndex[$0]?.timelineStartTimeOffset
            }.min() ?? .greatestFiniteMagnitude
            return lhsStart == rhsStart
                ? (lhs.strokeIndices.min() ?? .max) < (rhs.strokeIndices.min() ?? .max)
                : lhsStart < rhsStart
        }
        guard zip(chronologicallyOrderedGroups, chronologicallyOrderedGroups.dropFirst())
            .allSatisfy({ earlier, later in
                ChordInkSequentialTimingPolicy.supportsModifierContinuation(
                    timelineGap(
                        after: earlier.strokeIndices,
                        before: later.strokeIndices,
                        from: strokesByIndex
                    )
                )
            }),
            let firstGroup = chronologicallyOrderedGroups.first,
            let runStrokes = strokes(
                at: indexedStrokes.map(\.index),
                from: strokesByIndex
            ),
            !hasClearlyIndependentLaterRoot(
                in: chronologicallyOrderedGroups,
                after: firstGroup,
                from: strokesByIndex
            ) else {
            return groups
        }

        let runResult = ChordInkRecognizer(
            normalizesOversizedInput: false
        ).recognize(strokes: runStrokes)
        let reconstructsRecognizedChord = shouldMergeTightTemporalContinuation(
            previousGroup: firstGroup,
            mergedResult: runResult
        )
        let consistsOnlyOfSubordinateFragments = chronologicallyOrderedGroups
            .dropFirst()
            .allSatisfy { group in
                group.rootWasModifierLed
                    || group.strokeIndices.count == 1
                    || group.rootBounds.height <= max(firstGroup.rootBounds.height, 1) * 0.80
            }
        guard hasHardTemporalOwnership
                || reconstructsRecognizedChord
                || consistsOnlyOfSubordinateFragments else {
            return groups
        }

        var mergedGroup = firstGroup
        mergedGroup.strokeIndices = indexedStrokes.map(\.index).sorted()
        mergedGroup.bounds = InkBounds.enclosing(indexedStrokes.map { $0.stroke.bounds })
        return [mergedGroup]
    }

    private func hasClearlyIndependentLaterRoot(
        in groups: [ChordInkSequentialGroup],
        after firstGroup: ChordInkSequentialGroup,
        from strokesByIndex: [Int: InkStroke]
    ) -> Bool {
        let firstRootHeight = max(firstGroup.rootBounds.height, 1)
        for groupIndex in groups.indices.dropFirst() {
            let group = groups[groupIndex]
            let precedingGroup = groups[groups.index(before: groupIndex)]
            let horizontalGap = firstGroup.rootBounds.horizontalGap(to: group.rootBounds)
            let contentGap = firstGroup.bounds.horizontalGap(to: group.rootBounds)
            let centerAdvance = group.rootBounds.recognitionMidX
                - firstGroup.rootBounds.recognitionMidX
            let rootConfidence = group.rootConfidence ?? 0
            let rootCadenceGap = timelineGap(
                after: precedingGroup.strokeIndices,
                before: group.strokeIndices,
                from: strokesByIndex
            )
            let hasIndependentAmbiguousRootCadence = rootCadenceGap.map { $0 >= 0.55 } ?? false
            let hasRelaxedMultiStrokeRootCadence = rootCadenceGap.map { $0 >= 0.30 } ?? false
            let ordinaryMultiStrokeRoot = !group.rootWasModifierLed
                && group.strokeIndices.count >= 2
            let stronglyDetachedSingleStrokeRoot = group.strokeIndices.count == 1
                && hasIndependentAmbiguousRootCadence
                && rootConfidence >= 0.94
                && horizontalGap >= max(24, firstRootHeight * 0.50)
                && contentGap >= max(28, firstRootHeight * 0.55)
                && centerAdvance >= max(38, firstRootHeight * 0.80)
            let stronglyConstructedModifierLedRoot = group.rootWasModifierLed
                && group.strokeIndices.count >= 2
                && hasIndependentAmbiguousRootCadence
                && rootConfidence >= 0.94
                && horizontalGap >= max(20, firstRootHeight * 0.42)
                && contentGap >= max(17, firstRootHeight * 0.30)
                && centerAdvance >= max(32, firstRootHeight * 0.70)
            let fullSizedDetachedSingleStrokeRoot = group.strokeIndices.count == 1
                && hasRelaxedMultiStrokeRootCadence
                && rootConfidence >= 0.94
                && group.rootBounds.height >= firstRootHeight * 0.85
                && horizontalGap >= max(17, firstRootHeight * 0.28)
                && contentGap >= max(17, firstRootHeight * 0.28)
                && centerAdvance >= max(30, firstRootHeight * 0.62)
            let stronglyDetachedAmbiguousRoot = stronglyDetachedSingleStrokeRoot
                || stronglyConstructedModifierLedRoot
                || fullSizedDetachedSingleStrokeRoot
            let minimumRootHeightRatio: Double
            if stronglyDetachedAmbiguousRoot {
                minimumRootHeightRatio = 0.60
            } else if ordinaryMultiStrokeRoot && hasRelaxedMultiStrokeRootCadence {
                minimumRootHeightRatio = 0.65
            } else {
                // A near-immediate small construction is much more likely to
                // be the remainder of an accidental, alteration, or extension
                // than a new root. Preserve the older full-size floor unless
                // the adjacent Pencil cadence supports the relaxed device-row
                // case.
                minimumRootHeightRatio = 0.85
            }
            let isIndependent = rootConfidence >= 0.85
                && (group.rootText != firstGroup.rootText || hasRelaxedMultiStrokeRootCadence)
                && (ordinaryMultiStrokeRoot || stronglyDetachedAmbiguousRoot)
                // Fast rows often begin with a tall B followed by smaller but
                // otherwise unambiguous roots. C and G can legitimately be a
                // single stroke whose glyph also resembles a modifier. Size
                // and detachment must keep that completed root from being
                // retroactively swallowed by the preceding chord.
                && group.rootBounds.height >= firstRootHeight * minimumRootHeightRatio
                && horizontalGap >= max(14, firstRootHeight * 0.28)
                && centerAdvance >= max(30, firstRootHeight * 0.62)
            if isIndependent {
                return true
            }
        }
        return false
    }

    private func canReattachModifierLedTemporalRun(
        _ temporalRun: [(index: Int, stroke: InkStroke)],
        to previousGroup: ChordInkSequentialGroup,
        from indexedStrokes: [(index: Int, stroke: InkStroke)],
        strokesByIndex: [Int: InkStroke]
    ) -> Bool {
        let gap = timelineGap(
            after: previousGroup.strokeIndices,
            before: temporalRun.map(\.index),
            from: strokesByIndex
        )
        guard isDetachedRootConstruction(
            strokes: temporalRun.map(\.stroke),
            after: previousGroup,
            cadenceGap: gap
        ) else {
            return true
        }

        // A detached C/G body can also rank as 7/m. Finding that subordinate
        // candidate must not undo the new construction's ownership boundary.
        // Only a completed explicit slash-bass, crossed sharp, or raised
        // literal modifier can override it, with the same semantic checks used
        // for an unrecognized run. A root-looking bare fragment stays separate.
        let hasStructuralContinuation = temporalRun.first.map {
            isSupportedSlashBassSeparator($0.stroke)
        } == true || hasCompletedSharpConstruction(temporalRun.map(\.stroke))
        if hasStructuralContinuation && shouldAttachUnrecognizedTemporalRun(
            temporalRun,
            to: previousGroup,
            from: indexedStrokes
        ) {
            return true
        }
        return hasCompletedRaisedLiteralContinuation(
            temporalRun,
            after: previousGroup,
            strokesByIndex: strokesByIndex
        )
    }

    private func hasCompletedRaisedLiteralContinuation(
        _ temporalRun: [(index: Int, stroke: InkStroke)],
        after previousGroup: ChordInkSequentialGroup,
        strokesByIndex: [Int: InkStroke]
    ) -> Bool {
        let runStrokes = temporalRun.sorted { $0.index < $1.index }.map(\.stroke)
        let bounds = InkBounds.enclosing(runStrokes.map(\.bounds))
        let rootHeight = max(previousGroup.rootBounds.height, 1)
        guard (2...12).contains(runStrokes.count),
              bounds.height <= rootHeight * 0.90,
              bounds.maxY <= previousGroup.rootBounds.maxY - rootHeight * 0.15,
              bounds.width <= max(96, rootHeight * 2.0),
              bounds.minX > previousGroup.bounds.maxX,
              previousGroup.bounds.horizontalGap(to: bounds) <= max(48, rootHeight * 0.85),
              let previousStrokes = strokes(at: previousGroup.strokeIndices, from: strokesByIndex),
              previousStrokes.count + runStrokes.count <= 24 else {
            return false
        }

        // A paused b13 can bootstrap a false D root from its small flat bowl.
        // Require the completed leading flat itself, not grammar's ability to
        // reinterpret a detached B/D. Both one- and two-stroke flats are valid.
        let hasLeadingFlat = runStrokes.count >= 3 && (1...2).contains { count in
            let cluster = InkCluster(strokes: Array(runStrokes.prefix(count)))
            return glyphRecognizer.rankedCandidates(
                for: cluster,
                templates: templates,
                limit: 1
            ).first.map { $0.text == "b" && $0.confidence >= 0.90 } == true
        }
        let smallNumericExtension: String?
        if runStrokes.count <= 4, bounds.height <= rootHeight * 0.55 {
            let clusters = clusterer.indexedClusters(runStrokes)
            let digits = clusters.compactMap { cluster -> String? in
                guard let candidate = glyphRecognizer.rankedCandidates(
                    for: cluster.cluster,
                    templates: templates,
                    limit: 1
                ).first,
                candidate.confidence >= 0.90,
                ["1", "3"].contains(candidate.text) else { return nil }
                return candidate.text
            }
            let literal = digits.joined()
            smallNumericExtension = clusters.count == 2 && digits.count == 2
                && ["11", "13"].contains(literal) ? literal : nil
        } else {
            smallNumericExtension = nil
        }
        guard hasLeadingFlat || smallNumericExtension != nil else { return false }

        let recognizer = ChordInkRecognizer(normalizesOversizedInput: false)
        let previousResult = recognizer.recognize(strokes: previousStrokes)
        let mergedResult = recognizer.recognize(strokes: previousStrokes + runStrokes)
        guard let previousSymbol = previousResult.match?.symbol,
              let mergedSymbol = mergedResult.match?.symbol,
              previousSymbol.kind == .rooted,
              mergedSymbol.kind == .rooted,
              previousSymbol.root == mergedSymbol.root,
              previousSymbol.accidental == mergedSymbol.accidental,
              previousSymbol.quality == mergedSymbol.quality else {
            return false
        }
        let addsLiteralFlatAlteration = hasLeadingFlat
            && Set(mergedSymbol.alterations).subtracting(previousSymbol.alterations)
                .contains(where: { $0.hasPrefix("b") })
            && mergedResult.acceptedGlyphCandidates.contains(where: {
                $0.text == "b" && $0.confidence >= 0.90
            })
        let addsLiteralNumericExtension = smallNumericExtension.map { literal in
            mergedSymbol.extensions.contains(literal)
                && !previousSymbol.extensions.contains(literal)
                && mergedResult.acceptedGlyphCandidates.suffix(2).allSatisfy { $0.confidence >= 0.90 }
                && mergedResult.acceptedGlyphCandidates.suffix(2).map(\.text).joined() == literal
        } == true
        guard addsLiteralFlatAlteration || addsLiteralNumericExtension else { return false }
        return shouldMergeModifierLedContinuation(
            previousGroup: previousGroup,
            previousResult: previousResult,
            mergedResult: mergedResult
        )
    }

    private func shouldAttachUnrecognizedTemporalRun(
        _ temporalRun: [(index: Int, stroke: InkStroke)],
        to previousGroup: ChordInkSequentialGroup,
        from indexedStrokes: [(index: Int, stroke: InkStroke)]
    ) -> Bool {
        guard temporalRun.count <= 24 else {
            return false
        }
        let strokesByIndex = Dictionary(
            uniqueKeysWithValues: indexedStrokes.map { ($0.index, $0.stroke) }
        )
        if hasCompletedRaisedLiteralContinuation(
            temporalRun,
            after: previousGroup,
            strokesByIndex: strokesByIndex
        ) {
            return true
        }

        let runBounds = InkBounds.enclosing(temporalRun.map { $0.stroke.bounds })
        let previousRootHeight = max(previousGroup.rootBounds.height, 1)
        let runClusters = clusterer.indexedClusters(temporalRun.map(\.stroke))
        let isSuffixOnlyRun = !runClusters.isEmpty
            && temporalRun.count <= 3
            && runClusters.allSatisfy { cluster in
                guard let leadingCandidate = glyphRecognizer.rankedCandidates(
                    for: cluster.cluster,
                    templates: templates,
                    limit: 1
                ).first else {
                    return false
                }
                return ChordInkSequentialRootStartDetector.isSuffixOrModifier(
                    leadingCandidate.text
                )
            }
        let isCompleteRaisedSharpRun = temporalRun.count <= 12
            && hasCompletedSharpConstruction(temporalRun.sorted { $0.index < $1.index }.map(\.stroke))
            && runBounds.maxY <= previousGroup.rootBounds.maxY - previousRootHeight * 0.15
        let firstRunStroke = temporalRun.min { $0.index < $1.index }?.stroke
        let isExplicitSlashBassRun = firstRunStroke.map {
            isSupportedSlashBassSeparator($0)
        } == true
        let horizontalGap = previousGroup.bounds.horizontalGap(to: runBounds)
        let maximumRunWidth: Double
        if isExplicitSlashBassRun {
            maximumRunWidth = max(64, previousRootHeight * 3.0)
        } else if isCompleteRaisedSharpRun {
            maximumRunWidth = max(96, previousRootHeight * 2.25)
        } else {
            maximumRunWidth = max(64, previousRootHeight * 1.35)
        }
        guard isSuffixOnlyRun || isExplicitSlashBassRun || isCompleteRaisedSharpRun,
              runBounds.minX > previousGroup.rootBounds.minX,
              runBounds.width <= maximumRunWidth,
              // A suffix resumed after a pause still sits next to its root. A
              // far-right bar or stem is also a plausible first stroke of the
              // next root; keep it as its own pending no-read target so it
              // cannot retroactively turn a trusted G into G- while the user
              // is still constructing E/F/A.
              horizontalGap <= max(48, previousRootHeight * 0.85) else {
            return false
        }

        let mergedIndices = Array(
            Set(previousGroup.strokeIndices + temporalRun.map(\.index))
        ).sorted()
        guard mergedIndices.count <= 24,
              let mergedStrokes = strokes(at: mergedIndices, from: strokesByIndex) else {
            return false
        }

        let continuationGap = timelineGap(
            after: previousGroup.strokeIndices,
            before: temporalRun.map(\.index),
            from: strokesByIndex
        )
        let recognizer = ChordInkRecognizer(normalizesOversizedInput: false)
        let mergedResult = recognizer.recognize(strokes: mergedStrokes)
        let hasFullSizedCompetingRoot = runBounds.height >= previousRootHeight * 0.80
            && runClusters.contains(where: { cluster in
                glyphRecognizer.rankedCandidates(
                    for: cluster.cluster,
                    templates: templates,
                    limit: 3
                ).contains {
                    ["A", "B", "C", "D", "E", "F", "G"].contains($0.text)
                        && $0.confidence >= 0.94
                }
            })
        let hasCompletedSevenEvidence = runClusters.count == 1
            && !hasFullSizedCompetingRoot
            && runClusters[0].cluster.strokes.count == 1
            && hasCompletedSevenConstruction(runClusters[0].cluster.strokes[0])
            && glyphRecognizer.rankedCandidates(
                for: runClusters[0].cluster,
                templates: templates,
                limit: 1
            ).first.map { $0.text == "7" && $0.confidence >= 0.90 } == true
        let hasCompletedSlashBassEvidence = isExplicitSlashBassRun
            && mergedResult.match?.symbol.kind == .rooted
            && mergedResult.match?.symbol.root.rawValue == previousGroup.rootText
            && mergedResult.match?.symbol.slashBass != nil
            && mergedResult.acceptedGlyphCandidates.contains { $0.text == "/" }
            && recognizer.recognize(strokes: temporalRun.sorted { $0.index < $1.index }.map(\.stroke))
                .match == nil
        let hasCompletedSharpEvidence = isCompleteRaisedSharpRun
            && mergedResult.match?.symbol.kind == .rooted
            && mergedResult.match?.symbol.root.rawValue == previousGroup.rootText
            && mergedResult.confidence >= 0.85
            && mergedResult.acceptedGlyphCandidates.contains {
                $0.text == "#" && $0.confidence >= 0.90
            }
            && !((mergedResult.match?.symbol.alterations.isEmpty) ?? true)
            && recognizer.recognize(strokes: temporalRun.sorted { $0.index < $1.index }.map(\.stroke))
                .match?.symbol.kind != .rooted
        if isDetachedRootConstruction(
            strokes: temporalRun.map(\.stroke),
            after: previousGroup,
            cadenceGap: continuationGap
        ), !hasCompletedSevenEvidence, !hasCompletedSlashBassEvidence, !hasCompletedSharpEvidence {
            // A new root can initially look like a suffix. Keep the whole
            // construction pending, not just its last stroke. A completed,
            // compact suffix can still rejoin its root on a later snapshot.
            return false
        }
        return shouldMergeTightTemporalContinuation(
            previousGroup: previousGroup,
            mergedResult: mergedResult
        )
    }

    private func hasCompletedSevenConstruction(_ stroke: InkStroke) -> Bool {
        if stroke.isSevenCandidate {
            return true
        }
        guard stroke.points.count >= 3 else {
            return false
        }
        let first = stroke.points[0]
        let second = stroke.points[1]
        let last = stroke.points[stroke.points.count - 1]
        let bounds = stroke.bounds
        // Sparse templates retain just the top bar and descending tail. A
        // detached bare bar/stem is not a completed seven, nor is the leftward
        // top stroke of an E/F or a loop returning to a B's left stem.
        return second.x - first.x >= bounds.width * 0.45
            && abs(second.y - first.y) <= max(2, bounds.height * 0.10)
            && first.y <= bounds.minY + bounds.height * 0.15
            && last.y >= bounds.minY + bounds.height * 0.70
            && last.x >= bounds.minX + bounds.width * 0.15
    }

    private func hasCompletedSharpConstruction(_ strokes: [InkStroke]) -> Bool {
        guard strokes.count >= 4, strokes.count <= 12 else {
            return false
        }
        // With a pause between every pen stroke, a standalone suffix lacks
        // the root/extension anchor used by clustering to rebuild its sharp.
        // Check bounded, creation-ordered windows for the same completed sharp
        // geometry. The merged primary path must independently accept the #
        // as an alteration before this can authorize reattachment.
        for startIndex in strokes.indices {
            for length in 4...6 where startIndex + length <= strokes.count {
                let window = Array(strokes[startIndex..<(startIndex + length)])
                if MutableInkCluster(strokes: window, originalIndexes: Array(window.indices))
                    .isSharpGlyphCandidate,
                   hasTwoCrossingSharpBars(window) {
                    return true
                }
            }
        }
        return false
    }

    private func hasTwoCrossingSharpBars(_ strokes: [InkStroke]) -> Bool {
        MutableInkCluster(strokes: strokes, originalIndexes: Array(strokes.indices))
            .hasTwoCrossingSharpBars
    }

    private func append(
        _ temporalRun: [(index: Int, stroke: InkStroke)],
        to group: inout ChordInkSequentialGroup
    ) {
        group.strokeIndices = Array(
            Set(group.strokeIndices + temporalRun.map(\.index))
        ).sorted()
        group.bounds = group.bounds.union(
            InkBounds.enclosing(temporalRun.map { $0.stroke.bounds })
        )
    }

    private func fallbackGroup(
        for temporalRun: [(index: Int, stroke: InkStroke)]
    ) -> ChordInkSequentialGroup {
        let bounds = InkBounds.enclosing(temporalRun.map { $0.stroke.bounds })
        let result = ChordInkRecognizer(
            normalizesOversizedInput: false
        ).recognize(
            strokes: temporalRun.sorted { $0.index < $1.index }.map(\.stroke)
        )
        let rootedSymbol = result.match?.symbol.kind == .rooted
            ? result.match?.symbol
            : nil
        return ChordInkSequentialGroup(
            strokeIndices: temporalRun.map(\.index).sorted(),
            bounds: bounds,
            rootBounds: bounds,
            anchorReason: .fallbackGap,
            rootText: rootedSymbol?.root.rawValue,
            rootConfidence: nil,
            rootWasModifierLed: false
        )
    }

    private func ownershipTemporalRuns(
        for indexedStrokes: [(index: Int, stroke: InkStroke)]
    ) -> [[(index: Int, stroke: InkStroke)]] {
        guard !indexedStrokes.isEmpty,
              indexedStrokes.allSatisfy({ $0.stroke.timelineStartTimeOffset != nil
                  && $0.stroke.timelineEndTimeOffset != nil }) else {
            return [indexedStrokes]
        }

        let chronologicalStrokes = indexedStrokes.sorted { lhs, rhs in
            let lhsStart = lhs.stroke.timelineStartTimeOffset ?? 0
            let rhsStart = rhs.stroke.timelineStartTimeOffset ?? 0
            return lhsStart == rhsStart ? lhs.index < rhs.index : lhsStart < rhsStart
        }
        var runs = [[chronologicalStrokes[0]]]
        var currentEnd = chronologicalStrokes[0].stroke.timelineEndTimeOffset ?? 0

        for indexedStroke in chronologicalStrokes.dropFirst() {
            let start = indexedStroke.stroke.timelineStartTimeOffset ?? currentEnd
            let gap = start - currentEnd
            let hardBoundary = ChordInkSequentialTimingPolicy.supportsHardChordBoundary(gap)
            let detachedConstructionBoundary: Bool
            if !hardBoundary, gap >= 0.30,
               runs[runs.index(before: runs.endIndex)].last.map({
                    isSupportedSlashBassSeparator($0.stroke)
               }) != true {
                let currentRun = runs[runs.index(before: runs.endIndex)]
                let currentGroups = reconcilingTightTemporalFragments(
                    in: spatialGroups(for: currentRun),
                    from: currentRun,
                    hasHardTemporalOwnership: true
                )
                let previousGroup = currentGroups.last ?? fallbackGroup(for: currentRun)
                detachedConstructionBoundary = isDetachedRootConstruction(
                    strokes: [indexedStroke.stroke],
                    after: previousGroup,
                    cadenceGap: gap
                )
            } else {
                detachedConstructionBoundary = false
            }
            if hardBoundary || detachedConstructionBoundary {
                runs.append([indexedStroke])
            } else {
                runs[runs.index(before: runs.endIndex)].append(indexedStroke)
            }
            currentEnd = max(
                currentEnd,
                indexedStroke.stroke.timelineEndTimeOffset ?? start
            )
        }

        return runs
    }

    private func isSupportedSlashBassSeparator(_ stroke: InkStroke) -> Bool {
        guard stroke.isLooseSlashBassSeparatorCandidate,
              let candidate = glyphRecognizer.rankedCandidates(
                for: InkCluster(strokes: [stroke], bounds: stroke.bounds),
                templates: templates,
                limit: 1
              ).first else {
            return false
        }
        // A six or curved root tail can satisfy the permissive slash geometry.
        // It must not suppress a new-chord boundary merely because of its angle.
        return candidate.text == "/" && candidate.confidence >= 0.90
    }

    private func isDetachedRootConstruction(
        strokes constructionStrokes: [InkStroke],
        after previousGroup: ChordInkSequentialGroup,
        cadenceGap: TimeInterval?
    ) -> Bool {
        guard let cadenceGap, cadenceGap >= 0.30,
              !constructionStrokes.isEmpty else {
            return false
        }

        let bounds = InkBounds.enclosing(constructionStrokes.map(\.bounds))
        // Spatial discovery can bootstrap from a trailing circle/accidental
        // when the actual leading root is a modifier lookalike. That suffix's
        // short height is not a valid baseline for the next chord. Use the
        // already-owned construction bounds when the discovered root is not
        // the leading ink, or is compact beside a similarly tall new opening.
        // A short leading F can have a taller slash-bass already owned below
        // it; comparing the next F's stem only to that short root swallows the
        // new opening. Small suffixes retain the original root-height baseline.
        // This changes ownership geometry, never the prior text or trust.
        let discoveredRootIsNotLeading = previousGroup.rootBounds.minX
            > previousGroup.bounds.minX + max(4, previousGroup.rootBounds.height * 0.12)
        let hasOwnedHeightStemConstruction = constructionStrokes.count <= 4
            && constructionStrokes.contains { stroke in
                stroke.bounds.height >= max(14, previousGroup.bounds.height * 0.35)
                    && stroke.bounds.height / max(stroke.bounds.width, 1) >= 1.90
                    && stroke.straightness >= 0.38
                    && abs(abs(stroke.angleDegrees) - 90) <= 30
            }
        let discoveredRootIsCompactComparedWithOwnedContent = previousGroup.bounds.height
            >= max(previousGroup.rootBounds.height, 1) * 1.50
            && (bounds.height >= previousGroup.bounds.height * 0.75 || hasOwnedHeightStemConstruction)
        // A raised accidental can start above the discovered F's body. The
        // next F may begin with an upper stem outside that short body's band,
        // but inside the already-owned chord's band. This is only a baseline
        // correction; detached cadence and whole-content advance still apply.
        let discoveredRootStartsBelowOwnedTop = previousGroup.rootBounds.minY
            >= previousGroup.bounds.minY + max(4, previousGroup.bounds.height * 0.20)
            && bounds.maxY < previousGroup.rootBounds.minY
                + min(max(previousGroup.rootBounds.height, 1), bounds.height) * 0.30
            && hasOwnedHeightStemConstruction
        let rootBounds = discoveredRootIsNotLeading
            || discoveredRootIsCompactComparedWithOwnedContent
            || discoveredRootStartsBelowOwnedTop
            ? previousGroup.bounds
            : previousGroup.rootBounds
        let rootHeight = max(rootBounds.height, 1)
        let contentGap = previousGroup.bounds.horizontalGap(to: bounds)
        let centerAdvance = bounds.recognitionMidX - rootBounds.recognitionMidX
        guard bounds.minX > previousGroup.bounds.maxX,
              contentGap >= max(17, rootHeight * 0.18),
              centerAdvance >= max(30, rootHeight * 0.62) else {
            return false
        }
        guard cadenceGap >= 0.55 || contentGap >= max(48, rootHeight * 0.85) else {
            return false
        }

        // A smaller following root's initial stem can end well above the
        // preceding baseline. Compare overlap to the smaller construction,
        // with detached cadence, rather than letting its height mismatch
        // authorize a rewrite of the prior chord.
        let overlapsRootBodyBand = bounds.maxY
            >= rootBounds.minY + min(rootHeight, bounds.height) * 0.30
            // Compare a taller following body symmetrically. A legitimate
            // larger G otherwise misses this band by a point and shares a
            // temporal run with the prior chord, exposing its flat as a root.
            && bounds.maxY <= rootBounds.maxY + max(rootHeight, bounds.height) * 0.55
        let hasRootBody = overlapsRootBodyBand
            && bounds.height >= max(16, rootHeight * 0.35)
            && bounds.width >= 8
            && bounds.recognitionArea >= 180
        let isFarDetached = contentGap >= max(48, rootHeight * 0.85)
        let minimumStemHeight = isFarDetached ? max(8, rootHeight * 0.20) : max(14, rootHeight * 0.35)
        let isUpperShiftedInitialStem = constructionStrokes.count == 1
            && cadenceGap >= 0.55
            && contentGap >= max(24, rootHeight * 0.50)
            && centerAdvance >= max(40, rootHeight * 0.85)
            && bounds.height >= max(18, rootHeight * 0.55)
            && bounds.minY <= rootBounds.minY - rootHeight * 0.20
            && bounds.maxY >= rootBounds.minY
            && bounds.maxY <= rootBounds.maxY
        let hasRootStem = (overlapsRootBodyBand || isUpperShiftedInitialStem)
            && bounds.height >= minimumStemHeight
            && bounds.height / max(bounds.width, 1) >= 1.90
            && constructionStrokes.contains { stroke in
                stroke.straightness >= 0.38
                    && abs(abs(stroke.angleDegrees) - 90) <= 30
            }
        // A captured B can start with a short, nearly vertical mark before
        // either bowl exists. Size alone cannot assign that unfinished mark
        // to the previous chord. A separate writing pause plus a clear advance
        // past its entire content keeps it pending; completed modifier evidence
        // can still authorize reattachment on a later snapshot.
        let hasShortDetachedInitialStem = constructionStrokes.count == 1
            && cadenceGap >= 0.55
            && contentGap >= max(20, rootHeight * 0.42)
            && centerAdvance >= max(40, rootHeight * 0.85)
            && bounds.maxY >= rootBounds.minY
            && bounds.minY <= rootBounds.maxY
            && bounds.height >= max(6, rootHeight * 0.14)
            && bounds.height < minimumStemHeight
            && bounds.height / max(bounds.width, 1) >= 1.90
            && constructionStrokes[0].straightness >= 0.75
            && abs(abs(constructionStrokes[0].angleDegrees) - 90) <= 25
        let hasOpeningRootBar = constructionStrokes.count == 1
            && bounds.maxY <= rootBounds.minY + rootHeight * 0.60
            && bounds.height <= max(14, rootHeight * 0.30)
            && bounds.width >= 8
            && constructionStrokes[0].aspectRatio >= 2.0
            && constructionStrokes[0].straightness >= 0.38
            && constructionStrokes[0].horizontalAngleMagnitude <= 30

        return hasRootBody || hasRootStem || hasShortDetachedInitialStem || hasOpeningRootBar
    }

    private func temporalRunsAdvanceAcrossRow(
        _ runs: [[(index: Int, stroke: InkStroke)]]
    ) -> Bool {
        let bounds = runs.map { run in
            InkBounds.enclosing(run.map { $0.stroke.bounds })
        }

        return zip(bounds, bounds.dropFirst()).allSatisfy { earlier, later in
            later.minX > earlier.minX
                && later.recognitionMidX >= earlier.recognitionMidX + 8
        }
    }

    private func mergingModifierLedContinuations(
        in groups: [ChordInkSequentialGroup],
        from orderedStrokes: [(index: Int, stroke: InkStroke)]
    ) -> [ChordInkSequentialGroup] {
        guard groups.count > 1 else {
            return groups
        }

        let strokesByIndex = Dictionary(
            uniqueKeysWithValues: orderedStrokes.map { ($0.index, $0.stroke) }
        )
        let recognizer = ChordInkRecognizer(normalizesOversizedInput: false)
        var refinedGroups = groups
        var groupIndex = refinedGroups.index(after: refinedGroups.startIndex)

        while groupIndex < refinedGroups.endIndex {
            let currentGroup = refinedGroups[groupIndex]
            let previousGroupIndex = refinedGroups.index(before: groupIndex)
            let previousGroup = refinedGroups[previousGroupIndex]
            // A complete repeat is an independent chord token, even when its
            // marks were written at the cadence and size of a quality suffix.
            if currentGroup.anchorReason == .chordRepeat
                || previousGroup.anchorReason == .chordRepeat {
                groupIndex = refinedGroups.index(after: groupIndex)
                continue
            }
            let detachedFallbackGap = previousGroup.bounds.horizontalGap(to: currentGroup.bounds)
            if currentGroup.anchorReason == .fallbackGap,
               currentGroup.bounds.minX > previousGroup.bounds.maxX,
               detachedFallbackGap >= max(48, previousGroup.rootBounds.height * 0.85) {
                groupIndex = refinedGroups.index(after: groupIndex)
                continue
            }
            let timeGap = timelineGap(
                after: previousGroup.strokeIndices,
                before: currentGroup.strokeIndices,
                from: strokesByIndex
            )
            let hasTightContinuationTiming = ChordInkSequentialTimingPolicy
                .supportsModifierContinuation(timeGap)
            guard currentGroup.rootWasModifierLed || hasTightContinuationTiming else {
                groupIndex = refinedGroups.index(after: groupIndex)
                continue
            }
            guard !ChordInkSequentialTimingPolicy.supportsChordBoundary(timeGap) else {
                groupIndex = refinedGroups.index(after: groupIndex)
                continue
            }
            if (currentGroup.strokeIndices.count == 1 || currentGroup.rootWasModifierLed),
               hasClearlyIndependentLaterRoot(
                   in: [previousGroup, currentGroup],
                   after: previousGroup,
                   from: strokesByIndex
               ) {
                groupIndex = refinedGroups.index(after: groupIndex)
                continue
            }
            guard isSubordinateModifierFragment(
                currentGroup,
                after: previousGroup
            ) else {
                groupIndex = refinedGroups.index(after: groupIndex)
                continue
            }

            let mergedStrokeIndices = Array(
                Set(previousGroup.strokeIndices + currentGroup.strokeIndices)
            ).sorted()
            guard mergedStrokeIndices.count <= 24,
                  let previousStrokes = strokes(
                    at: previousGroup.strokeIndices,
                    from: strokesByIndex
                  ),
                  let currentStrokes = strokes(
                    at: currentGroup.strokeIndices,
                    from: strokesByIndex
                  ),
                  let mergedStrokes = strokes(
                    at: mergedStrokeIndices,
                    from: strokesByIndex
                  ) else {
                groupIndex = refinedGroups.index(after: groupIndex)
                continue
            }

            let currentResult = ChordInkMaximumTrustRecognizer(
                baseRecognizer: recognizer
            ).recognize(strokes: currentStrokes)
            let currentDecision = ChordInkRecognitionPolicy.decision(for: currentResult)
            guard currentDecision.action != .trusted || hasTightContinuationTiming else {
                groupIndex = refinedGroups.index(after: groupIndex)
                continue
            }

            let previousResult = recognizer.recognize(strokes: previousStrokes)
            let mergedResult = recognizer.recognize(strokes: mergedStrokes)
            let continuesRecognizedChord = shouldMergeModifierLedContinuation(
                previousGroup: previousGroup,
                previousResult: previousResult,
                mergedResult: mergedResult
            )
            let reconstructsIncompleteChord = hasTightContinuationTiming
                && shouldMergeTightTemporalContinuation(
                    previousGroup: previousGroup,
                    mergedResult: mergedResult
                )
            guard continuesRecognizedChord || reconstructsIncompleteChord else {
                groupIndex = refinedGroups.index(after: groupIndex)
                continue
            }

            refinedGroups[previousGroupIndex].strokeIndices = mergedStrokeIndices
            refinedGroups[previousGroupIndex].bounds = previousGroup.bounds.union(currentGroup.bounds)
            refinedGroups.remove(at: groupIndex)
            // Do not advance. A single suffix can be split into multiple
            // modifier-led groups, and each continuation must be considered
            // against the newly reconstructed chord.
        }

        return refinedGroups
    }

    private func isSubordinateModifierFragment(
        _ currentGroup: ChordInkSequentialGroup,
        after previousGroup: ChordInkSequentialGroup
    ) -> Bool {
        let previousRootHeight = max(previousGroup.rootBounds.height, 1)
        return currentGroup.strokeIndices.count <= 8
            && currentGroup.rootBounds.height <= previousRootHeight * 0.90
            && currentGroup.bounds.width <= max(96, previousRootHeight * 2.0)
            && currentGroup.rootBounds.minX > previousGroup.rootBounds.minX
    }

    private func strokes(
        at indices: [Int],
        from strokesByIndex: [Int: InkStroke]
    ) -> [InkStroke]? {
        let resolved = indices.sorted().compactMap { strokesByIndex[$0] }
        return resolved.count == indices.count ? resolved : nil
    }

    private func timelineGap(
        after earlierStrokeIndices: [Int],
        before laterStrokeIndices: [Int],
        from strokesByIndex: [Int: InkStroke]
    ) -> TimeInterval? {
        let earlierStrokes = earlierStrokeIndices.compactMap { strokesByIndex[$0] }
        let laterStrokes = laterStrokeIndices.compactMap { strokesByIndex[$0] }
        guard earlierStrokes.count == earlierStrokeIndices.count,
              laterStrokes.count == laterStrokeIndices.count else {
            return nil
        }

        let earlierEnds = earlierStrokes.compactMap(\.timelineEndTimeOffset)
        let laterStarts = laterStrokes.compactMap(\.timelineStartTimeOffset)
        guard earlierEnds.count == earlierStrokes.count,
              laterStarts.count == laterStrokes.count,
              let earlierEnd = earlierEnds.max(),
              let laterStart = laterStarts.min(),
              laterStart >= earlierEnd else {
            return nil
        }

        return laterStart - earlierEnd
    }

    private func shouldMergeModifierLedContinuation(
        previousGroup: ChordInkSequentialGroup,
        previousResult: ChordInkRecognitionResult,
        mergedResult: ChordInkRecognitionResult
    ) -> Bool {
        guard let previousSymbol = previousResult.match?.symbol,
              let mergedSymbol = mergedResult.match?.symbol,
              previousSymbol.kind == .rooted,
              mergedSymbol.kind == .rooted,
              previousGroup.rootText == previousSymbol.root.rawValue,
              previousSymbol.root == mergedSymbol.root else {
            return false
        }

        let accidentalContinues = previousSymbol.accidental == mergedSymbol.accidental
            || (previousSymbol.accidental == .natural && mergedSymbol.accidental != .natural)
        guard accidentalContinues,
              previousSymbol.quality.isEmpty || previousSymbol.quality == mergedSymbol.quality,
              Set(previousSymbol.extensions).isSubset(of: Set(mergedSymbol.extensions)),
              Set(previousSymbol.alterations).isSubset(of: Set(mergedSymbol.alterations)),
              previousSymbol.slashBass == nil || previousSymbol.slashBass == mergedSymbol.slashBass else {
            return false
        }

        return previousSymbol.accidental != mergedSymbol.accidental
            || previousSymbol.quality != mergedSymbol.quality
            || previousSymbol.extensions != mergedSymbol.extensions
            || previousSymbol.alterations != mergedSymbol.alterations
            || previousSymbol.slashBass != mergedSymbol.slashBass
    }

    private func shouldMergeTightTemporalContinuation(
        previousGroup: ChordInkSequentialGroup,
        mergedResult: ChordInkRecognitionResult
    ) -> Bool {
        guard let mergedSymbol = mergedResult.match?.symbol,
              mergedSymbol.kind == .rooted,
              previousGroup.rootText == mergedSymbol.root.rawValue else {
            return false
        }

        return mergedSymbol.accidental != .natural
            || !mergedSymbol.quality.isEmpty
            || !mergedSymbol.extensions.isEmpty
            || !mergedSymbol.alterations.isEmpty
            || mergedSymbol.slashBass != nil
    }

    private func reassignLeadingWrapperOverhangs(
        in groups: [ChordInkSequentialGroup],
        from orderedStrokes: [(index: Int, stroke: InkStroke)]
    ) -> [ChordInkSequentialGroup] {
        guard groups.count > 1 else {
            return groups
        }

        let strokesByIndex = Dictionary(
            uniqueKeysWithValues: orderedStrokes.map { ($0.index, $0.stroke) }
        )
        var adjustedGroups = groups

        for groupIndex in adjustedGroups.indices.dropFirst() {
            let rootBounds = adjustedGroups[groupIndex].rootBounds
            let rootStrokeIndexes = adjustedGroups[groupIndex].strokeIndices.filter { index in
                guard let stroke = strokesByIndex[index] else {
                    return false
                }

                return stroke.bounds.horizontalOverlap(with: rootBounds) > 0
                    && stroke.bounds.verticalOverlap(with: rootBounds) > 0
            }
            guard let firstRootStrokeIndex = rootStrokeIndexes.min() else {
                continue
            }

            let overhangingWrapperIndexes = adjustedGroups[groupIndex].strokeIndices.filter { index in
                guard index < firstRootStrokeIndex,
                      let stroke = strokesByIndex[index] else {
                    return false
                }

                return stroke.isTrailingParenthesizedAlterationWrapperCandidate
                    && stroke.bounds.maxY < rootBounds.minY
                    && stroke.bounds.horizontalOverlap(with: rootBounds) > 0
            }
            guard !overhangingWrapperIndexes.isEmpty else {
                continue
            }

            let previousGroupIndex = adjustedGroups.index(before: groupIndex)
            for index in overhangingWrapperIndexes {
                adjustedGroups[groupIndex].strokeIndices.removeAll { $0 == index }
                adjustedGroups[previousGroupIndex].strokeIndices.append(index)
                if let stroke = strokesByIndex[index] {
                    adjustedGroups[previousGroupIndex].bounds = adjustedGroups[previousGroupIndex]
                        .bounds
                        .union(stroke.bounds)
                }
            }
            adjustedGroups[groupIndex].strokeIndices.sort()
            adjustedGroups[previousGroupIndex].strokeIndices.sort()
        }

        return adjustedGroups
    }

    private func reattachingUnclusteredStrokes(
        to groups: [ChordInkSequentialGroup],
        from orderedStrokes: [(index: Int, stroke: InkStroke)]
    ) -> [ChordInkSequentialGroup] {
        guard !groups.isEmpty else {
            return groups
        }

        var completedGroups = groups
        let coveredIndexes = Set(groups.flatMap(\.strokeIndices))
        let unclusteredStrokes = orderedStrokes.filter { !coveredIndexes.contains($0.index) }

        for unclusteredStroke in unclusteredStrokes.sorted(by: { $0.index < $1.index }) {
            let laterGroupIndex = completedGroups.indices.first { groupIndex in
                let firstWrittenIndex = completedGroups[groupIndex].strokeIndices.min() ?? .max
                return firstWrittenIndex > unclusteredStroke.index
            }
            if laterGroupIndex == nil,
               let previousGroup = completedGroups.last,
               shouldPreserveDetachedTrailingConstruction(
                   unclusteredStroke.stroke,
                   after: previousGroup
               ) {
                completedGroups.append(fallbackGroup(for: [unclusteredStroke]))
                continue
            }
            let targetGroupIndex: Int
            if let laterGroupIndex, laterGroupIndex > completedGroups.startIndex {
                // In normal left-to-right chord entry, an ignored opening or
                // closing parenthesis is written after its root and before the
                // following root. Preserve that temporal ownership even when
                // the closing curve overhangs the next root in x.
                targetGroupIndex = completedGroups.index(before: laterGroupIndex)
            } else if laterGroupIndex != nil {
                targetGroupIndex = nearestGroupIndex(
                    to: unclusteredStroke.stroke.bounds,
                    in: completedGroups
                )
            } else if let precedingGroupIndex = completedGroups.indices.last(where: { groupIndex in
                let firstWrittenIndex = completedGroups[groupIndex].strokeIndices.min() ?? .max
                return firstWrittenIndex <= unclusteredStroke.index
            }) {
                targetGroupIndex = precedingGroupIndex
            } else {
                targetGroupIndex = nearestGroupIndex(
                    to: unclusteredStroke.stroke.bounds,
                    in: completedGroups
                )
            }

            completedGroups[targetGroupIndex].strokeIndices.append(unclusteredStroke.index)
            completedGroups[targetGroupIndex].strokeIndices.sort()
            completedGroups[targetGroupIndex].bounds = completedGroups[targetGroupIndex].bounds
                .union(unclusteredStroke.stroke.bounds)
        }

        return completedGroups
    }

    private func shouldPreserveDetachedTrailingConstruction(
        _ stroke: InkStroke,
        after previousGroup: ChordInkSequentialGroup
    ) -> Bool {
        let bounds = stroke.bounds
        let horizontalGap = previousGroup.bounds.horizontalGap(to: bounds)
        let centerAdvance = bounds.recognitionMidX - previousGroup.rootBounds.recognitionMidX
        let previousRootHeight = max(previousGroup.rootBounds.height, 1)
        let isHorizontalConstructionBar = bounds.width >= 8
            && stroke.aspectRatio >= 2.0
            && stroke.straightness >= 0.75
            && stroke.horizontalAngleMagnitude <= 30
        let isVerticalConstructionStem = bounds.height >= 14
            && bounds.height / max(bounds.width, 1) >= 1.90
            && stroke.straightness >= 0.65
            && abs(abs(stroke.angleDegrees) - 90) <= 30
        let isRootBodyFragment = bounds.width >= 8
            && bounds.height >= 16
            && bounds.recognitionArea >= 180

        return bounds.minX > previousGroup.bounds.maxX
            && horizontalGap >= max(48, previousRootHeight * 0.85)
            && centerAdvance >= max(60, previousRootHeight * 1.10)
            && (isHorizontalConstructionBar
                || isVerticalConstructionStem
                || isRootBodyFragment)
    }

    private func splittingDetachedTrailingConstruction(
        in groups: [ChordInkSequentialGroup],
        from indexedStrokes: [(index: Int, stroke: InkStroke)]
    ) -> [ChordInkSequentialGroup] {
        guard let finalGroupIndex = groups.indices.last,
              let trailingStroke = indexedStrokes.max(by: { $0.index < $1.index }),
              groups[finalGroupIndex].strokeIndices.contains(trailingStroke.index) else {
            return groups
        }

        let strokesByIndex = Dictionary(
            uniqueKeysWithValues: indexedStrokes.map { ($0.index, $0.stroke) }
        )
        let precedingIndices = groups[finalGroupIndex].strokeIndices
            .filter { $0 != trailingStroke.index }
            .sorted()
        guard !precedingIndices.isEmpty,
              let precedingStrokes = strokes(at: precedingIndices, from: strokesByIndex) else {
            return groups
        }

        let precedingBounds = InkBounds.enclosing(precedingStrokes.map(\.bounds))
        let syntheticPreviousGroup = ChordInkSequentialGroup(
            strokeIndices: precedingIndices,
            bounds: precedingBounds,
            rootBounds: precedingBounds,
            anchorReason: groups[finalGroupIndex].anchorReason,
            rootText: groups[finalGroupIndex].rootText,
            rootConfidence: groups[finalGroupIndex].rootConfidence,
            rootWasModifierLed: groups[finalGroupIndex].rootWasModifierLed
        )
        guard shouldPreserveDetachedTrailingConstruction(
            trailingStroke.stroke,
            after: syntheticPreviousGroup
        ) else {
            return groups
        }

        let precedingResult = ChordInkMaximumTrustRecognizer().recognize(
            strokes: precedingStrokes,
            options: .includingSymbolLedgerDiagnostics
        )
        let precedingDecision = ChordInkRecognitionPolicy.decision(for: precedingResult)
        guard precedingDecision.action == .trusted,
              let precedingSymbol = precedingResult.match?.symbol,
              precedingSymbol.kind == .rooted else {
            return groups
        }

        var splitGroups = groups
        splitGroups[finalGroupIndex].strokeIndices = precedingIndices
        splitGroups[finalGroupIndex].bounds = precedingBounds
        splitGroups[finalGroupIndex].rootBounds = precedingBounds
        splitGroups[finalGroupIndex].rootText = precedingSymbol.root.rawValue
        splitGroups.append(fallbackGroup(for: [trailingStroke]))
        return splitGroups
    }

    private func nearestGroupIndex(
        to bounds: InkBounds,
        in groups: [ChordInkSequentialGroup]
    ) -> Int {
        groups.indices.min { lhs, rhs in
            let lhsDistance = abs(groups[lhs].rootBounds.recognitionMidX - bounds.recognitionMidX)
            let rhsDistance = abs(groups[rhs].rootBounds.recognitionMidX - bounds.recognitionMidX)
            return lhsDistance < rhsDistance
        } ?? groups.startIndex
    }

    static func orderedStrokesForRecognition(
        _ indexedStrokes: [(index: Int, stroke: InkStroke)]
    ) -> [(index: Int, stroke: InkStroke)] {
        indexedStrokes
            .filter { _, stroke in
                !stroke.points.isEmpty
            }
            .sorted { lhs, rhs in
                // A closing alteration parenthesis can overhang the next root
                // by a point or two. Keep original writing order for those
                // overlapping strokes so the wrapper is stripped with the
                // chord it closes rather than prepended to the next target.
                if abs(lhs.stroke.bounds.minX - rhs.stroke.bounds.minX) <= 4,
                   lhs.stroke.bounds.horizontalOverlap(with: rhs.stroke.bounds) > 0 {
                    return lhs.index < rhs.index
                }

                if lhs.stroke.bounds.minX == rhs.stroke.bounds.minX {
                    return lhs.index < rhs.index
                }

                return lhs.stroke.bounds.minX < rhs.stroke.bounds.minX
            }
    }

    private func sequentialGlyph(
        for localCluster: IndexedInkCluster,
        orderedStrokes: [(index: Int, stroke: InkStroke)]
    ) -> SequentialGlyph? {
        let sourceIndexedStrokes = localCluster.originalIndexes.compactMap { localIndex -> SequentialIndexedStroke? in
            guard orderedStrokes.indices.contains(localIndex) else {
                return nil
            }

            let orderedStroke = orderedStrokes[localIndex]
            return SequentialIndexedStroke(
                index: orderedStroke.index,
                stroke: orderedStroke.stroke
            )
        }
        let sourceIndexes = sourceIndexedStrokes.map(\.index).sorted()
        guard !sourceIndexes.isEmpty else {
            return nil
        }

        let sourceOrderCluster = InkCluster(
            strokes: sourceIndexedStrokes
                .sorted { lhs, rhs in lhs.index < rhs.index }
                .map(\.stroke),
            bounds: localCluster.cluster.bounds
        )
        let candidates = glyphRecognizer.rankedCandidates(
            for: sourceOrderCluster,
            templates: templates,
            limit: 8
        )
        return SequentialGlyph(
            strokeIndices: sourceIndexes,
            indexedStrokes: sourceIndexedStrokes,
            cluster: sourceOrderCluster,
            candidates: candidates
        )
    }

    private func splitFusedSequentialRootClusters(
        _ localClusters: [IndexedInkCluster],
        orderedStrokes: [(index: Int, stroke: InkStroke)]
    ) -> [IndexedInkCluster] {
        localClusters.flatMap { localCluster in
            recursivelySplitFusedSequentialRootCluster(
                localCluster,
                orderedStrokes: orderedStrokes
            )
        }
    }

    private func recursivelySplitFusedSequentialRootCluster(
        _ localCluster: IndexedInkCluster,
        orderedStrokes: [(index: Int, stroke: InkStroke)]
    ) -> [IndexedInkCluster] {
        guard let splitClusters = splitFusedSequentialRootCluster(
            localCluster,
            orderedStrokes: orderedStrokes
        ) else {
            return [localCluster]
        }

        return splitClusters.flatMap { splitCluster in
            recursivelySplitFusedSequentialRootCluster(
                splitCluster,
                orderedStrokes: orderedStrokes
            )
        }
    }

    private func splitFusedSequentialRootCluster(
        _ localCluster: IndexedInkCluster,
        orderedStrokes: [(index: Int, stroke: InkStroke)]
    ) -> [IndexedInkCluster]? {
        let orderedPairs = localCluster.originalIndexes.compactMap { localIndex -> (localIndex: Int, stroke: InkStroke)? in
            guard orderedStrokes.indices.contains(localIndex) else {
                return nil
            }

            return (localIndex: localIndex, stroke: orderedStrokes[localIndex].stroke)
        }
            .sorted { lhs, rhs in
                if lhs.stroke.bounds.minX == rhs.stroke.bounds.minX {
                    return lhs.localIndex < rhs.localIndex
                }

                return lhs.stroke.bounds.minX < rhs.stroke.bounds.minX
            }

        guard orderedPairs.count >= 3 else {
            return nil
        }

        for splitIndex in orderedPairs.indices.dropFirst() {
            let leftCluster = indexedCluster(from: Array(orderedPairs[..<splitIndex]))
            let rightCluster = indexedCluster(from: Array(orderedPairs[splitIndex...]))

            guard let leftGlyph = sequentialGlyph(for: leftCluster, orderedStrokes: orderedStrokes),
                  let rightGlyph = sequentialGlyph(for: rightCluster, orderedStrokes: orderedStrokes),
                  hasFusedSequentialRootBoundary(left: leftGlyph, right: rightGlyph) else {
                continue
            }

            return [leftCluster, rightCluster]
        }

        return nil
    }

    private func indexedCluster(
        from pairs: [(localIndex: Int, stroke: InkStroke)]
    ) -> IndexedInkCluster {
        IndexedInkCluster(
            cluster: InkCluster(strokes: pairs.map(\.stroke)),
            originalIndexes: pairs.map(\.localIndex)
        )
    }

    private func hasFusedSequentialRootBoundary(
        left: SequentialGlyph,
        right: SequentialGlyph
    ) -> Bool {
        guard ChordInkSequentialRootStartDetector.evidence(
            in: left.candidates,
            cluster: left.cluster,
            currentGroupBounds: nil,
            previousGlyphWasSlashSeparator: false
        ) != nil else {
            return false
        }

        guard right.canBeginDetachedRootConstruction(from: left.cluster.bounds),
              ChordInkSequentialRootStartDetector.evidence(
            in: right.candidates,
            cluster: right.cluster,
            currentGroupBounds: left.cluster.bounds,
            previousGlyphWasSlashSeparator: false,
            timeGapFromCurrentGroup: left.timeGap(before: right)
              ) != nil else {
            return false
        }

        return true
    }

    private func rootConstructionStart(
        at index: Int,
        in glyphs: [SequentialGlyph],
        currentGroupBounds: InkBounds,
        currentGroupContentBounds: InkBounds,
        currentGroupTimelineEndTimeOffset: TimeInterval?,
        previousGlyphWasSlashSeparator: Bool
    ) -> (glyph: SequentialGlyph, evidence: ChordInkSequentialRootStartEvidence, nextIndex: Int)? {
        guard !previousGlyphWasSlashSeparator,
              glyphs.indices.contains(index),
              glyphs[index].canBeginDetachedRootConstruction(from: currentGroupBounds) else {
            return nil
        }

        let upperBound = min(glyphs.endIndex, index + 3)
        var constructionGlyphs = [SequentialGlyph]()
        var scanIndex = index

        while scanIndex < upperBound {
            let glyph = glyphs[scanIndex]
            if scanIndex > index,
               !glyph.canContinueDetachedRootConstruction(after: constructionGlyphs.last) {
                break
            }

            constructionGlyphs.append(glyph)

            if constructionGlyphs.count >= 2 {
                let combinedGlyph = combinedGlyph(from: constructionGlyphs)
                if var evidence = ChordInkSequentialRootStartDetector.evidence(
                    in: combinedGlyph.candidates,
                    cluster: combinedGlyph.cluster,
                    currentGroupBounds: currentGroupBounds,
                    previousGlyphWasSlashSeparator: false,
                    currentGroupContentBounds: currentGroupContentBounds,
                    timeGapFromCurrentGroup: Self.timelineGap(
                        after: currentGroupTimelineEndTimeOffset,
                        before: combinedGlyph.timelineStartTimeOffset
                    )
                ) {
                    if let firstConstructionGlyph = constructionGlyphs.first {
                        evidence.wasModifierLed = evidence.wasModifierLed
                            || ChordInkSequentialRootStartDetector.isModifierLed(
                                candidates: firstConstructionGlyph.candidates,
                                excludingRootText: evidence.text
                            )
                    }
                    return (
                        glyph: combinedGlyph,
                        evidence: evidence,
                        nextIndex: glyphs.index(after: scanIndex)
                    )
                }
            }

            scanIndex = glyphs.index(after: scanIndex)
        }

        return nil
    }

    /// PencilKit can split the first handwritten letter into separate stem,
    /// body, or crossbar clusters. Recover that construction before any later
    /// root exists; otherwise those opening strokes are eventually attached to
    /// the first independently recognized chord farther across the row.
    private func initialRootConstructionStart(
        at index: Int,
        in glyphs: [SequentialGlyph]
    ) -> (glyph: SequentialGlyph, evidence: ChordInkSequentialRootStartEvidence, nextIndex: Int)? {
        guard glyphs.indices.contains(index),
              glyphs[index].canBeginInitialRootConstruction else {
            return nil
        }

        let upperBound = min(glyphs.endIndex, index + 3)
        var constructionGlyphs = [SequentialGlyph]()
        var scanIndex = index

        while scanIndex < upperBound {
            let glyph = glyphs[scanIndex]
            if scanIndex > index,
               !glyph.canContinueDetachedRootConstruction(after: constructionGlyphs.last) {
                break
            }

            constructionGlyphs.append(glyph)
            if constructionGlyphs.count >= 2 {
                let combinedGlyph = combinedGlyph(from: constructionGlyphs)
                if var evidence = ChordInkSequentialRootStartDetector.evidence(
                    in: combinedGlyph.candidates,
                    cluster: combinedGlyph.cluster,
                    currentGroupBounds: nil,
                    previousGlyphWasSlashSeparator: false
                ) {
                    if let firstConstructionGlyph = constructionGlyphs.first {
                        evidence.wasModifierLed = evidence.wasModifierLed
                            || ChordInkSequentialRootStartDetector.isModifierLed(
                                candidates: firstConstructionGlyph.candidates,
                                excludingRootText: evidence.text
                            )
                    }
                    return (
                        glyph: combinedGlyph,
                        evidence: evidence,
                        nextIndex: glyphs.index(after: scanIndex)
                    )
                }
            }

            scanIndex = glyphs.index(after: scanIndex)
        }

        return nil
    }

    private static func timelineGap(
        after endTimeOffset: TimeInterval?,
        before startTimeOffset: TimeInterval?
    ) -> TimeInterval? {
        guard let endTimeOffset,
              let startTimeOffset,
              startTimeOffset >= endTimeOffset else {
            return nil
        }

        return startTimeOffset - endTimeOffset
    }

    private func chordRepeatStart(
        at index: Int,
        in glyphs: [SequentialGlyph]
    ) -> (glyph: SequentialGlyph, nextIndex: Int)? {
        let upperBound = min(glyphs.endIndex, index + 3)
        var repeatGlyphs = [SequentialGlyph]()
        var strokeCount = 0

        for scanIndex in index..<upperBound {
            let glyph = glyphs[scanIndex]
            repeatGlyphs.append(glyph)
            strokeCount += glyph.indexedStrokes.count
            guard strokeCount <= 3 else {
                return nil
            }
            guard strokeCount == 3 else {
                continue
            }

            let strokes = repeatGlyphs.flatMap(\.indexedStrokes)
                .sorted { lhs, rhs in lhs.index < rhs.index }
                .map(\.stroke)
            // Compact root letters can fit the detector's dot geometry. Preserve
            // independent root evidence before assigning these strokes to a repeat.
            guard !repeatGlyphs.contains(where: { glyph in
                ChordInkSequentialRootStartDetector.evidence(
                    in: glyph.candidates,
                    cluster: glyph.cluster,
                    currentGroupBounds: nil,
                    previousGlyphWasSlashSeparator: false
                ) != nil
            }) else {
                return nil
            }
            guard ChordRepeatInkDetector.candidate(
                from: strokes, requiresCompactDots: true
            ) != nil else {
                return nil
            }

            return (
                glyph: combinedGlyph(from: repeatGlyphs),
                nextIndex: glyphs.index(after: scanIndex)
            )
        }

        return nil
    }

    private func combinedGlyph(from glyphs: [SequentialGlyph]) -> SequentialGlyph {
        let indexedStrokes = glyphs
            .flatMap(\.indexedStrokes)
            .sorted { lhs, rhs in lhs.index < rhs.index }
        let cluster = InkCluster(
            strokes: indexedStrokes.map(\.stroke),
            bounds: InkBounds.enclosing(glyphs.map(\.cluster.bounds))
        )
        let candidates = glyphRecognizer.rankedCandidates(
            for: cluster,
            templates: templates,
            limit: 8
        )

        return SequentialGlyph(
            strokeIndices: indexedStrokes.map(\.index).sorted(),
            indexedStrokes: indexedStrokes,
            cluster: cluster,
            candidates: candidates
        )
    }

}

struct ChordInkSequentialRootStartEvidence: Hashable {
    var text: String
    var confidence: Double
    var wasModifierLed: Bool
}

enum ChordInkSymbolicSuffixContinuationPolicy {
    private static let symbolicSuffixTexts: Set<String> = ["△", "°", "ø", "•", "+"]

    static func requiresContinuation(
        candidates: [GlyphCandidate],
        rootCandidate: GlyphCandidate,
        hasIndependentSpatialRootEvidence: Bool,
        hasRootSizedModifierLookalikeOverride: Bool
    ) -> Bool {
        guard let leadingCandidate = candidates.first,
              symbolicSuffixTexts.contains(leadingCandidate.text),
              leadingCandidate.text != rootCandidate.text,
              leadingCandidate.confidence >= rootCandidate.confidence else {
            return false
        }

        // Timing can support a spatially independent root, but it cannot turn a
        // leading quality/repeat symbol into a root by itself. Keep ambiguous close ink
        // with the active chord; the complete recognizer still has to validate
        // the resulting quality/extension/alteration grammar. Existing explicit
        // root-lookalike evidence and detached root geometry remain authoritative.
        return !hasRootSizedModifierLookalikeOverride
            && !hasIndependentSpatialRootEvidence
    }
}

enum ChordInkSequentialRootStartDetector {
    private static let rootTexts: Set<String> = ["A", "B", "C", "D", "E", "F", "G"]
    private static let initialRootStartMinimumConfidence = 0.70
    private static let detachedRootStartMinimumConfidence = 0.50
    private static let rootSizedModifierLookalikeMinimumConfidence = 0.90
    private static let rootSizedModifierLookalikeMaximumLag = 0.08
    private static let suffixAndModifierTexts: Set<String> = [
        "#", "b", "△", "°", "ø", "•", "+", "m", "a", "d", "l", "t",
        "-", "s", "u", "2", "6", "7", "9", "(", ")", "1", "3", "5", "/"
    ]
    private static let rootSizedModifierLookalikeOverrideTexts: Set<String> = ["b", "m", "-", "6"]
    private static let detachedOnlyRootSizedModifierLookalikeOverrideTexts: Set<String> = ["+"]
    private static let closeBoundarySymbolicSuffixTexts: Set<String> = ["△", "°", "ø", "•", "+"]

    static func isSuffixOrModifier(_ text: String) -> Bool {
        suffixAndModifierTexts.contains(text)
    }

    static func evidence(
        in candidates: [GlyphCandidate],
        cluster: InkCluster,
        currentGroupBounds: InkBounds?,
        previousGlyphWasSlashSeparator: Bool,
        currentRootBounds: InkBounds? = nil,
        currentGroupContentBounds: InkBounds? = nil,
        timeGapFromCurrentGroup: TimeInterval? = nil
    ) -> ChordInkSequentialRootStartEvidence? {
        let minimumRootConfidence = currentGroupBounds == nil
            ? initialRootStartMinimumConfidence
            : detachedRootStartMinimumConfidence

        guard !previousGlyphWasSlashSeparator,
              !isHalfDiminishedQualityConstruction(cluster),
              cluster.bounds.width >= 8,
              cluster.bounds.height >= 16,
              cluster.bounds.recognitionArea >= 180,
              let rootCandidate = candidates.first(where: { candidate in
                rootTexts.contains(candidate.text) && candidate.confidence >= minimumRootConfidence
              }) else {
            return nil
        }

        let bestCandidate = candidates.first
        let bestConfidence = bestCandidate?.confidence ?? 0
        let suffixLeads = bestCandidate
            .map { suffixAndModifierTexts.contains($0.text) && $0.text != rootCandidate.text } ?? false
        let suffixLeadGap = bestConfidence - rootCandidate.confidence
        let hasRootSizedModifierLookalikeOverride = Self.hasRootSizedModifierLookalikeOverride(
            rootCandidate: rootCandidate,
            bestCandidate: bestCandidate,
            cluster: cluster,
            currentGroupBounds: currentGroupBounds,
            currentRootBounds: currentRootBounds
        )

        if let currentGroupBounds {
            let hasTemporalBoundary = ChordInkSequentialTimingPolicy.supportsChordBoundary(
                timeGapFromCurrentGroup
            )
            let hasTightModifierContinuation = suffixLeads
                && ChordInkSequentialTimingPolicy.supportsModifierContinuation(
                    timeGapFromCurrentGroup
                )
            let usesStrictBoundary = isDetachedRootSizedGlyph(
                cluster.bounds, from: currentGroupBounds, rootBounds: currentRootBounds
            )
            let usesCloseBoundary = !usesStrictBoundary
                && isRootSequenceBoundarySizedGlyph(
                    cluster.bounds, from: currentGroupBounds, rootBounds: currentRootBounds
                )
            let usesTemporalBoundary = hasTemporalBoundary
                && isTemporalRootSequenceBoundarySizedGlyph(
                    cluster.bounds,
                    from: currentGroupBounds,
                    rootBounds: currentRootBounds
                )
            let hasDetachedAccumulatedChordOverride = hasRootSizedModifierLookalikeOverride
                && currentGroupContentBounds.map {
                    isDetachedFromAccumulatedChord(
                        cluster.bounds,
                        accumulatedBounds: $0
                    )
                } == true
            let accumulatedChordBounds = currentGroupContentBounds ?? currentGroupBounds
            let hasIndependentSpatialRootEvidence = (usesStrictBoundary || usesCloseBoundary)
                && isDetachedFromAccumulatedChord(
                    cluster.bounds,
                    accumulatedBounds: accumulatedChordBounds
                )
            guard usesStrictBoundary || usesCloseBoundary || usesTemporalBoundary else {
                return nil
            }

            if usesTemporalBoundary,
               ChordInkSymbolicSuffixContinuationPolicy.requiresContinuation(
                candidates: candidates,
                rootCandidate: rootCandidate,
                hasIndependentSpatialRootEvidence: hasIndependentSpatialRootEvidence,
                hasRootSizedModifierLookalikeOverride: hasRootSizedModifierLookalikeOverride
               ) {
                return nil
            }

            if hasTightModifierContinuation,
               !hasDetachedAccumulatedChordOverride {
                return nil
            }

            if usesCloseBoundary,
               !usesTemporalBoundary,
               hasCloseBoundarySymbolicSuffixPressure(
                in: candidates,
                rootCandidate: rootCandidate
               ) {
                return nil
            }

            if suffixLeads,
               !usesTemporalBoundary,
               let currentGroupContentBounds,
               !isDetachedFromAccumulatedChord(
                cluster.bounds,
                accumulatedBounds: currentGroupContentBounds
               ) {
                return nil
            }

            if suffixLeads,
               !hasRootSizedModifierLookalikeOverride,
               !usesTemporalBoundary,
               (rootCandidate.source != .heuristic || suffixLeadGap >= 0.04) {
                return nil
            }
        } else if suffixLeads {
            // At the beginning of a row there is no preceding chord context to
            // disambiguate a suffix-only fragment. Only explicitly sized
            // letter lookalikes or a visibly curved C/G body may bootstrap a
            // root; a bare 7/9/triangle must not become a phantom chord target.
            guard hasRootSizedModifierLookalikeOverride
                    || hasCurvedInitialRootOverride(
                        rootCandidate: rootCandidate,
                        cluster: cluster
                    ) else {
                return nil
            }
        }

        let hasTemporalBoundary = currentGroupBounds != nil
            && ChordInkSequentialTimingPolicy.supportsChordBoundary(timeGapFromCurrentGroup)
        let maximumLag: Double
        if hasTemporalBoundary {
            maximumLag = max(rootSizedModifierLookalikeMaximumLag, 0.14)
        } else if hasRootSizedModifierLookalikeOverride {
            maximumLag = rootSizedModifierLookalikeMaximumLag
        } else {
            maximumLag = 0.06
        }
        guard rootCandidate.confidence + maximumLag >= bestConfidence else {
            return nil
        }

        if let suffixCandidate = candidates.first(where: { candidate in
            suffixAndModifierTexts.contains(candidate.text)
        }),
           suffixCandidate.confidence >= rootCandidate.confidence + 0.10,
           !hasRootSizedModifierLookalikeOverride,
           !hasTemporalBoundary {
            return nil
        }

        return ChordInkSequentialRootStartEvidence(
            text: rootCandidate.text,
            confidence: rootCandidate.confidence,
            wasModifierLed: suffixLeads
        )
    }

    private static func isDetachedFromAccumulatedChord(
        _ bounds: InkBounds,
        accumulatedBounds: InkBounds
    ) -> Bool {
        let referenceHeight = max(accumulatedBounds.height, bounds.height, 1)
        return accumulatedBounds.horizontalGap(to: bounds) >= max(17, referenceHeight * 0.18)
    }

    private static func isHalfDiminishedQualityConstruction(
        _ cluster: InkCluster
    ) -> Bool {
        guard cluster.strokes.count == 2 else {
            return false
        }

        return cluster.strokes.contains(where: \.isDiminishedCircleConstructionCandidate)
            && cluster.strokes.contains(where: \.isHalfDiminishedSlashConstructionCandidate)
    }

    private static func hasCloseBoundarySymbolicSuffixPressure(
        in candidates: [GlyphCandidate],
        rootCandidate: GlyphCandidate
    ) -> Bool {
        candidates.contains { candidate in
            closeBoundarySymbolicSuffixTexts.contains(candidate.text)
                && candidate.confidence >= 0.45
                && candidate.confidence + 0.25 >= rootCandidate.confidence
        }
    }

    static func isDetachedRootSizedGlyph(
        _ bounds: InkBounds,
        from currentGroupBounds: InkBounds,
        rootBounds: InkBounds? = nil
    ) -> Bool {
        isRootSequenceBoundarySizedGlyph(
            bounds,
            from: currentGroupBounds,
            rootBounds: rootBounds,
            minimumHorizontalGap: 16,
            minimumCenterAdvance: 18,
            heightRatioFloor: 0.55,
            widthRatioFloor: 0.18,
            heightGapScale: 0.30,
            widthAdvanceScale: 0.45
        )
    }

    static func isRootSequenceBoundarySizedGlyph(
        _ bounds: InkBounds,
        from currentGroupBounds: InkBounds,
        rootBounds: InkBounds? = nil
    ) -> Bool {
        isRootSequenceBoundarySizedGlyph(
            bounds,
            from: currentGroupBounds,
            rootBounds: rootBounds,
            minimumHorizontalGap: 10,
            minimumCenterAdvance: 14,
            heightRatioFloor: 0.55,
            widthRatioFloor: 0.18,
            heightGapScale: 0.22,
            widthAdvanceScale: 0.35
        )
    }

    private static func isTemporalRootSequenceBoundarySizedGlyph(
        _ bounds: InkBounds,
        from currentGroupBounds: InkBounds,
        rootBounds: InkBounds? = nil
    ) -> Bool {
        isRootSequenceBoundarySizedGlyph(
            bounds,
            from: currentGroupBounds,
            rootBounds: rootBounds,
            minimumHorizontalGap: 4,
            minimumCenterAdvance: 9,
            heightRatioFloor: 0.48,
            widthRatioFloor: 0.14,
            heightGapScale: 0.08,
            widthAdvanceScale: 0.20
        )
    }

    private static func isRootSequenceBoundarySizedGlyph(
        _ bounds: InkBounds,
        from currentGroupBounds: InkBounds,
        rootBounds: InkBounds?,
        minimumHorizontalGap: Double,
        minimumCenterAdvance: Double,
        heightRatioFloor: Double,
        widthRatioFloor: Double,
        heightGapScale: Double,
        widthAdvanceScale: Double
    ) -> Bool {
        let horizontalGap = currentGroupBounds.horizontalGap(to: bounds)
        let referenceHeight = max(currentGroupBounds.height, bounds.height, 1)
        // Suffix width must not shrink a following root's letter-size evidence.
        // Keep the complete chord edge for spacing, and its root for width.
        let referenceWidth = max(rootBounds?.width ?? currentGroupBounds.width, bounds.width, 1)
        let centerAdvance = bounds.recognitionMidX - currentGroupBounds.recognitionMidX
        let heightRatio = bounds.height / referenceHeight
        let widthRatio = bounds.width / referenceWidth
        let rootSized = heightRatio >= heightRatioFloor && widthRatio >= widthRatioFloor

        return rootSized
            && horizontalGap >= max(minimumHorizontalGap, referenceHeight * heightGapScale)
            && centerAdvance >= max(minimumCenterAdvance, referenceWidth * widthAdvanceScale)
    }

    private static func isInitialRootSizedModifierLookalike(_ bounds: InkBounds) -> Bool {
        bounds.width >= 18
            && bounds.height >= 18
            && bounds.recognitionArea >= 360
    }

    private static func hasCurvedInitialRootOverride(
        rootCandidate: GlyphCandidate,
        cluster: InkCluster
    ) -> Bool {
        guard ["C", "G"].contains(rootCandidate.text),
              rootCandidate.source == .heuristic,
              rootCandidate.confidence >= 0.94,
              cluster.strokes.count == 1,
              let stroke = cluster.strokes.first else {
            return false
        }

        return stroke.points.count >= 8
            && stroke.endpointClosureRatio <= 0.90
            && isInitialRootSizedModifierLookalike(cluster.bounds)
    }

    private static func hasRootSizedModifierLookalikeOverride(
        rootCandidate: GlyphCandidate,
        bestCandidate: GlyphCandidate?,
        cluster: InkCluster,
        currentGroupBounds: InkBounds?,
        currentRootBounds: InkBounds?
    ) -> Bool {
        guard let bestCandidate,
              bestCandidate.text != rootCandidate.text,
              bestCandidate.confidence > rootCandidate.confidence,
              (rootSizedModifierLookalikeOverrideTexts.contains(bestCandidate.text)
                  || currentGroupBounds != nil
                      && detachedOnlyRootSizedModifierLookalikeOverrideTexts.contains(bestCandidate.text)),
              rootCandidate.source == .heuristic,
              rootCandidate.confidence >= rootSizedModifierLookalikeMinimumConfidence,
              rootCandidate.confidence + rootSizedModifierLookalikeMaximumLag >= bestCandidate.confidence else {
            return false
        }

        if let currentGroupBounds {
            return isRootSequenceBoundarySizedGlyph(
                cluster.bounds, from: currentGroupBounds, rootBounds: currentRootBounds
            )
        }

        return isInitialRootSizedModifierLookalike(cluster.bounds)
    }

    static func isModifierLed(
        candidates: [GlyphCandidate],
        excludingRootText rootText: String
    ) -> Bool {
        candidates.first.map { candidate in
            suffixAndModifierTexts.contains(candidate.text)
                && candidate.text != rootText
        } ?? false
    }
}

private enum ChordInkSequentialTimingPolicy {
    /// A captured six-chord device row contained within-chord pauses up to
    /// 0.897 seconds and between-chord pauses no shorter than 2.472 seconds.
    /// Keep a neutral band between continuation and boundary evidence. Timing
    /// can support geometry and glyph evidence, but never invent a root alone.
    private static let minimumChordBoundaryGap: TimeInterval = 1.25
    private static let minimumHardChordBoundaryGap: TimeInterval = 1.75
    private static let maximumModifierContinuationGap: TimeInterval = 1.10

    static func supportsChordBoundary(_ gap: TimeInterval?) -> Bool {
        gap.map { $0 >= minimumChordBoundaryGap } ?? false
    }

    static func supportsModifierContinuation(_ gap: TimeInterval?) -> Bool {
        gap.map { $0 >= 0 && $0 <= maximumModifierContinuationGap } ?? false
    }

    static func supportsHardChordBoundary(_ gap: TimeInterval?) -> Bool {
        gap.map { $0 >= minimumHardChordBoundaryGap } ?? false
    }
}

private struct SequentialIndexedStroke: Hashable {
    var index: Int
    var stroke: InkStroke
}

private struct SequentialGlyph: Hashable {
    var strokeIndices: [Int]
    var indexedStrokes: [SequentialIndexedStroke]
    var cluster: InkCluster
    var candidates: [GlyphCandidate]
    var timelineStartTimeOffset: TimeInterval? {
        let offsets = cluster.strokes.compactMap(\.timelineStartTimeOffset)
        guard offsets.count == cluster.strokes.count else {
            return nil
        }

        return offsets.min()
    }

    var timelineEndTimeOffset: TimeInterval? {
        let offsets = cluster.strokes.compactMap(\.timelineEndTimeOffset)
        guard offsets.count == cluster.strokes.count else {
            return nil
        }

        return offsets.max()
    }

    func timeGap(before laterGlyph: SequentialGlyph) -> TimeInterval? {
        guard let end = timelineEndTimeOffset,
              let start = laterGlyph.timelineStartTimeOffset,
              start >= end else {
            return nil
        }

        return start - end
    }

    var isSlashSeparator: Bool {
        if cluster.strokes.count == 1,
           cluster.strokes.first?.isLooseSlashBassSeparatorCandidate == true {
            return true
        }

        return candidates.first?.text == "/"
            && (candidates.first?.confidence ?? 0) >= 0.60
    }

    var canBeginInitialRootConstruction: Bool {
        cluster.bounds.height >= 12
            && cluster.bounds.recognitionArea >= 18
            && (hasRootConstructionFragment || hasAmbiguousRootPressure)
    }

    func canBeginDetachedRootConstruction(from currentGroupBounds: InkBounds) -> Bool {
        guard !isSlashSeparator else {
            return false
        }

        let bounds = cluster.bounds
        let referenceHeight = max(currentGroupBounds.height, bounds.height, 1)
        let referenceWidth = max(currentGroupBounds.width, bounds.width, 1)
        let horizontalGap = currentGroupBounds.horizontalGap(to: bounds)
        let centerAdvance = bounds.recognitionMidX - currentGroupBounds.recognitionMidX

        guard horizontalGap >= max(10, referenceHeight * 0.22),
              centerAdvance >= max(14, referenceWidth * 0.35),
              bounds.height >= 12,
              bounds.recognitionArea >= 18 else {
            return false
        }

        return hasRootConstructionFragment || hasAmbiguousRootPressure
    }

    func canContinueDetachedRootConstruction(after previousGlyph: SequentialGlyph?) -> Bool {
        guard let previousGlyph,
              !isSlashSeparator else {
            return false
        }

        let previousBounds = previousGlyph.cluster.bounds
        let bounds = cluster.bounds
        let combinedBounds = InkBounds.enclosing([previousBounds, bounds])
        let horizontalGap = previousBounds.horizontalGap(to: bounds)
        let verticalMiss = previousBounds.verticalMiss(to: bounds)
        let horizontalOverlap = previousBounds.horizontalOverlap(with: bounds)
        let narrowerWidth = max(min(previousBounds.width, bounds.width), 1)

        return combinedBounds.width <= 58
            && combinedBounds.height <= 64
            && verticalMiss <= max(8, combinedBounds.height * 0.28)
            && (horizontalGap <= max(8, combinedBounds.height * 0.16)
                || horizontalOverlap >= narrowerWidth * 0.25)
            && (hasRootConstructionFragment || hasAmbiguousRootPressure)
    }

    private var hasRootConstructionFragment: Bool {
        hasRootConstructionVerticalStem
            || hasRootConstructionBody
            || hasRootConstructionBar
    }

    private var hasRootConstructionBar: Bool {
        cluster.strokes.contains { stroke in
            stroke.bounds.width >= 5
                && stroke.aspectRatio >= 1.6
                && stroke.straightness >= 0.50
                && stroke.horizontalAngleMagnitude <= 45
        }
    }

    private var hasRootConstructionVerticalStem: Bool {
        cluster.strokes.contains { stroke in
            stroke.bounds.height >= 14
                && stroke.bounds.height / max(stroke.bounds.width, 1) >= 1.90
                && stroke.straightness >= 0.50
                && abs(abs(stroke.angleDegrees) - 90) <= 32
        }
    }

    private var hasRootConstructionBody: Bool {
        cluster.bounds.height >= 14
            && cluster.bounds.width >= 8
            && cluster.bounds.recognitionArea >= 140
    }

    private var hasAmbiguousRootPressure: Bool {
        let rootCandidates = candidates.filter { candidate in
            ["A", "B", "C", "D", "E", "F", "G"].contains(candidate.text)
        }
        guard let bestRootConfidence = rootCandidates.map(\.confidence).max(),
              bestRootConfidence >= 0.46 else {
            return false
        }

        let bestCandidateConfidence = candidates.first?.confidence ?? 0
        return bestRootConfidence + 0.10 >= bestCandidateConfidence
    }
}

private struct WorkingGroup: Hashable {
    var strokeIndices: [Int]
    var bounds: InkBounds
    var rootBounds: InkBounds
    var anchorReason: ChordInkSequentialGroupAnchorReason
    var rootText: String?
    var rootConfidence: Double?
    var rootWasModifierLed: Bool
    var timelineEndTimeOffset: TimeInterval?

    init(
        glyph: SequentialGlyph,
        anchorReason: ChordInkSequentialGroupAnchorReason,
        rootText: String?,
        rootConfidence: Double?,
        rootWasModifierLed: Bool
    ) {
        strokeIndices = glyph.strokeIndices
        bounds = glyph.cluster.bounds
        rootBounds = glyph.cluster.bounds
        self.anchorReason = anchorReason
        self.rootText = rootText
        self.rootConfidence = rootConfidence
        self.rootWasModifierLed = rootWasModifierLed
        timelineEndTimeOffset = glyph.timelineEndTimeOffset
    }

    mutating func append(_ glyph: SequentialGlyph) {
        strokeIndices.append(contentsOf: glyph.strokeIndices)
        bounds = bounds.union(glyph.cluster.bounds)
        if let glyphEnd = glyph.timelineEndTimeOffset {
            timelineEndTimeOffset = max(timelineEndTimeOffset ?? glyphEnd, glyphEnd)
        }
    }

    func timeGap(before glyph: SequentialGlyph) -> TimeInterval? {
        guard let timelineEndTimeOffset,
              let glyphStart = glyph.timelineStartTimeOffset,
              glyphStart >= timelineEndTimeOffset else {
            return nil
        }

        return glyphStart - timelineEndTimeOffset
    }
}
