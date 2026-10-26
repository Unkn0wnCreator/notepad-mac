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

/// Lets the run loop process pending work (undo groups, layout, notifications).
func spin() {
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
}

/// Reads a private stored property, e.g. the status bar of a window controller.
func ivar<T>(_ object: Any, _ name: String) -> T {
    Mirror(reflecting: object).children.first { $0.label == name }!.value as! T
}
