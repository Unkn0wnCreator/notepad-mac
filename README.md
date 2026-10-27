# Notepad für macOS

Der klassische Windows-Editor als echte Mac-App: eine native Portierung des
[ReactOS Notepad](https://github.com/reactos/reactos/tree/master/base/applications/notepad)
in Swift/AppKit (plus etwas Objective-C für den Textspeicher). Schlicht, auf Geschwindigkeit
getrimmt, mit Menüleiste im Fenster wie unter Windows und Syntaxhervorhebung für Code und
Konfigurationsdateien.

- Universal-App (Apple Silicon + Intel), ab macOS 13, Oberfläche auf Deutsch
- Keine Abhängigkeiten, kein Netzwerkzugriff, ca. 1,5 MB
- Öffnet auch Gigabyte-Dateien und bleibt dabei flüssig (siehe [Leistung](#leistung))

> **Mit KI gebaut („vibe-coded“):** Code, Tests und Dokumentation hat
> [Claude Code](https://claude.com/claude-code) (KI von Anthropic) geschrieben, nach Vorgaben und
> Rückmeldungen eines Menschen. Abgesichert ist das durch über 550 automatische Tests und
> Leistungsgrenzen (siehe [Entwicklung](#entwicklung)), nicht durch ein Code-Review jeder Zeile.
> Nutzung auf eigene Verantwortung, wie bei jeder Software ohne Gewähr (siehe [Lizenz](#lizenz)).

## Installation

```sh
./build.sh
```

Danach `build/Notepad.app` nach `/Applications` ziehen. Benötigt werden nur die
Xcode Command Line Tools (`xcode-select --install`), kein vollständiges Xcode.

Die App ist nur lokal (ad hoc) signiert. Auf dem Mac, auf dem sie gebaut wurde, startet sie
normal. Auf einem anderen Mac beim ersten Start Rechtsklick → „Öffnen“ wählen (ab macOS 15:
*Systemeinstellungen > Datenschutz & Sicherheit > Trotzdem öffnen*).

### Fertiger Build aus der CI

Fertige Builds gibt es auf GitHub: unter
[Releases](https://github.com/Unkn0wnCreator/notepad-mac/releases) zu jeder Version (auf einem Mac
gebaut und mit allen Tests geprüft, Prüfsummen in `SHA256SUMS.txt`), und als
ZIP-Artefakt an jedem Lauf unter [Actions](https://github.com/Unkn0wnCreator/notepad-mac/actions)
(nur angemeldet abrufbar). Weil die App nur ad hoc signiert ist, gilt beim ersten Start dasselbe
wie oben; alternativ die Quarantäne entfernen: `xattr -dr com.apple.quarantine /Applications/Notepad.app`.

### Als Standard-Texteditor statt TextEdit

*Hilfe > Notepad als Standard-Texteditor verwenden*. macOS lässt eine App das nicht für alle
Dateitypen auf einmal festlegen, sondern fragt für jeden Typ einzeln nach. Beim ersten Mal muss man
also mehrmals bestätigen (bis zu ca. 30-mal, einmal pro Dateityp). Danach öffnen sich
Textdateien, Code und Skripte, JSON, XML, YAML, Markdown, CSV und Logdateien per Doppelklick mit
Notepad. HTML und RTF bleiben bei ihren bisherigen Apps. Notepad merkt sich die vorherigen Apps;
ein erneuter Klick auf den (dann abgehakten) Menüpunkt stellt sie wieder her (auch dabei fragt
macOS pro Typ nach). Am besten Notepad vorher nach `/Applications` legen.

### Schnell bereit

- *Hilfe > Im Hintergrund bereithalten* (Standard: an): Notepad läuft nach dem letzten Fenster
  weiter und hält ein Fenster vorbereitet. Eine Datei öffnet sich dann in ca. 0,1 s statt ca. 0,4 s.
- *Hilfe > Bei der Anmeldung starten*: startet Notepad beim Anmelden ohne Fenster, damit schon das
  erste Öffnen schnell ist. macOS fragt beim ersten Mal ggf. in den Systemeinstellungen nach.

## Funktionen

### Dateien

- **Kodierung wird erkannt** (BOM, UTF-8, UTF-16 LE/BE auch ohne BOM, ANSI/Windows-1252) und beim
  Speichern beibehalten. Ändern über *Format > Kodierung*.
- **Zeilenenden bleiben erhalten**: Windows (CRLF), Unix (LF), Mac klassisch (CR). Ändern über
  *Format > Zeilenende*. Neue Dateien: UTF-8 mit LF.
- **`.LOG`**: Beginnt eine Datei mit `.LOG`, wird bei jedem Öffnen Uhrzeit und Datum angehängt.
- **Drag & drop**: Dateien ins Fenster ziehen. Ist das Fenster leer und unverändert, lädt die Datei
  dort; sonst öffnet sie sich in einem neuen Fenster. Mehrere Dateien auf einmal gehen auch.
- Öffnet jede Datei, auch ohne Endung. NUL-Zeichen werden wie bei Notepad als Leerzeichen angezeigt.
- Kann Text nicht in ANSI gespeichert werden (z. B. Emoji), erscheint ein Hinweis statt Datenverlust.

### Syntaxhervorhebung

- **Programmiersprachen** (eigener, schneller Lexer): Swift, C/C++/Objective-C, Java, Kotlin, C#,
  Go, Rust, JavaScript/TypeScript, Python, Shell.
- **Weitere Formate**: Batch, HTML, XML, CSS, JSON, Markdown, YAML, INI, SQL, Makefile, Dockerfile.
- **Konfigurationsdateien**: TOML, Caddyfile, nginx, Apache (`.htaccess`, `httpd.conf`),
  systemd-Units, Terraform/HCL, `.env`, SSH-Konfiguration, Ignore-Dateien (`.gitignore` …).

Die Sprache wird an Dateiendung und Dateiname erkannt (`Makefile`, `Caddyfile`, `.zshrc`,
`~/.ssh/config`, `Dockerfile.dev` …), an der Shebang-Zeile (`#!/bin/bash`) oder am Inhalt –
eine `.conf` wird z. B. als nginx, Apache oder INI erkannt. Sie steht in der Statusleiste; manuell
wählen über *Format > Sprache*, ganz abschalten über *Ansicht > Syntaxhervorhebung*. Die Farben gibt
es nur in der Anzeige – gespeichert wird immer reiner Text. Dateien über 50 MB bleiben ungefärbt.

### Bearbeiten und Ansicht

- Suchen, Weitersuchen, Ersetzen (macOS-Suchleiste), Gehe zu Zeile, Uhrzeit/Datum einfügen
- Zeilenumbruch, Schriftauswahl, Zoom
- Statusleiste: Zeile/Spalte, Zoom, Sprache, Zeilenende, Kodierung
- Menüleiste im Fenster wie unter Windows: Ist ein Menü offen, wechselt es beim Überfahren eines
  anderen Titels mit der Maus.
- Drucken mit Dateiname als Kopfzeile und Seitenzahl als Fußzeile
- Dunkelmodus, Vollbild

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

Gemessen auf Apple Silicon mit dem Release-Build (`-O`):

| | Zeit |
|---|---|
| Datei öffnen, App läuft schon (inkl. ca. 65 ms für `open`/macOS) | ca. 0,1 s |
| Datei öffnen mit App-Start | ca. 0,4 s (TextEdit: ca. 0,9 s) |
| 50 MB lesen + dekodieren / Fenster / speichern | 27 ms / 28 ms / 18 ms |
| Tastendruck in 50 MB, egal wo (auch ohne Zeilenumbruch) | ca. 0,5 ms |
| Sprung in die Mitte von 50 MB / 200 MB / 1 GB | 25 ms / 85 ms / 0,43 s |
| 1 GB öffnen (Datei im Cache / frisch von der SSD) | ca. 0,5 s / ca. 2 s |
| Tastendruck in 1 GB, egal wo | ca. 0,5 ms |
| Speicher für 1 GB Text (ASCII/Umlaute) | ca. 1 GB (vorher ca. 3 GB) |
| Hervorhebung: 3 MB Swift komplett / neu nach Änderung | 16 ms / ca. 40 ms |

Wie das erreicht wird:

- **Textspeicher in Objective-C** (`PlainTextStorage`) mit **Lückenpuffer** (Gap Buffer):
  Einfügen kostet nur am Cursor etwas, statt den Rest der Datei zu verschieben. Text aus
  Latin-1-Zeichen (ASCII, Umlaute) braucht ein Byte pro Zeichen. Attribute werden erst bei Bedarf
  ergänzt, so muss für einen Sprung nicht der ganze Text davor gesetzt werden.
- **SIMD-UTF-8-Dekoder** (`FastUTF`): prüft, wandelt und normalisiert Zeilenenden in einem
  Durchgang (ca. 2–4 GB/s statt ca. 0,3 GB/s mit Foundation); Latin-1-Text landet ohne weitere
  Kopie direkt im Lückenpuffer. Speichern ebenso in einem Durchgang.
- **Hervorhebung im Hintergrund**: Programmiersprachen mit handgeschriebenem Lexer (20–90× schneller
  als reguläre Ausdrücke), übrige Formate mit optimierten Regex-Gruppen. Nach einer Änderung wird
  nur der betroffene Bereich neu analysiert; eingefärbt wird nur, was sichtbar ist.
- **Statusleiste** zählt Zeilen ab der letzten Cursorposition statt ab Dateianfang.
- **Ohne Zeilenumbruch** wächst die Breite nur mit tatsächlich gesetzten Zeilen, statt bei jedem
  Tastendruck die ganze Datei zu vermessen.
- **Bereithalten**: App bleibt aktiv, ein Fenster wird im Leerlauf vorbereitet.

Grenzen: Der ganze Text liegt im Arbeitsspeicher (ca. 1–2 Byte pro Zeichen). Für Dateien mit vielen
Gigabyte wäre ein eigener Großdatei-Modus (Datei per mmap, nur sichtbare Zeilen) nötig.

## Entwicklung

```sh
./build.sh   # baut build/Notepad.app
./test.sh    # über 550 Tests inkl. Leistungstests (öffnet kurz Fenster)
NOTEPAD_BIG_BENCH=1 ./test.sh   # zusätzlich Textspeicher-Benchmark mit 1 GB
NOTEPAD_SKIP_PERF=1 ./test.sh   # ohne Leistungstests und Benchmarks (so läuft die GitHub-CI)
```

`./test.sh` misst bei jedem Lauf u. a. Öffnen, Tastendruck, Sprung und Speichern mit 50 MB sowie
die Hervorhebung und schlägt fehl, wenn etwas langsamer wird als die festgelegten Grenzen.
Die CI führt bei jedem Push den Clang Static Analyzer für den Objective-C-Teil, `./test.sh` und
`./build.sh` auf einem Mac aus ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)), dort ohne
Leistungstests: Die geteilten GitHub-Runner sind von Lauf zu Lauf unterschiedlich schnell. Dazu
kommen CodeQL für die Swift-Quellen und die Workflows (`main` und wöchentlich), Secret Scanning und Dependabot für die
Versionen der verwendeten Actions.

### Aufbau

| Datei | Inhalt | Vorbild in ReactOS |
|---|---|---|
| `Sources/TextCodec.swift` | Kodierung, Zeilenenden, Zeilenzählung | `text.c` |
| `Sources/FastUTF.swift` | SIMD-UTF-8-Dekoder/-Encoder | – |
| `Sources/PlainTextStorage.h/.m` | Lückenpuffer und Textspeicher (Objective-C) | – |
| `Sources/TextDocument.swift` | Öffnen, Speichern, Drucken, Drag & drop | `dialog.c`, `printing.c` |
| `Sources/EditorWindowController.swift` | Fenster, Editor, Menü- und Statusleiste | `main.c`, `dialog.c` |
| `Sources/SyntaxHighlighter.swift` | Sprachen, Erkennung, inkrementelles Einfärben | – |
| `Sources/Lexer.swift` | handgeschriebener Lexer für Programmiersprachen | – |
| `Sources/RegexRules.swift` | Regex-Regeln mit möglichst wenigen Gruppen | – |
| `Sources/ConfigLanguages.swift` | Konfigurationsformate und Erkennung am Inhalt | – |
| `Sources/DefaultEditor.swift` | Standard-Texteditor festlegen/zurückstellen | – |
| `Sources/AppDelegate.swift` | Menüs, Hintergrundbetrieb, Anmeldestart | `lang/de-DE.rc` |
| `Sources/Preferences.swift` | Einstellungen | `settings.c` |
| `Tools/make-icon.swift` | zeichnet das App-Icon beim Bauen | – |
| `Tests/` | automatische Tests und Benchmarks | – |

Hinweise für Entwickler (und Claude Code) stehen in [`CLAUDE.md`](CLAUDE.md),
Änderungen in [`CHANGELOG.md`](CHANGELOG.md).

## Unterschiede zum Original

- Mac-typische Kürzel (⌘ statt Strg) und Mac-Dialoge für Öffnen, Sichern, Schrift und Drucken.
- Suchen/Ersetzen nutzt die Suchleiste von macOS statt eigener Dialogfenster.
- Kopf- und Fußzeile beim Drucken sind fest (Dateiname, „Seite n“) und nicht einstellbar.
- „ANSI“ bedeutet immer Windows-1252 (westeuropäisch), unabhängig von der Systemsprache.
- Die Erkennung von UTF-16 ohne BOM ist eine vereinfachte Version von Windows' `IsTextUnicode`.
- Neu gegenüber ReactOS: Syntaxhervorhebung, Drag & drop, Zoom, Dunkelmodus, Kodierung und
  Zeilenende im Menü umstellbar, Standard-Editor-Umschaltung, Hintergrundbetrieb.

## Lizenz

LGPL-2.1-or-later, wie das ReactOS Notepad, aus dem Logik und Funktionsumfang stammen
(siehe [`LICENSE`](LICENSE)). ReactOS Notepad: Copyright Marcel Baur, Mike McCormack,
Sylvain Petreolle, Andriy Palamarchuk, Katayama Hirofumi MZ und weitere.
