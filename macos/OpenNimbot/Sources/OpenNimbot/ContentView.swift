import SwiftUI

struct ContentView: View {
    @StateObject private var bluetooth = BluetoothManager()
    @State private var topText = "你好，NIMBOT"
    @State private var bottomText = "第二张标签"
    @State private var fontName = "System"
    @State private var fontSize = 24.0
    private let fontNames = ["System", "Hiragino Sans GB", "Songti SC", "Menlo"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("OpenNimbot").font(.title2.weight(.semibold))
                Spacer()
                printerMenu
            }
            Text(bluetooth.status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            HStack(spacing: 12) {
                labelEditor("Top label", text: $topText)
                labelEditor("Bottom label", text: $bottomText)
            }
            HStack {
                Picker("Font", selection: $fontName) {
                    ForEach(fontNames, id: \.self) { Text($0) }
                }
                .pickerStyle(.menu)
                Stepper("Size: \(Int(fontSize))", value: $fontSize, in: 10...48, step: 1)
                Spacer()
                Text(bluetooth.mediaProfile.name).font(.caption).foregroundStyle(.secondary)
            }
            GroupBox("Preview — two independent labels") {
                VStack(spacing: 12) {
                    preview("Top", text: topText)
                    preview("Bottom", text: bottomText)
                }
                .padding(6)
            }
            Button("Print 2 labels") {
                bluetooth.print([topText, bottomText], fontName: fontName, fontSize: fontSize)
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(bluetooth.connectedPrinter == nil || topText.isEmpty || bottomText.isEmpty)
        }
        .padding()
        .frame(minWidth: 600, minHeight: 650)
    }

    private func labelEditor(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.medium))
            TextEditor(text: text).font(.system(size: 16)).frame(height: 70)
        }
    }

    private func preview(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.weight(.medium))
            Image(nsImage: NimbotProtocol.preview(text: text, fontName: fontName, fontSize: fontSize, media: bluetooth.mediaProfile))
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .frame(width: 320)
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
