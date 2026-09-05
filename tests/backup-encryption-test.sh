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
  TEST_HOME="$(cd "$TEST_HOME" && /bin/pwd -P)"
  TEST_DIRS+=("$TEST_HOME")
  FAKE_BIN="$TEST_HOME/fake-bin"
  VOLUME="$TEST_HOME/GoogleDrive-Backup"
  DISKUTIL_LOG="$TEST_HOME/diskutil.log"
  DISKUTIL_COUNT_FILE="$TEST_HOME/diskutil-count"
  APFS_LIST_COUNT_FILE="$TEST_HOME/apfs-list-count"
  OSASCRIPT_LOG="$TEST_HOME/osascript.log"
  OPEN_LOG="$TEST_HOME/open.log"
  RCLONE_LOG="$TEST_HOME/rclone.log"
  CRYPT_CONFIG_COUNT="$TEST_HOME/crypt-config-count"
  RETENTION_TRASH="$TEST_HOME/retention-trash"
  mkdir -p "$FAKE_BIN"
  : >"$DISKUTIL_LOG"
  : >"$OSASCRIPT_LOG"
  : >"$OPEN_LOG"
  : >"$RCLONE_LOG"
  : >"$TEST_HOME/backup.log"

  cat >"$FAKE_BIN/rclone" <<'SH'
#!/bin/bash
set -u
printf '%s\n' "$*" >>"${FAKE_RCLONE_LOG:?}"
case "${1:-}" in
  config)
    if [[ "${2:-}" == "show" && "${3:-}" == "${FAKE_CRYPT_REMOTE:-backup-crypt}" ]]; then
      count=1
      if [[ -f "${FAKE_CRYPT_CONFIG_COUNT:?}" ]]; then
        count="$(( $(<"$FAKE_CRYPT_CONFIG_COUNT") + 1 ))"
      fi
      printf '%s\n' "$count" >"$FAKE_CRYPT_CONFIG_COUNT"
      no_data_encryption="${FAKE_CRYPT_NO_DATA_ENCRYPTION:-false}"
      if (( ${FAKE_CRYPT_WEAKEN_AFTER:-0} > 0 && count > FAKE_CRYPT_WEAKEN_AFTER )); then
        no_data_encryption=true
      fi
      printf '[%s]\n' "${FAKE_CRYPT_REMOTE:-backup-crypt}"
      printf 'type = %s\n' "${FAKE_CRYPT_TYPE:-crypt}"
      printf 'remote = %s\n' "${FAKE_CRYPT_ROOT:-/missing-crypt-root}"
      printf 'password = %s\n' "${FAKE_CRYPT_PASSWORD-*** ENCRYPTED ***}"
      if [[ "${FAKE_CRYPT_PASSWORD2_PRESENT:-1}" == "1" ]]; then
        printf 'password2 = %s\n' "${FAKE_CRYPT_PASSWORD2-*** ENCRYPTED ***}"
      fi
      printf 'filename_encryption = %s\n' "${FAKE_CRYPT_FILENAME_ENCRYPTION:-standard}"
      printf 'directory_name_encryption = %s\n' "${FAKE_CRYPT_DIRECTORY_ENCRYPTION:-true}"
      printf 'no_data_encryption = %s\n' "$no_data_encryption"
      printf 'show_mapping = %s\n' "${FAKE_CRYPT_SHOW_MAPPING:-false}"
    fi
    exit 0
    ;;
  backend)
    if [[ "${2:-}" == "encode" ]]; then
      logical="${*: -1}"
      case "$logical" in
        *"${FAKE_CRYPT_OLD_VERSION:-never-old}") printf '["cipher-versions/cipher-old"]\n' ;;
        *"${FAKE_CRYPT_KEEPER_VERSION:-never-keeper}") printf '["cipher-versions/cipher-keeper"]\n' ;;
        *) printf '[]\n' ;;
      esac
    elif [[ "${2:-}" == "query" ]]; then
      printf '%s\n' "${FAKE_RCLONE_COLLISION_QUERY_JSON:-[]}"
    elif [[ "${2:-}" == "copyid" ]]; then
      if [[ "${FAKE_RCLONE_ARCHIVE_STATUS:-0}" == "0" ]]; then
        mkdir -p "${5:-}"
        : >"${5:-}/${FAKE_RCLONE_ARCHIVE_FILE_NAME:-image.heic}"
        if [[ -n "${FAKE_COLLISION_IDENTITY_SWAP_MARKER:-}" ]]; then
          : >"$FAKE_COLLISION_IDENTITY_SWAP_MARKER"
        fi
      fi
      exit "${FAKE_RCLONE_ARCHIVE_STATUS:-0}"
    else
      printf '[]\n'
    fi
    exit 0
    ;;
  lsf)
    printf '%s' "${FAKE_CRYPT_VERSION_NAMES-}"
    exit "${FAKE_CRYPT_LSF_STATUS:-0}"
    ;;
  copy)
    if [[ -n "${FAKE_RCLONE_COPY_OUTPUT:-}" ]]; then
      if [[ -z "${FAKE_RCLONE_COPY_ONCE_MARKER:-}" ||
            ! -e "$FAKE_RCLONE_COPY_ONCE_MARKER" ]]; then
        printf '%s\n' "$FAKE_RCLONE_COPY_OUTPUT"
        if [[ -n "${FAKE_RCLONE_COPY_ONCE_MARKER:-}" ]]; then
          : >"$FAKE_RCLONE_COPY_ONCE_MARKER"
        fi
      fi
    fi
    exit "${FAKE_RCLONE_COPY_STATUS:-0}"
    ;;
esac
exit 64
SH

  cat >"$FAKE_BIN/trash" <<'SH'
#!/bin/bash
set -u
if [[ -n "${FAKE_RETENTION_SWAP_ON_TRASH_FAILURE:-}" ]]; then
  : >"$FAKE_RETENTION_SWAP_ON_TRASH_FAILURE"
  exit 1
fi
mkdir -p "${FAKE_RETENTION_TRASH:?}"
for path in "$@"; do
  /bin/mv "$path" "$FAKE_RETENTION_TRASH/${path##*/}" || exit $?
done
if [[ -n "${FAKE_RETENTION_SWAP_AFTER_TRASH:-}" ]]; then
  : >"$FAKE_RETENTION_SWAP_AFTER_TRASH"
fi
SH

  cat >"$FAKE_BIN/jq" <<'SH'
#!/bin/bash
if [[ "${FAKE_JQ_USE_SYSTEM:-0}" == "1" ]]; then
  exec /usr/bin/jq "$@"
fi
if [[ "$*" == *"APFSVolumeUUID"* ]]; then
  exec /usr/bin/jq "$@"
fi
case "${1:-}" in
  length) printf '0\n' ;;
  -r)
    if [[ -n "${FAKE_RETENTION_START_SWAP_MARKER:-}" ]]; then
      : >"$FAKE_RETENTION_START_SWAP_MARKER"
    fi
    exit 0
    ;;
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
  mount_point="${FAKE_MOUNT_POINT:-/missing-test-mount}"
  volume_name="${FAKE_VOLUME_NAME:-GoogleDrive-Backup}"
  container_reference="${FAKE_CONTAINER_REFERENCE:-disk99}"
  external_value="${FAKE_EXTERNAL_VALUE:-true}"
  writable_value="${FAKE_WRITABLE_VALUE:-true}"
  system_image_value="${FAKE_SYSTEM_IMAGE_VALUE:-false}"
  requested_identifier="$(printf '%s' "${3:-}" | /usr/bin/tr '[:upper:]' '[:lower:]')"
  new_identifier="$(printf '%s' "${FAKE_NEW_APFS_UUID:-/missing-new-uuid}" | /usr/bin/tr '[:upper:]' '[:lower:]')"
  named_identifier="$(printf '%s' "${FAKE_NAMED_UUID:-/missing-named-uuid}" | /usr/bin/tr '[:upper:]' '[:lower:]')"
  second_named_identifier="$(printf '%s' "${FAKE_SECOND_NAMED_UUID:-/missing-second-named-uuid}" | /usr/bin/tr '[:upper:]' '[:lower:]')"
  if [[ "${3:-}" == "${FAKE_CANDIDATE_MOUNT:-/missing-candidate}" ]]; then
    mount_point="$FAKE_CANDIDATE_MOUNT"
    volume_uuid="${FAKE_CANDIDATE_UUID:-99999999-9999-4999-8999-999999999999}"
    volume_name="${FAKE_CANDIDATE_NAME:-TOSHIBA_4TB}"
    container_reference="${FAKE_CANDIDATE_CONTAINER:-$container_reference}"
  elif [[ "${3:-}" == "${FAKE_SECOND_CANDIDATE_MOUNT:-/missing-second-candidate}" ]]; then
    mount_point="$FAKE_SECOND_CANDIDATE_MOUNT"
    volume_uuid="${FAKE_SECOND_CANDIDATE_UUID:-dddddddd-dddd-dddd-dddd-dddddddddddd}"
    volume_name="${FAKE_SECOND_CANDIDATE_NAME:-SECOND_DISK}"
    container_reference="${FAKE_SECOND_CANDIDATE_CONTAINER:-disk100}"
  elif [[ "$requested_identifier" == "$named_identifier" ]]; then
    mount_point="${FAKE_NAMED_MOUNT:-/missing-named-mount}"
    volume_uuid="$FAKE_NAMED_UUID"
    volume_name="${FAKE_NAMED_NAME:-GoogleDrive-Backup}"
    container_reference="${FAKE_NAMED_CONTAINER:-$container_reference}"
    external_value="${FAKE_NAMED_EXTERNAL_VALUE:-$external_value}"
    writable_value="${FAKE_NAMED_WRITABLE_VALUE:-$writable_value}"
    system_image_value="${FAKE_NAMED_SYSTEM_IMAGE_VALUE:-$system_image_value}"
  elif [[ "$requested_identifier" == "$second_named_identifier" ]]; then
    mount_point="${FAKE_SECOND_NAMED_MOUNT:-/missing-second-named-mount}"
    volume_uuid="$FAKE_SECOND_NAMED_UUID"
    volume_name="${FAKE_SECOND_NAMED_NAME:-GoogleDrive-Backup}"
    container_reference="${FAKE_SECOND_NAMED_CONTAINER:-$container_reference}"
  elif [[ "$requested_identifier" == "$new_identifier" ]]; then
    mount_point="${FAKE_CREATED_MOUNT:-/missing-created-mount}"
    volume_uuid="$FAKE_NEW_APFS_UUID"
    volume_name="${FAKE_CREATED_NAME:-GoogleDrive-Backup}"
  fi
  if (( count > ${FAKE_DISKUTIL_CHANGE_AFTER:-1} )); then
    encryption_value="${FAKE_ENCRYPTION_AFTER_FIRST-$encryption_value}"
    volume_uuid="${FAKE_VOLUME_UUID_AFTER_FIRST-$volume_uuid}"
  fi
  if [[ -f "${FAKE_IDENTITY_SWAP_MARKER:-/missing-identity-swap-marker}" ]]; then
    volume_uuid="${FAKE_VOLUME_UUID_AFTER_MARKER:-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee}"
  fi
  if [[ "${3:-}" == "${FAKE_CANDIDATE_MOUNT:-/missing-candidate}" &&
        -f "${FAKE_SETUP_SOURCE_SWAP_MARKER:-/missing-setup-source-swap-marker}" ]]; then
    volume_uuid="${FAKE_CANDIDATE_UUID_AFTER_SOURCE_SWAP:-44444444-4444-4444-8444-444444444444}"
  fi
  cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>FilesystemType</key><string>${FAKE_FILESYSTEM_TYPE:-apfs}</string>
  <key>MountPoint</key><string>${mount_point}</string>
  <key>RemovableMediaOrExternalDevice</key><${external_value}/>
  <key>WritableMedia</key><${writable_value}/>
  $(if [[ "${FAKE_PLIST_MODE:-valid}" != "missing-encryption" ]]; then
      printf '<key>Encryption</key><%s/>' "$encryption_value"
    fi)
  <key>Locked</key><${FAKE_LOCKED_VALUE:-false}/>
  <key>VolumeUUID</key><string>${volume_uuid}</string>
  <key>VolumeName</key><string>${volume_name}</string>
  <key>APFSContainerReference</key><string>${container_reference}</string>
  <key>SystemImage</key><${system_image_value}/>
  <key>DeviceIdentifier</key><string>${FAKE_DEVICE_IDENTIFIER:-disk99s1}</string>
</dict>
</plist>
PLIST
  exit 0
fi
if [[ "${1:-}" == "apfs" && "${2:-}" == "list" && "${3:-}" == "-plist" ]]; then
  list_count=1
  if [[ -f "${FAKE_APFS_LIST_COUNT_FILE:?}" ]]; then
    list_count="$(( $(<"$FAKE_APFS_LIST_COUNT_FILE") + 1 ))"
  fi
  printf '%s\n' "$list_count" >"$FAKE_APFS_LIST_COUNT_FILE"
  if (( ${FAKE_APFS_APPEAR_AFTER_LIST_COUNT:-0} > 0 &&
        list_count >= ${FAKE_APFS_APPEAR_AFTER_LIST_COUNT:-0} )) &&
     [[ ! -e "${FAKE_APFS_APPEARED_MARKER:-/missing-appeared-marker}" ]]; then
    : >"$FAKE_APFS_APPEARED_MARKER"
    mkdir -p "${FAKE_APPEARED_MOUNT:?}"
  fi
  emit_volume() {
    local uuid="$1"
    local name="$2"
    local omit_uuid="${3:-0}"
    [[ -n "$uuid" || "$omit_uuid" == "1" ]] || return 0
    printf '<dict><key>Name</key><string>%s</string>' "$name"
    if [[ "$omit_uuid" != "1" ]]; then
      printf '<key>APFSVolumeUUID</key><string>%s</string>' "$uuid"
    fi
    printf '</dict>\n'
  }
  source_volume_uuid="${FAKE_CANDIDATE_UUID:-99999999-9999-4999-8999-999999999999}"
  container_uuid="${FAKE_APFS_CONTAINER_UUID:-22222222-2222-4222-8222-222222222222}"
  physical_store_uuid="${FAKE_APFS_PHYSICAL_STORE_UUID:-33333333-3333-4333-8333-333333333333}"
  if [[ -f "${FAKE_SETUP_SOURCE_SWAP_MARKER:-/missing-setup-source-swap-marker}" ]]; then
    source_volume_uuid="${FAKE_CANDIDATE_UUID_AFTER_SOURCE_SWAP:-44444444-4444-4444-8444-444444444444}"
    container_uuid="${FAKE_APFS_CONTAINER_UUID_AFTER_SOURCE_SWAP:-55555555-5555-4555-8555-555555555555}"
    physical_store_uuid="${FAKE_APFS_PHYSICAL_STORE_UUID_AFTER_SOURCE_SWAP:-66666666-6666-4666-8666-666666666666}"
  fi
  cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>Containers</key><array>
PLIST
  if [[ -n "${FAKE_APFS_FOREIGN_CONTAINER_REFERENCE:-}" ]]; then
    cat <<PLIST
<dict><key>ContainerReference</key><string>${FAKE_APFS_FOREIGN_CONTAINER_REFERENCE}</string>
<key>Volumes</key><array>
PLIST
    emit_volume \
      "${FAKE_APFS_FOREIGN_VOLUME_UUID:-eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee}" \
      "${FAKE_APFS_FOREIGN_VOLUME_NAME:-GoogleDrive-Backup}"
    printf '</array></dict>\n'
  fi
  cat <<PLIST
<dict>
<key>ContainerReference</key><string>${4:-disk99}</string>
<key>APFSContainerUUID</key><string>${container_uuid}</string>
<key>PhysicalStores</key><array><dict>
<key>DeviceIdentifier</key><string>${FAKE_APFS_PHYSICAL_STORE_IDENTIFIER:-disk9s2}</string>
<key>DiskUUID</key><string>${physical_store_uuid}</string>
</dict></array>
<key>Volumes</key><array>
PLIST
  emit_volume "$source_volume_uuid" "${FAKE_CANDIDATE_NAME:-TOSHIBA_4TB}"
  emit_volume \
    "${FAKE_EXISTING_APFS_UUID_1-${FAKE_EXISTING_APFS_UUID:-aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa}}" \
    "${FAKE_EXISTING_APFS_NAME_1:-GoogleDrive-Backup}" \
    "${FAKE_EXISTING_APFS_OMIT_UUID_1:-0}"
  emit_volume \
    "${FAKE_EXISTING_APFS_UUID_2:-}" \
    "${FAKE_EXISTING_APFS_NAME_2:-GoogleDrive-Backup}" \
    "${FAKE_EXISTING_APFS_OMIT_UUID_2:-0}"
  emit_volume \
    "${FAKE_EXISTING_APFS_UUID_3:-}" \
    "${FAKE_EXISTING_APFS_NAME_3:-GoogleDrive-Backup}" \
    "${FAKE_EXISTING_APFS_OMIT_UUID_3:-0}"
  if [[ -f "${FAKE_APFS_CREATED_MARKER:-/missing-created-marker}" ]]; then
    emit_volume \
      "${FAKE_NEW_APFS_UUID:-bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb}" \
      "${FAKE_CREATED_NAME:-GoogleDrive-Backup}"
    emit_volume \
      "${FAKE_SECOND_NEW_APFS_UUID:-}" \
      "${FAKE_SECOND_CREATED_NAME:-GoogleDrive-Backup}"
  fi
  if [[ -f "${FAKE_APFS_APPEARED_MARKER:-/missing-appeared-marker}" ]]; then
    emit_volume \
      "${FAKE_APPEARED_APFS_UUID:-cccccccc-cccc-cccc-cccc-cccccccccccc}" \
      "${FAKE_APPEARED_APFS_NAME:-GoogleDrive-Backup}"
  fi
  printf '</array></dict>\n'
  if [[ "${FAKE_APFS_DUPLICATE_REQUESTED_CONTAINER:-0}" == "1" ]]; then
    cat <<PLIST
<dict><key>ContainerReference</key><string>${4:-disk99}</string>
<key>Volumes</key><array>
PLIST
    emit_volume \
      "${FAKE_APFS_DUPLICATE_CONTAINER_UUID:-ffffffff-ffff-ffff-ffff-ffffffffffff}" \
      "${FAKE_APFS_DUPLICATE_CONTAINER_NAME:-GoogleDrive-Backup}"
    printf '</array></dict>\n'
  fi
  cat <<'PLIST'
</array></dict></plist>
PLIST
  exit 0
fi
if [[ "${1:-}" == "apfs" && "${2:-}" == "addVolume" ]]; then
  if [[ "${FAKE_ADMIN_GUARD_ACTIVE:-0}" == "1" ]]; then
    : >"${FAKE_APFS_CREATED_MARKER:?}"
    mkdir -p "${FAKE_CREATED_MOUNT:?}"
    exit "${FAKE_PRIVILEGED_ADD_STATUS:-0}"
  fi
  if [[ "${FAKE_UNPRIVILEGED_ADD_STATUS:-0}" != "0" ]]; then
    exit "$FAKE_UNPRIVILEGED_ADD_STATUS"
  fi
  : >"${FAKE_APFS_CREATED_MARKER:?}"
  mkdir -p "${FAKE_CREATED_MOUNT:?}"
  exit 0
fi
exit 64
SH

  cat >"$FAKE_BIN/open" <<'SH'
#!/bin/bash
set -u
printf '%s\n' "$*" >>"${FAKE_OPEN_LOG:?}"
response_path="${!#}"
printf '%s\n' "${FAKE_CONFIRM_RESPONSE:-no}" >"$response_path"
if [[ -n "${FAKE_CONFIRMATION_APPEAR_MARKER:-}" ]]; then
  : >"$FAKE_CONFIRMATION_APPEAR_MARKER"
fi
if [[ -n "${FAKE_CONFIRMATION_SOURCE_SWAP_MARKER:-}" ]]; then
  : >"$FAKE_CONFIRMATION_SOURCE_SWAP_MARKER"
fi
if [[ -n "${FAKE_CONFIRMATION_APPEAR_MOUNT:-}" ]]; then
  mkdir -p "$FAKE_CONFIRMATION_APPEAR_MOUNT"
fi
exit "${FAKE_OPEN_STATUS:-0}"
SH

  cat >"$FAKE_BIN/osascript" <<'SH'
#!/bin/bash
set -u
printf 'invoked\n' >>"${FAKE_OSASCRIPT_LOG:?}"
if [[ -n "${FAKE_ADMIN_PHASE_APPEAR_MARKER:-}" ]]; then
  : >"$FAKE_ADMIN_PHASE_APPEAR_MARKER"
  mkdir -p "${FAKE_ADMIN_PHASE_APPEAR_MOUNT:?}"
fi
if [[ -n "${FAKE_ADMIN_PHASE_SOURCE_SWAP_MARKER:-}" ]]; then
  : >"$FAKE_ADMIN_PHASE_SOURCE_SWAP_MARKER"
fi
if (( $# >= 7 )); then
  guard_script="$2"
  container="$3"
  volume_name="$4"
  source_volume_uuid="$5"
  container_uuid="$6"
  physical_store_uuids="$7"
  FAKE_ADMIN_GUARD_ACTIVE=1 /bin/sh -c "$guard_script" \
    gdrive-apfs-admin "${0%/*}/diskutil" "$container" "$volume_name" \
    "$source_volume_uuid" "$container_uuid" "$physical_store_uuids"
  exit $?
fi
: >"${FAKE_APFS_CREATED_MARKER:?}"
mkdir -p "${FAKE_CREATED_MOUNT:?}"
exit "${FAKE_PRIVILEGED_ADD_STATUS:-0}"
SH

  chmod +x "$FAKE_BIN/rclone" "$FAKE_BIN/jq" "$FAKE_BIN/flock" "$FAKE_BIN/diskutil" \
    "$FAKE_BIN/osascript" "$FAKE_BIN/open" "$FAKE_BIN/trash"
}

run_backup_command() {
  local argument="$1"
  shift
  env \
    HOME="$TEST_HOME" \
    GDRIVE_BACKUP_PATH="$FAKE_BIN:/usr/bin:/bin:/usr/sbin:/sbin" \
    GDRIVE_BACKUP_DISKUTIL="$FAKE_BIN/diskutil" \
    GDRIVE_BACKUP_OSASCRIPT="$FAKE_BIN/osascript" \
    FAKE_DISKUTIL_LOG="$DISKUTIL_LOG" \
    FAKE_DISKUTIL_COUNT_FILE="$DISKUTIL_COUNT_FILE" \
    FAKE_APFS_LIST_COUNT_FILE="$APFS_LIST_COUNT_FILE" \
    FAKE_OSASCRIPT_LOG="$OSASCRIPT_LOG" \
    FAKE_OPEN_LOG="$OPEN_LOG" \
    FAKE_RCLONE_LOG="$RCLONE_LOG" \
    FAKE_CRYPT_CONFIG_COUNT="$CRYPT_CONFIG_COUNT" \
    FAKE_CRYPT_REMOTE="${FAKE_CRYPT_REMOTE:-backup-crypt}" \
    FAKE_CRYPT_TYPE="${FAKE_CRYPT_TYPE:-crypt}" \
    FAKE_CRYPT_ROOT="${FAKE_CRYPT_ROOT:-$VOLUME}" \
    FAKE_CRYPT_PASSWORD="${FAKE_CRYPT_PASSWORD-*** ENCRYPTED ***}" \
    FAKE_CRYPT_PASSWORD2="${FAKE_CRYPT_PASSWORD2-*** ENCRYPTED ***}" \
    FAKE_CRYPT_PASSWORD2_PRESENT="${FAKE_CRYPT_PASSWORD2_PRESENT:-1}" \
    FAKE_CRYPT_FILENAME_ENCRYPTION="${FAKE_CRYPT_FILENAME_ENCRYPTION:-standard}" \
    FAKE_CRYPT_DIRECTORY_ENCRYPTION="${FAKE_CRYPT_DIRECTORY_ENCRYPTION:-true}" \
    FAKE_CRYPT_NO_DATA_ENCRYPTION="${FAKE_CRYPT_NO_DATA_ENCRYPTION:-false}" \
    FAKE_CRYPT_SHOW_MAPPING="${FAKE_CRYPT_SHOW_MAPPING:-false}" \
    FAKE_CRYPT_WEAKEN_AFTER="${FAKE_CRYPT_WEAKEN_AFTER:-0}" \
    FAKE_CRYPT_VERSION_NAMES="${FAKE_CRYPT_VERSION_NAMES-}" \
    FAKE_CRYPT_OLD_VERSION="${FAKE_CRYPT_OLD_VERSION-never-old}" \
    FAKE_CRYPT_KEEPER_VERSION="${FAKE_CRYPT_KEEPER_VERSION-never-keeper}" \
    FAKE_CRYPT_LSF_STATUS="${FAKE_CRYPT_LSF_STATUS:-0}" \
    FAKE_RETENTION_TRASH="$RETENTION_TRASH" \
    MOUNT_SETTLE_SECONDS=0 \
    GDRIVE_BACKUP_TARGET=apfs \
    GDRIVE_BACKUP_VOLUME="$VOLUME" \
    GDRIVE_BACKUP_VOLUME_UUID="${GDRIVE_BACKUP_VOLUME_UUID:-11111111-2222-3333-4444-555555555555}" \
    GDRIVE_BACKUP_DEST_ROOT="$VOLUME" \
    GDRIVE_BACKUP_CONFIRM=0 \
    GDRIVE_BACKUP_AUTO_CREATE_VOLUME=1 \
    GDRIVE_BACKUP_VERSIONING=0 \
    GDRIVE_BACKUP_RETENTION=0 \
    GDRIVE_BACKUP_RETENTION_TRASH_BIN="$FAKE_BIN/trash" \
    GDRIVE_BACKUP_LOCK="$TEST_HOME/backup.lock" \
    GDRIVE_BACKUP_LOG="$TEST_HOME/backup.log" \
    BACKUP_DISABLE_ANIMATION=1 \
    FAKE_MOUNT_POINT="${FAKE_MOUNT_POINT:-$VOLUME}" \
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

  run_backup GDRIVE_BACKUP_ENCRYPTION=apfs \
    GDRIVE_BACKUP_VOLUME_UUID= GDRIVE_BACKUP_TRIGGER=setup
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

test_default_mode_preserves_uuid_bound_targets() {
  local name="default mode keeps existing UUID-bound unencrypted target behavior"
  local status
  prepare_test_environment
  mkdir -p "$VOLUME"

  run_backup
  status=$?

  if [[ "$status" == "0" && -s "$DISKUTIL_LOG" ]] &&
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

test_rclone_crypt_requires_a_safe_remote_name() {
  local name="rclone crypt requires one safe explicit destination remote"
  local value status rejected=0

  for value in '' '../../outside' 'source:remote'; do
    prepare_test_environment
    mkdir -p "$VOLUME"
    run_backup GDRIVE_BACKUP_ENCRYPTION=rclone-crypt \
      "GDRIVE_BACKUP_CRYPT_REMOTE=$value"
    status=$?
    if [[ "$status" == "64" ]] &&
      [[ ! -e "$RCLONE_LOG" || ! $(grep -Ec '^copy( |$)' "$RCLONE_LOG") -gt 0 ]]; then
      rejected=$((rejected + 1))
    fi
  done

  if [[ "$rejected" == "3" ]]; then
    pass "$name"
  else
    fail "$name ($rejected of 3 rejected)"
  fi
}

test_rclone_crypt_configuration_fails_closed() {
  local name="rclone crypt rejects wrong roots and weakened encryption settings"
  local mode status rejected=0

  for mode in type root password salt filename directories data mapping; do
    prepare_test_environment
    mkdir -p "$VOLUME"
    case "$mode" in
      type) FAKE_CRYPT_TYPE=local run_backup GDRIVE_BACKUP_ENCRYPTION=rclone-crypt GDRIVE_BACKUP_CRYPT_REMOTE=backup-crypt ;;
      root) FAKE_CRYPT_ROOT="$TEST_HOME/outside" run_backup GDRIVE_BACKUP_ENCRYPTION=rclone-crypt GDRIVE_BACKUP_CRYPT_REMOTE=backup-crypt ;;
      password) FAKE_CRYPT_PASSWORD='' run_backup GDRIVE_BACKUP_ENCRYPTION=rclone-crypt GDRIVE_BACKUP_CRYPT_REMOTE=backup-crypt ;;
      salt) FAKE_CRYPT_PASSWORD2_PRESENT=0 run_backup GDRIVE_BACKUP_ENCRYPTION=rclone-crypt GDRIVE_BACKUP_CRYPT_REMOTE=backup-crypt ;;
      filename) FAKE_CRYPT_FILENAME_ENCRYPTION=off run_backup GDRIVE_BACKUP_ENCRYPTION=rclone-crypt GDRIVE_BACKUP_CRYPT_REMOTE=backup-crypt ;;
      directories) FAKE_CRYPT_DIRECTORY_ENCRYPTION=false run_backup GDRIVE_BACKUP_ENCRYPTION=rclone-crypt GDRIVE_BACKUP_CRYPT_REMOTE=backup-crypt ;;
      data) FAKE_CRYPT_NO_DATA_ENCRYPTION=true run_backup GDRIVE_BACKUP_ENCRYPTION=rclone-crypt GDRIVE_BACKUP_CRYPT_REMOTE=backup-crypt ;;
      mapping) FAKE_CRYPT_SHOW_MAPPING=true run_backup GDRIVE_BACKUP_ENCRYPTION=rclone-crypt GDRIVE_BACKUP_CRYPT_REMOTE=backup-crypt ;;
    esac
    status=$?
    if [[ "$status" == "78" ]] &&
      grep -Fq 'config show backup-crypt' "$RCLONE_LOG" &&
      ! grep -Eq '^copy( |$)' "$RCLONE_LOG"; then
      rejected=$((rejected + 1))
    fi
  done

  if [[ "$rejected" == "8" ]]; then
    pass "$name"
  else
    fail "$name ($rejected of 8 rejected)"
  fi
}

test_rclone_crypt_copy_and_versions_share_one_remote() {
  local name="rclone crypt encrypts copy and backup-dir paths on one remote"
  local status
  prepare_test_environment
  mkdir -p "$VOLUME"

  run_backup GDRIVE_BACKUP_ENCRYPTION=rclone-crypt \
    GDRIVE_BACKUP_CRYPT_REMOTE=backup-crypt \
    GDRIVE_BACKUP_VERSIONING=1 GDRIVE_BACKUP_RETENTION=0
  status=$?

  if [[ "$status" == "0" ]] &&
    grep -Fq 'copy tdd-remote: backup-crypt:My Drive' "$RCLONE_LOG" &&
    grep -Fq -- '--backup-dir backup-crypt:.gdrive-versions/' "$RCLONE_LOG" &&
    [[ ! -e "$VOLUME/My Drive" ]]; then
    pass "$name"
  else
    fail "$name (status $status)"
  fi
}

test_rclone_crypt_retention_merges_then_trashes_physical_ciphertext() {
  local name="rclone crypt retention merges sparse history before trashing only ciphertext"
  local old keeper status merge_line encode_line
  prepare_test_environment
  mkdir -p "$VOLUME/cipher-versions/cipher-old" "$VOLUME/cipher-active"
  old="2026-07-09T08-00-00+0200-00000000-0000-4000-8000-000000000041"
  keeper="2026-07-09T20-00-00+0200-00000000-0000-4000-8000-000000000042"

  FAKE_CRYPT_VERSION_NAMES="$old/"$'\n'"$keeper/"$'\n' \
    FAKE_CRYPT_OLD_VERSION="$old" \
    FAKE_CRYPT_KEEPER_VERSION="$keeper" \
    run_backup GDRIVE_BACKUP_ENCRYPTION=rclone-crypt \
      GDRIVE_BACKUP_CRYPT_REMOTE=backup-crypt \
      GDRIVE_BACKUP_VERSIONING=1 GDRIVE_BACKUP_RETENTION=1
  status=$?

  merge_line="$(grep -nF "copy backup-crypt:.gdrive-versions/$old backup-crypt:.gdrive-versions/$keeper" "$RCLONE_LOG" | cut -d: -f1)"
  encode_line="$(grep -nF 'backend encode backup-crypt:' "$RCLONE_LOG" | cut -d: -f1)"
  if [[ "$status" == "0" && -n "$merge_line" && -n "$encode_line" &&
        "$merge_line" -lt "$encode_line" &&
        -d "$RETENTION_TRASH/cipher-old" &&
        ! -e "$VOLUME/cipher-versions/cipher-old" &&
        -d "$VOLUME/cipher-active" ]] &&
    ! grep -Eq '^(delete|deletefile|purge|rmdirs)( |$)' "$RCLONE_LOG"; then
    pass "$name"
  else
    fail "$name (status $status)"
  fi
}

test_rclone_crypt_rejects_physical_symlink_redirection() {
  local name="rclone crypt rejects symlinks at or below its physical ciphertext root"
  local mode status rejected=0
  for mode in root nested; do
    prepare_test_environment
    mkdir -p "$TEST_HOME/outside"
    if [[ "$mode" == "root" ]]; then
      ln -s "$TEST_HOME/outside" "$VOLUME"
    else
      mkdir -p "$VOLUME/cipher-tree"
      ln -s "$TEST_HOME/outside" "$VOLUME/cipher-tree/redirect"
    fi
    run_backup GDRIVE_BACKUP_ENCRYPTION=rclone-crypt \
      GDRIVE_BACKUP_CRYPT_REMOTE=backup-crypt
    status=$?
    if [[ "$status" == "69" || "$status" == "78" ]] &&
       ! grep -Eq '^copy( |$)' "$RCLONE_LOG"; then
      rejected=$((rejected + 1))
    fi
  done
  if [[ "$rejected" == "2" ]]; then
    pass "$name"
  else
    fail "$name ($rejected of 2 redirections rejected)"
  fi
}

test_rclone_crypt_revalidates_policy_before_copy() {
  local name="rclone crypt revalidates its policy immediately before copying plaintext"
  local status checks
  prepare_test_environment
  mkdir -p "$VOLUME"
  FAKE_CRYPT_WEAKEN_AFTER=1 run_backup \
    GDRIVE_BACKUP_ENCRYPTION=rclone-crypt \
    GDRIVE_BACKUP_CRYPT_REMOTE=backup-crypt
  status=$?
  checks="$(grep -Fc 'config show backup-crypt' "$RCLONE_LOG")"
  if [[ "$status" == "1" && "$checks" -ge 2 ]] &&
    ! grep -Eq '^copy( |$)' "$RCLONE_LOG"; then
    pass "$name"
  else
    fail "$name (status $status, checks $checks)"
  fi
}

test_rclone_crypt_keeps_local_log_owner_only() {
  local name="rclone crypt keeps its local operational log owner-only"
  local status permissions
  prepare_test_environment
  mkdir -p "$VOLUME"
  run_backup GDRIVE_BACKUP_ENCRYPTION=rclone-crypt \
    GDRIVE_BACKUP_CRYPT_REMOTE=backup-crypt
  status=$?
  permissions="$(/usr/bin/stat -f '%Lp' "$TEST_HOME/backup.log" 2>/dev/null || true)"
  if [[ "$status" == "0" && "$permissions" == "600" ]]; then
    pass "$name"
  else
    fail "$name (status $status, mode $permissions)"
  fi
}

test_saved_apfs_uuid_resolves_the_current_mount_path() {
  local name="saved APFS UUID resolves the current mount path instead of a same-name path"
  local configured_volume resolved_volume status
  prepare_test_environment
  configured_volume="$TEST_HOME/GoogleDrive-Backup"
  resolved_volume="$TEST_HOME/GoogleDrive-Backup 2"
  mkdir -p "$configured_volume" "$resolved_volume"
  configured_volume="$(cd "$configured_volume" && /bin/pwd -P)"
  resolved_volume="$(cd "$resolved_volume" && /bin/pwd -P)"

  run_backup \
    GDRIVE_BACKUP_ENCRYPTION=none \
    GDRIVE_BACKUP_VOLUME_UUID=11111111-2222-3333-4444-555555555555 \
    GDRIVE_BACKUP_VOLUME="$configured_volume" \
    GDRIVE_BACKUP_DEST_ROOT="$configured_volume" \
    FAKE_MOUNT_POINT="$resolved_volume"
  status=$?

  if [[ "$status" == "0" ]] &&
    grep -Fq "mount=$resolved_volume dest=$resolved_volume" "$TEST_HOME/backup.log" &&
    grep -Fq "$resolved_volume/My Drive" "$RCLONE_LOG" &&
    ! grep -Fq "$configured_volume/My Drive" "$RCLONE_LOG"; then
    pass "$name"
  else
    fail "$name (status $status)"
  fi
}

test_saved_apfs_uuid_mismatch_fails_closed() {
  local name="saved APFS UUID mismatch stops before Drive access"
  local status
  prepare_test_environment
  mkdir -p "$VOLUME"

  run_backup \
    GDRIVE_BACKUP_ENCRYPTION=none \
    GDRIVE_BACKUP_VOLUME_UUID=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee \
    FAKE_VOLUME_UUID=11111111-2222-3333-4444-555555555555 \
    FAKE_MOUNT_POINT="$VOLUME"
  status=$?

  if [[ "$status" == "69" ]] &&
    { [[ ! -e "$RCLONE_LOG" ]] || ! grep -Eq '^(config|backend|copy)( |$)' "$RCLONE_LOG"; }; then
    pass "$name"
  else
    fail "$name (status $status)"
  fi
}

test_saved_apfs_uuid_accepts_a_mounted_apfs_image() {
  local name="saved APFS UUID still supports a mounted APFS image"
  local status
  prepare_test_environment
  mkdir -p "$VOLUME"

  run_backup \
    GDRIVE_BACKUP_ENCRYPTION=none \
    GDRIVE_BACKUP_VOLUME_UUID=11111111-2222-3333-4444-555555555555 \
    FAKE_EXTERNAL_VALUE=false \
    FAKE_MOUNT_POINT="$VOLUME"
  status=$?

  if [[ "$status" == "0" ]] && grep -Eq '^copy( |$)' "$RCLONE_LOG"; then
    pass "$name"
  else
    fail "$name (status $status)"
  fi
}

test_malformed_saved_apfs_uuid_is_rejected() {
  local name="malformed saved APFS UUID is rejected before disk access"
  local status
  prepare_test_environment
  mkdir -p "$VOLUME"

  run_backup \
    GDRIVE_BACKUP_ENCRYPTION=none \
    GDRIVE_BACKUP_VOLUME_UUID='../wrong-volume'
  status=$?

  if [[ "$status" == "64" && ! -s "$DISKUTIL_LOG" && ! -s "$RCLONE_LOG" ]]; then
    pass "$name"
  else
    fail "$name (status $status)"
  fi
}

test_saved_apfs_uuid_rejects_parent_component_escape() {
  local name="saved APFS UUID rejects a destination containing a parent traversal"
  local configured_volume resolved_volume outside status
  prepare_test_environment
  configured_volume="$TEST_HOME/Configured Backup"
  resolved_volume="$TEST_HOME/Resolved Backup"
  outside="$TEST_HOME/outside"
  mkdir -p "$configured_volume" "$resolved_volume" "$outside"

  run_backup \
    GDRIVE_BACKUP_ENCRYPTION=none \
    GDRIVE_BACKUP_VOLUME_UUID=11111111-2222-3333-4444-555555555555 \
    GDRIVE_BACKUP_VOLUME="$configured_volume" \
    GDRIVE_BACKUP_DEST_ROOT="$configured_volume/../outside" \
    FAKE_MOUNT_POINT="$resolved_volume"
  status=$?

  if [[ "$status" == "69" ]] &&
    { [[ ! -e "$RCLONE_LOG" ]] || ! grep -Eq '^copy( |$)' "$RCLONE_LOG"; }; then
    pass "$name"
  else
    fail "$name (status $status)"
  fi
}

test_saved_apfs_uuid_rejects_destination_symlink_escape() {
  local name="saved APFS UUID rejects a destination symlink leaving the volume"
  local configured_volume resolved_volume outside status
  prepare_test_environment
  configured_volume="$TEST_HOME/Configured Backup"
  resolved_volume="$TEST_HOME/Resolved Backup"
  outside="$TEST_HOME/outside"
  mkdir -p "$configured_volume" "$resolved_volume" "$outside"
  /bin/ln -s "$outside" "$resolved_volume/subdir"

  run_backup \
    GDRIVE_BACKUP_ENCRYPTION=none \
    GDRIVE_BACKUP_VOLUME_UUID=11111111-2222-3333-4444-555555555555 \
    GDRIVE_BACKUP_VOLUME="$configured_volume" \
    GDRIVE_BACKUP_DEST_ROOT="$configured_volume/subdir" \
    FAKE_MOUNT_POINT="$resolved_volume"
  status=$?

  if [[ "$status" == "69" ]] &&
    { [[ ! -e "$RCLONE_LOG" ]] || ! grep -Eq '^copy( |$)' "$RCLONE_LOG"; }; then
    pass "$name"
  else
    fail "$name (status $status)"
  fi
}

test_saved_apfs_uuid_rejects_in_volume_destination_symlink() {
  local name="saved APFS UUID rejects an in-volume destination symlink before writes"
  local configured_volume resolved_volume redirect_target config before_hash after_hash status
  prepare_test_environment
  configured_volume="$TEST_HOME/Configured Backup"
  resolved_volume="$TEST_HOME/Resolved Backup"
  redirect_target="$resolved_volume/redirect-target"
  config="$TEST_HOME/in-volume-destination-symlink.conf"
  mkdir -p "$configured_volume" "$resolved_volume" "$redirect_target"
  printf '%s\n' 'destination-canary' >"$redirect_target/canary"
  /bin/ln -s "$redirect_target" "$resolved_volume/nested"
  cat >"$config" <<CONFIG
GDRIVE_BACKUP_TARGET=apfs
GDRIVE_BACKUP_VOLUME='$configured_volume'
GDRIVE_BACKUP_VOLUME_NAME=GoogleDrive-Backup
GDRIVE_BACKUP_VOLUME_UUID=11111111-2222-3333-4444-555555555555
GDRIVE_BACKUP_DEST_ROOT='$configured_volume/nested/backup'
GDRIVE_BACKUP_AUTO_CREATE_VOLUME=1
CONFIG
  before_hash="$(/usr/bin/shasum "$config" "$redirect_target/canary")"

  run_backup \
    GDRIVE_BACKUP_CONFIG="$config" \
    GDRIVE_BACKUP_DEST_ROOT= \
    GDRIVE_BACKUP_ENCRYPTION=none \
    FAKE_MOUNT_POINT="$resolved_volume"
  status=$?
  after_hash="$(/usr/bin/shasum "$config" "$redirect_target/canary")"

  if [[ "$status" == "69" && "$before_hash" == "$after_hash" &&
        ! -e "$redirect_target/backup" ]] &&
    { [[ ! -e "$RCLONE_LOG" ]] || ! grep -Eq '^(config|backend|copy)( |$)' "$RCLONE_LOG"; } &&
    grep -Fqi 'symbol' "$TEST_HOME/backup.log"; then
    pass "$name"
  else
    fail "$name (status $status)"
  fi
}

test_saved_apfs_uuid_accepts_nested_destination() {
  local name="saved APFS UUID allows a normal nested destination on the volume"
  local configured_volume resolved_volume resolved_real status
  prepare_test_environment
  configured_volume="$TEST_HOME/Configured Backup"
  resolved_volume="$TEST_HOME/Resolved Backup"
  mkdir -p "$configured_volume" "$resolved_volume"
  resolved_real="$(cd "$resolved_volume" && /bin/pwd -P)"

  run_backup \
    GDRIVE_BACKUP_ENCRYPTION=none \
    GDRIVE_BACKUP_VOLUME_UUID=11111111-2222-3333-4444-555555555555 \
    GDRIVE_BACKUP_VOLUME="$configured_volume" \
    GDRIVE_BACKUP_DEST_ROOT="$configured_volume/nested/backup" \
    FAKE_MOUNT_POINT="$resolved_volume"
  status=$?

  if [[ "$status" == "0" ]] &&
    grep -Fq "$resolved_real/nested/backup/My Drive" "$RCLONE_LOG"; then
    pass "$name"
  else
    fail "$name (status $status)"
  fi
}

test_saved_apfs_uuid_revalidates_before_creating_destination() {
  local name="saved APFS UUID is revalidated after approval before destination creation"
  local configured_volume resolved_volume destination status
  prepare_test_environment
  configured_volume="$TEST_HOME/Configured Backup"
  resolved_volume="$TEST_HOME/Resolved Backup"
  destination="$resolved_volume/new-destination"
  mkdir -p "$configured_volume" "$resolved_volume"

  run_backup \
    GDRIVE_BACKUP_ENCRYPTION=none \
    GDRIVE_BACKUP_VOLUME_UUID=11111111-2222-3333-4444-555555555555 \
    GDRIVE_BACKUP_VOLUME="$configured_volume" \
    GDRIVE_BACKUP_DEST_ROOT="$configured_volume/new-destination" \
    FAKE_MOUNT_POINT="$resolved_volume" \
    FAKE_DISKUTIL_CHANGE_AFTER=2 \
    FAKE_VOLUME_UUID_AFTER_FIRST=aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee
  status=$?

  if [[ "$status" == "69" && ! -e "$destination" ]] &&
    { [[ ! -e "$RCLONE_LOG" ]] || ! grep -Eq '^copy( |$)' "$RCLONE_LOG"; }; then
    pass "$name"
  else
    fail "$name (status $status)"
  fi
}

test_saved_apfs_uuid_rejects_copy_child_symlink_escape() {
  local name="saved APFS UUID rejects active and version child symlinks leaving the volume"
  local mode outside status bad_pattern volume_real rejected=0
  local active_status="unset" versions_status="unset"

  for mode in active versions; do
    prepare_test_environment
    mkdir -p "$VOLUME"
    volume_real="$(cd "$VOLUME" && /bin/pwd -P)"
    outside="$TEST_HOME/outside-$mode"
    mkdir -p "$outside"
    if [[ "$mode" == "active" ]]; then
      /bin/ln -s "$outside" "$VOLUME/My Drive"
      bad_pattern="$volume_real/My Drive"
      run_backup \
        GDRIVE_BACKUP_ENCRYPTION=none \
        GDRIVE_BACKUP_VOLUME_UUID=11111111-2222-3333-4444-555555555555 \
        FAKE_MOUNT_POINT="$VOLUME"
    else
      /bin/ln -s "$outside" "$VOLUME/.gdrive-versions"
      bad_pattern="--backup-dir $volume_real/.gdrive-versions"
      run_backup \
        GDRIVE_BACKUP_ENCRYPTION=none \
        GDRIVE_BACKUP_VOLUME_UUID=11111111-2222-3333-4444-555555555555 \
        FAKE_MOUNT_POINT="$VOLUME" \
        GDRIVE_BACKUP_VERSIONING=1
    fi
    status=$?
    if [[ "$mode" == "active" ]]; then
      active_status="$status"
    else
      versions_status="$status"
    fi
    if [[ "$status" != "0" ]] &&
      { [[ ! -e "$RCLONE_LOG" ]] || ! grep -Fq -- "$bad_pattern" "$RCLONE_LOG"; }; then
      rejected=$((rejected + 1))
    fi
  done

  if [[ "$rejected" == "2" ]]; then
    pass "$name"
  else
    fail "$name ($rejected of 2 escapes rejected; active=$active_status versions=$versions_status)"
  fi
}

test_saved_apfs_uuid_rejects_deep_tree_symlink_escape() {
  local name="saved APFS UUID rejects deep symlinks in active and version trees"
  local mode outside status rejected=0

  for mode in active versions; do
    prepare_test_environment
    mkdir -p "$VOLUME"
    outside="$TEST_HOME/deep-outside-$mode"
    mkdir -p "$outside"
    if [[ "$mode" == "active" ]]; then
      mkdir -p "$VOLUME/My Drive/Nested Parent"
      /bin/ln -s "$outside" "$VOLUME/My Drive/Nested Parent/Escape"
      run_backup \
        GDRIVE_BACKUP_ENCRYPTION=none \
        GDRIVE_BACKUP_VOLUME_UUID=11111111-2222-3333-4444-555555555555 \
        FAKE_MOUNT_POINT="$VOLUME"
    else
      mkdir -p "$VOLUME/.gdrive-versions/old/Nested Parent"
      /bin/ln -s "$outside" \
        "$VOLUME/.gdrive-versions/old/Nested Parent/Escape"
      run_backup \
        GDRIVE_BACKUP_ENCRYPTION=none \
        GDRIVE_BACKUP_VOLUME_UUID=11111111-2222-3333-4444-555555555555 \
        FAKE_MOUNT_POINT="$VOLUME" \
        GDRIVE_BACKUP_VERSIONING=1
    fi
    status=$?
    if [[ "$status" != "0" ]] &&
      { [[ ! -e "$RCLONE_LOG" ]] || ! grep -Eq '^copy( |$)' "$RCLONE_LOG"; }; then
      rejected=$((rejected + 1))
    fi
  done

  if [[ "$rejected" == "2" ]]; then
    pass "$name"
  else
    fail "$name ($rejected of 2 deep escapes rejected)"
  fi
}

test_saved_apfs_uuid_scans_history_once_and_current_version_paths_per_copy() {
  local name="saved APFS UUID scans old history once and only current version paths per copy"
  local trace_env validation_log volume_real history_root status
  local full_scans scoped_scans
  prepare_test_environment
  mkdir -p "$VOLUME/.gdrive-versions/old/Nested"
  trace_env="$TEST_HOME/trace-apfs-tree-validation.sh"
  validation_log="$TEST_HOME/apfs-tree-validations.log"
  volume_real="$(cd "$VOLUME" && /bin/pwd -P)"
  history_root="${volume_real%/}/.gdrive-versions"
  cat >"$trace_env" <<'SH'
if [[ -n "${FAKE_APFS_VALIDATION_LOG:-}" ]]; then
  set -T
  trap 'if [[ "${FUNCNAME[0]:-}" == "validate_configured_apfs_tree" ]]; then
          printf "%s\n" "${1:-}" >>"$FAKE_APFS_VALIDATION_LOG"
        fi' RETURN
fi
SH

  run_backup \
    GDRIVE_BACKUP_ENCRYPTION=none \
    GDRIVE_BACKUP_VOLUME_UUID=11111111-2222-3333-4444-555555555555 \
    FAKE_MOUNT_POINT="$VOLUME" \
    GDRIVE_BACKUP_VERSIONING=1 \
    GDRIVE_BACKUP_RETENTION=0 \
    BASH_ENV="$trace_env" \
    FAKE_APFS_VALIDATION_LOG="$validation_log"
  status=$?
  full_scans="$(grep -Fxc "$history_root" "$validation_log" 2>/dev/null || true)"
  scoped_scans="$(/usr/bin/awk -v prefix="$history_root/" '
    index($0, prefix) == 1 { count++ }
    END { print count + 0 }
  ' "$validation_log" 2>/dev/null)"

  if [[ "$status" == "0" && "$full_scans" == "1" && "$scoped_scans" == "4" ]]; then
    pass "$name"
  else
    fail "$name (status $status, full history scans $full_scans, scoped scans $scoped_scans)"
  fi
}

test_apfs_tree_device_validation_streams_its_inventory() {
  local name="APFS tree device validation streams instead of materializing its inventory"
  local function_text
  function_text="$(/usr/bin/awk '
    /^validate_configured_apfs_tree\(\)/ { capture = 1 }
    capture { print }
    capture && /^}$/ { exit }
  ' "$BACKUP_SCRIPT")"

  if [[ "$function_text" != *"device_listing="* &&
        "$function_text" == *"/usr/bin/find -x"* &&
        "$function_text" == *"/usr/bin/awk -v expected_device="* ]]; then
    pass "$name"
  else
    fail "$name"
  fi
}

test_existing_named_apfs_volume_is_recovered_idempotently() {
  local name="one existing exact-name APFS volume is recovered and reused by UUID"
  local volumes_root configured_volume source_mount recovered_mount recovered_real
  local config marker status_one status_two saved_volume saved_uuid saved_destination add_count copy_count
  prepare_test_environment
  volumes_root="$TEST_HOME/Volumes"
  configured_volume="$volumes_root/Stale Backup Path"
  source_mount="$volumes_root/TOSHIBA_4TB"
  recovered_mount="$volumes_root/GoogleDrive-Backup 2"
  config="$TEST_HOME/recover-existing.conf"
  marker="$TEST_HOME/apfs-created"
  mkdir -p "$source_mount" "$recovered_mount"
  recovered_real="$(cd "$recovered_mount" && /bin/pwd -P)"
  cat >"$config" <<CONFIG
GDRIVE_BACKUP_TARGET=apfs
GDRIVE_BACKUP_VOLUME='$configured_volume'
GDRIVE_BACKUP_VOLUME_NAME=GoogleDrive-Backup
GDRIVE_BACKUP_VOLUME_UUID=
GDRIVE_BACKUP_DEST_ROOT='$configured_volume/nested/backup'
GDRIVE_BACKUP_AUTO_CREATE_VOLUME=1
CONFIG

  run_backup \
    GDRIVE_BACKUP_CONFIG="$config" \
    GDRIVE_BACKUP_DEST_ROOT= \
    GDRIVE_BACKUP_VOLUMES_ROOT="$volumes_root" \
    GDRIVE_BACKUP_TRIGGER=setup \
    FAKE_APFS_CREATED_MARKER="$marker" \
    FAKE_CANDIDATE_MOUNT="$source_mount" \
    FAKE_CANDIDATE_UUID=11111111-2222-3333-4444-555555555555 \
    FAKE_NAMED_UUID=cccccccc-cccc-cccc-cccc-cccccccccccc \
    FAKE_NAMED_MOUNT="$recovered_mount" \
    FAKE_NAMED_CONTAINER=disk99 \
    FAKE_EXISTING_APFS_UUID_1=cccccccc-cccc-cccc-cccc-cccccccccccc \
    FAKE_CREATED_MOUNT="$volumes_root/Unexpected Created Volume" \
    FAKE_NEW_APFS_UUID=bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb \
    GDRIVE_BACKUP_APPROVE_VOLUME_CREATION=1
  status_one=$?

  run_backup \
    GDRIVE_BACKUP_CONFIG="$config" \
    GDRIVE_BACKUP_DEST_ROOT= \
    GDRIVE_BACKUP_VOLUMES_ROOT="$volumes_root" \
    GDRIVE_BACKUP_TRIGGER=manual \
    FAKE_APFS_CREATED_MARKER="$marker" \
    FAKE_CANDIDATE_MOUNT="$source_mount" \
    FAKE_CANDIDATE_UUID=11111111-2222-3333-4444-555555555555 \
    FAKE_NAMED_UUID=cccccccc-cccc-cccc-cccc-cccccccccccc \
    FAKE_NAMED_MOUNT="$recovered_mount" \
    FAKE_NAMED_CONTAINER=disk99 \
    FAKE_EXISTING_APFS_UUID_1=cccccccc-cccc-cccc-cccc-cccccccccccc \
    FAKE_CREATED_MOUNT="$volumes_root/Unexpected Created Volume" \
    FAKE_NEW_APFS_UUID=bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb \
    GDRIVE_BACKUP_APPROVE_VOLUME_CREATION=1
  status_two=$?

  saved_volume="$(/bin/bash -c 'source "$1"; printf "%s" "${GDRIVE_BACKUP_VOLUME:-}"' _ "$config")"
  saved_uuid="$(/bin/bash -c 'source "$1"; printf "%s" "${GDRIVE_BACKUP_VOLUME_UUID:-}"' _ "$config")"
  saved_destination="$(/bin/bash -c 'source "$1"; printf "%s" "${GDRIVE_BACKUP_DEST_ROOT:-}"' _ "$config")"
  add_count="$(grep -Fc 'apfs addVolume' "$DISKUTIL_LOG" 2>/dev/null || true)"
  copy_count="$(grep -Fc "$recovered_real/nested/backup/My Drive" "$RCLONE_LOG" 2>/dev/null || true)"

  if [[ "$status_one" == "0" && "$status_two" == "0" &&
        "$saved_volume" == "$recovered_real" &&
        "$saved_uuid" == "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC" &&
        "$saved_destination" == "$recovered_real/nested/backup" &&
        "$add_count" == "0" && "$copy_count" == "2" ]] &&
    ! grep -Fq "$configured_volume/My Drive" "$RCLONE_LOG"; then
    pass "$name"
  else
    fail "$name (statuses $status_one/$status_two, volume $saved_volume, destination $saved_destination, uuid $saved_uuid, add $add_count, copies $copy_count)"
  fi
}

test_numeric_family_apfs_volumes_block_setup_creation() {
  local name="numeric-family APFS volumes block setup before selection or creation"
  local volumes_root configured_volume source_mount family_one family_two family_three
  local config marker animation_app before_hash after_hash status
  prepare_test_environment
  volumes_root="$TEST_HOME/Volumes"
  configured_volume="$volumes_root/Stale Backup Path"
  source_mount="$volumes_root/TOSHIBA_4TB"
  family_one="$volumes_root/GoogleDrive-Backup 1"
  family_two="$volumes_root/GoogleDrive-Backup 2"
  family_three="$volumes_root/GoogleDrive-Backup 3"
  config="$TEST_HOME/numeric-family.conf"
  marker="$TEST_HOME/apfs-created"
  animation_app="$TEST_HOME/Fake Confirmation.app"
  mkdir -p "$source_mount" "$family_one" "$family_two" "$family_three" \
    "$animation_app"
  printf '%s\n' 'source-canary' >"$source_mount/canary"
  printf '%s\n' 'family-one-canary' >"$family_one/canary"
  printf '%s\n' 'family-two-canary' >"$family_two/canary"
  printf '%s\n' 'family-three-canary' >"$family_three/canary"
  cat >"$config" <<CONFIG
GDRIVE_BACKUP_TARGET=apfs
GDRIVE_BACKUP_VOLUME='$configured_volume'
GDRIVE_BACKUP_VOLUME_NAME=GoogleDrive-Backup
GDRIVE_BACKUP_VOLUME_UUID=
GDRIVE_BACKUP_AUTO_CREATE_VOLUME=1
CONFIG
  before_hash="$(/usr/bin/shasum "$config" "$source_mount/canary" \
    "$family_one/canary" "$family_two/canary" "$family_three/canary")"

  run_backup \
    GDRIVE_BACKUP_CONFIG="$config" \
    GDRIVE_BACKUP_DEST_ROOT= \
    GDRIVE_BACKUP_VOLUMES_ROOT="$volumes_root" \
    GDRIVE_BACKUP_TRIGGER=setup \
    GDRIVE_BACKUP_ANIMATION_APP="$animation_app" \
    GDRIVE_BACKUP_OPEN_BIN="$FAKE_BIN/open" \
    FAKE_CONFIRM_RESPONSE=yes \
    FAKE_CANDIDATE_MOUNT="$source_mount" \
    FAKE_EXISTING_APFS_UUID_1=cccccccc-cccc-cccc-cccc-cccccccccccc \
    FAKE_EXISTING_APFS_NAME_1='GoogleDrive-Backup 1' \
    FAKE_EXISTING_APFS_UUID_2=dddddddd-dddd-dddd-dddd-dddddddddddd \
    FAKE_EXISTING_APFS_NAME_2='GoogleDrive-Backup 2' \
    FAKE_EXISTING_APFS_UUID_3=eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee \
    FAKE_EXISTING_APFS_NAME_3='GoogleDrive-Backup 3' \
    FAKE_APFS_CREATED_MARKER="$marker" \
    FAKE_CREATED_MOUNT="$volumes_root/Unexpected Created Volume" \
    FAKE_NEW_APFS_UUID=bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb
  status=$?
  after_hash="$(/usr/bin/shasum "$config" "$source_mount/canary" \
    "$family_one/canary" "$family_two/canary" "$family_three/canary")"

  if [[ "$status" == "69" && "$before_hash" == "$after_hash" &&
        ! -e "$marker" && ! -s "$OPEN_LOG" && ! -s "$OSASCRIPT_LOG" ]] &&
    grep -Fq 'apfs list -plist disk99' "$DISKUTIL_LOG" &&
    ! grep -Eq 'apfs (addVolume|delete|erase|partition|rename|unmount)' "$DISKUTIL_LOG" 2>/dev/null &&
    { [[ ! -e "$RCLONE_LOG" ]] || ! grep -Eq '^(config|backend|copy)( |$)' "$RCLONE_LOG"; } &&
    grep -Fqi 'numerisch' "$TEST_HOME/backup.log" &&
    grep -Fqi 'explizit' "$TEST_HOME/backup.log"; then
    pass "$name"
  else
    fail "$name (status $status)"
  fi
}

assert_invalid_named_apfs_inventory_is_rejected() {
  local name="$1"
  local volumes_root configured_volume source_mount config marker animation_app
  local before_hash after_hash status
  shift
  prepare_test_environment
  volumes_root="$TEST_HOME/Volumes"
  configured_volume="$volumes_root/Stale Backup Path"
  source_mount="$volumes_root/TOSHIBA_4TB"
  config="$TEST_HOME/invalid-named-inventory.conf"
  marker="$TEST_HOME/apfs-created"
  animation_app="$TEST_HOME/Fake Confirmation.app"
  mkdir -p "$source_mount" "$animation_app"
  printf '%s\n' 'source-canary' >"$source_mount/canary"
  cat >"$config" <<CONFIG
GDRIVE_BACKUP_TARGET=apfs
GDRIVE_BACKUP_VOLUME='$configured_volume'
GDRIVE_BACKUP_VOLUME_NAME=GoogleDrive-Backup
GDRIVE_BACKUP_VOLUME_UUID=
GDRIVE_BACKUP_AUTO_CREATE_VOLUME=1
CONFIG
  before_hash="$(/usr/bin/shasum "$config" "$source_mount/canary")"

  run_backup \
    GDRIVE_BACKUP_CONFIG="$config" \
    GDRIVE_BACKUP_DEST_ROOT= \
    GDRIVE_BACKUP_VOLUMES_ROOT="$volumes_root" \
    GDRIVE_BACKUP_TRIGGER=setup \
    GDRIVE_BACKUP_ANIMATION_APP="$animation_app" \
    GDRIVE_BACKUP_OPEN_BIN="$FAKE_BIN/open" \
    FAKE_CONFIRM_RESPONSE=yes \
    FAKE_CANDIDATE_MOUNT="$source_mount" \
    FAKE_APFS_CREATED_MARKER="$marker" \
    FAKE_CREATED_MOUNT="$volumes_root/Unexpected Created Volume" \
    "$@"
  status=$?
  after_hash="$(/usr/bin/shasum "$config" "$source_mount/canary")"

  if [[ "$status" == "69" && "$before_hash" == "$after_hash" &&
        ! -e "$marker" && ! -s "$OPEN_LOG" && ! -s "$OSASCRIPT_LOG" ]] &&
    grep -Fq 'apfs list -plist disk99' "$DISKUTIL_LOG" &&
    ! grep -Eq 'apfs (addVolume|delete|erase|partition|rename|unmount)' "$DISKUTIL_LOG" 2>/dev/null &&
    { [[ ! -e "$RCLONE_LOG" ]] || ! grep -Eq '^(config|backend|copy)( |$)' "$RCLONE_LOG"; }; then
    pass "$name"
  else
    fail "$name (status $status)"
  fi
}

test_apfs_inventory_rejects_duplicate_requested_container_among_foreign_containers() {
  assert_invalid_named_apfs_inventory_is_rejected \
    "APFS inventory rejects a duplicate requested container among foreign containers" \
    FAKE_EXISTING_APFS_UUID_1= \
    FAKE_APFS_FOREIGN_CONTAINER_REFERENCE=disk100 \
    FAKE_APFS_DUPLICATE_REQUESTED_CONTAINER=1
}

test_apfs_inventory_ignores_exact_name_in_foreign_container() {
  local name="APFS inventory ignores an exact-name volume in a foreign container"
  local volumes_root configured_volume source_mount created_mount config marker output
  local status saved_uuid add_count copy_count
  prepare_test_environment
  volumes_root="$TEST_HOME/Volumes"
  configured_volume="$volumes_root/Stale Backup Path"
  source_mount="$volumes_root/TOSHIBA_4TB"
  created_mount="$volumes_root/GoogleDrive-Backup"
  config="$TEST_HOME/foreign-container.conf"
  marker="$TEST_HOME/apfs-created"
  output="$TEST_HOME/foreign-container-output.log"
  mkdir -p "$source_mount"
  printf '%s\n' 'source-canary' >"$source_mount/canary"
  cat >"$config" <<CONFIG
GDRIVE_BACKUP_TARGET=apfs
GDRIVE_BACKUP_VOLUME='$configured_volume'
GDRIVE_BACKUP_VOLUME_NAME=GoogleDrive-Backup
GDRIVE_BACKUP_VOLUME_UUID=
GDRIVE_BACKUP_AUTO_CREATE_VOLUME=1
CONFIG

  run_backup \
    GDRIVE_BACKUP_CONFIG="$config" \
    GDRIVE_BACKUP_DEST_ROOT= \
    GDRIVE_BACKUP_VOLUMES_ROOT="$volumes_root" \
    GDRIVE_BACKUP_TRIGGER=setup \
    GDRIVE_BACKUP_APPROVE_VOLUME_CREATION=1 \
    FAKE_CANDIDATE_MOUNT="$source_mount" \
    FAKE_EXISTING_APFS_UUID_1= \
    FAKE_APFS_FOREIGN_CONTAINER_REFERENCE=disk100 \
    FAKE_APFS_FOREIGN_VOLUME_UUID=deadbeef-dead-4eef-8bad-deadbeefcafe \
    FAKE_APFS_CREATED_MARKER="$marker" \
    FAKE_CREATED_MOUNT="$created_mount" \
    FAKE_NEW_APFS_UUID=bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb \
    >"$output" 2>&1
  status=$?
  saved_uuid="$(/bin/bash -c 'source "$1"; printf "%s" "${GDRIVE_BACKUP_VOLUME_UUID:-}"' _ "$config")"
  add_count="$(grep -Fxc 'apfs addVolume disk99 APFS GoogleDrive-Backup' "$DISKUTIL_LOG" 2>/dev/null || true)"
  copy_count="$(grep -Fc "$created_mount/My Drive" "$RCLONE_LOG" 2>/dev/null || true)"

  if [[ "$status" == "0" && "$saved_uuid" == "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB" &&
        "$add_count" == "1" && "$copy_count" == "1" &&
        "$(<"$source_mount/canary")" == "source-canary" && ! -s "$OSASCRIPT_LOG" ]] &&
    ! grep -Fqi 'deadbeef-dead-4eef-8bad-deadbeefcafe' "$config" "$output" \
      "$TEST_HOME/backup.log"; then
    pass "$name"
  else
    fail "$name (status $status, uuid $saved_uuid, add/copies $add_count/$copy_count)"
  fi
}

test_exact_name_apfs_inventory_rejects_missing_uuid() {
  assert_invalid_named_apfs_inventory_is_rejected \
    "exact-name APFS inventory rejects a record without APFSVolumeUUID" \
    FAKE_EXISTING_APFS_UUID_1= \
    FAKE_EXISTING_APFS_OMIT_UUID_1=1 \
    FAKE_EXISTING_APFS_NAME_1=GoogleDrive-Backup
}

test_exact_name_apfs_inventory_rejects_malformed_uuid() {
  assert_invalid_named_apfs_inventory_is_rejected \
    "exact-name APFS inventory rejects a malformed APFSVolumeUUID" \
    FAKE_EXISTING_APFS_UUID_1=not-a-volume-uuid \
    FAKE_EXISTING_APFS_NAME_1=GoogleDrive-Backup
}

assert_existing_named_apfs_metadata_is_rejected() {
  local name="$1"
  local volumes_root configured_volume source_mount recovered_mount config marker
  local before_hash after_hash status
  shift
  prepare_test_environment
  volumes_root="$TEST_HOME/Volumes"
  configured_volume="$volumes_root/Stale Backup Path"
  source_mount="$volumes_root/TOSHIBA_4TB"
  recovered_mount="$volumes_root/GoogleDrive-Backup 2"
  config="$TEST_HOME/rejected-existing.conf"
  marker="$TEST_HOME/apfs-created"
  mkdir -p "$source_mount" "$recovered_mount"
  printf '%s\n' 'recovery-canary' >"$recovered_mount/canary"
  cat >"$config" <<CONFIG
GDRIVE_BACKUP_TARGET=apfs
GDRIVE_BACKUP_VOLUME='$configured_volume'
GDRIVE_BACKUP_VOLUME_NAME=GoogleDrive-Backup
GDRIVE_BACKUP_VOLUME_UUID=
GDRIVE_BACKUP_AUTO_CREATE_VOLUME=1
CONFIG
  before_hash="$(/usr/bin/shasum "$config" "$recovered_mount/canary")"

  run_backup \
    GDRIVE_BACKUP_CONFIG="$config" \
    GDRIVE_BACKUP_DEST_ROOT= \
    GDRIVE_BACKUP_VOLUMES_ROOT="$volumes_root" \
    GDRIVE_BACKUP_TRIGGER=setup \
    FAKE_CANDIDATE_MOUNT="$source_mount" \
    FAKE_CANDIDATE_UUID=11111111-2222-3333-4444-555555555555 \
    FAKE_NAMED_UUID=cccccccc-cccc-cccc-cccc-cccccccccccc \
    FAKE_NAMED_MOUNT="$recovered_mount" \
    FAKE_NAMED_CONTAINER=disk99 \
    FAKE_EXISTING_APFS_UUID_1=cccccccc-cccc-cccc-cccc-cccccccccccc \
    FAKE_EXISTING_APFS_NAME_1=GoogleDrive-Backup \
    FAKE_APFS_CREATED_MARKER="$marker" \
    FAKE_CREATED_MOUNT="$volumes_root/Unexpected Created Volume" \
    FAKE_NEW_APFS_UUID=bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb \
    GDRIVE_BACKUP_APPROVE_VOLUME_CREATION=1 \
    "$@"
  status=$?
  after_hash="$(/usr/bin/shasum "$config" "$recovered_mount/canary")"

  if [[ "$status" == "69" && "$before_hash" == "$after_hash" &&
        ! -e "$marker" && ! -s "$OSASCRIPT_LOG" ]] &&
    ! grep -Fq 'apfs addVolume' "$DISKUTIL_LOG" 2>/dev/null &&
    { [[ ! -e "$RCLONE_LOG" ]] || ! grep -Eq '^copy( |$)' "$RCLONE_LOG"; }; then
    pass "$name"
  else
    fail "$name (status $status)"
  fi
}

test_existing_named_apfs_volume_rejects_info_name_mismatch() {
  assert_existing_named_apfs_metadata_is_rejected \
    "existing named APFS recovery rejects an independently mismatched name" \
    FAKE_NAMED_NAME='GoogleDrive-Backup 1'
}

test_existing_named_apfs_volume_rejects_info_container_mismatch() {
  assert_existing_named_apfs_metadata_is_rejected \
    "existing named APFS recovery rejects an independently mismatched container" \
    FAKE_NAMED_CONTAINER=disk100
}

test_existing_named_apfs_volume_rejects_internal_media() {
  assert_existing_named_apfs_metadata_is_rejected \
    "existing named APFS recovery rejects independently reported internal media" \
    FAKE_NAMED_EXTERNAL_VALUE=false
}

test_existing_named_apfs_volume_rejects_read_only_media() {
  assert_existing_named_apfs_metadata_is_rejected \
    "existing named APFS recovery rejects independently reported read-only media" \
    FAKE_NAMED_WRITABLE_VALUE=false
}

test_existing_named_apfs_volume_rejects_system_image() {
  assert_existing_named_apfs_metadata_is_rejected \
    "existing named APFS recovery rejects an independently reported system image" \
    FAKE_NAMED_SYSTEM_IMAGE_VALUE=true
}

test_ambiguous_existing_named_apfs_volumes_fail_closed_twice() {
  local name="multiple exact-name APFS volumes fail closed without side effects on repeated runs"
  local volumes_root configured_volume source_mount first_mount second_mount
  local config marker before_hash after_hash status_one status_two
  prepare_test_environment
  volumes_root="$TEST_HOME/Volumes"
  configured_volume="$volumes_root/Stale Backup Path"
  source_mount="$volumes_root/TOSHIBA_4TB"
  first_mount="$volumes_root/GoogleDrive-Backup 2"
  second_mount="$volumes_root/GoogleDrive-Backup 3"
  config="$TEST_HOME/ambiguous-existing.conf"
  marker="$TEST_HOME/apfs-created"
  mkdir -p "$source_mount" "$first_mount" "$second_mount"
  printf '%s\n' 'source-canary' >"$source_mount/canary"
  printf '%s\n' 'first-canary' >"$first_mount/canary"
  printf '%s\n' 'second-canary' >"$second_mount/canary"
  cat >"$config" <<CONFIG
GDRIVE_BACKUP_TARGET=apfs
GDRIVE_BACKUP_VOLUME='$configured_volume'
GDRIVE_BACKUP_VOLUME_NAME=GoogleDrive-Backup
GDRIVE_BACKUP_VOLUME_UUID=
GDRIVE_BACKUP_AUTO_CREATE_VOLUME=1
CONFIG
  before_hash="$(/usr/bin/shasum "$config" "$source_mount/canary" "$first_mount/canary" "$second_mount/canary")"

  run_backup \
    GDRIVE_BACKUP_CONFIG="$config" \
    GDRIVE_BACKUP_DEST_ROOT= \
    GDRIVE_BACKUP_VOLUMES_ROOT="$volumes_root" \
    GDRIVE_BACKUP_TRIGGER=setup \
    FAKE_APFS_CREATED_MARKER="$marker" \
    FAKE_CANDIDATE_MOUNT="$source_mount" \
    FAKE_EXISTING_APFS_UUID_1=cccccccc-cccc-cccc-cccc-cccccccccccc \
    FAKE_EXISTING_APFS_UUID_2=dddddddd-dddd-dddd-dddd-dddddddddddd \
    FAKE_CREATED_MOUNT="$volumes_root/Unexpected Created Volume" \
    FAKE_NEW_APFS_UUID=bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb \
    GDRIVE_BACKUP_APPROVE_VOLUME_CREATION=1
  status_one=$?
  run_backup \
    GDRIVE_BACKUP_CONFIG="$config" \
    GDRIVE_BACKUP_DEST_ROOT= \
    GDRIVE_BACKUP_VOLUMES_ROOT="$volumes_root" \
    GDRIVE_BACKUP_TRIGGER=setup \
    FAKE_APFS_CREATED_MARKER="$marker" \
    FAKE_CANDIDATE_MOUNT="$source_mount" \
    FAKE_EXISTING_APFS_UUID_1=cccccccc-cccc-cccc-cccc-cccccccccccc \
    FAKE_EXISTING_APFS_UUID_2=dddddddd-dddd-dddd-dddd-dddddddddddd \
    FAKE_CREATED_MOUNT="$volumes_root/Unexpected Created Volume" \
    FAKE_NEW_APFS_UUID=bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb \
    GDRIVE_BACKUP_APPROVE_VOLUME_CREATION=1
  status_two=$?
  after_hash="$(/usr/bin/shasum "$config" "$source_mount/canary" "$first_mount/canary" "$second_mount/canary")"

  if [[ "$status_one" == "69" && "$status_two" == "69" &&
        "$before_hash" == "$after_hash" && ! -s "$OSASCRIPT_LOG" ]] &&
    ! grep -Eq 'apfs (addVolume|delete|erase|partition|rename|unmount)' "$DISKUTIL_LOG" 2>/dev/null &&
    { [[ ! -e "$RCLONE_LOG" ]] || ! grep -Eq '^copy( |$)' "$RCLONE_LOG"; } &&
    grep -Fq 'Mehrere gleichnamige APFS-Volumes' "$TEST_HOME/backup.log" &&
    grep -Fq 'explizit' "$TEST_HOME/backup.log" &&
    grep -Fq 'nichts angelegt oder geloescht' "$TEST_HOME/backup.log"; then
    pass "$name"
  else
    fail "$name (statuses $status_one/$status_two)"
  fi
}

test_multiple_external_apfs_containers_fail_closed() {
  local name="multiple eligible external APFS containers abort instead of using mtime"
  local volumes_root configured_volume first_mount second_mount config marker
  local before_hash after_hash status
  prepare_test_environment
  volumes_root="$TEST_HOME/Volumes"
  configured_volume="$volumes_root/Stale Backup Path"
  first_mount="$volumes_root/FIRST_DISK"
  second_mount="$volumes_root/SECOND_DISK"
  config="$TEST_HOME/multiple-containers.conf"
  marker="$TEST_HOME/apfs-created"
  mkdir -p "$first_mount" "$second_mount"
  printf '%s\n' 'first-canary' >"$first_mount/canary"
  printf '%s\n' 'second-canary' >"$second_mount/canary"
  /usr/bin/touch -t 202001010000 "$first_mount"
  /usr/bin/touch -t 202501010000 "$second_mount"
  cat >"$config" <<CONFIG
GDRIVE_BACKUP_TARGET=apfs
GDRIVE_BACKUP_VOLUME='$configured_volume'
GDRIVE_BACKUP_VOLUME_NAME=GoogleDrive-Backup
GDRIVE_BACKUP_VOLUME_UUID=
GDRIVE_BACKUP_AUTO_CREATE_VOLUME=1
CONFIG
  before_hash="$(/usr/bin/shasum "$config" "$first_mount/canary" "$second_mount/canary")"

  run_backup \
    GDRIVE_BACKUP_CONFIG="$config" \
    GDRIVE_BACKUP_DEST_ROOT= \
    GDRIVE_BACKUP_VOLUMES_ROOT="$volumes_root" \
    GDRIVE_BACKUP_TRIGGER=setup \
    FAKE_CANDIDATE_MOUNT="$first_mount" \
    FAKE_CANDIDATE_CONTAINER=disk99 \
    FAKE_SECOND_CANDIDATE_MOUNT="$second_mount" \
    FAKE_SECOND_CANDIDATE_CONTAINER=disk100 \
    FAKE_EXISTING_APFS_UUID_1= \
    FAKE_APFS_CREATED_MARKER="$marker" \
    FAKE_CREATED_MOUNT="$volumes_root/Unexpected Created Volume" \
    FAKE_NEW_APFS_UUID=bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb \
    GDRIVE_BACKUP_APPROVE_VOLUME_CREATION=1
  status=$?
  after_hash="$(/usr/bin/shasum "$config" "$first_mount/canary" "$second_mount/canary")"

  if [[ "$status" == "69" && "$before_hash" == "$after_hash" &&
        ! -s "$OSASCRIPT_LOG" ]] &&
    ! grep -Eq 'apfs (addVolume|delete|erase|partition|rename|unmount)' "$DISKUTIL_LOG" 2>/dev/null &&
    { [[ ! -e "$RCLONE_LOG" ]] || ! grep -Eq '^copy( |$)' "$RCLONE_LOG"; } &&
    grep -Fq 'Mehrere geeignete externe APFS-Container' "$TEST_HOME/backup.log"; then
    pass "$name"
  else
    fail "$name (status $status)"
  fi
}

test_path_only_apfs_target_rejects_nonsetup_triggers() {
  local name="path-only APFS target cannot copy from schedule or manual triggers"
  local config before_hash after_hash schedule_status manual_status animation_app open_count
  prepare_test_environment
  mkdir -p "$VOLUME"
  config="$TEST_HOME/path-only-schedule.conf"
  cat >"$config" <<CONFIG
GDRIVE_BACKUP_TARGET=apfs
GDRIVE_BACKUP_VOLUME='$VOLUME'
GDRIVE_BACKUP_VOLUME_NAME=GoogleDrive-Backup
GDRIVE_BACKUP_VOLUME_UUID=
GDRIVE_BACKUP_AUTO_CREATE_VOLUME=1
CONFIG
  before_hash="$(/usr/bin/shasum "$config")"
  run_backup \
    GDRIVE_BACKUP_CONFIG="$config" \
    GDRIVE_BACKUP_TRIGGER=schedule \
    BACKUP_ASSUME_YES=1 \
    FAKE_MOUNT_POINT="$VOLUME" \
    FAKE_EXISTING_APFS_UUID_1=11111111-2222-3333-4444-555555555555
  schedule_status=$?
  after_hash="$(/usr/bin/shasum "$config")"
  schedule_safe=0
  if [[ "$schedule_status" == "69" && "$before_hash" == "$after_hash" &&
        ! -s "$OPEN_LOG" && ! -s "$OSASCRIPT_LOG" ]] &&
    { [[ ! -e "$RCLONE_LOG" ]] || ! grep -Eq '^copy( |$)' "$RCLONE_LOG"; }; then
    schedule_safe=1
  fi

  prepare_test_environment
  mkdir -p "$VOLUME"
  config="$TEST_HOME/path-only-manual.conf"
  animation_app="$TEST_HOME/Fake Confirmation.app"
  mkdir -p "$animation_app"
  cat >"$config" <<CONFIG
GDRIVE_BACKUP_TARGET=apfs
GDRIVE_BACKUP_VOLUME='$VOLUME'
GDRIVE_BACKUP_VOLUME_NAME=GoogleDrive-Backup
GDRIVE_BACKUP_VOLUME_UUID=
GDRIVE_BACKUP_AUTO_CREATE_VOLUME=1
CONFIG
  before_hash="$(/usr/bin/shasum "$config")"
  run_backup \
    GDRIVE_BACKUP_CONFIG="$config" \
    GDRIVE_BACKUP_TRIGGER=manual \
    GDRIVE_BACKUP_ANIMATION_APP="$animation_app" \
    GDRIVE_BACKUP_OPEN_BIN="$FAKE_BIN/open" \
    BACKUP_ASSUME_YES=1 \
    FAKE_MOUNT_POINT="$VOLUME" \
    FAKE_EXISTING_APFS_UUID_1=11111111-2222-3333-4444-555555555555
  manual_status=$?
  after_hash="$(/usr/bin/shasum "$config")"
  open_count="$(/usr/bin/grep -c '^' "$OPEN_LOG" 2>/dev/null || true)"

  if [[ "$schedule_safe" == "1" && "$manual_status" == "69" &&
        "$before_hash" == "$after_hash" && "$open_count" == "0" &&
        ! -s "$OSASCRIPT_LOG" ]] &&
    { [[ ! -e "$RCLONE_LOG" ]] || ! grep -Eq '^copy( |$)' "$RCLONE_LOG"; }; then
    pass "$name"
  else
    fail "$name (schedule $schedule_status/$schedule_safe, manual $manual_status, prompts $open_count)"
  fi
}

test_setup_path_only_apfs_binding_persists_uuid_and_reuses_it() {
  local name="setup path-only APFS binding persists UUID and reuses it without mutation"
  local config animation_app status_one status_two saved_volume saved_uuid copy_count add_count open_count
  prepare_test_environment
  mkdir -p "$VOLUME"
  animation_app="$TEST_HOME/Fake Confirmation.app"
  config="$TEST_HOME/manual-path-binding.conf"
  mkdir -p "$animation_app"
  cat >"$config" <<CONFIG
GDRIVE_BACKUP_TARGET=apfs
GDRIVE_BACKUP_VOLUME='$VOLUME'
GDRIVE_BACKUP_VOLUME_NAME=GoogleDrive-Backup
GDRIVE_BACKUP_VOLUME_UUID=
GDRIVE_BACKUP_AUTO_CREATE_VOLUME=1
CONFIG

  run_backup \
    GDRIVE_BACKUP_CONFIG="$config" \
    GDRIVE_BACKUP_TRIGGER=setup \
    GDRIVE_BACKUP_ANIMATION_APP="$animation_app" \
    GDRIVE_BACKUP_OPEN_BIN="$FAKE_BIN/open" \
    BACKUP_ASSUME_YES=1 \
    FAKE_CONFIRM_RESPONSE=yes \
    FAKE_MOUNT_POINT="$VOLUME" \
    FAKE_EXISTING_APFS_UUID_1=11111111-2222-3333-4444-555555555555
  status_one=$?
  run_backup \
    GDRIVE_BACKUP_CONFIG="$config" \
    GDRIVE_BACKUP_TRIGGER=manual \
    GDRIVE_BACKUP_ANIMATION_APP="$animation_app" \
    GDRIVE_BACKUP_OPEN_BIN="$FAKE_BIN/open" \
    BACKUP_ASSUME_YES=1 \
    FAKE_CONFIRM_RESPONSE=no \
    FAKE_MOUNT_POINT="$VOLUME" \
    FAKE_EXISTING_APFS_UUID_1=11111111-2222-3333-4444-555555555555
  status_two=$?
  saved_volume="$(/bin/bash -c 'source "$1"; printf "%s" "${GDRIVE_BACKUP_VOLUME:-}"' _ "$config")"
  saved_uuid="$(/bin/bash -c 'source "$1"; printf "%s" "${GDRIVE_BACKUP_VOLUME_UUID:-}"' _ "$config")"
  copy_count="$(grep -Fc "$VOLUME/My Drive" "$RCLONE_LOG" 2>/dev/null || true)"
  add_count="$(grep -Fc 'apfs addVolume' "$DISKUTIL_LOG" 2>/dev/null || true)"
  open_count="$(/usr/bin/grep -c '^' "$OPEN_LOG" 2>/dev/null || true)"

  if [[ "$status_one" == "0" && "$status_two" == "0" &&
        "$saved_volume" == "$VOLUME" &&
        "$saved_uuid" == "11111111-2222-3333-4444-555555555555" &&
        "$copy_count" == "2" && "$add_count" == "0" && "$open_count" == "1" ]]; then
    pass "$name"
  else
    fail "$name (statuses $status_one/$status_two, uuid $saved_uuid, copies/add/prompts $copy_count/$add_count/$open_count)"
  fi
}

test_setup_path_only_apfs_binding_rejects_duplicate_exact_names() {
  local name="setup path-only APFS binding rejects duplicate exact-name UUIDs"
  local config animation_app before_hash after_hash status
  prepare_test_environment
  mkdir -p "$VOLUME"
  animation_app="$TEST_HOME/Fake Confirmation.app"
  config="$TEST_HOME/duplicate-path-binding.conf"
  mkdir -p "$animation_app"
  cat >"$config" <<CONFIG
GDRIVE_BACKUP_TARGET=apfs
GDRIVE_BACKUP_VOLUME='$VOLUME'
GDRIVE_BACKUP_VOLUME_NAME=GoogleDrive-Backup
GDRIVE_BACKUP_VOLUME_UUID=
GDRIVE_BACKUP_AUTO_CREATE_VOLUME=1
CONFIG
  before_hash="$(/usr/bin/shasum "$config")"
  run_backup \
    GDRIVE_BACKUP_CONFIG="$config" \
    GDRIVE_BACKUP_TRIGGER=setup \
    GDRIVE_BACKUP_ANIMATION_APP="$animation_app" \
    GDRIVE_BACKUP_OPEN_BIN="$FAKE_BIN/open" \
    FAKE_CONFIRM_RESPONSE=yes \
    FAKE_MOUNT_POINT="$VOLUME" \
    FAKE_EXISTING_APFS_UUID_1=11111111-2222-3333-4444-555555555555 \
    FAKE_EXISTING_APFS_UUID_2=dddddddd-dddd-dddd-dddd-dddddddddddd
  status=$?
  after_hash="$(/usr/bin/shasum "$config")"

  if [[ "$status" == "69" && "$before_hash" == "$after_hash" &&
        ! -s "$OPEN_LOG" && ! -s "$OSASCRIPT_LOG" ]] &&
    ! grep -Fq 'apfs addVolume' "$DISKUTIL_LOG" 2>/dev/null &&
    { [[ ! -e "$RCLONE_LOG" ]] || ! grep -Eq '^copy( |$)' "$RCLONE_LOG"; }; then
    pass "$name"
  else
    fail "$name (status $status)"
  fi
}

test_nonmanual_apfs_creation_rejects_every_approval_source() {
  local name="every non-setup trigger rejects APFS creation before approval"
  local trigger expected_status status all_safe=1 details=""
  local volumes_root configured_volume source_mount config marker created_mount before_hash after_hash

  for trigger in manual schedule schedule-retry mount menu-bar-only unknown-trigger; do
    prepare_test_environment
    volumes_root="$TEST_HOME/Volumes"
    configured_volume="$volumes_root/Stale Backup Path"
    source_mount="$volumes_root/TOSHIBA_4TB"
    config="$TEST_HOME/nonmanual-create.conf"
    marker="$TEST_HOME/apfs-created"
    created_mount="$volumes_root/GoogleDrive-Backup"
    mkdir -p "$source_mount"
    cat >"$config" <<CONFIG
GDRIVE_BACKUP_TARGET=apfs
GDRIVE_BACKUP_VOLUME='$configured_volume'
GDRIVE_BACKUP_VOLUME_NAME=GoogleDrive-Backup
GDRIVE_BACKUP_VOLUME_UUID=
GDRIVE_BACKUP_AUTO_CREATE_VOLUME=1
GDRIVE_BACKUP_TRIGGER=setup
CONFIG
    before_hash="$(/usr/bin/shasum "$config")"

    run_backup \
      GDRIVE_BACKUP_CONFIG="$config" \
      GDRIVE_BACKUP_DEST_ROOT= \
      GDRIVE_BACKUP_VOLUMES_ROOT="$volumes_root" \
      GDRIVE_BACKUP_TRIGGER="$trigger" \
      GDRIVE_BACKUP_RETRY_ORIGIN_STARTED_AT=1757030400 \
      GDRIVE_BACKUP_RETRY_ATTEMPT=1 \
      GDRIVE_BACKUP_CONFIRM=1 \
      BACKUP_ASSUME_YES=1 \
      GDRIVE_BACKUP_APPROVE_VOLUME_CREATION=1 \
      FAKE_CANDIDATE_MOUNT="$source_mount" \
      FAKE_EXISTING_APFS_UUID_1= \
      FAKE_APFS_CREATED_MARKER="$marker" \
      FAKE_CREATED_MOUNT="$created_mount" \
      FAKE_NEW_APFS_UUID=bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb
    status=$?
    after_hash="$(/usr/bin/shasum "$config")"
    expected_status=69
    [[ "$trigger" == "mount" ]] && expected_status=0
    [[ "$trigger" == "menu-bar-only" || "$trigger" == "unknown-trigger" ]] && expected_status=64

    if [[ "$status" != "$expected_status" || "$before_hash" != "$after_hash" ||
          -e "$marker" || -s "$OPEN_LOG" || -s "$OSASCRIPT_LOG" ]] ||
       grep -Fq 'apfs addVolume' "$DISKUTIL_LOG" 2>/dev/null ||
       grep -Fq 'Warte auf Benutzerbestaetigung' "$TEST_HOME/backup.log" ||
       { [[ -e "$RCLONE_LOG" ]] && grep -Eq '^copy( |$)' "$RCLONE_LOG"; }; then
      all_safe=0
      details+=" $trigger:$status"
    fi
  done

  if [[ "$all_safe" == "1" ]]; then
    pass "$name"
  else
    fail "$name ($details)"
  fi
}

test_config_cannot_persist_apfs_creation_approval() {
  local name="config-contained APFS creation approval has no authority on repeated setup runs"
  local volumes_root configured_volume source_mount config marker created_mount animation_app
  local before_hash after_hash status_one status_two open_count
  prepare_test_environment
  volumes_root="$TEST_HOME/Volumes"
  configured_volume="$volumes_root/Stale Backup Path"
  source_mount="$volumes_root/TOSHIBA_4TB"
  config="$TEST_HOME/config-contained-approval.conf"
  marker="$TEST_HOME/apfs-created"
  created_mount="$volumes_root/GoogleDrive-Backup"
  animation_app="$TEST_HOME/Fake Confirmation.app"
  mkdir -p "$source_mount" "$animation_app"
  cat >"$config" <<CONFIG
GDRIVE_BACKUP_TARGET=apfs
GDRIVE_BACKUP_VOLUME='$configured_volume'
GDRIVE_BACKUP_VOLUME_NAME=GoogleDrive-Backup
GDRIVE_BACKUP_VOLUME_UUID=
GDRIVE_BACKUP_AUTO_CREATE_VOLUME=1
GDRIVE_BACKUP_TRIGGER=setup
GDRIVE_BACKUP_APPROVE_VOLUME_CREATION=1
CONFIG
  before_hash="$(/usr/bin/shasum "$config")"

  run_backup \
    GDRIVE_BACKUP_CONFIG="$config" \
    GDRIVE_BACKUP_DEST_ROOT= \
    GDRIVE_BACKUP_VOLUMES_ROOT="$volumes_root" \
    GDRIVE_BACKUP_TRIGGER=setup \
    GDRIVE_BACKUP_ANIMATION_APP="$animation_app" \
    GDRIVE_BACKUP_OPEN_BIN="$FAKE_BIN/open" \
    FAKE_CONFIRM_RESPONSE=no \
    FAKE_CANDIDATE_MOUNT="$source_mount" \
    FAKE_EXISTING_APFS_UUID_1= \
    FAKE_APFS_CREATED_MARKER="$marker" \
    FAKE_CREATED_MOUNT="$created_mount"
  status_one=$?
  run_backup \
    GDRIVE_BACKUP_CONFIG="$config" \
    GDRIVE_BACKUP_DEST_ROOT= \
    GDRIVE_BACKUP_VOLUMES_ROOT="$volumes_root" \
    GDRIVE_BACKUP_TRIGGER=setup \
    GDRIVE_BACKUP_ANIMATION_APP="$animation_app" \
    GDRIVE_BACKUP_OPEN_BIN="$FAKE_BIN/open" \
    FAKE_CONFIRM_RESPONSE=no \
    FAKE_CANDIDATE_MOUNT="$source_mount" \
    FAKE_EXISTING_APFS_UUID_1= \
    FAKE_APFS_CREATED_MARKER="$marker" \
    FAKE_CREATED_MOUNT="$created_mount"
  status_two=$?
  after_hash="$(/usr/bin/shasum "$config")"
  open_count="$(/usr/bin/grep -c '^' "$OPEN_LOG" 2>/dev/null || true)"

  if [[ "$status_one" == "69" && "$status_two" == "69" &&
        "$before_hash" == "$after_hash" && "$open_count" == "2" &&
        ! -e "$marker" && ! -s "$OSASCRIPT_LOG" ]] &&
    ! grep -Fq 'apfs addVolume' "$DISKUTIL_LOG" 2>/dev/null &&
    { [[ ! -e "$RCLONE_LOG" ]] || ! grep -Eq '^copy( |$)' "$RCLONE_LOG"; }; then
    pass "$name"
  else
    fail "$name (statuses $status_one/$status_two, prompts $open_count)"
  fi
}

test_process_apfs_creation_approval_is_one_invocation_only() {
  local name="process APFS creation approval works once and is absent on the next invocation"
  local volumes_root source_mount first_config second_config marker created_mount animation_app
  local first_status second_status add_count open_count
  prepare_test_environment
  volumes_root="$TEST_HOME/Volumes"
  source_mount="$volumes_root/TOSHIBA_4TB"
  first_config="$TEST_HOME/approved-once.conf"
  second_config="$TEST_HOME/no-approval-next.conf"
  marker="$TEST_HOME/apfs-created"
  created_mount="$volumes_root/GoogleDrive-Backup"
  animation_app="$TEST_HOME/Fake Confirmation.app"
  mkdir -p "$source_mount" "$animation_app"
  cat >"$first_config" <<CONFIG
GDRIVE_BACKUP_TARGET=apfs
GDRIVE_BACKUP_VOLUME='$volumes_root/First Stale Path'
GDRIVE_BACKUP_VOLUME_NAME=GoogleDrive-Backup
GDRIVE_BACKUP_VOLUME_UUID=
GDRIVE_BACKUP_AUTO_CREATE_VOLUME=1
CONFIG
  cat >"$second_config" <<CONFIG
GDRIVE_BACKUP_TARGET=apfs
GDRIVE_BACKUP_VOLUME='$volumes_root/Second Stale Path'
GDRIVE_BACKUP_VOLUME_NAME=SecondBackup
GDRIVE_BACKUP_VOLUME_UUID=
GDRIVE_BACKUP_AUTO_CREATE_VOLUME=1
CONFIG

  run_backup \
    GDRIVE_BACKUP_CONFIG="$first_config" \
    GDRIVE_BACKUP_DEST_ROOT= \
    GDRIVE_BACKUP_VOLUMES_ROOT="$volumes_root" \
    GDRIVE_BACKUP_TRIGGER=setup \
    GDRIVE_BACKUP_APPROVE_VOLUME_CREATION=1 \
    FAKE_CANDIDATE_MOUNT="$source_mount" \
    FAKE_EXISTING_APFS_UUID_1= \
    FAKE_APFS_CREATED_MARKER="$marker" \
    FAKE_CREATED_MOUNT="$created_mount" \
    FAKE_NEW_APFS_UUID=bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb
  first_status=$?
  run_backup \
    GDRIVE_BACKUP_CONFIG="$second_config" \
    GDRIVE_BACKUP_DEST_ROOT= \
    GDRIVE_BACKUP_VOLUMES_ROOT="$volumes_root" \
    GDRIVE_BACKUP_TRIGGER=setup \
    GDRIVE_BACKUP_ANIMATION_APP="$animation_app" \
    GDRIVE_BACKUP_OPEN_BIN="$FAKE_BIN/open" \
    FAKE_CONFIRM_RESPONSE=no \
    FAKE_CANDIDATE_MOUNT="$source_mount" \
    FAKE_EXISTING_APFS_UUID_1= \
    FAKE_APFS_CREATED_MARKER="$marker" \
    FAKE_CREATED_MOUNT="$created_mount" \
    FAKE_NEW_APFS_UUID=bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb \
    FAKE_CREATED_NAME=GoogleDrive-Backup
  second_status=$?
  add_count="$(grep -Fc 'apfs addVolume' "$DISKUTIL_LOG" 2>/dev/null || true)"
  open_count="$(/usr/bin/grep -c '^' "$OPEN_LOG" 2>/dev/null || true)"

  if [[ "$first_status" == "0" && "$second_status" == "69" &&
        "$add_count" == "1" && "$open_count" == "1" ]]; then
    pass "$name"
  else
    fail "$name (statuses $first_status/$second_status, add $add_count, prompts $open_count)"
  fi
}

test_setup_interactive_confirmation_can_create_apfs_volume() {
  local name="setup APFS creation requires and accepts interactive confirmation"
  local volumes_root configured_volume source_mount config marker created_mount animation_app
  local status add_count open_count
  prepare_test_environment
  volumes_root="$TEST_HOME/Volumes"
  configured_volume="$volumes_root/Stale Backup Path"
  source_mount="$volumes_root/TOSHIBA_4TB"
  config="$TEST_HOME/manual-confirmation.conf"
  marker="$TEST_HOME/apfs-created"
  created_mount="$volumes_root/GoogleDrive-Backup"
  animation_app="$TEST_HOME/Fake Confirmation.app"
  mkdir -p "$source_mount" "$animation_app"
  cat >"$config" <<CONFIG
GDRIVE_BACKUP_TARGET=apfs
GDRIVE_BACKUP_VOLUME='$configured_volume'
GDRIVE_BACKUP_VOLUME_NAME=GoogleDrive-Backup
GDRIVE_BACKUP_VOLUME_UUID=
GDRIVE_BACKUP_AUTO_CREATE_VOLUME=1
CONFIG

  run_backup \
    GDRIVE_BACKUP_CONFIG="$config" \
    GDRIVE_BACKUP_DEST_ROOT= \
    GDRIVE_BACKUP_VOLUMES_ROOT="$volumes_root" \
    GDRIVE_BACKUP_TRIGGER=setup \
    GDRIVE_BACKUP_ANIMATION_APP="$animation_app" \
    GDRIVE_BACKUP_OPEN_BIN="$FAKE_BIN/open" \
    BACKUP_ASSUME_YES=1 \
    FAKE_CONFIRM_RESPONSE=yes \
    FAKE_CANDIDATE_MOUNT="$source_mount" \
    FAKE_EXISTING_APFS_UUID_1= \
    FAKE_APFS_CREATED_MARKER="$marker" \
    FAKE_CREATED_MOUNT="$created_mount" \
    FAKE_NEW_APFS_UUID=bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb
  status=$?
  add_count="$(grep -Fc 'apfs addVolume' "$DISKUTIL_LOG" 2>/dev/null || true)"
  open_count="$(/usr/bin/grep -c '^' "$OPEN_LOG" 2>/dev/null || true)"

  if [[ "$status" == "0" && "$add_count" == "1" && "$open_count" == "1" ]]; then
    pass "$name"
  else
    fail "$name (status $status, add $add_count, prompts $open_count)"
  fi
}

test_invalid_process_apfs_creation_approval_is_rejected() {
  local name="invalid process APFS creation approval is rejected before disk access"
  local volumes_root configured_volume source_mount config marker created_mount animation_app status
  prepare_test_environment
  volumes_root="$TEST_HOME/Volumes"
  configured_volume="$volumes_root/Stale Backup Path"
  source_mount="$volumes_root/TOSHIBA_4TB"
  config="$TEST_HOME/invalid-approval.conf"
  marker="$TEST_HOME/apfs-created"
  created_mount="$volumes_root/GoogleDrive-Backup"
  animation_app="$TEST_HOME/Fake Confirmation.app"
  mkdir -p "$source_mount" "$animation_app"
  cat >"$config" <<CONFIG
GDRIVE_BACKUP_TARGET=apfs
GDRIVE_BACKUP_VOLUME='$configured_volume'
GDRIVE_BACKUP_VOLUME_NAME=GoogleDrive-Backup
GDRIVE_BACKUP_VOLUME_UUID=
GDRIVE_BACKUP_AUTO_CREATE_VOLUME=1
CONFIG

  run_backup \
    GDRIVE_BACKUP_CONFIG="$config" \
    GDRIVE_BACKUP_DEST_ROOT= \
    GDRIVE_BACKUP_VOLUMES_ROOT="$volumes_root" \
    GDRIVE_BACKUP_TRIGGER=setup \
    GDRIVE_BACKUP_APPROVE_VOLUME_CREATION=yes \
    GDRIVE_BACKUP_ANIMATION_APP="$animation_app" \
    GDRIVE_BACKUP_OPEN_BIN="$FAKE_BIN/open" \
    FAKE_CONFIRM_RESPONSE=yes \
    FAKE_CANDIDATE_MOUNT="$source_mount" \
    FAKE_EXISTING_APFS_UUID_1= \
    FAKE_APFS_CREATED_MARKER="$marker" \
    FAKE_CREATED_MOUNT="$created_mount"
  status=$?

  if [[ "$status" == "64" && ! -e "$marker" && ! -s "$DISKUTIL_LOG" &&
        ! -s "$OPEN_LOG" && ! -s "$OSASCRIPT_LOG" && ! -s "$RCLONE_LOG" ]]; then
    pass "$name"
  else
    fail "$name (status $status)"
  fi
}

test_apfs_creation_rechecks_inventory_after_confirmation() {
  local name="APFS creation recovers an exact-name volume that appears during confirmation"
  local volumes_root configured_volume source_mount config created_marker appeared_marker
  local created_mount appeared_mount animation_app status open_count saved_volume saved_uuid copy_count
  prepare_test_environment
  volumes_root="$TEST_HOME/Volumes"
  configured_volume="$volumes_root/Stale Backup Path"
  source_mount="$volumes_root/TOSHIBA_4TB"
  config="$TEST_HOME/confirmation-race.conf"
  created_marker="$TEST_HOME/apfs-created"
  appeared_marker="$TEST_HOME/apfs-appeared"
  created_mount="$volumes_root/Unexpected Created Volume"
  appeared_mount="$volumes_root/GoogleDrive-Backup 2"
  animation_app="$TEST_HOME/Fake Confirmation.app"
  mkdir -p "$source_mount" "$animation_app"
  printf '%s\n' 'source-canary' >"$source_mount/canary"
  cat >"$config" <<CONFIG
GDRIVE_BACKUP_TARGET=apfs
GDRIVE_BACKUP_VOLUME='$configured_volume'
GDRIVE_BACKUP_VOLUME_NAME=GoogleDrive-Backup
GDRIVE_BACKUP_VOLUME_UUID=
GDRIVE_BACKUP_AUTO_CREATE_VOLUME=1
CONFIG
  run_backup \
    GDRIVE_BACKUP_CONFIG="$config" \
    GDRIVE_BACKUP_DEST_ROOT= \
    GDRIVE_BACKUP_VOLUMES_ROOT="$volumes_root" \
    GDRIVE_BACKUP_TRIGGER=setup \
    GDRIVE_BACKUP_ANIMATION_APP="$animation_app" \
    GDRIVE_BACKUP_OPEN_BIN="$FAKE_BIN/open" \
    FAKE_CONFIRM_RESPONSE=yes \
    FAKE_CONFIRMATION_APPEAR_MARKER="$appeared_marker" \
    FAKE_CONFIRMATION_APPEAR_MOUNT="$appeared_mount" \
    FAKE_APFS_APPEARED_MARKER="$appeared_marker" \
    FAKE_APPEARED_APFS_UUID=cccccccc-cccc-cccc-cccc-cccccccccccc \
    FAKE_APPEARED_APFS_NAME=GoogleDrive-Backup \
    FAKE_NAMED_UUID=cccccccc-cccc-cccc-cccc-cccccccccccc \
    FAKE_NAMED_MOUNT="$appeared_mount" \
    FAKE_NAMED_CONTAINER=disk99 \
    FAKE_CANDIDATE_MOUNT="$source_mount" \
    FAKE_EXISTING_APFS_UUID_1= \
    FAKE_APFS_CREATED_MARKER="$created_marker" \
    FAKE_CREATED_MOUNT="$created_mount" \
    FAKE_NEW_APFS_UUID=bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb
  status=$?
  open_count="$(/usr/bin/grep -c '^' "$OPEN_LOG" 2>/dev/null || true)"
  saved_volume="$(/bin/bash -c 'source "$1"; printf "%s" "${GDRIVE_BACKUP_VOLUME:-}"' _ "$config")"
  saved_uuid="$(/bin/bash -c 'source "$1"; printf "%s" "${GDRIVE_BACKUP_VOLUME_UUID:-}"' _ "$config")"
  copy_count="$(grep -Fc "$appeared_mount/My Drive" "$RCLONE_LOG" 2>/dev/null || true)"

  if [[ "$status" == "0" && "$saved_volume" == "$appeared_mount" &&
        "$saved_uuid" == "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC" &&
        "$open_count" == "1" && -e "$appeared_marker" &&
        ! -e "$created_marker" && ! -s "$OSASCRIPT_LOG" ]] &&
    ! grep -Fq 'apfs addVolume' "$DISKUTIL_LOG" 2>/dev/null &&
    [[ "$copy_count" == "1" ]]; then
    pass "$name"
  else
    fail "$name (status $status, volume $saved_volume, uuid $saved_uuid, prompts/copies $open_count/$copy_count)"
  fi
}

test_apfs_creation_rejects_reused_source_identity_after_confirmation() {
  local name="APFS creation rejects a reused disk and container identifier after confirmation"
  local volumes_root configured_volume source_mount config created_marker created_mount
  local swap_marker animation_app before_hash after_hash status add_count
  prepare_test_environment
  volumes_root="$TEST_HOME/Volumes"
  configured_volume="$volumes_root/Stale Backup Path"
  source_mount="$volumes_root/TOSHIBA_4TB"
  config="$TEST_HOME/source-identity-confirmation-race.conf"
  created_marker="$TEST_HOME/apfs-created"
  created_mount="$volumes_root/Unexpected Created Volume"
  swap_marker="$TEST_HOME/setup-source-swapped"
  animation_app="$TEST_HOME/Fake Confirmation.app"
  mkdir -p "$source_mount" "$animation_app"
  printf '%s\n' 'source-canary' >"$source_mount/canary"
  cat >"$config" <<CONFIG
GDRIVE_BACKUP_TARGET=apfs
GDRIVE_BACKUP_VOLUME='$configured_volume'
GDRIVE_BACKUP_VOLUME_NAME=GoogleDrive-Backup
GDRIVE_BACKUP_VOLUME_UUID=
GDRIVE_BACKUP_AUTO_CREATE_VOLUME=1
CONFIG
  before_hash="$(/usr/bin/shasum "$config" "$source_mount/canary")"

  run_backup \
    GDRIVE_BACKUP_CONFIG="$config" \
    GDRIVE_BACKUP_DEST_ROOT= \
    GDRIVE_BACKUP_VOLUMES_ROOT="$volumes_root" \
    GDRIVE_BACKUP_TRIGGER=setup \
    GDRIVE_BACKUP_ANIMATION_APP="$animation_app" \
    GDRIVE_BACKUP_OPEN_BIN="$FAKE_BIN/open" \
    FAKE_CONFIRM_RESPONSE=yes \
    FAKE_CONFIRMATION_SOURCE_SWAP_MARKER="$swap_marker" \
    FAKE_SETUP_SOURCE_SWAP_MARKER="$swap_marker" \
    FAKE_CANDIDATE_MOUNT="$source_mount" \
    FAKE_EXISTING_APFS_UUID_1= \
    FAKE_APFS_CREATED_MARKER="$created_marker" \
    FAKE_CREATED_MOUNT="$created_mount" \
    FAKE_NEW_APFS_UUID=bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb
  status=$?
  after_hash="$(/usr/bin/shasum "$config" "$source_mount/canary")"
  add_count="$(grep -Fc 'apfs addVolume' "$DISKUTIL_LOG" 2>/dev/null || true)"

  if [[ "$status" == "69" && "$before_hash" == "$after_hash" &&
        "$add_count" == "0" && -e "$swap_marker" &&
        ! -e "$created_marker" ]] &&
    { [[ ! -e "$RCLONE_LOG" ]] || ! grep -Eq '^(config|backend|copy)( |$)' "$RCLONE_LOG"; } &&
    grep -Fqi 'identitaet' "$TEST_HOME/backup.log" &&
    grep -Fqi 'geaendert' "$TEST_HOME/backup.log"; then
    pass "$name"
  else
    fail "$name (status $status, add $add_count)"
  fi
}

test_auto_created_apfs_volume_uses_the_new_uuid_and_mount_path() {
  local name="auto-created APFS volume persists and uses only the newly added UUID"
  local volumes_root configured_volume created_mount created_real candidate_mount
  local config marker status_one status_two saved_volume saved_uuid saved_destination uuid_lines add_count copy_count
  prepare_test_environment
  volumes_root="$TEST_HOME/Volumes"
  configured_volume="$volumes_root/Missing Configured Backup"
  created_mount="$volumes_root/GoogleDrive-Backup 2"
  candidate_mount="$volumes_root/TOSHIBA_4TB"
  config="$TEST_HOME/auto-create.conf"
  marker="$TEST_HOME/apfs-created"
  mkdir -p "$volumes_root/GoogleDrive-Backup" "$candidate_mount"
  cat >"$config" <<CONFIG
GDRIVE_BACKUP_TARGET=apfs
GDRIVE_BACKUP_VOLUME='$configured_volume'
GDRIVE_BACKUP_VOLUME_NAME=GoogleDrive-Backup
GDRIVE_BACKUP_VOLUME_UUID=
GDRIVE_BACKUP_DEST_ROOT='$configured_volume/nested/backup'
GDRIVE_BACKUP_AUTO_CREATE_VOLUME=1
CONFIG

  run_backup \
    GDRIVE_BACKUP_CONFIG="$config" \
    GDRIVE_BACKUP_DEST_ROOT= \
    GDRIVE_BACKUP_VOLUMES_ROOT="$volumes_root" \
    GDRIVE_BACKUP_TRIGGER=setup \
    FAKE_APFS_CREATED_MARKER="$marker" \
    FAKE_CANDIDATE_MOUNT="$candidate_mount" \
    FAKE_EXISTING_APFS_UUID_1= \
    FAKE_CREATED_MOUNT="$created_mount" \
    FAKE_NEW_APFS_UUID=bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb \
    GDRIVE_BACKUP_APPROVE_VOLUME_CREATION=1
  status_one=$?
  run_backup \
    GDRIVE_BACKUP_CONFIG="$config" \
    GDRIVE_BACKUP_DEST_ROOT= \
    GDRIVE_BACKUP_VOLUMES_ROOT="$volumes_root" \
    GDRIVE_BACKUP_TRIGGER=manual \
    FAKE_APFS_CREATED_MARKER="$marker" \
    FAKE_CANDIDATE_MOUNT="$candidate_mount" \
    FAKE_EXISTING_APFS_UUID_1= \
    FAKE_CREATED_MOUNT="$created_mount" \
    FAKE_NEW_APFS_UUID=bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb
  status_two=$?
  created_real="$(cd "$created_mount" 2>/dev/null && /bin/pwd -P || true)"
  saved_volume="$(/bin/bash -c 'source "$1"; printf "%s" "${GDRIVE_BACKUP_VOLUME:-}"' _ "$config")"
  saved_uuid="$(/bin/bash -c 'source "$1"; printf "%s" "${GDRIVE_BACKUP_VOLUME_UUID:-}"' _ "$config")"
  saved_destination="$(/bin/bash -c 'source "$1"; printf "%s" "${GDRIVE_BACKUP_DEST_ROOT:-}"' _ "$config")"
  uuid_lines="$(grep -Ec '^GDRIVE_BACKUP_VOLUME_UUID=' "$config")"
  add_count="$(grep -Fc 'apfs addVolume' "$DISKUTIL_LOG" 2>/dev/null || true)"
  copy_count="$(grep -Fc "$created_real/nested/backup/My Drive" "$RCLONE_LOG" 2>/dev/null || true)"

  if [[ "$status_one" == "0" && "$status_two" == "0" && -n "$created_real" &&
        "$saved_volume" == "$created_real" &&
        "$saved_uuid" == "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB" &&
        "$saved_destination" == "$created_real/nested/backup" &&
        "$uuid_lines" == "1" && "$add_count" == "1" && "$copy_count" == "2" ]] &&
    ! grep -Fq "$volumes_root/GoogleDrive-Backup/My Drive" "$RCLONE_LOG"; then
    pass "$name"
  else
    fail "$name (statuses $status_one/$status_two, volume $saved_volume, destination $saved_destination, uuid $saved_uuid, lines/add/copies $uuid_lines/$add_count/$copy_count)"
  fi
}

test_auto_created_apfs_volume_rejects_ambiguous_new_uuids() {
  local name="auto-created APFS volume fails closed when more than one new UUID appears"
  local volumes_root configured_volume created_mount candidate_mount
  local config marker status
  prepare_test_environment
  volumes_root="$TEST_HOME/Volumes"
  configured_volume="$volumes_root/Missing Configured Backup"
  created_mount="$volumes_root/GoogleDrive-Backup 2"
  candidate_mount="$volumes_root/TOSHIBA_4TB"
  config="$TEST_HOME/ambiguous-auto-create.conf"
  marker="$TEST_HOME/apfs-created"
  mkdir -p "$volumes_root/GoogleDrive-Backup" "$candidate_mount"
  cat >"$config" <<CONFIG
GDRIVE_BACKUP_TARGET=apfs
GDRIVE_BACKUP_VOLUME='$configured_volume'
GDRIVE_BACKUP_VOLUME_NAME=GoogleDrive-Backup
GDRIVE_BACKUP_VOLUME_UUID=
GDRIVE_BACKUP_AUTO_CREATE_VOLUME=1
CONFIG

  run_backup \
    GDRIVE_BACKUP_CONFIG="$config" \
    GDRIVE_BACKUP_DEST_ROOT= \
    GDRIVE_BACKUP_VOLUMES_ROOT="$volumes_root" \
    GDRIVE_BACKUP_TRIGGER=setup \
    FAKE_APFS_CREATED_MARKER="$marker" \
    FAKE_CANDIDATE_MOUNT="$candidate_mount" \
    FAKE_EXISTING_APFS_UUID_1= \
    FAKE_CREATED_MOUNT="$created_mount" \
    FAKE_NEW_APFS_UUID=bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb \
    FAKE_SECOND_NEW_APFS_UUID=dddddddd-dddd-dddd-dddd-dddddddddddd \
    GDRIVE_BACKUP_APPROVE_VOLUME_CREATION=1
  status=$?

  if [[ "$status" == "69" ]] &&
    grep -Fxq 'GDRIVE_BACKUP_VOLUME_UUID=' "$config" &&
    { [[ ! -e "$RCLONE_LOG" ]] || ! grep -Eq '^(config|backend|copy)( |$)' "$RCLONE_LOG"; }; then
    pass "$name"
  else
    fail "$name (status $status)"
  fi
}

test_auto_created_apfs_volume_recovers_privileged_partial_failure() {
  local name="auto-created APFS volume detects a privileged partial success before retrying"
  local volumes_root configured_volume created_mount candidate_mount
  local config marker status saved_uuid
  prepare_test_environment
  volumes_root="$TEST_HOME/Volumes"
  configured_volume="$volumes_root/Missing Configured Backup"
  created_mount="$volumes_root/GoogleDrive-Backup 2"
  candidate_mount="$volumes_root/TOSHIBA_4TB"
  config="$TEST_HOME/privileged-partial-auto-create.conf"
  marker="$TEST_HOME/apfs-created"
  mkdir -p "$volumes_root/GoogleDrive-Backup" "$candidate_mount"
  cat >"$config" <<CONFIG
GDRIVE_BACKUP_TARGET=apfs
GDRIVE_BACKUP_VOLUME='$configured_volume'
GDRIVE_BACKUP_VOLUME_NAME=GoogleDrive-Backup
GDRIVE_BACKUP_VOLUME_UUID=
GDRIVE_BACKUP_AUTO_CREATE_VOLUME=1
CONFIG

  run_backup \
    GDRIVE_BACKUP_CONFIG="$config" \
    GDRIVE_BACKUP_DEST_ROOT= \
    GDRIVE_BACKUP_VOLUMES_ROOT="$volumes_root" \
    GDRIVE_BACKUP_TRIGGER=setup \
    FAKE_APFS_CREATED_MARKER="$marker" \
    FAKE_CANDIDATE_MOUNT="$candidate_mount" \
    FAKE_EXISTING_APFS_UUID_1= \
    FAKE_CREATED_MOUNT="$created_mount" \
    FAKE_NEW_APFS_UUID=bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb \
    FAKE_UNPRIVILEGED_ADD_STATUS=1 \
    FAKE_PRIVILEGED_ADD_STATUS=1 \
    GDRIVE_BACKUP_APPROVE_VOLUME_CREATION=1
  status=$?
  saved_uuid="$(/bin/bash -c 'source "$1"; printf "%s" "${GDRIVE_BACKUP_VOLUME_UUID:-}"' _ "$config")"

  if [[ "$status" == "0" &&
        "$saved_uuid" == "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB" &&
        "$(/usr/bin/wc -l <"$OSASCRIPT_LOG" | /usr/bin/tr -d '[:space:]')" == "1" ]]; then
    pass "$name"
  else
    fail "$name (status $status, uuid $saved_uuid)"
  fi
}

test_auto_created_apfs_volume_guards_inside_privileged_phase() {
  local name="APFS creation guards again after authorization before privileged add"
  local volumes_root configured_volume candidate_mount appeared_mount config
  local created_marker appeared_marker output canary first_status second_status
  local saved_uuid add_count copy_count
  prepare_test_environment
  volumes_root="$TEST_HOME/Volumes"
  configured_volume="$volumes_root/Missing Configured Backup"
  candidate_mount="$volumes_root/TOSHIBA_4TB"
  appeared_mount="$volumes_root/GoogleDrive-Backup 2"
  config="$TEST_HOME/pre-admin-race.conf"
  created_marker="$TEST_HOME/apfs-created"
  appeared_marker="$TEST_HOME/apfs-appeared"
  output="$TEST_HOME/admin-race-output.log"
  canary="$candidate_mount/canary"
  mkdir -p "$candidate_mount"
  printf '%s\n' 'source-canary' >"$canary"
  cat >"$config" <<CONFIG
GDRIVE_BACKUP_TARGET=apfs
GDRIVE_BACKUP_VOLUME='$configured_volume'
GDRIVE_BACKUP_VOLUME_NAME=GoogleDrive-Backup
GDRIVE_BACKUP_VOLUME_UUID=
GDRIVE_BACKUP_AUTO_CREATE_VOLUME=1
CONFIG

  run_backup \
    GDRIVE_BACKUP_CONFIG="$config" \
    GDRIVE_BACKUP_DEST_ROOT= \
    GDRIVE_BACKUP_VOLUMES_ROOT="$volumes_root" \
    GDRIVE_BACKUP_TRIGGER=setup \
    GDRIVE_BACKUP_APPROVE_VOLUME_CREATION=1 \
    FAKE_CANDIDATE_MOUNT="$candidate_mount" \
    FAKE_EXISTING_APFS_UUID_1= \
    FAKE_UNPRIVILEGED_ADD_STATUS=1 \
    FAKE_ADMIN_PHASE_APPEAR_MARKER="$appeared_marker" \
    FAKE_ADMIN_PHASE_APPEAR_MOUNT="$appeared_mount" \
    FAKE_APFS_APPEARED_MARKER="$appeared_marker" \
    FAKE_APPEARED_APFS_UUID=feedface-feed-4ace-8bad-c0ffeec0ffee \
    FAKE_NAMED_UUID=feedface-feed-4ace-8bad-c0ffeec0ffee \
    FAKE_NAMED_MOUNT="$appeared_mount" \
    FAKE_NAMED_CONTAINER=disk99 \
    FAKE_APFS_CREATED_MARKER="$created_marker" \
    FAKE_CREATED_MOUNT="$volumes_root/Unexpected Created Volume" \
    >"$output" 2>&1
  first_status=$?
  run_backup \
    GDRIVE_BACKUP_CONFIG="$config" \
    GDRIVE_BACKUP_DEST_ROOT= \
    GDRIVE_BACKUP_VOLUMES_ROOT="$volumes_root" \
    GDRIVE_BACKUP_TRIGGER=manual \
    FAKE_NAMED_UUID=feedface-feed-4ace-8bad-c0ffeec0ffee \
    FAKE_NAMED_MOUNT="$appeared_mount" \
    FAKE_NAMED_CONTAINER=disk99 \
    >>"$output" 2>&1
  second_status=$?
  saved_uuid="$(/bin/bash -c 'source "$1"; printf "%s" "${GDRIVE_BACKUP_VOLUME_UUID:-}"' _ "$config")"
  add_count="$(grep -Fc 'apfs addVolume' "$DISKUTIL_LOG" 2>/dev/null || true)"
  copy_count="$(grep -Fc "$appeared_mount/My Drive" "$RCLONE_LOG" 2>/dev/null || true)"

  if [[ "$first_status" == "0" && "$second_status" == "0" &&
        "$saved_uuid" == "FEEDFACE-FEED-4ACE-8BAD-C0FFEEC0FFEE" &&
        "$add_count" == "1" && "$copy_count" == "2" &&
        -e "$appeared_marker" && ! -e "$created_marker" &&
        "$(<"$canary")" == "source-canary" &&
        "$(/usr/bin/wc -l <"$OSASCRIPT_LOG" | /usr/bin/tr -d '[:space:]')" == "1" ]] &&
    ! grep -Fqi 'feedface-feed-4ace-8bad-c0ffeec0ffee' \
      "$output" "$TEST_HOME/backup.log" "$OSASCRIPT_LOG"; then
    pass "$name"
  else
    fail "$name (statuses $first_status/$second_status, uuid $saved_uuid, add/copies $add_count/$copy_count)"
  fi
}

test_privileged_apfs_guard_rejects_reused_source_identity() {
  local name="privileged APFS guard rejects a reused disk and container identifier"
  local volumes_root configured_volume candidate_mount config
  local created_marker swap_marker before_hash after_hash status add_count
  prepare_test_environment
  volumes_root="$TEST_HOME/Volumes"
  configured_volume="$volumes_root/Missing Configured Backup"
  candidate_mount="$volumes_root/TOSHIBA_4TB"
  config="$TEST_HOME/admin-source-identity-race.conf"
  created_marker="$TEST_HOME/apfs-created"
  swap_marker="$TEST_HOME/setup-source-swapped"
  mkdir -p "$candidate_mount"
  printf '%s\n' 'source-canary' >"$candidate_mount/canary"
  cat >"$config" <<CONFIG
GDRIVE_BACKUP_TARGET=apfs
GDRIVE_BACKUP_VOLUME='$configured_volume'
GDRIVE_BACKUP_VOLUME_NAME=GoogleDrive-Backup
GDRIVE_BACKUP_VOLUME_UUID=
GDRIVE_BACKUP_AUTO_CREATE_VOLUME=1
CONFIG
  before_hash="$(/usr/bin/shasum "$config" "$candidate_mount/canary")"

  run_backup \
    GDRIVE_BACKUP_CONFIG="$config" \
    GDRIVE_BACKUP_DEST_ROOT= \
    GDRIVE_BACKUP_VOLUMES_ROOT="$volumes_root" \
    GDRIVE_BACKUP_TRIGGER=setup \
    GDRIVE_BACKUP_APPROVE_VOLUME_CREATION=1 \
    FAKE_CANDIDATE_MOUNT="$candidate_mount" \
    FAKE_EXISTING_APFS_UUID_1= \
    FAKE_UNPRIVILEGED_ADD_STATUS=1 \
    FAKE_ADMIN_PHASE_SOURCE_SWAP_MARKER="$swap_marker" \
    FAKE_SETUP_SOURCE_SWAP_MARKER="$swap_marker" \
    FAKE_APFS_CREATED_MARKER="$created_marker" \
    FAKE_CREATED_MOUNT="$volumes_root/Unexpected Created Volume" \
    FAKE_NEW_APFS_UUID=bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb
  status=$?
  after_hash="$(/usr/bin/shasum "$config" "$candidate_mount/canary")"
  add_count="$(grep -Fc 'apfs addVolume' "$DISKUTIL_LOG" 2>/dev/null || true)"

  if [[ "$status" == "69" && "$before_hash" == "$after_hash" &&
        "$add_count" == "1" && -e "$swap_marker" &&
        ! -e "$created_marker" &&
        "$(/usr/bin/wc -l <"$OSASCRIPT_LOG" | /usr/bin/tr -d '[:space:]')" == "1" ]] &&
    { [[ ! -e "$RCLONE_LOG" ]] || ! grep -Eq '^(config|backend|copy)( |$)' "$RCLONE_LOG"; } &&
    grep -Fqi 'identitaet' "$TEST_HOME/backup.log" &&
    grep -Fqi 'geaendert' "$TEST_HOME/backup.log"; then
    pass "$name"
  else
    fail "$name (status $status, add $add_count)"
  fi
}

test_privileged_apfs_guard_rejects_numeric_family_race() {
  local name="privileged APFS guard blocks a numeric-family volume appearing during authorization"
  local volumes_root configured_volume candidate_mount appeared_mount config
  local created_marker appeared_marker before_hash after_hash status add_count
  prepare_test_environment
  volumes_root="$TEST_HOME/Volumes"
  configured_volume="$volumes_root/Missing Configured Backup"
  candidate_mount="$volumes_root/TOSHIBA_4TB"
  appeared_mount="$volumes_root/GoogleDrive-Backup 1"
  config="$TEST_HOME/admin-family-race.conf"
  created_marker="$TEST_HOME/apfs-created"
  appeared_marker="$TEST_HOME/apfs-appeared"
  mkdir -p "$candidate_mount"
  printf '%s\n' 'source-canary' >"$candidate_mount/canary"
  cat >"$config" <<CONFIG
GDRIVE_BACKUP_TARGET=apfs
GDRIVE_BACKUP_VOLUME='$configured_volume'
GDRIVE_BACKUP_VOLUME_NAME=GoogleDrive-Backup
GDRIVE_BACKUP_VOLUME_UUID=
GDRIVE_BACKUP_AUTO_CREATE_VOLUME=1
CONFIG
  before_hash="$(/usr/bin/shasum "$config" "$candidate_mount/canary")"

  run_backup \
    GDRIVE_BACKUP_CONFIG="$config" \
    GDRIVE_BACKUP_DEST_ROOT= \
    GDRIVE_BACKUP_VOLUMES_ROOT="$volumes_root" \
    GDRIVE_BACKUP_TRIGGER=setup \
    GDRIVE_BACKUP_APPROVE_VOLUME_CREATION=1 \
    FAKE_CANDIDATE_MOUNT="$candidate_mount" \
    FAKE_EXISTING_APFS_UUID_1= \
    FAKE_UNPRIVILEGED_ADD_STATUS=1 \
    FAKE_ADMIN_PHASE_APPEAR_MARKER="$appeared_marker" \
    FAKE_ADMIN_PHASE_APPEAR_MOUNT="$appeared_mount" \
    FAKE_APFS_APPEARED_MARKER="$appeared_marker" \
    FAKE_APPEARED_APFS_UUID=cccccccc-cccc-4ccc-8ccc-cccccccccccc \
    FAKE_APPEARED_APFS_NAME='GoogleDrive-Backup 1' \
    FAKE_APFS_CREATED_MARKER="$created_marker" \
    FAKE_CREATED_MOUNT="$volumes_root/Unexpected Created Volume"
  status=$?
  after_hash="$(/usr/bin/shasum "$config" "$candidate_mount/canary")"
  add_count="$(grep -Fc 'apfs addVolume' "$DISKUTIL_LOG" 2>/dev/null || true)"

  if [[ "$status" == "69" && "$before_hash" == "$after_hash" &&
        "$add_count" == "1" && -e "$appeared_marker" &&
        ! -e "$created_marker" &&
        "$(/usr/bin/wc -l <"$OSASCRIPT_LOG" | /usr/bin/tr -d '[:space:]')" == "1" ]] &&
    { [[ ! -e "$RCLONE_LOG" ]] || ! grep -Eq '^(config|backend|copy)( |$)' "$RCLONE_LOG"; } &&
    grep -Fqi 'numerisch' "$TEST_HOME/backup.log" &&
    grep -Fqi 'explizit' "$TEST_HOME/backup.log"; then
    pass "$name"
  else
    fail "$name (status $status, add $add_count)"
  fi
}

test_saved_apfs_uuid_blocks_retention_after_copy_swap() {
  local name="saved APFS UUID is revalidated before retention starts"
  local version marker status
  prepare_test_environment
  mkdir -p "$VOLUME"
  version="2020-01-01T00-00-00+0000-00000000-0000-4000-8000-000000000101"
  mkdir -p "$VOLUME/.gdrive-versions/$version"
  marker="$TEST_HOME/retention-start-swap"

  run_backup \
    GDRIVE_BACKUP_ENCRYPTION=none \
    GDRIVE_BACKUP_VOLUME_UUID=11111111-2222-3333-4444-555555555555 \
    FAKE_MOUNT_POINT="$VOLUME" \
    FAKE_RETENTION_START_SWAP_MARKER="$marker" \
    FAKE_IDENTITY_SWAP_MARKER="$marker" \
    GDRIVE_BACKUP_VERSIONING=1 \
    GDRIVE_BACKUP_RETENTION=1
  status=$?

  if [[ "$status" == "1" && -d "$VOLUME/.gdrive-versions/$version" &&
        ! -e "$RETENTION_TRASH/$version" ]]; then
    pass "$name"
  else
    fail "$name (status $status)"
  fi
}

test_saved_apfs_uuid_revalidates_before_each_retention_trash() {
  local name="saved APFS UUID is revalidated before every retention trash operation"
  local first second marker status remaining trashed
  prepare_test_environment
  mkdir -p "$VOLUME"
  first="2020-01-01T00-00-00+0000-00000000-0000-4000-8000-000000000201"
  second="2020-01-02T00-00-00+0000-00000000-0000-4000-8000-000000000202"
  mkdir -p "$VOLUME/.gdrive-versions/$first" "$VOLUME/.gdrive-versions/$second"
  marker="$TEST_HOME/retention-trash-swap"

  run_backup \
    GDRIVE_BACKUP_ENCRYPTION=none \
    GDRIVE_BACKUP_VOLUME_UUID=11111111-2222-3333-4444-555555555555 \
    FAKE_MOUNT_POINT="$VOLUME" \
    FAKE_RETENTION_SWAP_AFTER_TRASH="$marker" \
    FAKE_IDENTITY_SWAP_MARKER="$marker" \
    GDRIVE_BACKUP_VERSIONING=1 \
    GDRIVE_BACKUP_RETENTION=1
  status=$?
  remaining="$(/usr/bin/find "$VOLUME/.gdrive-versions" -mindepth 1 -maxdepth 1 -type d ! -name .retention-trash | /usr/bin/wc -l | /usr/bin/tr -d '[:space:]')"
  trashed="$(/usr/bin/find "$RETENTION_TRASH" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | /usr/bin/wc -l | /usr/bin/tr -d '[:space:]')"

  if [[ "$status" == "1" && "$remaining" == "1" && "$trashed" == "1" ]]; then
    pass "$name"
  else
    fail "$name (status $status, remaining $remaining, trashed $trashed)"
  fi
}

test_saved_apfs_uuid_blocks_retention_fallback_move_after_swap() {
  local name="saved APFS UUID blocks a retention fallback move after trash failure"
  local version marker status
  prepare_test_environment
  mkdir -p "$VOLUME"
  version="2020-01-03T00-00-00+0000-00000000-0000-4000-8000-000000000301"
  mkdir -p "$VOLUME/.gdrive-versions/$version"
  marker="$TEST_HOME/retention-fallback-swap"

  run_backup \
    GDRIVE_BACKUP_ENCRYPTION=none \
    GDRIVE_BACKUP_VOLUME_UUID=11111111-2222-3333-4444-555555555555 \
    FAKE_MOUNT_POINT="$VOLUME" \
    FAKE_RETENTION_SWAP_ON_TRASH_FAILURE="$marker" \
    FAKE_IDENTITY_SWAP_MARKER="$marker" \
    GDRIVE_BACKUP_VERSIONING=1 \
    GDRIVE_BACKUP_RETENTION=1
  status=$?

  if [[ "$status" == "1" && -d "$VOLUME/.gdrive-versions/$version" &&
        ! -e "$VOLUME/.gdrive-versions/.retention-trash/$version" ]]; then
    pass "$name"
  else
    fail "$name (status $status)"
  fi
}

test_saved_apfs_uuid_blocks_collision_publication_after_archive_copy_swap() {
  local name="saved APFS UUID blocks collision publication after an archive copy swap"
  local marker once_marker status manifest_count published_object_count
  prepare_test_environment
  mkdir -p "$VOLUME"
  marker="$TEST_HOME/collision-copy-swap"
  once_marker="$TEST_HOME/collision-notice-seen"

  run_backup \
    GDRIVE_BACKUP_ENCRYPTION=none \
    GDRIVE_BACKUP_VOLUME_UUID=11111111-2222-3333-4444-555555555555 \
    FAKE_MOUNT_POINT="$VOLUME" \
    FAKE_JQ_USE_SYSTEM=1 \
    FAKE_RCLONE_COPY_OUTPUT='NOTICE: image.heic: Duplicate object found in source - ignoring' \
    FAKE_RCLONE_COPY_ONCE_MARKER="$once_marker" \
    FAKE_RCLONE_COLLISION_QUERY_JSON='[
      {"id":"file-id-a","name":"image.heic","mimeType":"image/heic","parents":["root-id"]},
      {"id":"file-id-b","name":"image.heic","mimeType":"image/heic","parents":["root-id"]}
    ]' \
    FAKE_COLLISION_IDENTITY_SWAP_MARKER="$marker" \
    FAKE_IDENTITY_SWAP_MARKER="$marker"
  status=$?
  manifest_count="$(/usr/bin/find "$VOLUME/.gdrive-collisions" -name '*.json' -type f \
    2>/dev/null | /usr/bin/wc -l | /usr/bin/tr -d '[:space:]')"
  published_object_count="$(/usr/bin/find "$VOLUME/.gdrive-collisions" \
    -path '*/objects/*' -mindepth 1 -maxdepth 5 -type d ! -name '.*' \
    2>/dev/null | /usr/bin/wc -l | /usr/bin/tr -d '[:space:]')"

  if [[ "$status" == "1" && -e "$marker" && "$manifest_count" == "0" &&
        "$published_object_count" == "0" ]]; then
    pass "$name"
  else
    fail "$name (status $status, manifests $manifest_count, published objects $published_object_count)"
  fi
}

test_collision_archive_scans_inventory_once_then_only_mutation_scopes() {
  local name="collision archive scans global inventory once and only affected paths during publication"
  local trace_env validation_log volume_real collision_root versions_root
  local scope_hash object_key_a object_key_b once_marker status
  local collision_full version_history_full version_run_full
  local collision_scoped version_scoped
  prepare_test_environment
  mkdir -p "$VOLUME"
  volume_real="$(cd "$VOLUME" && /bin/pwd -P)"
  collision_root="${volume_real%/}/.gdrive-collisions"
  versions_root="${volume_real%/}/.gdrive-versions"
  scope_hash="$(printf '%s' 'My Drive' | /usr/bin/shasum -a 256)"
  scope_hash="${scope_hash%% *}"
  object_key_a="$(printf '%s' $'drive-object-id\037file-id-a' |
    /usr/bin/shasum -a 256)"
  object_key_a="${object_key_a%% *}"
  object_key_b="$(printf '%s' $'drive-object-id\037file-id-b' |
    /usr/bin/shasum -a 256)"
  object_key_b="${object_key_b%% *}"
  mkdir -p \
    "$collision_root/$scope_hash/objects/$object_key_a" \
    "$collision_root/$scope_hash/objects/$object_key_b"
  : >"$collision_root/$scope_hash/objects/$object_key_a/old.dat"
  : >"$collision_root/$scope_hash/objects/$object_key_b/old.dat"

  trace_env="$TEST_HOME/trace-collision-apfs-validation.sh"
  validation_log="$TEST_HOME/collision-apfs-validations.log"
  once_marker="$TEST_HOME/collision-performance-notice-seen"
  cat >"$trace_env" <<'SH'
if [[ -n "${FAKE_APFS_VALIDATION_LOG:-}" ]]; then
  set -T
  trap 'if [[ "${FUNCNAME[0]:-}" == "validate_configured_apfs_tree" ]]; then
          printf "%s\n" "${1:-}" >>"$FAKE_APFS_VALIDATION_LOG"
        fi' RETURN
fi
SH

  run_backup \
    GDRIVE_BACKUP_ENCRYPTION=none \
    GDRIVE_BACKUP_VOLUME_UUID=11111111-2222-3333-4444-555555555555 \
    FAKE_MOUNT_POINT="$VOLUME" \
    FAKE_JQ_USE_SYSTEM=1 \
    FAKE_RCLONE_COPY_OUTPUT='NOTICE: image.heic: Duplicate object found in source - ignoring' \
    FAKE_RCLONE_COPY_ONCE_MARKER="$once_marker" \
    FAKE_RCLONE_COLLISION_QUERY_JSON='[
      {"id":"file-id-a","name":"image.heic","mimeType":"image/heic","parents":["root-id"]},
      {"id":"file-id-b","name":"image.heic","mimeType":"image/heic","parents":["root-id"]}
    ]' \
    GDRIVE_BACKUP_VERSIONING=1 \
    GDRIVE_BACKUP_RETENTION=0 \
    BASH_ENV="$trace_env" \
    FAKE_APFS_VALIDATION_LOG="$validation_log"
  status=$?

  collision_full="$(/usr/bin/grep -Fxc "$collision_root" \
    "$validation_log" 2>/dev/null || true)"
  version_history_full="$(/usr/bin/grep -Fxc "$versions_root" \
    "$validation_log" 2>/dev/null || true)"
  version_run_full="$(/usr/bin/awk -v prefix="$versions_root/" '
    index($0, prefix) == 1 {
      suffix = substr($0, length(prefix) + 1)
      if (suffix !~ /\//) count++
    }
    END { print count + 0 }
  ' "$validation_log" 2>/dev/null)"
  collision_scoped="$(/usr/bin/awk -v prefix="$collision_root/" '
    index($0, prefix) == 1 { count++ }
    END { print count + 0 }
  ' "$validation_log" 2>/dev/null)"
  version_scoped="$(/usr/bin/awk -v prefix="$versions_root/" '
    index($0, prefix) == 1 {
      suffix = substr($0, length(prefix) + 1)
      if (suffix ~ /\//) count++
    }
    END { print count + 0 }
  ' "$validation_log" 2>/dev/null)"

  if [[ "$status" == "0" && "$collision_full" == "1" &&
        "$version_history_full" == "1" && "$version_run_full" == "0" &&
        "$collision_scoped" -gt 0 && "$version_scoped" -gt 0 ]]; then
    pass "$name"
  else
    fail "$name (status $status, collision full/scoped $collision_full/$collision_scoped, version history/run/scoped $version_history_full/$version_run_full/$version_scoped)"
  fi
}

test_invalid_encryption_mode_is_rejected
test_apfs_encryption_mode_rejects_nas_target
test_saved_apfs_uuid_resolves_the_current_mount_path
test_saved_apfs_uuid_mismatch_fails_closed
test_saved_apfs_uuid_accepts_a_mounted_apfs_image
test_malformed_saved_apfs_uuid_is_rejected
test_saved_apfs_uuid_rejects_parent_component_escape
test_saved_apfs_uuid_rejects_destination_symlink_escape
test_saved_apfs_uuid_rejects_in_volume_destination_symlink
test_saved_apfs_uuid_accepts_nested_destination
test_saved_apfs_uuid_revalidates_before_creating_destination
test_saved_apfs_uuid_rejects_copy_child_symlink_escape
test_saved_apfs_uuid_rejects_deep_tree_symlink_escape
test_saved_apfs_uuid_scans_history_once_and_current_version_paths_per_copy
test_apfs_tree_device_validation_streams_its_inventory
test_existing_named_apfs_volume_is_recovered_idempotently
test_numeric_family_apfs_volumes_block_setup_creation
test_apfs_inventory_rejects_duplicate_requested_container_among_foreign_containers
test_apfs_inventory_ignores_exact_name_in_foreign_container
test_exact_name_apfs_inventory_rejects_missing_uuid
test_exact_name_apfs_inventory_rejects_malformed_uuid
test_existing_named_apfs_volume_rejects_info_name_mismatch
test_existing_named_apfs_volume_rejects_info_container_mismatch
test_existing_named_apfs_volume_rejects_internal_media
test_existing_named_apfs_volume_rejects_read_only_media
test_existing_named_apfs_volume_rejects_system_image
test_ambiguous_existing_named_apfs_volumes_fail_closed_twice
test_multiple_external_apfs_containers_fail_closed
test_path_only_apfs_target_rejects_nonsetup_triggers
test_setup_path_only_apfs_binding_persists_uuid_and_reuses_it
test_setup_path_only_apfs_binding_rejects_duplicate_exact_names
test_nonmanual_apfs_creation_rejects_every_approval_source
test_config_cannot_persist_apfs_creation_approval
test_process_apfs_creation_approval_is_one_invocation_only
test_setup_interactive_confirmation_can_create_apfs_volume
test_invalid_process_apfs_creation_approval_is_rejected
test_apfs_creation_rechecks_inventory_after_confirmation
test_apfs_creation_rejects_reused_source_identity_after_confirmation
test_auto_created_apfs_volume_uses_the_new_uuid_and_mount_path
test_auto_created_apfs_volume_rejects_ambiguous_new_uuids
test_auto_created_apfs_volume_recovers_privileged_partial_failure
test_auto_created_apfs_volume_guards_inside_privileged_phase
test_privileged_apfs_guard_rejects_reused_source_identity
test_privileged_apfs_guard_rejects_numeric_family_race
test_saved_apfs_uuid_blocks_retention_after_copy_swap
test_saved_apfs_uuid_revalidates_before_each_retention_trash
test_saved_apfs_uuid_blocks_retention_fallback_move_after_swap
test_saved_apfs_uuid_blocks_collision_publication_after_archive_copy_swap
test_collision_archive_scans_inventory_once_then_only_mutation_scopes
test_encrypted_mode_never_auto_creates_plain_volume
test_unencrypted_apfs_volume_is_rejected
test_encrypted_apfs_volume_is_accepted
test_default_mode_preserves_uuid_bound_targets
test_unreadable_encryption_metadata_is_rejected
test_mismatched_mount_point_is_rejected
test_destination_symlink_escape_is_rejected
test_dry_run_checks_encryption
test_deep_destination_symlink_is_rejected
test_volume_identity_is_revalidated_after_confirmation
test_rclone_crypt_requires_a_safe_remote_name
test_rclone_crypt_configuration_fails_closed
test_rclone_crypt_copy_and_versions_share_one_remote
test_rclone_crypt_retention_merges_then_trashes_physical_ciphertext
test_rclone_crypt_rejects_physical_symlink_redirection
test_rclone_crypt_revalidates_policy_before_copy
test_rclone_crypt_keeps_local_log_owner_only

if (( failures > 0 )); then
  printf '%s encryption test(s) failed.\n' "$failures"
  exit 1
fi

printf '%s\n' 'All backup encryption tests passed.'
