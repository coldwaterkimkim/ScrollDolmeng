import Foundation

struct StartLifecycle {
    private(set) var isStarted = false

    mutating func beginIfNeeded() -> Bool {
        guard !isStarted else { return false }
        isStarted = true
        return true
    }

    mutating func reset() {
        isStarted = false
    }
}
