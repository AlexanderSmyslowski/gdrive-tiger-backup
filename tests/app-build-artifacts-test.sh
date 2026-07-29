#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAGE="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/gdrive-app-build-test.XXXXXX")"
APP="$STAGE/GDrive Backup Tiger.app"
ENTITLEMENTS="$STAGE/app-entitlements.plist"

cleanup() {
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

if ! /usr/bin/codesign --display --entitlements :- "$APP" >"$ENTITLEMENTS" 2>/dev/null ||
   [[ "$(/usr/libexec/PlistBuddy \
      -c 'Print :com.apple.developer.usernotifications.time-sensitive' \
      "$ENTITLEMENTS" 2>/dev/null || true)" != "true" ]]; then
  printf '%s\n' 'not ok - isolated app build preserves the time-sensitive notification entitlement'
  exit 1
fi

for signing_entrypoint in Makefile install.sh packaging/build-pkg.sh; do
  if ! /usr/bin/grep -Fq 'GDriveBackupTiger.entitlements' "$ROOT/$signing_entrypoint"; then
    printf 'not ok - %s preserves notification entitlements while signing\n' \
      "$signing_entrypoint"
    exit 1
  fi
done

printf '%s\n' \
  'ok - isolated app build produces signed universal binary, icon assets, and notification entitlement'
