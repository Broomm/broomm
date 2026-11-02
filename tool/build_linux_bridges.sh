#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
test "$(uname -s)" = Linux
# Match the native host ABI, as the existing Linux application build does.
# CI uses its approved Ubuntu compiler; local native checks may point to their
# already provisioned host compiler without changing any SDK selection.
broomm_linux_cc="${BROOMM_LINUX_CC:-/usr/bin/clang-18}"
test -x "$broomm_linux_cc"
mkdir -p build/native
stage="$(mktemp -d "$PWD/build/native/.linux-build.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
"$broomm_linux_cc" -std=c11 -shared -fPIC -O1 -g -Wall -Wextra -Werror \
  -pthread native/linux_retroarch.c -ldl -o "$stage/broomm-retroarch.so"
mv "$stage/broomm-retroarch.so" build/native/broomm-retroarch.so
"$broomm_linux_cc" -std=c11 -O1 -g -Wall -Wextra -Werror \
  native/linux_process.c -o "$stage/broomm-native-run"
mv "$stage/broomm-native-run" build/native/broomm-native-run
"$broomm_linux_cc" -std=c11 -shared -fPIC -O1 -g -Wall -Wextra -Werror \
  native/linux_installer.c -ldl -o "$stage/broomm-installer.so"
mv "$stage/broomm-installer.so" build/native/broomm-installer.so
for broomm_sdl in 2 3; do
  read -r -a broomm_x11_flags <<< "$(pkg-config --cflags x11)"
  "$broomm_linux_cc" -std=c11 -shared -fPIC -O1 -g -Wall -Wextra -Werror \
    "${broomm_x11_flags[@]}" -DBROOMM_SDL_MAJOR="$broomm_sdl" -pthread native/linux_bridge.c -ldl -lm \
    -o "$stage/broomm-sdl$broomm_sdl.so"
  mv "$stage/broomm-sdl$broomm_sdl.so" "build/native/broomm-sdl$broomm_sdl.so"
done
sha256sum build/native/broomm-retroarch.so > build/native/linux-SHA256SUMS
