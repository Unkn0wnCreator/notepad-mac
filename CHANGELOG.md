# Changelog

Alle nennenswerten Änderungen an diesem Projekt. Format nach
[Keep a Changelog](https://keepachangelog.com/de/1.1.0/), Versionen nach
[Semantic Versioning](https://semver.org/lang/de/).

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
