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
BRIDGE_BINARIES=()
for TARGET_ARCH in "${ARCHES[@]}"; do
    # Newer Swift build engines share a product path across architectures.
    # Keep each build separate so the next architecture cannot overwrite it.
    BUILD_DIR="$ROOT/.build/architectures/$TARGET_ARCH"
    swift build --package-path "$ROOT" --scratch-path "$BUILD_DIR" --configuration release --arch "$TARGET_ARCH"
    BIN_DIR="$(swift build --package-path "$ROOT" --scratch-path "$BUILD_DIR" --configuration release --arch "$TARGET_ARCH" --show-bin-path)"
    MAIN_BINARIES+=("$BIN_DIR/CaptureAccess")
    DEMO_BINARIES+=("$BIN_DIR/CaptureAccessDemo")
    BRIDGE_BINARIES+=("$BIN_DIR/CaptureAccessPageBridge")
done

APP="$ROOT/dist/CaptureAccess.app"
DEMO="$APP/Contents/Resources/CaptureAccessDemo.app"
BRIDGE="$APP/Contents/Helpers/CaptureAccessPageBridge"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$DEMO/Contents/MacOS"
if [[ "$ARCH" == "universal" ]]; then
    xcrun lipo -create "${MAIN_BINARIES[@]}" -output "$APP/Contents/MacOS/CaptureAccess"
    xcrun lipo -create "${DEMO_BINARIES[@]}" -output "$DEMO/Contents/MacOS/CaptureAccessDemo"
    xcrun lipo -create "${BRIDGE_BINARIES[@]}" -output "$BRIDGE"
else
    cp "${MAIN_BINARIES[0]}" "$APP/Contents/MacOS/CaptureAccess"
    cp "${DEMO_BINARIES[0]}" "$DEMO/Contents/MacOS/CaptureAccessDemo"
    cp "${BRIDGE_BINARIES[0]}" "$BRIDGE"
fi
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/LICENSE.txt" "$APP/Contents/Resources/LICENSE.txt"
cp "$ROOT/Resources/Demo-Info.plist" "$DEMO/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
printf 'APPL????' > "$DEMO/Contents/PkgInfo"
chmod +x "$APP/Contents/MacOS/CaptureAccess" "$DEMO/Contents/MacOS/CaptureAccessDemo" "$BRIDGE"
plutil -lint "$APP/Contents/Info.plist" "$DEMO/Contents/Info.plist"

# Prefer a stable local development identity: ad-hoc signatures change their
# designated requirement after a rebuild and invalidate screen capture consent.
SIGN_IDENTITY="${SIGN_IDENTITY:-auto}"
if [[ "$SIGN_IDENTITY" == "auto" ]]; then
    IDENTITIES=()
    while IFS= read -r identity; do
        [[ -n "$identity" ]] && IDENTITIES+=("$identity")
    done < <(security find-identity -v -p codesigning | awk '/"Apple Development:/ { print $2 }')
    if [[ ${#IDENTITIES[@]} -eq 1 ]]; then
        SIGN_IDENTITY="${IDENTITIES[0]}"
    else
        SIGN_IDENTITY="-"
        printf 'No unique Apple Development identity found; using ad-hoc signing. Screen capture consent may need to be renewed after rebuilding.\n' >&2
    fi
fi
# Sign the nested bundle first.
if [[ "$SIGN_IDENTITY" == "-" ]]; then
    codesign --force --sign - --timestamp=none "$BRIDGE"
    codesign --force --sign - --timestamp=none "$DEMO"
    codesign --force --sign - --timestamp=none "$APP"
else
    codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp "$BRIDGE"
    codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp "$DEMO"
    codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp "$APP"
fi
codesign --verify --deep --strict --verbose=2 "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ROOT/dist/CaptureAccess-macOS-$ARCH.zip"
printf '\nBuilt: %s\nArchive: %s\n' "$APP" "$ROOT/dist/CaptureAccess-macOS-$ARCH.zip"
