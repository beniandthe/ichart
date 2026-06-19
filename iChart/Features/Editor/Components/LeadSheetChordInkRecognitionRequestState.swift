import Foundation

struct LeadSheetChordInkRecognitionRequestState {
    var pendingWorkItem: DispatchWorkItem?
    var activeRequestID: UUID?
    var lastRecognizedDrawingData: Data?
    var continuationGraceDrawingData: Data?

    mutating func schedule(requestID: UUID, workItem: DispatchWorkItem) {
        pendingWorkItem?.cancel()
        activeRequestID = requestID
        pendingWorkItem = workItem
    }

    mutating func markPendingWorkStarted() {
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
    }

    mutating func cancelPendingRequest() {
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
        activeRequestID = nil
    }

    mutating func clearActiveRequest() {
        activeRequestID = nil
    }

    mutating func clearForChordEditingDisabled() {
        cancelPendingRequest()
        lastRecognizedDrawingData = nil
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
