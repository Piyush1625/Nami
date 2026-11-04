#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter is not installed. See https://docs.flutter.dev/get-started/install"
  exit 1
fi

if [ ! -d android ]; then
  TMP="$(mktemp -d)"
  flutter create --platforms=android --org com.nami --project-name nami "$TMP/nami"
  cp -R "$TMP/nami/android" ./android
  rm -rf "$TMP"
fi

flutter pub get
dart tool/patch_android.dart
flutter analyze

echo "Setup done."
