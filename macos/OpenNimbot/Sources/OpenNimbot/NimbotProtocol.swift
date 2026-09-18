import AppKit
import CoreBluetooth

enum NimbotProtocol {
    static let service = CBUUID(string: "E7810A71-73AE-499D-8C15-FAA9AEF0C3F2")
    static let characteristic = CBUUID(string: "BEF8D6C9-9C21-4C9E-B632-BD58C1009F9F")

    static func mediaQueries() -> [Data] {
        [frame(0x1A, [0x01])]
    }

    static func printFrames(labels: [NSAttributedString], media: LabelMedia) -> [Data] {
        var frames = [
            frame(0x21, [0x03]), frame(0x23, [0x01]),
            frame(0x01, uint16(labels.count) + [0, 0, 0, 0, 0]),
        ]
        for text in labels {
            let rows = rasterRows(document: text, width: media.width, height: media.height)
            frames += [frame(0x03, [0x01]), frame(0x13, uint16(rows.count) + uint16(media.width) + [0, 1])]
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
            frames.append(frame(0xE3, [0x01]))
        }
        return frames
    }

    static func finishPrintFrame() -> Data { frame(0xF3, [0x01]) }

    static func printFrames(canvases: [CanvasDocument], media: LabelMedia) -> [Data] {
        var frames = [frame(0x21, [0x03]), frame(0x23, [0x01]), frame(0x01, uint16(canvases.count) + [0, 0, 0, 0, 0])]
        for canvas in canvases {
            frames += [frame(0x03, [0x01]), frame(0x13, uint16(media.height) + uint16(media.width) + [0, 1])]
            for (y, row) in rasterRows(canvas: canvas, media: media).enumerated() {
                if row.allSatisfy({ $0 == 0 }) { frames.append(frame(0x84, uint16(y) + [1])) }
                else {
                    let counts = [UInt8(row.prefix(16).reduce(0) { $0 + $1.nonzeroBitCount }), UInt8(row.dropFirst(16).reduce(0) { $0 + $1.nonzeroBitCount }), 0]
                    frames.append(frame(0x85, uint16(y) + counts + [1] + row))
                }
            }
            frames.append(frame(0xE3, [1]))
        }
        return frames
    }

    static func preview(canvas: CanvasDocument, media: LabelMedia) -> NSImage {
        let bitmap = renderBitmap(canvas: canvas, media: media)
        let image = NSImage(size: bitmap.size)
        image.addRepresentation(bitmap)
        return image
    }

    static func preview(document: NSAttributedString, media: LabelMedia) -> NSImage {
        let bitmap = renderBitmap(document: document, width: media.width, height: media.height)
        let image = NSImage(size: bitmap.size)
        image.addRepresentation(bitmap)
        return image
    }

    static func mediaProfile(_ data: [UInt8]) -> LabelMedia? {
        guard data.count > 9 else { return nil }
        let barcodeLength = Int(data[8])
        guard data.count >= 9 + barcodeLength else { return nil }
        let barcode = String(decoding: data[9..<(9 + barcodeLength)], as: UTF8.self)
        // 6971501227682: NIIMBOT 30 × 15 mm / 2R white gap labels (203 dpi).
        if barcode == "6971501227682" {
            return LabelMedia(barcode: barcode, width: 240, height: 120, name: "30 × 15 mm gap label (2R; one label)")
        }
        return nil
    }

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

    private static func rasterRows(canvas: CanvasDocument, media: LabelMedia) -> [[UInt8]] {
        let bitmap = renderBitmap(canvas: canvas, media: media)
        return (0..<media.height).map { y in
            stride(from: 0, to: media.width, by: 8).map { x in
                (0..<8).reduce(0) { byte, bit in
                    let pixel = bitmap.colorAt(x: x + bit, y: y) ?? .white
                    return byte | (pixel.brightnessComponent < 0.5 ? 1 << (7 - bit) : 0)
                }
            }
        }
    }

    private static func renderBitmap(canvas: CanvasDocument, media: LabelMedia) -> NSBitmapImageRep {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: media.width, pixelsHigh: media.height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: media.width, height: media.height)).fill()
        for layer in canvas.layers.sorted(by: { $0.zIndex < $1.zIndex }) {
            switch layer.content {
            case let .text(text):
                let font = layer.bold ? NSFontManager.shared.convert(layer.font, toHaveTrait: .boldFontMask) : layer.font
                (text as NSString).draw(in: layer.frame, withAttributes: [.font: font, .foregroundColor: NSColor.black])
            case let .image(image):
                image.draw(in: layer.frame)
            case let .path(points):
                guard let first = points.first else { continue }
                let path = NSBezierPath()
                path.move(to: first)
                for point in points.dropFirst() { path.line(to: point) }
                path.lineWidth = 2
                NSColor.black.setStroke()
                path.stroke()
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }

    private static func uint16(_ value: Int) -> [UInt8] {
        [UInt8(value >> 8), UInt8(value & 0xff)]
    }

    private static func rasterRows(document: NSAttributedString, width: Int, height: Int) -> [[UInt8]] {
        let bitmap = renderBitmap(document: document, width: width, height: height)
        return (0..<bitmap.pixelsHigh).map { y in
            stride(from: 0, to: width, by: 8).map { x in
                (0..<8).reduce(0) { byte, bit in
                    let pixel = bitmap.colorAt(x: x + bit, y: y) ?? .white
                    return byte | (pixel.brightnessComponent < 0.5 ? 1 << (7 - bit) : 0)
                }
            }
        }
    }

    private static func renderBitmap(document: NSAttributedString, width: Int, height: Int) -> NSBitmapImageRep {
        let size = NSSize(width: width, height: height)
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        document.draw(in: NSRect(x: 12, y: 12, width: size.width - 24, height: size.height - 24))
        NSGraphicsContext.restoreGraphicsState()
        return bitmap
    }
}
