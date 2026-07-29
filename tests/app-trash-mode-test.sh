#!/bin/bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAIN_SOURCE="$ROOT/macos/GDriveBackupTiger/main.m"
BACKUP_SCRIPT="$ROOT/bin/backup-google-drive.sh"
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

check_contains "$MAIN_SOURCE" '@"--trash"' \
  'app executable exposes a non-UI Trash mode'
check_contains "$MAIN_SOURCE" 'trashItemAtURL:' \
  'Trash mode uses recoverable NSFileManager deletion'
# These literals intentionally assert shell variable references in the product script.
# shellcheck disable=SC2016
check_contains "$BACKUP_SCRIPT" '"$RETENTION_APP_TRASH_BIN" --trash "$path"' \
  'retention falls back to the packaged app on macOS without /usr/bin/trash'
# shellcheck disable=SC2016
check_contains "$BACKUP_SCRIPT" 'retry_retention_quarantine "$versions_root"' \
  'legacy quarantine is retried on later successful runs'

if (( failures > 0 )); then
  printf '%s app Trash mode check(s) failed.\n' "$failures"
  exit 1
fi

printf '%s\n' 'All app Trash mode checks passed.'
