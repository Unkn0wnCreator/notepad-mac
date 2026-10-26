/*
 * Notepad für macOS – Syntaxhervorhebung.
 *
 * Farben werden als temporäre Attribute des Layout-Managers gesetzt: Sie ändern weder den
 * Text noch die Undo-Historie und landen nie in der gespeicherten Datei.
 * LICENSE: LGPL-2.1-or-later
 */

import AppKit

enum TokenKind {
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
    private static let colors: [TokenKind: NSColor] = [
        .comment: dynamic(light: 0x5D6C79, dark: 0x7F8C98),
        .string: dynamic(light: 0xC41A16, dark: 0xFC6A5D),
        .keyword: dynamic(light: 0x9B2393, dark: 0xFC5FA3),
        .number: dynamic(light: 0x1C00CF, dark: 0xD0BF69),
        .type: dynamic(light: 0x0B4F79, dark: 0x5DD8FF),
        .attribute: dynamic(light: 0x643820, dark: 0xFD8F3F),
        .tag: dynamic(light: 0x0F68A0, dark: 0x41A1C0),
        .property: dynamic(light: 0x326D74, dark: 0x67B7A4),
        .variable: dynamic(light: 0x6C36A9, dark: 0xA167E6),
    ]

    var color: NSColor { Self.colors[self]! }
}

struct SyntaxLanguage {
    let id: String
    let name: String
    let extensions: Set<String>
    let fileNames: Set<String>
    private let regex: NSRegularExpression
    private let kinds: [TokenKind]

    /// Rules are combined into one alternation and matched left to right, so whatever starts
    /// first wins (e.g. "//" inside a string stays part of the string). Patterns must not
    /// contain capturing groups.
    init(id: String, name: String, extensions: [String], fileNames: [String] = [],
         caseInsensitive: Bool = false, rules: [(TokenKind, String)]) {
        self.id = id
        self.name = name
        self.extensions = Set(extensions)
        self.fileNames = Set(fileNames.map { $0.lowercased() })
        kinds = rules.map(\.0)
        var options: NSRegularExpression.Options = [.anchorsMatchLines]
        if caseInsensitive { options.insert(.caseInsensitive) }
        let pattern = rules.map { "(\($0.1))" }.joined(separator: "|")
        regex = try! NSRegularExpression(pattern: pattern, options: options)
    }

    func tokens(in text: NSString) -> [(range: NSRange, kind: TokenKind)] {
        var tokens: [(range: NSRange, kind: TokenKind)] = []
        regex.enumerateMatches(in: text as String, range: NSRange(location: 0, length: text.length)) { match, _, _ in
            guard let match else { return }
            for (index, kind) in kinds.enumerated() {
                let range = match.range(at: index + 1)
                if range.location != NSNotFound {
                    if range.length > 0 { tokens.append((range, kind)) }
                    break
                }
            }
        }
        return tokens
    }

    static func named(_ id: String) -> SyntaxLanguage? {
        all.first { $0.id == id }
    }

    /// Picks a language from the file name, a shebang line or an XML/HTML header.
    static func detect(fileName: String?, firstLine: String) -> SyntaxLanguage? {
        if let fileName {
            let lower = fileName.lowercased()
            if let language = all.first(where: { $0.fileNames.contains(lower) }) {
                return language
            }
            let ext = (lower as NSString).pathExtension
            if !ext.isEmpty, let language = all.first(where: { $0.extensions.contains(ext) }) {
                return language
            }
        }

        let line = firstLine.lowercased()
        if line.hasPrefix("#!") {
            if line.contains("python") { return named("python") }
            if line.contains("node") || line.contains("deno") || line.contains("bun") { return named("javascript") }
            if line.contains("sh") { return named("shell") }
        }
        if line.hasPrefix("<?xml") { return named("xml") }
        if line.hasPrefix("<!doctype html") || line.hasPrefix("<html") { return named("html") }
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
        static let capitalizedType = #"\b[A-Z][A-Za-z0-9_]*\b"#

        static func words(_ list: String) -> String {
            #"\b(?:"# + list.split(separator: " ").joined(separator: "|") + #")\b"#
        }
    }

    static let all: [SyntaxLanguage] = [
        SyntaxLanguage(id: "swift", name: "Swift", extensions: ["swift"], rules: [
            (.comment, P.slashComment), (.comment, P.blockComment),
            (.string, P.tripleDq), (.string, P.dqString),
            (.attribute, #"@\w+"#),
            (.attribute, #"#(?:if|elseif|else|endif|available|unavailable|selector|keyPath|warning|error|file|fileID|filePath|line|column|function|dsohandle|sourceLocation|Preview|expect|require)\b"#),
            (.keyword, P.words("associatedtype class deinit enum extension fileprivate func import init inout internal let open operator private precedencegroup protocol public rethrows static struct subscript typealias var break case catch continue default defer do else fallthrough for guard if in repeat return throw switch where while as Any false is nil self Self super throws true try async await actor nonisolated isolated some any lazy weak unowned override mutating nonmutating final required convenience dynamic optional get set willSet didSet macro consuming borrowing package sending")),
            (.type, P.capitalizedType), (.number, P.number),
        ]),
        SyntaxLanguage(id: "c", name: "C / C++ / Objective-C",
                       extensions: ["c", "h", "cpp", "cc", "cxx", "hpp", "hh", "hxx", "m", "mm", "ino"], rules: [
            (.comment, P.slashComment), (.comment, P.blockComment),
            (.attribute, #"^[ \t]*#[ \t]*\w+"#),
            (.string, #"<[\w./+-]+\.h(?:h|pp|xx)?>"#),
            (.string, P.dqString), (.string, P.charLiteral),
            (.attribute, #"@\w+"#),
            (.keyword, P.words("auto break case char const continue default do double else enum extern float for goto if inline int long register restrict return short signed sizeof static struct switch typedef union unsigned void volatile while bool true false NULL nullptr class namespace template typename public private protected virtual override final new delete this throw try catch using operator friend explicit constexpr consteval static_cast dynamic_cast reinterpret_cast const_cast noexcept decltype mutable nil YES NO self super id instancetype nonatomic strong weak assign readonly readwrite")),
            (.type, #"\b[a-z_][a-z0-9_]*_t\b"#), (.type, P.capitalizedType), (.number, P.number),
        ]),
        SyntaxLanguage(id: "java", name: "Java", extensions: ["java"], rules: [
            (.comment, P.slashComment), (.comment, P.blockComment),
            (.string, P.tripleDq), (.string, P.dqString), (.string, P.charLiteral),
            (.attribute, #"@\w+"#),
            (.keyword, P.words("abstract assert boolean break byte case catch char class const continue default do double else enum extends final finally float for goto if implements import instanceof int interface long native new package private protected public return short static strictfp super switch synchronized this throw throws transient try void volatile while true false null var record sealed permits yield")),
            (.type, P.capitalizedType), (.number, P.number),
        ]),
        SyntaxLanguage(id: "kotlin", name: "Kotlin", extensions: ["kt", "kts"], rules: [
            (.comment, P.slashComment), (.comment, P.blockComment),
            (.string, P.tripleDq), (.string, P.dqString), (.string, P.charLiteral),
            (.attribute, #"@\w+"#),
            (.keyword, P.words("as break class continue do else false for fun if in interface is null object package return super this throw true try typealias typeof val var when while by catch constructor finally get import init set where actual abstract annotation companion const crossinline data enum expect external final infix inline inner internal lateinit noinline open operator out override private protected public reified sealed suspend tailrec vararg")),
            (.type, P.capitalizedType), (.number, P.number),
        ]),
        SyntaxLanguage(id: "csharp", name: "C#", extensions: ["cs", "csx"], rules: [
            (.comment, P.slashComment), (.comment, P.blockComment),
            (.attribute, #"^[ \t]*#[ \t]*\w+"#),
            (.string, #"@"(?:[^"]|"")*"?"#), (.string, P.tripleDq), (.string, P.dqString), (.string, P.charLiteral),
            (.keyword, P.words("abstract as base bool break byte case catch char checked class const continue decimal default delegate do double else enum event explicit extern false finally fixed float for foreach goto if implicit in int interface internal is lock long namespace new null object operator out override params private protected public readonly ref return sbyte sealed short sizeof stackalloc static string struct switch this throw true try typeof uint ulong unchecked unsafe ushort using virtual void volatile while var async await dynamic get set value yield record init required")),
            (.type, P.capitalizedType), (.number, P.number),
        ]),
        SyntaxLanguage(id: "go", name: "Go", extensions: ["go"], rules: [
            (.comment, P.slashComment), (.comment, P.blockComment),
            (.string, P.dqString), (.string, P.backtickString), (.string, P.charLiteral),
            (.keyword, P.words("break case chan const continue default defer else fallthrough for func go goto if import interface map package range return select struct switch type var true false nil iota")),
            (.type, P.words("bool byte complex64 complex128 error float32 float64 int int8 int16 int32 int64 rune string uint uint8 uint16 uint32 uint64 uintptr any")),
            (.type, P.capitalizedType), (.number, P.number),
        ]),
        SyntaxLanguage(id: "rust", name: "Rust", extensions: ["rs"], rules: [
            (.comment, P.slashComment), (.comment, P.blockComment),
            (.string, ####"r###"[\s\S]*?(?:"###|\z)|r##"[\s\S]*?(?:"##|\z)|r#"[\s\S]*?(?:"#|\z)|r"[^"]*"?"####), (.string, P.dqString), (.string, P.charLiteral),
            (.type, #"'[A-Za-z_]\w*\b"#),
            (.attribute, #"#!?\[[^\]\n]*\]"#), (.attribute, #"\b\w+!"#),
            (.keyword, P.words("as async await break const continue crate dyn else enum extern false fn for if impl in let loop match mod move mut pub ref return self Self static struct super trait true type unsafe use where while")),
            (.type, P.words("i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize f32 f64 bool char str")),
            (.type, P.capitalizedType), (.number, P.number),
        ]),
        SyntaxLanguage(id: "javascript", name: "JavaScript / TypeScript",
                       extensions: ["js", "mjs", "cjs", "jsx", "ts", "mts", "cts", "tsx"], rules: [
            (.comment, P.slashComment), (.comment, P.blockComment),
            (.string, P.dqString), (.string, P.sqString), (.string, P.backtickString),
            (.attribute, #"@\w+"#),
            (.keyword, P.words("break case catch class const continue debugger default delete do else export extends finally for function if import in instanceof let new return super switch this throw try typeof var void while with yield async await of static get set true false null undefined NaN Infinity from as interface type enum implements private protected public readonly declare namespace abstract keyof never unknown any number string boolean symbol bigint object satisfies")),
            (.type, P.capitalizedType), (.number, P.number),
        ]),
        SyntaxLanguage(id: "python", name: "Python", extensions: ["py", "pyw", "pyi"], rules: [
            (.comment, P.hashComment),
            (.string, #"(?:\b[rRbBfFuU]{1,2})?"""[\s\S]*?(?:"""|\z)"#),
            (.string, #"(?:\b[rRbBfFuU]{1,2})?'''[\s\S]*?(?:'''|\z)"#),
            (.string, #"(?:\b[rRbBfFuU]{1,2})?"# + P.dqString),
            (.string, #"(?:\b[rRbBfFuU]{1,2})?"# + P.sqString),
            (.attribute, #"^[ \t]*@[\w.]+"#),
            (.keyword, P.words("False None True and as assert async await break class continue def del elif else except finally for from global if import in is lambda nonlocal not or pass raise return try while with yield match case self cls")),
            (.type, P.capitalizedType), (.number, P.number),
        ]),
        SyntaxLanguage(id: "shell", name: "Shell", extensions: ["sh", "bash", "zsh", "ksh", "command"],
                       fileNames: [".bashrc", ".bash_profile", ".zshrc", ".zprofile", ".profile", ".zshenv"], rules: [
            (.comment, P.hashCommentAfterSpace),
            (.string, P.dqString), (.string, #"'[^']*'?"#),
            (.variable, #"\$\{[^}\n]*\}|\$[A-Za-z_]\w*|\$[0-9@#?$!*-]"#),
            (.keyword, P.words("if then else elif fi case esac for select while until do done in function time return exit break continue local export readonly declare typeset unset shift source alias echo printf read cd test true false eval exec set trap wait")),
            (.number, P.number),
        ]),
        SyntaxLanguage(id: "batch", name: "Batch (Windows)", extensions: ["bat", "cmd"], caseInsensitive: true, rules: [
            (.comment, #"^[ \t]*@?(?:rem\b|::)[^\n]*"#),
            (.tag, #"^[ \t]*:[A-Za-z_]\w*"#),
            (.string, P.dqString),
            (.variable, #"%%~?\w|%~?[0-9*]|%[\w]+%|![\w]+!"#),
            (.keyword, P.words("echo set if else goto call exit for in do not exist defined errorlevel equ neq lss leq gtr geq setlocal endlocal enabledelayedexpansion shift pause cls start pushd popd cd copy move del mkdir rmdir title off on nul")),
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
        SyntaxLanguage(id: "json", name: "JSON", extensions: ["json", "jsonc", "json5", "geojson", "webmanifest"], rules: [
            (.comment, P.slashComment), (.comment, P.blockComment),
            (.property, #""(?:[^"\\\n]|\\.)*"(?=\s*:)"#),
            (.string, P.dqString),
            (.keyword, P.words("true false null")),
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
        SyntaxLanguage(id: "yaml", name: "YAML", extensions: ["yml", "yaml"], rules: [
            (.comment, P.hashCommentAfterSpace),
            (.attribute, #"^(?:---|\.\.\.)[ \t]*$"#),
            (.string, P.dqString), (.string, #"'(?:[^'\n]|'')*'"#),
            (.property, #"[\w.\-/]+(?=:(?:[ \t]|$))"#),
            (.variable, #"[&*][\w-]+"#),
            (.attribute, #"!!?\w+"#),
            (.keyword, P.words("true false yes no on off null True False Null TRUE FALSE NULL")),
            (.number, P.number),
        ]),
        SyntaxLanguage(id: "ini", name: "INI / TOML / Konfiguration",
                       extensions: ["ini", "cfg", "conf", "toml", "properties", "env", "editorconfig", "gitconfig"],
                       fileNames: [".gitconfig", ".editorconfig", ".env", ".npmrc", ".gitattributes"], rules: [
            (.comment, #"^[ \t]*[;#][^\n]*"#),
            (.tag, #"^[ \t]*\[\[?[^\]\n]*\]\]?"#),
            (.property, #"^[ \t]*[\w.\-]+(?=[ \t]*[=:])"#),
            (.string, P.dqString), (.string, P.sqStringClosed),
            (.keyword, P.words("true false yes no on off")),
            (.number, P.number),
        ]),
        SyntaxLanguage(id: "sql", name: "SQL", extensions: ["sql"], caseInsensitive: true, rules: [
            (.comment, #"--[^\n]*"#), (.comment, P.blockComment),
            (.string, #"'(?:[^']|'')*'?"#),
            (.property, #""[^"\n]*"|`[^`\n]*`"#),
            (.keyword, P.words("select from where and or not insert into values update set delete create table drop alter add column index view primary key foreign references join inner left right outer full on as group by order having limit offset distinct union all null is in like between exists case when then else end begin commit rollback transaction if default unique check constraint integer int varchar text char boolean date timestamp float double decimal real serial bigint smallint asc desc count sum avg min max returning with recursive replace trigger function procedure return returns declare cascade")),
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

/// Re-colors a text view after edits: tokenizes the whole text in the background (debounced),
/// then colors only the visible part plus a margin, and the rest as it scrolls into view.
final class SyntaxHighlighter {
    /// Larger documents stay uncolored.
    static let maxLength = 5_000_000
    /// Characters colored above and below the visible area.
    private static let margin = 10_000

    private weak var textView: NSTextView?
    private var generation = 0
    private var pending: DispatchWorkItem?
    private let queue = DispatchQueue(label: "notepad.syntax-highlighting", qos: .userInitiated)

    /// Tokens of the text at `tokensGeneration`, sorted by location.
    private var tokens: [(range: NSRange, kind: TokenKind)] = []
    private var tokensGeneration = -1
    private var coloredRange = NSRange(location: 0, length: 0)

    var language: SyntaxLanguage? {
        didSet {
            if oldValue?.id != language?.id { refresh() }
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
        NotificationCenter.default.removeObserver(self)
    }

    func textDidChange() {
        generation += 1
        let length = textView?.textStorage?.length ?? 0
        schedule(after: length < 200_000 ? 0.05 : 0.3)
    }

    func refresh() {
        generation += 1
        schedule(after: 0)
    }

    private func schedule(after delay: TimeInterval) {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.tokenize() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func tokenize() {
        guard let textView, let storage = textView.textStorage else { return }
        guard isEnabled, let language, storage.length <= Self.maxLength else {
            tokens = []
            tokensGeneration = generation
            textView.layoutManager?.removeTemporaryAttribute(.foregroundColor,
                                                            forCharacterRange: NSRange(location: 0, length: storage.length))
            return
        }

        let snapshot = storage.mutableString.copy() as! NSString
        let expectedGeneration = generation
        queue.async { [weak self] in
            let tokens = language.tokens(in: snapshot)
            DispatchQueue.main.async {
                guard let self, self.generation == expectedGeneration else { return }
                self.tokens = tokens
                self.tokensGeneration = expectedGeneration
                self.coloredRange = NSRange(location: 0, length: 0)
                self.colorVisibleRange()
            }
        }
    }

    @objc private func didScroll(_ notification: Notification) {
        colorVisibleRange()
    }

    private func colorVisibleRange() {
        // After an edit the token offsets are stale until the next tokenize() finishes.
        guard tokensGeneration == generation, let textView,
              let layoutManager = textView.layoutManager, let container = textView.textContainer,
              let storage = textView.textStorage else { return }

        let glyphs = layoutManager.glyphRange(forBoundingRect: textView.visibleRect, in: container)
        let visible = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        if coloredRange.length > 0 && NSIntersectionRange(visible, coloredRange) == visible {
            return
        }

        let start = max(0, visible.location - Self.margin)
        let end = min(storage.length, NSMaxRange(visible) + Self.margin)
        let target = NSRange(location: start, length: end - start)
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: target)

        // First token that ends after `start` (tokens are sorted and don't overlap).
        var low = 0, high = tokens.count
        while low < high {
            let mid = (low + high) / 2
            if NSMaxRange(tokens[mid].range) <= start { low = mid + 1 } else { high = mid }
        }
        var index = low
        while index < tokens.count && tokens[index].range.location < end {
            let token = tokens[index]
            if NSMaxRange(token.range) <= storage.length {
                layoutManager.addTemporaryAttribute(.foregroundColor, value: token.kind.color, forCharacterRange: token.range)
            }
            index += 1
        }
        coloredRange = target
    }
}
