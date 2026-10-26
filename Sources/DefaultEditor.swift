/*
 * Notepad für macOS – Notepad als Standard-Texteditor festlegen (statt TextEdit) und zurückstellen.
 * LICENSE: LGPL-2.1-or-later
 */

import AppKit
import UniformTypeIdentifiers

enum DefaultEditor {
    /// Text types that open with Notepad on double-click. HTML and RTF are left alone on purpose.
    static let contentTypes: [UTType] = {
        var types: [UTType] = [
            .plainText, .utf8PlainText, .utf16PlainText, .utf16ExternalPlainText,
            .delimitedText, .commaSeparatedText, .tabSeparatedText, .utf8TabSeparatedText,
            .sourceCode, .cSource, .cHeader, .cPlusPlusSource, .cPlusPlusHeader,
            .objectiveCSource, .objectiveCPlusPlusSource, .swiftSource,
            .script, .shellScript, .pythonScript, .rubyScript, .perlScript, .phpScript, .javaScript,
            .json, .xml, .yaml, .log, .makefile,
        ]
        for identifier in ["net.daringfireball.markdown", "public.css", "public.toml"] {
            if let type = UTType(identifier) { types.append(type) }
        }
        return types
    }()

    private static let previousHandlersKey = "previousDefaultEditors"
    private static let textEditURL = URL(fileURLWithPath: "/System/Applications/TextEdit.app")

    static var isDefault: Bool {
        guard let url = NSWorkspace.shared.urlForApplication(toOpen: .plainText) else { return false }
        return isNotepad(url)
    }

    static var isInApplicationsFolder: Bool {
        Bundle.main.bundleURL.path.hasPrefix("/Applications/")
    }

    private static func isNotepad(_ appURL: URL) -> Bool {
        Bundle(url: appURL)?.bundleIdentifier == Bundle.main.bundleIdentifier
    }

    /// Makes Notepad the default app and remembers the previous ones for `restore`.
    /// Returns the types that could not be changed.
    static func makeDefault() -> [UTType] {
        var previous = UserDefaults.standard.dictionary(forKey: previousHandlersKey) as? [String: String] ?? [:]
        for type in contentTypes where previous[type.identifier] == nil {
            if let url = NSWorkspace.shared.urlForApplication(toOpen: type), !isNotepad(url) {
                previous[type.identifier] = url.path
            }
        }
        UserDefaults.standard.set(previous, forKey: previousHandlersKey)

        // Make sure Launch Services resolves our bundle identifier to this copy of the app.
        LSRegisterURL(Bundle.main.bundleURL as CFURL, true)
        return setHandlers(contentTypes.map { ($0, Bundle.main.bundleURL) })
    }

    /// Gives every type back to the app it had before (TextEdit if unknown).
    static func restore() -> [UTType] {
        let previous = UserDefaults.standard.dictionary(forKey: previousHandlersKey) as? [String: String] ?? [:]
        let handlers = contentTypes.map { type -> (UTType, URL) in
            if let path = previous[type.identifier], FileManager.default.fileExists(atPath: path) {
                return (type, URL(fileURLWithPath: path))
            }
            return (type, textEditURL)
        }
        let failed = setHandlers(handlers)
        if failed.isEmpty {
            UserDefaults.standard.removeObject(forKey: previousHandlersKey)
        }
        return failed
    }

    /// Uses Launch Services directly: unlike NSWorkspace.setDefaultApplication it does not ask
    /// the user to confirm every single content type.
    private static func setHandlers(_ handlers: [(UTType, URL)]) -> [UTType] {
        var failed: [UTType] = []
        for (type, appURL) in handlers {
            guard let bundleID = Bundle(url: appURL)?.bundleIdentifier else {
                failed.append(type)
                continue
            }
            let status = LSSetDefaultRoleHandlerForContentType(type.identifier as CFString, .all, bundleID as CFString)
            if status != noErr {
                failed.append(type)
            }
        }
        return failed
    }

    // MARK: - Menu action

    /// One click in the menu, one confirmation. Only failures are reported afterwards.
    static func runToggleDialog() {
        let alert = NSAlert()
        if isDefault {
            alert.messageText = "Textdateien wieder mit den vorherigen Apps öffnen?"
            alert.informativeText = "Notepad ist zurzeit der Standard-Texteditor. Die vorher verwendeten Apps (z. B. TextEdit) werden wiederhergestellt."
            alert.addButton(withTitle: "Zurückstellen")
        } else {
            alert.messageText = "Notepad als Standard-Texteditor verwenden?"
            var info = "Text, Code und Skripte, JSON, XML, YAML, Markdown, CSV und Logdateien öffnen sich dann per Doppelklick mit Notepad. Über denselben Menüpunkt lässt sich das zurückstellen."
            if !isInApplicationsFolder {
                info += "\n\nTipp: Notepad liegt nicht im Ordner „Programme“, sondern in:\n"
                    + Bundle.main.bundleURL.deletingLastPathComponent().path
            }
            alert.informativeText = info
            alert.addButton(withTitle: "Als Standard festlegen")
        }
        alert.addButton(withTitle: "Abbrechen")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let failed = isDefault ? restore() : makeDefault()
        if !failed.isEmpty {
            let error = NSAlert()
            error.alertStyle = .warning
            error.messageText = "Einige Dateitypen konnten nicht umgestellt werden."
            error.informativeText = failed.map { $0.localizedDescription ?? $0.identifier }.joined(separator: "\n")
            error.runModal()
        }
    }
}
