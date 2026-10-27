/*
 * Notepad für macOS – Einstiegspunkt der Tests (./test.sh).
 * LICENSE: LGPL-2.1-or-later
 */

import AppKit

@main
enum TestMain {
    static func main() {
        let fixtures = FileManager.default.temporaryDirectory
            .appendingPathComponent("notepad-tests-\(ProcessInfo.processInfo.processIdentifier)")
        try! FileManager.default.createDirectory(at: fixtures, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtures) }

        // Start from default preferences and leave none behind.
        let defaultsDomain = ProcessInfo.processInfo.processName
        UserDefaults.standard.removePersistentDomain(forName: defaultsDomain)
        defer { UserDefaults.standard.removePersistentDomain(forName: defaultsDomain) }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        delegate.applicationWillFinishLaunching(Notification(name: NSApplication.willFinishLaunchingNotification))

        runCodecTests()
        runLatin1DecoderTests()
        runPositionCacheTests()
        runSyntaxTests()
        runLexerTests()
        runRegexPlanTests()
        runConfigSyntaxTests()
        runIncrementalSyntaxTests()
        runFastUTFTests()
        runGapBufferTests()
        runGUITests(app: app, delegate: delegate, fixtures: fixtures)
        runPerformanceTests(fixtures: fixtures)

        print(failures == 0 ? "\nALLE TESTS OK" : "\n\(failures) FEHLER")
        if failures != 0 { exit(1) }
    }
}
