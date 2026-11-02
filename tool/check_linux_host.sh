#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
test "$(uname -s)" = Linux
broomm_fixture="$(mktemp -d "${TMPDIR:-/tmp}/broomm-host-test.XXXXXX")"
trap 'rm -rf -- "$broomm_fixture"' EXIT
broomm_engine="$PWD/linux/flutter/ephemeral"
broomm_executable="$broomm_fixture/data/emulators/retroarch/$(printf '1%.0s' {1..64})/RetroArch/retroarch"
broomm_profile="$broomm_fixture/data/profiles/$(printf 'a%.0s' {1..32})/emulators/retroarch"
mkdir -p "$(dirname "$broomm_executable")" "$broomm_profile"
read -r -a broomm_gtk_flags <<< "$(pkg-config --cflags --libs gtk+-3.0 gio-2.0)"
env -u LIBRARY_PATH -u LD_LIBRARY_PATH "${BROOMM_LINUX_CXX:-/usr/bin/clang++-18}" \
  -std=c++14 -Wall -Wextra -Werror -Wno-unused-parameter -I"$broomm_engine" \
  tool/fixtures/linux_host_test.cc -L"$broomm_engine" -lflutter_linux_gtk \
  -Wl,-rpath,"$broomm_engine" "${broomm_gtk_flags[@]}" -o "$broomm_executable"
"$broomm_executable" "$broomm_fixture/data" "$broomm_executable" "$broomm_profile"
mkdir -p build/native-linux-checks
cp "$broomm_executable" build/native-linux-checks/host-probe
