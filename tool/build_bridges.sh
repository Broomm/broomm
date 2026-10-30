#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
test "$(uname -s)" = Darwin
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
mkdir -p build/native
stage="$(mktemp -d "$PWD/build/native/.bridge-build.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
for major in 2 3; do
  /usr/bin/xcrun clang -arch arm64 -arch x86_64 -dynamiclib -std=c11 -g -O1 -Wall -Wextra -Werror \
    -DBROOMM_SESSION_BRIDGE -DBROOMM_SDL_MAJOR="$major" \
    experiments/injection/src/probe.c experiments/injection/src/cache_redirect.c \
    -framework AppKit -framework CoreGraphics -framework CoreText \
    -o "$stage/broomm-sdl$major.dylib"
done
/usr/bin/xcrun clang -arch arm64 -arch x86_64 -dynamiclib -std=c11 -g -O1 -Wall -Wextra -Werror \
  native/installer_guard.c -framework AppKit -o "$stage/broomm-installer-guard.dylib"
for major in 2 3; do mv "$stage/broomm-sdl$major.dylib" "build/native/broomm-sdl$major.dylib"; done
mv "$stage/broomm-installer-guard.dylib" build/native/broomm-installer-guard.dylib
/usr/bin/xcrun clang -arch arm64 -arch x86_64 -dynamiclib -fobjc-arc -fblocks -std=c11 -g -O1 -Wall -Wextra -Werror \
  native/astris_bridge.m -framework AppKit -framework GameController -Wl,-undefined,dynamic_lookup \
  -o "$stage/broomm-astris.dylib"
mv "$stage/broomm-astris.dylib" build/native/broomm-astris.dylib
for library in build/native/broomm-*.dylib; do
  /usr/bin/codesign --force --sign - "$library"
  /usr/bin/codesign --verify --strict --all-architectures "$library"
done
shasum -a 256 build/native/*.dylib > build/native/SHA256SUMS
