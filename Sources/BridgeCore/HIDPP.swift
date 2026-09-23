import Foundation

/// Logitech HID++ 2.0 framing. Only long reports contain the four-control event payload.
public struct HIDPPPacket {
    public let deviceIndex: UInt8
    public let featureIndex: UInt8
    public let function: UInt8
    public let softwareID: UInt8
    public let parameters: [UInt8]

    public init?(_ bytes: [UInt8]) {
        guard let report = bytes.first else { return nil }
        let size: Int
        switch report { case 0x10: size = 7; case 0x11: size = 20; default: return nil }
        guard bytes.count == size else { return nil }
        deviceIndex = bytes[1]
        featureIndex = bytes[2]
        function = bytes[3] >> 4
        softwareID = bytes[3] & 0x0F
        parameters = Array(bytes.dropFirst(4))
    }

    public func pressedControls(feature: UInt8, allowed: Set<UInt16>) -> Set<UInt16>? {
        // Never interpret query responses, another feature, or raw motion as a button event.
        guard featureIndex == feature, function == 0, softwareID == 0, parameters.count >= 8 else { return nil }
        let ids = stride(from: 0, to: 8, by: 2).map { UInt16(parameters[$0]) << 8 | UInt16(parameters[$0 + 1]) }
        return Set(ids).intersection(allowed).subtracting([0, 0x50, 0x51])
    }

    /// IRoot.GetFeature(0x1B04). This query does not enable or disable button diversion.
    public static func featureQuery(slot: UInt8, softwareID: UInt8) -> [UInt8] {
        [0x10, slot, 0, softwareID & 0x0F, 0x1B, 0x04, 0]
    }
}

public struct HIDPPButtonState {
    public struct Edge: Equatable {
        public let control: UInt16
        public let down: Bool
        public init(control: UInt16, down: Bool) { self.control = control; self.down = down }
    }
    private var pressed = Set<UInt16>()
    public init() {}
    public mutating func update(_ current: Set<UInt16>) -> [Edge] {
        let changes = pressed.subtracting(current).sorted().map { Edge(control: $0, down: false) }
            + current.subtracting(pressed).sorted().map { Edge(control: $0, down: true) }
        pressed = current
        return changes
    }
}
