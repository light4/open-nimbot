import CoreBluetooth
import SwiftUI

@main
struct OpenNimbotApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct Printer: Identifiable {
    let peripheral: CBPeripheral
    var id: UUID { peripheral.identifier }
    var name: String { peripheral.name ?? "Unnamed printer" }
}

final class BluetoothManager: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    @Published var printers: [Printer] = []
    @Published var status = "Bluetooth starting…"
    @Published var media = "Label media: not read"
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
            peripheral.setNotifyValue(true, for: characteristic)
            status = "Ready to print."
        } else {
            status = "NIMBOT print channel was not found."
        }
    }

    func readMedia() {
        guard let characteristic, let peripheral = connectedPrinter?.peripheral else { return }
        responseBuffer = Data()
        media = "Reading label media…"
        for query in NimbotProtocol.mediaQueries() {
            peripheral.writeValue(query, for: characteristic, type: .withResponse)
        }
    }

    func print(_ text: String, fontName: String, fontSize: CGFloat) {
        guard let characteristic, !text.isEmpty else { return }
        queue = NimbotProtocol.printFrames(text: text, fontName: fontName, fontSize: fontSize)
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
            let length = Int(responseBuffer[responseBuffer.startIndex + 3])
            let packetLength = length + 7
            guard responseBuffer.count >= packetLength else { return }
            let packet = responseBuffer.prefix(packetLength)
            responseBuffer.removeFirst(packetLength)
            let command = packet[packet.startIndex + 2]
            let body = Array(packet.dropFirst(4).dropLast(3))
            switch command {
            case 0x1B:
                media = NimbotProtocol.mediaDescription(body)
            case 0x43:
                media += " · type \(body.first ?? 0)"
            case 0x4F:
                media += " · area \(body.map { String(format: "%02X", $0) }.joined())"
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
        let data = queue.removeFirst()
        connectedPrinter?.peripheral.writeValue(data, for: characteristic, type: .withResponse)
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

struct ContentView: View {
    @StateObject private var bluetooth = BluetoothManager()
    @State private var text = "你好，NIMBOT"
    @State private var fontName = "System"
    @State private var fontSize = 24.0
    private let fontNames = ["System", "Hiragino Sans GB", "Songti SC", "Menlo"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("OpenNimbot").font(.largeTitle)
            Text(bluetooth.status).foregroundStyle(.secondary)
            HStack {
                Button("Scan", action: bluetooth.scan)
                Button("Read label media", action: bluetooth.readMedia)
                    .disabled(bluetooth.connectedPrinter == nil)
                if let printer = bluetooth.connectedPrinter {
                    Text("Connected: \(printer.name)")
                }
            }
            Text(bluetooth.media).font(.caption).textSelection(.enabled)
            List(bluetooth.printers) { printer in
                HStack {
                    Text(printer.name)
                    Spacer()
                    Button("Connect") { bluetooth.connect(printer) }
                }
            }.frame(height: 160)
            TextEditor(text: $text).font(.system(size: 20)).frame(height: 100)
            HStack {
                Picker("Font", selection: $fontName) {
                    ForEach(fontNames, id: \.self) { Text($0) }
                }
                .pickerStyle(.menu)
                Stepper("Size: \(Int(fontSize))", value: $fontSize, in: 10...48, step: 1)
            }
            GroupBox("Print preview") {
                Image(nsImage: NimbotProtocol.preview(text: text, fontName: fontName, fontSize: fontSize))
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 320)
                    .padding(8)
            }
            Button("Print label") { bluetooth.print(text, fontName: fontName, fontSize: fontSize) }
                .disabled(bluetooth.connectedPrinter == nil || text.isEmpty)
        }
        .padding()
        .frame(minWidth: 440, minHeight: 620)
    }
}
