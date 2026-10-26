/*
 * Notepad für macOS – Oberflächen-Tests: steuern Dokument, Fenster und Menüs ohne Benutzer.
 * LICENSE: LGPL-2.1-or-later
 */

import AppKit
import PDFKit

func runGUITests(app: NSApplication, delegate: AppDelegate, fixtures: URL) {
    print("== Oberfläche")

    let menus = app.mainMenu!.items.map(\.title)
    check("Mac-Menüleiste", menus == ["Notepad", "Ablage", "Bearbeiten", "Format", "Darstellung", "Fenster", "Hilfe"], menus)
    check("Fenster-Menüleiste Titel", delegate.windowMenuTitles == ["Datei", "Bearbeiten", "Format", "Ansicht", "Hilfe"], delegate.windowMenuTitles)
    let datei = delegate.makeWindowMenu(at: 0)
    check("Datei endet mit Beenden", datei.items.last?.title == "Beenden")
    check("Original-Ablage ohne Beenden", app.mainMenu!.items[1].submenu!.items.last?.title == "Drucken …")
    let wrapItem = delegate.makeWindowMenu(at: 2).items.first!
    _ = delegate.validateMenuItem(wrapItem)
    check("Häkchen Zeilenumbruch in Fenster-Menü", wrapItem.title == "Zeilenumbruch" && wrapItem.state == .on)

    let dir = fixtures
    let ansiURL = dir.appendingPathComponent("ansi-test.txt")
    let ansiText = "Hallo aus der Mac-Version!\r\nZeile 2 mit Umlauten: äöüß\r\n\tEingerückt mit Tab\r\n"
    try! ansiText.data(using: .windowsCP1252)!.write(to: ansiURL)
    let doc = try! TextDocument(contentsOf: ansiURL, ofType: "public.plain-text")
    NSDocumentController.shared.addDocument(doc)
    doc.makeWindowControllers(); doc.showWindows(); spin()
    let wc = doc.windowControllers.first as! EditorWindowController
    let tv = wc.textView
    let strip: MenuStripView = ivar(wc, "menuStrip")
    let stripButtons = strip.subviews.compactMap { $0 as? NSStackView }.first!.arrangedSubviews.compactMap { ($0 as? NSButton)?.title }
    check("Menüleiste im Fenster sichtbar", stripButtons == ["Datei", "Bearbeiten", "Format", "Ansicht", "Hilfe"] && strip.frame.height == 26, stripButtons)
    check("Menüleiste oben, Text darunter", strip.frame.maxY == wc.window!.contentView!.bounds.maxY && tv.enclosingScrollView!.frame.maxY <= strip.frame.minY, "\(strip.frame) \(tv.enclosingScrollView!.frame)")

    check("ANSI-Text korrekt dekodiert", tv.string == "Hallo aus der Mac-Version!\nZeile 2 mit Umlauten: äöüß\n\tEingerückt mit Tab\n", tv.string)
    let bar: StatusBarView = ivar(wc, "statusBar")
    check("Statusleiste Kodierung", bar.encodingLabel.stringValue == "ANSI (Windows-1252)", bar.encodingLabel.stringValue)
    check("Statusleiste Zeilenende", bar.lineEndingLabel.stringValue == "Windows (CRLF)", bar.lineEndingLabel.stringValue)
    check("Statusleiste Sprache .txt", bar.languageLabel.stringValue == "Nur Text", bar.languageLabel.stringValue)
    check("Statusleiste Position", bar.positionLabel.stringValue == "Zeile 1, Spalte 1", bar.positionLabel.stringValue)
    check("Fenstertitel", wc.window!.title == "ansi-test.txt", wc.window!.title)
    check("unverändert nach Öffnen", !doc.isDocumentEdited)

    tv.setSelectedRange(NSRange(location: 33, length: 0))
    check("Position Zeile 2", bar.positionLabel.stringValue == "Zeile 2, Spalte 7", bar.positionLabel.stringValue)

    tv.setSelectedRange(NSRange(location: 0, length: 0))
    tv.insertText("X", replacementRange: tv.selectedRange()); spin()
    check("Tippen markiert als geändert", doc.isDocumentEdited)
    doc.undoManager?.undo(); spin()
    check("Undo stellt Text her", tv.string.hasPrefix("Hallo"))
    check("Nach Undo wieder unverändert", !doc.isDocumentEdited)

    check("Speichern byte-identisch", (try! doc.data(ofType: "")) == (try! Data(contentsOf: ansiURL)))

    tv.insertText("😀", replacementRange: NSRange(location: 0, length: 0))
    do { _ = try doc.data(ofType: ""); check("ANSI-Fehler", false) }
    catch { check("ANSI-Fehlermeldung", error.localizedDescription.contains("ANSI"), error.localizedDescription) }
    let enc = NSMenuItem(); enc.tag = TextEncoding.utf8.rawValue
    doc.changeTextEncoding(enc)
    check("Kodierung umgestellt", doc.encoding == .utf8 && bar.encodingLabel.stringValue == "UTF-8")
    check("UTF-8 speichern klappt", String(data: try! doc.data(ofType: ""), encoding: .utf8)!.hasPrefix("😀Hallo"))

    wc.insertTimeDate(nil)
    check("F5 fügt Datum ein", tv.string.contains(String(Calendar.current.component(.year, from: Date()))))

    wc.zoomIn(nil); wc.zoomIn(nil)
    check("Zoom 120 %", bar.zoomLabel.stringValue == "120 %" && abs((tv.typingAttributes[.font] as! NSFont).pointSize - 13 * 1.2) < 0.01, bar.zoomLabel.stringValue)
    wc.resetZoom(nil)

    check("Umbruch standardmäßig an", tv.textContainer!.widthTracksTextView)
    delegate.toggleWordWrap(nil); spin()
    check("Umbruch aus", !tv.textContainer!.widthTracksTextView && tv.enclosingScrollView!.hasHorizontalScroller)
    tv.insertText(String(repeating: "lang ", count: 400), replacementRange: NSRange(location: 0, length: 0))
    check("Ohne Umbruch: Breite wächst mit langer Zeile", waitUntil { tv.frame.width > 1500 }, tv.frame.width)
    doc.undoManager?.undo(); spin()
    delegate.toggleWordWrap(nil); spin()
    check("Umbruch wieder an", tv.textContainer!.widthTracksTextView && abs(tv.frame.width - tv.enclosingScrollView!.contentSize.width) < 1, tv.frame.width)

    delegate.toggleStatusBar(nil); spin()
    check("Statusleiste aus", bar.isHidden)
    delegate.toggleStatusBar(nil)

    let doc2 = TextDocument(); NSDocumentController.shared.addDocument(doc2); doc2.makeWindowControllers(); doc2.showWindows()
    Preferences.font = NSFont(name: "Menlo", size: 16)!
    let tv2 = (doc2.windowControllers.first as! EditorWindowController).textView
    check("Schrift in beiden Fenstern", (tv.typingAttributes[.font] as? NSFont)?.fontName == "Menlo-Regular" && tv2.font?.pointSize == 16, "\(String(describing: tv.font)) \(String(describing: tv2.font))")
    check("Neues Dokument: UTF-8/LF", doc2.encoding == .utf8 && doc2.lineEnding == .lf)

    let logURL = dir.appendingPathComponent("log.txt")
    try! ".LOG\r\nalt\r\n".data(using: .utf8)!.write(to: logURL)
    let logDoc = try! TextDocument(contentsOf: logURL, ofType: "public.plain-text")
    logDoc.makeWindowControllers(); spin()
    let logText = (logDoc.windowControllers.first as! EditorWindowController).textView.string
    check(".LOG hängt Zeitstempel an", logText.hasPrefix(".LOG\nalt\n\n") && logText.hasSuffix("\n") && logText.count > 15, logText)
    check(".LOG als geändert markiert", logDoc.isDocumentEdited)

    // Syntaxhervorhebung im Fenster
    let swiftURL = dir.appendingPathComponent("beispiel.swift")
    try! "import AppKit\nlet name = \"Notepad\" // Kommentar\n".data(using: .utf8)!.write(to: swiftURL)
    let swiftDoc = try! TextDocument(contentsOf: swiftURL, ofType: "public.plain-text")
    NSDocumentController.shared.addDocument(swiftDoc)
    swiftDoc.makeWindowControllers(); swiftDoc.showWindows()
    let swiftWC = swiftDoc.windowControllers.first as! EditorWindowController
    let swiftBar: StatusBarView = ivar(swiftWC, "statusBar")
    let lm = swiftWC.textView.layoutManager!
    func color(at location: Int) -> NSColor? {
        lm.temporaryAttribute(.foregroundColor, atCharacterIndex: location, effectiveRange: nil) as? NSColor
    }
    check("Sprache Swift erkannt", swiftBar.languageLabel.stringValue == "Swift", swiftBar.languageLabel.stringValue)
    check("Keyword eingefärbt", waitUntil { color(at: 0) == TokenKind.keyword.color })
    check("String eingefärbt", color(at: 25) == TokenKind.string.color)
    check("Bezeichner nicht eingefärbt", color(at: 18) == nil)
    check("Datei bleibt unverändert", !swiftDoc.isDocumentEdited)

    swiftWC.textView.insertText("var ", replacementRange: NSRange(location: 0, length: 0))
    check("Nach Tippen neu eingefärbt", waitUntil { color(at: 0) == TokenKind.keyword.color && color(at: 4) == TokenKind.keyword.color })

    let plainItem = NSMenuItem(); plainItem.tag = 1
    swiftDoc.changeSyntaxLanguage(plainItem)
    check("Nur Text: keine Farben", waitUntil { color(at: 0) == nil } && swiftBar.languageLabel.stringValue == "Nur Text")
    let autoItem = NSMenuItem(); autoItem.tag = 0
    swiftDoc.changeSyntaxLanguage(autoItem)
    check("Automatisch: wieder Swift", waitUntil { color(at: 0) == TokenKind.keyword.color })

    delegate.toggleSyntaxHighlighting(nil)
    check("Hervorhebung aus", waitUntil { color(at: 0) == nil })
    delegate.toggleSyntaxHighlighting(nil)
    check("Hervorhebung wieder an", waitUntil { color(at: 0) == TokenKind.keyword.color })

    let untitled = TextDocument(); NSDocumentController.shared.addDocument(untitled)
    untitled.makeWindowControllers(); untitled.showWindows()
    let untitledWC = untitled.windowControllers.first as! EditorWindowController
    untitledWC.textView.insertText("#!/bin/bash\necho hi\n", replacementRange: NSRange(location: 0, length: 0))
    let untitledBar: StatusBarView = ivar(untitledWC, "statusBar")
    check("Unbenannt: Shebang erkannt", waitUntil { untitledBar.languageLabel.stringValue == "Shell" }, untitledBar.languageLabel.stringValue)

    // Standard-Editor: nur Menü und Typliste prüfen, nichts am System ändern
    let helpMenu = delegate.makeWindowMenu(at: 4)
    check("Hilfe-Menü: Standard-Editor", helpMenu.items.first?.title == "Notepad als Standard-Texteditor verwenden", helpMenu.items.map(\.title))
    check("Standard-Editor: Typliste", DefaultEditor.contentTypes.count >= 25 && !DefaultEditor.contentTypes.contains(.html))
    let sprache = delegate.makeWindowMenu(at: 2).items.first { $0.title == "Sprache" }?.submenu
    check("Format > Sprache", sprache?.items.count == SyntaxLanguage.all.count + 3)

    // Drag & drop: into an empty untitled window → same window; into a window with text → new one
    let dropA = dir.appendingPathComponent("drop-a.txt"), dropB = dir.appendingPathComponent("drop-b.md")
    try! "Abgelegt A".data(using: .utf8)!.write(to: dropA)
    try! "# Abgelegt B".data(using: .utf8)!.write(to: dropB)
    let emptyDoc = TextDocument(); NSDocumentController.shared.addDocument(emptyDoc)
    emptyDoc.makeWindowControllers(); emptyDoc.showWindows()
    let dropWC = emptyDoc.windowControllers.first as! EditorWindowController
    let dropWindow = dropWC.window
    dropWC.openDroppedFiles([dropA])
    check("Drop in leeres Fenster: gleiches Fenster", waitUntil { (dropWC.document as? TextDocument)?.fileURL == dropA }
          && dropWC.window === dropWindow && dropWC.textView.string == "Abgelegt A", dropWC.textView.string)
    check("Drop: leeres Dokument geschlossen", !NSDocumentController.shared.documents.contains { $0 === emptyDoc })
    check("Drop: Titel aktualisiert", dropWindow?.title == "drop-a.txt", dropWindow?.title ?? "")
    dropWC.openDroppedFiles([dropB])
    check("Drop in Fenster mit Text: neues Fenster", waitUntil {
        NSDocumentController.shared.documents.contains { $0.fileURL == dropB && !$0.windowControllers.isEmpty }
    } && (dropWC.document as? TextDocument)?.fileURL == dropA)

    // Menu strip: hover detection maps screen points to titles
    let dropStrip: MenuStripView = ivar(dropWC, "menuStrip")
    dropStrip.layoutSubtreeIfNeeded()
    let second = dropStrip.buttons[1]
    let center = second.window!.convertPoint(toScreen: second.convert(NSPoint(x: second.bounds.midX, y: second.bounds.midY), to: nil))
    check("Menüleiste: Titel unter der Maus erkannt", dropStrip.buttonIndex(atScreenPoint: center) == 1)

    // Closing a window must free its text (storage, layout manager and text view form a cycle)
    weak var closedStorage: NSTextStorage?
    autoreleasepool {
        let leakDoc = try! TextDocument(contentsOf: dropA, ofType: "public.plain-text")
        leakDoc.makeWindowControllers(); leakDoc.showWindows()
        closedStorage = (leakDoc.windowControllers[0] as! EditorWindowController).textView.textStorage
        leakDoc.close()
    }
    check("Geschlossenes Fenster gibt Text frei", waitUntil { closedStorage == nil })

    let pdfURL = dir.appendingPathComponent("druck.pdf")
    try? FileManager.default.removeItem(at: pdfURL)
    tv.string = (1...150).map { "Zeile \($0)" }.joined(separator: "\n")
    doc.printInfo.dictionary()[NSPrintInfo.AttributeKey.jobDisposition] = NSPrintInfo.JobDisposition.save
    doc.printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = pdfURL
    let op = try! doc.printOperation(withSettings: [:])
    op.showsPrintPanel = false; op.showsProgressPanel = false
    check("Druck läuft", op.run())
    let pdf = PDFDocument(url: pdfURL)
    check("PDF mehrseitig", (pdf?.pageCount ?? 0) >= 2, pdf?.pageCount ?? 0)
    let p1 = pdf?.page(at: 0)?.string ?? ""
    check("Kopfzeile Dateiname", p1.contains("ansi-test.txt"), p1.prefix(80))
    check("Fußzeile Seite 1", p1.contains("Seite 1"), p1.suffix(80))
    check("Inhalt gedruckt", p1.contains("Zeile 1"))

}
