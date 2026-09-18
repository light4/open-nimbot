import CoreBluetooth
import SwiftUI

struct Printer: Identifiable {
    let peripheral: CBPeripheral
    var id: UUID { peripheral.identifier }
    var name: String { peripheral.name ?? "Unnamed printer" }
}

final class BluetoothManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published var printers: [Printer] = []
    @Published var status = "Bluetooth starting…"
    @Published var media = "Label media: not read"
    @Published var mediaProfile = LabelMedia.fallback
    @Published var connectedPrinter: Printer?

    private var central: CBCentralManager!
    private var characteristic: CBCharacteristic?
    private var responseBuffer = Data()
    private var queue: [Data] = []
    private var endingPrint = false

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else {
            status = "Bluetooth is \(central.state.description)."
            return
        }
        scan()
    }

    func scan() {
        guard central.state == .poweredOn else { return }
        printers = []
        status = "Scanning for B1 printers…"
        central.scanForPeripherals(withServices: nil)
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard (peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "").hasPrefix("B1-") else { return }
        if !printers.contains(where: { $0.id == peripheral.identifier }) {
            printers.append(Printer(peripheral: peripheral))
        }
    }

    func connect(_ printer: Printer) {
        central.stopScan()
        status = "Connecting to \(printer.name)…"
        central.connect(printer.peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedPrinter = Printer(peripheral: peripheral)
        peripheral.delegate = self
        peripheral.discoverServices([NimbotProtocol.service])
        status = "Connected; discovering print service…"
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        status = "Could not connect: \(error?.localizedDescription ?? "unknown error")"
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        characteristic = nil
        connectedPrinter = nil
        status = error == nil ? "Disconnected." : "Disconnected: \(error!.localizedDescription)"
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == NimbotProtocol.service }) else {
            status = "NIMBOT print service was not found."
            return
        }
        peripheral.discoverCharacteristics([NimbotProtocol.characteristic], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        characteristic = service.characteristics?.first(where: { $0.uuid == NimbotProtocol.characteristic })
        if let characteristic {
            status = "Preparing label media reader…"
            peripheral.setNotifyValue(true, for: characteristic)
        } else {
            status = "NIMBOT print channel was not found."
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, characteristic.uuid == NimbotProtocol.characteristic, characteristic.isNotifying else {
            status = "Could not enable the NIMBOT response channel."
            return
        }
        readMedia()
    }

    func readMedia() {
        guard let characteristic, let peripheral = connectedPrinter?.peripheral else { return }
        responseBuffer = Data()
        media = "Reading label media…"
        peripheral.writeValue(NimbotProtocol.mediaQueries()[0], for: characteristic, type: .withResponse)
    }

    func print(_ labels: [NSAttributedString]) {
        guard let characteristic, labels.allSatisfy({ $0.length > 0 }) else { return }
        queue = NimbotProtocol.printFrames(labels: labels, media: mediaProfile)
        endingPrint = true
        status = "Sending label…"
        writeNext(to: characteristic)
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            queue = []
            status = "Print failed: \(error.localizedDescription)"
            return
        }
        if !queue.isEmpty || endingPrint {
            writeNext(to: characteristic)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, characteristic.uuid == NimbotProtocol.characteristic, let value = characteristic.value else { return }
        responseBuffer.append(value)
        while responseBuffer.count >= 7 {
            guard responseBuffer[responseBuffer.startIndex] == 0x55, responseBuffer[responseBuffer.startIndex + 1] == 0x55 else {
                responseBuffer.removeFirst()
                continue
            }
            let packetLength = Int(responseBuffer[responseBuffer.startIndex + 3]) + 7
            guard responseBuffer.count >= packetLength else { return }
            let packet = responseBuffer.prefix(packetLength)
            responseBuffer.removeFirst(packetLength)
            switch packet[packet.startIndex + 2] {
            case 0x1B:
                let body = Array(packet.dropFirst(4).dropLast(3))
                if let profile = NimbotProtocol.mediaProfile(body) {
                    mediaProfile = profile
                }
                media = NimbotProtocol.mediaDescription(body)
            default:
                break
            }
        }
    }

    private func writeNext(to characteristic: CBCharacteristic) {
        guard !queue.isEmpty else {
            if endingPrint {
                endingPrint = false
                status = "Printing…"
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    guard let self, let characteristic = self.characteristic else { return }
                    self.queue = [NimbotProtocol.finishPrintFrame()]
                    self.status = "Finishing print…"
                    self.writeNext(to: characteristic)
                }
            } else {
                status = "Print sent."
            }
            return
        }
        connectedPrinter?.peripheral.writeValue(queue.removeFirst(), for: characteristic, type: .withResponse)
    }
}

private extension CBManagerState {
    var description: String {
        switch self {
        case .poweredOff: "powered off"
        case .unauthorized: "not authorized"
        case .unsupported: "unsupported"
        default: "unavailable"
        }
    }
}
