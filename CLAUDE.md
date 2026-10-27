# CLAUDE.md

Native macOS-Portierung des ReactOS Notepad in Swift/AppKit. Kein Xcode-Projekt, kein
Swift Package – gebaut wird direkt mit `swiftc` über die Command Line Tools.

## Befehle

```sh
./build.sh   # build/Notepad.app (Universal arm64 + x86_64, ad hoc signiert)
./test.sh    # alle Tests; muss mit "ALLE TESTS OK" enden
```

Die Linker-Warnung zu `libswiftCompatibilityPacks.a` (x86_64) ist bekannt und harmlos.

## Arbeitsregeln

- **Bei jeder Änderung `README.md` und `CHANGELOG.md` mitpflegen** (und diese Datei, wenn sich
  Aufbau oder Regeln ändern). Neue Changelog-Einträge oben, Format „Keep a Changelog“, Deutsch.
  Version steht zusätzlich in `Resources/Info.plist` (`CFBundleShortVersionString`, `CFBundleVersion`).
- **Nichts hochladen**: Das Repo ist bewusst nur lokal, kein Remote, kein `git push`.
- Vor jedem Commit `./test.sh`. Neue Funktionen bekommen Tests in `Tests/`.
- Oberflächentexte auf Deutsch, Code-Kommentare auf Englisch. Jede Quelldatei beginnt mit dem
  Kopfkommentar inkl. `LICENSE: LGPL-2.1-or-later`.
- Tests dürfen nie `DefaultEditor.makeDefault`/`restore` aufrufen – das ändert echte
  Systemeinstellungen des Benutzers.

## Aufbau

- `Sources/main.swift` – Einstiegspunkt, setzt `AppDelegate`.
- `Sources/AppDelegate.swift` – baut die macOS-Menüleiste. Die Windows-artige Menüleiste im Fenster
  (`MenuStripView`) nutzt dieselben Menüs: `makeWindowMenu(at:)` liefert beim Aufklappen eine
  frische Kopie (damit „Zuletzt benutzt“ aktuell ist; „Datei“ bekommt zusätzlich „Beenden“).
- `Sources/TextDocument.swift` – `NSDocument` (Klasse per `@objc(TextDocument)` in der Info.plist).
  Hält Kodierung, Zeilenende, Sprachwahl. Kein Autosave (klassisches Speichern wie Notepad).
- `Sources/EditorWindowController.swift` – Fenster, `NotepadTextView` (TextKit 1, non-contiguous
  layout), `MenuStripView`, `StatusBarView`, Zoom, Gehe zu Zeile, F5, `.LOG`.
- `Sources/PlainTextStorage.h/.m` – Objective-C: `GapBufferString` (Lückenpuffer, Latin-1 mit
  1 Byte pro Zeichen, sonst UTF-16) und `PlainTextStorage` (NSTextStorage mit Attribut-Läufen,
  Attribute werden faul ergänzt). Swift liest den Text über `backingString` ohne Kopie.
- `Sources/TextCodec.swift` – Kodierungserkennung/-umwandlung (Port von ReactOS `text.c`),
  `LineScanner` und `LinePositionCache` für Zeile/Spalte.
- `Sources/SyntaxHighlighter.swift` – `SyntaxLanguage` (Definitionen + Erkennung) und
  `SyntaxHighlighter` (Hintergrund-Tokenisierung, Einfärben des sichtbaren Bereichs).
- `Sources/Lexer.swift` – handgeschriebener Lexer (`LexerSpec` + eine Scan-Schleife über den
  UTF-16-Puffer) für die Programmiersprachen; bildet die früheren Regex-Regeln exakt nach.
- `Sources/RegexRules.swift` – `RegexRulePlan`: kombiniert die Regeln der übrigen Sprachen mit
  möglichst wenigen Capture-Gruppen (Analyse der möglichen ersten Zeichen jeder Regel).
- `Sources/DefaultEditor.swift` – Standard-App für Texttypen setzen/zurückstellen.
- `Sources/Preferences.swift` – `UserDefaults`, Änderungen per `Preferences.didChange` an alle Fenster.

## Wichtige Invarianten

- Der Text im Editor enthält nur `\n`. `TextCodec.decode` normalisiert beim Öffnen,
  `TextCodec.encode` schreibt das gewählte Zeilenende. Eingefügtes `\r` wird beim Speichern normalisiert.
- Syntaxfarben nur als **temporäre Attribute** des `NSLayoutManager` – niemals in den
  `NSTextStorage` schreiben (sonst Undo-Einträge, „geändert“-Markierung und Leistungsprobleme).
- Undo läuft über den Undo-Manager des Dokuments (`windowWillReturnUndoManager`); daraus ergibt
  sich auch die „geändert“-Markierung.
- `EditorWindowController.document` wird erst nach `init` gesetzt – alles, was das Dokument
  braucht (Statusleiste, Sprache), im `didSet` von `document` aktualisieren.

## Fallstricke

- **Sprachdefinitionen**: Alle Regeln einer Sprache werden zu einer Alternation verbunden;
  Capture-Gruppe bzw. erstes Zeichen des Treffers bestimmen die Farbe (`RegexRulePlan`). Muster
  dürfen daher **keine eigenen Capture-Gruppen** haben (nur `(?:…)`) und nie leer matchen.
  Reihenfolge = Priorität bei gleicher Startposition. ICU wird pro Capture-Gruppe langsamer, ab
  der siebten sprunghaft – der Plan legt Regeln gleicher Art zusammen, wo das sicher ist.
- **Lexer-Sprachen** (`lexer: LexerSpec(…)`): Änderungen an den Regeln in `Lexer.swift` und in
  der eingefrorenen Regex-Kopie in `Tests/LexerTests.swift` gemeinsam machen; der Test vergleicht
  beide. Der Lexer darf keinen Zustand zwischen Lexemen halten (Neustart an jedem Token-Ende für
  das inkrementelle Einfärben), nur wenige Zeichen zurückschauen (`^`, `\b`, Lookbehind).
- **Raw-Strings in Swift**: `#"…"#` endet bei `"#`, und `#"""` öffnet einen mehrzeiligen String.
  Muster mit `"""` als `"{3}` schreiben, Muster mit `"#` mit mehr Rauten (`##"…"##`).
- Kompiliert wird im Swift-5-Modus (`-swift-version 5`); im Swift-6-Modus brechen
  NSDocument/AppKit-Aufrufe an der Concurrency-Prüfung.
- `test.sh` kompiliert alle Quellen außer `main.swift` zusammen mit `Tests/` (`@main` in
  `Tests/TestMain.swift`, daher `-parse-as-library`). Private Properties prüfen die Tests über `ivar(_:_:)`.
  Die Tests nutzen `Tests/Tests-Bridging-Header.h`; `Tests/LegacyTextStorage.m` ist der alte
  Textspeicher als Vergleich für den Benchmark (`NOTEPAD_BIG_BENCH=1` misst zusätzlich 1 GB).
- **Textansicht freigeben**: Textspeicher, Layout-Manager, Container und `NSTextView` halten sich
  gegenseitig fest, bis der Layout-Manager aus dem Textspeicher entfernt wird
  (`removeLayoutManager`) – sonst bleibt der ganze Text nach dem Schließen im Speicher.

## Leistungsbudget

Vor/nach Änderungen an Editor, Statusleiste oder Hervorhebung grob prüfen (Zahlen im README):
Tastendruck in 50 MB < 1 ms, Blockierung beim Einfärben < 20 ms, Startanteil eigener Code ~20 ms.
`./test.sh` misst die Tokenisierung von 1 MB pro Sprache (Grenze 1,5 s).
