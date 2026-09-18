import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var bluetooth = BluetoothManager()
    @State private var topDocument = NSAttributedString(string: "你好，NIMBOT", attributes: [.font: NSFont.systemFont(ofSize: 24)])
    @State private var bottomDocument = NSAttributedString(string: "第二张标签", attributes: [.font: NSFont.systemFont(ofSize: 24)])
    @State private var selectedLabel = 0
    @State private var showingImagePicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("OpenNimbot").font(.title2.weight(.semibold))
                Spacer()
                printerMenu
            }
            Text(bluetooth.status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Picker("Label", selection: $selectedLabel) {
                Text("Top label").tag(0)
                Text("Bottom label").tag(1)
            }
            .pickerStyle(.segmented)
            HStack {
                Button("Font…") { NSFontManager.shared.orderFrontFontPanel(nil) }
                Button("Bold", action: RichTextActions.shared.toggleBold)
                Button("Insert image…") { showingImagePicker = true }
                Spacer()
                Text(bluetooth.mediaProfile.name).font(.caption).foregroundStyle(.secondary)
            }
            GroupBox("Canvas") {
                RichTextEditor(document: activeDocument).frame(height: 220)
            }
            GroupBox("Print preview — two independent labels") {
                HStack(spacing: 12) {
                    preview("Top", document: topDocument)
                    preview("Bottom", document: bottomDocument)
                }
                .padding(6)
            }
            Button("Print 2 labels") { bluetooth.print([topDocument, bottomDocument]) }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(bluetooth.connectedPrinter == nil || topDocument.length == 0 || bottomDocument.length == 0)
        }
        .padding()
        .frame(minWidth: 620, minHeight: 650)
        .fileImporter(isPresented: $showingImagePicker, allowedContentTypes: [.image]) { result in
            guard case let .success(url) = result else { return }
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let image = NSImage(contentsOf: url) else { return }
            RichTextActions.shared.insert(image)
        }
    }

    private var activeDocument: Binding<NSAttributedString> {
        Binding(
            get: { selectedLabel == 0 ? topDocument : bottomDocument },
            set: { if selectedLabel == 0 { topDocument = $0 } else { bottomDocument = $0 } }
        )
    }

    private func preview(_ title: String, document: NSAttributedString) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.weight(.medium))
            Image(nsImage: NimbotProtocol.preview(document: document, media: bluetooth.mediaProfile))
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .frame(width: 260)
        }
    }

    private var printerMenu: some View {
        Menu {
            Button("Scan printers", action: bluetooth.scan)
            if !bluetooth.printers.isEmpty {
                Divider()
                ForEach(bluetooth.printers) { printer in
                    Button(printer.name) { bluetooth.connect(printer) }
                }
            }
            if bluetooth.connectedPrinter != nil {
                Divider()
                Button("Refresh label media", action: bluetooth.readMedia)
            }
        } label: {
            Label(bluetooth.connectedPrinter?.name ?? "Select printer", systemImage: "printer")
        }
    }
}
