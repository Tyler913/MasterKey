import Foundation
import IOKit.hid
import BridgeCore

/// A second, shared channel for buttons already diverted by Options+.
/// Only GetFeature / GetCount / GetCidInfo are sent. No SetCidReporting or device seizure.
final class HIDPPMonitor {
    private var manager: IOHIDManager?
    private var sessions: [UInt64: HIDPPSession] = [:]
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
        sessions.values.forEach { $0.stop() }
        sessions.removeAll()
        if let manager {
            IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
            IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
            IOHIDManagerClose(manager, 0)
        }
        manager = nil
        isOpen = false
    }

    func rediscover() { sessions.values.forEach { $0.discover() } }

    private func registryID(_ device: IOHIDDevice) -> UInt64 {
        var value: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &value)
        return value
    }

    private func add(_ device: IOHIDDevice) {
        let id = registryID(device)
        guard sessions[id] == nil else { return }
        let session = HIDPPSession(device: device)
        session.onStatus = { [weak self] in self?.onStatus?($0) }
        session.onButton = { [weak self] in self?.onButton?($0, $1) }
        sessions[id] = session
        session.start()
    }

    private func remove(_ device: IOHIDDevice) {
        sessions.removeValue(forKey: registryID(device))?.stop()
        onDisconnect?()
    }
}

private final class HIDPPSession {
    private struct Slot {
        var feature: UInt8
        var count: Int = 0
        var nextIndex: Int = 0
        var mouseControls = Set<UInt16>()
        var state = HIDPPButtonState()
    }
    private struct Request { let feature: UInt8; let function: UInt8; let expires: Date }
    private let device: IOHIDDevice
    private let buffer: UnsafeMutablePointer<UInt8>
    private let bufferSize: Int
    private let softwareID: UInt8 = 0x0E
    private var slots: [UInt8: Slot] = [:]
    private var pending: [UInt8: Request] = [:]
    private var timer: Timer?
    private var active = false
    private var lastDiscovery = Date.distantPast
    var onButton: ((HIDBinding, Bool) -> Void)?
    var onStatus: ((String) -> Void)?

    init(device: IOHIDDevice) {
        self.device = device
        bufferSize = max(64, min(4096, (IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString) as? NSNumber)?.intValue ?? 64))
        buffer = .allocate(capacity: bufferSize)
        buffer.initialize(repeating: 0, count: bufferSize)
    }

    deinit { buffer.deallocate() }

    func start() {
        active = true
        IOHIDDeviceRegisterInputReportCallback(device, buffer, bufferSize, { context, result, _, _, _, bytes, length in
            guard result == kIOReturnSuccess, let context, length > 0 else { return }
            let session = Unmanaged<HIDPPSession>.fromOpaque(context).takeUnretainedValue()
            session.receive(Array(UnsafeBufferPointer(start: bytes, count: length)))
        }, Unmanaged.passUnretained(self).toOpaque())
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
        IOHIDDeviceRegisterInputReportCallback(device, buffer, bufferSize, nil, nil)
        pending.removeAll()
    }

    func discover() {
        guard active, Date().timeIntervalSince(lastDiscovery) > 2 else { return }
        lastDiscovery = Date()
        let transport = string(kIOHIDTransportKey)
        let indices: [UInt8] = transport == "USB" ? Array(1...6) : [0xFF]
        for slot in indices where slots[slot] == nil && pending[slot] == nil {
            query(slot, feature: 0, function: 0, parameters: [0x1B, 0x04, 0])
        }
    }

    private func query(_ slot: UInt8, feature: UInt8, function: UInt8, parameters: [UInt8] = []) {
        guard active else { return }
        let data: [UInt8] = [0x10, slot, feature, (function << 4) | softwareID] + Array((parameters + [0, 0, 0]).prefix(3))
        pending[slot] = Request(feature: feature, function: function, expires: Date().addingTimeInterval(2))
        let result = data.withUnsafeBufferPointer { IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0x10, $0.baseAddress!, data.count) }
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

    private func receive(_ bytes: [UInt8]) {
        guard active, let packet = HIDPPPacket(bytes) else { return }
        let slotIndex = packet.deviceIndex
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
            let binding = HIDBinding(productID: number(kIOHIDProductIDKey), locationID: number(kIOHIDLocationIDKey),
                transport: string(kIOHIDTransportKey), product: string(kIOHIDProductKey), usage: UInt32(edge.control),
                reportID: 0x11, deviceIndex: slotIndex, controlID: edge.control)
            onButton?(binding, edge.down)
        }
    }

    private func number(_ key: String) -> Int { (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue ?? 0 }
    private func string(_ key: String) -> String { IOHIDDeviceGetProperty(device, key as CFString) as? String ?? "" }
}
