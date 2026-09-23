/// Decodes physical left/right modifier key codes before a final key commits a shortcut.
public struct ShortcutCapture {
    public private(set) var heldModifiers: [UInt16] = []
    public init() {}

    @discardableResult public mutating func modifierChanged(keyCode: UInt16) -> Bool {
        guard Self.modifier(keyCode) != nil else { return false }
        if let index = heldModifiers.firstIndex(of: keyCode) { heldModifiers.remove(at: index) }
        else { heldModifiers.append(keyCode) }
        return true
    }

    public func shortcut(for keyCode: UInt16, flags: UInt64 = 0) -> CapturedShortcut? {
        let key = ShortcutKey(rawValue: keyCode)
        guard key.isRecordable else { return nil }
        return CapturedShortcut(
            control: side(left: 59, right: 62, flags: flags, generic: 0x40000, leftFlag: 0x1, rightFlag: 0x2000),
            command: side(left: 55, right: 54, flags: flags, generic: 0x100000, leftFlag: 0x8, rightFlag: 0x10),
            option: side(left: 58, right: 61, flags: flags, generic: 0x80000, leftFlag: 0x20, rightFlag: 0x40),
            shift: side(left: 56, right: 60, flags: flags, generic: 0x20000, leftFlag: 0x2, rightFlag: 0x4), key: key
        )
    }

    public var modifierTitle: String {
        heldModifiers.compactMap { code -> String? in
            guard let (name, side) = Self.modifier(code) else { return nil }
            return "\(side.title) \(name)"
        }.joined(separator: " + ")
    }

    private func side(left: UInt16, right: UInt16, flags: UInt64, generic: UInt64, leftFlag: UInt64, rightFlag: UInt64) -> KeySide {
        for code in heldModifiers.reversed() {
            if code == left { return .left }
            if code == right { return .right }
        }
        // Some input methods deliver the key-down with modifier flags but without
        // separate flagsChanged events. Prefer the physical side bits when present.
        if flags & rightFlag != 0 { return .right }
        if flags & leftFlag != 0 { return .left }
        if flags & generic != 0 { return .left }
        return .off
    }

    private static func modifier(_ code: UInt16) -> (String, KeySide)? {
        switch code {
        case 59: return ("Control", .left)
        case 62: return ("Control", .right)
        case 55: return ("Command", .left)
        case 54: return ("Command", .right)
        case 58: return ("Option", .left)
        case 61: return ("Option", .right)
        case 56: return ("Shift", .left)
        case 60: return ("Shift", .right)
        default: return nil
        }
    }
}

public struct CapturedShortcut: Equatable {
    public let control: KeySide
    public let command: KeySide
    public let option: KeySide
    public let shift: KeySide
    public let key: ShortcutKey

    public func applying(to configuration: Configuration) -> Configuration {
        var result = configuration
        result.control = control
        result.command = command
        result.option = option
        result.shift = shift
        result.key = key
        return result
    }
}
