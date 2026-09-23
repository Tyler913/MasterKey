import Foundation

public struct KeyStep: Equatable {
    public enum Kind: Equatable { case down, up, flagsChanged }
    public let keyCode: UInt16
    public let kind: Kind
    public let flags: UInt64
    public init(keyCode: UInt16, kind: Kind, flags: UInt64) {
        self.keyCode = keyCode
        self.kind = kind
        self.flags = flags
    }
}

/// Uses both the device-independent flag and the left/right device flag from IOLLEvent.h.
/// Sending only .maskControl / .maskCommand loses the distinction Typeless needs.
public struct KeyboardPlan {
    public var down: [KeyStep]
    public var up: [KeyStep]

    public init(configuration: Configuration) {
        if configuration.outputMode == .fn {
            down = [.init(keyCode: 63, kind: .flagsChanged, flags: 0x800000)]
            up = [.init(keyCode: 63, kind: .flagsChanged, flags: 0)]
            return
        }
        var modifiers: [(key: UInt16, mask: UInt64)] = []
        func add(_ side: KeySide, _ left: UInt16, _ right: UInt16, _ generic: UInt64, _ leftMask: UInt64, _ rightMask: UInt64) {
            if side != .off { modifiers.append((side == .left ? left : right, generic | (side == .left ? leftMask : rightMask))) }
        }
        add(configuration.control, 59, 62, 0x40000, 0x1, 0x2000)
        add(configuration.option, 58, 61, 0x80000, 0x20, 0x40)
        add(configuration.shift, 56, 60, 0x20000, 0x2, 0x4)
        add(configuration.command, 55, 54, 0x100000, 0x8, 0x10)
        var flags: UInt64 = 0
        down = []
        up = []
        for modifier in modifiers {
            flags |= modifier.mask
            down.append(.init(keyCode: modifier.key, kind: .flagsChanged, flags: flags))
        }
        down.append(.init(keyCode: configuration.key.rawValue, kind: .down, flags: flags))
        up.append(.init(keyCode: configuration.key.rawValue, kind: .up, flags: flags))
        for modifier in modifiers.reversed() {
            flags &= ~modifier.mask
            up.append(.init(keyCode: modifier.key, kind: .flagsChanged, flags: flags))
        }
    }
}

/// A held mouse button may produce many HID reports. Only the first down is a trigger.
public struct TriggerLatch {
    public enum Transition: Equatable { case began, ended, none }
    public private(set) var isDown = false
    public init() {}
    public mutating func receive(down: Bool) -> Transition {
        guard down != isDown else { return .none }
        isDown = down
        return down ? .began : .ended
    }
    public mutating func reset() { isDown = false }
}
