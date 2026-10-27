/*
 * Notepad für macOS – Tests der Oberflächensprachen (Deutsch im Code, Englisch als Tabelle).
 * LICENSE: LGPL-2.1-or-later
 */

import AppKit

func runLocalizationTests(delegate: AppDelegate) {
    print("== Sprachen")
    guard let table = NSDictionary(contentsOfFile: "Resources/en.lproj/Localizable.strings") as? [String: String] else {
        check("en.lproj/Localizable.strings lesbar", false)
        return
    }
    check("en.lproj/Localizable.strings lesbar", !table.isEmpty, table.count)

    // Every literal L("…") key in the sources needs an English entry with the same placeholders.
    var keys: [String] = []
    var interpolated: [String] = []
    let literal = try! NSRegularExpression(pattern: #"L\("((?:\\.|[^"\\])*)""#)
    for name in try! FileManager.default.contentsOfDirectory(atPath: "Sources") where name.hasSuffix(".swift") {
        let source = try! String(contentsOfFile: "Sources/" + name, encoding: .utf8)
        for match in literal.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
            let raw = String(source[Range(match.range(at: 1), in: source)!])
            if raw.contains(#"\("#) { interpolated.append("\(name): \(raw)") }
            keys.append(raw.replacingOccurrences(of: #"\n"#, with: "\n")
                .replacingOccurrences(of: #"\""#, with: "\"")
                .replacingOccurrences(of: #"\\"#, with: "\\"))
        }
    }
    check("L(…) ohne String-Interpolation im Schlüssel", interpolated.isEmpty, interpolated)
    check("Mindestens 70 übersetzte Texte im Code", Set(keys).count >= 70, Set(keys).count)
    let missing = Set(keys).subtracting(table.keys).sorted()
    check("Jeder Text hat eine englische Übersetzung", missing.isEmpty, missing)

    let placeholder = try! NSRegularExpression(pattern: "%[@a-z]+")
    func placeholders(_ s: String) -> [String] {
        placeholder.matches(in: s, range: NSRange(s.startIndex..., in: s)).map { (s as NSString).substring(with: $0.range) }
    }
    let wrongPlaceholders = table.filter { placeholders($0.key) != placeholders($0.value) }.keys.sorted()
    check("Gleiche Platzhalter in beiden Sprachen", wrongPlaceholders.isEmpty, wrongPlaceholders)
    let german = table.filter { $0.value.rangeOfCharacter(from: CharacterSet(charactersIn: "äöüÄÖÜß")) != nil }.keys.sorted()
    check("Englische Texte ohne Umlaute", german.isEmpty, german)
    for language in SyntaxLanguage.all where table[language.name] == nil {
        // Names without an entry stay as they are and must already be English.
        check("Sprachname \(language.name) braucht keine Übersetzung",
              language.name.rangeOfCharacter(from: CharacterSet(charactersIn: "äöüÄÖÜß")) == nil
                  && !language.name.contains("Konfiguration") && !language.name.contains("Datei"))
    }

    // Bundle setup: both localizations declared, InfoPlist.strings for the document type name.
    let info = NSDictionary(contentsOfFile: "Resources/Info.plist")!
    check("Info.plist: de und en", info["CFBundleLocalizations"] as? [String] == ["de", "en"]
          && info["CFBundleDevelopmentRegion"] as? String == "en")
    let typeName = ((info["CFBundleDocumentTypes"] as? [[String: Any]])?.first?["CFBundleTypeName"] as? String) ?? ""
    let infoStrings = NSDictionary(contentsOfFile: "Resources/en.lproj/InfoPlist.strings") as? [String: String]
    check("en.lproj/InfoPlist.strings übersetzt den Dokumenttyp", infoStrings?[typeName] == "Text Document", typeName)
    check("de.lproj vorhanden", FileManager.default.fileExists(atPath: "Resources/de.lproj/InfoPlist.strings"))

    // The UI in English, then back to German for the other tests.
    Localization.table = table
    let menus = delegate.makeMainMenu().items.map(\.title)
    check("Englisch: Mac-Menüleiste", menus == ["Notepad", "File", "Edit", "Format", "View", "Window", "Help"], menus)
    check("Englisch: Fenster-Menüleiste", delegate.windowMenuTitles == ["File", "Edit", "Format", "View", "Help"], delegate.windowMenuTitles)
    check("Englisch: Datei endet mit Exit", delegate.makeWindowMenu(at: 0).items.last?.title == "Exit")
    check("Englisch: Statusleiste", L("Zeile %ld, Spalte %ld", 3, 14) == "Ln 3, Col 14", L("Zeile %ld, Spalte %ld", 3, 14))
    check("Englisch: Zeilenende", LineEnding.cr.displayName == "Classic Mac (CR)", LineEnding.cr.displayName)
    Localization.table = [:]
    _ = delegate.makeMainMenu()
    check("Zurück auf Deutsch", delegate.windowMenuTitles.first == "Datei" && L("Zeile %ld, Spalte %ld", 1, 2) == "Zeile 1, Spalte 2")
}
