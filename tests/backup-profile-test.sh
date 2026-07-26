#!/bin/bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACKUP_SCRIPT="$ROOT/bin/backup-google-drive.sh"
TEST_HOME="$(mktemp -d "${TMPDIR:-/tmp}/gdrive-profile-shell-test.XXXXXX")"
CONFIG_DIR="$TEST_HOME/.config/gdrive-tiger-backup"
PROFILE_DIR="$CONFIG_DIR/profiles"
LOG_FILE="$TEST_HOME/Library/Logs/gdrive-backup.log"
failures=0

cleanup() {
  /usr/bin/trash "$TEST_HOME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

pass() {
  printf 'ok - %s\n' "$1"
}

fail() {
  printf 'not ok - %s\n' "$1"
  failures=$((failures + 1))
}

run_and_read_start() {
  /bin/mkdir -p "$TEST_HOME/Library/Logs"
  : >"$LOG_FILE"
  HOME="$TEST_HOME" \
    GDRIVE_BACKUP_CONFIG_DIR="$CONFIG_DIR" \
    GDRIVE_BACKUP_PATH=/usr/bin:/bin:/usr/sbin:/sbin \
    BACKUP_DISABLE_ANIMATION=1 \
    MOUNT_SETTLE_SECONDS=0 \
    "$BACKUP_SCRIPT" --dry-run >/dev/null 2>&1 || true
  /usr/bin/grep 'Start: ' "$LOG_FILE" | /usr/bin/tail -n 1
}

/bin/mkdir -p "$PROFILE_DIR"
/usr/bin/printf '%s\n' \
  'GDRIVE_BACKUP_TARGET=apfs' \
  'GDRIVE_BACKUP_VOLUME=/Volumes/Legacy' >"$CONFIG_DIR/config"
/usr/bin/printf '%s\n' \
  'GDRIVE_BACKUP_PROFILE_ID=default' \
  'GDRIVE_BACKUP_PROFILE_NAME=Default' \
  'GDRIVE_BACKUP_TARGET=nas' \
  'GDRIVE_BACKUP_NAS_MOUNT=/Volumes/ProfileNAS' \
  'GDRIVE_BACKUP_NAS_SUBDIR=ProfileBackup' >"$PROFILE_DIR/default.conf"
printf 'default\n' >"$CONFIG_DIR/active-profile"

start_line="$(run_and_read_start)"
if [[ "$start_line" == *'target=nas mount=/Volumes/ProfileNAS dest=/Volumes/ProfileNAS/ProfileBackup'* ]]; then
  pass "backup engine sources the selected profile config"
else
  fail "backup engine sources the selected profile config"
fi

printf '../../outside\n' >"$CONFIG_DIR/active-profile"
start_line="$(run_and_read_start)"
if [[ "$start_line" == *'target=apfs mount=/Volumes/Legacy dest=/Volumes/Legacy'* ]]; then
  pass "unsafe profile pointers fall back to the legacy config"
else
  fail "unsafe profile pointers fall back to the legacy config"
fi

outside="$TEST_HOME/outside.conf"
/usr/bin/printf '%s\n' \
  'GDRIVE_BACKUP_PROFILE_ID=linked' \
  'GDRIVE_BACKUP_PROFILE_NAME=Linked' \
  'GDRIVE_BACKUP_TARGET=nas' \
  'GDRIVE_BACKUP_NAS_MOUNT=/Volumes/LinkedNAS' >"$outside"
/bin/ln -s "$outside" "$PROFILE_DIR/linked.conf"
printf 'linked\n' >"$CONFIG_DIR/active-profile"
start_line="$(run_and_read_start)"
if [[ "$start_line" == *'target=apfs mount=/Volumes/Legacy dest=/Volumes/Legacy'* ]]; then
  pass "backup engine never sources a symlinked profile"
else
  fail "backup engine never sources a symlinked profile"
fi

# Keep the original directory recoverable inside the disposable test tree. The
# sandbox used by CI may deny access to the account's real macOS Trash.
/bin/mv "$PROFILE_DIR" "$TEST_HOME/profile-dir-before-symlink"
outside_profiles="$TEST_HOME/outside-profiles"
/bin/mkdir -p "$outside_profiles"
/usr/bin/printf '%s\n' \
  'GDRIVE_BACKUP_PROFILE_ID=default' \
  'GDRIVE_BACKUP_PROFILE_NAME=Outside' \
  'GDRIVE_BACKUP_TARGET=nas' \
  'GDRIVE_BACKUP_NAS_MOUNT=/Volumes/OutsideNAS' >"$outside_profiles/default.conf"
/bin/ln -s "$outside_profiles" "$PROFILE_DIR"
printf 'default\n' >"$CONFIG_DIR/active-profile"
start_line="$(run_and_read_start)"
if [[ "$start_line" == *'target=apfs mount=/Volumes/Legacy dest=/Volumes/Legacy'* ]]; then
  pass "backup engine never sources a symlinked profile directory"
else
  fail "backup engine never sources a symlinked profile directory"
fi

override="$TEST_HOME/explicit.conf"
/usr/bin/printf '%s\n' \
  'GDRIVE_BACKUP_TARGET=nas' \
  'GDRIVE_BACKUP_NAS_MOUNT=/Volumes/ExplicitNAS' \
  'GDRIVE_BACKUP_NAS_SUBDIR=ExplicitBackup' >"$override"
/bin/mkdir -p "$TEST_HOME/Library/Logs"
: >"$LOG_FILE"
HOME="$TEST_HOME" \
  GDRIVE_BACKUP_CONFIG_DIR="$CONFIG_DIR" \
  GDRIVE_BACKUP_CONFIG="$override" \
  GDRIVE_BACKUP_PATH=/usr/bin:/bin:/usr/sbin:/sbin \
  BACKUP_DISABLE_ANIMATION=1 \
  MOUNT_SETTLE_SECONDS=0 \
  "$BACKUP_SCRIPT" --dry-run >/dev/null 2>&1 || true
start_line="$(/usr/bin/grep 'Start: ' "$LOG_FILE" | /usr/bin/tail -n 1)"
if [[ "$start_line" == *'target=nas mount=/Volumes/ExplicitNAS dest=/Volumes/ExplicitNAS/ExplicitBackup'* ]]; then
  pass "explicit config overrides remain authoritative"
else
  fail "explicit config overrides remain authoritative"
fi

if (( failures > 0 )); then
  printf '%s profile shell test(s) failed.\n' "$failures"
  exit 1
fi

printf 'All backup profile shell tests passed.\n'
