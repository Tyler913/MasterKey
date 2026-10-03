import Foundation

/// Logitech HID++ 2.0 framing. Only long reports contain the four-control event payload.
public struct HIDPPPacket {
    public static let shortReportID: UInt8 = 0x10
    public static let longReportID: UInt8 = 0x11
    /// Index a device uses for itself when connected directly rather than through a receiver.
    public static let directDeviceIndex: UInt8 = 0xFF

    public let deviceIndex: UInt8
    public let featureIndex: UInt8
    public let function: UInt8
    public let softwareID: UInt8
    public let parameters: [UInt8]

    public init?(_ bytes: [UInt8]) {
        guard let report = bytes.first else { return nil }
        let size: Int
        switch report { case Self.shortReportID: size = 7; case Self.longReportID: size = 20; default: return nil }
        // Some transports pad the input buffer past the HID++ frame. Never accept a truncated frame.
        guard bytes.count >= size else { return nil }
        deviceIndex = bytes[1]
        featureIndex = bytes[2]
        function = bytes[3] >> 4
        softwareID = bytes[3] & 0x0F
        parameters = Array(bytes[4..<size])
    }

    /// For a HID++ 1.0 (0x8F) or 2.0 (0xFF) error reply, the request it rejects. Both
    /// echo the request's feature index and function/software ID byte after the marker.
    public var rejectedRequest: (feature: UInt8, function: UInt8, softwareID: UInt8)? {
        guard featureIndex == 0x8F || featureIndex == 0xFF, let echoed = parameters.first else { return nil }
        return ((function << 4) | softwareID, echoed >> 4, echoed & 0x0F)
    }

    public func pressedControls(feature: UInt8, allowed: Set<UInt16>) -> Set<UInt16>? {
        // Never interpret query responses, another feature, or raw motion as a button event.
        guard featureIndex == feature, function == 0, softwareID == 0, parameters.count >= 8 else { return nil }
        let ids = stride(from: 0, to: 8, by: 2).map { UInt16(parameters[$0]) << 8 | UInt16(parameters[$0 + 1]) }
        return Set(ids).intersection(allowed).subtracting([0, 0x50, 0x51])
    }

    /// IRoot.GetFeature(0x1B04). This query does not enable or disable button diversion.
    public static func featureQuery(slot: UInt8, softwareID: UInt8, long: Bool = false) -> [UInt8] {
        request(slot: slot, feature: 0, function: 0, softwareID: softwareID, parameters: [0x1B, 0x04], long: long)
    }

    /// A request frame. Long frames carry the same header and zero-padded parameters.
    public static func request(slot: UInt8, feature: UInt8, function: UInt8, softwareID: UInt8,
                               parameters: [UInt8] = [], long: Bool) -> [UInt8] {
        let header = [long ? longReportID : shortReportID, slot, feature, (function << 4) | (softwareID & 0x0F)]
        let size = long ? 16 : 3
        return header + Array((parameters + Array(repeating: 0, count: size)).prefix(size))
    }

    /// Prefer short reports whenever the interface declares them, as the receiver path
    /// always has. An interface that declares only the long report needs long requests.
    public static func usesLongReports(outputReportIDs: Set<UInt32>) -> Bool {
        !outputReportIDs.contains(UInt32(shortReportID)) && outputReportIDs.contains(UInt32(longReportID))
    }

    /// Receiver slots 1–6 for paired devices, plus the direct index for a device connected
    /// by cable or Bluetooth. A receiver answers the direct index with an error reply.
    public static func discoverySlots(transport: String) -> [UInt8] {
        transport == "USB" ? Array(1...6) + [directDeviceIndex] : [directDeviceIndex]
    }

    public static func isBluetooth(_ transport: String) -> Bool { transport.hasPrefix("Bluetooth") }

    /// Logitech's Bluetooth GATT characteristic carries a long report without its report ID
    /// and device index. Returns the equivalent long report, or nil for any other length.
    public static func report(fromBluetooth value: [UInt8]) -> [UInt8]? {
        value.count == 18 ? [longReportID, directDeviceIndex] + value : nil
    }

    /// The GATT write for a long request frame.
    public static func bluetoothValue(fromReport report: [UInt8]) -> [UInt8]? {
        report.count == 20 && report[0] == longReportID ? Array(report.dropFirst(2)) : nil
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
