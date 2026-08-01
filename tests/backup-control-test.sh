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

prepare_fake_tools() {
  local test_home="$1"
  local fake_bin="$test_home/fake-bin"
  mkdir -p "$fake_bin"
  for tool in rclone flock jq diskutil plutil mount; do
    printf '%s\n' '#!/bin/bash' 'exit 0' >"$fake_bin/$tool"
  done
  chmod +x "$fake_bin"/*
  printf '%s' "$fake_bin"
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

test_plain_directory_cannot_impersonate_a_nas_mount() {
  local name="plain directory cannot impersonate a mounted NAS"
  local test_home fake_bin fake_mount status log_file
  test_home="$(new_test_home)"
  fake_bin="$(prepare_fake_tools "$test_home")"
  fake_mount="$test_home/not-a-mounted-share"
  log_file="$test_home/Library/Logs/gdrive-backup.log"
  mkdir -p "$fake_mount"

  HOME="$test_home" \
    GDRIVE_BACKUP_PATH="$fake_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    GDRIVE_BACKUP_MOUNT_BIN="$fake_bin/mount" \
    MOUNT_SETTLE_SECONDS=0 \
    GDRIVE_BACKUP_TRIGGER=schedule \
    GDRIVE_BACKUP_TARGET=nas \
    GDRIVE_BACKUP_NAS_MOUNT="$fake_mount" \
    GDRIVE_BACKUP_CONFIRM=0 \
    GDRIVE_BACKUP_VERSIONING=0 \
    GDRIVE_BACKUP_RETENTION=0 \
    BACKUP_DISABLE_ANIMATION=1 \
    "$BACKUP_SCRIPT" --run
  status=$?

  if [[ "$status" == "69" ]] && grep -Fq 'kein verifiziertes Netzwerklaufwerk' "$log_file"; then
    pass "$name"
  else
    fail "$name (expected safe exit 69, got $status)"
  fi
}

test_scheduled_nas_mount_uses_noninteractive_helper() {
  local name="scheduled NAS mount uses only the noninteractive native helper"
  local test_home fake_bin fake_mount marker helper_log forbidden_ui_log log_file
  test_home="$(new_test_home)"
  fake_bin="$(prepare_fake_tools "$test_home")"
  fake_mount="$test_home/Volumes/Backups"
  marker="$test_home/nas-mounted"
  helper_log="$test_home/helper.log"
  forbidden_ui_log="$test_home/forbidden-ui.log"
  log_file="$test_home/Library/Logs/gdrive-backup.log"
  mkdir -p "$fake_mount"

  cat >"$fake_bin/mount" <<'SH'
#!/bin/bash
if [[ -f "$FAKE_NAS_MOUNT_MARKER" ]]; then
  printf '//backup-user@nas.local/Backups on %s (smbfs, nodev, nosuid)\n' \
    "$FAKE_NAS_MOUNT"
fi
SH
  cat >"$fake_bin/mount-helper" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$FAKE_MOUNT_HELPER_LOG"
touch "$FAKE_NAS_MOUNT_MARKER"
SH
  cat >"$fake_bin/open" <<'SH'
#!/bin/bash
printf 'open %s\n' "$*" >>"$FAKE_FORBIDDEN_UI_LOG"
exit 92
SH
  cat >"$fake_bin/osascript" <<'SH'
#!/bin/bash
printf 'osascript %s\n' "$*" >>"$FAKE_FORBIDDEN_UI_LOG"
exit 93
SH
  chmod +x "$fake_bin/mount" "$fake_bin/mount-helper" \
    "$fake_bin/open" "$fake_bin/osascript"

  HOME="$test_home" \
    FAKE_NAS_MOUNT="$fake_mount" \
    FAKE_NAS_MOUNT_MARKER="$marker" \
    FAKE_MOUNT_HELPER_LOG="$helper_log" \
    FAKE_FORBIDDEN_UI_LOG="$forbidden_ui_log" \
    GDRIVE_BACKUP_PATH="$fake_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    GDRIVE_BACKUP_MOUNT_BIN="$fake_bin/mount" \
    GDRIVE_BACKUP_NAS_MOUNT_HELPER="$fake_bin/mount-helper" \
    GDRIVE_BACKUP_OPEN_BIN="$fake_bin/open" \
    GDRIVE_BACKUP_OSASCRIPT="$fake_bin/osascript" \
    GDRIVE_BACKUP_NAS_READY_TIMEOUT_SECONDS=1 \
    GDRIVE_BACKUP_NAS_MOUNT_TIMEOUT_SECONDS=1 \
    MOUNT_SETTLE_SECONDS=0 \
    GDRIVE_BACKUP_TRIGGER=schedule \
    GDRIVE_BACKUP_TARGET=nas \
    GDRIVE_BACKUP_NAS_URL='smb://backup-user@nas.local/Backups' \
    GDRIVE_BACKUP_NAS_MOUNT="$fake_mount" \
    GDRIVE_BACKUP_CONFIRM=0 \
    GDRIVE_BACKUP_VERSIONING=0 \
    GDRIVE_BACKUP_RETENTION=0 \
    BACKUP_DISABLE_ANIMATION=1 \
    "$BACKUP_SCRIPT" --run

  if [[ -f "$marker" ]] &&
      grep -Fq -- '--mount-network-url smb://backup-user@nas.local/Backups' "$helper_log" &&
      [[ ! -e "$forbidden_ui_log" ]] &&
      grep -Fq 'NAS-Ziel bereit:' "$log_file"; then
    pass "$name"
  else
    fail "$name"
  fi
}

test_dry_run_never_logs_nas_credentials() {
  local name="NAS dry-run never logs URL credentials"
  local test_home log_file output_file
  test_home="$(new_test_home)"
  log_file="$test_home/Library/Logs/gdrive-backup.log"
  output_file="$test_home/dry-run.out"

  HOME="$test_home" \
    MOUNT_SETTLE_SECONDS=0 \
    GDRIVE_BACKUP_TRIGGER=manual \
    GDRIVE_BACKUP_TARGET=nas \
    GDRIVE_BACKUP_NAS_URL='smb://backup-user:LEAK-MARKER@nas.local/Backups' \
    GDRIVE_BACKUP_NAS_MOUNT='' \
    "$BACKUP_SCRIPT" --dry-run >"$output_file" 2>&1

  if ! grep -Fq 'LEAK-MARKER' "$log_file" "$output_file" &&
      grep -Fq 'NAS-Freigabe wuerde bei Bedarf still gemountet' "$log_file"; then
    pass "$name"
  else
    fail "$name"
  fi
}

test_embedded_nas_password_never_reaches_helper_or_log() {
  local name="embedded NAS password never reaches helper arguments or logs"
  local test_home fake_bin helper_log log_file output_file
  test_home="$(new_test_home)"
  fake_bin="$(prepare_fake_tools "$test_home")"
  helper_log="$test_home/helper.log"
  log_file="$test_home/Library/Logs/gdrive-backup.log"
  output_file="$test_home/run.out"

  cat >"$fake_bin/mount-helper" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$FAKE_MOUNT_HELPER_LOG"
exit 69
SH
  chmod +x "$fake_bin/mount-helper"

  HOME="$test_home" \
    FAKE_MOUNT_HELPER_LOG="$helper_log" \
    GDRIVE_BACKUP_PATH="$fake_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    GDRIVE_BACKUP_MOUNT_BIN="$fake_bin/mount" \
    GDRIVE_BACKUP_NAS_MOUNT_HELPER="$fake_bin/mount-helper" \
    GDRIVE_BACKUP_NAS_READY_TIMEOUT_SECONDS=1 \
    GDRIVE_BACKUP_NAS_MOUNT_TIMEOUT_SECONDS=1 \
    MOUNT_SETTLE_SECONDS=0 \
    GDRIVE_BACKUP_TRIGGER=schedule \
    GDRIVE_BACKUP_TARGET=nas \
    GDRIVE_BACKUP_NAS_URL='smb://backup-user:LEAK-MARKER@nas.local/Backups' \
    GDRIVE_BACKUP_NAS_MOUNT='/Volumes/Backups' \
    GDRIVE_BACKUP_CONFIRM=0 \
    BACKUP_DISABLE_ANIMATION=1 \
    "$BACKUP_SCRIPT" --run >"$output_file" 2>&1

  if [[ ! -e "$helper_log" ]] &&
      ! grep -Fq 'LEAK-MARKER' "$log_file" "$output_file"; then
    pass "$name"
  else
    fail "$name"
  fi
}

test_invalid_pause_setting_fails_closed() {
  local name="invalid automatic-backup pause setting fails closed"
  local test_home status
  test_home="$(new_test_home)"

  HOME="$test_home" \
    MOUNT_SETTLE_SECONDS=0 \
    GDRIVE_BACKUP_TRIGGER=schedule \
    GDRIVE_BACKUP_PAUSED=damaged \
    GDRIVE_BACKUP_TARGET=nas \
    GDRIVE_BACKUP_NAS_MOUNT='' \
    "$BACKUP_SCRIPT" --run
  status=$?

  if [[ "$status" == "64" ]]; then
    pass "$name"
  else
    fail "$name (expected 64, got $status)"
  fi
}

test_nas_can_opt_in_to_mount_trigger
test_nas_stays_opted_out_of_mount_trigger_by_default
test_manual_missing_target_is_an_error
test_scheduled_missing_target_is_an_error
test_nas_url_derives_mount_and_destination
test_plain_directory_cannot_impersonate_a_nas_mount
test_scheduled_nas_mount_uses_noninteractive_helper
test_dry_run_never_logs_nas_credentials
test_embedded_nas_password_never_reaches_helper_or_log
test_invalid_pause_setting_fails_closed

if (( failures > 0 )); then
  printf '%s test(s) failed.\n' "$failures"
  exit 1
fi

printf 'All backup control tests passed.\n'
