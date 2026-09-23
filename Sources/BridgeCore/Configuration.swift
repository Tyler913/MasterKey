import Foundation

public enum InputMode: String, Codable, CaseIterable, Identifiable {
    case hid, mouse, relay
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .hid: return L10n.text(.inputHID)
        case .mouse: return L10n.text(.inputMouse)
        case .relay: return L10n.text(.inputRelay)
        }
    }
}

public enum OutputMode: String, Codable, CaseIterable, Identifiable {
    case fn, shortcut
    public var id: String { rawValue }
}

public enum PressMode: String, Codable, CaseIterable, Identifiable {
    case tap, hold
    public var id: String { rawValue }
}

public enum KeySide: String, Codable, CaseIterable, Identifiable {
    case off, left, right
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .off: return L10n.text(.off)
        case .left: return L10n.text(.left)
        case .right: return L10n.text(.right)
        }
    }
}

/// The saved representation remains a single macOS virtual key code, as in 1.2.
public struct ShortcutKey: RawRepresentable, Codable, Hashable {
    public var rawValue: UInt16
    public init(rawValue: UInt16) { self.rawValue = rawValue }
    public init(from decoder: Decoder) throws { rawValue = try decoder.singleValueContainer().decode(UInt16.self) }
    public func encode(to encoder: Encoder) throws { var value = encoder.singleValueContainer(); try value.encode(rawValue) }
    public static let z = Self(rawValue: 6)
    public static let c = Self(rawValue: 8)
    public static let v = Self(rawValue: 9)
    public static let space = Self(rawValue: 49)
    public static let f18 = Self(rawValue: 79)
    public var title: String { Self.names[rawValue] ?? String(format: "Key 0x%02X", rawValue) }
    public var isRecordable: Bool { Self.names[rawValue] != nil }

    private static let names: [UInt16: String] = [
        0:"A", 1:"S", 2:"D", 3:"F", 4:"H", 5:"G", 6:"Z", 7:"X", 8:"C", 9:"V", 11:"B",
        12:"Q", 13:"W", 14:"E", 15:"R", 16:"Y", 17:"T", 18:"1", 19:"2", 20:"3", 21:"4",
        22:"6", 23:"5", 24:"=", 25:"9", 26:"7", 27:"-", 28:"8", 29:"0", 30:"]", 31:"O",
        32:"U", 33:"[", 34:"I", 35:"P", 36:"Return", 37:"L", 38:"J", 39:"'", 40:"K",
        41:";", 42:"\\", 43:",", 44:"/", 45:"N", 46:"M", 47:".", 48:"Tab", 49:"Space",
        50:"`", 51:"Delete", 53:"Esc", 64:"F17", 65:"Num .", 67:"Num ×", 69:"Num +",
        71:"Num Clear", 75:"Num /", 76:"Num Enter", 78:"Num -", 79:"F18", 80:"F19",
        81:"Num =", 82:"Num 0", 83:"Num 1", 84:"Num 2", 85:"Num 3", 86:"Num 4",
        87:"Num 5", 88:"Num 6", 89:"Num 7", 90:"F20", 91:"Num 8", 92:"Num 9",
        96:"F5", 97:"F6", 98:"F7", 99:"F3", 100:"F8", 101:"F9", 103:"F11",
        105:"F13", 106:"F16", 107:"F14", 109:"F10", 111:"F12", 113:"F15",
        114:"Help", 115:"Home", 116:"Page Up", 117:"Forward Delete", 118:"F4",
        119:"End", 120:"F2", 121:"Page Down", 122:"F1", 123:"←", 124:"→", 125:"↓", 126:"↑"
    ]
}

public enum RelayKey: String, Codable, CaseIterable, Identifiable {
    case f18, f19, hyperF12
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .f18: return "F18"
        case .f19: return "F19"
        case .hyperF12: return "⌃⌥⌘ F12"
        }
    }
    public var keyCode: UInt16 { self == .f18 ? 79 : (self == .f19 ? 80 : 111) }
    public var flags: UInt64 { self == .hyperF12 ? 0x1C0000 : 0 }
    public func matches(keyCode: UInt16, flags: UInt64) -> Bool {
        // Ignore device-specific bits, Caps Lock, Numeric Pad, and the Fn bit on F-keys.
        keyCode == self.keyCode && flags & 0x1E0000 == self.flags
    }
}

public struct HIDBinding: Codable, Equatable {
    public var productID: Int
    public var locationID: Int
    public var transport: String
    public var product: String
    public var usage: UInt32
    public var reportID: UInt32
    public var deviceIndex: UInt8?
    public var controlID: UInt16?
    public init(productID: Int, locationID: Int, transport: String, product: String, usage: UInt32, reportID: UInt32, deviceIndex: UInt8? = nil, controlID: UInt16? = nil) {
        self.productID = productID
        self.locationID = locationID
        self.transport = transport
        self.product = product
        self.usage = usage
        self.reportID = reportID
        self.deviceIndex = deviceIndex
        self.controlID = controlID
    }
    public func matches(_ other: HIDBinding) -> Bool {
        productID == other.productID && locationID == other.locationID && transport == other.transport
            && usage == other.usage && reportID == other.reportID
            && deviceIndex == other.deviceIndex && controlID == other.controlID
    }
    public var title: String {
        if let controlID { return "\(product) · " + L10n.format(.logitechButton, Int(controlID)) }
        return "\(product) · " + L10n.format(.systemButton, Int(usage))
    }
}

public struct Configuration: Codable, Equatable {
    public var enabled = true
    public var inputMode = InputMode.hid
    public var outputMode = OutputMode.fn
    public var pressMode = PressMode.tap
    public var control = KeySide.left
    public var command = KeySide.left
    public var option = KeySide.off
    public var shift = KeySide.off
    public var key = ShortcutKey.z
    public var relayKey = RelayKey.f18
    public var mouseButton: Int64 = 3
    public var hidBinding: HIDBinding?
    public init() {}
    public var outputTitle: String {
        if outputMode == .fn { return "Fn / 🌐" }
        let modifiers: [(String, KeySide)] = [("Control", control), ("Option", option), ("Shift", shift), ("Command", command)]
        return (modifiers.compactMap { name, side in side == .off ? nil : "\(side.title) \(name)" } + [key.title]).joined(separator: " + ")
    }
    public var conflictsWithRelay: Bool {
        guard inputMode == .relay, outputMode == .shortcut else { return false }
        let flags = KeyboardPlan(configuration: self).down.last?.flags ?? 0
        return relayKey.matches(keyCode: key.rawValue, flags: flags)
    }
}
