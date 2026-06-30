import CoreGraphics
import Foundation

struct ScrollPhysics {
    struct Tuning: Equatable {
        let deadzone: CGFloat
        let deltaFilterFactor: CGFloat
        let velocityFilterFactor: CGFloat
        let emissionThreshold: CGFloat
    }

    struct Output: Equatable {
        let delta: CGPoint
        let velocity: CGPoint
    }

    private var filteredDelta = CGPoint.zero
    private var filteredVelocity = CGPoint.zero
    private var remainder = CGPoint.zero

    mutating func reset() {
        filteredDelta = .zero
        filteredVelocity = .zero
        remainder = .zero
    }

    mutating func step(
        deltaMM: CGPoint,
        dt: Double,
        gain: Double,
        reverse: Bool,
        horizontalSign: CGFloat,
        verticalSign: CGFloat,
        tuning: Tuning
    ) -> Output {
        let safeDt = max(dt, 1.0 / 240.0)
        let globalDirection: CGFloat = reverse ? -1.0 : 1.0

        let deadzoned = CGPoint(
            x: applyDeadzone(deltaMM.x, threshold: tuning.deadzone),
            y: applyDeadzone(deltaMM.y, threshold: tuning.deadzone)
        )

        filteredDelta = mix(filteredDelta, deadzoned, factor: tuning.deltaFilterFactor)

        let rawVelocity = CGPoint(
            x: deadzoned.x / safeDt,
            y: deadzoned.y / safeDt
        )
        filteredVelocity = mix(filteredVelocity, rawVelocity, factor: tuning.velocityFilterFactor)

        let scaled = CGPoint(
            x: filteredDelta.x * gain * horizontalSign * globalDirection,
            y: filteredDelta.y * gain * verticalSign * globalDirection
        )

        remainder.x += scaled.x
        remainder.y += scaled.y

        let emitted = CGPoint(
            x: roundedTowardZeroIfTiny(remainder.x, threshold: tuning.emissionThreshold),
            y: roundedTowardZeroIfTiny(remainder.y, threshold: tuning.emissionThreshold)
        )

        remainder.x -= emitted.x
        remainder.y -= emitted.y

        let pixelVelocity = CGPoint(
            x: filteredVelocity.x * gain * horizontalSign * globalDirection,
            y: filteredVelocity.y * gain * verticalSign * globalDirection
        )

        return Output(delta: emitted, velocity: pixelVelocity)
    }

    private func applyDeadzone(_ value: CGFloat, threshold: CGFloat) -> CGFloat {
        guard abs(value) > threshold else { return 0 }
        return value
    }

    private func mix(_ lhs: CGPoint, _ rhs: CGPoint, factor: CGFloat) -> CGPoint {
        CGPoint(
            x: lhs.x + (rhs.x - lhs.x) * factor,
            y: lhs.y + (rhs.y - lhs.y) * factor
        )
    }

    private func roundedTowardZeroIfTiny(_ value: CGFloat, threshold: CGFloat) -> CGFloat {
        guard abs(value) >= threshold else { return 0 }
        return value.rounded(.toNearestOrAwayFromZero)
    }
}
