/*
 * Notepad für macOS – Dokument (Öffnen, Speichern, Drucken).
 * Entspricht DoOpenFile/DoSaveFile in dialog.c und printing.c von ReactOS Notepad.
 * LICENSE: LGPL-2.1-or-later
 */

import AppKit

@objc(TextDocument)
final class TextDocument: NSDocument {
    private(set) var encoding: TextEncoding = .utf8
    private(set) var lineEnding: LineEnding = .lf
    private var loadedText: NSString = ""
    private var startsWithLog = false

    /// nil = detect from file name; "" = plain text; otherwise a SyntaxLanguage id.
    private(set) var languageChoice: String?

    override var fileURL: URL? {
        didSet { editor?.updateSyntaxLanguage() }
    }

    func syntaxLanguage(sample: NSString) -> SyntaxLanguage? {
        switch languageChoice {
        case nil: return SyntaxLanguage.detect(fileName: fileURL?.path, sample: sample)
        case "": return nil
        case let id?: return SyntaxLanguage.named(id)
        }
    }

    private var editor: EditorWindowController? {
        windowControllers.first as? EditorWindowController
    }

    private var currentText: NSString {
        editor?.textView.plainText ?? loadedText
    }

    // Classic Notepad behaviour: explicit Save, ask on close.
    override class var autosavesInPlace: Bool { false }

    override var shouldRunSavePanelWithAccessoryView: Bool { false }

    override func makeWindowControllers() {
        let controller = EditorWindowController(text: loadedText)
        addWindowController(controller)
        loadedText = ""

        // Files starting with ".LOG" get a time stamp appended on every open.
        if startsWithLog {
            controller.appendLogTimestamp()
        }
    }

    /// Memory-maps the file instead of copying it into a buffer first.
    override func read(from url: URL, ofType typeName: String) throws {
        try read(from: Data(contentsOf: url, options: .alwaysMapped), ofType: typeName)
    }

    override func read(from data: Data, ofType typeName: String) throws {
        let decoded = TextCodec.decode(data)
        encoding = decoded.encoding
        lineEnding = decoded.lineEnding
        startsWithLog = decoded.text.hasPrefix(".LOG")

        if let editor {
            // "Zurück zur letzten gesicherten Version"
            editor.replaceText(decoded.text)
        } else {
            loadedText = decoded.text
        }
    }

    override func data(ofType typeName: String) throws -> Data {
        do {
            return try TextCodec.encode(currentText, encoding: encoding, lineEnding: lineEnding)
        } catch TextCodecError.unrepresentable(let encoding) {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteInapplicableStringEncodingError, userInfo: [
                NSLocalizedDescriptionKey: "Der Text enthält Zeichen, die in \(encoding.displayName) nicht gespeichert werden können.",
                NSLocalizedRecoverySuggestionErrorKey: "Wähle unter „Format > Kodierung“ z. B. UTF-8 und sichere erneut.",
            ])
        }
    }

    override func prepareSavePanel(_ savePanel: NSSavePanel) -> Bool {
        savePanel.allowsOtherFileTypes = true
        savePanel.isExtensionHidden = false
        return true
    }

    override func printOperation(withSettings printSettings: [NSPrintInfo.AttributeKey: Any]) throws -> NSPrintOperation {
        let info = printInfo.copy() as! NSPrintInfo
        info.dictionary().addEntries(from: printSettings)
        info.dictionary()[NSPrintInfo.AttributeKey.headerAndFooter] = true
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false

        let width = info.paperSize.width - info.leftMargin - info.rightMargin
        let view = PrintTextView(frame: NSRect(x: 0, y: 0, width: width, height: 100))
        view.documentTitle = displayName
        view.appearance = NSAppearance(named: .aqua)
        view.string = currentText as String
        view.font = Preferences.font
        view.textColor = .black
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.textContainer?.widthTracksTextView = true
        view.sizeToFit()

        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.jobTitle = displayName
        return operation
    }

    // MARK: - Format menu

    @objc func changeTextEncoding(_ sender: NSMenuItem) {
        guard let newEncoding = TextEncoding(rawValue: sender.tag), newEncoding != encoding else { return }
        encoding = newEncoding
        updateChangeCount(.changeDone)
        editor?.updateStatusBar()
    }

    @objc func changeLineEnding(_ sender: NSMenuItem) {
        guard let newLineEnding = LineEnding(rawValue: sender.tag), newLineEnding != lineEnding else { return }
        lineEnding = newLineEnding
        updateChangeCount(.changeDone)
        editor?.updateStatusBar()
    }

    /// Tag 0 = automatic, 1 = plain text, 2 + n = SyntaxLanguage.all[n].
    @objc func changeSyntaxLanguage(_ sender: NSMenuItem) {
        switch sender.tag {
        case 0: languageChoice = nil
        case 1: languageChoice = ""
        default: languageChoice = SyntaxLanguage.all[sender.tag - 2].id
        }
        editor?.updateSyntaxLanguage()
    }

    private var languageMenuTag: Int {
        switch languageChoice {
        case nil: return 0
        case "": return 1
        case let id?: return (SyntaxLanguage.all.firstIndex { $0.id == id } ?? -1) + 2
        }
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if let menuItem = item as? NSMenuItem {
            switch menuItem.action {
            case #selector(changeTextEncoding(_:)):
                menuItem.state = menuItem.tag == encoding.rawValue ? .on : .off
                return true
            case #selector(changeLineEnding(_:)):
                menuItem.state = menuItem.tag == lineEnding.rawValue ? .on : .off
                return true
            case #selector(changeSyntaxLanguage(_:)):
                menuItem.state = menuItem.tag == languageMenuTag ? .on : .off
                return true
            default:
                break
            }
        }
        return super.validateUserInterfaceItem(item)
    }
}

/// Text view used only for printing: header shows the file name, footer the page number
/// (ReactOS defaults "&f" and "Page &p").
final class PrintTextView: NSTextView {
    var documentTitle = ""

    override var pageHeader: NSAttributedString {
        centered(documentTitle)
    }

    override var pageFooter: NSAttributedString {
        centered("Seite \(NSPrintOperation.current?.currentPage ?? 1)")
    }

    private func centered(_ string: String) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        return NSAttributedString(string: string, attributes: [
            .font: NSFont.systemFont(ofSize: 9),
            .foregroundColor: NSColor.black,
            .paragraphStyle: style,
        ])
    }
}
