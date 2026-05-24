#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
lowercase() {
  printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]'
}

BACKUP_VOLUME="${BACKUP_VOLUME:-/Volumes/GoogleDrive-Backup}"
BACKUP_VOLUME_NAME="${BACKUP_VOLUME_NAME:-$(basename "$BACKUP_VOLUME")}"
BACKUP_TARGET="${GDRIVE_BACKUP_TARGET:-${BACKUP_TARGET:-apfs}}"
BACKUP_TARGET="$(lowercase "$BACKUP_TARGET")"
case "$BACKUP_TARGET" in
  apfs|volume|disk) BACKUP_TARGET="apfs" ;;
  nas|network|smb|afp|nfs) BACKUP_TARGET="nas" ;;
  *) echo "Invalid BACKUP_TARGET/GDRIVE_BACKUP_TARGET: $BACKUP_TARGET" >&2; exit 64 ;;
esac
NAS_MOUNT="${GDRIVE_BACKUP_NAS_MOUNT:-${NAS_MOUNT:-}}"
NAS_URL="${GDRIVE_BACKUP_NAS_URL:-${NAS_URL:-}}"
NAS_SUBDIR="${GDRIVE_BACKUP_NAS_SUBDIR:-${NAS_SUBDIR:-GoogleDrive-Backup}}"
RCLONE_REMOTE="${RCLONE_REMOTE:-gdrive}"
INSTALL_LANG="${GDRIVE_BACKUP_LANG:-${INSTALL_LANG:-auto}}"
CONFIG_DIR="$HOME/.config/gdrive-tiger-backup"
CONFIG_FILE="$CONFIG_DIR/config"
APP_DIR="${APP_DIR:-/Applications/GDrive Backup Tiger.app}"
APP_CONTENTS="$APP_DIR/Contents"
AGENT_SRC="$ROOT/launchd/com.commcats.gdrivebackup.plist"
AGENT_DST="$HOME/Library/LaunchAgents/com.commcats.gdrivebackup.plist"

if [[ "${INSTALL_DEPS:-0}" == "1" ]]; then
  if ! command -v brew >/dev/null 2>&1; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi
  brew install rclone flock jq
fi

for cmd in clang codesign iconutil install launchctl; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    exit 127
  fi
done
if [[ ! -x /usr/libexec/PlistBuddy ]]; then
  echo "Missing required command: /usr/libexec/PlistBuddy" >&2
  exit 127
fi

mkdir -p "$CONFIG_DIR" "$APP_CONTENTS/MacOS" "$APP_CONTENTS/Resources" "$HOME/Library/LaunchAgents"

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

language_label() {
  case "$1" in
    de) printf 'Deutsch' ;;
    en) printf 'English' ;;
    fr) printf 'Français' ;;
    es) printf 'Español' ;;
    ja) printf '日本語' ;;
    yue) printf '粵語' ;;
    ko) printf '한국어' ;;
    *) printf 'English' ;;
  esac
}

language_code_from_label() {
  case "$1" in
    Deutsch) printf 'de' ;;
    English) printf 'en' ;;
    Francais|Français) printf 'fr' ;;
    Espanol|Español) printf 'es' ;;
    日本語) printf 'ja' ;;
    粵語) printf 'yue' ;;
    한국어) printf 'ko' ;;
    *) detect_language "$1" ;;
  esac
}

choose_language() {
  local default_lang
  default_lang="$(detect_language "$INSTALL_LANG")"

  if [[ "${GDRIVE_BACKUP_LANG:-}" =~ ^(de|en|fr|es|ja|yue|ko)$ || "${INSTALL_LANG:-}" =~ ^(de|en|fr|es|ja|yue|ko)$ ]]; then
    printf '%s' "$default_lang"
    return
  fi

  if command -v osascript >/dev/null 2>&1; then
    local default_label
    default_label="$(language_label "$default_lang")"
    local answer
    answer="$(/usr/bin/osascript - "$default_label" <<'OSA'
on run argv
  set defaultLabel to item 1 of argv
  set languageOptions to {"Deutsch", "English", "Français", "Español", "日本語", "粵語", "한국어"}
  try
    set picked to choose from list languageOptions with title "Google Drive Backup" with prompt "Choose the language for the backup helper." & return & "Sprache fuer den Backup-Helfer auswaehlen." default items {defaultLabel} OK button name "OK" cancel button name "Cancel"
    if picked is false then return defaultLabel
    return item 1 of picked
  on error
    return defaultLabel
  end try
end run
OSA
)" || answer="$default_label"
    language_code_from_label "$answer"
    return
  fi

  if [[ -t 0 ]]; then
    printf 'Language / Sprache [de/en/fr/es/ja/yue/ko] (%s): ' "$default_lang" >&2
    local answer=""
    read -r answer || true
    answer="${answer:-$default_lang}"
    printf '%s' "$(detect_language "$answer")"
    return
  fi

  printf '%s' "$default_lang"
}

CONFIG_LANG=""
if [[ -f "$CONFIG_FILE" ]] && grep -q '^GDRIVE_BACKUP_LANG=' "$CONFIG_FILE"; then
  CONFIG_LANG="$(grep '^GDRIVE_BACKUP_LANG=' "$CONFIG_FILE" | tail -n 1 | cut -d= -f2-)"
else
  CONFIG_LANG="$(choose_language)"
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
  {
    printf 'GDRIVE_BACKUP_TARGET=%q\n' "$BACKUP_TARGET"
    if [[ "$BACKUP_TARGET" == "nas" ]]; then
      [[ -n "$NAS_MOUNT" ]] && printf 'GDRIVE_BACKUP_NAS_MOUNT=%q\n' "$NAS_MOUNT"
      [[ -n "$NAS_URL" ]] && printf 'GDRIVE_BACKUP_NAS_URL=%q\n' "$NAS_URL"
      printf 'GDRIVE_BACKUP_NAS_SUBDIR=%q\n' "$NAS_SUBDIR"
    else
      printf 'GDRIVE_BACKUP_VOLUME=%q\n' "$BACKUP_VOLUME"
      printf 'GDRIVE_BACKUP_VOLUME_NAME=%q\n' "$BACKUP_VOLUME_NAME"
    fi
    printf 'RCLONE_REMOTE=%q\n' "$RCLONE_REMOTE"
    printf 'GDRIVE_BACKUP_LANG=%q\n' "$CONFIG_LANG"
    printf 'GDRIVE_BACKUP_CONFIRM=1\n'
    printf 'GDRIVE_BACKUP_AUTO_CREATE_VOLUME=1\n'
  } >"$CONFIG_FILE"
elif ! grep -q '^GDRIVE_BACKUP_LANG=' "$CONFIG_FILE"; then
  printf 'GDRIVE_BACKUP_LANG=%q\n' "$CONFIG_LANG" >>"$CONFIG_FILE"
fi
if [[ -f "$CONFIG_FILE" ]] && ! grep -q '^GDRIVE_BACKUP_TARGET=' "$CONFIG_FILE"; then
  printf 'GDRIVE_BACKUP_TARGET=%q\n' "$BACKUP_TARGET" >>"$CONFIG_FILE"
fi
if [[ -f "$CONFIG_FILE" && "$BACKUP_TARGET" == "nas" ]]; then
  if [[ -n "$NAS_MOUNT" ]] && ! grep -q '^GDRIVE_BACKUP_NAS_MOUNT=' "$CONFIG_FILE"; then
    printf 'GDRIVE_BACKUP_NAS_MOUNT=%q\n' "$NAS_MOUNT" >>"$CONFIG_FILE"
  fi
  if [[ -n "$NAS_URL" ]] && ! grep -q '^GDRIVE_BACKUP_NAS_URL=' "$CONFIG_FILE"; then
    printf 'GDRIVE_BACKUP_NAS_URL=%q\n' "$NAS_URL" >>"$CONFIG_FILE"
  fi
  if ! grep -q '^GDRIVE_BACKUP_NAS_SUBDIR=' "$CONFIG_FILE"; then
    printf 'GDRIVE_BACKUP_NAS_SUBDIR=%q\n' "$NAS_SUBDIR" >>"$CONFIG_FILE"
  fi
fi

install -m 644 "$ROOT/macos/GDriveBackupTiger/Info.plist" "$APP_CONTENTS/Info.plist"
clang -fobjc-arc -framework Cocoa "$ROOT/macos/GDriveBackupTiger/main.m" \
  -o "$APP_CONTENTS/MacOS/GDriveBackupTiger"

ICON_WORK="$(mktemp -d "${TMPDIR:-/tmp}/gdrive-tiger-icon.XXXXXX")"
clang -fobjc-arc -framework Cocoa "$ROOT/macos/GDriveBackupTiger/IconGenerator.m" \
  -o "$ICON_WORK/IconGenerator"
"$ICON_WORK/IconGenerator" "$ICON_WORK/AppIcon.iconset"
iconutil -c icns "$ICON_WORK/AppIcon.iconset" -o "$APP_CONTENTS/Resources/AppIcon.icns"
rm -rf "$ICON_WORK"

codesign --force --deep --sign - "$APP_DIR" >/dev/null

sudo install -m 755 "$ROOT/bin/backup-google-drive.sh" /usr/local/bin/backup-google-drive.sh
install -m 644 "$AGENT_SRC" "$AGENT_DST"
/usr/libexec/PlistBuddy -c 'Delete :EnvironmentVariables' "$AGENT_DST" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c 'Add :EnvironmentVariables dict' "$AGENT_DST"
/usr/libexec/PlistBuddy -c "Add :EnvironmentVariables:HOME string $HOME" "$AGENT_DST"
/usr/libexec/PlistBuddy -c 'Add :EnvironmentVariables:PATH string /opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin' "$AGENT_DST"
/usr/libexec/PlistBuddy -c 'Add :EnvironmentVariables:GDRIVE_BACKUP_TRIGGER string mount' "$AGENT_DST"

launchctl bootout "gui/$(id -u)" "$AGENT_DST" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$AGENT_DST"
launchctl enable "gui/$(id -u)/com.commcats.gdrivebackup"

echo "Installed gdrive-tiger-backup."
echo "App: $APP_DIR"
echo "Config: $CONFIG_FILE"
echo "Run a dry-run with: /usr/local/bin/backup-google-drive.sh --dry-run"
