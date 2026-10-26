#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../../.."
test "$(uname -s)" = Darwin
test "$(uname -m)" = arm64
mkdir -p experiments/injection/build
for major in 2 3; do
  xcrun clang -dynamiclib -std=c11 -g -O1 -Wall -Wextra -Werror \
    -DBROOMM_SDL_MAJOR="$major" experiments/injection/src/probe.c experiments/injection/src/cache_redirect.c \
    -framework AppKit -framework CoreGraphics -framework CoreText \
    -o "experiments/injection/build/probe-sdl$major.dylib"
done
