/*
 * Notepad für macOS – App und Menüleiste (entspricht MAIN_MENU in lang/de-DE.rc von ReactOS Notepad).
 * LICENSE: LGPL-2.1-or-later
 */

import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    /// Templates for the Windows-style menu bar inside each window.
    private var windowMenuTemplates: [(title: String, menu: NSMenu)] = []

    var windowMenuTitles: [String] { windowMenuTemplates.map(\.title) }

    /// Fresh copy of an in-window menu, so "Zuletzt benutzt" is up to date.
    func makeWindowMenu(at index: Int) -> NSMenu {
        let menu = windowMenuTemplates[index].menu.copy() as! NSMenu
        if index == 0 {
            menu.addItem(.separator())
            menu.addItem(item(L("Beenden"), #selector(NSApplication.terminate(_:)), "q"))
        }
        return menu
    }

    /// Started by the system at login: stay in the background without opening a window.
    private var launchedAsLoginItem = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        Preferences.registerDefaults()
        // One window per file, like Notepad: no automatic window tabs (and no tab items that AppKit
        // would otherwise add to the Window menu, even with "Prefer tabs: always" in the system).
        NSWindow.allowsAutomaticWindowTabbing = false
        NSApp.mainMenu = makeMainMenu()
        if let event = NSAppleEventManager.shared().currentAppleEvent,
           event.eventID == kAEOpenApplication,
           event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem {
            launchedAsLoginItem = true
        }
        updateAutomaticTermination()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async {
            self.launchedAsLoginItem = false
            EditorWindowController.prepareSpare()
        }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        !launchedAsLoginItem
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !Preferences.keepRunning
    }

    private var automaticTerminationDisabled = false

    /// Without this macOS may silently quit a windowless app to reclaim memory.
    private func updateAutomaticTermination() {
        if Preferences.keepRunning && !automaticTerminationDisabled {
            ProcessInfo.processInfo.disableAutomaticTermination("Notepad bleibt für schnelles Öffnen bereit")
            automaticTerminationDisabled = true
        } else if !Preferences.keepRunning && automaticTerminationDisabled {
            ProcessInfo.processInfo.enableAutomaticTermination("Notepad bleibt für schnelles Öffnen bereit")
            automaticTerminationDisabled = false
        }
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

    @objc func toggleKeepRunning(_ sender: Any?) {
        Preferences.keepRunning.toggle()
        updateAutomaticTermination()
    }

    @objc func toggleLaunchAtLogin(_ sender: Any?) {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = L("Der Start bei der Anmeldung konnte nicht geändert werden.")
            alert.runModal()
        }
        if service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    @objc func toggleDefaultEditor(_ sender: Any?) {
        DefaultEditor.runToggleDialog()
    }

    @objc func showAbout(_ sender: Any?) {
        let credits = NSAttributedString(
            string: L("Mac-Portierung des ReactOS Notepad.\nLizenz: LGPL-2.1-or-later"),
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
        case #selector(toggleKeepRunning(_:)):
            menuItem.state = Preferences.keepRunning ? .on : .off
        case #selector(toggleLaunchAtLogin(_:)):
            menuItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        default:
            break
        }
        return true
    }

    // MARK: - Menu

    /// Internal (not private) so the tests can build the menus in English, too.
    func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appMenu = submenu(in: mainMenu, "Notepad")
        appMenu.addItem(item(L("Über Notepad"), #selector(showAbout(_:))))
        appMenu.addItem(.separator())
        let services = item(L("Dienste"), nil)
        services.submenu = NSMenu(title: L("Dienste"))
        NSApp.servicesMenu = services.submenu
        appMenu.addItem(services)
        appMenu.addItem(.separator())
        appMenu.addItem(item(L("Notepad ausblenden"), #selector(NSApplication.hide(_:)), "h"))
        appMenu.addItem(item(L("Andere ausblenden"), #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        appMenu.addItem(item(L("Alle einblenden"), #selector(NSApplication.unhideAllApplications(_:))))
        appMenu.addItem(.separator())
        appMenu.addItem(item(L("Notepad beenden"), #selector(NSApplication.terminate(_:)), "q"))

        let fileMenu = submenu(in: mainMenu, L("Ablage"))
        fileMenu.addItem(item(L("Neu"), #selector(NSDocumentController.newDocument(_:)), "n"))
        fileMenu.addItem(item(L("Öffnen …"), #selector(NSDocumentController.openDocument(_:)), "o"))
        let recent = item(L("Zuletzt benutzt"), nil)
        let recentMenu = NSMenu(title: L("Zuletzt benutzt"))
        recentMenu.addItem(item(L("Einträge löschen"), #selector(NSDocumentController.clearRecentDocuments(_:))))
        let setMenuName = NSSelectorFromString("_setMenuName:")
        if recentMenu.responds(to: setMenuName) {
            recentMenu.perform(setMenuName, with: "NSRecentDocumentsMenu")
        }
        recent.submenu = recentMenu
        fileMenu.addItem(recent)
        fileMenu.addItem(.separator())
        fileMenu.addItem(item(L("Schließen"), #selector(NSWindow.performClose(_:)), "w"))
        fileMenu.addItem(item(L("Sichern"), #selector(NSDocument.save(_:)), "s"))
        fileMenu.addItem(item(L("Sichern unter …"), #selector(NSDocument.saveAs(_:)), "s", [.command, .shift]))
        fileMenu.addItem(item(L("Zurück zur letzten gesicherten Version"), #selector(NSDocument.revertToSaved(_:))))
        fileMenu.addItem(.separator())
        fileMenu.addItem(item(L("Papierformat …"), #selector(NSDocument.runPageLayout(_:)), "p", [.command, .shift]))
        fileMenu.addItem(item(L("Drucken …"), #selector(NSDocument.printDocument(_:)), "p"))

        let editMenu = submenu(in: mainMenu, L("Bearbeiten"))
        editMenu.addItem(item(L("Widerrufen"), Selector(("undo:")), "z"))
        editMenu.addItem(item(L("Wiederholen"), Selector(("redo:")), "z", [.command, .shift]))
        editMenu.addItem(.separator())
        editMenu.addItem(item(L("Ausschneiden"), #selector(NSText.cut(_:)), "x"))
        editMenu.addItem(item(L("Kopieren"), #selector(NSText.copy(_:)), "c"))
        editMenu.addItem(item(L("Einsetzen"), #selector(NSText.paste(_:)), "v"))
        editMenu.addItem(item(L("Löschen"), #selector(NSText.delete(_:))))
        editMenu.addItem(.separator())
        let find = #selector(NSResponder.performTextFinderAction(_:))
        editMenu.addItem(item(L("Suchen …"), find, "f", tag: NSTextFinder.Action.showFindInterface.rawValue))
        editMenu.addItem(item(L("Weitersuchen"), find, "g", tag: NSTextFinder.Action.nextMatch.rawValue))
        editMenu.addItem(item(L("Vorheriges suchen"), find, "g", [.command, .shift], tag: NSTextFinder.Action.previousMatch.rawValue))
        editMenu.addItem(item(L("Ersetzen …"), find, "f", [.command, .option], tag: NSTextFinder.Action.showReplaceInterface.rawValue))
        editMenu.addItem(item(L("Auswahl für Suche verwenden"), find, "e", tag: NSTextFinder.Action.setSearchString.rawValue))
        editMenu.addItem(item(L("Gehe zu Zeile …"), #selector(EditorWindowController.goToLine(_:)), "l"))
        editMenu.addItem(.separator())
        editMenu.addItem(item(L("Alles auswählen"), #selector(NSText.selectAll(_:)), "a"))
        let f5 = String(Character(UnicodeScalar(NSF5FunctionKey)!))
        editMenu.addItem(item(L("Uhrzeit/Datum"), #selector(EditorWindowController.insertTimeDate(_:)), f5, []))

        let formatMenu = submenu(in: mainMenu, "Format")
        formatMenu.addItem(item(L("Zeilenumbruch"), #selector(toggleWordWrap(_:))))
        formatMenu.addItem(item(L("Schrift …"), #selector(EditorWindowController.showFonts(_:)), "t"))
        formatMenu.addItem(.separator())
        let encodingItem = item(L("Kodierung"), nil)
        encodingItem.submenu = NSMenu(title: L("Kodierung"))
        for encoding in TextEncoding.allCases {
            encodingItem.submenu!.addItem(item(encoding.displayName, #selector(TextDocument.changeTextEncoding(_:)), tag: encoding.rawValue))
        }
        formatMenu.addItem(encodingItem)
        let lineEndingItem = item(L("Zeilenende"), nil)
        lineEndingItem.submenu = NSMenu(title: L("Zeilenende"))
        for lineEnding in LineEnding.allCases {
            lineEndingItem.submenu!.addItem(item(lineEnding.displayName, #selector(TextDocument.changeLineEnding(_:)), tag: lineEnding.rawValue))
        }
        formatMenu.addItem(lineEndingItem)
        let languageItem = item(L("Sprache"), nil)
        let languageMenu = NSMenu(title: L("Sprache"))
        languageMenu.addItem(item(L("Automatisch (nach Dateiendung)"), #selector(TextDocument.changeSyntaxLanguage(_:)), tag: 0))
        languageMenu.addItem(item(L("Nur Text"), #selector(TextDocument.changeSyntaxLanguage(_:)), tag: 1))
        languageMenu.addItem(.separator())
        for (index, language) in SyntaxLanguage.all.enumerated() {
            languageMenu.addItem(item(L(language.name), #selector(TextDocument.changeSyntaxLanguage(_:)), tag: index + 2))
        }
        languageItem.submenu = languageMenu
        formatMenu.addItem(languageItem)

        let viewMenu = submenu(in: mainMenu, L("Darstellung"))
        viewMenu.addItem(item(L("Statusleiste"), #selector(toggleStatusBar(_:))))
        viewMenu.addItem(item(L("Syntaxhervorhebung"), #selector(toggleSyntaxHighlighting(_:))))
        viewMenu.addItem(.separator())
        viewMenu.addItem(item(L("Vergrößern"), #selector(EditorWindowController.zoomIn(_:)), "+"))
        viewMenu.addItem(item(L("Verkleinern"), #selector(EditorWindowController.zoomOut(_:)), "-"))
        viewMenu.addItem(item(L("Originalgröße"), #selector(EditorWindowController.resetZoom(_:)), "0"))
        viewMenu.addItem(.separator())
        viewMenu.addItem(item(L("Vollbild"), #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]))

        let windowMenu = submenu(in: mainMenu, L("Fenster"))
        windowMenu.addItem(item(L("Im Dock ablegen"), #selector(NSWindow.performMiniaturize(_:)), "m"))
        windowMenu.addItem(item(L("Zoomen"), #selector(NSWindow.performZoom(_:))))
        windowMenu.addItem(.separator())
        windowMenu.addItem(item(L("Alle nach vorne bringen"), #selector(NSApplication.arrangeInFront(_:))))
        NSApp.windowsMenu = windowMenu

        let helpMenu = submenu(in: mainMenu, L("Hilfe"))
        helpMenu.addItem(item(L("Notepad als Standard-Texteditor verwenden"), #selector(toggleDefaultEditor(_:))))
        helpMenu.addItem(item(L("Im Hintergrund bereithalten (schneller Start)"), #selector(toggleKeepRunning(_:))))
        helpMenu.addItem(item(L("Bei der Anmeldung starten"), #selector(toggleLaunchAtLogin(_:))))
        helpMenu.addItem(.separator())
        helpMenu.addItem(item(L("Über Notepad"), #selector(showAbout(_:))))
        NSApp.helpMenu = helpMenu

        windowMenuTemplates = [
            (L("Datei"), fileMenu),
            (L("Bearbeiten"), editMenu),
            ("Format", formatMenu),
            (L("Ansicht"), viewMenu),
            (L("Hilfe"), helpMenu),
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
