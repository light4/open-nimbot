import AppKit
import SwiftUI

struct CanvasEditor: View {
  @ObservedObject var document: CanvasDocument
  let size: CGSize
  @Binding var drawing: Bool
  let onActivate: () -> Void
  @FocusState private var focused: Bool
  @State private var stroke: [CGPoint] = []

  var body: some View {
    GeometryReader { proxy in
      let scale = min(proxy.size.width / size.width, proxy.size.height / size.height)
      ZStack(alignment: .topLeading) {
        Color.white
        ForEach(document.layers.sorted { $0.zIndex < $1.zIndex }) { layer in
          if case .path(let points) = layer.content {
            path(points, scale: scale)
              .stroke(document.selectedID == layer.id ? .blue : .black, lineWidth: 2)
              .contentShape(Rectangle())
              .onTapGesture {
                onActivate()
                focused = true
                document.selectedID = layer.id
              }
          } else {
            CanvasLayerView(
              layer: layer, document: document, scale: scale,
              onActivate: {
                onActivate()
                focused = true
              })
          }
        }
        if stroke.count > 1 {
          path(stroke, scale: scale).stroke(.black, lineWidth: 2)
        }
      }
      .contentShape(Rectangle())
      .focusable()
      .focused($focused)
      .onMoveCommand { direction in
        switch direction {
        case .up: document.nudgeSelected(x: 0, y: -1)
        case .down: document.nudgeSelected(x: 0, y: 1)
        case .left: document.nudgeSelected(x: -1, y: 0)
        case .right: document.nudgeSelected(x: 1, y: 0)
        @unknown default: break
        }
      }
      .gesture(drawing ? drawingGesture(scale: scale) : nil)
      .transaction { $0.animation = nil }
    }
    .aspectRatio(size.width / size.height, contentMode: .fit)
    .border(.secondary)
  }

  private func drawingGesture(scale: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { stroke.append(CGPoint(x: $0.location.x / scale, y: $0.location.y / scale)) }
      .onEnded { _ in
        document.addPath(stroke)
        stroke = []
      }
  }

  private func path(_ points: [CGPoint], scale: CGFloat) -> Path {
    Path { result in
      guard let first = points.first else { return }
      result.move(to: CGPoint(x: first.x * scale, y: first.y * scale))
      for point in points.dropFirst() {
        result.addLine(to: CGPoint(x: point.x * scale, y: point.y * scale))
      }
    }
  }
}

private struct CanvasLayerView: View {
  let layer: CanvasLayer
  @ObservedObject var document: CanvasDocument
  let scale: CGFloat
  let onActivate: () -> Void
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
        }
      }
      .overlay(alignment: .bottomTrailing) {
        if document.selectedID == layer.id {
          Circle()
            .fill(.blue)
            .frame(width: 14, height: 14)
            .contentShape(Circle())
            .highPriorityGesture(resizeGesture)
        }
      }
      .contentShape(Rectangle())
      .onTapGesture {
        onActivate()
        document.selectedID = layer.id
      }
      .gesture(
        DragGesture()
          .onChanged { dragOffset = $0.translation }
          .onEnded { value in
            document.move(
              layer.id,
              by: CGSize(
                width: value.translation.width / scale,
                height: value.translation.height / scale
              )
            )
            dragOffset = .zero
          }
      )
      .offset(
        x: layer.frame.minX * scale + dragOffset.width,
        y: layer.frame.minY * scale + dragOffset.height
      )
      .transaction { $0.animation = nil }
  }

  private var resizeGesture: some Gesture {
    DragGesture().onChanged { value in
      resizeOffset = value.translation
    }.onEnded { value in
      document.resize(
        layer.id,
        by: CGSize(
          width: value.translation.width / scale,
          height: value.translation.height / scale
        )
      )
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
    case .text(let text):
      Text(text)
        .font(Font(layer.font))
        .fontWeight(layer.bold ? .bold : .regular)
        .transformEffect(
          layer.italic ? CGAffineTransform(a: 1, b: 0, c: 0.2, d: 1, tx: 0, ty: 0) : .identity
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: textAlignment)
    case .image(let image): Image(nsImage: image).resizable().scaledToFit()
    case .path: EmptyView()
    }
  }
}
