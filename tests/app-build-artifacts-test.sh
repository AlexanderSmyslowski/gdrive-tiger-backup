#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAGE="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/gdrive-app-build-test.XXXXXX")"
APP="$STAGE/GDrive Backup Tiger.app"

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

printf '%s\n' 'ok - isolated app build produces signed universal binary and icon assets'
