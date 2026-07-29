#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$ROOT/macos/GDriveBackupTiger/Info.plist")"
IDENTIFIER="com.commcats.gdrivebackup"
PKG_NAME="GDrive-Backup-Tiger-${VERSION}.pkg"
APP_SIGN_IDENTITY="${APP_SIGN_IDENTITY:-}"
INSTALLER_SIGN_IDENTITY="${INSTALLER_SIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
export COPYFILE_DISABLE=1

if [[ ( -n "$APP_SIGN_IDENTITY" && -z "$INSTALLER_SIGN_IDENTITY" ) ||
      ( -z "$APP_SIGN_IDENTITY" && -n "$INSTALLER_SIGN_IDENTITY" ) ]]; then
  printf '%s\n' \
    'APP_SIGN_IDENTITY and INSTALLER_SIGN_IDENTITY must be provided together.' >&2
  exit 64
fi

if [[ -n "$NOTARY_PROFILE" && ( -z "$APP_SIGN_IDENTITY" || -z "$INSTALLER_SIGN_IDENTITY" ) ]]; then
  printf '%s\n' \
    'NOTARY_PROFILE requires both APP_SIGN_IDENTITY and INSTALLER_SIGN_IDENTITY.' >&2
  exit 64
fi

BUILD_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/gdrive-pkg-build.XXXXXX")"
PKG_ROOT="$BUILD_DIR/root"
DIST_DIR="$ROOT/dist"
COMPONENT_PKG="$BUILD_DIR/${PKG_NAME}"
FINAL_PKG="$DIST_DIR/${PKG_NAME}"
APP_PATH="$PKG_ROOT/Applications/GDrive Backup Tiger.app"

cleanup() {
  "$ROOT/scripts/trash-path.sh" "$BUILD_DIR" >/dev/null 2>&1 || true
}
trap cleanup EXIT

mkdir -p "$PKG_ROOT/usr/local/bin" \
  "$PKG_ROOT/usr/local/share/gdrive-tiger-backup/launchd" \
  "$DIST_DIR"

/usr/bin/make -C "$ROOT" build APP_DIR="$APP_PATH" >&2

if [[ -n "$APP_SIGN_IDENTITY" ]]; then
  /usr/bin/codesign \
    --force \
    --options runtime \
    --timestamp \
    --sign "$APP_SIGN_IDENTITY" \
    "$APP_PATH/Contents/MacOS/GDriveBackupTiger" >&2
  /usr/bin/codesign \
    --force \
    --options runtime \
    --timestamp \
    --entitlements "$ROOT/macos/GDriveBackupTiger/GDriveBackupTiger.entitlements" \
    --sign "$APP_SIGN_IDENTITY" \
    "$APP_PATH" >&2
fi

/usr/bin/codesign --verify --deep --strict "$APP_PATH"

install -m 755 "$ROOT/bin/backup-google-drive.sh" "$PKG_ROOT/usr/local/bin/backup-google-drive.sh"
install -m 644 "$ROOT/launchd/com.commcats.gdrivebackup.plist" \
  "$PKG_ROOT/usr/local/share/gdrive-tiger-backup/launchd/com.commcats.gdrivebackup.plist"

/usr/bin/xattr -rc "$PKG_ROOT" >/dev/null 2>&1 || true

pkgbuild_args=(
  --root "$PKG_ROOT"
  --scripts "$ROOT/packaging/scripts"
  --identifier "$IDENTIFIER"
  --version "$VERSION"
  --install-location "/"
)

if [[ -n "$INSTALLER_SIGN_IDENTITY" ]]; then
  pkgbuild_args+=(--sign "$INSTALLER_SIGN_IDENTITY")
fi

/usr/bin/pkgbuild "${pkgbuild_args[@]}" "$COMPONENT_PKG" >&2

if [[ -e "$FINAL_PKG" ]]; then
  "$ROOT/scripts/trash-path.sh" "$FINAL_PKG"
fi
/bin/cp "$COMPONENT_PKG" "$FINAL_PKG"

if [[ -n "$NOTARY_PROFILE" ]]; then
  /usr/bin/xcrun notarytool submit \
    "$FINAL_PKG" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait >&2
  /usr/bin/xcrun stapler staple "$FINAL_PKG" >&2
  /usr/bin/xcrun stapler validate "$FINAL_PKG" >&2
fi

printf '%s\n' "$FINAL_PKG"
