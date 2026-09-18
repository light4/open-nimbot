import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var bluetooth = BluetoothManager()
    @StateObject private var top = CanvasDocument(text: "你好，NIMBOT")
    @StateObject private var bottom = CanvasDocument(text: "第二张标签")
    @State private var selectedLabel = 0
    @State private var drawing = false
    @State private var showingImagePicker = false

    private var canvas: CanvasDocument { selectedLabel == 0 ? top : bottom }
    private var activeName: String { selectedLabel == 0 ? "Top" : "Bottom" }
    private var families: [String] { ["System"] + NSFontManager.shared.availableFontFamilies.sorted() }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("OpenNimbot").font(.title2.bold()); Spacer(); printerMenu }
            HStack {
                Button("Text", action: canvas.addText)
                Button("Image…") { showingImagePicker = true }
                Toggle("Draw", isOn: $drawing)
                Button("Delete", action: canvas.deleteSelected).disabled(canvas.selectedID == nil)
                Button("Front") { canvas.moveSelected(toFront: true) }.disabled(canvas.selectedID == nil)
                Button("Back") { canvas.moveSelected(toFront: false) }.disabled(canvas.selectedID == nil)
                Button("Copy Top → Bottom") { bottom.replaceLayers(with: top) }
                Spacer()
                Text("Editing \(activeName) · \(bluetooth.mediaProfile.name)").font(.caption)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    labelCanvas("Top label", document: top, index: 0)
                    Divider()
                    labelCanvas("Bottom label", document: bottom, index: 1)
                    inspector
                    GroupBox("Print preview — physical top / bottom layout") {
                        VStack(spacing: 12) { preview("Top", top); preview("Bottom", bottom) }.padding(4)
                    }
                }
            }
            Button("Print label pair") { bluetooth.print([top, bottom]) }.disabled(bluetooth.connectedPrinter == nil)
        }
        .padding().frame(minWidth: 620, minHeight: 650)
        .fileImporter(isPresented: $showingImagePicker, allowedContentTypes: [.image]) { result in
            guard case let .success(url) = result, url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            if let image = NSImage(contentsOf: url) { canvas.addImage(image) }
        }
    }

    private func labelCanvas(_ title: String, document: CanvasDocument, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            CanvasEditor(document: document, size: CGSize(width: bluetooth.mediaProfile.width, height: bluetooth.mediaProfile.height), drawing: $drawing, onActivate: { selectedLabel = index })
                .frame(height: 210)
        }
    }

    @ViewBuilder private var inspector: some View {
        if let item = canvas.selected, case let .text(value) = item.content {
            HStack {
                Text("\(activeName) text").font(.caption)
                TextField("Text", text: textBinding(item.id, value))
                Picker("Font", selection: fontBinding(item.id, item.font.familyName ?? "System")) { ForEach(families, id: \.self) { Text($0) } }.frame(width: 180)
                Stepper("\(Int(item.font.pointSize)) pt", value: fontSizeBinding(item.id, item.font.pointSize), in: 8...48)
                Toggle("Bold", isOn: boldBinding(item.id, item.bold))
                Toggle("Italic", isOn: italicBinding(item.id, item.italic))
            }
        }
    }

    private func preview(_ name: String, _ canvas: CanvasDocument) -> some View {
        VStack { Text(name).font(.caption); Image(nsImage: NimbotProtocol.preview(canvas: canvas, media: bluetooth.mediaProfile)).resizable().interpolation(.none).scaledToFit().frame(width: 300) }
    }

    private func textBinding(_ id: UUID, _ value: String) -> Binding<String> { Binding(get: { value }, set: { text in canvas.update(id) { $0.content = .text(text) } }) }
    private func fontBinding(_ id: UUID, _ value: String) -> Binding<String> { Binding(get: { value }, set: { family in canvas.update(id) { $0.font = family == "System" ? .systemFont(ofSize: $0.font.pointSize) : NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: $0.font.pointSize) ?? $0.font } }) }
    private func fontSizeBinding(_ id: UUID, _ value: CGFloat) -> Binding<Double> { Binding(get: { Double(value) }, set: { size in canvas.update(id) { $0.font = NSFontManager.shared.convert($0.font, toSize: CGFloat(size)) } }) }
    private func boldBinding(_ id: UUID, _ value: Bool) -> Binding<Bool> { Binding(get: { value }, set: { enabled in canvas.update(id) { $0.bold = enabled } }) }
    private func italicBinding(_ id: UUID, _ value: Bool) -> Binding<Bool> { Binding(get: { value }, set: { enabled in canvas.update(id) { $0.italic = enabled } }) }

    private var printerMenu: some View { Menu { Button("Scan", action: bluetooth.scan); ForEach(bluetooth.printers) { printer in Button(printer.name) { bluetooth.connect(printer) } }; if bluetooth.connectedPrinter != nil { Button("Refresh media", action: bluetooth.readMedia) } } label: { Label(bluetooth.connectedPrinter?.name ?? "Printer", systemImage: "printer") } }
}
