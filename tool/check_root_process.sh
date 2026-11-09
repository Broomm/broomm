#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
test "$(uname -s)" = Linux || { echo 'This check exercises the native Linux kernel.' >&2; exit 1; }
mkdir -p build/native-linux-checks
broomm_process_flags=(-std=c11 -Wall -Wextra -Werror -O1 -g -pthread)
if [[ "${BROOMM_NATIVE_SANITIZERS:-0}" == 1 ]]; then
  broomm_process_flags+=(-fsanitize=address,undefined -fno-omit-frame-pointer)
fi
"${CC:-cc}" "${broomm_process_flags[@]}" tool/android/check_root_process.c \
  -o build/native-linux-checks/root-process-test
build/native-linux-checks/root-process-test
