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
    @State private var dragOffset = CGSize.zero
    @State private var resizeOffset = CGSize.zero

    var body: some View {
        content
            .frame(
                width: max(12, layer.frame.width * scale + resizeOffset.width),
                height: max(12, layer.frame.height * scale + resizeOffset.height),
                alignment: .topLeading
            )
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
                    .onChanged { dragOffset = $0.translation }
                    .onEnded { value in
                        document.update(layer.id) {
                            $0.frame.origin.x += value.translation.width / scale
                            $0.frame.origin.y += value.translation.height / scale
                        }
                        dragOffset = .zero
                    }
            )
            .position(
                x: layer.frame.midX * scale + dragOffset.width + resizeOffset.width / 2,
                y: layer.frame.midY * scale + dragOffset.height + resizeOffset.height / 2
            )
    }

    private var resizeGesture: some Gesture {
        DragGesture().onChanged { value in
            resizeOffset = value.translation
        }.onEnded { value in
            document.update(layer.id) {
                $0.frame.size = CGSize(
                    width: max(12, $0.frame.width + value.translation.width / scale),
                    height: max(12, $0.frame.height + value.translation.height / scale)
                )
            }
            resizeOffset = .zero
        }
    }

    private var textAlignment: Alignment {
        switch layer.alignment {
        case .left, .natural, .justified: .leading
        case .right: .trailing
        default: .center
        }
    }

    @ViewBuilder private var content: some View {
        switch layer.content {
        case let .text(text): Text(text).font(Font(layer.font)).fontWeight(layer.bold ? .bold : .regular).italic(layer.italic).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: textAlignment)
        case let .image(image): Image(nsImage: image).resizable().scaledToFit()
        case .path: EmptyView()
        }
    }
}
