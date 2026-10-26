#!/usr/bin/env bash
# Devbox supplies Flutter/CMake/pkg-config/GTK headers. Use the runner's existing
# Ubuntu compiler/sysroot so published binaries do not require Nix's glibc.
set -euo pipefail
cd "$(dirname "$0")/../.."
test "$(uname -s)" = Linux
test -x /usr/bin/clang-18
test -x /usr/bin/clang++-18
unset CC CXX LD AR SDKROOT NIX_LDFLAGS NIX_CFLAGS_COMPILE NIX_CC
export PATH="$PWD/tool/ci/linux-tools:$PATH"
export CC=/usr/bin/clang-18 CXX=/usr/bin/clang++-18 LD=/usr/bin/ld AR=/usr/bin/ar
export LDFLAGS=-fuse-ld=/usr/bin/ld
pkg-config --exists gtk+-3.0
flutter --suppress-analytics build linux "$@"
