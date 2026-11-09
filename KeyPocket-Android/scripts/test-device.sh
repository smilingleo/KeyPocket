#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SDK="${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}"
BT="$SDK/build-tools/36.0.0"
PLATFORM="$SDK/platforms/android-36/android.jar"
OUT="$PWD/build/device-tests"
mkdir -p "$OUT/classes" "$OUT/dex"
"$BT/aapt2" link -I "$PLATFORM" --manifest tests/AndroidManifest.xml -o "$OUT/resources.apk"
javac -encoding UTF-8 -source 8 -target 8 -bootclasspath "$PLATFORM:$BT/core-lambda-stubs.jar" -d "$OUT/classes" tests/DeviceTests.java
jar cf "$OUT/classes.jar" -C "$OUT/classes" .
"$BT/d8" --lib "$PLATFORM" --min-api 26 --output "$OUT/dex" "$OUT/classes.jar"
cp "$OUT/resources.apk" "$OUT/unaligned.apk"
(cd "$OUT/dex" && zip -q -u "$OUT/unaligned.apk" classes*.dex)
"$BT/zipalign" -f -p 4 "$OUT/unaligned.apk" "$OUT/aligned.apk"
"$BT/apksigner" sign --ks "$HOME/.android/debug.keystore" --ks-key-alias androiddebugkey --ks-pass pass:android --key-pass pass:android --out "$OUT/tests.apk" "$OUT/aligned.apk"
# -e deliberately restricts this destructive test fixture to an emulator, never a physical phone.
"$SDK/platform-tools/adb" -e install -r "$OUT/tests.apk"
"$SDK/platform-tools/adb" -e shell am force-stop local.keypocket.android
"$SDK/platform-tools/adb" -e shell am instrument -w local.keypocket.tests/local.keypocket.tests.DeviceTests | tee "$OUT/result.txt"
grep -q 'PASS:' "$OUT/result.txt"
