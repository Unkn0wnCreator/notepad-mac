/*
 * Notepad für macOS – Syntaxhervorhebung.
 *
 * Farben werden als temporäre Attribute des Layout-Managers gesetzt: Sie ändern weder den
 * Text noch die Undo-Historie und landen nie in der gespeicherten Datei.
 * LICENSE: LGPL-2.1-or-later
 */

import AppKit

enum TokenKind: UInt8 {
    case comment, string, keyword, number, type, attribute, tag, property, variable

    private static func dynamic(light: UInt32, dark: UInt32) -> NSColor {
        func rgb(_ value: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                    green: CGFloat((value >> 8) & 0xFF) / 255,
                    blue: CGFloat(value & 0xFF) / 255, alpha: 1)
        }
        return NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? rgb(dark) : rgb(light)
        }
    }

    // Close to Xcode's default themes.
    private static let colors: [NSColor] = [
        dynamic(light: 0x5D6C79, dark: 0x7F8C98),  // comment
        dynamic(light: 0xC41A16, dark: 0xFC6A5D),  // string
        dynamic(light: 0x9B2393, dark: 0xFC5FA3),  // keyword
        dynamic(light: 0x1C00CF, dark: 0xD0BF69),  // number
        dynamic(light: 0x0B4F79, dark: 0x5DD8FF),  // type
        dynamic(light: 0x643820, dark: 0xFD8F3F),  // attribute
        dynamic(light: 0x0F68A0, dark: 0x41A1C0),  // tag
        dynamic(light: 0x326D74, dark: 0x67B7A4),  // property
        dynamic(light: 0x6C36A9, dark: 0xA167E6),  // variable
    ]

    var color: NSColor { Self.colors[Int(rawValue)] }
}

/// A colored range. Compact (12 bytes) because large files produce millions of them.
struct SyntaxToken: Equatable {
    var location: Int32
    var length: Int32
    var kind: TokenKind

    init(location: Int, length: Int, kind: TokenKind) {
        self.location = Int32(location)
        self.length = Int32(length)
        self.kind = kind
    }

    var range: NSRange { NSRange(location: Int(location), length: Int(length)) }
    var end: Int { Int(location) + Int(length) }
}

/// Set from the main thread when newer text makes a running tokenization pointless.
final class SyntaxCancellation {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

/// Text changed since the last tokenization, in current coordinates: `start..<end` is new,
/// everything after `end` is old text shifted by `delta`.
struct SyntaxEdit: Equatable {
    var start: Int
    var end: Int
    var delta: Int

    init(editedRange: NSRange, delta: Int) {
        start = editedRange.location
        end = NSMaxRange(editedRange)
        self.delta = delta
    }

    mutating func merge(editedRange: NSRange, delta change: Int) {
        let editEnd = NSMaxRange(editedRange)
        let replacedEnd = editEnd - change  // end of the replaced text before this edit
        let shiftedEnd = end >= replacedEnd ? end + change : editEnd
        start = min(start, editedRange.location)
        end = max(shiftedEnd, editEnd)
        delta += change
    }
}

final class SyntaxLanguage {
    let id: String
    let name: String
    let extensions: Set<String>
    let fileNames: Set<String>

    private let pattern: String
    private let options: NSRegularExpression.Options
    /// Kind per capture group; nil marks the identifier group, classified by word lists.
    private let kinds: [TokenKind?]
    private let identifierGroup: Int?
    private let keywords: Set<String>
    private let types: Set<String>
    private let maxWordLength: Int
    private let capitalizedTypes: Bool
    private let typeSuffix: String?
    private let caseInsensitive: Bool

    private let lock = NSLock()
    private var compiled: NSRegularExpression?

    /// Rules are combined into one alternation and matched left to right, so whatever starts
    /// first wins (e.g. "//" inside a string stays part of the string). Patterns must not
    /// contain capturing groups and must never match an empty string.
    ///
    /// Words are not matched by huge regex alternations: one identifier rule is appended and
    /// each word is looked up in `keywords`/`types`, which is several times faster.
    init(id: String, name: String, extensions: [String], fileNames: [String] = [],
         caseInsensitive: Bool = false, keywords: String = "", types: String = "",
         capitalizedTypes: Bool = false, typeSuffix: String? = nil, rules: [(TokenKind, String)]) {
        self.id = id
        self.name = name
        self.extensions = Set(extensions)
        self.fileNames = Set(fileNames.map { $0.lowercased() })
        self.caseInsensitive = caseInsensitive
        func words(_ list: String) -> Set<String> {
            Set(list.split(separator: " ").map { caseInsensitive ? $0.lowercased() : String($0) })
        }
        self.keywords = words(keywords)
        self.types = words(types)
        maxWordLength = (self.keywords.union(self.types).map { ($0 as NSString).length }.max() ?? 0)
        self.capitalizedTypes = capitalizedTypes
        self.typeSuffix = typeSuffix

        var patterns = rules.map(\.1)
        var kinds: [TokenKind?] = rules.map(\.0)
        if !self.keywords.isEmpty || !self.types.isEmpty || capitalizedTypes || typeSuffix != nil {
            patterns.append("[A-Za-z_][A-Za-z0-9_]*")
            kinds.append(nil)
            identifierGroup = kinds.count
        } else {
            identifierGroup = nil
        }
        self.kinds = kinds
        pattern = patterns.map { "(\($0))" }.joined(separator: "|")
        var options: NSRegularExpression.Options = [.anchorsMatchLines]
        if caseInsensitive { options.insert(.caseInsensitive) }
        self.options = options
    }

    /// Compiled on first use (keeps app launch fast); thread-safe.
    var regex: NSRegularExpression {
        lock.lock()
        defer { lock.unlock() }
        if let compiled { return compiled }
        let regex = try! NSRegularExpression(pattern: pattern, options: options)
        compiled = regex
        return regex
    }

    private func classify(_ range: NSRange, in text: NSString) -> TokenKind? {
        if range.length <= maxWordLength {
            var word = text.substring(with: range)
            if caseInsensitive { word = word.lowercased() }
            if keywords.contains(word) { return .keyword }
            if types.contains(word) { return .type }
        }
        if capitalizedTypes {
            let first = text.character(at: range.location)
            if first >= 0x41 && first <= 0x5A { return .type }
        }
        if let typeSuffix, text.substring(with: range).hasSuffix(typeSuffix) {
            return .type
        }
        return nil
    }

    /// Scans `text` (whose index 0 is document offset `offset`) from document offset `from`.
    /// `visit` gets every match in document coordinates with its kind (nil for plain words)
    /// and returns false to stop. Returns false if cancelled.
    private func scan(_ text: NSString, offset: Int, from: Int, cancel: SyntaxCancellation?,
                      visit: (_ range: NSRange, _ kind: TokenKind?) -> Bool) -> Bool {
        let regex = regex
        let groupCount = kinds.count
        var matches = 0
        var cancelled = false
        let range = NSRange(location: from - offset, length: text.length - (from - offset))
        regex.enumerateMatches(in: text as String, options: [.withTransparentBounds, .withoutAnchoringBounds],
                               range: range) { match, _, stop in
            guard let match else { return }
            matches += 1
            if matches & 511 == 0, cancel?.isCancelled == true {
                cancelled = true
                stop.pointee = true
                return
            }
            var kind: TokenKind?
            var matched = match.range
            if let identifierGroup, match.range(at: identifierGroup).location != NSNotFound {
                kind = classify(matched, in: text)
            } else {
                for group in 1...groupCount where group != identifierGroup {
                    let groupRange = match.range(at: group)
                    if groupRange.location != NSNotFound {
                        kind = kinds[group - 1]
                        matched = groupRange
                        break
                    }
                }
            }
            matched.location += offset
            if !visit(matched, kind) { stop.pointee = true }
        }
        return !cancelled
    }

    /// All tokens of `text`; nil if cancelled. `progress` is called now and then with the
    /// tokens so far and the offset up to which they are final.
    func tokens(in text: NSString, cancel: SyntaxCancellation? = nil,
                progress: ((_ tokens: [SyntaxToken], _ finalUpTo: Int) -> Void)? = nil) -> [SyntaxToken]? {
        var tokens: [SyntaxToken] = []
        var nextReport = 65_536  // the beginning of a file gets colored right away
        let finished = scan(text, offset: 0, from: 0, cancel: cancel) { range, kind in
            if let kind, range.length > 0 {
                tokens.append(SyntaxToken(location: range.location, length: range.length, kind: kind))
            }
            if let progress, range.location >= nextReport {
                progress(tokens, range.location)
                nextReport = range.location * 2  // geometric, so copying stays O(n) overall
            }
            return true
        }
        return finished ? tokens : nil
    }

    enum Retokenized {
        case tokens([SyntaxToken])
        /// The window ended before old and new tokens lined up again.
        case needsMoreText
        case cancelled
    }

    /// Re-scans only around an edit. `window` holds the document text from `windowStart`;
    /// scanning starts at `restart` (end of old token `prefixCount - 1`, unaffected by the
    /// edit) and stops as soon as a new token equals a shifted old token after the edit:
    /// from there on the scan would repeat exactly as before.
    func retokenize(window: NSString, windowStart: Int, documentLength: Int, restart: Int,
                    old: [SyntaxToken], prefixCount: Int, edit: SyntaxEdit,
                    cancel: SyntaxCancellation?) -> Retokenized {
        let windowEnd = windowStart + window.length
        let reachesEnd = windowEnd >= documentLength
        let resyncFrom = edit.end + 16  // lookbehind/\b/^ only look a few characters back
        var fresh: [SyntaxToken] = []
        var resyncIndex: Int?
        var hitWindowEnd = false

        let finished = scan(window, offset: windowStart, from: restart, cancel: cancel) { range, kind in
            if !reachesEnd && NSMaxRange(range) > windowEnd - 1024 {
                hitWindowEnd = true
                return false
            }
            guard let kind, range.length > 0 else { return true }
            let token = SyntaxToken(location: range.location, length: range.length, kind: kind)
            if range.location >= resyncFrom {
                let oldLocation = range.location - edit.delta
                if let index = Self.index(of: oldLocation, in: old),
                   old[index].length == token.length, old[index].kind == kind {
                    resyncIndex = index
                    return false
                }
            }
            fresh.append(token)
            return true
        }
        guard finished else { return .cancelled }

        var result = Array(old[..<prefixCount])
        result.reserveCapacity(prefixCount + fresh.count + (resyncIndex.map { old.count - $0 } ?? 0))
        result += fresh
        if let resyncIndex {
            let delta = Int32(edit.delta)
            for var token in old[resyncIndex...] {
                token.location += delta
                result.append(token)
            }
            return .tokens(result)
        }
        if hitWindowEnd { return .needsMoreText }
        return .tokens(result)
    }

    /// Where an incremental re-scan starts and which text it needs: two lines above the edit
    /// (lookaheads of earlier tokens may reach into it), at the end of an unaffected old token.
    struct RescanPlan {
        var prefixCount: Int
        var restart: Int
        var window: NSRange
    }

    static func rescanPlan(old: [SyntaxToken], text: NSString, edit: SyntaxEdit, windowSize: Int) -> RescanPlan {
        let editLine = LineScanner.lineStart(of: min(edit.start, text.length), in: text)
        let anchor = editLine > 0 ? LineScanner.lineStart(of: editLine - 1, in: text) : 0
        let prefixCount = countEnding(atOrBefore: anchor, in: old)
        let restart = prefixCount > 0 ? old[prefixCount - 1].end : 0
        let windowStart = max(0, restart - 64)
        let windowEnd = min(text.length, edit.end + windowSize)
        return RescanPlan(prefixCount: prefixCount, restart: restart,
                          window: NSRange(location: windowStart, length: windowEnd - windowStart))
    }

    /// Index of the token starting exactly at `location` (binary search).
    private static func index(of location: Int, in tokens: [SyntaxToken]) -> Int? {
        var low = 0, high = tokens.count
        while low < high {
            let mid = (low + high) / 2
            if Int(tokens[mid].location) < location { low = mid + 1 } else { high = mid }
        }
        return low < tokens.count && Int(tokens[low].location) == location ? low : nil
    }

    /// Number of tokens that end at or before `location` (tokens are sorted and disjoint).
    static func countEnding(atOrBefore location: Int, in tokens: [SyntaxToken]) -> Int {
        var low = 0, high = tokens.count
        while low < high {
            let mid = (low + high) / 2
            if tokens[mid].end <= location { low = mid + 1 } else { high = mid }
        }
        return low
    }

    static func named(_ id: String) -> SyntaxLanguage? {
        all.first { $0.id == id }
    }

    /// Picks a language from the file name, a shebang line or an XML/HTML header.
    /// `sample` is the beginning of the text (a few KB are enough).
    static func detect(fileName: String?, sample: NSString) -> SyntaxLanguage? {
        if let fileName, let language = detectConfig(path: fileName.lowercased(), sample: sample) {
            return language
        }
        if let fileName {
            let lower = (fileName.lowercased() as NSString).lastPathComponent
            if let language = all.first(where: { $0.fileNames.contains(lower) }) {
                return language
            }
            let ext = (lower as NSString).pathExtension
            if !ext.isEmpty, let language = all.first(where: { $0.extensions.contains(ext) }) {
                return language
            }
        }

        let firstLine = sample.substring(with: sample.lineRange(for: NSRange(location: 0, length: 0))).lowercased()
        if firstLine.hasPrefix("#!") {
            if firstLine.contains("python") { return named("python") }
            if firstLine.contains("node") || firstLine.contains("deno") || firstLine.contains("bun") { return named("javascript") }
            if firstLine.contains("sh") { return named("shell") }
        }
        if firstLine.hasPrefix("<?xml") { return named("xml") }
        if firstLine.hasPrefix("<!doctype html") || firstLine.hasPrefix("<html") { return named("html") }
        return nil
    }

    // MARK: - Languages

    private enum P {
        static let slashComment = #"//[^\n]*"#
        static let blockComment = #"/\*[\s\S]*?(?:\*/|\z)"#
        static let hashComment = #"#[^\n]*"#
        static let hashCommentAfterSpace = #"(?:^|(?<=[ \t;]))#[^\n]*"#
        static let dqString = #""(?:[^"\\\n]|\\.)*"?"#
        static let sqString = #"'(?:[^'\\\n]|\\.)*'?"#
        static let sqStringClosed = #"'(?:[^'\\\n]|\\.)*'"#
        static let charLiteral = #"'(?:[^'\\\n]|\\.{1,8})'"#
        static let backtickString = #"`(?:[^`\\]|\\[\s\S])*`?"#
        static let tripleDq = #""{3}[\s\S]*?(?:"{3}|\z)"#
        static let number = #"\b(?:0[xX][0-9a-fA-F_]+|0[bB][01_]+|0[oO][0-7_]+|\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?)[a-zA-Z]*\b"#
    }

    static let all: [SyntaxLanguage] = programmingLanguages + configLanguages

    private static let programmingLanguages: [SyntaxLanguage] = [
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
        SyntaxLanguage(id: "batch", name: "Batch (Windows)", extensions: ["bat", "cmd"], caseInsensitive: true,
                       keywords: "echo set if else goto call exit for in do not exist defined errorlevel equ neq lss leq gtr geq setlocal endlocal enabledelayedexpansion shift pause cls start pushd popd cd copy move del mkdir rmdir title off on nul", rules: [
            (.comment, #"^[ \t]*@?(?:rem\b|::)[^\n]*"#),
            (.tag, #"^[ \t]*:[A-Za-z_]\w*"#),
            (.string, P.dqString),
            (.variable, #"%%~?\w|%~?[0-9*]|%[\w]+%|![\w]+!"#),
            (.number, P.number),
        ]),
        SyntaxLanguage(id: "html", name: "HTML", extensions: ["html", "htm", "xhtml", "vue"], rules: htmlRules),
        SyntaxLanguage(id: "xml", name: "XML", extensions: ["xml", "plist", "svg", "xsd", "xsl", "xslt", "xib", "storyboard", "csproj", "resx", "rss", "atom"], rules: htmlRules),
        SyntaxLanguage(id: "css", name: "CSS", extensions: ["css", "scss", "sass", "less"], rules: [
            (.comment, P.blockComment), (.comment, P.slashComment),
            (.string, P.dqString), (.string, P.sqString),
            (.attribute, #"@[\w-]+"#),
            (.number, #"#[0-9a-fA-F]{3,8}\b"#),
            (.property, #"[\w-]+(?=[ \t]*:[^;{}\n]*;)"#),
            (.tag, #"[.#][A-Za-z_][\w-]*"#),
            (.keyword, #"!important\b"#),
            (.number, P.number),
        ]),
        SyntaxLanguage(id: "json", name: "JSON", extensions: ["json", "jsonc", "json5", "geojson", "webmanifest"],
                       keywords: "true false null", rules: [
            (.comment, P.slashComment), (.comment, P.blockComment),
            (.property, #""(?:[^"\\\n]|\\.)*"(?=\s*:)"#),
            (.string, P.dqString),
            (.number, #"-?"# + P.number),
        ]),
        SyntaxLanguage(id: "markdown", name: "Markdown", extensions: ["md", "markdown", "mdown", "mkd"], rules: [
            (.string, #"^[ \t]*```[\s\S]*?(?:^[ \t]*```[^\n]*$|\z)"#),
            (.comment, #"<!--[\s\S]*?(?:-->|\z)"#),
            (.tag, #"^#{1,6}[ \t].*$"#),
            (.comment, #"^[ \t]*>.*$"#),
            (.comment, #"^[ \t]*(?:-{3,}|\*{3,}|_{3,})[ \t]*$"#),
            (.attribute, #"^[ \t]*(?:[-*+]|\d+[.)])(?=[ \t])"#),
            (.string, #"`[^`\n]+`"#),
            (.variable, #"!?\[[^\]\n]*\]\([^)\n]*\)"#),
            (.keyword, #"\*\*[^*\n]+\*\*|__[^_\n]+__"#),
            (.type, #"(?<![*\w])\*[^*\n]+\*(?!\*)|(?<![_\w])_[^_\n]+_(?![_\w])"#),
        ]),
        SyntaxLanguage(id: "yaml", name: "YAML", extensions: ["yml", "yaml"],
                       keywords: "true false yes no on off null True False Null TRUE FALSE NULL", rules: [
            (.comment, P.hashCommentAfterSpace),
            (.attribute, #"^(?:---|\.\.\.)[ \t]*$"#),
            (.string, P.dqString), (.string, #"'(?:[^'\n]|'')*'"#),
            (.property, #"[\w.\-/]+(?=:(?:[ \t]|$))"#),
            (.variable, #"[&*][\w-]+"#),
            (.attribute, #"!!?\w+"#),
            (.number, P.number),
        ]),
        SyntaxLanguage(id: "ini", name: "INI / Konfiguration",
                       extensions: ["ini", "cfg", "conf", "cnf", "properties", "editorconfig", "gitconfig"],
                       fileNames: [".gitconfig", ".editorconfig", ".npmrc", ".gitattributes"],
                       keywords: "true false yes no on off", rules: [
            (.comment, #"^[ \t]*[;#][^\n]*"#),
            (.tag, #"^[ \t]*\[\[?[^\]\n]*\]\]?"#),
            (.property, #"^[ \t]*[\w.\-]+(?=[ \t]*[=:])"#),
            (.string, P.dqString), (.string, P.sqStringClosed),
            (.number, P.number),
        ]),
        SyntaxLanguage(id: "sql", name: "SQL", extensions: ["sql"], caseInsensitive: true,
                       keywords: "select from where and or not insert into values update set delete create table drop alter add column index view primary key foreign references join inner left right outer full on as group by order having limit offset distinct union all null is in like between exists case when then else end begin commit rollback transaction if default unique check constraint integer int varchar text char boolean date timestamp float double decimal real serial bigint smallint asc desc count sum avg min max returning with recursive replace trigger function procedure return returns declare cascade", rules: [
            (.comment, #"--[^\n]*"#), (.comment, P.blockComment),
            (.string, #"'(?:[^']|'')*'?"#),
            (.property, #""[^"\n]*"|`[^`\n]*`"#),
            (.number, P.number),
        ]),
        SyntaxLanguage(id: "makefile", name: "Makefile", extensions: ["mk", "make"],
                       fileNames: ["makefile", "gnumakefile"], rules: [
            (.comment, P.hashComment),
            (.variable, #"\$[({][^)}\n]*[)}]|\$[\w@<^?*%]"#),
            (.keyword, #"^[ \t]*(?:ifeq|ifneq|ifdef|ifndef|else|endif|include|-include|define|endef|export|override|\.PHONY)\b"#),
            (.tag, #"^[\w./%-]+(?=[ \t]*::?(?!=))"#),
            (.string, P.dqString), (.string, P.sqStringClosed),
        ]),
        SyntaxLanguage(id: "dockerfile", name: "Dockerfile", extensions: ["dockerfile"],
                       fileNames: ["dockerfile", "containerfile"], caseInsensitive: true, rules: [
            (.comment, #"^[ \t]*#[^\n]*"#),
            (.keyword, #"^[ \t]*(?:FROM|RUN|CMD|LABEL|EXPOSE|ENV|ADD|COPY|ENTRYPOINT|VOLUME|USER|WORKDIR|ARG|ONBUILD|STOPSIGNAL|HEALTHCHECK|SHELL|MAINTAINER)\b"#),
            (.keyword, #"\bAS\b"#),
            (.variable, #"\$\{[^}\n]*\}|\$\w+"#),
            (.string, P.dqString), (.string, P.sqStringClosed),
            (.number, P.number),
        ]),
    ]

    private static var htmlRules: [(TokenKind, String)] {
        [
            (.comment, #"<!--[\s\S]*?(?:-->|\z)"#),
            (.string, #"<!\[CDATA\[[\s\S]*?(?:\]\]>|\z)"#),
            (.attribute, #"<[!?][^>\n]*>?"#),
            (.tag, #"</?[A-Za-z][\w:.-]*|/?>"#),
            (.property, #"\b[A-Za-z_:][\w:.-]*(?=\s*=\s*["'])"#),
            (.string, #"(?<==)\s*"[^"]*"|(?<==)\s*'[^']*'"#),
            (.attribute, #"&#?\w+;"#),
        ]
    }
}

/// Colors a text view. Tokenizing runs on a background queue: after an edit only the text
/// around it is re-scanned (see `SyntaxLanguage.retokenize`), and only the visible part plus
/// a margin is colored on the main thread – the rest when it scrolls into view.
final class SyntaxHighlighter {
    /// Larger documents stay uncolored (tokens use 32-bit offsets anyway).
    static let maxLength = 50_000_000
    /// Characters colored above and below the visible area.
    private static let margin = 10_000
    /// Text copied for an incremental re-scan beyond the edit before falling back to all of it.
    private static let windowSize = 65_536

    private weak var textView: NSTextView?
    private let queue = DispatchQueue(label: "notepad.syntax-highlighting", qos: .userInitiated)
    private var generation = 0
    private var pending: DispatchWorkItem?
    private var running: SyntaxCancellation?

    /// Tokens sorted by location; final up to `finalUpTo` for the text at `tokensGeneration`.
    private var tokens: [SyntaxToken] = []
    private var finalUpTo = 0
    private var complete = false
    /// Edits since `tokens` were complete; nil means they match the text.
    private var edit: SyntaxEdit?
    private var coloredRange = NSRange(location: 0, length: 0)
    private var isStale = false

    var language: SyntaxLanguage? {
        didSet {
            if oldValue !== language { refresh() }
        }
    }

    var isEnabled = true {
        didSet {
            if oldValue != isEnabled { refresh() }
        }
    }

    init(textView: NSTextView, scrollView: NSScrollView) {
        self.textView = textView
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(didScroll(_:)),
                                               name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
    }

    deinit {
        running?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    /// Stops background work for good (window closed).
    func cancel() {
        isClosed = true
        pending?.cancel()
        running?.cancel()
    }

    private var isClosed = false

    /// Called from NSTextStorageDelegate for every character edit.
    func textChanged(editedRange: NSRange, delta: Int) {
        generation += 1
        isStale = true
        if complete {
            if edit == nil {
                edit = SyntaxEdit(editedRange: editedRange, delta: delta)
            } else {
                edit!.merge(editedRange: editedRange, delta: delta)
            }
        }
        running?.cancel()
        schedule(after: 0.02)
    }

    /// Forgets all tokens and scans everything again (new language, new text, toggled on/off).
    func refresh() {
        generation += 1
        isStale = true
        tokens = []
        finalUpTo = 0
        complete = false
        edit = nil
        running?.cancel()
        schedule(after: 0)
    }

    private func schedule(after delay: TimeInterval) {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.tokenize() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func tokenize() {
        guard !isClosed, let textView, let storage = textView.textStorage else { return }
        guard isEnabled, let language, storage.length <= Self.maxLength else {
            tokens = []
            complete = false
            edit = nil
            textView.layoutManager?.removeTemporaryAttribute(.foregroundColor,
                                                            forCharacterRange: NSRange(location: 0, length: storage.length))
            return
        }

        let cancel = SyntaxCancellation()
        running = cancel
        let expected = generation
        let text = textView.plainText

        if complete, let edit, !tokens.isEmpty {
            let plan = SyntaxLanguage.rescanPlan(old: tokens, text: text, edit: edit, windowSize: Self.windowSize)
            let window = text.substring(with: plan.window) as NSString
            let old = tokens
            let documentLength = text.length

            queue.async { [weak self] in
                let result = language.retokenize(window: window, windowStart: plan.window.location,
                                                 documentLength: documentLength, restart: plan.restart, old: old,
                                                 prefixCount: plan.prefixCount, edit: edit, cancel: cancel)
                DispatchQueue.main.async {
                    guard let self, self.generation == expected else { return }
                    switch result {
                    case .tokens(let tokens):
                        self.finish(tokens)
                    case .needsMoreText:
                        // The edit changed a lot (e.g. opened a block comment): scan everything.
                        self.complete = false
                        self.edit = nil
                        self.tokenize()
                    case .cancelled:
                        break
                    }
                }
            }
            return
        }

        complete = false
        edit = nil
        let snapshot = text.copy() as! NSString
        queue.async { [weak self] in
            let result = language.tokens(in: snapshot, cancel: cancel) { partial, upTo in
                DispatchQueue.main.async {
                    guard let self, self.generation == expected else { return }
                    self.tokens = partial
                    self.finalUpTo = upTo
                    self.isStale = false
                    self.coloredRange = NSRange(location: 0, length: 0)
                    self.colorVisibleRange()
                }
            }
            guard let result else { return }
            DispatchQueue.main.async {
                guard let self, self.generation == expected else { return }
                self.finish(result)
            }
        }
    }

    /// All tokens match the current text (used by tests).
    var isUpToDate: Bool { complete && !isStale && edit == nil }

    private func finish(_ tokens: [SyntaxToken]) {
        self.tokens = tokens
        finalUpTo = Int.max
        complete = true
        edit = nil
        isStale = false
        coloredRange = NSRange(location: 0, length: 0)
        colorVisibleRange()
    }

    @objc private func didScroll(_ notification: Notification) {
        colorVisibleRange()
    }

    private func colorVisibleRange() {
        // After an edit the token offsets are stale until the next scan finishes; the layout
        // manager keeps the old colors shifted along with the text meanwhile.
        guard !isStale, let textView, let layoutManager = textView.layoutManager,
              let container = textView.textContainer, let storage = textView.textStorage else { return }

        let glyphs = layoutManager.glyphRange(forBoundingRect: textView.visibleRect, in: container)
        let visible = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        if coloredRange.length > 0 && NSIntersectionRange(visible, coloredRange) == visible {
            return
        }

        let start = max(0, visible.location - Self.margin)
        let end = min(storage.length, NSMaxRange(visible) + Self.margin, finalUpTo)
        guard end > start else { return }
        let target = NSRange(location: start, length: end - start)
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: target)

        var index = SyntaxLanguage.countEnding(atOrBefore: start, in: tokens)
        while index < tokens.count && Int(tokens[index].location) < end {
            let token = tokens[index]
            if token.end <= storage.length {
                layoutManager.addTemporaryAttribute(.foregroundColor, value: token.kind.color, forCharacterRange: token.range)
            }
            index += 1
        }
        coloredRange = target
    }
}
