#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/test-libs build/test-classes
JAR=build/test-libs/json.jar
if [[ ! -f "$JAR" ]]; then curl -fL https://repo.maven.apache.org/maven2/org/json/json/20250517/json-20250517.jar -o "$JAR"; fi
javac -encoding UTF-8 -cp "$JAR" -d build/test-classes app/src/main/java/local/keypocket/android/{Door,Protocol,SoundProtocol,KeybootAPI,DoorPreference}.java tests/CoreTests.java
java -cp "build/test-classes:$JAR" local.keypocket.android.CoreTests
