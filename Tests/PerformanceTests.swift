/*
 * Notepad für macOS – Leistungstests. Laufen bei jedem ./test.sh, damit Verschlechterungen
 * sofort auffallen; die Grenzen sind großzügig gegenüber den gemessenen Werten gewählt.
 * LICENSE: LGPL-2.1-or-later
 */

import AppKit

private var results: [(name: String, value: String)] = []

/// Measures `block` in milliseconds and records it for the summary table.
@discardableResult
private func measure(_ name: String, limit: Double, _ block: () -> Void) -> Double {
    let start = Date()
    block()
    let ms = Date().timeIntervalSince(start) * 1000
    results.append((name, String(format: "%8.1f ms  (Grenze %.0f ms)", ms, limit)))
    check("Leistung: \(name)", ms <= limit, String(format: "%.1f ms > %.0f ms", ms, limit))
    return ms
}

func runPerformanceTests(fixtures: URL) {
    print("== Leistung")
    results = []

    // Window setup: from the prepared spare vs. built from scratch.
    EditorWindowController.prepareSpare()
    measure("Fenster aus Vorrat", limit: 15) {
        let controller = EditorWindowController.make(text: "Hallo")
        controller.window?.orderFront(nil)
        controller.window?.displayIfNeeded()
        controller.close()
    }
    measure("Fenster neu erzeugen", limit: 120) {
        let controller = EditorWindowController.make(text: "Hallo")
        controller.window?.orderFront(nil)
        controller.window?.displayIfNeeded()
        controller.close()
    }

    // A 50 MB file with CRLF line endings and some umlauts.
    let line = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor äöü.\r\n"
    let bigURL = fixtures.appendingPathComponent("gross-50mb.txt")
    let chunk = String(repeating: line, count: 1_000_000 / line.utf8.count).data(using: .utf8)!
    FileManager.default.createFile(atPath: bigURL.path, contents: nil)
    let handle = try! FileHandle(forWritingTo: bigURL)
    for _ in 0..<50 { handle.write(chunk) }
    try! handle.close()

    var document: TextDocument!
    measure("50 MB lesen + dekodieren", limit: 150) {
        document = try! TextDocument(contentsOf: bigURL, ofType: "public.plain-text")
    }
    measure("50 MB Fenster anzeigen", limit: 400) {
        document.makeWindowControllers()
        document.showWindows()
        document.windowControllers[0].window!.displayIfNeeded()
    }
    let controller = document.windowControllers[0] as! EditorWindowController
    let textView = controller.textView
    let window = textView.window!
    let length = textView.plainText.length

    func type(_ text: String, at location: Int) {
        textView.setSelectedRange(NSRange(location: location, length: 0))
        textView.insertText(text, replacementRange: textView.selectedRange())
        window.displayIfNeeded()
    }
    type("a", at: 0)  // the first edit at a position may move memory once
    measure("50 MB Tastendruck am Anfang", limit: 5) { type("b", at: 1) }
    measure("50 MB Sprung in die Mitte", limit: 150) {
        textView.setSelectedRange(NSRange(location: length / 2, length: 0))
        textView.scrollRangeToVisible(textView.selectedRange())
        window.displayIfNeeded()
    }
    type("c", at: length / 2)
    measure("50 MB Tastendruck in der Mitte", limit: 5) { type("d", at: length / 2 + 1) }
    type("e", at: textView.plainText.length)
    measure("50 MB Tastendruck am Ende", limit: 5) { type("f", at: textView.plainText.length) }

    Preferences.wordWrap = false
    type("f", at: 10)
    measure("50 MB Tastendruck ohne Umbruch", limit: 5) { type("g", at: 11) }
    Preferences.wordWrap = true

    measure("50 MB speichern (CRLF)", limit: 150) { _ = try! document.data(ofType: "") }
    document.close()

    // Incremental highlighting: 3 MB of Swift-like code, edit in the middle.
    let code = """
    struct Item { let name = "value // not a comment"; var count = 42 } // comment
    func compute(_ x: Int) -> Int { return x * 2 + 0x1F }

    """
    let codeURL = fixtures.appendingPathComponent("code-3mb.swift")
    try! String(repeating: code, count: 3_000_000 / code.utf8.count).data(using: .utf8)!.write(to: codeURL)
    let codeDocument = try! TextDocument(contentsOf: codeURL, ofType: "public.plain-text")
    codeDocument.makeWindowControllers()
    codeDocument.showWindows()
    let codeView = (codeDocument.windowControllers[0] as! EditorWindowController).textView
    let layoutManager = codeView.layoutManager!
    func color(at location: Int) -> NSColor? {
        layoutManager.temporaryAttribute(.foregroundColor, atCharacterIndex: location, effectiveRange: nil) as? NSColor
    }
    let highlighter: SyntaxHighlighter = ivar(codeDocument.windowControllers[0], "highlighter")
    var start = Date()
    waitUntil(timeout: 10) { color(at: 0) != nil }
    let firstColors = Date().timeIntervalSince(start) * 1000
    results.append(("3 MB Code: erste Farben", String(format: "%8.1f ms  (Grenze 500 ms)", firstColors)))
    check("Leistung: erste Farben", firstColors < 500, String(format: "%.1f ms", firstColors))
    waitUntil(timeout: 20) { highlighter.isUpToDate }
    results.append(("3 MB Code: komplett analysiert", String(format: "%8.1f ms", Date().timeIntervalSince(start) * 1000)))

    let editAt = (codeView.plainText.length / 2 / code.utf16.count) * code.utf16.count
    codeView.setSelectedRange(NSRange(location: editAt, length: 0))
    codeView.scrollRangeToVisible(codeView.selectedRange())
    waitUntil(timeout: 5) { color(at: editAt) != nil }
    start = Date()
    codeView.insertText("let ", replacementRange: NSRange(location: editAt, length: 0))
    let recolored = waitUntil(timeout: 5) {
        color(at: editAt) == TokenKind.keyword.color && color(at: editAt + 4) == TokenKind.keyword.color
    }
    let incremental = Date().timeIntervalSince(start) * 1000
    results.append(("3 MB Code: neu gefärbt nach Edit", String(format: "%8.1f ms  (Grenze 300 ms)", incremental)))
    check("Leistung: inkrementelle Hervorhebung", recolored && incremental < 300, String(format: "%.1f ms", incremental))
    codeDocument.close()

    for result in results {
        print("     " + result.name.padding(toLength: 36, withPad: " ", startingAt: 0) + result.value)
    }
}
