// Read-only HID++ capability probe. No button diversion / configuration commands.
import Foundation
import IOKit.hid
setbuf(stdout, nil)
var features: [UInt8: UInt8] = [:]

let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
// Receivers and wired devices use 0xFF00; devices connected over Bluetooth use 0xFF43.
IOHIDManagerSetDeviceMatchingMultiple(manager, [0xFF00, 0xFF43].map {
    [kIOHIDVendorIDKey: 0x046D, kIOHIDDeviceUsagePageKey: $0]
} as CFArray)
IOHIDManagerRegisterInputReportCallback(manager, { _, result, _, _, _, bytes, length in
    guard result == kIOReturnSuccess, length >= 7 else { return }
    let data = Array(UnsafeBufferPointer(start: bytes, count: length))
    // Only print responses to this probe's GetFeature request, never arbitrary input.
    if data[2] == 0 && data[3] == 0x0E {
        print("GetFeature reply:", data.prefix(8).map { String(format: "%02X", $0) }.joined(separator: " "))
        if data[4] != 0 { features[data[1]] = data[4] }
    } else if data.count >= 12, features[data[1]] == data[2], data[3] == 0 {
        let controls = stride(from: 4, to: 12, by: 2).map { UInt16(data[$0]) << 8 | UInt16(data[$0 + 1]) }
        print("Mouse controls currently pressed:", controls.filter { $0 != 0 }.map { String(format: "0x%04X", $0) })
    }
}, nil)
IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
let result = IOHIDManagerOpen(manager, 0)
print(String(format: "Shared vendor interface open: 0x%08X", UInt32(bitPattern: result)))
let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
print("Vendor interfaces:", devices.count)
for device in devices {
    let transport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String ?? ""
    let usagePage = (IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? NSNumber)?.intValue ?? 0
    let outputs = IOHIDDeviceCopyMatchingElements(device, [kIOHIDElementTypeKey: kIOHIDElementTypeOutput.rawValue] as CFDictionary, 0) as? [IOHIDElement] ?? []
    let reportIDs = Set(outputs.map(IOHIDElementGetReportID))
    // Bluetooth devices declare only the long report.
    let long = !reportIDs.contains(0x10) && (reportIDs.contains(0x11) || transport.hasPrefix("Bluetooth"))
    print(String(format: "Interface: %@ · usage page 0x%04X · output reports %@ · %@ reports", transport, usagePage,
                 reportIDs.sorted().map { String(format: "0x%02X", $0) }.joined(separator: ","), long ? "long" : "short"))
    let slots: [UInt8] = transport == "USB" ? Array(1...6) + [0xFF] : [0xFF]
    for slot in slots {
        // IRoot.GetFeature(0x1B04), software ID E; no device setting is changed.
        let query: [UInt8] = [long ? 0x11 : 0x10, slot, 0, 0x0E, 0x1B, 0x04] + Array(repeating: 0, count: long ? 14 : 1)
        let sent = query.withUnsafeBufferPointer { IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(query[0]), $0.baseAddress!, query.count) }
        print(String(format: "Read-only query slot %d: 0x%08X", slot, UInt32(bitPattern: sent)))
        CFRunLoopRunInMode(.defaultMode, 0.2, false)
    }
}
print("Listening for mouse button reports for 45 seconds...")
CFRunLoopRunInMode(.defaultMode, 45, false)
IOHIDManagerClose(manager, 0)
