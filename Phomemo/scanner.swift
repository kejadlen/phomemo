import Foundation
import CoreBluetooth

final class Scanner: NSObject, CBCentralManagerDelegate {
    private var central: CBCentralManager!
    private var discovered = Set<UUID>()
    private var name: String?

    public init?(name: String?) {
        super.init()
        self.name = name
        self.central = CBCentralManager(delegate: self, queue: .main)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .unknown:
            print("State: unknown")
        case .resetting:
            print("State: resetting")
        case .unsupported:
            print("Bluetooth unsupported on this device")
            exit(1)
        case .unauthorized:
            print("Bluetooth unauthorized. Check your Info.plist usage string / permissions.")
            exit(1)
        case .poweredOff:
            print("Bluetooth is powered off. Turn it on.")
            exit(1)
        case .poweredOn:
            print("Bluetooth powered on — starting scan")
            startScanning()
        @unknown default:
            print("Unknown central state")
        }
    }

    private func startScanning() {
        // nil to scan for all peripherals; add services array to filter
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        // Stop scan after 30s as an example
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            self?.stopScanningAndExit()
        }
    }

    private func stopScanningAndExit() {
        central.stopScan()
        print("Stopped scanning — exiting")
        // Give any final logs a moment then exit
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            exit(0)
        }
    }

    // Peripheral discovery callback
    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        
        if let name = self.name {
            // For example, if we only want a T02 phomemo printer
            if peripheral.name != name {
                return
            }
        }
        
        // Avoid duplicate prints for same peripheral
        if discovered.insert(peripheral.identifier).inserted {
            let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? "<unknown>"
            print("Discovered: \(name) (\(peripheral.identifier.uuidString)) RSSI: \(RSSI)")
            if let services = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID], !services.isEmpty {
                for service in services {
                    if service.uuidString.count == 4 {                    
                        print("  └── \(service) (UUID: 0000\(service.uuidString)-0000-1000-8000-00805F9B34FB")
                    } else {
                        print("  └── \(service) (UUID: \(service.uuidString)")
                    }
                }
            }
        }
    }        
}
