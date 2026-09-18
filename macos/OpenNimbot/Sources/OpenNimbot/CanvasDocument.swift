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
    var zIndex = 0
}

final class CanvasDocument: ObservableObject {
    @Published var layers: [CanvasLayer]
    @Published var selectedID: UUID?

    init(text: String) {
        layers = [CanvasLayer(content: .text(text), frame: CGRect(x: 12, y: 40, width: 200, height: 35))]
    }

    var selected: CanvasLayer? { layers.first { $0.id == selectedID } }

    func update(_ id: UUID, _ change: (inout CanvasLayer) -> Void) {
        guard let index = layers.firstIndex(where: { $0.id == id }) else { return }
        change(&layers[index])
    }

    func addText() {
        let layer = CanvasLayer(content: .text("Text"), frame: CGRect(x: 24, y: 24, width: 100, height: 32), zIndex: layers.count)
        layers.append(layer)
        selectedID = layer.id
    }

    func addImage(_ image: NSImage) {
        let layer = CanvasLayer(content: .image(image), frame: CGRect(x: 24, y: 24, width: 80, height: 60), zIndex: layers.count)
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
            CanvasLayer(content: $0.content, frame: $0.frame, font: $0.font, bold: $0.bold, italic: $0.italic, zIndex: $0.zIndex)
        }
        selectedID = nil
    }

    func deleteSelected() {
        guard let selectedID else { return }
        layers.removeAll { $0.id == selectedID }
        self.selectedID = nil
    }

    func moveSelected(toFront: Bool) {
        guard let selectedID, let index = layers.firstIndex(where: { $0.id == selectedID }) else { return }
        layers[index].zIndex = toFront ? (layers.map(\.zIndex).max() ?? 0) + 1 : (layers.map(\.zIndex).min() ?? 0) - 1
    }
}
