/*
 * Notepad für macOS – Aufbereitung der Regex-Regeln einer Sprache.
 *
 * ICU wird mit jeder Capture-Gruppe langsamer, ab der siebten sprunghaft. Darum bekommen nur so
 * viele Regeln eine eigene Gruppe wie nötig, um die Tokenart eindeutig zu erkennen.
 * LICENSE: LGPL-2.1-or-later
 */

import Foundation

/// The characters a regex match can start with: an ASCII bit set plus "some non-ASCII".
struct RegexFirstChars: Equatable {
    private var low: UInt64 = 0
    private var high: UInt64 = 0
    private(set) var nonASCII = false

    static let all = RegexFirstChars(low: ~0, high: ~0, nonASCII: true)

    private init(low: UInt64, high: UInt64, nonASCII: Bool) {
        self.low = low
        self.high = high
        self.nonASCII = nonASCII
    }

    init() {}

    mutating func insert(_ unit: UInt16) {
        if unit >= 128 {
            nonASCII = true
        } else if unit < 64 {
            low |= 1 << UInt64(unit)
        } else {
            high |= 1 << UInt64(unit - 64)
        }
    }

    func contains(_ unit: UInt16) -> Bool {
        if unit >= 128 { return nonASCII }
        return unit < 64 ? low & (1 << UInt64(unit)) != 0 : high & (1 << UInt64(unit - 64)) != 0
    }

    mutating func formUnion(_ other: RegexFirstChars) {
        low |= other.low
        high |= other.high
        nonASCII = nonASCII || other.nonASCII
    }

    func isDisjoint(with other: RegexFirstChars) -> Bool {
        low & other.low == 0 && high & other.high == 0 && !(nonASCII && other.nonASCII)
    }

    func inverted() -> RegexFirstChars {
        RegexFirstChars(low: ~low, high: ~high, nonASCII: true)
    }

    /// Adds the other case of ASCII letters. Non-ASCII characters can fold to ASCII letters
    /// (Kelvin sign, long s), so letters also make `nonASCII` possible.
    mutating func foldCase() {
        for unit in UInt16(0x41)...0x5A where contains(unit) || contains(unit + 0x20) {
            insert(unit)
            insert(unit + 0x20)
            nonASCII = true
        }
    }

    /// A superset of the characters a match of `pattern` can start with, or nil if the
    /// pattern uses syntax this conservative analysis does not know.
    static func of(_ pattern: String, caseInsensitive: Bool) -> RegexFirstChars? {
        var parser = FirstCharParser(pattern: Array(pattern.utf16), fold: caseInsensitive)
        guard let (set, _) = try? parser.alternation(), parser.index == parser.pattern.count else { return nil }
        return set
    }
}

/// Recursive descent over the regex subset used by the language rules. Every item yields
/// its possible first characters and whether it can match empty (then the next item's
/// first characters count too). Unknown syntax throws.
private struct FirstCharParser {
    struct Unknown: Error {}

    let pattern: [UInt16]
    let fold: Bool
    var index = 0

    init(pattern: [UInt16], fold: Bool) {
        self.pattern = pattern
        self.fold = fold
    }

    private var current: UInt16? { index < pattern.count ? pattern[index] : nil }

    private static func set(_ chars: String) -> RegexFirstChars {
        var set = RegexFirstChars()
        for unit in chars.utf16 { set.insert(unit) }
        return set
    }

    private static let word: RegexFirstChars = {
        var set = Self.set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")
        set.insert(0x80)
        return set
    }()

    private static let digit: RegexFirstChars = {
        var set = Self.set("0123456789")
        set.insert(0x80)
        return set
    }()

    private static let space: RegexFirstChars = {
        var set = Self.set(" \t\n\r\u{0B}\u{0C}")
        set.insert(0x80)
        return set
    }()

    mutating func alternation() throws -> (RegexFirstChars, Bool) {
        var (set, nullable) = try sequence()
        while current == 0x7C {  // |
            index += 1
            let (other, otherNullable) = try sequence()
            set.formUnion(other)
            nullable = nullable || otherNullable
        }
        return (set, nullable)
    }

    private mutating func sequence() throws -> (RegexFirstChars, Bool) {
        var set = RegexFirstChars()
        var nullable = true
        while let unit = current, unit != 0x7C, unit != 0x29 {  // | )
            var (atomSet, atomNullable) = try atom()
            if try quantifierAllowsZero() { atomNullable = true }
            if nullable {
                set.formUnion(atomSet)
                nullable = atomNullable
            }
            atomSet = RegexFirstChars()  // later items only matter while all before can be empty
        }
        return (set, nullable)
    }

    private mutating func quantifierAllowsZero() throws -> Bool {
        guard let unit = current else { return false }
        var allowsZero: Bool
        switch unit {
        case 0x2A, 0x3F:  // * ?
            index += 1
            allowsZero = true
        case 0x2B:  // +
            index += 1
            allowsZero = false
        case 0x7B:  // {n}, {n,}, {n,m}
            index += 1
            var minimum = 0
            var digits = 0
            while let digit = current, digit >= 0x30 && digit <= 0x39 {
                minimum = minimum * 10 + Int(digit - 0x30)
                digits += 1
                index += 1
            }
            guard digits > 0 else { throw Unknown() }
            while let next = current, next != 0x7D {
                guard next == 0x2C || (next >= 0x30 && next <= 0x39) else { throw Unknown() }
                index += 1
            }
            guard current == 0x7D else { throw Unknown() }
            index += 1
            allowsZero = minimum == 0
        default:
            return false
        }
        if current == 0x3F || current == 0x2B { index += 1 }  // lazy, possessive
        return allowsZero
    }

    private mutating func atom() throws -> (RegexFirstChars, Bool) {
        guard let unit = current else { throw Unknown() }
        index += 1
        switch unit {
        case 0x28:  // (
            var lookaround = false
            if current == 0x3F {  // (?
                index += 1
                guard let kind = current else { throw Unknown() }
                index += 1
                switch kind {
                case 0x3A, 0x3E: break  // (?:  (?>
                case 0x3D, 0x21: lookaround = true  // (?=  (?!
                case 0x3C:  // (?<=  (?<!
                    guard current == 0x3D || current == 0x21 else { throw Unknown() }
                    index += 1
                    lookaround = true
                default: throw Unknown()
                }
            }
            let inner = try alternation()
            guard current == 0x29 else { throw Unknown() }
            index += 1
            return lookaround ? (RegexFirstChars(), true) : inner
        case 0x5B:  // [
            return (try characterClass(), false)
        case 0x2E:  // .
            return (.all, false)
        case 0x5E, 0x24:  // ^ $
            return (RegexFirstChars(), true)
        case 0x5C:  // backslash
            guard let escaped = current else { throw Unknown() }
            index += 1
            switch escaped {
            case 0x62, 0x42, 0x41, 0x7A, 0x5A, 0x47: return (RegexFirstChars(), true)  // \b \B \A \z \Z \G
            case 0x77: return (folded(Self.word), false)  // \w
            case 0x64: return (Self.digit, false)  // \d
            case 0x73: return (Self.space, false)  // \s
            case 0x57, 0x44, 0x53: return (.all, false)  // \W \D \S
            default: return (try literal(escapedUnit(escaped)), false)
            }
        case 0x29, 0x7C, 0x2A, 0x2B, 0x3F, 0x7B:
            throw Unknown()
        default:
            return (try literal(unit), false)
        }
    }

    /// The character of a simple escape (`\n`, `\t`, `\.` …); letters with other meanings throw.
    private func escapedUnit(_ escaped: UInt16) throws -> UInt16 {
        switch escaped {
        case 0x6E: return 0x0A  // n
        case 0x74: return 0x09  // t
        case 0x72: return 0x0D  // r
        case 0x66: return 0x0C  // f
        case 0x30...0x39, 0x41...0x5A, 0x61...0x7A: throw Unknown()
        default: return escaped
        }
    }

    private func literal(_ unit: UInt16) throws -> RegexFirstChars {
        var set = RegexFirstChars()
        set.insert(unit)
        return folded(set)
    }

    private func folded(_ set: RegexFirstChars) -> RegexFirstChars {
        guard fold else { return set }
        var copy = set
        copy.foldCase()
        return copy
    }

    private mutating func characterClass() throws -> RegexFirstChars {
        var set = RegexFirstChars()
        let negated = current == 0x5E
        if negated { index += 1 }
        if current == 0x5D { throw Unknown() }  // leading ] – avoid dialect questions
        var previous: UInt16?
        while let unit = current, unit != 0x5D {
            index += 1
            var member: UInt16
            switch unit {
            case 0x5B, 0x26: throw Unknown()  // nested sets, &&
            case 0x5C:
                guard let escaped = current else { throw Unknown() }
                index += 1
                switch escaped {
                case 0x77: set.formUnion(Self.word); previous = nil; continue
                case 0x64: set.formUnion(Self.digit); previous = nil; continue
                case 0x73: set.formUnion(Self.space); previous = nil; continue
                case 0x57, 0x44, 0x53: set.formUnion(.all); previous = nil; continue
                default: member = try escapedUnit(escaped)
                }
            case 0x2D:  // - : a range if between two characters
                if let start = previous, let next = current, next != 0x5D {
                    index += 1
                    var end = next
                    if next == 0x5C {
                        guard let escaped = current else { throw Unknown() }
                        index += 1
                        end = try escapedUnit(escaped)
                    } else if next == 0x5B {
                        throw Unknown()
                    }
                    guard end >= start else { throw Unknown() }
                    for value in start...min(end, 127) { set.insert(value) }
                    if end >= 128 { set.insert(128) }
                    previous = nil
                    continue
                }
                member = unit
            default:
                member = unit
            }
            set.insert(member)
            previous = member
        }
        guard current == 0x5D else { throw Unknown() }
        index += 1
        if fold { set.foldCase() }
        return negated ? set.inverted() : set
    }
}

/// How the rules of a regex language become one alternation with as few capture groups as
/// possible, while every match keeps the kind and extent it would have with one group per
/// rule (the original definition).
///
/// 1. A rule joins an earlier group of the same kind if it is adjacent to it, or if no rule
///    it would then come before can start with the same character (so they never compete
///    at one position and their order does not matter).
/// 2. Groups whose possible first characters are pairwise disjoint need no capture group:
///    when no capturing group took part in a match, its first character tells the group.
struct RegexRulePlan {
    /// Kind per capture group (index 0 = group 1); nil marks identifiers.
    let capturedKinds: [TokenKind?]
    /// Non-capturing groups, recognized by the first character of the match.
    let uncaptured: [(first: RegexFirstChars, kind: TokenKind?)]
    let pattern: String

    /// `rules` in priority order, kind nil for the identifier rule.
    init(rules: [(kind: TokenKind?, pattern: String)], caseInsensitive: Bool, optimize: Bool = true) {
        struct Group {
            var kind: TokenKind?
            var patterns: [String]
            var first: RegexFirstChars?
            var rules: [RegexFirstChars?]
        }
        var groups: [Group] = []
        for rule in rules {
            let first = optimize ? RegexFirstChars.of(rule.pattern, caseInsensitive: caseInsensitive) : nil
            if optimize, let target = groups.lastIndex(where: { $0.kind == rule.kind }) {
                let jumped = groups[(target + 1)...].flatMap(\.rules)
                let safe = jumped.isEmpty || first.map { mine in
                    jumped.allSatisfy { $0.map { $0.isDisjoint(with: mine) } ?? false }
                } ?? false
                if safe {
                    groups[target].patterns.append(rule.pattern)
                    groups[target].rules.append(first)
                    if let first, var union = groups[target].first {
                        union.formUnion(first)
                        groups[target].first = union
                    } else {
                        groups[target].first = nil
                    }
                    continue
                }
            }
            groups.append(Group(kind: rule.kind, patterns: [rule.pattern], first: first, rules: [first]))
        }

        var captured: [TokenKind?] = []
        var uncaptured: [(first: RegexFirstChars, kind: TokenKind?)] = []
        var taken = RegexFirstChars()
        var parts: [String] = []
        for group in groups {
            let body = group.patterns.count == 1 ? group.patterns[0] : group.patterns.map { "(?:\($0))" }.joined(separator: "|")
            if optimize, let first = group.first, first.isDisjoint(with: taken) {
                taken.formUnion(first)
                uncaptured.append((first, group.kind))
                parts.append("(?:\(body))")
            } else {
                captured.append(group.kind)
                parts.append("(\(body))")
            }
        }
        capturedKinds = captured
        self.uncaptured = uncaptured
        pattern = parts.joined(separator: "|")
    }
}
