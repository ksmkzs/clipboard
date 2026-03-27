#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/ClipboardHistory.xcodeproj"
SCHEME="ClipboardHistory"
DERIVED_DATA="$ROOT_DIR/.codex-tmp/release-derived"
OUTPUT_DIR="$ROOT_DIR/build/release"
APP_NAME="ClipboardHistory.app"
EXECUTABLE_NAME="ClipboardHistory"

mkdir -p "$ROOT_DIR/.codex-tmp"
STAGING_DIR="$(mktemp -d "$ROOT_DIR/.codex-tmp/package-release.XXXXXX")"

cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

mkdir -p "$OUTPUT_DIR"
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
  echo "Building signed universal Release app..."
  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA" \
    ONLY_ACTIVE_ARCH=NO \
    build
else
  echo "Using existing Release build at $DERIVED_DATA"
fi

UNIVERSAL_APP="$DERIVED_DATA/Build/Products/Release/$APP_NAME"
UNIVERSAL_EXEC="$UNIVERSAL_APP/Contents/MacOS/$EXECUTABLE_NAME"

if [[ ! -f "$UNIVERSAL_EXEC" ]]; then
  echo "Missing built executable: $UNIVERSAL_EXEC" >&2
  exit 1
fi

SIGN_IDENTITY="$(codesign -dv --verbose=4 "$UNIVERSAL_APP" 2>&1 | sed -n 's/^Authority=//p' | head -n 1 || true)"
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="-"
fi

package_zip() {
  local app_path="$1"
  local output_zip="$2"
  ditto -c -k --sequesterRsrc --keepParent "$app_path" "$output_zip"
}

make_arch_build() {
  local arch="$1"
  local slug="$2"
  local bundle_dir="$STAGING_DIR/$slug/$APP_NAME"
  mkdir -p "$(dirname "$bundle_dir")"
  cp -R "$UNIVERSAL_APP" "$bundle_dir"
  lipo "$UNIVERSAL_EXEC" -thin "$arch" -output "$bundle_dir/Contents/MacOS/$EXECUTABLE_NAME"
  codesign --force --sign "$SIGN_IDENTITY" -o runtime --timestamp=none --deep "$bundle_dir"
  package_zip "$bundle_dir" "$OUTPUT_DIR/ClipboardHistory-mac-$slug.zip"
}

UNIVERSAL_COPY="$STAGING_DIR/universal/$APP_NAME"
mkdir -p "$(dirname "$UNIVERSAL_COPY")"
cp -R "$UNIVERSAL_APP" "$UNIVERSAL_COPY"
package_zip "$UNIVERSAL_COPY" "$OUTPUT_DIR/ClipboardHistory-mac-universal.zip"

make_arch_build "arm64" "apple-silicon"
make_arch_build "x86_64" "intel"

(cd "$OUTPUT_DIR" && shasum -a 256 ClipboardHistory-mac-*.zip > SHA256SUMS.txt)

echo
echo "Artifacts written to: $OUTPUT_DIR"
ls -lh "$OUTPUT_DIR"
