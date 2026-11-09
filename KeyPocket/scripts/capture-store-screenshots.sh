#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
DEVICE="${KEYPOCKET_SCREENSHOT_DEVICE:-F33D9EB7-7B72-4EE4-B9DE-4546DEC2254C}"
BUNDLE=net.smilingleo.KeyPocket
OUT="${KEYPOCKET_SCREENSHOT_OUTPUT:-AppStore/screenshots/zh-Hans/6.9-inch}"
mkdir -p "$OUT"
capture() {
  name="$1"
  shift
  xcrun simctl terminate "$DEVICE" "$BUNDLE" >/dev/null 2>&1 || true
  xcrun simctl launch "$DEVICE" "$BUNDLE" "$@" -AppleLanguages '(zh-Hans)' -AppleLocale zh_CN
  sleep 2
  xcrun simctl io "$DEVICE" screenshot "$OUT/$name.png"
}
capture 01-favorite-doors --demo
capture 02-door-configuration --demo --configuration
capture 03-sound-settings --demo --settings
capture 04-account-login
sips -g pixelWidth -g pixelHeight "$OUT"/*.png
