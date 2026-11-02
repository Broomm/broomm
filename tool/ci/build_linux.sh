#!/usr/bin/env bash
# Devbox supplies Flutter/CMake/pkg-config/GTK headers. Use the runner's existing
# Ubuntu compiler/sysroot so published binaries do not require Nix's glibc.
set -euo pipefail
cd "$(dirname "$0")/../.."
test "$(uname -s)" = Linux
export BROOMM_LINUX_CC="${BROOMM_LINUX_CC:-/usr/bin/clang-18}"
export BROOMM_LINUX_CXX="${BROOMM_LINUX_CXX:-/usr/bin/clang++-18}"
test -x "$BROOMM_LINUX_CC"
test -x "$BROOMM_LINUX_CXX"
unset CC CXX LD AR SDKROOT NIX_LDFLAGS NIX_CFLAGS_COMPILE NIX_CC
# Flutter's Nix wrapper adds its newer GTK flags after this script runs. Capture
# the Devbox target graph now; native tool shims restore it after that wrapper.
export BROOMM_LINUX_CMAKE
BROOMM_LINUX_CMAKE="$(command -v cmake)"
export BROOMM_LINUX_PKG_CONFIG_PATH="${PKG_CONFIG_PATH_FOR_TARGET:-${PKG_CONFIG_PATH:-}}"
export PATH="$PWD/tool/ci/linux-tools:$PATH"
export CC="$BROOMM_LINUX_CC" CXX="$BROOMM_LINUX_CXX" LD=/usr/bin/ld AR=/usr/bin/ar
export LDFLAGS=-fuse-ld=/usr/bin/ld
# FindPkgConfig queries both dynamic and static metadata even for shared builds.
# Fail with the complete missing-requirement diagnostic before invoking CMake.
pkg-config --print-errors --cflags --libs gtk+-3.0 glib-2.0 gio-2.0 x11
pkg-config --print-errors --static --cflags --libs gtk+-3.0 glib-2.0 gio-2.0 x11
flutter --suppress-analytics --verbose build linux "$@"
