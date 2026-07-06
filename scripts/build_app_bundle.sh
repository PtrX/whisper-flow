#!/usr/bin/env bash
set -euo pipefail

swift build -c release

APP_NAME="WhisperFlow"
BUNDLE="$APP_NAME.app"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/WhisperFlowApp" "$BUNDLE/Contents/MacOS/"
cp Resources/Info.plist "$BUNDLE/Contents/Info.plist"
cp Resources/AppIcon.icns "$BUNDLE/Contents/Resources/AppIcon.icns"

# The linker's automatic ad-hoc signature is created before Info.plist is copied in,
# so it doesn't bind the bundle identifier — re-sign explicitly so TCC (Accessibility/
# Microphone permissions) tracks the app by its real identifier, not an unbound one.
codesign --force --deep --sign - "$BUNDLE"

echo "Built and signed $BUNDLE. Move it to /Applications, then grant Microphone + Accessibility access in System Settings > Privacy & Security."
echo "Note: ad-hoc signing means macOS may ask you to re-grant permissions after each rebuild — that is expected, not a bug."
