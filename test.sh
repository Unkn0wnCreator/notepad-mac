#!/bin/bash
# Compiles the app sources (without main.swift) together with Tests/ and runs them.
# Opens a few windows briefly while the UI tests run.
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p build/tests
SDK=$(xcrun --show-sdk-path)
SOURCES=$(ls Sources/*.swift | grep -v '/main.swift$')
# Optimized like the release build, so the performance tests measure real numbers.
clang -O2 -fobjc-arc -isysroot "$SDK" -c Sources/PlainTextStorage.m -o build/tests/PlainTextStorage.o
swiftc -O -swift-version 5 -parse-as-library -sdk "$SDK" -import-objc-header Sources/Notepad-Bridging-Header.h \
  -framework AppKit -framework PDFKit \
  -o build/tests/notepad-tests $SOURCES Tests/*.swift build/tests/PlainTextStorage.o
build/tests/notepad-tests
