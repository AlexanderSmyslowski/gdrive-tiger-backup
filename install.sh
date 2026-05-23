#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BACKUP_VOLUME="${BACKUP_VOLUME:-/Volumes/GoogleDrive-Backup}"
BACKUP_VOLUME_NAME="${BACKUP_VOLUME_NAME:-$(basename "$BACKUP_VOLUME")}"
RCLONE_REMOTE="${RCLONE_REMOTE:-gdrive}"
INSTALL_LANG="${GDRIVE_BACKUP_LANG:-${INSTALL_LANG:-auto}}"
CONFIG_DIR="$HOME/.config/gdrive-tiger-backup"
CONFIG_FILE="$CONFIG_DIR/config"
APP_DIR="$HOME/Applications/GDrive Backup Tiger.app"
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

mkdir -p "$CONFIG_DIR" "$HOME/Applications" "$APP_CONTENTS/MacOS" "$APP_CONTENTS/Resources" "$HOME/Library/LaunchAgents"

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

choose_language() {
  local default_lang
  default_lang="$(detect_language "$INSTALL_LANG")"

  if [[ "${GDRIVE_BACKUP_LANG:-}" =~ ^(de|en)$ || "${INSTALL_LANG:-}" =~ ^(de|en)$ ]]; then
    printf '%s' "$default_lang"
    return
  fi

  if command -v osascript >/dev/null 2>&1; then
    local default_button="English"
    [[ "$default_lang" == "de" ]] && default_button="Deutsch"
    local answer
    answer="$(/usr/bin/osascript - "$default_button" <<'OSA'
on run argv
  set defaultButton to item 1 of argv
  try
    set answer to display dialog "Choose the language for the backup helper." & return & return & "Sprache fuer den Backup-Helfer auswaehlen." with title "Google Drive Backup" buttons {"Deutsch", "English"} default button defaultButton
    return button returned of answer
  on error
    return defaultButton
  end try
end run
OSA
)" || answer="$default_button"
    if [[ "$answer" == "Deutsch" ]]; then
      printf 'de'
    else
      printf 'en'
    fi
    return
  fi

  if [[ -t 0 ]]; then
    printf 'Language / Sprache [de/en] (%s): ' "$default_lang" >&2
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
    printf 'GDRIVE_BACKUP_VOLUME=%q\n' "$BACKUP_VOLUME"
    printf 'GDRIVE_BACKUP_VOLUME_NAME=%q\n' "$BACKUP_VOLUME_NAME"
    printf 'RCLONE_REMOTE=%q\n' "$RCLONE_REMOTE"
    printf 'GDRIVE_BACKUP_LANG=%q\n' "$CONFIG_LANG"
    printf 'GDRIVE_BACKUP_CONFIRM=1\n'
    printf 'GDRIVE_BACKUP_AUTO_CREATE_VOLUME=1\n'
  } >"$CONFIG_FILE"
elif ! grep -q '^GDRIVE_BACKUP_LANG=' "$CONFIG_FILE"; then
  printf 'GDRIVE_BACKUP_LANG=%q\n' "$CONFIG_LANG" >>"$CONFIG_FILE"
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

launchctl bootout "gui/$(id -u)" "$AGENT_DST" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$AGENT_DST"
launchctl enable "gui/$(id -u)/com.commcats.gdrivebackup"

echo "Installed gdrive-tiger-backup."
echo "Config: $CONFIG_FILE"
echo "Run a dry-run with: /usr/local/bin/backup-google-drive.sh --dry-run"
