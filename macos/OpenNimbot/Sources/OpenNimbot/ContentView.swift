import SwiftUI

struct ContentView: View {
    @StateObject private var bluetooth = BluetoothManager()
    @State private var text = "你好，NIMBOT"
    @State private var fontName = "System"
    @State private var fontSize = 24.0
    private let fontNames = ["System", "Hiragino Sans GB", "Songti SC", "Menlo"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("OpenNimbot").font(.largeTitle)
            Text(bluetooth.status).foregroundStyle(.secondary)
            HStack {
                Button("Scan", action: bluetooth.scan)
                Button("Read label media", action: bluetooth.readMedia)
                    .disabled(bluetooth.connectedPrinter == nil)
                if let printer = bluetooth.connectedPrinter {
                    Text("Connected: \(printer.name)")
                }
            }
            Text(bluetooth.media).font(.caption).textSelection(.enabled)
            List(bluetooth.printers) { printer in
                HStack {
                    Text(printer.name)
                    Spacer()
                    Button("Connect") { bluetooth.connect(printer) }
                }
            }
            .frame(height: 160)
            TextEditor(text: $text).font(.system(size: 20)).frame(height: 100)
            HStack {
                Picker("Font", selection: $fontName) {
                    ForEach(fontNames, id: \.self) { Text($0) }
                }
                .pickerStyle(.menu)
                Stepper("Size: \(Int(fontSize))", value: $fontSize, in: 10...48, step: 1)
            }
            GroupBox("Print preview") {
                Image(nsImage: NimbotProtocol.preview(text: text, fontName: fontName, fontSize: fontSize))
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 320)
                    .padding(8)
            }
            Button("Print label") { bluetooth.print(text, fontName: fontName, fontSize: fontSize) }
                .disabled(bluetooth.connectedPrinter == nil || text.isEmpty)
        }
        .padding()
        .frame(minWidth: 440, minHeight: 620)
    }
}
