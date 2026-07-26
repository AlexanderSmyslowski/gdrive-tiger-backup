#!/bin/bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INFO_PLIST="$ROOT/macos/GDriveBackupTiger/Info.plist"
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
minimum_macos="$(/usr/bin/plutil -extract LSMinimumSystemVersion raw -o - "$INFO_PLIST")"

check_contains "$ROOT/README.md" "Current release: \`v${version}\`" \
  "README release matches the app version"
check_contains "$ROOT/CHANGELOG.md" "## v${version} " \
  "changelog contains the app version"
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
check_contains "$ROOT/install.sh" "-framework UserNotifications" \
  "source installer links the macOS notification framework"
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
  NotificationSupport.m \
  SetupHealthSupport.m \
  RestoreSupport.m \
  RestoreBrowserView.m \
  DiagnosticsSupport.m \
  DiagnosticsView.m \
  UpdateSupport.m; do
  check_contains "$ROOT/install.sh" "macos/GDriveBackupTiger/$source" \
    "source installer links $source"
done

if (( failures > 0 )); then
  printf '%s release metadata check(s) failed.\n' "$failures"
  exit 1
fi

printf 'All release metadata checks passed.\n'
