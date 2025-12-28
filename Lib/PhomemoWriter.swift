import CoreBluetooth
import CoreGraphics
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

    func printImage(_ image: PhomemoImage) {
        guard let peripheral = targetPeripheral,
              let characteristic = writeChar else {
            delegate?.writer(self, didFailWithError: "Printer not connected")
            return
        }

        let imageData = Self.data(from: image.dithered)
        peripheral.writeValue(imageData, for: characteristic, type: .withoutResponse)
        print("Finished writing image data")
    }

    private static func data(from image: CGImage) -> Data {
        let width = image.width
        let height = image.height

        guard let buf = image.dataProvider?.data,
              let pixels = CFDataGetBytePtr(buf) else { return Data() }

        var remaining = height
        var y = 0

        var data = Data()
        data.append(header())

        while remaining > 0 {
            var lines = remaining
            if lines > 256 { lines = 256 }
            data.append(marker(lines: UInt8(lines - 1)))
            remaining -= lines
            while lines > 0 {
                data.append(line(pixels: pixels, width: width, row: y))
                lines -= 1
                y += 1
            }
        }
        data.append(footer())

        return data
    }

    private static func header() -> Data {
        Data([0x1b, 0x40, 0x1b, 0x61, 0x01, 0x1f, 0x11, 0x02, 0x04])
    }

    private static func marker(lines: UInt8) -> Data {
        Data([
            0x1d, 0x76,
            0x30, 0x00,
            0x30, 0x00,
            lines, 0x00
        ])
    }

    private static func line(pixels: UnsafePointer<UInt8>, width: Int, row: Int) -> Data {
        var data = Data()
        for x in 0..<(width) / 8 {
            var byte: UInt8 = 0
            for bit in 0..<8 {
                let pixelX = x * 8 + bit
                if pixels[row * width + pixelX] == 0 {
                    byte |= 1 << (7 - bit)
                }
            }
            if byte == 0x0a {
                byte = 0x14
            }
            data.append(byte)
        }
        return data
    }

    private static func footer() -> Data {
        Data([
            0x1b, 0x64, 0x02,
            0x1b, 0x64, 0x02,
            0x1f, 0x11, 0x08,
            0x1f, 0x11, 0x0e,
            0x1f, 0x11, 0x07,
            0x1f, 0x11, 0x09
        ])
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

        for char in chars where char.properties.contains(.notify) {
            peripheral.setNotifyValue(true, for: char)
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

    // swiftlint:disable:next cyclomatic_complexity
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
        case (0x03, 0xa9): // Too hot
            print("Too hot")
            ready = false
            delegate?.writer(self, didUpdateTemperatureStatus: false)

        case (0x03, 0xa8): // Temperature normal
            print("Temperature normal")
            delegate?.writer(self, didUpdateTemperatureStatus: true)

        case (0x05, 0x99): // Cover open
            print("Cover open")
            ready = false
            delegate?.writer(self, didUpdateCoverStatus: false)

        case (0x05, 0x98): // Cover closed
            print("Cover closed")
            delegate?.writer(self, didUpdateCoverStatus: true)

        case (0x06, 0x88): // No paper
            print("No paper")
            ready = false
            delegate?.writer(self, didUpdatePaperStatus: false)

        case (0x06, 0x89): // Have paper
            print("Have paper")
            delegate?.writer(self, didUpdatePaperStatus: true)

        case (0x0b, 0xb8): // Cancel
            print("Print cancelled")

        case (0x0f, 0x0c): // Print complete
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
            // Query serial number: "SSSGETSN\r\n"
            let sn = Data([0x53, 0x53, 0x53, 0x47, 0x45, 0x54, 0x53, 0x4e, 0x0d, 0x0a])
            peripheral.writeValue(sn, for: characteristic, type: .withResponse)

            // Query compress mode: "SSSGETBMAPMODE\r\n"
            let compressMode = Data([
                0x53, 0x53, 0x53, 0x47, 0x45, 0x54,
                0x42, 0x4d, 0x41, 0x50, 0x4d, 0x4f, 0x44, 0x45,
                0x0d, 0x0a
            ])
            peripheral.writeValue(compressMode, for: characteristic, type: .withResponse)

            // Ask paper status
            let askPaper = Data([0x1f, 0x11, 0x11])
            peripheral.writeValue(askPaper, for: characteristic, type: .withoutResponse)

            // Ask cover status
            let askCover = Data([0x1f, 0x11, 0x12])
            peripheral.writeValue(askCover, for: characteristic, type: .withoutResponse)

            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }
}
