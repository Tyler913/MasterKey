import Foundation
import IOKit.hid
import BridgeCore

/// A second, shared channel for buttons already diverted by Options+.
/// Only GetFeature / GetCount / GetCidInfo are sent. No SetCidReporting or device seizure.
final class HIDPPMonitor {
    private var manager: IOHIDManager?
    private var interfaces: [UInt64: HIDPPInterface] = [:]
    private(set) var isOpen = false
    var onButton: ((HIDBinding, Bool) -> Void)?
    var onStatus: ((String) -> Void)?
    var onDisconnect: (() -> Void)?

    func start() {
        stop()
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        self.manager = manager
        IOHIDManagerSetDeviceMatching(manager, [kIOHIDVendorIDKey: 0x046D, kIOHIDDeviceUsagePageKey: 0xFF00] as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<HIDPPMonitor>.fromOpaque(context).takeUnretainedValue().add(device)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, device in
            guard let context else { return }
            Unmanaged<HIDPPMonitor>.fromOpaque(context).takeUnretainedValue().remove(device)
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let result = IOHIDManagerOpen(manager, 0)
        isOpen = result == kIOReturnSuccess
        if !isOpen { onStatus?(L10n.format(.hidppFailed, UInt32(bitPattern: result))) }
        for device in IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? [] { add(device) }
    }

    func stop() {
        interfaces.values.forEach { $0.stop() }
        interfaces.removeAll()
        if let manager {
            IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
            IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(manager, 0)
        }
        manager = nil
        isOpen = false
    }

    func rediscover() { interfaces.values.forEach { $0.session.discover() } }

    private func registryID(_ device: IOHIDDevice) -> UInt64 {
        var value: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &value)
        return value
    }

    private func add(_ device: IOHIDDevice) {
        let id = registryID(device)
        guard interfaces[id] == nil else { return }
        let interface = HIDPPInterface(device: device)
        interface.session.onStatus = { [weak self] in self?.onStatus?($0) }
        interface.session.onButton = { [weak self] in self?.onButton?($0, $1) }
        interfaces[id] = interface
        interface.start()
    }

    private func remove(_ device: IOHIDDevice) {
        interfaces.removeValue(forKey: registryID(device))?.stop()
        onDisconnect?()
    }
}

/// Moves HID++ reports between one shared vendor HID interface and its session.
private final class HIDPPInterface {
    let session: HIDPPSession
    private let device: IOHIDDevice
    private let buffer: UnsafeMutablePointer<UInt8>
    private let bufferSize: Int

    init(device: IOHIDDevice) {
        self.device = device
        bufferSize = max(64, min(4096, (IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? NSNumber)?.intValue ?? 64))
        buffer = .allocate(capacity: bufferSize)
        buffer.initialize(repeating: 0, count: bufferSize)
        func number(_ key: String) -> Int { (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue ?? 0 }
        func string(_ key: String) -> String { IOHIDDeviceGetProperty(device, key as CFString) as? String ?? "" }
        let outputs = IOHIDDeviceCopyMatchingElements(device, [kIOHIDElementTypeKey: kIOHIDElementTypeOutput.rawValue] as CFDictionary, 0) as? [IOHIDElement] ?? []
        session = HIDPPSession(
            identity: .init(productID: number(kIOHIDProductIDKey), locationID: number(kIOHIDLocationIDKey),
                            transport: string(kIOHIDTransportKey), product: string(kIOHIDProductKey)),
            longReports: HIDPPPacket.usesLongReports(outputReportIDs: Set(outputs.map(IOHIDElementGetReportID)))
        ) { report in
            report.withUnsafeBufferPointer { IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(report[0]), $0.baseAddress!, report.count) }
        }
    }

    deinit { buffer.deallocate() }

    func start() {
        IOHIDDeviceRegisterInputReportCallback(device, buffer, bufferSize, { context, result, _, _, _, bytes, length in
            guard result == kIOReturnSuccess, let context, length > 0 else { return }
            let interface = Unmanaged<HIDPPInterface>.fromOpaque(context).takeUnretainedValue()
            interface.session.receive(Array(UnsafeBufferPointer(start: bytes, count: length)))
        }, Unmanaged.passUnretained(self).toOpaque())
        session.start()
    }

    func stop() {
        session.stop()
        IOHIDDeviceRegisterInputReportCallback(device, buffer, bufferSize, nil, nil)
    }
}

/// Read-only HID++ discovery and diverted-button tracking for one channel, independent of
/// how reports travel. Reports use HID framing: report ID, device index, feature index,
/// function and software ID, then parameters.
final class HIDPPSession {
    struct Identity {
        let productID: Int
        let locationID: Int
        let transport: String
        let product: String
    }
    private struct Slot {
        var feature: UInt8
        var count: Int = 0
        var nextIndex: Int = 0
        var mouseControls = Set<UInt16>()
        var state = HIDPPButtonState()
    }
    private struct Request { let feature: UInt8; let function: UInt8; let expires: Date }
    private let identity: Identity
    private let longReports: Bool
    private let send: ([UInt8]) -> IOReturn
    private let softwareID: UInt8 = 0x0E
    private var slots: [UInt8: Slot] = [:]
    private var pending: [UInt8: Request] = [:]
    private var timer: Timer?
    private var active = false
    private var lastDiscovery = Date.distantPast
    var onButton: ((HIDBinding, Bool) -> Void)?
    var onStatus: ((String) -> Void)?

    init(identity: Identity, longReports: Bool, send: @escaping ([UInt8]) -> IOReturn) {
        self.identity = identity
        self.longReports = longReports
        self.send = send
    }

    func start() {
        active = true
        onStatus?(L10n.text(.hidppConnecting))
        discover()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.expireRequests() }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        active = false
        timer?.invalidate()
        timer = nil
        pending.removeAll()
    }

    func discover() {
        guard active, Date().timeIntervalSince(lastDiscovery) > 2 else { return }
        lastDiscovery = Date()
        for slot in HIDPPPacket.discoverySlots(transport: identity.transport) where slots[slot] == nil && pending[slot] == nil {
            query(slot, feature: 0, function: 0, parameters: [0x1B, 0x04, 0])
        }
    }

    private func query(_ slot: UInt8, feature: UInt8, function: UInt8, parameters: [UInt8] = []) {
        guard active else { return }
        let report = HIDPPPacket.request(slot: slot, feature: feature, function: function, softwareID: softwareID,
                                         parameters: parameters, long: longReports)
        pending[slot] = Request(feature: feature, function: function, expires: Date().addingTimeInterval(2))
        let result = send(report)
        if result != kIOReturnSuccess {
            pending.removeValue(forKey: slot)
            onStatus?(L10n.format(.hidppQueryFailed, UInt32(bitPattern: result)))
        }
    }

    private func expireRequests() {
        let expired = pending.filter { $0.value.expires < Date() }.map(\.key)
        for slot in expired {
            pending.removeValue(forKey: slot)
            if slots[slot] != nil {
                slots.removeValue(forKey: slot)
                onStatus?(L10n.text(.hidppTimeout))
            }
        }
    }

    func receive(_ bytes: [UInt8]) {
        guard active, let packet = HIDPPPacket(bytes) else { return }
        let slotIndex = packet.deviceIndex
        // An empty receiver slot, or a receiver asked for the direct index, rejects the query.
        if let rejected = packet.rejectedRequest {
            if rejected.softwareID == softwareID, let request = pending[slotIndex],
               request.feature == rejected.feature, request.function == rejected.function {
                pending.removeValue(forKey: slotIndex)
            }
            return
        }
        if packet.softwareID == softwareID, let request = pending[slotIndex],
           request.feature == packet.featureIndex, request.function == packet.function {
            pending.removeValue(forKey: slotIndex)
            if request.feature == 0 {
                guard let feature = packet.parameters.first, feature != 0 else { return }
                slots[slotIndex] = Slot(feature: feature)
                query(slotIndex, feature: feature, function: 0)
            } else if request.function == 0 {
                guard let count = packet.parameters.first, count > 0, count <= 64, var slot = slots[slotIndex] else { return }
                slot.count = Int(count)
                slots[slotIndex] = slot
                query(slotIndex, feature: slot.feature, function: 1, parameters: [0])
            } else if request.function == 1 {
                guard packet.parameters.count >= 5, var slot = slots[slotIndex] else { return }
                let control = UInt16(packet.parameters[0]) << 8 | UInt16(packet.parameters[1])
                let flags = packet.parameters[4]
                // Accept physical mouse controls, never keyboard keys, virtual actions or primary clicks.
                if flags & 1 != 0 && flags & 0x80 == 0 && control != 0 && control != 0x50 && control != 0x51 {
                    slot.mouseControls.insert(control)
                }
                slot.nextIndex += 1
                slots[slotIndex] = slot
                if slot.nextIndex < slot.count { query(slotIndex, feature: slot.feature, function: 1, parameters: [UInt8(slot.nextIndex)]) }
                else { onStatus?(L10n.format(.hidppReady, Int(slotIndex), slot.mouseControls.count)) }
            }
            return
        }
        guard var slot = slots[slotIndex] else {
            if packet.softwareID == 0 { discover() }
            return
        }
        guard let controls = packet.pressedControls(feature: slot.feature, allowed: slot.mouseControls) else { return }
        let edges = slot.state.update(controls)
        slots[slotIndex] = slot
        for edge in edges {
            let binding = HIDBinding(productID: identity.productID, locationID: identity.locationID,
                transport: identity.transport, product: identity.product, usage: UInt32(edge.control),
                reportID: UInt32(HIDPPPacket.longReportID), deviceIndex: slotIndex, controlID: edge.control)
            onButton?(binding, edge.down)
        }
    }
}
