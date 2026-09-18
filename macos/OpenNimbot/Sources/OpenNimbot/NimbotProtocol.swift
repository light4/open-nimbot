import AppKit
import CoreBluetooth

enum NimbotProtocol {
    static let service = CBUUID(string: "E7810A71-73AE-499D-8C15-FAA9AEF0C3F2")
    static let characteristic = CBUUID(string: "BEF8D6C9-9C21-4C9E-B632-BD58C1009F9F")

    static func mediaQueries() -> [Data] {
        [frame(0x1A, [0x01])]
    }

    static func printFrames(text: String, fontName: String, fontSize: CGFloat) -> [Data] {
        let rows = rasterRows(text: text, width: 160, fontName: fontName, fontSize: fontSize)
        var frames = [
            frame(0x21, [0x03]), frame(0x23, [0x01]),
            frame(0x01, [0, 1, 0, 0, 0, 0, 0]), frame(0x03, [0x01]),
            frame(0x13, uint16(rows.count) + uint16(160) + [0, 1]),
        ]
        for (y, row) in rows.enumerated() {
            if row.allSatisfy({ $0 == 0 }) {
                frames.append(frame(0x84, uint16(y) + [0x01]))
            } else {
                let counts = [
                    UInt8(row.prefix(16).reduce(0) { $0 + $1.nonzeroBitCount }),
                    UInt8(row.dropFirst(16).reduce(0) { $0 + $1.nonzeroBitCount }),
                    0,
                ]
                frames.append(frame(0x85, uint16(y) + counts + [0x01] + row))
            }
        }
        return frames + [frame(0xE3, [0x01])]
    }

    static func finishPrintFrame() -> Data { frame(0xF3, [0x01]) }

    static func mediaDescription(_ data: [UInt8]) -> String {
        guard data.count > 9 else { return "No readable label RFID" }
        let uuid = data.prefix(8).map { String(format: "%02X", $0) }.joined()
        let barcodeLength = Int(data[8])
        guard data.count > 9 + barcodeLength else { return "Label RFID \(uuid)" }
        let barcode = String(decoding: data[9..<(9 + barcodeLength)], as: UTF8.self)
        var index = 9 + barcodeLength
        guard data.count > index else { return "Label RFID \(uuid) · barcode \(barcode)" }
        let serialLength = Int(data[index])
        index += 1
        guard data.count >= index + serialLength + 5 else { return "Label RFID \(uuid) · barcode \(barcode)" }
        let serial = String(decoding: data[index..<(index + serialLength)], as: UTF8.self)
        index += serialLength
        let total = Int(data[index]) << 8 | Int(data[index + 1])
        let used = Int(data[index + 2]) << 8 | Int(data[index + 3])
        let type = data[index + 4]
        return "RFID barcode \(barcode) · serial \(serial) · gapped type \(type) · used \(used)/\(total)"
    }

    static func frame(_ command: UInt8, _ body: [UInt8]) -> Data {
        let checksum = body.reduce(command ^ UInt8(body.count)) { $0 ^ $1 }
        return Data([0x55, 0x55, command, UInt8(body.count)] + body + [checksum, 0xAA, 0xAA])
    }

    private static func uint16(_ value: Int) -> [UInt8] {
        [UInt8(value >> 8), UInt8(value & 0xff)]
    }

    private static func rasterRows(text: String, width: Int, fontName: String, fontSize: CGFloat) -> [[UInt8]] {
        let font = fontName == "System" ? NSFont.systemFont(ofSize: fontSize) : NSFont(name: fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let textHeight = (text as NSString).boundingRect(
            with: NSSize(width: CGFloat(width - 24), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        ).height
        let size = NSSize(width: width, height: max(80, Int(ceil(textHeight)) + 24))
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        (text as NSString).draw(
            in: NSRect(x: 12, y: 12, width: size.width - 24, height: size.height - 24),
            withAttributes: attributes
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
