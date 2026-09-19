import CoreGraphics
import Foundation
@preconcurrency import IOKit.hid
import os

struct MXThumbWheelDirectionState: Equatable {
    private enum RawInput: Equatable {
        case thumbWheel(targetEventSign: Int)
        case mainWheel
    }

    // On this MX Master 3S, the desired fixed direction preserves the HID
    // AC Pan sign in the Quartz axis-1 event, independent of Logi's runtime state.
    static let standardEventSignMultiplier = -1
    static let rawInputMatchWindow = 0.05

    private var lastRawInput: RawInput?
    private var lastRawInputAt = -Double.infinity

    mutating func recordThumbWheel(rawValue: Int, at timestamp: Double) {
        guard rawValue != 0 else { return }

        let rawSign = rawValue > 0 ? 1 : -1
        let targetSign = rawSign * Self.standardEventSignMultiplier
        lastRawInput = .thumbWheel(targetEventSign: targetSign)
        lastRawInputAt = timestamp
    }

    mutating func recordMainWheel(rawValue: Int, at timestamp: Double) {
        guard rawValue != 0 else { return }

        lastRawInput = .mainWheel
        lastRawInputAt = timestamp
    }

    mutating func consumeTargetSignForScrollEvent(at timestamp: Double) -> Int? {
        defer { lastRawInput = nil }
        guard timestamp - lastRawInputAt <= Self.rawInputMatchWindow,
              case let .thumbWheel(targetEventSign) = lastRawInput else { return nil }
        return targetEventSign
    }
}

final class MXMasterThumbWheelDirectionLock: @unchecked Sendable {
    private enum HID {
        static let logitechVendorID = 0x046d
        static let mxMaster3SBluetoothProductID = 0xb034
        static let genericDesktopUsagePage = 0x01
        static let wheelUsage = 0x38
        static let consumerUsagePage = 0x0c
        static let acPanUsage = 0x0238
    }

    private static let logger = Logger(subsystem: "kim.chansuk.ScrollDolmeng", category: "MXThumbWheel")

    private let lock = NSLock()
    private var directionState = MXThumbWheelDirectionState()
    private var manager: IOHIDManager?
    private var scrollEventTap: CFMachPort?
    private var scrollRunLoopSource: CFRunLoopSource?
    private var matchedDevices = Set<IOHIDDevice>()

    private(set) var isStarted = false

    var hasMatchedDevice: Bool {
        lock.withLock { !matchedDevices.isEmpty }
    }

    @discardableResult
    func start() -> Bool {
        if isStarted {
            return true
        }

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: HID.logitechVendorID,
            kIOHIDProductIDKey as String: HID.mxMaster3SBluetoothProductID,
        ]
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
        IOHIDManagerRegisterDeviceMatchingCallback(manager, Self.deviceMatchedCallback, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, Self.deviceRemovedCallback, context)
        IOHIDManagerRegisterInputValueCallback(manager, Self.inputValueCallback, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)

        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            Self.logger.error("Could not open MX Master 3S HID manager: \(result)")
            return false
        }

        let scrollMask: CGEventMask = 1 << CGEventType.scrollWheel.rawValue
        guard let scrollEventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: scrollMask,
            callback: Self.scrollEventTapCallback,
            userInfo: context
        ) else {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            Self.logger.error("Could not create session scroll event tap")
            return false
        }

        let scrollRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, scrollEventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), scrollRunLoopSource, .commonModes)
        CGEvent.tapEnable(tap: scrollEventTap, enable: true)

        self.manager = manager
        self.scrollEventTap = scrollEventTap
        self.scrollRunLoopSource = scrollRunLoopSource
        isStarted = true
        return true
    }

    func stop() {
        guard let manager else {
            scrollEventTap = nil
            scrollRunLoopSource = nil
            isStarted = false
            return
        }

        if let scrollRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), scrollRunLoopSource, .commonModes)
        }

        IOHIDManagerRegisterInputValueCallback(manager, nil, nil)
        IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))

        lock.withLock {
            matchedDevices.removeAll()
            directionState = MXThumbWheelDirectionState()
        }
        self.manager = nil
        scrollEventTap = nil
        scrollRunLoopSource = nil
        isStarted = false
    }

    func normalize(event: CGEvent) {
        guard event.type == .scrollWheel else { return }

        let timestamp = ProcessInfo.processInfo.systemUptime
        guard let targetSign = lock.withLock({
            directionState.consumeTargetSignForScrollEvent(at: timestamp)
        }) else { return }

        if Self.forceAxis2Sign(in: event, targetSign: targetSign) {
            Self.logger.debug("Corrected MX Master 3S thumb-wheel direction")
        } else {
            Self.logger.debug("MX Master 3S thumb-wheel direction already locked")
        }
    }

    @discardableResult
    static func forceAxis2Sign(in event: CGEvent, targetSign: Int) -> Bool {
        let fields: [CGEventField] = [
            .scrollWheelEventDeltaAxis2,
            .scrollWheelEventFixedPtDeltaAxis2,
            .scrollWheelEventPointDeltaAxis2,
        ]
        let values = fields.map { event.getIntegerValueField($0) }
        guard let representative = values.first(where: { $0 != 0 }) else { return false }
        let currentSign = representative > 0 ? 1 : -1
        guard currentSign != targetSign else { return false }

        zip(fields, values).forEach { field, value in
            event.setIntegerValueField(field, value: -value)
        }
        return true
    }

    private func record(value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let rawValue = IOHIDValueGetIntegerValue(value)
        guard rawValue != 0 else { return }

        let timestamp = ProcessInfo.processInfo.systemUptime
        lock.withLock {
            if usagePage == HID.consumerUsagePage, usage == HID.acPanUsage {
                directionState.recordThumbWheel(rawValue: rawValue, at: timestamp)
                let direction = rawValue > 0 ? "positive" : "negative"
                Self.logger.debug("Raw MX thumb-wheel pan detected: \(direction, privacy: .public)")
            } else if usagePage == HID.genericDesktopUsagePage, usage == HID.wheelUsage {
                directionState.recordMainWheel(rawValue: rawValue, at: timestamp)
            }
        }
    }

    private func deviceMatched(_ device: IOHIDDevice) {
        _ = lock.withLock {
            matchedDevices.insert(device)
        }
        Self.logger.info("MX Master 3S connected; thumb-wheel direction lock active")
    }

    private func deviceRemoved(_ device: IOHIDDevice) {
        lock.withLock {
            matchedDevices.remove(device)
            directionState = MXThumbWheelDirectionState()
        }
        Self.logger.info("MX Master 3S disconnected; thumb-wheel direction lock idle")
    }

    private static let inputValueCallback: IOHIDValueCallback = { context, result, _, value in
        guard result == kIOReturnSuccess, let context else { return }
        let controller = Unmanaged<MXMasterThumbWheelDirectionLock>.fromOpaque(context).takeUnretainedValue()
        controller.record(value: value)
    }

    private static let deviceMatchedCallback: IOHIDDeviceCallback = { context, result, _, device in
        guard result == kIOReturnSuccess, let context else { return }
        let controller = Unmanaged<MXMasterThumbWheelDirectionLock>.fromOpaque(context).takeUnretainedValue()
        controller.deviceMatched(device)
    }

    private static let deviceRemovedCallback: IOHIDDeviceCallback = { context, result, _, device in
        guard result == kIOReturnSuccess, let context else { return }
        let controller = Unmanaged<MXMasterThumbWheelDirectionLock>.fromOpaque(context).takeUnretainedValue()
        controller.deviceRemoved(device)
    }

    private static let scrollEventTapCallback: CGEventTapCallBack = { _, type, event, context in
        guard let context else {
            return Unmanaged.passUnretained(event)
        }

        let controller = Unmanaged<MXMasterThumbWheelDirectionLock>.fromOpaque(context).takeUnretainedValue()
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let scrollEventTap = controller.scrollEventTap {
                CGEvent.tapEnable(tap: scrollEventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        controller.normalize(event: event)
        return Unmanaged.passUnretained(event)
    }
}
