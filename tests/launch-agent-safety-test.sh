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
restart_after_crash="$(/usr/bin/plutil -extract KeepAlive.SuccessfulExit raw -o - "$AGENT" 2>/dev/null || true)"
program="$(/usr/bin/plutil -extract ProgramArguments.0 raw -o - "$AGENT" 2>/dev/null || true)"
mode="$(/usr/bin/plutil -extract ProgramArguments.1 raw -o - "$AGENT" 2>/dev/null || true)"

if [[ -z "$start_on_mount" && "$run_at_load" == "true" &&
      "$restart_after_crash" == "false" &&
      "$program" == "/Applications/GDrive Backup Tiger.app/Contents/MacOS/GDriveBackupTiger" &&
      "$mode" == "--menubar" ]]; then
  pass 'login agent starts the exact-volume-aware controller and restarts it after a crash'
else
  fail "login agent lifecycle is unsafe (StartOnMount=$start_on_mount RunAtLoad=$run_at_load SuccessfulExit=$restart_after_crash program=$program mode=$mode)"
fi

if ! /usr/bin/grep -Fq 'GDRIVE_BACKUP_TRIGGER string mount' "$POSTINSTALL" &&
   ! /usr/bin/grep -Fq 'GDRIVE_BACKUP_TRIGGER string mount' "$INSTALLER"; then
  pass 'installers no longer recreate the broad mount-trigger environment'
else
  fail 'an installer can still recreate the broad mount trigger'
fi

schedule_reregistration_case() {
  local label="$1" state="$2" make_plist="$3" expected="$4"
  local work agents fake calls actual
  work="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/gdrive-schedule-agent.XXXXXX")"
  agents="$work/LaunchAgents"
  fake="$work/launchctl"
  calls="$work/calls"
  /bin/mkdir -p "$agents"
  case "$make_plist" in
    file) : >"$agents/com.commcats.gdrivebackup.schedule.plist" ;;
    symlink) /bin/ln -s /etc/hosts "$agents/com.commcats.gdrivebackup.schedule.plist" ;;
  esac
  cat >"$fake" <<FAKE
#!/bin/bash
printf '%s\n' "\$1" >>"$calls"
[[ "\$1" == print ]] && printf '\tstate = %s\n' "$state"
exit 0
FAKE
  /bin/chmod 755 "$fake"
  /bin/bash -c '
    eval "$(/usr/bin/awk '"'"'$0 == "reregister_schedule_agent() {" {p=1} p {print} p && /^}$/ {exit}'"'"' "$1")"
    reregister_schedule_agent 501 "$2" "$3"' _ "$POSTINSTALL" "$agents" "$fake"
  actual="$(/usr/bin/paste -sd, "$calls" 2>/dev/null)"
  "$ROOT/scripts/trash-path.sh" "$work" >/dev/null 2>&1 || true
  if [[ "$actual" == "$expected" ]]; then
    pass "$label"
  else
    fail "$label (launchctl calls: ${actual:-none})"
  fi
}

schedule_reregistration_case 'an idle schedule agent is re-registered after an update' \
  'not running' file 'print,bootout,bootstrap'
schedule_reregistration_case 'a running scheduled backup is never interrupted by an update' \
  'running' file 'print'
schedule_reregistration_case 'without a schedule agent the installer leaves launchd alone' \
  'not running' none ''
schedule_reregistration_case 'a symlinked schedule agent is not bootstrapped' \
  'not running' symlink ''

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
