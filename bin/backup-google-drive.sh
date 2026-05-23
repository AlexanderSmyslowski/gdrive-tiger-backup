#!/bin/bash
set -uo pipefail

PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export PATH

CONFIG_FILE="${GDRIVE_BACKUP_CONFIG:-$HOME/.config/gdrive-tiger-backup/config}"
if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
fi

VOLUME="${GDRIVE_BACKUP_VOLUME:-/Volumes/GoogleDrive-Backup}"
DEST_ROOT="${GDRIVE_BACKUP_DEST_ROOT:-$VOLUME}"
REMOTE="${RCLONE_REMOTE:-gdrive}"
REMOTE="${REMOTE%:}"

LOG="${GDRIVE_BACKUP_LOG:-$HOME/Library/Logs/gdrive-backup.log}"
LOCK="${GDRIVE_BACKUP_LOCK:-$HOME/Library/Logs/gdrive-backup.lock}"
MOUNT_SETTLE_SECONDS="${MOUNT_SETTLE_SECONDS:-5}"
ANIMATION_APP="${GDRIVE_BACKUP_ANIMATION_APP:-$HOME/Applications/GDrive Backup Tiger.app}"
ANIMATION_SENTINEL=""

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

if [[ ! -d "$VOLUME" ]]; then
  log "Volume nicht vorhanden: $VOLUME"
  exit 0
fi

for cmd in rclone flock jq; do
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

if ! rclone config show "$REMOTE" >/dev/null 2>&1; then
  log "FEHLER: rclone-Remote '${REMOTE}:' ist nicht konfiguriert."
  exit 78
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
