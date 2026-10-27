#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
broomm_apple_tools="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin"
broomm_apple_sdk="$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
mkdir -p .tool-cache/session-recovery
broomm_fixture=$(mktemp -d "$PWD/.tool-cache/session-recovery/native-XXXXXX")
mkdir -p "$broomm_fixture/emulators/Writer.app/Contents/MacOS"
cat > "$broomm_fixture/emulators/Writer.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleExecutable</key><string>Writer</string><key>CFBundleIdentifier</key><string>app.broomm.fixture.writer</string><key>CFBundleName</key><string>Broomm Writer Fixture</string><key>CFBundlePackageType</key><string>APPL</string><key>LSBackgroundOnly</key><true/></dict></plist>
PLIST
"$broomm_apple_tools/clang" -isysroot "$broomm_apple_sdk" -framework Cocoa tool/fixtures/session_writer.m -o "$broomm_fixture/emulators/Writer.app/Contents/MacOS/Writer"
/usr/bin/codesign --force --sign - --timestamp=none "$broomm_fixture/emulators/Writer.app"
"$broomm_apple_tools/swiftc" -module-cache-path "$PWD/.tool-cache/session-recovery/swift-cache" -target "$(uname -m)-apple-macos13.0" -sdk "$broomm_apple_sdk" macos/Runner/SessionRecovery.swift tool/check_session_recovery.swift -o "$broomm_fixture/check"
"$broomm_fixture/check" "$broomm_fixture"
