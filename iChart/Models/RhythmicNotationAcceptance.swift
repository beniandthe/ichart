import Foundation

enum RhythmicNotationPrimitive: String, Codable, CaseIterable, Hashable, Identifiable {
    case wholeNote
    case halfNote
    case dottedHalfNote
    case quarterNote
    case slash
    case dottedQuarterNote
    case eighthNote
    case tie
    case wholeRest
    case halfRest
    case quarterRest
    case eighthRest

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .wholeNote:
            return "Whole Note"
        case .halfNote:
            return "Half Note"
        case .dottedHalfNote:
            return "Dotted Half Note"
        case .quarterNote:
            return "Quarter Note"
        case .slash:
            return "Slash"
        case .dottedQuarterNote:
            return "Dotted Quarter Note"
        case .eighthNote:
            return "Eighth Note"
        case .tie:
            return "Tie"
        case .wholeRest:
            return "Whole Rest"
        case .halfRest:
            return "Half Rest"
        case .quarterRest:
            return "Quarter Rest"
        case .eighthRest:
            return "Eighth Rest"
        }
    }

    var shortLabel: String {
        switch self {
        case .wholeNote:
            return "W"
        case .halfNote:
            return "H"
        case .dottedHalfNote:
            return "H."
        case .quarterNote:
            return "Q"
        case .slash:
            return "/"
        case .dottedQuarterNote:
            return "Q."
        case .eighthNote:
            return "8"
        case .tie:
            return "Tie"
        case .wholeRest:
            return "WR"
        case .halfRest:
            return "HR"
        case .quarterRest:
            return "QR"
        case .eighthRest:
            return "8R"
        }
    }

    var universalGuide: RhythmicNotationUniversalGuide? {
        switch self {
        case .wholeNote:
            return RhythmicNotationUniversalGuide(
                primitive: self,
                acceptanceSummary: "Accept a single hollow closed loop with no stem. The loop can be tall, narrow, or slightly sideways, but it should read as one open notehead shape.",
                mustContain: [
                    "One continuous closed outline with empty interior",
                    "No attached vertical stem",
                    "No detached dot, flag, or extra zig-zag marks"
                ],
                allowedVariations: [
                    "Tall teardrop-style loop",
                    "Smaller eye-shaped oval",
                    "Slight overdraw or short top cap where the stroke begins and ends"
                ],
                rejectWhen: [
                    "A long vertical stroke extends from the loop",
                    "The head is fully filled like a quarter note",
                    "A detached dot or flag turns it into a different value"
                ]
            )
        case .halfNote:
            return RhythmicNotationUniversalGuide(
                primitive: self,
                acceptanceSummary: "Accept a hollow notehead with one upright stem. The head stays open, while the stem rises cleanly from the head.",
                mustContain: [
                    "One hollow loop for the notehead",
                    "One attached vertical or near-vertical stem",
                    "Stem anchored at the upper edge of the head"
                ],
                allowedVariations: [
                    "Slight hook or overdraw where the stem joins the head",
                    "Head can be narrow and slanted rather than perfectly oval",
                    "Stem can lean slightly but should still read upright"
                ],
                rejectWhen: [
                    "The head is fully filled",
                    "A separate dot appears to the right",
                    "A top flag appears, making it an eighth-note form"
                ]
            )
        case .dottedHalfNote:
            return RhythmicNotationUniversalGuide(
                primitive: self,
                acceptanceSummary: "Accept the same hollow-head-plus-stem shape as a half note, with one detached dot placed to the right of the head.",
                mustContain: [
                    "One hollow notehead",
                    "One attached upright stem",
                    "One separate dot to the right side of the note"
                ],
                allowedVariations: [
                    "The dot can sit slightly low or slightly far right",
                    "The head can be narrow and handwritten rather than perfectly oval",
                    "Minor overdraw at the head/stem join is acceptable"
                ],
                rejectWhen: [
                    "The dot touches and merges into the notehead",
                    "The head is fully filled",
                    "A top flag is present"
                ]
            )
        case .quarterNote:
            return RhythmicNotationUniversalGuide(
                primitive: self,
                acceptanceSummary: "Accept a standard quarter-note form: one filled notehead with one upright stem. The notehead can be compact or slightly slanted, but it should read filled rather than hollow.",
                mustContain: [
                    "One upright stem",
                    "One filled notehead attached near the lower end of the stem",
                    "No detached dot"
                ],
                allowedVariations: [
                    "Large filled oval head with stem",
                    "Compact filled head",
                    "Slightly separate head and stem as long as they visually connect"
                ],
                rejectWhen: [
                    "A top flag or hook appears",
                    "A separate dot appears to the right",
                    "The head stays hollow like a half note"
                ]
            )
        case .slash:
            return RhythmicNotationUniversalGuide(
                primitive: self,
                acceptanceSummary: "Accept one simple diagonal slash as a one-beat placeholder. It should behave like a quarter-note beat slot without adding a stem, flag, dot, or rest shape.",
                mustContain: [
                    "One straight or gently handwritten diagonal stroke",
                    "Enough diagonal travel to read as a slash rather than a dot",
                    "No notehead, stem, flag, dot, or rest zig-zag attached"
                ],
                allowedVariations: [
                    "Forward slash or backslash direction",
                    "Slight lean or mild curve from natural handwriting",
                    "A short overdraw at either end"
                ],
                rejectWhen: [
                    "The mark becomes mostly vertical like a stem",
                    "The mark becomes a zig-zag quarter rest",
                    "A notehead, dot, flag, or rest tail is attached"
                ]
            )
        case .dottedQuarterNote:
            return RhythmicNotationUniversalGuide(
                primitive: self,
                acceptanceSummary: "Accept the same filled-head quarter note as above, with one detached dot to the right of the note body.",
                mustContain: [
                    "One upright stem",
                    "One filled notehead attached near the lower end of the stem",
                    "One separate dot to the right"
                ],
                allowedVariations: [
                    "Filled oval head with dot",
                    "Compact filled head with dot",
                    "Dot may sit slightly low and slightly separated from the note"
                ],
                rejectWhen: [
                    "The dot merges into the note body",
                    "A top flag appears, making it closer to a dotted eighth-like form",
                    "The head is hollow"
                ]
            )
        case .eighthNote:
            return RhythmicNotationUniversalGuide(
                primitive: self,
                acceptanceSummary: "Accept a standard single eighth note: a filled notehead, one upright stem, and one top flag or hook.",
                mustContain: [
                    "One upright stem",
                    "One clear top flag, hook, or curved cap",
                    "One filled notehead attached near the lower end of the stem"
                ],
                allowedVariations: [
                    "Filled head with angled top flag",
                    "Compact filled head with a short top-right flag",
                    "Curved hook at the top rather than a sharp flag"
                ],
                rejectWhen: [
                    "There is no top flag or hook",
                    "A separate dot appears to the right",
                    "Multiple beams or extra flags make it a more complex value"
                ]
            )
        case .quarterRest:
            return RhythmicNotationUniversalGuide(
                primitive: self,
                acceptanceSummary: "Accept a handwritten zig-zag quarter-rest built as one continuous descending squiggle. It does not need the textbook engraving shape; it just needs to read as the same compact zig-zag gesture shown here.",
                mustContain: [
                    "One continuous stroke",
                    "A compact zig-zag or soft 'S' body",
                    "Overall vertical travel from top to bottom"
                ],
                allowedVariations: [
                    "Angular lightning-bolt version",
                    "Rounded 'S' version",
                    "Short finishing tail at the bottom"
                ],
                rejectWhen: [
                    "The shape becomes a note stem with head or flag",
                    "It opens into a rectangular rest block",
                    "It breaks into separate disconnected strokes"
                ]
            )
        case .wholeRest:
            return RhythmicNotationUniversalGuide(
                primitive: self,
                acceptanceSummary: "Accept a compact filled rectangular rest hanging below a horizontal staff line. It should look like a dark block attached under the line rather than a notehead or zig-zag.",
                mustContain: [
                    "One filled horizontal block",
                    "Block placed just under a horizontal line",
                    "No note stem, notehead, dot, or flag"
                ],
                allowedVariations: [
                    "Slightly rounded filled block",
                    "Short horizontal line extending beyond the block",
                    "Loose handwritten fill inside the block"
                ],
                rejectWhen: [
                    "The block sits above the line like a half rest",
                    "The shape becomes an open rectangle",
                    "A long vertical stroke makes it look like a note or quarter rest"
                ]
            )
        case .halfRest:
            return RhythmicNotationUniversalGuide(
                primitive: self,
                acceptanceSummary: "Accept a simple rectangular 'hat' sitting on a horizontal base line. The handwritten form can be loose, but it should still read as a block resting on the line.",
                mustContain: [
                    "A horizontal top edge or roof",
                    "Two short downward sides or corners",
                    "A horizontal base line underneath the block"
                ],
                allowedVariations: [
                    "Wide, low rectangular cap",
                    "Narrower bridge-like cap",
                    "Base line can extend beyond the block on one or both sides"
                ],
                rejectWhen: [
                    "The shape becomes a vertical zig-zag quarter rest",
                    "There is no clear base line under the block",
                    "The shape reads as a notehead plus stem instead of a rest block"
                ]
            )
        case .eighthRest:
            return RhythmicNotationUniversalGuide(
                primitive: self,
                acceptanceSummary: "Accept the standard eighth-rest gesture: a small upper dot or comma with a descending angled tail. It should read as a rest mark, not a notehead attached to a stem.",
                mustContain: [
                    "One compact upper dot or comma mark",
                    "One descending angled or curved tail",
                    "No lower filled notehead"
                ],
                allowedVariations: [
                    "Dot and tail drawn as separate strokes",
                    "Slight curve in the descending tail",
                    "Tail can lean right or left as long as it descends clearly"
                ],
                rejectWhen: [
                    "A filled notehead appears at the bottom",
                    "A top flag plus notehead makes it an eighth note",
                    "The shape becomes a zig-zag quarter rest"
                ]
            )
        case .tie:
            return nil
        }
    }

    static var supportedUniversalGuidePrimitives: [RhythmicNotationPrimitive] {
        allCases.filter { $0.universalGuide != nil }
    }

    static var pendingUniversalGuidePrimitives: [RhythmicNotationPrimitive] {
        allCases.filter { $0.universalGuide == nil }
    }
}

struct RhythmicNotationUniversalGuide: Hashable, Identifiable {
    let primitive: RhythmicNotationPrimitive
    let acceptanceSummary: String
    let mustContain: [String]
    let allowedVariations: [String]
    let rejectWhen: [String]

    var id: RhythmicNotationPrimitive {
        primitive
    }
}

enum RhythmicNotationReferenceKind: String, Hashable {
    case rhythm
    case note
    case rest

    var title: String {
        switch self {
        case .rhythm:
            return "Rhythm"
        case .note:
            return "Notes"
        case .rest:
            return "Rests"
        }
    }
}

struct RhythmicNotationReferenceEntry: Hashable, Identifiable {
    let value: RhythmValue
    let primitive: RhythmicNotationPrimitive
    let kind: RhythmicNotationReferenceKind
    let durationText: String
    let roleText: String
    let guide: RhythmicNotationUniversalGuide

    var id: RhythmValue {
        value
    }

    var title: String {
        value.referenceDisplayTitle
    }
}

enum RhythmicNotationReferenceCompendium {
    static let rhythm: [RhythmicNotationReferenceEntry] = [
        entry(
            value: .slash,
            primitive: .slash,
            kind: .rhythm,
            durationText: "One beat placeholder",
            roleText: "Use for slash notation and rhythm-section beat slots."
        )
    ]

    static let notes: [RhythmicNotationReferenceEntry] = [
        entry(value: .whole, primitive: .wholeNote, kind: .note, durationText: "4 beats in 4/4"),
        entry(value: .dottedHalf, primitive: .dottedHalfNote, kind: .note, durationText: "3 beats in 4/4"),
        entry(value: .half, primitive: .halfNote, kind: .note, durationText: "2 beats in 4/4"),
        entry(value: .dottedQuarter, primitive: .dottedQuarterNote, kind: .note, durationText: "1.5 beats in 4/4"),
        entry(value: .quarter, primitive: .quarterNote, kind: .note, durationText: "1 beat in 4/4"),
        entry(value: .eighth, primitive: .eighthNote, kind: .note, durationText: "Half beat in 4/4")
    ]

    static let rests: [RhythmicNotationReferenceEntry] = [
        entry(value: .wholeRest, primitive: .wholeRest, kind: .rest, durationText: "4 beats of silence in 4/4"),
        entry(value: .halfRest, primitive: .halfRest, kind: .rest, durationText: "2 beats of silence in 4/4"),
        entry(value: .quarterRest, primitive: .quarterRest, kind: .rest, durationText: "1 beat of silence in 4/4"),
        entry(value: .eighthRest, primitive: .eighthRest, kind: .rest, durationText: "Half beat of silence in 4/4")
    ]

    static let all: [RhythmicNotationReferenceEntry] = rhythm + notes + rests

    private static func entry(
        value: RhythmValue,
        primitive: RhythmicNotationPrimitive,
        kind: RhythmicNotationReferenceKind,
        durationText: String,
        roleText: String? = nil
    ) -> RhythmicNotationReferenceEntry {
        guard let guide = primitive.universalGuide else {
            preconditionFailure("Missing rhythm guide for \(primitive.rawValue)")
        }

        return RhythmicNotationReferenceEntry(
            value: value,
            primitive: primitive,
            kind: kind,
            durationText: durationText,
            roleText: roleText ?? defaultRoleText(for: kind),
            guide: guide
        )
    }

    private static func defaultRoleText(for kind: RhythmicNotationReferenceKind) -> String {
        switch kind {
        case .rhythm:
            return "Use as a rhythmic placeholder."
        case .note:
            return "Use as a sounded rhythm value."
        case .rest:
            return "Use as a silent rhythm value."
        }
    }
}

extension RhythmValue {
    var referenceDisplayTitle: String {
        switch self {
        case .slash:
            return "Slash"
        case .eighth:
            return "Eighth Note"
        case .eighthRest:
            return "Eighth Rest"
        case .quarter:
            return "Quarter Note"
        case .quarterRest:
            return "Quarter Rest"
        case .dottedQuarter:
            return "Dotted Quarter Note"
        case .half:
            return "Half Note"
        case .halfRest:
            return "Half Rest"
        case .dottedHalf:
            return "Dotted Half Note"
        case .whole:
            return "Whole Note"
        case .wholeRest:
            return "Whole Rest"
        case .tiedContinuation:
            return "Tie"
        }
    }

    var isDottedReferenceValue: Bool {
        switch self {
        case .dottedQuarter, .dottedHalf:
            return true
        case .slash, .eighth, .eighthRest, .quarter, .quarterRest, .half, .halfRest, .whole, .wholeRest, .tiedContinuation:
            return false
        }
    }
}
