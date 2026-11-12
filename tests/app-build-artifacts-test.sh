#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAGE="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/gdrive-app-build-test.XXXXXX")"
APP="$STAGE/GDrive Backup Tiger.app"
ENTITLEMENTS="$STAGE/app-entitlements.plist"
SMOKE_PID=""

cleanup() {
  if [[ -n "$SMOKE_PID" ]] && /bin/kill -0 "$SMOKE_PID" 2>/dev/null; then
    /bin/kill -TERM "$SMOKE_PID" 2>/dev/null || true
    wait "$SMOKE_PID" 2>/dev/null || true
  fi
  if [[ -e "$STAGE" ]]; then
    "$ROOT/scripts/trash-path.sh" "$STAGE"
  fi
}
trap cleanup EXIT

# Keep the test hermetic: never use (or prompt for) a local signing identity.
export GDRIVE_FORCE_ADHOC_SIGNATURE=1

if ! /usr/bin/make -C "$ROOT" APP_DIR="$APP" build; then
  printf '%s\n' 'not ok - an isolated app build completes successfully'
  exit 1
fi

for artifact in \
  "$APP/Contents/MacOS/GDriveBackupTiger" \
  "$APP/Contents/Resources/AppIcon.icns" \
  "$APP/Contents/Resources/Assets.car"; do
  if [[ ! -s "$artifact" ]]; then
    printf 'not ok - isolated app build produced %s\n' "$artifact"
    exit 1
  fi
done

/usr/bin/codesign --verify --deep --strict "$APP"
/usr/bin/file "$APP/Contents/MacOS/GDriveBackupTiger" \
  | /usr/bin/grep -Fq 'Mach-O universal binary with 2 architectures'

if /usr/bin/codesign --display --entitlements :- "$APP" >"$ENTITLEMENTS" 2>/dev/null &&
   [[ "$(/usr/libexec/PlistBuddy \
      -c 'Print :com.apple.developer.usernotifications.time-sensitive' \
      "$ENTITLEMENTS" 2>/dev/null || true)" == "true" ]]; then
  printf '%s\n' \
    'not ok - an ad-hoc app carries a restricted entitlement and macOS rejects it at launch'
  exit 1
fi

if /usr/bin/grep -Fq 'GDriveBackupTiger.entitlements' "$ROOT/install.sh"; then
  printf '%s\n' \
    'not ok - the source installer embeds a restricted entitlement in an ad-hoc signature'
  exit 1
fi

if /usr/bin/grep -Fq 'GDriveBackupTiger.entitlements' \
     "$ROOT/packaging/build-pkg.sh"; then
  printf '%s\n' \
    'not ok - package builds embed a protected entitlement without a provisioning profile'
  exit 1
fi

# Exercise a headless validation failure: no controller, config, mount or engine
# can start, even though Foundation may derive HOME from the real account.
SMOKE_STATUS=0
"$APP/Contents/MacOS/GDriveBackupTiger" --run-scheduled-backup --unexpected \
  >"$STAGE/launch-smoke.log" 2>&1 || SMOKE_STATUS=$?
if [[ "$SMOKE_STATUS" != "64" ]]; then
  printf 'not ok - signed headless CLI returned %s instead of usage status 64\n' "$SMOKE_STATUS"
  exit 1
fi

printf '%s\n' \
  'ok - isolated app build is Universal 2, signed, launchable, and free of restricted entitlements'
