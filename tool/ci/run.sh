#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
if [[ "${RUNNER_OS:-}" == Windows ]]; then
  exec bash tool/ci/in_env.sh "$@"
fi
broomm_devbox="$PWD"
case "${TARGET_PLATFORM:-}" in
  linux) broomm_devbox="$PWD/tool/ci/linux" ;;
  android) broomm_devbox="$PWD/tool/ci/android" ;;
esac
exec devbox --config "$broomm_devbox" run -- bash "$PWD/tool/ci/in_env.sh" "$@"
