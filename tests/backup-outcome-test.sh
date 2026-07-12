#!/bin/bash
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

prepare_test_environment() {
  TEST_HOME="$(mktemp -d "${TMPDIR:-/tmp}/gdrive-outcome-test.XXXXXX")"
  FAKE_BIN="$TEST_HOME/fake-bin"
  NAS_MOUNT="$TEST_HOME/nas"
  RUN_STATE_FILE="$TEST_HOME/run-state"
  SUMMARY_STATE_FILE="$TEST_HOME/last-run.status"
  OPEN_LOG="$TEST_HOME/open.log"
  mkdir -p "$FAKE_BIN" "$NAS_MOUNT"

  cat >"$FAKE_BIN/rclone" <<'SH'
#!/bin/bash
case "${1:-}" in
  config)
    if [[ -n "${FAKE_RCLONE_CONFIG_STARTED_FILE:-}" ]]; then
      : >"$FAKE_RCLONE_CONFIG_STARTED_FILE"
    fi
    if [[ "${FAKE_RCLONE_CONFIG_SLEEP_SECONDS:-0}" != "0" ]]; then
      /bin/sleep "$FAKE_RCLONE_CONFIG_SLEEP_SECONDS"
    fi
    exit 0
    ;;
  backend) printf '[]\n'; exit 0 ;;
  copy)
    if [[ -n "${FAKE_RCLONE_ARGS_FILE:-}" ]]; then
      printf '%s\n' "$@" >>"$FAKE_RCLONE_ARGS_FILE"
    fi
    if [[ -n "${FAKE_RCLONE_COPY_OUTPUT:-}" ]]; then
      printf '%s\n' "$FAKE_RCLONE_COPY_OUTPUT"
    fi
    if [[ -n "${FAKE_RCLONE_STARTED_FILE:-}" ]]; then
      : >"$FAKE_RCLONE_STARTED_FILE"
    fi
    if [[ "${FAKE_RCLONE_SLEEP_SECONDS:-0}" != "0" ]]; then
      /bin/sleep "$FAKE_RCLONE_SLEEP_SECONDS"
    fi
    if [[ -n "${FAKE_RCLONE_DISCONNECT_MOUNT:-}" ]]; then
      /bin/mv "$FAKE_RCLONE_DISCONNECT_MOUNT" "${FAKE_RCLONE_DISCONNECT_MOUNT}.disconnected"
    fi
    exit "${FAKE_RCLONE_COPY_STATUS:-0}"
    ;;
esac
exit 64
SH

  cat >"$FAKE_BIN/jq" <<'SH'
#!/bin/bash
case "${1:-}" in
  length) printf '0\n' ;;
  -r) exit 0 ;;
  *) exit 64 ;;
esac
SH

  cat >"$FAKE_BIN/open" <<'SH'
#!/bin/bash
: "${FAKE_OPEN_LOG:?}"
printf '%s\n' "$@" >"$FAKE_OPEN_LOG"
if [[ -n "${FAKE_CONFIRM_DECISION:-}" && " $* " == *" --confirm "* ]]; then
  printf '%s\n' "$FAKE_CONFIRM_DECISION" >"${!#}"
fi
exit "${FAKE_OPEN_STATUS:-0}"
SH

  cat >"$FAKE_BIN/flock" <<'SH'
#!/bin/bash
exit "${FAKE_FLOCK_STATUS:-0}"
SH

  cat >"$FAKE_BIN/mount" <<'SH'
#!/bin/bash
printf '%s on %s (smbfs, nodev, nosuid)\n' '//backup.test/share' "${FAKE_NAS_MOUNT:?}"
SH

  local tool
  for tool in diskutil plutil; do
    cat >"$FAKE_BIN/$tool" <<'SH'
#!/bin/bash
exit 0
SH
  done
  chmod +x "$FAKE_BIN/rclone" "$FAKE_BIN/jq" "$FAKE_BIN/open" "$FAKE_BIN/flock" \
    "$FAKE_BIN/mount" "$FAKE_BIN/diskutil" "$FAKE_BIN/plutil"
}

run_backup() {
  env \
    HOME="$TEST_HOME" \
    GDRIVE_BACKUP_PATH="$FAKE_BIN:/usr/bin:/bin:/usr/sbin:/sbin" \
    MOUNT_SETTLE_SECONDS=0 \
    GDRIVE_BACKUP_TARGET=nas \
    GDRIVE_BACKUP_NAS_MOUNT="$NAS_MOUNT" \
    GDRIVE_BACKUP_MOUNT_BIN="$FAKE_BIN/mount" \
    GDRIVE_BACKUP_DEST_ROOT="$NAS_MOUNT/backup" \
    GDRIVE_BACKUP_CONFIRM="${GDRIVE_BACKUP_CONFIRM:-0}" \
    GDRIVE_BACKUP_LOCK="$TEST_HOME/backup.lock" \
    GDRIVE_BACKUP_VERSIONING=0 \
    GDRIVE_BACKUP_RETENTION=0 \
    GDRIVE_BACKUP_RUN_STATE_FILE="${GDRIVE_BACKUP_RUN_STATE_FILE-$RUN_STATE_FILE}" \
    GDRIVE_BACKUP_SUMMARY_STATE_FILE="$SUMMARY_STATE_FILE" \
    BACKUP_DISABLE_ANIMATION="${BACKUP_DISABLE_ANIMATION:-1}" \
    FAKE_RCLONE_COPY_STATUS="${FAKE_RCLONE_COPY_STATUS:-0}" \
    FAKE_RCLONE_COPY_OUTPUT="${FAKE_RCLONE_COPY_OUTPUT:-}" \
    FAKE_RCLONE_ARGS_FILE="${FAKE_RCLONE_ARGS_FILE:-}" \
    FAKE_RCLONE_SLEEP_SECONDS="${FAKE_RCLONE_SLEEP_SECONDS:-0}" \
    FAKE_RCLONE_STARTED_FILE="${FAKE_RCLONE_STARTED_FILE:-}" \
    FAKE_RCLONE_DISCONNECT_MOUNT="${FAKE_RCLONE_DISCONNECT_MOUNT:-}" \
    FAKE_RCLONE_CONFIG_STARTED_FILE="${FAKE_RCLONE_CONFIG_STARTED_FILE:-}" \
    FAKE_RCLONE_CONFIG_SLEEP_SECONDS="${FAKE_RCLONE_CONFIG_SLEEP_SECONDS:-0}" \
    FAKE_FLOCK_STATUS="${FAKE_FLOCK_STATUS:-0}" \
    FAKE_NAS_MOUNT="$NAS_MOUNT" \
    FAKE_OPEN_LOG="$OPEN_LOG" \
    FAKE_OPEN_STATUS="${FAKE_OPEN_STATUS:-0}" \
    FAKE_CONFIRM_DECISION="${FAKE_CONFIRM_DECISION:-}" \
    RCLONE_REMOTE=tdd-remote \
    "$@" \
    "$BACKUP_SCRIPT" --run
}

test_paused_automatic_run_is_silent_and_preserves_history() {
  local name="paused automatic run is silent and preserves backup history"
  local before after status state
  prepare_test_environment
  before=$'protocol=1\nstatus=success\npid=1\nstarted_at=1783790000\nfinished_at=1783790100\nexit_code=0\ntrigger=manual\ntarget=nas\ndestination=/Volumes/Archive'
  printf '%s' "$before" >"$SUMMARY_STATE_FILE"
  chmod 600 "$SUMMARY_STATE_FILE"

  run_backup \
    "GDRIVE_BACKUP_TRIGGER=schedule" \
    "GDRIVE_BACKUP_PAUSED=1" \
    "FAKE_RCLONE_STARTED_FILE=$TEST_HOME/rclone-started"
  status=$?
  after="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"
  state="$(cat "$RUN_STATE_FILE" 2>/dev/null || true)"

  if [[ "$status" == "0" && "$after" == "$before" && ! -e "$TEST_HOME/rclone-started" &&
        "$state" == *$'status=skipped\n'* && "$state" == *$'reason=automatic_backups_paused\n'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status state=${state//$'\n'/,})"
  fi
}

start_backup_async() {
  env \
    HOME="$TEST_HOME" \
    GDRIVE_BACKUP_PATH="$FAKE_BIN:/usr/bin:/bin:/usr/sbin:/sbin" \
    MOUNT_SETTLE_SECONDS=0 \
    GDRIVE_BACKUP_TARGET=nas \
    GDRIVE_BACKUP_NAS_MOUNT="$NAS_MOUNT" \
    GDRIVE_BACKUP_MOUNT_BIN="$FAKE_BIN/mount" \
    GDRIVE_BACKUP_DEST_ROOT="$NAS_MOUNT/backup" \
    GDRIVE_BACKUP_CONFIRM=0 \
    GDRIVE_BACKUP_LOCK="$TEST_HOME/backup.lock" \
    GDRIVE_BACKUP_VERSIONING=0 \
    GDRIVE_BACKUP_RETENTION=0 \
    GDRIVE_BACKUP_RUN_STATE_FILE="$RUN_STATE_FILE" \
    GDRIVE_BACKUP_SUMMARY_STATE_FILE="$SUMMARY_STATE_FILE" \
    BACKUP_DISABLE_ANIMATION="${BACKUP_DISABLE_ANIMATION:-1}" \
    GDRIVE_BACKUP_ANIMATION_APP="${GDRIVE_BACKUP_ANIMATION_APP:-/Applications/GDrive Backup Tiger.app}" \
    GDRIVE_BACKUP_OPEN_BIN="${GDRIVE_BACKUP_OPEN_BIN:-$FAKE_BIN/open}" \
    FAKE_RCLONE_COPY_STATUS=0 \
    FAKE_RCLONE_SLEEP_SECONDS=3 \
    FAKE_RCLONE_STARTED_FILE="$1" \
    FAKE_RCLONE_CONFIG_STARTED_FILE="${FAKE_RCLONE_CONFIG_STARTED_FILE:-}" \
    FAKE_RCLONE_CONFIG_SLEEP_SECONDS="${FAKE_RCLONE_CONFIG_SLEEP_SECONDS:-0}" \
    FAKE_FLOCK_STATUS=0 \
    FAKE_NAS_MOUNT="$NAS_MOUNT" \
    FAKE_OPEN_LOG="$OPEN_LOG" \
    RCLONE_REMOTE=tdd-remote \
    "$BACKUP_SCRIPT" --run &
  ASYNC_BACKUP_PID=$!
}

test_failed_backup_publishes_failure() {
  local name="failed backup publishes failure instead of success"
  local status state
  prepare_test_environment

  FAKE_RCLONE_COPY_STATUS=23 run_backup
  status=$?
  state="$(cat "$RUN_STATE_FILE" 2>/dev/null || true)"

  if [[ "$status" == "1" && "$state" == *$'status=failure\n'* && "$state" == *'exit_code=1'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status state=${state//$'\n'/,})"
  fi
}

test_successful_backup_publishes_success() {
  local name="successful backup publishes success"
  local status state
  prepare_test_environment

  FAKE_RCLONE_COPY_STATUS=0 run_backup
  status=$?
  state="$(cat "$RUN_STATE_FILE" 2>/dev/null || true)"

  if [[ "$status" == "0" && "$state" == *$'status=success\n'* && "$state" == *'exit_code=0'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status state=${state//$'\n'/,})"
  fi
}

test_animation_receives_run_state_file() {
  local name="animation receives the explicit run state file"
  local status state_path state
  prepare_test_environment

  mkdir -p "$TEST_HOME/GDrive Backup Tiger.app"
  BACKUP_DISABLE_ANIMATION=0 \
    GDRIVE_BACKUP_RUN_STATE_FILE='' \
    run_backup \
      "GDRIVE_BACKUP_ANIMATION_APP=$TEST_HOME/GDrive Backup Tiger.app" \
      "GDRIVE_BACKUP_OPEN_BIN=$FAKE_BIN/open"
  status=$?
  state_path="$(sed -n '6p' "$OPEN_LOG" 2>/dev/null || true)"
  state="$(cat "$state_path" 2>/dev/null || true)"

  if [[ "$status" == "0" && -n "$state_path" && "$state" == *'status=success'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status path=$state_path state=${state//$'\n'/,})"
  fi
}

test_manual_progress_requests_foreground_activation() {
  local name="manual progress requests one foreground activation"
  local status
  prepare_test_environment

  mkdir -p "$TEST_HOME/GDrive Backup Tiger.app"
  BACKUP_DISABLE_ANIMATION=0 \
    run_backup \
      "GDRIVE_BACKUP_ANIMATION_APP=$TEST_HOME/GDrive Backup Tiger.app" \
      "GDRIVE_BACKUP_OPEN_BIN=$FAKE_BIN/open" \
      "BACKUP_PROGRESS_FOREGROUND=1"
  status=$?

  if [[ "$status" == "0" ]] && grep -Fxq -- '--foreground' "$OPEN_LOG"; then
    pass "$name"
  else
    fail "$name (exit=$status open=${OPEN_LOG//$'\n'/,})"
  fi
}

test_early_configuration_error_publishes_failure() {
  local name="early configuration error publishes failure"
  local status state
  prepare_test_environment

  run_backup "GDRIVE_BACKUP_TARGET=invalid"
  status=$?
  state="$(cat "$RUN_STATE_FILE" 2>/dev/null || true)"

  if [[ "$status" == "64" && "$state" == *$'status=failure\n'* && "$state" == *'exit_code=64'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status state=${state//$'\n'/,})"
  fi
}

test_existing_backup_is_skipped_not_successful() {
  local name="concurrent backup is skipped instead of reported successful"
  local status state
  prepare_test_environment

  FAKE_FLOCK_STATUS=1 run_backup
  status=$?
  state="$(cat "$RUN_STATE_FILE" 2>/dev/null || true)"

  if [[ "$status" == "0" && "$state" == *$'status=skipped\n'* &&
        "$state" == *$'reason=already_running\n'* && "$state" == *'exit_code=0'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status state=${state//$'\n'/,})"
  fi
}

test_state_is_versioned_and_identifies_the_process() {
  local name="run state is versioned and identifies its process"
  local state
  prepare_test_environment

  run_backup
  state="$(cat "$RUN_STATE_FILE" 2>/dev/null || true)"

  if [[ "$state" == *$'protocol=1\n'* && "$state" =~ (^|$'\n')pid=[0-9]+($|$'\n') ]]; then
    pass "$name"
  else
    fail "$name (state=${state//$'\n'/,})"
  fi
}

test_term_signal_publishes_cancellation() {
  local name="TERM publishes cancellation instead of failure"
  local backup_pid status state started_file
  prepare_test_environment
  started_file="$TEST_HOME/rclone-started"

  start_backup_async "$started_file"
  backup_pid="$ASYNC_BACKUP_PID"
  for _ in {1..60}; do
    [[ -e "$started_file" ]] && break
    /bin/sleep 0.05
  done
  kill -TERM "$backup_pid" 2>/dev/null || true
  wait "$backup_pid"
  status=$?
  state="$(cat "$RUN_STATE_FILE" 2>/dev/null || true)"

  if [[ "$status" == "143" && "$state" == *$'status=cancelled\n'* &&
        "$state" == *$'signal=TERM\n'* && "$state" == *'exit_code=143'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status state=${state//$'\n'/,})"
  fi
}

test_active_backup_publishes_running_summary() {
  local name="active backup publishes a durable running state"
  local backup_pid summary started_file
  prepare_test_environment
  started_file="$TEST_HOME/rclone-started"

  start_backup_async "$started_file"
  backup_pid="$ASYNC_BACKUP_PID"
  for _ in {1..60}; do
    [[ -e "$started_file" ]] && break
    /bin/sleep 0.05
  done
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"
  kill -TERM "$backup_pid" 2>/dev/null || true
  wait "$backup_pid" 2>/dev/null || true

  if [[ "$summary" == *$'status=running\n'* &&
        "$summary" == *"pid=$backup_pid"* &&
        "$summary" != *$'finished_at='* ]]; then
    pass "$name"
  else
    fail "$name (summary=${summary//$'\n'/,})"
  fi
}

test_locked_backup_publishes_running_before_remote_checks() {
  local name="locked backup publishes running state before slow remote checks"
  local backup_pid summary config_started_file
  prepare_test_environment
  config_started_file="$TEST_HOME/rclone-config-started"

  FAKE_RCLONE_CONFIG_STARTED_FILE="$config_started_file" \
    FAKE_RCLONE_CONFIG_SLEEP_SECONDS=3 \
    start_backup_async "$TEST_HOME/rclone-copy-started"
  backup_pid="$ASYNC_BACKUP_PID"
  for _ in {1..60}; do
    [[ -e "$config_started_file" ]] && break
    /bin/sleep 0.05
  done
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"
  kill -TERM "$backup_pid" 2>/dev/null || true
  wait "$backup_pid" 2>/dev/null || true

  if [[ "$summary" == *$'status=running\n'* && "$summary" == *"pid=$backup_pid"* ]]; then
    pass "$name"
  else
    fail "$name (summary=${summary//$'\n'/,})"
  fi
}

test_locked_backup_opens_progress_before_remote_checks() {
  local name="locked backup opens progress before slow remote checks"
  local backup_pid config_started_file
  prepare_test_environment
  config_started_file="$TEST_HOME/rclone-config-started"
  mkdir -p "$TEST_HOME/GDrive Backup Tiger.app"

  BACKUP_DISABLE_ANIMATION=0 \
    GDRIVE_BACKUP_ANIMATION_APP="$TEST_HOME/GDrive Backup Tiger.app" \
    FAKE_RCLONE_CONFIG_STARTED_FILE="$config_started_file" \
    FAKE_RCLONE_CONFIG_SLEEP_SECONDS=3 \
    start_backup_async "$TEST_HOME/rclone-copy-started"
  backup_pid="$ASYNC_BACKUP_PID"
  for _ in {1..60}; do
    [[ -e "$config_started_file" ]] && break
    /bin/sleep 0.05
  done
  local open_args=""
  open_args="$(cat "$OPEN_LOG" 2>/dev/null || true)"
  kill -TERM "$backup_pid" 2>/dev/null || true
  wait "$backup_pid" 2>/dev/null || true

  if [[ "$open_args" == *$'--args\n'* && "$open_args" == *"$RUN_STATE_FILE"* ]]; then
    pass "$name"
  else
    fail "$name (progress UI was not opened while preflight was running)"
  fi
}

test_nas_copy_uses_smb_safe_serial_writes() {
  local name="NAS copy disables concurrent and multi-thread destination writes"
  local args_file args
  prepare_test_environment
  args_file="$TEST_HOME/rclone-args"

  FAKE_RCLONE_ARGS_FILE="$args_file" run_backup
  args="$(cat "$args_file" 2>/dev/null || true)"

  if [[ "$args" == *$'--multi-thread-streams\n0\n'* &&
        "$args" == *$'--transfers\n1\n'* ]]; then
    pass "$name"
  else
    fail "$name (NAS safety flags missing)"
  fi
}

test_permission_failure_is_classified() {
  local name="destination permission failure is classified without persisting a path"
  local summary
  prepare_test_environment

  FAKE_RCLONE_COPY_STATUS=23 \
    FAKE_RCLONE_COPY_OUTPUT='ERROR : redacted: Failed to copy: mkdir redacted: permission denied' \
    run_backup
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"

  if [[ "$summary" == *$'status=failure\n'* &&
        "$summary" == *$'reason=destination_permission_denied\n'* &&
        "$summary" != *'redacted'* ]]; then
    pass "$name"
  else
    fail "$name (summary=${summary//$'\n'/,})"
  fi
}

test_source_permission_failure_stays_generic() {
  local name="source-side access failure is not mislabeled as a destination permission problem"
  local summary
  prepare_test_environment

  FAKE_RCLONE_COPY_STATUS=23 \
    FAKE_RCLONE_COPY_OUTPUT='ERROR : remote: Failed to open source object: access denied' \
    run_backup
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"

  if [[ "$summary" == *$'status=failure\n'* &&
        "$summary" != *$'reason=destination_permission_denied\n'* ]]; then
    pass "$name"
  else
    fail "$name (source failure was mislabeled)"
  fi
}

test_lost_nas_mount_is_classified_and_stops_followup_copies() {
  local name="lost NAS mount is classified and stops follow-up copies"
  local status summary args_file copy_count
  prepare_test_environment
  args_file="$TEST_HOME/rclone-args"

  FAKE_RCLONE_ARGS_FILE="$args_file" \
    FAKE_RCLONE_DISCONNECT_MOUNT="$NAS_MOUNT" \
    FAKE_RCLONE_COPY_STATUS=23 \
    run_backup
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"
  copy_count="$(/usr/bin/grep -c '^copy$' "$args_file" 2>/dev/null || true)"

  if [[ "$status" == "1" && "$summary" == *$'status=failure\n'* &&
        "$summary" == *$'reason=nas_connection_lost\n'* &&
        "$copy_count" == "1" ]]; then
    pass "$name"
  else
    fail "$name (exit=$status copies=$copy_count summary=${summary//$'\n'/,})"
  fi
}

test_confirmation_uses_injected_open_command() {
  local name="confirmation uses the testable open command"
  # This asserts literal shell source, so expansion would be a test bug.
  # shellcheck disable=SC2016
  if /usr/bin/grep -Fq 'if "$OPEN_BIN" -W -n "$ANIMATION_APP"' "$BACKUP_SCRIPT"; then
    pass "$name"
  else
    fail "$name"
  fi
}

test_declined_confirmation_is_skipped() {
  local name="declined destination confirmation is skipped without replacing backup history"
  local before after state status
  prepare_test_environment
  mkdir -p "$TEST_HOME/GDrive Backup Tiger.app"
  before=$'protocol=1\nstatus=success\npid=1\nstarted_at=1783790000\nfinished_at=1783790100\nexit_code=0\ntrigger=schedule\ntarget=nas\ndestination=/Volumes/Archive'
  printf '%s' "$before" >"$SUMMARY_STATE_FILE"
  chmod 600 "$SUMMARY_STATE_FILE"

  GDRIVE_BACKUP_CONFIRM=1 \
    FAKE_CONFIRM_DECISION=no \
    run_backup \
      "GDRIVE_BACKUP_ANIMATION_APP=$TEST_HOME/GDrive Backup Tiger.app" \
      "GDRIVE_BACKUP_OPEN_BIN=$FAKE_BIN/open"
  status=$?
  state="$(cat "$RUN_STATE_FILE" 2>/dev/null || true)"
  after="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"

  if [[ "$status" == "0" &&
        "$state" == *$'status=skipped\n'* &&
        "$state" == *$'reason=user_declined\n'* &&
        "$state" == *'exit_code=0'* &&
        "$after" == "$before" ]]; then
    pass "$name"
  else
    fail "$name (exit=$status state=${state//$'\n'/,})"
  fi
}

test_failed_ui_launch_cleans_internal_state() {
  local name="failed UI launch cleans its internal state"
  local status sentinel_path progress_path state_path
  prepare_test_environment

  mkdir -p "$TEST_HOME/GDrive Backup Tiger.app"
  BACKUP_DISABLE_ANIMATION=0 \
    GDRIVE_BACKUP_RUN_STATE_FILE='' \
    FAKE_OPEN_STATUS=1 \
    run_backup \
      "GDRIVE_BACKUP_ANIMATION_APP=$TEST_HOME/GDrive Backup Tiger.app" \
      "GDRIVE_BACKUP_OPEN_BIN=$FAKE_BIN/open"
  status=$?
  sentinel_path="$(sed -n '4p' "$OPEN_LOG" 2>/dev/null || true)"
  progress_path="$(sed -n '5p' "$OPEN_LOG" 2>/dev/null || true)"
  state_path="$(sed -n '6p' "$OPEN_LOG" 2>/dev/null || true)"

  if [[ "$status" == "0" && -n "$state_path" &&
        ! -e "$sentinel_path" && ! -e "$progress_path" && ! -e "$state_path" ]]; then
    pass "$name"
  else
    fail "$name (exit=$status sentinel=$sentinel_path progress=$progress_path state=$state_path)"
  fi
}

test_success_persists_private_summary() {
  local name="successful backup persists a private durable summary"
  local summary mode
  prepare_test_environment

  run_backup
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"
  mode="$(/usr/bin/stat -f '%Lp' "$SUMMARY_STATE_FILE" 2>/dev/null || true)"

  if [[ "$summary" == *$'protocol=1\n'* &&
        "$summary" == *$'status=success\n'* &&
        "$summary" =~ (^|$'\n')started_at=[0-9]+($|$'\n') &&
        "$summary" =~ (^|$'\n')finished_at=[0-9]+($|$'\n') &&
        "$summary" == *$'exit_code=0\n'* &&
        "$summary" == *$'trigger=manual\n'* &&
        "$summary" == *$'target=nas\n'* &&
        "$summary" == *"destination=$NAS_MOUNT/backup"* &&
        "$mode" == "600" ]]; then
    pass "$name"
  else
    fail "$name (mode=$mode summary=${summary//$'\n'/,})"
  fi
}

test_failure_persists_failed_summary() {
  local name="failed backup persists failure without claiming success"
  local status summary
  prepare_test_environment

  FAKE_RCLONE_COPY_STATUS=23 run_backup
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"

  if [[ "$status" == "1" && "$summary" == *$'status=failure\n'* &&
        "$summary" == *$'exit_code=1\n'* && "$summary" != *$'status=success\n'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status summary=${summary//$'\n'/,})"
  fi
}

test_concurrent_start_preserves_previous_summary() {
  local name="concurrent skipped start preserves the actual backup summary"
  local before after
  prepare_test_environment
  before=$'protocol=1\nstatus=running\npid=1\nstarted_at=1783790000\ntrigger=schedule\ntarget=nas\ndestination=/Volumes/Archive'
  printf '%s' "$before" >"$SUMMARY_STATE_FILE"
  chmod 600 "$SUMMARY_STATE_FILE"

  FAKE_FLOCK_STATUS=1 run_backup
  after="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"

  if [[ "$after" == "$before" ]]; then
    pass "$name"
  else
    fail "$name (summary was overwritten: ${after//$'\n'/,})"
  fi
}

test_failed_backup_publishes_failure
test_successful_backup_publishes_success
test_animation_receives_run_state_file
test_manual_progress_requests_foreground_activation
test_early_configuration_error_publishes_failure
test_existing_backup_is_skipped_not_successful
test_state_is_versioned_and_identifies_the_process
test_active_backup_publishes_running_summary
test_locked_backup_publishes_running_before_remote_checks
test_locked_backup_opens_progress_before_remote_checks
test_nas_copy_uses_smb_safe_serial_writes
test_permission_failure_is_classified
test_source_permission_failure_stays_generic
test_lost_nas_mount_is_classified_and_stops_followup_copies
test_confirmation_uses_injected_open_command
test_declined_confirmation_is_skipped
test_term_signal_publishes_cancellation
test_failed_ui_launch_cleans_internal_state
test_success_persists_private_summary
test_failure_persists_failed_summary
test_concurrent_start_preserves_previous_summary
test_paused_automatic_run_is_silent_and_preserves_history

if (( failures > 0 )); then
  printf '%s backup outcome test(s) failed.\n' "$failures"
  exit 1
fi

printf '%s\n' 'All backup outcome tests passed.'
