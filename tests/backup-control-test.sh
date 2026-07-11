#!/bin/bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACKUP_SCRIPT="$ROOT/bin/backup-google-drive.sh"
failures=0

fail() {
  printf 'not ok - %s\n' "$1"
  failures=$((failures + 1))
}

pass() {
  printf 'ok - %s\n' "$1"
}

new_test_home() {
  mktemp -d "${TMPDIR:-/tmp}/gdrive-tiger-test.XXXXXX"
}

test_nas_can_opt_in_to_mount_trigger() {
  local name="NAS target can opt in to mount-triggered backups"
  local test_home log_file
  test_home="$(new_test_home)"
  log_file="$test_home/Library/Logs/gdrive-backup.log"

  HOME="$test_home" \
    MOUNT_SETTLE_SECONDS=0 \
    GDRIVE_BACKUP_TRIGGER=mount \
    GDRIVE_BACKUP_TARGET=nas \
    GDRIVE_BACKUP_NAS_START_ON_MOUNT=1 \
    GDRIVE_BACKUP_NAS_MOUNT='' \
    "$BACKUP_SCRIPT" --dry-run

  if grep -q 'target=nas' "$log_file"; then
    pass "$name"
  else
    fail "$name"
  fi
}

test_nas_stays_opted_out_of_mount_trigger_by_default() {
  local name="NAS target stays excluded from mount-triggered backups by default"
  local test_home log_file
  test_home="$(new_test_home)"
  log_file="$test_home/Library/Logs/gdrive-backup.log"

  HOME="$test_home" \
    MOUNT_SETTLE_SECONDS=0 \
    GDRIVE_BACKUP_TRIGGER=mount \
    GDRIVE_BACKUP_TARGET=nas \
    GDRIVE_BACKUP_NAS_START_ON_MOUNT=0 \
    "$BACKUP_SCRIPT" --dry-run

  if grep -q 'target=apfs' "$log_file"; then
    pass "$name"
  else
    fail "$name"
  fi
}

test_manual_missing_target_is_an_error() {
  local name="manual backup reports an unavailable target"
  local test_home status
  test_home="$(new_test_home)"

  HOME="$test_home" \
    MOUNT_SETTLE_SECONDS=0 \
    GDRIVE_BACKUP_TRIGGER=manual \
    GDRIVE_BACKUP_TARGET=nas \
    GDRIVE_BACKUP_NAS_MOUNT='' \
    "$BACKUP_SCRIPT" --run
  status=$?

  if [[ "$status" == "69" ]]; then
    pass "$name"
  else
    fail "$name (expected 69, got $status)"
  fi
}

test_scheduled_missing_target_is_an_error() {
  local name="scheduled backup reports an unavailable target"
  local test_home status
  test_home="$(new_test_home)"

  HOME="$test_home" \
    MOUNT_SETTLE_SECONDS=0 \
    GDRIVE_BACKUP_TRIGGER=schedule \
    GDRIVE_BACKUP_TARGET=nas \
    GDRIVE_BACKUP_NAS_MOUNT='' \
    "$BACKUP_SCRIPT" --run
  status=$?

  if [[ "$status" == "69" ]]; then
    pass "$name"
  else
    fail "$name (expected 69, got $status)"
  fi
}

test_nas_url_derives_mount_and_destination() {
  local name="NAS URL derives its share mount and destination"
  local test_home log_file
  test_home="$(new_test_home)"
  log_file="$test_home/Library/Logs/gdrive-backup.log"

  HOME="$test_home" \
    MOUNT_SETTLE_SECONDS=0 \
    GDRIVE_BACKUP_TRIGGER=manual \
    GDRIVE_BACKUP_TARGET=nas \
    GDRIVE_BACKUP_NAS_URL='smb://nas.local/Backups' \
    GDRIVE_BACKUP_NAS_MOUNT='' \
    "$BACKUP_SCRIPT" --dry-run

  if grep -Fq 'target=nas mount=/Volumes/Backups dest=/Volumes/Backups/GoogleDrive-Backup' "$log_file"; then
    pass "$name"
  else
    fail "$name"
  fi
}

test_nas_can_opt_in_to_mount_trigger
test_nas_stays_opted_out_of_mount_trigger_by_default
test_manual_missing_target_is_an_error
test_scheduled_missing_target_is_an_error
test_nas_url_derives_mount_and_destination

if (( failures > 0 )); then
  printf '%s test(s) failed.\n' "$failures"
  exit 1
fi

printf 'All backup control tests passed.\n'
