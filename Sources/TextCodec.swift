/*
 * Notepad für macOS – Lesen und Schreiben von Textdateien.
 *
 * Portiert aus ReactOS Notepad, base/applications/notepad/text.c
 * (ReadText, AnalyzeEncoding, ProcessNewLinesAndNulls, WriteText).
 * LICENSE: LGPL-2.1-or-later
 */

import Foundation

enum TextEncoding: Int, CaseIterable {
    case utf8, utf8BOM, utf16LE, utf16BE, ansi

    var displayName: String {
        switch self {
        case .utf8: return "UTF-8"
        case .utf8BOM: return "UTF-8 mit BOM"
        case .utf16LE: return "UTF-16 LE"
        case .utf16BE: return "UTF-16 BE"
        case .ansi: return "ANSI (Windows-1252)"
        }
    }
}

enum LineEnding: Int, CaseIterable {
    case crlf, lf, cr

    var sequence: String {
        switch self {
        case .crlf: return "\r\n"
        case .lf: return "\n"
        case .cr: return "\r"
        }
    }

    var displayName: String {
        switch self {
        case .crlf: return "Windows (CRLF)"
        case .lf: return "Unix (LF)"
        case .cr: return "Mac klassisch (CR)"
        }
    }
}

struct DecodedText {
    /// Text with every line ending normalized to "\n".
    var text: NSString
    var encoding: TextEncoding
    var lineEnding: LineEnding
}

enum TextCodecError: Error {
    case unrepresentable(TextEncoding)
}

/// Fast paths: the bytes are scanned once with memchr, rewritten only when they contain "\r" or
/// NUL, and turned into an NSString in a single conversion (no Swift String round trips).
enum TextCodec {
    static func decode(_ data: Data) -> DecodedText {
        data.withUnsafeBytes { decode(bytes: $0) }
    }

    static func decode(bytes raw: UnsafeRawBufferPointer) -> DecodedText {
        guard let base = raw.baseAddress, raw.count > 0 else {
            return DecodedText(text: "", encoding: .utf8, lineEnding: .lf)
        }
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        let count = raw.count

        // Look for byte order marks
        if count >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE {
            return decodeUTF16(bytes + 2, count: count - 2, encoding: .utf16LE)
        }
        if count >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF {
            return decodeUTF16(bytes + 2, count: count - 2, encoding: .utf16BE)
        }
        if count >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF {
            return decodeBytes(bytes + 3, count: count - 3, encoding: .utf8BOM)
        }

        // UTF-16 without BOM is only possible if there are zero bytes.
        if memchr(bytes, 0, count) != nil, let utf16 = guessUTF16(bytes, count: count) {
            return decodeUTF16(bytes, count: count, encoding: utf16)
        }
        return decodeBytes(bytes, count: count, encoding: nil)
    }

    /// UTF-8 or ANSI. `encoding == nil` means: UTF-8 if valid, otherwise ANSI.
    private static func decodeBytes(_ bytes: UnsafePointer<UInt8>, count: Int, encoding: TextEncoding?) -> DecodedText {
        var lineEnding = LineEnding.lf
        var buffer: UnsafeMutablePointer<UInt8>?
        var length = count

        if memchr(bytes, 0x0D, count) != nil || memchr(bytes, 0, count) != nil {
            let output = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
            let result = normalize(bytes, count: count, into: output, lineFeed: 0x0A, space: 0x20)
            buffer = output
            length = result.length
            lineEnding = result.lineEnding
        }
        defer { buffer?.deallocate() }
        let source = UnsafeRawPointer(buffer ?? UnsafeMutablePointer(mutating: bytes))

        if encoding != .ansi, let text = NSString(bytes: source, length: length, encoding: String.Encoding.utf8.rawValue) {
            return DecodedText(text: text, encoding: encoding ?? .utf8, lineEnding: lineEnding)
        }
        if encoding == .utf8BOM {
            // Declared UTF-8 but invalid: repair with replacement characters.
            let repaired = String(decoding: UnsafeRawBufferPointer(start: source, count: length), as: UTF8.self)
            return DecodedText(text: repaired as NSString, encoding: .utf8BOM, lineEnding: lineEnding)
        }
        let text = NSString(bytes: source, length: length, encoding: String.Encoding.windowsCP1252.rawValue)
            ?? NSString(bytes: source, length: length, encoding: String.Encoding.isoLatin1.rawValue) ?? ""
        return DecodedText(text: text, encoding: .ansi, lineEnding: lineEnding)
    }

    private static func decodeUTF16(_ bytes: UnsafePointer<UInt8>, count: Int, encoding: TextEncoding) -> DecodedText {
        let units = count / 2
        let source = UnsafeMutablePointer<UInt16>.allocate(capacity: max(units, 1))
        defer { source.deallocate() }
        memcpy(source, bytes, units * 2)
        let bigEndianFile = encoding == .utf16BE
        if bigEndianFile != (UInt16(1).bigEndian == 1) {
            for i in 0..<units { source[i] = source[i].byteSwapped }
        }

        let output = UnsafeMutablePointer<UInt16>.allocate(capacity: max(units, 1))
        defer { output.deallocate() }
        let result = normalize(source, count: units, into: output, lineFeed: 0x0A, space: 0x20)
        // String(decoding:) repairs unpaired surrogates.
        let text = String(decoding: UnsafeBufferPointer(start: output, count: result.length), as: UTF16.self)
        return DecodedText(text: text as NSString, encoding: encoding, lineEnding: result.lineEnding)
    }

    /// Replaces NUL with a space, normalizes line endings to "\n" and picks the line ending to
    /// write back the same way ReactOS does (ProcessNewLinesAndNulls in text.c).
    private static func normalize<Unit: FixedWidthInteger>(_ input: UnsafePointer<Unit>, count: Int,
                                                           into output: UnsafeMutablePointer<Unit>,
                                                           lineFeed: Unit, space: Unit) -> (length: Int, lineEnding: LineEnding) {
        var crlfCount = 0, lfCount = 0, crCount = 0
        var i = 0, o = 0
        while i < count {
            let c = input[i]
            if c == 0x0D {
                if i + 1 < count && input[i + 1] == 0x0A {
                    crlfCount += 1
                    i += 1
                } else {
                    crCount += 1
                }
                output[o] = lineFeed
            } else if c == 0x0A {
                lfCount += 1
                output[o] = lineFeed
            } else if c == 0 {
                output[o] = space
            } else {
                output[o] = c
            }
            i += 1
            o += 1
        }

        let lineEnding: LineEnding
        if crlfCount + lfCount + crCount == 0 {
            lineEnding = .lf
        } else if crCount > crlfCount {
            lineEnding = .cr
        } else if lfCount > crlfCount {
            lineEnding = .lf
        } else {
            lineEnding = .crlf
        }
        return (o, lineEnding)
    }

    /// Simplified stand-in for IsTextUnicode's statistics test: Latin text in
    /// UTF-16 without BOM has a zero in (nearly) every other byte.
    private static func guessUTF16(_ bytes: UnsafePointer<UInt8>, count: Int) -> TextEncoding? {
        guard count % 2 == 0 else { return nil }
        var zerosEven = 0, zerosOdd = 0
        var i = 0
        while i < count {
            if bytes[i] == 0 { zerosEven += 1 }
            if bytes[i + 1] == 0 { zerosOdd += 1 }
            i += 2
        }
        let pairs = count / 2
        if zerosOdd * 2 >= pairs && zerosEven * 10 < zerosOdd {
            return .utf16LE
        }
        if zerosEven * 2 >= pairs && zerosOdd * 10 < zerosEven {
            return .utf16BE
        }
        return nil
    }

    static func encode(_ text: NSString, encoding: TextEncoding, lineEnding: LineEnding) throws -> Data {
        // The editor only produces "\n", but pasted text may still contain "\r".
        var text = text
        if text.range(of: "\r", options: .literal).location != NSNotFound {
            let normalized = text.mutableCopy() as! NSMutableString
            normalized.replaceOccurrences(of: "\r\n", with: "\n", options: .literal, range: NSRange(location: 0, length: normalized.length))
            normalized.replaceOccurrences(of: "\r", with: "\n", options: .literal, range: NSRange(location: 0, length: normalized.length))
            text = normalized
        }

        switch encoding {
        case .utf8, .utf8BOM, .ansi:
            let stringEncoding: String.Encoding = encoding == .ansi ? .windowsCP1252 : .utf8
            guard let body = text.data(using: stringEncoding.rawValue, allowLossyConversion: false) else {
                throw TextCodecError.unrepresentable(encoding)
            }
            let bom = encoding == .utf8BOM ? Data([0xEF, 0xBB, 0xBF]) : Data()
            return bom + convertLineFeeds(body, to: lineEnding, unitSize: 1, bigEndian: false)
        case .utf16LE, .utf16BE:
            let bigEndian = encoding == .utf16BE
            let body = text.data(using: bigEndian ? String.Encoding.utf16BigEndian.rawValue
                                                 : String.Encoding.utf16LittleEndian.rawValue) ?? Data()
            let bom = bigEndian ? Data([0xFE, 0xFF]) : Data([0xFF, 0xFE])
            return bom + convertLineFeeds(body, to: lineEnding, unitSize: 2, bigEndian: bigEndian)
        }
    }

    /// Rewrites encoded "\n" units as "\r\n" or "\r" in one pass over the bytes.
    private static func convertLineFeeds(_ data: Data, to lineEnding: LineEnding, unitSize: Int, bigEndian: Bool) -> Data {
        guard lineEnding != .lf else { return data }
        let lineFeedOffset = unitSize == 2 && bigEndian ? 1 : 0   // byte that holds 0x0A

        return data.withUnsafeBytes { raw -> Data in
            let bytes = raw.bindMemory(to: UInt8.self)
            let units = bytes.count / unitSize
            func isLineFeed(_ unit: Int) -> Bool {
                let start = unit * unitSize
                for b in 0..<unitSize {
                    let expected: UInt8 = b == lineFeedOffset ? 0x0A : 0
                    if bytes[start + b] != expected { return false }
                }
                return true
            }

            if lineEnding == .cr {
                var copy = Data(bytes)
                copy.withUnsafeMutableBytes { out in
                    for unit in 0..<units where isLineFeed(unit) {
                        out[unit * unitSize + lineFeedOffset] = 0x0D
                    }
                }
                return copy
            }

            // CRLF: count first, then copy once.
            var lineFeeds = 0
            for unit in 0..<units where isLineFeed(unit) { lineFeeds += 1 }
            var output = Data(count: bytes.count + lineFeeds * unitSize)
            output.withUnsafeMutableBytes { out in
                var o = 0
                for unit in 0..<units {
                    let start = unit * unitSize
                    if isLineFeed(unit) {
                        for b in 0..<unitSize { out[o + b] = b == lineFeedOffset ? 0x0D : 0 }
                        o += unitSize
                    }
                    for b in 0..<unitSize { out[o + b] = bytes[start + b] }
                    o += unitSize
                }
            }
            return output
        }
    }
}

enum LineScanner {
    private static let chunkSize = 65_536

    /// 1-based line and column of a UTF-16 offset. "\r\n", "\r" and "\n" each end a line.
    static func position(of location: Int, in text: NSString) -> (line: Int, column: Int) {
        let end = min(location, text.length)
        let result = scan(text, from: 0, to: end)
        return (1 + result.lineBreaks, end - result.lineStart + 1)
    }

    /// Counts line breaks in `start..<end` and returns where the last line in that range starts.
    static func scan(_ text: NSString, from start: Int, to end: Int) -> (lineBreaks: Int, lineStart: Int) {
        var lineBreaks = 0, lineStart = start
        var previousWasCR = start > 0 && text.character(at: start - 1) == 0x0D
        var buffer = [unichar](repeating: 0, count: min(chunkSize, max(end - start, 0)))
        var chunkStart = start

        while chunkStart < end {
            let length = min(chunkSize, end - chunkStart)
            text.getCharacters(&buffer, range: NSRange(location: chunkStart, length: length))
            for i in 0..<length {
                let c = buffer[i]
                if c == 0x0A {
                    if !previousWasCR { lineBreaks += 1 }
                    lineStart = chunkStart + i + 1
                    previousWasCR = false
                } else if c == 0x0D {
                    lineBreaks += 1
                    lineStart = chunkStart + i + 1
                    previousWasCR = true
                } else {
                    previousWasCR = false
                }
            }
            chunkStart += length
        }
        return (lineBreaks, lineStart)
    }

    /// Start of the line containing `location`, found by searching backwards.
    static func lineStart(of location: Int, in text: NSString) -> Int {
        var index = location
        while index > 0 {
            let c = text.character(at: index - 1)
            if c == 0x0A || c == 0x0D { break }
            index -= 1
        }
        return index
    }

    static func lineCount(in text: NSString) -> Int {
        position(of: text.length, in: text).line
    }

    /// UTF-16 offset of the first character of a 1-based line.
    static func offset(ofLine target: Int, in text: NSString) -> Int {
        var line = 1, lineStart = 0, previousWasCR = false
        var buffer = [unichar](repeating: 0, count: chunkSize)
        var chunkStart = 0

        while chunkStart < text.length {
            let length = min(chunkSize, text.length - chunkStart)
            text.getCharacters(&buffer, range: NSRange(location: chunkStart, length: length))
            for i in 0..<length {
                let c = buffer[i]
                if line == target && !(c == 0x0A && previousWasCR) {
                    return lineStart
                }
                if c == 0x0A {
                    if !previousWasCR { line += 1 }
                    lineStart = chunkStart + i + 1
                    previousWasCR = false
                } else if c == 0x0D {
                    line += 1
                    lineStart = chunkStart + i + 1
                    previousWasCR = true
                } else {
                    previousWasCR = false
                }
            }
            chunkStart += length
        }
        return lineStart
    }
}

/// Remembers the last caret position, so the status bar only scans the text between the old
/// and the new position instead of the whole document on every keystroke.
struct LinePositionCache {
    private var line = 1
    private var lineStart = 0

    /// Edits before the remembered line start change its line number.
    mutating func textChanged(at location: Int) {
        if location < lineStart {
            line = 1
            lineStart = 0
        }
    }

    mutating func position(of location: Int, in text: NSString) -> (line: Int, column: Int) {
        let location = min(location, text.length)
        if lineStart > text.length {
            line = 1
            lineStart = 0
        }

        if location >= lineStart {
            let result = LineScanner.scan(text, from: lineStart, to: location)
            line += result.lineBreaks
            lineStart = result.lineStart
        } else {
            let newLineStart = LineScanner.lineStart(of: location, in: text)
            line -= LineScanner.scan(text, from: newLineStart, to: lineStart).lineBreaks
            lineStart = newLineStart
        }
        return (line, location - lineStart + 1)
    }
}
