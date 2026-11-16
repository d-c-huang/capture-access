#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCH="native"

usage() {
    printf 'Usage: bash build.sh [--arch native|arm64|x86_64|universal]\n'
}
while [[ $# -gt 0 ]]; do
    case "$1" in
        --arch)
            [[ $# -ge 2 ]] || { usage >&2; exit 2; }
            ARCH="$2"
            shift 2
            ;;
        --help|-h) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done

if [[ "$(uname -s)" != "Darwin" ]]; then
    printf 'This build requires macOS 14+ and Xcode 15+ / Command Line Tools.\n' >&2
    exit 1
fi
command -v swift >/dev/null || { printf 'Swift is not installed.\n' >&2; exit 1; }
export MACOSX_DEPLOYMENT_TARGET=14.0

case "$ARCH" in
    native) ARCH="$(uname -m)"; ARCHES=("$ARCH") ;;
    arm64|x86_64) ARCHES=("$ARCH") ;;
    universal) ARCHES=(arm64 x86_64) ;;
    *) usage >&2; exit 2 ;;
esac

MAIN_BINARIES=()
DEMO_BINARIES=()
for TARGET_ARCH in "${ARCHES[@]}"; do
    swift build --package-path "$ROOT" --configuration release --arch "$TARGET_ARCH"
    BIN_DIR="$(swift build --package-path "$ROOT" --configuration release --arch "$TARGET_ARCH" --show-bin-path)"
    MAIN_BINARIES+=("$BIN_DIR/CaptureAccess")
    DEMO_BINARIES+=("$BIN_DIR/CaptureAccessDemo")
done

APP="$ROOT/dist/CaptureAccess.app"
DEMO="$APP/Contents/Resources/CaptureAccessDemo.app"
mkdir -p "$APP/Contents/MacOS" "$DEMO/Contents/MacOS"
if [[ "$ARCH" == "universal" ]]; then
    xcrun lipo -create "${MAIN_BINARIES[@]}" -output "$APP/Contents/MacOS/CaptureAccess"
    xcrun lipo -create "${DEMO_BINARIES[@]}" -output "$DEMO/Contents/MacOS/CaptureAccessDemo"
else
    cp "${MAIN_BINARIES[0]}" "$APP/Contents/MacOS/CaptureAccess"
    cp "${DEMO_BINARIES[0]}" "$DEMO/Contents/MacOS/CaptureAccessDemo"
fi
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/Demo-Info.plist" "$DEMO/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
printf 'APPL????' > "$DEMO/Contents/PkgInfo"
chmod +x "$APP/Contents/MacOS/CaptureAccess" "$DEMO/Contents/MacOS/CaptureAccessDemo"
plutil -lint "$APP/Contents/Info.plist" "$DEMO/Contents/Info.plist"

# Sign the nested bundle first; local ad-hoc signing requires no developer account.
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
    codesign --force --sign - --timestamp=none "$DEMO"
    codesign --force --sign - --timestamp=none "$APP"
else
    codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp "$DEMO"
    codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp "$APP"
fi
codesign --verify --deep --strict --verbose=2 "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ROOT/dist/CaptureAccess-macOS-$ARCH.zip"
printf '\nBuilt: %s\nArchive: %s\n' "$APP" "$ROOT/dist/CaptureAccess-macOS-$ARCH.zip"
