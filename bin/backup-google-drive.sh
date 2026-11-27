#!/bin/bash
set -uo pipefail

if [[ "${1:-}" == "--capabilities" ]]; then
  printf '%s\n' 'adhoc-target-v1' 'run-history-v1'
  exit 0
fi

# Homebrew copies come first so they keep their own updates; the tools the
# installer ships in /usr/local/libexec are the fallback for Macs without
# Homebrew.
BUNDLED_TOOLS_BIN="/usr/local/libexec/gdrive-tiger-backup/bin"
PATH="${GDRIVE_BACKUP_PATH:-/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$BUNDLED_TOOLS_BIN}"
export PATH

# Everything that needs macOS-only tools (diskutil, ioreg, plutil, osascript,
# BSD stat and find, the /Volumes layout) lives in a platform file so the core
# below stays portable. The installed engine reads it from the installer's
# libexec directory; a checkout reads lib/ next to bin/. The location is fixed
# before any configuration is read, so configuration cannot load other code.
case "$(/usr/bin/uname -s 2>/dev/null)" in
  Darwin) GDT_PLATFORM="macos" ;;
  Linux) GDT_PLATFORM="linux" ;;
  *)
    printf 'FEHLER: Dieses Betriebssystem wird noch nicht unterstuetzt.\n' >&2
    exit 69
    ;;
esac
GDT_ENGINE_DIR="${BASH_SOURCE[0]%/*}"
[[ "$GDT_ENGINE_DIR" != "${BASH_SOURCE[0]}" ]] || GDT_ENGINE_DIR="."
if [[ "$GDT_ENGINE_DIR" == "/usr/local/bin" ]]; then
  GDT_LIB_DIR="/usr/local/libexec/gdrive-tiger-backup/lib"
else
  GDT_LIB_DIR="$GDT_ENGINE_DIR/../lib"
fi
GDT_PLATFORM_FILE="$GDT_LIB_DIR/platform-$GDT_PLATFORM.sh"
if [[ ! -f "$GDT_PLATFORM_FILE" || -L "$GDT_PLATFORM_FILE" ]]; then
  printf 'FEHLER: Plattformdatei fehlt: %s\n' "$GDT_PLATFORM_FILE" >&2
  exit 69
fi
# shellcheck source=lib/platform-macos.sh
source "$GDT_PLATFORM_FILE"

if [[ -z "${HOME:-}" ]]; then
  HOME="$(platform_home_directory)"
  export HOME
fi

if [[ -z "${HOME:-}" || ! -d "$HOME" ]]; then
  printf 'FEHLER: HOME konnte nicht ermittelt werden.\n' >&2
  exit 78
fi

lowercase() {
  printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]'
}

nas_host_from_url() {
  local url="${1%%\?*}"
  local without_scheme host
  without_scheme="${url#*://}"
  [[ "$without_scheme" != "$url" ]] || return 0
  without_scheme="${without_scheme#*@}"
  host="${without_scheme%%/*}"
  printf '%s' "$(lowercase "$host")"
}

# These values are one-shot process capabilities. Capture them before the
# shell config is loaded so persistent configuration cannot grant setup rights.
_GDT_PROCESS_TRIGGER_SET=0
_GDT_PROCESS_TRIGGER_VALUE=""
if [[ "${GDRIVE_BACKUP_TRIGGER+x}" == "x" ]]; then
  _GDT_PROCESS_TRIGGER_SET=1
  _GDT_PROCESS_TRIGGER_VALUE="$GDRIVE_BACKUP_TRIGGER"
fi
_GDT_PROCESS_VOLUME_APPROVAL_SET=0
_GDT_PROCESS_VOLUME_APPROVAL_VALUE=""
if [[ "${GDRIVE_BACKUP_APPROVE_VOLUME_CREATION+x}" == "x" ]]; then
  _GDT_PROCESS_VOLUME_APPROVAL_SET=1
  _GDT_PROCESS_VOLUME_APPROVAL_VALUE="$GDRIVE_BACKUP_APPROVE_VOLUME_CREATION"
fi
_GDT_PROCESS_RUN_TARGET_SET=0
_GDT_PROCESS_RUN_TARGET_VALUE=""
if [[ "${GDRIVE_BACKUP_RUN_TARGET+x}" == "x" ]]; then
  _GDT_PROCESS_RUN_TARGET_SET=1
  _GDT_PROCESS_RUN_TARGET_VALUE="$GDRIVE_BACKUP_RUN_TARGET"
fi
_GDT_PROCESS_RUN_VOLUME_UUID_SET=0
_GDT_PROCESS_RUN_VOLUME_UUID_VALUE=""
if [[ "${GDRIVE_BACKUP_RUN_VOLUME_UUID+x}" == "x" ]]; then
  _GDT_PROCESS_RUN_VOLUME_UUID_SET=1
  _GDT_PROCESS_RUN_VOLUME_UUID_VALUE="$GDRIVE_BACKUP_RUN_VOLUME_UUID"
fi
_GDT_PROCESS_SUMMARY_STATE_FILE_SET=0
_GDT_PROCESS_SUMMARY_STATE_FILE_VALUE=""
if [[ "${GDRIVE_BACKUP_SUMMARY_STATE_FILE+x}" == "x" ]]; then
  _GDT_PROCESS_SUMMARY_STATE_FILE_SET=1
  _GDT_PROCESS_SUMMARY_STATE_FILE_VALUE="$GDRIVE_BACKUP_SUMMARY_STATE_FILE"
fi
_GDT_PROCESS_PROGRESS_STATE_FILE_SET=0
_GDT_PROCESS_PROGRESS_STATE_FILE_VALUE=""
if [[ "${GDRIVE_BACKUP_PROGRESS_STATE_FILE+x}" == "x" ]]; then
  _GDT_PROCESS_PROGRESS_STATE_FILE_SET=1
  _GDT_PROCESS_PROGRESS_STATE_FILE_VALUE="$GDRIVE_BACKUP_PROGRESS_STATE_FILE"
fi
readonly _GDT_PROCESS_TRIGGER_SET _GDT_PROCESS_TRIGGER_VALUE
readonly _GDT_PROCESS_VOLUME_APPROVAL_SET _GDT_PROCESS_VOLUME_APPROVAL_VALUE
readonly _GDT_PROCESS_RUN_TARGET_SET _GDT_PROCESS_RUN_TARGET_VALUE
readonly _GDT_PROCESS_RUN_VOLUME_UUID_SET _GDT_PROCESS_RUN_VOLUME_UUID_VALUE
readonly _GDT_PROCESS_SUMMARY_STATE_FILE_SET _GDT_PROCESS_SUMMARY_STATE_FILE_VALUE
readonly _GDT_PROCESS_PROGRESS_STATE_FILE_SET _GDT_PROCESS_PROGRESS_STATE_FILE_VALUE

CONFIG_DIR="${GDRIVE_BACKUP_CONFIG_DIR:-$HOME/.config/gdrive-tiger-backup}"
LEGACY_CONFIG_FILE="$CONFIG_DIR/config"
CONFIG_FILE="${GDRIVE_BACKUP_CONFIG:-}"
ACTIVE_PROFILE_ID=""
if [[ -z "$CONFIG_FILE" ]]; then
  CONFIG_FILE="$LEGACY_CONFIG_FILE"
  ACTIVE_PROFILE_FILE="$CONFIG_DIR/active-profile"
  if [[ -f "$ACTIVE_PROFILE_FILE" && ! -L "$ACTIVE_PROFILE_FILE" ]]; then
    profile_id="$(<"$ACTIVE_PROFILE_FILE")"
    profiles_dir="$CONFIG_DIR/profiles"
    if [[ "$profile_id" =~ ^[a-z0-9][a-z0-9-]{0,63}$ &&
          -d "$profiles_dir" && ! -L "$profiles_dir" ]]; then
      profile_config="$profiles_dir/$profile_id.conf"
      profile_id_matches=0
      if [[ -f "$profile_config" && ! -L "$profile_config" ]]; then
        while IFS= read -r profile_line || [[ -n "$profile_line" ]]; do
          case "$profile_line" in
            "GDRIVE_BACKUP_PROFILE_ID=$profile_id"|"GDRIVE_BACKUP_PROFILE_ID='$profile_id'"|"GDRIVE_BACKUP_PROFILE_ID=\"$profile_id\"")
              profile_id_matches=1
              break
              ;;
          esac
        done <"$profile_config"
      fi
      if [[ "$profile_id_matches" == "1" ]]; then
        CONFIG_FILE="$profile_config"
        ACTIVE_PROFILE_ID="$profile_id"
      fi
    fi
  fi
fi
if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
fi

if [[ "$_GDT_PROCESS_TRIGGER_SET" == "1" ]]; then
  BACKUP_TRIGGER="$_GDT_PROCESS_TRIGGER_VALUE"
else
  BACKUP_TRIGGER="manual"
fi
if [[ "$_GDT_PROCESS_VOLUME_APPROVAL_SET" == "1" ]]; then
  APPROVE_VOLUME_CREATION="$_GDT_PROCESS_VOLUME_APPROVAL_VALUE"
else
  APPROVE_VOLUME_CREATION=0
fi
RUN_TARGET_OVERRIDE=""
RUN_TARGET_OVERRIDE_ERROR=""
if [[ "$_GDT_PROCESS_RUN_TARGET_SET" == "1" ]]; then
  case "$_GDT_PROCESS_RUN_TARGET_VALUE" in
    apfs|nas) RUN_TARGET_OVERRIDE="$_GDT_PROCESS_RUN_TARGET_VALUE" ;;
    *) RUN_TARGET_OVERRIDE_ERROR="invalid_value" ;;
  esac
  if [[ "$BACKUP_TRIGGER" != "manual" ]]; then
    RUN_TARGET_OVERRIDE_ERROR="nonmanual_trigger"
  fi
fi
case "$BACKUP_TRIGGER" in
  manual|setup|schedule|schedule-retry|mount) ;;
  *)
    printf 'FEHLER: Unbekannter Backup-Ausloeser: %s\n' "$BACKUP_TRIGGER" >&2
    exit 64
    ;;
esac
case "$APPROVE_VOLUME_CREATION" in
  0|1) ;;
  *)
    printf 'FEHLER: GDRIVE_BACKUP_APPROVE_VOLUME_CREATION muss 0 oder 1 sein.\n' >&2
    exit 64
    ;;
esac
AUTOMATIC_BACKUPS_PAUSED="${GDRIVE_BACKUP_PAUSED:-0}"
NAS_START_ON_MOUNT="${GDRIVE_BACKUP_NAS_START_ON_MOUNT:-0}"
if [[ -n "$RUN_TARGET_OVERRIDE" ]]; then
  REQUESTED_BACKUP_TARGET="$RUN_TARGET_OVERRIDE"
elif [[ "$BACKUP_TRIGGER" == "mount" && "$NAS_START_ON_MOUNT" != "1" ]]; then
  REQUESTED_BACKUP_TARGET="apfs"
else
  REQUESTED_BACKUP_TARGET="${GDRIVE_BACKUP_TARGET:-apfs}"
fi
BACKUP_TARGET="$(lowercase "$REQUESTED_BACKUP_TARGET")"
case "$BACKUP_TARGET" in
  apfs|volume|disk) BACKUP_TARGET="apfs" ;;
  nas|network|smb|afp|nfs) BACKUP_TARGET="nas" ;;
  *) BACKUP_TARGET="invalid" ;;
esac

BACKUP_VOLUME_NAME="${GDRIVE_BACKUP_VOLUME_NAME:-GoogleDrive-Backup}"
BACKUP_VOLUME_UUID="${GDRIVE_BACKUP_VOLUME_UUID:-}"
VOLUMES_ROOT="${GDRIVE_BACKUP_VOLUMES_ROOT:-$PLATFORM_VOLUMES_ROOT}"
NAS_URL="${GDRIVE_BACKUP_NAS_URL:-}"
NAS_MOUNT="${GDRIVE_BACKUP_NAS_MOUNT:-}"
NAS_SUBDIR="${GDRIVE_BACKUP_NAS_SUBDIR:-GoogleDrive-Backup}"
if [[ "$BACKUP_TARGET" == "nas" ]]; then
  if [[ -z "$NAS_MOUNT" && -n "$NAS_URL" ]]; then
    NAS_MOUNT="$(nas_mount_from_url "$NAS_URL")"
  fi
  if [[ -z "$NAS_MOUNT" && -n "$NAS_URL" ]]; then
    NAS_MOUNT="$(find_nas_mount_for_url "$NAS_URL")"
  fi
  VOLUME="$NAS_MOUNT"
  if [[ -n "$NAS_MOUNT" ]]; then
    DEST_ROOT="${GDRIVE_BACKUP_DEST_ROOT:-${NAS_MOUNT%/}/$NAS_SUBDIR}"
  else
    DEST_ROOT="${GDRIVE_BACKUP_DEST_ROOT:-}"
  fi
else
  VOLUME="${GDRIVE_BACKUP_VOLUME:-$PLATFORM_VOLUMES_ROOT/$BACKUP_VOLUME_NAME}"
  DEST_ROOT="${GDRIVE_BACKUP_DEST_ROOT:-$VOLUME}"
fi
CONFIGURED_APFS_VOLUME="$VOLUME"
CONFIGURED_APFS_DEST_ROOT="$DEST_ROOT"
REMOTE="${RCLONE_REMOTE:-gdrive}"
REMOTE="${REMOTE%:}"

LOG="${GDRIVE_BACKUP_LOG:-$HOME/Library/Logs/gdrive-backup.log}"
LOCK="${GDRIVE_BACKUP_LOCK:-$HOME/Library/Logs/gdrive-backup.lock}"
MOUNT_SETTLE_SECONDS="${MOUNT_SETTLE_SECONDS:-5}"
NAS_READY_TIMEOUT_SECONDS="${GDRIVE_BACKUP_NAS_READY_TIMEOUT_SECONDS:-60}"
NAS_MOUNT_TIMEOUT_SECONDS="${GDRIVE_BACKUP_NAS_MOUNT_TIMEOUT_SECONDS:-90}"
ANIMATION_APP="${GDRIVE_BACKUP_ANIMATION_APP:-/Applications/GDrive Backup Tiger.app}"
if [[ ! -d "$ANIMATION_APP" && -d "$HOME/Applications/GDrive Backup Tiger.app" ]]; then
  ANIMATION_APP="$HOME/Applications/GDrive Backup Tiger.app"
fi
NAS_MOUNT_HELPER="${GDRIVE_BACKUP_NAS_MOUNT_HELPER:-$ANIMATION_APP/Contents/MacOS/GDriveBackupTiger}"
ANIMATION_SENTINEL=""
PROGRESS_FILE=""
RUN_STATE_FILE="${GDRIVE_BACKUP_RUN_STATE_FILE:-}"
RUN_STATE_IS_TEMP=0
RUN_STATE_OVERRIDE=""
RUN_OUTCOME="failure"
RUN_STATE_REASON=""
RUN_STATE_SIGNAL=""
RETRY_ORIGIN_STARTED_AT="${GDRIVE_BACKUP_RETRY_ORIGIN_STARTED_AT:-}"
RETRY_ATTEMPT="${GDRIVE_BACKUP_RETRY_ATTEMPT:-}"
if [[ "$BACKUP_TRIGGER" != "schedule-retry" ]]; then
  RETRY_ORIGIN_STARTED_AT=""
  RETRY_ATTEMPT=""
fi
if [[ "$_GDT_PROCESS_SUMMARY_STATE_FILE_SET" == "1" ]]; then
  SUMMARY_STATE_FILE="$_GDT_PROCESS_SUMMARY_STATE_FILE_VALUE"
elif [[ -n "${GDRIVE_BACKUP_SUMMARY_STATE_FILE:-}" ]]; then
  SUMMARY_STATE_FILE="$GDRIVE_BACKUP_SUMMARY_STATE_FILE"
elif [[ "$GDT_PLATFORM" == "linux" && -n "$ACTIVE_PROFILE_ID" ]]; then
  SUMMARY_STATE_FILE="$HOME/.local/state/gdrive-tiger-backup/profiles/$ACTIVE_PROFILE_ID/last-run.status"
elif [[ "$GDT_PLATFORM" == "linux" ]]; then
  SUMMARY_STATE_FILE="$HOME/.local/state/gdrive-tiger-backup/last-run.status"
elif [[ -n "$ACTIVE_PROFILE_ID" ]]; then
  SUMMARY_STATE_FILE="$HOME/Library/Application Support/GDrive Backup Tiger/profiles/$ACTIVE_PROFILE_ID/last-run.status"
else
  SUMMARY_STATE_FILE="$HOME/Library/Application Support/GDrive Backup Tiger/last-run.status"
fi
# One history for all profiles and one-off runs, so every destination's
# completed backups can be listed side by side.
if [[ -n "${GDRIVE_BACKUP_HISTORY_FILE:-}" ]]; then
  RUN_HISTORY_FILE="$GDRIVE_BACKUP_HISTORY_FILE"
elif [[ "$GDT_PLATFORM" == "linux" ]]; then
  RUN_HISTORY_FILE="$HOME/.local/state/gdrive-tiger-backup/run-history.tsv"
else
  RUN_HISTORY_FILE="$HOME/Library/Application Support/GDrive Backup Tiger/run-history.tsv"
fi
RUN_HISTORY_MAX_LINES=1000
if [[ "$_GDT_PROCESS_PROGRESS_STATE_FILE_SET" == "1" ]]; then
  DURABLE_PROGRESS_FILE="$_GDT_PROCESS_PROGRESS_STATE_FILE_VALUE"
else
  DURABLE_PROGRESS_FILE="${GDRIVE_BACKUP_PROGRESS_STATE_FILE:-}"
fi
PROGRESS_PROFILE_ID="${GDRIVE_BACKUP_PROFILE_ID:-${ACTIVE_PROFILE_ID:-legacy}}"
DURABLE_PROGRESS_OWNED=0
RUN_STARTED_AT=0
OPEN_BIN="${GDRIVE_BACKUP_OPEN_BIN:-/usr/bin/open}"
CONFIRM_BACKUP="${GDRIVE_BACKUP_CONFIRM:-1}"
AUTO_CREATE_VOLUME="${GDRIVE_BACKUP_AUTO_CREATE_VOLUME:-1}"
BACKUP_LANG="${GDRIVE_BACKUP_LANG:-auto}"
VERSIONING="${GDRIVE_BACKUP_VERSIONING-1}"
VERSIONS_SUBDIR="${GDRIVE_BACKUP_VERSIONS_SUBDIR-.gdrive-versions}"
RETENTION="${GDRIVE_BACKUP_RETENTION-1}"
RETENTION_TRASH_BIN="${GDRIVE_BACKUP_RETENTION_TRASH_BIN-}"
# Days a retired version state stays in the quarantine folder before it is
# deleted for good. 0 keeps quarantined states forever.
RETENTION_PURGE_DAYS="${GDRIVE_BACKUP_RETENTION_PURGE_DAYS-7}"
# Abort before copying when the destination has less free space than this.
MIN_FREE_MB="${GDRIVE_BACKUP_MIN_FREE_MB-1024}"
SCHEDULE_MODE="$(lowercase "${GDRIVE_BACKUP_SCHEDULE:-manual}")"
# A daily schedule opens one window per day at this hour. The launch agent
# fires hourly; later firings only catch up a window without a success.
DAILY_WINDOW_HOUR=20
DAILY_WINDOW_MAX_ATTEMPTS=4
DAILY_WINDOW_STARTED_AT=""
DAILY_WINDOW_ATTEMPTS=""
DAILY_RUN_KIND=""
CATCHUP_QUIET=0
# Scratch files of one run live in a private directory that is removed when
# the run ends, including after a signal. Files the progress window reads
# after the engine has exited stay in the base directory.
BASE_TMPDIR="${TMPDIR:-/tmp}"
BASE_TMPDIR="${BASE_TMPDIR%/}"
RUN_TMPDIR=""
# Upper bound for one small file operation on a network share.
NAS_FILE_TIMEOUT_SECONDS="${GDRIVE_BACKUP_NAS_FILE_TIMEOUT_SECONDS-60}"
if [[ ! "$NAS_FILE_TIMEOUT_SECONDS" =~ ^[1-9][0-9]{0,3}$ ]]; then
  NAS_FILE_TIMEOUT_SECONDS=60
fi
# Upper bound for the directory listing that detects a missing macOS privacy
# grant for network volumes before any backup work starts.
NAS_PRIVACY_PROBE_TIMEOUT_SECONDS="${GDRIVE_BACKUP_NAS_PRIVACY_PROBE_TIMEOUT_SECONDS-30}"
if [[ ! "$NAS_PRIVACY_PROBE_TIMEOUT_SECONDS" =~ ^[1-9][0-9]{0,3}$ ]]; then
  NAS_PRIVACY_PROBE_TIMEOUT_SECONDS=30
fi
# A run that writes nothing to its log for this long is treated as hung and
# terminated, so it cannot hold the backup lock indefinitely. 0 disables it.
STALL_SECONDS="${GDRIVE_BACKUP_STALL_SECONDS-2700}"
if [[ ! "$STALL_SECONDS" =~ ^[0-9]{1,6}$ ]]; then
  STALL_SECONDS=2700
fi
STALL_SECONDS=$((10#$STALL_SECONDS))
STALL_WATCHDOG_PID=""
NAS_WATCHDOG_PID=""
ENCRYPTION="$(lowercase "${GDRIVE_BACKUP_ENCRYPTION-none}")"
CRYPT_REMOTE="${GDRIVE_BACKUP_CRYPT_REMOTE-}"
DISKUTIL_BIN="${GDRIVE_BACKUP_DISKUTIL-/usr/sbin/diskutil}"
IOREG_BIN="${GDRIVE_BACKUP_IOREG-/usr/sbin/ioreg}"
OSASCRIPT_BIN="${GDRIVE_BACKUP_OSASCRIPT-/usr/bin/osascript}"
MOUNT_BIN="${GDRIVE_BACKUP_MOUNT_BIN-/sbin/mount}"
CMP_BIN="${GDRIVE_BACKUP_CMP_BIN-/usr/bin/cmp}"
LS_BIN="${GDRIVE_BACKUP_LS_BIN-/bin/ls}"
PERL_BIN="${GDRIVE_BACKUP_PERL_BIN-/usr/bin/perl}"
ENCRYPTED_VOLUME_REAL=""
ENCRYPTED_VOLUME_DEVICE=""
ENCRYPTED_VOLUME_UUID=""
ENCRYPTED_VOLUME_IDENTIFIER=""
APFS_VOLUME_REAL=""
APFS_VOLUME_DEVICE=""
APFS_VOLUME_UUID=""
APFS_VOLUME_IDENTIFIER=""
VALIDATED_APFS_VOLUME_PLIST=""
CREATED_APFS_VOLUME_UUID=""
SETUP_SOURCE_VOLUME_UUID=""
SETUP_SOURCE_CONTAINER_UUID=""
SETUP_SOURCE_PHYSICAL_STORE_UUIDS=""
SETUP_TARGET_EXACT_COUNT=0
SETUP_TARGET_EXACT_UUIDS=""
SETUP_TARGET_NUMERIC_COUNT=0
VERSION_RUN_ID=""
TARGET_APPROVED=0
COPY_INDEX=0
COPY_TOTAL=0
LAST_RCLONE_COLLISION_REPORT=""
NAS_NAME_CODEC_ENABLED=0
NAS_NAME_CODEC_MANIFEST=".gdrive-name-codec"
NAS_NAME_CODEC_PREFIX="__gdt0__"
NAS_NAME_CODEC_DOT_BIN_PREFIX="__gdt0__dotbin_"
# The literal ${1} belongs to rclone's replacement expression.
# shellcheck disable=SC2016
NAS_NAME_CODEC_ESCAPE_TRANSFORM='all,regex=(?i)^(__gdt0__.*)$/__gdt0__${1}'
NAS_NAME_CODEC_DOT_BIN_TRANSFORMS=(
  'dir,regex=^\.bin$/__gdt0__dotbin_000'
  'dir,regex=^\.biN$/__gdt0__dotbin_001'
  'dir,regex=^\.bIn$/__gdt0__dotbin_010'
  'dir,regex=^\.bIN$/__gdt0__dotbin_011'
  'dir,regex=^\.Bin$/__gdt0__dotbin_100'
  'dir,regex=^\.BiN$/__gdt0__dotbin_101'
  'dir,regex=^\.BIn$/__gdt0__dotbin_110'
  'dir,regex=^\.BIN$/__gdt0__dotbin_111'
)

mkdir -p "$HOME/Library/Logs"
if [[ -L "$LOG" || ( -e "$LOG" && ! -f "$LOG" ) ||
      ( -e "$LOG" && ! -O "$LOG" ) ]]; then
  printf '%s\n' 'FEHLER: Backup-Protokoll ist kein sicherer eigener Dateipfad.' >&2
  exit 73
fi
previous_umask="$(umask)"
umask 077
if ! : >>"$LOG"; then
  umask "$previous_umask"
  printf '%s\n' 'FEHLER: Backup-Protokoll kann nicht sicher angelegt werden.' >&2
  exit 73
fi
umask "$previous_umask"
if ! /bin/chmod 600 "$LOG"; then
  printf '%s\n' 'FEHLER: Backup-Protokoll kann nicht auf den Benutzer beschraenkt werden.' >&2
  exit 73
fi
exec >>"$LOG" 2>&1

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S%z')" "$*"
}

LOG_MAX_BYTES="${GDRIVE_BACKUP_LOG_MAX_BYTES:-5242880}"
if [[ ! "$LOG_MAX_BYTES" =~ ^[0-9]{1,12}$ ]]; then
  LOG_MAX_BYTES=5242880
fi

cleanup_temp_file() {
  local path
  local trash_bin="${GDRIVE_BACKUP_TEMP_TRASH_BIN:-}"
  for path in "$@"; do
    [[ -n "$path" && ( -e "$path" || -L "$path" ) ]] || continue
    # Every path handed to this function was created by this run through
    # mktemp or as a staging name it owns. Such scratch data is removed for
    # good: routing it through the Trash only filled the Trash on the Mac and
    # the hidden trash folders of backup disks and NAS shares.
    if [[ -n "$trash_bin" ]]; then
      if [[ -x "$trash_bin" ]] && "$trash_bin" "$path" >/dev/null 2>&1; then
        continue
      fi
      log "WARNUNG: Temporaere Datei konnte nicht in den Papierkorb verschoben werden: $path"
      continue
    fi
    if [[ -d "$path" && ! -L "$path" ]]; then
      /bin/rm -rf -- "$path" 2>/dev/null ||
        log "WARNUNG: Temporaerer Ordner konnte nicht entfernt werden: $path"
    else
      /bin/rm -f -- "$path" 2>/dev/null ||
        log "WARNUNG: Temporaere Datei konnte nicht entfernt werden: $path"
    fi
  done
}

# Keep the log useful and bounded. One compressed predecessor is retained. The
# live file is emptied in place, so the append-mode descriptor stays valid.

# Take the exclusive, non-blocking run lock on fd 9. flock(1) is used when
# installed; otherwise macOS's perl takes the same BSD flock(2) lock on the
# shared open file description, so the lock stays held by this shell after
# perl exits and the app's flock() probe sees it exactly as before.
acquire_run_lock() {
  if command -v flock >/dev/null 2>&1; then
    flock -n 9
    return
  fi
  # shellcheck disable=SC2016 # The single quotes hold Perl code, not shell.
  "$PERL_BIN" -MFcntl=:flock -e \
    'open(my $fh, ">&=", 9) or exit 2; flock($fh, LOCK_EX | LOCK_NB) or exit 1; exit 0'
}

rotate_log_if_needed() {
  local limit_bytes="$1" size previous="${LOG}.1.gz"

  (( limit_bytes > 0 )) || return 0
  [[ -f "$LOG" && ! -L "$LOG" ]] || return 0
  size="$(platform_stat_size "$LOG" 2>/dev/null || printf '0')"
  [[ "$size" =~ ^[0-9]+$ ]] || return 0
  (( size > limit_bytes )) || return 0
  if [[ -L "$previous" || ( -e "$previous" && ! -f "$previous" ) ]]; then
    return 0
  fi
  # gzip -c writes a complete archive before the live log is emptied, so an
  # interrupted rotation loses nothing.
  if (umask 077 && /usr/bin/gzip -c "$LOG" >"${previous}.tmp.$$") &&
     /bin/mv -f "${previous}.tmp.$$" "$previous"; then
    : >"$LOG"
  else
    /bin/rm -f -- "${previous}.tmp.$$" 2>/dev/null
  fi
  return 0
}

nas_name_codec_manifest_content() {
  printf '%s\n' \
    'protocol=1' \
    'codec=nas-path-v1' \
    "prefix=$NAS_NAME_CODEC_PREFIX" \
    "dot_bin_prefix=$NAS_NAME_CODEC_DOT_BIN_PREFIX" \
    'current_layers=1' \
    'version_layers=2'
}

compare_nas_name_codec_manifest() {
  local manifest_path="$1"
  local attempt compare_status=2 expected

  # Opening a file on a busy or waking SMB share can block for hours. The
  # expected content therefore lives in a local file and every comparison is
  # bounded; a timeout counts as "temporarily unreadable" and is retried.
  if ! expected="$(mktemp "${TMPDIR:-/tmp}/gdrive-name-codec.XXXXXX")" ||
     ! nas_name_codec_manifest_content >"$expected"; then
    cleanup_temp_file "${expected:-}"
    return 2
  fi
  for attempt in 1 2 3; do
    run_with_timeout "$NAS_FILE_TIMEOUT_SECONDS" "$CMP_BIN" -s "$manifest_path" "$expected"
    compare_status=$?
    case "$compare_status" in
      0|1)
        cleanup_temp_file "$expected"
        return "$compare_status"
        ;;
    esac
    if (( attempt < 3 )); then
      log "WARNUNG: Das NAS-Namenscodec-Manifest ist voruebergehend nicht lesbar; Vergleich wird wiederholt."
      /bin/sleep 0.25
    fi
  done
  cleanup_temp_file "$expected"
  return "$compare_status"
}

prepare_nas_name_codec() {
  local manifest_path manifest_compare_status legacy_collision temp_manifest copy_help

  [[ "$BACKUP_TARGET" == "nas" && "$ENCRYPTION" != "rclone-crypt" ]] || return 0

  if ! copy_help="$(rclone copy --help 2>&1)" ||
     [[ "$copy_help" != *"--name-transform"* ]]; then
    RUN_STATE_REASON="unsupported_rclone"
    log "FEHLER: Diese rclone-Version kann NAS-inkompatible Ordnernamen nicht verlustfrei abbilden."
    return 1
  fi

  manifest_path="${DEST_ROOT%/}/$NAS_NAME_CODEC_MANIFEST"
  if [[ -L "$manifest_path" || ( -e "$manifest_path" && ! -f "$manifest_path" ) ]]; then
    RUN_STATE_REASON="invalid_name_codec"
    log "FEHLER: Das NAS-Namenscodec-Manifest ist kein sicherer regulaerer Dateipfad."
    return 1
  fi
  if [[ -f "$manifest_path" ]]; then
    # cmp preserves the terminating newline. Restore uses the same byte-exact
    # contract so backup and restore cannot disagree about a damaged manifest.
    compare_nas_name_codec_manifest "$manifest_path"
    manifest_compare_status=$?
    case "$manifest_compare_status" in
      0)
        NAS_NAME_CODEC_ENABLED=1
        return 0
        ;;
      1)
        RUN_STATE_REASON="invalid_name_codec"
        log "FEHLER: Das NAS-Namenscodec-Manifest hat eine unbekannte oder beschaedigte Version."
        return 1
        ;;
      *)
        RUN_STATE_REASON="destination_unreadable"
        log "FEHLER: Das NAS-Namenscodec-Manifest konnte nicht zuverlaessig gelesen werden."
        return 1
        ;;
    esac
  fi

  # Before enabling the codec on an existing plain tree, make sure its reserved
  # namespace and vetoed .bin name were not already used below a copy root.
  # Destination area names themselves are raw rclone arguments, so the root
  # and immediate Shared Drive names are deliberately excluded.
  if [[ -d "$DEST_ROOT" ]]; then
    # The nested shell must expand its own positional parameters.
    # shellcheck disable=SC2016
    if ! legacy_collision="$(/usr/bin/find "$DEST_ROOT" \
        \( -iname "${NAS_NAME_CODEC_PREFIX}*" -o \
           \( -type d -iname '.bin' \) \) \
        -exec /bin/bash -c '
          destination_root="$1"
          versions_subdir="$2"
          candidate="$3"
          case "$candidate" in
            "$destination_root/"*) relative="${candidate#"$destination_root/"}" ;;
            *) exit 1 ;;
          esac
          case "$relative" in
            "My Drive/"*|"Shared with me/"*|"Shared Drives/"*"/"*)
              exit 0
              ;;
            "$versions_subdir/"*"/My Drive/"*|\
            "$versions_subdir/"*"/Shared with me/"*|\
            "$versions_subdir/"*"/Shared Drives/"*"/"*)
              exit 0
              ;;
          esac
          exit 1
        ' _ "$DEST_ROOT" "$VERSIONS_SUBDIR" {} \; -print -quit 2>/dev/null)"; then
      RUN_STATE_REASON="destination_unreadable"
      log "FEHLER: Das bestehende NAS-Ziel konnte nicht auf Namenskollisionen geprueft werden."
      return 1
    fi
    if [[ -n "$legacy_collision" ]]; then
      RUN_STATE_REASON="name_codec_collision"
      log "FEHLER: Das bestehende NAS-Ziel verwendet bereits den reservierten Namensraum des verlustfreien Codecs."
      return 1
    fi
  fi

  if [[ "$DRY_RUN" == "0" ]]; then
    temp_manifest="${manifest_path}.tmp.$$"
    if [[ -e "$temp_manifest" || -L "$temp_manifest" ]] ||
       ! nas_name_codec_manifest_content >"$temp_manifest" ||
       ! /bin/mv "$temp_manifest" "$manifest_path"; then
      cleanup_temp_file "$temp_manifest"
      RUN_STATE_REASON="destination_permission_denied"
      log "FEHLER: Das NAS-Namenscodec-Manifest konnte nicht sicher angelegt werden."
      return 1
    fi
  fi

  NAS_NAME_CODEC_ENABLED=1
  log "NAS-Namenscodec aktiv: .bin-Ordner werden verlustfrei und reversibel abgebildet."
}

validate_versioning_config() {
  if [[ ! "$RETENTION_PURGE_DAYS" =~ ^[0-9]{1,4}$ ]]; then
    log "FEHLER: GDRIVE_BACKUP_RETENTION_PURGE_DAYS muss eine Zahl zwischen 0 und 9999 sein."
    return 1
  fi
  RETENTION_PURGE_DAYS=$((10#$RETENTION_PURGE_DAYS))
  if [[ ! "$MIN_FREE_MB" =~ ^[0-9]{1,9}$ ]]; then
    log "FEHLER: GDRIVE_BACKUP_MIN_FREE_MB muss eine nichtnegative Zahl sein."
    return 1
  fi
  MIN_FREE_MB=$((10#$MIN_FREE_MB))

  case "$VERSIONING" in
    0|1) ;;
    *)
      log "FEHLER: GDRIVE_BACKUP_VERSIONING muss 0 oder 1 sein."
      return 1
      ;;
  esac

  case "$RETENTION" in
    0|1) ;;
    *)
      log "FEHLER: GDRIVE_BACKUP_RETENTION muss 0 oder 1 sein."
      return 1
      ;;
  esac

  [[ "$VERSIONING" == "1" ]] || return 0

  if [[ -z "$VERSIONS_SUBDIR" || "$VERSIONS_SUBDIR" == /* ||
        "$VERSIONS_SUBDIR" =~ [[:cntrl:]] ]]; then
    log "FEHLER: GDRIVE_BACKUP_VERSIONS_SUBDIR muss ein sicherer relativer Pfad sein."
    return 1
  fi

  case "/$VERSIONS_SUBDIR/" in
    *"//"*|*"/./"*|*"/../"*)
      log "FEHLER: GDRIVE_BACKUP_VERSIONS_SUBDIR darf keine leeren, Punkt- oder Elternsegmente enthalten."
      return 1
      ;;
  esac

  case "$(lowercase "${VERSIONS_SUBDIR%%/*}")" in
    "my drive"|"shared with me"|"shared drives")
      log "FEHLER: GDRIVE_BACKUP_VERSIONS_SUBDIR darf keinen aktiven Zielordner ueberlappen."
      return 1
      ;;
  esac
}

validate_encryption_config() {
  case "$ENCRYPTION" in
    none) return 0 ;;
    apfs)
      if [[ "$BACKUP_TARGET" != "apfs" ]]; then
        log "FEHLER: GDRIVE_BACKUP_ENCRYPTION=apfs ist nur fuer ein lokales APFS-Ziel zulaessig."
        return 1
      fi
      ;;
    rclone-crypt)
      if [[ -z "$CRYPT_REMOTE" ||
            ! "$CRYPT_REMOTE" =~ ^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$ ]]; then
        log "FEHLER: GDRIVE_BACKUP_CRYPT_REMOTE muss ein sicherer rclone-Remote-Name ohne Doppelpunkt sein."
        return 1
      fi
      if [[ "$CRYPT_REMOTE" == "$REMOTE" ]]; then
        log "FEHLER: Quell- und Verschluesselungs-Remote muessen verschieden sein."
        return 1
      fi
      ;;
    *)
      log "FEHLER: GDRIVE_BACKUP_ENCRYPTION muss 'none', 'apfs' oder 'rclone-crypt' sein."
      return 1
      ;;
  esac
}

rclone_config_value() {
  local config="$1"
  local requested_key="$2"
  printf '%s\n' "$config" | /usr/bin/awk -F= -v requested_key="$requested_key" '
    {
      key=$1
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
      if (key == requested_key) {
        value=substr($0, index($0, "=") + 1)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
        print value
      }
    }
  '
}

validate_rclone_crypt_physical_tree() {
  local root_real root_device symlink_path device_listing device

  [[ "$ENCRYPTION" == "rclone-crypt" ]] || return 0
  if [[ ! -d "$DEST_ROOT" || -L "$DEST_ROOT" ]] ||
     ! root_real="$(canonical_existing_directory "$DEST_ROOT")" ||
     ! root_device="$(platform_stat_device "$root_real" 2>/dev/null)" ||
     [[ -z "$root_device" ]]; then
    log "FEHLER: Der physische Crypt-Zielordner ist nicht sicher."
    return 1
  fi
  if ! symlink_path="$(platform_first_symlink "$root_real" 2>/dev/null)" ||
     [[ -n "$symlink_path" ]]; then
    log "FEHLER: Der physische Crypt-Zielbaum enthaelt einen symbolischen Link."
    return 1
  fi
  if ! device_listing="$(platform_directory_devices "$root_real" 2>/dev/null)"; then
    log "FEHLER: Der physische Crypt-Zielbaum kann nicht sicher geprueft werden."
    return 1
  fi
  while IFS= read -r device; do
    [[ -n "$device" ]] || continue
    if [[ "$device" != "$root_device" ]]; then
      log "FEHLER: Ein fremdes Dateisystem liegt im physischen Crypt-Zielbaum."
      return 1
    fi
  done <<<"$device_listing"
}

validate_rclone_crypt_config() {
  local config type root password password2 filename_encryption
  local directory_name_encryption no_data_encryption show_mapping
  local root_real destination_real

  [[ "$ENCRYPTION" == "rclone-crypt" ]] || return 0

  if ! config="$(rclone config show "$CRYPT_REMOTE" 2>/dev/null)" || [[ -z "$config" ]]; then
    log "FEHLER: Das rclone-Crypt-Remote ist nicht konfiguriert."
    return 1
  fi

  type="$(rclone_config_value "$config" type)"
  root="$(rclone_config_value "$config" remote)"
  password="$(rclone_config_value "$config" password)"
  password2="$(rclone_config_value "$config" password2)"
  filename_encryption="$(lowercase "$(rclone_config_value "$config" filename_encryption)")"
  directory_name_encryption="$(lowercase "$(rclone_config_value "$config" directory_name_encryption)")"
  no_data_encryption="$(lowercase "$(rclone_config_value "$config" no_data_encryption)")"
  show_mapping="$(lowercase "$(rclone_config_value "$config" show_mapping)")"

  if [[ "$type" != "crypt" || -z "$password" || -z "$password2" ||
        "$filename_encryption" != "standard" ||
        "$directory_name_encryption" != "true" ||
        "$no_data_encryption" != "false" || "$show_mapping" != "false" ]]; then
    log "FEHLER: Das rclone-Crypt-Remote erfuellt die Verschluesselungsrichtlinie nicht."
    return 1
  fi
  if [[ "$root" != /* || "$root" =~ [[:cntrl:]] || "$root" == *:* ]]; then
    log "FEHLER: Das rclone-Crypt-Remote muss direkt auf das lokale oder gemountete Backup-Ziel zeigen."
    return 1
  fi
  if ! root_real="$(canonical_existing_directory "$root")" ||
     ! destination_real="$(canonical_existing_directory "$DEST_ROOT")" ||
     [[ "$root_real" != "$destination_real" ]]; then
    log "FEHLER: Das rclone-Crypt-Remote zeigt nicht exakt auf das konfigurierte Backup-Ziel."
    return 1
  fi
  validate_rclone_crypt_physical_tree
}

backup_destination_for() {
  local relative_destination="$1"
  if [[ "$ENCRYPTION" == "rclone-crypt" ]]; then
    printf '%s:%s' "$CRYPT_REMOTE" "$relative_destination"
  else
    printf '%s/%s' "${DEST_ROOT%/}" "$relative_destination"
  fi
}

version_backup_dir_for() {
  local destination="$1"
  local relative_destination

  if [[ "$ENCRYPTION" == "rclone-crypt" ]]; then
    relative_destination="${destination#"$CRYPT_REMOTE":}"
    if [[ -z "$relative_destination" || "$relative_destination" == "$destination" ||
          "$relative_destination" == /* ]]; then
      return 1
    fi
    printf '%s:%s/%s/%s' "$CRYPT_REMOTE" "$VERSIONS_SUBDIR" "$VERSION_RUN_ID" "$relative_destination"
    return 0
  fi

  relative_destination="${destination#"$DEST_ROOT"/}"

  if [[ -z "$relative_destination" || "$relative_destination" == "$destination" ]]; then
    return 1
  fi

  printf '%s/%s/%s/%s' "${DEST_ROOT%/}" "$VERSIONS_SUBDIR" "$VERSION_RUN_ID" "$relative_destination"
}

safe_name() {
  local value="$1"
  value="${value//\//_}"
  value="${value//:/_}"
  value="${value//$'\n'/_}"
  printf '%s' "$value"
}

canonical_existing_directory() {
  local path="$1"
  [[ -d "$path" ]] || return 1
  (cd "$path" 2>/dev/null && /bin/pwd -P)
}

canonical_existing_ancestor() {
  local path="$1"
  local parent=""

  while [[ ! -e "$path" && ! -L "$path" ]]; do
    parent="$(/usr/bin/dirname "$path")"
    [[ "$parent" != "$path" ]] || return 1
    path="$parent"
  done

  canonical_existing_directory "$path"
}

path_has_existing_symlink_component() {
  local root="${1%/}"
  local path="$2"
  local relative component current

  [[ -n "$root" && "$path" == "$root"/* ]] || return 1
  relative="${path#"$root"/}"
  current="$root"
  while [[ -n "$relative" ]]; do
    component="${relative%%/*}"
    if [[ "$relative" == */* ]]; then
      relative="${relative#*/}"
    else
      relative=""
    fi
    [[ -n "$component" ]] || return 0
    current="${current%/}/$component"
    if [[ -L "$current" ]]; then
      return 0
    fi
    [[ -e "$current" ]] || return 1
  done
  return 1
}

path_is_on_encrypted_volume() {
  local path="$1"
  local existing_real device

  [[ "$ENCRYPTION" == "apfs" ]] || return 0
  [[ -n "$ENCRYPTED_VOLUME_REAL" && -n "$ENCRYPTED_VOLUME_DEVICE" ]] || return 1

  if ! existing_real="$(canonical_existing_ancestor "$path")"; then
    log "FEHLER: Verschluesseltes Ziel kann nicht sicher aufgeloest werden: $(safe_name "$path")"
    return 1
  fi
  if ! device="$(platform_stat_device "$existing_real" 2>/dev/null)" ||
     [[ -z "$device" ]]; then
    log "FEHLER: Volume-Zugehoerigkeit kann nicht geprueft werden: $(safe_name "$path")"
    return 1
  fi

  case "$existing_real/" in
    "$ENCRYPTED_VOLUME_REAL/"|"$ENCRYPTED_VOLUME_REAL/"*) ;;
    *)
      log "FEHLER: Zielpfad verlaesst das verschluesselte Volume: $(safe_name "$path")"
      return 1
      ;;
  esac

  if [[ "$device" != "$ENCRYPTED_VOLUME_DEVICE" ]]; then
    log "FEHLER: Zielpfad liegt auf einem anderen Dateisystem: $(safe_name "$path")"
    return 1
  fi
}

normalized_apfs_uuid() {
  printf '%s' "$1" | /usr/bin/tr '[:lower:]' '[:upper:]'
}

validate_configured_apfs_paths() {
  local path probe existing_ancestor destination_device
  local -a paths

  [[ "$BACKUP_TARGET" == "apfs" && -n "$BACKUP_VOLUME_UUID" ]] || return 0
  [[ -n "$APFS_VOLUME_REAL" && -n "$APFS_VOLUME_DEVICE" ]] || return 1

  paths=("$DEST_ROOT" "$@")
  for path in "${paths[@]}"; do
    [[ -n "$path" && "$path" == /* ]] || {
      log "FEHLER: APFS-Pfad ist nicht absolut."
      return 1
    }
    case "/${path#/}/" in
      *"//"*|*"/./"*|*"/../"*)
        log "FEHLER: APFS-Pfad enthaelt unsichere Pfadbestandteile."
        return 1
        ;;
    esac
    if path_has_existing_symlink_component "$APFS_VOLUME_REAL" "$path"; then
      log "FEHLER: APFS-Pfad enthaelt eine symbolisch verknuepfte Pfadkomponente."
      return 1
    fi
    probe="$path"
    if [[ ( -e "$probe" || -L "$probe" ) && ! -d "$probe" ]]; then
      probe="$(/usr/bin/dirname "$probe")"
    fi
    if ! existing_ancestor="$(canonical_existing_ancestor "$probe")"; then
      log "FEHLER: APFS-Pfad kann nicht sicher aufgeloest werden."
      return 1
    fi
    case "$existing_ancestor/" in
      "$APFS_VOLUME_REAL/"*) ;;
      *)
        log "FEHLER: APFS-Pfad verlaesst das konfigurierte Backup-Volume."
        return 1
        ;;
    esac
    if ! destination_device="$(platform_stat_device "$existing_ancestor" 2>/dev/null)" ||
       [[ -z "$destination_device" ||
          "$destination_device" != "$APFS_VOLUME_DEVICE" ]]; then
      log "FEHLER: APFS-Pfad liegt nicht mehr auf dem konfigurierten Backup-Volume."
      return 1
    fi
  done
  return 0
}

validate_all_configured_apfs_trees() {
  local tree

  [[ "$BACKUP_TARGET" == "apfs" && -n "$BACKUP_VOLUME_UUID" ]] || return 0
  for tree in \
    "$DEST_ROOT/My Drive" \
    "$DEST_ROOT/Shared with me" \
    "$DEST_ROOT/Shared Drives" \
    "$DEST_ROOT/.gdrive-collisions"; do
    if ! validate_configured_apfs_tree "$tree"; then
      return 1
    fi
  done
  if [[ "$VERSIONING" == "1" ]] &&
     ! validate_configured_apfs_tree "${DEST_ROOT%/}/$VERSIONS_SUBDIR"; then
    return 1
  fi
  return 0
}

validate_configured_apfs_target() {
  validate_configured_apfs_volume_identity &&
    validate_configured_apfs_paths
}

validate_configured_apfs_target_paths() {
  validate_configured_apfs_volume_identity &&
    validate_configured_apfs_paths "$@"
}

validate_encrypted_destination_tree() {
  local root="$1"
  local symlink_path device_listing device

  [[ "$ENCRYPTION" == "apfs" ]] || return 0
  [[ -e "$root" || -L "$root" ]] || return 0

  if ! path_is_on_encrypted_volume "$root"; then
    return 1
  fi
  if [[ -L "$root" ]]; then
    log "FEHLER: Symbolischer Link im verschluesselten Ziel ist nicht zulaessig: $(safe_name "$root")"
    return 1
  fi
  if ! symlink_path="$(platform_first_symlink "$root" 2>/dev/null)"; then
    log "FEHLER: Zielbaum kann nicht vollstaendig auf symbolische Links geprueft werden: $(safe_name "$root")"
    return 1
  fi
  if [[ -n "$symlink_path" ]]; then
    log "FEHLER: Symbolischer Link im verschluesselten Ziel ist nicht zulaessig: $(safe_name "$symlink_path")"
    return 1
  fi
  if ! device_listing="$(platform_directory_devices "$root" 2>/dev/null)"; then
    log "FEHLER: Zielbaum kann nicht vollstaendig auf fremde Dateisysteme geprueft werden: $(safe_name "$root")"
    return 1
  fi
  while IFS= read -r device; do
    [[ -n "$device" ]] || continue
    if [[ "$device" != "$ENCRYPTED_VOLUME_DEVICE" ]]; then
      log "FEHLER: Ein eingebundenes fremdes Dateisystem liegt im verschluesselten Zielbaum: $(safe_name "$root")"
      return 1
    fi
  done <<<"$device_listing"
}

validate_all_encrypted_active_trees() {
  local active_path
  [[ "$ENCRYPTION" == "apfs" ]] || return 0

  if ! validate_encrypted_apfs_destination; then
    return 1
  fi
  for active_path in \
    "$DEST_ROOT/My Drive" \
    "$DEST_ROOT/Shared with me" \
    "$DEST_ROOT/Shared Drives"; do
    if ! validate_encrypted_destination_tree "$active_path"; then
      return 1
    fi
  done
}

retention_timestamp_for_name() {
  local name="$1"
  if [[ "$name" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}-[0-9]{2}-[0-9]{2}[+-][0-9]{4})-[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

crypt_retention_remote_path_is_safe() {
  local path="$1"
  local prefix="${CRYPT_REMOTE}:${VERSIONS_SUBDIR}/"
  local name="${path#"$prefix"}"

  [[ "$ENCRYPTION" == "rclone-crypt" && "$name" != "$path" && -n "$name" &&
     "$name" != */* && ! "$name" =~ [[:cntrl:]] ]] || return 1
  retention_timestamp_for_name "$name" >/dev/null
}

crypt_physical_path_for_logical() {
  local logical_path="$1"
  local prefix="${CRYPT_REMOTE}:"
  local relative="${logical_path#"$prefix"}"
  local encoded_json encoded physical root_real physical_real
  local root_device physical_device

  [[ "$relative" != "$logical_path" && -n "$relative" && "$relative" != /* &&
     ! "$relative" =~ [[:cntrl:]] ]] || return 1
  case "/$relative/" in
    *"//"*|*"/./"*|*"/../"*) return 1 ;;
  esac

  if ! encoded_json="$(rclone backend encode "$CRYPT_REMOTE:" --json "$relative" 2>/dev/null)" ||
     ! encoded="$(printf '%s' "$encoded_json" |
       jq -er 'if type == "array" and length == 1 and (.[0] | type) == "string" then .[0] else empty end' 2>/dev/null)"; then
    return 1
  fi
  [[ -n "$encoded" && "$encoded" != /* && ! "$encoded" =~ [[:cntrl:]] ]] || return 1
  case "/$encoded/" in
    *"//"*|*"/./"*|*"/../"*) return 1 ;;
  esac

  physical="${DEST_ROOT%/}/$encoded"
  [[ -d "$physical" && ! -L "$physical" ]] || return 1
  if ! root_real="$(canonical_existing_directory "$DEST_ROOT")" ||
     ! physical_real="$(canonical_existing_directory "$physical")"; then
    return 1
  fi
  case "$physical_real/" in
    "$root_real/"*) ;;
    *) return 1 ;;
  esac
  if ! root_device="$(platform_stat_device "$root_real" 2>/dev/null)" ||
     ! physical_device="$(platform_stat_device "$physical_real" 2>/dev/null)" ||
     [[ -z "$root_device" || "$root_device" != "$physical_device" ]]; then
    return 1
  fi

  printf '%s' "$physical_real"
}

validate_retention_destination_identity() {
  local path probe existing_ancestor destination_device
  local -a paths

  if ! validate_live_nas_destination ||
     ! validate_configured_apfs_target; then
    log "FEHLER: Backup-Ziel konnte fuer die Aufbewahrung nicht erneut bestaetigt werden."
    return 1
  fi
  [[ "$BACKUP_TARGET" == "apfs" && -n "$BACKUP_VOLUME_UUID" ]] ||
    return 0

  if (( $# == 0 )); then
    paths=("$DEST_ROOT")
  else
    paths=("$@")
  fi
  for path in "${paths[@]}"; do
    probe="$path"
    if [[ ( -e "$probe" || -L "$probe" ) && ! -d "$probe" ]]; then
      probe="$(/usr/bin/dirname "$probe")"
    fi
    if ! existing_ancestor="$(canonical_existing_ancestor "$probe")"; then
      log "FEHLER: Aufbewahrungspfad kann nicht sicher aufgeloest werden."
      return 1
    fi
    case "$existing_ancestor/" in
      "$APFS_VOLUME_REAL/"*) ;;
      *)
        log "FEHLER: Aufbewahrungspfad verlaesst das konfigurierte APFS-Volume."
        return 1
        ;;
    esac
    if ! destination_device="$(platform_stat_device "$existing_ancestor" 2>/dev/null)" ||
       [[ -z "$destination_device" ||
          "$destination_device" != "$APFS_VOLUME_DEVICE" ]]; then
      log "FEHLER: Aufbewahrungspfad liegt nicht mehr auf dem konfigurierten APFS-Volume."
      return 1
    fi
  done
  return 0
}

retry_crypt_retention_quarantine() {
  local quarantine="${DEST_ROOT%/}/.retention-trash"
  local root_real path path_real name remaining=0 moved=0 trash_status

  [[ -e "$quarantine" || -L "$quarantine" ]] || return 0
  if [[ ! -d "$quarantine" || -L "$quarantine" ]] ||
     ! root_real="$(canonical_existing_directory "$DEST_ROOT")"; then
    log "WARNUNG: Verschluesselte Aufbewahrungs-Quarantaene ist unsicher und bleibt unangetastet."
    return 0
  fi
  for path in "$quarantine"/* "$quarantine"/.[!.]* "$quarantine"/..?*; do
    [[ -d "$path" && ! -L "$path" ]] || continue
    if ! path_real="$(canonical_existing_directory "$path")"; then
      remaining=$((remaining + 1))
      continue
    fi
    case "$path_real/" in
      "$root_real/"*) ;;
      *) remaining=$((remaining + 1)); continue ;;
    esac
    name="${path##*/}"
    if [[ "$DRY_RUN" == "1" ]]; then
      log "DRY-RUN verschluesselte Quarantaene-Papierkorb: $(safe_name "$name")"
      remaining=$((remaining + 1))
    else
      trash_status=0
      trash_retention_path "$path" || trash_status=$?
      case "$trash_status" in
        0) moved=$((moved + 1)) ;;
        2) return 1 ;;
        *) remaining=$((remaining + 1)) ;;
      esac
    fi
  done
  if (( moved > 0 || remaining > 0 )); then
    log "Aufbewahrung: verschluesselte Quarantaene nachgeprueft, papierkorb=$moved verbleibend=$remaining"
  fi
  return 0
}

merge_retention_candidate_into_keeper() {
  local source="$1"
  local keeper="$2"
  local bucket="$3"
  local unsafe_link
  local -a merge_options

  [[ "$source" != "$keeper" ]] || return 0
  if [[ "$DRY_RUN" == "1" ]]; then
    log "DRY-RUN Aufbewahrung wuerde Dateiversionen zusammenfuehren: ${source##*/} -> ${keeper##*/} ($bucket)"
    return 0
  fi

  if [[ "$ENCRYPTION" == "rclone-crypt" ]]; then
    if ! crypt_retention_remote_path_is_safe "$source" ||
       ! crypt_retention_remote_path_is_safe "$keeper" ||
       ! validate_rclone_crypt_config; then
      log "FEHLER: Verschluesselte Versionsstaende koennen nicht sicher zusammengefuehrt werden."
      return 1
    fi
    merge_options=(--ignore-existing --create-empty-src-dirs --log-level INFO)
    if [[ "$BACKUP_TARGET" == "nas" ]]; then
      merge_options+=(--multi-thread-streams 0 --transfers 1)
    fi
    if ! validate_retention_destination_identity "$DEST_ROOT" ||
       ! rclone copy "$source" "$keeper" "${merge_options[@]}"; then
      log "FEHLER: Verschluesselte Dateiversionen konnten nicht zusammengefuehrt werden."
      return 1
    fi
    log "Aufbewahrung: verschluesselte Dateiversionen zusammengefuehrt: ${source##*/} -> ${keeper##*/} ($bucket)"
    return 0
  fi

  if ! validate_encrypted_apfs_destination ||
     ! validate_encrypted_destination_tree "$source" ||
     ! validate_encrypted_destination_tree "$keeper"; then
    log "FEHLER: Versionsstaende koennen nicht sicher zusammengefuehrt werden: ${source##*/}"
    return 1
  fi

  if ! unsafe_link="$(platform_first_symlink "$keeper" 2>/dev/null)" ||
     [[ -n "$unsafe_link" ]]; then
    log "FEHLER: Aufbewahrungsstand enthaelt einen unsicheren symbolischen Link: ${keeper##*/}"
    return 1
  fi

  merge_options=(--ignore-existing --create-empty-src-dirs --log-level INFO --one-file-system)
  if [[ "$BACKUP_TARGET" == "nas" ]]; then
    # Version trees are already in their physical encoded form, so retention
    # preserves names verbatim while keeping writes serialized for SMB.
    merge_options+=(--multi-thread-streams 0 --transfers 1)
  fi
  if ! validate_retention_destination_identity "$source" "$keeper" ||
     ! rclone copy "$source" "$keeper" "${merge_options[@]}"; then
    log "FEHLER: Dateiversionen konnten nicht in den Aufbewahrungsstand uebernommen werden: ${source##*/}"
    return 1
  fi

  log "Aufbewahrung: neueste Dateiversionen zusammengefuehrt: ${source##*/} -> ${keeper##*/} ($bucket)"
}

move_retention_candidate() {
  local path="$1"
  local reason="$2"
  local versions_root="$3"
  local name="${path##*/}"
  local quarantine="$versions_root/.retention-trash"
  local quarantine_target="$quarantine/$name"
  local physical_path physical_name root_real quarantine_real trash_status

  if [[ "$DRY_RUN" == "1" ]]; then
    log "DRY-RUN Aufbewahrungskandidat: $name ($reason)"
    return 0
  fi

  if [[ "$ENCRYPTION" == "rclone-crypt" ]]; then
    if ! crypt_retention_remote_path_is_safe "$path" ||
       ! validate_rclone_crypt_config ||
       ! physical_path="$(crypt_physical_path_for_logical "$path")"; then
      log "FEHLER: Verschluesselter Aufbewahrungskandidat kann nicht sicher zugeordnet werden: $name"
      return 1
    fi
    trash_status=0
    trash_retention_path "$physical_path" || trash_status=$?
    case "$trash_status" in
      0)
        log "Aufbewahrung: verschluesselter Stand in den Papierkorb verschoben: $name ($reason)."
        return 0
        ;;
      2) return 1 ;;
    esac

    physical_name="${physical_path##*/}"
    quarantine="${DEST_ROOT%/}/.retention-trash"
    quarantine_target="$quarantine/$physical_name"
    if ! validate_retention_destination_identity "$physical_path" "$quarantine" ||
       ! root_real="$(canonical_existing_directory "$DEST_ROOT")" ||
       ! mkdir -p "$quarantine" ||
       ! quarantine_real="$(canonical_existing_directory "$quarantine")"; then
      log "FEHLER: Verschluesselte Aufbewahrungs-Quarantaene kann nicht sicher angelegt werden."
      return 1
    fi
    case "$quarantine_real/" in
      "$root_real/"*) ;;
      *) log "FEHLER: Verschluesselte Aufbewahrungs-Quarantaene verlaesst das Backup-Ziel."; return 1 ;;
    esac
    if [[ -e "$quarantine_target" || -L "$quarantine_target" ]] ||
       ! validate_retention_destination_identity "$physical_path" "$quarantine_target" ||
       ! /bin/mv "$physical_path" "$quarantine_target"; then
      log "FEHLER: Verschluesselter Aufbewahrungskandidat bleibt erhalten: $name"
      return 1
    fi
    # The modification time marks the start of the grace period.
    /usr/bin/touch "$quarantine_target" 2>/dev/null || true
    log "Aufbewahrung: verschluesselter Stand in Quarantaene verschoben: $name ($reason)."
    return 0
  fi

  trash_status=0
  trash_retention_path "$path" || trash_status=$?
  case "$trash_status" in
    0)
      log "Aufbewahrung: $name in den Papierkorb verschoben ($reason)."
      return 0
      ;;
    2) return 1 ;;
  esac
  if [[ -n "$RETENTION_TRASH_BIN" ]]; then
    log "WARNUNG: Papierkorb fehlgeschlagen; verwende lokale Quarantaene fuer $name."
  fi

  if ! validate_retention_destination_identity "$path" "$quarantine" ||
     ! path_is_on_encrypted_volume "$quarantine" ||
     ! path_is_on_encrypted_volume "$quarantine_target"; then
    log "FEHLER: Aufbewahrungs-Quarantaene verlaesst das verschluesselte Volume: $name"
    return 1
  fi
  if ! mkdir -p "$quarantine"; then
    log "FEHLER: Aufbewahrungs-Quarantaene kann nicht angelegt werden: $quarantine"
    return 1
  fi
  if [[ -e "$quarantine_target" ]]; then
    log "FEHLER: Aufbewahrungskandidat bleibt erhalten; Quarantaeneziel existiert bereits: $name"
    return 1
  fi
  if ! validate_retention_destination_identity "$path" "$quarantine_target" ||
     ! /bin/mv "$path" "$quarantine_target"; then
    log "FEHLER: Aufbewahrungskandidat konnte nicht in die Quarantaene verschoben werden: $name"
    return 1
  fi
  # The modification time marks the start of the grace period.
  /usr/bin/touch "$quarantine_target" 2>/dev/null || true

  log "Aufbewahrung: $name nach .retention-trash verschoben ($reason)."
}

trash_retention_path() {
  local path="$1"

  # Retired version states leave the history through the quarantine folder on
  # the backup destination and are deleted for good after the grace period.
  # The Trash is used only when a tool is configured explicitly, because the
  # system Trash of an external disk or NAS share is never emptied by itself.
  [[ -n "$RETENTION_TRASH_BIN" && -x "$RETENTION_TRASH_BIN" ]] || return 1
  validate_retention_destination_identity "$path" || return 2
  if "$RETENTION_TRASH_BIN" "$path" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

# Delete quarantined version states whose grace period has elapsed. Only real
# directories directly inside the quarantine qualify; everything else stays.
purge_retention_quarantine() {
  local quarantine="$1"
  local require_version_name="$2"
  local now_epoch limit path name stamped purged=0 kept=0

  [[ "$RETENTION_PURGE_DAYS" != "0" ]] || return 0
  [[ -d "$quarantine" && ! -L "$quarantine" ]] || return 0
  now_epoch="$(date '+%s')"
  [[ "$now_epoch" =~ ^[0-9]+$ ]] || return 0
  limit=$((RETENTION_PURGE_DAYS * 24 * 60 * 60))

  for path in "$quarantine"/* "$quarantine"/.[!.]* "$quarantine"/..?*; do
    [[ -e "$path" || -L "$path" ]] || continue
    name="${path##*/}"
    if [[ -L "$path" || ! -d "$path" ]] ||
       { [[ "$require_version_name" == "1" ]] &&
         ! retention_timestamp_for_name "$name" >/dev/null; }; then
      kept=$((kept + 1))
      continue
    fi
    stamped="$(platform_stat_mtime "$path" 2>/dev/null || true)"
    if [[ ! "$stamped" =~ ^[0-9]+$ ]] || (( now_epoch - stamped < limit )); then
      kept=$((kept + 1))
      continue
    fi
    if [[ "$DRY_RUN" == "1" ]]; then
      log "DRY-RUN Quarantaene wuerde endgueltig geloescht: $(safe_name "$name")"
      kept=$((kept + 1))
      continue
    fi
    if ! validate_retention_destination_identity "$path" ||
       ! validate_configured_apfs_tree "$path" ||
       ! validate_encrypted_destination_tree "$path"; then
      log "WARNUNG: Quarantaene-Eintrag bleibt erhalten, weil das Ziel nicht sicher bestaetigt ist: $(safe_name "$name")"
      kept=$((kept + 1))
      continue
    fi
    if /bin/rm -rf -- "$path" 2>/dev/null && [[ ! -e "$path" ]]; then
      purged=$((purged + 1))
      log "Aufbewahrung: Quarantaene nach $RETENTION_PURGE_DAYS Tagen endgueltig geloescht: $(safe_name "$name")"
    else
      kept=$((kept + 1))
      log "WARNUNG: Quarantaene-Eintrag konnte nicht geloescht werden: $(safe_name "$name")"
    fi
  done

  if (( purged > 0 )); then
    log "Aufbewahrung: Quarantaene bereinigt, geloescht=$purged verbleibend=$kept"
  fi
  return 0
}

retry_retention_quarantine() {
  local versions_root="$1"
  local quarantine="$versions_root/.retention-trash"
  local path name remaining=0 moved=0 trash_status

  [[ -e "$quarantine" || -L "$quarantine" ]] || return 0
  if [[ ! -d "$quarantine" || -L "$quarantine" ]]; then
    log "WARNUNG: Aufbewahrungs-Quarantaene ist kein sicherer Ordner und bleibt unangetastet."
    return 0
  fi
  if ! path_is_on_encrypted_volume "$quarantine"; then
    log "WARNUNG: Aufbewahrungs-Quarantaene verlaesst das verschluesselte Volume und bleibt unangetastet."
    return 0
  fi

  for path in "$quarantine"/* "$quarantine"/.[!.]* "$quarantine"/..?*; do
    [[ -e "$path" || -L "$path" ]] || continue
    name="${path##*/}"
    if [[ "$DRY_RUN" == "1" ]]; then
      log "DRY-RUN Quarantaene-Papierkorb: $name"
      remaining=$((remaining + 1))
    else
      trash_status=0
      trash_retention_path "$path" || trash_status=$?
      case "$trash_status" in
        0)
          log "Aufbewahrung: Quarantaene nachtraeglich in den Papierkorb verschoben: $name"
          moved=$((moved + 1))
          ;;
        2) return 1 ;;
        *) remaining=$((remaining + 1)) ;;
      esac
    fi
  done

  if (( moved > 0 || remaining > 0 )); then
    log "Aufbewahrung: Quarantaene nachgeprueft, papierkorb=$moved verbleibend=$remaining"
  fi
  return 0
}

prune_version_history() {
  local versions_root="${DEST_ROOT%/}/$VERSIONS_SUBDIR"
  local now_epoch path name timestamp epoch age tier bucket day listing listed_name
  local calendar_value normalized_calendar timezone_hours timezone_minutes
  local entry_count=0 daily_count=0 weekly_count=0
  local recent_count=0 unknown_count=0 future_count=0 candidate_count=0 prune_errors=0
  local index keeper_index found
  local -a entry_paths entry_tiers entry_buckets entry_epochs entry_processed
  local -a daily_buckets daily_keeper_epochs daily_keeper_paths
  local -a weekly_buckets weekly_keeper_epochs weekly_keeper_paths
  # Bash 5 treats a declared-but-unassigned array as unset under nounset.
  local -a retention_paths=()

  if ! validate_retention_destination_identity "$versions_root"; then
    return 1
  fi
  if ! validate_configured_apfs_tree "$versions_root"; then
    log "FEHLER: Versionsbaum enthaelt einen unsicheren APFS-Pfad oder ein fremdes Dateisystem."
    return 1
  fi

  if [[ "$ENCRYPTION" == "rclone-crypt" ]]; then
    if ! validate_rclone_crypt_config; then
      log "FEHLER: Crypt-Konfiguration konnte vor der Aufbewahrung nicht erneut bestaetigt werden."
      return 1
    fi
    if ! retry_crypt_retention_quarantine; then
      return 1
    fi
    purge_retention_quarantine "${DEST_ROOT%/}/.retention-trash" 0
    if ! listing="$(rclone lsf "${CRYPT_REMOTE}:${VERSIONS_SUBDIR}" --dirs-only --max-depth 1 2>/dev/null)"; then
      log "FEHLER: Verschluesselte Versionsstaende konnten nicht sicher aufgelistet werden."
      return 1
    fi
    while IFS= read -r listed_name; do
      [[ -n "$listed_name" ]] || continue
      if [[ "$listed_name" != */ ]]; then
        log "FEHLER: Unerwarteter Eintrag in der verschluesselten Versionsliste."
        return 1
      fi
      listed_name="${listed_name%/}"
      if [[ -z "$listed_name" || "$listed_name" == */* ||
            "$listed_name" =~ [[:cntrl:]] ]]; then
        log "FEHLER: Unsicherer Eintrag in der verschluesselten Versionsliste."
        return 1
      fi
      retention_paths[${#retention_paths[@]}]="${CRYPT_REMOTE}:${VERSIONS_SUBDIR}/$listed_name"
    done <<<"$listing"
    if (( ${#retention_paths[@]} == 0 )); then
      log "Aufbewahrung: Noch kein verschluesselter Versionsstand vorhanden."
      return 0
    fi
  else
    if ! validate_encrypted_apfs_destination; then
      log "FEHLER: Verschluesseltes Volume konnte vor der Aufbewahrung nicht erneut bestaetigt werden."
      return 1
    fi
    if ! path_is_on_encrypted_volume "$versions_root"; then
      log "FEHLER: Versionsaufbewahrung verlaesst das verschluesselte Volume."
      return 1
    fi

    if [[ ! -d "$versions_root" ]]; then
      log "Aufbewahrung: Noch kein Versionsbaum vorhanden."
      return 0
    fi
    if [[ -L "$versions_root" ]]; then
      log "FEHLER: Versionsbaum ist ein symbolischer Link und bleibt unangetastet."
      return 1
    fi

    if ! retry_retention_quarantine "$versions_root"; then
      return 1
    fi
    purge_retention_quarantine "$versions_root/.retention-trash" 1

    if ! validate_encrypted_destination_tree "$versions_root"; then
      log "FEHLER: Versionsbaum enthaelt einen unsicheren Link oder Mount."
      return 1
    fi
    for path in "$versions_root"/* "$versions_root"/.[!.]* "$versions_root"/..?*; do
      [[ -d "$path" ]] || continue
      retention_paths[${#retention_paths[@]}]="$path"
    done
  fi

  now_epoch="$(date '+%s')"
  if [[ ! "$now_epoch" =~ ^[0-9]+$ ]]; then
    log "FEHLER: Aktuelle Zeit fuer die Aufbewahrung konnte nicht ermittelt werden."
    return 1
  fi

  for path in "${retention_paths[@]}"; do
    name="${path##*/}"
    [[ "$name" != ".retention-trash" ]] || continue
    if [[ "$ENCRYPTION" != "rclone-crypt" && -L "$path" ]]; then
      log "Aufbewahrung: Symbolischer Versionsordner bleibt erhalten: $(safe_name "$name")"
      unknown_count=$((unknown_count + 1))
      continue
    fi

    if ! timestamp="$(retention_timestamp_for_name "$name")"; then
      log "Aufbewahrung: Unbekannter Versionsordner bleibt erhalten: $(safe_name "$name")"
      unknown_count=$((unknown_count + 1))
      continue
    fi
    calendar_value="${timestamp:0:19}"
    timezone_hours="${timestamp:20:2}"
    timezone_minutes="${timestamp:22:2}"
    if ! normalized_calendar="$(platform_date_parse '%Y-%m-%dT%H-%M-%S' \
        "$calendar_value" '+%Y-%m-%dT%H-%M-%S' 2>/dev/null)" ||
       [[ "$normalized_calendar" != "$calendar_value" ]] ||
       (( 10#$timezone_hours > 23 || 10#$timezone_minutes > 59 )); then
      log "Aufbewahrung: Ungueltiger Versionszeitpunkt bleibt erhalten: $(safe_name "$name")"
      unknown_count=$((unknown_count + 1))
      continue
    fi
    if ! epoch="$(platform_date_parse '%Y-%m-%dT%H-%M-%S%z' "$timestamp" '+%s' 2>/dev/null)" ||
       [[ ! "$epoch" =~ ^[0-9]+$ ]]; then
      log "Aufbewahrung: Ungueltiger Versionszeitpunkt bleibt erhalten: $(safe_name "$name")"
      unknown_count=$((unknown_count + 1))
      continue
    fi

    age=$((now_epoch - epoch))
    if (( age < 0 )); then
      future_count=$((future_count + 1))
      continue
    fi
    if (( age < 24 * 60 * 60 )); then
      recent_count=$((recent_count + 1))
      continue
    fi

    day="${timestamp:0:10}"
    if (( age <= 30 * 24 * 60 * 60 )); then
      tier="daily"
      bucket="$day"
    elif (( age <= 52 * 7 * 24 * 60 * 60 )); then
      tier="weekly"
      if ! bucket="$(platform_date_parse '%Y-%m-%d' "$day" '+%G-W%V' 2>/dev/null)" ||
         [[ ! "$bucket" =~ ^[0-9]{4}-W[0-9]{2}$ ]]; then
        log "Aufbewahrung: ISO-Woche unklar; Versionsordner bleibt erhalten: $(safe_name "$name")"
        unknown_count=$((unknown_count + 1))
        continue
      fi
    else
      tier="expired"
      bucket=""
    fi

    entry_paths[entry_count]="$path"
    entry_tiers[entry_count]="$tier"
    entry_buckets[entry_count]="$bucket"
    entry_epochs[entry_count]="$epoch"
    entry_count=$((entry_count + 1))

    if [[ "$tier" == "daily" ]]; then
      found=-1
      for ((index = 0; index < daily_count; index++)); do
        if [[ "${daily_buckets[$index]}" == "$bucket" ]]; then
          found=$index
          break
        fi
      done
      if (( found < 0 )); then
        daily_buckets[daily_count]="$bucket"
        daily_keeper_epochs[daily_count]="$epoch"
        daily_keeper_paths[daily_count]="$path"
        daily_count=$((daily_count + 1))
      elif [[ "$epoch" -gt "${daily_keeper_epochs[$found]}" ||
              ( "$epoch" == "${daily_keeper_epochs[$found]}" && "$path" > "${daily_keeper_paths[$found]}" ) ]]; then
        daily_keeper_epochs[found]="$epoch"
        daily_keeper_paths[found]="$path"
      fi
    elif [[ "$tier" == "weekly" ]]; then
      found=-1
      for ((index = 0; index < weekly_count; index++)); do
        if [[ "${weekly_buckets[$index]}" == "$bucket" ]]; then
          found=$index
          break
        fi
      done
      if (( found < 0 )); then
        weekly_buckets[weekly_count]="$bucket"
        weekly_keeper_epochs[weekly_count]="$epoch"
        weekly_keeper_paths[weekly_count]="$path"
        weekly_count=$((weekly_count + 1))
      elif [[ "$epoch" -gt "${weekly_keeper_epochs[$found]}" ||
              ( "$epoch" == "${weekly_keeper_epochs[$found]}" && "$path" > "${weekly_keeper_paths[$found]}" ) ]]; then
        weekly_keeper_epochs[found]="$epoch"
        weekly_keeper_paths[found]="$path"
      fi
    fi
  done

  local pass_index candidate_index selected_index merge_target
  for ((pass_index = 0; pass_index < entry_count; pass_index++)); do
    selected_index=-1
    for ((candidate_index = 0; candidate_index < entry_count; candidate_index++)); do
      [[ "${entry_processed[$candidate_index]-0}" != "1" ]] || continue
      if (( selected_index < 0 )) ||
         [[ "${entry_epochs[$candidate_index]}" -gt "${entry_epochs[$selected_index]}" ]] ||
         [[ "${entry_epochs[$candidate_index]}" == "${entry_epochs[$selected_index]}" &&
            "${entry_paths[$candidate_index]}" > "${entry_paths[$selected_index]}" ]]; then
        selected_index=$candidate_index
      fi
    done
    (( selected_index >= 0 )) || break
    entry_processed[selected_index]=1
    index=$selected_index
    path="${entry_paths[$index]}"
    tier="${entry_tiers[$index]}"
    bucket="${entry_buckets[$index]}"
    keeper_index=-1
    merge_target=""

    if [[ "$tier" == "daily" ]]; then
      for ((found = 0; found < daily_count; found++)); do
        if [[ "${daily_buckets[$found]}" == "$bucket" ]]; then
          keeper_index=$found
          break
        fi
      done
      if (( keeper_index < 0 )); then
        log "WARNUNG: Tages-Bucket unklar; Versionsordner bleibt erhalten: $(safe_name "${path##*/}")"
        continue
      fi
      [[ "$path" != "${daily_keeper_paths[$keeper_index]}" ]] || continue
      merge_target="${daily_keeper_paths[$keeper_index]}"
      bucket="weiterer Stand fuer Kalendertag $bucket"
    elif [[ "$tier" == "weekly" ]]; then
      for ((found = 0; found < weekly_count; found++)); do
        if [[ "${weekly_buckets[$found]}" == "$bucket" ]]; then
          keeper_index=$found
          break
        fi
      done
      if (( keeper_index < 0 )); then
        log "WARNUNG: Wochen-Bucket unklar; Versionsordner bleibt erhalten: $(safe_name "${path##*/}")"
        continue
      fi
      [[ "$path" != "${weekly_keeper_paths[$keeper_index]}" ]] || continue
      merge_target="${weekly_keeper_paths[$keeper_index]}"
      bucket="weiterer Stand fuer ISO-Woche $bucket"
    else
      bucket="aelter als 52 Wochen"
    fi

    candidate_count=$((candidate_count + 1))
    if [[ -n "$merge_target" ]] &&
       ! merge_retention_candidate_into_keeper "$path" "$merge_target" "$bucket"; then
      log "FEHLER: Aufbewahrung wird abgebrochen, damit kein aelterer Dateistand eine fehlgeschlagene neuere Zusammenfuehrung ersetzt."
      return 1
    fi
    if ! move_retention_candidate "$path" "$bucket" "$versions_root"; then
      prune_errors=$((prune_errors + 1))
    fi
  done

  log "Aufbewahrung: geprueft=$((entry_count + recent_count + unknown_count + future_count)) frisch=$recent_count zukunft=$future_count unbekannt=$unknown_count kandidaten=$candidate_count"
  (( prune_errors == 0 ))
}

detect_language() {
  local value="${1:-auto}"
  value="$(lowercase "$value")"

  case "$value" in
    de*) printf 'de' ;;
    en*) printf 'en' ;;
    fr*) printf 'fr' ;;
    es*) printf 'es' ;;
    ja*) printf 'ja' ;;
    yue*|zh-hk*|zh_hk*|zh-hant-hk*|zh_hant_hk*|zh-mo*|zh_mo*) printf 'yue' ;;
    ko*) printf 'ko' ;;
    auto|"")
      local locale
      locale="$(platform_system_locale)"
      locale="$(lowercase "$locale")"
      case "$locale" in
        de*) printf 'de' ;;
        fr*) printf 'fr' ;;
        es*) printf 'es' ;;
        ja*) printf 'ja' ;;
        ko*) printf 'ko' ;;
        yue*|zh-hk*|zh_hk*|zh-hant-hk*|zh_hant_hk*|zh-mo*|zh_mo*) printf 'yue' ;;
        *) printf 'en' ;;
      esac
      ;;
    *) printf 'en' ;;
  esac
}

BACKUP_LANG="$(detect_language "$BACKUP_LANG")"

t() {
  local key="$1"
  case "$BACKUP_LANG:$key" in
    de:not_now) printf 'Nicht jetzt' ;;
    de:start_backup) printf 'Backup starten' ;;
    de:use_volume) printf 'Dieses Volume verwenden?' ;;
    de:use_destination) printf 'Dieses Backup-Ziel verwenden?' ;;
    de:disk_label) printf 'Festplatte' ;;
    de:volume_label) printf 'Volume' ;;
    de:external_disk) printf 'Externe Festplatte' ;;
    de:storage_set) printf 'Speicherverbund' ;;
    de:backup_volume) printf 'Backup-Volume' ;;
    de:create_volume) printf 'Backup-Volume anlegen?' ;;
    de:create_volume_action) printf 'Volume anlegen' ;;
    de:log_confirmed) printf 'Backup durch Benutzer bestaetigt.' ;;
    de:log_skipped) printf 'Backup nicht bestaetigt; ueberspringe.' ;;
    de:log_setup_skipped) printf 'Volume-Einrichtung nicht bestaetigt; ueberspringe.' ;;
    de:progress_preparing) printf 'Wird vorbereitet ...' ;;
    de:progress_done) printf 'Kopiervorgang abgeschlossen.' ;;
    en:not_now) printf 'Not now' ;;
    en:start_backup) printf 'Start backup' ;;
    en:use_volume) printf 'Use this volume?' ;;
    en:use_destination) printf 'Use this backup destination?' ;;
    en:disk_label) printf 'Disk' ;;
    en:volume_label) printf 'Volume' ;;
    en:external_disk) printf 'External disk' ;;
    en:storage_set) printf 'Storage set' ;;
    en:backup_volume) printf 'Backup volume' ;;
    en:create_volume) printf 'Create backup volume?' ;;
    en:create_volume_action) printf 'Create volume' ;;
    en:log_confirmed) printf 'Backup confirmed by user.' ;;
    en:log_skipped) printf 'Backup was not confirmed; skipping.' ;;
    en:log_setup_skipped) printf 'Volume setup was not confirmed; skipping.' ;;
    en:progress_preparing) printf 'Preparing ...' ;;
    en:progress_done) printf 'Copy completed.' ;;
    fr:not_now) printf 'Pas maintenant' ;;
    fr:start_backup) printf 'Sauvegarder' ;;
    fr:use_volume) printf 'Utiliser ce volume ?' ;;
    fr:use_destination) printf 'Utiliser cette destination ?' ;;
    fr:disk_label) printf 'Disque' ;;
    fr:volume_label) printf 'Volume' ;;
    fr:external_disk) printf 'Disque externe' ;;
    fr:storage_set) printf 'Ensemble de stockage' ;;
    fr:backup_volume) printf 'Volume de sauvegarde' ;;
    fr:create_volume) printf 'Créer le volume de sauvegarde ?' ;;
    fr:create_volume_action) printf 'Créer volume' ;;
    fr:log_confirmed) printf 'Sauvegarde confirmée par l utilisateur.' ;;
    fr:log_skipped) printf 'Sauvegarde non confirmée; ignorée.' ;;
    fr:log_setup_skipped) printf 'Création du volume non confirmée; ignorée.' ;;
    fr:progress_preparing) printf 'Préparation ...' ;;
    fr:progress_done) printf 'Copie terminée.' ;;
    es:not_now) printf 'Ahora no' ;;
    es:start_backup) printf 'Iniciar copia' ;;
    es:use_volume) printf '¿Usar este volumen?' ;;
    es:use_destination) printf '¿Usar este destino de copia?' ;;
    es:disk_label) printf 'Disco' ;;
    es:volume_label) printf 'Volumen' ;;
    es:external_disk) printf 'Disco externo' ;;
    es:storage_set) printf 'Conjunto de almacenamiento' ;;
    es:backup_volume) printf 'Volumen de copia' ;;
    es:create_volume) printf '¿Crear volumen de copia?' ;;
    es:create_volume_action) printf 'Crear volumen' ;;
    es:log_confirmed) printf 'Copia confirmada por el usuario.' ;;
    es:log_skipped) printf 'Copia no confirmada; se omite.' ;;
    es:log_setup_skipped) printf 'Configuración del volumen no confirmada; se omite.' ;;
    es:progress_preparing) printf 'Preparando ...' ;;
    es:progress_done) printf 'Copia completada.' ;;
    ja:not_now) printf '今はしない' ;;
    ja:start_backup) printf 'バックアップ開始' ;;
    ja:use_volume) printf 'このボリュームを使いますか？' ;;
    ja:use_destination) printf 'このバックアップ先を使いますか？' ;;
    ja:disk_label) printf 'ディスク' ;;
    ja:volume_label) printf 'ボリューム' ;;
    ja:external_disk) printf '外付けディスク' ;;
    ja:storage_set) printf 'ストレージセット' ;;
    ja:backup_volume) printf 'バックアップボリューム' ;;
    ja:create_volume) printf 'バックアップ用ボリュームを作成？' ;;
    ja:create_volume_action) printf 'ボリューム作成' ;;
    ja:log_confirmed) printf 'ユーザーがバックアップを確認しました。' ;;
    ja:log_skipped) printf 'バックアップは確認されませんでした。スキップします。' ;;
    ja:log_setup_skipped) printf 'ボリューム作成は確認されませんでした。スキップします。' ;;
    ja:progress_preparing) printf '準備中...' ;;
    ja:progress_done) printf 'コピー完了。' ;;
    yue:not_now) printf '暫時唔好' ;;
    yue:start_backup) printf '開始備份' ;;
    yue:use_volume) printf '使用呢個卷宗？' ;;
    yue:use_destination) printf '使用呢個備份目的地？' ;;
    yue:disk_label) printf '硬碟' ;;
    yue:volume_label) printf '卷宗' ;;
    yue:external_disk) printf '外置硬碟' ;;
    yue:storage_set) printf '儲存組合' ;;
    yue:backup_volume) printf '備份卷宗' ;;
    yue:create_volume) printf '建立備份卷宗？' ;;
    yue:create_volume_action) printf '建立卷宗' ;;
    yue:log_confirmed) printf '使用者已確認備份。' ;;
    yue:log_skipped) printf '備份未確認，略過。' ;;
    yue:log_setup_skipped) printf '卷宗設定未確認，略過。' ;;
    yue:progress_preparing) printf '準備中...' ;;
    yue:progress_done) printf '複製完成。' ;;
    ko:not_now) printf '지금 안 함' ;;
    ko:start_backup) printf '백업 시작' ;;
    ko:use_volume) printf '이 볼륨을 사용할까요?' ;;
    ko:use_destination) printf '이 백업 대상을 사용할까요?' ;;
    ko:disk_label) printf '디스크' ;;
    ko:volume_label) printf '볼륨' ;;
    ko:external_disk) printf '외장 디스크' ;;
    ko:storage_set) printf '스토리지 세트' ;;
    ko:backup_volume) printf '백업 볼륨' ;;
    ko:create_volume) printf '백업 볼륨을 만들까요?' ;;
    ko:create_volume_action) printf '볼륨 생성' ;;
    ko:log_confirmed) printf '사용자가 백업을 확인했습니다.' ;;
    ko:log_skipped) printf '백업이 확인되지 않아 건너뜁니다.' ;;
    ko:log_setup_skipped) printf '볼륨 설정이 확인되지 않아 건너뜁니다.' ;;
    ko:progress_preparing) printf '준비 중...' ;;
    ko:progress_done) printf '복사 완료.' ;;
    *) printf '%s' "$key" ;;
  esac
}

progress_escape() {
  local value="${1:-}"
  value="${value//$'\r'/ }"
  value="${value//$'\n'/ }"
  printf '%s' "$value"
}

write_progress() {
  [[ -n "${PROGRESS_FILE:-}" ]] || return 0

  local label="${1:-}"
  local percent="${2:-}"
  local detail="${3:-}"
  local phase="${4:-}"
  local checked="${5:-}"
  local listed="${6:-}"
  local transferred="${7:-}"
  local speed="${8:-}"
  local tmp

  tmp="$(umask 077; mktemp "${PROGRESS_FILE}.tmp.XXXXXX")" || return 1
  if ! (umask 077; {
    printf 'label=%s\n' "$(progress_escape "$label")"
    [[ -n "$phase" ]] && printf 'phase=%s\n' "$(progress_escape "$phase")"
    [[ -n "$percent" ]] && printf 'percent=%s\n' "$(progress_escape "$percent")"
    [[ -n "$detail" ]] && printf 'detail=%s\n' "$(progress_escape "$detail")"
    [[ -n "$checked" ]] && printf 'checked=%s\n' "$checked"
    [[ -n "$listed" ]] && printf 'listed=%s\n' "$listed"
    [[ -n "$transferred" ]] && printf 'transferred=%s\n' "$(progress_escape "$transferred")"
    [[ -n "$speed" ]] && printf 'speed=%s\n' "$(progress_escape "$speed")"
    :
  } >"$tmp" && chmod 600 "$tmp"); then
    cleanup_temp_file "$tmp"
    return 1
  fi
  if ! mv -f "$tmp" "$PROGRESS_FILE"; then
    cleanup_temp_file "$tmp"
    return 1
  fi
}

public_progress_label() {
  case "$1" in
    "My Drive") printf 'My Drive' ;;
    "Shared with me") printf 'Shared with me' ;;
    *) printf 'Shared Drive' ;;
  esac
}

reset_rclone_transfer_progress() {
  RCLONE_PROGRESS_TRANSFERRED=""
  RCLONE_PROGRESS_TOTAL=""
  RCLONE_PROGRESS_PERCENT=""
  RCLONE_PROGRESS_SPEED=""
  RCLONE_PROGRESS_ETA=""
  RCLONE_PROGRESS_DETAIL=""
}

parse_rclone_progress_fields() {
  local line="$1"
  local pattern='^Transferred:[[:space:]]*([0-9][0-9.]*[[:space:]]+([KMGTPE]i)?B)[[:space:]]+/[[:space:]]+([0-9][0-9.]*[[:space:]]+([KMGTPE]i)?B),[[:space:]]+([0-9]{1,3})%,[[:space:]]+([0-9][0-9.]*[[:space:]]+([KMGTPE]i)?B/s),[[:space:]]+ETA[[:space:]]+(-|([0-9]+[dhms])+)$'
  local transferred total percent speed eta
  [[ "$line" =~ $pattern ]] || return 1
  transferred="${BASH_REMATCH[1]}"
  total="${BASH_REMATCH[3]}"
  percent="${BASH_REMATCH[5]}"
  speed="${BASH_REMATCH[6]}"
  eta="${BASH_REMATCH[8]}"
  [[ "${transferred%% *}" =~ ^[0-9]+([.][0-9]+)?$ &&
     "${total%% *}" =~ ^[0-9]+([.][0-9]+)?$ &&
     "${speed%% *}" =~ ^[0-9]+([.][0-9]+)?$ &&
     "$percent" -le 100 ]] || return 1
  RCLONE_PROGRESS_TRANSFERRED="$transferred"
  RCLONE_PROGRESS_TOTAL="$total"
  RCLONE_PROGRESS_PERCENT="$percent"
  RCLONE_PROGRESS_SPEED="$speed"
  RCLONE_PROGRESS_ETA="$eta"
  RCLONE_PROGRESS_DETAIL="$RCLONE_PROGRESS_TRANSFERRED / $RCLONE_PROGRESS_TOTAL, $RCLONE_PROGRESS_SPEED, ETA $RCLONE_PROGRESS_ETA"
}

parse_rclone_unknown_total_progress() {
  local line="$1"
  local pattern='^Transferred:[[:space:]]*([0-9][0-9.]*[[:space:]]+([KMGTPE]i)?B)[[:space:]]+/[[:space:]]+(0[[:space:]]+B|off),[[:space:]]+-,[[:space:]]+([0-9][0-9.]*[[:space:]]+([KMGTPE]i)?B/s),[[:space:]]+ETA[[:space:]]+-$'
  local transferred speed
  [[ "$line" =~ $pattern ]] || return 1
  transferred="${BASH_REMATCH[1]}"
  speed="${BASH_REMATCH[4]}"
  [[ "${transferred%% *}" =~ ^[0-9]+([.][0-9]+)?$ &&
     "${speed%% *}" =~ ^[0-9]+([.][0-9]+)?$ ]] || return 1
  RCLONE_PROGRESS_TRANSFERRED="$transferred"
  RCLONE_PROGRESS_TOTAL=""
  RCLONE_PROGRESS_PERCENT=""
  RCLONE_PROGRESS_SPEED="$speed"
  RCLONE_PROGRESS_ETA=""
  RCLONE_PROGRESS_DETAIL=""
}

parse_rclone_check_progress() {
  local line="$1"
  local pattern='^Checks:[[:space:]]*([0-9]{1,18})[[:space:]]*/[[:space:]]*[0-9]{1,18},[[:space:]]*(-|[0-9]{1,3}%)[[:space:]]*,[[:space:]]*Listed[[:space:]]+([0-9]{1,18})$'
  local check_percent
  [[ "$line" =~ $pattern ]] || return 1
  check_percent="${BASH_REMATCH[2]}"
  if [[ "$check_percent" != "-" ]]; then
    check_percent="${check_percent%%%}"
    (( 10#$check_percent <= 100 )) || return 1
  fi
  RCLONE_PROGRESS_CHECKED="${BASH_REMATCH[1]}"
  RCLONE_PROGRESS_LISTED="${BASH_REMATCH[3]}"
}

write_durable_progress() {
  local label="${1:-preparing}" percent="${2:-}" detail="${3:-}" phase="${4:-}"
  local checked="${5:-}" listed="${6:-}"
  local transferred="${7:-}" speed="${8:-}"
  local directory temporary existing_owner phase_current phase_total
  [[ -n "$DURABLE_PROGRESS_FILE" ]] || return 0
  case "$label" in preparing|"My Drive"|"Shared with me"|"Shared Drive") ;; *) return 1 ;; esac
  [[ -z "$phase" || "$phase" =~ ^[1-9][0-9]*/[1-9][0-9]*$ ]] || return 1
  if [[ -n "$phase" ]]; then
    phase_current="${phase%/*}"
    phase_total="${phase#*/}"
    [[ "$phase_current" -le "$phase_total" && "$phase_total" -le 9999 ]] || return 1
  fi
  [[ -z "$percent" || ( "$percent" =~ ^[0-9]+$ && "$percent" -le 100 ) ]] || return 1
  if [[ -n "$detail" && "$detail" != "${RCLONE_PROGRESS_DETAIL:-}" ]]; then return 1; fi
  if [[ -n "$checked" || -n "$listed" ]]; then
    [[ "$checked" =~ ^[0-9]{1,18}$ && "$listed" =~ ^[0-9]{1,18}$ ]] || return 1
  fi
  if [[ -n "$transferred" || -n "$speed" ]]; then
    [[ "$label" != "preparing" &&
       ${#transferred} -le 32 && ${#speed} -le 34 &&
       "$transferred" =~ ^[0-9]+([.][0-9]+)?[[:space:]]+([KMGTPE]i)?B$ &&
       "$speed" =~ ^[0-9]+([.][0-9]+)?[[:space:]]+([KMGTPE]i)?B/s$ ]] || return 1
  fi
  [[ ! -L "$DURABLE_PROGRESS_FILE" ]] || return 1
  [[ ! -e "$DURABLE_PROGRESS_FILE" || -f "$DURABLE_PROGRESS_FILE" ]] || return 1
  if [[ -e "$DURABLE_PROGRESS_FILE" ]]; then
    existing_owner="$(platform_stat_owner "$DURABLE_PROGRESS_FILE")" || return 1
    [[ "$existing_owner" == "$(id -u)" ]] || return 1
  fi
  directory="${DURABLE_PROGRESS_FILE%/*}"
  (umask 077 && mkdir -p "$directory") || return 1
  temporary="$(umask 077; mktemp "${DURABLE_PROGRESS_FILE}.tmp.XXXXXX")" || return 1
  if ! (umask 077; {
      printf 'protocol=1\nprofile_id=%s\npid=%s\nstarted_at=%s\ntrigger=%s\n' \
        "$PROGRESS_PROFILE_ID" "$$" "$RUN_STARTED_AT" "$BACKUP_TRIGGER"
      [[ -n "$RETRY_ATTEMPT" ]] && printf 'retry_attempt=%s\n' "$RETRY_ATTEMPT"
      printf 'label=%s\n' "$label"
      [[ -n "$phase" ]] && printf 'phase=%s\n' "$phase"
      [[ -n "$percent" ]] && printf 'percent=%s\n' "$percent"
      [[ -n "$detail" ]] && printf 'detail=%s\n' "$detail"
      [[ -n "$checked" ]] && printf 'checked=%s\n' "$checked"
      [[ -n "$listed" ]] && printf 'listed=%s\n' "$listed"
      [[ -n "$transferred" ]] && printf 'transferred=%s\n' "$transferred"
      [[ -n "$speed" ]] && printf 'speed=%s\n' "$speed"
      printf 'updated_at=%s\n' "$(date +%s)"
    } >"$temporary" && chmod 600 "$temporary"); then
    cleanup_temp_file "$temporary"
    return 1
  fi
  mv -f "$temporary" "$DURABLE_PROGRESS_FILE"
}

initialize_durable_progress() {
  [[ "$DRY_RUN" == "0" && "$SETUP_UI" == "0" ]] || return 0
  [[ "$PROGRESS_PROFILE_ID" =~ ^[a-z0-9][a-z0-9-]{0,63}$ ]] || return 0
  if [[ -z "$DURABLE_PROGRESS_FILE" ]]; then
    DURABLE_PROGRESS_FILE="${SUMMARY_STATE_FILE%/*}/current-progress.status"
  fi
  write_durable_progress "preparing" "" "" ""
}

finish_durable_progress() {
  local directory temporary existing_owner
  [[ "$DRY_RUN" == "0" && "$SETUP_UI" == "0" ]] || return 0
  [[ -n "$DURABLE_PROGRESS_FILE" ]] || return 0
  [[ "$PROGRESS_PROFILE_ID" =~ ^[a-z0-9][a-z0-9-]{0,63}$ ]] || return 0
  [[ ! -L "$DURABLE_PROGRESS_FILE" ]] || return 1
  [[ ! -e "$DURABLE_PROGRESS_FILE" || -f "$DURABLE_PROGRESS_FILE" ]] || return 1
  if [[ -e "$DURABLE_PROGRESS_FILE" ]]; then
    existing_owner="$(platform_stat_owner "$DURABLE_PROGRESS_FILE")" || return 1
    [[ "$existing_owner" == "$(id -u)" ]] || return 1
  fi
  directory="${DURABLE_PROGRESS_FILE%/*}"
  (umask 077 && mkdir -p "$directory") || return 1
  temporary="$(umask 077; mktemp "${DURABLE_PROGRESS_FILE}.tmp.XXXXXX")" || return 1
  if ! (umask 077; {
      printf 'protocol=1\nprofile_id=%s\npid=%s\nstarted_at=%s\ntrigger=%s\n' \
        "$PROGRESS_PROFILE_ID" "$$" "$RUN_STARTED_AT" "$BACKUP_TRIGGER"
      [[ -n "$RETRY_ATTEMPT" ]] && printf 'retry_attempt=%s\n' "$RETRY_ATTEMPT"
      printf 'status=finished\nupdated_at=%s\n' "$(date +%s)"
    } >"$temporary" && chmod 600 "$temporary"); then
    cleanup_temp_file "$temporary"
    return 1
  fi
  mv -f "$temporary" "$DURABLE_PROGRESS_FILE"
}

warn_progress_unavailable() {
  if [[ "${DURABLE_PROGRESS_WARNING_LOGGED:-0}" != "1" ]]; then
    log "WARNUNG: Backup-Fortschritt konnte nicht sicher aktualisiert werden."
    DURABLE_PROGRESS_WARNING_LOGGED=1
  fi
}

warn_state_publication_unavailable() {
  if [[ "${RUN_STATE_WARNING_LOGGED:-0}" != "1" ]]; then
    log "WARNUNG: Backup-Status konnte nicht sicher aktualisiert werden."
    RUN_STATE_WARNING_LOGGED=1
  fi
}

write_run_state() {
  [[ -n "$RUN_STATE_FILE" ]] || return 0

  local status="$1"
  local exit_code="${2:-}"
  local tmp
  [[ ! -L "$RUN_STATE_FILE" ]] || return 1
  [[ ! -e "$RUN_STATE_FILE" || ( -f "$RUN_STATE_FILE" && -O "$RUN_STATE_FILE" ) ]] || return 1
  tmp="$(umask 077; mktemp "${RUN_STATE_FILE}.tmp.XXXXXX")" || return 1
  if ! (umask 077; {
    printf 'protocol=1\n'
    printf 'status=%s\n' "$status"
    printf 'pid=%s\n' "$$"
    [[ -n "$RUN_STATE_REASON" ]] && printf 'reason=%s\n' "$RUN_STATE_REASON"
    [[ -n "$RUN_STATE_SIGNAL" ]] && printf 'signal=%s\n' "$RUN_STATE_SIGNAL"
    [[ -n "$RETRY_ORIGIN_STARTED_AT" ]] &&
      printf 'retry_origin_started_at=%s\n' "$RETRY_ORIGIN_STARTED_AT"
    [[ -n "$RETRY_ATTEMPT" ]] && printf 'retry_attempt=%s\n' "$RETRY_ATTEMPT"
    [[ -n "$exit_code" ]] && printf 'exit_code=%s\n' "$exit_code"
  } >"$tmp" && chmod 600 "$tmp"); then
    cleanup_temp_file "$tmp"
    return 1
  fi
  if ! mv -f "$tmp" "$RUN_STATE_FILE"; then
    cleanup_temp_file "$tmp"
    return 1
  fi
}

write_last_run_summary() {
  local status="$1"
  local exit_code="${2:-}"
  local summary_dir tmp finished_at last_success_at=""
  local last_success_target="" last_success_destination="" last_success_volume=""
  local old_protocol="" old_status="" old_started="" old_finished="" old_exit=""
  local old_target="" old_destination="" key value successful_volume successful_destination
  local success_nas="" success_apfs="" window_started="" window_attempts=""

  [[ "$DRY_RUN" == "0" && "$SETUP_UI" == "0" ]] || return 2
  # A lock-contended process did not perform a backup and must not replace the
  # status of the process that actually owns the destination.
  [[ "$status" != "skipped" ]] || return 2
  [[ -n "$SUMMARY_STATE_FILE" ]] || return 2

  summary_dir="${SUMMARY_STATE_FILE%/*}"
  [[ "$summary_dir" != "$SUMMARY_STATE_FILE" ]] || summary_dir="."
  (umask 077 && mkdir -p "$summary_dir") || return 1
  tmp="${SUMMARY_STATE_FILE}.$$"
  finished_at="$(date +%s 2>/dev/null || printf '0')"
  if [[ -f "$SUMMARY_STATE_FILE" ]]; then
    while IFS='=' read -r key value; do
      case "$key" in
        protocol) old_protocol="$value" ;;
        status) old_status="$value" ;;
        started_at) old_started="$value" ;;
        finished_at) old_finished="$value" ;;
        exit_code) old_exit="$value" ;;
        target) old_target="$value" ;;
        destination) old_destination="$value" ;;
        last_success_at) last_success_at="$value" ;;
        last_success_target) last_success_target="$value" ;;
        last_success_destination) last_success_destination="$value" ;;
        last_success_volume) last_success_volume="$value" ;;
        last_success_at_nas) success_nas="$value" ;;
        last_success_at_apfs) success_apfs="$value" ;;
        daily_window_started_at) window_started="$value" ;;
        daily_window_attempts) window_attempts="$value" ;;
      esac
    done <"$SUMMARY_STATE_FILE"
    # Recover the previous successful target before the running record replaces it.
    # A timestamp left by a failed attempt cannot identify that earlier target.
    if [[ "$old_protocol" == "1" && "$old_status" == "success" && "$old_exit" == "0" &&
          "$old_started" =~ ^[0-9]{1,12}$ && "$old_finished" =~ ^[0-9]{1,12}$ ]] &&
        (( 10#$old_started > 0 && 10#$old_finished >= 10#$old_started )); then
      if [[ "$last_success_at" != "$old_finished" || -z "$last_success_destination" ]]; then
        last_success_volume=""
        last_success_target="$old_target"
        last_success_destination="$old_destination"
        if [[ "$old_destination" == "$PLATFORM_VOLUMES_ROOT"/* ]]; then
          last_success_volume="${old_destination#"$PLATFORM_VOLUMES_ROOT"/}"
          last_success_volume="${last_success_volume%%/*}"
        fi
      fi
      last_success_at="$old_finished"
    fi
  fi
  if [[ "$old_protocol" != "1" || ! "$last_success_at" =~ ^[0-9]{1,12}$ ]] ||
      (( 10#${last_success_at:-0} <= 0 || 10#${last_success_at:-0} > finished_at )); then
    last_success_at=""
    last_success_target=""
    last_success_destination=""
    last_success_volume=""
  fi
  # One profile can back up to its scheduled destination and to an attached
  # disk. Track each destination's last success separately, so a success on
  # one never hides that the other is overdue. Older summaries carry only the
  # most recent success; adopt it for the destination it names.
  if [[ ! "$success_nas" =~ ^[0-9]{1,12}$ ]] || (( 10#$success_nas > finished_at )); then
    success_nas=""
  fi
  if [[ ! "$success_apfs" =~ ^[0-9]{1,12}$ ]] || (( 10#$success_apfs > finished_at )); then
    success_apfs=""
  fi
  if [[ -n "$last_success_at" ]]; then
    case "$last_success_target" in
      nas) [[ -n "$success_nas" ]] || success_nas="$last_success_at" ;;
      apfs) [[ -n "$success_apfs" ]] || success_apfs="$last_success_at" ;;
    esac
  fi
  if [[ "$status" == "success" ]]; then
    case "$BACKUP_TARGET" in
      nas) success_nas="$finished_at" ;;
      apfs) success_apfs="$finished_at" ;;
    esac
  fi
  if [[ -n "$DAILY_WINDOW_STARTED_AT" && -n "$DAILY_WINDOW_ATTEMPTS" ]]; then
    window_started="$DAILY_WINDOW_STARTED_AT"
    window_attempts="$DAILY_WINDOW_ATTEMPTS"
  elif [[ ! "$window_started" =~ ^[0-9]{1,12}$ || ! "$window_attempts" =~ ^[0-9]{1,3}$ ]]; then
    window_started=""
    window_attempts=""
  fi
  if [[ "$status" == "success" ]]; then
    last_success_at="$finished_at"
    last_success_target="$BACKUP_TARGET"
    last_success_destination="$DEST_ROOT"
    last_success_volume=""
    # A destination override can point outside the selected disk, including via
    # a symlink. Only name that disk when the successful destination is inside it.
    if successful_volume="$(canonical_existing_directory "$VOLUME")" &&
        successful_destination="$(canonical_existing_directory "$DEST_ROOT")" &&
        [[ "$successful_destination" == "$successful_volume" ||
           "$successful_destination" == "$successful_volume"/* ]]; then
      last_success_volume="${successful_volume##*/}"
    fi
  fi

  if (umask 077 && {
    printf 'protocol=1\n'
    printf 'status=%s\n' "$status"
    printf 'pid=%s\n' "$$"
    printf 'started_at=%s\n' "$RUN_STARTED_AT"
    if [[ "$status" != "running" ]]; then
      printf 'finished_at=%s\n' "$finished_at"
    fi
    [[ -n "$last_success_at" ]] && printf 'last_success_at=%s\n' "$last_success_at"
    if [[ -n "$last_success_at" ]]; then
      [[ -n "$last_success_target" ]] && printf 'last_success_target=%s\n' "$(progress_escape "$last_success_target")"
      [[ -n "$last_success_destination" ]] && printf 'last_success_destination=%s\n' "$(progress_escape "$last_success_destination")"
      [[ -n "$last_success_volume" ]] && printf 'last_success_volume=%s\n' "$(progress_escape "$last_success_volume")"
    fi
    [[ -n "$success_nas" ]] && printf 'last_success_at_nas=%s\n' "$success_nas"
    [[ -n "$success_apfs" ]] && printf 'last_success_at_apfs=%s\n' "$success_apfs"
    if [[ -n "$window_started" ]]; then
      printf 'daily_window_started_at=%s\n' "$window_started"
      printf 'daily_window_attempts=%s\n' "$window_attempts"
    fi
    [[ -n "$exit_code" ]] && printf 'exit_code=%s\n' "$exit_code"
    [[ -n "$RUN_STATE_REASON" ]] && printf 'reason=%s\n' "$(progress_escape "$RUN_STATE_REASON")"
    [[ -n "$RUN_STATE_SIGNAL" ]] && printf 'signal=%s\n' "$(progress_escape "$RUN_STATE_SIGNAL")"
    printf 'trigger=%s\n' "$(progress_escape "$BACKUP_TRIGGER")"
    [[ -n "$RETRY_ORIGIN_STARTED_AT" ]] &&
      printf 'retry_origin_started_at=%s\n' "$RETRY_ORIGIN_STARTED_AT"
    [[ -n "$RETRY_ATTEMPT" ]] && printf 'retry_attempt=%s\n' "$RETRY_ATTEMPT"
    printf 'target=%s\n' "$(progress_escape "$BACKUP_TARGET")"
    printf 'destination=%s\n' "$(progress_escape "$DEST_ROOT")"
  } >"$tmp") && chmod 600 "$tmp" && mv -f "$tmp" "$SUMMARY_STATE_FILE"; then
    return 0
  fi

  cleanup_temp_file "$tmp"
  return 1
}

# Run history: one tab-separated line per finished run, oldest first.
#   v1 <TAB> finished_at <TAB> status <TAB> target <TAB> destination
#      <TAB> trigger <TAB> started_at
#      [<TAB> volume_uuid <TAB> device <TAB> bytes <TAB> solid <TAB> bus]
# The device fields describe an external disk at the end of the run; readers
# must accept lines without them (NAS runs, older lines, a vanished disk).
# status is success, failure or cancelled; times are epoch seconds. Lines
# rebuilt from the log before the history existed carry the trigger "log".
history_field() {
  local value="${1-}"
  value="${value//$'\t'/ }"
  value="${value//$'\n'/ }"
  value="${value//$'\r'/ }"
  printf '%s' "$value"
}

history_record() {
  printf 'v1\t%s\t%s\t%s\t%s\t%s\t%s' "$1" "$2" "$(history_field "$3")" \
    "$(history_field "$4")" "$(history_field "$5")" "$6"
  # Optional device fields: volume uuid, device name, size, solid state, bus.
  [[ -z "${7-}" ]] || printf '\t%s' "$7"
  printf '\n'
}

# "[2026-11-26 20:00:05+0100]" -> epoch, through the platform's date parser.
log_timestamp_epoch() {
  local stamp="$1"
  [[ "$stamp" =~ ^([0-9]{4}-[0-9]{2}-[0-9]{2})\ ([0-9]{2}):([0-9]{2}):([0-9]{2})([+-][0-9]{4})$ ]] || return 1
  platform_date_parse '%Y-%m-%dT%H-%M-%S%z' \
    "${BASH_REMATCH[1]}T${BASH_REMATCH[2]}-${BASH_REMATCH[3]}-${BASH_REMATCH[4]}${BASH_REMATCH[5]}" '+%s'
}

# Older versions kept no history. Rebuild completed runs from the current and
# the rotated log once, so the first view is not empty. Runs whose end is not
# in the log (still running, skipped, killed) are left out.
seed_run_history_from_log() {
  local started finished status target destination started_at finished_at
  {
    [[ -f "${LOG}.1.gz" ]] && /usr/bin/gzip -dc "${LOG}.1.gz" 2>/dev/null
    [[ -f "$LOG" ]] && cat "$LOG" 2>/dev/null
  } | LC_ALL=C awk '
    match($0, /^\[[0-9-]+ [0-9:]+[+-][0-9]+\] /) {
      stamp = substr($0, 2, RLENGTH - 3)
      text = substr($0, RLENGTH + 1)
      if (text ~ /^Start: remote=.* dry_run=0 target=(nas|apfs) /) {
        target = text; sub(/.* target=/, "", target); sub(/ .*/, "", target)
        dest = text; if (!sub(/.* dest=/, "", dest)) dest = ""
        open_start = stamp; open_target = target; open_dest = dest
        next
      }
      if (open_start == "") next
      status = ""
      if (text == "Fertig ohne Fehler." || text ~ /^Fertig: Backup erfolgreich/) status = "success"
      else if (text ~ /^Fertig mit [0-9]+ Fehler/) status = "failure"
      if (status != "") {
        printf "%s\t%s\t%s\t%s\t%s\n", open_start, stamp, status, open_target, open_dest
        open_start = ""
      }
    }' |
  while IFS=$'\t' read -r started finished status target destination; do
    started_at="$(log_timestamp_epoch "$started" 2>/dev/null)" || continue
    finished_at="$(log_timestamp_epoch "$finished" 2>/dev/null)" || continue
    # The running process has already logged its own start; it is recorded
    # by append_run_history with its real outcome instead.
    if [[ "$RUN_STARTED_AT" =~ ^[0-9]+$ ]] && (( RUN_STARTED_AT > 0 && started_at >= RUN_STARTED_AT )); then
      continue
    fi
    history_record "$finished_at" "$status" "$target" "$destination" "log" "$started_at"
  done | tail -n "$RUN_HISTORY_MAX_LINES"
}

append_run_history() {
  local status="$1" directory tmp finished_at device_info
  [[ "$DRY_RUN" == "0" && "$SETUP_UI" == "0" && -n "$RUN_HISTORY_FILE" ]] || return 0
  case "$status" in
    success|failure|cancelled) ;;
    *) return 0 ;;
  esac
  [[ "$BACKUP_TARGET" == "nas" || "$BACKUP_TARGET" == "apfs" ]] || return 0

  directory="${RUN_HISTORY_FILE%/*}"
  [[ "$directory" != "$RUN_HISTORY_FILE" ]] || directory="."
  (umask 077 && mkdir -p "$directory") || return 1
  [[ ! -L "$RUN_HISTORY_FILE" ]] || return 1
  [[ ! -e "$RUN_HISTORY_FILE" || -f "$RUN_HISTORY_FILE" ]] || return 1
  finished_at="$(date +%s 2>/dev/null)" || return 1
  device_info=""
  # Only a successful run has validated the destination's identity; a
  # rejected or unverified volume must not be queried after the fact.
  if [[ "$status" == "success" && "$BACKUP_TARGET" == "apfs" && -d "$VOLUME" ]]; then
    device_info="$(platform_destination_device_info "$VOLUME" 2>/dev/null | head -n 1 || true)"
    # Exactly five tab-separated fields, or nothing.
    [[ "$(printf '%s' "$device_info" | tr -cd '\t' | wc -c | tr -d ' ')" == "4" &&
       ! "${device_info//$'\t'/}" =~ [[:cntrl:]] ]] || device_info=""
  fi

  tmp="${RUN_HISTORY_FILE}.$$"
  if ! (umask 077 && {
      if [[ -f "$RUN_HISTORY_FILE" ]]; then
        tail -n "$((RUN_HISTORY_MAX_LINES - 1))" "$RUN_HISTORY_FILE"
      else
        seed_run_history_from_log | tail -n "$((RUN_HISTORY_MAX_LINES - 1))"
      fi
      history_record "$finished_at" "$status" "$BACKUP_TARGET" "$DEST_ROOT" \
        "$BACKUP_TRIGGER" "$RUN_STARTED_AT" "$device_info"
    } >"$tmp") || ! chmod 600 "$tmp" || ! mv -f "$tmp" "$RUN_HISTORY_FILE"; then
    cleanup_temp_file "$tmp"
    return 1
  fi
}

# Epoch of the most recent daily window boundary at or before the given time.
daily_window_start_epoch() {
  local now="$1" day boundary

  day="$(platform_date_from_epoch "$now" '+%Y-%m-%d' 2>/dev/null)" || return 1
  boundary="$(platform_date_parse '%Y-%m-%d %H:%M:%S' \
    "$day $(printf '%02d' "$DAILY_WINDOW_HOUR"):00:00" '+%s' 2>/dev/null)" || return 1
  [[ "$boundary" =~ ^[0-9]+$ ]] || return 1
  if (( boundary > now )); then
    day="$(platform_date_from_epoch "$((now - 86400))" '+%Y-%m-%d' 2>/dev/null)" || return 1
    boundary="$(platform_date_parse '%Y-%m-%d %H:%M:%S' \
      "$day $(printf '%02d' "$DAILY_WINDOW_HOUR"):00:00" '+%s' 2>/dev/null)" || return 1
    [[ "$boundary" =~ ^[0-9]+$ ]] || return 1
  fi
  printf '%s' "$boundary"
}

# Decide what an hourly firing of the daily schedule should do:
#   done      - this window already has a success for the destination
#   primary   - first attempt of the window; failures are reported as before
#   catchup   - an earlier attempt failed; probe quietly and run if possible
#   exhausted - the window used all of its attempts
# Any uncertainty falls back to "primary", which is the previous behavior.
classify_daily_schedule_run() {
  local now="$RUN_STARTED_AT" window key value
  local success="" generic="" generic_target="" recorded_window="" recorded_attempts=""

  DAILY_RUN_KIND="primary"
  [[ "$now" =~ ^[0-9]+$ ]] && (( now > 0 )) || return 0
  window="$(daily_window_start_epoch "$now")" || return 0
  if [[ -f "$SUMMARY_STATE_FILE" && ! -L "$SUMMARY_STATE_FILE" ]]; then
    while IFS='=' read -r key value; do
      case "$key" in
        "last_success_at_$BACKUP_TARGET") success="$value" ;;
        last_success_at) generic="$value" ;;
        last_success_target) generic_target="$value" ;;
        daily_window_started_at) recorded_window="$value" ;;
        daily_window_attempts) recorded_attempts="$value" ;;
      esac
    done <"$SUMMARY_STATE_FILE"
  fi
  if [[ -z "$success" && "$generic_target" == "$BACKUP_TARGET" ]]; then
    success="$generic"
  fi

  DAILY_WINDOW_STARTED_AT="$window"
  DAILY_WINDOW_ATTEMPTS=1
  if [[ "$success" =~ ^[0-9]{1,12}$ ]] &&
     (( 10#$success >= window && 10#$success <= now )); then
    DAILY_RUN_KIND="done"
    return 0
  fi
  if [[ "$recorded_window" == "$window" && "$recorded_attempts" =~ ^[0-9]{1,3}$ ]] &&
     (( 10#$recorded_attempts >= 1 )); then
    if (( 10#$recorded_attempts >= DAILY_WINDOW_MAX_ATTEMPTS )); then
      DAILY_RUN_KIND="exhausted"
      return 0
    fi
    DAILY_WINDOW_ATTEMPTS=$((10#$recorded_attempts + 1))
    DAILY_RUN_KIND="catchup"
    CATCHUP_QUIET=1
  fi
  return 0
}

# A catch-up firing found the destination still unavailable. That is the
# expected state while a NAS is off or a disk is detached, so the run ends
# without touching the recorded result of the real attempt.
skip_quiet_catchup() {
  RUN_OUTCOME="skipped"
  RUN_STATE_REASON="catchup_target_unavailable"
  log "Nachhol-Lauf: Backup-Ziel weiterhin nicht verfuegbar; der naechste Versuch folgt automatisch."
  exit 0
}

check_destination_free_space() {
  local probe="$DEST_ROOT" available_kb

  [[ -d "$probe" ]] || probe="$VOLUME"
  available_kb="$(/bin/df -Pk "$probe" 2>/dev/null | /usr/bin/awk 'NR == 2 { print $4 }')"
  [[ "$available_kb" =~ ^[0-9]+$ ]] || return 0
  log "Freier Speicher am Ziel: $((available_kb / 1048576)) GB"
  if (( MIN_FREE_MB > 0 && available_kb / 1024 < MIN_FREE_MB )); then
    RUN_STATE_REASON="destination_full"
    log "FEHLER: Am Backup-Ziel sind weniger als $MIN_FREE_MB MB frei; es wird nichts kopiert."
    return 1
  fi
  return 0
}

finish_run_state() {
  local exit_status="$1"
  local status="$RUN_OUTCOME"
  if [[ "$RUN_STATE_OVERRIDE" == "cancelled" ]]; then
    status="cancelled"
  fi
  local summary_status=0
  write_run_state "$status" "$exit_status"
  write_last_run_summary "$status" "$exit_status" || summary_status=$?
  # The history is informational: a failure there is logged but never changes
  # the result callers act on, which is the summary publication.
  append_run_history "$status" ||
    log "WARNUNG: Backup-Verlauf konnte nicht fortgeschrieben werden."
  return "$summary_status"
}

update_progress_from_rclone_line() {
  local label="$1"
  local phase="$2"
  local line="$3"

  # Keep check counters across each stats block, but never pair them with a
  # stale transfer percentage if rclone changes or emits an unknown format.
  if [[ "$line" == Transferred:* ]]; then
    reset_rclone_transfer_progress
  fi
  if parse_rclone_progress_fields "$line"; then
    write_progress "$label" "$RCLONE_PROGRESS_PERCENT" "$RCLONE_PROGRESS_DETAIL" \
      "$phase" "$RCLONE_PROGRESS_CHECKED" "$RCLONE_PROGRESS_LISTED" \
      "$RCLONE_PROGRESS_TRANSFERRED" "$RCLONE_PROGRESS_SPEED"
    if ! write_durable_progress "$(public_progress_label "$label")" \
        "$RCLONE_PROGRESS_PERCENT" "$RCLONE_PROGRESS_DETAIL" "$phase" \
        "$RCLONE_PROGRESS_CHECKED" "$RCLONE_PROGRESS_LISTED" \
        "$RCLONE_PROGRESS_TRANSFERRED" "$RCLONE_PROGRESS_SPEED"; then
      warn_progress_unavailable
      write_progress "$label" "" "" "$phase"
      write_durable_progress "$(public_progress_label "$label")" "" "" "$phase" || true
    fi
  elif parse_rclone_unknown_total_progress "$line"; then
    write_progress "$label" "" "" "$phase" \
      "$RCLONE_PROGRESS_CHECKED" "$RCLONE_PROGRESS_LISTED" \
      "$RCLONE_PROGRESS_TRANSFERRED" "$RCLONE_PROGRESS_SPEED"
    if ! write_durable_progress "$(public_progress_label "$label")" "" "" "$phase" \
        "$RCLONE_PROGRESS_CHECKED" "$RCLONE_PROGRESS_LISTED" \
        "$RCLONE_PROGRESS_TRANSFERRED" "$RCLONE_PROGRESS_SPEED"; then
      warn_progress_unavailable
    fi
  elif parse_rclone_check_progress "$line"; then
    write_progress "$label" "$RCLONE_PROGRESS_PERCENT" "$RCLONE_PROGRESS_DETAIL" \
      "$phase" "$RCLONE_PROGRESS_CHECKED" "$RCLONE_PROGRESS_LISTED" \
      "$RCLONE_PROGRESS_TRANSFERRED" "$RCLONE_PROGRESS_SPEED"
    if ! write_durable_progress "$(public_progress_label "$label")" \
        "$RCLONE_PROGRESS_PERCENT" "$RCLONE_PROGRESS_DETAIL" "$phase" \
        "$RCLONE_PROGRESS_CHECKED" "$RCLONE_PROGRESS_LISTED" \
        "$RCLONE_PROGRESS_TRANSFERRED" "$RCLONE_PROGRESS_SPEED"; then
      warn_progress_unavailable
    fi
  fi
}

run_rclone_with_progress() {
  local label="$1"
  local phase="$2"
  shift 2

  local line status error_class_file="" collision_report="" collision_path=""
  local collision_prefix="" collision_kind=""
  local detected_count=0 parsed_count=0 unhandled_count=0
  reset_rclone_transfer_progress
  RCLONE_PROGRESS_CHECKED=""
  RCLONE_PROGRESS_LISTED=""
  LAST_RCLONE_COLLISION_REPORT=""
  if ! error_class_file="$(mktemp "${TMPDIR:-/tmp}/gdrive-backup-error-class.XXXXXX")"; then
    log "FEHLER: Die rclone-Auswertung konnte nicht sicher vorbereitet werden."
    RUN_STATE_REASON="internal_state_unavailable"
    return 70
  fi
  if ! collision_report="$(mktemp "${TMPDIR:-/tmp}/gdrive-backup-collisions.XXXXXX")"; then
    cleanup_temp_file "$error_class_file"
    log "FEHLER: Die Drive-Kollisionsauswertung konnte nicht sicher vorbereitet werden."
    RUN_STATE_REASON="internal_state_unavailable"
    return 70
  fi
  # rclone repeats an identical statistics block every ten seconds. The
  # progress display consumes each one, but the log keeps only the first, one
  # per five minutes, and every final (NOTICE) block. Per-file lines, warnings
  # and errors are always logged.
  local stats_block=0 stats_keep=1 stats_logged_at=-300
  "$@" 2>&1 | while IFS= read -r line; do
    if [[ "$line" == *" INFO  : " || "$line" == *" NOTICE: " ]]; then
      stats_block=1
      if [[ "$line" == *" NOTICE: " ]] || (( SECONDS - stats_logged_at >= 300 )); then
        stats_keep=1
        stats_logged_at=$SECONDS
      else
        stats_keep=0
      fi
    elif [[ "$stats_block" == "1" &&
            ( -z "$line" || "$line" =~ ^[0-9]{4}/[0-9]{2}/[0-9]{2}[[:space:]] ) ]]; then
      stats_block=0
      if [[ -z "$line" && "$stats_keep" == "0" ]]; then
        update_progress_from_rclone_line "$label" "$phase" "$line"
        continue
      fi
      stats_keep=1
    fi
    if [[ "$stats_block" == "0" || "$stats_keep" == "1" ]]; then
      printf '%s\n' "$line"
    fi
    update_progress_from_rclone_line "$label" "$phase" "$line"
    if [[ -n "$error_class_file" && "$line" == *"Failed to copy:"* &&
          ( "$line" == *"permission denied"* || "$line" == *"Permission denied"* ||
            "$line" == *"access denied"* || "$line" == *"Access denied"* ) ]]; then
      printf 'destination_permission_denied\n' >>"$error_class_file"
    fi
    # Google Drive permits equal names. rclone normally logs that it ignored
    # one of them but exits zero, which must not be mistaken for a complete
    # backup. Case/Unicode collisions on a case-insensitive NAS are equivalent.
    if [[ -n "$error_class_file" &&
          ( "$line" == *"Duplicate object found in source - ignoring"* ||
            "$line" == *"Duplicate directory found in source - ignoring"* ||
            ( "$line" == *"duplicate filename"* &&
              "$line" == *"case/unicode normalization"* ) ) ]]; then
      printf 'source_name_collision\n' >>"$error_class_file"
    fi
    if [[ "$line" == *"Duplicate object found in source - ignoring"* ||
          "$line" == *"Duplicate directory found in source - ignoring"* ]]; then
      printf 'source_exact_collision_detected\n' >>"$error_class_file"
    elif [[ "$line" == *"duplicate filename"* &&
            "$line" == *"case/unicode normalization"* ]]; then
      printf 'source_collision_unhandled\n' >>"$error_class_file"
    fi
    collision_kind=""
    collision_prefix=""
    if [[ "$line" == *": Duplicate object found in source - ignoring"* ]]; then
      collision_kind="file"
      collision_prefix="${line%: Duplicate object found in source - ignoring*}"
    elif [[ "$line" == *": Duplicate directory found in source - ignoring"* ]]; then
      collision_kind="directory"
      collision_prefix="${line%: Duplicate directory found in source - ignoring*}"
    fi
    if [[ -n "$collision_kind" && -n "$collision_report" &&
          "$collision_prefix" == *"NOTICE: "* ]]; then
      collision_path="${collision_prefix#*"NOTICE: "}"
      if [[ -n "$collision_path" && "$collision_path" != /* &&
            ! "$collision_path" =~ [[:cntrl:]] ]]; then
        case "/$collision_path/" in
          *"//"*|*"/./"*|*"/../"*) ;;
          *)
            printf '%s\t%s\n' "$collision_kind" "$collision_path" >>"$collision_report"
            printf 'source_exact_collision_parsed\n' >>"$error_class_file"
            ;;
        esac
      fi
    fi
  done
  status=${PIPESTATUS[0]}
  if [[ "$status" != "0" && -n "$error_class_file" ]]; then
    if /usr/bin/grep -Fxq 'destination_permission_denied' "$error_class_file"; then
      RUN_STATE_REASON="destination_permission_denied"
    fi
  elif [[ "$status" == "0" && -n "$error_class_file" ]] &&
       /usr/bin/grep -Fxq 'source_name_collision' "$error_class_file"; then
    RUN_STATE_REASON="source_name_collision"
    status=65
    detected_count="$(/usr/bin/grep -Fxc 'source_exact_collision_detected' \
      "$error_class_file" 2>/dev/null || true)"
    parsed_count="$(/usr/bin/grep -Fxc 'source_exact_collision_parsed' \
      "$error_class_file" 2>/dev/null || true)"
    unhandled_count="$(/usr/bin/grep -Fxc 'source_collision_unhandled' \
      "$error_class_file" 2>/dev/null || true)"
    if (( detected_count > 0 && detected_count == parsed_count &&
          unhandled_count == 0 )); then
      LAST_RCLONE_COLLISION_REPORT="$collision_report"
      collision_report=""
      log "Google Drive enthaelt gleichnamige Eintraege; die separaten Drive-IDs werden gesichert."
    else
      log "FEHLER: Nicht jede erkannte Drive-Kollision kann sicher einer ID-Gruppe zugeordnet werden."
    fi
  fi
  cleanup_temp_file "$error_class_file"
  cleanup_temp_file "$collision_report"
  return "$status"
}

start_animation() {
  if [[ "$DRY_RUN" == "1" || "${BACKUP_DISABLE_ANIMATION:-0}" == "1" ||
        "${BACKUP_PROGRESS_FOREGROUND:-0}" != "1" ]]; then
    return
  fi

  if [[ ! -d "$ANIMATION_APP" ]]; then
    log "WARNUNG: Backup-Animation nicht gefunden: $ANIMATION_APP"
    return
  fi

  ANIMATION_SENTINEL="$(mktemp "$BASE_TMPDIR/gdrive-backup-ui.XXXXXX")" || {
    log "WARNUNG: Sentinel fuer Backup-Animation konnte nicht angelegt werden."
    return
  }
  printf '%s\n' "$$" >"$ANIMATION_SENTINEL"

  PROGRESS_FILE="$(mktemp "$BASE_TMPDIR/gdrive-backup-progress.XXXXXX")" || {
    log "WARNUNG: Fortschrittsdatei fuer Backup-Animation konnte nicht angelegt werden."
    PROGRESS_FILE=""
  }
  if [[ -n "$PROGRESS_FILE" ]]; then
    write_progress "Google Drive Backup" "" "$(t progress_preparing)" ""
  fi

  if [[ -z "$RUN_STATE_FILE" ]]; then
    RUN_STATE_FILE="$(mktemp "$BASE_TMPDIR/gdrive-backup-state.XXXXXX")" || {
      log "WARNUNG: Ergebnisdatei fuer Backup-Animation konnte nicht angelegt werden."
      cleanup_temp_file "$ANIMATION_SENTINEL" "$PROGRESS_FILE"
      ANIMATION_SENTINEL=""
      PROGRESS_FILE=""
      return
    }
    RUN_STATE_IS_TEMP=1
  fi
  write_run_state "running"

  local -a animation_arguments=("$ANIMATION_SENTINEL" "$PROGRESS_FILE" "$RUN_STATE_FILE")
  if [[ "${BACKUP_PROGRESS_FOREGROUND:-0}" == "1" ]]; then
    animation_arguments+=("--foreground")
  fi

  if "$OPEN_BIN" -n "$ANIMATION_APP" --args "${animation_arguments[@]}" >/dev/null 2>&1; then
    log "Backup-Animation gestartet."
  else
    log "WARNUNG: Backup-Animation konnte nicht gestartet werden."
    cleanup_temp_file "$ANIMATION_SENTINEL"
    ANIMATION_SENTINEL=""
    cleanup_temp_file "$PROGRESS_FILE"
    PROGRESS_FILE=""
    if [[ "$RUN_STATE_IS_TEMP" == "1" ]]; then
      cleanup_temp_file "$RUN_STATE_FILE"
      RUN_STATE_FILE=""
      RUN_STATE_IS_TEMP=0
    fi
  fi
}

stop_animation() {
  if [[ -n "${ANIMATION_SENTINEL:-}" ]]; then
    cleanup_temp_file "$ANIMATION_SENTINEL"
    ANIMATION_SENTINEL=""
  fi
  if [[ -n "${PROGRESS_FILE:-}" ]]; then
    cleanup_temp_file "$PROGRESS_FILE"
    PROGRESS_FILE=""
  fi
}

cleanup() {
  local exit_status="$1"
  local summary_publish_status=0
  # Publish the terminal result before the sentinel disappears, so the UI can
  # never infer success merely from process cleanup.
  finish_run_state "$exit_status"
  summary_publish_status=$?
  if [[ "$summary_publish_status" == "0" && "$DURABLE_PROGRESS_OWNED" == "1" ]]; then
    if ! finish_durable_progress; then
      warn_progress_unavailable
    fi
  elif [[ "$summary_publish_status" == "1" ]]; then
    # Keep the last live record intact. Its PID check makes it invalid as soon
    # as this process exits, without ever claiming a terminal backup result.
    warn_state_publication_unavailable
  fi
  stop_animation
  if [[ -n "$STALL_WATCHDOG_PID" ]]; then
    kill "$STALL_WATCHDOG_PID" 2>/dev/null || true
    STALL_WATCHDOG_PID=""
  fi
  if [[ -n "$NAS_WATCHDOG_PID" ]]; then
    kill "$NAS_WATCHDOG_PID" 2>/dev/null || true
    NAS_WATCHDOG_PID=""
  fi
  if [[ -n "$RUN_TMPDIR" && -d "$RUN_TMPDIR" && ! -L "$RUN_TMPDIR" ]]; then
    /bin/rm -rf -- "$RUN_TMPDIR" 2>/dev/null || true
  fi
}

# Watch the log as the run's heartbeat. rclone reports at least every five
# minutes and every other step logs when it starts, so a silent log means the
# run is blocked, typically in a network file system call that never returns.
# The watchdog ends the blocked child first; the engine then records the
# cancellation itself. Only if that fails is the engine killed.
start_stall_watchdog() {
  local engine=$$ interval="${GDRIVE_BACKUP_STALL_CHECK_SECONDS:-60}"

  (( STALL_SECONDS > 0 )) || return 0
  (
    # The watchdog must not keep the backup lock alive.
    exec 9>&-
    self="$(/bin/sh -c 'echo $PPID')"
    while kill -0 "$engine" 2>/dev/null; do
      /bin/sleep "$interval"
      modified="$(platform_stat_mtime "$LOG" 2>/dev/null || printf '0')"
      now="$(/bin/date '+%s')"
      [[ "$modified" =~ ^[0-9]+$ && "$now" =~ ^[0-9]+$ ]] || continue
      (( now - modified >= STALL_SECONDS )) || continue
      printf '[%s] ABBRUCH: Seit %s Sekunden ohne Fortschritt; der blockierte Lauf wird beendet.\n' \
        "$(/bin/date '+%Y-%m-%d %H:%M:%S%z')" "$STALL_SECONDS" >>"$LOG"
      for signal in TERM KILL; do
        for child in $(/usr/bin/pgrep -P "$engine" 2>/dev/null); do
          [[ "$child" == "$self" ]] || kill "-$signal" "$child" 2>/dev/null || true
        done
        kill -0 "$engine" 2>/dev/null || exit 0
        [[ "$signal" == "KILL" ]] || kill -TERM "$engine" 2>/dev/null || true
        /bin/sleep 10
        kill -0 "$engine" 2>/dev/null || exit 0
      done
      kill -KILL "$engine" 2>/dev/null || true
      exit 0
    done
  ) >/dev/null 2>&1 &
  STALL_WATCHDOG_PID=$!
}

# A vanished SMB mount does not stop a running rclone copy: it fails every
# remaining file one by one, which keeps the log busy for hours and therefore
# hides the hang from the stall watchdog. This watchdog checks the mount once
# per interval and, after three consecutive misses, ends only the engine's own
# rclone processes. The engine's existing post-transfer validation then
# records nas_connection_lost and skips the remaining areas.
list_descendant_pids() {
  local child
  for child in $(/usr/bin/pgrep -P "$1" 2>/dev/null); do
    printf '%s\n' "$child"
    list_descendant_pids "$child"
  done
}

start_nas_watchdog() {
  local engine=$$ interval="${GDRIVE_BACKUP_NAS_WATCH_SECONDS:-60}"

  [[ "$BACKUP_TARGET" == "nas" && "$DRY_RUN" == "0" ]] || return 0
  [[ "$interval" =~ ^[1-9][0-9]{0,3}$ ]] || interval=60
  (
    # The watchdog must not keep the backup lock alive.
    exec 9>&-
    misses=0
    while kill -0 "$engine" 2>/dev/null; do
      /bin/sleep "$interval"
      if nas_mount_is_verified; then
        misses=0
        continue
      fi
      misses=$((misses + 1))
      (( misses >= 3 )) || continue
      stopped=0
      for pid in $(list_descendant_pids "$engine"); do
        command_line="$(/bin/ps -o command= -p "$pid" 2>/dev/null)" || continue
        case "$command_line" in
          rclone\ *|*/rclone\ *)
            kill -TERM "$pid" 2>/dev/null && stopped=1
            ;;
        esac
      done
      if (( stopped == 1 )); then
        printf '[%s] FEHLER: NAS-Verbindung ist seit %s Pruefungen getrennt; die laufende Kopie wird beendet.\n' \
          "$(/bin/date '+%Y-%m-%d %H:%M:%S%z')" "$misses" >>"$LOG"
      fi
    done
  ) >/dev/null 2>&1 &
  NAS_WATCHDOG_PID=$!
}

# Create this run's scratch directory and drop directories that a killed
# earlier run (power loss, forced restart) could not remove itself.
prepare_run_tmpdir() {
  local stale

  if [[ -d "$BASE_TMPDIR" ]]; then
    while IFS= read -r stale; do
      [[ -n "$stale" && -d "$stale" && ! -L "$stale" ]] || continue
      /bin/rm -rf -- "$stale" 2>/dev/null || true
    done < <(/usr/bin/find "$BASE_TMPDIR" -maxdepth 1 -type d \
      -name 'gdrive-backup-run.??????' -user "$(/usr/bin/id -un)" -mtime +1 2>/dev/null)
  fi
  if RUN_TMPDIR="$(/usr/bin/mktemp -d "$BASE_TMPDIR/gdrive-backup-run.XXXXXX" 2>/dev/null)"; then
    TMPDIR="$RUN_TMPDIR"
    export TMPDIR
  else
    RUN_TMPDIR=""
  fi
}

on_exit() {
  local exit_status=$?
  cleanup "$exit_status"
}

cancel_run() {
  RUN_STATE_OVERRIDE="cancelled"
  RUN_STATE_SIGNAL="$2"
  # Without this line an interrupted run (logout, restart, manual stop) ends
  # mid-transfer in the log and cannot be told apart from a crash.
  log "ABBRUCH: Backup wurde durch Signal $2 beendet (Abmelden, Neustart oder Stopp)."
  exit "$1"
}

run_with_timeout() {
  local seconds="$1"
  shift

  "$@" &
  local command_pid=$!

  (
    sleep "$seconds"
    kill "$command_pid" 2>/dev/null || true
    # A process stuck in a network file system call can ignore TERM.
    sleep 5
    kill -KILL "$command_pid" 2>/dev/null || true
  ) >/dev/null 2>&1 &
  local killer_pid=$!

  wait "$command_pid"
  local status=$?
  kill "$killer_pid" 2>/dev/null || true
  wait "$killer_pid" 2>/dev/null || true
  return "$status"
}

display_metadata_value() {
  local value="${1:-}"

  # Disk labels come from removable media. Reject control characters rather
  # than forwarding untrusted formatting into the dialog or backup log.
  if [[ "$value" =~ [[:cntrl:]] ]]; then
    return 0
  fi
  value="$(printf '%s' "$value" | /usr/bin/sed -E \
    -e 's/^[[:space:]]+//' -e 's/[[:space:]]+$//' -e 's/[[:space:]]+/ /g')"

  # Bidirectional format characters can make a device label visually claim a
  # different identity. Keep the display metadata plain and reasonably short;
  # the actual trust decision continues to use the validated APFS UUID.
  local marker
  for marker in \
    "$(printf '\330\234')" \
    "$(printf '\342\200\216')" "$(printf '\342\200\217')" \
    "$(printf '\342\200\252')" "$(printf '\342\200\253')" \
    "$(printf '\342\200\254')" "$(printf '\342\200\255')" \
    "$(printf '\342\200\256')" \
    "$(printf '\342\201\246')" "$(printf '\342\201\247')" \
    "$(printf '\342\201\250')" "$(printf '\342\201\251')"; do
    if [[ "$value" == *"$marker"* ]]; then
      return 0
    fi
  done
  if (( ${#value} > 96 )); then
    return 0
  fi
  printf '%s' "$value"
}

first_valid_size_value() {
  local value

  for value in "$@"; do
    if [[ "$value" =~ ^[0-9]+$ && "$value" != "0" ]]; then
      printf '%s' "$value"
      return 0
    fi
  done
  return 1
}

first_nonempty_display_value() {
  local candidate value

  for candidate in "$@"; do
    value="$(display_metadata_value "$candidate")"
    if [[ -n "$value" ]]; then
      printf '%s' "$value"
      return 0
    fi
  done
  return 1
}

decimal_capacity_label() {
  local bytes="${1:-}"

  [[ "$bytes" =~ ^[0-9]+$ && "$bytes" != "0" ]] || return 0
  LC_ALL=C /usr/bin/awk -v bytes="$bytes" 'BEGIN {
    split("B KB MB GB TB PB", units, " ")
    value = bytes + 0
    unit = 1
    while (value >= 1000 && unit < 6) {
      value /= 1000
      unit++
    }
    if (unit == 1 || value >= 100) {
      formatted = sprintf("%.0f", value)
    } else {
      formatted = sprintf("%.1f", value)
      sub(/\.0$/, "", formatted)
    }
    printf "%s %s", formatted, units[unit]
  }'
}

confirm_prompt() {
  local title="$1"
  local detail="$2"
  local primary_button="$3"
  local require_human="${4:-0}"
  local secondary_button
  secondary_button="$(t not_now)"

  if [[ "$require_human" != "1" &&
        ( "$CONFIRM_BACKUP" == "0" || "${BACKUP_ASSUME_YES:-0}" == "1" ) ]]; then
    return 0
  fi

  local response=""
  local decision=""

  log "Warte auf Benutzerbestaetigung: $title $detail"

  if [[ -d "$ANIMATION_APP" ]]; then
    response="$(mktemp "$BASE_TMPDIR/gdrive-backup-confirm.XXXXXX")" || {
      log "FEHLER: Bestaetigungsdatei konnte nicht angelegt werden."
      return 1
    }
    : >"$response"

    local -a confirmation_arguments=(
      --confirm "$title" "$detail" "$primary_button" "$secondary_button" "$response"
    )
    if [[ "${BACKUP_PROGRESS_FOREGROUND:-0}" == "1" ]]; then
      confirmation_arguments+=(--foreground)
    fi

    if "$OPEN_BIN" -W -n "$ANIMATION_APP" --args "${confirmation_arguments[@]}" >/dev/null 2>&1; then
      decision="$(tr -d '\r\n' <"$response" 2>/dev/null || true)"
    fi
    cleanup_temp_file "$response"

    if [[ "$decision" == "yes" ]]; then
      return 0
    fi

    return 1
  fi

  if platform_confirm_dialog_available; then
    decision="$(platform_confirm_dialog "$title" "$detail" "$primary_button" "$secondary_button")" || decision="no"

    if [[ "$decision" == "yes" ]]; then
      return 0
    fi
  fi

  return 1
}

confirm_backup_target() {
  if [[ "$DRY_RUN" == "1" || "$TARGET_APPROVED" == "1" ]]; then
    return 0
  fi

  local title
  local detail="$VOLUME"
  if [[ "$BACKUP_TARGET" == "nas" ]]; then
    title="$(t use_destination)"
    detail="$DEST_ROOT"
  else
    title="$(t use_volume)"
    if [[ "$CONFIRM_BACKUP" != "0" && "${BACKUP_ASSUME_YES:-0}" != "1" ]]; then
      detail="$(external_volume_confirmation_detail)"
    fi
  fi

  if confirm_prompt "$title" "$detail" "$(t start_backup)"; then
    TARGET_APPROVED=1
    # Only an answered backup-consent prompt promotes this mount run. Setup
    # consent and unattended confirmation bypasses must remain passive.
    if [[ "$BACKUP_TRIGGER" == "mount" && "$CONFIRM_BACKUP" != "0" &&
          "${BACKUP_ASSUME_YES:-0}" != "1" ]]; then
      BACKUP_PROGRESS_FOREGROUND=1
    fi
    if [[ "$CONFIRM_BACKUP" == "0" || "${BACKUP_ASSUME_YES:-0}" == "1" ]]; then
      # Nobody was asked: do not record a user confirmation that never happened.
      log "Backup-Ziel ohne Rueckfrage freigegeben (automatischer Lauf oder Bestaetigung deaktiviert)."
    else
      log "$(t log_confirmed)"
    fi
    return 0
  fi

  log "$(t log_skipped)"
  return 1
}

setup_source_identity_matches() {
  local source_mount="$1"
  local expected_container="$2"
  local expected_volume_uuid="$3"
  local expected_container_uuid="$4"
  local expected_physical_store_uuids="$5"
  local target_policy="${6:-allow}"
  local expected_target_uuid="${7:-}"
  local identity_status=0

  capture_setup_source_identity "$source_mount" "$expected_container" ||
    identity_status=$?
  [[ "$identity_status" == "0" ]] || return "$identity_status"
  if [[ "$SETUP_SOURCE_VOLUME_UUID" != "$expected_volume_uuid" ||
        "$SETUP_SOURCE_CONTAINER_UUID" != "$expected_container_uuid" ||
        "$SETUP_SOURCE_PHYSICAL_STORE_UUIDS" != "$expected_physical_store_uuids" ]]; then
    return 1
  fi
  case "$target_policy" in
    allow) return 0 ;;
    absent)
      [[ "$SETUP_TARGET_EXACT_COUNT" == "0" &&
         "$SETUP_TARGET_NUMERIC_COUNT" == "0" ]] || return 2
      ;;
    unique)
      [[ "$expected_target_uuid" =~ ^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$ &&
         "$SETUP_TARGET_EXACT_COUNT" == "1" &&
         "$SETUP_TARGET_NUMERIC_COUNT" == "0" &&
         "$SETUP_TARGET_EXACT_UUIDS" == "$(normalized_apfs_uuid "$expected_target_uuid")" ]] || return 2
      ;;
    *) return 1 ;;
  esac
  return 0
}

new_apfs_volume_uuid_since() {
  local before_file="$1"
  local after_file="$2"
  local diff_file count

  diff_file="$(mktemp "${TMPDIR:-/tmp}/gdrive-new-apfs-uuid.XXXXXX")" ||
    return 3
  /usr/bin/comm -13 "$before_file" "$after_file" >"$diff_file"
  count="$(/usr/bin/wc -l <"$diff_file" | /usr/bin/tr -d '[:space:]')"
  case "$count" in
    1)
      cat "$diff_file"
      cleanup_temp_file "$diff_file" >/dev/null
      return 0
      ;;
    0)
      cleanup_temp_file "$diff_file" >/dev/null
      return 1
      ;;
    *)
      cleanup_temp_file "$diff_file" >/dev/null
      return 2
      ;;
  esac
}

persist_volume_config() {
  local created_uuid="$1"
  local config_dir temp_config

  if [[ ! "$created_uuid" =~ ^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$ ]]; then
    log "FEHLER: Neu angelegtes APFS-Volume hat keine gueltige Volume-UUID."
    return 1
  fi
  config_dir="$(/usr/bin/dirname "$CONFIG_FILE")"
  mkdir -p "$config_dir" || return 1
  temp_config="$(mktemp "${CONFIG_FILE}.tmp.XXXXXX")" || return 1
  if [[ -f "$CONFIG_FILE" ]]; then
    /usr/bin/awk '
      !/^GDRIVE_BACKUP_TARGET=/ &&
      !/^GDRIVE_BACKUP_VOLUME=/ &&
      !/^GDRIVE_BACKUP_DEST_ROOT=/ &&
      !/^GDRIVE_BACKUP_VOLUME_NAME=/ &&
      !/^GDRIVE_BACKUP_VOLUME_UUID=/ &&
      !/^GDRIVE_BACKUP_AUTO_CREATE_VOLUME=/
    ' "$CONFIG_FILE" >"$temp_config" || {
      cleanup_temp_file "$temp_config"
      return 1
    }
  fi
  {
    printf 'GDRIVE_BACKUP_TARGET=apfs\n'
    LC_ALL=C printf 'GDRIVE_BACKUP_VOLUME=%q\n' "$VOLUME"
    LC_ALL=C printf 'GDRIVE_BACKUP_DEST_ROOT=%q\n' "$DEST_ROOT"
    LC_ALL=C printf 'GDRIVE_BACKUP_VOLUME_NAME=%q\n' "$BACKUP_VOLUME_NAME"
    LC_ALL=C printf 'GDRIVE_BACKUP_VOLUME_UUID=%q\n' "$created_uuid"
    printf 'GDRIVE_BACKUP_AUTO_CREATE_VOLUME=1\n'
  } >>"$temp_config"
  /bin/chmod 600 "$temp_config" || {
    cleanup_temp_file "$temp_config"
    return 1
  }
  if ! /bin/mv "$temp_config" "$CONFIG_FILE"; then
    cleanup_temp_file "$temp_config"
    return 1
  fi
  BACKUP_VOLUME_UUID="$(normalized_apfs_uuid "$created_uuid")"
  CONFIGURED_APFS_VOLUME="$VOLUME"
  CONFIGURED_APFS_DEST_ROOT="$DEST_ROOT"
  return 0
}

bind_existing_apfs_volume_by_path() {
  local initial_uuid initial_container initial_mount initial_identifier initial_device

  if [[ "$BACKUP_TRIGGER" != "setup" ]]; then
    log "FEHLER: Ein APFS-Ziel ohne gespeicherte UUID darf nur in der interaktiven Einrichtung gebunden werden."
    return 1
  fi
  if ! inspect_path_only_apfs_binding "$VOLUME"; then
    return 1
  fi
  initial_uuid="$INSPECTED_BINDING_UUID"
  initial_container="$INSPECTED_BINDING_CONTAINER"
  initial_mount="$INSPECTED_BINDING_MOUNT"
  initial_identifier="$INSPECTED_BINDING_IDENTIFIER"
  initial_device="$INSPECTED_BINDING_DEVICE"

  if ! confirm_prompt "$(t use_volume)" "$initial_mount" "$(t start_backup)" 1; then
    log "APFS-Volume-Bindung abgebrochen."
    return 1
  fi
  if ! inspect_path_only_apfs_binding "$initial_mount" ||
     [[ "$INSPECTED_BINDING_UUID" != "$initial_uuid" ||
        "$INSPECTED_BINDING_CONTAINER" != "$initial_container" ||
        "$INSPECTED_BINDING_MOUNT" != "$initial_mount" ||
        "$INSPECTED_BINDING_IDENTIFIER" != "$initial_identifier" ||
        "$INSPECTED_BINDING_DEVICE" != "$initial_device" ]]; then
    log "FEHLER: Das APFS-Volume hat sich waehrend der Bestaetigung geaendert."
    return 1
  fi
  if ! recover_existing_named_apfs_volume "$initial_container" "$initial_uuid"; then
    return 1
  fi
  TARGET_APPROVED=1
  return 0
}

confirm_apfs_volume_creation() {
  local source_name="$1"

  if [[ "$BACKUP_TRIGGER" != "setup" ]]; then
    log "FEHLER: Nur die interaktive Einrichtung darf ein APFS-Volume anlegen."
    return 1
  fi
  # Backup-start approval is intentionally broader than permission to mutate
  # disk layout. Only the snapshotted one-shot setup capability can bypass UI.
  if [[ "$APPROVE_VOLUME_CREATION" == "1" ]]; then
    return 0
  fi
  confirm_prompt "$(t create_volume)" "${source_name} -> ${BACKUP_VOLUME_NAME}" "$(t create_volume_action)" 1
}

admit_appeared_apfs_candidate() {
  local candidate_uuid="$1"
  local source_mount="$2"
  local container="$3"
  local expected_source_volume_uuid="$4"
  local expected_source_container_uuid="$5"
  local expected_source_physical_store_uuids="$6"
  local identity_status=0

  setup_source_identity_matches \
    "$source_mount" "$container" \
    "$expected_source_volume_uuid" "$expected_source_container_uuid" \
    "$expected_source_physical_store_uuids" unique "$candidate_uuid" ||
    identity_status=$?
  case "$identity_status" in
    0)
      CREATED_APFS_VOLUME_UUID="$candidate_uuid"
      return 0
      ;;
    1)
      log "FEHLER: Die stabile Identitaet des freigegebenen APFS-Ausgangscontainers hat sich geaendert. Das erschienene Ziel-Volume wird nicht verwendet."
      ;;
    *)
      log "FEHLER: Das erschienene APFS-Ziel ist nicht mehr der einzige eindeutige Kandidat. Es wird nicht verwendet."
      ;;
  esac
  return 1
}

ensure_backup_volume() {
  if [[ -z "$BACKUP_VOLUME_UUID" && "$BACKUP_TRIGGER" != "setup" ]]; then
    log "FEHLER: Ein APFS-Ziel ohne gespeicherte UUID darf nur durch die interaktive Einrichtung gebunden oder angelegt werden."
    return 1
  fi
  if [[ -d "$VOLUME" ]]; then
    if [[ -n "$BACKUP_VOLUME_UUID" ]]; then
      return 0
    fi
    bind_existing_apfs_volume_by_path
    return $?
  fi

  log "Backup-Volume noch nicht vorhanden: $VOLUME"

  if [[ "$ENCRYPTION" == "apfs" ]]; then
    log "FEHLER: Verschluesseltes APFS muss bereits entsperrt und gemountet sein; ein unverschluesseltes Volume wird nicht automatisch angelegt."
    return 1
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    log "DRY-RUN: Volume-Setup wird nicht ausgefuehrt."
    return 1
  fi

  if [[ "$AUTO_CREATE_VOLUME" != "1" ]]; then
    log "Automatisches APFS-Volume-Setup ist deaktiviert."
    return 1
  fi

  local candidate candidate_status source_mount container source_name named_count
  local initial_source_volume_uuid initial_source_container_uuid
  local initial_source_physical_store_uuids
  local fresh_candidate fresh_candidate_status fresh_container
  local fresh_file fresh_count
  local before_file after_file candidate_uuid detect_status resolve_status
  candidate_status=0
  candidate="$(find_setup_candidate)" || candidate_status=$?
  case "$candidate_status" in
    0) ;;
    1)
      log "Kein geeignetes externes APFS-Volume fuer die Einrichtung gefunden."
      return 1
      ;;
    *)
      log "FEHLER: Mehrere geeignete externe APFS-Container wurden gefunden. Waehle das Backup-Volume explizit aus."
      return 1
      ;;
  esac

  IFS=$'\t' read -r source_mount container source_name <<<"$candidate"
  if ! capture_setup_source_identity "$source_mount" "$container"; then
    log "FEHLER: Die stabile Identitaet des APFS-Ausgangscontainers konnte nicht ermittelt werden."
    return 1
  fi
  initial_source_volume_uuid="$SETUP_SOURCE_VOLUME_UUID"
  initial_source_container_uuid="$SETUP_SOURCE_CONTAINER_UUID"
  initial_source_physical_store_uuids="$SETUP_SOURCE_PHYSICAL_STORE_UUIDS"
  before_file="$(mktemp "${TMPDIR:-/tmp}/gdrive-apfs-before.XXXXXX")" ||
    return 1
  if ! capture_named_apfs_volume_uuids "$container" "$before_file"; then
    cleanup_temp_file "$before_file"
    log "FEHLER: Vorhandene APFS-Volumes konnten nicht sicher erfasst werden."
    return 1
  fi
  named_count="$(/usr/bin/wc -l <"$before_file" | /usr/bin/tr -d '[:space:]')"
  case "$named_count" in
    0) ;;
    1)
      candidate_uuid="$(cat "$before_file")"
      cleanup_temp_file "$before_file"
      if recover_existing_named_apfs_volume \
        "$container" "$candidate_uuid" "$source_mount" \
        "$initial_source_volume_uuid" "$initial_source_container_uuid" \
        "$initial_source_physical_store_uuids"; then
        return 0
      fi
      return 1
      ;;
    *)
      cleanup_temp_file "$before_file"
      log "FEHLER: Mehrere gleichnamige APFS-Volumes wurden gefunden. Waehle das gewuenschte Volume explizit aus; es wurde nichts angelegt oder geloescht."
      return 1
      ;;
  esac

  if ! confirm_apfs_volume_creation "$source_name"; then
    cleanup_temp_file "$before_file"
    log "$(t log_setup_skipped)"
    return 1
  fi

  # Confirmation is an intentional scheduling gap. Re-establish both the sole
  # source container and the exact-name UUID baseline immediately before add.
  fresh_candidate_status=0
  fresh_candidate="$(find_setup_candidate)" || fresh_candidate_status=$?
  if [[ "$fresh_candidate_status" == "0" ]]; then
    fresh_container="${fresh_candidate#*$'\t'}"
    fresh_container="${fresh_container%%$'\t'*}"
  fi
  if [[ "$fresh_candidate_status" != "0" || "$fresh_container" != "$container" ]] ||
     ! capture_setup_source_identity "$source_mount" "$container" ||
     [[ "$SETUP_SOURCE_VOLUME_UUID" != "$initial_source_volume_uuid" ||
        "$SETUP_SOURCE_CONTAINER_UUID" != "$initial_source_container_uuid" ||
        "$SETUP_SOURCE_PHYSICAL_STORE_UUIDS" != "$initial_source_physical_store_uuids" ]]; then
    cleanup_temp_file "$before_file"
    log "FEHLER: Die stabile Identitaet des APFS-Ausgangscontainers hat sich waehrend der Bestaetigung geaendert. Es wurde kein Volume angelegt."
    return 1
  fi
  fresh_file="$(mktemp "${TMPDIR:-/tmp}/gdrive-apfs-confirmed.XXXXXX")" || {
    cleanup_temp_file "$before_file"
    return 1
  }
  if ! capture_named_apfs_volume_uuids "$container" "$fresh_file"; then
    cleanup_temp_file "$fresh_file"
    cleanup_temp_file "$before_file"
    log "FEHLER: APFS-Volumes konnten nach der Bestaetigung nicht sicher erfasst werden."
    return 1
  fi
  fresh_count="$(/usr/bin/wc -l <"$fresh_file" | /usr/bin/tr -d '[:space:]')"
  case "$fresh_count" in
    0)
      cleanup_temp_file "$before_file"
      before_file="$fresh_file"
      ;;
    1)
      candidate_uuid="$(cat "$fresh_file")"
      cleanup_temp_file "$fresh_file"
      cleanup_temp_file "$before_file"
      if recover_existing_named_apfs_volume \
        "$container" "$candidate_uuid" "$source_mount" \
        "$initial_source_volume_uuid" "$initial_source_container_uuid" \
        "$initial_source_physical_store_uuids"; then
        TARGET_APPROVED=1
        return 0
      fi
      return 1
      ;;
    *)
      cleanup_temp_file "$fresh_file"
      cleanup_temp_file "$before_file"
      log "FEHLER: Mehrere gleichnamige APFS-Volumes wurden nach der Bestaetigung gefunden; es wurde nichts angelegt."
      return 1
      ;;
  esac

  log "Lege APFS-Volume '$BACKUP_VOLUME_NAME' im Container $container an (Ausgangsvolume: $source_mount)."
  if ! create_apfs_backup_volume \
    "$container" "$before_file" "$source_mount" \
    "$initial_source_volume_uuid" "$initial_source_container_uuid" \
    "$initial_source_physical_store_uuids"; then
    cleanup_temp_file "$before_file"
    log "FEHLER: APFS-Volume konnte nicht angelegt werden."
    return 1
  fi

  for _ in {1..30}; do
    candidate_uuid="$CREATED_APFS_VOLUME_UUID"
    detect_status=0
    if [[ -z "$candidate_uuid" ]]; then
      after_file="$(mktemp "${TMPDIR:-/tmp}/gdrive-apfs-after.XXXXXX")" || {
        cleanup_temp_file "$before_file"
        return 1
      }
      if ! capture_named_apfs_volume_uuids "$container" "$after_file"; then
        cleanup_temp_file "$after_file"
        cleanup_temp_file "$before_file"
        log "FEHLER: APFS-Volumes konnten nach dem Anlegen nicht sicher verglichen werden."
        return 1
      fi
      candidate_uuid="$(new_apfs_volume_uuid_since "$before_file" "$after_file")" ||
        detect_status=$?
      cleanup_temp_file "$after_file"
    fi
    case "$detect_status" in
      0)
        if ! admit_appeared_apfs_candidate \
          "$candidate_uuid" "$source_mount" "$container" \
          "$initial_source_volume_uuid" "$initial_source_container_uuid" \
          "$initial_source_physical_store_uuids"; then
          cleanup_temp_file "$before_file"
          BACKUP_VOLUME_UUID=""
          return 1
        fi
        BACKUP_VOLUME_UUID="$candidate_uuid"
        resolve_status=0
        resolve_configured_apfs_volume || resolve_status=$?
        if [[ "$resolve_status" == "0" ]]; then
          if ! admit_appeared_apfs_candidate \
            "$candidate_uuid" "$source_mount" "$container" \
            "$initial_source_volume_uuid" "$initial_source_container_uuid" \
            "$initial_source_physical_store_uuids"; then
            cleanup_temp_file "$before_file"
            BACKUP_VOLUME_UUID=""
            return 1
          fi
          cleanup_temp_file "$before_file"
          TARGET_APPROVED=1
          if ! persist_volume_config "$candidate_uuid"; then
            log "FEHLER: Identitaet des neuen APFS-Volumes konnte nicht gespeichert werden."
            return 1
          fi
          log "Backup-Volume bereit: $VOLUME"
          return 0
        fi
        ;;
      1) ;;
      *)
        cleanup_temp_file "$before_file"
        log "FEHLER: Mehr als ein neues gleichnamiges APFS-Volume wurde gefunden."
        return 1
        ;;
    esac
    if [[ -n "$CREATED_APFS_VOLUME_UUID" ]]; then
      # The UUID is known, but the volume is not safely mounted yet.
      BACKUP_VOLUME_UUID=""
    fi
    sleep 1
  done

  cleanup_temp_file "$before_file"
  log "FEHLER: Neues APFS-Volume konnte nicht eindeutig gemountet werden."
  return 1
}

nas_url_has_embedded_password() {
  local authority userinfo
  [[ "$NAS_URL" == smb://* ]] || return 1
  authority="${NAS_URL#smb://}"
  authority="${authority%%/*}"
  [[ "$authority" == *"@"* ]] || return 1
  userinfo="${authority%@*}"
  [[ "$userinfo" == *":"* ]]
}

mount_nas_url() {
  [[ -n "$NAS_URL" ]] || return 1

  if nas_url_has_embedded_password; then
    log "FEHLER: Die NAS-URL darf kein eingebettetes Passwort enthalten."
    return 64
  fi

  log "NAS-Freigabe ist noch nicht gemountet; versuche stillen System-Mount."
  if [[ -x "$NAS_MOUNT_HELPER" ]]; then
    run_with_timeout "$NAS_MOUNT_TIMEOUT_SECONDS" \
      "$NAS_MOUNT_HELPER" --mount-network-url "$NAS_URL"
    return $?
  fi

  log "WARNUNG: Der nichtinteraktive NAS-Mount-Helfer ist nicht verfügbar."
  return 1
}

ensure_nas_destination() {
  local mount_requested=0 waited=0

  if [[ -z "$NAS_MOUNT" ]]; then
    RUN_STATE_REASON="nas_configuration_invalid"
    if [[ -n "$NAS_URL" ]]; then
      log "NAS-URL ist konfiguriert, aber keine gemountete Freigabe wurde gefunden. Oeffne die NAS-URL im Finder oder waehle den Mountpunkt in der Setup-App."
    else
      log "FEHLER: NAS-Ziel ist nicht konfiguriert. Setze GDRIVE_BACKUP_NAS_MOUNT oder GDRIVE_BACKUP_NAS_URL."
    fi
    return 1
  fi

  if ! nas_mount_is_verified && [[ -n "$NAS_URL" ]]; then
    if [[ "$DRY_RUN" == "1" ]]; then
      RUN_STATE_REASON="nas_mount_unavailable"
      log "DRY-RUN: NAS-Freigabe wuerde bei Bedarf still gemountet."
      return 1
    else
      mount_requested=1
      mount_nas_url || log "WARNUNG: NAS-Freigabe konnte nicht automatisch gemountet werden."
    fi
  fi

  if nas_mount_is_verified; then
    while [[ "$DRY_RUN" == "0" && ! -w "$NAS_MOUNT" &&
             "$waited" -lt "$NAS_READY_TIMEOUT_SECONDS" ]]; do
      sleep 1
      waited=$((waited + 1))
    done
  elif [[ "$mount_requested" == "1" ]]; then
    while [[ "$waited" -lt "$NAS_READY_TIMEOUT_SECONDS" ]]; do
      if nas_mount_is_verified &&
          [[ "$DRY_RUN" == "1" || -w "$NAS_MOUNT" ]]; then
        break
      fi
      sleep 1
      waited=$((waited + 1))
    done
  fi

  if ! nas_mount_is_verified; then
    RUN_STATE_REASON="nas_mount_unavailable"
    log "NAS-Ziel ist kein verifiziertes Netzwerklaufwerk: $NAS_MOUNT"
    return 1
  fi

  if [[ "$DRY_RUN" == "0" && ! -w "$NAS_MOUNT" ]]; then
    if [[ "$mount_requested" == "1" ]]; then
      RUN_STATE_REASON="nas_mount_not_ready"
    else
      RUN_STATE_REASON="destination_permission_denied"
    fi
    log "FEHLER: NAS-Mount ist nicht beschreibbar: $NAS_MOUNT"
    return 1
  fi

  if [[ "$DRY_RUN" == "0" ]] && ! check_nas_privacy_access; then
    return 1
  fi

  log "NAS-Ziel bereit: mount=$NAS_MOUNT ziel=$DEST_ROOT"
  return 0
}

# macOS asks once per app before it may read files on a network volume. While
# that grant is missing every read fails with EPERM, and while its dialog is
# open every read blocks. Both used to surface minutes later as an unreadable
# codec manifest. One bounded listing names the real cause up front instead.
check_nas_privacy_access() {
  local probe_dir="$NAS_MOUNT" error_file status

  [[ -d "$DEST_ROOT" && ! -L "$DEST_ROOT" ]] && probe_dir="$DEST_ROOT"
  error_file="$(mktemp "${TMPDIR:-/tmp}/gdrive-privacy-probe.XXXXXX")" || return 0
  run_with_timeout "$NAS_PRIVACY_PROBE_TIMEOUT_SECONDS" \
    "$LS_BIN" -a "$probe_dir" >/dev/null 2>"$error_file"
  status=$?
  if (( status == 0 )); then
    cleanup_temp_file "$error_file"
    return 0
  fi
  if /usr/bin/grep -Fq "Operation not permitted" "$error_file"; then
    cleanup_temp_file "$error_file"
    RUN_STATE_REASON="macos_privacy_permission_missing"
    log "FEHLER: macOS erlaubt GDrive Backup Tiger keinen Zugriff auf Dateien auf dem NAS. Freigabe einmalig erteilen: Systemeinstellungen > Datenschutz & Sicherheit > Voller Festplattenzugriff > GDrive Backup Tiger einschalten."
    return 1
  fi
  cleanup_temp_file "$error_file"
  if (( status > 128 )); then
    # Killed by the timeout: an unanswered macOS access dialog or a NAS that
    # does not answer. Both are worth a later retry.
    RUN_STATE_REASON="destination_unreadable"
    log "FEHLER: Der NAS-Ordner antwortet nicht. Falls ein macOS-Fenster nach Zugriff auf ein Netzwerkvolume fragt, bitte 'Erlauben' waehlen; dauerhaft hilft 'Voller Festplattenzugriff' fuer GDrive Backup Tiger."
    return 1
  fi
  # Other listing errors are judged by the existing destination checks.
  return 0
}

ensure_backup_target() {
  case "$BACKUP_TARGET" in
    apfs) ensure_backup_volume ;;
    nas) ensure_nas_destination ;;
    *)
      log "FEHLER: Ungueltiger Zieltyp '$BACKUP_TARGET'. Erlaubt sind 'apfs' und 'nas'."
      return 1
      ;;
  esac
}

DRY_RUN=1
SETUP_UI=0
INIT_HISTORY=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --run) DRY_RUN=0 ;;
    --setup) SETUP_UI=1 ;;
    --init-history) INIT_HISTORY=1 ;;
    *)
      log "Unbekannter Parameter: $arg"
      exit 64
      ;;
  esac
done

# The app asks for this once after an update, so the history is not empty
# until the next backup. It only writes a missing history and never waits for
# or interferes with a running backup, which seeds the history itself.
if [[ "$INIT_HISTORY" == "1" ]]; then
  [[ -n "$RUN_HISTORY_FILE" && ! -e "$RUN_HISTORY_FILE" && ! -L "$RUN_HISTORY_FILE" ]] || exit 0
  exec 9>"$LOCK" || exit 1
  acquire_run_lock || exit 0
  [[ ! -e "$RUN_HISTORY_FILE" && ! -L "$RUN_HISTORY_FILE" ]] || exit 0
  history_directory="${RUN_HISTORY_FILE%/*}"
  [[ "$history_directory" != "$RUN_HISTORY_FILE" ]] || history_directory="."
  (umask 077 && mkdir -p "$history_directory") || exit 1
  history_tmp="${RUN_HISTORY_FILE}.$$"
  if (umask 077 && seed_run_history_from_log >"$history_tmp") &&
     chmod 600 "$history_tmp" && mv -f "$history_tmp" "$RUN_HISTORY_FILE"; then
    exit 0
  fi
  cleanup_temp_file "$history_tmp"
  exit 1
fi

RUN_STARTED_AT="$(date +%s 2>/dev/null || printf '0')"
write_run_state "running"
trap on_exit EXIT
trap 'cancel_run 129 HUP' HUP
trap 'cancel_run 130 INT' INT
trap 'cancel_run 143 TERM' TERM

case "$RUN_TARGET_OVERRIDE_ERROR" in
  "") ;;
  nonmanual_trigger)
    RUN_STATE_REASON="invalid_run_target"
    log "FEHLER: GDRIVE_BACKUP_RUN_TARGET ist nur fuer manuelle Backups erlaubt."
    exit 64
    ;;
  *)
    RUN_STATE_REASON="invalid_run_target"
    log "FEHLER: GDRIVE_BACKUP_RUN_TARGET muss apfs oder nas sein."
    exit 64
    ;;
esac
if [[ "$RUN_TARGET_OVERRIDE" == "apfs" && -z "$BACKUP_VOLUME_UUID" ]]; then
  RUN_STATE_REASON="invalid_run_target"
  log "FEHLER: Fuer ein einmaliges APFS-Backup ist eine gespeicherte Volume-UUID erforderlich."
  exit 64
fi
if [[ "$_GDT_PROCESS_RUN_VOLUME_UUID_SET" == "1" &&
      ( "$BACKUP_TRIGGER" != "manual" || "$RUN_TARGET_OVERRIDE" != "apfs" ) ]]; then
  RUN_STATE_REASON="invalid_run_volume_identity"
  log "FEHLER: GDRIVE_BACKUP_RUN_VOLUME_UUID ist nur fuer manuelle APFS-Einmal-Backups erlaubt."
  exit 64
fi
if [[ "$RUN_TARGET_OVERRIDE" == "apfs" ]]; then
  if [[ "$_GDT_PROCESS_RUN_VOLUME_UUID_SET" != "1" ||
        -z "$_GDT_PROCESS_RUN_VOLUME_UUID_VALUE" ]]; then
    RUN_STATE_REASON="invalid_run_volume_identity"
    log "FEHLER: Die in der App ausgewaehlte Volume-UUID fehlt."
    exit 78
  fi
  if [[ ! "$_GDT_PROCESS_RUN_VOLUME_UUID_VALUE" =~ ^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$ ]]; then
    RUN_STATE_REASON="invalid_run_volume_identity"
    log "FEHLER: Die in der App ausgewaehlte Volume-UUID ist ungueltig."
    exit 78
  fi
  RUN_VOLUME_UUID_NORMALIZED="$(lowercase "$_GDT_PROCESS_RUN_VOLUME_UUID_VALUE")"
  CONFIGURED_VOLUME_UUID_NORMALIZED="$(lowercase "$BACKUP_VOLUME_UUID")"
  if [[ "$RUN_VOLUME_UUID_NORMALIZED" != "$CONFIGURED_VOLUME_UUID_NORMALIZED" ]]; then
    RUN_STATE_REASON="invalid_run_volume_identity"
    log "FEHLER: Die ausgewaehlte Volume-UUID stimmt nicht mehr mit dem gespeicherten Profil ueberein."
    exit 78
  fi
fi

if [[ ! "$NAS_READY_TIMEOUT_SECONDS" =~ ^[0-9]{1,3}$ ]] ||
   (( 10#$NAS_READY_TIMEOUT_SECONDS > 300 )); then
  RUN_STATE_REASON="invalid_configuration"
  log "FEHLER: GDRIVE_BACKUP_NAS_READY_TIMEOUT_SECONDS muss zwischen 0 und 300 liegen."
  exit 64
fi
NAS_READY_TIMEOUT_SECONDS=$((10#$NAS_READY_TIMEOUT_SECONDS))
if [[ ! "$NAS_MOUNT_TIMEOUT_SECONDS" =~ ^[0-9]{1,3}$ ]] ||
   (( 10#$NAS_MOUNT_TIMEOUT_SECONDS < 1 ||
      10#$NAS_MOUNT_TIMEOUT_SECONDS > 300 )); then
  RUN_STATE_REASON="invalid_configuration"
  log "FEHLER: GDRIVE_BACKUP_NAS_MOUNT_TIMEOUT_SECONDS muss zwischen 1 und 300 liegen."
  exit 64
fi
NAS_MOUNT_TIMEOUT_SECONDS=$((10#$NAS_MOUNT_TIMEOUT_SECONDS))
if [[ "$BACKUP_TRIGGER" == "schedule-retry" ]] &&
   { [[ ! "$RETRY_ORIGIN_STARTED_AT" =~ ^[0-9]{1,12}$ ]] ||
     [[ "$RETRY_ORIGIN_STARTED_AT" == "0" ]] ||
     [[ "$RETRY_ATTEMPT" != "1" ]]; }; then
  RUN_STATE_REASON="invalid_retry_metadata"
  log "FEHLER: Der automatische Wiederholungsversuch ist nicht eindeutig gekennzeichnet."
  exit 64
fi

case "$AUTOMATIC_BACKUPS_PAUSED" in
  0|1) ;;
  *)
    log "FEHLER: GDRIVE_BACKUP_PAUSED muss 0 oder 1 sein."
    exit 64
    ;;
esac
if [[ "$AUTOMATIC_BACKUPS_PAUSED" == "1" &&
      "$BACKUP_TRIGGER" != "manual" && "$BACKUP_TRIGGER" != "setup" ]]; then
  log "Automatische Backups sind pausiert; Lauf wird still uebersprungen."
  RUN_OUTCOME="skipped"
  RUN_STATE_REASON="automatic_backups_paused"
  exit 0
fi

if ! validate_versioning_config; then
  exit 64
fi
if ! validate_encryption_config; then
  exit 64
fi

if [[ "$SETUP_UI" == "1" ]]; then
  if [[ -d "$ANIMATION_APP" ]]; then
    /usr/bin/open -n "$ANIMATION_APP" --args --setup >/dev/null 2>&1
    exit 0
  fi
  log "FEHLER: Setup-App nicht gefunden: $ANIMATION_APP"
  exit 69
fi

if [[ "$BACKUP_TRIGGER" == "schedule" && "$SCHEDULE_MODE" == "daily" &&
      "$DRY_RUN" == "0" ]]; then
  classify_daily_schedule_run
  case "$DAILY_RUN_KIND" in
    done)
      # Hourly firings after a successful window are the normal case and
      # deliberately leave no trace in the log.
      RUN_OUTCOME="skipped"
      RUN_STATE_REASON="daily_window_complete"
      exit 0
      ;;
    exhausted)
      RUN_OUTCOME="skipped"
      RUN_STATE_REASON="daily_window_exhausted"
      exit 0
      ;;
  esac
fi

resolve_status=0
resolve_configured_apfs_volume || resolve_status=$?
if [[ "$resolve_status" != "0" ]]; then
  if [[ "$CATCHUP_QUIET" == "1" ]]; then
    skip_quiet_catchup
  fi
  exit "$resolve_status"
fi
log "Start: remote=${REMOTE}: dry_run=$DRY_RUN target=$BACKUP_TARGET mount=$VOLUME dest=$DEST_ROOT"
if [[ "$BACKUP_TARGET" == "invalid" ]]; then
  log "FEHLER: Ungueltiger Zieltyp '$REQUESTED_BACKUP_TARGET'. Erlaubt sind 'apfs' und 'nas'."
  exit 64
fi
sleep "$MOUNT_SETTLE_SECONDS"

for cmd in rclone jq ${PLATFORM_REQUIRED_TOOLS[@]+"${PLATFORM_REQUIRED_TOOLS[@]}"}; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    log "FEHLER: '$cmd' nicht gefunden."
    exit 127
  fi
done
if ! command -v flock >/dev/null 2>&1 && [[ ! -x "$PERL_BIN" ]]; then
  log "FEHLER: Weder 'flock' noch '$PERL_BIN' gefunden."
  exit 127
fi

exec 9>"$LOCK"
if ! acquire_run_lock; then
  log "Backup laeuft bereits; ueberspringe."
  RUN_OUTCOME="skipped"
  RUN_STATE_REASON="already_running"
  exit 0
fi
rotate_log_if_needed "$LOG_MAX_BYTES"
prepare_run_tmpdir
start_stall_watchdog

if [[ "$CATCHUP_QUIET" == "1" ]]; then
  # Probe before any progress or "running" record is published; a quiet skip
  # must leave the result of the window's real attempt untouched.
  catchup_reachable=0
  if [[ "$BACKUP_TARGET" == "nas" ]]; then
    configured_nas_ready_timeout="$NAS_READY_TIMEOUT_SECONDS"
    (( NAS_READY_TIMEOUT_SECONDS > 15 )) && NAS_READY_TIMEOUT_SECONDS=15
    ensure_nas_destination && catchup_reachable=1
    NAS_READY_TIMEOUT_SECONDS="$configured_nas_ready_timeout"
  elif [[ "$BACKUP_TARGET" == "apfs" && -d "$VOLUME" ]]; then
    catchup_reachable=1
  fi
  if [[ "$catchup_reachable" != "1" ]]; then
    skip_quiet_catchup
  fi
  RUN_STATE_REASON=""
  log "Nachhol-Lauf: Backup-Ziel ist wieder verfuegbar; Versuch $DAILY_WINDOW_ATTEMPTS von $DAILY_WINDOW_MAX_ATTEMPTS in diesem Tagesfenster."
fi
DURABLE_PROGRESS_OWNED=1

if ! initialize_durable_progress; then
  warn_progress_unavailable
fi

# Owning the lock is the first reliable point at which this process is the
# actual backup run. Publish that fact before network and destination checks,
# which can otherwise make a manual click appear to do nothing for minutes.
if [[ "$CONFIRM_BACKUP" == "0" || "${BACKUP_ASSUME_YES:-0}" == "1" || "$TARGET_APPROVED" == "1" ]]; then
  write_last_run_summary "running"
  start_animation
fi

if ! ensure_backup_target; then
  if [[ "$BACKUP_TRIGGER" == "mount" ]]; then
    exit 0
  fi
  log "FEHLER: Das konfigurierte Backup-Ziel ist nicht verfuegbar."
  exit 69
fi

# Inherit the verified mount identity before the watchdog forks. Otherwise a
# replacement before its first probe could become its independent baseline.
start_nas_watchdog

if ! validate_configured_apfs_target; then
  log "FEHLER: Das konfigurierte APFS-Backup-Volume konnte nicht sicher bestaetigt werden."
  exit 69
fi

if ! validate_encrypted_apfs_destination; then
  log "FEHLER: Das konfigurierte Backup-Ziel erfuellt die Verschluesselungsrichtlinie nicht."
  exit 69
fi

if ! rclone config show "$REMOTE" >/dev/null 2>&1; then
  log "FEHLER: rclone-Remote '${REMOTE}:' ist nicht konfiguriert."
  exit 78
fi

if ! confirm_backup_target; then
  RUN_OUTCOME="skipped"
  RUN_STATE_REASON="user_declined"
  exit 0
fi
write_last_run_summary "running"

if ! validate_configured_apfs_target; then
  log "FEHLER: Das konfigurierte APFS-Backup-Volume ist nach der Bestaetigung nicht mehr sicher verfuegbar."
  exit 69
fi

if [[ "$DRY_RUN" == "0" ]]; then
  if ! mkdir -p "$DEST_ROOT"; then
    log "FEHLER: Zielordner kann nicht angelegt werden: $DEST_ROOT"
    exit 73
  fi
  if ! validate_configured_apfs_target; then
    log "FEHLER: Der angelegte Zielordner liegt nicht mehr sicher auf dem konfigurierten APFS-Volume."
    exit 69
  fi
fi

if ! check_destination_free_space; then
  exit 73
fi

if ! validate_rclone_crypt_config; then
  exit 78
fi

if ! validate_all_encrypted_active_trees; then
  log "FEHLER: Der vorhandene Zielbaum erfuellt die Verschluesselungsrichtlinie nicht."
  exit 69
fi
if ! validate_all_configured_apfs_trees; then
  log "FEHLER: Der vorhandene Zielbaum verlaesst das UUID-gebundene APFS-Backup-Volume."
  exit 69
fi
if ! prepare_nas_name_codec; then
  exit 69
fi

if [[ "$VERSIONING" == "1" ]]; then
  # The UUID prevents two Macs writing to the same NAS—or a repeated local
  # run in one second—from overwriting one another's archived copy.
  VERSION_RUN_UUID="$(/usr/bin/uuidgen 2>/dev/null | /usr/bin/tr '[:upper:]' '[:lower:]')"
  VERSION_RUN_ID="$(date '+%Y-%m-%dT%H-%M-%S%z')-$VERSION_RUN_UUID"
  if [[ ! "$VERSION_RUN_ID" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}-[0-9]{2}-[0-9]{2}[+-][0-9]{4}-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
    log "FEHLER: Zeitstempel fuer den Versionsordner konnte nicht sicher erzeugt werden."
    exit 70
  fi
  if [[ "$ENCRYPTION" == "rclone-crypt" ]]; then
    log "Dateiversionierung aktiv: ${CRYPT_REMOTE}:$VERSIONS_SUBDIR/$VERSION_RUN_ID"
  else
    log "Dateiversionierung aktiv: ${DEST_ROOT%/}/$VERSIONS_SUBDIR/$VERSION_RUN_ID"
  fi
else
  log "Dateiversionierung ist deaktiviert."
fi

if [[ -z "$ANIMATION_SENTINEL" ]]; then
  start_animation
fi

RCLONE_OPTS=(
  --drive-export-formats "docx,xlsx,pptx"
  --create-empty-src-dirs
  --stats 10s
  --log-level INFO
  --retries 3
  --low-level-retries 10
)

if [[ "$BACKUP_TARGET" == "nas" ]]; then
  # Several SMB implementations reject concurrent opens or overlapping
  # directory creation even though the mount reports itself writable. A NAS
  # backup favors a slower, deterministic stream over an incomplete copy.
  RCLONE_OPTS+=(--multi-thread-streams 0 --transfers 1)
fi

if [[ "$NAS_NAME_CODEC_ENABLED" == "1" ]]; then
  # The first transform escapes the reserved namespace, making the second
  # exact-name mapping injective even if Drive contains a marker-like folder.
  RCLONE_OPTS+=(--name-transform "$NAS_NAME_CODEC_ESCAPE_TRANSFORM")
  for name_transform in "${NAS_NAME_CODEC_DOT_BIN_TRANSFORMS[@]}"; do
    RCLONE_OPTS+=(--name-transform "$name_transform")
  done
fi

if [[ "$ENCRYPTION" == "apfs" ]]; then
  RCLONE_OPTS+=(--one-file-system)
fi

if [[ "$DRY_RUN" == "1" ]]; then
  RCLONE_OPTS+=(--dry-run)
  log "DRY-RUN aktiv: Es werden keine Dateien kopiert, geloescht oder veraendert."
fi

errors=0

validate_live_nas_destination() {
  local attempt

  [[ "$BACKUP_TARGET" == "nas" ]] || return 0

  # SMB shares answer a single probe unreliably while they are busy. One failed
  # probe must not discard a transfer that just completed, so the destination
  # counts as lost only when it stays unavailable across three checks.
  for attempt in 1 2 3; do
    if nas_mount_is_verified &&
       [[ "$DRY_RUN" == "1" || -w "$NAS_MOUNT" ]]; then
      return 0
    fi
    if (( attempt < 3 )); then
      /bin/sleep "${GDRIVE_BACKUP_NAS_RECHECK_SECONDS:-2}"
    fi
  done

  if ! nas_mount_is_verified; then
    RUN_STATE_REASON="nas_connection_lost"
    log "FEHLER: NAS-Verbindung wurde waehrend des Backups getrennt."
    return 1
  fi
  if [[ "$DRY_RUN" == "0" && ! -w "$NAS_MOUNT" ]]; then
    RUN_STATE_REASON="destination_permission_denied"
    log "FEHLER: NAS-Ziel ist waehrend des Backups nicht mehr beschreibbar."
    return 1
  fi
  return 0
}

stable_sha256() {
  local digest
  digest="$(printf '%s' "$1" | /usr/bin/shasum -a 256 2>/dev/null)" || return 1
  digest="${digest%% *}"
  [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || return 1
  printf '%s' "$digest"
}

drive_query_literal() {
  local value="$1"
  local apostrophe_escape="\\'"
  value="${value//\\/\\\\}"
  value="${value//\'/$apostrophe_escape}"
  printf "'%s'" "$value"
}

validate_collision_path_components() {
  local path="$1"
  local destination_root current relative component

  [[ "$BACKUP_TARGET" == "apfs" && -n "$BACKUP_VOLUME_UUID" ]] || return 0
  destination_root="${DEST_ROOT%/}"
  [[ -n "$path" && "$path" == "$destination_root"/* ]] || return 1
  if [[ -L "$DEST_ROOT" ]]; then
    return 1
  fi

  current="$destination_root"
  relative="${path#"$destination_root"/}"
  while [[ -n "$relative" ]]; do
    if [[ "$relative" == */* ]]; then
      component="${relative%%/*}"
      relative="${relative#*/}"
    else
      component="$relative"
      relative=""
    fi
    [[ -n "$component" ]] || return 1
    current="$current/$component"
    if [[ -L "$current" ||
          ( -n "$relative" && -e "$current" && ! -d "$current" ) ]]; then
      return 1
    fi
  done
  return 0
}

validate_collision_archive_write_boundary() {
  local archive_root="$1"
  local groups_root="$2"
  local objects_root="$3"
  local candidate
  local -a paths
  shift 3

  if ! validate_live_nas_destination; then
    return 1
  fi

  paths=(
    "${DEST_ROOT%/}/.gdrive-collisions"
    "$archive_root"
    "$groups_root"
    "$objects_root"
  )
  for candidate in "$@"; do
    [[ -n "$candidate" ]] || continue
    paths[${#paths[@]}]="$candidate"
  done

  if ! validate_configured_apfs_target_paths "${paths[@]}"; then
    log "FEHLER: Das Drive-ID-Archiv liegt nicht mehr sicher auf dem konfigurierten Backup-Ziel."
    return 1
  fi

  # The complete archive and version history were inventoried once before any
  # copy starts. Mutation guards must still reject swapped ancestors, but only
  # the paths touched by this operation need another recursive walk.
  for candidate in \
      "${DEST_ROOT%/}/.gdrive-collisions" \
      "$archive_root" "$groups_root" "$objects_root"; do
    if ! validate_collision_path_components "$candidate" ||
       [[ -L "$candidate" ||
          ( -e "$candidate" && ! -d "$candidate" ) ]]; then
      log "FEHLER: Das Drive-ID-Archiv enthaelt einen unsicheren Basispfad."
      return 1
    fi
  done
  for candidate in "$@"; do
    [[ -n "$candidate" ]] || continue
    if ! validate_collision_path_components "$candidate" ||
       ! validate_configured_apfs_tree "$candidate"; then
      log "FEHLER: Ein veraenderter Pfad des Drive-ID-Archivs ist nicht mehr sicher."
      return 1
    fi
  done
  return 0
}

cleanup_collision_target_if_safe() {
  local archive_root="$1"
  local groups_root="$2"
  local objects_root="$3"
  local target="$4"

  [[ -n "$target" && ( -e "$target" || -L "$target" ) ]] || return 0
  if ! validate_collision_archive_write_boundary \
      "$archive_root" "$groups_root" "$objects_root" "$target"; then
    return 1
  fi
  cleanup_temp_file "$target"
  validate_collision_archive_write_boundary \
    "$archive_root" "$groups_root" "$objects_root"
}

archive_source_collisions() {
  local label="$1"
  local phase="$2"
  local source="$3"
  local destination="$4"
  local collision_report="$5"
  shift 5
  # Keep one harmless Drive option in the array because macOS Bash 3.2 treats
  # expansion of a declared-but-empty array as an unbound variable under set -u.
  local -a source_options=(--drive-export-formats "docx,xlsx,pptx")
  source_options+=("$@")
  local -a id_source_options=()
  local relative_destination scope_hash archive_root groups_root objects_root
  local collision_kind logical_path group_hash seen_hashes=""
  local parent_path leaf_name parent_id query query_json
  local parent_component parent_remaining parent_literal parent_query
  local parent_query_json parent_query_errors previous_parent_id first_component
  local query_errors validated_json objects_tsv match_count tsv_count copied_count
  local object_id mime_type archive_name source_md5 source_size source_modified_time
  local object_key
  local object_directory object_destination copy_status nested_report
  local archived_file entry_count local_md5 local_sha256 object_stage=""
  local recorded_sha256=""
  local existing_is_current old_destination old_destination_parent
  local old_destination_moved=0 replacement_root
  local verification_report verification_status folder_backup_dir
  local manifest_objects manifest_path manifest_temp generated_at archive_path
  local archive_destination_untrusted=0
  local option uses_shared_with_me=0 shared_root=0 provider_root=0
  local team_drive_id="" expect_team_drive_id=0 provider_parent_id=""
  local proof_count manifest_umask
  local -a file_options folder_options

  if [[ "$ENCRYPTION" == "rclone-crypt" ]]; then
    log "FEHLER: Gleichnamige Drive-IDs koennen fuer dieses verschluesselte Ziel noch nicht getrennt archiviert werden."
    return 1
  fi
  if [[ ! -f "$collision_report" || -L "$collision_report" ]]; then
    log "FEHLER: Die Liste gleichnamiger Drive-Eintraege ist nicht sicher lesbar."
    return 1
  fi

  for option in "${source_options[@]}"; do
    if [[ "$expect_team_drive_id" == "1" ]]; then
      if [[ ! "$option" =~ ^[A-Za-z0-9_-]{3,255}$ ]]; then
        log "FEHLER: Die Shared-Drive-ID fuer das ID-Archiv ist ungueltig."
        return 1
      fi
      team_drive_id="$option"
      expect_team_drive_id=0
    elif [[ "$option" == "--drive-team-drive" ]]; then
      if [[ -n "$team_drive_id" ]]; then
        log "FEHLER: Das ID-Archiv erhielt mehrere Shared-Drive-Wurzeln."
        return 1
      fi
      expect_team_drive_id=1
    fi
    if [[ "$option" == "--drive-shared-with-me" ]]; then
      uses_shared_with_me=1
      continue
    fi
    id_source_options[${#id_source_options[@]}]="$option"
  done
  if [[ "$expect_team_drive_id" == "1" ]]; then
    log "FEHLER: Die Shared-Drive-ID fuer das ID-Archiv fehlt."
    return 1
  fi

  relative_destination="${destination#"$DEST_ROOT"/}"
  if [[ -z "$relative_destination" || "$relative_destination" == "$destination" ||
        "$relative_destination" =~ [[:cntrl:]] ]]; then
    log "FEHLER: Der Backup-Bereich fuer das ID-Archiv ist ungueltig."
    return 1
  fi
  if ! scope_hash="$(stable_sha256 "$relative_destination")"; then
    log "FEHLER: Der sichere Bezeichner fuer das ID-Archiv konnte nicht erzeugt werden."
    return 1
  fi

  archive_root="${DEST_ROOT%/}/.gdrive-collisions/$scope_hash"
  groups_root="$archive_root/groups"
  objects_root="$archive_root/objects"
  for object_destination in \
      "${DEST_ROOT%/}/.gdrive-collisions" "$archive_root" "$groups_root" "$objects_root"; do
    if [[ -L "$object_destination" ||
          ( -e "$object_destination" && ! -d "$object_destination" ) ]]; then
      log "FEHLER: Das ID-Archiv enthaelt einen unsicheren Pfad."
      return 1
    fi
  done
  if ! validate_collision_archive_write_boundary \
      "$archive_root" "$groups_root" "$objects_root"; then
    log "FEHLER: Das ID-Archiv konnte auf dem Backup-Ziel nicht sicher bestaetigt werden."
    return 1
  fi
  if [[ "$DRY_RUN" == "0" ]]; then
    if ! validate_collision_archive_write_boundary \
        "$archive_root" "$groups_root" "$objects_root"; then
      return 1
    fi
    if ! mkdir -p "$groups_root" "$objects_root"; then
      RUN_STATE_REASON="destination_permission_denied"
      log "FEHLER: Das ID-Archiv konnte auf dem Backup-Ziel nicht angelegt werden."
      return 1
    fi
    if ! validate_collision_archive_write_boundary \
        "$archive_root" "$groups_root" "$objects_root"; then
      log "FEHLER: Das angelegte ID-Archiv liegt nicht sicher auf dem UUID-gebundenen APFS-Backup-Volume."
      return 1
    fi
  fi

  while IFS=$'\t' read -r collision_kind logical_path; do
    if ! validate_collision_archive_write_boundary \
        "$archive_root" "$groups_root" "$objects_root"; then
      return 1
    fi
    if [[ ( "$collision_kind" != "file" && "$collision_kind" != "directory" ) ||
          -z "$logical_path" || "$logical_path" == /* ||
          "$logical_path" =~ [[:cntrl:]] ]]; then
      log "FEHLER: Ein gleichnamiger Drive-Eintrag konnte nicht sicher zugeordnet werden."
      return 1
    fi
    case "/$logical_path/" in
      *"//"*|*"/./"*|*"/../"*)
        log "FEHLER: Ein gleichnamiger Drive-Pfad ist unsicher."
        return 1
        ;;
    esac
    if ! group_hash="$(stable_sha256 "$collision_kind"$'\037'"$logical_path")"; then
      return 1
    fi
    case " $seen_hashes " in
      *" $group_hash "*) continue ;;
    esac
    seen_hashes="$seen_hashes $group_hash"
    manifest_path="$groups_root/$group_hash.json"

    if [[ "$logical_path" == */* ]]; then
      parent_path="${logical_path%/*}"
      leaf_name="${logical_path##*/}"
    else
      parent_path=""
      leaf_name="$logical_path"
    fi
    [[ -n "$leaf_name" ]] || return 1

    parent_id=""
    shared_root=0
    provider_root=0
    provider_parent_id=""
    if [[ "$uses_shared_with_me" == "1" && -z "$parent_path" ]]; then
      # Root entries in Drive's virtual "Shared with me" view have no common
      # parent ID. Query that view explicitly, then copy each result by ID
      # without carrying the virtual-root option into the ID-rooted copy.
      shared_root=1
      query="sharedWithMe = true and trashed = false"
    elif [[ -z "$parent_path" ]]; then
      # rclone's stat for a Drive root intentionally omits its provider ID.
      # Google's root alias still scopes the query to the configured My Drive
      # or Shared Drive; matching objects must then prove one common real
      # parent ID in the returned metadata.
      provider_root=1
      if [[ -n "$team_drive_id" ]]; then
        provider_parent_id="$team_drive_id"
        query="'$team_drive_id' in parents and trashed = false"
      else
        query="'root' in parents and trashed = false"
      fi
    else
      # lsjson --stat describes any opened Drive path as a synthetic root and
      # therefore omits its provider ID. Resolve each folder from the provider
      # root instead, so duplicate ancestors can never be guessed by name.
      parent_remaining="$parent_path"
      first_component=1
      while [[ -n "$parent_remaining" ]]; do
        if ! validate_collision_archive_write_boundary \
            "$archive_root" "$groups_root" "$objects_root"; then
          return 1
        fi
        if [[ "$parent_remaining" == */* ]]; then
          parent_component="${parent_remaining%%/*}"
          parent_remaining="${parent_remaining#*/}"
        else
          parent_component="$parent_remaining"
          parent_remaining=""
        fi
        [[ -n "$parent_component" ]] || return 1
        parent_literal="$(drive_query_literal "$parent_component")" || return 1
        previous_parent_id="$parent_id"
        if [[ "$first_component" == "1" && "$uses_shared_with_me" == "1" ]]; then
          parent_query="sharedWithMe = true and name = $parent_literal and mimeType = 'application/vnd.google-apps.folder' and trashed = false"
        elif [[ "$first_component" == "1" ]]; then
          if [[ -n "$team_drive_id" ]]; then
            parent_query="'$team_drive_id' in parents and name = $parent_literal and mimeType = 'application/vnd.google-apps.folder' and trashed = false"
          else
            parent_query="'root' in parents and name = $parent_literal and mimeType = 'application/vnd.google-apps.folder' and trashed = false"
          fi
        else
          parent_query="'$previous_parent_id' in parents and name = $parent_literal and mimeType = 'application/vnd.google-apps.folder' and trashed = false"
        fi

        parent_query_json="$(mktemp \
          "${TMPDIR:-/tmp}/gdrive-parent-query.XXXXXX")" || return 1
        parent_query_errors="$(mktemp \
          "${TMPDIR:-/tmp}/gdrive-parent-query-errors.XXXXXX")" || {
          cleanup_temp_file "$parent_query_json"
          return 1
        }
        if ! rclone backend query "$source" "$parent_query" \
            "${id_source_options[@]}" >"$parent_query_json" \
            2>"$parent_query_errors"; then
          while IFS= read -r line; do
            [[ -n "$line" ]] && log "rclone query: $line"
          done <"$parent_query_errors"
          cleanup_temp_file "$parent_query_json" "$parent_query_errors"
          log "FEHLER: Ein Elternordner eines gleichnamigen Drive-Eintrags konnte nicht gesucht werden."
          return 1
        fi
        while IFS= read -r line; do
          [[ -n "$line" ]] && log "rclone query: $line"
        done <"$parent_query_errors"
        if /usr/bin/grep -Eiq \
            'incomplete|(^|[[:space:]])error([ :]|$)|failed to' \
            "$parent_query_errors" 2>/dev/null ||
           ! parent_id="$(/usr/bin/jq -er \
              --arg component "$parent_component" \
              --arg previous "$previous_parent_id" \
              --arg first "$first_component" \
              --arg shared "$uses_shared_with_me" \
              --arg providerParent "$team_drive_id" '
                if type != "array" then error("invalid folder query result")
                else
                  [ .[]
                    | select(.name == $component)
                    | select(.mimeType ==
                        "application/vnd.google-apps.folder")
                  ] as $matches
                  | if ($matches | length) != 1
                    then error("ambiguous folder")
                    else $matches[0]
                    end
                  | select(
                      ((.id | type) == "string") and
                      (.id | test("^[A-Za-z0-9_-]{3,255}$")) and
                      (if $first == "1" and $shared == "1" then true
                       elif $first == "1" then
                         ((.parents | type) == "array") and
                         ((.parents | length) == 1) and
                         ((.parents[0] | type) == "string") and
                         (.parents[0] |
                           test("^[A-Za-z0-9_-]{3,255}$")) and
                         (if $providerParent == "" then true
                          else .parents[0] == $providerParent
                          end)
                       else
                         ((.parents | type) == "array") and
                         ((.parents | index($previous)) != null)
                       end)
                    )
                  | .id
                end
              ' "$parent_query_json" 2>/dev/null)"; then
          cleanup_temp_file "$parent_query_json" "$parent_query_errors"
          log "FEHLER: Ein Elternordner eines gleichnamigen Drive-Eintrags ist nicht eindeutig per ID aufloesbar."
          return 1
        fi
        cleanup_temp_file "$parent_query_json" "$parent_query_errors"
        if ! validate_collision_archive_write_boundary \
            "$archive_root" "$groups_root" "$objects_root"; then
          return 1
        fi
        first_component=0
      done
      query="'$parent_id' in parents and trashed = false"
    fi

    query_json="$(mktemp "${TMPDIR:-/tmp}/gdrive-collision-query.XXXXXX")" || return 1
    query_errors="$(mktemp "${TMPDIR:-/tmp}/gdrive-collision-query-errors.XXXXXX")" || {
      cleanup_temp_file "$query_json"
      return 1
    }
    validated_json="$(mktemp "${TMPDIR:-/tmp}/gdrive-collision-validated.XXXXXX")" || {
      cleanup_temp_file "$query_json" "$query_errors"
      return 1
    }
    if ! rclone backend query "$source" "$query" \
        "${id_source_options[@]}" >"$query_json" 2>"$query_errors"; then
      while IFS= read -r line; do
        [[ -n "$line" ]] && log "rclone query: $line"
      done <"$query_errors"
      cleanup_temp_file "$query_json" "$query_errors" "$validated_json"
      log "FEHLER: Die Drive-Suche fuer einen gleichnamigen Eintrag ist fehlgeschlagen."
      return 1
    fi
    while IFS= read -r line; do
      [[ -n "$line" ]] && log "rclone query: $line"
    done <"$query_errors"
    if /usr/bin/grep -Eiq 'incomplete|(^|[[:space:]])error([ :]|$)|failed to' \
        "$query_errors" 2>/dev/null ||
       ! /usr/bin/jq -e \
          --arg parent "$parent_id" \
          --arg name "$leaf_name" \
          --arg kind "$collision_kind" \
          --arg sharedRoot "$shared_root" \
          --arg providerRoot "$provider_root" \
          --arg providerParent "$provider_parent_id" '
          def rendered_name:
            if .mimeType == "application/vnd.google-apps.document" then .name + ".docx"
            elif .mimeType == "application/vnd.google-apps.spreadsheet" then .name + ".xlsx"
            elif .mimeType == "application/vnd.google-apps.presentation" then .name + ".pptx"
            else .name
            end;
          def supported_type:
            (.mimeType == "application/vnd.google-apps.folder") or
            ((.mimeType | startswith("application/vnd.google-apps.")) | not) or
            (.mimeType == "application/vnd.google-apps.document") or
            (.mimeType == "application/vnd.google-apps.spreadsheet") or
            (.mimeType == "application/vnd.google-apps.presentation");
          if type != "array" then error("invalid query result")
          else
            [ .[]
              | select((.name | type) == "string" and
                       (.mimeType | type) == "string")
              | . + {archiveName: rendered_name}
              | select(.archiveName == $name)
              | select(
                  if $kind == "directory"
                  then .mimeType == "application/vnd.google-apps.folder"
                  else .mimeType != "application/vnd.google-apps.folder"
                  end)
            ] as $matches
              | if ($matches | length) < 2 then error("not a duplicate group")
              elif ([$matches[].id] | unique | length) != ($matches | length)
                then error("duplicate IDs")
              elif
                all($matches[];
                  ((.id | type) == "string") and
                  (.id | test("^[A-Za-z0-9_-]{3,255}$")) and
                  supported_type
                ) and
                (if $sharedRoot == "1" then true
                 elif $providerRoot == "1" then
                   all($matches[];
                     ((.parents | type) == "array") and
                     ((.parents | length) == 1) and
                     ((.parents[0] | type) == "string") and
                     (.parents[0] | test("^[A-Za-z0-9_-]{3,255}$")) and
                     (if $providerParent == "" then true
                      else .parents[0] == $providerParent
                      end)
                   ) and
                   (([$matches[].parents[0]] | unique | length) == 1)
                 else
                   all($matches[];
                     ((.parents | type) == "array") and
                     ((.parents | index($parent)) != null)
                   )
                 end)
              then $matches
              else error("invalid duplicate metadata")
              end
          end
        ' "$query_json" >"$validated_json" 2>/dev/null; then
      cleanup_temp_file "$query_json" "$query_errors" "$validated_json"
      log "FEHLER: Die Drive-IDs eines gleichnamigen Eintrags konnten nicht vollstaendig inventarisiert werden."
      return 1
    fi
    cleanup_temp_file "$query_json" "$query_errors"
    match_count="$(/usr/bin/jq 'length' "$validated_json" 2>/dev/null || printf '0')"
    if [[ ! "$match_count" =~ ^[0-9]+$ || "$match_count" -lt 2 ]]; then
      cleanup_temp_file "$validated_json"
      return 1
    fi
    objects_tsv="$(mktemp "${TMPDIR:-/tmp}/gdrive-collision-objects.XXXXXX")" || {
      cleanup_temp_file "$validated_json"
      return 1
    }
    manifest_objects="$(mktemp "${TMPDIR:-/tmp}/gdrive-collision-manifest.XXXXXX")" || {
      cleanup_temp_file "$validated_json" "$objects_tsv"
      return 1
    }
    if ! /usr/bin/jq -er '
        .[] | [
          .id, .mimeType, .archiveName,
          (.md5Checksum // "-"), (.size // "-"), (.modifiedTime // "-")
        ] | @tsv
      ' "$validated_json" >"$objects_tsv"; then
      cleanup_temp_file "$validated_json" "$objects_tsv" "$manifest_objects"
      return 1
    fi
    tsv_count="$(/usr/bin/wc -l <"$objects_tsv" | /usr/bin/tr -d '[:space:]')"
    if [[ "$tsv_count" != "$match_count" ]]; then
      cleanup_temp_file "$validated_json" "$objects_tsv" "$manifest_objects"
      log "FEHLER: Nicht jede inventarisierte Drive-ID kann verarbeitet werden."
      return 1
    fi
    if ! validate_collision_archive_write_boundary \
        "$archive_root" "$groups_root" "$objects_root"; then
      cleanup_temp_file "$validated_json" "$objects_tsv" "$manifest_objects"
      return 1
    fi

    copied_count=0
    # Every failure path returns immediately after cleanup, so moving the
    # materialized TSV while its read descriptor is open cannot continue a
    # partial loop.
    # shellcheck disable=SC2094
    while IFS=$'\t' read -r object_id mime_type archive_name source_md5 source_size \
        source_modified_time; do
      if ! validate_collision_archive_write_boundary \
          "$archive_root" "$groups_root" "$objects_root" "$manifest_path"; then
        cleanup_temp_file "$validated_json" "$objects_tsv" "$manifest_objects"
        return 1
      fi
      [[ "$object_id" =~ ^[A-Za-z0-9_-]{3,255}$ &&
          -n "$mime_type" && "$archive_name" == "$leaf_name" ]] || {
        cleanup_temp_file "$validated_json" "$objects_tsv" "$manifest_objects"
        return 1
      }
      if ! validate_live_nas_destination; then
        cleanup_temp_file "$validated_json" "$objects_tsv" "$manifest_objects"
        return 1
      fi
      if ! object_key="$(stable_sha256 "drive-object-id"$'\037'"$object_id")"; then
        cleanup_temp_file "$validated_json" "$objects_tsv" "$manifest_objects"
        return 1
      fi
      object_directory="$objects_root/$object_key"
      if [[ -L "$object_directory" ||
            ( -e "$object_directory" && ! -d "$object_directory" ) ]]; then
        cleanup_temp_file "$validated_json" "$objects_tsv" "$manifest_objects"
        log "FEHLER: Ein Drive-ID-Ziel ist kein sicherer Ordner."
        return 1
      fi
      if ! validate_collision_archive_write_boundary \
          "$archive_root" "$groups_root" "$objects_root" \
          "$manifest_path" "$object_directory"; then
        cleanup_temp_file "$validated_json" "$objects_tsv" "$manifest_objects"
        return 1
      fi

      copy_status=0
      archive_destination_untrusted=0
      LAST_RCLONE_COLLISION_REPORT=""
      if [[ "$mime_type" == "application/vnd.google-apps.folder" ]]; then
        object_destination="$object_directory/root"
        if [[ -L "$object_destination" ||
              ( -e "$object_destination" && ! -d "$object_destination" ) ]]; then
          cleanup_temp_file "$validated_json" "$objects_tsv" "$manifest_objects"
          log "FEHLER: Eine Drive-ID-Ordnerwurzel ist kein sicherer Ordner."
          return 1
        fi
        if [[ "$DRY_RUN" == "0" ]]; then
          if ! validate_collision_archive_write_boundary \
              "$archive_root" "$groups_root" "$objects_root" \
              "$manifest_path" "$object_directory" "$object_destination"; then
            cleanup_temp_file "$validated_json" "$objects_tsv" "$manifest_objects"
            return 1
          fi
          # rclone does not create the destination root for an empty source folder.
          if ! mkdir -p "$object_destination"; then
            cleanup_temp_file "$validated_json" "$objects_tsv" "$manifest_objects"
            RUN_STATE_REASON="destination_permission_denied"
            return 1
          fi
          if ! validate_collision_archive_write_boundary \
              "$archive_root" "$groups_root" "$objects_root" \
              "$manifest_path" "$object_directory" "$object_destination"; then
            cleanup_temp_file "$validated_json" "$objects_tsv" "$manifest_objects"
            return 1
          fi
        fi
        folder_backup_dir=""
        folder_options=(--drive-root-folder-id "$object_id")
        if [[ "$VERSIONING" == "1" ]]; then
          folder_backup_dir="${DEST_ROOT%/}/$VERSIONS_SUBDIR/$VERSION_RUN_ID/.gdrive-collisions/$scope_hash/objects/$object_key/root"
          folder_options+=(--backup-dir "$folder_backup_dir")
        fi
        if ! validate_collision_archive_write_boundary \
            "$archive_root" "$groups_root" "$objects_root" \
            "$manifest_path" "$object_directory" "$object_destination" \
            "$folder_backup_dir"; then
          cleanup_temp_file "$validated_json" "$objects_tsv" "$manifest_objects"
          return 1
        fi
        run_rclone_with_progress "$label (ID-Archiv)" "$phase" \
          rclone copy "$source" "$object_destination" \
          "${folder_options[@]}" "${id_source_options[@]}" \
          "${RCLONE_OPTS[@]}" || copy_status=$?
        if ! validate_collision_archive_write_boundary \
            "$archive_root" "$groups_root" "$objects_root" \
            "$manifest_path" "$object_directory" "$object_destination" \
            "$folder_backup_dir"; then
          copy_status=1
          archive_destination_untrusted=1
        fi
      else
        existing_is_current=0
        archived_file="$object_directory/$archive_name"
        if [[ "$DRY_RUN" == "0" && "$source_md5" =~ ^[0-9a-fA-F]{32}$ &&
              -f "$archived_file" && ! -L "$archived_file" ]]; then
          entry_count="$(/usr/bin/find "$object_directory" -mindepth 1 -maxdepth 1 \
            -exec /usr/bin/printf 'x\n' \; 2>/dev/null | /usr/bin/wc -l |
            /usr/bin/tr -d '[:space:]')"
          local_md5="$(/sbin/md5 -q -- "$archived_file" 2>/dev/null || true)"
          if [[ "$entry_count" == "1" &&
                "$(lowercase "$local_md5")" == "$(lowercase "$source_md5")" ]]; then
            existing_is_current=1
          fi
        elif [[ "$DRY_RUN" == "0" && -n "$source_modified_time" &&
                -f "$archived_file" && ! -L "$archived_file" &&
                -f "$manifest_path" && ! -L "$manifest_path" ]]; then
          entry_count="$(/usr/bin/find "$object_directory" -mindepth 1 -maxdepth 1 \
            -exec /usr/bin/printf 'x\n' \; 2>/dev/null | /usr/bin/wc -l |
            /usr/bin/tr -d '[:space:]')"
          recorded_sha256="$(/usr/bin/jq -er \
            --arg id "$object_id" \
            --arg archiveName "$archive_name" \
            --arg modifiedTime "$source_modified_time" '
              .objects[]
              | select(.id == $id and .archiveName == $archiveName and
                       .modifiedTime == $modifiedTime)
              | .storedSha256
              | select(type == "string" and test("^[0-9a-f]{64}$"))
            ' "$manifest_path" 2>/dev/null || true)"
          local_sha256="$(/usr/bin/shasum -a 256 -- "$archived_file" 2>/dev/null)"
          local_sha256="${local_sha256%% *}"
          if [[ "$entry_count" == "1" && -n "$recorded_sha256" &&
                "$local_sha256" == "$recorded_sha256" ]]; then
            existing_is_current=1
          fi
        fi
        if [[ "$DRY_RUN" == "1" ]]; then
          file_options=(--retries 3 --low-level-retries 10 --dry-run)
          if ! validate_collision_archive_write_boundary \
              "$archive_root" "$groups_root" "$objects_root" \
              "$manifest_path" "$object_directory"; then
            cleanup_temp_file "$validated_json" "$objects_tsv" "$manifest_objects"
            return 1
          fi
          run_rclone_with_progress "$label (ID-Archiv)" "$phase" \
            rclone backend copyid "$source" "$object_id" "${object_directory%/}/" \
            "${id_source_options[@]}" "${file_options[@]}" || copy_status=$?
          if ! validate_collision_archive_write_boundary \
              "$archive_root" "$groups_root" "$objects_root" \
              "$manifest_path" "$object_directory"; then
            copy_status=1
            archive_destination_untrusted=1
          fi
        elif [[ "$existing_is_current" != "1" ]]; then
          if ! validate_collision_archive_write_boundary \
              "$archive_root" "$groups_root" "$objects_root" \
              "$manifest_path" "$object_directory"; then
            cleanup_temp_file "$validated_json" "$objects_tsv" "$manifest_objects"
            return 1
          fi
          object_stage="$(/usr/bin/mktemp -d \
            "${objects_root}/.${object_key}.stage.XXXXXX")" || copy_status=70
          if ! validate_collision_archive_write_boundary \
              "$archive_root" "$groups_root" "$objects_root" \
              "$manifest_path" "$object_directory" "$object_stage"; then
            copy_status=1
            archive_destination_untrusted=1
          fi
          if [[ "$copy_status" == "0" ]]; then
            file_options=(--retries 3 --low-level-retries 10)
            if ! validate_collision_archive_write_boundary \
                "$archive_root" "$groups_root" "$objects_root" \
                "$manifest_path" "$object_directory" "$object_stage"; then
              copy_status=1
              archive_destination_untrusted=1
            fi
          fi
          if [[ "$copy_status" == "0" ]]; then
            run_rclone_with_progress "$label (ID-Archiv)" "$phase" \
              rclone backend copyid "$source" "$object_id" "${object_stage%/}/" \
              "${id_source_options[@]}" "${file_options[@]}" || copy_status=$?
            if ! validate_collision_archive_write_boundary \
                "$archive_root" "$groups_root" "$objects_root" \
                "$manifest_path" "$object_directory" "$object_stage"; then
              copy_status=1
              archive_destination_untrusted=1
            fi
          fi
          archived_file="$object_stage/$archive_name"
          if [[ "$copy_status" == "0" ]]; then
            entry_count="$(/usr/bin/find "$object_stage" -mindepth 1 -maxdepth 1 \
              -exec /usr/bin/printf 'x\n' \; 2>/dev/null | /usr/bin/wc -l |
              /usr/bin/tr -d '[:space:]')"
            if [[ "$entry_count" != "1" || ! -f "$archived_file" ||
                  -L "$archived_file" ]]; then
              copy_status=1
            fi
          fi
          if [[ "$copy_status" == "0" && "$source_size" =~ ^[0-9]+$ ]]; then
            [[ "$(platform_stat_size "$archived_file" 2>/dev/null || printf x)" == \
              "$source_size" ]] || copy_status=1
          fi
          if [[ "$copy_status" == "0" && "$source_md5" =~ ^[0-9a-fA-F]{32}$ ]]; then
            local_md5="$(/sbin/md5 -q -- "$archived_file" 2>/dev/null || true)"
            [[ "$(lowercase "$local_md5")" == "$(lowercase "$source_md5")" ]] ||
              copy_status=1
          fi
          if [[ "$copy_status" == "0" ]]; then
            old_destination=""
            old_destination_parent=""
            old_destination_moved=0
            if [[ -d "$object_directory" ]]; then
              if [[ "$VERSIONING" == "1" ]]; then
                old_destination="${DEST_ROOT%/}/$VERSIONS_SUBDIR/$VERSION_RUN_ID/.gdrive-collisions/$scope_hash/objects/$object_key"
              else
                replacement_root="$archive_root/.replacement-trash/$object_key"
                if ! validate_collision_archive_write_boundary \
                    "$archive_root" "$groups_root" "$objects_root" \
                    "$manifest_path" "$object_directory" "$object_stage" \
                    "$replacement_root"; then
                  copy_status=1
                  archive_destination_untrusted=1
                elif ! mkdir -p "$replacement_root"; then
                  copy_status=1
                else
                  if ! validate_collision_archive_write_boundary \
                      "$archive_root" "$groups_root" "$objects_root" \
                      "$manifest_path" "$object_directory" "$object_stage" \
                      "$replacement_root"; then
                    copy_status=1
                    archive_destination_untrusted=1
                  else
                    old_destination="$replacement_root/$(date -u '+%Y%m%dT%H%M%SZ')-$(/usr/bin/uuidgen | /usr/bin/tr '[:upper:]' '[:lower:]')"
                  fi
                fi
              fi
              if [[ "$copy_status" == "0" &&
                    ( -e "$old_destination" || -L "$old_destination" ) ]]; then
                copy_status=1
              elif [[ "$copy_status" == "0" ]]; then
                old_destination_parent="$(/usr/bin/dirname "$old_destination")"
                if ! validate_collision_archive_write_boundary \
                    "$archive_root" "$groups_root" "$objects_root" \
                    "$manifest_path" "$object_directory" "$object_stage" \
                    "$old_destination_parent" "$old_destination"; then
                  copy_status=1
                  archive_destination_untrusted=1
                elif ! mkdir -p "$old_destination_parent"; then
                  copy_status=1
                elif ! validate_collision_archive_write_boundary \
                    "$archive_root" "$groups_root" "$objects_root" \
                    "$manifest_path" "$object_directory" "$object_stage" \
                    "$old_destination_parent" "$old_destination"; then
                  copy_status=1
                  archive_destination_untrusted=1
                fi
              fi
              if [[ "$copy_status" == "0" ]]; then
                if ! validate_collision_archive_write_boundary \
                    "$archive_root" "$groups_root" "$objects_root" \
                    "$manifest_path" "$object_directory" "$object_stage" \
                    "$old_destination"; then
                  copy_status=1
                  archive_destination_untrusted=1
                elif ! /bin/mv "$object_directory" "$old_destination"; then
                  copy_status=1
                elif ! validate_collision_archive_write_boundary \
                    "$archive_root" "$groups_root" "$objects_root" \
                    "$manifest_path" "$object_directory" "$object_stage" \
                    "$old_destination"; then
                  copy_status=1
                  archive_destination_untrusted=1
                else
                  old_destination_moved=1
                fi
              fi
            fi
            if [[ "$copy_status" == "0" ]]; then
              if ! validate_collision_archive_write_boundary \
                  "$archive_root" "$groups_root" "$objects_root" \
                  "$manifest_path" "$object_directory" "$object_stage" \
                  "$old_destination"; then
                copy_status=1
                archive_destination_untrusted=1
              elif ! /bin/mv "$object_stage" "$object_directory"; then
                copy_status=1
              elif ! validate_collision_archive_write_boundary \
                  "$archive_root" "$groups_root" "$objects_root" \
                  "$manifest_path" "$object_directory" "$old_destination"; then
                copy_status=1
                archive_destination_untrusted=1
              else
                object_stage=""
              fi
            fi
            if [[ "$copy_status" != "0" &&
                  "$archive_destination_untrusted" == "0" &&
                  "$old_destination_moved" == "1" &&
                  -d "$old_destination" && ! -e "$object_directory" ]]; then
              if validate_collision_archive_write_boundary \
                  "$archive_root" "$groups_root" "$objects_root" \
                  "$manifest_path" "$object_directory" "$object_stage" \
                  "$old_destination"; then
                if /bin/mv "$old_destination" "$object_directory"; then
                  validate_collision_archive_write_boundary \
                    "$archive_root" "$groups_root" "$objects_root" \
                    "$manifest_path" "$object_directory" "$object_stage" \
                    >/dev/null 2>&1 || archive_destination_untrusted=1
                fi
              fi
            fi
            if [[ "$copy_status" == "0" ]]; then
              archived_file="$object_directory/$archive_name"
            fi
          fi
        fi
      fi
      nested_report="$LAST_RCLONE_COLLISION_REPORT"
      LAST_RCLONE_COLLISION_REPORT=""
      cleanup_temp_file "$nested_report"
      if [[ "$copy_status" != "0" ]]; then
        if [[ -n "$object_stage" && "$archive_destination_untrusted" == "0" ]]; then
          cleanup_collision_target_if_safe \
            "$archive_root" "$groups_root" "$objects_root" "$object_stage" ||
            archive_destination_untrusted=1
        fi
        cleanup_temp_file "$validated_json" "$objects_tsv" "$manifest_objects"
        log "FEHLER: Eine gleichnamige Drive-ID konnte nicht separat gesichert werden."
        return 1
      fi

      if [[ "$DRY_RUN" == "0" && "$mime_type" == "application/vnd.google-apps.folder" ]]; then
        if [[ ! -d "$object_destination" || -L "$object_destination" ]]; then
          cleanup_temp_file "$validated_json" "$objects_tsv" "$manifest_objects"
          log "FEHLER: Das ID-Archiv des Drive-Ordners wurde nicht materialisiert."
          return 1
        fi
        verification_report="$(mktemp \
          "${TMPDIR:-/tmp}/gdrive-collision-folder-check.XXXXXX")" || {
          cleanup_temp_file "$validated_json" "$objects_tsv" "$manifest_objects"
          return 1
        }
        if ! validate_collision_archive_write_boundary \
            "$archive_root" "$groups_root" "$objects_root" \
            "$manifest_path" "$object_directory" "$object_destination" \
            "$folder_backup_dir"; then
          cleanup_temp_file "$verification_report" "$validated_json" \
            "$objects_tsv" "$manifest_objects"
          return 1
        fi
        verification_status=0
        run_rclone_with_progress "$label (ID-Pruefung)" "$phase" \
          rclone copy "$source" "$object_destination" \
          --drive-root-folder-id "$object_id" "${id_source_options[@]}" \
          "${RCLONE_OPTS[@]}" --dry-run --retries 1 \
          --combined "$verification_report" || verification_status=$?
        if ! validate_collision_archive_write_boundary \
            "$archive_root" "$groups_root" "$objects_root" \
            "$manifest_path" "$object_directory" "$object_destination" \
            "$folder_backup_dir"; then
          cleanup_temp_file "$verification_report" "$validated_json" \
            "$objects_tsv" "$manifest_objects"
          return 1
        fi
        nested_report="$LAST_RCLONE_COLLISION_REPORT"
        LAST_RCLONE_COLLISION_REPORT=""
        cleanup_temp_file "$nested_report"
        if [[ "$verification_status" != "0" ]] ||
           /usr/bin/grep -Eq '^[+*!][[:space:]]' "$verification_report" 2>/dev/null; then
          cleanup_temp_file "$verification_report" "$validated_json" \
            "$objects_tsv" "$manifest_objects"
          log "FEHLER: Das ID-Archiv eines Drive-Ordners ist nach dem Kopieren nicht vollstaendig."
          return 1
        fi
        cleanup_temp_file "$verification_report"
      fi

      local_sha256=""
      if ! validate_collision_archive_write_boundary \
          "$archive_root" "$groups_root" "$objects_root" \
          "$manifest_path" "$object_directory"; then
        cleanup_temp_file "$validated_json" "$objects_tsv" "$manifest_objects"
        return 1
      fi
      if [[ "$DRY_RUN" == "0" && "$mime_type" != "application/vnd.google-apps.folder" ]]; then
        archived_file="$object_directory/$archive_name"
        local_sha256="$(/usr/bin/shasum -a 256 -- "$archived_file" 2>/dev/null)"
        local_sha256="${local_sha256%% *}"
        if [[ ! "$local_sha256" =~ ^[0-9a-f]{64}$ ]]; then
          cleanup_temp_file "$validated_json" "$objects_tsv" "$manifest_objects"
          return 1
        fi
        archive_path=".gdrive-collisions/$scope_hash/objects/$object_key/$archive_name"
      else
        archive_path=".gdrive-collisions/$scope_hash/objects/$object_key/root"
      fi
      if ! /usr/bin/jq -ce \
          --arg id "$object_id" \
          --arg objectKey "$object_key" \
          --arg archiveName "$archive_name" \
          --arg archivePath "$archive_path" \
          --arg storedSha256 "$local_sha256" '
            map(select(.id == $id))[0] +
            {
              objectKey: $objectKey,
              archiveName: $archiveName,
              archivePath: $archivePath,
              storedSha256: $storedSha256
            }
            | with_entries(select(.value != null and .value != ""))
          ' "$validated_json" >>"$manifest_objects"; then
        cleanup_temp_file "$validated_json" "$objects_tsv" "$manifest_objects"
        return 1
      fi
      copied_count=$((copied_count + 1))
      if ! validate_collision_archive_write_boundary \
          "$archive_root" "$groups_root" "$objects_root" \
          "$manifest_path" "$object_directory"; then
        cleanup_temp_file "$validated_json" "$objects_tsv" "$manifest_objects"
        return 1
      fi
    done <"$objects_tsv"

    proof_count="$(/usr/bin/wc -l <"$manifest_objects" | /usr/bin/tr -d '[:space:]')"
    if [[ "$copied_count" != "$match_count" || "$proof_count" != "$match_count" ]]; then
      cleanup_temp_file "$validated_json" "$objects_tsv" "$manifest_objects"
      log "FEHLER: Nicht jede inventarisierte Drive-ID wurde nachweislich archiviert."
      return 1
    fi

    if [[ "$DRY_RUN" == "0" ]]; then
      if ! validate_collision_archive_write_boundary \
          "$archive_root" "$groups_root" "$objects_root" "$manifest_path"; then
        cleanup_temp_file "$validated_json" "$objects_tsv" "$manifest_objects"
        return 1
      fi
      if [[ -L "$manifest_path" ||
            ( -e "$manifest_path" && ! -f "$manifest_path" ) ]]; then
        cleanup_temp_file "$validated_json" "$objects_tsv" "$manifest_objects"
        log "FEHLER: Das Manifest des Drive-ID-Archivs ist unsicher."
        return 1
      fi
      manifest_umask="$(umask)"
      umask 077
      manifest_temp=""
      if ! validate_collision_archive_write_boundary \
          "$archive_root" "$groups_root" "$objects_root" "$manifest_path"; then
        umask "$manifest_umask"
        cleanup_temp_file "$validated_json" "$objects_tsv" "$manifest_objects"
        return 1
      fi
      manifest_temp="$(/usr/bin/mktemp "${manifest_path}.tmp.XXXXXX")" || {
        umask "$manifest_umask"
        cleanup_temp_file "$validated_json" "$objects_tsv" "$manifest_objects"
        return 1
      }
      umask "$manifest_umask"
      if ! validate_collision_archive_write_boundary \
          "$archive_root" "$groups_root" "$objects_root" \
          "$manifest_path" "$manifest_temp"; then
        cleanup_temp_file "$validated_json" "$objects_tsv" "$manifest_objects"
        return 1
      fi
      generated_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
      if ! validate_collision_archive_write_boundary \
          "$archive_root" "$groups_root" "$objects_root" \
          "$manifest_path" "$manifest_temp"; then
        cleanup_temp_file "$validated_json" "$objects_tsv" "$manifest_objects"
        return 1
      fi
      if ! /usr/bin/jq -n \
          --arg area "$relative_destination" \
          --arg path "$logical_path" \
          --arg collisionKind "$collision_kind" \
          --arg generatedAt "$generated_at" \
          --arg versionRunID "$VERSION_RUN_ID" \
          --slurpfile objects "$manifest_objects" '
            {
              protocol: 1,
              archive: "drive-id-collisions-v1",
              area: $area,
              logicalPath: $path,
              collisionKind: $collisionKind,
              generatedAt: $generatedAt,
              versionRunID: $versionRunID,
              objects: $objects
            }
            | with_entries(select(.value != null and .value != ""))
          ' >"$manifest_temp"; then
        cleanup_collision_target_if_safe \
          "$archive_root" "$groups_root" "$objects_root" "$manifest_temp" || true
        cleanup_temp_file "$validated_json" "$objects_tsv" "$manifest_objects"
        RUN_STATE_REASON="destination_permission_denied"
        log "FEHLER: Das Manifest des Drive-ID-Archivs konnte nicht atomar geschrieben werden."
        return 1
      fi
      if ! validate_collision_archive_write_boundary \
          "$archive_root" "$groups_root" "$objects_root" \
          "$manifest_path" "$manifest_temp"; then
        cleanup_temp_file "$validated_json" "$objects_tsv" "$manifest_objects"
        return 1
      fi
      if ! /bin/chmod 600 "$manifest_temp"; then
        cleanup_collision_target_if_safe \
          "$archive_root" "$groups_root" "$objects_root" "$manifest_temp" || true
        cleanup_temp_file "$validated_json" "$objects_tsv" "$manifest_objects"
        RUN_STATE_REASON="destination_permission_denied"
        log "FEHLER: Das Manifest des Drive-ID-Archivs konnte nicht atomar geschrieben werden."
        return 1
      fi
      if ! validate_collision_archive_write_boundary \
          "$archive_root" "$groups_root" "$objects_root" \
          "$manifest_path" "$manifest_temp"; then
        cleanup_temp_file "$validated_json" "$objects_tsv" "$manifest_objects"
        return 1
      fi
      if ! /bin/mv "$manifest_temp" "$manifest_path"; then
        cleanup_collision_target_if_safe \
          "$archive_root" "$groups_root" "$objects_root" "$manifest_temp" || true
        cleanup_temp_file "$validated_json" "$objects_tsv" "$manifest_objects"
        RUN_STATE_REASON="destination_permission_denied"
        log "FEHLER: Das Manifest des Drive-ID-Archivs konnte nicht atomar geschrieben werden."
        return 1
      fi
      manifest_temp=""
      if ! validate_collision_archive_write_boundary \
          "$archive_root" "$groups_root" "$objects_root" "$manifest_path"; then
        cleanup_temp_file "$validated_json" "$objects_tsv" "$manifest_objects"
        return 1
      fi
    fi
    cleanup_temp_file "$validated_json" "$objects_tsv" "$manifest_objects"
    if ! validate_collision_archive_write_boundary \
        "$archive_root" "$groups_root" "$objects_root" "$manifest_path"; then
      return 1
    fi
    log "Drive-ID-Archiv vollstaendig: $match_count getrennte Objekte fuer einen gleichnamigen Eintrag."
  done <"$collision_report"

  [[ -n "$seen_hashes" ]] || {
    log "FEHLER: Die rclone-Kollisionsmeldung enthielt keine sicher archivierbare Drive-ID."
    return 1
  }
  if ! validate_collision_archive_write_boundary \
      "$archive_root" "$groups_root" "$objects_root"; then
    log "FEHLER: Das ID-Archiv konnte nach dem Schreiben nicht sicher bestaetigt werden."
    return 1
  fi
  return 0
}

copy_one() {
  local label="$1"
  local source="$2"
  local dest="$3"
  shift 3
  local phase=""
  local backup_dir=""
  local copy_status=0
  local apfs_target_status=0
  local collision_report=""

  COPY_INDEX=$((COPY_INDEX + 1))
  if (( COPY_TOTAL > 0 )); then
    phase="${COPY_INDEX}/${COPY_TOTAL}"
  fi

  if ! validate_live_nas_destination; then
    errors=$((errors + 1))
    return
  fi
  if [[ "$ENCRYPTION" == "rclone-crypt" ]]; then
    validate_configured_apfs_target || apfs_target_status=$?
  else
    validate_configured_apfs_target_paths "$dest" ||
      apfs_target_status=$?
  fi
  if [[ "$apfs_target_status" != "0" ]]; then
    log "FEHLER: APFS-Backup-Volume konnte vor '$label' nicht erneut bestaetigt werden."
    errors=$((errors + 1))
    return
  fi
  if [[ "$ENCRYPTION" == "rclone-crypt" ]] && ! validate_rclone_crypt_config; then
    log "FEHLER: Crypt-Ziel konnte vor '$label' nicht erneut bestaetigt werden."
    errors=$((errors + 1))
    return
  fi
  if ! validate_encrypted_apfs_destination; then
    log "FEHLER: Verschluesseltes Volume konnte vor '$label' nicht erneut bestaetigt werden."
    errors=$((errors + 1))
    return
  fi
  if [[ "$ENCRYPTION" != "rclone-crypt" ]] && ! path_is_on_encrypted_volume "$dest"; then
    log "FEHLER: Kopierziel liegt nicht sicher auf dem verschluesselten Volume: $dest"
    errors=$((errors + 1))
    return
  fi

  if [[ "$DRY_RUN" == "0" && "$ENCRYPTION" != "rclone-crypt" ]]; then
    mkdir -p "$dest" || {
      log "FEHLER: Zielordner kann nicht angelegt werden: $dest"
      errors=$((errors + 1))
      return
    }
    if ! validate_configured_apfs_target_paths "$dest"; then
      log "FEHLER: Angelegtes Kopierziel liegt nicht sicher auf dem APFS-Backup-Volume: $dest"
      errors=$((errors + 1))
      return
    fi
  fi

  if [[ "$ENCRYPTION" != "rclone-crypt" ]] && ! validate_encrypted_destination_tree "$dest"; then
    log "FEHLER: Kopierziel enthaelt einen unsicheren Link oder Mount: $dest"
    errors=$((errors + 1))
    return
  fi
  if [[ "$ENCRYPTION" != "rclone-crypt" ]] &&
     ! validate_configured_apfs_tree "$dest"; then
    log "FEHLER: Kopierziel enthaelt einen unsicheren APFS-Pfad oder ein fremdes Dateisystem: $dest"
    errors=$((errors + 1))
    return
  fi

  if [[ "$VERSIONING" == "1" ]]; then
    if ! backup_dir="$(version_backup_dir_for "$dest")"; then
      log "FEHLER: Versionsziel konnte fuer '$dest' nicht sicher bestimmt werden."
      errors=$((errors + 1))
      return
    fi
    if [[ "$ENCRYPTION" != "rclone-crypt" ]] && ! path_is_on_encrypted_volume "$backup_dir"; then
      log "FEHLER: Versionsziel liegt nicht sicher auf dem verschluesselten Volume: $backup_dir"
      errors=$((errors + 1))
      return
    fi
    if [[ "$ENCRYPTION" != "rclone-crypt" ]] &&
       ! validate_configured_apfs_tree "$backup_dir"; then
      log "FEHLER: Aktuelles Versionsziel enthaelt einen unsicheren APFS-Pfad oder ein fremdes Dateisystem."
      errors=$((errors + 1))
      return
    fi
  fi
  if [[ "$ENCRYPTION" != "rclone-crypt" ]]; then
    if [[ -n "$backup_dir" ]]; then
      if ! validate_configured_apfs_target_paths "$dest" "$backup_dir"; then
        log "FEHLER: Kopier- oder Versionsziel verlaesst das konfigurierte APFS-Backup-Volume."
        errors=$((errors + 1))
        return
      fi
    elif ! validate_configured_apfs_target_paths "$dest"; then
      log "FEHLER: Kopierziel verlaesst das konfigurierte APFS-Backup-Volume."
      errors=$((errors + 1))
      return
    fi
  fi

  log "Kopiere $label -> $dest"
  if ! write_durable_progress "$(public_progress_label "$label")" "" "" "$phase"; then
    warn_progress_unavailable
  fi
  write_progress "$label" "" "" "$phase"
  if [[ "$VERSIONING" == "1" ]]; then
    run_rclone_with_progress "$label" "$phase" rclone copy "$source" "$dest" \
      --backup-dir "$backup_dir" "$@" "${RCLONE_OPTS[@]}" || copy_status=$?
  else
    run_rclone_with_progress "$label" "$phase" rclone copy "$source" "$dest" \
      "$@" "${RCLONE_OPTS[@]}" || copy_status=$?
  fi
  collision_report="$LAST_RCLONE_COLLISION_REPORT"
  LAST_RCLONE_COLLISION_REPORT=""
  if [[ "$copy_status" == "65" ]]; then
    if archive_source_collisions "$label" "$phase" "$source" "$dest" \
        "$collision_report" "$@"; then
      copy_status=0
      if [[ "$RUN_STATE_REASON" == "source_name_collision" && "$errors" == "0" ]]; then
        RUN_STATE_REASON=""
      fi
    else
      copy_status=1
      RUN_STATE_REASON="${RUN_STATE_REASON:-source_name_collision}"
    fi
  fi
  cleanup_temp_file "$collision_report"

  # A vanished SMB mount must never be recreated as an ordinary directory on
  # the startup disk. Revalidate after every transfer before attempting the
  # next destination, even when rclone itself returned success.
  if ! validate_live_nas_destination; then
    copy_status=1
  fi
  if [[ "$ENCRYPTION" == "rclone-crypt" ]]; then
    if ! validate_configured_apfs_target; then
      copy_status=1
    fi
  elif [[ -n "$backup_dir" ]]; then
    if ! validate_configured_apfs_target_paths "$dest" "$backup_dir"; then
      copy_status=1
    fi
  elif ! validate_configured_apfs_target_paths "$dest"; then
    copy_status=1
  fi
  if [[ "$ENCRYPTION" != "rclone-crypt" ]]; then
    if ! validate_configured_apfs_tree "$dest"; then
      copy_status=1
    fi
    if [[ -n "$backup_dir" ]] &&
       ! validate_configured_apfs_tree "$backup_dir"; then
      copy_status=1
    fi
  fi

  if [[ "$copy_status" == "0" ]]; then
    write_progress "$label" "100" "$(t progress_done)" "$phase"
    log "OK: $label"
  else
    log "FEHLER: $label"
    errors=$((errors + 1))
  fi
}

drives_json="$(mktemp "${TMPDIR:-/tmp}/gdrive-shared-drives.XXXXXX")"
if rclone backend --json drives "${REMOTE}:" >"$drives_json"; then
  drive_count="$(jq 'length' "$drives_json" 2>/dev/null || printf '0')"
  log "$drive_count Shared Drive(s) gefunden."
  COPY_TOTAL=$((2 + drive_count))

  copy_one "My Drive" "${REMOTE}:" "$(backup_destination_for 'My Drive')"
  copy_one "Shared with me" "${REMOTE}:" "$(backup_destination_for 'Shared with me')" --drive-shared-with-me

  while IFS=$'\t' read -r drive_id drive_name; do
    [[ -n "$drive_id" ]] || continue
    safe="$(safe_name "$drive_name")"

    copy_one "Shared Drive: $drive_name" "${REMOTE}:" \
      "$(backup_destination_for "Shared Drives/${safe} (${drive_id})")" \
      --drive-team-drive "$drive_id"
  done < <(jq -r '.[] | [.id, .name] | @tsv' "$drives_json")
else
  log "FEHLER: Shared Drives konnten nicht gelesen werden."
  errors=$((errors + 1))

  COPY_TOTAL=2
  copy_one "My Drive" "${REMOTE}:" "$(backup_destination_for 'My Drive')"
  copy_one "Shared with me" "${REMOTE}:" "$(backup_destination_for 'Shared with me')" --drive-shared-with-me
fi
cleanup_temp_file "$drives_json"

if (( errors > 0 )); then
  log "Fertig mit $errors Fehler(n)."
  exit 1
fi

if [[ "$VERSIONING" == "1" && "$RETENTION" == "1" ]]; then
  if ! prune_version_history; then
    log "Fertig: Backup erfolgreich, aber Aufbewahrung mit Fehler(n)."
    exit 1
  fi
elif [[ "$RETENTION" == "0" ]]; then
  log "Automatische Versionsaufbewahrung ist deaktiviert."
else
  log "Versionsaufbewahrung uebersprungen, weil Dateiversionierung deaktiviert ist."
fi

RUN_OUTCOME="success"
log "Fertig ohne Fehler."
