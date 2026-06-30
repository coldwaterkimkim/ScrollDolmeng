import Foundation

enum SettingsPresentation {
    static func selectedSpeedPresetName(for value: Double) -> String {
        if abs(value - 0.82) < 0.01 {
            return "Slow"
        }
        if abs(value - 1.00) < 0.01 {
            return "Normal"
        }
        if abs(value - 1.18) < 0.01 {
            return "Fast"
        }
        return "Custom"
    }

    static func speedDescription(for value: Double) -> String {
        switch value {
        case ..<0.85:
            return "Shorter travel per finger movement. Easier to place the page precisely."
        case 0.85...1.15:
            return "Closest to the default macOS travel distance."
        default:
            return "Longer travel per finger movement. Faster for long pages."
        }
    }

    static func axisSummary(flipHorizontal: Bool, flipVertical: Bool) -> String {
        var parts: [String] = []
        if flipHorizontal {
            parts.append("Horizontal Flipped")
        }
        if flipVertical {
            parts.append("Vertical Flipped")
        }
        if parts.isEmpty {
            parts.append("Default")
        }
        return parts.joined(separator: " / ")
    }

    static func statusTitle(hasTap: Bool, hasTrackpadDevices: Bool, isEnabled: Bool) -> String {
        if !hasTap {
            return "Permissions Needed"
        }
        if !hasTrackpadDevices {
            return "Trackpad Not Found"
        }
        return isEnabled ? "Active" : "Paused"
    }

    static func statusSubtitle(
        hasTap: Bool,
        hasTrackpadDevices: Bool,
        isEnabled: Bool,
        modifierKey: ModifierKey
    ) -> String {
        if !hasTap {
            return "Allow Accessibility and Input Monitoring for ScrollDolmeng.app, then reconnect the input hook."
        }
        if !hasTrackpadDevices {
            return "No Apple multitouch trackpad is available right now, so one-finger modifier scrolling cannot start."
        }
        if !isEnabled {
            return "Turn one-finger scrolling back on when you want Left Option to activate scrolling."
        }
        return "Hold \(TrackpadScrollController.fixedModifierKey.title) and move one finger on the trackpad to scroll while the pointer stays locked in place."
    }
}
