#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$ROOT/macos/GDriveBackupTiger/Info.plist")"
IDENTIFIER="com.commcats.gdrivebackup"
PKG_NAME="GDrive-Backup-Tiger-${VERSION}.pkg"
export COPYFILE_DISABLE=1

BUILD_DIR="$ROOT/build/pkg"
PKG_ROOT="$BUILD_DIR/root"
DIST_DIR="$ROOT/dist"
COMPONENT_PKG="$BUILD_DIR/${PKG_NAME}"
FINAL_PKG="$DIST_DIR/${PKG_NAME}"

rm -rf "$BUILD_DIR"
mkdir -p "$PKG_ROOT/usr/local/bin" \
  "$PKG_ROOT/usr/local/share/gdrive-tiger-backup/launchd" \
  "$DIST_DIR"

make -C "$ROOT" build APP_DIR="$PKG_ROOT/Applications/GDrive Backup Tiger.app"

install -m 755 "$ROOT/bin/backup-google-drive.sh" "$PKG_ROOT/usr/local/bin/backup-google-drive.sh"
install -m 644 "$ROOT/launchd/com.commcats.gdrivebackup.plist" \
  "$PKG_ROOT/usr/local/share/gdrive-tiger-backup/launchd/com.commcats.gdrivebackup.plist"

/usr/bin/xattr -rc "$PKG_ROOT" >/dev/null 2>&1 || true
/usr/bin/find "$PKG_ROOT" -name '.DS_Store' -delete -o -name '._*' -delete

/usr/bin/pkgbuild \
  --root "$PKG_ROOT" \
  --scripts "$ROOT/packaging/scripts" \
  --identifier "$IDENTIFIER" \
  --version "$VERSION" \
  --install-location "/" \
  "$COMPONENT_PKG"

cp "$COMPONENT_PKG" "$FINAL_PKG"

printf '%s\n' "$FINAL_PKG"
