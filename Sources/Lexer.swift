/*
 * Notepad für macOS – handgeschriebener Lexer für die Programmiersprachen.
 *
 * Ersetzt für Swift, C, Java, Kotlin, C#, Go, Rust, JavaScript, Python und Shell die große
 * Regex-Alternation (ICU) durch eine einzige Schleife über den UTF-16-Puffer – gleiche Tokens,
 * aber ein Vielfaches schneller.
 * LICENSE: LGPL-2.1-or-later
 */

import Foundation

/// The lexical rules of a programming language. Each flag reproduces one rule of the former
/// regex definitions exactly – including its quirks – so the tokens stay the same (the regex
/// originals live in Tests/LexerTests.swift, which compares both on many samples).
///
/// The lexer emulates the regex engine: at every position the rules are tried in the order
/// of the old alternation, and without a match it moves on by one code point. It keeps no
/// state between lexemes, so a scan can restart at any token end (incremental re-scans);
/// line-start (`^`), word-boundary (`\b`) and lookbehind checks only look back a few characters.
struct LexerSpec {
    enum SingleQuote {
        case none
        /// `'(?:[^'\\\n]|\\.)*'?` – like a double-quoted string.
        case string
        /// `'(?:[^'\\\n]|\\.{1,8}?)'` – one character or an escape of up to eight characters,
        /// closed. (The former regex used a greedy `.{1,8}`, which turned `'\n', 'x'` into one
        /// literal; the lexer ends at the first closing quote.)
        case charLiteral
        /// `'[^']*'?` – no escapes, may span lines (shell).
        case raw
    }

    /// `//…` and `/*…*/` (unterminated: to the end of the text).
    var slashComments = true
    /// `#…` anywhere (Python).
    var hashComments = false
    /// `#…` at line start or after a space, tab or `;` (shell).
    var shellComments = false
    /// `"""…"""`, unterminated to the end of the text.
    var tripleDoubleQuotes = false
    /// `'''…'''`, unterminated to the end of the text (Python).
    var tripleSingleQuotes = false
    /// Python string prefixes: one or two of `rRbBfFuU` at a word start, part of the token.
    var stringPrefixes = false
    var singleQuotes = SingleQuote.none
    /// `` `…` `` with backslash escapes, may span lines (Go, JavaScript).
    var backticks = false
    /// `@name` (attribute).
    var atAttributes = false
    /// Swift `#if`, `#available`, `#selector` … (attribute).
    var swiftDirectives = false
    /// `^[ \t]*#[ \t]*\w+` – preprocessor line start incl. its indentation (C, C#).
    var preprocessor = false
    /// `<path/file.h>` (C).
    var includePaths = false
    /// C# `@"…"` with `""` as escaped quote.
    var verbatimStrings = false
    /// Rust: raw strings `r#"…"#`, lifetimes `'a` (type), `#[attr]`, `name!` macros (attribute).
    var rust = false
    /// `^[ \t]*@[\w.]+` – Python decorators incl. indentation.
    var decorators = false
    /// `${…}`, `$NAME`, `$1`, `$@` … (variable).
    var shellVariables = false
}

/// Character classes of the regex engine for code points: `\w`, `\d` and the characters that
/// ICU's `\b` skips (grapheme extenders and format characters).
enum LexerUnicode {
    static let word: UInt8 = 1
    static let digit: UInt8 = 2
    static let skip: UInt8 = 4

    /// Classes of the BMP, taken from ICU itself so `\w`/`\d`/`\b` agree exactly with the
    /// regex rules. Built on first use (only text with non-ASCII characters needs it).
    private static let bmp: UnsafeMutablePointer<UInt8> = {
        let table = UnsafeMutablePointer<UInt8>.allocate(capacity: 0x10000)
        table.initialize(repeating: 0, count: 0x10000)
        var units = [UInt16](repeating: 0x20, count: 0x10000)
        for unit in 0..<0x10000 where unit < 0xD800 || unit > 0xDFFF { units[unit] = UInt16(unit) }
        let text = NSString(characters: units, length: units.count) as String
        let all = NSRange(location: 0, length: units.count)
        for (pattern, flag) in [(#"\w+"#, word), (#"\d+"#, digit), (#"[\p{Grapheme_Extend}\p{Cf}]+"#, skip)] {
            let regex = try! NSRegularExpression(pattern: pattern)
            regex.enumerateMatches(in: text, range: all) { match, _, _ in
                guard let range = match?.range else { return }
                for unit in range.location..<NSMaxRange(range) { table[unit] |= flag }
            }
        }
        return table
    }()

    static func flags(_ scalar: UInt32) -> UInt8 {
        if scalar < 0x10000 { return bmp[Int(scalar)] }
        guard let value = Unicode.Scalar(scalar) else { return 0 }
        let properties = value.properties
        var flags: UInt8 = properties.isAlphabetic ? word : 0
        switch properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark, .connectorPunctuation: flags |= word
        case .decimalNumber: flags |= word | digit
        case .format: flags |= skip
        default: break
        }
        if properties.isGraphemeExtend { flags |= skip }
        return flags
    }
}

/// Keywords and types of a language for lookups straight from the UTF-16 buffer
/// (open addressing, no String allocation per word).
final class LexerWords {
    private struct Slot {
        var start: Int32 = 0
        var length: Int16 = 0
        var kind: UInt8 = 0
    }

    let maxLength: Int
    private let capitalizedTypes: Bool
    private let suffix: [UInt16]
    private let mask: Int
    private let slots: UnsafeMutablePointer<Slot>
    private let pool: UnsafeMutablePointer<UInt16>

    static let none: UInt8 = 255

    init(keywords: Set<String>, types: Set<String>, capitalizedTypes: Bool, typeSuffix: String?) {
        self.capitalizedTypes = capitalizedTypes
        suffix = Array((typeSuffix ?? "").utf16)
        var entries: [([UInt16], TokenKind)] = keywords.sorted().map { (Array($0.utf16), .keyword) }
        entries += types.subtracting(keywords).sorted().map { (Array($0.utf16), .type) }
        maxLength = entries.map(\.0.count).max() ?? 0

        var capacity = 16
        while capacity < entries.count * 4 { capacity *= 2 }
        mask = capacity - 1
        slots = .allocate(capacity: capacity)
        slots.initialize(repeating: Slot(), count: capacity)
        let poolSize = entries.reduce(0) { $0 + $1.0.count }
        pool = .allocate(capacity: max(poolSize, 1))
        var offset = 0
        for (word, kind) in entries {
            (pool + offset).initialize(from: word, count: word.count)
            var index = word.withUnsafeBufferPointer { Self.hash($0.baseAddress!, word.count) } & mask
            while slots[index].length != 0 { index = (index + 1) & mask }
            slots[index] = Slot(start: Int32(offset), length: Int16(word.count), kind: kind.rawValue)
            offset += word.count
        }
    }

    deinit {
        slots.deallocate()
        pool.deallocate()
    }

    @inline(__always)
    private static func hash(_ word: UnsafePointer<UInt16>, _ length: Int) -> Int {
        var hash: UInt32 = 2_166_136_261
        for index in 0..<length { hash = (hash ^ UInt32(word[index])) &* 16_777_619 }
        return Int(hash ^ (hash >> 15))
    }

    /// Kind of an identifier (`TokenKind` raw value), or `none` for a plain word.
    @inline(__always)
    func classify(_ word: UnsafePointer<UInt16>, _ length: Int) -> UInt8 {
        if length <= maxLength {
            var index = Self.hash(word, length) & mask
            while true {
                let slot = slots[index]
                if slot.length == 0 { break }
                if Int(slot.length) == length {
                    let candidate = pool + Int(slot.start)
                    var same = true
                    for offset in 0..<length where candidate[offset] != word[offset] {
                        same = false
                        break
                    }
                    if same { return slot.kind }
                }
                index = (index + 1) & mask
            }
        }
        if capitalizedTypes && word[0] >= 0x41 && word[0] <= 0x5A { return TokenKind.type.rawValue }
        if !suffix.isEmpty && length >= suffix.count {
            let tail = word + (length - suffix.count)
            var same = true
            for offset in 0..<suffix.count where tail[offset] != suffix[offset] {
                same = false
                break
            }
            if same { return TokenKind.type.rawValue }
        }
        return Self.none
    }
}

/// ASCII character classes (bit masks), indexed by code unit < 0x80.
private enum ASCII {
    static let word: UInt16 = 1         // [A-Za-z0-9_] (same bit as LexerUnicode.word)
    static let digit: UInt16 = 2        // [0-9] (same bit as LexerUnicode.digit)
    static let letter: UInt16 = 8       // [A-Za-z]
    static let hex: UInt16 = 16         // [0-9a-fA-F_]
    static let dot: UInt16 = 32         // .
    static let pathPunct: UInt16 = 64   // . / + -
    static let underscore: UInt16 = 128
    static let prefix: UInt16 = 256     // [rRbBfFuU]
    static let identStart: UInt16 = 512 // [A-Za-z_]

    static let table: UnsafeMutablePointer<UInt16> = {
        let table = UnsafeMutablePointer<UInt16>.allocate(capacity: 128)
        table.initialize(repeating: 0, count: 128)
        func set(_ chars: String, _ flag: UInt16) {
            for unit in chars.utf16 { table[Int(unit)] |= flag }
        }
        let lower = "abcdefghijklmnopqrstuvwxyz", upper = lower.uppercased(), digits = "0123456789"
        set(lower + upper + digits + "_", word)
        set(digits, digit)
        set(lower + upper, letter)
        set(digits + "abcdefABCDEF_", hex)
        set(".", dot)
        set("./+-", pathPunct)
        set("_", underscore)
        set("rRbBfFuU", prefix)
        set(lower + upper + "_", identStart)
        return table
    }()
}

private let swiftDirectives: [[UInt16]] = [
    "if", "elseif", "else", "endif", "available", "unavailable", "selector", "keyPath", "warning", "error",
    "file", "fileID", "filePath", "line", "column", "function", "dsohandle", "sourceLocation", "Preview",
    "expect", "require",
].map { Array($0.utf16) }

/// Scans a UTF-16 buffer with the rules of a `LexerSpec`.
struct Lexer {
    private let s: UnsafePointer<UInt16>
    private let n: Int
    private let spec: LexerSpec
    private let words: LexerWords
    private let ascii: UnsafePointer<UInt16>

    init(_ buffer: UnsafePointer<UInt16>, count: Int, spec: LexerSpec, words: LexerWords) {
        s = buffer
        n = count
        self.spec = spec
        self.words = words
        ascii = UnsafePointer(ASCII.table)
    }

    private static let comment = TokenKind.comment.rawValue
    private static let string = TokenKind.string.rawValue
    private static let number = TokenKind.number.rawValue
    private static let attribute = TokenKind.attribute.rawValue
    private static let type = TokenKind.type.rawValue
    private static let variable = TokenKind.variable.rawValue

    /// Visits every lexeme from `start` on with its kind (`LexerWords.none` for plain words);
    /// `visit` returns false to stop. Returns false if cancelled.
    func scan(from start: Int, cancel: SyntaxCancellation?,
              visit: (_ location: Int, _ length: Int, _ kind: UInt8) -> Bool) -> Bool {
        var p = start
        var count = 0
        while p < n {
            let c = s[p]
            var kind: UInt8 = 0
            let end = c < 0x80 ? matchASCII(p, c, &kind) : matchOther(p, &kind)
            if end < 0 {
                p += isHigh(c) && p + 1 < n && isLow(s[p + 1]) ? 2 : 1
                continue
            }
            count += 1
            if count & 511 == 0, cancel?.isCancelled == true { return false }
            if !visit(p, end - p, kind) { return true }
            p = end
        }
        return true
    }

    // MARK: - Characters

    @inline(__always) private func isHigh(_ c: UInt16) -> Bool { c & 0xFC00 == 0xD800 }
    @inline(__always) private func isLow(_ c: UInt16) -> Bool { c & 0xFC00 == 0xDC00 }

    @inline(__always)
    private func scalar(_ high: UInt16, _ low: UInt16) -> UInt32 {
        0x10000 + ((UInt32(high) - 0xD800) << 10) + (UInt32(low) - 0xDC00)
    }

    /// Line terminators of ICU (`.` stops there, `^` matches after them).
    @inline(__always)
    private func isLineTerminator(_ c: UInt16) -> Bool {
        (c >= 0x0A && c <= 0x0D) || c == 0x85 || c == 0x2028 || c == 0x2029
    }

    @inline(__always)
    private func isLineStart(_ p: Int) -> Bool {
        p == 0 || isLineTerminator(s[p - 1])
    }

    /// Unicode flags and width of the (non-ASCII) code point starting at `i`.
    private func codePoint(at i: Int) -> (flags: UInt8, width: Int) {
        let c = s[i]
        if isHigh(c), i + 1 < n, isLow(s[i + 1]) {
            return (LexerUnicode.flags(scalar(c, s[i + 1])), 2)
        }
        return (LexerUnicode.flags(UInt32(c)), 1)
    }

    /// End of the run of characters from `i` matching `mask` (ASCII) or `unicode` (others).
    @inline(__always)
    private func run(_ i: Int, _ mask: UInt16, _ unicode: UInt8) -> Int {
        var i = i
        while i < n {
            let c = s[i]
            if c < 0x80 {
                if ascii[Int(c)] & mask == 0 { return i }
                i += 1
            } else {
                if unicode == 0 { return i }
                let (flags, width) = codePoint(at: i)
                if flags & unicode == 0 { return i }
                i += width
            }
        }
        return i
    }

    @inline(__always)
    private func wordRun(_ i: Int) -> Int { run(i, ASCII.word, LexerUnicode.word) }

    @inline(__always)
    private func isDigit(_ i: Int) -> Bool {
        guard i < n else { return false }
        let c = s[i]
        if c < 0x80 { return ascii[Int(c)] & ASCII.digit != 0 }
        return codePoint(at: i).flags & LexerUnicode.digit != 0
    }

    /// ICU's `\b`: the code point at `pos` (unless it is a grapheme extender or format
    /// character) and the one before it, skipping those, differ in being word characters.
    private func boundary(_ pos: Int) -> Bool {
        var isWord = false
        if pos < n {
            let c = s[pos]
            if c < 0x80 {
                isWord = ascii[Int(c)] & ASCII.word != 0
            } else {
                var value = UInt32(c)
                if isHigh(c), pos + 1 < n, isLow(s[pos + 1]) {
                    value = scalar(c, s[pos + 1])
                } else if isLow(c), pos > 0, isHigh(s[pos - 1]) {
                    value = scalar(s[pos - 1], c)
                }
                let flags = LexerUnicode.flags(value)
                if flags & LexerUnicode.skip != 0 { return false }
                isWord = flags & LexerUnicode.word != 0
            }
        }
        var wasWord = false
        var i = pos
        while i > 0 {
            let c = s[i - 1]
            if c < 0x80 {
                wasWord = ascii[Int(c)] & ASCII.word != 0
                break
            }
            i -= 1
            var value = UInt32(c)
            if isLow(c), i > 0, isHigh(s[i - 1]) {
                value = scalar(s[i - 1], c)
                i -= 1
            }
            let flags = LexerUnicode.flags(value)
            if flags & LexerUnicode.skip == 0 {
                wasWord = flags & LexerUnicode.word != 0
                break
            }
        }
        return isWord != wasWord
    }

    // MARK: - Dispatch

    @inline(__always)
    private func matchASCII(_ p: Int, _ c: UInt16, _ kind: inout UInt8) -> Int {
        switch c {
        case 0x41...0x5A, 0x61...0x7A, 0x5F:  // letters, _
            return word(p, c, &kind)
        case 0x30...0x39:
            if spec.rust, let end = macro(p) {
                kind = Self.attribute
                return end
            }
            if let end = number(p) {
                kind = Self.number
                return end
            }
            return -1
        case 0x2F:  // /
            guard spec.slashComments, p + 1 < n else { return -1 }
            kind = Self.comment
            if s[p + 1] == 0x2F { return lineEnd(p + 2) }
            if s[p + 1] == 0x2A { return blockCommentEnd(p + 2) }
            return -1
        case 0x22:  // "
            kind = Self.string
            if spec.tripleDoubleQuotes, p + 2 < n, s[p + 1] == 0x22, s[p + 2] == 0x22 {
                return tripleEnd(p + 3, 0x22)
            }
            return quotedEnd(p, 0x22)
        case 0x27:  // '
            return singleQuote(p, &kind)
        case 0x20, 0x09:  // indentation before a preprocessor line or decorator
            guard spec.preprocessor || spec.decorators, isLineStart(p) else { return -1 }
            return lineStartRule(p, &kind)
        case 0x23:  // #
            return hash(p, &kind)
        case 0x40:  // @
            if spec.verbatimStrings, p + 1 < n, s[p + 1] == 0x22 {
                kind = Self.string
                return verbatimEnd(p + 2)
            }
            if spec.atAttributes {
                let end = wordRun(p + 1)
                if end > p + 1 {
                    kind = Self.attribute
                    return end
                }
            }
            if spec.decorators, isLineStart(p) { return lineStartRule(p, &kind) }
            return -1
        case 0x60:  // `
            guard spec.backticks else { return -1 }
            kind = Self.string
            return backtickEnd(p + 1)
        case 0x3C:  // <
            guard spec.includePaths, let end = includePath(p) else { return -1 }
            kind = Self.string
            return end
        case 0x24:  // $
            guard spec.shellVariables, let end = variable(p) else { return -1 }
            kind = Self.variable
            return end
        default:
            return -1
        }
    }

    private func matchOther(_ p: Int, _ kind: inout UInt8) -> Int {
        let flags = codePoint(at: p).flags
        if spec.rust, flags & LexerUnicode.word != 0, let end = macro(p) {
            kind = Self.attribute
            return end
        }
        if flags & LexerUnicode.digit != 0, let end = number(p) {
            kind = Self.number
            return end
        }
        return -1
    }

    /// Letters and `_`: prefixed strings, raw strings and macros come before identifiers.
    @inline(__always)
    private func word(_ p: Int, _ c: UInt16, _ kind: inout UInt8) -> Int {
        if spec.stringPrefixes, ascii[Int(c)] & ASCII.prefix != 0, let end = prefixedString(p) {
            kind = Self.string
            return end
        }
        if spec.rust {
            if c == 0x72, let end = rawString(p) {  // r
                kind = Self.string
                return end
            }
        }
        var end = p + 1
        while end < n {
            let next = s[end]
            if next >= 0x80 || ascii[Int(next)] & ASCII.word == 0 { break }
            end += 1
        }
        if spec.rust, let macroEnd = macro(p, asciiEnd: end) {
            kind = Self.attribute
            return macroEnd
        }
        kind = words.classify(s + p, end - p)
        return end
    }

    // MARK: - Rules

    /// `[^\n]*`
    private func lineEnd(_ i: Int) -> Int {
        var i = i
        while i < n && s[i] != 0x0A { i += 1 }
        return i
    }

    /// `[\s\S]*?(?:\*/|\z)`
    private func blockCommentEnd(_ i: Int) -> Int {
        var i = i
        while i + 1 < n {
            if s[i] == 0x2A && s[i + 1] == 0x2F { return i + 2 }
            i += 1
        }
        return n
    }

    /// `[\s\S]*?(?:qqq|\z)`
    private func tripleEnd(_ i: Int, _ quote: UInt16) -> Int {
        var i = i
        while i + 2 < n {
            if s[i] == quote && s[i + 1] == quote && s[i + 2] == quote { return i + 3 }
            i += 1
        }
        return n
    }

    /// `q(?:[^q\\\n]|\\.)*q?` from the opening quote at `p`.
    private func quotedEnd(_ p: Int, _ quote: UInt16) -> Int {
        var i = p + 1
        while i < n {
            let c = s[i]
            if c == quote { return i + 1 }
            if c == 0x0A { return i }
            if c == 0x5C {
                guard i + 1 < n, !isLineTerminator(s[i + 1]) else { return i }
                i += 2
                continue
            }
            i += 1
        }
        return n
    }

    /// `` (?:[^`\\]|\\[\s\S])*`? `` after the opening backtick.
    private func backtickEnd(_ i: Int) -> Int {
        var i = i
        while i < n {
            let c = s[i]
            if c == 0x60 { return i + 1 }
            if c == 0x5C {
                guard i + 1 < n else { return i }
                i += 2
                continue
            }
            i += 1
        }
        return n
    }

    /// `(?:[^"]|"")*"?` after `@"`.
    private func verbatimEnd(_ i: Int) -> Int {
        var i = i
        while i < n {
            if s[i] == 0x22 {
                if i + 1 < n && s[i + 1] == 0x22 {
                    i += 2
                    continue
                }
                return i + 1
            }
            i += 1
        }
        return n
    }

    private func singleQuote(_ p: Int, _ kind: inout UInt8) -> Int {
        if spec.tripleSingleQuotes, p + 2 < n, s[p + 1] == 0x27, s[p + 2] == 0x27 {
            kind = Self.string
            return tripleEnd(p + 3, 0x27)
        }
        switch spec.singleQuotes {
        case .none:
            return -1
        case .string:
            kind = Self.string
            return quotedEnd(p, 0x27)
        case .raw:  // '[^']*'?
            kind = Self.string
            var i = p + 1
            while i < n && s[i] != 0x27 { i += 1 }
            return i < n ? i + 1 : n
        case .charLiteral:
            if let end = charLiteral(p) {
                kind = Self.string
                return end
            }
            if spec.rust, let end = lifetime(p) {
                kind = Self.type
                return end
            }
            return -1
        }
    }

    /// `'(?:[^'\\\n]|\\.{1,8}?)'` – the first closing quote within eight code points after
    /// the backslash ends the literal.
    private func charLiteral(_ p: Int) -> Int? {
        let q = p + 1
        guard q < n else { return nil }
        let c = s[q]
        if c == 0x5C {
            var i = q + 1
            for _ in 0..<8 {
                guard i < n, !isLineTerminator(s[i]) else { break }
                i += isHigh(s[i]) && i + 1 < n && isLow(s[i + 1]) ? 2 : 1
                if i < n && s[i] == 0x27 { return i + 1 }
            }
            return nil
        }
        if c == 0x27 || c == 0x0A { return nil }
        let i = q + (isHigh(c) && q + 1 < n && isLow(s[q + 1]) ? 2 : 1)
        return i < n && s[i] == 0x27 ? i + 1 : nil
    }

    /// Rust `'[A-Za-z_]\w*\b`.
    private func lifetime(_ p: Int) -> Int? {
        let q = p + 1
        guard q < n, s[q] < 0x80, ascii[Int(s[q])] & ASCII.identStart != 0 else { return nil }
        let end = wordRun(q + 1)
        return boundary(end) ? end : nil
    }

    /// Rust `r###"…"###` (up to three `#`, to the end of the text if open) and `r"[^"]*"?`.
    private func rawString(_ p: Int) -> Int? {
        for hashes in stride(from: 3, through: 1, by: -1) {
            let quote = p + 1 + hashes
            guard quote < n, s[quote] == 0x22 else { continue }
            var all = true
            for i in (p + 1)..<quote where s[i] != 0x23 { all = false }
            guard all else { continue }
            var i = quote + 1
            while i + hashes < n {
                if s[i] == 0x22 {
                    var closes = true
                    for k in 1...hashes where s[i + k] != 0x23 { closes = false }
                    if closes { return i + 1 + hashes }
                }
                i += 1
            }
            return n
        }
        guard p + 1 < n, s[p + 1] == 0x22 else { return nil }
        var i = p + 2
        while i < n && s[i] != 0x22 { i += 1 }
        return i < n ? i + 1 : n
    }

    /// Rust `\b\w+!`; `asciiEnd` is where the ASCII word characters from `p` end, if known.
    @inline(__always)
    private func macro(_ p: Int, asciiEnd: Int? = nil) -> Int? {
        var end = asciiEnd ?? p
        if end < n && s[end] >= 0x80 || asciiEnd == nil { end = wordRun(end) }
        guard end > p, end < n, s[end] == 0x21, boundary(p) else { return nil }
        return end + 1
    }

    /// Python `\b[rRbBfFuU]{1,2}` before a (triple) quoted string.
    private func prefixedString(_ p: Int) -> Int? {
        var q = p + 1
        if q < n, s[q] < 0x80, ascii[Int(s[q])] & ASCII.prefix != 0 { q += 1 }
        guard q < n else { return nil }
        let quote = s[q]
        guard quote == 0x22 || quote == 0x27, boundary(p) else { return nil }
        if q + 2 < n && s[q + 1] == quote && s[q + 2] == quote { return tripleEnd(q + 3, quote) }
        return quotedEnd(q, quote)
    }

    /// `^[ \t]*#[ \t]*\w+` (preprocessor) or `^[ \t]*@[\w.]+` (decorator); `p` is a line start.
    private func lineStartRule(_ p: Int, _ kind: inout UInt8) -> Int {
        var i = p
        while i < n && (s[i] == 0x20 || s[i] == 0x09) { i += 1 }
        guard i < n else { return -1 }
        if spec.preprocessor && s[i] == 0x23 {
            i += 1
            while i < n && (s[i] == 0x20 || s[i] == 0x09) { i += 1 }
            let end = wordRun(i)
            guard end > i else { return -1 }
            kind = Self.attribute
            return end
        }
        if spec.decorators && s[i] == 0x40 {
            let end = run(i + 1, ASCII.word | ASCII.dot, LexerUnicode.word)
            guard end > i + 1 else { return -1 }
            kind = Self.attribute
            return end
        }
        return -1
    }

    private func hash(_ p: Int, _ kind: inout UInt8) -> Int {
        if spec.preprocessor, isLineStart(p) {
            let end = lineStartRule(p, &kind)
            if end >= 0 { return end }
        }
        if spec.hashComments
            || spec.shellComments && (isLineStart(p) || s[p - 1] == 0x20 || s[p - 1] == 0x09 || s[p - 1] == 0x3B) {
            kind = Self.comment
            return lineEnd(p + 1)
        }
        if spec.swiftDirectives {
            for directive in swiftDirectives {
                let end = p + 1 + directive.count
                guard end <= n else { continue }
                var same = true
                for (k, unit) in directive.enumerated() where s[p + 1 + k] != unit {
                    same = false
                    break
                }
                if same && boundary(end) {
                    kind = Self.attribute
                    return end
                }
            }
        }
        if spec.rust {  // #!?\[[^\]\n]*\]
            var i = p + 1
            if i < n && s[i] == 0x21 { i += 1 }
            guard i < n, s[i] == 0x5B else { return -1 }
            i += 1
            while i < n && s[i] != 0x5D && s[i] != 0x0A { i += 1 }
            guard i < n, s[i] == 0x5D else { return -1 }
            kind = Self.attribute
            return i + 1
        }
        return -1
    }

    /// C `<[\w./+-]+\.h(?:h|pp|xx)?>`: the `>` must follow the whole run, which then has to
    /// end in `.h`, `.hh`, `.hpp` or `.hxx` with at least one character before.
    private func includePath(_ p: Int) -> Int? {
        let start = p + 1
        let end = run(start, ASCII.word | ASCII.pathPunct, LexerUnicode.word)
        guard end < n, s[end] == 0x3E else { return nil }
        for suffix in Self.headerSuffixes where end - start > suffix.count {
            var same = true
            for (k, unit) in suffix.enumerated() where s[end - suffix.count + k] != unit {
                same = false
                break
            }
            if same { return end + 1 }
        }
        return nil
    }

    private static let headerSuffixes: [[UInt16]] = [".h", ".hh", ".hpp", ".hxx"].map { Array($0.utf16) }

    /// `\$\{[^}\n]*\}|\$[A-Za-z_]\w*|\$[0-9@#?$!*-]`
    private func variable(_ p: Int) -> Int? {
        let q = p + 1
        guard q < n else { return nil }
        let c = s[q]
        if c == 0x7B {
            var i = q + 1
            while i < n && s[i] != 0x7D && s[i] != 0x0A { i += 1 }
            return i < n && s[i] == 0x7D ? i + 1 : nil
        }
        guard c < 0x80 else { return nil }
        if ascii[Int(c)] & ASCII.identStart != 0 { return wordRun(q + 1) }
        switch c {
        case 0x30...0x39, 0x40, 0x23, 0x3F, 0x24, 0x21, 0x2A, 0x2D: return q + 1  // 0-9 @ # ? $ ! * -
        default: return nil
        }
    }

    /// `[a-zA-Z]*`
    @inline(__always)
    private func letters(_ i: Int) -> Int {
        var i = i
        while i < n && s[i] < 0x80 && ascii[Int(s[i])] & ASCII.letter != 0 { i += 1 }
        return i
    }

    /// `\b(?:0[xX][0-9a-fA-F_]+|0[bB][01_]+|0[oO][0-7_]+|\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?)[a-zA-Z]*\b`
    ///
    /// Backtracking can only succeed where the run before the final `\b` is complete (a shorter
    /// run is followed by a word character), so it suffices to try the optional parts present
    /// and absent with maximal runs.
    private func number(_ p: Int) -> Int? {
        guard boundary(p) else { return nil }
        if s[p] == 0x30 && p + 1 < n {
            let marker = s[p + 1] | 0x20
            var end = p + 2
            switch marker {
            case 0x78:  // x
                end = run(end, ASCII.hex, 0)
            case 0x62:  // b
                while end < n && (s[end] == 0x30 || s[end] == 0x31 || s[end] == 0x5F) { end += 1 }
            case 0x6F:  // o
                while end < n && ((s[end] >= 0x30 && s[end] <= 0x37) || s[end] == 0x5F) { end += 1 }
            default:
                break
            }
            if end > p + 2 {
                let last = letters(end)
                if boundary(last) { return last }
            }
        }
        let digits = ASCII.digit | ASCII.underscore
        let integer = run(p, digits, LexerUnicode.digit)
        var fraction = -1
        if integer < n && s[integer] == 0x2E && isDigit(integer + 1) {
            fraction = run(integer + 1, digits, LexerUnicode.digit)
        }
        for attempt in 0..<2 {
            if attempt == 0 && fraction < 0 { continue }
            let mantissa = attempt == 0 ? fraction : integer
            if mantissa < n && (s[mantissa] == 0x65 || s[mantissa] == 0x45) {  // e E
                var i = mantissa + 1
                if i < n && (s[i] == 0x2B || s[i] == 0x2D) { i += 1 }
                if isDigit(i) {
                    let last = letters(run(i, ASCII.digit, LexerUnicode.digit))
                    if boundary(last) { return last }
                }
            }
            let last = letters(mantissa)
            if boundary(last) { return last }
        }
        return nil
    }
}
