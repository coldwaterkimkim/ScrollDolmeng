import CoreGraphics
import Foundation

enum ModifierSide: Int, CaseIterable, Sendable {
    case off
    case left
    case both
    case right

    var title: String {
        switch self {
        case .off:
            return "Off"
        case .left:
            return "Left"
        case .both:
            return "Both"
        case .right:
            return "Right"
        }
    }
}

struct ModifierKey: Equatable, Sendable {
    var control: ModifierSide
    var shift: ModifierSide
    var option: ModifierSide
    var command: ModifierSide

    static let leftControl = ModifierKey(control: .left)
    static let leftShift = ModifierKey(shift: .left)
    static let leftCommand = ModifierKey(command: .left)
    static let leftOption = ModifierKey(option: .left)

    private struct Component: Sendable {
        let name: String
        let genericMask: UInt64
        let leftMask: UInt64
        let rightMask: UInt64
        let type: ModifierComponent
    }

    private static let components: [Component] = [
        .init(
            name: "Control",
            genericMask: CGEventFlags.maskControl.rawValue,
            leftMask: 0x00000001,
            rightMask: 0x00002000,
            type: .control
        ),
        .init(
            name: "Shift",
            genericMask: CGEventFlags.maskShift.rawValue,
            leftMask: 0x00000002,
            rightMask: 0x00000004,
            type: .shift
        ),
        .init(
            name: "Option",
            genericMask: CGEventFlags.maskAlternate.rawValue,
            leftMask: 0x00000020,
            rightMask: 0x00000040,
            type: .option
        ),
        .init(
            name: "Command",
            genericMask: CGEventFlags.maskCommand.rawValue,
            leftMask: 0x00000008,
            rightMask: 0x00000010,
            type: .command
        ),
    ]

    init(
        control: ModifierSide = .off,
        shift: ModifierSide = .off,
        option: ModifierSide = .off,
        command: ModifierSide = .off
    ) {
        self.control = control
        self.shift = shift
        self.option = option
        self.command = command
    }

    init(packedValue: UInt64) {
        control = ModifierSide(rawValue: Int((packedValue >> 0) & 0b11)) ?? .off
        shift = ModifierSide(rawValue: Int((packedValue >> 2) & 0b11)) ?? .off
        option = ModifierSide(rawValue: Int((packedValue >> 4) & 0b11)) ?? .off
        command = ModifierSide(rawValue: Int((packedValue >> 6) & 0b11)) ?? .off
    }

    init?(flagsValue: UInt64) {
        let flags = CGEventFlags(rawValue: flagsValue)
        let migrated = ModifierKey(
            control: flags.contains(.maskControl) ? .both : .off,
            shift: flags.contains(.maskShift) ? .both : .off,
            option: flags.contains(.maskAlternate) ? .both : .off,
            command: flags.contains(.maskCommand) ? .both : .off
        )

        if migrated.isEmpty {
            return nil
        }

        self = migrated
    }

    init?(legacyRawValue: Int) {
        switch legacyRawValue {
        case 0:
            self = .leftControl
        case 1:
            self = .leftShift
        case 2:
            self = .leftCommand
        case 3:
            self = .leftOption
        default:
            return nil
        }
    }

    var packedValue: UInt64 {
        UInt64(control.rawValue) |
        (UInt64(shift.rawValue) << 2) |
        (UInt64(option.rawValue) << 4) |
        (UInt64(command.rawValue) << 6)
    }

    var isEmpty: Bool {
        control == .off && shift == .off && option == .off && command == .off
    }

    var title: String {
        let parts = Self.components.compactMap { component -> String? in
            let side = side(for: component.type)
            switch side {
            case .off:
                return nil
            case .left:
                return "Left \(component.name)"
            case .both:
                return component.name
            case .right:
                return "Right \(component.name)"
            }
        }

        if parts.isEmpty {
            return "Not Set"
        }

        return parts.joined(separator: " + ")
    }

    func side(for component: ModifierComponent) -> ModifierSide {
        switch component {
        case .control:
            return control
        case .shift:
            return shift
        case .option:
            return option
        case .command:
            return command
        }
    }

    func updating(_ component: ModifierComponent, side: ModifierSide) -> ModifierKey {
        var copy = self
        switch component {
        case .control:
            copy.control = side
        case .shift:
            copy.shift = side
        case .option:
            copy.option = side
        case .command:
            copy.command = side
        }
        return copy
    }

    func matches(_ eventFlags: CGEventFlags) -> Bool {
        guard !isEmpty else { return false }

        let rawFlags = eventFlags.rawValue

        for component in Self.components {
            let side = side(for: component.type)
            let genericDown = rawFlags & component.genericMask != 0
            let leftDown = rawFlags & component.leftMask != 0
            let rightDown = rawFlags & component.rightMask != 0

            switch side {
            case .off:
                if genericDown {
                    return false
                }

            case .left:
                if !(genericDown && leftDown && !rightDown) {
                    return false
                }

            case .both:
                if !genericDown {
                    return false
                }

            case .right:
                if !(genericDown && rightDown && !leftDown) {
                    return false
                }
            }
        }

        return true
    }
}

enum ModifierComponent: CaseIterable, Sendable {
    case control
    case shift
    case option
    case command

    var title: String {
        switch self {
        case .control:
            return "Control"
        case .shift:
            return "Shift"
        case .option:
            return "Option"
        case .command:
            return "Command"
        }
    }
}
