/*
 * Notepad für macOS – Tests für Kodierung, Zeilenenden und Zeilenzählung (TextCodec.swift).
 * LICENSE: LGPL-2.1-or-later
 */

import Foundation

func runCodecTests() {
    print("== Datei-Logik")
    func roundtrip(_ name: String, _ bytes: [UInt8], enc: TextEncoding, eol: LineEnding, text: String) {
        let d = TextCodec.decode(Data(bytes))
        check("\(name): Kodierung \(d.encoding)", d.encoding == enc)
        check("\(name): Zeilenende \(d.lineEnding)", d.lineEnding == eol)
        check("\(name): Text", d.text as String == text)
        let back = try! TextCodec.encode(d.text, encoding: d.encoding, lineEnding: d.lineEnding)
        check("\(name): Roundtrip byte-identisch", [UInt8](back) == bytes)
    }
    roundtrip("ASCII CRLF", Array("a\r\nb\r\n".utf8), enc: .utf8, eol: .crlf, text: "a\nb\n")
    roundtrip("UTF-8 LF Umlaute", Array("Grüße\nÄÖÜ".utf8), enc: .utf8, eol: .lf, text: "Grüße\nÄÖÜ")
    roundtrip("UTF-8 BOM", [0xEF,0xBB,0xBF] + Array("hä\r\n".utf8), enc: .utf8BOM, eol: .crlf, text: "hä\n")
    roundtrip("UTF-16 LE BOM", [0xFF,0xFE] + Array("hi\r\nü".data(using: .utf16LittleEndian)!), enc: .utf16LE, eol: .crlf, text: "hi\nü")
    roundtrip("UTF-16 BE BOM", [0xFE,0xFF] + Array("hi\nü".data(using: .utf16BigEndian)!), enc: .utf16BE, eol: .lf, text: "hi\nü")
    roundtrip("ANSI cp1252", [0x47,0x72,0xFC,0xDF,0x65,0x0D], enc: .ansi, eol: .cr, text: "Grüße\n")
    let le = TextCodec.decode("Hallo Welt\r\n".data(using: .utf16LittleEndian)!)
    check("UTF-16 LE ohne BOM erkannt", le.encoding == .utf16LE && le.text as String == "Hallo Welt\n")
    check("NUL wird Leerzeichen", TextCodec.decode(Data([0x61,0x00,0x62,0xC3,0xBC])).text as String == "a bü")
    let be = TextCodec.decode("Hallo\nWelt".data(using: .utf16BigEndian)!)
    check("UTF-16 BE ohne BOM erkannt", be.encoding == .utf16BE && be.text as String == "Hallo\nWelt")
    roundtrip("UTF-16 LE CR", [0xFF,0xFE] + Array("a\rb\r".data(using: .utf16LittleEndian)!), enc: .utf16LE, eol: .cr, text: "a\nb\n")
    roundtrip("UTF-16 BE CRLF", [0xFE,0xFF] + Array("a\r\nb".data(using: .utf16BigEndian)!), enc: .utf16BE, eol: .crlf, text: "a\nb")
    let broken = TextCodec.decode(Data([0xEF,0xBB,0xBF,0x61,0xFF,0x62]))
    check("Kaputtes UTF-8 mit BOM wird repariert", broken.encoding == .utf8BOM && broken.text as String == "a\u{FFFD}b")
    let pasted = try! TextCodec.encode("a\r\nb\rc\n", encoding: .utf8, lineEnding: .crlf)
    check("Eingefügte \\r werden beim Speichern normalisiert", pasted == Data("a\r\nb\r\nc\r\n".utf8))
    check("Leere Datei", TextCodec.decode(Data()).text.length == 0 )
    check("ANSI unmögliches Zeichen wirft Fehler", (try? TextCodec.encode("€😀", encoding: .ansi, lineEnding: .lf)) == nil)
    check("Emoji UTF-16 Roundtrip", TextCodec.decode(try! TextCodec.encode("😀\n", encoding: .utf16LE, lineEnding: .crlf)).text as String == "😀\n")
    let s = "eins\nzwei\r\ndrei\rvier" as NSString
    check("Position Zeile 3", LineScanner.position(of: 12, in: s) == (3, 2) && LineScanner.position(of: 15, in: s) == (3, 5))
    check("Zeilenanzahl 4", LineScanner.lineCount(in: s) == 4)
    check("Offset Zeile 3", LineScanner.offset(ofLine: 3, in: s) == 11)
    check("Offset Zeile 4", LineScanner.offset(ofLine: 4, in: s) == 16)
    check("Offset leere letzte Zeile", LineScanner.offset(ofLine: 2, in: "a\n") == 2)
}

func runPositionCacheTests() {
    print("== Zeilen-Cache der Statusleiste")
    // Random caret moves and edits must give the same result as a full scan.
    var generator = SystemRandomNumberGenerator()
    let pieces = ["a", "bc", "\n", "\r\n", "\r", "xyz", "\n\n"]
    let text = NSMutableString(string: (0..<400).map { _ in pieces.randomElement(using: &generator)! }.joined())
    var cache = LinePositionCache()
    var mismatches = 0
    for step in 0..<3000 {
        if step % 7 == 0 {
            let location = Int.random(in: 0...text.length, using: &generator)
            let length = min(Int.random(in: 0...3, using: &generator), text.length - location)
            text.replaceCharacters(in: NSRange(location: location, length: length),
                                   with: pieces.randomElement(using: &generator)!)
            cache.textChanged(at: location)
        }
        let location = Int.random(in: 0...text.length, using: &generator)
        let cached = cache.position(of: location, in: text)
        let full = LineScanner.position(of: location, in: text)
        if cached != full { mismatches += 1 }
    }
    check("Cache stimmt mit vollständiger Zählung überein (3000 Schritte)", mismatches == 0, mismatches)
}
