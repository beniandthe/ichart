import Foundation

enum RhythmRecognitionOverhaulGate {
    /// V1 ships rhythm entry as Free-Write only while literal rhythm input is designed.
    static let shipsDedicatedRhythmTool = false

    /// Kept for parked recognizer research only; the app must not route live input here.
    static let isConstrainedGlyphOCRPrimaryForSimpleMeters = false
}
