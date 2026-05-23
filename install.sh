#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BACKUP_VOLUME="${BACKUP_VOLUME:-/Volumes/GoogleDrive-Backup}"
RCLONE_REMOTE="${RCLONE_REMOTE:-gdrive}"
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

for cmd in clang codesign install launchctl; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    exit 127
  fi
done

mkdir -p "$CONFIG_DIR" "$HOME/Applications" "$APP_CONTENTS/MacOS" "$HOME/Library/LaunchAgents"

if [[ ! -f "$CONFIG_FILE" ]]; then
  {
    printf 'GDRIVE_BACKUP_VOLUME=%q\n' "$BACKUP_VOLUME"
    printf 'RCLONE_REMOTE=%q\n' "$RCLONE_REMOTE"
  } >"$CONFIG_FILE"
fi

install -m 644 "$ROOT/macos/GDriveBackupTiger/Info.plist" "$APP_CONTENTS/Info.plist"
clang -fobjc-arc -framework Cocoa "$ROOT/macos/GDriveBackupTiger/main.m" \
  -o "$APP_CONTENTS/MacOS/GDriveBackupTiger"
codesign --force --deep --sign - "$APP_DIR" >/dev/null

sudo install -m 755 "$ROOT/bin/backup-google-drive.sh" /usr/local/bin/backup-google-drive.sh
install -m 644 "$AGENT_SRC" "$AGENT_DST"

launchctl bootout "gui/$(id -u)" "$AGENT_DST" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$AGENT_DST"
launchctl enable "gui/$(id -u)/com.commcats.gdrivebackup"

echo "Installed gdrive-tiger-backup."
echo "Config: $CONFIG_FILE"
echo "Run a dry-run with: /usr/local/bin/backup-google-drive.sh --dry-run"
