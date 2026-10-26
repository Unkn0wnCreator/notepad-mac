# Notepad für macOS

Der klassische Windows-Editor als echte Mac-App: eine native Portierung des
[ReactOS Notepad](https://github.com/reactos/reactos/tree/master/base/applications/notepad)
in Swift/AppKit. Schlicht, schnell, ohne Formatierung, mit Menüleiste im Fenster wie unter Windows.

- Universal-App (Apple Silicon + Intel), ab macOS 13
- Oberfläche auf Deutsch
- Keine Abhängigkeiten, kein Netzwerkzugriff, ca. 750 KB

## Installation

```sh
./build.sh
```

Danach `build/Notepad.app` nach `/Applications` ziehen. Benötigt werden nur die
Xcode Command Line Tools (`xcode-select --install`), kein vollständiges Xcode.

Die App ist nur lokal (ad hoc) signiert. Auf dem Mac, auf dem sie gebaut wurde, startet sie
normal. Auf einem anderen Mac beim ersten Start Rechtsklick → „Öffnen“ wählen.

## Funktionen

### Dateien

- **Kodierung wird erkannt** (BOM, UTF-8, UTF-16 LE/BE auch ohne BOM, ANSI/Windows-1252) und beim
  Speichern beibehalten. Ändern über *Format > Kodierung*.
- **Zeilenenden bleiben erhalten**: Windows (CRLF), Unix (LF), Mac klassisch (CR). Ändern über
  *Format > Zeilenende*. Neue Dateien: UTF-8 mit LF.
- **`.LOG`**: Beginnt eine Datei mit `.LOG`, wird bei jedem Öffnen Uhrzeit und Datum angehängt –
  praktisch als Tagebuch oder Protokoll.
- Öffnet jede Datei, auch ohne Endung. NUL-Zeichen werden wie bei Notepad als Leerzeichen angezeigt.
- Kann Text nicht in ANSI gespeichert werden (z. B. Emoji), erscheint ein Hinweis statt Datenverlust.

### Bearbeiten und Ansicht

- Suchen, Weitersuchen, Ersetzen (macOS-Suchleiste)
- Gehe zu Zeile, Uhrzeit/Datum einfügen
- Zeilenumbruch, Schriftauswahl, Zoom
- Statusleiste: Zeile/Spalte, Zoom, Zeilenende, Kodierung
- Drucken mit Dateiname als Kopfzeile und Seitenzahl als Fußzeile
- Dunkelmodus, Vollbild, macOS-Fenster-Tabs

Schrift, Zeilenumbruch und Statusleiste werden gespeichert und gelten für alle Fenster.
Wird das letzte Fenster geschlossen, beendet sich die App – wie unter Windows.

## Tastenkürzel

| Aktion | Kürzel |
|---|---|
| Neu / Öffnen / Sichern | ⌘N / ⌘O / ⌘S |
| Sichern unter | ⇧⌘S |
| Drucken / Papierformat | ⌘P / ⇧⌘P |
| Suchen / Ersetzen | ⌘F / ⌥⌘F |
| Weitersuchen / Vorheriges | ⌘G / ⇧⌘G |
| Gehe zu Zeile | ⌘L |
| Uhrzeit/Datum | F5 (ggf. fn+F5) |
| Schrift | ⌘T |
| Vergrößern / Verkleinern / Originalgröße | ⌘+ / ⌘- / ⌘0 |
| Widerrufen / Wiederholen | ⌘Z / ⇧⌘Z |

## Entwicklung

```sh
./build.sh   # baut build/Notepad.app
./test.sh    # 70 Tests: Datei-Logik und Oberfläche (öffnet kurz einige Fenster)
```

### Aufbau

| Datei | Inhalt | Vorbild in ReactOS |
|---|---|---|
| `Sources/TextCodec.swift` | Kodierung, Zeilenenden, Zeilenzählung | `text.c` |
| `Sources/TextDocument.swift` | Öffnen, Speichern, Drucken | `dialog.c`, `printing.c` |
| `Sources/EditorWindowController.swift` | Fenster, Editor, Menü- und Statusleiste | `main.c`, `dialog.c` |
| `Sources/AppDelegate.swift` | Menüs | `lang/de-DE.rc` |
| `Sources/Preferences.swift` | Einstellungen | `settings.c` |
| `Tools/make-icon.swift` | zeichnet das App-Icon beim Bauen | – |
| `Tests/` | automatische Tests | – |

## Unterschiede zum Original

- Mac-typische Kürzel (⌘ statt Strg) und Mac-Dialoge für Öffnen, Sichern, Schrift und Drucken.
- Suchen/Ersetzen nutzt die Suchleiste von macOS statt eigener Dialogfenster.
- Kopf- und Fußzeile beim Drucken sind fest (Dateiname, „Seite n“) und nicht einstellbar.
- „ANSI“ bedeutet immer Windows-1252 (westeuropäisch), unabhängig von der Systemsprache.
- Die Erkennung von UTF-16 ohne BOM ist eine vereinfachte Version von Windows' `IsTextUnicode`.
- Neu gegenüber ReactOS: Zoom, Dunkelmodus, Tabs, Kodierung und Zeilenende im Menü umstellbar.

## Lizenz

LGPL-2.1-or-later, wie das ReactOS Notepad, aus dem Logik und Funktionsumfang stammen
(siehe [`LICENSE`](LICENSE)). ReactOS Notepad: Copyright Marcel Baur, Mike McCormack,
Sylvain Petreolle, Andriy Palamarchuk, Katayama Hirofumi MZ und weitere.
