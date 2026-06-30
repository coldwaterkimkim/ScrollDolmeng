import Foundation

final class LatestSnapshotBuffer<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var latestValue: Value?
    private var isDraining = false

    func push(_ value: Value) -> Bool {
        lock.withLock {
            latestValue = value
            guard !isDraining else { return false }
            isDraining = true
            return true
        }
    }

    func popLatest() -> Value? {
        lock.withLock {
            guard let latestValue else {
                isDraining = false
                return nil
            }

            self.latestValue = nil
            return latestValue
        }
    }

    func clear() {
        lock.withLock {
            latestValue = nil
            isDraining = false
        }
    }
}
