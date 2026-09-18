import AppKit
import SwiftUI

struct CanvasEditor: View {
    @ObservedObject var document: CanvasDocument
    let size: CGSize
    @Binding var drawing: Bool
    @State private var stroke: [CGPoint] = []

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / size.width, proxy.size.height / size.height)
            ZStack(alignment: .topLeading) {
                Color.white
                ForEach(document.layers.sorted { $0.zIndex < $1.zIndex }) { layer in
                    if case let .path(points) = layer.content {
                        path(points, scale: scale)
                            .stroke(document.selectedID == layer.id ? .blue : .black, lineWidth: 2)
                            .contentShape(Rectangle())
                            .onTapGesture { document.selectedID = layer.id }
                    } else {
                        CanvasLayerView(layer: layer, document: document, scale: scale)
                    }
                }
                if stroke.count > 1 {
                    path(stroke, scale: scale).stroke(.black, lineWidth: 2)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                guard drawing else { return }
                stroke.append(CGPoint(x: value.location.x / scale, y: value.location.y / scale))
            }.onEnded { _ in
                guard drawing else { return }
                document.addPath(stroke)
                stroke = []
            })
        }
        .aspectRatio(size.width / size.height, contentMode: .fit)
        .border(.secondary)
    }

    private func path(_ points: [CGPoint], scale: CGFloat) -> Path {
        Path { result in
            guard let first = points.first else { return }
            result.move(to: CGPoint(x: first.x * scale, y: first.y * scale))
            for point in points.dropFirst() { result.addLine(to: CGPoint(x: point.x * scale, y: point.y * scale)) }
        }
    }
}

private struct CanvasLayerView: View {
    let layer: CanvasLayer
    @ObservedObject var document: CanvasDocument
    let scale: CGFloat
    @State private var dragOrigin: CGPoint?
    @State private var resizeFrame: CGRect?

    var body: some View {
        content
            .frame(width: max(1, layer.frame.width * scale), height: max(1, layer.frame.height * scale), alignment: .topLeading)
            .position(x: layer.frame.midX * scale, y: layer.frame.midY * scale)
            .overlay { if document.selectedID == layer.id { Rectangle().stroke(.blue, lineWidth: 1) } }
            .contentShape(Rectangle())
            .onTapGesture { document.selectedID = layer.id }
            .gesture(DragGesture().onChanged { value in
                if dragOrigin == nil { dragOrigin = layer.frame.origin }
                document.update(layer.id) { $0.frame.origin = CGPoint(x: dragOrigin!.x + value.translation.width / scale, y: dragOrigin!.y + value.translation.height / scale) }
            }.onEnded { _ in dragOrigin = nil })
            .simultaneousGesture(MagnificationGesture().onChanged { value in
                if resizeFrame == nil { resizeFrame = layer.frame }
                document.update(layer.id) { $0.frame.size = CGSize(width: max(12, resizeFrame!.width * value), height: max(12, resizeFrame!.height * value)) }
            }.onEnded { _ in resizeFrame = nil })
    }

    @ViewBuilder private var content: some View {
        switch layer.content {
        case let .text(text): Text(text).font(Font(layer.font)).fontWeight(layer.bold ? .bold : .regular)
        case let .image(image): Image(nsImage: image).resizable().scaledToFit()
        case .path: EmptyView()
        }
    }
}
