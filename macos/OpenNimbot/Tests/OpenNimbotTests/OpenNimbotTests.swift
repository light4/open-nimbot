import XCTest
@testable import OpenNimbot

final class OpenNimbotIntegrationTests: XCTestCase {
    func testDetected2RMediaRendersAndPrintsAsOnePhysicalPage() {
        let barcode = Array("6971501227682".utf8)
        let media = NimbotProtocol.mediaProfile(Array(repeating: 0, count: 8) + [UInt8(barcode.count)] + barcode)
        XCTAssertEqual(media?.width, 240)
        XCTAssertEqual(media?.height, 120)

        let top = CanvasDocument(text: "Top\nlabel")
        let bottom = CanvasDocument(text: "Bottom")
        let preview = NimbotProtocol.preview(canvas: top, media: media!)
        let frames = NimbotProtocol.printFrames(canvases: [top, bottom], media: media!)

        XCTAssertEqual(preview.size, CGSize(width: 240, height: 120))
        XCTAssertEqual(frames.filter { $0[2] == 0x01 }.count, 1)
        XCTAssertEqual(frames.filter { $0[2] == 0x03 }.count, 1)
        XCTAssertEqual(frames.filter { $0[2] == 0x13 }.count, 1)
        XCTAssertEqual(frames.filter { $0[2] == 0xE3 }.count, 1)
    }

    func testCanvasEditCopyPreviewAndPrintPipeline() {
        let media = LabelMedia(barcode: "test", width: 240, height: 120, name: "test")
        let top = CanvasDocument(text: "A")
        top.addText()
        let layer = top.layers[1]
        top.update(layer.id) {
            $0.content = .text("Copied\ntext")
            $0.font = .systemFont(ofSize: 22)
            $0.bold = true
            $0.italic = true
            $0.alignment = .right
            $0.frame.origin = CGPoint(x: 30, y: 40)
        }
        top.fitText(layer.id)
        top.selectedID = layer.id
        top.nudgeSelected(x: 2, y: -3)

        let bottom = CanvasDocument(text: "placeholder")
        bottom.replaceLayers(with: top)
        let frames = NimbotProtocol.printFrames(canvases: [top, bottom], media: media)

        XCTAssertEqual(bottom.layers.count, top.layers.count)
        XCTAssertEqual(bottom.layers[1].frame.origin, CGPoint(x: 32, y: 37))
        XCTAssertEqual(frames.filter { $0[2] == 0x85 || $0[2] == 0x84 }.count, 240)
    }
}
