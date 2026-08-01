#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
lowercase() {
  printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]'
}

BACKUP_VOLUME="${BACKUP_VOLUME:-/Volumes/GoogleDrive-Backup}"
BACKUP_VOLUME_NAME="${BACKUP_VOLUME_NAME:-$(basename "$BACKUP_VOLUME")}"
BACKUP_VOLUME_UUID_INPUT_SET=0
if [[ "${GDRIVE_BACKUP_VOLUME_UUID+x}" == "x" ]]; then
  BACKUP_VOLUME_UUID_INPUT_SET=1
  BACKUP_VOLUME_UUID="$GDRIVE_BACKUP_VOLUME_UUID"
elif [[ "${BACKUP_VOLUME_UUID+x}" == "x" ]]; then
  BACKUP_VOLUME_UUID_INPUT_SET=1
else
  BACKUP_VOLUME_UUID=""
fi
if [[ "$BACKUP_VOLUME_UUID_INPUT_SET" == "1" && -z "$BACKUP_VOLUME_UUID" ]]; then
  echo "An explicitly supplied APFS UUID cannot be empty." >&2
  exit 64
fi
BACKUP_TARGET="${GDRIVE_BACKUP_TARGET:-${BACKUP_TARGET:-apfs}}"
BACKUP_TARGET="$(lowercase "$BACKUP_TARGET")"
case "$BACKUP_TARGET" in
  apfs|volume|disk) BACKUP_TARGET="apfs" ;;
  nas|network|smb|afp|nfs) BACKUP_TARGET="nas" ;;
  *) echo "Invalid BACKUP_TARGET/GDRIVE_BACKUP_TARGET: $BACKUP_TARGET" >&2; exit 64 ;;
esac
if [[ -n "$BACKUP_VOLUME_UUID" ]]; then
  if [[ "$BACKUP_TARGET" != "apfs" ]]; then
    echo "GDRIVE_BACKUP_VOLUME_UUID is valid only for an APFS target." >&2
    exit 64
  fi
  if [[ ! "$BACKUP_VOLUME_UUID" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]]; then
    echo "Invalid GDRIVE_BACKUP_VOLUME_UUID: $BACKUP_VOLUME_UUID" >&2
    exit 64
  fi
  BACKUP_VOLUME_UUID="$(printf '%s' "$BACKUP_VOLUME_UUID" | tr '[:lower:]' '[:upper:]')"
fi
NAS_MOUNT="${GDRIVE_BACKUP_NAS_MOUNT:-${NAS_MOUNT:-}}"
NAS_URL="${GDRIVE_BACKUP_NAS_URL:-${NAS_URL:-}}"
NAS_SUBDIR="${GDRIVE_BACKUP_NAS_SUBDIR:-${NAS_SUBDIR:-GoogleDrive-Backup}}"
RCLONE_REMOTE="${RCLONE_REMOTE:-gdrive}"
INSTALL_LANG="${GDRIVE_BACKUP_LANG:-${INSTALL_LANG:-auto}}"
CONFIG_DIR="$HOME/.config/gdrive-tiger-backup"
CONFIG_FILE="$CONFIG_DIR/config"
PROFILES_DIR="$CONFIG_DIR/profiles"
ACTIVE_PROFILE_FILE="$CONFIG_DIR/active-profile"
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

for cmd in clang codesign install launchctl xcrun; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    exit 127
  fi
done
if ! xcrun --find actool >/dev/null 2>&1; then
  echo "Missing required command: actool" >&2
  exit 127
fi
if [[ ! -x /usr/libexec/PlistBuddy ]]; then
  echo "Missing required command: /usr/libexec/PlistBuddy" >&2
  exit 127
fi
if [[ -n "$BACKUP_VOLUME_UUID" ]]; then
  if [[ ! -d "$BACKUP_VOLUME" || -L "$BACKUP_VOLUME" ]]; then
    echo "The APFS target must be mounted at the exact nonsymlink path: $BACKUP_VOLUME" >&2
    exit 69
  fi
  if ! VOLUME_INFO_PLIST="$(/usr/sbin/diskutil info -plist "$BACKUP_VOLUME" 2>/dev/null)"; then
    echo "The mounted APFS identity could not be read: $BACKUP_VOLUME" >&2
    exit 69
  fi
  if ! MOUNTED_FILESYSTEM_TYPE="$(
    printf '%s' "$VOLUME_INFO_PLIST" |
      /usr/bin/plutil -extract FilesystemType raw -o - - 2>/dev/null
  )" ||
     ! MOUNTED_WRITABLE_MEDIA="$(
       printf '%s' "$VOLUME_INFO_PLIST" |
         /usr/bin/plutil -extract WritableMedia raw -o - - 2>/dev/null
     )" ||
     [[ "$MOUNTED_FILESYSTEM_TYPE" != "apfs" ||
        "$MOUNTED_WRITABLE_MEDIA" != "true" ]]; then
    echo "The mounted target is not a writable APFS volume: $BACKUP_VOLUME" >&2
    exit 69
  fi
  if ! MOUNTED_VOLUME_UUID="$(
    printf '%s' "$VOLUME_INFO_PLIST" |
      /usr/bin/plutil -extract VolumeUUID raw -o - - 2>/dev/null
  )"; then
    echo "The mounted target has no readable APFS volume UUID: $BACKUP_VOLUME" >&2
    exit 69
  fi
  MOUNTED_VOLUME_UUID="$(
    printf '%s' "$MOUNTED_VOLUME_UUID" | tr '[:lower:]' '[:upper:]'
  )"
  if [[ "$MOUNTED_VOLUME_UUID" != "$BACKUP_VOLUME_UUID" ]]; then
    echo "The supplied APFS UUID does not belong to the mounted target: $BACKUP_VOLUME" >&2
    exit 69
  fi
  if ! MOUNTED_VOLUME_PATH="$(
    printf '%s' "$VOLUME_INFO_PLIST" |
      /usr/bin/plutil -extract MountPoint raw -o - - 2>/dev/null
  )" ||
     ! BACKUP_VOLUME_REAL="$(cd "$BACKUP_VOLUME" 2>/dev/null && /bin/pwd -P)" ||
     ! MOUNTED_VOLUME_REAL="$(cd "$MOUNTED_VOLUME_PATH" 2>/dev/null && /bin/pwd -P)" ||
     [[ "$BACKUP_VOLUME_REAL" != "$MOUNTED_VOLUME_REAL" ]]; then
    echo "The supplied APFS path is not the exact mounted volume root: $BACKUP_VOLUME" >&2
    exit 69
  fi
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
    LC_ALL=C printf 'GDRIVE_BACKUP_TARGET=%q\n' "$BACKUP_TARGET"
    if [[ "$BACKUP_TARGET" == "nas" ]]; then
      [[ -n "$NAS_MOUNT" ]] && LC_ALL=C printf 'GDRIVE_BACKUP_NAS_MOUNT=%q\n' "$NAS_MOUNT"
      [[ -n "$NAS_URL" ]] && LC_ALL=C printf 'GDRIVE_BACKUP_NAS_URL=%q\n' "$NAS_URL"
      LC_ALL=C printf 'GDRIVE_BACKUP_NAS_SUBDIR=%q\n' "$NAS_SUBDIR"
    else
      LC_ALL=C printf 'GDRIVE_BACKUP_VOLUME=%q\n' "$BACKUP_VOLUME"
      LC_ALL=C printf 'GDRIVE_BACKUP_VOLUME_NAME=%q\n' "$BACKUP_VOLUME_NAME"
      [[ -n "$BACKUP_VOLUME_UUID" ]] &&
        LC_ALL=C printf 'GDRIVE_BACKUP_VOLUME_UUID=%q\n' "$BACKUP_VOLUME_UUID"
    fi
    LC_ALL=C printf 'RCLONE_REMOTE=%q\n' "$RCLONE_REMOTE"
    LC_ALL=C printf 'GDRIVE_BACKUP_LANG=%q\n' "$CONFIG_LANG"
    printf 'GDRIVE_BACKUP_CONFIRM=1\n'
    printf 'GDRIVE_BACKUP_AUTO_CREATE_VOLUME=1\n'
    printf 'GDRIVE_BACKUP_VERSIONING=1\n'
    LC_ALL=C printf 'GDRIVE_BACKUP_VERSIONS_SUBDIR=%q\n' '.gdrive-versions'
    printf 'GDRIVE_BACKUP_RETENTION=1\n'
    printf 'GDRIVE_BACKUP_ENCRYPTION=none\n'
    printf 'GDRIVE_BACKUP_PAUSED=0\n'
    printf 'GDRIVE_BACKUP_NOTIFY_FAILURES=1\n'
  } >"$CONFIG_FILE"
elif ! grep -q '^GDRIVE_BACKUP_LANG=' "$CONFIG_FILE"; then
  LC_ALL=C printf 'GDRIVE_BACKUP_LANG=%q\n' "$CONFIG_LANG" >>"$CONFIG_FILE"
fi
if [[ -f "$CONFIG_FILE" ]] && ! grep -q '^GDRIVE_BACKUP_TARGET=' "$CONFIG_FILE"; then
  LC_ALL=C printf 'GDRIVE_BACKUP_TARGET=%q\n' "$BACKUP_TARGET" >>"$CONFIG_FILE"
fi
if [[ -f "$CONFIG_FILE" ]] && ! grep -q '^GDRIVE_BACKUP_ENCRYPTION=' "$CONFIG_FILE"; then
  printf 'GDRIVE_BACKUP_ENCRYPTION=none\n' >>"$CONFIG_FILE"
fi
if [[ -f "$CONFIG_FILE" ]] && ! grep -q '^GDRIVE_BACKUP_RETENTION=' "$CONFIG_FILE"; then
  printf 'GDRIVE_BACKUP_RETENTION=1\n' >>"$CONFIG_FILE"
fi
if [[ -f "$CONFIG_FILE" ]] && ! grep -q '^GDRIVE_BACKUP_PAUSED=' "$CONFIG_FILE"; then
  printf 'GDRIVE_BACKUP_PAUSED=0\n' >>"$CONFIG_FILE"
fi
if [[ -f "$CONFIG_FILE" ]] && ! grep -q '^GDRIVE_BACKUP_NOTIFY_FAILURES=' "$CONFIG_FILE"; then
  printf 'GDRIVE_BACKUP_NOTIFY_FAILURES=1\n' >>"$CONFIG_FILE"
fi
if [[ -f "$CONFIG_FILE" && "$BACKUP_TARGET" == "nas" ]]; then
  if [[ -n "$NAS_MOUNT" ]] && ! grep -q '^GDRIVE_BACKUP_NAS_MOUNT=' "$CONFIG_FILE"; then
    LC_ALL=C printf 'GDRIVE_BACKUP_NAS_MOUNT=%q\n' "$NAS_MOUNT" >>"$CONFIG_FILE"
  fi
  if [[ -n "$NAS_URL" ]] && ! grep -q '^GDRIVE_BACKUP_NAS_URL=' "$CONFIG_FILE"; then
    LC_ALL=C printf 'GDRIVE_BACKUP_NAS_URL=%q\n' "$NAS_URL" >>"$CONFIG_FILE"
  fi
  if ! grep -q '^GDRIVE_BACKUP_NAS_SUBDIR=' "$CONFIG_FILE"; then
    LC_ALL=C printf 'GDRIVE_BACKUP_NAS_SUBDIR=%q\n' "$NAS_SUBDIR" >>"$CONFIG_FILE"
  fi
fi

UUID_CONFIG_TMP=""
cleanup_uuid_config_tmp() {
  if [[ -n "$UUID_CONFIG_TMP" && -e "$UUID_CONFIG_TMP" ]]; then
    "$ROOT/scripts/trash-path.sh" "$UUID_CONFIG_TMP" >/dev/null 2>&1 || true
  fi
}
trap cleanup_uuid_config_tmp EXIT

trusted_active_profile_config() {
  local profile_id profile_config profile_line id_matches=0
  if [[ ! -f "$ACTIVE_PROFILE_FILE" || -L "$ACTIVE_PROFILE_FILE" ]]; then
    echo "The active profile pointer is not a trusted regular file." >&2
    return 73
  fi
  profile_id="$(<"$ACTIVE_PROFILE_FILE")"
  if [[ ! "$profile_id" =~ ^[a-z0-9][a-z0-9-]{0,63}$ ||
        ! -d "$PROFILES_DIR" || -L "$PROFILES_DIR" ]]; then
    echo "The active profile store is not trusted." >&2
    return 73
  fi
  profile_config="$PROFILES_DIR/$profile_id.conf"
  if [[ ! -f "$profile_config" || -L "$profile_config" ]]; then
    echo "The active profile configuration is not a trusted regular file." >&2
    return 73
  fi
  while IFS= read -r profile_line || [[ -n "$profile_line" ]]; do
    case "$profile_line" in
      "GDRIVE_BACKUP_PROFILE_ID=$profile_id"|"GDRIVE_BACKUP_PROFILE_ID='$profile_id'"|"GDRIVE_BACKUP_PROFILE_ID=\"$profile_id\"")
        id_matches=1
        break
        ;;
    esac
  done <"$profile_config"
  if [[ "$id_matches" != "1" ]]; then
    echo "The active profile identity does not match its file name." >&2
    return 73
  fi
  printf '%s' "$profile_config"
}

upsert_volume_identity() {
  local target="$1"
  if [[ ! -f "$target" || -L "$target" ]]; then
    echo "Refusing to update an untrusted configuration file: $target" >&2
    return 73
  fi
  UUID_CONFIG_TMP="$(/usr/bin/mktemp "${target}.uuid.XXXXXX")"
  /usr/bin/awk '
    !/^GDRIVE_BACKUP_VOLUME=/ &&
    !/^GDRIVE_BACKUP_VOLUME_NAME=/ &&
    !/^GDRIVE_BACKUP_VOLUME_UUID=/
  ' "$target" >"$UUID_CONFIG_TMP"
  {
    LC_ALL=C printf 'GDRIVE_BACKUP_VOLUME=%q\n' "$BACKUP_VOLUME"
    LC_ALL=C printf 'GDRIVE_BACKUP_VOLUME_NAME=%q\n' "$BACKUP_VOLUME_NAME"
    LC_ALL=C printf 'GDRIVE_BACKUP_VOLUME_UUID=%q\n' "$BACKUP_VOLUME_UUID"
  } >>"$UUID_CONFIG_TMP"
  /bin/chmod 600 "$UUID_CONFIG_TMP"
  /bin/mv "$UUID_CONFIG_TMP" "$target"
  UUID_CONFIG_TMP=""
}

if [[ "$BACKUP_TARGET" == "apfs" && -n "$BACKUP_VOLUME_UUID" ]]; then
  ACTIVE_PROFILE_CONFIG=""
  if [[ -e "$ACTIVE_PROFILE_FILE" || -L "$ACTIVE_PROFILE_FILE" ]]; then
    if ! ACTIVE_PROFILE_CONFIG="$(trusted_active_profile_config)"; then
      exit 73
    fi
  fi
  if [[ -n "$ACTIVE_PROFILE_CONFIG" ]]; then
    upsert_volume_identity "$ACTIVE_PROFILE_CONFIG"
  fi
  upsert_volume_identity "$CONFIG_FILE"
fi
/bin/chmod 600 "$CONFIG_FILE"

install -m 644 "$ROOT/macos/GDriveBackupTiger/Info.plist" "$APP_CONTENTS/Info.plist"
clang -fobjc-arc -Wall -Wextra -mmacosx-version-min=13.0 \
  -arch arm64 -arch x86_64 -framework Cocoa -framework UserNotifications \
  -framework Security -framework NetFS \
  "$ROOT/macos/GDriveBackupTiger/main.m" \
  "$ROOT/macos/GDriveBackupTiger/ConfigSupport.m" \
  "$ROOT/macos/GDriveBackupTiger/ProfileSupport.m" \
  "$ROOT/macos/GDriveBackupTiger/BackupStatusSupport.m" \
  "$ROOT/macos/GDriveBackupTiger/BackupProgressSupport.m" \
  "$ROOT/macos/GDriveBackupTiger/NotificationSupport.m" \
  "$ROOT/macos/GDriveBackupTiger/SetupHealthSupport.m" \
  "$ROOT/macos/GDriveBackupTiger/RestoreSupport.m" \
  "$ROOT/macos/GDriveBackupTiger/RestoreBrowserView.m" \
  "$ROOT/macos/GDriveBackupTiger/DiagnosticsSupport.m" \
  "$ROOT/macos/GDriveBackupTiger/DiagnosticsView.m" \
  "$ROOT/macos/GDriveBackupTiger/UpdateSupport.m" \
  "$ROOT/macos/GDriveBackupTiger/NetworkMountSupport.m" \
  "$ROOT/macos/GDriveBackupTiger/Localization.m" \
  -o "$APP_CONTENTS/MacOS/GDriveBackupTiger"

ICON_WORK="$(mktemp -d "${TMPDIR:-/tmp}/gdrive-tiger-icon.XXXXXX")"
clang -fobjc-arc -Wall -Wextra -framework Cocoa "$ROOT/macos/GDriveBackupTiger/IconGenerator.m" \
  -o "$ICON_WORK/IconGenerator"
"$ICON_WORK/IconGenerator" "$ICON_WORK/Assets.xcassets/AppIcon.appiconset"
install -m 644 "$ROOT/macos/GDriveBackupTiger/AppIcon.appiconset/Contents.json" \
  "$ICON_WORK/Assets.xcassets/AppIcon.appiconset/Contents.json"
xcrun actool "$ICON_WORK/Assets.xcassets" \
  --compile "$APP_CONTENTS/Resources" \
  --platform macosx \
  --minimum-deployment-target 13.0 \
  --app-icon AppIcon \
  --output-partial-info-plist "$ICON_WORK/AppIcon-partial.plist"
test -s "$APP_CONTENTS/Resources/AppIcon.icns"
test -s "$APP_CONTENTS/Resources/Assets.car"
"$ROOT/scripts/trash-path.sh" "$ICON_WORK"

/usr/bin/xattr -cr "$APP_DIR"
# The source installer uses an ad-hoc signature, which cannot carry protected
# Apple notification entitlements without being rejected at exec time.
codesign --force --deep --sign - "$APP_DIR" >/dev/null

sudo install -m 755 "$ROOT/bin/backup-google-drive.sh" /usr/local/bin/backup-google-drive.sh
install -m 644 "$AGENT_SRC" "$AGENT_DST"
/usr/libexec/PlistBuddy -c 'Delete :EnvironmentVariables' "$AGENT_DST" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c 'Add :EnvironmentVariables dict' "$AGENT_DST"
/usr/libexec/PlistBuddy -c "Add :EnvironmentVariables:HOME string $HOME" "$AGENT_DST"
/usr/libexec/PlistBuddy -c 'Add :EnvironmentVariables:PATH string /opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin' "$AGENT_DST"

launchctl bootout "gui/$(id -u)" "$AGENT_DST" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$AGENT_DST"
launchctl enable "gui/$(id -u)/com.commcats.gdrivebackup"

echo "Installed gdrive-tiger-backup."
echo "App: $APP_DIR"
echo "Config: $CONFIG_FILE"
echo "Run a dry-run with: /usr/local/bin/backup-google-drive.sh --dry-run"
