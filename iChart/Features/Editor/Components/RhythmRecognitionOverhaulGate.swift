import Foundation

enum RhythmRecognitionOverhaulGate {
    /// Keeps the old timer-driven rhythm render loop parked while the V2 recognizer is rebuilt.
    static let isLegacyAutoRenderParked = true

    /// Enables deliberate rhythm recognition from the active ink, committed only by tap/finalization.
    static let isTapToRenderRecognitionEnabled = true

    static let isLegacyHandwritingRecognitionParked = isLegacyAutoRenderParked
}
