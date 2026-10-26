# Notepad für macOS

Der klassische Windows-Editor als echte Mac-App: eine native Portierung des
[ReactOS Notepad](https://github.com/reactos/reactos/tree/master/base/applications/notepad)
in Swift/AppKit. Schlicht, schnell, mit Menüleiste im Fenster wie unter Windows und
Syntaxhervorhebung für gängige Sprachen.

- Universal-App (Apple Silicon + Intel), ab macOS 13
- Oberfläche auf Deutsch
- Keine Abhängigkeiten, kein Netzwerkzugriff, ca. 1 MB

## Installation

```sh
./build.sh
```

Danach `build/Notepad.app` nach `/Applications` ziehen. Benötigt werden nur die
Xcode Command Line Tools (`xcode-select --install`), kein vollständiges Xcode.

Die App ist nur lokal (ad hoc) signiert. Auf dem Mac, auf dem sie gebaut wurde, startet sie
normal. Auf einem anderen Mac beim ersten Start Rechtsklick → „Öffnen“ wählen.

### Als Standard-Texteditor statt TextEdit

*Hilfe > Notepad als Standard-Texteditor verwenden* öffnet danach Textdateien, Code und Skripte,
JSON, XML, YAML, Markdown, CSV und Logdateien per Doppelklick mit Notepad. HTML und RTF bleiben
bei ihren bisherigen Apps. Notepad merkt sich die vorherigen Apps; ein erneuter Klick auf den
(dann abgehakten) Menüpunkt stellt sie wieder her. Am besten Notepad vorher nach `/Applications`
legen, damit die Zuordnung nicht auf den Build-Ordner zeigt.

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

### Syntaxhervorhebung

Swift, C/C++/Objective-C, Java, Kotlin, C#, Go, Rust, JavaScript/TypeScript, Python, Shell,
Batch, HTML, XML, CSS, JSON, Markdown, YAML, INI/TOML, SQL, Makefile und Dockerfile.

- Die Sprache wird an Dateiendung, Dateiname (`Makefile`, `.zshrc` …), Shebang-Zeile
  (`#!/bin/bash`) oder XML-/HTML-Kopf erkannt und in der Statusleiste angezeigt.
- Manuell wählen über *Format > Sprache*, ganz abschalten über *Ansicht > Syntaxhervorhebung*.
- Die Farben gibt es nur in der Anzeige – gespeichert wird immer reiner Text.
- Dateien über 5 MB bleiben ungefärbt.

### Bearbeiten und Ansicht

- Suchen, Weitersuchen, Ersetzen (macOS-Suchleiste)
- Gehe zu Zeile, Uhrzeit/Datum einfügen
- Zeilenumbruch, Schriftauswahl, Zoom
- Statusleiste: Zeile/Spalte, Zoom, Sprache, Zeilenende, Kodierung
- Drucken mit Dateiname als Kopfzeile und Seitenzahl als Fußzeile
- Dunkelmodus, Vollbild, macOS-Fenster-Tabs

Schrift, Zeilenumbruch, Statusleiste und Syntaxhervorhebung werden gespeichert und gelten für alle
Fenster. Wird das letzte Fenster geschlossen, beendet sich die App – wie unter Windows.

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

## Leistung

Gemessen auf Apple Silicon (Release-Build):

| | Zeit |
|---|---|
| Start bis Fenster sichtbar (`open`, inkl. macOS-Anteil) | ca. 0,3 s (TextEdit: ca. 0,9 s) |
| davon eigener Code (Menüs, Sprachen, Fenster) | ca. 20 ms |
| 10 MB Text öffnen / speichern | ca. 0,15 s / 0,2 s |
| Tastendruck in 50 MB Datei | < 1 ms |
| Tastendruck in 1 GB Datei, auch am Anfang (nach dem ersten an dieser Stelle) | ca. 1 ms (vorher bis 500 ms) |
| Speicher für 1 GB ASCII- oder Latin-1-Text | ca. 1 GB (vorher 1,4–2,9 GB) |
| Längste Blockierung beim Einfärben von 1–3 MB Code | ca. 15 ms |

Wie das erreicht wird: Die Datei wird im Hintergrund in Tokens zerlegt, eingefärbt wird nur der
sichtbare Bereich (plus Puffer) und beim Scrollen der Rest. Die Statusleiste zählt Zeilen ab der
letzten bekannten Cursorposition statt jedes Mal ab Dateianfang. Der Text liegt in einem
Lückenpuffer (Gap Buffer): Eingaben verschieben nicht mehr den ganzen Rest der Datei, und Text aus
Latin-1-Zeichen braucht nur ein Byte pro Zeichen.

## Entwicklung

```sh
./build.sh   # baut build/Notepad.app
./test.sh    # 136 Tests: Datei-Logik, Zeilenzählung, Syntax, Oberfläche (öffnet kurz Fenster)
```

### Aufbau

| Datei | Inhalt | Vorbild in ReactOS |
|---|---|---|
| `Sources/TextCodec.swift` | Kodierung, Zeilenenden, Zeilenzählung | `text.c` |
| `Sources/TextDocument.swift` | Öffnen, Speichern, Drucken, Kodierung/Sprache je Dokument | `dialog.c`, `printing.c` |
| `Sources/EditorWindowController.swift` | Fenster, Editor, Menü- und Statusleiste | `main.c`, `dialog.c` |
| `Sources/SyntaxHighlighter.swift` | Sprachen, Erkennung, Einfärben | – |
| `Sources/DefaultEditor.swift` | Standard-Texteditor festlegen/zurückstellen | – |
| `Sources/AppDelegate.swift` | Menüs | `lang/de-DE.rc` |
| `Sources/Preferences.swift` | Einstellungen | `settings.c` |
| `Tools/make-icon.swift` | zeichnet das App-Icon beim Bauen | – |
| `Tests/` | automatische Tests | – |

Hinweise für Entwickler (und Claude Code) stehen in [`CLAUDE.md`](CLAUDE.md),
Änderungen in [`CHANGELOG.md`](CHANGELOG.md).

## Unterschiede zum Original

- Mac-typische Kürzel (⌘ statt Strg) und Mac-Dialoge für Öffnen, Sichern, Schrift und Drucken.
- Suchen/Ersetzen nutzt die Suchleiste von macOS statt eigener Dialogfenster.
- Kopf- und Fußzeile beim Drucken sind fest (Dateiname, „Seite n“) und nicht einstellbar.
- „ANSI“ bedeutet immer Windows-1252 (westeuropäisch), unabhängig von der Systemsprache.
- Die Erkennung von UTF-16 ohne BOM ist eine vereinfachte Version von Windows' `IsTextUnicode`.
- Neu gegenüber ReactOS: Syntaxhervorhebung, Zoom, Dunkelmodus, Tabs, Kodierung und Zeilenende im
  Menü umstellbar, Standard-Editor-Umschaltung.

## Lizenz

LGPL-2.1-or-later, wie das ReactOS Notepad, aus dem Logik und Funktionsumfang stammen
(siehe [`LICENSE`](LICENSE)). ReactOS Notepad: Copyright Marcel Baur, Mike McCormack,
Sylvain Petreolle, Andriy Palamarchuk, Katayama Hirofumi MZ und weitere.
