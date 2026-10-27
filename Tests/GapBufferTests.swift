/*
 * Notepad für macOS – Tests und Benchmarks für den Lückenpuffer-Textspeicher.
 * LICENSE: LGPL-2.1-or-later
 */

import AppKit

func runGapBufferTests() {
    let start = Date()
    defer { print("     (Lückenpuffer-Tests insgesamt \(String(format: "%.1f", Date().timeIntervalSince(start))) s)") }
    gapBufferStringTests()
    storageDifferentialTest()
    storageTextViewTests()
    print("     -- dieselben Tests mit dem alten Textspeicher:")
    storageTextViewTests(LegacyTextStorage())
    if skipPerformance {
        print("     (Textspeicher-Benchmarks übersprungen, NOTEPAD_SKIP_PERF=1)")
        return
    }
    storageBenchmark(characters: 200_000_000, label: "200 MB", rounds: 3, legacyKeystrokes: 3)
    if ProcessInfo.processInfo.environment["NOTEPAD_BIG_BENCH"] == "1" {
        storageBenchmark(characters: 1_000_000_000, label: "1 GB", rounds: 3, legacyKeystrokes: 2, big: true)
    } else {
        print("     (1-GB-Benchmark übersprungen; NOTEPAD_BIG_BENCH=1 setzen)")
    }
}

/// Deterministic random numbers (SplitMix64), so a failing sequence can be replayed.
private struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private let samplePieces = ["a", "b", "Z", " ", "\n", "ä", "ö", "ü", "😀", "👍🏽", "漢", "字", "\t", "xyz", "Lorem ipsum ", "\u{301}"]

/// Mostly Latin-1 (kept with one byte per character); rarely a wider character.
private let latinPieces = ["a", "b", " ", "\n", "ä", "ß", "é", "xyz", "Lorem ipsum ", "\u{FF}", "\u{7F}"]

private func randomText(_ rng: inout SeededRandom, maxPieces: Int, pieces: [String] = samplePieces) -> String {
    let count = Int.random(in: 0...maxPieces, using: &rng)
    return (0..<count).map { _ in pieces.randomElement(using: &rng)! }.joined()
}

private func randomRange(_ rng: inout SeededRandom, length: Int) -> NSRange {
    let location = Int.random(in: 0...length, using: &rng)
    let rangeLength = Int.random(in: 0...min(length - location, 12), using: &rng)
    return NSRange(location: location, length: rangeLength)
}

// MARK: - GapBufferString

private func gapBufferStringTests() {
    gapBufferRandomTest(name: "gemischt", pieces: samplePieces, wideEvery: 0)
    gapBufferRandomTest(name: "Latin-1 (1 Byte pro Zeichen)", pieces: latinPieces, wideEvery: 900)
    gapBufferAPITests()
}

/// Random edits compared against NSMutableString. `wideEvery`: insert a character > U+00FF
/// every n steps (otherwise the text stays Latin-1).
private func gapBufferRandomTest(name: String, pieces: [String], wideEvery: Int) {
    var rng = SeededRandom(state: 42)
    let gap = GapBufferString()
    let reference = NSMutableString()
    var ok = true
    var detail = ""
    for step in 0..<5000 {
        let length = reference.length
        var range = randomRange(&rng, length: length)
        if step % 500 == 499 { range = NSRange(location: 0, length: length) }
        if length > 3000 { range.length = min(length - range.location, 200) }
        var text = randomText(&rng, maxPieces: 6, pieces: pieces)
        if wideEvery > 0 && step % wideEvery == wideEvery - 1 { text += "€😀" }
        gap.replaceCharacters(in: range, with: text)
        reference.replaceCharacters(in: range, with: text)
        if gap.length != reference.length || !gap.isEqual(to: reference as String) {
            ok = false; detail = "Schritt \(step): Inhalt weicht ab"; break
        }
        // Random reads around and across the gap.
        let newLength = reference.length
        if newLength > 0 {
            let probe = randomRange(&rng, length: newLength)
            var a = [unichar](repeating: 0, count: probe.length)
            var b = [unichar](repeating: 0, count: probe.length)
            gap.getCharacters(&a, range: probe)
            reference.getCharacters(&b, range: probe)
            let index = Int.random(in: 0..<newLength, using: &rng)
            if a != b || gap.character(at: index) != reference.character(at: index)
                || gap.substring(with: probe) != reference.substring(with: probe)
                || (step % 97 == 0 && !(gap.copy() as! NSString).isEqual(to: reference as String)) {
                ok = false; detail = "Schritt \(step): Lesen \(probe) weicht ab"; break
            }
        }
    }
    check("Lückenpuffer: 5000 zufällige Änderungen wie NSMutableString, \(name)", ok, detail)
}

private func gapBufferAPITests() {
    // Snapshots of narrow (ASCII / Latin-1) and wide contents, with the gap in the middle.
    for sample in ["Hallo Welt", "Grüße aus Köln", "Grüße € 😀"] {
        let g = GapBufferString(string: sample)
        g.replaceCharacters(in: NSRange(location: 3, length: 0), with: "ab")
        g.replaceCharacters(in: NSRange(location: 3, length: 2), with: "")
        let copy = g.copy() as! NSString
        check("Lückenpuffer: Schnappschuss \(sample)", copy.isEqual(to: sample) && g.substring(from: 2) == String(sample.dropFirst(2)), copy)
    }

    // Self-insertion, copies and the NSString API used by the Swift code.
    let s = GapBufferString(string: "Hallo\nWelt\n")
    s.replaceCharacters(in: NSRange(location: 5, length: 0), with: s as String)
    check("Lückenpuffer: sich selbst einfügen", s.isEqual(to: "HalloHallo\nWelt\n\nWelt\n"), s)
    s.replaceCharacters(in: NSRange(location: 3, length: 0), with: "äöü")
    let snapshot = s.copy() as! NSString
    s.replaceCharacters(in: NSRange(location: 0, length: 1), with: "X")
    check("Lückenpuffer: copy ist unabhängiger Schnappschuss",
          snapshot.isEqual(to: "HaläöüloHallo\nWelt\n\nWelt\n") && !(snapshot is GapBufferString), snapshot)
    check("Lückenpuffer: range(of:)", s.range(of: "Welt").location == 14, s.range(of: "Welt"))
    check("Lückenpuffer: lineRange", s.lineRange(for: NSRange(location: 15, length: 0)) == NSRange(location: 14, length: 5),
          s.lineRange(for: NSRange(location: 15, length: 0)))
    check("Lückenpuffer: data(using:)", s.data(using: String.Encoding.utf8.rawValue) == "XaläöüloHallo\nWelt\n\nWelt\n".data(using: .utf8))
    let regex = try! NSRegularExpression(pattern: "W\\w+")
    check("Lückenpuffer: NSRegularExpression", regex.numberOfMatches(in: s as String, range: NSRange(location: 0, length: s.length)) == 2)
    let mutable = s.mutableCopy() as! NSMutableString
    mutable.append("!")
    check("Lückenpuffer: mutableCopy unabhängig", mutable.length == s.length + 1)
    s.setString("")
    check("Lückenpuffer: leeren", s.length == 0 && (s.copy() as! NSString).length == 0)
}

// MARK: - PlainTextStorage vs. NSMutableAttributedString

private func storageDifferentialTest() {
    var rng = SeededRandom(state: 7)
    let fontA: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12)]
    let fontB: [NSAttributedString.Key: Any] = [.font: NSFont.userFixedPitchFont(ofSize: 13)!]
    let underlined: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .underlineStyle: 1]
    let colored: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.red]
    let choices: [[NSAttributedString.Key: Any]?] = [fontA, fontB, underlined, colored, [:], nil,
                                                     [.font: NSFont.systemFont(ofSize: 12)]]   // equal to fontA, other instance

    let storage = PlainTextStorage()
    let reference = NSMutableAttributedString()
    var ok = true
    var detail = ""
    var operations = 0

    func compare(_ step: Int) -> Bool {
        let length = reference.length
        guard storage.length == length, storage.backingString.isEqual(to: reference.string) else {
            detail = "Schritt \(step): Text weicht ab: \(storage.backingString) vs. \(reference.string)"
            return false
        }
        // Walk all runs: attributes equal and effective ranges maximal like the reference's.
        var index = 0
        while index < length {
            var mine = NSRange(), longest = NSRange()
            let a = storage.attributes(at: index, effectiveRange: &mine)
            let b = reference.attributes(at: index, longestEffectiveRange: &longest,
                                         in: NSRange(location: 0, length: length))
            guard NSDictionary(dictionary: a).isEqual(to: b), mine == longest else {
                detail = "Schritt \(step), Index \(index): \(a) \(mine) vs. \(b) \(longest)"
                return false
            }
            index = NSMaxRange(mine)
        }
        // Random single lookups (exercise the lookup hint from all directions).
        for _ in 0..<4 where length > 0 {
            let i = Int.random(in: 0..<length, using: &rng)
            var mine = NSRange(), longest = NSRange()
            let a = storage.attributes(at: i, effectiveRange: &mine)
            let b = reference.attributes(at: i, longestEffectiveRange: &longest, in: NSRange(location: 0, length: length))
            guard NSDictionary(dictionary: a).isEqual(to: b), mine == longest else {
                detail = "Schritt \(step), Stichprobe \(i): \(a) \(mine) vs. \(b) \(longest)"
                return false
            }
        }
        return true
    }

    for step in 0..<6000 where ok {
        let length = reference.length
        let kind = Int.random(in: 0..<100, using: &rng)
        if kind < 35 {
            // Attribute change on a random range.
            var range = randomRange(&rng, length: length)
            if kind < 3 { range = NSRange(location: 0, length: length) }
            let attrs = choices.randomElement(using: &rng)!
            storage.setAttributes(attrs, range: range)
            reference.setAttributes(attrs, range: range)
        } else {
            var range = randomRange(&rng, length: length)
            var text = randomText(&rng, maxPieces: 5)
            switch kind {
            case 35..<40: range = NSRange(location: 0, length: length)         // replace everything
            case 40..<55: text = ""                                            // delete
            case 55..<75: range.length = 0                                     // insert
            default: break
            }
            if length > 600 { range.length = min(length - range.location, 60); text = "" }
            storage.replaceCharacters(in: range, with: text)
            reference.replaceCharacters(in: range, with: text)
        }
        operations += 1
        ok = compare(step)
    }
    check("Textspeicher: \(operations) zufällige Änderungen wie NSMutableAttributedString", ok, detail)
    check("Textspeicher: string ist backingString (keine Kopie)",
          (storage.value(forKey: "string") as AnyObject) === storage.backingString)

    let initialized = PlainTextStorage(string: "Hallo", attributes: fontA)
    check("Textspeicher: init(string:attributes:)", initialized.backingString.isEqual(to: "Hallo")
          && initialized.attribute(.font, at: 4, effectiveRange: nil) as? NSFont == fontA[.font] as? NSFont)
}

// MARK: - NSTextView integration

private func makeEditor(_ storage: NSTextStorage) -> (NSWindow, NSTextView) {
    let layoutManager = NSLayoutManager()
    layoutManager.allowsNonContiguousLayout = true
    storage.addLayoutManager(layoutManager)
    let container = NSTextContainer(size: NSSize(width: 780, height: CGFloat.greatestFiniteMagnitude))
    container.widthTracksTextView = true
    layoutManager.addTextContainer(container)
    let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 800, height: 600),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let scrollView = NSScrollView(frame: window.contentView!.bounds)
    scrollView.autoresizingMask = [.width, .height]
    scrollView.hasVerticalScroller = true
    let textView = NSTextView(frame: NSRect(origin: .zero, size: scrollView.contentSize), textContainer: container)
    textView.autoresizingMask = [.width]
    textView.isVerticallyResizable = true
    textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    textView.isRichText = false
    textView.allowsUndo = true
    textView.font = NSFont.userFixedPitchFont(ofSize: 13)
    textView.isContinuousSpellCheckingEnabled = false
    textView.isAutomaticSpellingCorrectionEnabled = false
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticTextReplacementEnabled = false
    scrollView.documentView = textView
    window.contentView!.addSubview(scrollView)
    window.orderFrontRegardless()
    // Let the window server show the window; before that, display calls draw nothing.
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    return (window, textView)
}

/// Closes the window and frees the text: storage, layout manager, container and text view
/// keep each other alive until the layout manager is removed from the storage.
private func closeEditor(_ window: NSWindow, _ textView: NSTextView) {
    window.close()
    if let layoutManager = textView.layoutManager {
        layoutManager.textStorage?.removeLayoutManager(layoutManager)
    }
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
}

private func storageTextViewTests(_ storage: NSTextStorage = PlainTextStorage()) {
    let (window, tv) = makeEditor(storage)
    defer { closeEditor(window, tv) }
    let undo = tv.undoManager!
    undo.removeAllActions()

    tv.insertText("Hallo Welt\n", replacementRange: NSRange(location: NSNotFound, length: 0))
    tv.breakUndoCoalescing()
    spin()
    tv.setSelectedRange(NSRange(location: 0, length: 0))
    tv.insertText("Ä😀漢 ", replacementRange: NSRange(location: NSNotFound, length: 0))
    tv.breakUndoCoalescing()
    spin()
    check("Textansicht: Eingabe", storage.string == "Ä😀漢 Hallo Welt\n", storage.string)

    // Layout fixes attributes lazily (fonts for every character, also emoji/CJK).
    tv.layoutManager!.ensureLayout(for: tv.textContainer!)
    tv.displayIfNeeded()
    let allHaveFonts = (0..<storage.length).allSatisfy { storage.attribute(.font, at: $0, effectiveRange: nil) is NSFont }
    check("Textansicht: Attribute nachträglich ergänzt", allHaveFonts)

    tv.setSelectedRange(NSRange(location: 5, length: 5))
    tv.deleteBackward(nil)
    tv.breakUndoCoalescing()
    spin()
    check("Textansicht: Löschen", storage.string == "Ä😀漢  Welt\n", storage.string)

    undo.undo()
    check("Textansicht: Rückgängig Löschen", storage.string == "Ä😀漢 Hallo Welt\n", storage.string)
    undo.undo()
    check("Textansicht: Rückgängig Eingabe", storage.string == "Hallo Welt\n", storage.string)
    undo.redo()
    undo.redo()
    check("Textansicht: Wiederholen", storage.string == "Ä😀漢  Welt\n", storage.string)

    // Marked text (input method) sets attributes on a sub-range, then commits.
    tv.setSelectedRange(NSRange(location: storage.length, length: 0))
    tv.setMarkedText("かな", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
    let marked = tv.markedRange()
    tv.insertText("仮名", replacementRange: marked)
    spin()
    check("Textansicht: Eingabemethode", storage.string == "Ä😀漢  Welt\n仮名", storage.string)
    check("Textansicht: keine Unterstreichung nach Bestätigung",
          storage.attribute(.underlineStyle, at: storage.length - 1, effectiveRange: nil) == nil)

    tv.string = "neu"
    check("Textansicht: string setzen", storage.string == "neu" && tv.string == "neu")
}

// MARK: - Benchmark

/// Builds `count` characters of repeated Lorem-ipsum lines without per-character work.
/// `compact` uses pure ASCII lines, which NSString stores with one byte per character – the
/// 1 GB benchmark would otherwise need 2 GB just for the source text.
private func makeLargeText(_ count: Int, compact: Bool = false) -> NSString {
    func fill<T>(_ line: [T]) -> UnsafeMutablePointer<T> {
        let buffer = UnsafeMutablePointer<T>.allocate(capacity: count)
        let first = min(line.count, count)
        line.withUnsafeBufferPointer { buffer.update(from: $0.baseAddress!, count: first) }
        var filled = first
        while filled < count {
            let chunk = min(filled, count - filled)
            (buffer + filled).update(from: buffer, count: chunk)
            filled += chunk
        }
        return buffer
    }
    if compact {
        let bytes = fill(Array("Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor aou\n".utf8))
        return NSString(bytesNoCopy: bytes, length: count, encoding: String.Encoding.ascii.rawValue, freeWhenDone: true)!
    }
    let characters = fill(Array("Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor äöü\n".utf16))
    return NSString(charactersNoCopy: characters, length: count, freeWhenDone: true)
}

private func milliseconds(_ body: () -> Void) -> Double {
    let start = DispatchTime.now().uptimeNanoseconds
    body()
    return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
}

/// Bytes in use according to malloc (unlike the footprint not distorted by pages malloc keeps
/// cached after a free). Call `malloc_zone_pressure_relief` first: a cached block reused for a
/// smaller request would count with its full size.
private func mallocInUseMB() -> Double {
    var stats = malloc_statistics_t()
    malloc_zone_statistics(nil, &stats)
    return Double(stats.size_in_use) / 1_048_576
}

/// Loads the text into `storage` alone and returns the time and the memory it takes (the text
/// itself is not counted).
private func loadStorage(_ storage: NSTextStorage, text makeText: () -> NSString) -> (ms: Double, memoryMB: Double) {
    autoreleasepool {
        let text = makeText()
        malloc_zone_pressure_relief(nil, 0)   // no cached, already touched blocks: a cold load
        let baseline = mallocInUseMB()
        let time = milliseconds { storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: text as String) }
        let used = mallocInUseMB() - baseline
        storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: "")
        return (time, used)
    }
}

private struct BenchResult {
    var load = 0.0, firstDisplay = 0.0, jump = 0.0
    var keys: [String: (first: Double, later: [Double])] = [:]
    var snapshot = 0.0, getCharacters = 0.0
    var widen = 0.0
}

private func runBenchmark(_ storage: NSTextStorage, backing: () -> NSString, text makeText: () -> NSString,
                          characters: Int, keystrokes: Int) -> BenchResult {
    var result = BenchResult()
    let (window, tv) = makeEditor(storage)
    defer { closeEditor(window, tv) }
    autoreleasepool {
        let text = makeText()
        malloc_zone_pressure_relief(nil, 0)   // no cached, already touched blocks: a cold load
        result.load = milliseconds { tv.string = text as String }
    }
    result.firstDisplay = milliseconds { tv.displayIfNeeded() }

    let middle = characters / 2
    result.jump = milliseconds {
        tv.setSelectedRange(NSRange(location: middle, length: 0))
        tv.scrollRangeToVisible(NSRange(location: middle, length: 0))
        tv.displayIfNeeded()
    }
    guard keystrokes > 0 else { return result }
    func typeKeys(_ name: String, at position: Int) {
        let location = position < 0 ? storage.length : position
        tv.setSelectedRange(NSRange(location: location, length: 0))
        tv.scrollRangeToVisible(NSRange(location: location, length: 0))
        tv.displayIfNeeded()
        var times: [Double] = []
        for _ in 0..<keystrokes {
            times.append(milliseconds {
                tv.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))
                tv.displayIfNeeded()
            })
        }
        result.keys[name] = (times[0], Array(times.dropFirst()))
    }
    typeKeys("Mitte", at: middle)
    typeKeys("Anfang", at: 0)
    typeKeys("Ende", at: -1)

    // The first character above U+00FF converts 8-bit storage to UTF-16 (both implementations).
    result.widen = milliseconds {
        tv.insertText("€", replacementRange: NSRange(location: NSNotFound, length: 0))
        tv.displayIfNeeded()
    }
    typeKeys("Anfang UTF-16", at: 0)
    typeKeys("Mitte UTF-16", at: middle)

    let string = backing()
    result.snapshot = milliseconds { _ = string.copy() }
    result.getCharacters = milliseconds {
        let chunk = 65536
        var buffer = [unichar](repeating: 0, count: chunk)
        var location = 0, sum = 0
        let length = string.length
        while location < length {
            let n = min(chunk, length - location)
            string.getCharacters(&buffer, range: NSRange(location: location, length: n))
            sum &+= Int(buffer[n - 1])
            location += n
        }
        if sum == 42 { print("") }   // keep the loop from being optimized away
    }
    return result
}

private func format(_ value: Double) -> String { String(format: "%7.1f", value) }

/// `big`: compact source text generated per run and freed right after loading
/// (keeps the peak memory of the 1 GB run around 5 GB on an 8 GB Mac).
private func storageBenchmark(characters: Int, label: String, rounds: Int, legacyKeystrokes: Int, big: Bool = false) {
    let keystrokes = 6
    var legacy = BenchResult(), gap = BenchResult()
    var legacyMemory = 0.0, gapMemory = 0.0, legacyStorageLoad = 0.0, gapStorageLoad = 0.0
    var legacyLoads: [Double] = [], gapLoads: [Double] = [], legacyJumps: [Double] = [], gapJumps: [Double] = []
    // Loading with a text view and jumping are noisy (page faults, malloc reusing freed
    // blocks, other processes): alternate the order over several rounds and compare the best
    // times. Keystrokes etc. only in the last round.
    autoreleasepool {
        let shared = big ? nil : makeLargeText(characters)
        let text = { shared ?? makeLargeText(characters, compact: true) }
        // Load into the storage alone (time and memory), alternating the order.
        var gapStorageLoads: [Double] = [], legacyStorageLoads: [Double] = []
        for round in 0..<rounds {
            if round % 2 == 1 { legacyStorageLoads.append(loadStorage(LegacyTextStorage(), text: text).ms) }
            let gapLoad = loadStorage(PlainTextStorage(), text: text)
            gapStorageLoads.append(gapLoad.ms)
            gapMemory = gapLoad.memoryMB
            if round % 2 == 0 {
                let legacyLoad = loadStorage(LegacyTextStorage(), text: text)
                legacyStorageLoads.append(legacyLoad.ms)
                legacyMemory = legacyLoad.memoryMB
            }
        }
        gapStorageLoad = gapStorageLoads.min()!
        legacyStorageLoad = legacyStorageLoads.min()!
        for round in 0..<rounds {
            let last = round == rounds - 1
            func runLegacy() {
                autoreleasepool {
                    let storage = LegacyTextStorage()
                    legacy = runBenchmark(storage, backing: { storage.backingString }, text: text, characters: characters,
                                          keystrokes: last ? legacyKeystrokes : 0)
                }
            }
            func runGap() {
                autoreleasepool {
                    let storage = PlainTextStorage()
                    gap = runBenchmark(storage, backing: { storage.backingString }, text: text, characters: characters,
                                       keystrokes: last ? keystrokes : 0)
                }
            }
            if round % 2 == 0 { runLegacy(); runGap() } else { runGap(); runLegacy() }
            legacyLoads.append(legacy.load); gapLoads.append(gap.load)
            legacyJumps.append(legacy.jump); gapJumps.append(gap.jump)
        }
    }
    legacy.load = legacyLoads.min()!; gap.load = gapLoads.min()!
    legacy.jump = legacyJumps.min()!; gap.jump = gapJumps.min()!

    // Median of the keystrokes after the first one (single outliers come from page faults or
    // other processes), and their maximum.
    func later(_ r: BenchResult, _ key: String) -> Double {
        let times = r.keys[key]!.later.sorted()
        return times.isEmpty ? .nan : times[times.count / 2]
    }
    func worst(_ r: BenchResult, _ key: String) -> Double { r.keys[key]!.later.max() ?? .nan }
    func row(_ name: String, _ old: String, _ new: String) {
        print("       \(name.padding(toLength: 40, withPad: " ", startingAt: 0)) \(old) | \(new)")
    }
    func row(_ name: String, _ old: Double, _ new: Double) { row(name, format(old), format(new)) }
    func keyRow(_ key: String) {
        func cell(_ r: BenchResult) -> String {
            "\(format(r.keys[key]!.first))/\(format(later(r, key)))/\(format(worst(r, key)))"
        }
        row("Taste \(key) erste/weitere/max.", cell(legacy), cell(gap))
    }
    print("     Textspeicher \(label) (\(characters / 1_000_000) Mio. Zeichen), ms – alt (NSMutableAttributedString) | neu (Lückenpuffer)")
    row("Laden in Textspeicher allein (Bestwert)", legacyStorageLoad, gapStorageLoad)
    row("Laden mit Textansicht (Bestwert)", legacy.load, gap.load)
    row("erste Anzeige", legacy.firstDisplay, gap.firstDisplay)
    row("Sprung zur Mitte (Bestwert)", legacy.jump, gap.jump)
    row("Speicher Textspeicher, MB", legacyMemory, gapMemory)
    for key in ["Mitte", "Anfang", "Ende"] { keyRow(key) }
    row("copy() Schnappschuss", legacy.snapshot, gap.snapshot)
    row("getCharacters über alles", legacy.getCharacters, gap.getCharacters)
    row("erstes Zeichen > U+00FF", legacy.widen, gap.widen)
    for key in ["Anfang UTF-16", "Mitte UTF-16"] { keyRow(key) }

    // Small absolute slack on top of 20 % so scheduler noise on tiny numbers cannot fail the run.
    check("Textspeicher \(label): Laden höchstens 20 % langsamer", gapStorageLoad <= legacyStorageLoad * 1.2 + 10,
          "\(gapStorageLoad) vs. \(legacyStorageLoad)")
    check("Textspeicher \(label): Sprung höchstens 20 % langsamer", gap.jump <= legacy.jump * 1.2 + 10, "\(gap.jump) vs. \(legacy.jump)")
    for key in ["Anfang", "Mitte", "Ende", "Anfang UTF-16", "Mitte UTF-16"] {
        check("Textspeicher \(label): weitere Tastendrücke \(key) < 20 ms (Median)", later(gap, key) < 20, gap.keys[key]!.later)
    }
}
