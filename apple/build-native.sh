#!/bin/bash
# Reproducible local native builds. Physical-device distribution needs developer signing.
set -euo pipefail
EEG_APPLE_DIR="$(cd "$(dirname "$0")" && pwd)"
EEG_REPO_DIR="$(cd "$EEG_APPLE_DIR/.." && pwd)"
EEG_TARGET="${1:-all}"
case "$EEG_TARGET" in macos|ios|visionos|all) ;; *) echo 'Usage: build-native.sh [macos|ios|visionos|all]' >&2; exit 2 ;; esac
command -v xcodegen >/dev/null || { echo 'Install XcodeGen before generating the native project.' >&2; exit 1; }
xcodegen generate --spec "$EEG_APPLE_DIR/project.yml"
if [[ "$EEG_TARGET" == macos || "$EEG_TARGET" == all ]]; then
  xcodebuild -project "$EEG_APPLE_DIR/EEG.xcodeproj" -scheme EEG-macOS -configuration Debug \
    -destination 'platform=macOS' -derivedDataPath "$EEG_REPO_DIR/build/native/macOS" CODE_SIGN_IDENTITY=- build
fi
if [[ "$EEG_TARGET" == ios || "$EEG_TARGET" == all ]]; then
  xcodebuild -project "$EEG_APPLE_DIR/EEG.xcodeproj" -scheme EEG-iOS -configuration Debug \
    -destination 'generic/platform=iOS Simulator' -derivedDataPath "$EEG_REPO_DIR/build/native/iOS" CODE_SIGNING_ALLOWED=NO build
fi
if [[ "$EEG_TARGET" == visionos || "$EEG_TARGET" == all ]]; then
  xcodebuild -project "$EEG_APPLE_DIR/EEG.xcodeproj" -scheme EEG-visionOS -configuration Debug \
    -destination 'generic/platform=visionOS Simulator' -derivedDataPath "$EEG_REPO_DIR/build/native/visionOS" CODE_SIGNING_ALLOWED=NO build
fi
