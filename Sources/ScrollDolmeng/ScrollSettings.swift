import Foundation

struct ScrollSettings {
    static let defaults = ScrollSettings(
        isEnabled: true,
        scrollMultiplier: 1.0,
        flipHorizontal: false,
        flipVertical: false,
        showMenuBarIcon: true
    )

    var isEnabled: Bool
    var scrollMultiplier: Double
    var flipHorizontal: Bool
    var flipVertical: Bool
    var showMenuBarIcon: Bool
}

final class SettingsStore {
    private enum Key {
        static let isEnabled = "settings.isEnabled"
        static let scrollMultiplier = "settings.scrollMultiplier"
        static let flipHorizontal = "settings.flipHorizontal"
        static let flipVertical = "settings.flipVertical"
        static let showMenuBarIcon = "settings.showMenuBarIcon"

        static let removedKeys = [
            "settings.modifierConfiguration",
            "settings.modifierFlags",
            "settings.modifierKey",
            "settings.smoothnessValue",
            "settings.momentumValue",
            "settings.reverseScroll",
        ]
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> ScrollSettings {
        let fallback = ScrollSettings.defaults

        return ScrollSettings(
            isEnabled: value(forKey: Key.isEnabled, fallback: fallback.isEnabled),
            scrollMultiplier: value(forKey: Key.scrollMultiplier, fallback: fallback.scrollMultiplier),
            flipHorizontal: value(forKey: Key.flipHorizontal, fallback: fallback.flipHorizontal),
            flipVertical: value(forKey: Key.flipVertical, fallback: fallback.flipVertical),
            showMenuBarIcon: value(forKey: Key.showMenuBarIcon, fallback: fallback.showMenuBarIcon)
        )
    }

    func save(_ settings: ScrollSettings) {
        defaults.set(settings.isEnabled, forKey: Key.isEnabled)
        defaults.set(settings.scrollMultiplier, forKey: Key.scrollMultiplier)
        defaults.set(settings.flipHorizontal, forKey: Key.flipHorizontal)
        defaults.set(settings.flipVertical, forKey: Key.flipVertical)
        defaults.set(settings.showMenuBarIcon, forKey: Key.showMenuBarIcon)

        Key.removedKeys.forEach(defaults.removeObject(forKey:))
    }

    private func value<T>(forKey key: String, fallback: T) -> T {
        defaults.object(forKey: key) as? T ?? fallback
    }
}
