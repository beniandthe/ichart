import Foundation

/// Explicit user-labeled setup only. Having an example indicates coverage,
/// not recognition accuracy, and whole-chord labels do not label their parts.
enum PersonalInkSetupCatalog {
    struct Prompt: Equatable, Identifiable {
        let label: String
        let title: String
        var kind: PersonalInkExampleKind = .glyph
        var id: String { "\(kind.rawValue):\(label)" }
    }

    static let coreSymbols: [Prompt] = [
        .init(label: "A", title: "A"), .init(label: "B", title: "B"), .init(label: "C", title: "C"),
        .init(label: "D", title: "D"), .init(label: "E", title: "E"), .init(label: "F", title: "F"),
        .init(label: "G", title: "G"), .init(label: "b", title: "♭  (flat)"),
        .init(label: "#", title: "♯  (sharp)"), .init(label: "-", title: "−  (minor)"),
        .init(label: "7", title: "7"), .init(label: "△", title: "△  (major)"),
        .init(label: "/", title: "/  (slash bass)")
    ]

    static let symbols: [Prompt] = coreSymbols + [
        .init(label: "m", title: "m  (minor)"), .init(label: "+", title: "+  (augmented)"),
        .init(label: "o", title: "°  (diminished)"), .init(label: "ø", title: "ø  (half-diminished)"),
        .init(label: "6", title: "6"), .init(label: "9", title: "9"),
        .init(label: "2", title: "2"), .init(label: "4", title: "4"), .init(label: "5", title: "5"),
        .init(label: "1", title: "1"), .init(label: "3", title: "3"),
        .init(label: "(", title: "(  (opening parenthesis)"),
        .init(label: ")", title: ")  (closing parenthesis)")
    ]

    static let quickSetup: [Prompt] = coreSymbols + [
        .init(label: "Bb7", title: "B♭7", kind: .chord),
        .init(label: "Cm7", title: "Cm7", kind: .chord),
        .init(label: "G/B", title: "G/B", kind: .chord)
    ]

    static func missingSymbols(in profile: PersonalInkProfile) -> [Prompt] {
        let learned = Set(profile.examples.filter { $0.kind == .glyph }.map(\.label))
        return symbols.filter { !learned.contains($0.label) }
    }

    static func suggestedSetup(for profile: PersonalInkProfile) -> [Prompt] {
        guard !profile.examples.isEmpty else { return quickSetup }
        let missing = missingSymbols(in: profile)
        return missing.isEmpty ? quickSetup : missing
    }
}
