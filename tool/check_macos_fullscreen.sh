#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
mkdir -p .tool-cache/macos-fullscreen
broomm_fixture=$(mktemp -d "$PWD/.tool-cache/macos-fullscreen/native-XXXXXX")
broomm_sdk=$(/usr/bin/xcrun --sdk macosx --show-sdk-path)
/usr/bin/xcrun clang -isysroot "$broomm_sdk" -mmacosx-version-min=13.0 -fobjc-arc -fblocks -c \
  native/macos_window.m -o "$broomm_fixture/window.o"
/usr/bin/xcrun swiftc -sdk "$broomm_sdk" -target "$(uname -m)-apple-macos13.0" \
  -module-cache-path "$PWD/.tool-cache/macos-fullscreen/swift-cache" \
  -import-objc-header native/macos_window.h -framework AppKit \
  tool/check_macos_fullscreen.swift macos/Runner/SessionRecovery.swift \
  "$broomm_fixture/window.o" -o "$broomm_fixture/check"
for broomm_role in Launcher Emulator; do
  broomm_app="$broomm_fixture/$broomm_role.app"
  mkdir -p "$broomm_app/Contents/MacOS"
  cp "$broomm_fixture/check" "$broomm_app/Contents/MacOS/check"
  cat > "$broomm_app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>check</string>
<key>CFBundleIdentifier</key><string>app.broomm.fixture.fullscreen.$broomm_role</string>
<key>CFBundleName</key><string>Broomm Fullscreen Fixture $broomm_role</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
  /usr/bin/codesign --force --sign - --timestamp=none "$broomm_app"
done
broomm_failed=0
for broomm_mode in fullscreen windowed borderless recreated ryubing; do
  "$broomm_fixture/Launcher.app/Contents/MacOS/check" launcher "$broomm_fixture" "$broomm_mode" || broomm_failed=1
done
exit "$broomm_failed"
