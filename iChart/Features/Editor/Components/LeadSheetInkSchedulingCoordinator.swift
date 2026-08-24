#if canImport(UIKit)
import Foundation

struct LeadSheetInkSchedulingCoordinator {
    private var inputCoalescingWorkItem: DispatchWorkItem?
    private var persistenceWorkItem: DispatchWorkItem?

    mutating func scheduleInputCoalescing(_ workItem: DispatchWorkItem, after delay: TimeInterval) {
        cancelInputCoalescing()
        inputCoalescingWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    mutating func schedulePersistence(_ workItem: DispatchWorkItem, after delay: TimeInterval) {
        cancelPersistence()
        persistenceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    mutating func clearInputCoalescing() {
        inputCoalescingWorkItem = nil
    }

    mutating func clearPersistence() {
        persistenceWorkItem = nil
    }

    mutating func cancelInputCoalescing() {
        inputCoalescingWorkItem?.cancel()
        inputCoalescingWorkItem = nil
    }

    mutating func cancelPersistence() {
        persistenceWorkItem?.cancel()
        persistenceWorkItem = nil
    }

    mutating func cancelAll() {
        cancelInputCoalescing()
        cancelPersistence()
    }
}
#endif
