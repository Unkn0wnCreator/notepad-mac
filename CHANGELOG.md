# Changelog

Alle nennenswerten Änderungen an diesem Projekt. Format nach
[Keep a Changelog](https://keepachangelog.com/de/1.1.0/), Versionen nach
[Semantic Versioning](https://semver.org/lang/de/).

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
- `build.sh` zum Bauen, `test.sh` mit 70 automatischen Tests (Datei-Logik und Oberfläche).
