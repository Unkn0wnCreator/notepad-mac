/*
 * Notepad für macOS – Einstellungen (entspricht settings.c in ReactOS Notepad).
 * LICENSE: LGPL-2.1-or-later
 */

import AppKit

enum Preferences {
    /// Posted whenever font, word wrap or status bar visibility changes.
    static let didChange = Notification.Name("NotepadPreferencesDidChange")

    private static let fontKey = "font"
    private static let wordWrapKey = "wordWrap"
    private static let showStatusBarKey = "showStatusBar"
    private static let syntaxHighlightingKey = "syntaxHighlighting"

    private static var defaults: UserDefaults { .standard }

    static func registerDefaults() {
        defaults.register(defaults: [wordWrapKey: true, showStatusBarKey: true, syntaxHighlightingKey: true])
    }

    static var defaultFont: NSFont {
        .monospacedSystemFont(ofSize: 13, weight: .regular)
    }

    static var font: NSFont {
        get {
            guard let data = defaults.data(forKey: fontKey),
                  let font = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSFont.self, from: data)
            else { return defaultFont }
            return font
        }
        set {
            let data = try? NSKeyedArchiver.archivedData(withRootObject: newValue, requiringSecureCoding: true)
            defaults.set(data, forKey: fontKey)
            notify()
        }
    }

    static var wordWrap: Bool {
        get { defaults.bool(forKey: wordWrapKey) }
        set { defaults.set(newValue, forKey: wordWrapKey); notify() }
    }

    static var showStatusBar: Bool {
        get { defaults.bool(forKey: showStatusBarKey) }
        set { defaults.set(newValue, forKey: showStatusBarKey); notify() }
    }

    static var syntaxHighlighting: Bool {
        get { defaults.bool(forKey: syntaxHighlightingKey) }
        set { defaults.set(newValue, forKey: syntaxHighlightingKey); notify() }
    }

    private static func notify() {
        NotificationCenter.default.post(name: didChange, object: nil)
    }
}
