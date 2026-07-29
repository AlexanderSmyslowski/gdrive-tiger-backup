#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAGE="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/gdrive-pkg-entitlement-test.XXXXXX")"
DIST="$STAGE/dist"
EXPANDED="$STAGE/expanded"
MUTATED_PKG="$STAGE/restricted-entitlement.pkg"
VERIFY_OUTPUT="$STAGE/verify-output.txt"

cleanup() {
  if [[ -e "$STAGE" ]]; then
    "$ROOT/scripts/trash-path.sh" "$STAGE"
  fi
}
trap cleanup EXIT

PKG_PATH="$(DIST_DIR="$DIST" "$ROOT/packaging/build-pkg.sh")"
"$ROOT/packaging/verify-pkg.sh" --expect-unsigned "$PKG_PATH" >/dev/null

/usr/sbin/pkgutil --expand-full "$PKG_PATH" "$EXPANDED"
APP="$EXPANDED/Payload/Applications/GDrive Backup Tiger.app"

# Reproduce the v2.4.1 failure shape: codesign accepts the ad-hoc signature,
# but macOS rejects the protected entitlement when the app is executed.
/usr/bin/codesign \
  --force \
  --deep \
  --entitlements "$ROOT/macos/GDriveBackupTiger/GDriveBackupTiger.entitlements" \
  --sign - \
  "$APP" >/dev/null
/usr/sbin/pkgutil --flatten "$EXPANDED" "$MUTATED_PKG"

if "$ROOT/packaging/verify-pkg.sh" --expect-unsigned "$MUTATED_PKG" \
     >"$VERIFY_OUTPUT" 2>&1; then
  printf '%s\n' \
    'not ok - package verification accepted a launch-blocking entitlement'
  exit 1
fi

if ! /usr/bin/grep -Fq \
     'Packaged app must not carry the restricted time-sensitive notification entitlement.' \
     "$VERIFY_OUTPUT"; then
  printf '%s\n' \
    'not ok - package verification failed without identifying the restricted entitlement'
  exit 1
fi

printf '%s\n' \
  'ok - package verification rejects the launch-blocking entitlement mutation'
