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
  TEMP_TRASH_DIR="$TEST_HOME/temp-trash"
  mkdir -p "$FAKE_BIN" "$NAS_MOUNT" "$TEMP_TRASH_DIR"

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
  backend)
    if [[ " $* " == *" drives "* ]]; then
      printf '%s\n' "${FAKE_RCLONE_DRIVES_JSON:-[]}"
      exit 0
    fi
    if [[ " $* " == *" query "* ]]; then
      if [[ -n "${FAKE_RCLONE_ARGS_FILE:-}" ]]; then
        printf '%s\n' "$@" >>"$FAKE_RCLONE_ARGS_FILE"
      fi
      if [[ -n "${FAKE_RCLONE_QUERY_STDERR:-}" ]]; then
        printf '%s\n' "$FAKE_RCLONE_QUERY_STDERR" >&2
      fi
      if [[ -n "${FAKE_RCLONE_QUERY_MATCH_1:-}" &&
            "${4:-}" == "$FAKE_RCLONE_QUERY_MATCH_1" ]]; then
        printf '%s\n' "${FAKE_RCLONE_QUERY_JSON_1:-[]}"
        exit "${FAKE_RCLONE_COLLISION_QUERY_STATUS:-0}"
      fi
      if [[ -n "${FAKE_RCLONE_QUERY_MATCH_2:-}" &&
            "${4:-}" == "$FAKE_RCLONE_QUERY_MATCH_2" ]]; then
        printf '%s\n' "${FAKE_RCLONE_QUERY_JSON_2:-[]}"
        exit "${FAKE_RCLONE_COLLISION_QUERY_STATUS:-0}"
      fi
      if [[ -n "${FAKE_RCLONE_QUERY_MATCH_3:-}" &&
            "${4:-}" == "$FAKE_RCLONE_QUERY_MATCH_3" ]]; then
        printf '%s\n' "${FAKE_RCLONE_QUERY_JSON_3:-[]}"
        exit "${FAKE_RCLONE_COLLISION_QUERY_STATUS:-0}"
      fi
      if [[ -n "${FAKE_RCLONE_QUERY_MATCH_4:-}" &&
            "${4:-}" == "$FAKE_RCLONE_QUERY_MATCH_4" ]]; then
        printf '%s\n' "${FAKE_RCLONE_QUERY_JSON_4:-[]}"
        exit "${FAKE_RCLONE_COLLISION_QUERY_STATUS:-0}"
      fi
      printf '%s\n' "${FAKE_RCLONE_COLLISION_QUERY_JSON:-[]}"
      exit "${FAKE_RCLONE_COLLISION_QUERY_STATUS:-0}"
    fi
    if [[ " $* " == *" copyid "* ]]; then
      if [[ -n "${FAKE_RCLONE_ARGS_FILE:-}" ]]; then
        printf '%s\n' "$@" >>"$FAKE_RCLONE_ARGS_FILE"
      fi
      if [[ "${FAKE_RCLONE_ARCHIVE_STATUS:-0}" == "0" &&
            "${FAKE_RCLONE_ARCHIVE_DRY_OUTPUT:-0}" != "1" ]]; then
        if [[ "${FAKE_RCLONE_REJECT_SHARED_FOR_ID:-0}" == "1" &&
              " $* " == *" --drive-shared-with-me "* ]]; then
          exit 88
        fi
        mkdir -p "${5:-}"
        : >"${5:-}/${FAKE_RCLONE_ARCHIVE_FILE_NAME:-image.heic}"
      fi
      exit "${FAKE_RCLONE_ARCHIVE_STATUS:-0}"
    fi
    printf '[]\n'
    exit 0
    ;;
  lsjson)
    printf '%s\n' "${FAKE_RCLONE_PARENT_JSON:-{\"ID\":\"parent-id\",\"IsDir\":true}}"
    exit "${FAKE_RCLONE_PARENT_STATUS:-0}"
    ;;
  copy)
    if [[ "${2:-}" == "--help" ]]; then
      if [[ "${FAKE_RCLONE_SUPPORTS_NAME_TRANSFORM:-1}" == "1" ]]; then
        printf '%s\n' '      --name-transform stringArray   Transform paths during the copy process'
      fi
      exit 0
    fi
    if [[ -n "${FAKE_RCLONE_ARGS_FILE:-}" ]]; then
      printf '%s\n' "$@" >>"$FAKE_RCLONE_ARGS_FILE"
    fi
    if [[ " $* " == *" --drive-root-folder-id "* &&
          "${FAKE_RCLONE_ARCHIVE_CREATE_FOLDER:-1}" == "1" &&
          "${FAKE_RCLONE_ARCHIVE_STATUS:-0}" == "0" ]]; then
      mkdir -p "${3:-}"
    fi
    previous=""
    for argument in "$@"; do
      if [[ "$previous" == "--combined" ]]; then
        printf '= verified\n' >"$argument"
      fi
      previous="$argument"
    done
    if [[ -n "${FAKE_RCLONE_COPY_OUTPUT:-}" &&
          " $* " != *" --drive-root-folder-id "* ]]; then
      if [[ "${FAKE_RCLONE_COPY_OUTPUT_SHARED_ONLY:-0}" != "1" ||
            " $* " == *" --drive-shared-with-me "* ]] &&
         [[ "${FAKE_RCLONE_COPY_OUTPUT_TEAM_DRIVE_ONLY:-0}" != "1" ||
            " $* " == *" --drive-team-drive "* ]]; then
        printf '%s\n' "$FAKE_RCLONE_COPY_OUTPUT"
      fi
    fi
    if [[ "${FAKE_RCLONE_REJECT_SHARED_FOR_ID:-0}" == "1" &&
          " $* " == *" --drive-root-folder-id "* &&
          " $* " == *" --drive-shared-with-me "* ]]; then
      exit 88
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
if [[ "${FAKE_JQ_USE_SYSTEM:-0}" == "1" ]]; then
  exec /usr/bin/jq "$@"
fi
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
  response_path="${!#}"
  if [[ "$response_path" == "--foreground" ]]; then
    response_path="${@: -2:1}"
  fi
  printf '%s\n' "$FAKE_CONFIRM_DECISION" >"$response_path"
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

  cat >"$FAKE_BIN/cmp" <<'SH'
#!/bin/bash
if [[ -n "${FAKE_CMP_CALLS_FILE:-}" ]]; then
  printf 'call\n' >>"$FAKE_CMP_CALLS_FILE"
fi
sequence="${FAKE_CMP_STATUS_SEQUENCE:-real}"
if [[ "$sequence" != "real" ]]; then
  IFS=',' read -r -a statuses <<<"$sequence"
  call_number="$(wc -l <"${FAKE_CMP_CALLS_FILE:?}")"
  index=$((call_number - 1))
  if (( index >= ${#statuses[@]} )); then
    index=$((${#statuses[@]} - 1))
  fi
  cmp_status="${statuses[$index]}"
  if [[ "$cmp_status" != "0" ]]; then
    exit "$cmp_status"
  fi
fi
exec /usr/bin/cmp "$@"
SH

  cat >"$FAKE_BIN/trash" <<'SH'
#!/bin/bash
: "${FAKE_TEMP_TRASH_DIR:?}"
for path in "$@"; do
  [[ -e "$path" || -L "$path" ]] || continue
  item_dir="$(mktemp -d "$FAKE_TEMP_TRASH_DIR/item.XXXXXX")" || exit 1
  /bin/mv "$path" "$item_dir/original" || exit 1
done
SH

  local tool
  for tool in diskutil plutil; do
    cat >"$FAKE_BIN/$tool" <<'SH'
#!/bin/bash
exit 0
SH
  done
  chmod +x "$FAKE_BIN/rclone" "$FAKE_BIN/jq" "$FAKE_BIN/open" "$FAKE_BIN/flock" \
    "$FAKE_BIN/mount" "$FAKE_BIN/cmp" "$FAKE_BIN/trash" \
    "$FAKE_BIN/diskutil" "$FAKE_BIN/plutil"
}

run_backup_with_mode() {
  local mode="$1"
  shift
  env \
    HOME="$TEST_HOME" \
    GDRIVE_BACKUP_PATH="$FAKE_BIN:/usr/bin:/bin:/usr/sbin:/sbin" \
    MOUNT_SETTLE_SECONDS=0 \
    GDRIVE_BACKUP_TARGET=nas \
    GDRIVE_BACKUP_NAS_MOUNT="$NAS_MOUNT" \
    GDRIVE_BACKUP_MOUNT_BIN="$FAKE_BIN/mount" \
    GDRIVE_BACKUP_CMP_BIN="$FAKE_BIN/cmp" \
    GDRIVE_BACKUP_DEST_ROOT="$NAS_MOUNT/backup" \
    GDRIVE_BACKUP_CONFIRM="${GDRIVE_BACKUP_CONFIRM:-0}" \
    GDRIVE_BACKUP_LOCK="$TEST_HOME/backup.lock" \
    GDRIVE_BACKUP_VERSIONING=0 \
    GDRIVE_BACKUP_RETENTION=0 \
    GDRIVE_BACKUP_RUN_STATE_FILE="${GDRIVE_BACKUP_RUN_STATE_FILE-$RUN_STATE_FILE}" \
    GDRIVE_BACKUP_SUMMARY_STATE_FILE="$SUMMARY_STATE_FILE" \
    GDRIVE_BACKUP_TEMP_TRASH_BIN="$FAKE_BIN/trash" \
    BACKUP_DISABLE_ANIMATION="${BACKUP_DISABLE_ANIMATION:-1}" \
    FAKE_RCLONE_COPY_STATUS="${FAKE_RCLONE_COPY_STATUS:-0}" \
    FAKE_RCLONE_COPY_OUTPUT="${FAKE_RCLONE_COPY_OUTPUT:-}" \
    FAKE_RCLONE_DRIVES_JSON="${FAKE_RCLONE_DRIVES_JSON:-[]}" \
    FAKE_RCLONE_SUPPORTS_NAME_TRANSFORM="${FAKE_RCLONE_SUPPORTS_NAME_TRANSFORM:-1}" \
    FAKE_RCLONE_COLLISION_QUERY_JSON="${FAKE_RCLONE_COLLISION_QUERY_JSON:-[]}" \
    FAKE_RCLONE_COLLISION_QUERY_STATUS="${FAKE_RCLONE_COLLISION_QUERY_STATUS:-0}" \
    FAKE_RCLONE_QUERY_STDERR="${FAKE_RCLONE_QUERY_STDERR:-}" \
    FAKE_RCLONE_QUERY_MATCH_1="${FAKE_RCLONE_QUERY_MATCH_1:-}" \
    FAKE_RCLONE_QUERY_JSON_1="${FAKE_RCLONE_QUERY_JSON_1:-}" \
    FAKE_RCLONE_QUERY_MATCH_2="${FAKE_RCLONE_QUERY_MATCH_2:-}" \
    FAKE_RCLONE_QUERY_JSON_2="${FAKE_RCLONE_QUERY_JSON_2:-}" \
    FAKE_RCLONE_QUERY_MATCH_3="${FAKE_RCLONE_QUERY_MATCH_3:-}" \
    FAKE_RCLONE_QUERY_JSON_3="${FAKE_RCLONE_QUERY_JSON_3:-}" \
    FAKE_RCLONE_QUERY_MATCH_4="${FAKE_RCLONE_QUERY_MATCH_4:-}" \
    FAKE_RCLONE_QUERY_JSON_4="${FAKE_RCLONE_QUERY_JSON_4:-}" \
    FAKE_RCLONE_PARENT_JSON="${FAKE_RCLONE_PARENT_JSON:-}" \
    FAKE_RCLONE_PARENT_STATUS="${FAKE_RCLONE_PARENT_STATUS:-0}" \
    FAKE_RCLONE_ARCHIVE_STATUS="${FAKE_RCLONE_ARCHIVE_STATUS:-0}" \
    FAKE_RCLONE_ARCHIVE_CREATE_FOLDER="${FAKE_RCLONE_ARCHIVE_CREATE_FOLDER:-1}" \
    FAKE_RCLONE_ARCHIVE_FILE_NAME="${FAKE_RCLONE_ARCHIVE_FILE_NAME:-image.heic}" \
    FAKE_RCLONE_REJECT_SHARED_FOR_ID="${FAKE_RCLONE_REJECT_SHARED_FOR_ID:-0}" \
    FAKE_RCLONE_COPY_OUTPUT_SHARED_ONLY="${FAKE_RCLONE_COPY_OUTPUT_SHARED_ONLY:-0}" \
    FAKE_RCLONE_COPY_OUTPUT_TEAM_DRIVE_ONLY="${FAKE_RCLONE_COPY_OUTPUT_TEAM_DRIVE_ONLY:-0}" \
    FAKE_JQ_USE_SYSTEM="${FAKE_JQ_USE_SYSTEM:-0}" \
    FAKE_RCLONE_ARGS_FILE="${FAKE_RCLONE_ARGS_FILE:-}" \
    FAKE_RCLONE_SLEEP_SECONDS="${FAKE_RCLONE_SLEEP_SECONDS:-0}" \
    FAKE_RCLONE_STARTED_FILE="${FAKE_RCLONE_STARTED_FILE:-}" \
    FAKE_RCLONE_DISCONNECT_MOUNT="${FAKE_RCLONE_DISCONNECT_MOUNT:-}" \
    FAKE_RCLONE_CONFIG_STARTED_FILE="${FAKE_RCLONE_CONFIG_STARTED_FILE:-}" \
    FAKE_RCLONE_CONFIG_SLEEP_SECONDS="${FAKE_RCLONE_CONFIG_SLEEP_SECONDS:-0}" \
    FAKE_CMP_STATUS_SEQUENCE="${FAKE_CMP_STATUS_SEQUENCE:-real}" \
    FAKE_CMP_CALLS_FILE="${FAKE_CMP_CALLS_FILE:-}" \
    FAKE_FLOCK_STATUS="${FAKE_FLOCK_STATUS:-0}" \
    FAKE_NAS_MOUNT="$NAS_MOUNT" \
    FAKE_TEMP_TRASH_DIR="$TEMP_TRASH_DIR" \
    FAKE_OPEN_LOG="$OPEN_LOG" \
    FAKE_OPEN_STATUS="${FAKE_OPEN_STATUS:-0}" \
    FAKE_CONFIRM_DECISION="${FAKE_CONFIRM_DECISION:-}" \
    RCLONE_REMOTE=tdd-remote \
    "$@" \
    "$BACKUP_SCRIPT" "$mode"
}

run_backup() {
  run_backup_with_mode --run "$@"
}

run_dry_backup() {
  run_backup_with_mode --dry-run
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
    GDRIVE_BACKUP_TEMP_TRASH_BIN="$FAKE_BIN/trash" \
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
    FAKE_TEMP_TRASH_DIR="$TEMP_TRASH_DIR" \
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
      "GDRIVE_BACKUP_OPEN_BIN=$FAKE_BIN/open" \
      "BACKUP_PROGRESS_FOREGROUND=1"
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
  local name="explicit progress request keeps one reopenable Dock window"
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

test_automatic_backup_does_not_open_progress_ui() {
  local name="automatic backup stays headless while publishing its status"
  local status summary open_args
  prepare_test_environment

  mkdir -p "$TEST_HOME/GDrive Backup Tiger.app"
  BACKUP_DISABLE_ANIMATION=0 \
    run_backup \
      "GDRIVE_BACKUP_TRIGGER=schedule" \
      "GDRIVE_BACKUP_ANIMATION_APP=$TEST_HOME/GDrive Backup Tiger.app" \
      "GDRIVE_BACKUP_OPEN_BIN=$FAKE_BIN/open"
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"
  open_args="$(cat "$OPEN_LOG" 2>/dev/null || true)"

  if [[ "$status" == "0" && -z "$open_args" && "$summary" == *$'status=success\n'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status open=${open_args//$'\n'/,} summary=${summary//$'\n'/,})"
  fi
}

test_visible_manual_confirmation_requests_foreground() {
  local name="visible manual confirmation is the only foreground prompt"
  local status open_args
  prepare_test_environment

  mkdir -p "$TEST_HOME/GDrive Backup Tiger.app"
  BACKUP_DISABLE_ANIMATION=1 \
    GDRIVE_BACKUP_CONFIRM=1 \
    FAKE_CONFIRM_DECISION=yes \
    run_backup \
      "GDRIVE_BACKUP_ANIMATION_APP=$TEST_HOME/GDrive Backup Tiger.app" \
      "GDRIVE_BACKUP_OPEN_BIN=$FAKE_BIN/open" \
      "BACKUP_PROGRESS_FOREGROUND=1"
  status=$?
  open_args="$(cat "$OPEN_LOG" 2>/dev/null || true)"

  if [[ "$status" == "0" ]] &&
      grep -Fxq -- '--confirm' "$OPEN_LOG" &&
      grep -Fxq -- '--foreground' "$OPEN_LOG"; then
    pass "$name"
  else
    fail "$name (exit=$status open=${open_args//$'\n'/,})"
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
    BACKUP_PROGRESS_FOREGROUND=1 \
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

test_nas_copy_uses_reversible_dot_bin_codec() {
  local name="NAS copy preserves vetoed .bin directories with a reversible codec"
  local args_file manifest escape_line first_dot_bin_line last_dot_bin_line dot_bin_count
  prepare_test_environment
  args_file="$TEST_HOME/rclone-args"

  FAKE_RCLONE_ARGS_FILE="$args_file" run_backup
  manifest="$(cat "$NAS_MOUNT/backup/.gdrive-name-codec" 2>/dev/null || true)"
  # The literal ${1} is part of rclone's replacement syntax.
  # shellcheck disable=SC2016
  escape_line="$(grep -nFx -- 'all,regex=(?i)^(__gdt0__.*)$/__gdt0__${1}' \
    "$args_file" 2>/dev/null | head -n 1 | cut -d: -f1)"
  first_dot_bin_line="$(grep -nFx -- 'dir,regex=^\.bin$/__gdt0__dotbin_000' \
    "$args_file" 2>/dev/null | head -n 1 | cut -d: -f1)"
  last_dot_bin_line="$(grep -nFx -- 'dir,regex=^\.BIN$/__gdt0__dotbin_111' \
    "$args_file" 2>/dev/null | head -n 1 | cut -d: -f1)"
  dot_bin_count="$(grep -Fc 'dir,regex=^\.' \
    "$args_file" 2>/dev/null || true)"

  if [[ "$escape_line" =~ ^[0-9]+$ && "$first_dot_bin_line" =~ ^[0-9]+$ &&
        "$last_dot_bin_line" =~ ^[0-9]+$ && "$dot_bin_count" == "16" &&
        "$escape_line" -lt "$first_dot_bin_line" &&
        "$first_dot_bin_line" -lt "$last_dot_bin_line" &&
        "$manifest" == *$'protocol=1\n'* &&
        "$manifest" == *$'codec=nas-path-v1\n'* &&
        "$manifest" == *$'prefix=__gdt0__\n'* &&
        "$manifest" == *$'dot_bin_prefix=__gdt0__dotbin_\n'* &&
        "$manifest" == *$'current_layers=1\n'* &&
        "$manifest" == *$'version_layers=2' ]]; then
    pass "$name"
  else
    fail "$name (escape=$escape_line first=$first_dot_bin_line last=$last_dot_bin_line count=$dot_bin_count manifest=${manifest//$'\n'/,})"
  fi
}

test_nas_codec_dry_run_does_not_create_manifest() {
  local name="NAS codec dry-run reports transformed work without writing its manifest"
  local args_file status
  prepare_test_environment
  args_file="$TEST_HOME/rclone-args"

  FAKE_RCLONE_ARGS_FILE="$args_file" run_dry_backup
  status=$?

  if [[ "$status" == "0" &&
        ! -e "$NAS_MOUNT/backup/.gdrive-name-codec" &&
        "$(cat "$args_file" 2>/dev/null || true)" == *$'--dry-run\n'* &&
        "$(cat "$args_file" 2>/dev/null || true)" == \
          *$'all,regex=(?i)^(__gdt0__.*)$/__gdt0__${1}\n'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status manifest=$([[ -e "$NAS_MOUNT/backup/.gdrive-name-codec" ]] && printf yes || printf no))"
  fi
}

test_nas_codec_rejects_unsupported_rclone() {
  local name="NAS codec fails closed when rclone lacks name transforms"
  local status summary
  prepare_test_environment

  FAKE_RCLONE_SUPPORTS_NAME_TRANSFORM=0 run_backup
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"

  if [[ "$status" == "69" &&
        "$summary" == *$'status=failure\n'* &&
        "$summary" == *$'reason=unsupported_rclone\n'* &&
        ! -e "$NAS_MOUNT/backup/.gdrive-name-codec" ]]; then
    pass "$name"
  else
    fail "$name (exit=$status summary=${summary//$'\n'/,})"
  fi
}

test_nas_codec_rejects_malformed_manifest() {
  local name="NAS codec rejects a manifest missing its terminating newline"
  local status summary
  prepare_test_environment
  mkdir -p "$NAS_MOUNT/backup"
  printf '%s' $'protocol=1\ncodec=nas-path-v1\nprefix=__gdt0__\n'\
$'dot_bin_prefix=__gdt0__dotbin_\ncurrent_layers=1\nversion_layers=2' \
    >"$NAS_MOUNT/backup/.gdrive-name-codec"

  run_backup
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"

  if [[ "$status" == "69" &&
        "$summary" == *$'reason=invalid_name_codec\n'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status summary=${summary//$'\n'/,})"
  fi
}

write_valid_nas_codec_manifest() {
  mkdir -p "$NAS_MOUNT/backup"
  printf '%s\n' \
    'protocol=1' \
    'codec=nas-path-v1' \
    'prefix=__gdt0__' \
    'dot_bin_prefix=__gdt0__dotbin_' \
    'current_layers=1' \
    'version_layers=2' \
    >"$NAS_MOUNT/backup/.gdrive-name-codec"
}

test_nas_codec_retries_transient_manifest_read_errors() {
  local name="NAS codec retries transient manifest read errors"
  local calls_file status calls
  prepare_test_environment
  write_valid_nas_codec_manifest
  calls_file="$TEST_HOME/cmp-calls"

  FAKE_CMP_STATUS_SEQUENCE='2,2,0' \
    FAKE_CMP_CALLS_FILE="$calls_file" \
    run_backup
  status=$?
  calls="$(/usr/bin/awk 'END { print NR + 0 }' "$calls_file" 2>/dev/null)"

  if [[ "$status" == "0" && "$calls" == "3" ]]; then
    pass "$name"
  else
    fail "$name (exit=$status calls=$calls)"
  fi
}

test_nas_codec_classifies_persistent_manifest_read_errors() {
  local name="NAS codec distinguishes unreadable manifests from invalid content"
  local calls_file status calls summary manifest_before manifest_after
  prepare_test_environment
  write_valid_nas_codec_manifest
  calls_file="$TEST_HOME/cmp-calls"
  manifest_before="$(/usr/bin/shasum -a 256 \
    "$NAS_MOUNT/backup/.gdrive-name-codec" | /usr/bin/awk '{print $1}')"

  FAKE_CMP_STATUS_SEQUENCE='2,2,2' \
  FAKE_CMP_CALLS_FILE="$calls_file" \
    run_backup
  status=$?
  calls="$(/usr/bin/awk 'END { print NR + 0 }' "$calls_file" 2>/dev/null)"
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"
  manifest_after="$(/usr/bin/shasum -a 256 \
    "$NAS_MOUNT/backup/.gdrive-name-codec" | /usr/bin/awk '{print $1}')"

  if [[ "$status" == "69" &&
        "$calls" == "3" &&
        "$summary" == *$'reason=destination_unreadable\n'* &&
        "$manifest_before" == "$manifest_after" ]]; then
    pass "$name"
  else
    fail "$name (exit=$status calls=$calls summary=${summary//$'\n'/,})"
  fi
}

test_nas_codec_rejects_nonregular_manifest() {
  local name="NAS codec rejects a nonregular manifest"
  local status summary
  prepare_test_environment
  mkdir -p "$NAS_MOUNT/backup/.gdrive-name-codec"

  run_backup
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"

  if [[ "$status" == "69" &&
        "$summary" == *$'reason=invalid_name_codec\n'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status summary=${summary//$'\n'/,})"
  fi
}

test_nas_codec_rejects_ambiguous_legacy_names() {
  local name="NAS codec rejects preexisting .bin and reserved names below copy roots"
  local status summary
  prepare_test_environment
  mkdir -p "$NAS_MOUNT/backup/My Drive/project/.BIN"
  printf '%s\n' legacy >"$NAS_MOUNT/backup/My Drive/__GDT0__legacy-file"

  run_backup
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"

  if [[ "$status" == "69" &&
        "$summary" == *$'reason=name_codec_collision\n'* &&
        ! -e "$NAS_MOUNT/backup/.gdrive-name-codec" ]]; then
    pass "$name"
  else
    fail "$name (exit=$status summary=${summary//$'\n'/,})"
  fi
}

test_nas_codec_keeps_shared_drive_destination_raw() {
  local name="NAS codec permits a reserved-looking raw Shared Drive destination"
  local status
  prepare_test_environment
  mkdir -p "$NAS_MOUNT/backup/Shared Drives/__GDT0__Team (drive-1)"

  run_backup
  status=$?

  if [[ "$status" == "0" &&
        -f "$NAS_MOUNT/backup/.gdrive-name-codec" ]]; then
    pass "$name"
  else
    fail "$name (exit=$status)"
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

test_duplicate_source_file_fails_closed() {
  local name="ignored duplicate Drive file cannot be reported as a successful backup"
  local status summary
  prepare_test_environment

  FAKE_RCLONE_COPY_OUTPUT='NOTICE: image.heic: Duplicate object found in source - ignoring' \
    run_backup
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"

  if [[ "$status" == "1" &&
        "$summary" == *$'status=failure\n'* &&
        "$summary" == *$'reason=source_name_collision\n'* &&
        "$summary" != *$'last_success_at='* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status summary=${summary//$'\n'/,})"
  fi
}

test_duplicate_source_directory_fails_closed() {
  local name="ignored duplicate Drive directory cannot be reported as a successful backup"
  local status summary
  prepare_test_environment

  FAKE_RCLONE_COPY_OUTPUT='NOTICE: EventOS-Backups: Duplicate directory found in source - ignoring' \
    run_backup
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"

  if [[ "$status" == "1" &&
        "$summary" == *$'status=failure\n'* &&
        "$summary" == *$'reason=source_name_collision\n'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status summary=${summary//$'\n'/,})"
  fi
}

test_duplicate_source_files_are_archived_by_id() {
  local name="duplicate Drive files are preserved in an ID-addressed collision archive"
  local status summary args_file manifest_count
  prepare_test_environment
  args_file="$TEST_HOME/rclone-args"

  FAKE_RCLONE_ARGS_FILE="$args_file" \
    FAKE_RCLONE_COPY_OUTPUT='NOTICE: Photos/image.heic: Duplicate object found in source - ignoring' \
    FAKE_RCLONE_QUERY_MATCH_1="'root' in parents and name = 'Photos' and mimeType = 'application/vnd.google-apps.folder' and trashed = false" \
    FAKE_RCLONE_QUERY_JSON_1='[
      {"id":"parent-id","name":"Photos","mimeType":"application/vnd.google-apps.folder","parents":["root-id"]}
    ]' \
    FAKE_RCLONE_QUERY_MATCH_4="sharedWithMe = true and name = 'Photos' and mimeType = 'application/vnd.google-apps.folder' and trashed = false" \
    FAKE_RCLONE_QUERY_JSON_4='[
      {"id":"parent-id","name":"Photos","mimeType":"application/vnd.google-apps.folder"}
    ]' \
    FAKE_RCLONE_COLLISION_QUERY_JSON='[
      {"id":"file-id-a","name":"image.heic","mimeType":"image/heic","parents":["parent-id"]},
      {"id":"file-id-b","name":"image.heic","mimeType":"image/heic","parents":["parent-id"]}
    ]' \
    run_backup
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"
  manifest_count="$(find "$NAS_MOUNT/backup/.gdrive-collisions" \
    -name '*.json' -type f 2>/dev/null | wc -l | tr -d ' ')"

  if [[ "$status" == "0" &&
        "$summary" == *$'status=success\n'* &&
        "$manifest_count" == "2" &&
        "$(grep -cFx 'copyid' "$args_file" 2>/dev/null || true)" == "4" &&
        "$(cat "$args_file" 2>/dev/null || true)" == *$'file-id-a\n'* &&
        "$(cat "$args_file" 2>/dev/null || true)" == *$'file-id-b\n'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status manifests=$manifest_count summary=${summary//$'\n'/,})"
  fi
}

test_duplicate_source_directories_are_archived_by_id() {
  local name="duplicate Drive directories are preserved under separate ID roots"
  local status summary args_file root_copy_count
  prepare_test_environment
  args_file="$TEST_HOME/rclone-args"

  FAKE_RCLONE_ARGS_FILE="$args_file" \
    FAKE_RCLONE_COPY_OUTPUT='NOTICE: EventOS-Backups: Duplicate directory found in source - ignoring' \
    FAKE_RCLONE_COLLISION_QUERY_JSON='[
      {"id":"folder-id-a","name":"EventOS-Backups","mimeType":"application/vnd.google-apps.folder","parents":["parent-id"]},
      {"id":"folder-id-b","name":"EventOS-Backups","mimeType":"application/vnd.google-apps.folder","parents":["parent-id"]}
    ]' \
    run_backup
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"
  root_copy_count="$(grep -cFx -- '--drive-root-folder-id' "$args_file" 2>/dev/null || true)"

  if [[ "$status" == "0" &&
        "$summary" == *$'status=success\n'* &&
        "$root_copy_count" == "8" &&
        "$(cat "$args_file" 2>/dev/null || true)" == *$'folder-id-a\n'* &&
        "$(cat "$args_file" 2>/dev/null || true)" == *$'folder-id-b\n'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status root-copies=$root_copy_count summary=${summary//$'\n'/,})"
  fi
}

test_root_duplicate_uses_drive_root_query() {
  local name="root-level Drive duplicates use the provider root query"
  local status summary args_file
  prepare_test_environment
  args_file="$TEST_HOME/rclone-args"

  FAKE_RCLONE_ARGS_FILE="$args_file" \
    FAKE_RCLONE_PARENT_JSON='{"Path":"","Name":"","IsDir":true}' \
    FAKE_RCLONE_COPY_OUTPUT='NOTICE: EventOS-Backups: Duplicate directory found in source - ignoring' \
    FAKE_RCLONE_COLLISION_QUERY_JSON='[
      {"id":"folder-id-a","name":"EventOS-Backups","mimeType":"application/vnd.google-apps.folder","parents":["actual-root-id"]},
      {"id":"folder-id-b","name":"EventOS-Backups","mimeType":"application/vnd.google-apps.folder","parents":["actual-root-id"]}
    ]' \
    run_backup
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"

  if [[ "$status" == "0" &&
        "$summary" == *$'status=success\n'* &&
        "$(grep -cFx -- "'root' in parents and trashed = false" \
          "$args_file" 2>/dev/null || true)" -ge 1 ]]; then
    pass "$name"
  else
    fail "$name (exit=$status summary=${summary//$'\n'/,})"
  fi
}

test_nested_duplicate_resolves_each_parent_by_drive_id() {
  local name="nested Drive duplicate resolves every parent component by ID"
  local status summary args_file args
  prepare_test_environment
  args_file="$TEST_HOME/rclone-args"

  FAKE_RCLONE_ARGS_FILE="$args_file" \
    FAKE_RCLONE_PARENT_JSON='{"Path":"","Name":"","IsDir":true}' \
    FAKE_RCLONE_COPY_OUTPUT='NOTICE: Top/Middle/Photos/image.heic: Duplicate object found in source - ignoring' \
    FAKE_RCLONE_QUERY_MATCH_1="'root' in parents and name = 'Top' and mimeType = 'application/vnd.google-apps.folder' and trashed = false" \
    FAKE_RCLONE_QUERY_JSON_1='[
      {"id":"folder-id-a","name":"Top","mimeType":"application/vnd.google-apps.folder","parents":["root-id"]}
    ]' \
    FAKE_RCLONE_QUERY_MATCH_2="'folder-id-a' in parents and name = 'Middle' and mimeType = 'application/vnd.google-apps.folder' and trashed = false" \
    FAKE_RCLONE_QUERY_JSON_2='[
      {"id":"folder-id-b","name":"Middle","mimeType":"application/vnd.google-apps.folder","parents":["folder-id-a"]}
    ]' \
    FAKE_RCLONE_QUERY_MATCH_3="'folder-id-b' in parents and name = 'Photos' and mimeType = 'application/vnd.google-apps.folder' and trashed = false" \
    FAKE_RCLONE_QUERY_JSON_3='[
      {"id":"folder-id-c","name":"Photos","mimeType":"application/vnd.google-apps.folder","parents":["folder-id-b"]}
    ]' \
    FAKE_RCLONE_QUERY_MATCH_4="sharedWithMe = true and name = 'Top' and mimeType = 'application/vnd.google-apps.folder' and trashed = false" \
    FAKE_RCLONE_QUERY_JSON_4='[
      {"id":"folder-id-a","name":"Top","mimeType":"application/vnd.google-apps.folder"}
    ]' \
    FAKE_RCLONE_COLLISION_QUERY_JSON='[
      {"id":"file-id-a","name":"image.heic","mimeType":"image/heic","parents":["folder-id-c"]},
      {"id":"file-id-b","name":"image.heic","mimeType":"image/heic","parents":["folder-id-c"]}
    ]' \
    run_backup
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"
  args="$(cat "$args_file" 2>/dev/null || true)"

  if [[ "$status" == "0" &&
        "$summary" == *$'status=success\n'* &&
        "$args" == *$'file-id-a\n'* &&
        "$args" == *$'file-id-b\n'* &&
        "$args" == *$'folder-id-c\x27 in parents and trashed = false\n'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status summary=${summary//$'\n'/,})"
  fi
}

test_parent_folder_query_escapes_drive_literals() {
  local name="parent folder query escapes apostrophes and backslashes"
  local status summary args_file args component expected_query folder_json
  prepare_test_environment
  args_file="$TEST_HOME/rclone-args"
  component="Client's\\Files"
  expected_query="sharedWithMe = true and name = 'Client\\'s\\\\Files' and mimeType = 'application/vnd.google-apps.folder' and trashed = false"
  folder_json="$(/usr/bin/jq -cn \
    --arg name "$component" \
    '[{id:"parent-id", name:$name, mimeType:"application/vnd.google-apps.folder"}]')"

  FAKE_RCLONE_ARGS_FILE="$args_file" \
    FAKE_RCLONE_COPY_OUTPUT_SHARED_ONLY=1 \
    FAKE_RCLONE_COPY_OUTPUT="NOTICE: $component/image.heic: Duplicate object found in source - ignoring" \
    FAKE_RCLONE_QUERY_MATCH_1="$expected_query" \
    FAKE_RCLONE_QUERY_JSON_1="$folder_json" \
    FAKE_RCLONE_COLLISION_QUERY_JSON='[
      {"id":"file-id-a","name":"image.heic","mimeType":"image/heic","parents":["parent-id"]},
      {"id":"file-id-b","name":"image.heic","mimeType":"image/heic","parents":["parent-id"]}
    ]' \
    run_backup
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"
  args="$(cat "$args_file" 2>/dev/null || true)"

  if [[ "$status" == "0" &&
        "$summary" == *$'status=success\n'* &&
        "$args" == *"$expected_query"* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status summary=${summary//$'\n'/,})"
  fi
}

test_ambiguous_parent_folder_fails_closed() {
  local name="ambiguous parent folder IDs keep the backup failed"
  local status summary args_file
  prepare_test_environment
  args_file="$TEST_HOME/rclone-args"

  FAKE_RCLONE_ARGS_FILE="$args_file" \
    FAKE_RCLONE_COPY_OUTPUT_SHARED_ONLY=1 \
    FAKE_RCLONE_COPY_OUTPUT='NOTICE: Photos/image.heic: Duplicate object found in source - ignoring' \
    FAKE_RCLONE_QUERY_MATCH_1="sharedWithMe = true and name = 'Photos' and mimeType = 'application/vnd.google-apps.folder' and trashed = false" \
    FAKE_RCLONE_QUERY_JSON_1='[
      {"id":"folder-id-a","name":"Photos","mimeType":"application/vnd.google-apps.folder"},
      {"id":"folder-id-b","name":"Photos","mimeType":"application/vnd.google-apps.folder"}
    ]' \
    run_backup
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"

  if [[ "$status" == "1" &&
        "$summary" == *$'status=failure\n'* &&
        "$summary" == *$'reason=source_name_collision\n'* &&
        "$(grep -cFx 'copyid' "$args_file" 2>/dev/null || true)" == "0" ]]; then
    pass "$name"
  else
    fail "$name (exit=$status summary=${summary//$'\n'/,})"
  fi
}

test_team_drive_parent_uses_the_drive_root_id() {
  local name="nested Shared Drive parent starts from the drive root ID"
  local status summary args_file args
  prepare_test_environment
  args_file="$TEST_HOME/rclone-args"

  FAKE_RCLONE_ARGS_FILE="$args_file" \
    FAKE_JQ_USE_SYSTEM=1 \
    FAKE_RCLONE_DRIVES_JSON='[
      {"id":"team-drive-id","name":"Team"}
    ]' \
    FAKE_RCLONE_COPY_OUTPUT_TEAM_DRIVE_ONLY=1 \
    FAKE_RCLONE_COPY_OUTPUT='NOTICE: Photos/image.heic: Duplicate object found in source - ignoring' \
    FAKE_RCLONE_QUERY_MATCH_1="'team-drive-id' in parents and name = 'Photos' and mimeType = 'application/vnd.google-apps.folder' and trashed = false" \
    FAKE_RCLONE_QUERY_JSON_1='[
      {"id":"parent-id","name":"Photos","mimeType":"application/vnd.google-apps.folder","parents":["team-drive-id"]}
    ]' \
    FAKE_RCLONE_COLLISION_QUERY_JSON='[
      {"id":"file-id-a","name":"image.heic","mimeType":"image/heic","parents":["parent-id"]},
      {"id":"file-id-b","name":"image.heic","mimeType":"image/heic","parents":["parent-id"]}
    ]' \
    run_backup
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"
  args="$(cat "$args_file" 2>/dev/null || true)"

  if [[ "$status" == "0" &&
        "$summary" == *$'status=success\n'* &&
        "$args" == *$'\x27team-drive-id\x27 in parents and name = \x27Photos\x27'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status summary=${summary//$'\n'/,})"
  fi
}

test_team_drive_root_duplicate_uses_the_drive_id() {
  local name="root-level Shared Drive duplicate uses the drive ID"
  local status summary args_file args
  prepare_test_environment
  args_file="$TEST_HOME/rclone-args"

  FAKE_RCLONE_ARGS_FILE="$args_file" \
    FAKE_JQ_USE_SYSTEM=1 \
    FAKE_RCLONE_DRIVES_JSON='[
      {"id":"team-drive-id","name":"Team"}
    ]' \
    FAKE_RCLONE_COPY_OUTPUT_TEAM_DRIVE_ONLY=1 \
    FAKE_RCLONE_COPY_OUTPUT='NOTICE: image.heic: Duplicate object found in source - ignoring' \
    FAKE_RCLONE_COLLISION_QUERY_JSON='[
      {"id":"file-id-a","name":"image.heic","mimeType":"image/heic","parents":["team-drive-id"]},
      {"id":"file-id-b","name":"image.heic","mimeType":"image/heic","parents":["team-drive-id"]}
    ]' \
    run_backup
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"
  args="$(cat "$args_file" 2>/dev/null || true)"

  if [[ "$status" == "0" &&
        "$summary" == *$'status=success\n'* &&
        "$args" == *$'\x27team-drive-id\x27 in parents and trashed = false\n'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status summary=${summary//$'\n'/,})"
  fi
}

test_collision_archive_failure_keeps_backup_failed() {
  local name="a failed ID archive cannot convert a duplicate source into success"
  local status summary
  prepare_test_environment

  FAKE_RCLONE_COPY_OUTPUT='NOTICE: image.heic: Duplicate object found in source - ignoring' \
    FAKE_RCLONE_COLLISION_QUERY_JSON='[
      {"id":"file-id-a","name":"image.heic","mimeType":"image/heic","parents":["parent-id"]},
      {"id":"file-id-b","name":"image.heic","mimeType":"image/heic","parents":["parent-id"]}
    ]' \
    FAKE_RCLONE_ARCHIVE_STATUS=23 \
    run_backup
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"

  if [[ "$status" == "1" &&
        "$summary" == *$'status=failure\n'* &&
        "$summary" == *$'reason=source_name_collision\n'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status summary=${summary//$'\n'/,})"
  fi
}

test_mixed_collision_notices_cannot_be_partially_archived() {
  local name="every detected Drive collision must be represented in the ID archive"
  local status summary
  prepare_test_environment

  FAKE_RCLONE_COPY_OUTPUT=$'NOTICE: image.heic: Duplicate object found in source - ignoring\nNOTICE: other: duplicate filename after case/unicode normalization' \
    FAKE_RCLONE_COLLISION_QUERY_JSON='[
      {"id":"file-id-a","name":"image.heic","mimeType":"image/heic","parents":["parent-id"]},
      {"id":"file-id-b","name":"image.heic","mimeType":"image/heic","parents":["parent-id"]}
    ]' \
    run_backup
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"

  if [[ "$status" == "1" &&
        "$summary" == *$'status=failure\n'* &&
        "$summary" == *$'reason=source_name_collision\n'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status summary=${summary//$'\n'/,})"
  fi
}

test_unparsed_exact_collision_cannot_hide_behind_valid_group() {
  local name="an unparseable duplicate notice keeps the whole backup failed"
  local status summary
  prepare_test_environment

  FAKE_RCLONE_COPY_OUTPUT=$'NOTICE: image.heic: Duplicate object found in source - ignoring\nunstructured: Duplicate object found in source - ignoring' \
    FAKE_RCLONE_COLLISION_QUERY_JSON='[
      {"id":"file-id-a","name":"image.heic","mimeType":"image/heic","parents":["parent-id"]},
      {"id":"file-id-b","name":"image.heic","mimeType":"image/heic","parents":["parent-id"]}
    ]' \
    run_backup
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"

  if [[ "$status" == "1" &&
        "$summary" == *$'status=failure\n'* &&
        "$summary" == *$'reason=source_name_collision\n'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status summary=${summary//$'\n'/,})"
  fi
}

test_folder_archive_requires_a_materialized_root() {
  local name="an ID-rooted folder copy must materialize its archive root"
  local status summary
  prepare_test_environment

  FAKE_RCLONE_COPY_OUTPUT='NOTICE: EventOS-Backups: Duplicate directory found in source - ignoring' \
    FAKE_RCLONE_COLLISION_QUERY_JSON='[
      {"id":"folder-id-a","name":"EventOS-Backups","mimeType":"application/vnd.google-apps.folder","parents":["parent-id"]},
      {"id":"folder-id-b","name":"EventOS-Backups","mimeType":"application/vnd.google-apps.folder","parents":["parent-id"]}
    ]' \
    FAKE_RCLONE_ARCHIVE_CREATE_FOLDER=0 \
    run_backup
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"

  if [[ "$status" == "1" &&
        "$summary" == *$'status=failure\n'* &&
        "$summary" == *$'reason=source_name_collision\n'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status summary=${summary//$'\n'/,})"
  fi
}

test_google_workspace_duplicates_use_exported_names() {
  local name="Google Workspace duplicate IDs are matched to their exported file name"
  local status summary args_file
  prepare_test_environment
  args_file="$TEST_HOME/rclone-args"

  FAKE_RCLONE_ARGS_FILE="$args_file" \
    FAKE_RCLONE_COPY_OUTPUT='NOTICE: Docs/Plan.docx: Duplicate object found in source - ignoring' \
    FAKE_RCLONE_ARCHIVE_FILE_NAME='Plan.docx' \
    FAKE_RCLONE_QUERY_MATCH_1="'root' in parents and name = 'Docs' and mimeType = 'application/vnd.google-apps.folder' and trashed = false" \
    FAKE_RCLONE_QUERY_JSON_1='[
      {"id":"parent-id","name":"Docs","mimeType":"application/vnd.google-apps.folder","parents":["root-id"]}
    ]' \
    FAKE_RCLONE_QUERY_MATCH_4="sharedWithMe = true and name = 'Docs' and mimeType = 'application/vnd.google-apps.folder' and trashed = false" \
    FAKE_RCLONE_QUERY_JSON_4='[
      {"id":"parent-id","name":"Docs","mimeType":"application/vnd.google-apps.folder"}
    ]' \
    FAKE_RCLONE_COLLISION_QUERY_JSON='[
      {"id":"doc-id-a","name":"Plan","mimeType":"application/vnd.google-apps.document","parents":["parent-id"]},
      {"id":"doc-id-b","name":"Plan","mimeType":"application/vnd.google-apps.document","parents":["parent-id"]},
      {"id":"file-id-c","name":"Plan.docx","mimeType":"application/vnd.openxmlformats-officedocument.wordprocessingml.document","parents":["parent-id"]}
    ]' \
    run_backup
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"

  if [[ "$status" == "0" &&
        "$summary" == *$'status=success\n'* &&
        "$(grep -cFx 'copyid' "$args_file" 2>/dev/null || true)" == "6" &&
        "$(cat "$args_file" 2>/dev/null || true)" == *$'doc-id-a\n'* &&
        "$(cat "$args_file" 2>/dev/null || true)" == *$'doc-id-b\n'* &&
        "$(cat "$args_file" 2>/dev/null || true)" == *$'file-id-c\n'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status summary=${summary//$'\n'/,})"
  fi
}

test_incomplete_drive_query_fails_closed() {
  local name="an incomplete Drive API search cannot publish a complete archive"
  local status summary
  prepare_test_environment

  FAKE_RCLONE_COPY_OUTPUT='NOTICE: image.heic: Duplicate object found in source - ignoring' \
    FAKE_RCLONE_QUERY_STDERR='NOTICE: search result INCOMPLETE' \
    FAKE_RCLONE_COLLISION_QUERY_JSON='[
      {"id":"file-id-a","name":"image.heic","mimeType":"image/heic","parents":["parent-id"]},
      {"id":"file-id-b","name":"image.heic","mimeType":"image/heic","parents":["parent-id"]}
    ]' \
    run_backup
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"

  if [[ "$status" == "1" &&
        "$summary" == *$'status=failure\n'* &&
        "$summary" == *$'reason=source_name_collision\n'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status summary=${summary//$'\n'/,})"
  fi
}

test_shared_with_me_ids_drop_the_virtual_root_flag() {
  local name="Shared-with-me duplicate IDs are copied outside the virtual root view"
  local status summary
  prepare_test_environment

  FAKE_RCLONE_COPY_OUTPUT_SHARED_ONLY=1 \
    FAKE_RCLONE_REJECT_SHARED_FOR_ID=1 \
    FAKE_RCLONE_PARENT_STATUS=88 \
    FAKE_RCLONE_ARCHIVE_FILE_NAME='shared.heic' \
    FAKE_RCLONE_COPY_OUTPUT='NOTICE: shared.heic: Duplicate object found in source - ignoring' \
    FAKE_RCLONE_COLLISION_QUERY_JSON='[
      {"id":"shared-id-a","name":"shared.heic","mimeType":"image/heic"},
      {"id":"shared-id-b","name":"shared.heic","mimeType":"image/heic"}
    ]' \
    run_backup
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"

  if [[ "$status" == "0" && "$summary" == *$'status=success\n'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status summary=${summary//$'\n'/,})"
  fi
}

test_normal_notice_remains_successful() {
  local name="ordinary rclone notices do not become source collision failures"
  local status summary
  prepare_test_environment

  FAKE_RCLONE_COPY_OUTPUT='NOTICE: normal informational message' run_backup
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"

  if [[ "$status" == "0" &&
        "$summary" == *$'status=success\n'* &&
        "$summary" != *$'reason=source_name_collision\n'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status summary=${summary//$'\n'/,})"
  fi
}

test_destination_permission_error_has_priority_over_duplicate_notice() {
  local name="destination permission failure keeps priority over a duplicate notice"
  local status summary
  prepare_test_environment

  FAKE_RCLONE_COPY_STATUS=23 \
    FAKE_RCLONE_COPY_OUTPUT=$'NOTICE: duplicate: Duplicate object found in source - ignoring\nERROR : target: Failed to copy: permission denied' \
    run_backup
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"

  if [[ "$status" == "1" &&
        "$summary" == *$'reason=destination_permission_denied\n'* &&
        "$summary" != *$'reason=source_name_collision\n'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status summary=${summary//$'\n'/,})"
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
      "GDRIVE_BACKUP_OPEN_BIN=$FAKE_BIN/open" \
      "BACKUP_PROGRESS_FOREGROUND=1"
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

test_later_failure_preserves_last_success_marker() {
  local name="a later failed attempt preserves the durable success marker"
  local success_marker status summary
  prepare_test_environment

  run_backup
  success_marker="$(/usr/bin/awk -F= '$1 == "last_success_at" { print $2 }' \
    "$SUMMARY_STATE_FILE")"
  FAKE_RCLONE_COPY_STATUS=23 run_backup
  status=$?
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"

  if [[ "$status" == "1" && "$success_marker" =~ ^[0-9]+$ &&
        "$summary" == *$'status=failure\n'* &&
        "$summary" == *"last_success_at=$success_marker"* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status marker=$success_marker summary=${summary//$'\n'/,})"
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
test_automatic_backup_does_not_open_progress_ui
test_visible_manual_confirmation_requests_foreground
test_early_configuration_error_publishes_failure
test_existing_backup_is_skipped_not_successful
test_state_is_versioned_and_identifies_the_process
test_active_backup_publishes_running_summary
test_locked_backup_publishes_running_before_remote_checks
test_locked_backup_opens_progress_before_remote_checks
test_nas_copy_uses_smb_safe_serial_writes
test_nas_copy_uses_reversible_dot_bin_codec
test_nas_codec_dry_run_does_not_create_manifest
test_nas_codec_rejects_unsupported_rclone
test_nas_codec_rejects_malformed_manifest
test_nas_codec_retries_transient_manifest_read_errors
test_nas_codec_classifies_persistent_manifest_read_errors
test_nas_codec_rejects_nonregular_manifest
test_nas_codec_rejects_ambiguous_legacy_names
test_nas_codec_keeps_shared_drive_destination_raw
test_permission_failure_is_classified
test_source_permission_failure_stays_generic
test_duplicate_source_file_fails_closed
test_duplicate_source_directory_fails_closed
test_duplicate_source_files_are_archived_by_id
test_duplicate_source_directories_are_archived_by_id
test_root_duplicate_uses_drive_root_query
test_nested_duplicate_resolves_each_parent_by_drive_id
test_parent_folder_query_escapes_drive_literals
test_ambiguous_parent_folder_fails_closed
test_team_drive_parent_uses_the_drive_root_id
test_team_drive_root_duplicate_uses_the_drive_id
test_collision_archive_failure_keeps_backup_failed
test_mixed_collision_notices_cannot_be_partially_archived
test_unparsed_exact_collision_cannot_hide_behind_valid_group
test_folder_archive_requires_a_materialized_root
test_google_workspace_duplicates_use_exported_names
test_incomplete_drive_query_fails_closed
test_shared_with_me_ids_drop_the_virtual_root_flag
test_normal_notice_remains_successful
test_destination_permission_error_has_priority_over_duplicate_notice
test_lost_nas_mount_is_classified_and_stops_followup_copies
test_confirmation_uses_injected_open_command
test_declined_confirmation_is_skipped
test_term_signal_publishes_cancellation
test_failed_ui_launch_cleans_internal_state
test_success_persists_private_summary
test_failure_persists_failed_summary
test_later_failure_preserves_last_success_marker
test_concurrent_start_preserves_previous_summary
test_paused_automatic_run_is_silent_and_preserves_history

if (( failures > 0 )); then
  printf '%s backup outcome test(s) failed.\n' "$failures"
  exit 1
fi

printf '%s\n' 'All backup outcome tests passed.'
