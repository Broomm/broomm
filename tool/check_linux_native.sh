#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
test "$(uname -s)" = Linux
broomm_compiler="${BROOMM_LINUX_CXX:-/usr/bin/clang++-18}"
broomm_fixture="$(mktemp -d "${TMPDIR:-/tmp}/broomm-kernel-test.XXXXXX")"
trap 'rm -rf -- "$broomm_fixture"' EXIT
broomm_flags=()
if [[ -n "${BROOMM_NATIVE_SANITIZERS:-}" ]]; then
  broomm_flags=('-fsanitize=address,undefined' -fno-omit-frame-pointer)
fi
env -u LIBRARY_PATH -u LD_LIBRARY_PATH "$broomm_compiler" -std=c++14 -Wall -Wextra -Werror \
  "${broomm_flags[@]}" \
  tool/fixtures/linux_kernel_test.cc -o "$broomm_fixture/check"
"$broomm_fixture/check" "$broomm_fixture"

# Exercise the shipped process supervisor independently of the kernel adapter.
broomm_c_compiler="${BROOMM_LINUX_CC:-/usr/bin/clang-18}"
env -u LIBRARY_PATH -u LD_LIBRARY_PATH "$broomm_c_compiler" -std=c11 -Wall -Wextra -Werror \
  "${broomm_flags[@]}" native/linux_process.c -o "$broomm_fixture/native-run"
env -u LIBRARY_PATH -u LD_LIBRARY_PATH "$broomm_compiler" -std=c++14 -Wall -Wextra -Werror \
  "${broomm_flags[@]}" tool/fixtures/linux_process_test.cc -o "$broomm_fixture/process-check"
mkdir "$broomm_fixture/process-data"
"$broomm_fixture/process-check" "$broomm_fixture/native-run" "$broomm_fixture/process-check" "$broomm_fixture/process-data"
env -u LIBRARY_PATH -u LD_LIBRARY_PATH "$broomm_c_compiler" -std=c11 -Wall -Wextra -Werror \
  "${broomm_flags[@]}" -pthread tool/fixtures/linux_control_test.c -ldl -o "$broomm_fixture/control-check"
"$broomm_fixture/control-check"
