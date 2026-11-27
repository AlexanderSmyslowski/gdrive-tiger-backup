#!/bin/bash
# Installs the Linux edition of GDrive Backup Tiger for the current user,
# without root:
#   ~/.local/share/gdrive-tiger-backup/{bin,lib}   engine and platform file
#   ~/.local/bin/gdrive-tiger-backup               command
#   ~/.config/systemd/user/gdrive-tiger-backup.*   service and hourly timer
# Run it again to update; configuration and history are kept.
# Usage: packaging/linux/install.sh [--uninstall]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SHARE_DIR="${GDRIVE_TIGER_SHARE_DIR:-$HOME/.local/share/gdrive-tiger-backup}"
BIN_DIR="${GDRIVE_TIGER_BIN_DIR:-$HOME/.local/bin}"
UNIT_DIR="${GDRIVE_TIGER_UNIT_DIR:-$HOME/.config/systemd/user}"
MIN_RCLONE="1.70.0"

say() { printf '%s\n' "$*"; }
die() { printf 'install: %s\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == "Linux" ]] || die "this installer is for Linux; on macOS use the .pkg installer"

systemctl_user() {
  command -v systemctl >/dev/null 2>&1 || return 0
  [[ "${GDRIVE_TIGER_SKIP_SYSTEMCTL:-0}" == "1" ]] && return 0
  systemctl --user "$@" || true
}

if [[ "${1:-}" == "--uninstall" ]]; then
  systemctl_user disable --now gdrive-tiger-backup.timer
  rm -f "$UNIT_DIR/gdrive-tiger-backup.service" "$UNIT_DIR/gdrive-tiger-backup.timer" \
        "$BIN_DIR/gdrive-tiger-backup"
  rm -rf "$SHARE_DIR"
  systemctl_user daemon-reload
  say "Removed the program. Configuration (~/.config/gdrive-tiger-backup), history and"
  say "log (~/.local/state/gdrive-tiger-backup) and your backups are untouched."
  exit 0
fi

# Dependencies. rclone's name transforms (1.70) keep NAS file names reversible.
missing=()
for tool in rclone jq findmnt cmp; do
  command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
done
if (( ${#missing[@]} )); then
  say "Missing: ${missing[*]}"
  say "  Arch/Omarchy:  sudo pacman -S rclone jq util-linux diffutils"
  say "  Debian/Ubuntu: sudo apt install jq util-linux diffutils  (rclone from https://rclone.org/install/)"
  exit 1
fi
rclone_version="$(rclone version 2>/dev/null | sed -n '1s/^rclone v\([0-9.]*\).*/\1/p')"
if [[ -z "$rclone_version" ]] ||
   [[ "$(printf '%s\n%s\n' "$MIN_RCLONE" "$rclone_version" | sort -V | head -n 1)" != "$MIN_RCLONE" ]]; then
  say "Warning: rclone ${rclone_version:-unknown} is older than $MIN_RCLONE."
  say "  Backups to a network share need $MIN_RCLONE or later: https://rclone.org/install/"
fi

install -d -m 755 "$SHARE_DIR/bin" "$SHARE_DIR/lib" "$BIN_DIR" "$UNIT_DIR"
install -m 755 "$ROOT/bin/backup-google-drive.sh" "$SHARE_DIR/bin/backup-google-drive.sh"
install -m 644 "$ROOT/lib/platform-linux.sh" "$SHARE_DIR/lib/platform-linux.sh"
install -m 755 "$ROOT/packaging/linux/gdrive-tiger-backup" "$BIN_DIR/gdrive-tiger-backup"
install -m 644 "$ROOT/packaging/linux/gdrive-tiger-backup.service" "$UNIT_DIR/gdrive-tiger-backup.service"
install -m 644 "$ROOT/packaging/linux/gdrive-tiger-backup.timer" "$UNIT_DIR/gdrive-tiger-backup.timer"
systemctl_user daemon-reload

say "Installed GDrive Backup Tiger for Linux."
case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) say "Note: $BIN_DIR is not on your PATH; add it to your shell profile." ;;
esac
say "Next: gdrive-tiger-backup setup"
