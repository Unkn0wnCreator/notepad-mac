/*
 * Notepad für macOS – Einstiegspunkt.
 * LICENSE: LGPL-2.1-or-later
 */

import AppKit

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
