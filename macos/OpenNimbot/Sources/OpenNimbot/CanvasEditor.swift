import AppKit
import SwiftUI

struct CanvasEditor: View {
    @ObservedObject var document: CanvasDocument
    let size: CGSize
    @Binding var drawing: Bool
    let onActivate: () -> Void
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
            .simultaneousGesture(TapGesture().onEnded(onActivate))
            .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { value in
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
    @GestureState private var dragTranslation = CGSize.zero
    @State private var resizeFrame: CGRect?
    @State private var resizeFont: NSFont?

    var body: some View {
        content
            .frame(width: max(1, layer.frame.width * scale), height: max(1, layer.frame.height * scale), alignment: .topLeading)
            .overlay {
                if document.selectedID == layer.id {
                    Rectangle().inset(by: -3).stroke(.blue, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    Circle()
                        .fill(.blue)
                        .frame(width: 10, height: 10)
                        .offset(x: 5, y: 5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .highPriorityGesture(resizeGesture)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { document.selectedID = layer.id }
            .gesture(
                DragGesture()
                    .updating($dragTranslation) { value, state, _ in state = value.translation }
                    .onEnded { value in
                        document.update(layer.id) {
                            $0.frame.origin.x += value.translation.width / scale
                            $0.frame.origin.y += value.translation.height / scale
                        }
                    }
            )
            .position(
                x: layer.frame.midX * scale + dragTranslation.width,
                y: layer.frame.midY * scale + dragTranslation.height
            )
    }

    private var resizeGesture: some Gesture {
        DragGesture().onChanged { value in
            if case .text = layer.content {
                if resizeFont == nil || resizeFrame == nil { resizeFont = layer.font; resizeFrame = layer.frame }
                let factor = max(0.25, (resizeFrame!.width + value.translation.width / scale) / resizeFrame!.width)
                document.update(layer.id) { $0.font = NSFontManager.shared.convert(resizeFont!, toSize: max(8, resizeFont!.pointSize * factor)) }
                document.fitText(layer.id)
            } else {
                if resizeFrame == nil { resizeFrame = layer.frame }
                document.update(layer.id) { $0.frame.size = CGSize(width: max(12, resizeFrame!.width + value.translation.width / scale), height: max(12, resizeFrame!.height + value.translation.height / scale)) }
            }
        }.onEnded { _ in resizeFrame = nil; resizeFont = nil }
    }

    @ViewBuilder private var content: some View {
        switch layer.content {
        case let .text(text): Text(text).font(Font(layer.font)).fontWeight(layer.bold ? .bold : .regular).italic(layer.italic)
        case let .image(image): Image(nsImage: image).resizable().scaledToFit()
        case .path: EmptyView()
        }
    }
}
