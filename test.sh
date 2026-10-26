#!/bin/bash
# Compiles the app sources (without main.swift) together with Tests/ and runs them.
# Opens a few windows briefly while the UI tests run.
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p build/tests
SOURCES=$(ls Sources/*.swift | grep -v '/main.swift$')
swiftc -swift-version 5 -parse-as-library -sdk "$(xcrun --show-sdk-path)" \
  -framework AppKit -framework PDFKit \
  -o build/tests/notepad-tests $SOURCES Tests/*.swift
build/tests/notepad-tests
