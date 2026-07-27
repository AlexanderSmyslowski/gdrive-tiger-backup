#!/bin/bash
set -uo pipefail

PATH="${GDRIVE_BACKUP_PATH:-/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin}"
export PATH

if [[ -z "${HOME:-}" ]]; then
  HOME="$(/usr/bin/dscl . -read "/Users/$(/usr/bin/id -un)" NFSHomeDirectory 2>/dev/null | /usr/bin/awk '{print $2}')"
  export HOME
fi

if [[ -z "${HOME:-}" || ! -d "$HOME" ]]; then
  printf 'FEHLER: HOME konnte nicht ermittelt werden.\n' >&2
  exit 78
fi

lowercase() {
  printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]'
}

nas_mount_from_url() {
  local url="${1%%\?*}"
  local without_scheme path share
  url="${url%/}"

  without_scheme="${url#*://}"
  if [[ "$without_scheme" == "$url" || "$without_scheme" != */* ]]; then
    return 0
  fi

  path="${without_scheme#*/}"
  share="${path%%/*}"
  if [[ -n "$share" ]]; then
    printf '/Volumes/%s' "$share"
  fi
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

find_nas_mount_for_url() {
  local host line source mount_path source_host
  host="$(nas_host_from_url "$1")"
  [[ -n "$host" ]] || return 0

  while IFS= read -r line; do
    [[ "$line" == *" on /Volumes/"* ]] || continue
    [[ "$line" == *" (smbfs,"* || "$line" == *" (afpfs,"* || "$line" == *" (nfs,"* ]] || continue
    source="${line%% on /Volumes/*}"
    source="${source#//}"
    source="${source#*@}"
    source_host="${source%%/*}"
    source_host="$(lowercase "$source_host")"
    [[ "$source_host" == "$host" ]] || continue
    mount_path="${line#* on }"
    mount_path="${mount_path%% (*}"
    printf '%s' "$mount_path"
    return 0
  done < <(/sbin/mount)
}

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

BACKUP_TRIGGER="${GDRIVE_BACKUP_TRIGGER:-manual}"
AUTOMATIC_BACKUPS_PAUSED="${GDRIVE_BACKUP_PAUSED:-0}"
NAS_START_ON_MOUNT="${GDRIVE_BACKUP_NAS_START_ON_MOUNT:-0}"
if [[ "$BACKUP_TRIGGER" == "mount" && "$NAS_START_ON_MOUNT" != "1" ]]; then
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
VOLUMES_ROOT="${GDRIVE_BACKUP_VOLUMES_ROOT:-/Volumes}"
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
  VOLUME="${GDRIVE_BACKUP_VOLUME:-/Volumes/$BACKUP_VOLUME_NAME}"
  DEST_ROOT="${GDRIVE_BACKUP_DEST_ROOT:-$VOLUME}"
fi
CONFIGURED_APFS_VOLUME="$VOLUME"
CONFIGURED_APFS_DEST_ROOT="$DEST_ROOT"
REMOTE="${RCLONE_REMOTE:-gdrive}"
REMOTE="${REMOTE%:}"

LOG="${GDRIVE_BACKUP_LOG:-$HOME/Library/Logs/gdrive-backup.log}"
LOCK="${GDRIVE_BACKUP_LOCK:-$HOME/Library/Logs/gdrive-backup.lock}"
MOUNT_SETTLE_SECONDS="${MOUNT_SETTLE_SECONDS:-5}"
ANIMATION_APP="${GDRIVE_BACKUP_ANIMATION_APP:-/Applications/GDrive Backup Tiger.app}"
if [[ ! -d "$ANIMATION_APP" && -d "$HOME/Applications/GDrive Backup Tiger.app" ]]; then
  ANIMATION_APP="$HOME/Applications/GDrive Backup Tiger.app"
fi
ANIMATION_SENTINEL=""
PROGRESS_FILE=""
RUN_STATE_FILE="${GDRIVE_BACKUP_RUN_STATE_FILE:-}"
RUN_STATE_IS_TEMP=0
RUN_STATE_OVERRIDE=""
RUN_OUTCOME="failure"
RUN_STATE_REASON=""
RUN_STATE_SIGNAL=""
if [[ -n "${GDRIVE_BACKUP_SUMMARY_STATE_FILE:-}" ]]; then
  SUMMARY_STATE_FILE="$GDRIVE_BACKUP_SUMMARY_STATE_FILE"
elif [[ -n "$ACTIVE_PROFILE_ID" ]]; then
  SUMMARY_STATE_FILE="$HOME/Library/Application Support/GDrive Backup Tiger/profiles/$ACTIVE_PROFILE_ID/last-run.status"
else
  SUMMARY_STATE_FILE="$HOME/Library/Application Support/GDrive Backup Tiger/last-run.status"
fi
RUN_STARTED_AT=0
OPEN_BIN="${GDRIVE_BACKUP_OPEN_BIN:-/usr/bin/open}"
CONFIRM_BACKUP="${GDRIVE_BACKUP_CONFIRM:-1}"
AUTO_CREATE_VOLUME="${GDRIVE_BACKUP_AUTO_CREATE_VOLUME:-1}"
BACKUP_LANG="${GDRIVE_BACKUP_LANG:-auto}"
VERSIONING="${GDRIVE_BACKUP_VERSIONING-1}"
VERSIONS_SUBDIR="${GDRIVE_BACKUP_VERSIONS_SUBDIR-.gdrive-versions}"
RETENTION="${GDRIVE_BACKUP_RETENTION-1}"
RETENTION_TRASH_BIN="${GDRIVE_BACKUP_RETENTION_TRASH_BIN-}"
RETENTION_APP_TRASH_BIN="${GDRIVE_BACKUP_APP_TRASH_BIN-${ANIMATION_APP%/}/Contents/MacOS/GDriveBackupTiger}"
ENCRYPTION="$(lowercase "${GDRIVE_BACKUP_ENCRYPTION-none}")"
CRYPT_REMOTE="${GDRIVE_BACKUP_CRYPT_REMOTE-}"
DISKUTIL_BIN="${GDRIVE_BACKUP_DISKUTIL-/usr/sbin/diskutil}"
OSASCRIPT_BIN="${GDRIVE_BACKUP_OSASCRIPT-/usr/bin/osascript}"
MOUNT_BIN="${GDRIVE_BACKUP_MOUNT_BIN-/sbin/mount}"
CMP_BIN="${GDRIVE_BACKUP_CMP_BIN-/usr/bin/cmp}"
ENCRYPTED_VOLUME_REAL=""
ENCRYPTED_VOLUME_DEVICE=""
ENCRYPTED_VOLUME_UUID=""
ENCRYPTED_VOLUME_IDENTIFIER=""
APFS_VOLUME_REAL=""
APFS_VOLUME_DEVICE=""
APFS_VOLUME_UUID=""
APFS_VOLUME_IDENTIFIER=""
CREATED_APFS_VOLUME_UUID=""
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

cleanup_temp_file() {
  local path
  local trash_bin="${GDRIVE_BACKUP_TEMP_TRASH_BIN:-/usr/bin/trash}"
  for path in "$@"; do
    [[ -n "$path" && -e "$path" ]] || continue
    # Cleanup stays recoverable; older systems without trash intentionally keep the temp file.
    if [[ ! -x "$trash_bin" ]]; then
      log "WARNUNG: Temporaere Datei bleibt erhalten, weil das Papierkorb-Werkzeug fehlt: $path"
      continue
    fi
    if ! "$trash_bin" "$path" >/dev/null 2>&1; then
      log "WARNUNG: Temporaere Datei konnte nicht in den Papierkorb verschoben werden: $path"
    fi
  done
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
  local attempt compare_status=2

  for attempt in 1 2 3; do
    "$CMP_BIN" -s "$manifest_path" <(nas_name_codec_manifest_content)
    compare_status=$?
    case "$compare_status" in
      0|1) return "$compare_status" ;;
    esac
    if (( attempt < 3 )); then
      log "WARNUNG: Das NAS-Namenscodec-Manifest ist voruebergehend nicht lesbar; Vergleich wird wiederholt."
      /bin/sleep 0.25
    fi
  done
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
     ! root_device="$(/usr/bin/stat -f '%d' "$root_real" 2>/dev/null)" ||
     [[ -z "$root_device" ]]; then
    log "FEHLER: Der physische Crypt-Zielordner ist nicht sicher."
    return 1
  fi
  if ! symlink_path="$(/usr/bin/find -x "$root_real" -type l -print -quit 2>/dev/null)" ||
     [[ -n "$symlink_path" ]]; then
    log "FEHLER: Der physische Crypt-Zielbaum enthaelt einen symbolischen Link."
    return 1
  fi
  if ! device_listing="$(/usr/bin/find -x "$root_real" -type d \
      -exec /usr/bin/stat -f '%d' {} + 2>/dev/null)"; then
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

path_is_on_encrypted_volume() {
  local path="$1"
  local existing_real device

  [[ "$ENCRYPTION" == "apfs" ]] || return 0
  [[ -n "$ENCRYPTED_VOLUME_REAL" && -n "$ENCRYPTED_VOLUME_DEVICE" ]] || return 1

  if ! existing_real="$(canonical_existing_ancestor "$path")"; then
    log "FEHLER: Verschluesseltes Ziel kann nicht sicher aufgeloest werden: $(safe_name "$path")"
    return 1
  fi
  if ! device="$(/usr/bin/stat -f '%d' "$existing_real" 2>/dev/null)" ||
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

plist_data_value() {
  local plist_data="$1"
  local key="$2"
  printf '%s' "$plist_data" | /usr/bin/plutil -extract "$key" raw -o - - 2>/dev/null
}

normalized_apfs_uuid() {
  printf '%s' "$1" | /usr/bin/tr '[:lower:]' '[:upper:]'
}

resolve_configured_apfs_volume() {
  local plist_data filesystem mount_point volume_uuid writable_media
  local configured_volume configured_destination resolved_mount destination_suffix
  local resolved_destination existing_ancestor mount_device destination_device

  [[ "$BACKUP_TARGET" == "apfs" && -n "$BACKUP_VOLUME_UUID" ]] || return 0
  if [[ ! "$BACKUP_VOLUME_UUID" =~ ^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$ ]]; then
    log "FEHLER: GDRIVE_BACKUP_VOLUME_UUID ist keine gueltige APFS-Volume-UUID."
    return 64
  fi
  if [[ ! -x "$DISKUTIL_BIN" ]]; then
    log "FEHLER: diskutil fuer die APFS-Volume-Identitaet fehlt: $(safe_name "$DISKUTIL_BIN")"
    return 127
  fi
  if ! plist_data="$(run_with_timeout 8 "$DISKUTIL_BIN" info -plist "$BACKUP_VOLUME_UUID" 2>/dev/null)"; then
    log "FEHLER: Das konfigurierte APFS-Backup-Volume ist nicht verfuegbar."
    return 69
  fi

  filesystem="$(plist_data_value "$plist_data" FilesystemType || true)"
  mount_point="$(plist_data_value "$plist_data" MountPoint || true)"
  volume_uuid="$(plist_data_value "$plist_data" VolumeUUID || true)"
  writable_media="$(plist_data_value "$plist_data" WritableMedia || true)"
  if [[ "$filesystem" != "apfs" || -z "$mount_point" ||
        "$(normalized_apfs_uuid "$volume_uuid")" != "$(normalized_apfs_uuid "$BACKUP_VOLUME_UUID")" ||
        "$writable_media" != "true" ]]; then
    log "FEHLER: diskutil bestaetigt nicht das konfigurierte APFS-Backup-Volume."
    return 69
  fi
  if ! resolved_mount="$(canonical_existing_directory "$mount_point")"; then
    log "FEHLER: Das konfigurierte APFS-Backup-Volume ist nicht eingehängt."
    return 69
  fi

  configured_volume="$CONFIGURED_APFS_VOLUME"
  configured_destination="$CONFIGURED_APFS_DEST_ROOT"
  if [[ "$configured_destination" == "$configured_volume" ]]; then
    DEST_ROOT="$resolved_mount"
  elif [[ "$configured_destination" == "$configured_volume/"* ]]; then
    destination_suffix="${configured_destination#"$configured_volume"}"
    case "/${destination_suffix#/}/" in
      *"//"*|*"/./"*|*"/../"*)
        log "FEHLER: Das APFS-Ziel enthaelt unsichere Pfadbestandteile."
        return 69
        ;;
    esac
    resolved_destination="${resolved_mount}${destination_suffix}"
    if ! existing_ancestor="$(canonical_existing_ancestor "$resolved_destination")"; then
      log "FEHLER: Das APFS-Ziel kann nicht sicher aufgeloest werden."
      return 69
    fi
    case "$existing_ancestor/" in
      "$resolved_mount/"*) ;;
      *)
        log "FEHLER: Das APFS-Ziel verlaesst das konfigurierte Backup-Volume."
        return 69
        ;;
    esac
    if ! mount_device="$(/usr/bin/stat -f '%d' "$resolved_mount" 2>/dev/null)" ||
       ! destination_device="$(/usr/bin/stat -f '%d' "$existing_ancestor" 2>/dev/null)" ||
       [[ -z "$mount_device" || "$mount_device" != "$destination_device" ]]; then
      log "FEHLER: Das APFS-Ziel liegt nicht auf dem konfigurierten Backup-Volume."
      return 69
    fi
    DEST_ROOT="$resolved_destination"
  else
    log "FEHLER: Das APFS-Ziel liegt ausserhalb des konfigurierten Backup-Volumes."
    return 69
  fi
  VOLUME="$resolved_mount"
  log "APFS-Backup-Volume per UUID aufgeloest: $VOLUME"
  return 0
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
    if ! destination_device="$(/usr/bin/stat -f '%d' "$existing_ancestor" 2>/dev/null)" ||
       [[ -z "$destination_device" ||
          "$destination_device" != "$APFS_VOLUME_DEVICE" ]]; then
      log "FEHLER: APFS-Pfad liegt nicht mehr auf dem konfigurierten Backup-Volume."
      return 1
    fi
  done
  return 0
}

validate_configured_apfs_tree() {
  local root="$1"

  [[ "$BACKUP_TARGET" == "apfs" && -n "$BACKUP_VOLUME_UUID" ]] || return 0
  [[ -e "$root" || -L "$root" ]] || return 0
  if ! validate_configured_apfs_paths "$root"; then
    return 1
  fi
  if [[ -L "$root" ]]; then
    log "FEHLER: Symbolischer Link im UUID-gebundenen APFS-Ziel ist nicht zulaessig: $(safe_name "$root")"
    return 1
  fi
  # One streamed walk catches both link redirections and nested mount points.
  # Device IDs stay bounded by find's argv batches instead of being retained
  # as one shell variable for a potentially very large backup history.
  if ! /usr/bin/find -x "$root" \
      \( -type l -print \) -o \
      \( -type d -exec /bin/bash -c '
        /usr/bin/stat -f "%d" "$@" 2>/dev/null ||
          printf "%s\n" "__GDRIVE_APFS_STAT_FAILED__"
      ' _ {} + \) 2>/dev/null |
      /usr/bin/awk -v expected_device="$APFS_VOLUME_DEVICE" '
        $0 != expected_device { unsafe = 1 }
        END { exit unsafe ? 1 : 0 }
      '; then
    log "FEHLER: APFS-Zielbaum enthaelt einen symbolischen Link, ein fremdes Dateisystem oder einen unlesbaren Pfad: $(safe_name "$root")"
    return 1
  fi
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

validate_configured_apfs_volume_identity() {
  local plist_data filesystem mount_point volume_uuid volume_identifier
  local mount_real current_real current_device

  [[ "$BACKUP_TARGET" == "apfs" && -n "$BACKUP_VOLUME_UUID" ]] || return 0
  if ! plist_data="$(run_with_timeout 8 "$DISKUTIL_BIN" info -plist "$BACKUP_VOLUME_UUID" 2>/dev/null)"; then
    log "FEHLER: Identitaet des APFS-Backup-Volumes ist nicht mehr lesbar."
    return 1
  fi
  filesystem="$(plist_data_value "$plist_data" FilesystemType || true)"
  mount_point="$(plist_data_value "$plist_data" MountPoint || true)"
  volume_uuid="$(plist_data_value "$plist_data" VolumeUUID || true)"
  volume_identifier="$(plist_data_value "$plist_data" DeviceIdentifier || true)"
  if [[ "$filesystem" != "apfs" || -z "$mount_point" || -z "$volume_identifier" ||
        "$(normalized_apfs_uuid "$volume_uuid")" != "$(normalized_apfs_uuid "$BACKUP_VOLUME_UUID")" ]]; then
    log "FEHLER: Identitaet des APFS-Backup-Volumes stimmt nicht mehr."
    return 1
  fi
  if ! current_real="$(canonical_existing_directory "$VOLUME")" ||
     ! mount_real="$(canonical_existing_directory "$mount_point")" ||
     [[ "$current_real" != "$mount_real" ]]; then
    log "FEHLER: Das APFS-Backup-Volume ist nicht mehr am aufgeloesten Mountpunkt."
    return 1
  fi
  if ! current_device="$(/usr/bin/stat -f '%d' "$current_real" 2>/dev/null)" ||
     [[ -z "$current_device" ]]; then
    log "FEHLER: Dateisystem-ID des APFS-Backup-Volumes ist nicht lesbar."
    return 1
  fi

  if [[ -z "$APFS_VOLUME_UUID" ]]; then
    APFS_VOLUME_REAL="$current_real"
    APFS_VOLUME_DEVICE="$current_device"
    APFS_VOLUME_UUID="$volume_uuid"
    APFS_VOLUME_IDENTIFIER="$volume_identifier"
  elif [[ "$current_real" != "$APFS_VOLUME_REAL" ||
          "$current_device" != "$APFS_VOLUME_DEVICE" ||
          "$(normalized_apfs_uuid "$volume_uuid")" != "$(normalized_apfs_uuid "$APFS_VOLUME_UUID")" ||
          "$volume_identifier" != "$APFS_VOLUME_IDENTIFIER" ]]; then
    log "FEHLER: Das APFS-Backup-Volume wurde waehrend des Laufs ausgetauscht."
    return 1
  fi
  return 0
}

validate_encrypted_apfs_destination() {
  local plist_data filesystem encrypted mount_point locked volume_uuid volume_identifier
  local mount_real current_real current_device active_path initial_validation=0

  [[ "$ENCRYPTION" == "apfs" ]] || return 0

  if [[ ! -x "$DISKUTIL_BIN" ]]; then
    log "FEHLER: diskutil fuer die Verschluesselungspruefung fehlt: $(safe_name "$DISKUTIL_BIN")"
    return 1
  fi
  if ! plist_data="$(run_with_timeout 8 "$DISKUTIL_BIN" info -plist "$VOLUME" 2>/dev/null)"; then
    log "FEHLER: Verschluesselungsstatus des Backup-Volumes ist nicht lesbar."
    return 1
  fi

  filesystem="$(plist_data_value "$plist_data" FilesystemType || true)"
  encrypted="$(plist_data_value "$plist_data" Encryption || true)"
  mount_point="$(plist_data_value "$plist_data" MountPoint || true)"
  locked="$(plist_data_value "$plist_data" Locked || true)"
  volume_uuid="$(plist_data_value "$plist_data" VolumeUUID || true)"
  volume_identifier="$(plist_data_value "$plist_data" DeviceIdentifier || true)"
  if [[ "$filesystem" != "apfs" || "$encrypted" != "true" || "$locked" != "false" ||
        -z "$mount_point" || -z "$volume_uuid" || -z "$volume_identifier" ]]; then
    log "FEHLER: Backup-Volume ist nicht verschluesselt oder kein entsperrtes APFS-Volume."
    return 1
  fi

  if ! current_real="$(canonical_existing_directory "$VOLUME")" ||
     ! mount_real="$(canonical_existing_directory "$mount_point")" ||
     [[ "$current_real" != "$mount_real" ]]; then
    log "FEHLER: diskutil bestaetigt nicht den konfigurierten APFS-Mountpunkt."
    return 1
  fi
  if ! current_device="$(/usr/bin/stat -f '%d' "$current_real" 2>/dev/null)" ||
     [[ -z "$current_device" ]]; then
    log "FEHLER: Dateisystem-ID des verschluesselten Volumes ist nicht lesbar."
    return 1
  fi

  if [[ -z "$ENCRYPTED_VOLUME_UUID" ]]; then
    initial_validation=1
    ENCRYPTED_VOLUME_REAL="$current_real"
    ENCRYPTED_VOLUME_DEVICE="$current_device"
    ENCRYPTED_VOLUME_UUID="$volume_uuid"
    ENCRYPTED_VOLUME_IDENTIFIER="$volume_identifier"
  elif [[ "$current_real" != "$ENCRYPTED_VOLUME_REAL" ||
          "$current_device" != "$ENCRYPTED_VOLUME_DEVICE" ||
          "$volume_uuid" != "$ENCRYPTED_VOLUME_UUID" ||
          "$volume_identifier" != "$ENCRYPTED_VOLUME_IDENTIFIER" ]]; then
    log "FEHLER: Identitaet des verschluesselten Backup-Volumes hat sich waehrend des Laufs geaendert."
    return 1
  fi

  if ! path_is_on_encrypted_volume "$DEST_ROOT"; then
    return 1
  fi
  for active_path in \
    "$DEST_ROOT/My Drive" \
    "$DEST_ROOT/Shared with me" \
    "$DEST_ROOT/Shared Drives" \
    "$DEST_ROOT/Shared Drives"/* \
    "$DEST_ROOT/Shared Drives"/.[!.]* \
    "$DEST_ROOT/Shared Drives"/..?*; do
    if [[ -e "$active_path" || -L "$active_path" ]] &&
       ! path_is_on_encrypted_volume "$active_path"; then
      return 1
    fi
  done
  if [[ "$VERSIONING" == "1" ]] &&
     ! path_is_on_encrypted_volume "${DEST_ROOT%/}/$VERSIONS_SUBDIR"; then
    return 1
  fi

  if (( initial_validation == 1 )); then
    log "Verschluesseltes APFS-Ziel bestaetigt: $ENCRYPTED_VOLUME_REAL"
  fi
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
  if ! symlink_path="$(/usr/bin/find -x "$root" -type l -print -quit 2>/dev/null)"; then
    log "FEHLER: Zielbaum kann nicht vollstaendig auf symbolische Links geprueft werden: $(safe_name "$root")"
    return 1
  fi
  if [[ -n "$symlink_path" ]]; then
    log "FEHLER: Symbolischer Link im verschluesselten Ziel ist nicht zulaessig: $(safe_name "$symlink_path")"
    return 1
  fi
  if ! device_listing="$(/usr/bin/find -x "$root" -type d -exec /usr/bin/stat -f '%d' {} + 2>/dev/null)"; then
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
     ! encoded="$(printf '%s' "$encoded_json" | /usr/bin/plutil -extract 0 raw -o - - 2>/dev/null)" ||
     printf '%s' "$encoded_json" | /usr/bin/plutil -extract 1 raw -o - - >/dev/null 2>&1; then
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
  if ! root_device="$(/usr/bin/stat -f '%d' "$root_real" 2>/dev/null)" ||
     ! physical_device="$(/usr/bin/stat -f '%d' "$physical_real" 2>/dev/null)" ||
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
    if ! destination_device="$(/usr/bin/stat -f '%d' "$existing_ancestor" 2>/dev/null)" ||
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

  if ! unsafe_link="$(/usr/bin/find -x "$keeper" -type l -print -quit 2>/dev/null)" ||
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
  if [[ -n "$RETENTION_TRASH_BIN" || -x /usr/bin/trash || -x "$RETENTION_APP_TRASH_BIN" ]]; then
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

  log "Aufbewahrung: $name nach .retention-trash verschoben ($reason)."
}

trash_retention_path() {
  local path="$1"

  if [[ -n "$RETENTION_TRASH_BIN" ]]; then
    [[ -x "$RETENTION_TRASH_BIN" ]] || return 1
    validate_retention_destination_identity "$path" || return 2
    if "$RETENTION_TRASH_BIN" "$path" >/dev/null 2>&1; then
      return 0
    fi
    return 1
  fi
  if [[ -x /usr/bin/trash ]]; then
    validate_retention_destination_identity "$path" || return 2
    if /usr/bin/trash "$path" >/dev/null 2>&1; then
      return 0
    fi
    return 1
  fi
  if [[ -x "$RETENTION_APP_TRASH_BIN" ]]; then
    validate_retention_destination_identity "$path" || return 2
    if "$RETENTION_APP_TRASH_BIN" --trash "$path" >/dev/null 2>&1; then
      return 0
    fi
    return 1
  fi
  return 1
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
  local -a retention_paths

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
    if ! normalized_calendar="$(LC_ALL=C /bin/date -j -f '%Y-%m-%dT%H-%M-%S' \
        "$calendar_value" '+%Y-%m-%dT%H-%M-%S' 2>/dev/null)" ||
       [[ "$normalized_calendar" != "$calendar_value" ]] ||
       (( 10#$timezone_hours > 23 || 10#$timezone_minutes > 59 )); then
      log "Aufbewahrung: Ungueltiger Versionszeitpunkt bleibt erhalten: $(safe_name "$name")"
      unknown_count=$((unknown_count + 1))
      continue
    fi
    if ! epoch="$(LC_ALL=C /bin/date -j -f '%Y-%m-%dT%H-%M-%S%z' "$timestamp" '+%s' 2>/dev/null)" ||
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
      if ! bucket="$(LC_ALL=C /bin/date -j -f '%Y-%m-%d' "$day" '+%G-W%V' 2>/dev/null)" ||
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
      local locale="${LANG:-}"
      if command -v defaults >/dev/null 2>&1; then
        locale="$(defaults read -g AppleLocale 2>/dev/null || printf '%s' "$locale")"
      fi
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
  local tmp="${PROGRESS_FILE}.$$"

  {
    printf 'label=%s\n' "$(progress_escape "$label")"
    [[ -n "$phase" ]] && printf 'phase=%s\n' "$(progress_escape "$phase")"
    [[ -n "$percent" ]] && printf 'percent=%s\n' "$(progress_escape "$percent")"
    [[ -n "$detail" ]] && printf 'detail=%s\n' "$(progress_escape "$detail")"
  } >"$tmp" && mv -f "$tmp" "$PROGRESS_FILE"
}

write_run_state() {
  [[ -n "$RUN_STATE_FILE" ]] || return 0

  local status="$1"
  local exit_code="${2:-}"
  local tmp="${RUN_STATE_FILE}.$$"
  {
    printf 'protocol=1\n'
    printf 'status=%s\n' "$status"
    printf 'pid=%s\n' "$$"
    [[ -n "$RUN_STATE_REASON" ]] && printf 'reason=%s\n' "$RUN_STATE_REASON"
    [[ -n "$RUN_STATE_SIGNAL" ]] && printf 'signal=%s\n' "$RUN_STATE_SIGNAL"
    [[ -n "$exit_code" ]] && printf 'exit_code=%s\n' "$exit_code"
  } >"$tmp" && mv -f "$tmp" "$RUN_STATE_FILE"
}

write_last_run_summary() {
  local status="$1"
  local exit_code="${2:-}"
  local summary_dir tmp finished_at last_success_at=""

  [[ "$DRY_RUN" == "0" && "$SETUP_UI" == "0" ]] || return 0
  # A lock-contended process did not perform a backup and must not replace the
  # status of the process that actually owns the destination.
  [[ "$status" != "skipped" ]] || return 0
  [[ -n "$SUMMARY_STATE_FILE" ]] || return 0

  summary_dir="${SUMMARY_STATE_FILE%/*}"
  [[ "$summary_dir" != "$SUMMARY_STATE_FILE" ]] || summary_dir="."
  (umask 077 && mkdir -p "$summary_dir") || return 0
  tmp="${SUMMARY_STATE_FILE}.$$"
  finished_at="$(date +%s 2>/dev/null || printf '0')"
  if [[ -f "$SUMMARY_STATE_FILE" ]]; then
    last_success_at="$(awk -F= '
      $1 == "last_success_at" && $2 ~ /^[0-9]+$/ { value = $2 }
      END { if (value) print value }
    ' "$SUMMARY_STATE_FILE" 2>/dev/null || true)"
  fi
  if [[ "$status" == "success" ]]; then
    last_success_at="$finished_at"
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
    [[ -n "$exit_code" ]] && printf 'exit_code=%s\n' "$exit_code"
    [[ -n "$RUN_STATE_REASON" ]] && printf 'reason=%s\n' "$(progress_escape "$RUN_STATE_REASON")"
    [[ -n "$RUN_STATE_SIGNAL" ]] && printf 'signal=%s\n' "$(progress_escape "$RUN_STATE_SIGNAL")"
    printf 'trigger=%s\n' "$(progress_escape "$BACKUP_TRIGGER")"
    printf 'target=%s\n' "$(progress_escape "$BACKUP_TARGET")"
    printf 'destination=%s\n' "$(progress_escape "$DEST_ROOT")"
  } >"$tmp") && chmod 600 "$tmp" && mv -f "$tmp" "$SUMMARY_STATE_FILE"; then
    return 0
  fi

  cleanup_temp_file "$tmp"
  return 0
}

finish_run_state() {
  local exit_status="$1"
  local status="$RUN_OUTCOME"
  if [[ "$RUN_STATE_OVERRIDE" == "cancelled" ]]; then
    status="cancelled"
  fi
  write_run_state "$status" "$exit_status"
  write_last_run_summary "$status" "$exit_status"
}

update_progress_from_rclone_line() {
  local label="$1"
  local phase="$2"
  local line="$3"

  if [[ "$line" =~ Transferred:[[:space:]]*(.*) ]]; then
    [[ "$line" == *"B /"* ]] || return 0
    local detail="${BASH_REMATCH[1]}"
    local percent=""
    if [[ "$detail" =~ ([0-9]+)% ]]; then
      percent="${BASH_REMATCH[1]}"
    fi
    if [[ -n "$percent" ]]; then
      write_progress "$label" "$percent" "$detail" "$phase"
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
  "$@" 2>&1 | while IFS= read -r line; do
    printf '%s\n' "$line"
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

  ANIMATION_SENTINEL="$(mktemp "${TMPDIR:-/tmp}/gdrive-backup-ui.XXXXXX")" || {
    log "WARNUNG: Sentinel fuer Backup-Animation konnte nicht angelegt werden."
    return
  }
  printf '%s\n' "$$" >"$ANIMATION_SENTINEL"

  PROGRESS_FILE="$(mktemp "${TMPDIR:-/tmp}/gdrive-backup-progress.XXXXXX")" || {
    log "WARNUNG: Fortschrittsdatei fuer Backup-Animation konnte nicht angelegt werden."
    PROGRESS_FILE=""
  }
  if [[ -n "$PROGRESS_FILE" ]]; then
    write_progress "Google Drive Backup" "" "$(t progress_preparing)" ""
  fi

  if [[ -z "$RUN_STATE_FILE" ]]; then
    RUN_STATE_FILE="$(mktemp "${TMPDIR:-/tmp}/gdrive-backup-state.XXXXXX")" || {
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
  # Publish the terminal result before the sentinel disappears, so the UI can
  # never infer success merely from process cleanup.
  finish_run_state "$exit_status"
  stop_animation
}

on_exit() {
  local exit_status=$?
  cleanup "$exit_status"
}

cancel_run() {
  RUN_STATE_OVERRIDE="cancelled"
  RUN_STATE_SIGNAL="$2"
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
  ) >/dev/null 2>&1 &
  local killer_pid=$!

  wait "$command_pid"
  local status=$?
  kill "$killer_pid" 2>/dev/null || true
  wait "$killer_pid" 2>/dev/null || true
  return "$status"
}

plist_value() {
  local plist="$1"
  local key="$2"
  /usr/bin/plutil -extract "$key" raw -o - "$plist" 2>/dev/null || true
}

confirm_prompt() {
  local title="$1"
  local detail="$2"
  local primary_button="$3"
  local secondary_button
  secondary_button="$(t not_now)"

  if [[ "$CONFIRM_BACKUP" == "0" || "${BACKUP_ASSUME_YES:-0}" == "1" ]]; then
    return 0
  fi

  local response=""
  local decision=""

  log "Warte auf Benutzerbestaetigung: $title $detail"

  if [[ -d "$ANIMATION_APP" ]]; then
    response="$(mktemp "${TMPDIR:-/tmp}/gdrive-backup-confirm.XXXXXX")" || {
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

  if command -v osascript >/dev/null 2>&1; then
    decision="$(/usr/bin/osascript - "$title" "$detail" "$primary_button" "$secondary_button" <<'OSA'
on run argv
  set dialogTitle to item 1 of argv
  set dialogDetail to item 2 of argv
  set primaryButton to item 3 of argv
  set secondaryButton to item 4 of argv
  try
    set answer to display dialog dialogTitle & return & return & dialogDetail with title "Google Drive Backup" buttons {secondaryButton, primaryButton} default button secondaryButton cancel button secondaryButton giving up after 120
    if gave up of answer then return "no"
    if button returned of answer is primaryButton then return "yes"
  end try
  return "no"
end run
OSA
)" || decision="no"

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
  fi

  if confirm_prompt "$title" "$detail" "$(t start_backup)"; then
    TARGET_APPROVED=1
    log "$(t log_confirmed)"
    return 0
  fi

  log "$(t log_skipped)"
  return 1
}

find_setup_candidate() {
  local best_mtime=0
  local best_mount=""
  local best_container=""
  local best_name=""
  local mount plist fs external container name system_image writable_media mtime

  for mount in "$VOLUMES_ROOT"/*; do
    [[ -d "$mount" ]] || continue
    [[ "$mount" != "$VOLUME" ]] || continue
    [[ "$(basename "$mount")" != "$BACKUP_VOLUME_NAME" ]] || continue

    plist="$(mktemp "${TMPDIR:-/tmp}/gdrive-volume-info.XXXXXX")" || continue
    if ! run_with_timeout 6 "$DISKUTIL_BIN" info -plist "$mount" >"$plist"; then
      cleanup_temp_file "$plist" >/dev/null
      continue
    fi

    fs="$(plist_value "$plist" FilesystemType)"
    external="$(plist_value "$plist" RemovableMediaOrExternalDevice)"
    container="$(plist_value "$plist" APFSContainerReference)"
    name="$(plist_value "$plist" VolumeName)"
    system_image="$(plist_value "$plist" SystemImage)"
    writable_media="$(plist_value "$plist" WritableMedia)"
    cleanup_temp_file "$plist" >/dev/null

    [[ "$fs" == "apfs" ]] || continue
    [[ "$external" == "true" ]] || continue
    [[ -n "$container" ]] || continue
    [[ "$system_image" != "true" ]] || continue
    [[ "$writable_media" == "true" ]] || continue

    mtime="$(stat -f '%m' "$mount" 2>/dev/null || printf '0')"
    if (( mtime > best_mtime )); then
      best_mtime="$mtime"
      best_mount="$mount"
      best_container="$container"
      best_name="${name:-$(basename "$mount")}"
    fi
  done

  [[ -n "$best_mount" ]] || return 1
  printf '%s\t%s\t%s\n' "$best_mount" "$best_container" "$best_name"
}

capture_named_apfs_volume_uuids() {
  local container="$1"
  local output_file="$2"
  local plist_data json_data uuid invalid_uuid=0
  local unsorted_file

  unsorted_file="$(mktemp "${TMPDIR:-/tmp}/gdrive-apfs-uuids.XXXXXX")" ||
    return 1
  : >"$unsorted_file"
  if ! plist_data="$(run_with_timeout 8 "$DISKUTIL_BIN" apfs list -plist "$container" 2>/dev/null)" ||
     ! json_data="$(printf '%s' "$plist_data" |
       /usr/bin/plutil -convert json -o - - 2>/dev/null)" ||
     ! printf '%s' "$json_data" |
       jq -r --arg name "$BACKUP_VOLUME_NAME" \
         '.Containers[]?.Volumes[]? |
          select(.Name == $name) |
          (.APFSVolumeUUID // empty)' >"$unsorted_file"; then
    cleanup_temp_file "$unsorted_file"
    return 1
  fi

  : >"$output_file"
  while IFS= read -r uuid; do
    [[ -n "$uuid" ]] || continue
    if [[ ! "$uuid" =~ ^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$ ]]; then
      invalid_uuid=1
      continue
    fi
    normalized_apfs_uuid "$uuid" >>"$output_file"
    printf '\n' >>"$output_file"
  done <"$unsorted_file"
  cleanup_temp_file "$unsorted_file"
  [[ "$invalid_uuid" == "0" ]] || return 1
  /usr/bin/sort -u -o "$output_file" "$output_file"
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
  BACKUP_VOLUME_UUID="$created_uuid"
  return 0
}

create_apfs_backup_volume() {
  local container="$1"
  local before_file="$2"
  local after_file candidate_uuid detect_status admin_status=0

  CREATED_APFS_VOLUME_UUID=""
  if "$DISKUTIL_BIN" apfs addVolume "$container" APFS "$BACKUP_VOLUME_NAME"; then
    return 0
  fi

  # diskutil can create a volume successfully and still report a later mount
  # failure. Confirm the set difference before ever attempting a second add.
  for _ in 1 2 3; do
    after_file="$(mktemp "${TMPDIR:-/tmp}/gdrive-apfs-after.XXXXXX")" ||
      return 1
    if ! capture_named_apfs_volume_uuids "$container" "$after_file"; then
      cleanup_temp_file "$after_file"
      log "FEHLER: APFS-Volumes konnten nach dem fehlgeschlagenen Anlegen nicht sicher verglichen werden."
      return 1
    fi
    detect_status=0
    candidate_uuid="$(new_apfs_volume_uuid_since "$before_file" "$after_file")" ||
      detect_status=$?
    cleanup_temp_file "$after_file"
    case "$detect_status" in
      0)
        CREATED_APFS_VOLUME_UUID="$candidate_uuid"
        return 0
        ;;
      1) sleep 1 ;;
      *)
        log "FEHLER: Das neu angelegte APFS-Volume ist nicht eindeutig."
        return 1
        ;;
    esac
  done

  log "APFS-Volume konnte ohne Adminrechte nicht angelegt werden; frage nach Administratorrechten."
  "$OSASCRIPT_BIN" - "$container" "$BACKUP_VOLUME_NAME" <<'OSA' || admin_status=$?
on run argv
  set containerRef to item 1 of argv
  set volumeName to item 2 of argv
  set cmd to "/usr/sbin/diskutil apfs addVolume " & quoted form of containerRef & " APFS " & quoted form of volumeName
  do shell script cmd with administrator privileges
end run
OSA
  if [[ "$admin_status" != "0" ]]; then
    # diskutil can create the APFS volume and still report a later mount error.
    # Let the caller compare UUID sets before deciding whether creation failed.
    log "WARNUNG: Der privilegierte APFS-Aufruf meldete Status $admin_status; pruefe die Volume-UUIDs vor einem Abbruch."
  fi
  return 0
}

ensure_backup_volume() {
  if [[ -d "$VOLUME" ]]; then
    return 0
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

  local candidate source_mount container source_name
  local before_file after_file candidate_uuid detect_status resolve_status
  candidate="$(find_setup_candidate || true)"
  if [[ -z "$candidate" ]]; then
    log "Kein geeignetes externes APFS-Volume fuer die Einrichtung gefunden."
    return 1
  fi

  IFS=$'\t' read -r source_mount container source_name <<<"$candidate"
  if ! confirm_prompt "$(t create_volume)" "${source_name} -> ${BACKUP_VOLUME_NAME}" "$(t create_volume_action)"; then
    log "$(t log_setup_skipped)"
    return 1
  fi

  log "Lege APFS-Volume '$BACKUP_VOLUME_NAME' im Container $container an (Ausgangsvolume: $source_mount)."
  before_file="$(mktemp "${TMPDIR:-/tmp}/gdrive-apfs-before.XXXXXX")" ||
    return 1
  if ! capture_named_apfs_volume_uuids "$container" "$before_file"; then
    cleanup_temp_file "$before_file"
    log "FEHLER: Vorhandene APFS-Volumes konnten nicht sicher erfasst werden."
    return 1
  fi
  if ! create_apfs_backup_volume "$container" "$before_file"; then
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
        BACKUP_VOLUME_UUID="$candidate_uuid"
        resolve_status=0
        resolve_configured_apfs_volume || resolve_status=$?
        if [[ "$resolve_status" == "0" ]]; then
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

mount_nas_url() {
  [[ -n "$NAS_URL" ]] || return 1

  log "NAS-Freigabe ist noch nicht gemountet; versuche zu mounten: $NAS_URL"
  if command -v osascript >/dev/null 2>&1; then
    /usr/bin/osascript - "$NAS_URL" <<'OSA'
on run argv
  mount volume (item 1 of argv)
end run
OSA
    return $?
  fi

  /usr/bin/open "$NAS_URL"
}

ensure_nas_destination() {
  if [[ -z "$NAS_MOUNT" ]]; then
    if [[ -n "$NAS_URL" ]]; then
      log "NAS-URL ist konfiguriert, aber keine gemountete Freigabe wurde gefunden. Oeffne die NAS-URL im Finder oder waehle den Mountpunkt in der Setup-App."
    else
      log "FEHLER: NAS-Ziel ist nicht konfiguriert. Setze GDRIVE_BACKUP_NAS_MOUNT oder GDRIVE_BACKUP_NAS_URL."
    fi
    return 1
  fi

  if ! nas_mount_is_verified && [[ -n "$NAS_URL" ]]; then
    if [[ "$DRY_RUN" == "1" ]]; then
      log "DRY-RUN: NAS-Freigabe wuerde bei Bedarf gemountet: $NAS_URL"
      return 1
    else
      mount_nas_url || log "WARNUNG: NAS-Freigabe konnte nicht automatisch gemountet werden."
    fi
  fi

  if [[ -n "$NAS_URL" ]]; then
    local waited=0
    while ! nas_mount_is_verified && [[ "$waited" -lt 30 ]]; do
      sleep 1
      waited=$((waited + 1))
    done
  fi

  if ! nas_mount_is_verified; then
    log "NAS-Ziel ist kein verifiziertes Netzwerklaufwerk: $NAS_MOUNT"
    return 1
  fi

  if [[ "$DRY_RUN" == "0" && ! -w "$NAS_MOUNT" ]]; then
    log "FEHLER: NAS-Mount ist nicht beschreibbar: $NAS_MOUNT"
    return 1
  fi

  log "NAS-Ziel bereit: mount=$NAS_MOUNT ziel=$DEST_ROOT"
  return 0
}

nas_mount_is_verified() {
  local line mount_path filesystem

  [[ -d "$NAS_MOUNT" && ! -L "$NAS_MOUNT" && -x "$MOUNT_BIN" ]] || return 1
  while IFS= read -r line; do
    [[ "$line" == *" on "* && "$line" == *" ("* ]] || continue
    mount_path="${line#* on }"
    mount_path="${mount_path% (*}"
    [[ "$mount_path" == "$NAS_MOUNT" ]] || continue
    filesystem="${line##* (}"
    filesystem="${filesystem%%,*}"
    case "$filesystem" in
      smbfs|afpfs|nfs) return 0 ;;
    esac
  done < <("$MOUNT_BIN" 2>/dev/null)
  return 1
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
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --run) DRY_RUN=0 ;;
    --setup) SETUP_UI=1 ;;
    *)
      log "Unbekannter Parameter: $arg"
      exit 64
      ;;
  esac
done

RUN_STARTED_AT="$(date +%s 2>/dev/null || printf '0')"
write_run_state "running"
trap on_exit EXIT
trap 'cancel_run 129 HUP' HUP
trap 'cancel_run 130 INT' INT
trap 'cancel_run 143 TERM' TERM

case "$AUTOMATIC_BACKUPS_PAUSED" in
  0|1) ;;
  *)
    log "FEHLER: GDRIVE_BACKUP_PAUSED muss 0 oder 1 sein."
    exit 64
    ;;
esac
if [[ "$AUTOMATIC_BACKUPS_PAUSED" == "1" && "$BACKUP_TRIGGER" != "manual" ]]; then
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

resolve_status=0
resolve_configured_apfs_volume || resolve_status=$?
if [[ "$resolve_status" != "0" ]]; then
  exit "$resolve_status"
fi
log "Start: remote=${REMOTE}: dry_run=$DRY_RUN target=$BACKUP_TARGET mount=$VOLUME dest=$DEST_ROOT"
if [[ "$BACKUP_TARGET" == "invalid" ]]; then
  log "FEHLER: Ungueltiger Zieltyp '$REQUESTED_BACKUP_TARGET'. Erlaubt sind 'apfs' und 'nas'."
  exit 64
fi
sleep "$MOUNT_SETTLE_SECONDS"

for cmd in rclone flock jq diskutil plutil; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    log "FEHLER: '$cmd' nicht gefunden."
    exit 127
  fi
done

exec 9>"$LOCK"
if ! flock -n 9; then
  log "Backup laeuft bereits; ueberspringe."
  RUN_OUTCOME="skipped"
  RUN_STATE_REASON="already_running"
  exit 0
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
  [[ "$BACKUP_TARGET" == "nas" ]] || return 0

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
    log "FEHLER: Das ID-Archiv verlaesst das UUID-gebundene APFS-Backup-Volume."
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
        if [[ "$DRY_RUN" == "0" ]]; then
          if ! validate_collision_archive_write_boundary \
              "$archive_root" "$groups_root" "$objects_root" \
              "$manifest_path" "$object_directory"; then
            cleanup_temp_file "$validated_json" "$objects_tsv" "$manifest_objects"
            return 1
          fi
          if ! mkdir -p "$object_directory"; then
            cleanup_temp_file "$validated_json" "$objects_tsv" "$manifest_objects"
            RUN_STATE_REASON="destination_permission_denied"
            return 1
          fi
          if ! validate_collision_archive_write_boundary \
              "$archive_root" "$groups_root" "$objects_root" \
              "$manifest_path" "$object_directory"; then
            cleanup_temp_file "$validated_json" "$objects_tsv" "$manifest_objects"
            return 1
          fi
        fi
        object_destination="$object_directory/root"
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
            [[ "$(/usr/bin/stat -f '%z' "$archived_file" 2>/dev/null || printf x)" == \
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
  write_progress "$label" "0" "$(t progress_preparing)" "$phase"
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
