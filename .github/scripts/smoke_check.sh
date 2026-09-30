#!/usr/bin/env bash
# DB-init smoke check, run inside the Android emulator job.
#
# Kept as a standalone script because reactivecircus/android-emulator-runner
# executes each line of an inline `script:` separately, which breaks multi-line
# shell constructs (a `for` loop errors with "end of file unexpected"). Invoking
# one file with bash runs the whole thing as a single program.
set -euo pipefail

APK="build/app/outputs/flutter-apk/app-debug.apk"
PKG="com.portableai.portable_ai_flutter"

echo "Installing $APK"
adb install -r "$APK"
adb logcat -c
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 || true

# Poll logcat for the storage-init marker the splash prints once the memory
# engine has opened. Fail fast on an explicit init failure or a WAL regression.
ok=0
for _ in $(seq 1 45); do
  log="$(adb logcat -d 2>/dev/null || true)"
  if echo "$log" | grep -q "AETHER_SMOKE_DB_OK"; then ok=1; break; fi
  if echo "$log" | grep -q "AETHER_SMOKE_FAIL"; then
    echo "::error::App init failed on device:"
    echo "$log" | grep "AETHER_SMOKE_FAIL"
    exit 1
  fi
  if echo "$log" | grep -qi "journal_mode=WAL"; then
    echo "::error::WAL DatabaseException regressed:"
    echo "$log" | grep -i "journal_mode\|DatabaseException" | head -n 20
    exit 1
  fi
  sleep 2
done

if [ "$ok" != "1" ]; then
  echo "::error::Timed out waiting for AETHER_SMOKE_DB_OK. Logcat tail:"
  adb logcat -d | tail -n 200
  exit 1
fi
echo "Storage layer initialized cleanly (AETHER_SMOKE_DB_OK)."
