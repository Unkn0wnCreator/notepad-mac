/*
 * Notepad für macOS – Test-Hilfsfunktionen.
 * LICENSE: LGPL-2.1-or-later
 */

import AppKit

var failures = 0

func check(_ name: String, _ ok: Bool, _ detail: Any = "") {
    print(ok ? "OK  " : "FAIL", name, ok ? "" : "→ \(detail)")
    if !ok { failures += 1 }
}

/// NOTEPAD_SKIP_PERF=1 (GitHub CI, whose shared runners vary in speed by a factor of 2–5 between
/// runs): no benchmarks and no time limits. Locally they always run.
let skipPerformance = ProcessInfo.processInfo.environment["NOTEPAD_SKIP_PERF"] == "1"

/// `check` for time limits and speed ratios; functional results always go through `check`.
func checkPerformance(_ name: String, _ ok: Bool, _ detail: Any = "") {
    if !skipPerformance { check(name, ok, detail) }
}

/// Lets the run loop process pending work (undo groups, layout, notifications).
func spin() {
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
}

/// Reads a private stored property, e.g. the status bar of a window controller.
func ivar<T>(_ object: Any, _ name: String) -> T {
    Mirror(reflecting: object).children.first { $0.label == name }!.value as! T
}

/// Runs the run loop until `condition` holds (or the timeout passes) – for asynchronous
/// work like background syntax highlighting, instead of fixed sleeps that can be flaky.
@discardableResult
func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > deadline { return false }
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    return true
}
