import CoreGraphics
import Foundation
@preconcurrency import MultitouchSupport

final class TrackpadScrollController: @unchecked Sendable {
    static let fixedModifierKey = ModifierKey.leftOption

    private static let fixedSmoothnessValue = SmoothnessPreset.balanced.sliderValue
    private static let fixedMomentumValue = MomentumPreset.off.sliderValue
    private static let fixedReverseScroll = false

    struct FrameSnapshot: Equatable {
        let activeTouchCount: Int
        let primaryTouchPosition: CGPoint?
        let timestamp: Double
    }

    enum SmoothnessPreset: Int, CaseIterable {
        case crisp
        case balanced
        case soft

        var sliderValue: Double {
            switch self {
            case .crisp:
                return 0.18
            case .balanced:
                return 0.50
            case .soft:
                return 0.84
            }
        }

        static func tuning(for value: Double) -> ScrollPhysics.Tuning {
            let x = clamp01(value)
            return .init(
                deadzone: lerp(0.0024, 0.0045, x),
                deltaFilterFactor: lerp(0.36, 0.10, x),
                velocityFilterFactor: lerp(0.30, 0.08, x),
                emissionThreshold: lerp(0.18, 0.60, x)
            )
        }
    }

    enum MomentumPreset: Int, CaseIterable {
        case off
        case light
        case normal
        case strong

        var sliderValue: Double {
            switch self {
            case .off:
                return 0.0
            case .light:
                return 0.28
            case .normal:
                return 0.58
            case .strong:
                return 0.88
            }
        }

        static func profile(for value: Double) -> MomentumProfile {
            let x = clamp01(value)
            guard x > 0.03 else {
                return .init(enabled: false, startThreshold: .greatestFiniteMagnitude, initialScale: 0, decay: 0, deltaScale: 0, stopThreshold: 0)
            }

            return .init(
                enabled: true,
                startThreshold: lerp(72, 30, x),
                initialScale: lerp(0.045, 0.130, x),
                decay: lerp(0.86, 0.94, x),
                deltaScale: lerp(0.0072, 0.0090, x),
                stopThreshold: lerp(9, 4, x)
            )
        }
    }

    struct MomentumProfile {
        let enabled: Bool
        let startThreshold: CGFloat
        let initialScale: CGFloat
        let decay: CGFloat
        let deltaScale: CGFloat
        let stopThreshold: CGFloat
    }

    private enum GestureState {
        case idle
        case active
    }

    nonisolated(unsafe) private static weak var current: TrackpadScrollController?
    private static let touchCallback: MTFrameCallbackFunction = { _, touches, count, timestamp, _ in
        guard let current = TrackpadScrollController.current else { return }
        let snapshot = TrackpadScrollController.makeFrameSnapshot(touches: touches, count: count, timestamp: timestamp)
        current.enqueueFrame(snapshot)
    }

    private let eventTapController = ScrollEventTapController()
    private let dispatcher = SyntheticScrollDispatcher()
    private let pointerLock = PointerLock()
    private let processingQueue = DispatchQueue(label: "ScrollDolmeng.trackpad")
    private let frameBuffer = LatestSnapshotBuffer<FrameSnapshot>()

    private var devices: [MTDevice] = []
    private var startLifecycle = StartLifecycle()
    private var scrollModeActive = false
    private var gestureState = GestureState.idle
    private var physics = ScrollPhysics()
    private var lastPosition = CGPoint.zero
    private var lastTimestamp = 0.0
    private var lastVelocity = CGPoint.zero
    private var momentumTimer: DispatchSourceTimer?

    var isEnabled = true {
        didSet {
            processingQueue.async {
                if !self.isEnabled {
                    self.deactivateScrollMode(allowMomentum: false)
                }
            }
        }
    }

    var scrollMultiplier = 1.0
    var flipHorizontal = false
    var flipVertical = false

    var hasTap: Bool { eventTapController.hasTap }
    var hasTrackpadDevices: Bool { !devices.isEmpty }

    init() {
        eventTapController.modifierKey = Self.fixedModifierKey
        eventTapController.onModifierChanged = { [weak self] isDown in
            guard let self else { return }
            self.processingQueue.async {
                if !isDown {
                    self.deactivateScrollMode(allowMomentum: false)
                }
            }
        }
    }

    func start() -> Bool {
        guard eventTapController.start() else {
            startLifecycle.reset()
            return false
        }

        guard startLifecycle.beginIfNeeded() else {
            return true
        }

        Self.current = self
        registerDevices()
        return true
    }

    func restart() -> Bool {
        stop()
        return start()
    }

    func stop() {
        Self.current = nil
        frameBuffer.clear()

        processingQueue.sync {
            deactivateScrollMode(allowMomentum: false)
        }

        unregisterDevices()
        eventTapController.stop()
        startLifecycle.reset()
    }

    private func registerDevices() {
        guard devices.isEmpty else { return }
        devices = MTDevice.createList().filter { MTDeviceIsMTHIDDevice($0) }
        devices.forEach { $0.registerAndStart(Self.touchCallback) }
    }

    private func unregisterDevices() {
        devices.forEach { $0.unregisterAndStop(Self.touchCallback) }
        devices.removeAll()
    }

    private func enqueueFrame(_ snapshot: FrameSnapshot) {
        guard frameBuffer.push(snapshot) else { return }

        processingQueue.async { [weak self] in
            self?.drainPendingFrames()
        }
    }

    private func drainPendingFrames() {
        while let snapshot = frameBuffer.popLatest() {
            processFrame(snapshot)
        }
    }

    private func processFrame(_ snapshot: FrameSnapshot) {
        guard isEnabled, eventTapController.modifierDown else {
            deactivateScrollMode(allowMomentum: false)
            return
        }

        guard snapshot.activeTouchCount == 1, let position = snapshot.primaryTouchPosition else {
            if gestureState == .active {
                deactivateScrollMode(allowMomentum: true)
            } else {
                deactivateScrollModeIfNeeded()
            }
            return
        }

        switch gestureState {
        case .idle:
            stopMomentum()
            activateScrollModeIfNeeded()
            pointerLock.pinToAnchorIfNeeded(timestamp: snapshot.timestamp, minimumDistance: 0)
            physics.reset()
            lastPosition = position
            lastTimestamp = snapshot.timestamp
            lastVelocity = .zero
            gestureState = .active

        case .active:
            let dt = snapshot.timestamp - lastTimestamp
            lastTimestamp = snapshot.timestamp

            let delta = CGPoint(
                x: position.x - lastPosition.x,
                y: position.y - lastPosition.y
            )
            lastPosition = position

            let output = physics.step(
                deltaMM: delta,
                dt: dt,
                gain: 42.0 * scrollMultiplier,
                reverse: Self.fixedReverseScroll,
                horizontalSign: horizontalSign,
                verticalSign: verticalSign,
                tuning: SmoothnessPreset.tuning(for: Self.fixedSmoothnessValue)
            )
            lastVelocity = output.velocity
            dispatcher.postGestureDelta(
                output.delta,
                rawDelta: rawEventDelta(from: output.delta)
            )
            pointerLock.pinToAnchorIfNeeded(timestamp: snapshot.timestamp, minimumDistance: 0)
        }
    }

    private func finishGesture(allowMomentum: Bool) {
        guard gestureState == .active else {
            stopMomentum()
            return
        }

        dispatcher.endGesture()
        gestureState = .idle

        let momentumVelocity = lastVelocity
        lastVelocity = .zero

        guard allowMomentum else {
            stopMomentum()
            return
        }

        startMomentum(with: momentumVelocity)
    }

    private func startMomentum(with velocity: CGPoint) {
        stopMomentum()

        let profile = MomentumPreset.profile(for: Self.fixedMomentumValue)
        guard profile.enabled else { return }

        let magnitude = hypot(velocity.x, velocity.y)
        guard magnitude > profile.startThreshold else { return }

        var currentVelocity = CGPoint(
            x: velocity.x * profile.initialScale,
            y: velocity.y * profile.initialScale
        )
        let timer = DispatchSource.makeTimerSource(queue: processingQueue)
        timer.schedule(deadline: .now() + .milliseconds(8), repeating: .milliseconds(8))

        var phase: CGMomentumScrollPhase = .begin
        timer.setEventHandler { [weak self] in
            guard let self else { return }

            currentVelocity.x *= profile.decay
            currentVelocity.y *= profile.decay

            let delta = CGPoint(
                x: currentVelocity.x * profile.deltaScale,
                y: currentVelocity.y * profile.deltaScale
            )
            let speed = hypot(currentVelocity.x, currentVelocity.y)

            if speed < profile.stopThreshold {
                self.dispatcher.postMomentum(delta: .zero, rawDelta: .zero, phase: .end)
                self.stopMomentum()
                return
            }

            self.dispatcher.postMomentum(
                delta: delta,
                rawDelta: self.rawEventDelta(from: delta),
                phase: phase
            )
            phase = CGMomentumScrollPhase(rawValue: 2)!
        }

        momentumTimer = timer
        timer.resume()
    }

    private func stopMomentum() {
        momentumTimer?.cancel()
        momentumTimer = nil
    }

    private func activateScrollModeIfNeeded() {
        guard isEnabled else { return }
        guard !scrollModeActive else { return }

        scrollModeActive = true
        pointerLock.begin()
        eventTapController.setPointerSuppression(true)
    }

    private func deactivateScrollMode(allowMomentum: Bool) {
        finishGesture(allowMomentum: allowMomentum)
        deactivateScrollModeIfNeeded()
    }

    private func deactivateScrollModeIfNeeded() {
        guard scrollModeActive else { return }

        scrollModeActive = false
        eventTapController.setPointerSuppression(false)
        pointerLock.end()
    }

    private static func isFingerTouching(_ touch: MTTouch) -> Bool {
        switch touch.stage {
        case .makeTouch, .touching, .breakTouch:
            return true
        default:
            return false
        }
    }

    private static func makeFrameSnapshot(touches: UnsafePointer<MTTouch>?, count: Int32, timestamp: Double) -> FrameSnapshot {
        guard let touches, count > 0 else {
            return FrameSnapshot(activeTouchCount: 0, primaryTouchPosition: nil, timestamp: timestamp)
        }

        let buffer = UnsafeBufferPointer(start: touches, count: Int(count))
        var activeTouchCount = 0
        var primaryTouchPosition: CGPoint?

        for touch in buffer {
            guard isFingerTouching(touch) else { continue }

            activeTouchCount += 1
            if activeTouchCount == 1 {
                primaryTouchPosition = CGPoint(
                    x: CGFloat(touch.absoluteVector.position.x),
                    y: CGFloat(touch.absoluteVector.position.y)
                )
            }

            if activeTouchCount > 1 {
                break
            }
        }

        return FrameSnapshot(
            activeTouchCount: activeTouchCount,
            primaryTouchPosition: primaryTouchPosition,
            timestamp: timestamp
        )
    }

    private var horizontalSign: CGFloat {
        // Horizontal scroll events use the opposite sign from our raw touch X delta.
        // Browsers also reuse this sign for edge-swipe history navigation.
        let natural: CGFloat = -1.0
        return flipHorizontal ? -natural : natural
    }

    private var verticalSign: CGFloat {
        let natural: CGFloat = -1.0
        return flipVertical ? -natural : natural
    }

    private func rawEventDelta(from delta: CGPoint) -> CGPoint {
        // Keep raw/accelerated delta aligned with the actual emitted scroll delta.
        // Conflicting horizontal signs can make browsers treat the gesture as
        // regular momentum scrolling instead of edge history navigation.
        delta
    }

    private static func clamp01(_ value: Double) -> Double {
        max(0, min(1, value))
    }

    private static func lerp(_ min: CGFloat, _ max: CGFloat, _ x: Double) -> CGFloat {
        min + (max - min) * CGFloat(x)
    }
}
