# Changelog

Alle nennenswerten Änderungen an diesem Projekt. Format nach
[Keep a Changelog](https://keepachangelog.com/de/1.1.0/), Versionen nach
[Semantic Versioning](https://semver.org/lang/de/).

## 1.3.0 – 2026-10-27

### Hinzugefügt

- Oberfläche auf Englisch: Menüs, Statusleiste, Dialoge und Meldungen erscheinen bei jeder
  Systemsprache außer Deutsch auf Englisch (Statusleiste z. B. „Ln 1, Col 1“, Menü „File“ mit
  „Exit“ wie im englischen Notepad). Bei deutscher Systemsprache bleibt alles wie bisher.
- README: Hinweis, dass das Projekt mit KI gebaut ist (Claude Code, „vibe-coded“), und Screenshot.

### Geändert

- Keine automatischen Fenster-Tabs von macOS mehr: jede Datei in einem eigenen Fenster wie bei
  Notepad, auch wenn in den Systemeinstellungen „Tabs bevorzugen“ gesetzt ist. Die Tab-Einträge im
  Menü „Fenster“ entfallen.
- CodeQL prüft zusätzlich die Workflow-Dateien.

### Korrigiert

- README: Fenster-Tabs als Funktion gestrichen, App-Größe (ca. 1,5 MB statt ca. 1 MB).

## 1.2.1 – 2026-10-27

### Hinzugefügt

- GitHub-Repo [Unkn0wnCreator/notepad-mac](https://github.com/Unkn0wnCreator/notepad-mac) mit CI
  auf `macos-latest`: baut und testet bei jedem Push und stellt die App als ZIP-Artefakt bereit. Zu
  jedem Tag `v…` veröffentlicht sie ein Release, Notizen aus dem passenden Changelog-Abschnitt.
  Dies ist das erste Release dort.
- CodeQL für die Swift-Quellen (GitHub), Dependabot für die Versionen der Actions.
- Clang Static Analyzer für `PlainTextStorage.m` in der CI (CodeQL kann kein Objective-C).
- `NOTEPAD_SKIP_PERF=1 ./test.sh` lässt Leistungstests und Benchmarks weg. Die GitHub-CI nutzt das,
  weil ihre geteilten Runner zu unterschiedlich schnell sind; lokal wird weiter alles geprüft.

### Korrigiert

- Baut auch mit Swift 6.3 (Xcode 26): mehrdeutiger Aufruf von `withUnsafeMutableBytes` in
  `TextCodec.swift` (mit neuerem Swift kompilierte es ohne Fehler).
- README und Dialog: *Notepad als Standard-Texteditor verwenden* braucht nicht nur eine
  Bestätigung – macOS fragt für jeden Dateityp einzeln nach. Die Angabe in 1.2.0 war falsch.

## 1.2.0 – 2026-10-27

Schwerpunkt Geschwindigkeit: große Dateien, Start und Hervorhebung.

### Hinzugefügt

- Syntaxhervorhebung für Konfigurationsdateien: TOML, Caddyfile, nginx, Apache (`.htaccess`,
  `httpd.conf`), systemd-Units, Terraform/HCL, `.env`, SSH-Konfiguration, Ignore-Dateien.
  `.conf`-Dateien werden am Inhalt als nginx, Apache oder INI erkannt; dazu Sonderfälle wie
  `Dockerfile.dev`, `~/.ssh/config`, `.babelrc` (JSON oder YAML), `Cargo.lock`.
- Drag & drop: Dateien ins Fenster ziehen. In ein leeres, unverändertes Fenster wird die Datei
  geladen, sonst öffnet sie sich in einem neuen Fenster.
- Menüleiste im Fenster: Ist ein Menü offen, wechselt es beim Überfahren eines anderen Titels.
- *Hilfe > Im Hintergrund bereithalten* (Standard: an): Notepad bleibt nach dem letzten Fenster
  aktiv und hält ein Fenster vorbereitet – Dateien öffnen sich in ca. 0,1 s statt ca. 0,4 s.
- *Hilfe > Bei der Anmeldung starten* (startet ohne Fenster).

### Geändert

- *Notepad als Standard-Texteditor verwenden* setzt die Dateitypen direkt über Launch Services.
  Eine Meldung kommt nur noch bei Fehlern. (Die hier ursprünglich angegebene „eine Bestätigung“
  stimmt nicht: macOS fragt weiterhin pro Dateityp nach.)
- Bei „Im Hintergrund bereithalten“ beendet sich Notepad nach dem letzten Fenster nicht mehr.

### Verbessert

- Öffnen und Speichern: eigener SIMD-UTF-8-Dekoder/-Encoder (ca. 2–4 GB/s statt ca. 0,3 GB/s),
  Latin-1-Text geht ohne Zwischenkopie in den Textspeicher (50 MB: lesen 282 → 27 ms,
  speichern 358 → 18 ms; 1 GB öffnen ca. 9 s → ca. 0,5–2 s je nach Dateicache).
- Eigener Textspeicher in Objective-C mit Lückenpuffer (Gap Buffer): Tastendruck in 1 GB überall
  ca. 0,5 ms (vorher bis 500 ms), Sprung in die Mitte von 200 MB 1,6 s → 85 ms,
  Speicher für 1 GB Text ca. 3 GB → ca. 1 GB (Latin-1 mit einem Byte pro Zeichen).
- Ohne Zeilenumbruch: Tastendruck in 200 MB 45 ms → unter 1 ms.
- Syntaxhervorhebung: handgeschriebener Lexer für die Programmiersprachen (20–90× schneller),
  übrige Sprachen mit weniger Regex-Gruppen (bis 4× schneller); nach einer Änderung wird nur der
  betroffene Bereich neu analysiert, die ersten Farben erscheinen sofort, der Rest im Hintergrund.
  Grenze für die Hervorhebung von 5 auf 50 MB angehoben.
- Fensteraufbau für große Dateien: Die Statusleiste zählte beim Laden einmal alle Zeilen
  (1 GB: 2,4 s → 0,6 s).

### Behoben

- Geschlossene Fenster gaben ihren Text nie frei; ein geschlossenes 1-GB-Dokument blieb im Speicher.
- Zeichenliterale mit Escape (`'\n'`) wurden in C/Java/Kotlin/C#/Go/Rust zu weit gefärbt.
- Nach einer Änderung konnte die Hervorhebung hinter der Stelle verschwinden, wenn der neu
  analysierte Ausschnitt keine Tokens enthielt (z. B. Fließtext in Markdown oder XML).

### Tests

- Über 550 Tests (vorher 136). Neu: Leistungstests bei jedem Lauf (50 MB öffnen, tippen, springen,
  speichern; Hervorhebung), Zufallstests für Lückenpuffer, Zeilen-Cache, Latin-1-/UTF-8-Dekoder und
  inkrementelle Hervorhebung, Vergleich Lexer gegen die früheren Regex-Regeln, Erkennung von
  Konfigurationsdateien, Drag & drop, Speicherfreigabe beim Schließen.

## 1.1.0 – 2026-10-26

### Hinzugefügt

- Syntaxhervorhebung für 21 Sprachen: Swift, C/C++/Objective-C, Java, Kotlin, C#, Go, Rust,
  JavaScript/TypeScript, Python, Shell, Batch, HTML, XML, CSS, JSON, Markdown, YAML,
  INI/TOML, SQL, Makefile, Dockerfile.
  - Automatische Erkennung über Dateiendung, Dateiname (`Makefile`, `.zshrc` …), Shebang-Zeile
    oder XML-/HTML-Kopf; manuell über *Format > Sprache*.
  - Ein- und ausschaltbar über *Ansicht > Syntaxhervorhebung*; Farben passend zu Hell- und Dunkelmodus.
  - Farben liegen nur in der Anzeige und landen nie in der Datei.
- Sprache in der Statusleiste.
- *Hilfe > Notepad als Standard-Texteditor verwenden*: macht Notepad zum Standardprogramm für
  Text-, Code-, JSON-, XML-, YAML-, Markdown-, CSV- und Logdateien. Die vorherigen Apps werden
  gemerkt; ein zweiter Klick stellt sie wieder her. HTML und RTF bleiben unberührt.

### Verbessert

- Tippen und Cursorbewegungen in sehr großen Dateien: Die Statusleiste zählt Zeilen nur noch ab der
  letzten bekannten Position (50 MB: ca. 60 ms → 0,4 ms pro Tastendruck).

### Tests

- 136 Tests (vorher 70), u. a. Beispiele für jede Sprache, Leistung bei 1 MB Code und ein
  Zufallstest für die Zeilenzählung.

## 1.0.0 – 2026-10-26

Erste Version: native Mac-Portierung des ReactOS Notepad.

### Hinzugefügt

- Dokumentbasierte AppKit-App (Swift) mit mehreren Fenstern und macOS-Tabs, Universal-Binary für
  Apple Silicon und Intel, ab macOS 13.
- Menüleiste im Fenster wie unter Windows (Datei, Bearbeiten, Format, Ansicht, Hilfe), zusätzlich zur
  macOS-Menüleiste.
- Aus ReactOS `text.c` portiert:
  - Kodierungserkennung beim Öffnen: BOM, reines ASCII, UTF-16 ohne BOM, UTF-8, ANSI (Windows-1252).
  - Zeilenenden (CRLF, LF, CR) erkennen und beim Speichern beibehalten.
  - NUL-Zeichen werden beim Öffnen durch Leerzeichen ersetzt.
- Aus ReactOS `dialog.c` portiert:
  - Gehe zu Zeile (⌘L) mit Bereichsprüfung.
  - Uhrzeit/Datum einfügen (F5).
  - `.LOG`-Funktion: Zeitstempel wird beim Öffnen angehängt.
  - Zeilenumbruch, Schriftauswahl, Statusleiste (Zeile/Spalte, Zoom, Zeilenende, Kodierung).
- Aus ReactOS `printing.c`: Drucken mit Dateiname als Kopfzeile und „Seite n“ als Fußzeile.
- Kodierung und Zeilenende über „Format“ änderbar; Fehlermeldung, wenn Zeichen nicht in ANSI passen.
- Suchen und Ersetzen über die macOS-Suchleiste, Zoom (⌘+ / ⌘- / ⌘0), Dunkelmodus.
- Schrift, Zeilenumbruch und Statusleiste werden gespeichert und gelten für alle Fenster.
- Eigenes App-Icon (wird beim Bauen gezeichnet).
- `build.sh` zum Bauen, `test.sh` mit automatischen Tests (Datei-Logik und Oberfläche).
