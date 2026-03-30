#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/ClipboardHistory.xcodeproj"
SCHEME="ClipboardHistory"
DERIVED_DATA="$ROOT_DIR/.codex-tmp/release-derived"
ARM64_DERIVED_DATA="$ROOT_DIR/.codex-tmp/release-derived-arm64"
X86_64_DERIVED_DATA="$ROOT_DIR/.codex-tmp/release-derived-x86_64"
OUTPUT_DIR="$ROOT_DIR/build/release"
APP_NAME="ClipboardHistory.app"
EXECUTABLE_NAME="ClipboardHistory"
DMG_NAME="ClipboardHistory.dmg"

mkdir -p "$ROOT_DIR/.codex-tmp"
STAGING_DIR="$(mktemp -d "$ROOT_DIR/.codex-tmp/package-release.XXXXXX")"

cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

mkdir -p "$OUTPUT_DIR"
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

COMMON_XCODEBUILD_ARGS=(
  -project "$PROJECT_PATH"
  -scheme "$SCHEME"
  -configuration Release
  CODE_SIGNING_ALLOWED="${CODE_SIGNING_ALLOWED:-NO}"
  CODE_SIGNING_REQUIRED="${CODE_SIGNING_REQUIRED:-NO}"
)

build_release_app() {
  local arch="$1"
  local derived_data="$2"
  echo "Building Release app for $arch..."
  xcodebuild \
    "${COMMON_XCODEBUILD_ARGS[@]}" \
    -derivedDataPath "$derived_data" \
    ARCHS="$arch" \
    ONLY_ACTIVE_ARCH=YES \
    build
}

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  rm -rf "$DERIVED_DATA" "$ARM64_DERIVED_DATA" "$X86_64_DERIVED_DATA"
  build_release_app "arm64" "$ARM64_DERIVED_DATA"
  build_release_app "x86_64" "$X86_64_DERIVED_DATA"
else
  echo "Using existing Release builds at $ARM64_DERIVED_DATA and $X86_64_DERIVED_DATA"
fi

ARM64_APP="$ARM64_DERIVED_DATA/Build/Products/Release/$APP_NAME"
X86_64_APP="$X86_64_DERIVED_DATA/Build/Products/Release/$APP_NAME"
ARM64_EXEC="$ARM64_APP/Contents/MacOS/$EXECUTABLE_NAME"
X86_64_EXEC="$X86_64_APP/Contents/MacOS/$EXECUTABLE_NAME"
UNIVERSAL_APP="$STAGING_DIR/universal/$APP_NAME"
UNIVERSAL_EXEC="$UNIVERSAL_APP/Contents/MacOS/$EXECUTABLE_NAME"

if [[ ! -f "$ARM64_EXEC" ]]; then
  echo "Missing built executable: $ARM64_EXEC" >&2
  exit 1
fi

if [[ ! -f "$X86_64_EXEC" ]]; then
  echo "Missing built executable: $X86_64_EXEC" >&2
  exit 1
fi

SIGN_IDENTITY="$(codesign -dv --verbose=4 "$ARM64_APP" 2>&1 | sed -n 's/^Authority=//p' | head -n 1 || true)"
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="-"
fi

package_zip() {
  local app_path="$1"
  local output_zip="$2"
  ditto -c -k --sequesterRsrc --keepParent "$app_path" "$output_zip"
}

package_dmg() {
  local app_path="$1"
  local output_dmg="$2"
  local dmg_stage="$STAGING_DIR/dmg"
  local temp_dmg="$STAGING_DIR/ClipboardHistory-temp.dmg"

  rm -rf "$dmg_stage" "$temp_dmg" "$output_dmg"
  mkdir -p "$dmg_stage"
  cp -R "$app_path" "$dmg_stage/$APP_NAME"
  ln -s /Applications "$dmg_stage/Applications"

  hdiutil create \
    -volname "ClipboardHistory" \
    -srcfolder "$dmg_stage" \
    -fs HFS+ \
    -format UDZO \
    "$output_dmg" >/dev/null
}

make_arch_build() {
  local source_app="$1"
  local source_exec="$2"
  local slug="$3"
  local bundle_dir="$STAGING_DIR/$slug/$APP_NAME"
  mkdir -p "$(dirname "$bundle_dir")"
  cp -R "$source_app" "$bundle_dir"
  cp "$source_exec" "$bundle_dir/Contents/MacOS/$EXECUTABLE_NAME"
  codesign --force --sign "$SIGN_IDENTITY" -o runtime --timestamp=none --deep "$bundle_dir"
  package_zip "$bundle_dir" "$OUTPUT_DIR/ClipboardHistory-mac-$slug.zip"
}

mkdir -p "$(dirname "$UNIVERSAL_APP")"
cp -R "$ARM64_APP" "$UNIVERSAL_APP"
lipo -create "$ARM64_EXEC" "$X86_64_EXEC" -output "$UNIVERSAL_EXEC"
codesign --force --sign "$SIGN_IDENTITY" -o runtime --timestamp=none --deep "$UNIVERSAL_APP"
package_zip "$UNIVERSAL_APP" "$OUTPUT_DIR/ClipboardHistory-mac-universal.zip"
package_dmg "$UNIVERSAL_APP" "$OUTPUT_DIR/$DMG_NAME"

make_arch_build "$ARM64_APP" "$ARM64_EXEC" "apple-silicon"
make_arch_build "$X86_64_APP" "$X86_64_EXEC" "intel"

(cd "$OUTPUT_DIR" && shasum -a 256 ClipboardHistory.dmg ClipboardHistory-mac-*.zip > SHA256SUMS.txt)

echo
echo "Artifacts written to: $OUTPUT_DIR"
ls -lh "$OUTPUT_DIR"
