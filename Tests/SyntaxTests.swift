/*
 * Notepad für macOS – Tests für Spracherkennung und Syntaxhervorhebung.
 * LICENSE: LGPL-2.1-or-later
 */

import Foundation

/// Kind of the token that covers `snippet` (first occurrence), or nil if uncolored.
private func kind(of snippet: String, in text: String, language: String) -> TokenKind? {
    let ns = text as NSString
    let target = ns.range(of: snippet)
    precondition(target.location != NSNotFound, "\(snippet) not in sample")
    let tokens = SyntaxLanguage.named(language)!.tokens(in: ns)!
    return tokens.first { NSLocationInRange(target.location, $0.range) && NSMaxRange(target) <= NSMaxRange($0.range) }?.kind
}

func runSyntaxTests() {
    print("== Syntaxhervorhebung")

    check("Alle \(SyntaxLanguage.all.count) Sprachen kompilieren", SyntaxLanguage.all.count >= 20)
    check("IDs eindeutig", Set(SyntaxLanguage.all.map(\.id)).count == SyntaxLanguage.all.count)

    let detections: [(String?, String, String?)] = [
        ("main.swift", "", "swift"), ("App.TSX", "", "javascript"), ("Makefile", "", "makefile"),
        (".zshrc", "", "shell"), ("config.yml", "", "yaml"), ("notes.txt", "", nil), ("README", "", nil),
        (nil, "#!/usr/bin/env python3", "python"), (nil, "#!/bin/bash", "shell"),
        (nil, "<?xml version=\"1.0\"?>", "xml"), (nil, "<!DOCTYPE html>", "html"), (nil, "Hallo", nil),
    ]
    for (fileName, firstLine, expected) in detections {
        let detected = SyntaxLanguage.detect(fileName: fileName, sample: firstLine as NSString)?.id
        check("Erkennung \(fileName ?? firstLine)", detected == expected, detected ?? "nil")
    }

    let swift = """
    // Kommentar
    @MainActor struct Foo { let url = "http://x" /* block */ ; var n = 42 }
    """
    check("Swift: Kommentar", kind(of: "Kommentar", in: swift, language: "swift") == .comment)
    check("Swift: // im String bleibt String", kind(of: "http://x", in: swift, language: "swift") == .string)
    check("Swift: Keyword", kind(of: "struct", in: swift, language: "swift") == .keyword)
    check("Swift: Typ", kind(of: "Foo", in: swift, language: "swift") == .type)
    check("Swift: Attribut", kind(of: "@MainActor", in: swift, language: "swift") == .attribute)
    check("Swift: Zahl", kind(of: "42", in: swift, language: "swift") == .number)
    check("Swift: Blockkommentar", kind(of: "block", in: swift, language: "swift") == .comment)
    check("Swift: Bezeichner bleibt neutral", kind(of: "url", in: swift, language: "swift") == nil)

    let python = "@dataclass\ndef f(x):\n    s = '''lang\n#kein Kommentar'''\n    return None  # echt\n"
    check("Python: Dekorator", kind(of: "@dataclass", in: python, language: "python") == .attribute)
    check("Python: # in Triple-String", kind(of: "#kein", in: python, language: "python") == .string)
    check("Python: Kommentar", kind(of: "# echt", in: python, language: "python") == .comment)
    check("Python: None", kind(of: "None", in: python, language: "python") == .keyword)

    let json = #"{"name": "Notepad", "n": -1.5e3, "ok": true}"#
    check("JSON: Schlüssel", kind(of: "\"name\"", in: json, language: "json") == .property)
    check("JSON: Wert", kind(of: "\"Notepad\"", in: json, language: "json") == .string)
    check("JSON: Zahl", kind(of: "-1.5e3", in: json, language: "json") == .number)
    check("JSON: true", kind(of: "true", in: json, language: "json") == .keyword)

    let html = #"<!-- c --><a href="x.html">Don't</a>"#
    check("HTML: Kommentar", kind(of: "c --", in: html, language: "html") == .comment)
    check("HTML: Tag", kind(of: "<a", in: html, language: "html") == .tag)
    check("HTML: Attribut", kind(of: "href", in: html, language: "html") == .property)
    check("HTML: Attributwert", kind(of: "x.html", in: html, language: "html") == .string)
    check("HTML: Apostroph im Text neutral", kind(of: "Don't", in: html, language: "html") == nil)

    let shell = "echo \"$HOME\" ${PATH} # Kommentar\nurl=a#b\n"
    check("Shell: Variable", kind(of: "${PATH}", in: shell, language: "shell") == .variable)
    check("Shell: Kommentar", kind(of: "# Kommentar", in: shell, language: "shell") == .comment)
    check("Shell: # mitten im Wort kein Kommentar", kind(of: "#b", in: shell, language: "shell") == nil)

    let markdown = "# Titel\n\n**fett** und `code`\n\n- Punkt\n\n```\nlet x = 1\n```\n"
    check("Markdown: Überschrift", kind(of: "Titel", in: markdown, language: "markdown") == .tag)
    check("Markdown: fett", kind(of: "**fett**", in: markdown, language: "markdown") == .keyword)
    check("Markdown: Code", kind(of: "`code`", in: markdown, language: "markdown") == .string)
    check("Markdown: Codeblock", kind(of: "let x = 1", in: markdown, language: "markdown") == .string)

    let sql = "SELECT name FROM t WHERE x = 'a''b' -- k"
    check("SQL: Keyword", kind(of: "SELECT", in: sql, language: "sql") == .keyword)
    check("SQL: String mit ''", kind(of: "'a''b'", in: sql, language: "sql") == .string)
    check("SQL: Kommentar", kind(of: "-- k", in: sql, language: "sql") == .comment)

    let rust = ##"let s = r#"a"b"#; fn f<'a>() { println!("x"); }"##
    check("Rust: Raw-String", kind(of: ##"r#"a"b"#"##, in: rust, language: "rust") == .string)
    check("Rust: Lifetime", kind(of: "'a", in: rust, language: "rust") == .type)
    check("Rust: Makro", kind(of: "println!", in: rust, language: "rust") == .attribute)

    // Every language must handle an unterminated comment/string and text without matches.
    for language in SyntaxLanguage.all {
        _ = language.tokens(in: "/* \" ' ``` <!-- \n plain words 123")!
        _ = language.tokens(in: "")
    }
    check("Alle Sprachen: Randfälle ohne Absturz", true)

    // Performance: ~1 MB of code per language.
    let line = "    let value = compute(\"text // not a comment\", 0x1F) // comment\n"
    let big = String(repeating: line, count: 1_000_000 / line.utf8.count) as NSString
    var slowest = (name: "", seconds: 0.0)
    for language in SyntaxLanguage.all {
        let start = Date()
        _ = language.tokens(in: big)
        let seconds = Date().timeIntervalSince(start)
        if seconds > slowest.seconds { slowest = (language.name, seconds) }
    }
    print(String(format: "     1 MB: langsamste Sprache %@ mit %.0f ms", slowest.name, slowest.seconds * 1000))
    check("1 MB in jeder Sprache unter 1,5 s", slowest.seconds < 1.5, slowest)
}

/// After random edits, the incremental re-scan must give exactly the tokens of a full scan.
func runIncrementalSyntaxTests() {
    print("== Inkrementelle Hervorhebung")
    let sample = """
    // comment "quoted" /* not */
    let s = "string // not a comment" + 'c' + `tpl`
    /* block
       comment */ fn main() { return 42 + 0x1F; }
    # hash comment
    key: value
    [section]
    name = "x" ; note
    <tag attr="v">text</tag> <!-- c -->
    SELECT * FROM t WHERE a = 'b' -- k
    \"\"\" triple
    still \"\"\" done
    """
    let pieces = ["\"", "'", "/*", "*/", "//", "\n", "#", "x", "let ", " ", "<!--", "-->", "`", "\"\"\"", "{", "}", ":", "="]
    var generator = SystemRandomNumberGenerator()
    var mismatches: [String] = []

    for language in SyntaxLanguage.all {
        let text = NSMutableString(string: String(repeating: sample + "\n", count: 6))
        var tokens = language.tokens(in: text)!
        for _ in 0..<60 {
            // One to three edits before each re-scan, like fast typing.
            var edit: SyntaxEdit?
            for _ in 0..<Int.random(in: 1...3, using: &generator) {
                let location = Int.random(in: 0...text.length, using: &generator)
                let removed = min(Int.random(in: 0...4, using: &generator), text.length - location)
                let inserted = Bool.random(using: &generator) ? pieces.randomElement(using: &generator)! : ""
                text.replaceCharacters(in: NSRange(location: location, length: removed), with: inserted)
                let edited = NSRange(location: location, length: (inserted as NSString).length)
                let delta = edited.length - removed
                if edit == nil { edit = SyntaxEdit(editedRange: edited, delta: delta) } else { edit!.merge(editedRange: edited, delta: delta) }
            }
            for windowSize in [200, 1_000_000] {
                let plan = SyntaxLanguage.rescanPlan(old: tokens, text: text, edit: edit!, windowSize: windowSize)
                var result = language.retokenize(window: text.substring(with: plan.window) as NSString,
                                                 windowStart: plan.window.location, documentLength: text.length,
                                                 restart: plan.restart, old: tokens, prefixCount: plan.prefixCount,
                                                 edit: edit!, cancel: nil)
                if case .needsMoreText = result {
                    result = language.retokenize(window: text.copy() as! NSString, windowStart: 0, documentLength: text.length,
                                                 restart: plan.restart, old: tokens, prefixCount: plan.prefixCount,
                                                 edit: edit!, cancel: nil)
                }
                guard case .tokens(let incremental) = result else { mismatches.append(language.id); break }
                let full = language.tokens(in: text)!
                if incremental != full {
                    mismatches.append(language.id)
                    break
                }
                if windowSize == 1_000_000 { tokens = full }
            }
        }
    }
    check("Inkrementell = vollständig (\(SyntaxLanguage.all.count) Sprachen × 60 Runden)", mismatches.isEmpty,
          Array(Set(mismatches)).sorted())
}
