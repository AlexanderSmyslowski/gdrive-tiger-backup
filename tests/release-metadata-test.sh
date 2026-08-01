#!/bin/bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INFO_PLIST="$ROOT/macos/GDriveBackupTiger/Info.plist"
EXPECTED_VERSION="2.4.4"
EXPECTED_BUILD="28"
failures=0

check_contains() {
  local file="$1"
  local expected="$2"
  local description="$3"
  if /usr/bin/grep -Fq -- "$expected" "$file"; then
    printf 'ok - %s\n' "$description"
  else
    printf 'not ok - %s\n' "$description"
    failures=$((failures + 1))
  fi
}

version="$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$INFO_PLIST")"
build="$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$INFO_PLIST")"
minimum_macos="$(/usr/bin/plutil -extract LSMinimumSystemVersion raw -o - "$INFO_PLIST")"

if [[ "$version" != "$EXPECTED_VERSION" || "$build" != "$EXPECTED_BUILD" ]]; then
  printf 'not ok - expected app version %s build %s, got %s build %s\n' \
    "$EXPECTED_VERSION" "$EXPECTED_BUILD" "$version" "$build"
  failures=$((failures + 1))
else
  printf 'ok - app version and build match the release plan\n'
fi

check_contains "$ROOT/README.md" "Current release: \`v${version}\`" \
  "README release matches the app version"
check_contains "$ROOT/README.md" "GDrive-Backup-Tiger-${EXPECTED_VERSION}.pkg" \
  "README names the exact release installer"
check_contains "$ROOT/CHANGELOG.md" "## v${version} " \
  "changelog contains the app version"
check_contains "$ROOT/docs/version-history.md" "| v${version} | ${build} |" \
  "publication history contains the app version and build"
check_contains "$ROOT/README.md" "macOS ${minimum_macos%%.*}" \
  "README states the minimum macOS generation"
check_contains "$ROOT/install.sh" "GDRIVE_BACKUP_RETENTION=1" \
  "source installer enables retention explicitly"
check_contains "$ROOT/install.sh" "GDRIVE_BACKUP_ENCRYPTION=none" \
  "source installer keeps encryption opt-in"
check_contains "$ROOT/install.sh" "GDRIVE_BACKUP_PAUSED=0" \
  "source installer enables automatic backups explicitly"
check_contains "$ROOT/install.sh" "GDRIVE_BACKUP_NOTIFY_FAILURES=1" \
  "source installer enables automatic-backup notifications explicitly"
check_contains "$ROOT/install.sh" "if [[ \"\${GDRIVE_BACKUP_VOLUME_UUID+x}\" == \"x\" ]]" \
  "source installer accepts only an explicitly supplied APFS UUID"
check_contains "$ROOT/install.sh" "An explicitly supplied APFS UUID cannot be empty." \
  "source installer rejects an explicitly empty APFS UUID"
check_contains "$ROOT/install.sh" "LC_ALL=C printf 'GDRIVE_BACKUP_VOLUME_UUID=%q\\n' \"\$BACKUP_VOLUME_UUID\"" \
  "source installer persists the explicitly verified APFS UUID"
check_contains "$ROOT/install.sh" "ACTIVE_PROFILE_FILE=\"\$CONFIG_DIR/active-profile\"" \
  "source installer resolves the active profile before UUID migration"
check_contains "$ROOT/install.sh" "upsert_volume_identity \"\$ACTIVE_PROFILE_CONFIG\"" \
  "source installer updates the active runtime profile as well as the legacy config"
check_contains "$ROOT/install.sh" "/usr/sbin/diskutil info -plist \"\$BACKUP_VOLUME\"" \
  "source installer reads the mounted APFS identity"
check_contains "$ROOT/install.sh" "MOUNTED_VOLUME_UUID\" != \"\$BACKUP_VOLUME_UUID\"" \
  "source installer rejects a UUID that belongs to another mounted volume"
check_contains "$ROOT/install.sh" "MOUNTED_FILESYSTEM_TYPE\" != \"apfs\"" \
  "source installer rejects a mounted non-APFS target"
check_contains "$ROOT/install.sh" "MOUNTED_WRITABLE_MEDIA\" != \"true\"" \
  "source installer rejects a read-only APFS target"
check_contains "$ROOT/install.sh" "-framework UserNotifications" \
  "source installer links the macOS notification framework"
check_contains "$ROOT/install.sh" "-framework NetFS" \
  "source installer links the native network mount framework"

GDRIVE_BACKUP_VOLUME_UUID=not-a-uuid \
  BACKUP_TARGET=apfs \
  /bin/bash "$ROOT/install.sh" >/dev/null 2>&1
invalid_uuid_status=$?
if [[ "$invalid_uuid_status" == "64" ]]; then
  printf 'ok - source installer rejects an invalid APFS UUID before installation\n'
else
  printf 'not ok - source installer rejects an invalid APFS UUID before installation\n'
  failures=$((failures + 1))
fi

check_contains "$ROOT/packaging/scripts/postinstall" "GDRIVE_BACKUP_RETENTION=1" \
  "package installer enables retention explicitly"
check_contains "$ROOT/packaging/scripts/postinstall" "GDRIVE_BACKUP_ENCRYPTION=none" \
  "package installer keeps encryption opt-in"
check_contains "$ROOT/packaging/scripts/postinstall" "GDRIVE_BACKUP_PAUSED=0" \
  "package installer enables automatic backups explicitly"
check_contains "$ROOT/packaging/scripts/postinstall" "GDRIVE_BACKUP_NOTIFY_FAILURES=1" \
  "package installer enables automatic-backup notifications explicitly"

for source in \
  ProfileSupport.m \
  BackupProgressSupport.m \
  NotificationSupport.m \
  SetupHealthSupport.m \
  RestoreSupport.m \
  RestoreBrowserView.m \
  DiagnosticsSupport.m \
  DiagnosticsView.m \
  UpdateSupport.m \
  NetworkMountSupport.m; do
  check_contains "$ROOT/install.sh" "macos/GDriveBackupTiger/$source" \
    "source installer links $source"
done

if (( failures > 0 )); then
  printf '%s release metadata check(s) failed.\n' "$failures"
  exit 1
fi

printf 'All release metadata checks passed.\n'
