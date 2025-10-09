import CoreBluetooth
import Foundation

final class PhomemoWriter: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var url: URL?
    private var ready = false
    private var central: CBCentralManager!
    private var targetPeripheral: CBPeripheral? = nil
    private var writeChar: CBCharacteristic? = nil
    private let targetServiceUUID = CBUUID(string: "00001812-0000-1000-8000-00805F9B34FB")
    
    public init?(url: URL) {
        super.init()
        self.url = url
        self.central = CBCentralManager(delegate: self, queue: .main)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else {
            print("Bluetooth not ready: \(central.state.rawValue)")
            return
        }
        print("Scanning for peripherals…")
        central.scanForPeripherals(withServices: [targetServiceUUID], options: nil)
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        print("Found \(peripheral.name ?? "<unknown>") — connecting…")
        self.targetPeripheral = peripheral
        self.central.stopScan()
        self.central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("Connected! Discovering services…")
        peripheral.delegate = self
        peripheral.discoverServices(nil)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else { return print("Service discovery failed:", error!) }
        guard let services = peripheral.services else { return print("No services found") }
        
        // There is only one service, FF00
        let service = services.first!
        print("Did discover service \(services)")
        peripheral.discoverCharacteristics(nil, for: service)
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard error == nil else { return print("Characteristic discovery failed:", error!) }
        guard let chars = service.characteristics else { return print("No characteristics found for service \(service)") }
        print("Did discover charateristics")
        
        for char in chars {
            print("Char \(char.uuid) properties: \(char.properties.rawValue)")
            if char.properties.contains(.notify) {
                print("  → supports notify")
                peripheral.setNotifyValue(true, for: char)
            }
            if char.properties.contains(.read) {
                print("  → supports read")
            }
            if char.properties.contains(.indicate) {
                print("  → supports indicate")
            }
        }

        let writeChar = chars[1] // FF02
        self.writeChar = writeChar
        
        Task {
            await pollUntilReady(peripheral: peripheral, characteristic: writeChar)
        }
        
        guard let url = self.url else { return }
        writeFileData(url: url, peripheral: peripheral, characteristic: writeChar)
    }
    
    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error = error {
            print("Notify failed:", error.localizedDescription)
            
            if error.localizedDescription.contains("Encryption is insufficient") {
                print("➡️  Try pairing the printer in Bluetooth settings first.")
            }
            
            return
        }
        print("Notifications enabled for \(characteristic.uuid)")
    }
    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            print("Error reading characteristic:", error.localizedDescription)
            return
        }

        print("Notification from \(characteristic.uuid)")
        guard let data = characteristic.value else { return }
        let bytes = [UInt8](data)
        print("-- : \(bytes)")
        
        if bytes.count > 2 && bytes[1] == 3 && bytes[2] == 169 {
            print("🔥 Too hot, please let me take a break")
            self.ready = false
            return
        }
        
        if bytes.count > 2 && bytes[1] == 3 && bytes[2] == 168 {
            print("🌡️ Temperature is normal");
            return
        }
        
        if bytes.count > 2 && bytes[1] == 5 && bytes[2] == 153 {
            print("📖 Cover open")
            self.ready = false
            return
        }
        
        if bytes.count > 2 && bytes[1] == 5 && bytes[2] == 152 {
            print("🚪 Printer cover is closed");
            return
        }
        
        if bytes.count > 2 && bytes[1] == 6 && bytes[2] == 136 {
            print("🚫 No paper")
            self.ready = false
            return
        }
        
        if bytes.count > 2 && bytes[1] == 6 && bytes[2] == 137 {
            print("📃 Have paper");
            return
        }
        
        if bytes.count > 2 && bytes[1] == 11 && bytes[2] == 184 {
            print("🛑 Cancel");
            return
        }
        
        if bytes.count > 2 && bytes[1] == 15 && bytes[2] == 12 {
            print("✅ Print complete");
            return
        }
        
        if !self.ready {
            print("🖨️ Ready");
            self.ready = true
        }

        // print("🔌 I have no electricity, please charge")
    }
    
    private func pollUntilReady(peripheral: CBPeripheral, characteristic: CBCharacteristic) async {        
        while !ready {
            // Turn on notifications: "SSSGETSN\r\n"
            let sn = Data([83, 83, 83, 71, 69, 84, 83, 78, 13, 10])
            peripheral.writeValue(sn, for: characteristic, type: .withResponse)
            
            let compressMode = Data([83, 83, 83, 71, 69, 84, 66, 77, 65, 80, 77, 79, 68, 69, 13, 10])
            peripheral.writeValue(compressMode, for: characteristic, type: .withResponse)
            
            let askPaper = Data([31,17,17])
            peripheral.writeValue(askPaper, for: characteristic, type: .withoutResponse)
            
            let askCover = Data([31,17,18])
            peripheral.writeValue(askCover, for: characteristic, type: .withoutResponse)

            // Wait 0.5 seconds between writes
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }
    
    private func writeFileData(url: URL, peripheral: CBPeripheral, characteristic: CBCharacteristic) {
        if let image = PhomemoImage(url: url),
           let imageData = image.toPhomemoData(dithered: true) {
        
            // The phomemo printer can handle full buffer writes, but often with BLE you
            // need to slow things down, leaving this here in case we need to handle long
            // prints and transfers
            let writeSlowly: Bool = false

            do {
                let data = imageData
                if writeSlowly {
                    let mtu = peripheral.maximumWriteValueLength(for: .withoutResponse)
                    print("Writing \(data.count) bytes in chunks of \(mtu)")
                    
                    var offset = 0
                    while offset < data.count {
                        let chunkSize = min(mtu, data.count - offset)
                        let chunk = data.subdata(in: offset ..< offset + chunkSize)
                        peripheral.writeValue(chunk, for: characteristic, type: .withoutResponse)
                        offset += chunkSize
                        // Small delay to avoid flooding BLE buffer
                        usleep(20_000)
                    }
                } else {
                    peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
                }

                print("✅ Finished writing file.")
            }
        } else {
            print("❌ Failed to convert image.")
        }
    }
    
    func crc8(_ data: Data) -> UInt8 {
        var crc: UInt8 = 0
        for byte in data {
            let b = byte
            crc ^= b
            for _ in 0..<8 {
                if (crc & 0x80) != 0 {
                    crc = (crc << 1) ^ 0x07
                } else {
                    crc <<= 1
                }
            }
        }
        return crc & 0xFF
    }

    func formatMessage(command: UInt8, data: Data) -> Data {
        var message = Data([0x51, 0x78, command, 0x00, UInt8(data.count), 0x00])
        message.append(data)
        message.append(crc8(data))
        message.append(0xFF)
        
        return message
    }
}
