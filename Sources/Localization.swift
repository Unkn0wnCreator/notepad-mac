/*
 * Notepad für macOS – Oberflächensprache: Deutsch oder Englisch, nach der Systemsprache.
 * LICENSE: LGPL-2.1-or-later
 */

import Foundation

/// UI texts are written in German in the code, and the German text is the key into
/// `en.lproj/Localizable.strings`. With German as the preferred localization the keys are shown
/// as they are; any other system language gets the English table (CFBundleDevelopmentRegion is
/// `en`). Placeholders use `String(format:)` syntax (`%@`, `%ld`), never string interpolation in
/// the key – the test checks that every key has an English entry with the same placeholders.
enum Localization {
    /// German → English, empty for German. Tests set it explicitly.
    static var table: [String: String] = loadTable()

    static func loadTable(bundle: Bundle = .main) -> [String: String] {
        guard bundle.preferredLocalizations.first != "de",
              let url = bundle.url(forResource: "Localizable", withExtension: "strings",
                                   subdirectory: nil, localization: "en"),
              let table = NSDictionary(contentsOf: url) as? [String: String]
        else { return [:] }
        return table
    }
}

/// The UI text for `german` in the current language.
func L(_ german: String) -> String {
    Localization.table[german] ?? german
}

/// Like `L(_:)`, then `String(format:)` with `arguments`.
func L(_ german: String, _ arguments: CVarArg...) -> String {
    String(format: L(german), arguments: arguments)
}
