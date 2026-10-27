#!/bin/bash
# Builds build/Notepad.app (Universal: Apple Silicon + Intel).
set -euo pipefail
cd "$(dirname "$0")"

APP=build/Notepad.app
SDK=$(xcrun --show-sdk-path)
SWIFTFLAGS=(-O -swift-version 5 -sdk "$SDK" -framework AppKit)

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/tmp

for arch in arm64 x86_64; do
  clang -arch "$arch" -mmacosx-version-min=13.0 -isysroot "$SDK" -O2 -fobjc-arc \
    -c Sources/PlainTextStorage.m -o "build/tmp/PlainTextStorage-$arch.o"
  swiftc "${SWIFTFLAGS[@]}" -target "$arch-apple-macos13.0" -import-objc-header Sources/Notepad-Bridging-Header.h \
    -o "build/tmp/Notepad-$arch" Sources/*.swift "build/tmp/PlainTextStorage-$arch.o"
done
lipo -create -output "$APP/Contents/MacOS/Notepad" build/tmp/Notepad-arm64 build/tmp/Notepad-x86_64

cp Resources/Info.plist "$APP/Contents/Info.plist"
# UI languages: German (keys in the code) and English (Sources/Localization.swift).
cp -R Resources/de.lproj Resources/en.lproj "$APP/Contents/Resources/"

# App icon
swiftc "${SWIFTFLAGS[@]}" -o build/tmp/make-icon Tools/make-icon.swift
build/tmp/make-icon build/tmp/icon-1024.png
ICONSET=build/tmp/AppIcon.iconset
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size build/tmp/icon-1024.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) build/tmp/icon-1024.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$APP"
rm -rf build/tmp
echo "Fertig: $APP"
