/*
 * Notepad für macOS – Schnelle UTF-8 ↔ UTF-16-Umwandlung für große Dateien.
 *
 * Decoding validates UTF-8 strictly and normalizes line endings and NULs in the same pass;
 * encoding writes the chosen line ending while transcoding. Both use a 16-unit SIMD fast path
 * for plain ASCII blocks.
 * LICENSE: LGPL-2.1-or-later
 */

import Foundation

enum FastUTF {
    struct Decoded {
        /// UTF-16 text with every line ending normalized to "\n" and NUL replaced by a space.
        var text: NSString
        var crlfCount: Int
        var lfCount: Int
        var crCount: Int
    }

    // MARK: - Decoding

    /// Strict UTF-8 → UTF-16 with line ending and NUL normalization (like `TextCodec.normalize`):
    /// "\r\n" → "\n", lone "\r" → "\n", NUL → " ". Returns nil if the bytes are not valid UTF-8
    /// (overlong forms, surrogates, code points > U+10FFFF, bad or truncated sequences).
    /// A leading BOM is not stripped (the caller handles it) and stays as U+FEFF.
    static func decodeUTF8(_ bytes: UnsafePointer<UInt8>, count: Int) -> Decoded? {
        guard count > 0 else { return Decoded(text: "", crlfCount: 0, lfCount: 0, crCount: 0) }
        // Every input byte yields at most one UTF-16 unit (4-byte sequences yield 2 units).
        guard let raw = malloc(count * 2) else { fatalError("FastUTF: out of memory") }
        let out = raw.bindMemory(to: UInt16.self, capacity: count)

        var i = 0, o = 0
        var crlf = 0, lf = 0, cr = 0
        // Per-lane line feed counters for the fast path, flushed before they can overflow.
        var lfLanes = SIMD16<UInt8>()
        var lfLanesUsed = 0
        let lineFeed = SIMD16<UInt8>(repeating: 0x0A)
        let carriageReturn = SIMD16<UInt8>(repeating: 0x0D)
        let highBit = SIMD16<UInt8>(repeating: 0x80)
        let zero = SIMD16<UInt8>()
        let one = SIMD16<UInt8>(repeating: 1)
        let allOnes = SIMD16<UInt8>(repeating: 0xFF)
        let laneIndex = SIMD16<UInt8>(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15)

        while i < count {
            // Fast path: a 16-byte block is always widened; the output advances only over the
            // leading run of plain ASCII (no "\r", no NUL). Writing past it is harmless because
            // the output never runs ahead of the input (o ≤ i), so o + 16 ≤ count.
            if i &+ 16 <= count {
                let v = UnsafeRawPointer(bytes + i).loadUnaligned(as: SIMD16<UInt8>.self)
                let special = (v .>= highBit) .| (v .== carriageReturn) .| (v .== zero)
                UnsafeMutableRawPointer(out + o).storeBytes(of: widen(v), as: SIMD16<UInt16>.self)
                let mask = nibbleMask(zero.replacing(with: allOnes, where: special))
                let lineFeeds = v .== lineFeed
                if lfLanesUsed == 255 {
                    lf &+= laneSum(lfLanes)
                    lfLanes = zero
                    lfLanesUsed = 0
                }
                lfLanesUsed &+= 1
                // Branch on the common case so the next load does not depend on the run length.
                if mask == 0 {
                    lfLanes &+= zero.replacing(with: one, where: lineFeeds)
                    i &+= 16
                    o &+= 16
                    continue
                }
                let run = mask.trailingZeroBitCount >> 2
                let inRun = laneIndex .< SIMD16<UInt8>(repeating: UInt8(truncatingIfNeeded: run))
                lfLanes &+= zero.replacing(with: one, where: lineFeeds .& inRun)
                i &+= run
                o &+= run
            }

            // Scalar path: one character, then more as long as the next byte is not plain ASCII
            // (keeps non-Latin text out of the fast path). Sequences may cross block boundaries.
            repeat {
                let b0 = bytes[i]
                if b0 < 0x80 {
                    if b0 == 0x0D {
                        if i &+ 1 < count && bytes[i &+ 1] == 0x0A {
                            crlf &+= 1
                            i &+= 2
                        } else {
                            cr &+= 1
                            i &+= 1
                        }
                        out[o] = 0x0A
                    } else {
                        if b0 == 0x0A { lf &+= 1 }
                        out[o] = b0 == 0 ? 0x20 : UInt16(b0)
                        i &+= 1
                    }
                    o &+= 1
                } else if b0 < 0xE0 {
                    // 2 bytes: C2..DF 80..BF (C0, C1 would be overlong; 80..BF is a lone continuation)
                    guard b0 >= 0xC2, i &+ 1 < count else { free(raw); return nil }
                    let b1 = bytes[i &+ 1]
                    guard b1 & 0xC0 == 0x80 else { free(raw); return nil }
                    out[o] = UInt16(b0 & 0x1F) << 6 | UInt16(b1 & 0x3F)
                    i &+= 2
                    o &+= 1
                } else if b0 < 0xF0 {
                    // 3 bytes: E0 A0..BF, ED 80..9F (no surrogates), otherwise 80..BF
                    guard i &+ 2 < count else { free(raw); return nil }
                    let b1 = bytes[i &+ 1], b2 = bytes[i &+ 2]
                    let low: UInt8 = b0 == 0xE0 ? 0xA0 : 0x80
                    let high: UInt8 = b0 == 0xED ? 0x9F : 0xBF
                    guard b1 >= low, b1 <= high, b2 & 0xC0 == 0x80 else { free(raw); return nil }
                    out[o] = UInt16(b0 & 0x0F) << 12 | UInt16(b1 & 0x3F) << 6 | UInt16(b2 & 0x3F)
                    i &+= 3
                    o &+= 1
                } else {
                    // 4 bytes: F0 90..BF, F1..F3 80..BF, F4 80..8F (≤ U+10FFFF)
                    guard b0 <= 0xF4, i &+ 3 < count else { free(raw); return nil }
                    let b1 = bytes[i &+ 1], b2 = bytes[i &+ 2], b3 = bytes[i &+ 3]
                    let low: UInt8 = b0 == 0xF0 ? 0x90 : 0x80
                    let high: UInt8 = b0 == 0xF4 ? 0x8F : 0xBF
                    guard b1 >= low, b1 <= high, b2 & 0xC0 == 0x80, b3 & 0xC0 == 0x80 else { free(raw); return nil }
                    let scalar = UInt32(b0 & 0x07) << 18 | UInt32(b1 & 0x3F) << 12
                        | UInt32(b2 & 0x3F) << 6 | UInt32(b3 & 0x3F)
                    let v = scalar &- 0x10000
                    out[o] = UInt16(truncatingIfNeeded: 0xD800 | (v >> 10))
                    out[o &+ 1] = UInt16(truncatingIfNeeded: 0xDC00 | (v & 0x3FF))
                    i &+= 4
                    o &+= 2
                }
            } while i < count && (bytes[i] >= 0x80 || bytes[i] == 0x0D || bytes[i] == 0)
        }
        lf &+= laneSum(lfLanes)

        // Give back the unused part of the worst-case allocation.
        let final = realloc(raw, o * 2) ?? raw
        let text = NSString(charactersNoCopy: final.assumingMemoryBound(to: unichar.self), length: o, freeWhenDone: true)
        return Decoded(text: text, crlfCount: crlf, lfCount: lf, crCount: cr)
    }

    // MARK: - Encoding

    /// UTF-16 → UTF-8, writing every line break as `lineEnding` ("\n", "\r\n" or "\r").
    /// Like `TextCodec.encode`, stray "\r\n" and "\r" in the text (e.g. pasted) count as line
    /// breaks too. Unpaired surrogates become U+FFFD. `bom` prepends EF BB BF.
    static func encodeUTF8(_ text: NSString, lineEnding: String, bom: Bool) -> Data {
        let eol = Array(lineEnding.utf8)
        precondition(eol.count == 1 || eol.count == 2, "FastUTF: unsupported line ending")
        let length = text.length
        // Worst case: 3 bytes per UTF-16 unit (BMP characters and "\n" → "\r\n" need ≤ 3,
        // a surrogate pair needs 4 for 2 units), plus the BOM.
        let capacity = length * 3 + 3
        guard let raw = malloc(capacity) else { fatalError("FastUTF: out of memory") }
        let out = raw.bindMemory(to: UInt8.self, capacity: capacity)
        var o = 0
        if bom {
            out[0] = 0xEF; out[1] = 0xBB; out[2] = 0xBF
            o = 3
        }

        if let direct = CFStringGetCharactersPtr(text as CFString) {
            _ = encodeUnits(direct, count: length, isFinal: true, eol: eol, into: out, at: &o)
        } else {
            let chunkSize = 65536
            let chunk = UnsafeMutablePointer<unichar>.allocate(capacity: chunkSize)
            defer { chunk.deallocate() }
            var start = 0
            while start < length {
                let n = min(chunkSize, length - start)
                text.getCharacters(chunk, range: NSRange(location: start, length: n))
                start += encodeUnits(chunk, count: n, isFinal: start + n == length, eol: eol, into: out, at: &o)
            }
        }

        guard o > 0 else { free(raw); return Data() }
        let final = realloc(raw, o) ?? raw
        return Data(bytesNoCopy: final, count: o, deallocator: .free)
    }

    /// Encodes `count` units and returns how many were consumed. If more units follow
    /// (`isFinal == false`), a trailing "\r" or high surrogate is left for the next chunk.
    private static func encodeUnits(_ src: UnsafePointer<UInt16>, count: Int, isFinal: Bool, eol: [UInt8],
                                    into out: UnsafeMutablePointer<UInt8>, at position: inout Int) -> Int {
        var n = count
        if !isFinal && n > 0 && (src[n - 1] == 0x0D || (src[n - 1] & 0xFC00) == 0xD800) { n -= 1 }

        let eol0 = eol[0]
        let eolTwo = eol.count == 2
        let eol1: UInt8 = eolTwo ? eol[1] : 0
        // With "\n" as line ending, line feeds can stay in the fast path.
        let probe: UInt16 = eol == [0x0A] ? 0x0D : 0x0A
        let lineFeedProbe = SIMD16<UInt16>(repeating: probe)
        let carriageReturn = SIMD16<UInt16>(repeating: 0x0D)
        let asciiLimit = SIMD16<UInt16>(repeating: 0x80)
        let zero = SIMD16<UInt16>()
        let allOnes = SIMD16<UInt16>(repeating: 0xFFFF)

        var i = 0, o = position
        while i < n {
            // Fast path like in decoding: narrow 16 units, advance over the leading ASCII run.
            // The output (≤ 3 bytes per unit) never catches up with the reserved capacity here.
            if i &+ 16 <= n {
                let v = UnsafeRawPointer(src + i).loadUnaligned(as: SIMD16<UInt16>.self)
                let special = (v .>= asciiLimit) .| (v .== carriageReturn) .| (v .== lineFeedProbe)
                let lowHalf = narrow8(v.lowHalf), highHalf = narrow8(v.highHalf)
                UnsafeMutableRawPointer(out + o).storeBytes(of: lowHalf, as: SIMD8<UInt8>.self)
                UnsafeMutableRawPointer(out + o + 8).storeBytes(of: highHalf, as: SIMD8<UInt8>.self)
                let flags = zero.replacing(with: allOnes, where: special)
                let mask = nibbleMask(narrow8(flags.lowHalf), narrow8(flags.highHalf))
                // Branch on the common case so the next load does not depend on the run length.
                if mask == 0 {
                    i &+= 16
                    o &+= 16
                    continue
                }
                let run = mask.trailingZeroBitCount >> 2
                i &+= run
                o &+= run
            }

            repeat {
                let c = src[i]
                if c < 0x80 {
                    if c == 0x0A || c == 0x0D {
                        i &+= (c == 0x0D && i &+ 1 < n && src[i &+ 1] == 0x0A) ? 2 : 1
                        out[o] = eol0
                        o &+= 1
                        if eolTwo {
                            out[o] = eol1
                            o &+= 1
                        }
                    } else {
                        out[o] = UInt8(truncatingIfNeeded: c)
                        o &+= 1
                        i &+= 1
                    }
                } else if c < 0x800 {
                    out[o] = UInt8(truncatingIfNeeded: 0xC0 | (c >> 6))
                    out[o &+ 1] = UInt8(truncatingIfNeeded: 0x80 | (c & 0x3F))
                    o &+= 2
                    i &+= 1
                } else if (c & 0xF800) == 0xD800 {
                    if c < 0xDC00 && i &+ 1 < n && (src[i &+ 1] & 0xFC00) == 0xDC00 {
                        let scalar = 0x10000 &+ (UInt32(c & 0x3FF) << 10 | UInt32(src[i &+ 1] & 0x3FF))
                        out[o] = UInt8(truncatingIfNeeded: 0xF0 | (scalar >> 18))
                        out[o &+ 1] = UInt8(truncatingIfNeeded: 0x80 | ((scalar >> 12) & 0x3F))
                        out[o &+ 2] = UInt8(truncatingIfNeeded: 0x80 | ((scalar >> 6) & 0x3F))
                        out[o &+ 3] = UInt8(truncatingIfNeeded: 0x80 | (scalar & 0x3F))
                        o &+= 4
                        i &+= 2
                    } else {
                        // Unpaired surrogate → U+FFFD
                        out[o] = 0xEF; out[o &+ 1] = 0xBF; out[o &+ 2] = 0xBD
                        o &+= 3
                        i &+= 1
                    }
                } else {
                    out[o] = UInt8(truncatingIfNeeded: 0xE0 | (c >> 12))
                    out[o &+ 1] = UInt8(truncatingIfNeeded: 0x80 | ((c >> 6) & 0x3F))
                    out[o &+ 2] = UInt8(truncatingIfNeeded: 0x80 | (c & 0x3F))
                    o &+= 3
                    i &+= 1
                }
            } while i < n && (src[i] >= 0x80 || src[i] == 0x0D || src[i] == probe)
        }
        position = o
        return n
    }

    // Lane conversions are plain loops and comparisons use vector operands (not scalars): LLVM
    // turns these into single vector instructions (ushll/xtn/shrn, pmovzxbw/packuswb), whereas
    // the generic stdlib conversions and any()/min() become out-of-line calls into the stdlib.

    @inline(__always)
    private static func widen(_ v: SIMD16<UInt8>) -> SIMD16<UInt16> {
        var r = SIMD16<UInt16>()
        for k in 0..<16 { r[k] = UInt16(v[k]) }
        return r
    }

    @inline(__always)
    private static func narrow8(_ v: SIMD8<UInt16>) -> SIMD8<UInt8> {
        var r = SIMD8<UInt8>()
        for k in 0..<8 { r[k] = UInt8(truncatingIfNeeded: v[k]) }
        return r
    }

    @inline(__always)
    private static func laneSum(_ v: SIMD16<UInt8>) -> Int {
        var sum = 0
        for k in 0..<16 { sum &+= Int(v[k]) }
        return sum
    }

    /// Compresses a 0x00/0xFF lane mask into 4 bits per lane (lane k → bits 4k..4k+3), so the
    /// first set lane is `trailingZeroBitCount >> 2` (16 if none). Compiles to shrn on arm64.
    @inline(__always)
    private static func nibbleMask(_ flags: SIMD16<UInt8>) -> UInt64 {
        let pairs = unsafeBitCast(flags, to: SIMD8<UInt16>.self)
        var r = SIMD8<UInt8>()
        for k in 0..<8 { r[k] = UInt8(truncatingIfNeeded: pairs[k] >> 4) }
        return UInt64(littleEndian: unsafeBitCast(r, to: UInt64.self))
    }

    @inline(__always)
    private static func nibbleMask(_ low: SIMD8<UInt8>, _ high: SIMD8<UInt8>) -> UInt64 {
        let pairs = unsafeBitCast((low, high), to: SIMD8<UInt16>.self)
        var r = SIMD8<UInt8>()
        for k in 0..<8 { r[k] = UInt8(truncatingIfNeeded: pairs[k] >> 4) }
        return UInt64(littleEndian: unsafeBitCast(r, to: UInt64.self))
    }
}
