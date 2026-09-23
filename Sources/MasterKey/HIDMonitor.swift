import Foundation
import IOKit.hid
import BridgeCore

final class HIDMonitor {
    private var manager: IOHIDManager?
    private(set) var isOpen = false
    var onButton: ((HIDBinding, Bool) -> Void)?
    var onDevices: (([String]) -> Void)?
    var onStatus: ((String) -> Void)?
    var onDisconnect: (() -> Void)?

    func start() {
        stop()
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager
        // Match only Logitech mouse collections, never keyboards or vendor command channels.
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey: 0x046D,
            kIOHIDDeviceUsagePageKey: 0x01,
            kIOHIDDeviceUsageKey: 0x02
        ] as CFDictionary)
        IOHIDManagerSetInputValueMatching(manager, [kIOHIDElementUsagePageKey: 0x09] as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(manager, { context, result, _, value in
            guard result == kIOReturnSuccess, let context else { return }
            Unmanaged<HIDMonitor>.fromOpaque(context).takeUnretainedValue().receive(value)
        }, context)
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, _ in
            guard let context else { return }
            Unmanaged<HIDMonitor>.fromOpaque(context).takeUnretainedValue().updateDevices()
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, _, _, _ in
            guard let context else { return }
            let monitor = Unmanaged<HIDMonitor>.fromOpaque(context).takeUnretainedValue()
            monitor.onDisconnect?()
            monitor.updateDevices()
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        // Deliberately shared. Never seize the mouse, send HID++ commands, or change its settings.
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        isOpen = result == kIOReturnSuccess
        if result == kIOReturnSuccess {
            onStatus?(L10n.text(.standardConnected))
        } else {
            onStatus?(L10n.format(.standardFailed, UInt32(bitPattern: result)))
        }
        updateDevices()
    }

    func stop() {
        isOpen = false
        guard let manager else { return }
        IOHIDManagerRegisterInputValueCallback(manager, nil, nil)
        IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil
    }

    private func updateDevices() {
        guard let manager else { return }
        let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
        onDevices?(devices.map { device in
            let product = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Logitech Mouse"
            let transport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String ?? "HID"
            return "\(product) · \(transport)"
        }.sorted())
    }

    private func receive(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let usage = IOHIDElementGetUsage(element)
        guard IOHIDElementGetUsagePage(element) == 0x09, usage >= 3 else { return }
        let device = IOHIDElementGetDevice(element)
        func number(_ key: String) -> Int { (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue ?? 0 }
        func string(_ key: String) -> String { IOHIDDeviceGetProperty(device, key as CFString) as? String ?? "" }
        let binding = HIDBinding(productID: number(kIOHIDProductIDKey), locationID: number(kIOHIDLocationIDKey),
                                 transport: string(kIOHIDTransportKey), product: string(kIOHIDProductKey),
                                 usage: usage, reportID: IOHIDElementGetReportID(element))
        onButton?(binding, IOHIDValueGetIntegerValue(value) != 0)
    }
}
