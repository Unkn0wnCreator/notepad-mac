/*
 * Notepad für macOS – Tests und Messung für die schnelle UTF-8-Umwandlung (FastUTF.swift).
 * LICENSE: LGPL-2.1-or-later
 */

import Foundation

func runFastUTFTests() {
    print("== FastUTF")
    fastUTFDecodeTests()
    fastUTFEncodeTests()
    fastUTFBenchmark()
}

/// Deterministic generator so failures are reproducible.
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Random text mixing ASCII runs, umlauts, CJK, emoji, all line ending kinds and NULs.
private func randomUnits(_ rng: inout SplitMix64, length: Int, loneSurrogates: Bool = false) -> [UInt16] {
    let pools: [[UInt16]] = [
        Array("abcdefghijklmnopqrstuvwxyz ABC 0123456789.,;".utf16),
        Array("äöüÄÖÜß€©".utf16),
        Array("日本語中文한국어".utf16),
        Array("😀🎉👍🏽𝄞".utf16),           // surrogate pairs
        [0x0A, 0x0D, 0x0D, 0x0A, 0x00],
    ]
    var units: [UInt16] = []
    units.reserveCapacity(length + 2)
    while units.count < length {
        let r = Int.random(in: 0..<100, using: &rng)
        if r < 60 {
            // ASCII run, sometimes long enough for the SIMD path
            let run = Int.random(in: 1...40, using: &rng)
            for _ in 0..<run { units.append(pools[0].randomElement(using: &rng)!) }
        } else if r < 70 {
            units.append(pools[1].randomElement(using: &rng)!)
        } else if r < 75 {
            units.append(pools[2].randomElement(using: &rng)!)
        } else if r < 80 {
            let pairs = pools[3]
            let k = Int.random(in: 0..<(pairs.count / 2), using: &rng) * 2
            units.append(pairs[k]); units.append(pairs[k + 1])
        } else if r < 98 || !loneSurrogates {
            units.append(pools[4].randomElement(using: &rng)!)
        } else {
            units.append(Bool.random(using: &rng) ? 0xD83D : 0xDE00)
        }
    }
    return units
}

/// Reference normalization (same rules as TextCodec.normalize) on UTF-16 units.
private func referenceNormalize(_ units: [UInt16]) -> (units: [UInt16], crlf: Int, lf: Int, cr: Int) {
    var result: [UInt16] = []
    result.reserveCapacity(units.count)
    var crlf = 0, lf = 0, cr = 0, i = 0
    while i < units.count {
        let c = units[i]
        if c == 0x0D {
            if i + 1 < units.count && units[i + 1] == 0x0A { crlf += 1; i += 1 } else { cr += 1 }
            result.append(0x0A)
        } else if c == 0x0A {
            lf += 1
            result.append(0x0A)
        } else {
            result.append(c == 0 ? 0x20 : c)
        }
        i += 1
    }
    return (result, crlf, lf, cr)
}

private func decode(_ bytes: [UInt8]) -> FastUTF.Decoded? {
    bytes.withUnsafeBufferPointer { FastUTF.decodeUTF8($0.baseAddress ?? UnsafePointer(bitPattern: 1)!, count: $0.count) }
}

private func units(of text: NSString) -> [UInt16] {
    var result = [UInt16](repeating: 0, count: text.length)
    text.getCharacters(&result, range: NSRange(location: 0, length: text.length))
    return result
}

private func fastUTFDecodeTests() {
    var rng = SplitMix64(state: 0x5EED)
    var mismatches = 0, invalidMisses = 0
    for round in 0..<1500 {
        let length = round < 100 ? round : Int.random(in: 0...5000, using: &rng)
        let source = randomUnits(&rng, length: length)
        let bytes = Array(String(decoding: source, as: UTF16.self).utf8)

        // Valid input: same text as Foundation, plus normalization.
        let foundation = NSString(bytes: bytes, length: bytes.count, encoding: String.Encoding.utf8.rawValue)!
        let expected = referenceNormalize(units(of: foundation))
        if let d = decode(bytes), units(of: d.text) == expected.units,
           d.crlfCount == expected.crlf, d.lfCount == expected.lf, d.crCount == expected.cr {
        } else {
            mismatches += 1
            if mismatches == 1 { print("     erster Fehler bei Runde \(round), Länge \(bytes.count)") }
        }

        // Invalid input: break one position; FastUTF must agree with Foundation on validity.
        if !bytes.isEmpty {
            var broken = bytes
            let bad: [UInt8] = [0x80, 0xBF, 0xC0, 0xC1, 0xF5, 0xFF, 0xED, 0xE0, 0xF4]
            broken[Int.random(in: 0..<broken.count, using: &rng)] = bad.randomElement(using: &rng)!
            let foundationOK = NSString(bytes: broken, length: broken.count, encoding: String.Encoding.utf8.rawValue) != nil
            if (decode(broken) != nil) != foundationOK { invalidMisses += 1 }
        }
    }
    check("FastUTF decode = Foundation + Normalisierung (1500 Zufallstexte)", mismatches == 0, mismatches)
    check("FastUTF decode erkennt ungültiges UTF-8 wie Foundation", invalidMisses == 0, invalidMisses)

    // Explicit invalid sequences, also right after a SIMD block and at the very end.
    let invalid: [(String, [UInt8])] = [
        ("überlang C0 AF", [0xC0, 0xAF]),
        ("überlang E0 80 AF", [0xE0, 0x80, 0xAF]),
        ("überlang F0 80 80 AF", [0xF0, 0x80, 0x80, 0xAF]),
        ("Surrogat ED A0 80", [0xED, 0xA0, 0x80]),
        ("Surrogat ED BF BF", [0xED, 0xBF, 0xBF]),
        ("> U+10FFFF F4 90 80 80", [0xF4, 0x90, 0x80, 0x80]),
        ("F5", [0xF5, 0x80, 0x80, 0x80]),
        ("einzelnes Folgebyte", [0x80]),
        ("abgeschnitten C3", [0xC3]),
        ("abgeschnitten E2 82", [0xE2, 0x82]),
        ("abgeschnitten F0 9F 98", [0xF0, 0x9F, 0x98]),
        ("falsches Folgebyte C3 41", [0xC3, 0x41]),
    ]
    let prefix = Array("0123456789abcdef0123456789abcde".utf8)   // 31 bytes
    for (name, seq) in invalid {
        check("FastUTF ungültig: \(name)", decode(seq) == nil && decode(prefix + seq) == nil
              && decode(prefix + seq + Array("tail".utf8)) == nil)
    }
    check("FastUTF gültig: Grenzwerte", decode([0xC2, 0x80, 0xDF, 0xBF, 0xE0, 0xA0, 0x80, 0xED, 0x9F, 0xBF, 0xEE, 0x80, 0x80,
                                               0xF0, 0x90, 0x80, 0x80, 0xF4, 0x8F, 0xBF, 0xBF]).map { units(of: $0.text) }
          == [0x80, 0x7FF, 0x800, 0xD7FF, 0xE000, 0xD800, 0xDC00, 0xDBFF, 0xDFFF])

    // "\r" on every position around block boundaries, followed by "\n" or not.
    var boundaryOK = true
    for pos in 0..<48 {
        for follow in ["\n", "x", "ä", ""] {
            let s = String(repeating: "a", count: pos) + "\r" + follow + String(repeating: "b", count: 20)
            let d = decode(Array(s.utf8))!
            let expected = referenceNormalize(Array(s.utf16))
            if units(of: d.text) != expected.units || d.crlfCount != expected.crlf || d.crCount != expected.cr { boundaryOK = false }
        }
        // Multi-byte sequences starting at every offset of a block.
        let m = String(repeating: "a", count: pos) + "😀€ä" + String(repeating: "b", count: 20)
        if (decode(Array(m.utf8)).map { $0.text as String }) != m { boundaryOK = false }
    }
    check("FastUTF \\r und Mehrbytefolgen an Blockgrenzen", boundaryOK)
    check("FastUTF leere Eingabe", decode([])?.text.length == 0)
    check("FastUTF NUL → Leerzeichen, BOM bleibt", decode([0xEF, 0xBB, 0xBF, 0x61, 0x00]).map { $0.text as String } == "\u{FEFF}a ")
}

private func fastUTFEncodeTests() {
    var rng = SplitMix64(state: 0xC0FFEE)
    let endings = ["\n", "\r\n", "\r"]
    var mismatches = 0, roundtripFails = 0
    for round in 0..<1000 {
        let length = round < 100 ? round : Int.random(in: 0...5000, using: &rng)
        let source = randomUnits(&rng, length: length, loneSurrogates: true)
        // Alternate between CFString storage (direct pointer) and a bridged Swift string (chunked path).
        let text: NSString = round % 2 == 0
            ? NSString(characters: source, length: source.count)
            : String(decoding: source, as: UTF16.self) as NSString
        // Encoding normalizes line breaks but keeps NUL; decoding also turns NUL into a space.
        let normalized = referenceNormalize(units(of: text)).units
        let normalizedString = String(decoding: normalized, as: UTF16.self)   // repairs lone surrogates
        let lineBreaksOnly = (text as String).replacingOccurrences(of: "\r\n", with: "\n", options: .literal)
            .replacingOccurrences(of: "\r", with: "\n", options: .literal)
        for eol in endings {
            let bom = round % 3 == 0
            let data = FastUTF.encodeUTF8(text, lineEnding: eol, bom: bom)
            let expected = (bom ? [0xEF, 0xBB, 0xBF] : []) + Array(lineBreaksOnly.replacingOccurrences(of: "\n", with: eol, options: .literal).utf8)
            if [UInt8](data) != expected { mismatches += 1 }
            let body = Array(data.dropFirst(bom ? 3 : 0))
            if decode(body).map({ units(of: $0.text) }) != Array(normalizedString.utf16) { roundtripFails += 1 }
        }
    }
    check("FastUTF encode = Foundation + Zeilenenden (1000 Zufallstexte × 3)", mismatches == 0, mismatches)
    check("FastUTF decode(encode(x)) == normalisiertes x", roundtripFails == 0, roundtripFails)

    // Chunked path (no direct character pointer) with "\r\n" and a surrogate pair across 64K chunks.
    for split in [65534, 65535, 65536] {
        var units = [UInt16](repeating: 0x61, count: 140_000)
        units[split - 1] = 0x0D; units[split] = 0x0A
        units[split + 65536 - 1] = 0xD83D; units[split + 65536] = 0xDE00
        let text = String(decoding: units, as: UTF16.self) as NSString
        let expected = Array((text as String).replacingOccurrences(of: "\r\n", with: "\n")
                             .replacingOccurrences(of: "\n", with: "\r\n").utf8)
        check("FastUTF encode Chunkgrenze \(split)", [UInt8](FastUTF.encodeUTF8(text, lineEnding: "\r\n", bom: false)) == expected)
    }
    check("FastUTF encode leer", FastUTF.encodeUTF8("", lineEnding: "\n", bom: false).isEmpty
          && FastUTF.encodeUTF8("", lineEnding: "\n", bom: true) == Data([0xEF, 0xBB, 0xBF]))
    check("FastUTF encode eingefügte \\r", FastUTF.encodeUTF8("a\r\nb\rc\n", lineEnding: "\r\n", bom: false)
          == Data("a\r\nb\r\nc\r\n".utf8))
}

/// Global (lazily initialized) so the compiler does not warn about the folded condition.
private var fastUTFOptimizedBuild = !_isDebugAssertConfiguration()

private func fastUTFBenchmark() {
    // ~50 MB of mostly ASCII lines, one word in 20 with umlauts, built from a repeated 1 MB pattern.
    var rng = SplitMix64(state: 42)
    var pattern = [UInt8]()
    let words = ["lorem", "ipsum", "dolor", "sit", "amet", "consectetur", "12345", "{", "}", "=", "x", "return", "value"]
    let umlautWords = ["Grüße", "für", "Größe", "Äpfel", "übrig"]
    while pattern.count < 1 << 20 {
        let n = Int.random(in: 0...14, using: &rng)
        for _ in 0..<n {
            let word = Int.random(in: 0..<20, using: &rng) == 0 ? umlautWords.randomElement(using: &rng)! : words.randomElement(using: &rng)!
            pattern += Array(word.utf8)
            pattern.append(0x20)
        }
        pattern.append(0x0A)
    }
    // Unoptimized builds (./test.sh) run the SIMD code ~100× slower, so measure less there.
    let optimized = fastUTFOptimizedBuild
    let megabytes = optimized ? 50 : 1
    var input = Data(capacity: megabytes * pattern.count)
    for _ in 0..<megabytes { input.append(contentsOf: pattern) }
    let mb = Double(input.count) / 1_000_000

    // Prefer performance cores; on a busy machine default QoS work may land on efficiency cores.
    pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0)
    // Best of 5; results are dropped right away to keep the memory footprint low (~1 GB peak).
    func measure(_ block: () -> Void) -> Double {
        var best = Double.infinity
        for _ in 0..<5 {
            let start = DispatchTime.now().uptimeNanoseconds
            autoreleasepool { block() }
            best = min(best, Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9)
        }
        return best
    }
    func fastDecode(_ data: Data) -> NSString {
        data.withUnsafeBytes { FastUTF.decodeUTF8($0.bindMemory(to: UInt8.self).baseAddress!, count: $0.count)!.text }
    }

    let fastDecodeCRLF: Double = {
        var crlfInput = Data(capacity: input.count + input.count / 20)
        let crlfPattern = pattern.flatMap { $0 == 0x0A ? [0x0D, 0x0A] : [$0] }
        for _ in 0..<megabytes { crlfInput.append(contentsOf: crlfPattern) }
        return measure { _ = fastDecode(crlfInput) }
    }()
    let fastDecodeLF = measure { _ = fastDecode(input) }
    let foundationDecode = measure {
        _ = input.withUnsafeBytes { NSString(bytes: $0.baseAddress!, length: $0.count, encoding: String.Encoding.utf8.rawValue) }
    }
    let decoded = fastDecode(input)
    let fastEncode = measure { _ = FastUTF.encodeUTF8(decoded, lineEnding: "\n", bom: false) }
    let fastEncodeCRLF = measure { _ = FastUTF.encodeUTF8(decoded, lineEnding: "\r\n", bom: false) }
    let foundationEncode = measure { _ = decoded.data(using: String.Encoding.utf8.rawValue) }
    check("FastUTF Benchmark-Roundtrip", FastUTF.encodeUTF8(decoded, lineEnding: "\n", bom: false) == input)

    func rate(_ seconds: Double) -> String { String(format: "%6.0f MB/s (%4.0f ms)", mb / seconds, seconds * 1000) }
    print(String(format: "     %.0f MB:", mb))
    print("     decode FastUTF LF       \(rate(fastDecodeLF))")
    print("     decode FastUTF CRLF     \(rate(fastDecodeCRLF))")
    print("     decode NSString(bytes:) \(rate(foundationDecode))")
    print("     encode FastUTF LF       \(rate(fastEncode))")
    print("     encode FastUTF CRLF     \(rate(fastEncodeCRLF))")
    print("     encode data(using:)     \(rate(foundationEncode))")

    // The speed-ups need an optimized build (-O); ./test.sh builds without optimization.
    if !optimized {
        print("     (unoptimierter Build – Geschwindigkeitsgrenzen nur mit -O geprüft)")
    }
    if optimized {
        check("FastUTF decode ≥ 5× schneller als NSString(bytes:)", foundationDecode / fastDecodeLF >= 5, foundationDecode / fastDecodeLF)
        check("FastUTF encode ≥ 3× schneller als data(using:)", foundationEncode / fastEncode >= 3, foundationEncode / fastEncode)
    }
}
