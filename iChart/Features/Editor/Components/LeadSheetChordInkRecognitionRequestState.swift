import Foundation

struct LeadSheetChordInkRecognitionRequestState {
    var activeRequestID: UUID?

    mutating func beginRequest(_ requestID: UUID) {
        activeRequestID = requestID
    }

    mutating func cancelPendingRequest() {
        activeRequestID = nil
    }

    mutating func clearActiveRequest() {
        activeRequestID = nil
    }

    mutating func clearForChordEditingDisabled() {
        cancelPendingRequest()
    }

    func isActive(_ requestID: UUID) -> Bool {
        activeRequestID == requestID
    }

    mutating func finishActiveRequest(_ requestID: UUID) -> Bool {
        guard isActive(requestID) else {
            return false
        }

        activeRequestID = nil
        return true
    }
}
