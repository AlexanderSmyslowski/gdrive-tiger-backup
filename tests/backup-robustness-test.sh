#!/bin/bash
# Covers the housekeeping and catch-up behavior that keeps unattended backups
# running without filling the Mac, its Trash, or the backup destination.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACKUP_SCRIPT="$ROOT/bin/backup-google-drive.sh"
failures=0

fail() {
  printf 'not ok - %s\n' "$1"
  failures=$((failures + 1))
}

pass() {
  printf 'ok - %s\n' "$1"
}

TEST_HOME=""

remove_test_home() {
  [[ -n "$TEST_HOME" && -d "$TEST_HOME" && "$TEST_HOME" == */gdrive-robustness-test.* ]] || return 0
  /bin/rm -rf -- "$TEST_HOME"
}
trap remove_test_home EXIT

prepare_test_environment() {
  remove_test_home
  TEST_HOME="$(mktemp -d "${TMPDIR:-/tmp}/gdrive-robustness-test.XXXXXX")"
  FAKE_BIN="$TEST_HOME/fake-bin"
  FAKE_RCLONE_LOG="$TEST_HOME/rclone-calls.log"
  FAKE_TRASH_DIR="$TEST_HOME/system-trash"
  TEST_TMP="$TEST_HOME/tmp"
  NAS_MOUNT="$TEST_HOME/nas"
  MOUNTED_NAS="$NAS_MOUNT"
  DEST_ROOT="$NAS_MOUNT/backup"
  VERSIONS_ROOT="$DEST_ROOT/.gdrive-versions"
  QUARANTINE="$VERSIONS_ROOT/.retention-trash"
  BACKUP_LOG="$TEST_HOME/Library/Logs/gdrive-backup.log"
  SUMMARY="$TEST_HOME/Library/Application Support/GDrive Backup Tiger/last-run.status"
  FAKE_NOW="$(/bin/date '+%s')"
  mkdir -p "$FAKE_BIN" "$NAS_MOUNT" "$FAKE_TRASH_DIR" "$TEST_TMP" "${SUMMARY%/*}"
  : >"$FAKE_RCLONE_LOG"

  cat >"$FAKE_BIN/rclone" <<'SH'
#!/bin/bash
set -u
: "${FAKE_RCLONE_LOG:?}"

if [[ "${1:-}" == "copy" && "${2:-}" == "--help" ]]; then
  printf '%s\n' '      --name-transform stringArray   Transform paths during the copy process'
  exit 0
fi

printf '%s\n' "${1:-}" >>"$FAKE_RCLONE_LOG"
case "${1:-}" in
  config) exit 0 ;;
  backend)
    printf '[]\n'
    exit 0
    ;;
  copy)
    if [[ " $* " == *' --ignore-existing '* ]]; then
      mkdir -p "$3"
      /bin/cp -R -n "$2"/. "$3"/ 2>/dev/null || true
      exit 0
    fi
    if [[ -n "${FAKE_RCLONE_STATS_BLOCKS:-}" ]]; then
      for ((block = 0; block < FAKE_RCLONE_STATS_BLOCKS; block++)); do
        printf '2026/11/10 20:00:%02d INFO  : \n' "$block"
        printf 'Transferred:   \t          0 B / 0 B, -, 0 B/s, ETA -\n'
        printf 'Checks:                %d / %d, 100%%, Listed 10\n' "$block" "$block"
        printf 'Elapsed time:         %d.0s\n\n' "$block"
      done
      printf '2026/11/10 20:01:00 INFO  : report.pdf: Copied (new)\n'
    fi
    [[ -z "${FAKE_RCLONE_SLEEP:-}" ]] || /bin/sleep "$FAKE_RCLONE_SLEEP"
    exit "${FAKE_RCLONE_COPY_STATUS:-0}"
    ;;
esac
exit 64
SH

  cat >"$FAKE_BIN/jq" <<'SH'
#!/bin/bash
case "${1:-}" in
  length) printf '0\n' ;;
  -r) ;;
  *) exit 64 ;;
esac
SH

  cat >"$FAKE_BIN/date" <<'SH'
#!/bin/bash
if [[ "${1:-}" == '+%s' ]]; then
  printf '%s\n' "${FAKE_NOW:?}"
else
  /bin/date "$@"
fi
SH

  cat >"$FAKE_BIN/trash" <<'SH'
#!/bin/bash
: "${FAKE_TRASH_DIR:?}"
for path in "$@"; do
  /bin/mv "$path" "$FAKE_TRASH_DIR/" || exit $?
done
SH

  cat >"$FAKE_BIN/mount" <<'SH'
#!/bin/bash
[[ -n "${FAKE_MOUNTED_NAS:-}" ]] || exit 0
printf '%s on %s (smbfs, nodev, nosuid)\n' '//backup.test/share' "$FAKE_MOUNTED_NAS"
SH

  local tool
  for tool in flock diskutil plutil; do
    printf '#!/bin/bash\nexit 0\n' >"$FAKE_BIN/$tool"
  done
  chmod +x "$FAKE_BIN"/*
}

run_backup() {
  env \
    HOME="$TEST_HOME" \
    TMPDIR="$TEST_TMP" \
    GDRIVE_BACKUP_PATH="$FAKE_BIN:/usr/bin:/bin:/usr/sbin:/sbin" \
    FAKE_RCLONE_LOG="$FAKE_RCLONE_LOG" \
    FAKE_TRASH_DIR="$FAKE_TRASH_DIR" \
    FAKE_NOW="$FAKE_NOW" \
    FAKE_MOUNTED_NAS="$MOUNTED_NAS" \
    MOUNT_SETTLE_SECONDS=0 \
    GDRIVE_BACKUP_NAS_RECHECK_SECONDS=0 \
    GDRIVE_BACKUP_TARGET=nas \
    GDRIVE_BACKUP_NAS_MOUNT="$NAS_MOUNT" \
    GDRIVE_BACKUP_MOUNT_BIN="$FAKE_BIN/mount" \
    GDRIVE_BACKUP_DEST_ROOT="$DEST_ROOT" \
    GDRIVE_BACKUP_CONFIRM=0 \
    GDRIVE_BACKUP_LOCK="$TEST_HOME/backup.lock" \
    BACKUP_DISABLE_ANIMATION=1 \
    RCLONE_REMOTE=tdd-remote \
    "$@" \
    "$BACKUP_SCRIPT" --run
}

run_daily_schedule() {
  run_backup GDRIVE_BACKUP_TRIGGER=schedule GDRIVE_BACKUP_SCHEDULE=daily \
    BACKUP_ASSUME_YES=1
}

copy_calls() {
  /usr/bin/grep -c '^copy$' "$FAKE_RCLONE_LOG" 2>/dev/null || true
}

summary_value() {
  /usr/bin/awk -F= -v key="$1" '$1 == key { print $2 }' "$SUMMARY" 2>/dev/null
}

version_name() {
  printf '%s-00000000-0000-4000-8000-%012d' "$1" "$2"
}

# touch -t takes local time; this ages a path by whole days before FAKE_NOW.
age_path_days() {
  /usr/bin/touch -t "$(/bin/date -r "$((FAKE_NOW - $2 * 86400))" '+%Y%m%d%H%M.%S')" "$1"
}

test_quarantine_is_purged_after_grace_period() {
  local name="retention deletes quarantined version states after the grace period"
  local old young foreign status
  prepare_test_environment
  old="$(version_name '2025-06-01T12-00-00+0000' 1)"
  young="$(version_name '2025-06-02T12-00-00+0000' 2)"
  foreign="not-a-version-state"
  mkdir -p "$QUARANTINE/$old/My Drive" "$QUARANTINE/$young" "$QUARANTINE/$foreign"
  printf 'payload' >"$QUARANTINE/$old/My Drive/file.txt"
  age_path_days "$QUARANTINE/$old" 10
  age_path_days "$QUARANTINE/$young" 2
  age_path_days "$QUARANTINE/$foreign" 400

  run_backup
  status=$?

  if [[ "$status" == "0" && ! -e "$QUARANTINE/$old" && -d "$QUARANTINE/$young" &&
        -d "$QUARANTINE/$foreign" && -z "$(ls -A "$FAKE_TRASH_DIR")" ]]; then
    pass "$name"
  else
    fail "$name (status=$status)"
  fi
}

test_quarantine_purge_can_be_disabled() {
  local name="retention keeps the quarantine forever when purging is disabled"
  local old status
  prepare_test_environment
  old="$(version_name '2025-06-01T12-00-00+0000' 3)"
  mkdir -p "$QUARANTINE/$old"
  age_path_days "$QUARANTINE/$old" 400

  run_backup GDRIVE_BACKUP_RETENTION_PURGE_DAYS=0
  status=$?

  if [[ "$status" == "0" && -d "$QUARANTINE/$old" ]]; then
    pass "$name"
  else
    fail "$name (status=$status)"
  fi
}

test_expired_state_is_quarantined_not_trashed() {
  local name="an expired version state enters the quarantine and stays out of the Trash"
  local expired status stamped
  prepare_test_environment
  expired="$(version_name '2025-06-01T12-00-00+0000' 4)"
  mkdir -p "$VERSIONS_ROOT/$expired"
  age_path_days "$VERSIONS_ROOT/$expired" 400

  run_backup
  status=$?
  stamped="$(/usr/bin/stat -f '%m' "$QUARANTINE/$expired" 2>/dev/null || printf '0')"

  # The grace period starts when the state is quarantined, not when it was created.
  if [[ "$status" == "0" && ! -e "$VERSIONS_ROOT/$expired" && -d "$QUARANTINE/$expired" &&
        -z "$(ls -A "$FAKE_TRASH_DIR")" && ! -e "$TEST_HOME/.Trash" ]] &&
     (( FAKE_NOW - stamped < 3600 )); then
    pass "$name"
  else
    fail "$name (status=$status stamped=$stamped)"
  fi
}

test_scratch_files_are_removed() {
  local name="a run leaves no scratch files behind and puts none in the Trash"
  local status
  prepare_test_environment

  run_backup
  status=$?

  if [[ "$status" == "0" && -z "$(ls -A "$TEST_TMP")" && ! -e "$TEST_HOME/.Trash" &&
        -z "$(ls -A "$FAKE_TRASH_DIR")" ]]; then
    pass "$name"
  else
    fail "$name (status=$status leftovers=$(/usr/bin/find "$TEST_TMP" -mindepth 1 -maxdepth 1 | tr '\n' ' '))"
  fi
}

test_log_is_rotated() {
  local name="an oversized log is compressed once and restarted"
  local status
  prepare_test_environment
  mkdir -p "${BACKUP_LOG%/*}"
  { printf 'OLD-RUN-MARKER\n'; /usr/bin/head -c 4000 /dev/zero | /usr/bin/tr '\0' 'x'; printf '\n'; } >"$BACKUP_LOG"

  run_backup GDRIVE_BACKUP_LOG_MAX_BYTES=1000
  status=$?

  if [[ "$status" == "0" && -f "$BACKUP_LOG.1.gz" ]] &&
     /usr/bin/gunzip -c "$BACKUP_LOG.1.gz" | /usr/bin/grep -q 'OLD-RUN-MARKER' &&
     ! /usr/bin/grep -q 'OLD-RUN-MARKER' "$BACKUP_LOG" &&
     /usr/bin/grep -q 'Fertig ohne Fehler' "$BACKUP_LOG"; then
    pass "$name"
  else
    fail "$name (status=$status)"
  fi
}

test_repeated_statistics_are_not_logged() {
  local name="repeated rclone statistics are throttled while file lines stay in the log"
  local status blocks
  prepare_test_environment

  run_backup FAKE_RCLONE_STATS_BLOCKS=20
  status=$?
  blocks="$(/usr/bin/grep -c '^Elapsed time:' "$BACKUP_LOG")"

  # Both copy phases (My Drive, Shared with me) log their first block only.
  if [[ "$status" == "0" && "$blocks" == "2" ]] &&
     [[ "$(/usr/bin/grep -c 'report.pdf: Copied (new)' "$BACKUP_LOG")" == "2" ]]; then
    pass "$name"
  else
    fail "$name (status=$status blocks=$blocks)"
  fi
}

test_signal_is_logged() {
  local name="an interrupted run records the signal in the log and summary"
  local pid engine status
  prepare_test_environment

  run_backup FAKE_RCLONE_SLEEP=2 &
  pid=$!
  /bin/sleep 1
  # The background job is a subshell; the engine is its only child.
  engine="$(/usr/bin/pgrep -P "$pid" | /usr/bin/head -n 1)"
  kill -TERM "${engine:-$pid}" 2>/dev/null
  wait "$pid"
  status=$?

  if [[ "$status" == "143" ]] && /usr/bin/grep -q 'ABBRUCH: Backup wurde durch Signal TERM' "$BACKUP_LOG" &&
     [[ "$(summary_value status)" == "cancelled" && -z "$(ls -A "$TEST_TMP")" ]]; then
    pass "$name"
  else
    fail "$name (status=$status)"
  fi
}

test_daily_window_catches_up() {
  local name="a daily schedule catches up quietly and runs once per window"
  local status finished_before window
  prepare_test_environment
  # 21:00 local time: one hour into the daily window that opened at 20:00.
  FAKE_NOW="$(LC_ALL=C /bin/date -j -f '%Y-%m-%d %H:%M:%S' '2026-11-10 21:00:00' '+%s')"
  window=$((FAKE_NOW - 3600))

  # Primary attempt: the NAS is not mounted and the failure is reported.
  MOUNTED_NAS=""
  run_daily_schedule
  status=$?
  if [[ "$status" != "69" || "$(summary_value status)" != "failure" ||
        "$(summary_value daily_window_started_at)" != "$window" ||
        "$(summary_value daily_window_attempts)" != "1" ]]; then
    fail "$name (primary attempt: status=$status)"
    return
  fi
  finished_before="$(summary_value finished_at)"

  # Next hourly firing: still unreachable, so nothing is reported or counted.
  FAKE_NOW=$((FAKE_NOW + 3600))
  run_daily_schedule
  status=$?
  if [[ "$status" != "0" || "$(summary_value status)" != "failure" ||
        "$(summary_value finished_at)" != "$finished_before" ||
        "$(summary_value daily_window_attempts)" != "1" || "$(copy_calls)" != "0" ]] ||
     ! /usr/bin/grep -q 'Nachhol-Lauf: Backup-Ziel weiterhin nicht verfuegbar' "$BACKUP_LOG"; then
    fail "$name (quiet catch-up: status=$status)"
    return
  fi

  # The NAS returns: the catch-up firing performs the backup.
  FAKE_NOW=$((FAKE_NOW + 3600))
  MOUNTED_NAS="$NAS_MOUNT"
  run_daily_schedule
  status=$?
  if [[ "$status" != "0" || "$(summary_value status)" != "success" ||
        "$(summary_value daily_window_attempts)" != "2" ||
        "$(summary_value last_success_at_nas)" != "$FAKE_NOW" || "$(copy_calls)" != "2" ]]; then
    fail "$name (recovery: status=$status copies=$(copy_calls))"
    return
  fi

  # Later firings of the same window do nothing at all.
  FAKE_NOW=$((FAKE_NOW + 3600))
  run_daily_schedule
  status=$?
  if [[ "$status" == "0" && "$(copy_calls)" == "2" &&
        "$(summary_value status)" == "success" ]]; then
    pass "$name"
  else
    fail "$name (completed window: status=$status copies=$(copy_calls))"
  fi
}

test_other_destination_does_not_complete_window() {
  local name="a success on the attached disk does not complete the NAS window"
  local status
  prepare_test_environment
  FAKE_NOW="$(LC_ALL=C /bin/date -j -f '%Y-%m-%d %H:%M:%S' '2026-11-10 21:00:00' '+%s')"
  cat >"$SUMMARY" <<EOF
protocol=1
status=success
pid=1
started_at=$((FAKE_NOW - 900))
finished_at=$((FAKE_NOW - 600))
last_success_at=$((FAKE_NOW - 600))
last_success_target=apfs
last_success_destination=/Volumes/Disk
exit_code=0
trigger=mount
target=apfs
destination=/Volumes/Disk
EOF

  run_daily_schedule
  status=$?

  if [[ "$status" == "0" && "$(copy_calls)" == "2" &&
        "$(summary_value last_success_at_nas)" == "$FAKE_NOW" &&
        "$(summary_value last_success_at_apfs)" == "$((FAKE_NOW - 600))" ]]; then
    pass "$name"
  else
    fail "$name (status=$status copies=$(copy_calls))"
  fi
}

test_daily_window_attempts_are_bounded() {
  local name="a daily window stops retrying after its attempts are used"
  local status window
  prepare_test_environment
  FAKE_NOW="$(LC_ALL=C /bin/date -j -f '%Y-%m-%d %H:%M:%S' '2026-11-10 23:00:00' '+%s')"
  window=$((FAKE_NOW - 3 * 3600))
  cat >"$SUMMARY" <<EOF
protocol=1
status=failure
pid=1
started_at=$((FAKE_NOW - 1800))
finished_at=$((FAKE_NOW - 1700))
exit_code=1
trigger=schedule
target=nas
destination=$DEST_ROOT
daily_window_started_at=$window
daily_window_attempts=4
EOF

  run_daily_schedule
  status=$?

  if [[ "$status" == "0" && "$(copy_calls)" == "0" &&
        "$(summary_value status)" == "failure" && ! -s "$BACKUP_LOG" ]]; then
    pass "$name"
  else
    fail "$name (status=$status copies=$(copy_calls))"
  fi
}

test_low_free_space_stops_before_copying() {
  local name="a destination without free space fails before anything is copied"
  local status
  prepare_test_environment

  run_backup GDRIVE_BACKUP_MIN_FREE_MB=999999999
  status=$?

  if [[ "$status" == "73" && "$(copy_calls)" == "0" &&
        "$(summary_value reason)" == "destination_full" ]]; then
    pass "$name"
  else
    fail "$name (status=$status copies=$(copy_calls))"
  fi
}

test_quarantine_is_purged_after_grace_period
test_quarantine_purge_can_be_disabled
test_expired_state_is_quarantined_not_trashed
test_scratch_files_are_removed
test_log_is_rotated
test_repeated_statistics_are_not_logged
test_signal_is_logged
test_daily_window_catches_up
test_other_destination_does_not_complete_window
test_daily_window_attempts_are_bounded
test_low_free_space_stops_before_copying

if (( failures > 0 )); then
  printf '%d backup robustness test(s) failed.\n' "$failures"
  exit 1
fi
printf 'All backup robustness tests passed.\n'
