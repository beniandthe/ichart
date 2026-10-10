import Foundation

/// Product boundary for parked handwriting-personalization experiments.
///
/// Keep this independent of build configuration: the next app candidate must
/// behave the same on Debug devices and Release builds. Saved profile,
/// correction-memory, preference, and evaluation files remain intact so a
/// future explicitly reviewed candidate can reuse them without migration or
/// data loss.
enum HandwritingPersonalizationProductPolicy {
    static let isAvailable = false
}
