import CoreGraphics
import Foundation
import Testing
@testable import ScrollDolmeng

@Test func physicsEmitsNoScrollForTinyDeadzoneMovement() async throws {
    var physics = ScrollPhysics()
    let output = physics.step(
        deltaMM: CGPoint(x: 0.001, y: 0.001),
        dt: 1.0 / 120.0,
        gain: 42,
        reverse: false,
        horizontalSign: 1,
        verticalSign: -1,
        tuning: .init(deadzone: 0.0033, deltaFilterFactor: 0.22, velocityFilterFactor: 0.18, emissionThreshold: 0.35)
    )
    #expect(output.delta == .zero)
}

@Test func physicsRespectsReverseFlag() async throws {
    var physics = ScrollPhysics()
    let tuning = ScrollPhysics.Tuning(deadzone: 0.0033, deltaFilterFactor: 0.22, velocityFilterFactor: 0.18, emissionThreshold: 0.35)
    _ = physics.step(
        deltaMM: CGPoint(x: 0.02, y: 0.03),
        dt: 1.0 / 120.0,
        gain: 42,
        reverse: false,
        horizontalSign: 1,
        verticalSign: -1,
        tuning: tuning
    )
    let reversed = physics.step(
        deltaMM: CGPoint(x: 0.08, y: 0.12),
        dt: 1.0 / 120.0,
        gain: 42,
        reverse: true,
        horizontalSign: 1,
        verticalSign: -1,
        tuning: tuning
    )
    #expect(reversed.delta.x < 0)
    #expect(reversed.delta.y > 0)
}

@Test func physicsUsesNaturalHorizontalAndVerticalSigns() async throws {
    var physics = ScrollPhysics()
    let tuning = ScrollPhysics.Tuning(deadzone: 0.0033, deltaFilterFactor: 0.22, velocityFilterFactor: 0.18, emissionThreshold: 0.35)

    _ = physics.step(
        deltaMM: CGPoint(x: 0.02, y: 0.02),
        dt: 1.0 / 120.0,
        gain: 42,
        reverse: false,
        horizontalSign: -1,
        verticalSign: -1,
        tuning: tuning
    )

    let output = physics.step(
        deltaMM: CGPoint(x: 0.08, y: 0.08),
        dt: 1.0 / 120.0,
        gain: 42,
        reverse: false,
        horizontalSign: -1,
        verticalSign: -1,
        tuning: tuning
    )

    #expect(output.delta.x < 0)
    #expect(output.delta.y < 0)
}

@Test func latestSnapshotBufferKeepsOnlyLatestPendingValue() async throws {
    let buffer = LatestSnapshotBuffer<Int>()

    #expect(buffer.push(1))
    #expect(!buffer.push(2))
    #expect(buffer.popLatest() == 2)
    #expect(buffer.popLatest() == nil)

    #expect(buffer.push(3))
    #expect(buffer.popLatest() == 3)
    #expect(buffer.popLatest() == nil)
}

@Test func startLifecyclePreventsDuplicateRegistrationCycles() async throws {
    var lifecycle = StartLifecycle()

    let firstStart = lifecycle.beginIfNeeded()
    let secondStart = lifecycle.beginIfNeeded()

    #expect(firstStart)
    #expect(!secondStart)

    lifecycle.reset()

    let thirdStart = lifecycle.beginIfNeeded()
    #expect(thirdStart)
}

@Test func modifierKeyMatchesBothSideHyperCombination() async throws {
    let hyperKey = ModifierKey(control: .both, shift: .both, option: .both, command: .both)

    let leftHyperFlags = CGEventFlags(rawValue:
        CGEventFlags.maskControl.rawValue |
        CGEventFlags.maskShift.rawValue |
        CGEventFlags.maskAlternate.rawValue |
        CGEventFlags.maskCommand.rawValue |
        0x00000001 |
        0x00000002 |
        0x00000020 |
        0x00000008
    )

    let mixedSideHyperFlags = CGEventFlags(rawValue:
        CGEventFlags.maskControl.rawValue |
        CGEventFlags.maskShift.rawValue |
        CGEventFlags.maskAlternate.rawValue |
        CGEventFlags.maskCommand.rawValue |
        0x00002000 |
        0x00000004 |
        0x00000020 |
        0x00000010
    )

    #expect(hyperKey.matches(leftHyperFlags))
    #expect(hyperKey.matches(mixedSideHyperFlags))
    #expect(!hyperKey.matches(.maskCommand))
}

@Test func modifierKeyRespectsLeftAndRightSpecificSelection() async throws {
    let modifierKey = ModifierKey(option: .left, command: .right)

    let matchingFlags = CGEventFlags(rawValue:
        CGEventFlags.maskAlternate.rawValue |
        CGEventFlags.maskCommand.rawValue |
        0x00000020 |
        0x00000010
    )
    let wrongOptionSideFlags = CGEventFlags(rawValue:
        CGEventFlags.maskAlternate.rawValue |
        CGEventFlags.maskCommand.rawValue |
        0x00000040 |
        0x00000010
    )
    let extraShiftFlags = CGEventFlags(rawValue:
        matchingFlags.rawValue |
        CGEventFlags.maskShift.rawValue |
        0x00000002
    )

    #expect(modifierKey.matches(matchingFlags))
    #expect(!modifierKey.matches(wrongOptionSideFlags))
    #expect(!modifierKey.matches(extraShiftFlags))
}

@Test func settingsStoreIgnoresRemovedPreferenceKeysWhenLoading() async throws {
    let suiteName = "ScrollDolmengTests.SettingsStoreIgnoresRemovedPreferenceKeysWhenLoading"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        Issue.record("Failed to create UserDefaults suite")
        return
    }

    defaults.removePersistentDomain(forName: suiteName)
    defaults.set(false, forKey: "settings.isEnabled")
    defaults.set(1.18, forKey: "settings.scrollMultiplier")
    defaults.set(true, forKey: "settings.flipHorizontal")
    defaults.set(false, forKey: "settings.flipVertical")
    defaults.set(false, forKey: "settings.showMenuBarIcon")
    defaults.set(
        NSNumber(value: CGEventFlags.maskAlternate.rawValue | CGEventFlags.maskCommand.rawValue),
        forKey: "settings.modifierFlags"
    )
    defaults.set(0.84, forKey: "settings.smoothnessValue")
    defaults.set(0.88, forKey: "settings.momentumValue")
    defaults.set(true, forKey: "settings.reverseScroll")

    let store = SettingsStore(defaults: defaults)
    let settings = store.load()

    #expect(!settings.isEnabled)
    #expect(settings.scrollMultiplier == 1.18)
    #expect(settings.flipHorizontal)
    #expect(!settings.flipVertical)
    #expect(!settings.showMenuBarIcon)

    defaults.removePersistentDomain(forName: suiteName)
}

@Test func settingsStoreRemovesObsoletePreferenceKeysWhenSaving() async throws {
    let suiteName = "ScrollDolmengTests.SettingsStoreRemovesObsoletePreferenceKeysWhenSaving"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        Issue.record("Failed to create UserDefaults suite")
        return
    }

    defaults.removePersistentDomain(forName: suiteName)
    let obsoleteKeys = [
        "settings.modifierConfiguration",
        "settings.modifierFlags",
        "settings.modifierKey",
        "settings.smoothnessValue",
        "settings.momentumValue",
        "settings.reverseScroll",
    ]
    obsoleteKeys.forEach { defaults.set(3, forKey: $0) }

    let store = SettingsStore(defaults: defaults)
    store.save(.defaults)

    obsoleteKeys.forEach { key in
        #expect(defaults.object(forKey: key) == nil)
    }

    defaults.removePersistentDomain(forName: suiteName)
}
