#!/bin/bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACKUP_SCRIPT="$ROOT/bin/backup-google-drive.sh"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/gdrive-adhoc-target-test.XXXXXX")"
FAKE_BIN="$TEST_ROOT/fake-bin"
CONFIG="$TEST_ROOT/config"
LOG_FILE="$TEST_ROOT/backup.log"
RUN_STATE_FILE="$TEST_ROOT/run-state.status"
SUMMARY_STATE_FILE="$TEST_ROOT/adhoc-last-run.status"
PERSISTENT_SUMMARY_FILE="$TEST_ROOT/persistent-last-run.status"
RCLONE_LOG="$TEST_ROOT/rclone.log"
FAKE_TRASH="$TEST_ROOT/fake-trash"
APFS_MOUNT="$TEST_ROOT/Volumes/TOSHIBA_4TB"
NAS_MOUNT="$TEST_ROOT/Volumes/NAS"
APFS_UUID="11111111-2222-3333-4444-555555555555"
failures=0

cleanup() {
  "$ROOT/scripts/trash-path.sh" "$TEST_ROOT" >/dev/null 2>&1 || true
}
trap cleanup EXIT

pass() {
  printf 'ok - %s\n' "$1"
}

fail() {
  printf 'not ok - %s\n' "$1"
  failures=$((failures + 1))
}

write_config() {
  local target="$1"
  local include_uuid="$2"
  local destination_root="${3:-}"
  local config_run_target="${4:-}"
  local config_run_volume_uuid="${5:-}"

  {
    LC_ALL=C printf 'GDRIVE_BACKUP_TARGET=%q\n' "$target"
    LC_ALL=C printf 'GDRIVE_BACKUP_VOLUME=%q\n' "$APFS_MOUNT"
    LC_ALL=C printf 'GDRIVE_BACKUP_VOLUME_NAME=%q\n' 'TOSHIBA_4TB'
    if [[ "$include_uuid" == "1" ]]; then
      LC_ALL=C printf 'GDRIVE_BACKUP_VOLUME_UUID=%q\n' "$APFS_UUID"
    fi
    LC_ALL=C printf 'GDRIVE_BACKUP_NAS_MOUNT=%q\n' "$NAS_MOUNT"
    LC_ALL=C printf 'GDRIVE_BACKUP_NAS_SUBDIR=%q\n' 'Scheduled'
    if [[ -n "$destination_root" ]]; then
      LC_ALL=C printf 'GDRIVE_BACKUP_DEST_ROOT=%q\n' "$destination_root"
    fi
    if [[ -n "$config_run_target" ]]; then
      LC_ALL=C printf 'GDRIVE_BACKUP_RUN_TARGET=%q\n' "$config_run_target"
    fi
    if [[ -n "$config_run_volume_uuid" ]]; then
      LC_ALL=C printf 'GDRIVE_BACKUP_RUN_VOLUME_UUID=%q\n' \
        "$config_run_volume_uuid"
    fi
    LC_ALL=C printf 'GDRIVE_BACKUP_SUMMARY_STATE_FILE=%q\n' \
      "$PERSISTENT_SUMMARY_FILE"
    printf '%s\n' \
      'GDRIVE_BACKUP_CONFIRM=0' \
      'GDRIVE_BACKUP_VERSIONING=0' \
      'GDRIVE_BACKUP_RETENTION=0'
  } >"$CONFIG"
}

reset_observations() {
  : >"$LOG_FILE"
  : >"$RCLONE_LOG"
  printf 'sentinel=adhoc\n' >"$SUMMARY_STATE_FILE"
  printf 'sentinel=persistent\n' >"$PERSISTENT_SUMMARY_FILE"
}

run_dry() {
  local trigger="$1"
  local run_target_set="$2"
  local run_target="${3:-}"
  local run_volume_uuid_set="${4:-0}"
  local run_volume_uuid="${5:-}"
  local -a env_options=()
  local -a one_shot_environment=()

  if [[ "$run_target_set" == "1" ]]; then
    one_shot_environment+=("GDRIVE_BACKUP_RUN_TARGET=$run_target")
  else
    env_options+=(-u GDRIVE_BACKUP_RUN_TARGET)
  fi
  if [[ "$run_volume_uuid_set" == "1" ]]; then
    one_shot_environment+=("GDRIVE_BACKUP_RUN_VOLUME_UUID=$run_volume_uuid")
  else
    env_options+=(-u GDRIVE_BACKUP_RUN_VOLUME_UUID)
  fi

  env ${env_options[@]+"${env_options[@]}"} \
    ${one_shot_environment[@]+"${one_shot_environment[@]}"} \
    HOME="$TEST_ROOT" \
    FAKE_APFS_MOUNT="$APFS_MOUNT" \
    FAKE_APFS_UUID="$APFS_UUID" \
    FAKE_NAS_MOUNT="$NAS_MOUNT" \
    FAKE_RCLONE_LOG="$RCLONE_LOG" \
    FAKE_TRASH="$FAKE_TRASH" \
    GDRIVE_BACKUP_CONFIG="$CONFIG" \
    GDRIVE_BACKUP_PATH="$FAKE_BIN:/usr/bin:/bin:/usr/sbin:/sbin" \
    GDRIVE_BACKUP_DISKUTIL="$FAKE_BIN/diskutil" \
    GDRIVE_BACKUP_MOUNT_BIN="$FAKE_BIN/mount" \
    GDRIVE_BACKUP_TEMP_TRASH_BIN="$FAKE_BIN/trash" \
    GDRIVE_BACKUP_LOG="$LOG_FILE" \
    GDRIVE_BACKUP_LOCK="$TEST_ROOT/backup.lock" \
    GDRIVE_BACKUP_RUN_STATE_FILE="$RUN_STATE_FILE" \
    GDRIVE_BACKUP_SUMMARY_STATE_FILE="$SUMMARY_STATE_FILE" \
    GDRIVE_BACKUP_TRIGGER="$trigger" \
    BACKUP_DISABLE_ANIMATION=1 \
    MOUNT_SETTLE_SECONDS=0 \
    "$BACKUP_SCRIPT" --dry-run
}

mkdir -p "$FAKE_BIN" "$FAKE_TRASH" "$APFS_MOUNT" "$NAS_MOUNT"
APFS_REAL="$(cd "$APFS_MOUNT" && pwd -P)"

cat >"$FAKE_BIN/rclone" <<'SH'
#!/bin/bash
printf '%q ' "$@" >>"$FAKE_RCLONE_LOG"
printf '\n' >>"$FAKE_RCLONE_LOG"
if [[ "${1:-}" == "copy" && "${2:-}" == "--help" ]]; then
  printf '%s\n' '  --name-transform stringArray'
elif [[ "${1:-}" == "backend" && "${2:-}" == "--json" &&
        "${3:-}" == "drives" ]]; then
  printf '[]\n'
fi
exit 0
SH

cat >"$FAKE_BIN/diskutil" <<'SH'
#!/bin/bash
if [[ "${1:-}" != "info" || "${2:-}" != "-plist" ]]; then
  exit 90
fi
cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>FilesystemType</key><string>apfs</string>
<key>MountPoint</key><string>${FAKE_APFS_MOUNT}</string>
<key>VolumeUUID</key><string>${FAKE_APFS_UUID}</string>
<key>VolumeName</key><string>TOSHIBA_4TB</string>
<key>WritableMedia</key><true/>
<key>RemovableMediaOrExternalDevice</key><true/>
<key>SystemImage</key><false/>
<key>Encryption</key><false/>
<key>Locked</key><false/>
<key>DeviceIdentifier</key><string>disk99s1</string>
<key>APFSContainerReference</key><string>disk99</string>
</dict></plist>
PLIST
SH

cat >"$FAKE_BIN/mount" <<'SH'
#!/bin/bash
printf '//fixture@nas.test/Backups on %s (smbfs, nodev, nosuid)\n' \
  "$FAKE_NAS_MOUNT"
SH

cat >"$FAKE_BIN/jq" <<'SH'
#!/bin/bash
case " $* " in
  *' length '*) printf '0\n' ;;
esac
exit 0
SH

cat >"$FAKE_BIN/trash" <<'SH'
#!/bin/bash
for path in "$@"; do
  [[ -e "$path" ]] || continue
  destination="$FAKE_TRASH/$(basename "$path").$$.$RANDOM"
  /bin/mv "$path" "$destination"
done
SH

for tool in flock plutil; do
  cat >"$FAKE_BIN/$tool" <<'SH'
#!/bin/bash
exit 0
SH
done
chmod +x "$FAKE_BIN"/*

test_manual_apfs_override_is_repeatable_and_process_bound() {
  local name="manual APFS override is repeatable without changing the NAS profile"
  local before after first_status second_status starts
  write_config nas 1 '' nas
  reset_observations
  before="$(/usr/bin/shasum -a 256 "$CONFIG")"

  run_dry manual 1 apfs 1 "$APFS_UUID"
  first_status=$?
  run_dry manual 1 apfs 1 "$APFS_UUID"
  second_status=$?
  after="$(/usr/bin/shasum -a 256 "$CONFIG")"
  starts="$(/usr/bin/grep -F "target=apfs mount=$APFS_REAL dest=$APFS_REAL" \
    "$LOG_FILE" | /usr/bin/wc -l | /usr/bin/tr -d '[:space:]')"

  if [[ "$first_status" == "0" && "$second_status" == "0" &&
        "$starts" == "2" && "$before" == "$after" &&
        "$(cat "$SUMMARY_STATE_FILE")" == 'sentinel=adhoc' &&
        "$(cat "$PERSISTENT_SUMMARY_FILE")" == 'sentinel=persistent' ]]; then
    pass "$name"
  else
    fail "$name (statuses=$first_status/$second_status starts=$starts)"
  fi
}

test_manual_nas_override_uses_nas_defaults() {
  local name="manual NAS override selects the configured NAS destination"
  local status
  write_config apfs 1
  reset_observations

  run_dry manual 1 nas
  status=$?

  if [[ "$status" == "0" ]] &&
     /usr/bin/grep -Fq \
       "target=nas mount=$NAS_MOUNT dest=$NAS_MOUNT/Scheduled" "$LOG_FILE"; then
    pass "$name"
  else
    fail "$name (status=$status)"
  fi
}

test_config_cannot_grant_run_target_override() {
  local name="persistent configuration cannot grant an ad-hoc target override"
  local status
  write_config nas 1 '' apfs
  reset_observations

  run_dry manual 0
  status=$?

  if [[ "$status" == "0" ]] &&
     /usr/bin/grep -Fq \
       "target=nas mount=$NAS_MOUNT dest=$NAS_MOUNT/Scheduled" "$LOG_FILE"; then
    pass "$name"
  else
    fail "$name (status=$status)"
  fi
}

test_nonmanual_override_is_rejected() {
  local name="scheduled runs cannot consume an ad-hoc target override"
  local status
  write_config nas 1
  reset_observations

  run_dry schedule 1 apfs 1 "$APFS_UUID"
  status=$?

  if [[ "$status" == "64" ]] &&
     /usr/bin/grep -Fq 'nur fuer manuelle Backups' "$LOG_FILE" &&
     [[ ! -s "$RCLONE_LOG" ]]; then
    pass "$name"
  else
    fail "$name (expected safe exit 64 before rclone, got $status)"
  fi
}

test_invalid_override_is_rejected() {
  local name="ad-hoc target accepts only the exact values apfs and nas"
  local status
  write_config nas 1
  reset_observations

  run_dry manual 1 volume
  status=$?

  if [[ "$status" == "64" ]] &&
     /usr/bin/grep -Fq 'muss apfs oder nas sein' "$LOG_FILE" &&
     [[ ! -s "$RCLONE_LOG" ]]; then
    pass "$name"
  else
    fail "$name (expected safe exit 64 before rclone, got $status)"
  fi
}

test_apfs_override_requires_uuid() {
  local name="ad-hoc APFS target requires a stored volume UUID"
  local status
  write_config nas 0
  reset_observations

  run_dry manual 1 apfs 1 "$APFS_UUID"
  status=$?

  if [[ "$status" == "64" ]] &&
     /usr/bin/grep -Fq 'gespeicherte Volume-UUID' "$LOG_FILE" &&
     [[ ! -s "$RCLONE_LOG" ]]; then
    pass "$name"
  else
    fail "$name (expected safe exit 64 before rclone, got $status)"
  fi
}

test_apfs_override_rejects_nas_destination_root() {
  local name="APFS override never guesses past a retained NAS destination root"
  local status
  write_config nas 1 "$NAS_MOUNT/Scheduled"
  reset_observations

  run_dry manual 1 apfs 1 "$APFS_UUID"
  status=$?

  if [[ "$status" == "69" ]] &&
     /usr/bin/grep -Fq \
       'APFS-Ziel liegt ausserhalb des konfigurierten Backup-Volumes' "$LOG_FILE" &&
     [[ ! -s "$RCLONE_LOG" ]]; then
    pass "$name"
  else
    fail "$name (expected fail-closed exit 69 before rclone, got $status)"
  fi
}

test_capability_probe_never_sources_configuration() {
  local name="capability probe is available before configuration is sourced"
  local hostile_config="$TEST_ROOT/hostile-capability-config"
  local output status
  printf 'exit 91\n' >"$hostile_config"

  output="$(HOME="$TEST_ROOT" GDRIVE_BACKUP_CONFIG="$hostile_config" \
    "$BACKUP_SCRIPT" --capabilities 2>/dev/null)"
  status=$?

  if [[ "$status" == "0" && "$output" == 'adhoc-target-v1' ]]; then
    pass "$name"
  else
    fail "$name (expected adhoc-target-v1 with exit 0, got status=$status)"
  fi
}

test_apfs_override_requires_process_selected_uuid() {
  local name="configuration cannot supply the UI-selected APFS volume UUID"
  local status
  write_config nas 1 '' nas "$APFS_UUID"
  reset_observations

  run_dry manual 1 apfs 0
  status=$?

  if [[ "$status" == "78" ]] &&
     /usr/bin/grep -Fq 'ausgewaehlte Volume-UUID fehlt' "$LOG_FILE" &&
     [[ ! -s "$RCLONE_LOG" ]]; then
    pass "$name"
  else
    fail "$name (expected process-bound UUID rejection 78, got $status)"
  fi
}

test_apfs_override_rejects_selected_uuid_mismatch() {
  local name="selected APFS UUID must still match the saved profile at launch"
  local selected_uuid="AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
  local before after status
  write_config nas 1
  reset_observations
  before="$(/usr/bin/shasum -a 256 "$CONFIG")"

  run_dry manual 1 apfs 1 "$selected_uuid"
  status=$?
  after="$(/usr/bin/shasum -a 256 "$CONFIG")"

  if [[ "$status" == "78" && "$before" == "$after" ]] &&
     /usr/bin/grep -Fq 'stimmt nicht mehr mit dem gespeicherten Profil ueberein' \
       "$LOG_FILE" &&
     [[ ! -s "$RCLONE_LOG" ]]; then
    pass "$name"
  else
    fail "$name (expected immutable UUID mismatch exit 78, got $status)"
  fi
}

test_manual_apfs_override_is_repeatable_and_process_bound
test_manual_nas_override_uses_nas_defaults
test_config_cannot_grant_run_target_override
test_nonmanual_override_is_rejected
test_invalid_override_is_rejected
test_apfs_override_requires_uuid
test_apfs_override_rejects_nas_destination_root
test_capability_probe_never_sources_configuration
test_apfs_override_requires_process_selected_uuid
test_apfs_override_rejects_selected_uuid_mismatch

if (( failures > 0 )); then
  printf '%s ad-hoc target test(s) failed.\n' "$failures"
  exit 1
fi

printf 'All ad-hoc target tests passed.\n'
