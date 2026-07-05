#!/usr/bin/env bash
set -euo pipefail

swift build -c release

APP_NAME="WhisperFlow"
BUNDLE="$APP_NAME.app"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/WhisperFlowApp" "$BUNDLE/Contents/MacOS/"
cp Resources/Info.plist "$BUNDLE/Contents/Info.plist"

echo "Built $BUNDLE. Move it to /Applications, then grant Microphone + Accessibility access in System Settings > Privacy & Security."
