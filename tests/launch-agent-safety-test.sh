#!/bin/bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AGENT="$ROOT/launchd/com.commcats.gdrivebackup.plist"
POSTINSTALL="$ROOT/packaging/scripts/postinstall"
INSTALLER="$ROOT/install.sh"
failures=0

pass() {
  printf 'ok - %s\n' "$1"
}

fail() {
  printf 'not ok - %s\n' "$1"
  failures=$((failures + 1))
}

if ! start_on_mount="$(/usr/bin/plutil -extract StartOnMount raw -o - "$AGENT" 2>/dev/null)"; then
  # Newer plutil versions emit their missing-key diagnostic on stdout. The
  # failed extraction still means exactly what this assertion needs: no key.
  start_on_mount=""
fi
run_at_load="$(/usr/bin/plutil -extract RunAtLoad raw -o - "$AGENT" 2>/dev/null || true)"
program="$(/usr/bin/plutil -extract ProgramArguments.0 raw -o - "$AGENT" 2>/dev/null || true)"
mode="$(/usr/bin/plutil -extract ProgramArguments.1 raw -o - "$AGENT" 2>/dev/null || true)"

if [[ -z "$start_on_mount" && "$run_at_load" == "true" &&
      "$program" == "/Applications/GDrive Backup Tiger.app/Contents/MacOS/GDriveBackupTiger" &&
      "$mode" == "--menubar" ]]; then
  pass 'login agent starts only the exact-volume-aware menu bar controller'
else
  fail "login agent still uses a broad mount trigger (StartOnMount=$start_on_mount RunAtLoad=$run_at_load program=$program mode=$mode)"
fi

if ! /usr/bin/grep -Fq 'GDRIVE_BACKUP_TRIGGER string mount' "$POSTINSTALL" &&
   ! /usr/bin/grep -Fq 'GDRIVE_BACKUP_TRIGGER string mount' "$INSTALLER"; then
  pass 'installers no longer recreate the broad mount-trigger environment'
else
  fail 'an installer can still recreate the broad mount trigger'
fi

if /usr/bin/grep -Fq 'launchctl bootout' "$POSTINSTALL" &&
   /usr/bin/grep -Fq 'launchctl bootstrap' "$POSTINSTALL" &&
   /usr/bin/grep -Fq 'launchctl bootout' "$INSTALLER" &&
   /usr/bin/grep -Fq 'launchctl bootstrap' "$INSTALLER"; then
  pass 'installers migrate the loaded legacy agent to the safe controller'
else
  fail 'agent migration is incomplete'
fi

# The third pattern is intentionally a literal source assertion.
# shellcheck disable=SC2016
if /usr/bin/grep -Fq 'new_install=0' "$POSTINSTALL" &&
   /usr/bin/grep -Fq 'new_install=1' "$POSTINSTALL" &&
   /usr/bin/grep -Fq 'if [[ "$new_install" == "1" ]]' "$POSTINSTALL" &&
   /usr/bin/grep -Fq -- '--args --setup' "$POSTINSTALL" &&
   ! /usr/bin/grep -Fq '/usr/bin/open -n "$APP_PATH" >/dev/null' "$POSTINSTALL"; then
  pass 'package opens setup only on first install and keeps one controller on upgrades'
else
  fail 'package can still create a duplicate controller during upgrade'
fi

if (( failures > 0 )); then
  printf '%s launch agent safety test(s) failed.\n' "$failures"
  exit 1
fi

printf '%s\n' 'All launch agent safety tests passed.'
