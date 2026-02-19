import Foundation

actor CommandRateLimiter {
    private var lastCommandTimestamps: [String: Date] = [:]

    func waitIfNeeded(for command: TVCommand) async {
        let key = command.rateLimitKey
        let minimumInterval = command.minimumInterval
        let now = Date()

        if let lastTimestamp = lastCommandTimestamps[key] {
            let elapsed = now.timeIntervalSince(lastTimestamp)
            if elapsed < minimumInterval {
                let waitInterval = minimumInterval - elapsed
                let nanos = UInt64(waitInterval * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanos)
            }
        }

        lastCommandTimestamps[key] = Date()
    }

    func reset() {
        lastCommandTimestamps.removeAll()
    }
}

