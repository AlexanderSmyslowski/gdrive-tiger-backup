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

CONFIG_FILE="${GDRIVE_BACKUP_CONFIG:-$HOME/.config/gdrive-tiger-backup/config}"
if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
fi

BACKUP_TRIGGER="${GDRIVE_BACKUP_TRIGGER:-manual}"
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
CONFIRM_BACKUP="${GDRIVE_BACKUP_CONFIRM:-1}"
AUTO_CREATE_VOLUME="${GDRIVE_BACKUP_AUTO_CREATE_VOLUME:-1}"
BACKUP_LANG="${GDRIVE_BACKUP_LANG:-auto}"
VERSIONING="${GDRIVE_BACKUP_VERSIONING-1}"
VERSIONS_SUBDIR="${GDRIVE_BACKUP_VERSIONS_SUBDIR-.gdrive-versions}"
RETENTION="${GDRIVE_BACKUP_RETENTION-1}"
RETENTION_TRASH_BIN="${GDRIVE_BACKUP_RETENTION_TRASH_BIN-}"
RETENTION_APP_TRASH_BIN="${GDRIVE_BACKUP_APP_TRASH_BIN-${ANIMATION_APP%/}/Contents/MacOS/GDriveBackupTiger}"
ENCRYPTION="$(lowercase "${GDRIVE_BACKUP_ENCRYPTION-none}")"
DISKUTIL_BIN="${GDRIVE_BACKUP_DISKUTIL-/usr/sbin/diskutil}"
ENCRYPTED_VOLUME_REAL=""
ENCRYPTED_VOLUME_DEVICE=""
ENCRYPTED_VOLUME_UUID=""
ENCRYPTED_VOLUME_IDENTIFIER=""
VERSION_RUN_ID=""
TARGET_APPROVED=0
COPY_INDEX=0
COPY_TOTAL=0

mkdir -p "$HOME/Library/Logs"
exec >>"$LOG" 2>&1

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S%z')" "$*"
}

cleanup_temp_file() {
  local path
  for path in "$@"; do
    [[ -n "$path" && -e "$path" ]] || continue
    # Cleanup stays recoverable; older systems without trash intentionally keep the temp file.
    if [[ ! -x /usr/bin/trash ]]; then
      log "WARNUNG: Temporaere Datei bleibt erhalten, weil /usr/bin/trash fehlt: $path"
      continue
    fi
    if ! /usr/bin/trash "$path" >/dev/null 2>&1; then
      log "WARNUNG: Temporaere Datei konnte nicht in den Papierkorb verschoben werden: $path"
    fi
  done
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
    *)
      log "FEHLER: GDRIVE_BACKUP_ENCRYPTION muss 'none' oder 'apfs' sein."
      return 1
      ;;
  esac
}

version_backup_dir_for() {
  local destination="$1"
  local relative_destination="${destination#"$DEST_ROOT"/}"

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
  if ! rclone copy "$source" "$keeper" "${merge_options[@]}"; then
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

  if [[ "$DRY_RUN" == "1" ]]; then
    log "DRY-RUN Aufbewahrungskandidat: $name ($reason)"
    return 0
  fi

  if trash_retention_path "$path"; then
    log "Aufbewahrung: $name in den Papierkorb verschoben ($reason)."
    return 0
  fi
  if [[ -n "$RETENTION_TRASH_BIN" || -x /usr/bin/trash || -x "$RETENTION_APP_TRASH_BIN" ]]; then
    log "WARNUNG: Papierkorb fehlgeschlagen; verwende lokale Quarantaene fuer $name."
  fi

  if ! path_is_on_encrypted_volume "$quarantine" ||
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
  if ! /bin/mv "$path" "$quarantine_target"; then
    log "FEHLER: Aufbewahrungskandidat konnte nicht in die Quarantaene verschoben werden: $name"
    return 1
  fi

  log "Aufbewahrung: $name nach .retention-trash verschoben ($reason)."
}

trash_retention_path() {
  local path="$1"

  if [[ -n "$RETENTION_TRASH_BIN" ]]; then
    [[ -x "$RETENTION_TRASH_BIN" ]] || return 1
    "$RETENTION_TRASH_BIN" "$path" >/dev/null 2>&1
    return
  fi
  if [[ -x /usr/bin/trash ]]; then
    /usr/bin/trash "$path" >/dev/null 2>&1
    return
  fi
  if [[ -x "$RETENTION_APP_TRASH_BIN" ]]; then
    "$RETENTION_APP_TRASH_BIN" --trash "$path" >/dev/null 2>&1
    return
  fi
  return 1
}

retry_retention_quarantine() {
  local versions_root="$1"
  local quarantine="$versions_root/.retention-trash"
  local path name remaining=0 moved=0

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
    elif trash_retention_path "$path"; then
      log "Aufbewahrung: Quarantaene nachtraeglich in den Papierkorb verschoben: $name"
      moved=$((moved + 1))
    else
      remaining=$((remaining + 1))
    fi
  done

  if (( moved > 0 || remaining > 0 )); then
    log "Aufbewahrung: Quarantaene nachgeprueft, papierkorb=$moved verbleibend=$remaining"
  fi
}

prune_version_history() {
  local versions_root="${DEST_ROOT%/}/$VERSIONS_SUBDIR"
  local now_epoch path name timestamp epoch age tier bucket day
  local calendar_value normalized_calendar timezone_hours timezone_minutes
  local entry_count=0 daily_count=0 weekly_count=0
  local recent_count=0 unknown_count=0 future_count=0 candidate_count=0 prune_errors=0
  local index keeper_index found
  local -a entry_paths entry_tiers entry_buckets entry_epochs entry_processed
  local -a daily_buckets daily_keeper_epochs daily_keeper_paths
  local -a weekly_buckets weekly_keeper_epochs weekly_keeper_paths

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

  retry_retention_quarantine "$versions_root"

  if ! validate_encrypted_destination_tree "$versions_root"; then
    log "FEHLER: Versionsbaum enthaelt einen unsicheren Link oder Mount."
    return 1
  fi

  now_epoch="$(date '+%s')"
  if [[ ! "$now_epoch" =~ ^[0-9]+$ ]]; then
    log "FEHLER: Aktuelle Zeit fuer die Aufbewahrung konnte nicht ermittelt werden."
    return 1
  fi

  for path in "$versions_root"/* "$versions_root"/.[!.]* "$versions_root"/..?*; do
    [[ -d "$path" ]] || continue
    name="${path##*/}"
    [[ "$name" != ".retention-trash" ]] || continue
    if [[ -L "$path" ]]; then
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

  local line status
  "$@" 2>&1 | while IFS= read -r line; do
    printf '%s\n' "$line"
    update_progress_from_rclone_line "$label" "$phase" "$line"
  done
  status=${PIPESTATUS[0]}
  return "$status"
}

start_animation() {
  if [[ "$DRY_RUN" == "1" || "${BACKUP_DISABLE_ANIMATION:-0}" == "1" ]]; then
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

  if /usr/bin/open -n "$ANIMATION_APP" --args "$ANIMATION_SENTINEL" "$PROGRESS_FILE" >/dev/null 2>&1; then
    log "Backup-Animation gestartet."
  else
    log "WARNUNG: Backup-Animation konnte nicht gestartet werden."
    cleanup_temp_file "$ANIMATION_SENTINEL"
    ANIMATION_SENTINEL=""
    cleanup_temp_file "$PROGRESS_FILE"
    PROGRESS_FILE=""
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
  stop_animation
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

    if /usr/bin/open -W -n "$ANIMATION_APP" --args --confirm "$title" "$detail" "$primary_button" "$secondary_button" "$response" >/dev/null 2>&1; then
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

  for mount in /Volumes/*; do
    [[ -d "$mount" ]] || continue
    [[ "$mount" != "$VOLUME" ]] || continue
    [[ "$(basename "$mount")" != "$BACKUP_VOLUME_NAME" ]] || continue

    plist="$(mktemp "${TMPDIR:-/tmp}/gdrive-volume-info.XXXXXX")" || continue
    if ! run_with_timeout 6 /usr/sbin/diskutil info -plist "$mount" >"$plist"; then
      cleanup_temp_file "$plist"
      continue
    fi

    fs="$(plist_value "$plist" FilesystemType)"
    external="$(plist_value "$plist" RemovableMediaOrExternalDevice)"
    container="$(plist_value "$plist" APFSContainerReference)"
    name="$(plist_value "$plist" VolumeName)"
    system_image="$(plist_value "$plist" SystemImage)"
    writable_media="$(plist_value "$plist" WritableMedia)"
    cleanup_temp_file "$plist"

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

persist_volume_config() {
  mkdir -p "$(dirname "$CONFIG_FILE")"
  touch "$CONFIG_FILE"
  /bin/chmod 600 "$CONFIG_FILE"

  if ! grep -q '^GDRIVE_BACKUP_TARGET=' "$CONFIG_FILE"; then
    printf 'GDRIVE_BACKUP_TARGET=apfs\n' >>"$CONFIG_FILE"
  fi
  if ! grep -q '^GDRIVE_BACKUP_VOLUME=' "$CONFIG_FILE"; then
    LC_ALL=C printf 'GDRIVE_BACKUP_VOLUME=%q\n' "$VOLUME" >>"$CONFIG_FILE"
  fi
  if ! grep -q '^GDRIVE_BACKUP_VOLUME_NAME=' "$CONFIG_FILE"; then
    LC_ALL=C printf 'GDRIVE_BACKUP_VOLUME_NAME=%q\n' "$BACKUP_VOLUME_NAME" >>"$CONFIG_FILE"
  fi
  if ! grep -q '^GDRIVE_BACKUP_AUTO_CREATE_VOLUME=' "$CONFIG_FILE"; then
    printf 'GDRIVE_BACKUP_AUTO_CREATE_VOLUME=1\n' >>"$CONFIG_FILE"
  fi
}

create_apfs_backup_volume() {
  local container="$1"

  if /usr/sbin/diskutil apfs addVolume "$container" APFS "$BACKUP_VOLUME_NAME"; then
    return 0
  fi

  log "APFS-Volume konnte ohne Adminrechte nicht angelegt werden; frage nach Administratorrechten."
  /usr/bin/osascript - "$container" "$BACKUP_VOLUME_NAME" <<'OSA'
on run argv
  set containerRef to item 1 of argv
  set volumeName to item 2 of argv
  set cmd to "/usr/sbin/diskutil apfs addVolume " & quoted form of containerRef & " APFS " & quoted form of volumeName
  do shell script cmd with administrator privileges
end run
OSA
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
  if ! create_apfs_backup_volume "$container"; then
    log "FEHLER: APFS-Volume konnte nicht angelegt werden."
    return 1
  fi

  VOLUME="/Volumes/$BACKUP_VOLUME_NAME"
  if [[ -z "${GDRIVE_BACKUP_DEST_ROOT:-}" ]]; then
    DEST_ROOT="$VOLUME"
  fi

  for _ in {1..30}; do
    if [[ -d "$VOLUME" ]]; then
      TARGET_APPROVED=1
      persist_volume_config
      log "Backup-Volume bereit: $VOLUME"
      return 0
    fi
    sleep 1
  done

  log "FEHLER: Neues APFS-Volume ist nicht unter $VOLUME erschienen."
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

  if [[ ! -d "$NAS_MOUNT" && -n "$NAS_URL" ]]; then
    if [[ "$DRY_RUN" == "1" ]]; then
      log "DRY-RUN: NAS-Freigabe wuerde bei Bedarf gemountet: $NAS_URL"
      return 1
    else
      mount_nas_url || log "WARNUNG: NAS-Freigabe konnte nicht automatisch gemountet werden."
    fi
  fi

  local waited=0
  while [[ ! -d "$NAS_MOUNT" && "$waited" -lt 30 ]]; do
    sleep 1
    waited=$((waited + 1))
  done

  if [[ ! -d "$NAS_MOUNT" ]]; then
    log "NAS-Ziel ist nicht gemountet: $NAS_MOUNT"
    return 1
  fi

  if [[ "$DRY_RUN" == "0" && ! -w "$NAS_MOUNT" ]]; then
    log "FEHLER: NAS-Mount ist nicht beschreibbar: $NAS_MOUNT"
    return 1
  fi

  log "NAS-Ziel bereit: mount=$NAS_MOUNT ziel=$DEST_ROOT"
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
  exit 0
fi

if ! ensure_backup_target; then
  if [[ "$BACKUP_TRIGGER" == "mount" ]]; then
    exit 0
  fi
  log "FEHLER: Das konfigurierte Backup-Ziel ist nicht verfuegbar."
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
  exit 0
fi

if [[ "$DRY_RUN" == "0" ]]; then
  if ! mkdir -p "$DEST_ROOT"; then
    log "FEHLER: Zielordner kann nicht angelegt werden: $DEST_ROOT"
    exit 73
  fi
fi

if ! validate_all_encrypted_active_trees; then
  log "FEHLER: Der vorhandene Zielbaum erfuellt die Verschluesselungsrichtlinie nicht."
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
  log "Dateiversionierung aktiv: ${DEST_ROOT%/}/$VERSIONS_SUBDIR/$VERSION_RUN_ID"
else
  log "Dateiversionierung ist deaktiviert."
fi

start_animation
trap cleanup EXIT
trap 'cleanup; exit 129' HUP
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

RCLONE_OPTS=(
  --drive-export-formats "docx,xlsx,pptx"
  --create-empty-src-dirs
  --stats 10s
  --log-level INFO
  --retries 3
  --low-level-retries 10
)

if [[ "$ENCRYPTION" == "apfs" ]]; then
  RCLONE_OPTS+=(--one-file-system)
fi

if [[ "$DRY_RUN" == "1" ]]; then
  RCLONE_OPTS+=(--dry-run)
  log "DRY-RUN aktiv: Es werden keine Dateien kopiert, geloescht oder veraendert."
fi

errors=0

copy_one() {
  local label="$1"
  local source="$2"
  local dest="$3"
  shift 3
  local phase=""
  local backup_dir=""
  local copy_status=0

  COPY_INDEX=$((COPY_INDEX + 1))
  if (( COPY_TOTAL > 0 )); then
    phase="${COPY_INDEX}/${COPY_TOTAL}"
  fi

  if ! validate_encrypted_apfs_destination; then
    log "FEHLER: Verschluesseltes Volume konnte vor '$label' nicht erneut bestaetigt werden."
    errors=$((errors + 1))
    return
  fi
  if ! path_is_on_encrypted_volume "$dest"; then
    log "FEHLER: Kopierziel liegt nicht sicher auf dem verschluesselten Volume: $dest"
    errors=$((errors + 1))
    return
  fi

  if [[ "$DRY_RUN" == "0" ]]; then
    mkdir -p "$dest" || {
      log "FEHLER: Zielordner kann nicht angelegt werden: $dest"
      errors=$((errors + 1))
      return
    }
  fi

  if ! validate_encrypted_destination_tree "$dest"; then
    log "FEHLER: Kopierziel enthaelt einen unsicheren Link oder Mount: $dest"
    errors=$((errors + 1))
    return
  fi

  if [[ "$VERSIONING" == "1" ]]; then
    if ! backup_dir="$(version_backup_dir_for "$dest")"; then
      log "FEHLER: Versionsziel konnte fuer '$dest' nicht sicher bestimmt werden."
      errors=$((errors + 1))
      return
    fi
    if ! path_is_on_encrypted_volume "$backup_dir"; then
      log "FEHLER: Versionsziel liegt nicht sicher auf dem verschluesselten Volume: $backup_dir"
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

  copy_one "My Drive" "${REMOTE}:" "$DEST_ROOT/My Drive"
  copy_one "Shared with me" "${REMOTE}:" "$DEST_ROOT/Shared with me" --drive-shared-with-me

  while IFS=$'\t' read -r drive_id drive_name; do
    [[ -n "$drive_id" ]] || continue
    safe="$(safe_name "$drive_name")"

    copy_one "Shared Drive: $drive_name" "${REMOTE}:" \
      "$DEST_ROOT/Shared Drives/${safe} (${drive_id})" \
      --drive-team-drive "$drive_id"
  done < <(jq -r '.[] | [.id, .name] | @tsv' "$drives_json")
else
  log "FEHLER: Shared Drives konnten nicht gelesen werden."
  errors=$((errors + 1))

  COPY_TOTAL=2
  copy_one "My Drive" "${REMOTE}:" "$DEST_ROOT/My Drive"
  copy_one "Shared with me" "${REMOTE}:" "$DEST_ROOT/Shared with me" --drive-shared-with-me
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

log "Fertig ohne Fehler."
