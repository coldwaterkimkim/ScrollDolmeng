import CoreGraphics
import Foundation

final class PointerLock: @unchecked Sendable {
    private let lock = NSLock()
    private var anchor: CGPoint?
    private var isLocked = false
    private var lastPinTimestamp: Double?

    func begin() {
        lock.lock()
        defer { lock.unlock() }

        guard !isLocked else { return }

        anchor = CGEvent(source: nil)?.location ?? .zero
        lastPinTimestamp = nil
        let result = CGAssociateMouseAndMouseCursorPosition(0)
        if result == .success {
            isLocked = true
        }
    }

    func pinToAnchorIfNeeded(timestamp: Double, minimumDistance: CGFloat = 0.5, minimumInterval: Double = 1.0 / 60.0) {
        lock.lock()
        let anchor = anchor
        let isLocked = isLocked
        let lastPinTimestamp = lastPinTimestamp
        lock.unlock()

        guard isLocked, let anchor else { return }
        if let lastPinTimestamp, timestamp - lastPinTimestamp < minimumInterval {
            return
        }

        let currentLocation = CGEvent(source: nil)?.location ?? anchor
        guard hypot(currentLocation.x - anchor.x, currentLocation.y - anchor.y) >= minimumDistance else {
            return
        }

        lock.withLock {
            self.lastPinTimestamp = timestamp
        }
        _ = CGWarpMouseCursorPosition(anchor)
    }

    func end() {
        lock.lock()
        let anchor = anchor
        let wasLocked = isLocked
        self.anchor = nil
        isLocked = false
        lastPinTimestamp = nil
        lock.unlock()

        guard wasLocked else { return }

        if let anchor {
            _ = CGWarpMouseCursorPosition(anchor)
        }
        _ = CGAssociateMouseAndMouseCursorPosition(1)
    }
}
