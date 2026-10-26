#!/usr/bin/env bash
set -euo pipefail
broomm_bundle="$(realpath "$1")"
test -f "$broomm_bundle/broomm"
test -f "$broomm_bundle/lib/libflutter_linux_gtk.so"
broomm_elfs=()
while IFS= read -r -d '' broomm_elf; do
  if readelf -h "$broomm_elf" >/dev/null 2>&1; then
    broomm_elfs+=("$broomm_elf")
  fi
done < <(find "$broomm_bundle" -type f -print0)
# Prepare every library before loading any dependency tree: ldd on the launcher
# also loads the engine, which can still have its own SDK RPATH/NEEDED entries.
# Remove build-machine paths only in the produced bundle, never in the SDK.
printf 'Preparing runtime paths for %s Linux ELF files\n' "${#broomm_elfs[@]}"
for broomm_elf in "${broomm_elfs[@]}"; do
  if [[ "$broomm_elf" == "$broomm_bundle/broomm" ]]; then
    # The ELF loader expands ORIGIN at runtime, not this build shell.
    # shellcheck disable=SC2016
    patchelf --set-rpath '$ORIGIN/lib' "$broomm_elf"
  else
    # shellcheck disable=SC2016
    patchelf --set-rpath '$ORIGIN' "$broomm_elf"
  fi
  broomm_needed_entries="$(patchelf --print-needed "$broomm_elf")"
  while IFS= read -r broomm_needed; do
    if [[ "$broomm_needed" == /nix/store/* ]]; then
      patchelf --replace-needed "$broomm_needed" "$(basename "$broomm_needed")" "$broomm_elf"
    fi
  done <<< "$broomm_needed_entries"
done
for broomm_elf in "${broomm_elfs[@]}"; do
  printf 'Checking Linux dependencies: %s\n' "${broomm_elf#"$broomm_bundle"/}"
  if readelf -l -d "$broomm_elf" | rg '/nix/store/'; then
    printf 'Linux bundle still refers to the build SDK: %s\n' "$broomm_elf" >&2
    exit 1
  fi
  # Use the host loader with Nix library overrides removed. Missing host GTK or
  # a newer required GLIBC is a build failure, not a package to publish.
  if ! broomm_deps="$(env -u LD_LIBRARY_PATH /usr/bin/ldd "$broomm_elf" 2>&1)"; then
    printf 'Linux dependency inspection failed: %s\n%s\n' "$broomm_elf" "$broomm_deps" >&2
    exit 1
  fi
  if [[ "$broomm_deps" == *'not found'* || "$broomm_deps" == *'/nix/store/'* ]]; then
    printf 'Unresolved or SDK-dependent Linux libraries: %s\n%s\n' "$broomm_elf" "$broomm_deps" >&2
    exit 1
  fi
done
cat > "$broomm_bundle/RUNNING.txt" <<'EOF'
Run ./broomm from this extracted directory. Keep data/ and lib/ beside it.
Requires a desktop with GTK 3, a Secret Service, and graphics drivers.
Built against Ubuntu 24.04 (glibc 2.39). Broomm does not install OS dependencies.
Linux emulator bridges/Steam/gamescope acceptance remain pending. This is an
early application build, not a claim of native emulator integration parity.
EOF
