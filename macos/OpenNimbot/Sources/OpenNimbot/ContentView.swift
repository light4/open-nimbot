import SwiftUI

struct ContentView: View {
    @StateObject private var bluetooth = BluetoothManager()
    @State private var text = "你好，NIMBOT"
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
            TextEditor(text: $text).font(.system(size: 20)).frame(height: 90)
            HStack {
                Picker("Font", selection: $fontName) {
                    ForEach(fontNames, id: \.self) { Text($0) }
                }
                .pickerStyle(.menu)
                Stepper("Size: \(Int(fontSize))", value: $fontSize, in: 10...48, step: 1)
                Spacer()
                Text(bluetooth.mediaProfile.name).font(.caption).foregroundStyle(.secondary)
            }
            GroupBox("Preview — one label") {
                Image(nsImage: NimbotProtocol.preview(text: text, fontName: fontName, fontSize: fontSize, media: bluetooth.mediaProfile))
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 320)
                    .padding(6)
            }
            Button("Print label") { bluetooth.print(text, fontName: fontName, fontSize: fontSize) }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(bluetooth.connectedPrinter == nil || text.isEmpty)
        }
        .padding()
        .frame(minWidth: 440, minHeight: 440)
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
