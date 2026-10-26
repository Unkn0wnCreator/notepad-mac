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
    var text: String
    var encoding: TextEncoding
    var lineEnding: LineEnding
}

enum TextCodecError: Error {
    case unrepresentable(TextEncoding)
}

enum TextCodec {
    static func decode(_ data: Data) -> DecodedText {
        let bytes = [UInt8](data)
        if bytes.isEmpty {
            return DecodedText(text: "", encoding: .utf8, lineEnding: .lf)
        }

        // Look for byte order marks
        let encoding: TextEncoding
        let bomLength: Int
        if bytes.starts(with: [0xFF, 0xFE]) {
            (encoding, bomLength) = (.utf16LE, 2)
        } else if bytes.starts(with: [0xFE, 0xFF]) {
            (encoding, bomLength) = (.utf16BE, 2)
        } else if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            (encoding, bomLength) = (.utf8BOM, 3)
        } else {
            (encoding, bomLength) = (analyzeEncoding(bytes), 0)
        }

        let body = bytes[bomLength...]
        let units: [UInt16]
        switch encoding {
        case .utf16LE, .utf16BE:
            var decoded = [UInt16]()
            decoded.reserveCapacity(body.count / 2)
            var i = body.startIndex
            while i + 1 < body.endIndex {
                let first = UInt16(body[i]), second = UInt16(body[i + 1])
                decoded.append(encoding == .utf16LE ? first | second << 8 : first << 8 | second)
                i += 2
            }
            units = decoded
        case .utf8, .utf8BOM:
            units = Array(String(decoding: body, as: UTF8.self).utf16)
        case .ansi:
            let data = Data(body)
            let string = String(data: data, encoding: .windowsCP1252)
                ?? String(data: data, encoding: .isoLatin1) ?? ""
            units = Array(string.utf16)
        }

        let (normalized, lineEnding) = processNewLinesAndNulls(units)
        return DecodedText(text: String(decoding: normalized, as: UTF16.self),
                           encoding: encoding, lineEnding: lineEnding)
    }

    static func encode(_ text: String, encoding: TextEncoding, lineEnding: LineEnding) throws -> Data {
        var string = text
            .replacingOccurrences(of: "\r\n", with: "\n", options: .literal)
            .replacingOccurrences(of: "\r", with: "\n", options: .literal)
        if lineEnding != .lf {
            string = string.replacingOccurrences(of: "\n", with: lineEnding.sequence, options: .literal)
        }

        switch encoding {
        case .utf8:
            return Data(string.utf8)
        case .utf8BOM:
            return Data([0xEF, 0xBB, 0xBF]) + Data(string.utf8)
        case .utf16LE:
            return Data([0xFF, 0xFE]) + (string.data(using: .utf16LittleEndian) ?? Data())
        case .utf16BE:
            return Data([0xFE, 0xFF]) + (string.data(using: .utf16BigEndian) ?? Data())
        case .ansi:
            guard let data = string.data(using: .windowsCP1252) else {
                throw TextCodecError.unrepresentable(encoding)
            }
            return data
        }
    }

    private static func analyzeEncoding(_ bytes: [UInt8]) -> TextEncoding {
        if bytes.allSatisfy({ $0 > 0 && $0 < 0x80 }) {
            return .utf8
        }
        if let utf16 = guessUTF16(bytes) {
            return utf16
        }
        if String(bytes: bytes, encoding: .utf8) != nil {
            return .utf8
        }
        return .ansi
    }

    /// Simplified stand-in for IsTextUnicode's statistics test: Latin text in
    /// UTF-16 without BOM has a zero in (nearly) every other byte.
    private static func guessUTF16(_ bytes: [UInt8]) -> TextEncoding? {
        var zerosEven = 0, zerosOdd = 0
        for (index, byte) in bytes.enumerated() where byte == 0 {
            if index % 2 == 0 { zerosEven += 1 } else { zerosOdd += 1 }
        }
        guard bytes.count % 2 == 0 else { return nil }
        let pairs = bytes.count / 2
        if pairs > 0 && zerosOdd * 2 >= pairs && zerosEven * 10 < zerosOdd {
            return .utf16LE
        }
        if pairs > 0 && zerosEven * 2 >= pairs && zerosOdd * 10 < zerosEven {
            return .utf16BE
        }
        return nil
    }

    /// Replaces NUL with a space, normalizes line endings to "\n" and picks the
    /// line ending to write back the same way ReactOS does.
    private static func processNewLinesAndNulls(_ units: [UInt16]) -> ([UInt16], LineEnding) {
        var output = [UInt16]()
        output.reserveCapacity(units.count)
        var crlfCount = 0, lfCount = 0, crCount = 0

        var i = 0
        while i < units.count {
            switch units[i] {
            case 0x0D:
                if i + 1 < units.count && units[i + 1] == 0x0A {
                    crlfCount += 1
                    i += 1
                } else {
                    crCount += 1
                }
                output.append(0x0A)
            case 0x0A:
                lfCount += 1
                output.append(0x0A)
            case 0x00:
                output.append(0x20)
            default:
                output.append(units[i])
            }
            i += 1
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
        return (output, lineEnding)
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
