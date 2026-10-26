#!/usr/bin/env bash
# Native ELF/loader regressions; run on each Linux build architecture in Devbox.
set -euo pipefail
cd "$(dirname "$0")/../.."
test "$(uname -s)" = Linux
test -x /usr/bin/clang-18
broomm_checker="$(realpath "${1:-tool/ci/check_linux_bundle.sh}")"
broomm_fixture="$(mktemp -d "${TMPDIR:-/tmp}/broomm-bundle-test.XXXXXX")"
trap 'rm -rf -- "$broomm_fixture"' EXIT
mkdir -p "$broomm_fixture/bin"
export BROOMM_TEST_FIND
BROOMM_TEST_FIND="$(command -v find)"
# Force both discovery orders instead of relying on a filesystem's traversal.
cat > "$broomm_fixture/bin/find" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ $# == 4 && "$1" == "$BROOMM_TEST_BUNDLE" && "$2" == -type && "$3" == f && "$4" == -print0 ]]; then
  if [[ "$BROOMM_TEST_ORDER" == launcher-first ]]; then
    printf '%s\0' "$1/broomm" "$1/lib/libflutter_linux_gtk.so"
  else
    printf '%s\0' "$1/lib/libflutter_linux_gtk.so" "$1/broomm"
  fi
else
  exec "$BROOMM_TEST_FIND" "$@"
fi
EOF
chmod +x "$broomm_fixture/bin/find"
export PATH="$broomm_fixture/bin:$PATH"
export BROOMM_TEST_BUNDLE='' BROOMM_TEST_ORDER=''
cat > "$broomm_fixture/engine.c" <<'EOF'
int broomm_fixture(void) { return 42; }
EOF
cat > "$broomm_fixture/main.c" <<'EOF'
extern int broomm_fixture(void);
int main(void) { return broomm_fixture() == 42 ? 0 : 1; }
EOF
broomm_fixture_sdk="$broomm_fixture/nix/store/broomm-fixture/lib"
mkdir -p "$broomm_fixture_sdk"
broomm_libm="$(env -u LIBRARY_PATH -u LD_LIBRARY_PATH /usr/bin/clang-18 -print-file-name=libm.so.6)"
test -f "$broomm_libm"
cp "$broomm_libm" "$broomm_fixture_sdk/libm.so.6"
prepare_fixture() {
  BROOMM_TEST_BUNDLE="$broomm_fixture/$1"
  mkdir -p "$BROOMM_TEST_BUNDLE/lib"
  env -u LIBRARY_PATH -u LD_LIBRARY_PATH /usr/bin/clang-18 -fuse-ld=/usr/bin/ld \
    -shared -fPIC "$broomm_fixture/engine.c" -Wl,-soname,libflutter_linux_gtk.so \
    -o "$BROOMM_TEST_BUNDLE/lib/libflutter_linux_gtk.so"
  env -u LIBRARY_PATH -u LD_LIBRARY_PATH /usr/bin/clang-18 -fuse-ld=/usr/bin/ld \
    "$broomm_fixture/main.c" -L"$BROOMM_TEST_BUNDLE/lib" -lflutter_linux_gtk \
    -o "$BROOMM_TEST_BUNDLE/broomm"
  # Like the real Flutter engine, this library resolves a unique dependency from
  # its SDK RUNPATH until prepared. The fixture never writes to the actual SDK.
  patchelf --set-rpath "$broomm_fixture_sdk" "$BROOMM_TEST_BUNDLE/broomm"
  patchelf --set-rpath "$broomm_fixture_sdk" "$BROOMM_TEST_BUNDLE/lib/libflutter_linux_gtk.so"
  patchelf --add-needed libm.so.6 "$BROOMM_TEST_BUNDLE/lib/libflutter_linux_gtk.so"
}
expect_rejected() {
  local broomm_log="$broomm_fixture/$1.log"
  if bash "$broomm_checker" "$BROOMM_TEST_BUNDLE" > "$broomm_log" 2>&1; then
    printf 'Invalid bundle was accepted: %s\n' "$1" >&2
    exit 1
  fi
  cat "$broomm_log"
  # Identify the rejected resource rather than matching incidental wording.
  rg --fixed-strings "$2" "$broomm_log"
  test ! -e "$BROOMM_TEST_BUNDLE/RUNNING.txt"
}

for BROOMM_TEST_ORDER in launcher-first engine-first; do
  prepare_fixture "$BROOMM_TEST_ORDER with spaces"
  bash "$broomm_checker" "$BROOMM_TEST_BUNDLE"
  test -s "$BROOMM_TEST_BUNDLE/RUNNING.txt"
  mv "$BROOMM_TEST_BUNDLE" "$BROOMM_TEST_BUNDLE relocated"
  env -u LD_LIBRARY_PATH "$BROOMM_TEST_BUNDLE relocated/broomm"
done
printf 'PASS: normalized dependency trees work in both orders and after relocation\n'

BROOMM_TEST_ORDER=launcher-first
prepare_fixture missing-dependency
patchelf --add-needed libbroomm_fixture_missing.so "$BROOMM_TEST_BUNDLE/lib/libflutter_linux_gtk.so"
expect_rejected missing-dependency libbroomm_fixture_missing.so
printf 'PASS: genuinely missing transitive dependency is rejected\n'

prepare_fixture sdk-interpreter
patchelf --set-interpreter /nix/store/broomm-fixture/ld-linux.so "$BROOMM_TEST_BUNDLE/broomm"
expect_rejected sdk-interpreter /nix/store/broomm-fixture/ld-linux.so
printf 'PASS: SDK interpreter is rejected\n'
