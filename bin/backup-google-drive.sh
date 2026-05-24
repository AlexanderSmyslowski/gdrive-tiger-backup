#!/bin/bash
set -uo pipefail

PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
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
  local share
  url="${url%/}"
  share="${url##*/}"

  if [[ -n "$share" && "$share" != "$url" ]]; then
    printf '/Volumes/%s' "$share"
  fi
}

CONFIG_FILE="${GDRIVE_BACKUP_CONFIG:-$HOME/.config/gdrive-tiger-backup/config}"
if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
fi

REQUESTED_BACKUP_TARGET="${GDRIVE_BACKUP_TARGET:-apfs}"
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
  VOLUME="$NAS_MOUNT"
  DEST_ROOT="${GDRIVE_BACKUP_DEST_ROOT:-${NAS_MOUNT%/}/$NAS_SUBDIR}"
else
  VOLUME="${GDRIVE_BACKUP_VOLUME:-/Volumes/$BACKUP_VOLUME_NAME}"
  DEST_ROOT="${GDRIVE_BACKUP_DEST_ROOT:-$VOLUME}"
fi
REMOTE="${RCLONE_REMOTE:-gdrive}"
REMOTE="${REMOTE%:}"

LOG="${GDRIVE_BACKUP_LOG:-$HOME/Library/Logs/gdrive-backup.log}"
LOCK="${GDRIVE_BACKUP_LOCK:-$HOME/Library/Logs/gdrive-backup.lock}"
MOUNT_SETTLE_SECONDS="${MOUNT_SETTLE_SECONDS:-5}"
ANIMATION_APP="${GDRIVE_BACKUP_ANIMATION_APP:-$HOME/Applications/GDrive Backup Tiger.app}"
ANIMATION_SENTINEL=""
PROGRESS_FILE=""
CONFIRM_BACKUP="${GDRIVE_BACKUP_CONFIRM:-1}"
AUTO_CREATE_VOLUME="${GDRIVE_BACKUP_AUTO_CREATE_VOLUME:-1}"
BACKUP_LANG="${GDRIVE_BACKUP_LANG:-auto}"
BACKUP_TRIGGER="${GDRIVE_BACKUP_TRIGGER:-manual}"
NAS_START_ON_MOUNT="${GDRIVE_BACKUP_NAS_START_ON_MOUNT:-0}"
TARGET_APPROVED=0
COPY_INDEX=0
COPY_TOTAL=0

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
    rm -f "$ANIMATION_SENTINEL"
    ANIMATION_SENTINEL=""
    rm -f "$PROGRESS_FILE"
    PROGRESS_FILE=""
  fi
}

stop_animation() {
  if [[ -n "${ANIMATION_SENTINEL:-}" ]]; then
    rm -f "$ANIMATION_SENTINEL"
    ANIMATION_SENTINEL=""
  fi
  if [[ -n "${PROGRESS_FILE:-}" ]]; then
    rm -f "$PROGRESS_FILE"
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

  if ! grep -q '^GDRIVE_BACKUP_TARGET=' "$CONFIG_FILE"; then
    printf 'GDRIVE_BACKUP_TARGET=apfs\n' >>"$CONFIG_FILE"
  fi
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
    log "FEHLER: NAS-Ziel ist nicht konfiguriert. Setze GDRIVE_BACKUP_NAS_MOUNT oder GDRIVE_BACKUP_NAS_URL."
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
if [[ "$BACKUP_TARGET" == "nas" && "$BACKUP_TRIGGER" == "mount" && "$NAS_START_ON_MOUNT" != "1" ]]; then
  log "NAS-Ziel ist konfiguriert; Mount-Trigger ist deaktiviert. Verwende Setup-App, manuellen Start oder Zeitplan."
  exit 0
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
  --stats 10s
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
  local phase=""

  COPY_INDEX=$((COPY_INDEX + 1))
  if (( COPY_TOTAL > 0 )); then
    phase="${COPY_INDEX}/${COPY_TOTAL}"
  fi

  if [[ "$DRY_RUN" == "0" ]]; then
    mkdir -p "$dest" || {
      log "FEHLER: Zielordner kann nicht angelegt werden: $dest"
      errors=$((errors + 1))
      return
    }
  fi

  log "Kopiere $label -> $dest"
  write_progress "$label" "0" "$(t progress_preparing)" "$phase"
  if run_rclone_with_progress "$label" "$phase" rclone copy "$source" "$dest" "$@" "${RCLONE_OPTS[@]}"; then
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
rm -f "$drives_json"

if (( errors > 0 )); then
  log "Fertig mit $errors Fehler(n)."
  exit 1
fi

log "Fertig ohne Fehler."
