#!/usr/bin/env bash
set -euo pipefail
broomm_bundle="$(realpath "$1")"
test -f "$broomm_bundle/broomm"
test -f "$broomm_bundle/lib/libflutter_linux_gtk.so"
# Remove build-machine RPATHs only in the produced bundle, never in the SDK.
while IFS= read -r -d '' broomm_elf; do
  if readelf -h "$broomm_elf" >/dev/null 2>&1; then
    if [[ "$broomm_elf" == "$broomm_bundle/broomm" ]]; then
      # The ELF loader expands ORIGIN at runtime, not this build shell.
      # shellcheck disable=SC2016
      patchelf --set-rpath '$ORIGIN/lib' "$broomm_elf"
    else
      # shellcheck disable=SC2016
      patchelf --set-rpath '$ORIGIN' "$broomm_elf"
    fi
    while IFS= read -r broomm_needed; do
      if [[ "$broomm_needed" == /nix/store/* ]]; then
        patchelf --replace-needed "$broomm_needed" "$(basename "$broomm_needed")" "$broomm_elf"
      fi
    done < <(patchelf --print-needed "$broomm_elf")
    if readelf -l -d "$broomm_elf" | rg '/nix/store/'; then
      echo 'Linux bundle still refers to the build SDK' >&2; exit 1
    fi
    # Use the host loader with Nix library overrides removed. Missing host GTK or
    # a newer required GLIBC is a build failure, not a package to publish.
    broomm_deps="$(env -u LD_LIBRARY_PATH /usr/bin/ldd "$broomm_elf")"
    if [[ "$broomm_deps" == *'not found'* || "$broomm_deps" == *'/nix/store/'* ]]; then
      echo "$broomm_deps" >&2; exit 1
    fi
  fi
done < <(find "$broomm_bundle" -type f -print0)
cat > "$broomm_bundle/RUNNING.txt" <<'EOF'
Run ./broomm from this extracted directory. Keep data/ and lib/ beside it.
Requires a desktop with GTK 3, a Secret Service, and graphics drivers.
Built against Ubuntu 24.04 (glibc 2.39). Broomm does not install OS dependencies.
Linux emulator bridges/Steam/gamescope acceptance remain pending. This is an
early application build, not a claim of native emulator integration parity.
EOF
