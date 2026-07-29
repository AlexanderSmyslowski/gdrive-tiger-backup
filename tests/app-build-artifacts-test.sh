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

# Give the isolated copy its own Launch Services identity so this test can run
# beside an installed controller with the production bundle identifier.
/usr/libexec/PlistBuddy \
  -c 'Set :CFBundleIdentifier com.commcats.gdrivebackup.smoketest' \
  "$APP/Contents/Info.plist"
/usr/bin/codesign --force --deep --sign - "$APP" >/dev/null
"$APP/Contents/MacOS/GDriveBackupTiger" --menubar >/dev/null 2>&1 &
SMOKE_PID=$!
for _ in {1..20}; do
  if ! /bin/kill -0 "$SMOKE_PID" 2>/dev/null; then
    wait "$SMOKE_PID" 2>/dev/null || true
    printf '%s\n' \
      'not ok - macOS rejected or immediately terminated the isolated menu bar app'
    exit 1
  fi
  /bin/sleep 0.1
done
/bin/kill -TERM "$SMOKE_PID"
wait "$SMOKE_PID" 2>/dev/null || true
SMOKE_PID=""

printf '%s\n' \
  'ok - isolated app build is Universal 2, signed, launchable, and free of restricted entitlements'
