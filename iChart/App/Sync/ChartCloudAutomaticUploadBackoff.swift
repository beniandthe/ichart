import Foundation

struct ChartCloudAutomaticUploadBackoff {
    static let defaultCooldown: TimeInterval = 30

    private let cooldown: TimeInterval
    private(set) var retryAfter: Date?

    init(cooldown: TimeInterval = Self.defaultCooldown, retryAfter: Date? = nil) {
        self.cooldown = cooldown
        self.retryAfter = retryAfter
    }

    func allowsAutomaticUpload(at date: Date) -> Bool {
        guard let retryAfter else {
            return true
        }

        return date >= retryAfter
    }

    func remainingCooldown(at date: Date) -> TimeInterval {
        guard let retryAfter else {
            return 0
        }

        return max(0, retryAfter.timeIntervalSince(date))
    }

    mutating func recordFailure(at date: Date) {
        retryAfter = date.addingTimeInterval(cooldown)
    }

    mutating func recordSuccess() {
        retryAfter = nil
    }

    mutating func reset() {
        retryAfter = nil
    }
}
