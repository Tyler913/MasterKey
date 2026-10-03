import Foundation
import CoreBluetooth
import BridgeCore

/// HID++ for Logitech devices connected directly over Bluetooth. Options+ exchanges HID++
/// with these devices through Logitech's GATT service instead of the HID interface, so
/// diverted-button events only arrive there. macOS delivers each notification to every
/// subscriber, and this listener sends only the same read-only queries as `HIDPPMonitor`.
final class BluetoothHIDPPMonitor: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private static let service = CBUUID(string: "00010000-0000-1000-8000-011F2000046D")
    private static let characteristic = CBUUID(string: "00010001-0000-1000-8000-011F2000046D")
    private var central: CBCentralManager?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var sessions: [UUID: HIDPPSession] = [:]
    private var timer: Timer?
    private(set) var isAvailable = false
    var isRunning: Bool { central != nil }
    var onButton: ((HIDBinding, Bool) -> Void)?
    var onStatus: ((String) -> Void)?
    var onDisconnect: (() -> Void)?

    /// Creating the central manager is what asks for Bluetooth access, so callers start the
    /// monitor only once a Logitech Bluetooth device is present.
    func start() {
        stop()
        central = CBCentralManager(delegate: self, queue: .main)
        // macOS has no connection event for peripherals the system connected, so poll.
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in self?.connectPeripherals() }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        removeAll()
        central?.delegate = nil
        central = nil
        isAvailable = false
    }

    func rediscover() {
        connectPeripherals()
        sessions.values.forEach { $0.discover() }
    }

    /// Releases this app's claim only. The system keeps the link for the HID connection.
    private func removeAll() {
        sessions.values.forEach { $0.stop() }
        sessions.removeAll()
        for peripheral in peripherals.values {
            peripheral.delegate = nil
            central?.cancelPeripheralConnection(peripheral)
        }
        peripherals.removeAll()
    }

    private func connectPeripherals() {
        guard let central, central.state == .poweredOn else { return }
        for peripheral in central.retrieveConnectedPeripherals(withServices: [Self.service]) where peripherals[peripheral.identifier] == nil {
            peripherals[peripheral.identifier] = peripheral
            peripheral.delegate = self
            central.connect(peripheral)
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        isAvailable = central.state == .poweredOn
        if isAvailable { connectPeripherals(); return }
        removeAll()
        if central.state == .unauthorized { onStatus?(L10n.text(.bluetoothDenied)) }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([Self.service])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        // Retried by the next poll.
        peripherals.removeValue(forKey: peripheral.identifier)
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        peripherals.removeValue(forKey: peripheral.identifier)
        sessions.removeValue(forKey: peripheral.identifier)?.stop()
        onDisconnect?()
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for service in peripheral.services ?? [] where service.uuid == Self.service {
            peripheral.discoverCharacteristics([Self.characteristic], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for characteristic in service.characteristics ?? [] where characteristic.uuid == Self.characteristic {
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.isNotifying, sessions[peripheral.identifier] == nil else { return }
        let writeType: CBCharacteristicWriteType = characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
        let session = HIDPPSession(identity: identity(of: peripheral), longReports: true) { [weak peripheral] report in
            guard let peripheral, peripheral.state == .connected,
                  let value = HIDPPPacket.bluetoothValue(fromReport: report) else { return kIOReturnNotReady }
            peripheral.writeValue(Data(value), for: characteristic, type: writeType)
            return kIOReturnSuccess
        }
        session.onStatus = { [weak self] in self?.onStatus?($0) }
        session.onButton = { [weak self] in self?.onButton?($0, $1) }
        sessions[peripheral.identifier] = session
        session.start()
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error { onStatus?(L10n.format(.hidppQueryFailed, UInt32(truncatingIfNeeded: (error as NSError).code))) }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == Self.characteristic, let value = characteristic.value,
              let report = HIDPPPacket.report(fromBluetooth: Array(value)) else { return }
        sessions[peripheral.identifier]?.receive(report)
    }

    /// The peripheral identifier is stable for this Mac and device, so recorded buttons
    /// survive reconnection. The product ID is not exposed over this channel.
    private func identity(of peripheral: CBPeripheral) -> HIDPPSession.Identity {
        let id = peripheral.identifier.uuid
        let location = Int(id.0) << 24 | Int(id.1) << 16 | Int(id.2) << 8 | Int(id.3)
        return .init(productID: 0, locationID: location, transport: "Bluetooth Low Energy", product: peripheral.name ?? "Logitech")
    }
}
