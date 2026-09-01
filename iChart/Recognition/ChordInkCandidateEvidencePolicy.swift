import Foundation

struct ChordInkCandidateEvidencePolicy {
    private static let rootTexts: Set<String> = ["A", "B", "C", "D", "E", "F", "G"]
    private static let rootAccidentalVetoTexts: Set<String> = ["b", "#"]
    private static let detachedSuffixVetoTexts: Set<String> = ["b", "#", "m", "-", "6"]
    private static let hardSlashConflictTexts: Set<String> = ["△", "°", "ø", "7"]
    private static let rootPressureMinimumConfidence = 0.90
    private static let rootPressureMaximumLag = 0.08
    private static let triangleOwnershipMinimumConfidence = 0.55
    private static let angularTriangleOwnershipMinimumConfidence = 0.40

    func allows(
        _ candidate: ChordInkCandidate,
        candidateColumns: [[GlyphCandidate]],
        clusters: [InkCluster],
        roleContext: ChordInkTheoryRoleContext
    ) -> Bool {
        guard candidate.glyphCandidates.count <= candidateColumns.count,
              candidate.glyphCandidates.count <= clusters.count else {
            return true
        }

        guard allowsRootAccidentalEvidence(
            candidate,
            candidateColumns: candidateColumns,
            clusters: clusters
        ) else {
            return false
        }

        guard !usesDetachedRootPressureAsAttachedDescriptor(
            candidate,
            candidateColumns: candidateColumns,
            clusters: clusters
        ) else {
            return false
        }

        guard let symbol = try? ChordSymbolParser.parse(candidate.text) else {
            return true
        }

        guard symbol.kind == .rooted else {
            return true
        }

        if symbol.slashBass != nil,
           !hasOwnedSlashBassEvidence(
               candidate,
               symbol: symbol,
               candidateColumns: candidateColumns,
               clusters: clusters,
               roleContext: roleContext
           ) {
            return false
        }

        if isDiminishedQuality(symbol),
           !hasOwnedDiminishedQualityEvidence(
               candidate,
               candidateColumns: candidateColumns,
               clusters: clusters
           ) {
            return false
        }

        if isHalfDiminishedQuality(symbol),
           !hasOwnedHalfDiminishedQualityEvidence(
               candidate,
               candidateColumns: candidateColumns,
               clusters: clusters
           ) {
            return false
        }

        if isMajorTriangleQuality(symbol),
           !hasOwnedMajorTriangleQualityEvidence(
               candidate,
               candidateColumns: candidateColumns,
               clusters: clusters
           ) {
            return false
        }

        if isPlainSixthExtension(symbol),
           !hasOwnedPlainSixthExtensionEvidence(
               candidate,
               candidateColumns: candidateColumns
           ) {
            return false
        }

        return true
    }

    private func allowsRootAccidentalEvidence(
        _ candidate: ChordInkCandidate,
        candidateColumns: [[GlyphCandidate]],
        clusters: [InkCluster]
    ) -> Bool {
        guard let symbol = try? ChordSymbolParser.parse(candidate.text),
              symbol.kind == .rooted,
              symbol.accidental != .natural else {
            return true
        }

        guard candidate.glyphCandidates.indices.contains(1),
              candidateColumns.indices.contains(1),
              clusters.indices.contains(1) else {
            return false
        }

        let accidentalGlyph = candidate.glyphCandidates[1]
        if accidentalGlyph.text == "B" {
            return false
        }

        guard Self.rootAccidentalVetoTexts.contains(accidentalGlyph.text) else {
            return true
        }

        return !hasDetachedRootPressure(
            in: candidateColumns[1],
            selectedGlyph: accidentalGlyph,
            cluster: clusters[1],
            prefixBounds: clusters[0].bounds
        )
    }

    private func usesDetachedRootPressureAsAttachedDescriptor(
        _ candidate: ChordInkCandidate,
        candidateColumns: [[GlyphCandidate]],
        clusters: [InkCluster]
    ) -> Bool {
        guard candidate.glyphCandidates.count >= 2,
              let symbol = try? ChordSymbolParser.parse(candidate.text),
              symbol.kind == .rooted else {
            return false
        }

        for index in candidate.glyphCandidates.indices.dropFirst() {
            let glyph = candidate.glyphCandidates[index]
            guard Self.detachedSuffixVetoTexts.contains(glyph.text),
                  !isSlashBassRole(at: index, in: candidate.glyphCandidates),
                  !isProtectedChordSuffixRole(at: index, in: candidate.glyphCandidates),
                  candidateColumns.indices.contains(index),
                  clusters.indices.contains(index) else {
                continue
            }

            let prefixBounds = InkBounds.enclosing(Array(clusters.prefix(index)).map(\.bounds))
            if hasDetachedRootPressure(
                in: candidateColumns[index],
                selectedGlyph: glyph,
                cluster: clusters[index],
                prefixBounds: prefixBounds
            ) {
                return true
            }
        }

        return false
    }

    private func hasDetachedRootPressure(
        in column: [GlyphCandidate],
        selectedGlyph: GlyphCandidate,
        cluster: InkCluster,
        prefixBounds: InkBounds
    ) -> Bool {
        let clusterBounds = cluster.bounds

        guard ChordInkSequentialRootStartDetector.isDetachedRootSizedGlyph(
            clusterBounds,
            from: prefixBounds
        ),
              let rootCandidate = column.first(where: { candidate in
                  Self.rootTexts.contains(candidate.text)
                      && candidate.source == .heuristic
                      && candidate.confidence >= Self.rootPressureMinimumConfidence
              }) else {
            return false
        }

        if rootCandidate.text == "G",
           hasAttachedFlatAccidentalEvidence(
            selectedGlyph: selectedGlyph,
            cluster: cluster,
            prefixBounds: prefixBounds
        ) {
            return false
        }

        let selectedConfidence = column.first { candidate in
            candidate.text == selectedGlyph.text
        }?.confidence ?? selectedGlyph.confidence
        let bestConfidence = column.first?.confidence ?? selectedConfidence

        return rootCandidate.confidence
            + Self.rootPressureMaximumLag
            >= max(bestConfidence, selectedConfidence)
    }

    private func hasAttachedFlatAccidentalEvidence(
        selectedGlyph: GlyphCandidate,
        cluster: InkCluster,
        prefixBounds: InkBounds
    ) -> Bool {
        guard selectedGlyph.text == "b" else {
            return false
        }

        let clusterBounds = cluster.bounds
        let prefixWidth = max(prefixBounds.width, 1)
        let prefixHeight = max(prefixBounds.height, 1)
        let prefixArea = max(prefixBounds.recognitionArea, 1)
        let horizontalGap = prefixBounds.horizontalGap(to: clusterBounds)
        let verticalMiss = prefixBounds.verticalMiss(to: clusterBounds)
        let startsAtPrefixRightEdge = clusterBounds.minX >= prefixBounds.maxX - max(4, prefixWidth * 0.22)
        let closeEnoughToBelongToPrefix = horizontalGap <= max(8, prefixHeight * 0.45)
            && verticalMiss <= max(8, prefixHeight * 0.55)
        let modifierSized = clusterBounds.recognitionArea / prefixArea <= 0.72
            || clusterBounds.width <= prefixWidth * 0.85
        let flatShaped = aspectRatio(of: clusterBounds) <= 0.70
            || clusterBounds.width <= max(16, prefixWidth * 0.55)

        return startsAtPrefixRightEdge
            && closeEnoughToBelongToPrefix
            && modifierSized
            && flatShaped
            && clusterBounds.recognitionMidX > prefixBounds.recognitionMidX
            && hasFlatStrokeEvidence(cluster)
    }

    private func hasFlatStrokeEvidence(_ cluster: InkCluster) -> Bool {
        guard cluster.strokes.count == 1,
              let stroke = cluster.strokes.first,
              let firstPoint = stroke.points.first,
              let lastPoint = stroke.points.last else {
            return false
        }

        let endpointYRatios = [
            stroke.normalizedYRatio(of: firstPoint),
            stroke.normalizedYRatio(of: lastPoint)
        ]
        let endpointPositions = [firstPoint, lastPoint].map { point in
            (
                x: stroke.normalizedXRatio(of: point),
                y: stroke.normalizedYRatio(of: point)
            )
        }
        let leftStemYRatios = stroke.points
            .filter { point in
                stroke.normalizedXRatio(of: point) <= 0.35
            }
            .map(stroke.normalizedYRatio(of:))
        let hasTopEndpointOnStem = endpointPositions.contains { position in
            position.x <= 0.40 && position.y <= 0.35
        }
        let hasReturningBodyEndpoint = endpointPositions.contains { position in
            position.x <= 0.55 && position.y >= 0.45
        }
        let hasOpenLoopBodyEndpoint = stroke.points.count >= 12
            && stroke.bounds.width >= 6
            && stroke.bounds.width <= 18
            && stroke.bounds.height >= 14
            && stroke.bounds.height <= 30
            && stroke.aspectRatio >= 0.35
            && stroke.aspectRatio <= 1.05
            && stroke.straightness >= 0.08
            && stroke.straightness <= 0.36
            && stroke.angleDegrees >= 55
            && stroke.angleDegrees <= 115
            && stroke.endpointClosureRatio >= 0.30
            && stroke.endpointClosureRatio <= 0.82
            && stroke.normalizedYRatio(of: firstPoint) <= 0.35
            && stroke.normalizedYRatio(of: lastPoint) >= 0.42
            && stroke.horizontalDirectionChangeCount >= 1
            && !stroke.looksLikeTriangleReturn
        let hasLeftStemCoverage = (leftStemYRatios.min() ?? 1) <= 0.20
            && (leftStemYRatios.max() ?? 0) >= 0.78
        let hasRightBody = stroke.points.contains { point in
            let xRatio = stroke.normalizedXRatio(of: point)
            let yRatio = stroke.normalizedYRatio(of: point)
            return xRatio >= 0.55
                && yRatio >= 0.35
                && yRatio <= 0.85
        }
        let hasFlatAspect = stroke.aspectRatio <= 0.75 || hasOpenLoopBodyEndpoint

        return stroke.points.count >= 4
            && stroke.bounds.height >= 8
            && hasFlatAspect
            && abs(stroke.angleDegrees) >= 45
            && abs(stroke.angleDegrees) <= 115
            && (endpointYRatios.min() ?? 1) <= 0.35
            && (endpointYRatios.max() ?? 0) >= 0.45
            && hasTopEndpointOnStem
            && (hasReturningBodyEndpoint || hasOpenLoopBodyEndpoint)
            && hasLeftStemCoverage
            && hasRightBody
            && !stroke.hasEarlyTopHorizontalRun
    }

    private func hasOwnedSlashBassEvidence(
        _ candidate: ChordInkCandidate,
        symbol: ChordSymbol,
        candidateColumns: [[GlyphCandidate]],
        clusters: [InkCluster],
        roleContext: ChordInkTheoryRoleContext
    ) -> Bool {
        guard let slashIndex = candidate.glyphCandidates.firstIndex(where: { $0.text == "/" }),
              candidate.glyphCandidates.indices.contains(slashIndex + 1),
              candidateColumns.indices.contains(slashIndex),
              clusters.indices.contains(slashIndex),
              isOwnedSlashSeparator(
                  at: slashIndex,
                  in: candidate,
                  candidateColumns: candidateColumns,
                  clusters: clusters,
                  roleContext: roleContext
              ) else {
            return false
        }

        let bassRootGlyph = candidate.glyphCandidates[slashIndex + 1]
        guard Self.rootTexts.contains(bassRootGlyph.text) else {
            return false
        }

        guard let slashBass = symbol.slashBass,
              let parsedBass = ChordPitch.parse(slashBass),
              bassRootGlyph.text == parsedBass.root.rawValue else {
            return false
        }

        switch parsedBass.accidental {
        case .natural:
            return true
        case .sharp, .flat:
            guard candidate.glyphCandidates.indices.contains(slashIndex + 2) else {
                return false
            }

            return candidate.glyphCandidates[slashIndex + 2].text == parsedBass.accidental.rawValue
        }
    }

    private func isOwnedSlashSeparator(
        at index: Int,
        in candidate: ChordInkCandidate,
        candidateColumns: [[GlyphCandidate]],
        clusters: [InkCluster],
              roleContext: ChordInkTheoryRoleContext
    ) -> Bool {
        let selectedSlash = candidate.glyphCandidates[index]
        guard selectedSlash.text == "/",
              selectedSlash.source != .composer,
              selectedSlash.confidence >= 0.60 else {
            return false
        }

        let cluster = clusters[index]
        if cluster.strokes.contains(where: \.isLooseSlashBassSeparatorCandidate) {
            return true
        }

        let column = candidateColumns[index]
        if hasDominantConflict(
            in: column,
            selected: selectedSlash,
            conflictTexts: Self.hardSlashConflictTexts,
            minimumConflictConfidence: 0.70,
            allowedLag: 0.04
        ) {
            return false
        }

        return selectedSlash.confidence >= 0.85
    }

    private func hasOwnedDiminishedQualityEvidence(
        _ candidate: ChordInkCandidate,
        candidateColumns: [[GlyphCandidate]],
        clusters: [InkCluster]
    ) -> Bool {
        for index in candidate.glyphCandidates.indices {
            let glyph = candidate.glyphCandidates[index]
            guard glyph.text == "°",
                  candidateColumns.indices.contains(index),
                  clusters.indices.contains(index),
                  glyph.confidence >= 0.55 else {
                continue
            }

            if hasTriangleOwnershipConflict(
                in: candidateColumns[index],
                selected: glyph,
                cluster: clusters[index]
            ) {
                return false
            }

            return true
        }

        return false
    }

    private func hasOwnedHalfDiminishedQualityEvidence(
        _ candidate: ChordInkCandidate,
        candidateColumns: [[GlyphCandidate]],
        clusters: [InkCluster]
    ) -> Bool {
        if hasMinorSevenFlatFiveEvidence(candidate) {
            return true
        }

        for index in candidate.glyphCandidates.indices {
            let glyph = candidate.glyphCandidates[index]
            guard glyph.text == "ø",
                  candidateColumns.indices.contains(index),
                  clusters.indices.contains(index),
                  glyph.confidence >= 0.55 else {
                continue
            }

            if hasTriangleOwnershipConflict(
                in: candidateColumns[index],
                selected: glyph,
                cluster: clusters[index]
            ) {
                return false
            }

            return true
        }

        return false
    }

    private func hasOwnedMajorTriangleQualityEvidence(
        _ candidate: ChordInkCandidate,
        candidateColumns: [[GlyphCandidate]],
        clusters: [InkCluster]
    ) -> Bool {
        for index in candidate.glyphCandidates.indices {
            let glyph = candidate.glyphCandidates[index]
            guard glyph.text == "△",
                  candidateColumns.indices.contains(index),
                  clusters.indices.contains(index),
                  glyph.confidence >= 0.55 else {
                continue
            }

            if hasStrongerRoundQualityConflict(
                in: candidateColumns[index],
                selected: glyph
            ),
               !hasAngularMajorTriangleEvidence(clusters[index]) {
                return false
            }

            return true
        }

        return false
    }

    private func hasOwnedPlainSixthExtensionEvidence(
        _ candidate: ChordInkCandidate,
        candidateColumns: [[GlyphCandidate]]
    ) -> Bool {
        for index in candidate.glyphCandidates.indices {
            let glyph = candidate.glyphCandidates[index]
            guard glyph.text == "6",
                  candidateColumns.indices.contains(index),
                  glyph.confidence >= 0.55 else {
                continue
            }

            if hasMuchStrongerQualityConflict(
                in: candidateColumns[index],
                selected: glyph
            ) {
                return false
            }

            return true
        }

        return false
    }

    private func hasMinorSevenFlatFiveEvidence(_ candidate: ChordInkCandidate) -> Bool {
        let glyphTexts = candidate.glyphCandidates.map(\.text)
        guard glyphTexts.count >= 5 else {
            return false
        }

        for index in glyphTexts.indices.dropFirst() where glyphTexts[index] == "-" || glyphTexts[index] == "m" {
            guard glyphTexts.indices.contains(index + 3),
                  glyphTexts[index + 1] == "7",
                  glyphTexts[index + 2] == "b",
                  glyphTexts[index + 3] == "5" else {
                continue
            }

            return true
        }

        return false
    }

    private func hasTriangleOwnershipConflict(
        in column: [GlyphCandidate],
        selected: GlyphCandidate,
        cluster: InkCluster
    ) -> Bool {
        let selectedConfidence = column.first { candidate in
            candidate.text == selected.text
        }?.confidence ?? selected.confidence

        let hasOpenHandwrittenTriangleEvidence = hasOpenHandwrittenTriangleEvidence(cluster)
        let hasAngularTriangleEvidence = hasAngularMajorTriangleEvidence(cluster)
        let minimumTriangleConfidence = hasOpenHandwrittenTriangleEvidence
            ? Self.angularTriangleOwnershipMinimumConfidence
            : Self.triangleOwnershipMinimumConfidence

        return column.contains { candidate in
            candidate.text == "△"
                && candidate.confidence >= minimumTriangleConfidence
                && (candidate.confidence > selectedConfidence || hasAngularTriangleEvidence)
        }
    }

    private func hasAngularMajorTriangleEvidence(_ cluster: InkCluster) -> Bool {
        guard cluster.bounds.width >= 7,
              cluster.bounds.height >= 10,
              aspectRatio(of: cluster.bounds) >= 0.30,
              aspectRatio(of: cluster.bounds) <= 1.80 else {
            return false
        }

        if cluster.strokes.count == 1,
           let stroke = cluster.strokes.first {
            return hasSingleStrokeTriangleEvidence(stroke)
        }

        let diagonalStrokes = cluster.strokes.filter { stroke in
            stroke.bounds.width >= 4
                && stroke.bounds.height >= 4
                && stroke.straightness >= 0.50
                && stroke.diagonalAngleMagnitude >= 24
                && stroke.diagonalAngleMagnitude <= 78
        }
        guard diagonalStrokes.count >= 2 else {
            return false
        }

        let hasLeftSide = diagonalStrokes.contains { stroke in
            let firstPoint = stroke.points.first ?? InkPoint(x: 0, y: 0, timeOffset: nil)
            let lastPoint = stroke.points.last ?? firstPoint
            return (lastPoint.x - firstPoint.x) * (lastPoint.y - firstPoint.y) < 0
        }
        let hasRightSide = diagonalStrokes.contains { stroke in
            let firstPoint = stroke.points.first ?? InkPoint(x: 0, y: 0, timeOffset: nil)
            let lastPoint = stroke.points.last ?? firstPoint
            return (lastPoint.x - firstPoint.x) * (lastPoint.y - firstPoint.y) > 0
        }
        guard hasLeftSide && hasRightSide else {
            return false
        }

        let hasBaseStroke = cluster.strokes.contains { stroke in
            stroke.bounds.width >= cluster.bounds.width * 0.45
                && stroke.straightness >= 0.50
                && stroke.horizontalAngleMagnitude <= 28
                && stroke.bounds.recognitionMidY >= cluster.bounds.minY + cluster.bounds.height * 0.50
        }

        return hasBaseStroke || hasTriangleCornerCoverage(cluster)
    }

    private func hasSingleStrokeTriangleEvidence(_ stroke: InkStroke) -> Bool {
        guard stroke.bounds.width >= 7,
              stroke.bounds.height >= 10,
              stroke.aspectRatio >= 0.30,
              stroke.aspectRatio <= 1.45 else {
            return false
        }

        if hasOpenHandwrittenTriangleEvidence(stroke) {
            return true
        }

        guard !stroke.isDiminishedCircleConstructionCandidate else {
            return false
        }

        let closedAngularTriangle = stroke.points.count >= 4
            && stroke.endpointClosureRatio <= 0.25
            && hasTriangleCornerCoverage(InkCluster(strokes: [stroke]))

        return closedAngularTriangle
    }

    private func hasOpenHandwrittenTriangleEvidence(_ cluster: InkCluster) -> Bool {
        guard cluster.strokes.count == 1,
              let stroke = cluster.strokes.first else {
            return false
        }

        return hasOpenHandwrittenTriangleEvidence(stroke)
    }

    private func hasOpenHandwrittenTriangleEvidence(_ stroke: InkStroke) -> Bool {
        stroke.bounds.width >= 7
            && stroke.bounds.height >= 10
            && stroke.aspectRatio >= 0.30
            && stroke.aspectRatio <= 1.45
            && stroke.points.count >= 8
            && stroke.hasLowerBodyThenUpperPeakReturn
            && stroke.endpointClosureRatio >= 0.40
            && stroke.straightness <= 0.48
            && stroke.normalizedMaxY >= 0.82
            && hasTriangleCornerCoverage(InkCluster(strokes: [stroke]))
    }

    private func hasTriangleCornerCoverage(_ cluster: InkCluster) -> Bool {
        let points = cluster.strokes.flatMap(\.points)
        guard !points.isEmpty else {
            return false
        }

        let hasTopPeak = points.contains { point in
            let xRatio = normalizedXRatio(of: point, in: cluster.bounds)
            let yRatio = normalizedYRatio(of: point, in: cluster.bounds)
            return xRatio >= 0.25
                && xRatio <= 0.75
                && yRatio <= 0.32
        }
        let hasLowerLeft = points.contains { point in
            normalizedXRatio(of: point, in: cluster.bounds) <= 0.28
                && normalizedYRatio(of: point, in: cluster.bounds) >= 0.58
        }
        let hasLowerRight = points.contains { point in
            normalizedXRatio(of: point, in: cluster.bounds) >= 0.72
                && normalizedYRatio(of: point, in: cluster.bounds) >= 0.58
        }

        return hasTopPeak && hasLowerLeft && hasLowerRight
    }

    private func normalizedXRatio(of point: InkPoint, in bounds: InkBounds) -> Double {
        (point.x - bounds.minX) / max(bounds.width, 1)
    }

    private func normalizedYRatio(of point: InkPoint, in bounds: InkBounds) -> Double {
        (point.y - bounds.minY) / max(bounds.height, 1)
    }

    private func aspectRatio(of bounds: InkBounds) -> Double {
        max(bounds.width, 1) / max(bounds.height, 1)
    }

    private func hasStrongerRoundQualityConflict(
        in column: [GlyphCandidate],
        selected: GlyphCandidate
    ) -> Bool {
        let selectedConfidence = column.first { candidate in
            candidate.text == selected.text
        }?.confidence ?? selected.confidence

        return column.contains { candidate in
            (candidate.text == "°" || candidate.text == "ø")
                && candidate.confidence >= 0.55
                && candidate.confidence > selectedConfidence
        }
    }

    private func hasMuchStrongerQualityConflict(
        in column: [GlyphCandidate],
        selected: GlyphCandidate
    ) -> Bool {
        let selectedConfidence = column.first { candidate in
            candidate.text == selected.text
        }?.confidence ?? selected.confidence

        return column.contains { candidate in
            (candidate.text == "△" || candidate.text == "°" || candidate.text == "ø")
                && candidate.confidence >= selectedConfidence + 0.20
        }
    }

    private func hasDominantConflict(
        in column: [GlyphCandidate],
        selected: GlyphCandidate,
        conflictTexts: Set<String>,
        minimumConflictConfidence: Double,
        allowedLag: Double
    ) -> Bool {
        let selectedConfidence = column.first { candidate in
            candidate.text == selected.text
        }?.confidence ?? selected.confidence

        return column.contains { candidate in
            conflictTexts.contains(candidate.text)
                && candidate.confidence >= minimumConflictConfidence
                && candidate.confidence + allowedLag >= selectedConfidence
        }
    }

    private func isDiminishedQuality(_ symbol: ChordSymbol) -> Bool {
        symbol.quality == "°"
    }

    private func isHalfDiminishedQuality(_ symbol: ChordSymbol) -> Bool {
        symbol.quality == "ø"
    }

    private func isMajorTriangleQuality(_ symbol: ChordSymbol) -> Bool {
        symbol.quality == "△" || symbol.quality == "-△"
    }

    private func isPlainSixthExtension(_ symbol: ChordSymbol) -> Bool {
        symbol.quality.isEmpty
            && symbol.extensions == ["6"]
            && symbol.alterations.isEmpty
    }

    private func isProtectedChordSuffixRole(
        at index: Int,
        in glyphCandidates: [GlyphCandidate]
    ) -> Bool {
        if (glyphCandidates[index].text == "b" || glyphCandidates[index].text == "#"),
           hasExtensionBefore(index, in: glyphCandidates) {
            return true
        }

        if hasRootAccidentalBefore(index, in: glyphCandidates) {
            return true
        }

        if glyphCandidates[index].text == "6",
           hasQualityBefore(index, in: glyphCandidates) {
            return true
        }

        return false
    }

    private func hasExtensionBefore(
        _ index: Int,
        in glyphCandidates: [GlyphCandidate]
    ) -> Bool {
        guard index > 1 else {
            return false
        }

        return glyphCandidates[1..<index].contains { glyph in
            glyph.text == "6"
                || glyph.text == "7"
                || glyph.text == "9"
                || glyph.text == "1"
                || glyph.text == "3"
        }
    }

    private func hasRootAccidentalBefore(
        _ index: Int,
        in glyphCandidates: [GlyphCandidate]
    ) -> Bool {
        guard index > 1 else {
            return false
        }

        return glyphCandidates[1..<index].contains { glyph in
            glyph.text == "b" || glyph.text == "#"
        }
    }

    private func hasQualityBefore(
        _ index: Int,
        in glyphCandidates: [GlyphCandidate]
    ) -> Bool {
        guard index > 1 else {
            return false
        }

        return glyphCandidates[1..<index].contains { glyph in
            glyph.text == "-" || glyph.text == "m"
        }
    }

    private func isSlashBassRole(
        at index: Int,
        in glyphCandidates: [GlyphCandidate]
    ) -> Bool {
        if index > 0,
           glyphCandidates[index - 1].text == "/" {
            return true
        }

        if index > 1,
           glyphCandidates[index - 2].text == "/",
           glyphCandidates[index - 1].text.count == 1,
           glyphCandidates[index - 1].text.first.map({ "ABCDEFG".contains($0) }) == true,
           glyphCandidates[index].text == "b" || glyphCandidates[index].text == "#" {
            return true
        }

        return false
    }
}
