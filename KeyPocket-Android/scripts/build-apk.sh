#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SDK="${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}"
BT="$SDK/build-tools/36.0.0"
PLATFORM="$SDK/platforms/android-36/android.jar"
OUT="$PWD/build"
for task_tool in "$BT/aapt2" "$BT/d8" "$BT/apksigner" "$PLATFORM"; do
  if [[ ! -f "$task_tool" ]]; then echo "Missing Android SDK component: $task_tool" >&2; exit 1; fi
done
rm -rf "$OUT/generated" "$OUT/classes" "$OUT/dex"
mkdir -p "$OUT/generated" "$OUT/classes" "$OUT/dex" "$HOME/.android"
python3 - <<'PYMANIFEST'
from pathlib import Path
p=Path('app/src/main/AndroidManifest.xml')
Path('build/AndroidManifest.xml').write_text(p.read_text().replace('<manifest ', '<manifest package="local.keypocket.android" ',1))
PYMANIFEST
"$BT/aapt2" compile --dir app/src/main/res -o "$OUT/resources.zip"
"$BT/aapt2" link -I "$PLATFORM" --manifest "$OUT/AndroidManifest.xml" --java "$OUT/generated" --min-sdk-version 26 --target-sdk-version 36 --version-code 1 --version-name 1.0 --auto-add-overlay -o "$OUT/resources.apk" "$OUT/resources.zip"
find app/src/main/java "$OUT/generated" -name '*.java' > "$OUT/java-sources.txt"
javac -encoding UTF-8 -source 8 -target 8 -bootclasspath "$PLATFORM:$BT/core-lambda-stubs.jar" -d "$OUT/classes" @"$OUT/java-sources.txt"
jar cf "$OUT/classes.jar" -C "$OUT/classes" .
"$BT/d8" --lib "$PLATFORM" --min-api 26 --output "$OUT/dex" "$OUT/classes.jar"
cp "$OUT/resources.apk" "$OUT/unaligned.apk"
(cd "$OUT/dex" && zip -q -u "$OUT/unaligned.apk" classes*.dex)
"$BT/zipalign" -f -p 4 "$OUT/unaligned.apk" "$OUT/aligned.apk"
KEY="${KEYPOCKET_KEYSTORE:-$HOME/.android/debug.keystore}"
if [[ ! -f "$KEY" ]]; then
  keytool -genkeypair -keystore "$KEY" -storepass android -keypass android -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 -dname 'CN=Android Debug,O=Android,C=US' -noprompt
fi
"$BT/apksigner" sign --ks "$KEY" --ks-key-alias androiddebugkey --ks-pass pass:android --key-pass pass:android --out "$OUT/KeyPocket-Android-1.0.apk" "$OUT/aligned.apk"
"$BT/apksigner" verify --verbose "$OUT/KeyPocket-Android-1.0.apk"
echo "APK: $OUT/KeyPocket-Android-1.0.apk"
