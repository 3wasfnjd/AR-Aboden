#!/usr/bin/env bash
# Reproducible Meta Quest 3 test APK build of table-war/ (used by
# .github/workflows/table-war-apk.yml). Runs on a stock ubuntu-24.04 GitHub runner.
# Mirrors the Dahrooj Quest build (quest-native/tools/ci/build_apk.sh):
#   Godot 4.6.3-stable editor + export templates (SHA-512 checked, cached)
#   OpenXR Vendors plugin 5.1.0-stable + Godot Meta Toolkit (vendored in table-war/addons)
#   JDK 17, Android platform 36, build-tools 36.1.0, NDK 29.0.14206865
#
# Signing: a throw-away TEST key generated here for every run (never committed, never
# reused). Successive test APKs therefore carry different certificates: uninstall the
# previous build before installing a new one (see README).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"   # table-war/
REPO="$(cd "$ROOT/.." && pwd)"
OUT="${OUT_DIR:-$REPO/build}"
CACHE="${GODOT_CACHE:-$HOME/.cache/dahrooj-godot}"

GODOT_VERSION="4.6.3-stable"
GODOT_TEMPLATE_DIR="4.6.3.stable"
GODOT_URL="https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}"
GODOT_EDITOR_ZIP="Godot_v${GODOT_VERSION}_linux.x86_64.zip"
GODOT_EDITOR_SHA512="a035258da32b77f966a5376f9fa29c30a6adde826a85ba918e1605bd1fc9823eba7d85f1dd5e748956bd2ba72827c0025ffa11bb82aec91128c407a2e723c99c"
GODOT_TPZ="Godot_v${GODOT_VERSION}_export_templates.tpz"
GODOT_TPZ_SHA512="da606b61c10157844f8300172df374472665f95015495cb1a7cd132c40ede404faa96cc1016a4b9662db9909ddea69632c4948b2cd11163438dad4808881fb68"
ANDROID_PLATFORM="platforms;android-36"
ANDROID_BUILD_TOOLS="36.1.0"
ANDROID_NDK="29.0.14206865"
PACKAGE="com.abodengames.tablewar"

APP_VERSION="${APP_VERSION:-$(sed -n 's/^config\/version="\(.*\)"/\1/p' "$ROOT/project.godot")}"
VERSION_CODE="${VERSION_CODE:-1}"

log() { printf '\n==> %s\n' "$*"; }

fetch() {  # fetch <file> <sha512>
  local f="$1" sum="$2"
  mkdir -p "$CACHE"
  if [ ! -f "$CACHE/$f" ] || ! echo "$sum  $CACHE/$f" | sha512sum -c --quiet - 2>/dev/null; then
    curl -fL --retry 4 --retry-delay 5 -o "$CACHE/$f.part" "$GODOT_URL/$f"
    mv "$CACHE/$f.part" "$CACHE/$f"
  fi
  echo "$sum  $CACHE/$f" | sha512sum -c -
}

log "Godot ${GODOT_VERSION}"
fetch "$GODOT_EDITOR_ZIP" "$GODOT_EDITOR_SHA512"
fetch "$GODOT_TPZ" "$GODOT_TPZ_SHA512"
mkdir -p "$CACHE/bin"
if [ ! -x "$CACHE/bin/godot" ]; then
  unzip -o -q "$CACHE/$GODOT_EDITOR_ZIP" -d "$CACHE/bin"
  mv "$CACHE/bin/Godot_v${GODOT_VERSION}_linux.x86_64" "$CACHE/bin/godot"
fi
GODOT="$CACHE/bin/godot"
"$GODOT" --version
TPL="$HOME/.local/share/godot/export_templates/$GODOT_TEMPLATE_DIR"
if [ ! -f "$TPL/android_source.zip" ]; then
  mkdir -p "$TPL" /tmp/tpz
  unzip -o -q "$CACHE/$GODOT_TPZ" 'templates/android_*' 'templates/version.txt' -d /tmp/tpz
  mv /tmp/tpz/templates/* "$TPL/"
fi
ls -la "$TPL"

log "Android SDK"
SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-/usr/local/lib/android/sdk}}"
SDKMANAGER="$SDK/cmdline-tools/latest/bin/sdkmanager"
yes | "$SDKMANAGER" --licenses >/dev/null || true
"$SDKMANAGER" --install "$ANDROID_PLATFORM" "build-tools;$ANDROID_BUILD_TOOLS" "ndk;$ANDROID_NDK" "platform-tools" >/dev/null
JAVA="${JAVA_HOME:?JDK 17 required}"
"$JAVA/bin/java" -version 2>&1 | head -1

mkdir -p "$HOME/.config/godot"
cat > "$HOME/.config/godot/editor_settings-4.6.tres" <<EOT
[gd_resource type="EditorSettings" format=3]

[resource]
export/android/android_sdk_path = "$SDK"
export/android/java_sdk_path = "$JAVA"
EOT

log "Signing (throw-away test key, generated for this run)"
KEYDIR="$(mktemp -d)"
trap 'rm -rf "$KEYDIR"' EXIT
SIGN_PASS="$(openssl rand -hex 24)"
echo "::add-mask::$SIGN_PASS"
"$JAVA/bin/keytool" -genkeypair -noprompt -keystore "$KEYDIR/test.p12" -storetype PKCS12 \
  -alias tablewar-test -keyalg RSA -keysize 2048 -validity 3650 \
  -storepass "$SIGN_PASS" -keypass "$SIGN_PASS" \
  -dname "CN=Table War test build, OU=Sideload testing only, O=Aboden Games" >/dev/null 2>&1
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$KEYDIR/test.p12"
export GODOT_ANDROID_KEYSTORE_RELEASE_USER="tablewar-test"
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$SIGN_PASS"
SIGNING="TEST-ONLY key generated in CI for this run (sideload testing, not for store release)"
echo "$SIGNING"

log "Version ${APP_VERSION} (${VERSION_CODE})"
sed -i "s/^version\/code=.*/version\/code=${VERSION_CODE}/; s/^version\/name=.*/version\/name=\"${APP_VERSION}\"/" "$ROOT/export_presets.cfg"

log "Import"
"$GODOT" --headless --xr-mode off --path "$ROOT" --import 2>&1 | grep -v "OpenXR-Loader" | tail -5 || true

mkdir -p "$OUT"
if [ "${SKIP_TESTS:-0}" != "1" ]; then
  log "Tests"
  if ! GODOT="$GODOT" bash "$ROOT/tests/run_tests.sh" 2>&1 | tee "$OUT/test-report.txt"; then
    echo "::error::Headless tests failed (tests/run_tests.sh, see test-report.txt)"
    exit 1
  fi
fi

log "Export"
APK="$OUT/table-war-test-${APP_VERSION}-${VERSION_CODE}.apk"
# Install the Godot Android build template the same way the editor does.
rm -rf "$ROOT/android"
mkdir -p "$ROOT/android/build"
unzip -q "$TPL/android_source.zip" -d "$ROOT/android/build"
rm -rf "$ROOT/android/build/src/main/assets"
echo "$GODOT_TEMPLATE_DIR" > "$ROOT/android/.build_version"
touch "$ROOT/android/build/.gdignore"
"$GODOT" --headless --xr-mode off --path "$ROOT" --export-release "Quest" "$APK" 2>&1 | grep -v "OpenXR-Loader" | tee "$OUT/export.log"
test -s "$APK" || { echo "::error::Export failed: no APK produced (see export.log)"; exit 1; }

log "Verify"
BT="$SDK/build-tools/$ANDROID_BUILD_TOOLS"
{
  echo "Table War (test) Quest APK build report"
  echo "file: $(basename "$APK")"
  echo "version: ${APP_VERSION} (code ${VERSION_CODE})"
  echo "size_bytes: $(stat -c %s "$APK")"
  echo "sha256: $(sha256sum "$APK" | cut -d' ' -f1)"
  echo "signing: $SIGNING"
  echo "godot: ${GODOT_VERSION}; openxr_vendors: 5.1.0-stable; build-tools: ${ANDROID_BUILD_TOOLS}; ndk: ${ANDROID_NDK}"
  echo
  echo "--- apksigner verify"
  "$BT/apksigner" verify --verbose --print-certs "$APK" | grep -E "Verified|Signer #1 certificate (DN|SHA-256)|Number of signers"
  echo
  echo "--- badging"
  "$BT/aapt2" dump badging "$APK" | grep -E "^package:|sdkVersion|targetSdkVersion|application-label|native-code|uses-feature|uses-permission|launchable-activity"
  echo
  echo "--- manifest (XR launch)"
  "$BT/aapt2" dump xmltree --file AndroidManifest.xml "$APK" | grep -E "com.oculus|android.intent.category|PASSTHROUGH|supportedDevices|org.khronos.openxr" | sed 's/^ *//' | sort -u
  echo
  echo "--- native libraries"
  unzip -l "$APK" | grep -E "lib/.*\.so" | awk '{print $4}'
} | tee "$OUT/apk-report.txt"

# Hard checks: valid signature, arm64 only, OpenXR/Quest launch entries, Quest 3 / 3S only.
"$BT/apksigner" verify "$APK"
unzip -l "$APK" | grep -q "lib/arm64-v8a/libgodot_android.so"
unzip -l "$APK" | grep -q "lib/arm64-v8a/libgodotopenxrvendors.so"
! unzip -l "$APK" | grep -qE "lib/(armeabi-v7a|x86|x86_64)/"
"$BT/aapt2" dump xmltree --file AndroidManifest.xml "$APK" | grep -q "com.oculus.intent.category.VR"
"$BT/aapt2" dump xmltree --file AndroidManifest.xml "$APK" | grep -q "org.khronos.openxr.intent.category.IMMERSIVE_HMD"
"$BT/aapt2" dump badging "$APK" | grep -q "package: name='${PACKAGE}'"
"$BT/aapt2" dump xmltree --file AndroidManifest.xml "$APK" | grep -q 'Raw: "quest3|quest3s"'
# Soft checks (warn only): passthrough feature and the scene permission for real tables.
"$BT/aapt2" dump badging "$APK" | grep -q "com.oculus.feature.PASSTHROUGH" \
  || echo "::warning::com.oculus.feature.PASSTHROUGH not in the manifest: the app may start in VR only"
"$BT/aapt2" dump badging "$APK" | grep -q "com.oculus.permission.USE_SCENE" \
  || echo "::warning::com.oculus.permission.USE_SCENE not in the manifest: real table planes unavailable (virtual table fallback)"
# Boundaryless MR (export preset meta_xr_features/boundary_mode=1): the Guardian does not
# stop the player walking around the real table while the app shows passthrough.
"$BT/aapt2" dump badging "$APK" | grep -q "com.oculus.feature.BOUNDARYLESS_APP" \
  || echo "::warning::com.oculus.feature.BOUNDARYLESS_APP not in the manifest: the Guardian boundary stays on"
sha256sum "$APK" | tee "$APK.sha256"
echo "APK=$APK" >> "${GITHUB_ENV:-/dev/null}"
log "Done: $APK"
