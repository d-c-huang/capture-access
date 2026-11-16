#!/bin/bash
set -euo pipefail

test_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
macos_directory="$(cd -- "$test_directory/.." && pwd)"
temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/capture-access-settings.XXXXXX")"
trap 'rm -rf "$temporary_directory"' EXIT

swiftc -swift-version 5 \
    "$macos_directory/Sources/CaptureAccessMac/AppPreferences.swift" \
    "$macos_directory/Sources/CaptureAccessMac/GlobalCaptureShortcut.swift" \
    "$test_directory/SettingsChecks.swift" \
    -o "$temporary_directory/settings-checks"
"$temporary_directory/settings-checks"
