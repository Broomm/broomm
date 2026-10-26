#!/usr/bin/env bash
# Use only the hosted runner's already licensed SDK components; never sdkmanager
# into a global SDK or silently accept licenses. All Gradle writes stay local.
set -euo pipefail
cd "$(dirname "$0")/../.."
broomm_sdk_source="${ANDROID_HOME:?A provisioned Android SDK is required}"
broomm_sdk_dest="$PWD/.tool-cache/android/sdk"
mkdir -p "$broomm_sdk_dest"
for broomm_component in platforms/android-36 build-tools/36.1.0 ndk/29.0.14206865 platform-tools licenses; do
  test -d "$broomm_sdk_source/$broomm_component" || {
    echo "Missing pre-provisioned Android component: $broomm_component" >&2; exit 1;
  }
  test ! -e "$broomm_sdk_dest/$broomm_component" || {
    echo 'Private Android SDK staging already exists; preserve/remove it before retrying.' >&2; exit 1;
  }
  mkdir -p "$(dirname "$broomm_sdk_dest/$broomm_component")"
  # Linux hosted images support reflink when available; ordinary copy otherwise.
  cp -a --reflink=auto "$broomm_sdk_source/$broomm_component" "$broomm_sdk_dest/$broomm_component"
done
mkdir -p "$PWD/.tool-cache/android/gradle"
cat > "$PWD/.tool-cache/android/gradle/gradle.properties" <<'EOF'
org.gradle.jvmargs=-Xmx3G -XX:MaxMetaspaceSize=1G -XX:ReservedCodeCacheSize=256m -XX:+HeapDumpOnOutOfMemoryError
org.gradle.workers.max=2
org.gradle.parallel=false
org.gradle.vfs.watch=false
EOF
test ! -f android/key.properties
test ! -f android/app/release.jks
{
  echo "ANDROID_HOME=$broomm_sdk_dest"
  echo "ANDROID_SDK_ROOT=$broomm_sdk_dest"
  echo "ANDROID_NDK_HOME=$broomm_sdk_dest/ndk/29.0.14206865"
  echo "ANDROID_NDK_ROOT=$broomm_sdk_dest/ndk/29.0.14206865"
  echo "ANDROID_NDK=$broomm_sdk_dest/ndk/29.0.14206865"
} >> "${GITHUB_ENV:?}"
