import CoreBluetooth
import Foundation

protocol PhomemoWriterDelegate: AnyObject {
    func writerDidStartScanning(_ writer: PhomemoWriter)
    func writerDidConnect(_ writer: PhomemoWriter)
    func writerDidBecomeReady(_ writer: PhomemoWriter)
    func writer(_ writer: PhomemoWriter, didUpdatePaperStatus hasPaper: Bool)
    func writer(_ writer: PhomemoWriter, didUpdateCoverStatus closed: Bool)
    func writer(_ writer: PhomemoWriter, didUpdateTemperatureStatus ok: Bool)
    func writerDidCompletePrint(_ writer: PhomemoWriter)
    func writer(_ writer: PhomemoWriter, didFailWithError error: String)
}

final class PhomemoWriter: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private weak var delegate: PhomemoWriterDelegate?
    private var ready = false
    private var central: CBCentralManager!
    private var targetPeripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?
    private let targetServiceUUID = CBUUID(string: "00001812-0000-1000-8000-00805F9B34FB")

    init(delegate: PhomemoWriterDelegate) {
        super.init()
        self.delegate = delegate
        self.central = CBCentralManager(delegate: self, queue: .main)
    }

    func printImage(from url: URL) {
        guard let peripheral = targetPeripheral,
              let characteristic = writeChar else {
            delegate?.writer(self, didFailWithError: "Printer not connected")
            return
        }

        guard let image = PhomemoImage(url: url),
              let imageData = image.toPhomemoData(dithered: true) else {
            delegate?.writer(self, didFailWithError: "Failed to convert image")
            return
        }

        peripheral.writeValue(imageData, for: characteristic, type: .withoutResponse)
        print("Finished writing image data")
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("Bluetooth powered on - starting scan")
            delegate?.writerDidStartScanning(self)
            central.scanForPeripherals(withServices: [targetServiceUUID], options: nil)
        case .poweredOff:
            delegate?.writer(self, didFailWithError: "Bluetooth is powered off")
        case .unauthorized:
            delegate?.writer(self, didFailWithError: "Bluetooth unauthorized")
        case .unsupported:
            delegate?.writer(self, didFailWithError: "Bluetooth unsupported")
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        print("Found \(peripheral.name ?? "<unknown>") - connecting...")
        self.targetPeripheral = peripheral
        self.central.stopScan()
        self.central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Connected! Discovering services...")
        delegate?.writerDidConnect(self)
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        delegate?.writer(self, didFailWithError: "Failed to connect: \(error?.localizedDescription ?? "unknown")")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        ready = false
        delegate?.writer(self, didFailWithError: "Printer disconnected")
        // Try to reconnect
        central.scanForPeripherals(withServices: [targetServiceUUID], options: nil)
    }

    // MARK: - CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            delegate?.writer(self, didFailWithError: "Service discovery failed: \(error!.localizedDescription)")
            return
        }
        guard let services = peripheral.services, let service = services.first else {
            delegate?.writer(self, didFailWithError: "No services found")
            return
        }

        print("Discovered service \(service)")
        peripheral.discoverCharacteristics(nil, for: service)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard error == nil else {
            delegate?.writer(self, didFailWithError: "Characteristic discovery failed: \(error!.localizedDescription)")
            return
        }
        guard let chars = service.characteristics else {
            delegate?.writer(self, didFailWithError: "No characteristics found")
            return
        }

        print("Discovered characteristics")

        for char in chars {
            if char.properties.contains(.notify) {
                peripheral.setNotifyValue(true, for: char)
            }
        }

        // FF02 is the write characteristic
        if chars.count > 1 {
            self.writeChar = chars[1]
        }

        Task {
            await pollUntilReady(peripheral: peripheral, characteristic: chars[1])
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error = error {
            print("Notify failed: \(error.localizedDescription)")
            if error.localizedDescription.contains("Encryption is insufficient") {
                delegate?.writer(self, didFailWithError: "Pair the printer in Bluetooth settings first")
            }
            return
        }
        print("Notifications enabled for \(characteristic.uuid)")
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("Error reading characteristic: \(error.localizedDescription)")
            return
        }

        guard let data = characteristic.value else { return }
        let bytes = [UInt8](data)
        print("Notification: \(bytes)")

        // Parse printer status messages
        guard bytes.count > 2 else { return }

        switch (bytes[1], bytes[2]) {
        case (3, 169): // Too hot
            print("Too hot")
            ready = false
            delegate?.writer(self, didUpdateTemperatureStatus: false)

        case (3, 168): // Temperature normal
            print("Temperature normal")
            delegate?.writer(self, didUpdateTemperatureStatus: true)

        case (5, 153): // Cover open
            print("Cover open")
            ready = false
            delegate?.writer(self, didUpdateCoverStatus: false)

        case (5, 152): // Cover closed
            print("Cover closed")
            delegate?.writer(self, didUpdateCoverStatus: true)

        case (6, 136): // No paper
            print("No paper")
            ready = false
            delegate?.writer(self, didUpdatePaperStatus: false)

        case (6, 137): // Have paper
            print("Have paper")
            delegate?.writer(self, didUpdatePaperStatus: true)

        case (11, 184): // Cancel
            print("Print cancelled")

        case (15, 12): // Print complete
            print("Print complete")
            delegate?.writerDidCompletePrint(self)

        default:
            if !ready {
                print("Printer ready")
                ready = true
                delegate?.writerDidBecomeReady(self)
            }
        }
    }

    private func pollUntilReady(peripheral: CBPeripheral, characteristic: CBCharacteristic) async {
        while !ready {
            // Query serial number
            let sn = Data([83, 83, 83, 71, 69, 84, 83, 78, 13, 10])
            peripheral.writeValue(sn, for: characteristic, type: .withResponse)

            // Query compress mode
            let compressMode = Data([83, 83, 83, 71, 69, 84, 66, 77, 65, 80, 77, 79, 68, 69, 13, 10])
            peripheral.writeValue(compressMode, for: characteristic, type: .withResponse)

            // Ask paper status
            let askPaper = Data([31, 17, 17])
            peripheral.writeValue(askPaper, for: characteristic, type: .withoutResponse)

            // Ask cover status
            let askCover = Data([31, 17, 18])
            peripheral.writeValue(askCover, for: characteristic, type: .withoutResponse)

            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }
}
