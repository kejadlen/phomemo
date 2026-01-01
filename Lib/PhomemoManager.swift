import CoreBluetooth
import CoreGraphics
import Foundation

struct NotReadyReason: OptionSet {
    let rawValue: Int
    static let noPaper    = NotReadyReason(rawValue: 1 << 0)
    static let coverOpen  = NotReadyReason(rawValue: 1 << 1)
    static let overheated = NotReadyReason(rawValue: 1 << 2)
}

enum PrinterState {
    case disconnected
    case scanning
    case connecting
    case ready(ReadyPrinter)
    case printing
    case notReady(NotReadyReason)
    case error(String)
}

struct ReadyPrinter {
    private let manager: PhomemoManager

    fileprivate init(manager: PhomemoManager) {
        self.manager = manager
    }

    func print(_ image: PhomemoImage) {
        manager.printImage(image)
    }
}

protocol PhomemoManagerDelegate: AnyObject {
    func manager(_ manager: PhomemoManager, didChangeState state: PrinterState)
}

final class PhomemoManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private weak var delegate: PhomemoManagerDelegate?
    private var central: CBCentralManager!
    private var targetPeripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?
    private let targetServiceUUID = CBUUID(string: "00001812-0000-1000-8000-00805F9B34FB")

    private var statusFlags: NotReadyReason = []
    private var connected = false

    private(set) var state: PrinterState = .disconnected {
        didSet { delegate?.manager(self, didChangeState: state) }
    }

    init(delegate: PhomemoManagerDelegate) {
        super.init()
        self.delegate = delegate
        self.central = CBCentralManager(delegate: self, queue: .main)
    }

    private func updateReadyState() {
        guard connected else { return }
        if statusFlags.isEmpty {
            state = .ready(ReadyPrinter(manager: self))
        } else {
            state = .notReady(statusFlags)
        }
    }

    fileprivate func printImage(_ image: PhomemoImage) {
        guard let peripheral = targetPeripheral,
              let characteristic = writeChar else { return }

        state = .printing
        let imageData = Self.data(from: image.dithered)
        peripheral.writeValue(imageData, for: characteristic, type: .withoutResponse)
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
            state = .scanning
            central.scanForPeripherals(withServices: [targetServiceUUID], options: nil)
        case .poweredOff:
            state = .error("Bluetooth is powered off")
        case .unauthorized:
            state = .error("Bluetooth unauthorized")
        case .unsupported:
            state = .error("Bluetooth unsupported")
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        self.targetPeripheral = peripheral
        self.central.stopScan()
        self.central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        state = .connecting
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        state = .error("Failed to connect: \(error?.localizedDescription ?? "unknown")")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        connected = false
        state = .disconnected
        // Try to reconnect
        central.scanForPeripherals(withServices: [targetServiceUUID], options: nil)
    }

    // MARK: - CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            state = .error("Service discovery failed: \(error!.localizedDescription)")
            return
        }
        guard let services = peripheral.services, let service = services.first else {
            state = .error("No services found")
            return
        }
        peripheral.discoverCharacteristics(nil, for: service)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard error == nil else {
            state = .error("Characteristic discovery failed: \(error!.localizedDescription)")
            return
        }
        guard let chars = service.characteristics else {
            state = .error("No characteristics found")
            return
        }

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
            if error.localizedDescription.contains("Encryption is insufficient") {
                state = .error("Pair the printer in Bluetooth settings first")
            }
            return
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value else { return }
        let bytes = [UInt8](data)

        guard bytes.count > 2 else { return }

        switch (bytes[1], bytes[2]) {
        case (0x03, 0xa9): // Too hot
            statusFlags.insert(.overheated)
            updateReadyState()

        case (0x03, 0xa8): // Temperature normal
            statusFlags.remove(.overheated)
            updateReadyState()

        case (0x05, 0x99): // Cover open
            statusFlags.insert(.coverOpen)
            updateReadyState()

        case (0x05, 0x98): // Cover closed
            statusFlags.remove(.coverOpen)
            updateReadyState()

        case (0x06, 0x88): // No paper
            statusFlags.insert(.noPaper)
            updateReadyState()

        case (0x06, 0x89): // Have paper
            statusFlags.remove(.noPaper)
            updateReadyState()

        case (0x0b, 0xb8): // Cancel
            updateReadyState()

        case (0x0f, 0x0c): // Print complete
            updateReadyState()

        default:
            if !connected {
                connected = true
                updateReadyState()
            }
        }
    }

    private func pollUntilReady(peripheral: CBPeripheral, characteristic: CBCharacteristic) async {
        while !connected {
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
