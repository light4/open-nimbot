import AppKit
import SwiftUI

final class RichTextActions {
    static let shared = RichTextActions()
    weak var textView: NSTextView?

    func toggleBold() {
        guard let textView, textView.selectedRange().length > 0 else { return }
        textView.textStorage?.enumerateAttribute(.font, in: textView.selectedRange()) { value, range, _ in
            let font = value as? NSFont ?? NSFont.systemFont(ofSize: 14)
            let traits = NSFontManager.shared.traits(of: font)
            let converted = traits.contains(.boldFontMask)
                ? NSFontManager.shared.convert(font, toNotHaveTrait: .boldFontMask)
                : NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
            textView.textStorage?.addAttribute(.font, value: converted, range: range)
        }
        textView.didChangeText()
    }

    func insert(_ image: NSImage) {
        guard let textView else { return }
        let attachment = NSTextAttachment()
        attachment.attachmentCell = NSTextAttachmentCell(imageCell: image)
        textView.textStorage?.replaceCharacters(in: textView.selectedRange(), with: NSAttributedString(attachment: attachment))
        textView.didChangeText()
    }
}

struct RichTextEditor: NSViewRepresentable {
    @Binding var document: NSAttributedString

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isRichText = true
        textView.importsGraphics = true
        textView.allowsImageEditing = true
        textView.usesFontPanel = true
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        textView.textStorage?.setAttributedString(document)
        textView.delegate = context.coordinator
        context.coordinator.textView = textView
        RichTextActions.shared.textView = textView

        let scrollView = NSScrollView()
        scrollView.borderType = .bezelBorder
        scrollView.hasVerticalScroller = true
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView, textView.attributedString() != document else { return }
        RichTextActions.shared.textView = textView
        textView.textStorage?.setAttributedString(document)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditor
        weak var textView: NSTextView?

        init(_ parent: RichTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.document = textView.attributedString()
        }
    }
}
