#!/usr/bin/env bash
# DB-init smoke check, run inside the Android emulator job.
#
# Kept as a standalone script because reactivecircus/android-emulator-runner
# executes each line of an inline `script:` separately, which breaks multi-line
# shell constructs. Invoking one file with bash runs it as a single program.
#
# logcat is captured to a FILE from before launch, so the app's early startup
# lines can't rotate out of the ring buffer (Play Services is very chatty) before
# we read them — the failure mode that made the first attempt undiagnosable.
set -uo pipefail

APK="build/app/outputs/flutter-apk/app-debug.apk"
PKG="com.portableai.portable_ai_flutter"
LOG="${RUNNER_TEMP:-/tmp}/smoke_logcat.txt"

echo "Installing $APK"
adb install -r "$APK"

adb logcat -c || true
adb logcat -v time > "$LOG" 2>&1 &
LOGCAT_PID=$!
trap 'kill "$LOGCAT_PID" 2>/dev/null || true' EXIT

echo "Launching $PKG"
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 || true

ok=0
for _ in $(seq 1 60); do
  if grep -q "AETHER_SMOKE_DB_OK" "$LOG"; then ok=1; break; fi
  if grep -q "AETHER_SMOKE_FAIL" "$LOG"; then
    echo "::error::App init failed on device:"
    grep "AETHER_SMOKE_FAIL" "$LOG"
    exit 1
  fi
  if grep -qi "journal_mode=WAL" "$LOG"; then
    echo "::error::WAL DatabaseException regressed:"
    grep -i "journal_mode\|DatabaseException" "$LOG" | head -n 20
    exit 1
  fi
  if grep -q "FATAL EXCEPTION" "$LOG"; then
    echo "::error::App crashed on launch:"
    grep -A 30 "FATAL EXCEPTION" "$LOG" | head -n 40
    exit 1
  fi
  sleep 2
done

if [ "$ok" != "1" ]; then
  echo "::error::Timed out waiting for AETHER_SMOKE_DB_OK."
  echo "---- relevant logcat lines (flutter / app / crash) ----"
  grep -iE "flutter|AETHER_SMOKE|FATAL|AndroidRuntime|portable_ai|llama|UnsatisfiedLink|SIGSEGV" "$LOG" | tail -n 120 || true
  exit 1
fi
echo "Storage layer initialized cleanly (AETHER_SMOKE_DB_OK)."
