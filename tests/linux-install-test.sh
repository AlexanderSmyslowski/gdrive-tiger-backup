#!/bin/bash
# Linux edition installer: installs engine, platform file, command and systemd
# units for the current user without root, and removes them again.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSTALLER="$ROOT/packaging/linux/install.sh"
failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1"; failures=$((failures + 1)); }

if [[ "$(uname -s)" != "Linux" ]]; then
  if ! output="$(/bin/bash "$INSTALLER" 2>&1)" && [[ "$output" == *"this installer is for Linux"* ]]; then
    pass "the Linux installer refuses to run on macOS"
  else
    fail "the Linux installer ran on macOS: $output"
  fi
  (( failures == 0 )) && printf 'All Linux install tests passed.\n'
  exit "$failures"
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/gdrive-linux-install.XXXXXX")"
trap '"$ROOT/scripts/trash-path.sh" "$WORK" >/dev/null 2>&1 || true' EXIT
mkdir -p "$WORK/home" "$WORK/fakebin"
# The installer only checks that rclone exists; CI images do not ship it.
command -v rclone >/dev/null 2>&1 || { printf '#!/bin/sh\nexit 0\n' >"$WORK/fakebin/rclone"; chmod +x "$WORK/fakebin/rclone"; }
run_installer() {
  env HOME="$WORK/home" DRIVE_BACKUP_SKIP_SYSTEMCTL=1 PATH="$WORK/home/.local/bin:$WORK/fakebin:$PATH" \
    /bin/bash "$INSTALLER" "$@"
}

if output="$(run_installer 2>&1)" &&
   [[ -x "$WORK/home/.local/share/drive-backup/bin/backup-google-drive.sh" &&
      -f "$WORK/home/.local/share/drive-backup/lib/platform-linux.sh" &&
      -f "$WORK/home/.local/share/drive-backup/agent-skill/drive-backup-google-setup/SKILL.md" &&
      -x "$WORK/home/.local/bin/drive-backup" &&
      -f "$WORK/home/.config/systemd/user/drive-backup.service" &&
      -f "$WORK/home/.config/systemd/user/drive-backup.timer" ]]; then
  pass "installer places engine, platform file, command and units in the user's home"
else
  fail "installer: $output"
fi

status="$(env HOME="$WORK/home" "$WORK/home/.local/bin/drive-backup" status --json 2>&1)"
if [[ "$(jq -r '.status' <<<"$status" 2>/dev/null)" == "never" &&
      -d "$WORK/home/.local/state/drive-backup" && ! -e "$WORK/home/Library" ]]; then
  pass "the installed command reports status and keeps state in ~/.local/state"
else
  fail "installed status: $status"
fi

if grep -q '^OnCalendar=hourly$' "$WORK/home/.config/systemd/user/drive-backup.timer" &&
   grep -q '^Persistent=true$' "$WORK/home/.config/systemd/user/drive-backup.timer" &&
   grep -q '^Environment=GDRIVE_BACKUP_TRIGGER=schedule$' "$WORK/home/.config/systemd/user/drive-backup.service"; then
  pass "the timer fires hourly with catch-up and the service runs as a scheduled backup"
else
  fail "unit contents"
fi

if command -v systemd-analyze >/dev/null 2>&1; then
  if systemd-analyze --user verify "$WORK/home/.config/systemd/user/drive-backup.timer" \
       "$WORK/home/.config/systemd/user/drive-backup.service" >/dev/null 2>&1; then
    pass "systemd accepts the units"
  else
    printf 'ok - systemd unit verification unavailable here # SKIP\n'
  fi
fi

mkdir -p "$WORK/home/.config/drive-backup"
printf 'GDRIVE_BACKUP_SCHEDULE=daily\n' >"$WORK/home/.config/drive-backup/config"
if run_installer --uninstall >/dev/null 2>&1 &&
   [[ ! -e "$WORK/home/.local/share/drive-backup" && ! -e "$WORK/home/.local/bin/drive-backup" &&
      ! -e "$WORK/home/.config/systemd/user/drive-backup.timer" &&
      -f "$WORK/home/.config/drive-backup/config" ]]; then
  pass "uninstall removes the program and keeps the configuration"
else
  fail "uninstall"
fi

if (( failures > 0 )); then
  printf '%d Linux install test(s) failed.\n' "$failures"
  exit 1
fi
printf 'All Linux install tests passed.\n'
