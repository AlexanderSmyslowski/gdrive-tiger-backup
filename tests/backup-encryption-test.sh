#!/bin/bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACKUP_SCRIPT="$ROOT/bin/backup-google-drive.sh"
failures=0
TEST_DIRS=()

cleanup() {
  local path
  for path in "${TEST_DIRS[@]}"; do
    [[ -e "$path" ]] || continue
    "$ROOT/scripts/trash-path.sh" "$path" >/dev/null 2>&1 || true
  done
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1"
  failures=$((failures + 1))
}

pass() {
  printf 'ok - %s\n' "$1"
}

prepare_test_environment() {
  TEST_HOME="$(mktemp -d "${TMPDIR:-/tmp}/gdrive-encryption-test.XXXXXX")"
  TEST_DIRS+=("$TEST_HOME")
  FAKE_BIN="$TEST_HOME/fake-bin"
  VOLUME="$TEST_HOME/GoogleDrive-Backup"
  DISKUTIL_LOG="$TEST_HOME/diskutil.log"
  DISKUTIL_COUNT_FILE="$TEST_HOME/diskutil-count"
  RCLONE_LOG="$TEST_HOME/rclone.log"
  mkdir -p "$FAKE_BIN"

  cat >"$FAKE_BIN/rclone" <<'SH'
#!/bin/bash
set -u
printf '%s\n' "$*" >>"${FAKE_RCLONE_LOG:?}"
case "${1:-}" in
  config) exit 0 ;;
  backend) printf '[]\n'; exit 0 ;;
  copy) exit 0 ;;
esac
exit 64
SH

  cat >"$FAKE_BIN/jq" <<'SH'
#!/bin/bash
case "${1:-}" in
  length) printf '0\n' ;;
  -r) exit 0 ;;
  *) exit 64 ;;
esac
SH

  cat >"$FAKE_BIN/flock" <<'SH'
#!/bin/bash
exit 0
SH

  cat >"$FAKE_BIN/diskutil" <<'SH'
#!/bin/bash
set -u
printf '%s\n' "$*" >>"${FAKE_DISKUTIL_LOG:?}"
if [[ "${1:-}" == "info" && "${2:-}" == "-plist" ]]; then
  count=1
  if [[ -f "${FAKE_DISKUTIL_COUNT_FILE:?}" ]]; then
    count="$(( $(<"$FAKE_DISKUTIL_COUNT_FILE") + 1 ))"
  fi
  printf '%s\n' "$count" >"$FAKE_DISKUTIL_COUNT_FILE"
  if [[ "${FAKE_PLIST_MODE:-valid}" == "malformed" ]]; then
    printf '%s\n' 'not a plist'
    exit 0
  fi
  encryption_value="${FAKE_ENCRYPTION_VALUE:-false}"
  volume_uuid="${FAKE_VOLUME_UUID:-11111111-2222-3333-4444-555555555555}"
  if (( count > 1 )); then
    encryption_value="${FAKE_ENCRYPTION_AFTER_FIRST-$encryption_value}"
    volume_uuid="${FAKE_VOLUME_UUID_AFTER_FIRST-$volume_uuid}"
  fi
  cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>FilesystemType</key><string>${FAKE_FILESYSTEM_TYPE:-apfs}</string>
  <key>MountPoint</key><string>${FAKE_MOUNT_POINT:-/missing-test-mount}</string>
  $(if [[ "${FAKE_PLIST_MODE:-valid}" != "missing-encryption" ]]; then
      printf '<key>Encryption</key><%s/>' "$encryption_value"
    fi)
  <key>Locked</key><${FAKE_LOCKED_VALUE:-false}/>
  <key>VolumeUUID</key><string>${volume_uuid}</string>
  <key>DeviceIdentifier</key><string>${FAKE_DEVICE_IDENTIFIER:-disk99s1}</string>
</dict>
</plist>
PLIST
  exit 0
fi
if [[ "${1:-}" == "apfs" && "${2:-}" == "addVolume" ]]; then
  exit 0
fi
exit 64
SH

  chmod +x "$FAKE_BIN/rclone" "$FAKE_BIN/jq" "$FAKE_BIN/flock" "$FAKE_BIN/diskutil"
}

run_backup_command() {
  local argument="$1"
  shift
  env \
    HOME="$TEST_HOME" \
    GDRIVE_BACKUP_PATH="$FAKE_BIN:/usr/bin:/bin:/usr/sbin:/sbin" \
    GDRIVE_BACKUP_DISKUTIL="$FAKE_BIN/diskutil" \
    FAKE_DISKUTIL_LOG="$DISKUTIL_LOG" \
    FAKE_DISKUTIL_COUNT_FILE="$DISKUTIL_COUNT_FILE" \
    FAKE_RCLONE_LOG="$RCLONE_LOG" \
    MOUNT_SETTLE_SECONDS=0 \
    GDRIVE_BACKUP_TARGET=apfs \
    GDRIVE_BACKUP_VOLUME="$VOLUME" \
    GDRIVE_BACKUP_DEST_ROOT="$VOLUME" \
    GDRIVE_BACKUP_CONFIRM=0 \
    GDRIVE_BACKUP_AUTO_CREATE_VOLUME=1 \
    GDRIVE_BACKUP_VERSIONING=0 \
    GDRIVE_BACKUP_RETENTION=0 \
    GDRIVE_BACKUP_LOCK="$TEST_HOME/backup.lock" \
    GDRIVE_BACKUP_LOG="$TEST_HOME/backup.log" \
    BACKUP_DISABLE_ANIMATION=1 \
    RCLONE_REMOTE=tdd-remote \
    "$@" \
    "$BACKUP_SCRIPT" "$argument"
}

run_backup() {
  run_backup_command --run "$@"
}

test_invalid_encryption_mode_is_rejected() {
  local name="invalid encryption mode is rejected before backup access"
  local status
  prepare_test_environment
  mkdir -p "$VOLUME"

  run_backup GDRIVE_BACKUP_ENCRYPTION=magic
  status=$?

  if [[ "$status" == "64" && ! -s "$RCLONE_LOG" ]] &&
    grep -Fq 'GDRIVE_BACKUP_ENCRYPTION' "$TEST_HOME/backup.log"; then
    pass "$name"
  else
    fail "$name (status $status)"
  fi
}

test_apfs_encryption_mode_rejects_nas_target() {
  local name="APFS encryption mode cannot silently accept a NAS target"
  local status
  prepare_test_environment
  mkdir -p "$VOLUME"

  run_backup GDRIVE_BACKUP_ENCRYPTION=apfs GDRIVE_BACKUP_TARGET=nas \
    GDRIVE_BACKUP_NAS_MOUNT="$VOLUME" GDRIVE_BACKUP_DEST_ROOT="$VOLUME/backup"
  status=$?

  if [[ "$status" == "64" && ! -s "$RCLONE_LOG" ]] &&
    grep -Fq 'APFS' "$TEST_HOME/backup.log"; then
    pass "$name"
  else
    fail "$name (status $status)"
  fi
}

test_encrypted_mode_never_auto_creates_plain_volume() {
  local name="encrypted mode never auto-creates an unencrypted APFS volume"
  local status
  prepare_test_environment

  run_backup GDRIVE_BACKUP_ENCRYPTION=apfs
  status=$?

  if [[ "$status" == "69" ]] &&
    ! grep -Fq 'apfs addVolume' "$DISKUTIL_LOG" 2>/dev/null &&
    grep -Fq 'verschluesselt' "$TEST_HOME/backup.log"; then
    pass "$name"
  else
    fail "$name (status $status)"
  fi
}

test_unencrypted_apfs_volume_is_rejected() {
  local name="unencrypted APFS volume is rejected in fail-closed mode"
  local status
  prepare_test_environment
  mkdir -p "$VOLUME"

  run_backup GDRIVE_BACKUP_ENCRYPTION=apfs FAKE_ENCRYPTION_VALUE=false \
    FAKE_MOUNT_POINT="$VOLUME"
  status=$?

  if [[ "$status" == "69" && ! -s "$RCLONE_LOG" ]] &&
    grep -Fq 'nicht verschluesselt' "$TEST_HOME/backup.log"; then
    pass "$name"
  else
    fail "$name (status $status)"
  fi
}

test_encrypted_apfs_volume_is_accepted() {
  local name="encrypted APFS volume proceeds without storing a passphrase"
  local status
  prepare_test_environment
  mkdir -p "$VOLUME"

  run_backup GDRIVE_BACKUP_ENCRYPTION=apfs FAKE_ENCRYPTION_VALUE=true \
    FAKE_MOUNT_POINT="$VOLUME" GDRIVE_BACKUP_VERSIONING=1
  status=$?

  if [[ "$status" == "0" ]] &&
    grep -Fq 'info -plist' "$DISKUTIL_LOG" &&
    grep -Fq 'copy ' "$RCLONE_LOG" &&
    grep -Fq -- "--backup-dir $VOLUME/.gdrive-versions/" "$RCLONE_LOG"; then
    pass "$name"
  else
    fail "$name (status $status)"
  fi
}

test_default_mode_preserves_existing_targets() {
  local name="default mode keeps existing unencrypted target behavior"
  local status
  prepare_test_environment
  mkdir -p "$VOLUME"

  run_backup
  status=$?

  if [[ "$status" == "0" && ( ! -e "$DISKUTIL_LOG" || ! -s "$DISKUTIL_LOG" ) ]] &&
    grep -Fq 'copy ' "$RCLONE_LOG"; then
    pass "$name"
  else
    fail "$name (status $status)"
  fi
}

test_unreadable_encryption_metadata_is_rejected() {
  local name="missing or malformed encryption metadata fails closed"
  local mode status rejected=0

  for mode in missing-encryption malformed; do
    prepare_test_environment
    mkdir -p "$VOLUME"
    run_backup GDRIVE_BACKUP_ENCRYPTION=apfs FAKE_ENCRYPTION_VALUE=true \
      FAKE_MOUNT_POINT="$VOLUME" "FAKE_PLIST_MODE=$mode"
    status=$?
    if [[ "$status" == "69" && ! -s "$RCLONE_LOG" ]]; then
      rejected=$((rejected + 1))
    fi
  done

  if [[ "$rejected" == "2" ]]; then
    pass "$name"
  else
    fail "$name ($rejected of 2 rejected)"
  fi
}

test_mismatched_mount_point_is_rejected() {
  local name="disk metadata must identify the configured mount point"
  local status
  prepare_test_environment
  mkdir -p "$VOLUME"

  run_backup GDRIVE_BACKUP_ENCRYPTION=apfs FAKE_ENCRYPTION_VALUE=true \
    FAKE_MOUNT_POINT="$TEST_HOME/other-volume"
  status=$?

  if [[ "$status" == "69" && ! -s "$RCLONE_LOG" ]]; then
    pass "$name"
  else
    fail "$name (status $status)"
  fi
}

test_destination_symlink_escape_is_rejected() {
  local name="destination overrides and symlinks cannot escape encrypted APFS"
  local status escaped=0 outside

  prepare_test_environment
  mkdir -p "$VOLUME"
  outside="$TEST_HOME/plain-destination"
  mkdir -p "$outside"
  /bin/ln -s "$outside" "$VOLUME/backup"
  run_backup GDRIVE_BACKUP_ENCRYPTION=apfs FAKE_ENCRYPTION_VALUE=true \
    FAKE_MOUNT_POINT="$VOLUME" GDRIVE_BACKUP_DEST_ROOT="$VOLUME/backup"
  status=$?
  if [[ "$status" == "69" && ! -s "$RCLONE_LOG" ]]; then
    escaped=$((escaped + 1))
  fi

  prepare_test_environment
  mkdir -p "$VOLUME"
  outside="$TEST_HOME/plain-versions"
  mkdir -p "$outside"
  /bin/ln -s "$outside" "$VOLUME/.gdrive-versions"
  run_backup GDRIVE_BACKUP_ENCRYPTION=apfs FAKE_ENCRYPTION_VALUE=true \
    FAKE_MOUNT_POINT="$VOLUME" GDRIVE_BACKUP_VERSIONING=1
  status=$?
  if [[ "$status" == "69" && ! -s "$RCLONE_LOG" ]]; then
    escaped=$((escaped + 1))
  fi

  prepare_test_environment
  mkdir -p "$VOLUME"
  outside="$TEST_HOME/plain-override"
  mkdir -p "$outside"
  run_backup GDRIVE_BACKUP_ENCRYPTION=apfs FAKE_ENCRYPTION_VALUE=true \
    FAKE_MOUNT_POINT="$VOLUME" GDRIVE_BACKUP_DEST_ROOT="$outside"
  status=$?
  if [[ "$status" == "69" && ! -s "$RCLONE_LOG" ]]; then
    escaped=$((escaped + 1))
  fi

  prepare_test_environment
  mkdir -p "$VOLUME"
  outside="$TEST_HOME/plain-copy-target"
  mkdir -p "$outside"
  /bin/ln -s "$outside" "$VOLUME/My Drive"
  run_backup GDRIVE_BACKUP_ENCRYPTION=apfs FAKE_ENCRYPTION_VALUE=true \
    FAKE_MOUNT_POINT="$VOLUME"
  status=$?
  if [[ "$status" == "69" && ! -s "$RCLONE_LOG" ]]; then
    escaped=$((escaped + 1))
  fi

  if [[ "$escaped" == "4" ]]; then
    pass "$name"
  else
    fail "$name ($escaped of 4 escapes rejected)"
  fi
}

test_dry_run_checks_encryption() {
  local name="dry-run also rejects an unencrypted destination"
  local status
  prepare_test_environment
  mkdir -p "$VOLUME"

  run_backup_command --dry-run GDRIVE_BACKUP_ENCRYPTION=apfs \
    FAKE_ENCRYPTION_VALUE=false FAKE_MOUNT_POINT="$VOLUME"
  status=$?

  if [[ "$status" == "69" && ! -s "$RCLONE_LOG" ]]; then
    pass "$name"
  else
    fail "$name (status $status)"
  fi
}

test_deep_destination_symlink_is_rejected() {
  local name="deep destination symlink cannot redirect cleartext outside APFS"
  local status outside
  prepare_test_environment
  mkdir -p "$VOLUME/My Drive/Nested Parent"
  outside="$TEST_HOME/plain-deep-target"
  mkdir -p "$outside"
  /bin/ln -s "$outside" "$VOLUME/My Drive/Nested Parent/Escape"

  run_backup GDRIVE_BACKUP_ENCRYPTION=apfs FAKE_ENCRYPTION_VALUE=true \
    FAKE_MOUNT_POINT="$VOLUME"
  status=$?

  if [[ "$status" == "69" ]] && ! grep -Eq '^copy( |$)' "$RCLONE_LOG"; then
    pass "$name"
  else
    fail "$name (status $status)"
  fi
}

test_volume_identity_is_revalidated_after_confirmation() {
  local name="volume identity and encryption are revalidated after confirmation"
  local mode status rejected=0

  for mode in encryption uuid; do
    prepare_test_environment
    mkdir -p "$VOLUME"
    if [[ "$mode" == "encryption" ]]; then
      run_backup GDRIVE_BACKUP_ENCRYPTION=apfs FAKE_ENCRYPTION_VALUE=true \
        FAKE_ENCRYPTION_AFTER_FIRST=false FAKE_MOUNT_POINT="$VOLUME"
    else
      run_backup GDRIVE_BACKUP_ENCRYPTION=apfs FAKE_ENCRYPTION_VALUE=true \
        FAKE_VOLUME_UUID_AFTER_FIRST=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee \
        FAKE_MOUNT_POINT="$VOLUME"
    fi
    status=$?
    if [[ "$status" == "69" ]] && ! grep -Eq '^copy( |$)' "$RCLONE_LOG"; then
      rejected=$((rejected + 1))
    fi
  done

  if [[ "$rejected" == "2" ]]; then
    pass "$name"
  else
    fail "$name ($rejected of 2 swaps rejected)"
  fi
}

test_invalid_encryption_mode_is_rejected
test_apfs_encryption_mode_rejects_nas_target
test_encrypted_mode_never_auto_creates_plain_volume
test_unencrypted_apfs_volume_is_rejected
test_encrypted_apfs_volume_is_accepted
test_default_mode_preserves_existing_targets
test_unreadable_encryption_metadata_is_rejected
test_mismatched_mount_point_is_rejected
test_destination_symlink_escape_is_rejected
test_dry_run_checks_encryption
test_deep_destination_symlink_is_rejected
test_volume_identity_is_revalidated_after_confirmation

if (( failures > 0 )); then
  printf '%s encryption test(s) failed.\n' "$failures"
  exit 1
fi

printf '%s\n' 'All backup encryption tests passed.'
