#!/bin/bash
# Build APKs to hand out: one for every device and three smaller ones, one per processor type.
#   app-release.apk              — any Android 7.0+ device (all processors; the largest file);
#   app-arm64-v8a-release.apk    — nearly all phones and tablets made after 2017;
#   app-armeabi-v7a-release.apk  — older and low-cost 32-bit devices;
#   app-x86_64-release.apk       — the Android emulator on a PC, rare Intel tablets.
# Not sure which processor the device has? Send app-release.apk.
# Run from the project folder: bash tools/build_apk.sh
# Needs flutter on PATH (JAVA_HOME and ANDROID_HOME set as for any Flutter Android build).
set -e
cd "$(dirname "$0")/.."
# Own signing key (android/key.properties): the password is asked here and never written to a file.
# A Windows console adds an invisible carriage return (\r) to what is typed, so it is removed.
if [ -f android/key.properties ] && [ -z "$ROAD_GPS_KEY_PASSWORD" ]; then
  read -r -s -p "Signing key password: " ROAD_GPS_KEY_PASSWORD; echo
  ROAD_GPS_KEY_PASSWORD="$(printf '%s' "$ROAD_GPS_KEY_PASSWORD" | tr -d '\r')"; export ROAD_GPS_KEY_PASSWORD
fi
flutter build apk --release
flutter build apk --release --split-per-abi
ls -la build/app/outputs/flutter-apk/*.apk
