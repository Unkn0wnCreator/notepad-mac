/*
 * Notepad für macOS – App und Menüleiste (entspricht MAIN_MENU in lang/de-DE.rc von ReactOS Notepad).
 * LICENSE: LGPL-2.1-or-later
 */

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    /// Templates for the Windows-style menu bar inside each window.
    private var windowMenuTemplates: [(title: String, menu: NSMenu)] = []

    var windowMenuTitles: [String] { windowMenuTemplates.map(\.title) }

    /// Fresh copy of an in-window menu, so "Zuletzt benutzt" is up to date.
    func makeWindowMenu(at index: Int) -> NSMenu {
        let menu = windowMenuTemplates[index].menu.copy() as! NSMenu
        if index == 0 {
            menu.addItem(.separator())
            menu.addItem(item("Beenden", #selector(NSApplication.terminate(_:)), "q"))
        }
        return menu
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        Preferences.registerDefaults()
        NSApp.mainMenu = makeMainMenu()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // MARK: - Global actions

    @objc func toggleWordWrap(_ sender: Any?) {
        Preferences.wordWrap.toggle()
    }

    @objc func toggleStatusBar(_ sender: Any?) {
        Preferences.showStatusBar.toggle()
    }

    @objc func toggleSyntaxHighlighting(_ sender: Any?) {
        Preferences.syntaxHighlighting.toggle()
    }

    @objc func toggleDefaultEditor(_ sender: Any?) {
        DefaultEditor.runToggleDialog()
    }

    @objc func showAbout(_ sender: Any?) {
        let credits = NSAttributedString(
            string: "Mac-Portierung des ReactOS Notepad.\nLizenz: LGPL-2.1-or-later",
            attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                         .foregroundColor: NSColor.labelColor])
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(toggleWordWrap(_:)):
            menuItem.state = Preferences.wordWrap ? .on : .off
        case #selector(toggleStatusBar(_:)):
            menuItem.state = Preferences.showStatusBar ? .on : .off
        case #selector(toggleSyntaxHighlighting(_:)):
            menuItem.state = Preferences.syntaxHighlighting ? .on : .off
        case #selector(toggleDefaultEditor(_:)):
            menuItem.state = DefaultEditor.isDefault ? .on : .off
        default:
            break
        }
        return true
    }

    // MARK: - Menu

    private func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appMenu = submenu(in: mainMenu, "Notepad")
        appMenu.addItem(item("Über Notepad", #selector(showAbout(_:))))
        appMenu.addItem(.separator())
        let services = item("Dienste", nil)
        services.submenu = NSMenu(title: "Dienste")
        NSApp.servicesMenu = services.submenu
        appMenu.addItem(services)
        appMenu.addItem(.separator())
        appMenu.addItem(item("Notepad ausblenden", #selector(NSApplication.hide(_:)), "h"))
        appMenu.addItem(item("Andere ausblenden", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        appMenu.addItem(item("Alle einblenden", #selector(NSApplication.unhideAllApplications(_:))))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Notepad beenden", #selector(NSApplication.terminate(_:)), "q"))

        let fileMenu = submenu(in: mainMenu, "Ablage")
        fileMenu.addItem(item("Neu", #selector(NSDocumentController.newDocument(_:)), "n"))
        fileMenu.addItem(item("Öffnen …", #selector(NSDocumentController.openDocument(_:)), "o"))
        let recent = item("Zuletzt benutzt", nil)
        let recentMenu = NSMenu(title: "Zuletzt benutzt")
        recentMenu.addItem(item("Einträge löschen", #selector(NSDocumentController.clearRecentDocuments(_:))))
        let setMenuName = NSSelectorFromString("_setMenuName:")
        if recentMenu.responds(to: setMenuName) {
            recentMenu.perform(setMenuName, with: "NSRecentDocumentsMenu")
        }
        recent.submenu = recentMenu
        fileMenu.addItem(recent)
        fileMenu.addItem(.separator())
        fileMenu.addItem(item("Schließen", #selector(NSWindow.performClose(_:)), "w"))
        fileMenu.addItem(item("Sichern", #selector(NSDocument.save(_:)), "s"))
        fileMenu.addItem(item("Sichern unter …", #selector(NSDocument.saveAs(_:)), "s", [.command, .shift]))
        fileMenu.addItem(item("Zurück zur letzten gesicherten Version", #selector(NSDocument.revertToSaved(_:))))
        fileMenu.addItem(.separator())
        fileMenu.addItem(item("Papierformat …", #selector(NSDocument.runPageLayout(_:)), "p", [.command, .shift]))
        fileMenu.addItem(item("Drucken …", #selector(NSDocument.printDocument(_:)), "p"))

        let editMenu = submenu(in: mainMenu, "Bearbeiten")
        editMenu.addItem(item("Widerrufen", Selector(("undo:")), "z"))
        editMenu.addItem(item("Wiederholen", Selector(("redo:")), "z", [.command, .shift]))
        editMenu.addItem(.separator())
        editMenu.addItem(item("Ausschneiden", #selector(NSText.cut(_:)), "x"))
        editMenu.addItem(item("Kopieren", #selector(NSText.copy(_:)), "c"))
        editMenu.addItem(item("Einsetzen", #selector(NSText.paste(_:)), "v"))
        editMenu.addItem(item("Löschen", #selector(NSText.delete(_:))))
        editMenu.addItem(.separator())
        let find = #selector(NSResponder.performTextFinderAction(_:))
        editMenu.addItem(item("Suchen …", find, "f", tag: NSTextFinder.Action.showFindInterface.rawValue))
        editMenu.addItem(item("Weitersuchen", find, "g", tag: NSTextFinder.Action.nextMatch.rawValue))
        editMenu.addItem(item("Vorheriges suchen", find, "g", [.command, .shift], tag: NSTextFinder.Action.previousMatch.rawValue))
        editMenu.addItem(item("Ersetzen …", find, "f", [.command, .option], tag: NSTextFinder.Action.showReplaceInterface.rawValue))
        editMenu.addItem(item("Auswahl für Suche verwenden", find, "e", tag: NSTextFinder.Action.setSearchString.rawValue))
        editMenu.addItem(item("Gehe zu Zeile …", #selector(EditorWindowController.goToLine(_:)), "l"))
        editMenu.addItem(.separator())
        editMenu.addItem(item("Alles auswählen", #selector(NSText.selectAll(_:)), "a"))
        let f5 = String(Character(UnicodeScalar(NSF5FunctionKey)!))
        editMenu.addItem(item("Uhrzeit/Datum", #selector(EditorWindowController.insertTimeDate(_:)), f5, []))

        let formatMenu = submenu(in: mainMenu, "Format")
        formatMenu.addItem(item("Zeilenumbruch", #selector(toggleWordWrap(_:))))
        formatMenu.addItem(item("Schrift …", #selector(EditorWindowController.showFonts(_:)), "t"))
        formatMenu.addItem(.separator())
        let encodingItem = item("Kodierung", nil)
        encodingItem.submenu = NSMenu(title: "Kodierung")
        for encoding in TextEncoding.allCases {
            encodingItem.submenu!.addItem(item(encoding.displayName, #selector(TextDocument.changeTextEncoding(_:)), tag: encoding.rawValue))
        }
        formatMenu.addItem(encodingItem)
        let lineEndingItem = item("Zeilenende", nil)
        lineEndingItem.submenu = NSMenu(title: "Zeilenende")
        for lineEnding in LineEnding.allCases {
            lineEndingItem.submenu!.addItem(item(lineEnding.displayName, #selector(TextDocument.changeLineEnding(_:)), tag: lineEnding.rawValue))
        }
        formatMenu.addItem(lineEndingItem)
        let languageItem = item("Sprache", nil)
        let languageMenu = NSMenu(title: "Sprache")
        languageMenu.addItem(item("Automatisch (nach Dateiendung)", #selector(TextDocument.changeSyntaxLanguage(_:)), tag: 0))
        languageMenu.addItem(item("Nur Text", #selector(TextDocument.changeSyntaxLanguage(_:)), tag: 1))
        languageMenu.addItem(.separator())
        for (index, language) in SyntaxLanguage.all.enumerated() {
            languageMenu.addItem(item(language.name, #selector(TextDocument.changeSyntaxLanguage(_:)), tag: index + 2))
        }
        languageItem.submenu = languageMenu
        formatMenu.addItem(languageItem)

        let viewMenu = submenu(in: mainMenu, "Darstellung")
        viewMenu.addItem(item("Statusleiste", #selector(toggleStatusBar(_:))))
        viewMenu.addItem(item("Syntaxhervorhebung", #selector(toggleSyntaxHighlighting(_:))))
        viewMenu.addItem(.separator())
        viewMenu.addItem(item("Vergrößern", #selector(EditorWindowController.zoomIn(_:)), "+"))
        viewMenu.addItem(item("Verkleinern", #selector(EditorWindowController.zoomOut(_:)), "-"))
        viewMenu.addItem(item("Originalgröße", #selector(EditorWindowController.resetZoom(_:)), "0"))
        viewMenu.addItem(.separator())
        viewMenu.addItem(item("Vollbild", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]))

        let windowMenu = submenu(in: mainMenu, "Fenster")
        windowMenu.addItem(item("Im Dock ablegen", #selector(NSWindow.performMiniaturize(_:)), "m"))
        windowMenu.addItem(item("Zoomen", #selector(NSWindow.performZoom(_:))))
        windowMenu.addItem(.separator())
        windowMenu.addItem(item("Alle nach vorne bringen", #selector(NSApplication.arrangeInFront(_:))))
        NSApp.windowsMenu = windowMenu

        let helpMenu = submenu(in: mainMenu, "Hilfe")
        helpMenu.addItem(item("Notepad als Standard-Texteditor verwenden", #selector(toggleDefaultEditor(_:))))
        helpMenu.addItem(.separator())
        helpMenu.addItem(item("Über Notepad", #selector(showAbout(_:))))
        NSApp.helpMenu = helpMenu

        windowMenuTemplates = [
            ("Datei", fileMenu),
            ("Bearbeiten", editMenu),
            ("Format", formatMenu),
            ("Ansicht", viewMenu),
            ("Hilfe", helpMenu),
        ]

        return mainMenu
    }

    private func submenu(in mainMenu: NSMenu, _ title: String) -> NSMenu {
        let menu = NSMenu(title: title)
        let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        holder.submenu = menu
        mainMenu.addItem(holder)
        return menu
    }

    private func item(_ title: String, _ action: Selector?, _ key: String = "",
                      _ modifiers: NSEvent.ModifierFlags = [.command], tag: Int = 0) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
        item.tag = tag
        return item
    }
}
