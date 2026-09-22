import Foundation

enum ChordInkLearnedDecodeError: Error, Equatable, Sendable {
    case outputContractVersionMismatch(expected: String, actual: String)
    case labelSetMismatch(head: String, expected: [String], actual: [String])
    case nonFiniteLogit(head: String, label: String)
}

struct ChordInkLearnedDecodedCandidate: Equatable, Sendable {
    let notation: ChordNotation

    /// Sum of per-head log-softmax values before grammar survivors are
    /// renormalized. This is deliberately not exposed as a probability or a
    /// calibrated confidence.
    let rawJointLogScore: Double
}

struct ChordInkLearnedDecodeResult: Equatable, Sendable {
    let candidates: [ChordInkLearnedDecodedCandidate]
    let noReadLogScore: Double
}

/// Deterministic factor decoder that admits only values accepted by the typed
/// chord grammar. Invalid combinations keep their probability mass in their
/// source heads, so grammar pruning cannot inflate survivor confidence.
struct ChordInkCompositionalDecoder {
    private struct Ranked<Value> {
        let value: Value
        let score: Double
        let tieKey: String
    }

    private struct Suffix: Sendable {
        let form: ChordNotation.Form
        let extensionTone: ChordNotation.Extension?
        let alterations: [ChordNotation.Alteration]
    }

    func decode(
        _ output: ChordInkLearnedFactorOutput,
        maximumCandidateCount: Int = 3
    ) throws -> ChordInkLearnedDecodeResult {
        guard output.contractVersion == ChordInkLearnedOutputContract.version else {
            throw ChordInkLearnedDecodeError.outputContractVersionMismatch(
                expected: ChordInkLearnedOutputContract.version,
                actual: output.contractVersion
            )
        }
        let validity = try normalizedLogScores(
            output.validity,
            labels: ChordInkValidityFactorLabel.allCases,
            head: ChordInkLearnedOutputContract.validityHeadName,
            labelName: \.rawValue
        )
        let kind = try normalizedLogScores(
            output.kind,
            labels: ChordInkKindFactorLabel.allCases,
            head: ChordInkLearnedOutputContract.kindHeadName,
            labelName: \.rawValue
        )
        let rootLetter = try normalizedLogScores(
            output.rootLetter,
            labels: ChordNotation.Letter.allCases,
            head: ChordInkLearnedOutputContract.rootLetterHeadName,
            labelName: \.rawValue
        )
        let rootAccidental = try normalizedLogScores(
            output.rootAccidental,
            labels: ChordInkAccidentalFactorLabel.allCases,
            head: ChordInkLearnedOutputContract.rootAccidentalHeadName,
            labelName: \.rawValue
        )
        let quality = try normalizedLogScores(
            output.quality,
            labels: ChordNotation.Form.allCases,
            head: ChordInkLearnedOutputContract.qualityHeadName,
            labelName: \.rawValue
        )
        let extensionTone = try normalizedLogScores(
            output.extensionTone,
            labels: ChordInkExtensionFactorLabel.allCases,
            head: ChordInkLearnedOutputContract.extensionHeadName,
            labelName: \.rawValue
        )
        let alterations = try validatedBernoulliLogits(
            output.alterations,
            labels: ChordNotation.Alteration.allCases,
            head: ChordInkLearnedOutputContract.alterationHeadName,
            labelName: \.rawValue
        )
        let slashPresence = try normalizedLogScores(
            output.slashPresence,
            labels: ChordInkSlashPresenceFactorLabel.allCases,
            head: ChordInkLearnedOutputContract.slashPresenceHeadName,
            labelName: \.rawValue
        )
        let bassLetter = try normalizedLogScores(
            output.slashBassLetter,
            labels: ChordNotation.Letter.allCases,
            head: ChordInkLearnedOutputContract.slashBassLetterHeadName,
            labelName: \.rawValue
        )
        let bassAccidental = try normalizedLogScores(
            output.slashBassAccidental,
            labels: ChordInkAccidentalFactorLabel.allCases,
            head: ChordInkLearnedOutputContract.slashBassAccidentalHeadName,
            labelName: \.rawValue
        )

        let requestedCount = max(0, min(3, maximumCandidateCount))
        let noReadScore = validity[.noRead]!
        guard requestedCount > 0 else {
            return ChordInkLearnedDecodeResult(candidates: [], noReadLogScore: noReadScore)
        }

        let roots = topRootChoices(letter: rootLetter, accidental: rootAccidental)
        let suffixes = topSuffixChoices(
            quality: quality,
            extensionTone: extensionTone,
            alterations: alterations
        )
        let slashChoices = topSlashChoices(
            presence: slashPresence,
            letter: bassLetter,
            accidental: bassAccidental
        )

        // For three requested results, retaining the best three values in each
        // independent factor group is exact: a fourth-ranked group member has
        // at least three strictly better (or deterministically tie-broken)
        // substitutions with identical remaining factors.
        var ranked: [Ranked<ChordNotation>] = []
        let notationBaseScore = validity[.notation]!

        let repeatNotation = ChordNotation.chordRepeat
        retain(
            Ranked(
                value: repeatNotation,
                score: notationBaseScore + kind[.chordRepeat]!,
                tieKey: repeatNotation.canonicalDisplay
            ),
            in: &ranked,
            limit: requestedCount
        )

        for root in roots {
            for suffix in suffixes {
                for slash in slashChoices {
                    guard let rooted = try? ChordNotation.Rooted(
                        root: root.value,
                        form: suffix.value.form,
                        extensionTone: suffix.value.extensionTone,
                        alterations: suffix.value.alterations,
                        slashBass: slash.value
                    ) else {
                        continue
                    }
                    let notation = ChordNotation.rooted(rooted)
                    guard isAcceptedByTypedGrammar(notation) else { continue }

                    retain(
                        Ranked(
                            value: notation,
                            score: notationBaseScore
                                + kind[.rooted]!
                                + root.score
                                + suffix.score
                                + slash.score,
                            tieKey: notation.canonicalDisplay
                        ),
                        in: &ranked,
                        limit: requestedCount
                    )
                }
            }
        }

        return ChordInkLearnedDecodeResult(
            candidates: ranked.map {
                ChordInkLearnedDecodedCandidate(
                    notation: $0.value,
                    rawJointLogScore: $0.score
                )
            },
            noReadLogScore: noReadScore
        )
    }

    private func topRootChoices(
        letter: [ChordNotation.Letter: Double],
        accidental: [ChordInkAccidentalFactorLabel: Double]
    ) -> [Ranked<ChordNotation.Pitch>] {
        var result: [Ranked<ChordNotation.Pitch>] = []
        for letterLabel in ChordNotation.Letter.allCases {
            for accidentalLabel in ChordInkAccidentalFactorLabel.allCases {
                let pitch = ChordNotation.Pitch(
                    letter: letterLabel,
                    accidental: accidentalLabel.notation
                )
                retain(
                    Ranked(
                        value: pitch,
                        score: letter[letterLabel]! + accidental[accidentalLabel]!,
                        tieKey: pitch.canonicalDisplay
                    ),
                    in: &result,
                    limit: 3
                )
            }
        }
        return result
    }

    private func topSuffixChoices(
        quality: [ChordNotation.Form: Double],
        extensionTone: [ChordInkExtensionFactorLabel: Double],
        alterations: [ChordNotation.Alteration: Double]
    ) -> [Ranked<Suffix>] {
        var result: [Ranked<Suffix>] = []

        for form in ChordNotation.Form.allCases {
            for extensionLabel in ChordInkExtensionFactorLabel.allCases {
                enumerateAlterationSubsets(logits: alterations) { selectedAlterations, alterationScore in
                    guard let probe = try? ChordNotation.Rooted(
                            root: ChordNotation.Pitch(letter: .c),
                            form: form,
                            extensionTone: extensionLabel.notation,
                            alterations: selectedAlterations
                          ) else {
                        return
                    }

                    let suffix = Suffix(
                        form: form,
                        extensionTone: extensionLabel.notation,
                        alterations: selectedAlterations
                    )
                    retain(
                        Ranked(
                            value: suffix,
                            score: quality[form]! + extensionTone[extensionLabel]! + alterationScore,
                            tieKey: probe.canonicalDisplay
                        ),
                        in: &result,
                        limit: 3
                    )
                }
            }
        }
        return result
    }

    private func topSlashChoices(
        presence: [ChordInkSlashPresenceFactorLabel: Double],
        letter: [ChordNotation.Letter: Double],
        accidental: [ChordInkAccidentalFactorLabel: Double]
    ) -> [Ranked<ChordNotation.Pitch?>] {
        var result: [Ranked<ChordNotation.Pitch?>] = []
        retain(
            Ranked(value: nil, score: presence[.none]!, tieKey: ""),
            in: &result,
            limit: 3
        )

        for letterLabel in ChordNotation.Letter.allCases {
            for accidentalLabel in ChordInkAccidentalFactorLabel.allCases {
                let pitch = ChordNotation.Pitch(
                    letter: letterLabel,
                    accidental: accidentalLabel.notation
                )
                retain(
                    Ranked(
                        value: pitch,
                        score: presence[.present]!
                            + letter[letterLabel]!
                            + accidental[accidentalLabel]!,
                        tieKey: pitch.canonicalDisplay
                    ),
                    in: &result,
                    limit: 3
                )
            }
        }
        return result
    }

    /// Enumerates all 2^7 Bernoulli selections. Every label contributes either
    /// log-sigmoid(present) or log-sigmoid(absent), including selections later
    /// rejected by the typed grammar. This preserves invalid-combination mass.
    private func enumerateAlterationSubsets(
        logits: [ChordNotation.Alteration: Double],
        visit: ([ChordNotation.Alteration], Double) -> Void
    ) {
        let labels = ChordNotation.Alteration.allCases
        for mask in 0..<(1 << labels.count) {
            var selected: [ChordNotation.Alteration] = []
            var score = 0.0
            for (index, label) in labels.enumerated() {
                let isPresent = mask & (1 << index) != 0
                let logit = logits[label]!
                if isPresent {
                    selected.append(label)
                    score += logSigmoid(logit)
                } else {
                    score += logSigmoid(-logit)
                }
            }
            visit(selected.sorted(), score)
        }
    }

    private func isAcceptedByTypedGrammar(_ notation: ChordNotation) -> Bool {
        var state = ChordNotationGrammar.start
        for token in ChordNotationGrammar.tokens(for: notation) {
            guard let next = ChordNotationGrammar.transition(from: state, consuming: token) else {
                return false
            }
            state = next
        }
        return state.completedNotation == notation
    }

    private func normalizedLogScores<Label>(
        _ logits: ChordInkFactorLogits<Label>,
        labels: [Label],
        head: String,
        labelName: KeyPath<Label, String>
    ) throws -> [Label: Double] where Label: Hashable & Sendable {
        let expected = Set(labels)
        let actual = Set(logits.values.keys)
        guard actual == expected else {
            throw ChordInkLearnedDecodeError.labelSetMismatch(
                head: head,
                expected: labels.map { $0[keyPath: labelName] },
                actual: logits.values.keys.map { $0[keyPath: labelName] }.sorted()
            )
        }

        for label in labels where !(logits.values[label] ?? .nan).isFinite {
            throw ChordInkLearnedDecodeError.nonFiniteLogit(
                head: head,
                label: label[keyPath: labelName]
            )
        }

        let maximum = labels.map { logits.values[$0]! }.max()!
        let denominator = labels.reduce(0.0) { partial, label in
            partial + exp(logits.values[label]! - maximum)
        }
        let logDenominator = log(denominator)
        return Dictionary(uniqueKeysWithValues: labels.map { label in
            (label, logits.values[label]! - maximum - logDenominator)
        })
    }

    private func validatedBernoulliLogits<Label>(
        _ logits: ChordInkFactorLogits<Label>,
        labels: [Label],
        head: String,
        labelName: KeyPath<Label, String>
    ) throws -> [Label: Double] where Label: Hashable & Sendable {
        let expected = Set(labels)
        let actual = Set(logits.values.keys)
        guard actual == expected else {
            throw ChordInkLearnedDecodeError.labelSetMismatch(
                head: head,
                expected: labels.map { $0[keyPath: labelName] },
                actual: logits.values.keys.map { $0[keyPath: labelName] }.sorted()
            )
        }
        for label in labels where !(logits.values[label] ?? .nan).isFinite {
            throw ChordInkLearnedDecodeError.nonFiniteLogit(
                head: head,
                label: label[keyPath: labelName]
            )
        }
        return logits.values
    }

    private func logSigmoid(_ value: Double) -> Double {
        if value >= 0 {
            return -log1p(exp(-value))
        }
        return value - log1p(exp(value))
    }

    private func retain<Value>(
        _ candidate: Ranked<Value>,
        in ranked: inout [Ranked<Value>],
        limit: Int
    ) {
        ranked.append(candidate)
        ranked.sort(by: ranksBefore)
        if ranked.count > limit {
            ranked.removeLast(ranked.count - limit)
        }
    }

    private func ranksBefore<Value>(_ lhs: Ranked<Value>, _ rhs: Ranked<Value>) -> Bool {
        if lhs.score != rhs.score {
            return lhs.score > rhs.score
        }
        return lhs.tieKey < rhs.tieKey
    }
}
