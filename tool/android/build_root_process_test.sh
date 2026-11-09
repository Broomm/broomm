#!/usr/bin/env bash
# The NDK is already pinned by the application. Keep this fixture out of APKs.
set -euo pipefail
cd "$(dirname "$0")/../.."
broomm_process_ndk="${1:-${ANDROID_NDK_HOME:-}}"
test -n "$broomm_process_ndk"
rg -q '^Pkg.Revision = 29\.0\.14206865$' "$broomm_process_ndk/source.properties"
case "$(uname -s)" in
  Darwin) broomm_process_host=darwin-x86_64 ;;
  Linux) broomm_process_host=linux-x86_64 ;;
  *) echo 'This fixture build requires the approved macOS/Linux NDK host.' >&2; exit 1 ;;
esac
broomm_process_out="$PWD/.tool-cache/research/android/root-process"
mkdir -p "$broomm_process_out"
"$broomm_process_ndk/toolchains/llvm/prebuilt/$broomm_process_host/bin/aarch64-linux-android24-clang" \
  -std=c11 -Wall -Wextra -Werror -O2 -fPIE -pie -pthread \
  tool/android/check_root_process.c -o "$broomm_process_out/root-process-test-arm64"
"$broomm_process_ndk/ndk-build" NDK_PROJECT_PATH=null \
  APP_BUILD_SCRIPT="$PWD/android/app/src/main/cpp/Android.mk" \
  APP_PLATFORM=android-24 APP_ABI='arm64-v8a armeabi-v7a x86 x86_64' \
  NDK_OUT="$broomm_process_out/obj" NDK_LIBS_OUT="$broomm_process_out/lib"
