#!/usr/bin/env bash
# Devbox runs in its config directory; every CI command runs at the repo root.
set -euo pipefail
cd "$(dirname "$0")/../.."
broomm_cache_root="$PWD"
if [[ "${RUNNER_OS:-}" == Windows ]]; then
  broomm_cache_root="$(pwd -W)"
  # Nested Android captures exceed MAX_PATH beneath the user-profile Temp.
  # This is child-scoped runner scratch storage, never a system setting.
  if [[ -n "${RUNNER_TEMP:-}" ]]; then
    export TEMP="$RUNNER_TEMP" TMP="$RUNNER_TEMP"
  fi
fi
export PUB_CACHE="$broomm_cache_root/.tool-cache/pub"
export GRADLE_USER_HOME="$broomm_cache_root/.tool-cache/android/gradle"
export FLUTTER_SUPPRESS_ANALYTICS=true DART_SUPPRESS_ANALYTICS=true CI=true
if [[ "$(uname -s)" == Darwin ]]; then
  # Native Dart assets introduced by path_provider's Objective-C bindings need
  # Apple's compiler/SDK, just like the app. Keep selection child-scoped.
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  export PATH="$PWD/tool/apple_tools:$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin:/usr/bin:/bin:$PATH"
  unset CC CXX LD AR SDKROOT NIX_LDFLAGS NIX_CFLAGS_COMPILE NIX_CC
  export SDKROOT
  SDKROOT="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"
fi
if [[ "${TARGET_PLATFORM:-}" == android ]]; then
  # Ignore the hosted runner's inherited JAVA_HOME; use this Devbox's JDK.
  broomm_java="$(readlink -f "$(command -v java)")"
  JAVA_HOME="$(dirname "$(dirname "$broomm_java")")"
  export JAVA_HOME
  broomm_java_version="$("$JAVA_HOME/bin/java" --version)"
  if [[ "$broomm_java_version" != 'openjdk 21.'* ]]; then
    echo 'Android CI requires the pinned Devbox JDK 21.' >&2; exit 1
  fi
fi
exec "$@"
