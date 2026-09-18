import AppKit
import SwiftUI

enum CanvasContent {
  case text(String)
  case image(NSImage)
  case path([CGPoint])
}

struct CanvasLayer: Identifiable {
  let id = UUID()
  var content: CanvasContent
  var frame: CGRect
  var font: NSFont = .systemFont(ofSize: 18)
  var bold = false
  var italic = false
  var alignment: NSTextAlignment = .center
  var zIndex = 0
}

final class CanvasDocument: ObservableObject {
  @Published var layers: [CanvasLayer]
  @Published var selectedID: UUID?

  init(text: String) {
    let layer = CanvasLayer(content: .text(text), frame: CGRect(x: 12, y: 40, width: 1, height: 1))
    layers = [layer]
    fitText(layer.id)
  }

  var selected: CanvasLayer? { layers.first { $0.id == selectedID } }

  func update(_ id: UUID, _ change: (inout CanvasLayer) -> Void) {
    guard let index = layers.firstIndex(where: { $0.id == id }) else { return }
    change(&layers[index])
  }

  func addText() {
    let layer = CanvasLayer(
      content: .text("Text"), frame: CGRect(x: 24, y: 24, width: 1, height: 1), zIndex: layers.count
    )
    layers.append(layer)
    fitText(layer.id)
    selectedID = layer.id
  }

  func fitText(_ id: UUID) {
    guard let index = layers.firstIndex(where: { $0.id == id }),
      case .text(let text) = layers[index].content
    else { return }
    var font = layers[index].font
    if layers[index].bold { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
    if layers[index].italic {
      font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
    }
    let size = (text as NSString).boundingRect(
      with: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin, .usesFontLeading],
      attributes: [.font: font]
    ).integral.size
    layers[index].frame.size = CGSize(
      width: max(1, size.width + 8 + (layers[index].italic ? font.pointSize * 0.2 : 0)),
      height: max(1, size.height + 6))
  }

  func addImage(_ image: NSImage) {
    let layer = CanvasLayer(
      content: .image(image), frame: CGRect(x: 24, y: 24, width: 80, height: 60),
      zIndex: layers.count)
    layers.append(layer)
    selectedID = layer.id
  }

  func addPath(_ points: [CGPoint]) {
    guard points.count > 1 else { return }
    let layer = CanvasLayer(content: .path(points), frame: .zero, zIndex: layers.count)
    layers.append(layer)
    selectedID = layer.id
  }

  func replaceLayers(with source: CanvasDocument) {
    layers = source.layers.map {
      CanvasLayer(
        content: $0.content, frame: $0.frame, font: $0.font, bold: $0.bold, italic: $0.italic,
        alignment: $0.alignment, zIndex: $0.zIndex)
    }
    selectedID = nil
  }

  func move(_ id: UUID, by offset: CGSize) {
    update(id) {
      $0.frame.origin.x += offset.width
      $0.frame.origin.y += offset.height
    }
  }

  func resize(_ id: UUID, by offset: CGSize) {
    update(id) {
      $0.frame.size.width = max(12, $0.frame.width + offset.width)
      $0.frame.size.height = max(12, $0.frame.height + offset.height)
    }
  }

  func nudgeSelected(x: CGFloat, y: CGFloat) {
    guard let selectedID else { return }
    move(selectedID, by: CGSize(width: x, height: y))
  }

  func deleteSelected() {
    guard let selectedID else { return }
    layers.removeAll { $0.id == selectedID }
    self.selectedID = nil
  }

  func moveSelected(toFront: Bool) {
    guard let selectedID, let index = layers.firstIndex(where: { $0.id == selectedID }) else {
      return
    }
    layers[index].zIndex =
      toFront ? (layers.map(\.zIndex).max() ?? 0) + 1 : (layers.map(\.zIndex).min() ?? 0) - 1
  }
}
