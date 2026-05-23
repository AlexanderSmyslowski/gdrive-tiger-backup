#!/bin/bash
set -uo pipefail

PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export PATH

CONFIG_FILE="${GDRIVE_BACKUP_CONFIG:-$HOME/.config/gdrive-tiger-backup/config}"
if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
fi

BACKUP_VOLUME_NAME="${GDRIVE_BACKUP_VOLUME_NAME:-GoogleDrive-Backup}"
VOLUME="${GDRIVE_BACKUP_VOLUME:-/Volumes/$BACKUP_VOLUME_NAME}"
DEST_ROOT="${GDRIVE_BACKUP_DEST_ROOT:-$VOLUME}"
REMOTE="${RCLONE_REMOTE:-gdrive}"
REMOTE="${REMOTE%:}"

LOG="${GDRIVE_BACKUP_LOG:-$HOME/Library/Logs/gdrive-backup.log}"
LOCK="${GDRIVE_BACKUP_LOCK:-$HOME/Library/Logs/gdrive-backup.lock}"
MOUNT_SETTLE_SECONDS="${MOUNT_SETTLE_SECONDS:-5}"
ANIMATION_APP="${GDRIVE_BACKUP_ANIMATION_APP:-$HOME/Applications/GDrive Backup Tiger.app}"
ANIMATION_SENTINEL=""
CONFIRM_BACKUP="${GDRIVE_BACKUP_CONFIRM:-1}"
AUTO_CREATE_VOLUME="${GDRIVE_BACKUP_AUTO_CREATE_VOLUME:-1}"
BACKUP_LANG="${GDRIVE_BACKUP_LANG:-auto}"
TARGET_APPROVED=0

mkdir -p "$HOME/Library/Logs"
exec >>"$LOG" 2>&1

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S%z')" "$*"
}

safe_name() {
  local value="$1"
  value="${value//\//_}"
  value="${value//:/_}"
  value="${value//$'\n'/_}"
  printf '%s' "$value"
}

detect_language() {
  local value="${1:-auto}"
  value="${value,,}"

  case "$value" in
    de*) printf 'de' ;;
    en*) printf 'en' ;;
    auto|"")
      local locale="${LANG:-}"
      if command -v defaults >/dev/null 2>&1; then
        locale="$(defaults read -g AppleLocale 2>/dev/null || printf '%s' "$locale")"
      fi
      locale="${locale,,}"
      if [[ "$locale" == de* ]]; then
        printf 'de'
      else
        printf 'en'
      fi
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
    de:create_volume) printf 'Backup-Volume anlegen?' ;;
    de:create_volume_action) printf 'Volume anlegen' ;;
    de:log_confirmed) printf 'Backup durch Benutzer bestaetigt.' ;;
    de:log_skipped) printf 'Backup nicht bestaetigt; ueberspringe.' ;;
    de:log_setup_skipped) printf 'Volume-Einrichtung nicht bestaetigt; ueberspringe.' ;;
    en:not_now) printf 'Not now' ;;
    en:start_backup) printf 'Start backup' ;;
    en:use_volume) printf 'Use this volume?' ;;
    en:create_volume) printf 'Create backup volume?' ;;
    en:create_volume_action) printf 'Create volume' ;;
    en:log_confirmed) printf 'Backup confirmed by user.' ;;
    en:log_skipped) printf 'Backup was not confirmed; skipping.' ;;
    en:log_setup_skipped) printf 'Volume setup was not confirmed; skipping.' ;;
    *) printf '%s' "$key" ;;
  esac
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

  if /usr/bin/open -n "$ANIMATION_APP" --args "$ANIMATION_SENTINEL" >/dev/null 2>&1; then
    log "Backup-Animation gestartet."
  else
    log "WARNUNG: Backup-Animation konnte nicht gestartet werden."
    rm -f "$ANIMATION_SENTINEL"
    ANIMATION_SENTINEL=""
  fi
}

stop_animation() {
  if [[ -n "${ANIMATION_SENTINEL:-}" ]]; then
    rm -f "$ANIMATION_SENTINEL"
    ANIMATION_SENTINEL=""
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
  ) &
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
    rm -f "$response"

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

  if confirm_prompt "$(t use_volume)" "$VOLUME" "$(t start_backup)"; then
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
      rm -f "$plist"
      continue
    fi

    fs="$(plist_value "$plist" FilesystemType)"
    external="$(plist_value "$plist" RemovableMediaOrExternalDevice)"
    container="$(plist_value "$plist" APFSContainerReference)"
    name="$(plist_value "$plist" VolumeName)"
    system_image="$(plist_value "$plist" SystemImage)"
    writable_media="$(plist_value "$plist" WritableMedia)"
    rm -f "$plist"

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

  if ! grep -q '^GDRIVE_BACKUP_VOLUME=' "$CONFIG_FILE"; then
    printf 'GDRIVE_BACKUP_VOLUME=%q\n' "$VOLUME" >>"$CONFIG_FILE"
  fi
  if ! grep -q '^GDRIVE_BACKUP_VOLUME_NAME=' "$CONFIG_FILE"; then
    printf 'GDRIVE_BACKUP_VOLUME_NAME=%q\n' "$BACKUP_VOLUME_NAME" >>"$CONFIG_FILE"
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

DRY_RUN=1
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --run) DRY_RUN=0 ;;
    *)
      log "Unbekannter Parameter: $arg"
      exit 64
      ;;
  esac
done

log "Start: remote=${REMOTE}: dry_run=$DRY_RUN volume=$VOLUME"
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

if ! ensure_backup_volume; then
  exit 0
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

start_animation
trap cleanup EXIT
trap 'cleanup; exit 129' HUP
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

RCLONE_OPTS=(
  --drive-export-formats docx,xlsx,pptx
  --create-empty-src-dirs
  --stats 60s
  --log-level INFO
  --retries 3
  --low-level-retries 10
)

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

  if [[ "$DRY_RUN" == "0" ]]; then
    mkdir -p "$dest" || {
      log "FEHLER: Zielordner kann nicht angelegt werden: $dest"
      errors=$((errors + 1))
      return
    }
  fi

  log "Kopiere $label -> $dest"
  if rclone copy "$source" "$dest" "$@" "${RCLONE_OPTS[@]}"; then
    log "OK: $label"
  else
    log "FEHLER: $label"
    errors=$((errors + 1))
  fi
}

copy_one "My Drive" "${REMOTE}:" "$DEST_ROOT/My Drive"
copy_one "Shared with me" "${REMOTE}:" "$DEST_ROOT/Shared with me" --drive-shared-with-me

drives_json="$(mktemp "${TMPDIR:-/tmp}/gdrive-shared-drives.XXXXXX")"
if rclone backend --json drives "${REMOTE}:" >"$drives_json"; then
  drive_count="$(jq 'length' "$drives_json" 2>/dev/null || printf '0')"
  log "$drive_count Shared Drive(s) gefunden."

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
fi
rm -f "$drives_json"

if (( errors > 0 )); then
  log "Fertig mit $errors Fehler(n)."
  exit 1
fi

log "Fertig ohne Fehler."
