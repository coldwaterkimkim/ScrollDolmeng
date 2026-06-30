import ApplicationServices
import CoreGraphics
import Foundation

final class SyntheticScrollDispatcher {
    private var gestureActive = false
    private let eventSource = CGEventSource(stateID: .combinedSessionState)

    func postGestureDelta(_ delta: CGPoint, rawDelta: CGPoint) {
        guard delta.x != 0 || delta.y != 0 else { return }

        let phase: CGScrollPhase = gestureActive ? .changed : .began
        gestureActive = true
        post(delta: delta, rawDelta: rawDelta, scrollPhase: phase, momentumPhase: .none)
    }

    func endGesture() {
        guard gestureActive else { return }
        post(delta: .zero, rawDelta: .zero, scrollPhase: .ended, momentumPhase: .none)
        gestureActive = false
    }

    func postMomentum(delta: CGPoint, rawDelta: CGPoint, phase: CGMomentumScrollPhase) {
        post(delta: delta, rawDelta: rawDelta, scrollPhase: nil, momentumPhase: phase)
    }

    private func post(delta: CGPoint, rawDelta: CGPoint, scrollPhase: CGScrollPhase?, momentumPhase: CGMomentumScrollPhase) {
        guard let event = CGEvent(
            scrollWheelEvent2Source: eventSource,
            units: .pixel,
            wheelCount: 2,
            wheel1: Int32(delta.y.rounded(.toNearestOrAwayFromZero)),
            wheel2: Int32(delta.x.rounded(.toNearestOrAwayFromZero)),
            wheel3: 0
        ) else {
            return
        }

        event.flags = []
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(delta.y.rounded(.toNearestOrAwayFromZero)))
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: Int64(delta.x.rounded(.toNearestOrAwayFromZero)))
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: delta.y)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: delta.x)
        event.setIntegerValueField(.scrollWheelEventAcceleratedDeltaAxis1, value: Int64(delta.y.rounded(.toNearestOrAwayFromZero)))
        event.setIntegerValueField(.scrollWheelEventAcceleratedDeltaAxis2, value: Int64(delta.x.rounded(.toNearestOrAwayFromZero)))
        event.setIntegerValueField(.scrollWheelEventRawDeltaAxis1, value: Int64(rawDelta.y.rounded(.toNearestOrAwayFromZero)))
        event.setIntegerValueField(.scrollWheelEventRawDeltaAxis2, value: Int64(rawDelta.x.rounded(.toNearestOrAwayFromZero)))
        event.setIntegerValueField(.scrollWheelEventScrollCount, value: 1)

        if let scrollPhase {
            event.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(scrollPhase.rawValue))
        }

        if momentumPhase != .none {
            event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: Int64(momentumPhase.rawValue))
        }

        event.post(tap: .cghidEventTap)
    }
}
