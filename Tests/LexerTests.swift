/*
 * Notepad für macOS – Tests für den handgeschriebenen Lexer: Vergleich mit den früheren
 * Regex-Definitionen und Geschwindigkeit.
 * LICENSE: LGPL-2.1-or-later
 */

import Foundation

/// The former regex rules (frozen copy). The lexer must produce the same tokens.
private enum P {
    static let slashComment = #"//[^\n]*"#
    static let blockComment = #"/\*[\s\S]*?(?:\*/|\z)"#
    static let hashComment = #"#[^\n]*"#
    static let hashCommentAfterSpace = #"(?:^|(?<=[ \t;]))#[^\n]*"#
    static let dqString = #""(?:[^"\\\n]|\\.)*"?"#
    static let sqString = #"'(?:[^'\\\n]|\\.)*'?"#
    static let sqStringClosed = #"'(?:[^'\\\n]|\\.)*'"#
    /// Intentional difference: the old greedy `\\.{1,8}` made `'\n', 'x'` one literal; the
    /// lexer ends at the first closing quote, as the lazy `\\.{1,8}?` does.
    static let charLiteralBuggy = #"'(?:[^'\\\n]|\\.{1,8})'"#
    static let charLiteral = #"'(?:[^'\\\n]|\\.{1,8}?)'"#
    static let backtickString = #"`(?:[^`\\]|\\[\s\S])*`?"#
    static let tripleDq = #""{3}[\s\S]*?(?:"{3}|\z)"#
    static let number = #"\b(?:0[xX][0-9a-fA-F_]+|0[bB][01_]+|0[oO][0-7_]+|\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?)[a-zA-Z]*\b"#
}

/// Regex-only definitions of the lexer languages, exactly as before the lexer.
private let regexLanguages: [SyntaxLanguage] = [
    SyntaxLanguage(id: "swift", name: "Swift", extensions: ["swift"],
                   keywords: "associatedtype class deinit enum extension fileprivate func import init inout internal let open operator private precedencegroup protocol public rethrows static struct subscript typealias var break case catch continue default defer do else fallthrough for guard if in repeat return throw switch where while as Any false is nil self Self super throws true try async await actor nonisolated isolated some any lazy weak unowned override mutating nonmutating final required convenience dynamic optional get set willSet didSet macro consuming borrowing package sending", capitalizedTypes: true, rules: [
        (.comment, P.slashComment), (.comment, P.blockComment),
        (.string, P.tripleDq), (.string, P.dqString),
        (.attribute, #"@\w+"#),
        (.attribute, #"#(?:if|elseif|else|endif|available|unavailable|selector|keyPath|warning|error|file|fileID|filePath|line|column|function|dsohandle|sourceLocation|Preview|expect|require)\b"#),
        (.number, P.number),
    ]),
    SyntaxLanguage(id: "c", name: "C / C++ / Objective-C",
                   extensions: ["c", "h", "cpp", "cc", "cxx", "hpp", "hh", "hxx", "m", "mm", "ino"],
                   keywords: "auto break case char const continue default do double else enum extern float for goto if inline int long register restrict return short signed sizeof static struct switch typedef union unsigned void volatile while bool true false NULL nullptr class namespace template typename public private protected virtual override final new delete this throw try catch using operator friend explicit constexpr consteval static_cast dynamic_cast reinterpret_cast const_cast noexcept decltype mutable nil YES NO self super id instancetype nonatomic strong weak assign readonly readwrite", capitalizedTypes: true, typeSuffix: "_t", rules: [
        (.comment, P.slashComment), (.comment, P.blockComment),
        (.attribute, #"^[ \t]*#[ \t]*\w+"#),
        (.string, #"<[\w./+-]+\.h(?:h|pp|xx)?>"#),
        (.string, P.dqString), (.string, P.charLiteral),
        (.attribute, #"@\w+"#),
        (.number, P.number),
    ]),
    SyntaxLanguage(id: "java", name: "Java", extensions: ["java"],
                   keywords: "abstract assert boolean break byte case catch char class const continue default do double else enum extends final finally float for goto if implements import instanceof int interface long native new package private protected public return short static strictfp super switch synchronized this throw throws transient try void volatile while true false null var record sealed permits yield", capitalizedTypes: true, rules: [
        (.comment, P.slashComment), (.comment, P.blockComment),
        (.string, P.tripleDq), (.string, P.dqString), (.string, P.charLiteral),
        (.attribute, #"@\w+"#),
        (.number, P.number),
    ]),
    SyntaxLanguage(id: "kotlin", name: "Kotlin", extensions: ["kt", "kts"],
                   keywords: "as break class continue do else false for fun if in interface is null object package return super this throw true try typealias typeof val var when while by catch constructor finally get import init set where actual abstract annotation companion const crossinline data enum expect external final infix inline inner internal lateinit noinline open operator out override private protected public reified sealed suspend tailrec vararg", capitalizedTypes: true, rules: [
        (.comment, P.slashComment), (.comment, P.blockComment),
        (.string, P.tripleDq), (.string, P.dqString), (.string, P.charLiteral),
        (.attribute, #"@\w+"#),
        (.number, P.number),
    ]),
    SyntaxLanguage(id: "csharp", name: "C#", extensions: ["cs", "csx"],
                   keywords: "abstract as base bool break byte case catch char checked class const continue decimal default delegate do double else enum event explicit extern false finally fixed float for foreach goto if implicit in int interface internal is lock long namespace new null object operator out override params private protected public readonly ref return sbyte sealed short sizeof stackalloc static string struct switch this throw true try typeof uint ulong unchecked unsafe ushort using virtual void volatile while var async await dynamic get set value yield record init required", capitalizedTypes: true, rules: [
        (.comment, P.slashComment), (.comment, P.blockComment),
        (.attribute, #"^[ \t]*#[ \t]*\w+"#),
        (.string, #"@"(?:[^"]|"")*"?"#), (.string, P.tripleDq), (.string, P.dqString), (.string, P.charLiteral),
        (.number, P.number),
    ]),
    SyntaxLanguage(id: "go", name: "Go", extensions: ["go"],
                   keywords: "break case chan const continue default defer else fallthrough for func go goto if import interface map package range return select struct switch type var true false nil iota", types: "bool byte complex64 complex128 error float32 float64 int int8 int16 int32 int64 rune string uint uint8 uint16 uint32 uint64 uintptr any", capitalizedTypes: true, rules: [
        (.comment, P.slashComment), (.comment, P.blockComment),
        (.string, P.dqString), (.string, P.backtickString), (.string, P.charLiteral),
        
        (.number, P.number),
    ]),
    SyntaxLanguage(id: "rust", name: "Rust", extensions: ["rs"],
                   keywords: "as async await break const continue crate dyn else enum extern false fn for if impl in let loop match mod move mut pub ref return self Self static struct super trait true type unsafe use where while", types: "i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize f32 f64 bool char str", capitalizedTypes: true, rules: [
        (.comment, P.slashComment), (.comment, P.blockComment),
        (.string, ####"r###"[\s\S]*?(?:"###|\z)|r##"[\s\S]*?(?:"##|\z)|r#"[\s\S]*?(?:"#|\z)|r"[^"]*"?"####), (.string, P.dqString), (.string, P.charLiteral),
        (.type, #"'[A-Za-z_]\w*\b"#),
        (.attribute, #"#!?\[[^\]\n]*\]"#), (.attribute, #"\b\w+!"#),
        
        (.number, P.number),
    ]),
    SyntaxLanguage(id: "javascript", name: "JavaScript / TypeScript",
                   extensions: ["js", "mjs", "cjs", "jsx", "ts", "mts", "cts", "tsx"],
                   keywords: "break case catch class const continue debugger default delete do else export extends finally for function if import in instanceof let new return super switch this throw try typeof var void while with yield async await of static get set true false null undefined NaN Infinity from as interface type enum implements private protected public readonly declare namespace abstract keyof never unknown any number string boolean symbol bigint object satisfies", capitalizedTypes: true, rules: [
        (.comment, P.slashComment), (.comment, P.blockComment),
        (.string, P.dqString), (.string, P.sqString), (.string, P.backtickString),
        (.attribute, #"@\w+"#),
        (.number, P.number),
    ]),
    SyntaxLanguage(id: "python", name: "Python", extensions: ["py", "pyw", "pyi"],
                   keywords: "False None True and as assert async await break class continue def del elif else except finally for from global if import in is lambda nonlocal not or pass raise return try while with yield match case self cls", capitalizedTypes: true, rules: [
        (.comment, P.hashComment),
        (.string, #"(?:\b[rRbBfFuU]{1,2})?"""[\s\S]*?(?:"""|\z)"#),
        (.string, #"(?:\b[rRbBfFuU]{1,2})?'''[\s\S]*?(?:'''|\z)"#),
        (.string, #"(?:\b[rRbBfFuU]{1,2})?"# + P.dqString),
        (.string, #"(?:\b[rRbBfFuU]{1,2})?"# + P.sqString),
        (.attribute, #"^[ \t]*@[\w.]+"#),
        (.number, P.number),
    ]),
    SyntaxLanguage(id: "shell", name: "Shell", extensions: ["sh", "bash", "zsh", "ksh", "command"],
                   fileNames: [".bashrc", ".bash_profile", ".zshrc", ".zprofile", ".profile", ".zshenv"],
                   keywords: "if then else elif fi case esac for select while until do done in function time return exit break continue local export readonly declare typeset unset shift source alias echo printf read cd test true false eval exec set trap wait", rules: [
        (.comment, P.hashCommentAfterSpace),
        (.string, P.dqString), (.string, #"'[^']*'?"#),
        (.variable, #"\$\{[^}\n]*\}|\$[A-Za-z_]\w*|\$[0-9@#?$!*-]"#),
        (.number, P.number),
    ]),
]

/// Realistic code per language (also the benchmark input, repeated to ~3 MB).
private let lexerSamples: [String: String] = [
    "swift": #"""
    // Copyright header
    import AppKit

    /// Documentation comment with `code` and a URL: https://example.com
    @MainActor
    final class ViewModel: ObservableObject {
        @Published var items: [Item] = []
        private let limit = 1_000
        let hex = 0xFF_FF, binary = 0b1010, octal = 0o17, float = 3.14e-2, big = 1e10
        let message = "Hello, \(name)! \"quoted\" \\ done"
        let multi = """
            Line one "with quotes"
            Line two \(value)
            """
        /* block comment
           spanning lines */
        func load(from url: URL) async throws -> [Item] {
            #if DEBUG
            print("debug", #file, #line, #function)
            #elseif os(macOS)
            guard #available(macOS 13, *) else { return [] }
            #endif
            let (data, _) = try await URLSession.shared.data(from: url)
            return try JSONDecoder().decode([Item].self, from: data).filter { $0.count > 0 && $0.name != "" }
        }
        let selector = #selector(NSText.copy(_:)), path = #keyPath(Item.name), raw = #"raw "string""#
        subscript(index: Int) -> Item? { index < items.count ? items[index] : nil }
    }

    """#,
    "c": #"""
    #include <stdio.h>
    #include <sys/types.h>
    #include "local.h"
      #  define MAX(a, b) ((a) > (b) ? (a) : (b))
    #import <Foundation/Foundation.hpp>

    /* Block comment
     * with several lines */
    typedef struct node_t { int value; struct node_t *next; } node_t;
    static const char *names[] = { "alpha", "beta\n", "gamma \"quoted\"" };

    @interface Foo : NSObject @property (nonatomic, strong) NSString *name; @end

    int main(int argc, char **argv) {
        size_t count = 0x1Fu + 017 + 1.5e3f + 42UL + 0b1011;
        char c = 'x', nl = '\n', q = '\'', hex = '\x41';
        uint32_t flags = argc < 2 ? 0 : 1; // comment with "string"
        for (int i = 0; i < argc; i++) { printf("%s %d\n", argv[i], i); }
        if (count > MAX(1, 2) && flags < 3) return NULL == 0 ? YES : NO;
        std::vector<std::string> v; template<typename T> class Box {};
        return 0;
    }

    """#,
    "java": #"""
    package com.example.app;

    import java.util.*;

    /** Javadoc with {@link List}. */
    @SuppressWarnings("unchecked")
    public final class Main extends Base implements Runnable {
        private static final long MAX = 1_000_000L;
        private final Map<String, Integer> counts = new HashMap<>();
        String text = """
            Hello "world"
            """;
        char c = 'c', esc = '\t', uni = '\u0041';

        @Override
        public void run() {
            for (int i = 0; i < 10; i++) {
                counts.merge("key" + i, 1, Integer::sum); // count
            }
            double d = 3.5e-3d; float f = 2.0f; int hex = 0xCAFE;
            /* block */ var list = List.of(1, 2, 3);
            if (list instanceof ArrayList<?> a && a.size() > 0) throw new IllegalStateException("bad: " + a);
        }
        record Point(int x, int y) {}
    }

    """#,
    "kotlin": #"""
    package app

    import kotlinx.coroutines.*

    @JvmInline value class Id(val raw: Long)

    data class User(val name: String, val age: Int = 0) {
        companion object { const val MAX = 0xFF; val pattern = """[a-z]+\d*""" }
    }

    suspend fun load(users: List<User>): Map<String, Int> = coroutineScope {
        val c = 'k'; val esc = '\n'
        val text = "Hello ${users.first().name}, you are ${users.size} \"users\""
        // line comment
        /* block comment */
        users.filter { it.age > 18 && it.name != "" }.associate { it.name to it.age * 2 + 1.5e2.toInt() }
    }

    """#,
    "csharp": #"""
    #region Usings
    using System;
    using System.Collections.Generic;
    #endregion

    namespace App
    {
        [Serializable]
        public sealed class Program : IDisposable
        {
            private const int Max = 0x7FFF;
            private readonly List<string> _items = new();
            string path = @"C:\temp\file ""quoted"".txt";
            string raw = """
                raw "text"
                """;
            char c = 'c', nl = '\n';

            public static async Task<int> Main(string[] args)
            {
                #if DEBUG
                Console.WriteLine($"Args: {args.Length} \"quoted\""); // comment
                #endif
                var total = 1.5e3 + 2.0f + 10UL + 1_000m;
                /* block */ foreach (var arg in args) { if (arg is null) continue; }
                return await Task.FromResult(args.Length > 0 ? 1 : 0);
            }
            public void Dispose() { }
        }
    }

    """#,
    "go": #"""
    package main

    import (
    	"fmt"
    	"strings"
    )

    // Point is a point.
    type Point struct {
    	X, Y float64 `json:"x"`
    }

    /* Block
       comment */
    func (p *Point) String() string {
    	r := 'x'
    	esc := '\n'
    	raw := `C:\path\with
    newline`
    	return fmt.Sprintf("(%g, %g) %c %c %s", p.X, p.Y, r, esc, raw)
    }

    func main() {
    	values := []int{1, 2, 0x1F, 0o17, 1_000, 3}
    	var total int64 = 0
    	for i, v := range values {
    		total += int64(v * i) // sum
    	}
    	m := map[string]error{"a": nil}
    	if len(m) > 0 && total > 1e3 { fmt.Println(strings.ToUpper("done"), 3.14i) }
    	go func() { defer close(ch) }()
    }

    """#,
    "rust": ##"""
    //! Crate documentation
    #![allow(dead_code)]
    use std::collections::HashMap;

    /// A thing with a lifetime.
    #[derive(Debug, Clone, PartialEq)]
    pub struct Thing<'a> {
        name: &'a str,
        values: Vec<u32>,
    }

    impl<'a> Thing<'a> {
        pub fn new(name: &'a str) -> Self {
            let raw = r#"raw "string" here"#;
            let raw2 = r##"with "# inside"##;
            let simple = r"C:\path";
            let bytes = b"bytes"; let byte = b'x';
            let c = 'c'; let esc = '\n'; let uni = '\u{1F600}';
            println!("{} {} {}", raw, raw2, simple);
            let numbers = [1u8, 0xFFu8, 0b1010_1010, 0o777, 1_000_000, 3.5e-2f64 as u8];
            /* block /* comment */
            Thing { name, values: vec![1, 2, 3] }
        }
    }

    fn main() -> Result<(), Box<dyn std::error::Error>> {
        let mut map: HashMap<String, i32> = HashMap::new();
        map.insert("key".to_string(), 42); // comment
        assert_eq!(map.len(), 1);
        Ok(())
    }

    """##,
    "javascript": #"""
    // @ts-check
    import { readFile } from 'node:fs/promises';

    /**
     * JSDoc comment
     * @param {string} path
     */
    export async function load(path) {
      const text = await readFile(path, 'utf8');
      const data = JSON.parse(text);
      const greeting = `Hello ${data.name}, you have ${data.count * 2} "items"
    on two lines`;
      const re = /ab+c/gi, hex = 0xFF, big = 123n, exp = 1.5e-3, sep = 1_000;
      if (data.items?.length > 0 && data.ok !== false) {
        return data.items.map((item, i) => ({ ...item, index: i, label: 'item-' + i }));
      }
      throw new Error("Unexpected \"data\": " + typeof data);
    }

    @Component({ selector: 'app-root' })
    class AppComponent implements OnInit {
      private readonly items: Array<string> = [];
      ngOnInit(): void { console.log(this.items, null, undefined, NaN); }
    }

    """#,
    "python": #"""
    #!/usr/bin/env python3
    """Module docstring with "quotes"."""
    import os
    from dataclasses import dataclass, field

    @dataclass
    class Item:
        name: str
        count: int = 0
        tags: list = field(default_factory=list)

        @property
        def label(self) -> str:
            return f"{self.name} ({self.count})"  # comment

    @app.route("/items/<int:item_id>")
    def handler(item_id, *args, **kwargs):
        '''Docstring
        with lines'''
        raw = r"C:\path\n"
        data = b'\x00\x01'
        both = rb'raw bytes' + Rb"more" + u'unicode' + f'''multi {item_id}'''
        numbers = [0x1F, 0o17, 0b101, 1_000, 3.14, 1e-5, 2j]
        if item_id is None or not isinstance(item_id, int):
            raise ValueError('bad id: %s' % item_id)
        return {k: v for k, v in kwargs.items() if v}, lambda x: x * 2

    """#,
    "shell": #"""
    #!/bin/bash
    # Build script
    set -euo pipefail

    readonly DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    VERSION=1.2.3; COUNT=42 # trailing comment
    url=http://example.com/a#anchor

    function build() {
        local target="$1" args=("$@")
        echo "Building $target with ${#args[@]} args in $DIR"
        if [ -f "$DIR/build.sh" ] && [[ $COUNT -gt 10 ]]; then
            printf '%s\n' 'single quoted $NOT_A_VAR'
        elif test -z "${TARGET:-}"; then
            exit 1
        fi
        for file in "$DIR"/*.txt; do cat "$file" | grep -v '^#' || true; done
        echo $? $# $0 $$ $!
    }

    case "$1" in
        build) build "$@" ;;
        *) echo "usage: $0 build" >&2; exit 2 ;;
    esac

    """#,
]

/// Pieces for random texts: syntax that starts or ends tokens, plus Unicode edge cases
/// (non-ASCII word characters and digits, combining marks, format characters, line and
/// paragraph separators, surrogate pairs and lone surrogates).
private let fuzzPieces: [[UInt16]] = {
    var pieces = [
        "\"", "'", "\"\"\"", "'''", "`", "\\", "\n", "\r", "\r\n", " ", "  ", "\t", "/", "*", "/*", "*/", "//",
        "#", "#if", "#else", "#elseif", "#fileID", "#file", "#selector", "@", "@x", "@\"", "$", "${", "}", "{",
        "$1", "$#", "$a", "<", ">", ".h", ".hpp", ".hxx", "stdio", "sys/", "+", "-", "0x1F", "0X", "0b101", "0b2",
        "0o7", "1.5e+3", "1e", "1.", ".5", "12", "_", "abc", "Foo", "size_t", "r", "br", "f", "rb", "u", "R",
        "r#", "r##", "\"#", "#[", "#![", "]", "#!", "!", "'a", "'\\n'", "\\'", "x", "let", "if", "None", "self",
        "e", "E", "L", "_t", "\"\"", ";", "=", ":", "(", ")", ",", ".", "9", "0", "é", "٣", "ß", "😀", "𝐀", "\u{0301}",
        "\u{200B}", "\u{200D}", "\u{2028}", "\u{85}", "\u{0B}", "\u{0C}", "\u{FEFF}", "a\u{0301}", "1\u{0301}",
    ].map { Array($0.utf16) }
    pieces.append([0xD800])
    pieces.append([0xDC00])
    pieces.append([0xD835])  // lead of 𝐀 without trail
    return pieces
}()

/// Deterministic generator, so a failure can be reproduced.
private struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// First difference between the regex and the lexer tokens of `text`, or nil.
private func lexerDifference(_ regex: SyntaxLanguage, _ lexer: SyntaxLanguage, _ text: NSString) -> String? {
    let expected = regex.tokens(in: text)!
    let actual = lexer.tokens(in: text)!
    guard expected != actual else { return nil }
    let index = (0..<min(expected.count, actual.count)).first { expected[$0] != actual[$0] } ?? min(expected.count, actual.count)
    func describe(_ tokens: [SyntaxToken]) -> String {
        guard index < tokens.count else { return "–" }
        let token = tokens[index]
        return "\(token.kind) \(token.location)+\(token.length) \(text.substring(with: token.range).debugDescription)"
    }
    let context = max(0, Int(index < expected.count ? expected[index].location : actual[index].location) - 20)
    let snippet = text.substring(with: NSRange(location: context, length: min(60, text.length - context)))
    return "Token \(index): Regex \(describe(expected)) / Lexer \(describe(actual)) bei \(snippet.debugDescription)"
}

func runLexerTests() {
    print("== Lexer (Vergleich mit Regex)")

    for regex in regexLanguages {
        let lexer = SyntaxLanguage.named(regex.id)!
        var failures: [String] = []

        // Realistic samples of every lexer language (other languages' code is good noise too).
        for (_, sample) in lexerSamples.sorted(by: { $0.key < $1.key }) {
            if let difference = lexerDifference(regex, lexer, sample as NSString) { failures.append(difference) }
        }
        check("\(regex.name): Beispielcode wie Regex", failures.isEmpty, failures.first ?? "")

        // Random texts made of tricky pieces.
        var random = SplitMix(state: UInt64(abs(regex.id.hashValue % 1000)) + 7)
        var fuzzFailure: String?
        for _ in 0..<600 where fuzzFailure == nil {
            var units: [UInt16] = []
            for _ in 0..<Int.random(in: 1...60, using: &random) {
                units += fuzzPieces.randomElement(using: &random)!
            }
            let text = NSString(characters: units, length: units.count)
            fuzzFailure = lexerDifference(regex, lexer, text)
        }
        check("\(regex.name): 600 Zufallstexte wie Regex", fuzzFailure == nil, fuzzFailure ?? "")
    }

    // The one intentional difference: escaped char literals end at the first closing quote.
    let chars = #"char nl = '\n', q = '\'', x = '\x41';"# as NSString
    let fixedTokens = SyntaxLanguage.named("c")!.tokens(in: chars)!.filter { $0.kind == .string }.map { chars.substring(with: $0.range) }
    check("Char-Literale enden am ersten schließenden Apostroph", fixedTokens == [#"'\n'"#, #"'\''"#, #"'\x41'"#], fixedTokens)
    let buggy = SyntaxLanguage(id: "c-old", name: "C (alt)", extensions: [], keywords: "char",
                               rules: [(.string, P.charLiteralBuggy)])
    let buggyTokens = buggy.tokens(in: chars)!.filter { $0.kind == .string }.map { chars.substring(with: $0.range) }
    check("Früheres Regex fasste '\\n', q = ' zusammen", buggyTokens.first == #"'\n', q = '"#, buggyTokens)

    print("== Lexer (Geschwindigkeit, ~3 MB je Sprache)")
    for regex in regexLanguages {
        let lexer = SyntaxLanguage.named(regex.id)!
        let sample = lexerSamples[regex.id]!
        let text = String(repeating: sample, count: max(1, 3_000_000 / sample.utf8.count)) as NSString
        let megabytes = Double(text.length) / 1_000_000  // UTF-16 code units ≈ bytes of ASCII code

        func seconds(_ language: SyntaxLanguage, runs: Int) -> (Double, [SyntaxToken]) {
            var best = Double.infinity
            var tokens: [SyntaxToken] = []
            for _ in 0..<runs {
                let start = Date()
                tokens = language.tokens(in: text)!
                best = min(best, Date().timeIntervalSince(start))
            }
            return (best, tokens)
        }
        let (oldTime, oldTokens) = seconds(regex.withOneGroupPerRule(), runs: 1)
        let (regexTime, _) = seconds(regex, runs: 1)
        let (lexerTime, lexerTokens) = seconds(lexer, runs: 3)
        let factor = oldTime / lexerTime
        print(String(format: "     %@ Regex %5.1f MB/s (mit weniger Gruppen %5.1f)  Lexer %6.1f MB/s  %3.0f× (%2.0f×)",
                     regex.id.padding(toLength: 11, withPad: " ", startingAt: 0),
                     megabytes / oldTime, megabytes / regexTime, megabytes / lexerTime, factor, regexTime / lexerTime))
        check("\(regex.name): 3 MB gleiche Tokens", oldTokens == lexerTokens)
        checkPerformance("\(regex.name): Lexer mindestens 5× schneller", factor >= 5, String(format: "%.1f×", factor))
    }
}

/// Samples for the languages that keep the regex path.
private let regexSamples: [String: String] = [
    "html": #"""
    <!DOCTYPE html>
    <html lang="de">
    <head><meta charset="utf-8"><title>Seite &amp; Titel</title>
    <link rel="stylesheet" href='style.css'></head>
    <body class="main" data-x = "1">
      <!-- Kommentar
           über Zeilen -->
      <p id=main>Text mit &lt;Tag&gt; &#169; und <a href="https://example.com?a=1&b=2">Link</a>.</p>
      <script>if (a < b && c > d) { x = "y"; }</script>
      <img src="bild.png" alt="Bild"/><br/>
    </body>
    </html>

    """#,
    "xml": #"""
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
        <key>CFBundleName</key><string>Notepad</string>
        <ns:item xmlns:ns="urn:x" ns:attr='v'><![CDATA[ <raw> & "data" ]]></ns:item>
        <!-- comment --><empty/>
    </dict>
    </plist>

    """#,
    "css": #"""
    @import url("theme.css");
    /* Block comment */
    :root { --main-color: #1E90FF; --gap: 8px; }
    body, .container > #header a:hover::before {
      color: #fff !important;
      margin: 0 auto 1.5em -2px;
      font-family: 'Helvetica Neue', "Arial", sans-serif;
      background: url(data:image/png;base64,AAAA) no-repeat;
    }
    @media (max-width: 600px) { .grid { display: grid; grid-template-columns: repeat(2, 1fr); } }
    // scss comment
    .btn-primary:not(.disabled) { transition: all .3s ease-in-out; z-index: 10; }

    """#,
    "json": #"""
    {
      "name": "notepad", "version": "1.2.0", "private": true,
      "numbers": [1, -2.5, 3e10, -0.5E-3, 0x1F],
      "nested": { "key": "value with \"escapes\" and \\ backslash", "empty": "", "null": null },
      // comment (JSONC)
      /* block */ "list": [true, false, null, "a:b", {"x": 1}]
    }

    """#,
    "markdown": #"""
    # Titel

    Ein Absatz mit **fett**, __auch fett__, *kursiv*, _kursiv_ und `code`.
    Ein [Link](https://example.com) und ein Bild ![Alt](bild.png).

    > Zitat über
    > zwei Zeilen

    - Punkt eins
    * Punkt zwei
    1. Nummer
    2) Nummer

    ---

    ```swift
    let x = 1 // kein Kommentar hier
    ```
    <!-- HTML-Kommentar -->
    ## Unterkapitel mit snake_case_word und 2*3*4

    """#,
    "yaml": #"""
    ---
    # Kommentar
    name: notepad
    version: 1.2.0
    enabled: true
    ratio: 0.75
    list:
      - "doppelt # kein Kommentar"
      - 'einfach ''zitiert'''
      - &anker wert
      - *anker
    url: http://example.com/#anchor # echter Kommentar
    typed: !!str 123
    nested: {a: 1, b: [x, y]}
    ...

    """#,
    "ini": #"""
    ; Kommentar
    # auch Kommentar
    [section]
    key = value
    name.sub-key: "quoted ; not comment"
    enabled = true
    count = 42
    [[array.table]]
    path = 'C:\temp'

    """#,
    "sql": #"""
    -- Kommentar
    CREATE TABLE users (id SERIAL PRIMARY KEY, name VARCHAR(100) NOT NULL, "Quoted Col" INT DEFAULT 0);
    /* Block
       comment */
    SELECT u.name, COUNT(*) AS n FROM users u LEFT JOIN orders o ON o.user_id = u.id
    WHERE u.name LIKE 'A%' AND u.note <> 'it''s' GROUP BY u.name HAVING COUNT(*) > 1.5e2 ORDER BY n DESC LIMIT 10;
    insert into `log` values (1, 'x');

    """#,
    "makefile": #"""
    # Makefile
    CC := clang
    CFLAGS = -O2 -Wall $(EXTRA) ${MORE}
    .PHONY: all clean

    all: build/app

    build/%.o: src/%.c include/%.h
    	$(CC) $(CFLAGS) -c $< -o $@ # compile
    	@echo "built $@" 'quoted'

    ifeq ($(OS),Darwin)
    LDFLAGS += -framework AppKit
    else
    LDFLAGS += -lm
    endif
    include config.mk

    """#,
    "dockerfile": #"""
    # syntax=docker/dockerfile:1
    FROM swift:5.9 AS build
    ARG VERSION=1.0
    ENV PATH="/opt/bin:${PATH}" HOME=/root
    WORKDIR /src
    COPY . .
    RUN swift build -c release && echo "done $VERSION" 'x'
    EXPOSE 8080
    from alpine as final
    CMD ["./app", "--port", "8080"]

    """#,
    "batch": #"""
    @echo off
    rem Kommentar
    :: auch Kommentar
    setlocal enabledelayedexpansion
    set NAME=Welt
    if "%NAME%"=="Welt" (echo Hallo %NAME%!) else goto :ende
    for %%f in (*.txt) do echo %%~nf !COUNT!
    call :unter %1 %*
    :ende
    exit /b 0

    """#,
]

/// Pieces for random texts in markup and configuration syntaxes.
private let regexFuzzPieces: [String] = [
    "<", ">", "</", "/>", "<!--", "-->", "<![CDATA[", "]]>", "<?", "<!", "&amp;", "&#169;", "&", ";", "=", "\"", "'",
    "a", "div", "href", "x:y", " ", "\n", "\t", "#", "##", "# ", "*", "**", "_", "__", "`", "```", "[", "]", "(", ")",
    "![", "](", "> ", "- ", "1. ", "2) ", "---", "...", ":", ": ", "key", "Key", "true", "NULL", "!!str", "&a", "*a",
    "@media", "{", "}", "#fff", ".cls", "!important", "--", "/*", "*/", "//", "$", "$(", "${", "$@", "%", "%%",
    "%~1", "!v!", "rem", "REM ", "::", ":label", "@echo", "[section]", "[[t]]", "SELECT", "from", "'it''s'",
    "ifeq", ".PHONY", "all:", "FROM", "as", "AS", "RUN", "0x1F", "1.5", "-2", "12px", "é", "K", "ſ", "\u{212A}",
    "\u{2028}", "\r",
]

func runRegexPlanTests() {
    print("== Regex-Sprachen: weniger Capture-Gruppen")
    let regexOnly = SyntaxLanguage.all.filter { !$0.usesLexer }
    let mixed = regexSamples.sorted { $0.key < $1.key }.map(\.value).joined()
    var random = SplitMix(state: 42)

    for language in regexOnly {
        let reference = language.withOneGroupPerRule()
        var failure: String?
        for sample in regexSamples.sorted(by: { $0.key < $1.key }).map(\.value) + [mixed] where failure == nil {
            failure = lexerDifference(reference, language, sample as NSString)
        }
        for _ in 0..<400 where failure == nil {
            let text = (0..<Int.random(in: 1...50, using: &random))
                .map { _ in regexFuzzPieces.randomElement(using: &random)! }.joined() as NSString
            failure = lexerDifference(reference, language, text)
        }
        check("\(language.name): gleiche Tokens mit \(language.captureGroupCount) statt \(reference.captureGroupCount) Gruppen",
              failure == nil, failure ?? "")
    }

    print("     Regex-Sprachen, 1 MB je Sprache (vorher → nachher):")
    for language in regexOnly {
        let sample = regexSamples[language.id] ?? mixed
        let text = String(repeating: sample, count: max(1, 1_000_000 / sample.utf8.count)) as NSString
        func milliseconds(_ language: SyntaxLanguage) -> Double {
            var best = Double.infinity
            for _ in 0..<2 {
                let start = Date()
                _ = language.tokens(in: text)
                best = min(best, Date().timeIntervalSince(start) * 1000)
            }
            return best * 1_000_000 / Double(text.length)
        }
        let before = milliseconds(language.withOneGroupPerRule())
        let after = milliseconds(language)
        print(String(format: "     %@ %2d → %d Gruppen  %6.0f → %6.0f ms/MB  (%.1f×)",
                     language.id.padding(toLength: 11, withPad: " ", startingAt: 0),
                     language.withOneGroupPerRule().captureGroupCount, language.captureGroupCount,
                     before, after, before / after))
    }
}
