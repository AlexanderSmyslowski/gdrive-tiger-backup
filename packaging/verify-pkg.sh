#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

usage() {
  printf 'Usage: %s [--expect-unsigned|--expect-signed] PACKAGE\n' "$0" >&2
}

SIGNATURE_EXPECTATION="any"
if [[ "${1:-}" == "--expect-unsigned" || "${1:-}" == "--expect-signed" ]]; then
  SIGNATURE_EXPECTATION="${1#--expect-}"
  shift
fi

if [[ $# -ne 1 || ! -f "$1" ]]; then
  usage
  exit 64
fi

PKG_PATH="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
VERIFY_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/gdrive-pkg-verify.XXXXXX")"
EXPANDED_PKG="$VERIFY_ROOT/expanded"

cleanup() {
  "$ROOT/scripts/trash-path.sh" "$VERIFY_ROOT" >/dev/null 2>&1 || true
}
trap cleanup EXIT

archive_listing="$(/usr/bin/xar -tf "$PKG_PATH")"
has_signature=0
if /usr/bin/grep -qx 'Signature' <<<"$archive_listing"; then
  has_signature=1
fi

if [[ "$SIGNATURE_EXPECTATION" == "unsigned" && $has_signature -ne 0 ]]; then
  printf 'Expected an unsigned package, but a signature is present: %s\n' "$PKG_PATH" >&2
  exit 1
fi
if [[ "$SIGNATURE_EXPECTATION" == "signed" && $has_signature -eq 0 ]]; then
  printf 'Expected a signed package, but no signature is present: %s\n' "$PKG_PATH" >&2
  exit 1
fi
if [[ "$SIGNATURE_EXPECTATION" == "signed" ]]; then
  /usr/sbin/pkgutil --check-signature "$PKG_PATH"
fi

/usr/sbin/pkgutil --expand-full "$PKG_PATH" "$EXPANDED_PKG"

PACKAGE_INFO="$EXPANDED_PKG/PackageInfo"
PAYLOAD_ROOT="$EXPANDED_PKG/Payload"
APP_PATH="$PAYLOAD_ROOT/Applications/GDrive Backup Tiger.app"
APP_EXECUTABLE="$APP_PATH/Contents/MacOS/GDriveBackupTiger"
BACKUP_SCRIPT="$PAYLOAD_ROOT/usr/local/bin/backup-google-drive.sh"
LAUNCH_AGENT="$PAYLOAD_ROOT/usr/local/share/gdrive-tiger-backup/launchd/com.commcats.gdrivebackup.plist"
POSTINSTALL="$EXPANDED_PKG/Scripts/postinstall"

required_files=(
  "$PACKAGE_INFO"
  "$APP_PATH/Contents/Info.plist"
  "$APP_EXECUTABLE"
  "$BACKUP_SCRIPT"
  "$LAUNCH_AGENT"
  "$POSTINSTALL"
)

for required_file in "${required_files[@]}"; do
  if [[ ! -f "$required_file" ]]; then
    printf 'Required package file is missing: %s\n' "$required_file" >&2
    exit 1
  fi
done

metadata_file="$(/usr/bin/find "$PAYLOAD_ROOT" \( -name '._*' -o -name '.DS_Store' \) -print -quit)"
if [[ -n "$metadata_file" ]]; then
  printf 'Package contains unwanted Finder metadata: %s\n' "$metadata_file" >&2
  exit 1
fi

if [[ ! -x "$APP_EXECUTABLE" || ! -x "$BACKUP_SCRIPT" || ! -x "$POSTINSTALL" ]]; then
  printf '%s\n' 'Package executable permissions are incomplete.' >&2
  exit 1
fi

if ! /usr/bin/lipo "$APP_EXECUTABLE" -verify_arch arm64 x86_64; then
  printf '%s\n' 'Packaged app is not a Universal 2 arm64/x86_64 binary.' >&2
  exit 1
fi

build_info="$(/usr/bin/vtool -show-build "$APP_EXECUTABLE")"
minos_count=0
while IFS= read -r minos; do
  [[ -n "$minos" ]] || continue
  minos_count=$((minos_count + 1))
  if [[ "$minos" != "13.0" ]]; then
    printf 'Packaged app has unexpected deployment target: %s\n' "$minos" >&2
    exit 1
  fi
done < <(/usr/bin/awk '$1 == "minos" { print $2 }' <<<"$build_info")
if [[ "$minos_count" != "2" ]]; then
  printf 'Expected deployment metadata for two architectures, found %s.\n' "$minos_count" >&2
  exit 1
fi

package_identifier="$(/usr/bin/xmllint --xpath 'string(/pkg-info/@identifier)' "$PACKAGE_INFO")"
package_version="$(/usr/bin/xmllint --xpath 'string(/pkg-info/@version)' "$PACKAGE_INFO")"
install_location="$(/usr/bin/xmllint --xpath 'string(/pkg-info/@install-location)' "$PACKAGE_INFO")"
app_version="$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$APP_PATH/Contents/Info.plist")"

if [[ "$package_identifier" != "com.commcats.gdrivebackup" ]]; then
  printf 'Package identifier is incorrect: %s\n' "$package_identifier" >&2
  exit 1
fi
if [[ "$package_version" != "$app_version" ]]; then
  printf 'Package version %s does not match app version %s.\n' \
    "$package_version" "$app_version" >&2
  exit 1
fi
if [[ "$install_location" != "/" ]]; then
  printf 'Package install location is incorrect: %s\n' "$install_location" >&2
  exit 1
fi

/usr/bin/plutil -lint "$APP_PATH/Contents/Info.plist" "$LAUNCH_AGENT" >/dev/null
/bin/bash -n "$BACKUP_SCRIPT" "$POSTINSTALL"
if ! /usr/bin/grep -Fq "/bin/chmod 600 \"\$config_file\"" "$POSTINSTALL"; then
  printf '%s\n' 'Postinstall does not enforce private config permissions.' >&2
  exit 1
fi
/usr/bin/codesign --verify --deep --strict "$APP_PATH"
APP_ENTITLEMENTS="$VERIFY_ROOT/app-entitlements.plist"
if ! /usr/bin/codesign --display --entitlements :- "$APP_PATH" \
        >"$APP_ENTITLEMENTS" 2>/dev/null ||
   [[ "$(/usr/libexec/PlistBuddy \
        -c 'Print :com.apple.developer.usernotifications.time-sensitive' \
        "$APP_ENTITLEMENTS" 2>/dev/null || true)" != "true" ]]; then
  printf '%s\n' \
    'Packaged app is missing the time-sensitive notification entitlement.' >&2
  exit 1
fi

if [[ "$SIGNATURE_EXPECTATION" == "signed" ]]; then
  app_signature="$(/usr/bin/codesign --display --verbose=4 "$APP_PATH" 2>&1)"
  if ! /usr/bin/grep -Fq 'Authority=Developer ID Application:' <<<"$app_signature"; then
    printf '%s\n' 'Signed package does not contain a Developer ID Application-signed app.' >&2
    exit 1
  fi
  if ! /usr/bin/grep -Eq 'flags=.*\(runtime\)' <<<"$app_signature"; then
    printf '%s\n' 'Signed app does not enable hardened runtime.' >&2
    exit 1
  fi
fi

printf 'Package smoke verification passed: %s\n' "$PKG_PATH"
