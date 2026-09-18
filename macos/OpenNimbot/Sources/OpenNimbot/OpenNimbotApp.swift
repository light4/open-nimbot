import AppKit
import CoreBluetooth
import SwiftUI

private let nimbotService = CBUUID(string: "E7810A71-73AE-499D-8C15-FAA9AEF0C3F2")
private let nimbotCharacteristic = CBUUID(string: "BEF8D6C9-9C21-4C9E-B632-BD58C1009F9F")

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
        peripheral.discoverServices([nimbotService])
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
        guard let service = peripheral.services?.first(where: { $0.uuid == nimbotService }) else {
            status = "NIMBOT print service was not found."
            return
        }
        peripheral.discoverCharacteristics([nimbotCharacteristic], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        characteristic = service.characteristics?.first(where: { $0.uuid == nimbotCharacteristic })
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
        peripheral.writeValue(frame(0x1A, [0x01]), for: characteristic, type: .withResponse)
        peripheral.writeValue(frame(0x40, [0x03]), for: characteristic, type: .withResponse)
        peripheral.writeValue(frame(0x40, [0x0F]), for: characteristic, type: .withResponse)
    }

    func print(_ text: String, fontName: String, fontSize: CGFloat) {
        guard let characteristic, !text.isEmpty else { return }
        let rows = rasterRows(text: text, width: 160, fontName: fontName, fontSize: fontSize)
        let height = rows.count
        queue = [
            frame(0x21, [0x03]), frame(0x23, [0x01]),
            frame(0x01, [0, 1, 0, 0, 0, 0, 0]), frame(0x03, [0x01]),
            frame(0x13, uint16(height) + uint16(160) + [0, 1])
        ]
        for (y, row) in rows.enumerated() {
            if row.allSatisfy({ $0 == 0 }) {
                queue.append(frame(0x84, uint16(y) + [0x01]))
            } else {
                let counts = [
                    UInt8(row.prefix(16).reduce(0) { $0 + $1.nonzeroBitCount }),
                    UInt8(row.dropFirst(16).reduce(0) { $0 + $1.nonzeroBitCount }),
                    0,
                ]
                queue.append(frame(0x85, uint16(y) + counts + [0x01] + row))
            }
        }
        queue.append(frame(0xE3, [0x01]))
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
        guard error == nil, characteristic.uuid == nimbotCharacteristic, let value = characteristic.value else { return }
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
            case 0x2A:
                media = rfidDescription(body)
            case 0x43:
                media += " · type \(body.first ?? 0)"
            case 0x4F:
                media += " · area \(body.map { String(format: "%02X", $0) }.joined())"
            default:
                break
            }
        }
    }

    private func rfidDescription(_ data: [UInt8]) -> String {
        guard data.count > 9 else { return "No readable label RFID (\(data.map { String(format: "%02X", $0) }.joined()))" }
        let uuid = data.prefix(8).map { String(format: "%02X", $0) }.joined()
        let barcodeLength = Int(data[8])
        guard data.count > 9 + barcodeLength else { return "Label RFID \(uuid)" }
        let barcode = String(decoding: data[9..<(9 + barcodeLength)], as: UTF8.self)
        return "Label RFID \(uuid) · barcode \(barcode)"
    }

    private func writeNext(to characteristic: CBCharacteristic) {
        guard !queue.isEmpty else {
            if endingPrint {
                endingPrint = false
                status = "Printing…"
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    guard let self, let characteristic = self.characteristic else { return }
                    self.queue = [self.frame(0xF3, [0x01])]
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

    private func frame(_ command: UInt8, _ body: [UInt8]) -> Data {
        let checksum = body.reduce(command ^ UInt8(body.count)) { $0 ^ $1 }
        return Data([0x55, 0x55, command, UInt8(body.count)] + body + [checksum, 0xAA, 0xAA])
    }

    private func uint16(_ value: Int) -> [UInt8] {
        [UInt8(value >> 8), UInt8(value & 0xff)]
    }

    private func rasterRows(text: String, width: Int, fontName: String, fontSize: CGFloat) -> [[UInt8]] {
        let font = fontName == "System" ? NSFont.systemFont(ofSize: fontSize) : NSFont(name: fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        let lines = max(1, text.split(separator: "\n", omittingEmptySubsequences: false).count)
        let size = NSSize(width: width, height: max(80, 20 + Int(ceil(fontSize * 1.5)) * lines))
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        (text as NSString).draw(
            in: NSRect(x: 12, y: 12, width: size.width - 24, height: size.height - 24),
            withAttributes: [.font: font, .foregroundColor: NSColor.black]
        )
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return [] }
        return (0..<Int(size.height)).map { y in
            stride(from: 0, to: width, by: 8).map { x in
                (0..<8).reduce(0) { byte, bit in
                    let pixel = bitmap.colorAt(x: x + bit, y: y) ?? .white
                    return byte | (pixel.brightnessComponent < 0.5 ? 1 << (7 - bit) : 0)
                }
            }
        }
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
            Button("Print label") { bluetooth.print(text, fontName: fontName, fontSize: fontSize) }
                .disabled(bluetooth.connectedPrinter == nil || text.isEmpty)
        }
        .padding()
        .frame(minWidth: 440, minHeight: 430)
    }
}
