#!/usr/bin/env bash
# Generate the Xcode project, build an unsigned iOS app, and zip Payload/*.app
# into an .ipa. One build invocation. No extra package managers.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

XCODEGEN_VERSION="2.46.0"
TOOL_ROOT="$ROOT/.tools/xcodegen"
BIN="$TOOL_ROOT/bin/xcodegen"

if [[ ! -x "$BIN" ]]; then
  echo "Downloading XcodeGen ${XCODEGEN_VERSION}"
  mkdir -p "$ROOT/.tools"
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/xcodegen.zip" \
    "https://github.com/yonaskolb/XcodeGen/releases/download/${XCODEGEN_VERSION}/xcodegen.zip"
  unzip -q "$tmp/xcodegen.zip" -d "$tmp"
  rm -rf "$TOOL_ROOT"
  mv "$tmp/xcodegen" "$TOOL_ROOT"
  rm -rf "$tmp"
  chmod +x "$BIN"
fi

"$BIN" generate --spec "$ROOT/project.yml"

DERIVED="${DERIVED_DATA_PATH:-${RUNNER_TEMP:-$ROOT/build}/DerivedData}"
xcodebuild \
  -project "$ROOT/RepostSweep.xcodeproj" \
  -scheme RepostSweep \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build

APP="$DERIVED/Build/Products/Release-iphoneos/RepostSweep.app"
if [[ ! -d "$APP" ]]; then
  echo "App bundle not found at $APP" >&2
  find "$DERIVED/Build/Products" -name '*.app' -print >&2 || true
  exit 1
fi

STAGE="$(mktemp -d)"
mkdir -p "$STAGE/Payload"
cp -R "$APP" "$STAGE/Payload/RepostSweep.app"
OUT="${IPA_OUTPUT:-$ROOT/RepostSweep-unsigned.ipa}"
rm -f "$OUT"
(
  cd "$STAGE"
  COPYFILE_DISABLE=1 zip -qr -X "$OUT" Payload
)
rm -rf "$STAGE"
echo "Wrote $OUT"
