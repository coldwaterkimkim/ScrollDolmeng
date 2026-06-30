import ApplicationServices
import CoreGraphics
import Foundation

final class ScrollEventTapController: @unchecked Sendable {
    var onModifierChanged: ((Bool) -> Void)?
    private(set) var hasTap = false

    var modifierKey: ModifierKey = .leftOption {
        didSet {
            lock.withLock {
                state.modifierDown = false
            }
            onModifierChanged?(false)
        }
    }

    var modifierDown: Bool {
        lock.withLock { state.modifierDown }
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let lock = NSLock()
    private var state = State()

    private struct State {
        var modifierDown = false
        var suppressPointerMovement = false
    }

    func start() -> Bool {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
            hasTap = true
            return true
        }

        let eventMask =
            mask(for: .flagsChanged) |
            mask(for: .mouseMoved) |
            mask(for: .leftMouseDragged) |
            mask(for: .rightMouseDragged) |
            mask(for: .otherMouseDragged)

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: Self.eventTapCallback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            hasTap = false
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        CGEvent.tapEnable(tap: tap, enable: true)
        hasTap = true
        return true
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        eventTap = nil
        runLoopSource = nil
        lock.withLock {
            state.modifierDown = false
            state.suppressPointerMovement = false
        }
        hasTap = false
    }

    func setPointerSuppression(_ enabled: Bool) {
        lock.withLock {
            state.suppressPointerMovement = enabled
        }
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
                hasTap = true
            }
            return Unmanaged.passUnretained(event)

        case .flagsChanged:
            let isDown = modifierKey.matches(event.flags)
            let shouldNotify = lock.withLock { () -> Bool in
                let changed = state.modifierDown != isDown
                state.modifierDown = isDown
                return changed
            }

            if shouldNotify {
                onModifierChanged?(isDown)
            }

            return Unmanaged.passUnretained(event)

        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            let suppress = lock.withLock { state.suppressPointerMovement }
            if suppress {
                return nil
            }
            return Unmanaged.passUnretained(event)

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func mask(for type: CGEventType) -> CGEventMask {
        1 << type.rawValue
    }

    fileprivate static let eventTapCallback: CGEventTapCallBack = { proxy, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let controller = Unmanaged<ScrollEventTapController>.fromOpaque(userInfo).takeUnretainedValue()
        return controller.handleEvent(proxy: proxy, type: type, event: event)
    }
}
