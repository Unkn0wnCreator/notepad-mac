/*
 * Notepad für macOS – Syntaxhervorhebung für Konfigurationsdateien.
 * LICENSE: LGPL-2.1-or-later
 */

import Foundation

extension SyntaxLanguage {
    static let configLanguages: [SyntaxLanguage] = []

    /// Special file names and content sniffing (e.g. `.conf` as nginx, Apache or INI).
    /// `path` is lowercased; returns nil to fall back to file name/extension lookup.
    static func detectConfig(path: String, sample: NSString) -> SyntaxLanguage? {
        nil
    }
}
