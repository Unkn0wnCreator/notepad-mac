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
    static func makeDefault(completion: @escaping (_ failed: [UTType]) -> Void) {
        var previous = UserDefaults.standard.dictionary(forKey: previousHandlersKey) as? [String: String] ?? [:]
        for type in contentTypes where previous[type.identifier] == nil {
            if let url = NSWorkspace.shared.urlForApplication(toOpen: type), !isNotepad(url) {
                previous[type.identifier] = url.path
            }
        }
        UserDefaults.standard.set(previous, forKey: previousHandlersKey)

        setHandlers(contentTypes.map { ($0, Bundle.main.bundleURL) }, completion: completion)
    }

    /// Gives every type back to the app it had before (TextEdit if unknown).
    static func restore(completion: @escaping (_ failed: [UTType]) -> Void) {
        let previous = UserDefaults.standard.dictionary(forKey: previousHandlersKey) as? [String: String] ?? [:]
        let handlers = contentTypes.map { type -> (UTType, URL) in
            if let path = previous[type.identifier], FileManager.default.fileExists(atPath: path) {
                return (type, URL(fileURLWithPath: path))
            }
            return (type, textEditURL)
        }
        setHandlers(handlers) { failed in
            if failed.isEmpty {
                UserDefaults.standard.removeObject(forKey: previousHandlersKey)
            }
            completion(failed)
        }
    }

    private static func setHandlers(_ handlers: [(UTType, URL)], completion: @escaping ([UTType]) -> Void) {
        let group = DispatchGroup()
        let lock = NSLock()
        var failed: [UTType] = []
        for (type, appURL) in handlers {
            group.enter()
            NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: type) { error in
                if error != nil {
                    lock.lock()
                    failed.append(type)
                    lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) { completion(failed) }
    }

    // MARK: - Menu action

    static func runToggleDialog() {
        if isDefault {
            let alert = NSAlert()
            alert.messageText = "Notepad ist der Standard-Texteditor."
            alert.informativeText = "Sollen Textdateien wieder mit den vorherigen Apps (z. B. TextEdit) geöffnet werden?"
            alert.addButton(withTitle: "Zurückstellen")
            alert.addButton(withTitle: "Abbrechen")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            restore { failed in
                showResult(failed, success: "Textdateien öffnen sich wieder mit den vorherigen Apps.")
            }
        } else {
            let alert = NSAlert()
            alert.messageText = "Notepad als Standard-Texteditor verwenden?"
            var info = "Textdateien, Code und Skripte, JSON, XML, YAML, Markdown, CSV und Logdateien "
                + "werden danach per Doppelklick mit Notepad geöffnet statt mit TextEdit oder anderen Apps.\n\n"
                + "Die bisherigen Apps werden gemerkt. Über denselben Menüpunkt lässt sich alles zurückstellen."
            if !isInApplicationsFolder {
                info += "\n\nTipp: Lege Notepad vorher in den Ordner „Programme“. Notepad liegt gerade hier:\n"
                    + Bundle.main.bundleURL.deletingLastPathComponent().path
            }
            alert.informativeText = info
            alert.addButton(withTitle: "Als Standard festlegen")
            alert.addButton(withTitle: "Abbrechen")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            makeDefault { failed in
                showResult(failed, success: "Notepad ist jetzt der Standard-Texteditor.")
            }
        }
    }

    private static func showResult(_ failed: [UTType], success: String) {
        let alert = NSAlert()
        if failed.isEmpty {
            alert.messageText = success
        } else {
            alert.alertStyle = .warning
            alert.messageText = "Einige Dateitypen konnten nicht umgestellt werden."
            alert.informativeText = failed.map { $0.localizedDescription ?? $0.identifier }.joined(separator: "\n")
        }
        alert.runModal()
    }
}
