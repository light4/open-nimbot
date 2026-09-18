import XCTest

@testable import OpenNimbot

final class OpenNimbotIntegrationTests: XCTestCase {
  func testDetected2RMediaRendersAndPrintsAsOnePhysicalPage() {
    let barcode = Array("6971501227682".utf8)
    let media = NimbotProtocol.mediaProfile(
      Array(repeating: 0, count: 8) + [UInt8(barcode.count)] + barcode)
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

  func testColorImagesAreConvertedToGrayscale() {
    let image = NSImage(size: NSSize(width: 2, height: 2))
    image.lockFocus()
    NSColor.red.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: 2, height: 2)).fill()
    image.unlockFocus()

    let grayscale = CanvasDocument.grayscale(image)
    let color = NSBitmapImageRep(data: grayscale.tiffRepresentation!)!.colorAt(x: 0, y: 0)!
    XCTAssertEqual(color.redComponent, color.greenComponent, accuracy: 0.01)
    XCTAssertEqual(color.greenComponent, color.blueComponent, accuracy: 0.01)
  }

  func testGrayscaleImagesAreDitheredForPrinting() {
    let media = LabelMedia(barcode: "test", width: 16, height: 16, name: "test")
    let canvas = CanvasDocument(text: "")
    let image = NSImage(size: NSSize(width: 2, height: 2))
    image.lockFocus()
    NSColor(calibratedWhite: 0.5, alpha: 1).setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: 2, height: 2)).fill()
    image.unlockFocus()
    canvas.addImage(image)
    canvas.update(canvas.layers[1].id) {
      $0.frame = CGRect(x: 0, y: 0, width: media.width, height: media.height)
    }

    let rows = NimbotProtocol.printFrames(canvases: [canvas], media: media).filter { $0[2] == 0x85 }
    let blackPixels = rows.flatMap { $0[10..<12] }.reduce(0) { $0 + $1.nonzeroBitCount }
    XCTAssertTrue((96...160).contains(blackPixels))
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
    let previewBeforeMove = NimbotProtocol.preview(canvas: top, media: media).tiffRepresentation
    top.move(layer.id, by: CGSize(width: 2, height: -3))
    top.resize(layer.id, by: CGSize(width: 12, height: 8))
    let previewAfterMove = NimbotProtocol.preview(canvas: top, media: media).tiffRepresentation

    let bottom = CanvasDocument(text: "placeholder")
    bottom.replaceLayers(with: top)
    let frames = NimbotProtocol.printFrames(canvases: [top, bottom], media: media)

    XCTAssertEqual(bottom.layers.count, top.layers.count)
    XCTAssertEqual(bottom.layers[1].frame.origin, CGPoint(x: 32, y: 37))
    XCTAssertEqual(bottom.layers[1].frame.size, top.layers[1].frame.size)
    XCTAssertNotEqual(previewBeforeMove, previewAfterMove)

    let italic = CanvasDocument(text: "Italic")
    let regularPreview = NimbotProtocol.preview(canvas: italic, media: media).tiffRepresentation
    italic.update(italic.layers[0].id) { $0.italic = true }
    italic.fitText(italic.layers[0].id)
    XCTAssertNotEqual(
      regularPreview, NimbotProtocol.preview(canvas: italic, media: media).tiffRepresentation)
    XCTAssertEqual(frames.filter { $0[2] == 0x85 || $0[2] == 0x84 }.count, 240)
  }
}
