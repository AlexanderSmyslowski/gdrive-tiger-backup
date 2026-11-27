#!/bin/bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACKUP_SCRIPT="$ROOT/bin/backup-google-drive.sh"
PLATFORM_SCRIPT="$ROOT/lib/platform-macos.sh"
failures=0

fail() {
  printf 'not ok - %s\n' "$1"
  failures=$((failures + 1))
}

pass() {
  printf 'ok - %s\n' "$1"
}

prepare_test_environment() {
  TEST_HOME="$(mktemp -d "${TMPDIR:-/tmp}/gdrive-outcome-test.XXXXXX")"
  FAKE_BIN="$TEST_HOME/fake-bin"
  NAS_MOUNT="$TEST_HOME/nas"
  RUN_STATE_FILE="$TEST_HOME/run-state"
  SUMMARY_STATE_FILE="$TEST_HOME/last-run.status"
  OPEN_LOG="$TEST_HOME/open.log"
  TEMP_TRASH_DIR="$TEST_HOME/temp-trash"
  mkdir -p "$FAKE_BIN" "$NAS_MOUNT" "$TEMP_TRASH_DIR"

  cat >"$FAKE_BIN/rclone" <<'SH'
#!/bin/bash
case "${1:-}" in
  config)
    if [[ -n "${FAKE_RCLONE_CONFIG_STARTED_FILE:-}" ]]; then
      : >"$FAKE_RCLONE_CONFIG_STARTED_FILE"
    fi
    if [[ "${FAKE_RCLONE_CONFIG_SLEEP_SECONDS:-0}" != "0" ]]; then
      /bin/sleep "$FAKE_RCLONE_CONFIG_SLEEP_SECONDS"
    fi
    exit 0
    ;;
  backend)
    if [[ " $* " == *" drives "* ]]; then
      printf '%s\n' "${FAKE_RCLONE_DRIVES_JSON:-[]}"
      exit 0
    fi
    if [[ " $* " == *" query "* ]]; then
      if [[ -n "${FAKE_RCLONE_ARGS_FILE:-}" ]]; then
        printf '%s\n' "$@" >>"$FAKE_RCLONE_ARGS_FILE"
      fi
      if [[ -n "${FAKE_RCLONE_QUERY_STDERR:-}" ]]; then
        printf '%s\n' "$FAKE_RCLONE_QUERY_STDERR" >&2
      fi
      if [[ -n "${FAKE_RCLONE_QUERY_MATCH_1:-}" &&
            "${4:-}" == "$FAKE_RCLONE_QUERY_MATCH_1" ]]; then
        printf '%s\n' "${FAKE_RCLONE_QUERY_JSON_1:-[]}"
        exit "${FAKE_RCLONE_COLLISION_QUERY_STATUS:-0}"
      fi
      if [[ -n "${FAKE_RCLONE_QUERY_MATCH_2:-}" &&
            "${4:-}" == "$FAKE_RCLONE_QUERY_MATCH_2" ]]; then
        printf '%s\n' "${FAKE_RCLONE_QUERY_JSON_2:-[]}"
        exit "${FAKE_RCLONE_COLLISION_QUERY_STATUS:-0}"
      fi
      if [[ -n "${FAKE_RCLONE_QUERY_MATCH_3:-}" &&
            "${4:-}" == "$FAKE_RCLONE_QUERY_MATCH_3" ]]; then
        printf '%s\n' "${FAKE_RCLONE_QUERY_JSON_3:-[]}"
        exit "${FAKE_RCLONE_COLLISION_QUERY_STATUS:-0}"
      fi
      if [[ -n "${FAKE_RCLONE_QUERY_MATCH_4:-}" &&
            "${4:-}" == "$FAKE_RCLONE_QUERY_MATCH_4" ]]; then
        printf '%s\n' "${FAKE_RCLONE_QUERY_JSON_4:-[]}"
        exit "${FAKE_RCLONE_COLLISION_QUERY_STATUS:-0}"
      fi
      printf '%s\n' "${FAKE_RCLONE_COLLISION_QUERY_JSON:-[]}"
      exit "${FAKE_RCLONE_COLLISION_QUERY_STATUS:-0}"
    fi
    if [[ " $* " == *" copyid "* ]]; then
      if [[ -n "${FAKE_RCLONE_ARGS_FILE:-}" ]]; then
        printf '%s\n' "$@" >>"$FAKE_RCLONE_ARGS_FILE"
      fi
      if [[ "${FAKE_RCLONE_ARCHIVE_STATUS:-0}" == "0" &&
            "${FAKE_RCLONE_ARCHIVE_DRY_OUTPUT:-0}" != "1" ]]; then
        if [[ "${FAKE_RCLONE_REJECT_SHARED_FOR_ID:-0}" == "1" &&
              " $* " == *" --drive-shared-with-me "* ]]; then
          exit 88
        fi
        mkdir -p "${5:-}"
        : >"${5:-}/${FAKE_RCLONE_ARCHIVE_FILE_NAME:-image.heic}"
      fi
      exit "${FAKE_RCLONE_ARCHIVE_STATUS:-0}"
    fi
    printf '[]\n'
    exit 0
    ;;
  lsjson)
    printf '%s\n' "${FAKE_RCLONE_PARENT_JSON:-{\"ID\":\"parent-id\",\"IsDir\":true}}"
    exit "${FAKE_RCLONE_PARENT_STATUS:-0}"
    ;;
  copy)
    if [[ "${2:-}" == "--help" ]]; then
      if [[ "${FAKE_RCLONE_SUPPORTS_NAME_TRANSFORM:-1}" == "1" ]]; then
        printf '%s\n' '      --name-transform stringArray   Transform paths during the copy process'
      fi
      exit 0
    fi
    if [[ -n "${FAKE_RCLONE_ARGS_FILE:-}" ]]; then
      printf '%s\n' "$@" >>"$FAKE_RCLONE_ARGS_FILE"
    fi
    if [[ " $* " == *" --drive-root-folder-id "* &&
          "${FAKE_RCLONE_ARCHIVE_CREATE_FOLDER:-1}" == "1" &&
          "${FAKE_RCLONE_ARCHIVE_STATUS:-0}" == "0" ]]; then
      mkdir -p "${3:-}"
    fi
    previous=""
    for argument in "$@"; do
      if [[ "$previous" == "--combined" ]]; then
        printf '%s\n' "${FAKE_RCLONE_ARCHIVE_VERIFY_REPORT:-= verified}" >"$argument"
      fi
      previous="$argument"
    done
    if [[ -n "${FAKE_RCLONE_ADVANCE_EPOCH_TO:-}" &&
          -n "${FAKE_DATE_EPOCH_FILE:-}" ]]; then
      printf '%s\n' "$FAKE_RCLONE_ADVANCE_EPOCH_TO" >"$FAKE_DATE_EPOCH_FILE"
    fi
    if [[ -n "${FAKE_RCLONE_COPY_OUTPUT:-}" &&
          " $* " != *" --drive-root-folder-id "* ]]; then
      if [[ "${FAKE_RCLONE_COPY_OUTPUT_SHARED_ONLY:-0}" != "1" ||
            " $* " == *" --drive-shared-with-me "* ]] &&
         [[ "${FAKE_RCLONE_COPY_OUTPUT_TEAM_DRIVE_ONLY:-0}" != "1" ||
            " $* " == *" --drive-team-drive "* ]]; then
        printf '%s\n' "$FAKE_RCLONE_COPY_OUTPUT"
      fi
    fi
    if [[ "${FAKE_RCLONE_REJECT_SHARED_FOR_ID:-0}" == "1" &&
          " $* " == *" --drive-root-folder-id "* &&
          " $* " == *" --drive-shared-with-me "* ]]; then
      exit 88
    fi
    if [[ -n "${FAKE_RCLONE_STARTED_FILE:-}" ]]; then
      : >"$FAKE_RCLONE_STARTED_FILE"
    fi
    if [[ -n "${FAKE_RCLONE_HIDE_MOUNT_FILE:-}" ]]; then
      # Simulates an SMB mount that vanishes while rclone keeps failing files.
      : >"$FAKE_RCLONE_HIDE_MOUNT_FILE"
      while :; do
        printf '%s\n' 'ERROR : file: Failed to copy: mkdir /Volumes/share: permission denied'
        /bin/sleep 1
      done
    fi
    if [[ "${FAKE_RCLONE_SLEEP_SECONDS:-0}" != "0" ]]; then
      /bin/sleep "$FAKE_RCLONE_SLEEP_SECONDS"
    fi
    if [[ -n "${FAKE_RCLONE_DISCONNECT_MOUNT:-}" ]]; then
      /bin/mv "$FAKE_RCLONE_DISCONNECT_MOUNT" "${FAKE_RCLONE_DISCONNECT_MOUNT}.disconnected"
    fi
    exit "${FAKE_RCLONE_COPY_STATUS:-0}"
    ;;
esac
exit 64
SH

  cat >"$FAKE_BIN/date" <<'SH'
#!/bin/bash
if [[ "${1:-}" == "+%s" && -n "${FAKE_DATE_EPOCH_FILE:-}" ]]; then
  /bin/cat "$FAKE_DATE_EPOCH_FILE"
  exit 0
fi
exec /bin/date "$@"
SH

  cat >"$FAKE_BIN/jq" <<'SH'
#!/bin/bash
if [[ "${FAKE_JQ_USE_SYSTEM:-0}" == "1" ]]; then
  exec /usr/bin/jq "$@"
fi
case "${1:-}" in
  length) printf '0\n' ;;
  -r) exit 0 ;;
  *) exit 64 ;;
esac
SH

  cat >"$FAKE_BIN/open" <<'SH'
#!/bin/bash
: "${FAKE_OPEN_LOG:?}"
printf '%s\n' "$@" >"$FAKE_OPEN_LOG"
if [[ -n "${FAKE_OPEN_HISTORY_LOG:-}" ]]; then
  kind=progress
  [[ " $* " == *" --confirm "* ]] && kind=confirm
  foreground=0
  [[ " $* " == *" --foreground "* ]] && foreground=1
  printf '%s:%s\n' "$kind" "$foreground" >>"$FAKE_OPEN_HISTORY_LOG"
fi
if [[ -n "${FAKE_CONFIRM_DETAIL_LOG:-}" ]]; then
  arguments=("$@")
  for ((index = 0; index < ${#arguments[@]}; index++)); do
    if [[ "${arguments[$index]}" == "--confirm" &&
          $((index + 2)) -lt ${#arguments[@]} ]]; then
      printf '%s' "${arguments[$((index + 2))]}" >"$FAKE_CONFIRM_DETAIL_LOG"
      break
    fi
  done
fi
if [[ -n "${FAKE_CONFIRM_DECISION:-}" && " $* " == *" --confirm "* ]]; then
  response_path="${!#}"
  if [[ "$response_path" == "--foreground" ]]; then
    response_path="${@: -2:1}"
  fi
  printf '%s\n' "$FAKE_CONFIRM_DECISION" >"$response_path"
fi
exit "${FAKE_OPEN_STATUS:-0}"
SH

  cat >"$FAKE_BIN/flock" <<'SH'
#!/bin/bash
exit "${FAKE_FLOCK_STATUS:-0}"
SH

  cat >"$FAKE_BIN/mount" <<'SH'
#!/bin/bash
visible="${FAKE_NAS_MOUNT_VISIBLE:-1}"
if [[ -n "${FAKE_NAS_MOUNT_VISIBLE_FILE:-}" &&
      -e "$FAKE_NAS_MOUNT_VISIBLE_FILE" ]]; then
  visible=1
fi
if [[ -n "${FAKE_NAS_MOUNT_HIDDEN_FILE:-}" &&
      -e "$FAKE_NAS_MOUNT_HIDDEN_FILE" ]]; then
  visible=0
fi
if [[ "$visible" != "1" ]]; then
  exit 0
fi
printf '%s on %s (smbfs, nodev, nosuid)\n' '//backup.test/share' "${FAKE_NAS_MOUNT:?}"
SH

  cat >"$FAKE_BIN/osascript" <<'SH'
#!/bin/bash
exit 90
SH

  cat >"$FAKE_BIN/mount-helper" <<'SH'
#!/bin/bash
if [[ "${1:-}" != "--mount-network-url" || -z "${2:-}" ]]; then
  exit 64
fi
if [[ "${FAKE_MOUNT_HELPER_SLEEP_SECONDS:-0}" != "0" ]]; then
  /bin/sleep "$FAKE_MOUNT_HELPER_SLEEP_SECONDS"
fi
if [[ -n "${FAKE_MOUNT_HELPER_VISIBLE_FILE:-}" ]]; then
  : >"$FAKE_MOUNT_HELPER_VISIBLE_FILE"
fi
if [[ "${FAKE_MOUNT_HELPER_MAKE_WRITABLE:-0}" == "1" ]]; then
  chmod 700 "${FAKE_NAS_MOUNT:?}"
fi
exit "${FAKE_MOUNT_HELPER_STATUS:-0}"
SH

  cat >"$FAKE_BIN/cmp" <<'SH'
#!/bin/bash
if [[ -n "${FAKE_CMP_CALLS_FILE:-}" ]]; then
  printf 'call\n' >>"$FAKE_CMP_CALLS_FILE"
fi
sequence="${FAKE_CMP_STATUS_SEQUENCE:-real}"
if [[ "$sequence" != "real" ]]; then
  IFS=',' read -r -a statuses <<<"$sequence"
  call_number="$(wc -l <"${FAKE_CMP_CALLS_FILE:?}")"
  index=$((call_number - 1))
  if (( index >= ${#statuses[@]} )); then
    index=$((${#statuses[@]} - 1))
  fi
  cmp_status="${statuses[$index]}"
  if [[ "$cmp_status" != "0" ]]; then
    exit "$cmp_status"
  fi
fi
exec /usr/bin/cmp "$@"
SH

  cat >"$FAKE_BIN/trash" <<'SH'
#!/bin/bash
: "${FAKE_TEMP_TRASH_DIR:?}"
for path in "$@"; do
  [[ -e "$path" || -L "$path" ]] || continue
  item_dir="$(mktemp -d "$FAKE_TEMP_TRASH_DIR/item.XXXXXX")" || exit 1
  /bin/mv "$path" "$item_dir/original" || exit 1
done
SH

  cat >"$FAKE_BIN/diskutil" <<'SH'
#!/bin/bash
if [[ "${FAKE_DISKUTIL_MODE:-}" != "external-confirmation" ]]; then
  exit 0
fi

reference="${3:-}"
if [[ -n "${FAKE_DISKUTIL_LOG:-}" ]]; then
  printf '%s\n' "$reference" >>"$FAKE_DISKUTIL_LOG"
fi
case "$reference" in
  "${FAKE_APFS_UUID:?}"|"${FAKE_APFS_MOUNT:?}")
    container_size="4000785104896"
    second_physical_store=""
    if [[ "${FAKE_DISKUTIL_INVALID_SIZE:-0}" == "1" ]]; then
      container_size="not-a-size"
    fi
    if [[ -n "${FAKE_SECOND_PHYSICAL_STORE:-}" ]]; then
      second_physical_store="<dict><key>APFSPhysicalStore</key><string>${FAKE_SECOND_PHYSICAL_STORE}</string></dict>"
    fi
    /bin/cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>FilesystemType</key><string>apfs</string>
<key>MountPoint</key><string>${FAKE_APFS_MOUNT}</string>
<key>VolumeUUID</key><string>${FAKE_APFS_UUID}</string>
<key>VolumeName</key><string>GoogleDrive-Backup</string>
<key>DeviceIdentifier</key><string>disk89s1</string>
<key>WritableMedia</key><true/>
<key>BusProtocol</key><string>USB</string>
<key>APFSContainerSize</key><string>${container_size}</string>
<key>APFSPhysicalStores</key><array><dict>
<key>APFSPhysicalStore</key><string>${FAKE_PHYSICAL_STORE:-disk88s1}</string>
</dict>${second_physical_store}</array>
</dict></plist>
PLIST
    ;;
  disk88s1|/dev/disk88s1)
    if [[ "${FAKE_DISKUTIL_PHYSICAL_STATUS:-0}" != "0" ]]; then
      exit "$FAKE_DISKUTIL_PHYSICAL_STATUS"
    fi
    physical_name="TOSHIBA_4TB"
    physical_size="4000785104896"
    physical_bus="USB"
    if [[ "${FAKE_DISKUTIL_EMPTY_PRIMARY_FIELDS:-0}" == "1" ]]; then
      physical_name=""
      physical_size=""
      physical_bus=""
    elif [[ "${FAKE_DISKUTIL_BIDI_NAME:-0}" == "1" ]]; then
      physical_name="TOSHIBA$(printf '\342\200\256')BT4"
    fi
    if [[ "${FAKE_DISKUTIL_INVALID_SIZE:-0}" == "1" ]]; then
      physical_size="not-a-size"
    fi
    /bin/cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>DeviceIdentifier</key><string>disk88s1</string>
<key>ParentWholeDisk</key><string>disk88</string>
<key>DeviceVendor</key><string></string>
<key>DeviceModel</key><string></string>
<key>IORegistryEntryName</key><string>${physical_name}</string>
<key>TotalSize</key><string>${physical_size}</string>
<key>BusProtocol</key><string>${physical_bus}</string>
<key>SerialNumber</key><string>SECRET-SERIAL-PHYSICAL</string>
</dict></plist>
PLIST
    ;;
  disk88|/dev/disk88)
    /bin/cat <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>DeviceIdentifier</key><string>disk88</string>
<key>IORegistryEntryName</key><string>TOSHIBA EXTERNAL_USB Media</string>
<key>MediaName</key><string>EXTERNAL_USB</string>
<key>TotalSize</key><integer>4000787027968</integer>
<key>BusProtocol</key><string>USB</string>
<key>SerialNumber</key><string>SECRET-SERIAL-WHOLE</string>
</dict></plist>
PLIST
    ;;
  *) exit 1 ;;
esac
SH

  cat >"$FAKE_BIN/ioreg" <<'SH'
#!/bin/bash
if [[ "${FAKE_DISKUTIL_MODE:-}" != "external-confirmation" ]]; then
  exit 1
fi
if [[ "${FAKE_IOREG_SLEEP_SECONDS:-0}" != "0" ]]; then
  /bin/sleep "$FAKE_IOREG_SLEEP_SECONDS"
fi
if [[ "${FAKE_IOREG_STATUS:-0}" != "0" ]]; then
  exit "$FAKE_IOREG_STATUS"
fi
media_name="TOSHIBA_4TB"
if [[ "${FAKE_DISKUTIL_EMPTY_PRIMARY_FIELDS:-0}" == "1" ]]; then
  media_name=""
elif [[ "${FAKE_DISKUTIL_BIDI_NAME:-0}" == "1" ]]; then
  media_name="TOSHIBA$(printf '\342\200\256')BT4"
fi
/bin/cat <<IOREG
+-o ${media_name}@1  <class IOMedia, id 0x100000001, registered, matched, active, busy 0>
  |   "BSD Name" = "${FAKE_PHYSICAL_STORE:-disk88s1}"
IOREG
SH

  cat >"$FAKE_BIN/plutil" <<'SH'
#!/bin/bash
exit 0
SH
  chmod +x "$FAKE_BIN/rclone" "$FAKE_BIN/jq" "$FAKE_BIN/open" "$FAKE_BIN/flock" \
    "$FAKE_BIN/mount" "$FAKE_BIN/osascript" "$FAKE_BIN/mount-helper" \
    "$FAKE_BIN/cmp" "$FAKE_BIN/trash" "$FAKE_BIN/date" \
    "$FAKE_BIN/diskutil" "$FAKE_BIN/ioreg" "$FAKE_BIN/plutil"
}

enable_state_publish_order_spy() {
  cat >"$FAKE_BIN/mv" <<'SH'
#!/bin/bash
destination=""
for argument in "$@"; do destination="$argument"; done
source_path="${@: -2:1}"
case "$destination" in
  */last-run.status|*/current-progress.status)
    if [[ -n "${GDRIVE_BACKUP_STATE_PUBLISH_TEST_LOG:-}" ]]; then
      printf '%s\n' "${destination##*/}" >>"$GDRIVE_BACKUP_STATE_PUBLISH_TEST_LOG"
    fi
    ;;
esac
if [[ "$destination" == */last-run.status &&
      "${GDRIVE_BACKUP_FAIL_TERMINAL_SUMMARY:-0}" == "1" ]] &&
   /usr/bin/grep -Eq '^status=(success|failure|cancelled)$' "$source_path"; then
  exit 91
fi
if [[ "$destination" == */current-progress.status &&
      "${GDRIVE_BACKUP_FAIL_RICH_PROGRESS_AT:-0}" =~ ^[1-9][0-9]*$ ]] &&
   /usr/bin/grep -q '^percent=' "$source_path"; then
  count_file="${GDRIVE_BACKUP_RICH_PROGRESS_COUNT_FILE:?}"
  count="$(/bin/cat "$count_file" 2>/dev/null || printf '0')"
  count=$((count + 1))
  printf '%s\n' "$count" >"$count_file"
  if [[ "$count" == "$GDRIVE_BACKUP_FAIL_RICH_PROGRESS_AT" ]]; then
    exit 92
  fi
fi
if [[ -n "${GDRIVE_BACKUP_FOREGROUND_PROGRESS_MODE_FILE:-}" &&
      "$destination" == */gdrive-backup-progress.* ]]; then
  /usr/bin/stat -f '%Lp' "$source_path" >"$GDRIVE_BACKUP_FOREGROUND_PROGRESS_MODE_FILE"
fi
if [[ -n "${GDRIVE_BACKUP_FOREGROUND_PROGRESS_SNAPSHOT_FILE:-}" &&
      ! -e "$GDRIVE_BACKUP_FOREGROUND_PROGRESS_SNAPSHOT_FILE" &&
      "$destination" == */gdrive-backup-progress.* ]] &&
   /usr/bin/grep -Fxq 'label=My Drive' "$source_path" &&
   /usr/bin/grep -Fxq 'phase=1/2' "$source_path"; then
  /bin/cat "$source_path" >"$GDRIVE_BACKUP_FOREGROUND_PROGRESS_SNAPSHOT_FILE"
fi
exec /bin/mv "$@"
SH
  chmod +x "$FAKE_BIN/mv"
}

last_terminal_publish_order() {
  tail -n 2 "$1" 2>/dev/null | paste -sd, -
}

run_backup_with_mode() {
  local mode="$1"
  shift
  env \
    HOME="$TEST_HOME" \
    GDRIVE_BACKUP_PATH="$FAKE_BIN:/usr/bin:/bin:/usr/sbin:/sbin" \
    MOUNT_SETTLE_SECONDS=0 \
    GDRIVE_BACKUP_TARGET=nas \
    GDRIVE_BACKUP_NAS_MOUNT="$NAS_MOUNT" \
    GDRIVE_BACKUP_MOUNT_BIN="$FAKE_BIN/mount" \
    GDRIVE_BACKUP_NAS_MOUNT_HELPER="$FAKE_BIN/mount-helper" \
    GDRIVE_BACKUP_OPEN_BIN="$FAKE_BIN/open" \
    GDRIVE_BACKUP_OSASCRIPT="${GDRIVE_BACKUP_OSASCRIPT:-$FAKE_BIN/osascript}" \
    GDRIVE_BACKUP_DISKUTIL="${GDRIVE_BACKUP_DISKUTIL:-$FAKE_BIN/diskutil}" \
    GDRIVE_BACKUP_IOREG="${GDRIVE_BACKUP_IOREG:-$FAKE_BIN/ioreg}" \
    GDRIVE_BACKUP_CMP_BIN="$FAKE_BIN/cmp" \
    GDRIVE_BACKUP_DEST_ROOT="$NAS_MOUNT/backup" \
    GDRIVE_BACKUP_CONFIRM="${GDRIVE_BACKUP_CONFIRM:-0}" \
    GDRIVE_BACKUP_LOCK="$TEST_HOME/backup.lock" \
    GDRIVE_BACKUP_VERSIONING=0 \
    GDRIVE_BACKUP_RETENTION=0 \
    GDRIVE_BACKUP_RUN_STATE_FILE="${GDRIVE_BACKUP_RUN_STATE_FILE-$RUN_STATE_FILE}" \
    GDRIVE_BACKUP_SUMMARY_STATE_FILE="$SUMMARY_STATE_FILE" \
    GDRIVE_BACKUP_TEMP_TRASH_BIN="$FAKE_BIN/trash" \
    BACKUP_DISABLE_ANIMATION="${BACKUP_DISABLE_ANIMATION:-1}" \
    FAKE_RCLONE_COPY_STATUS="${FAKE_RCLONE_COPY_STATUS:-0}" \
    FAKE_RCLONE_COPY_OUTPUT="${FAKE_RCLONE_COPY_OUTPUT:-}" \
    FAKE_RCLONE_DRIVES_JSON="${FAKE_RCLONE_DRIVES_JSON:-[]}" \
    FAKE_RCLONE_SUPPORTS_NAME_TRANSFORM="${FAKE_RCLONE_SUPPORTS_NAME_TRANSFORM:-1}" \
    FAKE_RCLONE_COLLISION_QUERY_JSON="${FAKE_RCLONE_COLLISION_QUERY_JSON:-[]}" \
    FAKE_RCLONE_COLLISION_QUERY_STATUS="${FAKE_RCLONE_COLLISION_QUERY_STATUS:-0}" \
    FAKE_RCLONE_QUERY_STDERR="${FAKE_RCLONE_QUERY_STDERR:-}" \
    FAKE_RCLONE_QUERY_MATCH_1="${FAKE_RCLONE_QUERY_MATCH_1:-}" \
    FAKE_RCLONE_QUERY_JSON_1="${FAKE_RCLONE_QUERY_JSON_1:-}" \
    FAKE_RCLONE_QUERY_MATCH_2="${FAKE_RCLONE_QUERY_MATCH_2:-}" \
    FAKE_RCLONE_QUERY_JSON_2="${FAKE_RCLONE_QUERY_JSON_2:-}" \
    FAKE_RCLONE_QUERY_MATCH_3="${FAKE_RCLONE_QUERY_MATCH_3:-}" \
    FAKE_RCLONE_QUERY_JSON_3="${FAKE_RCLONE_QUERY_JSON_3:-}" \
    FAKE_RCLONE_QUERY_MATCH_4="${FAKE_RCLONE_QUERY_MATCH_4:-}" \
    FAKE_RCLONE_QUERY_JSON_4="${FAKE_RCLONE_QUERY_JSON_4:-}" \
    FAKE_RCLONE_PARENT_JSON="${FAKE_RCLONE_PARENT_JSON:-}" \
    FAKE_RCLONE_PARENT_STATUS="${FAKE_RCLONE_PARENT_STATUS:-0}" \
    FAKE_RCLONE_ARCHIVE_STATUS="${FAKE_RCLONE_ARCHIVE_STATUS:-0}" \
    FAKE_RCLONE_ARCHIVE_CREATE_FOLDER="${FAKE_RCLONE_ARCHIVE_CREATE_FOLDER:-1}" \
    FAKE_RCLONE_ARCHIVE_VERIFY_REPORT="${FAKE_RCLONE_ARCHIVE_VERIFY_REPORT:-= verified}" \
    FAKE_RCLONE_ARCHIVE_FILE_NAME="${FAKE_RCLONE_ARCHIVE_FILE_NAME:-image.heic}" \
    FAKE_RCLONE_REJECT_SHARED_FOR_ID="${FAKE_RCLONE_REJECT_SHARED_FOR_ID:-0}" \
    FAKE_RCLONE_COPY_OUTPUT_SHARED_ONLY="${FAKE_RCLONE_COPY_OUTPUT_SHARED_ONLY:-0}" \
    FAKE_RCLONE_COPY_OUTPUT_TEAM_DRIVE_ONLY="${FAKE_RCLONE_COPY_OUTPUT_TEAM_DRIVE_ONLY:-0}" \
    FAKE_RCLONE_ADVANCE_EPOCH_TO="${FAKE_RCLONE_ADVANCE_EPOCH_TO:-}" \
    FAKE_DATE_EPOCH_FILE="${FAKE_DATE_EPOCH_FILE:-}" \
    FAKE_JQ_USE_SYSTEM="${FAKE_JQ_USE_SYSTEM:-0}" \
    FAKE_RCLONE_ARGS_FILE="${FAKE_RCLONE_ARGS_FILE:-}" \
    FAKE_RCLONE_SLEEP_SECONDS="${FAKE_RCLONE_SLEEP_SECONDS:-0}" \
    FAKE_RCLONE_STARTED_FILE="${FAKE_RCLONE_STARTED_FILE:-}" \
    FAKE_RCLONE_DISCONNECT_MOUNT="${FAKE_RCLONE_DISCONNECT_MOUNT:-}" \
    FAKE_RCLONE_CONFIG_STARTED_FILE="${FAKE_RCLONE_CONFIG_STARTED_FILE:-}" \
    FAKE_RCLONE_CONFIG_SLEEP_SECONDS="${FAKE_RCLONE_CONFIG_SLEEP_SECONDS:-0}" \
    FAKE_CMP_STATUS_SEQUENCE="${FAKE_CMP_STATUS_SEQUENCE:-real}" \
    FAKE_CMP_CALLS_FILE="${FAKE_CMP_CALLS_FILE:-}" \
    FAKE_FLOCK_STATUS="${FAKE_FLOCK_STATUS:-0}" \
    FAKE_NAS_MOUNT="$NAS_MOUNT" \
    FAKE_NAS_MOUNT_VISIBLE="${FAKE_NAS_MOUNT_VISIBLE:-1}" \
    FAKE_NAS_MOUNT_VISIBLE_FILE="${FAKE_NAS_MOUNT_VISIBLE_FILE:-}" \
    FAKE_MOUNT_HELPER_VISIBLE_FILE="${FAKE_MOUNT_HELPER_VISIBLE_FILE:-}" \
    FAKE_MOUNT_HELPER_MAKE_WRITABLE="${FAKE_MOUNT_HELPER_MAKE_WRITABLE:-0}" \
    FAKE_MOUNT_HELPER_SLEEP_SECONDS="${FAKE_MOUNT_HELPER_SLEEP_SECONDS:-0}" \
    FAKE_MOUNT_HELPER_STATUS="${FAKE_MOUNT_HELPER_STATUS:-0}" \
    FAKE_TEMP_TRASH_DIR="$TEMP_TRASH_DIR" \
    FAKE_OPEN_LOG="$OPEN_LOG" \
    FAKE_OPEN_STATUS="${FAKE_OPEN_STATUS:-0}" \
    FAKE_CONFIRM_DECISION="${FAKE_CONFIRM_DECISION:-}" \
    FAKE_CONFIRM_DETAIL_LOG="${FAKE_CONFIRM_DETAIL_LOG:-}" \
    FAKE_DISKUTIL_MODE="${FAKE_DISKUTIL_MODE:-}" \
    FAKE_DISKUTIL_PHYSICAL_STATUS="${FAKE_DISKUTIL_PHYSICAL_STATUS:-0}" \
    FAKE_DISKUTIL_EMPTY_PRIMARY_FIELDS="${FAKE_DISKUTIL_EMPTY_PRIMARY_FIELDS:-0}" \
    FAKE_DISKUTIL_BIDI_NAME="${FAKE_DISKUTIL_BIDI_NAME:-0}" \
    FAKE_DISKUTIL_INVALID_SIZE="${FAKE_DISKUTIL_INVALID_SIZE:-0}" \
    FAKE_DISKUTIL_LOG="${FAKE_DISKUTIL_LOG:-}" \
    FAKE_IOREG_SLEEP_SECONDS="${FAKE_IOREG_SLEEP_SECONDS:-0}" \
    FAKE_IOREG_STATUS="${FAKE_IOREG_STATUS:-0}" \
    FAKE_PHYSICAL_STORE="${FAKE_PHYSICAL_STORE:-disk88s1}" \
    FAKE_SECOND_PHYSICAL_STORE="${FAKE_SECOND_PHYSICAL_STORE:-}" \
    FAKE_APFS_UUID="${FAKE_APFS_UUID:-}" \
    FAKE_APFS_MOUNT="${FAKE_APFS_MOUNT:-}" \
    GDRIVE_BACKUP_FAIL_TERMINAL_SUMMARY="${GDRIVE_BACKUP_FAIL_TERMINAL_SUMMARY:-0}" \
    GDRIVE_BACKUP_FAIL_RICH_PROGRESS_AT="${GDRIVE_BACKUP_FAIL_RICH_PROGRESS_AT:-0}" \
    GDRIVE_BACKUP_RICH_PROGRESS_COUNT_FILE="${GDRIVE_BACKUP_RICH_PROGRESS_COUNT_FILE:-}" \
    GDRIVE_BACKUP_FOREGROUND_PROGRESS_SNAPSHOT_FILE="${GDRIVE_BACKUP_FOREGROUND_PROGRESS_SNAPSHOT_FILE:-}" \
    GDRIVE_BACKUP_FOREGROUND_PROGRESS_MODE_FILE="${GDRIVE_BACKUP_FOREGROUND_PROGRESS_MODE_FILE:-}" \
    RCLONE_REMOTE=tdd-remote \
    "$@" \
    "$BACKUP_SCRIPT" "$mode"
}

run_backup() {
  run_backup_with_mode --run "$@"
}

run_dry_backup() {
  run_backup_with_mode --dry-run
}

test_paused_automatic_run_is_silent_and_preserves_history() {
  local name="paused automatic run is silent and preserves backup history"
  local before after status state
  prepare_test_environment
  before=$'protocol=1\nstatus=success\npid=1\nstarted_at=1783790000\nfinished_at=1783790100\nexit_code=0\ntrigger=manual\ntarget=nas\ndestination=/Volumes/Archive'
  printf '%s' "$before" >"$SUMMARY_STATE_FILE"
  chmod 600 "$SUMMARY_STATE_FILE"

  run_backup \
    "GDRIVE_BACKUP_TRIGGER=schedule" \
    "GDRIVE_BACKUP_PAUSED=1" \
    "FAKE_RCLONE_STARTED_FILE=$TEST_HOME/rclone-started"
  status=$?
  after="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"
  state="$(cat "$RUN_STATE_FILE" 2>/dev/null || true)"

  if [[ "$status" == "0" && "$after" == "$before" && ! -e "$TEST_HOME/rclone-started" &&
        "$state" == *$'status=skipped\n'* && "$state" == *$'reason=automatic_backups_paused\n'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status state=${state//$'\n'/,})"
  fi
}

start_backup_async() {
  env \
    HOME="$TEST_HOME" \
    GDRIVE_BACKUP_PATH="$FAKE_BIN:/usr/bin:/bin:/usr/sbin:/sbin" \
    MOUNT_SETTLE_SECONDS=0 \
    GDRIVE_BACKUP_TARGET=nas \
    GDRIVE_BACKUP_NAS_MOUNT="$NAS_MOUNT" \
    GDRIVE_BACKUP_MOUNT_BIN="$FAKE_BIN/mount" \
    GDRIVE_BACKUP_DEST_ROOT="$NAS_MOUNT/backup" \
    GDRIVE_BACKUP_CONFIRM=0 \
    GDRIVE_BACKUP_LOCK="$TEST_HOME/backup.lock" \
    GDRIVE_BACKUP_VERSIONING=0 \
    GDRIVE_BACKUP_RETENTION=0 \
    GDRIVE_BACKUP_RUN_STATE_FILE="$RUN_STATE_FILE" \
    GDRIVE_BACKUP_SUMMARY_STATE_FILE="$SUMMARY_STATE_FILE" \
    GDRIVE_BACKUP_PROFILE_ID="${GDRIVE_BACKUP_PROFILE_ID:-default}" \
    GDRIVE_BACKUP_PROGRESS_STATE_FILE="${GDRIVE_BACKUP_PROGRESS_STATE_FILE:-}" \
    GDRIVE_BACKUP_STATE_PUBLISH_TEST_LOG="${GDRIVE_BACKUP_STATE_PUBLISH_TEST_LOG:-}" \
    GDRIVE_BACKUP_TEMP_TRASH_BIN="$FAKE_BIN/trash" \
    BACKUP_DISABLE_ANIMATION="${BACKUP_DISABLE_ANIMATION:-1}" \
    GDRIVE_BACKUP_ANIMATION_APP="${GDRIVE_BACKUP_ANIMATION_APP:-/Applications/GDrive Backup Tiger.app}" \
    GDRIVE_BACKUP_OPEN_BIN="${GDRIVE_BACKUP_OPEN_BIN:-$FAKE_BIN/open}" \
    FAKE_RCLONE_COPY_STATUS=0 \
    FAKE_RCLONE_SLEEP_SECONDS=3 \
    FAKE_RCLONE_STARTED_FILE="$1" \
    FAKE_RCLONE_CONFIG_STARTED_FILE="${FAKE_RCLONE_CONFIG_STARTED_FILE:-}" \
    FAKE_RCLONE_CONFIG_SLEEP_SECONDS="${FAKE_RCLONE_CONFIG_SLEEP_SECONDS:-0}" \
    FAKE_FLOCK_STATUS=0 \
    FAKE_NAS_MOUNT="$NAS_MOUNT" \
    FAKE_TEMP_TRASH_DIR="$TEMP_TRASH_DIR" \
    FAKE_OPEN_LOG="$OPEN_LOG" \
    RCLONE_REMOTE=tdd-remote \
    "$BACKUP_SCRIPT" --run &
  ASYNC_BACKUP_PID=$!
}

test_failed_backup_publishes_failure() {
  local name="failed backup publishes failure instead of success"
  local status state
  prepare_test_environment

  FAKE_RCLONE_COPY_STATUS=23 run_backup
  status=$?
  state="$(cat "$RUN_STATE_FILE" 2>/dev/null || true)"

  if [[ "$status" == "1" && "$state" == *$'status=failure\n'* && "$state" == *'exit_code=1'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status state=${state//$'\n'/,})"
  fi
}

test_successful_backup_publishes_success() {
  local name="successful backup publishes success"
  local status state
  prepare_test_environment

  FAKE_RCLONE_COPY_STATUS=0 run_backup
  status=$?
  state="$(cat "$RUN_STATE_FILE" 2>/dev/null || true)"

  if [[ "$status" == "0" && "$state" == *$'status=success\n'* && "$state" == *'exit_code=0'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status state=${state//$'\n'/,})"
  fi
}

test_animation_receives_run_state_file() {
  local name="animation receives the explicit run state file"
  local status state_path state
  prepare_test_environment

  mkdir -p "$TEST_HOME/GDrive Backup Tiger.app"
  BACKUP_DISABLE_ANIMATION=0 \
    GDRIVE_BACKUP_RUN_STATE_FILE='' \
    run_backup \
      "GDRIVE_BACKUP_ANIMATION_APP=$TEST_HOME/GDrive Backup Tiger.app" \
      "GDRIVE_BACKUP_OPEN_BIN=$FAKE_BIN/open" \
      "BACKUP_PROGRESS_FOREGROUND=1"
  status=$?
  state_path="$(sed -n '6p' "$OPEN_LOG" 2>/dev/null || true)"
  state="$(cat "$state_path" 2>/dev/null || true)"

  if [[ "$status" == "0" && -n "$state_path" && "$state" == *'status=success'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status path=$state_path state=${state//$'\n'/,})"
  fi
}

test_manual_progress_requests_foreground_activation() {
  local name="explicit progress request keeps one reopenable Dock window"
  local status
  prepare_test_environment

  mkdir -p "$TEST_HOME/GDrive Backup Tiger.app"
  BACKUP_DISABLE_ANIMATION=0 \
    run_backup \
      "GDRIVE_BACKUP_ANIMATION_APP=$TEST_HOME/GDrive Backup Tiger.app" \
      "GDRIVE_BACKUP_OPEN_BIN=$FAKE_BIN/open" \
      "BACKUP_PROGRESS_FOREGROUND=1"
  status=$?

  if [[ "$status" == "0" ]] && grep -Fxq -- '--foreground' "$OPEN_LOG"; then
    pass "$name"
  else
    fail "$name (exit=$status open=${OPEN_LOG//$'\n'/,})"
  fi
}

test_automatic_backup_does_not_open_progress_ui() {
  local name="automatic backup stays headless while publishing its status"
  local status summary open_args
  prepare_test_environment

  mkdir -p "$TEST_HOME/GDrive Backup Tiger.app"
  BACKUP_DISABLE_ANIMATION=0 \
    run_backup \
      "GDRIVE_BACKUP_TRIGGER=schedule" \
      "GDRIVE_BACKUP_ANIMATION_APP=$TEST_HOME/GDrive Backup Tiger.app" \
      "GDRIVE_BACKUP_OPEN_BIN=$FAKE_BIN/open"
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"
  open_args="$(cat "$OPEN_LOG" 2>/dev/null || true)"

  if [[ "$status" == "0" && -z "$open_args" && "$summary" == *$'status=success\n'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status open=${open_args//$'\n'/,} summary=${summary//$'\n'/,})"
  fi
}

test_mount_consent_controls_foreground_progress() {
  local scenario trigger confirm assume decision expected status history
  for scenario in accepted declined timeout disabled assumed scheduled retry; do
    prepare_test_environment
    mkdir -p "$TEST_HOME/GDrive Backup Tiger.app"
    trigger=mount; confirm=1; assume=0; decision=yes
    expected=$'confirm:0\nprogress:1'
    case "$scenario" in
      declined) decision=no; expected='confirm:0' ;;
      timeout) decision=''; expected='confirm:0' ;;
      disabled) confirm=0; expected='' ;;
      assumed) assume=1; expected='' ;;
      scheduled) trigger=schedule; expected='confirm:0' ;;
      retry) trigger=schedule-retry; expected='confirm:0' ;;
    esac
    BACKUP_DISABLE_ANIMATION=0 GDRIVE_BACKUP_CONFIRM="$confirm" \
      FAKE_CONFIRM_DECISION="$decision" run_backup \
        "GDRIVE_BACKUP_TRIGGER=$trigger" \
        "GDRIVE_BACKUP_RETRY_ORIGIN_STARTED_AT=1785261605" \
        "GDRIVE_BACKUP_RETRY_ATTEMPT=1" \
        "GDRIVE_BACKUP_NAS_START_ON_MOUNT=1" \
        "BACKUP_ASSUME_YES=$assume" \
        "BACKUP_PROGRESS_FOREGROUND=0" \
        "GDRIVE_BACKUP_ANIMATION_APP=$TEST_HOME/GDrive Backup Tiger.app" \
        "GDRIVE_BACKUP_OPEN_BIN=$FAKE_BIN/open" \
        "FAKE_OPEN_HISTORY_LOG=$TEST_HOME/open-history"
    status=$?
    history="$(cat "$TEST_HOME/open-history" 2>/dev/null || true)"
    if [[ "$status" == 0 && "$history" == "$expected" ]]; then
      pass "mount consent foreground policy: $scenario"
    else
      fail "mount consent foreground policy: $scenario (exit=$status history=${history//$'\n'/,})"
    fi
  done
}

test_visible_manual_confirmation_requests_foreground() {
  local name="visible manual confirmation is the only foreground prompt"
  local status open_args
  prepare_test_environment

  mkdir -p "$TEST_HOME/GDrive Backup Tiger.app"
  BACKUP_DISABLE_ANIMATION=1 \
    GDRIVE_BACKUP_CONFIRM=1 \
    FAKE_CONFIRM_DECISION=yes \
    run_backup \
      "GDRIVE_BACKUP_ANIMATION_APP=$TEST_HOME/GDrive Backup Tiger.app" \
      "GDRIVE_BACKUP_OPEN_BIN=$FAKE_BIN/open" \
      "BACKUP_PROGRESS_FOREGROUND=1"
  status=$?
  open_args="$(cat "$OPEN_LOG" 2>/dev/null || true)"

  if [[ "$status" == "0" ]] &&
      grep -Fxq -- '--confirm' "$OPEN_LOG" &&
      grep -Fxq -- '--foreground' "$OPEN_LOG"; then
    pass "$name"
  else
    fail "$name (exit=$status open=${open_args//$'\n'/,})"
  fi
}

test_early_configuration_error_publishes_failure() {
  local name="early configuration error publishes failure"
  local status state
  prepare_test_environment

  run_backup "GDRIVE_BACKUP_TARGET=invalid"
  status=$?
  state="$(cat "$RUN_STATE_FILE" 2>/dev/null || true)"

  if [[ "$status" == "64" && "$state" == *$'status=failure\n'* && "$state" == *'exit_code=64'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status state=${state//$'\n'/,})"
  fi
}

test_existing_backup_is_skipped_not_successful() {
  local name="concurrent backup is skipped instead of reported successful"
  local status state
  prepare_test_environment

  FAKE_FLOCK_STATUS=1 run_backup
  status=$?
  state="$(cat "$RUN_STATE_FILE" 2>/dev/null || true)"

  if [[ "$status" == "0" && "$state" == *$'status=skipped\n'* &&
        "$state" == *$'reason=already_running\n'* && "$state" == *'exit_code=0'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status state=${state//$'\n'/,})"
  fi
}

test_perl_lock_replaces_missing_flock() {
  local name="without flock the engine takes the same run lock through perl"
  local status state lock holder
  prepare_test_environment
  /bin/rm -f "$FAKE_BIN/flock"
  lock="$TEST_HOME/backup.lock"
  /bin/mkdir -p "${lock%/*}"

  # A second process holds the lock: the run must be skipped.
  # shellcheck disable=SC2016 # Perl code, not shell.
  /usr/bin/perl -MFcntl=:flock -e \
    'open(my $fh, ">", $ARGV[0]) or exit 2; flock($fh, LOCK_EX) or exit 1; sleep 30' \
    "$lock" &
  holder=$!
  sleep 1
  run_backup
  status=$?
  state="$(cat "$RUN_STATE_FILE" 2>/dev/null || true)"
  kill "$holder" 2>/dev/null
  wait "$holder" 2>/dev/null

  if [[ "$status" == "0" && "$state" == *$'reason=already_running\n'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status state=${state//$'\n'/,})"
  fi

  # Without a holder the same run takes the lock and proceeds.
  run_backup
  state="$(cat "$RUN_STATE_FILE" 2>/dev/null || true)"
  if [[ "$state" != *$'reason=already_running\n'* ]]; then
    pass "without flock and without a concurrent run the backup proceeds"
  else
    fail "without flock and without a concurrent run the backup proceeds (state=${state//$'\n'/,})"
  fi
}

test_run_history_lists_each_finished_run() {
  local name="run history records each finished run and rebuilds older runs from the log"
  local history log_file lines
  prepare_test_environment
  history="$TEST_HOME/Library/Application Support/GDrive Backup Tiger/run-history.tsv"
  log_file="$TEST_HOME/Library/Logs/gdrive-backup.log"
  /bin/mkdir -p "${log_file%/*}"
  # Two finished runs, one dry run and one run that never logged its end.
  cat >"$log_file" <<'LOG'
[2026-05-01 20:00:05+0200] Start: remote=gdrive: dry_run=0 target=apfs mount=/Volumes/Disk A dest=/Volumes/Disk A/GoogleDrive-Backup
2026/05/01 20:10:00 INFO  : Fertig ohne Fehler.
[2026-05-01 20:30:00+0200] Fertig ohne Fehler.
[2026-05-02 20:00:05+0200] Start: remote=gdrive: dry_run=1 target=nas mount=/Volumes/share dest=/Volumes/share/GoogleDrive-Backup
[2026-05-02 20:01:00+0200] Fertig ohne Fehler.
[2026-05-03 20:00:05+0200] Start: remote=gdrive: dry_run=0 target=nas mount=/Volumes/share dest=/Volumes/share/GoogleDrive-Backup
[2026-05-03 20:20:00+0200] Fertig mit 2 Fehler(n).
[2026-05-04 20:00:05+0200] Start: remote=gdrive: dry_run=0 target=nas mount=/Volumes/share dest=/Volumes/share/GoogleDrive-Backup
LOG

  FAKE_RCLONE_COPY_STATUS=0 run_backup >/dev/null 2>&1
  FAKE_RCLONE_COPY_STATUS=23 run_backup >/dev/null 2>&1
  lines="$(cut -f1-4,6 "$history" 2>/dev/null | /usr/bin/sed "s|$NAS_MOUNT|NAS|")"
  local expected
  expected="$(printf '%s\n' \
    $'v1\t1777660200\tsuccess\tapfs\tlog' \
    $'v1\t1777832400\tfailure\tnas\tlog' \
    'SUCCESS' 'FAILURE')"
  lines="$(printf '%s\n' "$lines" | /usr/bin/awk -F'\t' '
    $5 == "log" { print; next }
    $3 == "success" && $4 == "nas" && $5 == "manual" { print "SUCCESS"; next }
    $3 == "failure" && $4 == "nas" && $5 == "manual" { print "FAILURE"; next }
    { print "UNEXPECTED " $0 }')"
  if [[ "$lines" == "$expected" &&
        "$(cut -f5 "$history" | /usr/bin/tail -1)" == "$NAS_MOUNT/backup" &&
        "$(/usr/bin/stat -f '%Lp' "$history")" == "600" ]]; then
    pass "$name"
  else
    fail "$name (got: ${lines//$'\n'/ | })"
  fi
}

test_run_history_keeps_the_newest_lines_and_skips_dry_runs() {
  local name="run history is capped and dry runs do not add entries"
  local history count
  prepare_test_environment
  history="$TEST_HOME/Library/Application Support/GDrive Backup Tiger/run-history.tsv"
  /bin/mkdir -p "${history%/*}"
  for count in $(/usr/bin/seq 1 1005); do
    printf 'v1\t%s\tsuccess\tnas\t/old\tschedule\t%s\n' "$count" "$count"
  done >"$history"
  run_dry_backup >/dev/null 2>&1
  count="$(/usr/bin/wc -l <"$history" | /usr/bin/tr -d ' ')"
  [[ "$count" == "1005" ]] || { fail "$name (dry run changed history: $count lines)"; return; }
  run_backup >/dev/null 2>&1
  count="$(/usr/bin/wc -l <"$history" | /usr/bin/tr -d ' ')"
  if [[ "$count" == "1000" && "$(/usr/bin/head -1 "$history" | cut -f2)" == "7" &&
        "$(/usr/bin/tail -1 "$history" | cut -f3,4)" == $'success\tnas' ]]; then
    pass "$name"
  else
    fail "$name (lines=$count first=$(/usr/bin/head -1 "$history" | cut -f2))"
  fi
}

test_init_history_rebuilds_only_a_missing_history() {
  local name="--init-history rebuilds a missing history from the log and keeps an existing one"
  local history log_file status
  prepare_test_environment
  history="$TEST_HOME/Library/Application Support/GDrive Backup Tiger/run-history.tsv"
  log_file="$TEST_HOME/Library/Logs/gdrive-backup.log"
  /bin/mkdir -p "${log_file%/*}"
  cat >"$log_file" <<'LOG'
[2026-05-01 20:00:05+0200] Start: remote=gdrive: dry_run=0 target=nas mount=/Volumes/share dest=/Volumes/share/GoogleDrive-Backup
[2026-05-01 20:30:00+0200] Fertig ohne Fehler.
LOG
  run_backup_with_mode --init-history >/dev/null 2>&1
  status=$?
  local first
  first="$(cat "$history" 2>/dev/null)"
  printf 'v1\t1\tsuccess\tnas\t/kept\tschedule\t1\n' >"$history"
  run_backup_with_mode --init-history >/dev/null 2>&1
  if [[ "$status" == "0" &&
        "$first" == $'v1\t1777660200\tsuccess\tnas\t/Volumes/share/GoogleDrive-Backup\tlog\t1777658405' &&
        "$(cat "$history")" == $'v1\t1\tsuccess\tnas\t/kept\tschedule\t1' &&
        ! -e "$RUN_STATE_FILE" ]]; then
    pass "$name"
  else
    fail "$name (status=$status first=$first)"
  fi
}

test_state_is_versioned_and_identifies_the_process() {
  local name="run state is versioned and identifies its process"
  local state mode
  prepare_test_environment

  run_backup
  state="$(cat "$RUN_STATE_FILE" 2>/dev/null || true)"
  mode="$(stat -f '%Lp' "$RUN_STATE_FILE" 2>/dev/null || true)"

  if [[ "$state" == *$'protocol=1\n'* &&
        "$state" =~ (^|$'\n')pid=[0-9]+($|$'\n') && "$mode" == "600" ]]; then
    pass "$name"
  else
    fail "$name (mode=$mode state=${state//$'\n'/,})"
  fi
}

test_term_signal_publishes_cancellation() {
  local name="TERM publishes cancellation and invalidates live progress"
  local backup_pid status state summary terminal started_file progress
  local order_log terminal_order
  prepare_test_environment
  enable_state_publish_order_spy
  started_file="$TEST_HOME/rclone-started"
  progress="$TEST_HOME/profiles/default/current-progress.status"
  order_log="$TEST_HOME/state-publish-order.log"
  mkdir -p "${progress%/*}"

  GDRIVE_BACKUP_PROGRESS_STATE_FILE="$progress" \
  GDRIVE_BACKUP_STATE_PUBLISH_TEST_LOG="$order_log" \
    start_backup_async "$started_file"
  backup_pid="$ASYNC_BACKUP_PID"
  for _ in {1..60}; do
    [[ -e "$started_file" ]] && break
    /bin/sleep 0.05
  done
  kill -TERM "$backup_pid" 2>/dev/null || true
  wait "$backup_pid"
  status=$?
  state="$(cat "$RUN_STATE_FILE" 2>/dev/null || true)"
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"
  terminal="$(cat "$progress" 2>/dev/null || true)"
  terminal_order="$(last_terminal_publish_order "$order_log")"

  if [[ "$status" == "143" && "$state" == *$'status=cancelled\n'* &&
        "$state" == *$'signal=TERM\n'* && "$state" == *'exit_code=143'* &&
        "$summary" == *$'status=cancelled\n'* &&
        "$terminal" == *$'status=finished\n'* &&
        "$terminal" != *$'percent='* &&
        "$terminal_order" == "last-run.status,current-progress.status" ]]; then
    pass "$name"
  else
    fail "$name (exit=$status state=${state//$'\n'/,} summary=${summary//$'\n'/,} progress=${terminal//$'\n'/,})"
  fi
}

test_active_backup_publishes_running_summary() {
  local name="active backup publishes a durable running state"
  local backup_pid summary started_file
  prepare_test_environment
  started_file="$TEST_HOME/rclone-started"

  start_backup_async "$started_file"
  backup_pid="$ASYNC_BACKUP_PID"
  for _ in {1..60}; do
    [[ -e "$started_file" ]] && break
    /bin/sleep 0.05
  done
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"
  kill -TERM "$backup_pid" 2>/dev/null || true
  wait "$backup_pid" 2>/dev/null || true

  if [[ "$summary" == *$'status=running\n'* &&
        "$summary" == *"pid=$backup_pid"* &&
        "$summary" != *$'finished_at='* ]]; then
    pass "$name"
  else
    fail "$name (summary=${summary//$'\n'/,})"
  fi
}

test_locked_backup_publishes_running_before_remote_checks() {
  local name="locked backup publishes running state before slow remote checks"
  local backup_pid summary config_started_file
  prepare_test_environment
  config_started_file="$TEST_HOME/rclone-config-started"

  FAKE_RCLONE_CONFIG_STARTED_FILE="$config_started_file" \
    FAKE_RCLONE_CONFIG_SLEEP_SECONDS=3 \
    start_backup_async "$TEST_HOME/rclone-copy-started"
  backup_pid="$ASYNC_BACKUP_PID"
  for _ in {1..60}; do
    [[ -e "$config_started_file" ]] && break
    /bin/sleep 0.05
  done
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"
  kill -TERM "$backup_pid" 2>/dev/null || true
  wait "$backup_pid" 2>/dev/null || true

  if [[ "$summary" == *$'status=running\n'* && "$summary" == *"pid=$backup_pid"* ]]; then
    pass "$name"
  else
    fail "$name (summary=${summary//$'\n'/,})"
  fi
}

test_locked_backup_opens_progress_before_remote_checks() {
  local name="locked backup opens progress before slow remote checks"
  local backup_pid config_started_file
  prepare_test_environment
  config_started_file="$TEST_HOME/rclone-config-started"
  mkdir -p "$TEST_HOME/GDrive Backup Tiger.app"

  BACKUP_DISABLE_ANIMATION=0 \
    BACKUP_PROGRESS_FOREGROUND=1 \
    GDRIVE_BACKUP_ANIMATION_APP="$TEST_HOME/GDrive Backup Tiger.app" \
    FAKE_RCLONE_CONFIG_STARTED_FILE="$config_started_file" \
    FAKE_RCLONE_CONFIG_SLEEP_SECONDS=3 \
    start_backup_async "$TEST_HOME/rclone-copy-started"
  backup_pid="$ASYNC_BACKUP_PID"
  for _ in {1..60}; do
    [[ -e "$config_started_file" ]] && break
    /bin/sleep 0.05
  done
  local open_args=""
  open_args="$(cat "$OPEN_LOG" 2>/dev/null || true)"
  kill -TERM "$backup_pid" 2>/dev/null || true
  wait "$backup_pid" 2>/dev/null || true

  if [[ "$open_args" == *$'--args\n'* && "$open_args" == *"$RUN_STATE_FILE"* ]]; then
    pass "$name"
  else
    fail "$name (progress UI was not opened while preflight was running)"
  fi
}

test_nas_copy_uses_smb_safe_serial_writes() {
  local name="NAS copy disables concurrent and multi-thread destination writes"
  local args_file args
  prepare_test_environment
  args_file="$TEST_HOME/rclone-args"

  FAKE_RCLONE_ARGS_FILE="$args_file" run_backup
  args="$(cat "$args_file" 2>/dev/null || true)"

  if [[ "$args" == *$'--multi-thread-streams\n0\n'* &&
        "$args" == *$'--transfers\n1\n'* ]]; then
    pass "$name"
  else
    fail "$name (NAS safety flags missing)"
  fi
}

test_nas_copy_uses_reversible_dot_bin_codec() {
  local name="NAS copy preserves vetoed .bin directories with a reversible codec"
  local args_file manifest escape_line first_dot_bin_line last_dot_bin_line dot_bin_count
  prepare_test_environment
  args_file="$TEST_HOME/rclone-args"

  FAKE_RCLONE_ARGS_FILE="$args_file" run_backup
  manifest="$(cat "$NAS_MOUNT/backup/.gdrive-name-codec" 2>/dev/null || true)"
  # The literal ${1} is part of rclone's replacement syntax.
  # shellcheck disable=SC2016
  escape_line="$(grep -nFx -- 'all,regex=(?i)^(__gdt0__.*)$/__gdt0__${1}' \
    "$args_file" 2>/dev/null | head -n 1 | cut -d: -f1)"
  first_dot_bin_line="$(grep -nFx -- 'dir,regex=^\.bin$/__gdt0__dotbin_000' \
    "$args_file" 2>/dev/null | head -n 1 | cut -d: -f1)"
  last_dot_bin_line="$(grep -nFx -- 'dir,regex=^\.BIN$/__gdt0__dotbin_111' \
    "$args_file" 2>/dev/null | head -n 1 | cut -d: -f1)"
  dot_bin_count="$(grep -Fc 'dir,regex=^\.' \
    "$args_file" 2>/dev/null || true)"

  if [[ "$escape_line" =~ ^[0-9]+$ && "$first_dot_bin_line" =~ ^[0-9]+$ &&
        "$last_dot_bin_line" =~ ^[0-9]+$ && "$dot_bin_count" == "16" &&
        "$escape_line" -lt "$first_dot_bin_line" &&
        "$first_dot_bin_line" -lt "$last_dot_bin_line" &&
        "$manifest" == *$'protocol=1\n'* &&
        "$manifest" == *$'codec=nas-path-v1\n'* &&
        "$manifest" == *$'prefix=__gdt0__\n'* &&
        "$manifest" == *$'dot_bin_prefix=__gdt0__dotbin_\n'* &&
        "$manifest" == *$'current_layers=1\n'* &&
        "$manifest" == *$'version_layers=2' ]]; then
    pass "$name"
  else
    fail "$name (escape=$escape_line first=$first_dot_bin_line last=$last_dot_bin_line count=$dot_bin_count manifest=${manifest//$'\n'/,})"
  fi
}

test_nas_codec_dry_run_does_not_create_manifest() {
  local name="NAS codec dry-run reports transformed work without writing its manifest"
  local args_file status
  prepare_test_environment
  args_file="$TEST_HOME/rclone-args"

  FAKE_RCLONE_ARGS_FILE="$args_file" run_dry_backup
  status=$?

  if [[ "$status" == "0" &&
        ! -e "$NAS_MOUNT/backup/.gdrive-name-codec" &&
        "$(cat "$args_file" 2>/dev/null || true)" == *$'--dry-run\n'* &&
        "$(cat "$args_file" 2>/dev/null || true)" == \
          *$'all,regex=(?i)^(__gdt0__.*)$/__gdt0__${1}\n'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status manifest=$([[ -e "$NAS_MOUNT/backup/.gdrive-name-codec" ]] && printf yes || printf no))"
  fi
}

test_nas_codec_rejects_unsupported_rclone() {
  local name="NAS codec fails closed when rclone lacks name transforms"
  local status summary
  prepare_test_environment

  FAKE_RCLONE_SUPPORTS_NAME_TRANSFORM=0 run_backup
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"

  if [[ "$status" == "69" &&
        "$summary" == *$'status=failure\n'* &&
        "$summary" == *$'reason=unsupported_rclone\n'* &&
        ! -e "$NAS_MOUNT/backup/.gdrive-name-codec" ]]; then
    pass "$name"
  else
    fail "$name (exit=$status summary=${summary//$'\n'/,})"
  fi
}

test_nas_codec_rejects_malformed_manifest() {
  local name="NAS codec rejects a manifest missing its terminating newline"
  local status summary
  prepare_test_environment
  mkdir -p "$NAS_MOUNT/backup"
  printf '%s' $'protocol=1\ncodec=nas-path-v1\nprefix=__gdt0__\n'\
$'dot_bin_prefix=__gdt0__dotbin_\ncurrent_layers=1\nversion_layers=2' \
    >"$NAS_MOUNT/backup/.gdrive-name-codec"

  run_backup
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"

  if [[ "$status" == "69" &&
        "$summary" == *$'reason=invalid_name_codec\n'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status summary=${summary//$'\n'/,})"
  fi
}

write_valid_nas_codec_manifest() {
  mkdir -p "$NAS_MOUNT/backup"
  printf '%s\n' \
    'protocol=1' \
    'codec=nas-path-v1' \
    'prefix=__gdt0__' \
    'dot_bin_prefix=__gdt0__dotbin_' \
    'current_layers=1' \
    'version_layers=2' \
    >"$NAS_MOUNT/backup/.gdrive-name-codec"
}

test_nas_codec_retries_transient_manifest_read_errors() {
  local name="NAS codec retries transient manifest read errors"
  local calls_file status calls
  prepare_test_environment
  write_valid_nas_codec_manifest
  calls_file="$TEST_HOME/cmp-calls"

  FAKE_CMP_STATUS_SEQUENCE='2,2,0' \
    FAKE_CMP_CALLS_FILE="$calls_file" \
    run_backup
  status=$?
  calls="$(/usr/bin/awk 'END { print NR + 0 }' "$calls_file" 2>/dev/null)"

  if [[ "$status" == "0" && "$calls" == "3" ]]; then
    pass "$name"
  else
    fail "$name (exit=$status calls=$calls)"
  fi
}

test_nas_codec_classifies_persistent_manifest_read_errors() {
  local name="NAS codec distinguishes unreadable manifests from invalid content"
  local calls_file status calls summary manifest_before manifest_after
  prepare_test_environment
  write_valid_nas_codec_manifest
  calls_file="$TEST_HOME/cmp-calls"
  manifest_before="$(/usr/bin/shasum -a 256 \
    "$NAS_MOUNT/backup/.gdrive-name-codec" | /usr/bin/awk '{print $1}')"

  FAKE_CMP_STATUS_SEQUENCE='2,2,2' \
  FAKE_CMP_CALLS_FILE="$calls_file" \
    run_backup
  status=$?
  calls="$(/usr/bin/awk 'END { print NR + 0 }' "$calls_file" 2>/dev/null)"
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"
  manifest_after="$(/usr/bin/shasum -a 256 \
    "$NAS_MOUNT/backup/.gdrive-name-codec" | /usr/bin/awk '{print $1}')"

  if [[ "$status" == "69" &&
        "$calls" == "3" &&
        "$summary" == *$'reason=destination_unreadable\n'* &&
        "$manifest_before" == "$manifest_after" ]]; then
    pass "$name"
  else
    fail "$name (exit=$status calls=$calls summary=${summary//$'\n'/,})"
  fi
}

test_nas_codec_rejects_nonregular_manifest() {
  local name="NAS codec rejects a nonregular manifest"
  local status summary
  prepare_test_environment
  mkdir -p "$NAS_MOUNT/backup/.gdrive-name-codec"

  run_backup
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"

  if [[ "$status" == "69" &&
        "$summary" == *$'reason=invalid_name_codec\n'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status summary=${summary//$'\n'/,})"
  fi
}

test_nas_codec_rejects_ambiguous_legacy_names() {
  local name="NAS codec rejects preexisting .bin and reserved names below copy roots"
  local status summary
  prepare_test_environment
  mkdir -p "$NAS_MOUNT/backup/My Drive/project/.BIN"
  printf '%s\n' legacy >"$NAS_MOUNT/backup/My Drive/__GDT0__legacy-file"

  run_backup
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"

  if [[ "$status" == "69" &&
        "$summary" == *$'reason=name_codec_collision\n'* &&
        ! -e "$NAS_MOUNT/backup/.gdrive-name-codec" ]]; then
    pass "$name"
  else
    fail "$name (exit=$status summary=${summary//$'\n'/,})"
  fi
}

test_nas_codec_keeps_shared_drive_destination_raw() {
  local name="NAS codec permits a reserved-looking raw Shared Drive destination"
  local status
  prepare_test_environment
  mkdir -p "$NAS_MOUNT/backup/Shared Drives/__GDT0__Team (drive-1)"

  run_backup
  status=$?

  if [[ "$status" == "0" &&
        -f "$NAS_MOUNT/backup/.gdrive-name-codec" ]]; then
    pass "$name"
  else
    fail "$name (exit=$status)"
  fi
}

test_permission_failure_is_classified() {
  local name="destination permission failure is classified without persisting a path"
  local summary
  prepare_test_environment

  FAKE_RCLONE_COPY_STATUS=23 \
    FAKE_RCLONE_COPY_OUTPUT='ERROR : redacted: Failed to copy: mkdir redacted: permission denied' \
    run_backup
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"

  if [[ "$summary" == *$'status=failure\n'* &&
        "$summary" == *$'reason=destination_permission_denied\n'* &&
        "$summary" != *'redacted'* ]]; then
    pass "$name"
  else
    fail "$name (summary=${summary//$'\n'/,})"
  fi
}

test_source_permission_failure_stays_generic() {
  local name="source-side access failure is not mislabeled as a destination permission problem"
  local summary
  prepare_test_environment

  FAKE_RCLONE_COPY_STATUS=23 \
    FAKE_RCLONE_COPY_OUTPUT='ERROR : remote: Failed to open source object: access denied' \
    run_backup
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"

  if [[ "$summary" == *$'status=failure\n'* &&
        "$summary" != *$'reason=destination_permission_denied\n'* ]]; then
    pass "$name"
  else
    fail "$name (source failure was mislabeled)"
  fi
}

test_duplicate_source_file_fails_closed() {
  local name="ignored duplicate Drive file cannot be reported as a successful backup"
  local status summary
  prepare_test_environment

  FAKE_RCLONE_COPY_OUTPUT='NOTICE: image.heic: Duplicate object found in source - ignoring' \
    run_backup
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"

  if [[ "$status" == "1" &&
        "$summary" == *$'status=failure\n'* &&
        "$summary" == *$'reason=source_name_collision\n'* &&
        "$summary" != *$'last_success_at='* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status summary=${summary//$'\n'/,})"
  fi
}

test_duplicate_source_directory_fails_closed() {
  local name="ignored duplicate Drive directory cannot be reported as a successful backup"
  local status summary
  prepare_test_environment

  FAKE_RCLONE_COPY_OUTPUT='NOTICE: EventOS-Backups: Duplicate directory found in source - ignoring' \
    run_backup
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"

  if [[ "$status" == "1" &&
        "$summary" == *$'status=failure\n'* &&
        "$summary" == *$'reason=source_name_collision\n'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status summary=${summary//$'\n'/,})"
  fi
}

test_duplicate_source_files_are_archived_by_id() {
  local name="duplicate Drive files are preserved in an ID-addressed collision archive"
  local status summary args_file manifest_count
  prepare_test_environment
  args_file="$TEST_HOME/rclone-args"

  FAKE_RCLONE_ARGS_FILE="$args_file" \
    FAKE_RCLONE_COPY_OUTPUT='NOTICE: Photos/image.heic: Duplicate object found in source - ignoring' \
    FAKE_RCLONE_QUERY_MATCH_1="'root' in parents and name = 'Photos' and mimeType = 'application/vnd.google-apps.folder' and trashed = false" \
    FAKE_RCLONE_QUERY_JSON_1='[
      {"id":"parent-id","name":"Photos","mimeType":"application/vnd.google-apps.folder","parents":["root-id"]}
    ]' \
    FAKE_RCLONE_QUERY_MATCH_4="sharedWithMe = true and name = 'Photos' and mimeType = 'application/vnd.google-apps.folder' and trashed = false" \
    FAKE_RCLONE_QUERY_JSON_4='[
      {"id":"parent-id","name":"Photos","mimeType":"application/vnd.google-apps.folder"}
    ]' \
    FAKE_RCLONE_COLLISION_QUERY_JSON='[
      {"id":"file-id-a","name":"image.heic","mimeType":"image/heic","parents":["parent-id"]},
      {"id":"file-id-b","name":"image.heic","mimeType":"image/heic","parents":["parent-id"]}
    ]' \
    run_backup
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"
  manifest_count="$(find "$NAS_MOUNT/backup/.gdrive-collisions" \
    -name '*.json' -type f 2>/dev/null | wc -l | tr -d ' ')"

  if [[ "$status" == "0" &&
        "$summary" == *$'status=success\n'* &&
        "$manifest_count" == "2" &&
        "$(grep -cFx 'copyid' "$args_file" 2>/dev/null || true)" == "4" &&
        "$(cat "$args_file" 2>/dev/null || true)" == *$'file-id-a\n'* &&
        "$(cat "$args_file" 2>/dev/null || true)" == *$'file-id-b\n'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status manifests=$manifest_count summary=${summary//$'\n'/,})"
  fi
}

test_duplicate_source_directories_are_archived_by_id() {
  local name="duplicate Drive directories are preserved under separate ID roots"
  local status summary args_file root_copy_count
  prepare_test_environment
  args_file="$TEST_HOME/rclone-args"

  FAKE_RCLONE_ARGS_FILE="$args_file" \
    FAKE_RCLONE_COPY_OUTPUT='NOTICE: EventOS-Backups: Duplicate directory found in source - ignoring' \
    FAKE_RCLONE_COLLISION_QUERY_JSON='[
      {"id":"folder-id-a","name":"EventOS-Backups","mimeType":"application/vnd.google-apps.folder","parents":["parent-id"]},
      {"id":"folder-id-b","name":"EventOS-Backups","mimeType":"application/vnd.google-apps.folder","parents":["parent-id"]}
    ]' \
    run_backup
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"
  root_copy_count="$(grep -cFx -- '--drive-root-folder-id' "$args_file" 2>/dev/null || true)"

  if [[ "$status" == "0" &&
        "$summary" == *$'status=success\n'* &&
        "$root_copy_count" == "8" &&
        "$(cat "$args_file" 2>/dev/null || true)" == *$'folder-id-a\n'* &&
        "$(cat "$args_file" 2>/dev/null || true)" == *$'folder-id-b\n'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status root-copies=$root_copy_count summary=${summary//$'\n'/,})"
  fi
}

test_root_duplicate_uses_drive_root_query() {
  local name="root-level Drive duplicates use the provider root query"
  local status summary args_file
  prepare_test_environment
  args_file="$TEST_HOME/rclone-args"

  FAKE_RCLONE_ARGS_FILE="$args_file" \
    FAKE_RCLONE_PARENT_JSON='{"Path":"","Name":"","IsDir":true}' \
    FAKE_RCLONE_COPY_OUTPUT='NOTICE: EventOS-Backups: Duplicate directory found in source - ignoring' \
    FAKE_RCLONE_COLLISION_QUERY_JSON='[
      {"id":"folder-id-a","name":"EventOS-Backups","mimeType":"application/vnd.google-apps.folder","parents":["actual-root-id"]},
      {"id":"folder-id-b","name":"EventOS-Backups","mimeType":"application/vnd.google-apps.folder","parents":["actual-root-id"]}
    ]' \
    run_backup
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"

  if [[ "$status" == "0" &&
        "$summary" == *$'status=success\n'* &&
        "$(grep -cFx -- "'root' in parents and trashed = false" \
          "$args_file" 2>/dev/null || true)" -ge 1 ]]; then
    pass "$name"
  else
    fail "$name (exit=$status summary=${summary//$'\n'/,})"
  fi
}

test_nested_duplicate_resolves_each_parent_by_drive_id() {
  local name="nested Drive duplicate resolves every parent component by ID"
  local status summary args_file args
  prepare_test_environment
  args_file="$TEST_HOME/rclone-args"

  FAKE_RCLONE_ARGS_FILE="$args_file" \
    FAKE_RCLONE_PARENT_JSON='{"Path":"","Name":"","IsDir":true}' \
    FAKE_RCLONE_COPY_OUTPUT='NOTICE: Top/Middle/Photos/image.heic: Duplicate object found in source - ignoring' \
    FAKE_RCLONE_QUERY_MATCH_1="'root' in parents and name = 'Top' and mimeType = 'application/vnd.google-apps.folder' and trashed = false" \
    FAKE_RCLONE_QUERY_JSON_1='[
      {"id":"folder-id-a","name":"Top","mimeType":"application/vnd.google-apps.folder","parents":["root-id"]}
    ]' \
    FAKE_RCLONE_QUERY_MATCH_2="'folder-id-a' in parents and name = 'Middle' and mimeType = 'application/vnd.google-apps.folder' and trashed = false" \
    FAKE_RCLONE_QUERY_JSON_2='[
      {"id":"folder-id-b","name":"Middle","mimeType":"application/vnd.google-apps.folder","parents":["folder-id-a"]}
    ]' \
    FAKE_RCLONE_QUERY_MATCH_3="'folder-id-b' in parents and name = 'Photos' and mimeType = 'application/vnd.google-apps.folder' and trashed = false" \
    FAKE_RCLONE_QUERY_JSON_3='[
      {"id":"folder-id-c","name":"Photos","mimeType":"application/vnd.google-apps.folder","parents":["folder-id-b"]}
    ]' \
    FAKE_RCLONE_QUERY_MATCH_4="sharedWithMe = true and name = 'Top' and mimeType = 'application/vnd.google-apps.folder' and trashed = false" \
    FAKE_RCLONE_QUERY_JSON_4='[
      {"id":"folder-id-a","name":"Top","mimeType":"application/vnd.google-apps.folder"}
    ]' \
    FAKE_RCLONE_COLLISION_QUERY_JSON='[
      {"id":"file-id-a","name":"image.heic","mimeType":"image/heic","parents":["folder-id-c"]},
      {"id":"file-id-b","name":"image.heic","mimeType":"image/heic","parents":["folder-id-c"]}
    ]' \
    run_backup
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"
  args="$(cat "$args_file" 2>/dev/null || true)"

  if [[ "$status" == "0" &&
        "$summary" == *$'status=success\n'* &&
        "$args" == *$'file-id-a\n'* &&
        "$args" == *$'file-id-b\n'* &&
        "$args" == *$'folder-id-c\x27 in parents and trashed = false\n'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status summary=${summary//$'\n'/,})"
  fi
}

test_parent_folder_query_escapes_drive_literals() {
  local name="parent folder query escapes apostrophes and backslashes"
  local status summary args_file args component expected_query folder_json
  prepare_test_environment
  args_file="$TEST_HOME/rclone-args"
  component="Client's\\Files"
  expected_query="sharedWithMe = true and name = 'Client\\'s\\\\Files' and mimeType = 'application/vnd.google-apps.folder' and trashed = false"
  folder_json="$(/usr/bin/jq -cn \
    --arg name "$component" \
    '[{id:"parent-id", name:$name, mimeType:"application/vnd.google-apps.folder"}]')"

  FAKE_RCLONE_ARGS_FILE="$args_file" \
    FAKE_RCLONE_COPY_OUTPUT_SHARED_ONLY=1 \
    FAKE_RCLONE_COPY_OUTPUT="NOTICE: $component/image.heic: Duplicate object found in source - ignoring" \
    FAKE_RCLONE_QUERY_MATCH_1="$expected_query" \
    FAKE_RCLONE_QUERY_JSON_1="$folder_json" \
    FAKE_RCLONE_COLLISION_QUERY_JSON='[
      {"id":"file-id-a","name":"image.heic","mimeType":"image/heic","parents":["parent-id"]},
      {"id":"file-id-b","name":"image.heic","mimeType":"image/heic","parents":["parent-id"]}
    ]' \
    run_backup
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"
  args="$(cat "$args_file" 2>/dev/null || true)"

  if [[ "$status" == "0" &&
        "$summary" == *$'status=success\n'* &&
        "$args" == *"$expected_query"* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status summary=${summary//$'\n'/,})"
  fi
}

test_ambiguous_parent_folder_fails_closed() {
  local name="ambiguous parent folder IDs keep the backup failed"
  local status summary args_file
  prepare_test_environment
  args_file="$TEST_HOME/rclone-args"

  FAKE_RCLONE_ARGS_FILE="$args_file" \
    FAKE_RCLONE_COPY_OUTPUT_SHARED_ONLY=1 \
    FAKE_RCLONE_COPY_OUTPUT='NOTICE: Photos/image.heic: Duplicate object found in source - ignoring' \
    FAKE_RCLONE_QUERY_MATCH_1="sharedWithMe = true and name = 'Photos' and mimeType = 'application/vnd.google-apps.folder' and trashed = false" \
    FAKE_RCLONE_QUERY_JSON_1='[
      {"id":"folder-id-a","name":"Photos","mimeType":"application/vnd.google-apps.folder"},
      {"id":"folder-id-b","name":"Photos","mimeType":"application/vnd.google-apps.folder"}
    ]' \
    run_backup
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"

  if [[ "$status" == "1" &&
        "$summary" == *$'status=failure\n'* &&
        "$summary" == *$'reason=source_name_collision\n'* &&
        "$(grep -cFx 'copyid' "$args_file" 2>/dev/null || true)" == "0" ]]; then
    pass "$name"
  else
    fail "$name (exit=$status summary=${summary//$'\n'/,})"
  fi
}

test_team_drive_parent_uses_the_drive_root_id() {
  local name="nested Shared Drive parent starts from the drive root ID"
  local status summary args_file args
  prepare_test_environment
  args_file="$TEST_HOME/rclone-args"

  FAKE_RCLONE_ARGS_FILE="$args_file" \
    FAKE_JQ_USE_SYSTEM=1 \
    FAKE_RCLONE_DRIVES_JSON='[
      {"id":"team-drive-id","name":"Team"}
    ]' \
    FAKE_RCLONE_COPY_OUTPUT_TEAM_DRIVE_ONLY=1 \
    FAKE_RCLONE_COPY_OUTPUT='NOTICE: Photos/image.heic: Duplicate object found in source - ignoring' \
    FAKE_RCLONE_QUERY_MATCH_1="'team-drive-id' in parents and name = 'Photos' and mimeType = 'application/vnd.google-apps.folder' and trashed = false" \
    FAKE_RCLONE_QUERY_JSON_1='[
      {"id":"parent-id","name":"Photos","mimeType":"application/vnd.google-apps.folder","parents":["team-drive-id"]}
    ]' \
    FAKE_RCLONE_COLLISION_QUERY_JSON='[
      {"id":"file-id-a","name":"image.heic","mimeType":"image/heic","parents":["parent-id"]},
      {"id":"file-id-b","name":"image.heic","mimeType":"image/heic","parents":["parent-id"]}
    ]' \
    run_backup
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"
  args="$(cat "$args_file" 2>/dev/null || true)"

  if [[ "$status" == "0" &&
        "$summary" == *$'status=success\n'* &&
        "$args" == *$'\x27team-drive-id\x27 in parents and name = \x27Photos\x27'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status summary=${summary//$'\n'/,})"
  fi
}

test_team_drive_root_duplicate_uses_the_drive_id() {
  local name="root-level Shared Drive duplicate uses the drive ID"
  local status summary args_file args
  prepare_test_environment
  args_file="$TEST_HOME/rclone-args"

  FAKE_RCLONE_ARGS_FILE="$args_file" \
    FAKE_JQ_USE_SYSTEM=1 \
    FAKE_RCLONE_DRIVES_JSON='[
      {"id":"team-drive-id","name":"Team"}
    ]' \
    FAKE_RCLONE_COPY_OUTPUT_TEAM_DRIVE_ONLY=1 \
    FAKE_RCLONE_COPY_OUTPUT='NOTICE: image.heic: Duplicate object found in source - ignoring' \
    FAKE_RCLONE_COLLISION_QUERY_JSON='[
      {"id":"file-id-a","name":"image.heic","mimeType":"image/heic","parents":["team-drive-id"]},
      {"id":"file-id-b","name":"image.heic","mimeType":"image/heic","parents":["team-drive-id"]}
    ]' \
    run_backup
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"
  args="$(cat "$args_file" 2>/dev/null || true)"

  if [[ "$status" == "0" &&
        "$summary" == *$'status=success\n'* &&
        "$args" == *$'\x27team-drive-id\x27 in parents and trashed = false\n'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status summary=${summary//$'\n'/,})"
  fi
}

test_collision_archive_failure_keeps_backup_failed() {
  local name="a failed ID archive cannot convert a duplicate source into success"
  local status summary
  prepare_test_environment

  FAKE_RCLONE_COPY_OUTPUT='NOTICE: image.heic: Duplicate object found in source - ignoring' \
    FAKE_RCLONE_COLLISION_QUERY_JSON='[
      {"id":"file-id-a","name":"image.heic","mimeType":"image/heic","parents":["parent-id"]},
      {"id":"file-id-b","name":"image.heic","mimeType":"image/heic","parents":["parent-id"]}
    ]' \
    FAKE_RCLONE_ARCHIVE_STATUS=23 \
    run_backup
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"

  if [[ "$status" == "1" &&
        "$summary" == *$'status=failure\n'* &&
        "$summary" == *$'reason=source_name_collision\n'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status summary=${summary//$'\n'/,})"
  fi
}

test_mixed_collision_notices_cannot_be_partially_archived() {
  local name="every detected Drive collision must be represented in the ID archive"
  local status summary
  prepare_test_environment

  FAKE_RCLONE_COPY_OUTPUT=$'NOTICE: image.heic: Duplicate object found in source - ignoring\nNOTICE: other: duplicate filename after case/unicode normalization' \
    FAKE_RCLONE_COLLISION_QUERY_JSON='[
      {"id":"file-id-a","name":"image.heic","mimeType":"image/heic","parents":["parent-id"]},
      {"id":"file-id-b","name":"image.heic","mimeType":"image/heic","parents":["parent-id"]}
    ]' \
    run_backup
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"

  if [[ "$status" == "1" &&
        "$summary" == *$'status=failure\n'* &&
        "$summary" == *$'reason=source_name_collision\n'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status summary=${summary//$'\n'/,})"
  fi
}

test_unparsed_exact_collision_cannot_hide_behind_valid_group() {
  local name="an unparseable duplicate notice keeps the whole backup failed"
  local status summary
  prepare_test_environment

  FAKE_RCLONE_COPY_OUTPUT=$'NOTICE: image.heic: Duplicate object found in source - ignoring\nunstructured: Duplicate object found in source - ignoring' \
    FAKE_RCLONE_COLLISION_QUERY_JSON='[
      {"id":"file-id-a","name":"image.heic","mimeType":"image/heic","parents":["parent-id"]},
      {"id":"file-id-b","name":"image.heic","mimeType":"image/heic","parents":["parent-id"]}
    ]' \
    run_backup
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"

  if [[ "$status" == "1" &&
        "$summary" == *$'status=failure\n'* &&
        "$summary" == *$'reason=source_name_collision\n'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status summary=${summary//$'\n'/,})"
  fi
}

test_folder_archive_requires_a_materialized_root() {
  local name="a failed archive-root creation cannot become a successful backup"
  local status summary
  prepare_test_environment

  cat >"$FAKE_BIN/mkdir" <<'SH'
#!/bin/bash
for directory in "$@"; do
  case "$directory" in
    "${FAKE_NAS_MOUNT}/backup/.gdrive-collisions/"*/objects/*/root) exit 73 ;;
  esac
done
exec /bin/mkdir "$@"
SH
  chmod +x "$FAKE_BIN/mkdir"

  FAKE_RCLONE_COPY_OUTPUT='NOTICE: EventOS-Backups: Duplicate directory found in source - ignoring' \
    FAKE_RCLONE_COLLISION_QUERY_JSON='[
      {"id":"folder-id-a","name":"EventOS-Backups","mimeType":"application/vnd.google-apps.folder","parents":["parent-id"]},
      {"id":"folder-id-b","name":"EventOS-Backups","mimeType":"application/vnd.google-apps.folder","parents":["parent-id"]}
    ]' \
    FAKE_RCLONE_ARCHIVE_CREATE_FOLDER=0 \
    run_backup
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"

  if [[ "$status" == "1" &&
        "$summary" == *$'status=failure\n'* &&
        "$summary" == *$'reason=destination_permission_denied\n'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status summary=${summary//$'\n'/,})"
  fi
}

test_empty_duplicate_folders_preserve_separate_archive_roots() {
  local name="empty duplicate folders retain separate materialized ID roots"
  local status summary root_count manifest_count
  prepare_test_environment

  FAKE_RCLONE_COPY_OUTPUT='NOTICE: Empty: Duplicate directory found in source - ignoring' \
    FAKE_RCLONE_COLLISION_QUERY_JSON='[
      {"id":"folder-id-a","name":"Empty","mimeType":"application/vnd.google-apps.folder","parents":["parent-id"]},
      {"id":"folder-id-b","name":"Empty","mimeType":"application/vnd.google-apps.folder","parents":["parent-id"]}
    ]' \
    FAKE_RCLONE_ARCHIVE_CREATE_FOLDER=0 \
    run_backup
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"
  root_count="$(find "$NAS_MOUNT/backup/.gdrive-collisions" -type d \
    -path '*/objects/*/root' 2>/dev/null | wc -l | tr -d '[:space:]')"
  manifest_count="$(find "$NAS_MOUNT/backup/.gdrive-collisions" -type f \
    -path '*/groups/*.json' 2>/dev/null | wc -l | tr -d '[:space:]')"
  if [[ "$status" == "0" && "$summary" == *$'status=success\n'* &&
        "$root_count" == "4" && "$manifest_count" == "2" ]]; then
    pass "$name"
  else
    fail "$name (exit=$status roots=$root_count manifests=$manifest_count)"
  fi
}

test_folder_archive_still_rejects_missing_contents() {
  local name="an existing archive root cannot hide missing folder contents"
  local status summary manifest_count
  prepare_test_environment

  FAKE_RCLONE_COPY_OUTPUT='NOTICE: Contents: Duplicate directory found in source - ignoring' \
    FAKE_RCLONE_COLLISION_QUERY_JSON='[
      {"id":"folder-id-a","name":"Contents","mimeType":"application/vnd.google-apps.folder","parents":["parent-id"]},
      {"id":"folder-id-b","name":"Contents","mimeType":"application/vnd.google-apps.folder","parents":["parent-id"]}
    ]' \
    FAKE_RCLONE_ARCHIVE_VERIFY_REPORT='+ missing.txt' \
    run_backup
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"
  manifest_count="$(find "$NAS_MOUNT/backup/.gdrive-collisions" -type f \
    -path '*/groups/*.json' 2>/dev/null | wc -l | tr -d '[:space:]')"
  if [[ "$status" == "1" && "$summary" == *$'reason=source_name_collision\n'* &&
        "$manifest_count" == "0" ]]; then
    pass "$name"
  else
    fail "$name (exit=$status manifests=$manifest_count)"
  fi
}

test_folder_archive_rejects_unsafe_root_before_writing() {
  local kind scope label object directory status args_file
  for kind in symlink file; do
    prepare_test_environment
    object="$(printf 'drive-object-id\037folder-id-a' | /usr/bin/shasum -a 256)"; object="${object%% *}"
    for label in 'My Drive' 'Shared with me'; do
      scope="$(printf '%s' "$label" | /usr/bin/shasum -a 256)"; scope="${scope%% *}"
      directory="$NAS_MOUNT/backup/.gdrive-collisions/$scope/objects/$object"
      mkdir -p "$directory" "$TEST_HOME/outside"
      if [[ "$kind" == symlink ]]; then
        ln -s "$TEST_HOME/outside" "$directory/root"
      else
        : >"$directory/root"
      fi
    done
    args_file="$TEST_HOME/rclone-args"
    FAKE_RCLONE_ARGS_FILE="$args_file" \
      FAKE_RCLONE_COPY_OUTPUT='NOTICE: Empty: Duplicate directory found in source - ignoring' \
      FAKE_RCLONE_COLLISION_QUERY_JSON='[
        {"id":"folder-id-a","name":"Empty","mimeType":"application/vnd.google-apps.folder","parents":["parent-id"]},
        {"id":"folder-id-b","name":"Empty","mimeType":"application/vnd.google-apps.folder","parents":["parent-id"]}
      ]' run_backup
    status=$?
    if [[ "$status" == 1 ]] && ! grep -qFx -- '--drive-root-folder-id' "$args_file"; then
      pass "unsafe folder root is rejected before ID copy: $kind"
    else
      fail "unsafe folder root reached ID copy: $kind (exit=$status)"
    fi
  done
}

test_empty_folder_dry_run_does_not_create_archive_roots() {
  local name="dry-run of empty duplicate folders does not create archive roots"
  local status
  prepare_test_environment

  FAKE_RCLONE_COPY_OUTPUT='NOTICE: Empty: Duplicate directory found in source - ignoring' \
    FAKE_RCLONE_COLLISION_QUERY_JSON='[
      {"id":"folder-id-a","name":"Empty","mimeType":"application/vnd.google-apps.folder","parents":["parent-id"]},
      {"id":"folder-id-b","name":"Empty","mimeType":"application/vnd.google-apps.folder","parents":["parent-id"]}
    ]' \
    FAKE_RCLONE_ARCHIVE_CREATE_FOLDER=0 \
    run_backup_with_mode --dry-run
  status=$?
  if [[ "$status" == "0" && ! -e "$NAS_MOUNT/backup/.gdrive-collisions" ]]; then
    pass "$name"
  else
    fail "$name (exit=$status)"
  fi
}

test_google_workspace_duplicates_use_exported_names() {
  local name="Google Workspace duplicate IDs are matched to their exported file name"
  local status summary args_file
  prepare_test_environment
  args_file="$TEST_HOME/rclone-args"

  FAKE_RCLONE_ARGS_FILE="$args_file" \
    FAKE_RCLONE_COPY_OUTPUT='NOTICE: Docs/Plan.docx: Duplicate object found in source - ignoring' \
    FAKE_RCLONE_ARCHIVE_FILE_NAME='Plan.docx' \
    FAKE_RCLONE_QUERY_MATCH_1="'root' in parents and name = 'Docs' and mimeType = 'application/vnd.google-apps.folder' and trashed = false" \
    FAKE_RCLONE_QUERY_JSON_1='[
      {"id":"parent-id","name":"Docs","mimeType":"application/vnd.google-apps.folder","parents":["root-id"]}
    ]' \
    FAKE_RCLONE_QUERY_MATCH_4="sharedWithMe = true and name = 'Docs' and mimeType = 'application/vnd.google-apps.folder' and trashed = false" \
    FAKE_RCLONE_QUERY_JSON_4='[
      {"id":"parent-id","name":"Docs","mimeType":"application/vnd.google-apps.folder"}
    ]' \
    FAKE_RCLONE_COLLISION_QUERY_JSON='[
      {"id":"doc-id-a","name":"Plan","mimeType":"application/vnd.google-apps.document","parents":["parent-id"]},
      {"id":"doc-id-b","name":"Plan","mimeType":"application/vnd.google-apps.document","parents":["parent-id"]},
      {"id":"file-id-c","name":"Plan.docx","mimeType":"application/vnd.openxmlformats-officedocument.wordprocessingml.document","parents":["parent-id"]}
    ]' \
    run_backup
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"

  if [[ "$status" == "0" &&
        "$summary" == *$'status=success\n'* &&
        "$(grep -cFx 'copyid' "$args_file" 2>/dev/null || true)" == "6" &&
        "$(cat "$args_file" 2>/dev/null || true)" == *$'doc-id-a\n'* &&
        "$(cat "$args_file" 2>/dev/null || true)" == *$'doc-id-b\n'* &&
        "$(cat "$args_file" 2>/dev/null || true)" == *$'file-id-c\n'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status summary=${summary//$'\n'/,})"
  fi
}

test_incomplete_drive_query_fails_closed() {
  local name="an incomplete Drive API search cannot publish a complete archive"
  local status summary
  prepare_test_environment

  FAKE_RCLONE_COPY_OUTPUT='NOTICE: image.heic: Duplicate object found in source - ignoring' \
    FAKE_RCLONE_QUERY_STDERR='NOTICE: search result INCOMPLETE' \
    FAKE_RCLONE_COLLISION_QUERY_JSON='[
      {"id":"file-id-a","name":"image.heic","mimeType":"image/heic","parents":["parent-id"]},
      {"id":"file-id-b","name":"image.heic","mimeType":"image/heic","parents":["parent-id"]}
    ]' \
    run_backup
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"

  if [[ "$status" == "1" &&
        "$summary" == *$'status=failure\n'* &&
        "$summary" == *$'reason=source_name_collision\n'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status summary=${summary//$'\n'/,})"
  fi
}

test_shared_with_me_ids_drop_the_virtual_root_flag() {
  local name="Shared-with-me duplicate IDs are copied outside the virtual root view"
  local status summary
  prepare_test_environment

  FAKE_RCLONE_COPY_OUTPUT_SHARED_ONLY=1 \
    FAKE_RCLONE_REJECT_SHARED_FOR_ID=1 \
    FAKE_RCLONE_PARENT_STATUS=88 \
    FAKE_RCLONE_ARCHIVE_FILE_NAME='shared.heic' \
    FAKE_RCLONE_COPY_OUTPUT='NOTICE: shared.heic: Duplicate object found in source - ignoring' \
    FAKE_RCLONE_COLLISION_QUERY_JSON='[
      {"id":"shared-id-a","name":"shared.heic","mimeType":"image/heic"},
      {"id":"shared-id-b","name":"shared.heic","mimeType":"image/heic"}
    ]' \
    run_backup
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"

  if [[ "$status" == "0" && "$summary" == *$'status=success\n'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status summary=${summary//$'\n'/,})"
  fi
}

test_normal_notice_remains_successful() {
  local name="ordinary rclone notices do not become source collision failures"
  local status summary
  prepare_test_environment

  FAKE_RCLONE_COPY_OUTPUT='NOTICE: normal informational message' run_backup
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"

  if [[ "$status" == "0" &&
        "$summary" == *$'status=success\n'* &&
        "$summary" != *$'reason=source_name_collision\n'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status summary=${summary//$'\n'/,})"
  fi
}

test_destination_permission_error_has_priority_over_duplicate_notice() {
  local name="destination permission failure keeps priority over a duplicate notice"
  local status summary
  prepare_test_environment

  FAKE_RCLONE_COPY_STATUS=23 \
    FAKE_RCLONE_COPY_OUTPUT=$'NOTICE: duplicate: Duplicate object found in source - ignoring\nERROR : target: Failed to copy: permission denied' \
    run_backup
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"

  if [[ "$status" == "1" &&
        "$summary" == *$'reason=destination_permission_denied\n'* &&
        "$summary" != *$'reason=source_name_collision\n'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status summary=${summary//$'\n'/,})"
  fi
}

test_lost_nas_mount_is_classified_and_stops_followup_copies() {
  local name="lost NAS mount is classified and stops follow-up copies"
  local status summary args_file copy_count
  prepare_test_environment
  args_file="$TEST_HOME/rclone-args"

  FAKE_RCLONE_ARGS_FILE="$args_file" \
    FAKE_RCLONE_DISCONNECT_MOUNT="$NAS_MOUNT" \
    FAKE_RCLONE_COPY_STATUS=23 \
    run_backup
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"
  copy_count="$(/usr/bin/grep -c '^copy$' "$args_file" 2>/dev/null || true)"

  if [[ "$status" == "1" && "$summary" == *$'status=failure\n'* &&
        "$summary" == *$'reason=nas_connection_lost\n'* &&
        "$copy_count" == "1" ]]; then
    pass "$name"
  else
    fail "$name (exit=$status copies=$copy_count summary=${summary//$'\n'/,})"
  fi
}

test_nas_mount_waits_until_it_is_writable() {
  local name="a newly visible NAS mount is allowed to finish becoming writable"
  local status summary ready_pid
  prepare_test_environment
  chmod 500 "$NAS_MOUNT"

  (
    /bin/sleep 1
    chmod 700 "$NAS_MOUNT"
  ) &
  ready_pid=$!
  GDRIVE_BACKUP_NAS_READY_TIMEOUT_SECONDS=008 run_backup
  status=$?
  wait "$ready_pid"
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"

  if [[ "$status" == "0" && "$summary" == *$'status=success\n'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status summary=${summary//$'\n'/,})"
  fi
}

test_nas_auto_mount_transitions_to_a_writable_share() {
  local name="automatic NAS mount waits for the new verified writable share"
  local status summary visible_file
  prepare_test_environment
  visible_file="$TEST_HOME/nas-mounted"

  FAKE_NAS_MOUNT_VISIBLE=0 \
    FAKE_NAS_MOUNT_VISIBLE_FILE="$visible_file" \
    FAKE_MOUNT_HELPER_VISIBLE_FILE="$visible_file" \
    FAKE_MOUNT_HELPER_MAKE_WRITABLE=1 \
    GDRIVE_BACKUP_NAS_URL="smb://backup.test/share" \
    GDRIVE_BACKUP_NAS_READY_TIMEOUT_SECONDS=2 \
    run_backup
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"

  if [[ "$status" == "0" && -e "$visible_file" &&
        "$summary" == *$'status=success\n'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status summary=${summary//$'\n'/,})"
  fi
}

test_nas_privacy_denial_names_the_macos_grant() {
  local name="a macOS privacy denial on the NAS names the missing grant before any copy"
  local status summary log_text fake_ls
  prepare_test_environment
  fake_ls="$TEST_HOME/fake-ls-denied"
  # The fake script must expand its own arguments when it runs.
  # shellcheck disable=SC2016
  printf '%s\n' '#!/bin/bash' \
    'printf "ls: %s: Operation not permitted\n" "${@: -1}" >&2' 'exit 1' >"$fake_ls"
  chmod +x "$fake_ls"

  GDRIVE_BACKUP_LS_BIN="$fake_ls" run_backup
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"
  log_text="$(cat "$TEST_HOME/Library/Logs/gdrive-backup.log" 2>/dev/null || true)"

  if [[ "$status" != "0" && ! -e "$TEST_HOME/rclone-started" &&
        "$summary" == *$'reason=macos_privacy_permission_missing\n'* &&
        "$log_text" == *"Voller Festplattenzugriff"* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status summary=${summary//$'\n'/,})"
  fi
}

test_nas_privacy_probe_timeout_is_retryable() {
  local name="a NAS listing blocked by an open macOS dialog is bounded and retryable"
  local status summary fake_ls started finished
  prepare_test_environment
  fake_ls="$TEST_HOME/fake-ls-blocked"
  printf '%s\n' '#!/bin/bash' 'exec /bin/sleep 30' >"$fake_ls"
  chmod +x "$fake_ls"
  started="$(date +%s)"

  GDRIVE_BACKUP_LS_BIN="$fake_ls" \
    GDRIVE_BACKUP_NAS_PRIVACY_PROBE_TIMEOUT_SECONDS=1 \
    run_backup
  status=$?
  finished="$(date +%s)"
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"

  if [[ "$status" != "0" && ! -e "$TEST_HOME/rclone-started" &&
        $(( finished - started )) -lt 20 &&
        "$summary" == *$'reason=destination_unreadable\n'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status seconds=$(( finished - started )) summary=${summary//$'\n'/,})"
  fi
}

test_vanished_nas_mount_stops_a_running_copy() {
  local name="a NAS mount that vanishes during a copy ends the copy instead of failing every file"
  local status summary log_text started finished hidden
  prepare_test_environment
  hidden="$TEST_HOME/nas-hidden"
  started="$(date +%s)"

  FAKE_NAS_MOUNT_HIDDEN_FILE="$hidden" \
    FAKE_RCLONE_HIDE_MOUNT_FILE="$hidden" \
    GDRIVE_BACKUP_NAS_WATCH_SECONDS=1 \
    GDRIVE_BACKUP_NAS_RECHECK_SECONDS=0 \
    run_backup
  status=$?
  finished="$(date +%s)"
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"
  log_text="$(cat "$TEST_HOME/Library/Logs/gdrive-backup.log" 2>/dev/null || true)"

  if [[ "$status" != "0" && $(( finished - started )) -lt 30 &&
        "$summary" == *$'reason=nas_connection_lost\n'* &&
        "$log_text" == *"die laufende Kopie wird beendet"* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status seconds=$(( finished - started )) summary=${summary//$'\n'/,})"
  fi
}

test_nas_auto_mount_not_ready_is_retryable() {
  local name="automatic NAS mount timeout publishes the retryable readiness reason"
  local status summary visible_file
  prepare_test_environment
  visible_file="$TEST_HOME/nas-mounted"
  chmod 500 "$NAS_MOUNT"

  FAKE_NAS_MOUNT_VISIBLE=0 \
    FAKE_NAS_MOUNT_VISIBLE_FILE="$visible_file" \
    FAKE_MOUNT_HELPER_VISIBLE_FILE="$visible_file" \
    GDRIVE_BACKUP_NAS_URL="smb://backup.test/share" \
    GDRIVE_BACKUP_NAS_READY_TIMEOUT_SECONDS=1 \
    run_backup
  status=$?
  chmod 700 "$NAS_MOUNT"
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"

  if [[ "$status" == "69" &&
        "$summary" == *$'reason=nas_mount_not_ready\n'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status summary=${summary//$'\n'/,})"
  fi
}

test_hung_nas_mount_command_is_bounded() {
  local name="a hung NAS mount command becomes a terminal retryable failure"
  local status summary started finished
  prepare_test_environment
  started="$(date +%s)"

  FAKE_NAS_MOUNT_VISIBLE=0 \
    FAKE_MOUNT_HELPER_SLEEP_SECONDS=4 \
    GDRIVE_BACKUP_NAS_URL="smb://backup.test/share" \
    GDRIVE_BACKUP_NAS_MOUNT_TIMEOUT_SECONDS=1 \
    GDRIVE_BACKUP_NAS_READY_TIMEOUT_SECONDS=0 \
    run_backup
  status=$?
  finished="$(date +%s)"
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"

  # macOS date reports whole seconds, so a roughly two-second bounded path can
  # span three wall-clock ticks under CI load. It must still beat the helper's
  # unbounded four-second completion.
  if [[ "$status" == "69" && $((finished - started)) -lt 4 &&
        "$summary" == *$'status=failure\n'* &&
        "$summary" == *$'reason=nas_mount_unavailable\n'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status elapsed=$((finished - started)) summary=${summary//$'\n'/,})"
  fi
}

test_unavailable_nas_mount_has_retryable_reason() {
  local name="an unavailable configured NAS mount publishes a retryable reason"
  local status summary
  prepare_test_environment

  FAKE_NAS_MOUNT_VISIBLE=0 \
    GDRIVE_BACKUP_NAS_READY_TIMEOUT_SECONDS=0 \
    run_backup
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"

  if [[ "$status" == "69" &&
        "$summary" == *$'status=failure\n'* &&
        "$summary" == *$'reason=nas_mount_unavailable\n'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status summary=${summary//$'\n'/,})"
  fi
}

test_permanent_nas_permission_failure_is_not_retryable() {
  local name="an already mounted permanent permission failure is classified separately"
  local status summary
  prepare_test_environment
  chmod 500 "$NAS_MOUNT"

  GDRIVE_BACKUP_NAS_READY_TIMEOUT_SECONDS=1 run_backup
  status=$?
  chmod 700 "$NAS_MOUNT"
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"

  if [[ "$status" == "69" &&
        "$summary" == *$'status=failure\n'* &&
        "$summary" == *$'reason=destination_permission_denied\n'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status summary=${summary//$'\n'/,})"
  fi
}

test_retry_metadata_is_published() {
  local name="an automatic retry remains identifiable in durable status"
  local status summary
  prepare_test_environment

  run_backup \
    "GDRIVE_BACKUP_TRIGGER=schedule-retry" \
    "GDRIVE_BACKUP_RETRY_ORIGIN_STARTED_AT=1785261605" \
    "GDRIVE_BACKUP_RETRY_ATTEMPT=1"
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"

  if [[ "$status" == "0" &&
        "$summary" == *$'trigger=schedule-retry\n'* &&
        "$summary" == *$'retry_origin_started_at=1785261605\n'* &&
        "$summary" == *$'retry_attempt=1\n'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status summary=${summary//$'\n'/,})"
  fi
}

test_confirmation_uses_injected_open_command() {
  local name="confirmation uses the testable open command"
  # This asserts literal shell source, so expansion would be a test bug.
  # shellcheck disable=SC2016
  if /usr/bin/grep -Fq 'if "$OPEN_BIN" -W -n "$ANIMATION_APP"' "$BACKUP_SCRIPT"; then
    pass "$name"
  else
    fail "$name"
  fi
}

test_external_confirmation_counts_stores_without_an_out_of_range_probe() {
  local name="external confirmation counts physical stores without probing past the array"
  # macOS 15 can emit non-empty output for an out-of-range numeric key path.
  # Cardinality is therefore the portable way to distinguish one disk from a set.
  # The second grep deliberately matches literal shell source.
  # shellcheck disable=SC2016
  if ! /usr/bin/grep -Fq 'APFSPhysicalStores.1.APFSPhysicalStore' "$PLATFORM_SCRIPT" &&
     /usr/bin/grep -Fq 'plist_data_value "$volume_plist" APFSPhysicalStores' "$PLATFORM_SCRIPT"; then
    pass "$name"
  else
    fail "$name"
  fi
}

test_external_confirmation_identifies_physical_disk() {
  local name="external confirmation names the physical disk without technical identifiers"
  local app detail_file diskutil_log expected mount uuid status detail
  prepare_test_environment
  app="$TEST_HOME/GDrive Backup Tiger.app"
  detail_file="$TEST_HOME/confirm-detail"
  diskutil_log="$TEST_HOME/diskutil-calls"
  mount="$TEST_HOME/GoogleDrive-Backup 2"
  uuid="11111111-2222-3333-4444-555555555555"
  mkdir -p "$app" "$mount"
  expected=$'Festplatte: TOSHIBA_4TB · 4 TB · USB\nVolume: GoogleDrive-Backup'

  GDRIVE_BACKUP_CONFIRM=1 \
    FAKE_CONFIRM_DECISION=yes \
    FAKE_CONFIRM_DETAIL_LOG="$detail_file" \
    FAKE_DISKUTIL_MODE=external-confirmation \
    FAKE_DISKUTIL_LOG="$diskutil_log" \
    FAKE_APFS_UUID="$uuid" \
    FAKE_APFS_MOUNT="$mount" \
    run_backup \
      "GDRIVE_BACKUP_TARGET=apfs" \
      "GDRIVE_BACKUP_VOLUME=$mount" \
      "GDRIVE_BACKUP_VOLUME_NAME=GoogleDrive-Backup" \
      "GDRIVE_BACKUP_VOLUME_UUID=$uuid" \
      "GDRIVE_BACKUP_DEST_ROOT=$mount" \
      "GDRIVE_BACKUP_LANG=de" \
      "GDRIVE_BACKUP_ANIMATION_APP=$app"
  status=$?
  detail="$(cat "$detail_file" 2>/dev/null || true)"

  if [[ "$status" == "0" && "$detail" == "$expected" &&
        "$detail" != *"$mount"* && "$detail" != *'/Volumes/'* &&
        "$detail" != *'GoogleDrive-Backup 2'* && "$detail" != *'/dev/disk'* &&
        ! "$detail" =~ disk[0-9]+ &&
        ! "$detail" =~ [[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12} &&
        "$detail" != *'SECRET-SERIAL'* ]] &&
     ! /usr/bin/grep -Fxq 'disk88' "$diskutil_log"; then
    pass "$name"
  else
    fail "$name (exit=$status detail=${detail//$'\n'/,})"
  fi
}

test_external_confirmation_identifies_multiple_physical_stores_as_a_set() {
  local name="external confirmation identifies a real multi-disk store as a storage set"
  local app detail_file expected mount uuid status detail
  prepare_test_environment
  app="$TEST_HOME/GDrive Backup Tiger.app"
  detail_file="$TEST_HOME/confirm-detail"
  mount="$TEST_HOME/GoogleDrive-Backup 2"
  uuid="11111111-2222-3333-4444-555555555555"
  mkdir -p "$app" "$mount"
  expected=$'Festplatte: Speicherverbund · 4 TB · USB\nVolume: GoogleDrive-Backup'

  GDRIVE_BACKUP_CONFIRM=1 \
    FAKE_CONFIRM_DECISION=yes \
    FAKE_CONFIRM_DETAIL_LOG="$detail_file" \
    FAKE_DISKUTIL_MODE=external-confirmation \
    FAKE_SECOND_PHYSICAL_STORE=disk87s1 \
    FAKE_APFS_UUID="$uuid" \
    FAKE_APFS_MOUNT="$mount" \
    run_backup \
      "GDRIVE_BACKUP_TARGET=apfs" \
      "GDRIVE_BACKUP_VOLUME=$mount" \
      "GDRIVE_BACKUP_VOLUME_NAME=GoogleDrive-Backup" \
      "GDRIVE_BACKUP_VOLUME_UUID=$uuid" \
      "GDRIVE_BACKUP_DEST_ROOT=$mount" \
      "GDRIVE_BACKUP_LANG=de" \
      "GDRIVE_BACKUP_ANIMATION_APP=$app"
  status=$?
  detail="$(cat "$detail_file" 2>/dev/null || true)"

  if [[ "$status" == "0" && "$detail" == "$expected" &&
        ! "$detail" =~ disk[0-9]+ && "$detail" != *'SECRET-SERIAL'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status detail=${detail//$'\n'/,})"
  fi
}

test_external_confirmation_has_private_fallback() {
  local name="external confirmation fallback stays useful and hides mount suffixes"
  local app detail_file expected mount uuid status detail
  prepare_test_environment
  app="$TEST_HOME/GDrive Backup Tiger.app"
  detail_file="$TEST_HOME/confirm-detail"
  mount="$TEST_HOME/GoogleDrive-Backup 2"
  uuid="11111111-2222-3333-4444-555555555555"
  mkdir -p "$app" "$mount"
  expected=$'Festplatte: Externe Festplatte · 4 TB · USB\nVolume: GoogleDrive-Backup'

  GDRIVE_BACKUP_CONFIRM=1 \
    FAKE_CONFIRM_DECISION=yes \
    FAKE_CONFIRM_DETAIL_LOG="$detail_file" \
    FAKE_DISKUTIL_MODE=external-confirmation \
    FAKE_DISKUTIL_PHYSICAL_STATUS=1 \
    FAKE_IOREG_STATUS=1 \
    FAKE_APFS_UUID="$uuid" \
    FAKE_APFS_MOUNT="$mount" \
    run_backup \
      "GDRIVE_BACKUP_TARGET=apfs" \
      "GDRIVE_BACKUP_VOLUME=$mount" \
      "GDRIVE_BACKUP_VOLUME_NAME=GoogleDrive-Backup" \
      "GDRIVE_BACKUP_VOLUME_UUID=$uuid" \
      "GDRIVE_BACKUP_DEST_ROOT=$mount" \
      "GDRIVE_BACKUP_LANG=de" \
      "GDRIVE_BACKUP_ANIMATION_APP=$app"
  status=$?
  detail="$(cat "$detail_file" 2>/dev/null || true)"

  if [[ "$status" == "0" && "$detail" == "$expected" &&
        "$detail" != *"$mount"* && "$detail" != *'/Volumes/'* &&
        "$detail" != *'GoogleDrive-Backup 2'* && "$detail" != *'/dev/disk'* &&
        ! "$detail" =~ disk[0-9]+ &&
        ! "$detail" =~ [[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12} &&
        "$detail" != *'SECRET-SERIAL'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status detail=${detail//$'\n'/,})"
  fi
}

test_external_confirmation_uses_nonempty_metadata_fallbacks() {
  local name="external confirmation skips empty disk metadata and uses whole-disk fallbacks"
  local app detail_file expected mount uuid status detail
  prepare_test_environment
  app="$TEST_HOME/GDrive Backup Tiger.app"
  detail_file="$TEST_HOME/confirm-detail"
  mount="$TEST_HOME/GoogleDrive-Backup 2"
  uuid="11111111-2222-3333-4444-555555555555"
  mkdir -p "$app" "$mount"
  expected=$'Festplatte: TOSHIBA EXTERNAL_USB · 4 TB · USB\nVolume: GoogleDrive-Backup'

  GDRIVE_BACKUP_CONFIRM=1 \
    FAKE_CONFIRM_DECISION=yes \
    FAKE_CONFIRM_DETAIL_LOG="$detail_file" \
    FAKE_DISKUTIL_MODE=external-confirmation \
    FAKE_DISKUTIL_EMPTY_PRIMARY_FIELDS=1 \
    FAKE_APFS_UUID="$uuid" \
    FAKE_APFS_MOUNT="$mount" \
    run_backup \
      "GDRIVE_BACKUP_TARGET=apfs" \
      "GDRIVE_BACKUP_VOLUME=$mount" \
      "GDRIVE_BACKUP_VOLUME_NAME=GoogleDrive-Backup" \
      "GDRIVE_BACKUP_VOLUME_UUID=$uuid" \
      "GDRIVE_BACKUP_DEST_ROOT=$mount" \
      "GDRIVE_BACKUP_LANG=de" \
      "GDRIVE_BACKUP_ANIMATION_APP=$app"
  status=$?
  detail="$(cat "$detail_file" 2>/dev/null || true)"

  if [[ "$status" == "0" && "$detail" == "$expected" &&
        "$detail" != *'SECRET-SERIAL'* && ! "$detail" =~ disk[0-9]+ ]]; then
    pass "$name"
  else
    fail "$name (exit=$status detail=${detail//$'\n'/,})"
  fi
}

test_external_confirmation_rejects_bidi_disk_metadata() {
  local name="external confirmation rejects bidirectional disk labels"
  local app detail_file expected mount uuid status detail
  prepare_test_environment
  app="$TEST_HOME/GDrive Backup Tiger.app"
  detail_file="$TEST_HOME/confirm-detail"
  mount="$TEST_HOME/GoogleDrive-Backup 2"
  uuid="11111111-2222-3333-4444-555555555555"
  mkdir -p "$app" "$mount"
  expected=$'Festplatte: TOSHIBA EXTERNAL_USB · 4 TB · USB\nVolume: GoogleDrive-Backup'

  GDRIVE_BACKUP_CONFIRM=1 \
    FAKE_CONFIRM_DECISION=yes \
    FAKE_CONFIRM_DETAIL_LOG="$detail_file" \
    FAKE_DISKUTIL_MODE=external-confirmation \
    FAKE_DISKUTIL_BIDI_NAME=1 \
    FAKE_APFS_UUID="$uuid" \
    FAKE_APFS_MOUNT="$mount" \
    run_backup \
      "GDRIVE_BACKUP_TARGET=apfs" \
      "GDRIVE_BACKUP_VOLUME=$mount" \
      "GDRIVE_BACKUP_VOLUME_NAME=GoogleDrive-Backup" \
      "GDRIVE_BACKUP_VOLUME_UUID=$uuid" \
      "GDRIVE_BACKUP_DEST_ROOT=$mount" \
      "GDRIVE_BACKUP_LANG=de" \
      "GDRIVE_BACKUP_ANIMATION_APP=$app"
  status=$?
  detail="$(cat "$detail_file" 2>/dev/null || true)"

  if [[ "$status" == "0" && "$detail" == "$expected" ]]; then
    pass "$name"
  else
    fail "$name (exit=$status detail=${detail//$'\n'/,})"
  fi
}

test_external_confirmation_rejects_invalid_physical_store_id() {
  local name="external confirmation never queries an invalid physical-store identifier"
  local app detail_file diskutil_log expected mount uuid status detail invalid_id
  prepare_test_environment
  app="$TEST_HOME/GDrive Backup Tiger.app"
  detail_file="$TEST_HOME/confirm-detail"
  diskutil_log="$TEST_HOME/diskutil-calls"
  mount="$TEST_HOME/GoogleDrive-Backup 2"
  uuid="11111111-2222-3333-4444-555555555555"
  invalid_id='disk88s1-invalid'
  mkdir -p "$app" "$mount"
  expected=$'Festplatte: Externe Festplatte · 4 TB · USB\nVolume: GoogleDrive-Backup'

  GDRIVE_BACKUP_CONFIRM=1 \
    FAKE_CONFIRM_DECISION=yes \
    FAKE_CONFIRM_DETAIL_LOG="$detail_file" \
    FAKE_DISKUTIL_MODE=external-confirmation \
    FAKE_DISKUTIL_LOG="$diskutil_log" \
    FAKE_PHYSICAL_STORE="$invalid_id" \
    FAKE_APFS_UUID="$uuid" \
    FAKE_APFS_MOUNT="$mount" \
    run_backup \
      "GDRIVE_BACKUP_TARGET=apfs" \
      "GDRIVE_BACKUP_VOLUME=$mount" \
      "GDRIVE_BACKUP_VOLUME_NAME=GoogleDrive-Backup" \
      "GDRIVE_BACKUP_VOLUME_UUID=$uuid" \
      "GDRIVE_BACKUP_DEST_ROOT=$mount" \
      "GDRIVE_BACKUP_LANG=de" \
      "GDRIVE_BACKUP_ANIMATION_APP=$app"
  status=$?
  detail="$(cat "$detail_file" 2>/dev/null || true)"

  if [[ "$status" == "0" && "$detail" == "$expected" ]] &&
     ! /usr/bin/grep -Fxq "$invalid_id" "$diskutil_log"; then
    pass "$name"
  else
    fail "$name (exit=$status detail=${detail//$'\n'/,})"
  fi
}

test_external_confirmation_ignores_invalid_capacity() {
  local name="external confirmation replaces an invalid physical-store capacity"
  local app detail_file expected mount uuid status detail
  prepare_test_environment
  app="$TEST_HOME/GDrive Backup Tiger.app"
  detail_file="$TEST_HOME/confirm-detail"
  mount="$TEST_HOME/GoogleDrive-Backup 2"
  uuid="11111111-2222-3333-4444-555555555555"
  mkdir -p "$app" "$mount"
  expected=$'Festplatte: TOSHIBA_4TB · 4 TB · USB\nVolume: GoogleDrive-Backup'

  GDRIVE_BACKUP_CONFIRM=1 \
    FAKE_CONFIRM_DECISION=yes \
    FAKE_CONFIRM_DETAIL_LOG="$detail_file" \
    FAKE_DISKUTIL_MODE=external-confirmation \
    FAKE_DISKUTIL_INVALID_SIZE=1 \
    FAKE_APFS_UUID="$uuid" \
    FAKE_APFS_MOUNT="$mount" \
    run_backup \
      "GDRIVE_BACKUP_TARGET=apfs" \
      "GDRIVE_BACKUP_VOLUME=$mount" \
      "GDRIVE_BACKUP_VOLUME_NAME=GoogleDrive-Backup" \
      "GDRIVE_BACKUP_VOLUME_UUID=$uuid" \
      "GDRIVE_BACKUP_DEST_ROOT=$mount" \
      "GDRIVE_BACKUP_LANG=de" \
      "GDRIVE_BACKUP_ANIMATION_APP=$app"
  status=$?
  detail="$(cat "$detail_file" 2>/dev/null || true)"

  if [[ "$status" == "0" && "$detail" == "$expected" ]]; then
    pass "$name"
  else
    fail "$name (exit=$status detail=${detail//$'\n'/,})"
  fi
}

test_external_confirmation_waits_for_realistic_registry_lookup() {
  local name="external confirmation tolerates a realistic delayed media lookup"
  local app detail_file expected mount uuid status detail
  prepare_test_environment
  app="$TEST_HOME/GDrive Backup Tiger.app"
  detail_file="$TEST_HOME/confirm-detail"
  mount="$TEST_HOME/GoogleDrive-Backup 2"
  uuid="11111111-2222-3333-4444-555555555555"
  mkdir -p "$app" "$mount"
  expected=$'Festplatte: TOSHIBA_4TB · 4 TB · USB\nVolume: GoogleDrive-Backup'

  GDRIVE_BACKUP_CONFIRM=1 \
    FAKE_CONFIRM_DECISION=yes \
    FAKE_CONFIRM_DETAIL_LOG="$detail_file" \
    FAKE_DISKUTIL_MODE=external-confirmation \
    FAKE_DISKUTIL_PHYSICAL_STATUS=1 \
    FAKE_IOREG_SLEEP_SECONDS=2 \
    FAKE_APFS_UUID="$uuid" \
    FAKE_APFS_MOUNT="$mount" \
    run_backup \
      "GDRIVE_BACKUP_TARGET=apfs" \
      "GDRIVE_BACKUP_VOLUME=$mount" \
      "GDRIVE_BACKUP_VOLUME_NAME=GoogleDrive-Backup" \
      "GDRIVE_BACKUP_VOLUME_UUID=$uuid" \
      "GDRIVE_BACKUP_DEST_ROOT=$mount" \
      "GDRIVE_BACKUP_LANG=de" \
      "GDRIVE_BACKUP_ANIMATION_APP=$app"
  status=$?
  detail="$(cat "$detail_file" 2>/dev/null || true)"

  if [[ "$status" == "0" && "$detail" == "$expected" ]]; then
    pass "$name"
  else
    fail "$name (exit=$status detail=${detail//$'\n'/,})"
  fi
}

test_declined_confirmation_is_skipped() {
  local name="declined destination confirmation is skipped without replacing backup history"
  local before after state status
  prepare_test_environment
  mkdir -p "$TEST_HOME/GDrive Backup Tiger.app"
  before=$'protocol=1\nstatus=success\npid=1\nstarted_at=1783790000\nfinished_at=1783790100\nexit_code=0\ntrigger=schedule\ntarget=nas\ndestination=/Volumes/Archive'
  printf '%s' "$before" >"$SUMMARY_STATE_FILE"
  chmod 600 "$SUMMARY_STATE_FILE"

  GDRIVE_BACKUP_CONFIRM=1 \
    FAKE_CONFIRM_DECISION=no \
    run_backup \
      "GDRIVE_BACKUP_ANIMATION_APP=$TEST_HOME/GDrive Backup Tiger.app" \
      "GDRIVE_BACKUP_OPEN_BIN=$FAKE_BIN/open"
  status=$?
  state="$(cat "$RUN_STATE_FILE" 2>/dev/null || true)"
  after="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"

  if [[ "$status" == "0" &&
        "$state" == *$'status=skipped\n'* &&
        "$state" == *$'reason=user_declined\n'* &&
        "$state" == *'exit_code=0'* &&
        "$after" == "$before" ]]; then
    pass "$name"
  else
    fail "$name (exit=$status state=${state//$'\n'/,})"
  fi
}

test_failed_ui_launch_cleans_internal_state() {
  local name="failed UI launch cleans its internal state"
  local status sentinel_path progress_path state_path
  prepare_test_environment

  mkdir -p "$TEST_HOME/GDrive Backup Tiger.app"
  BACKUP_DISABLE_ANIMATION=0 \
    GDRIVE_BACKUP_RUN_STATE_FILE='' \
    FAKE_OPEN_STATUS=1 \
    run_backup \
      "GDRIVE_BACKUP_ANIMATION_APP=$TEST_HOME/GDrive Backup Tiger.app" \
      "GDRIVE_BACKUP_OPEN_BIN=$FAKE_BIN/open" \
      "BACKUP_PROGRESS_FOREGROUND=1"
  status=$?
  sentinel_path="$(sed -n '4p' "$OPEN_LOG" 2>/dev/null || true)"
  progress_path="$(sed -n '5p' "$OPEN_LOG" 2>/dev/null || true)"
  state_path="$(sed -n '6p' "$OPEN_LOG" 2>/dev/null || true)"

  if [[ "$status" == "0" && -n "$state_path" &&
        ! -e "$sentinel_path" && ! -e "$progress_path" && ! -e "$state_path" ]]; then
    pass "$name"
  else
    fail "$name (exit=$status sentinel=$sentinel_path progress=$progress_path state=$state_path)"
  fi
}

test_success_persists_private_summary() {
  local name="successful backup persists a private durable summary"
  local summary mode
  prepare_test_environment

  run_backup
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"
  mode="$(/usr/bin/stat -f '%Lp' "$SUMMARY_STATE_FILE" 2>/dev/null || true)"

  if [[ "$summary" == *$'protocol=1\n'* &&
        "$summary" == *$'status=success\n'* &&
        "$summary" =~ (^|$'\n')started_at=[0-9]+($|$'\n') &&
        "$summary" =~ (^|$'\n')finished_at=[0-9]+($|$'\n') &&
        "$summary" == *$'exit_code=0\n'* &&
        "$summary" == *$'trigger=manual\n'* &&
        "$summary" == *$'target=nas\n'* &&
        "$summary" == *"destination=$NAS_MOUNT/backup"* &&
        "$mode" == "600" ]]; then
    pass "$name"
  else
    fail "$name (mode=$mode summary=${summary//$'\n'/,})"
  fi
}

test_failure_persists_failed_summary() {
  local name="failed backup persists failure without claiming success"
  local status summary
  prepare_test_environment

  FAKE_RCLONE_COPY_STATUS=23 run_backup
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"

  if [[ "$status" == "1" && "$summary" == *$'status=failure\n'* &&
        "$summary" == *$'exit_code=1\n'* && "$summary" != *$'status=success\n'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status summary=${summary//$'\n'/,})"
  fi
}

test_later_failure_preserves_last_success_marker() {
  local name="a later failed attempt preserves the durable success marker"
  local success_marker status summary
  prepare_test_environment

  run_backup
  success_marker="$(/usr/bin/awk -F= '$1 == "last_success_at" { print $2 }' \
    "$SUMMARY_STATE_FILE")"
  FAKE_RCLONE_COPY_STATUS=23 run_backup
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"

  if [[ "$status" == "1" && "$success_marker" =~ ^[0-9]+$ &&
        "$summary" == *$'status=failure\n'* &&
        "$summary" == *"last_success_at=$success_marker"* &&
        "$summary" == *$'last_success_target=nas\n'* &&
        "$summary" == *"last_success_destination=$NAS_MOUNT/backup"* &&
        "$summary" == *"last_success_volume=${NAS_MOUNT##*/}"* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status marker=$success_marker summary=${summary//$'\n'/,})"
  fi
}

test_legacy_success_destination_survives_failure() {
  local summary status
  prepare_test_environment
  printf 'protocol=1\nstatus=success\npid=123\nstarted_at=100\nfinished_at=200\nexit_code=0\nlast_success_at=200\ntarget=apfs\ndestination=/Volumes/Old=Disk/backup\n' >"$SUMMARY_STATE_FILE"
  FAKE_RCLONE_COPY_STATUS=23 run_backup
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE")"
  if [[ "$status" == "1" && "$summary" == *$'last_success_at=200\n'* &&
        "$summary" == *$'last_success_target=apfs\n'* &&
        "$summary" == *$'last_success_destination=/Volumes/Old=Disk/backup\n'* &&
        "$summary" == *$'last_success_volume=Old=Disk\n'* ]]; then
    pass "legacy successful destination survives a later failed run with equals signs intact"
  else
    fail "legacy success destination was lost or mixed with current target"
  fi
}

test_success_override_does_not_claim_selected_volume() {
  prepare_test_environment
  local alternate="$TEST_HOME/Other/backup" status summary
  mkdir -p "$alternate"
  run_backup GDRIVE_BACKUP_DEST_ROOT="$alternate"
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE")"
  if [[ "$status" == "0" && "$summary" == *"last_success_destination=$alternate"* &&
        "$summary" != *'last_success_volume='* ]]; then
    pass "an override outside the selected volume records no guessed medium"
  else
    fail "an override claims the selected volume despite writing elsewhere"
  fi
}

test_new_success_replaces_previous_destination() {
  prepare_test_environment
  printf 'protocol=1\nstatus=failure\nlast_success_at=200\nlast_success_target=apfs\nlast_success_destination=/Volumes/Old/backup\nlast_success_volume=Old\n' >"$SUMMARY_STATE_FILE"
  run_backup
  local status=$? summary
  summary="$(cat "$SUMMARY_STATE_FILE")"
  if [[ "$status" == "0" && "$summary" == *$'last_success_target=nas\n'* &&
        "$summary" == *"last_success_destination=$NAS_MOUNT/backup"* &&
        "$summary" == *"last_success_volume=${NAS_MOUNT##*/}"* &&
        "$summary" != *$'last_success_at=200\n'* ]]; then
    pass "a new success replaces the previous timestamp and medium together"
  else
    fail "new success did not replace the complete record"
  fi
}

test_concurrent_start_preserves_previous_summary() {
  local name="concurrent skipped start preserves the actual backup summary"
  local before after
  prepare_test_environment
  before=$'protocol=1\nstatus=running\npid=1\nstarted_at=1783790000\ntrigger=schedule\ntarget=nas\ndestination=/Volumes/Archive'
  printf '%s' "$before" >"$SUMMARY_STATE_FILE"
  chmod 600 "$SUMMARY_STATE_FILE"

  FAKE_FLOCK_STATUS=1 run_backup
  after="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"

  if [[ "$after" == "$before" ]]; then
    pass "$name"
  else
    fail "$name (summary was overwritten: ${after//$'\n'/,})"
  fi
}

test_lock_loser_preserves_owner_progress() {
  local name="lock loser cannot invalidate the owner's live progress"
  local progress before after status
  prepare_test_environment
  progress="$TEST_HOME/profiles/default/current-progress.status"
  mkdir -p "${progress%/*}"
  before=$'protocol=1\nprofile_id=default\npid=4242\nstarted_at=1783790000\ntrigger=schedule\nlabel=My Drive\nphase=1/2\npercent=42\ndetail=42 MiB / 100 MiB, 1 MiB/s, ETA 58s\nupdated_at=1783790010'
  printf '%s\n' "$before" >"$progress"
  chmod 600 "$progress"

  FAKE_FLOCK_STATUS=1 run_backup \
    "GDRIVE_BACKUP_PROFILE_ID=default" \
    "GDRIVE_BACKUP_PROGRESS_STATE_FILE=$progress"
  status=$?
  after="$(cat "$progress" 2>/dev/null || true)"

  if [[ "$status" == "0" && "$after" == "$before" ]]; then
    pass "$name"
  else
    fail "$name (exit=$status progress=${after//$'\n'/,})"
  fi
}

test_terminal_summary_publish_failure_keeps_progress_live() {
  local name="failed terminal summary publication cannot finish durable progress"
  local progress summary status warning_count log_file
  prepare_test_environment
  enable_state_publish_order_spy
  progress="$TEST_HOME/profiles/default/current-progress.status"
  mkdir -p "${progress%/*}"

  GDRIVE_BACKUP_FAIL_TERMINAL_SUMMARY=1 run_backup \
    "GDRIVE_BACKUP_PROFILE_ID=default" \
    "GDRIVE_BACKUP_PROGRESS_STATE_FILE=$progress"
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"
  progress="$(cat "$progress" 2>/dev/null || true)"
  log_file="$TEST_HOME/Library/Logs/gdrive-backup.log"
  warning_count="$(grep -Fc 'Backup-Status konnte nicht sicher aktualisiert werden.' \
    "$log_file" 2>/dev/null || true)"

  if [[ "$status" == "0" && "$summary" == *$'status=running\n'* &&
        "$summary" != *$'finished_at='* &&
        "$progress" != *$'status=finished\n'* &&
        "$warning_count" == "1" ]]; then
    pass "$name"
  else
    fail "$name (exit=$status warning_count=$warning_count summary=${summary//$'\n'/,} progress=${progress//$'\n'/,})"
  fi
}

test_unknown_total_publishes_check_activity() {
  local name="unknown-total aggregate publishes private check activity"
  local progress epoch_file content status backup_pid attempt
  prepare_test_environment
  progress="$TEST_HOME/profiles/default/current-progress.status"
  epoch_file="$TEST_HOME/epoch"
  mkdir -p "${progress%/*}"
  printf '1783790000\n' >"$epoch_file"

  FAKE_RCLONE_COPY_OUTPUT=$'Transferred: 12.000 MiB / 0 B, -, 1.500 MiB/s, ETA -\nChecks: 43129 / 43129, 100%, Listed 103256' \
  FAKE_RCLONE_ADVANCE_EPOCH_TO=1783790121 \
  FAKE_RCLONE_SLEEP_SECONDS=2 \
    run_backup \
      "GDRIVE_BACKUP_PROFILE_ID=default" \
      "GDRIVE_BACKUP_PROGRESS_STATE_FILE=$progress" \
      "FAKE_DATE_EPOCH_FILE=$epoch_file" &
  backup_pid=$!

  content=""
  for attempt in {1..200}; do
    : "$attempt"
    content="$(cat "$progress" 2>/dev/null || true)"
    [[ "$content" == *$'checked=43129\n'* &&
       "$content" == *$'listed=103256\n'* &&
       "$content" == *'updated_at=1783790121'* ]] && break
    /bin/sleep 0.02
  done
  kill -TERM "$backup_pid" 2>/dev/null || true
  wait "$backup_pid" 2>/dev/null
  status=$?

  if [[ "$status" == "143" &&
        "$content" == *$'label=My Drive\n'* &&
        "$content" == *$'phase=1/2\n'* &&
        "$content" == *$'checked=43129\n'* &&
        "$content" == *$'listed=103256\n'* &&
        "$content" == *$'transferred=12.000 MiB\n'* &&
        "$content" == *$'speed=1.500 MiB/s\n'* &&
        "$content" == *'updated_at=1783790121'* &&
        "$content" != *$'percent='* &&
        "$content" != *$'detail='* &&
        "$content" != *'secret'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status progress=${content//$'\n'/,})"
  fi
}

test_off_total_refreshes_indeterminate_progress() {
  local name="canonical off-total aggregate publishes dash-percent check activity"
  local progress epoch_file content status backup_pid attempt
  prepare_test_environment
  progress="$TEST_HOME/profiles/default/current-progress.status"
  epoch_file="$TEST_HOME/epoch"
  mkdir -p "${progress%/*}"
  printf '1783790200\n' >"$epoch_file"

  FAKE_RCLONE_COPY_OUTPUT=$'Transferred: 0 B / off, -, 0 B/s, ETA -\nChecks: 0 / 0, -, Listed 1' \
  FAKE_RCLONE_ADVANCE_EPOCH_TO=1783790321 \
  FAKE_RCLONE_SLEEP_SECONDS=2 \
    run_backup \
      "GDRIVE_BACKUP_PROFILE_ID=default" \
      "GDRIVE_BACKUP_PROGRESS_STATE_FILE=$progress" \
      "FAKE_DATE_EPOCH_FILE=$epoch_file" &
  backup_pid=$!

  content=""
  for attempt in {1..200}; do
    : "$attempt"
    content="$(cat "$progress" 2>/dev/null || true)"
    [[ "$content" == *$'checked=0\n'* &&
       "$content" == *$'listed=1\n'* &&
       "$content" == *'updated_at=1783790321'* ]] && break
    /bin/sleep 0.02
  done
  kill -TERM "$backup_pid" 2>/dev/null || true
  wait "$backup_pid" 2>/dev/null
  status=$?

  if [[ "$status" == "143" &&
        "$content" == *$'label=My Drive\n'* &&
        "$content" == *$'phase=1/2\n'* &&
        "$content" == *$'checked=0\n'* &&
        "$content" == *$'listed=1\n'* &&
        "$content" == *$'transferred=0 B\n'* &&
        "$content" == *$'speed=0 B/s\n'* &&
        "$content" == *'updated_at=1783790321'* &&
        "$content" != *$'percent='* &&
        "$content" != *$'detail='* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status progress=${content//$'\n'/,})"
  fi
}

test_rich_progress_failure_falls_back_to_phase_only() {
  local name="failed rich publication replaces prior percent with phase-only progress"
  local progress count_file content status backup_pid attempt count
  prepare_test_environment
  enable_state_publish_order_spy
  progress="$TEST_HOME/profiles/default/current-progress.status"
  count_file="$TEST_HOME/rich-progress-count"
  mkdir -p "${progress%/*}"

  GDRIVE_BACKUP_FAIL_RICH_PROGRESS_AT=2 \
  GDRIVE_BACKUP_RICH_PROGRESS_COUNT_FILE="$count_file" \
  FAKE_RCLONE_COPY_OUTPUT=$'Transferred: 250.000 MiB / 1.000 GiB, 25%, 10.000 MiB/s, ETA 1m\nTransferred: 630.000 MiB / 1.000 GiB, 63%, 10.000 MiB/s, ETA 37s' \
  FAKE_RCLONE_SLEEP_SECONDS=5 \
    run_backup \
      "GDRIVE_BACKUP_PROFILE_ID=default" \
      "GDRIVE_BACKUP_PROGRESS_STATE_FILE=$progress" &
  backup_pid=$!

  content=""
  count="0"
  for attempt in {1..200}; do
    : "$attempt"
    count="$(cat "$count_file" 2>/dev/null || printf '0')"
    content="$(cat "$progress" 2>/dev/null || true)"
    if [[ "$count" == "2" && "$content" != *$'percent='* &&
          "$content" != *$'detail='* ]]; then
      break
    fi
    /bin/sleep 0.02
  done
  kill -TERM "$backup_pid" 2>/dev/null || true
  wait "$backup_pid" 2>/dev/null
  status=$?

  if [[ "$status" == "143" && "$count" == "2" &&
        "$content" == *$'label=My Drive\n'* &&
        "$content" == *$'phase=1/2\n'* &&
        "$content" != *$'percent='* &&
        "$content" != *$'detail='* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status rich_attempts=$count progress=${content//$'\n'/,})"
  fi
}

test_foreground_copy_starts_indeterminate() {
  local name="foreground copy phase starts indeterminate without invented zero"
  local content snapshot_file mode_file mode status
  prepare_test_environment
  enable_state_publish_order_spy
  mkdir -p "$TEST_HOME/GDrive Backup Tiger.app"
  snapshot_file="$TEST_HOME/copy-start-progress.status"
  mode_file="$TEST_HOME/copy-start-progress.mode"

  BACKUP_DISABLE_ANIMATION=0 \
  GDRIVE_BACKUP_FOREGROUND_PROGRESS_SNAPSHOT_FILE="$snapshot_file" \
  GDRIVE_BACKUP_FOREGROUND_PROGRESS_MODE_FILE="$mode_file" \
    run_backup \
      "GDRIVE_BACKUP_ANIMATION_APP=$TEST_HOME/GDrive Backup Tiger.app" \
      "GDRIVE_BACKUP_OPEN_BIN=$FAKE_BIN/open" \
      "BACKUP_PROGRESS_FOREGROUND=1"
  status=$?
  content="$(cat "$snapshot_file" 2>/dev/null || true)"
  mode="$(cat "$mode_file" 2>/dev/null || true)"

  if [[ "$status" == "0" &&
        "$content" == $'label=My Drive\nphase=1/2' && "$mode" == "600" ]]; then
    pass "$name"
  else
    fail "$name (exit=$status mode=$mode progress=${content//$'\n'/,})"
  fi
}

test_headless_retry_publishes_private_progress() {
  local name="headless retry publishes private aggregate progress"
  local progress content summary mode status backup_pid attempt
  local summary_pid summary_started progress_updated
  prepare_test_environment
  progress="$TEST_HOME/profiles/default/current-progress.status"
  mkdir -p "${progress%/*}"

  FAKE_RCLONE_COPY_OUTPUT=$'INFO : secret-file.pdf: Copied\nTransferred: 1.200 GiB / 1.900 GiB, 63%, 12.400 MiB/s, ETA 58s' \
  FAKE_RCLONE_SLEEP_SECONDS=3 \
    run_backup \
      "GDRIVE_BACKUP_TRIGGER=schedule-retry" \
      "GDRIVE_BACKUP_RETRY_ORIGIN_STARTED_AT=1785520805" \
      "GDRIVE_BACKUP_RETRY_ATTEMPT=1" \
      "GDRIVE_BACKUP_PROFILE_ID=default" \
      "GDRIVE_BACKUP_PROGRESS_STATE_FILE=$progress" \
      "BACKUP_PROGRESS_FOREGROUND=0" &
  backup_pid=$!

  for attempt in {1..100}; do
    : "$attempt"
    content="$(cat "$progress" 2>/dev/null || true)"
    [[ "$content" == *$'percent=63\n'* ]] && break
    sleep 0.05
  done
  mode="$(stat -f '%Lp' "$progress" 2>/dev/null || true)"
  content="$(cat "$progress" 2>/dev/null || true)"
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"
  summary_pid="$(awk -F= '$1 == "pid" {print $2}' "$SUMMARY_STATE_FILE")"
  summary_started="$(awk -F= '$1 == "started_at" {print $2}' "$SUMMARY_STATE_FILE")"
  progress_updated="$(awk -F= '$1 == "updated_at" {print $2}' "$progress")"
  wait "$backup_pid"
  status=$?

  if [[ "$status" == "0" && "$mode" == "600" &&
        "$content" == *$'protocol=1\n'* &&
        "$content" == *$'profile_id=default\n'* &&
        "$summary" == *$'status=running\n'* &&
        "$summary_pid" =~ ^[0-9]+$ &&
        "$summary_started" =~ ^[0-9]+$ &&
        "$content" == *"pid=$summary_pid"* &&
        "$content" == *"started_at=$summary_started"* &&
        "$content" == *$'trigger=schedule-retry\n'* &&
        "$content" == *$'retry_attempt=1\n'* &&
        "$content" == *$'label=My Drive\n'* &&
        "$content" == *$'phase=1/2\n'* &&
        "$content" == *$'percent=63\n'* &&
        "$content" == *$'detail=1.200 GiB / 1.900 GiB, 12.400 MiB/s, ETA 58s\n'* &&
        "$progress_updated" =~ ^[0-9]+$ &&
        "$content" != *'secret-file.pdf'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status mode=$mode progress=${content//$'\n'/,})"
  fi
}

test_headless_retry_never_opens_progress_window() {
  local name="headless retry telemetry remains passive"
  local progress status open_args terminal
  prepare_test_environment
  progress="$TEST_HOME/profiles/default/current-progress.status"
  mkdir -p "${progress%/*}" "$TEST_HOME/GDrive Backup Tiger.app"

  BACKUP_DISABLE_ANIMATION=0 \
    run_backup \
      "GDRIVE_BACKUP_TRIGGER=schedule-retry" \
      "GDRIVE_BACKUP_RETRY_ORIGIN_STARTED_AT=1785520805" \
      "GDRIVE_BACKUP_RETRY_ATTEMPT=1" \
      "GDRIVE_BACKUP_PROFILE_ID=default" \
      "GDRIVE_BACKUP_PROGRESS_STATE_FILE=$progress" \
      "GDRIVE_BACKUP_ANIMATION_APP=$TEST_HOME/GDrive Backup Tiger.app" \
      "GDRIVE_BACKUP_OPEN_BIN=$FAKE_BIN/open" \
      "BACKUP_PROGRESS_FOREGROUND=0"
  status=$?
  open_args="$(cat "$OPEN_LOG" 2>/dev/null || true)"
  terminal="$(cat "$progress" 2>/dev/null || true)"

  if [[ "$status" == "0" && -z "$open_args" &&
        "$terminal" == *$'status=finished\n'* &&
        "$terminal" != *$'percent='* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status open=${open_args//$'\n'/,} progress=${terminal//$'\n'/,})"
  fi
}

test_terminal_outcomes_invalidate_durable_progress() {
  local name="terminal summaries invalidate durable progress"
  local progress status success_summary success_progress
  local failure_summary failure_progress success_order failure_order
  local order_log success_ok=0

  prepare_test_environment
  enable_state_publish_order_spy
  order_log="$TEST_HOME/state-publish-order.log"
  progress="$TEST_HOME/profiles/default/current-progress.status"
  mkdir -p "${progress%/*}"
  run_backup \
    "GDRIVE_BACKUP_PROFILE_ID=default" \
    "GDRIVE_BACKUP_STATE_PUBLISH_TEST_LOG=$order_log" \
    "GDRIVE_BACKUP_PROGRESS_STATE_FILE=$progress"
  status=$?
  success_summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"
  success_progress="$(cat "$progress" 2>/dev/null || true)"
  success_order="$(last_terminal_publish_order "$order_log")"
  if [[ "$status" == "0" &&
        "$success_summary" == *$'status=success\n'* &&
        "$success_summary" == *$'exit_code=0\n'* &&
        "$success_progress" == *$'status=finished\n'* &&
        "$success_progress" != *$'percent='* &&
        "$success_order" == "last-run.status,current-progress.status" ]]; then
    success_ok=1
  fi

  prepare_test_environment
  enable_state_publish_order_spy
  order_log="$TEST_HOME/state-publish-order.log"
  progress="$TEST_HOME/profiles/default/current-progress.status"
  mkdir -p "${progress%/*}"
  FAKE_RCLONE_COPY_STATUS=23 run_backup \
    "GDRIVE_BACKUP_PROFILE_ID=default" \
    "GDRIVE_BACKUP_STATE_PUBLISH_TEST_LOG=$order_log" \
    "GDRIVE_BACKUP_PROGRESS_STATE_FILE=$progress"
  status=$?
  failure_summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"
  failure_progress="$(cat "$progress" 2>/dev/null || true)"
  failure_order="$(last_terminal_publish_order "$order_log")"

  if [[ "$success_ok" == "1" && "$status" == "1" &&
        "$failure_summary" == *$'status=failure\n'* &&
        "$failure_summary" == *$'exit_code=1\n'* &&
        "$failure_progress" == *$'status=finished\n'* &&
        "$failure_progress" != *$'percent='* &&
        "$failure_order" == "last-run.status,current-progress.status" ]]; then
    pass "$name"
  else
    fail "$name (success=${success_summary//$'\n'/,}; failure=${failure_summary//$'\n'/,}; progress=${failure_progress//$'\n'/,})"
  fi
}

# Named cases allow focused regression runs without invoking the slower fixtures.
if (( $# > 0 )); then
  for selected_test in "$@"; do
    if [[ "$selected_test" != test_* ]] || ! declare -F "$selected_test" >/dev/null; then
      printf 'Unknown test: %s\n' "$selected_test" >&2
      exit 64
    fi
    "$selected_test"
  done
  (( failures == 0 ))
  exit $?
fi

test_mount_consent_controls_foreground_progress
test_failed_backup_publishes_failure
test_successful_backup_publishes_success
test_animation_receives_run_state_file
test_manual_progress_requests_foreground_activation
test_automatic_backup_does_not_open_progress_ui
test_visible_manual_confirmation_requests_foreground
test_early_configuration_error_publishes_failure
test_existing_backup_is_skipped_not_successful
test_perl_lock_replaces_missing_flock
test_run_history_lists_each_finished_run
test_run_history_keeps_the_newest_lines_and_skips_dry_runs
test_init_history_rebuilds_only_a_missing_history
test_state_is_versioned_and_identifies_the_process
test_active_backup_publishes_running_summary
test_locked_backup_publishes_running_before_remote_checks
test_locked_backup_opens_progress_before_remote_checks
test_nas_copy_uses_smb_safe_serial_writes
test_nas_copy_uses_reversible_dot_bin_codec
test_nas_codec_dry_run_does_not_create_manifest
test_nas_codec_rejects_unsupported_rclone
test_nas_codec_rejects_malformed_manifest
test_nas_codec_retries_transient_manifest_read_errors
test_nas_codec_classifies_persistent_manifest_read_errors
test_nas_codec_rejects_nonregular_manifest
test_nas_codec_rejects_ambiguous_legacy_names
test_nas_codec_keeps_shared_drive_destination_raw
test_permission_failure_is_classified
test_source_permission_failure_stays_generic
test_duplicate_source_file_fails_closed
test_duplicate_source_directory_fails_closed
test_duplicate_source_files_are_archived_by_id
test_duplicate_source_directories_are_archived_by_id
test_root_duplicate_uses_drive_root_query
test_nested_duplicate_resolves_each_parent_by_drive_id
test_parent_folder_query_escapes_drive_literals
test_ambiguous_parent_folder_fails_closed
test_team_drive_parent_uses_the_drive_root_id
test_team_drive_root_duplicate_uses_the_drive_id
test_collision_archive_failure_keeps_backup_failed
test_mixed_collision_notices_cannot_be_partially_archived
test_unparsed_exact_collision_cannot_hide_behind_valid_group
test_folder_archive_requires_a_materialized_root
test_empty_duplicate_folders_preserve_separate_archive_roots
test_folder_archive_still_rejects_missing_contents
test_folder_archive_rejects_unsafe_root_before_writing
test_empty_folder_dry_run_does_not_create_archive_roots
test_google_workspace_duplicates_use_exported_names
test_incomplete_drive_query_fails_closed
test_shared_with_me_ids_drop_the_virtual_root_flag
test_normal_notice_remains_successful
test_destination_permission_error_has_priority_over_duplicate_notice
test_lost_nas_mount_is_classified_and_stops_followup_copies
test_nas_mount_waits_until_it_is_writable
test_nas_auto_mount_transitions_to_a_writable_share
test_nas_auto_mount_not_ready_is_retryable
test_nas_privacy_denial_names_the_macos_grant
test_nas_privacy_probe_timeout_is_retryable
test_vanished_nas_mount_stops_a_running_copy
test_hung_nas_mount_command_is_bounded
test_unavailable_nas_mount_has_retryable_reason
test_permanent_nas_permission_failure_is_not_retryable
test_retry_metadata_is_published
test_confirmation_uses_injected_open_command
test_external_confirmation_counts_stores_without_an_out_of_range_probe
test_external_confirmation_identifies_physical_disk
test_external_confirmation_identifies_multiple_physical_stores_as_a_set
test_external_confirmation_has_private_fallback
test_external_confirmation_uses_nonempty_metadata_fallbacks
test_external_confirmation_rejects_bidi_disk_metadata
test_external_confirmation_rejects_invalid_physical_store_id
test_external_confirmation_ignores_invalid_capacity
test_external_confirmation_waits_for_realistic_registry_lookup
test_declined_confirmation_is_skipped
test_term_signal_publishes_cancellation
test_failed_ui_launch_cleans_internal_state
test_success_persists_private_summary
test_failure_persists_failed_summary
test_later_failure_preserves_last_success_marker
test_legacy_success_destination_survives_failure
test_new_success_replaces_previous_destination
test_success_override_does_not_claim_selected_volume
test_concurrent_start_preserves_previous_summary
test_lock_loser_preserves_owner_progress
test_terminal_summary_publish_failure_keeps_progress_live
test_unknown_total_publishes_check_activity
test_off_total_refreshes_indeterminate_progress
test_rich_progress_failure_falls_back_to_phase_only
test_foreground_copy_starts_indeterminate
test_paused_automatic_run_is_silent_and_preserves_history
test_headless_retry_publishes_private_progress
test_headless_retry_never_opens_progress_window
test_terminal_outcomes_invalidate_durable_progress

if (( failures > 0 )); then
  printf '%s backup outcome test(s) failed.\n' "$failures"
  exit 1
fi

printf '%s\n' 'All backup outcome tests passed.'
