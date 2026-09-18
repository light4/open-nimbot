import XCTest
@testable import OpenNimbot

final class OpenNimbotTests: XCTestCase {
    func testPacketChecksum() {
        XCTAssertEqual(NimbotProtocol.frame(0x5A, [0x01]), Data([0x55, 0x55, 0x5A, 0x01, 0x01, 0x5A, 0xAA, 0xAA]))
    }

    func testMultilineTextHasTwoLineSelectionFrame() {
        let singleLine = CanvasDocument(text: "A")
        let twoLines = CanvasDocument(text: "A\nB")
        XCTAssertGreaterThan(twoLines.layers[0].frame.height, singleLine.layers[0].frame.height)
    }

    func testTwoLabelsAreOnePrintPage() {
        let media = LabelMedia(barcode: "test", width: 240, height: 120, name: "test")
        let frames = NimbotProtocol.printFrames(canvases: [CanvasDocument(text: "Top"), CanvasDocument(text: "Bottom")], media: media)
        XCTAssertEqual(frames.filter { $0[2] == 0x01 }.count, 1)
        XCTAssertEqual(frames.filter { $0[2] == 0x03 }.count, 1)
        XCTAssertEqual(frames.filter { $0[2] == 0xE3 }.count, 1)
    }

    func testTextSelectionFrameFitsContent() {
        let document = CanvasDocument(text: "A")
        XCTAssertLessThan(document.layers[0].frame.width, 216)
        XCTAssertGreaterThan(document.layers[0].frame.height, 0)
    }
}
