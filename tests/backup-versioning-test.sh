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
  TEST_HOME="$(mktemp -d "${TMPDIR:-/tmp}/gdrive-versioning-test.XXXXXX")"
  FAKE_BIN="$TEST_HOME/fake-bin"
  FAKE_RCLONE_LOG="$TEST_HOME/rclone-calls.log"
  FAKE_RETENTION_TRASH_DIR="$TEST_HOME/system-trash"
  NAS_MOUNT="$TEST_HOME/nas"
  DEST_ROOT="$NAS_MOUNT/backup"
  VERSIONS_ROOT="$DEST_ROOT/.gdrive-versions"
  mkdir -p "$FAKE_BIN" "$NAS_MOUNT" "$FAKE_RETENTION_TRASH_DIR"

  cat >"$FAKE_BIN/rclone" <<'SH'
#!/bin/bash
set -u
: "${FAKE_RCLONE_LOG:?}"

printf '%s' "${1:-}" >>"$FAKE_RCLONE_LOG"
for arg in "${@:2}"; do
  printf '\t%s' "$arg" >>"$FAKE_RCLONE_LOG"
done
printf '\n' >>"$FAKE_RCLONE_LOG"

case "${1:-}" in
  config)
    exit 0
    ;;
  backend)
    printf '[{"id":"drive-123","name":"Team/Alpha"}]\n'
    exit 0
    ;;
  copy)
    if [[ " $* " == *' --ignore-existing '* ]]; then
      mkdir -p "$3"
      /bin/cp -R -n "$2"/. "$3"/ 2>/dev/null || true
      exit "${FAKE_RETENTION_MERGE_STATUS:-0}"
    fi
    exit "${FAKE_RCLONE_COPY_STATUS:-0}"
    ;;
esac

exit 64
SH

  cat >"$FAKE_BIN/jq" <<'SH'
#!/bin/bash
set -u

case "${1:-}" in
  length)
    printf '1\n'
    ;;
  -r)
    printf 'drive-123\tTeam/Alpha\n'
    ;;
  *)
    exit 64
    ;;
esac
SH

  cat >"$FAKE_BIN/date" <<'SH'
#!/bin/bash
if [[ "${1:-}" == '+%Y-%m-%dT%H-%M-%S%z' ]]; then
  printf '2026-07-11T00-00-00+0200\n'
elif [[ "${1:-}" == '+%s' ]]; then
  printf '1783771200\n'
else
  /bin/date "$@"
fi
SH

  cat >"$FAKE_BIN/trash" <<'SH'
#!/bin/bash
set -u
: "${FAKE_RETENTION_TRASH_DIR:?}"

mkdir -p "$FAKE_RETENTION_TRASH_DIR"
for path in "$@"; do
  destination="$FAKE_RETENTION_TRASH_DIR/${path##*/}"
  [[ ! -e "$destination" ]] || exit 73
  /bin/mv "$path" "$destination" || exit $?
done
SH

  cat >"$FAKE_BIN/mount" <<'SH'
#!/bin/bash
printf '%s on %s (smbfs, nodev, nosuid)\n' '//backup.test/share' "${FAKE_NAS_MOUNT:?}"
SH

  local tool
  for tool in flock diskutil plutil; do
    cat >"$FAKE_BIN/$tool" <<'SH'
#!/bin/bash
exit 0
SH
  done

  chmod +x "$FAKE_BIN/rclone" "$FAKE_BIN/jq" "$FAKE_BIN/date" "$FAKE_BIN/trash" \
    "$FAKE_BIN/mount" "$FAKE_BIN/flock" "$FAKE_BIN/diskutil" "$FAKE_BIN/plutil"
}

run_backup_with_mode() {
  local mode="$1"
  shift
  env \
    HOME="$TEST_HOME" \
    GDRIVE_BACKUP_PATH="$FAKE_BIN:/usr/bin:/bin:/usr/sbin:/sbin" \
    FAKE_RCLONE_LOG="$FAKE_RCLONE_LOG" \
    FAKE_RETENTION_TRASH_DIR="$FAKE_RETENTION_TRASH_DIR" \
    MOUNT_SETTLE_SECONDS=0 \
    GDRIVE_BACKUP_TARGET=nas \
    GDRIVE_BACKUP_NAS_MOUNT="$NAS_MOUNT" \
    GDRIVE_BACKUP_MOUNT_BIN="$FAKE_BIN/mount" \
    GDRIVE_BACKUP_DEST_ROOT="$DEST_ROOT" \
    GDRIVE_BACKUP_CONFIRM=0 \
    GDRIVE_BACKUP_LOCK="$TEST_HOME/backup.lock" \
    FAKE_NAS_MOUNT="$NAS_MOUNT" \
    BACKUP_DISABLE_ANIMATION=1 \
    RCLONE_REMOTE=tdd-remote \
    GDRIVE_BACKUP_RETENTION_TRASH_BIN="$FAKE_BIN/trash" \
    "$@" \
    "$BACKUP_SCRIPT" "$mode"
}

run_backup() {
  run_backup_with_mode --run "$@"
}

run_dry_backup() {
  run_backup_with_mode --dry-run
}

backup_dirs() {
  awk -F '\t' '
    $1 == "copy" {
      for (i = 1; i <= NF; i++) {
        if ($i == "--backup-dir") print $(i + 1)
      }
    }
  ' "$FAKE_RCLONE_LOG"
}

retention_version_name() {
  printf '%s-00000000-0000-4000-8000-%012d' "$1" "$2"
}

create_version() {
  local name
  name="$(retention_version_name "$1" "$2")"
  mkdir -p "$VERSIONS_ROOT/$name"
  printf '%s' "$name"
}

test_versioning_is_enabled_by_default() {
  local name="versioning uses one timestamped backup tree for every copy phase"
  local status dirs dir_count my_drive shared_with_me shared_drive prefix run_id
  prepare_test_environment

  run_backup
  status=$?
  if [[ "$status" != "0" ]]; then
    fail "$name (backup exited with $status)"
    return
  fi

  dirs="$(backup_dirs)"
  dir_count="$(printf '%s\n' "$dirs" | awk 'NF {count++} END {print count + 0}')"
  my_drive="$(printf '%s\n' "$dirs" | sed -n '1p')"
  shared_with_me="$(printf '%s\n' "$dirs" | sed -n '2p')"
  shared_drive="$(printf '%s\n' "$dirs" | sed -n '3p')"
  prefix="$DEST_ROOT/.gdrive-versions/"
  run_id="${my_drive#"$prefix"}"
  run_id="${run_id%/My Drive}"

  if [[ "$dir_count" == "3" &&
        "$my_drive" == "$prefix$run_id/My Drive" &&
        "$shared_with_me" == "$prefix$run_id/Shared with me" &&
        "$shared_drive" == "$prefix$run_id/Shared Drives/Team_Alpha (drive-123)" &&
        "$run_id" =~ ^2026-07-11T00-00-00\+0200-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
    pass "$name"
  else
    fail "$name (unexpected backup dirs: $dirs)"
  fi
}

test_versioning_can_be_disabled() {
  local name="versioning can be disabled explicitly"
  local status
  prepare_test_environment

  run_backup GDRIVE_BACKUP_VERSIONING=0
  status=$?

  if [[ "$status" == "0" ]] && ! grep -Fq -- $'\t--backup-dir\t' "$FAKE_RCLONE_LOG"; then
    pass "$name"
  else
    fail "$name"
  fi
}

test_invalid_versioning_toggle_is_rejected() {
  local name="invalid versioning toggle is rejected before rclone"
  local status log_file
  prepare_test_environment
  log_file="$TEST_HOME/Library/Logs/gdrive-backup.log"

  run_backup GDRIVE_BACKUP_VERSIONING=yes
  status=$?

  if [[ "$status" == "64" && ! -s "$FAKE_RCLONE_LOG" ]] &&
    grep -Fq 'GDRIVE_BACKUP_VERSIONING' "$log_file"; then
    pass "$name"
  else
    fail "$name (expected exit 64 without rclone calls, got $status)"
  fi
}

test_unsafe_version_subdirs_are_rejected() {
  local name="unsafe or overlapping version subdirectories are rejected"
  local value status rejected=0

  for value in '../Versions' 'My Drive/archive'; do
    prepare_test_environment
    run_backup "GDRIVE_BACKUP_VERSIONS_SUBDIR=$value"
    status=$?
    if [[ "$status" == "64" && ! -s "$FAKE_RCLONE_LOG" ]]; then
      rejected=$((rejected + 1))
    fi
  done

  if [[ "$rejected" == "2" ]]; then
    pass "$name"
  else
    fail "$name ($rejected of 2 values rejected safely)"
  fi
}

test_retention_never_uses_destructive_rclone_commands() {
  local name="retention never invokes destructive rclone commands"
  local status
  prepare_test_environment

  run_backup
  status=$?

  if [[ "$status" == "0" ]] &&
    ! grep -Eq '^(delete|deletefile|purge|rmdirs)(\t|$)' "$FAKE_RCLONE_LOG"; then
    pass "$name"
  else
    fail "$name"
  fi
}

test_default_retention_policy() {
  local name="default retention keeps hourly, daily, and weekly representatives"
  local status log_file
  local recent_one recent_two daily_old daily_new daily_other
  local weekly_old weekly_new weekly_other expired invalid_calendar invalid_day invalid_time invalid_zone
  prepare_test_environment
  log_file="$TEST_HOME/Library/Logs/gdrive-backup.log"

  recent_one="$(create_version '2026-07-11T10-00-00+0000' 1)"
  recent_two="$(create_version '2026-07-11T11-00-00+0000' 2)"
  daily_old="$(create_version '2026-07-09T08-00-00+0000' 3)"
  daily_new="$(create_version '2026-07-09T20-00-00+0000' 4)"
  daily_other="$(create_version '2026-07-08T18-00-00+0000' 5)"
  weekly_old="$(create_version '2026-05-04T08-00-00+0000' 6)"
  weekly_new="$(create_version '2026-05-10T20-00-00+0000' 7)"
  weekly_other="$(create_version '2026-05-03T20-00-00+0000' 8)"
  expired="$(create_version '2025-06-01T12-00-00+0000' 9)"
  invalid_calendar="$(retention_version_name '2026-99-99T12-00-00+0000' 10)"
  invalid_day="$(retention_version_name '2026-02-30T12-00-00+0000' 15)"
  invalid_time="$(retention_version_name '2026-02-20T25-00-00+0000' 16)"
  invalid_zone="$(retention_version_name '2026-02-20T12-00-00+2460' 17)"
  mkdir -p "$VERSIONS_ROOT/$invalid_calendar" "$VERSIONS_ROOT/$invalid_day" \
    "$VERSIONS_ROOT/$invalid_time" "$VERSIONS_ROOT/$invalid_zone" "$VERSIONS_ROOT/notes"

  run_backup
  status=$?

  if [[ "$status" == "0" &&
        -d "$VERSIONS_ROOT/$recent_one" &&
        -d "$VERSIONS_ROOT/$recent_two" &&
        -d "$VERSIONS_ROOT/$daily_new" &&
        -d "$VERSIONS_ROOT/$daily_other" &&
        -d "$VERSIONS_ROOT/$weekly_new" &&
        -d "$VERSIONS_ROOT/$weekly_other" &&
        -d "$VERSIONS_ROOT/$invalid_calendar" &&
        -d "$VERSIONS_ROOT/$invalid_day" &&
        -d "$VERSIONS_ROOT/$invalid_time" &&
        -d "$VERSIONS_ROOT/$invalid_zone" &&
        -d "$VERSIONS_ROOT/notes" &&
        -d "$FAKE_RETENTION_TRASH_DIR/$daily_old" &&
        -d "$FAKE_RETENTION_TRASH_DIR/$weekly_old" &&
        -d "$FAKE_RETENTION_TRASH_DIR/$expired" &&
        ! -e "$VERSIONS_ROOT/$daily_old" &&
        ! -e "$VERSIONS_ROOT/$weekly_old" &&
        ! -e "$VERSIONS_ROOT/$expired" ]] &&
    grep -Fq 'Unbekannter Versionsordner bleibt erhalten: notes' "$log_file"; then
    pass "$name"
  else
    fail "$name"
  fi
}

test_retention_can_be_disabled() {
  local name="retention can be disabled explicitly"
  local expired status
  prepare_test_environment
  expired="$(create_version '2025-06-01T12-00-00+0000' 11)"

  run_backup GDRIVE_BACKUP_RETENTION=0
  status=$?

  if [[ "$status" == "0" && -d "$VERSIONS_ROOT/$expired" &&
        ! -e "$FAKE_RETENTION_TRASH_DIR/$expired" ]]; then
    pass "$name"
  else
    fail "$name"
  fi
}

test_invalid_retention_toggle_is_rejected() {
  local name="invalid retention toggle is rejected before rclone"
  local status log_file
  prepare_test_environment
  log_file="$TEST_HOME/Library/Logs/gdrive-backup.log"

  run_backup GDRIVE_BACKUP_RETENTION=yes
  status=$?

  if [[ "$status" == "64" && ! -s "$FAKE_RCLONE_LOG" ]] &&
    grep -Fq 'GDRIVE_BACKUP_RETENTION' "$log_file"; then
    pass "$name"
  else
    fail "$name (expected exit 64 without rclone calls, got $status)"
  fi
}

test_retention_runs_only_after_successful_backup() {
  local name="retention does not run after a failed backup"
  local expired status
  prepare_test_environment
  expired="$(create_version '2025-06-01T12-00-00+0000' 12)"

  run_backup FAKE_RCLONE_COPY_STATUS=1
  status=$?

  if [[ "$status" == "1" && -d "$VERSIONS_ROOT/$expired" &&
        ! -e "$FAKE_RETENTION_TRASH_DIR/$expired" ]]; then
    pass "$name"
  else
    fail "$name"
  fi
}

test_retention_dry_run_only_logs_candidates() {
  local name="retention dry-run logs candidates without moving them"
  local expired status log_file
  prepare_test_environment
  log_file="$TEST_HOME/Library/Logs/gdrive-backup.log"
  expired="$(create_version '2025-06-01T12-00-00+0000' 13)"

  run_dry_backup
  status=$?

  if [[ "$status" == "0" && -d "$VERSIONS_ROOT/$expired" &&
        ! -e "$FAKE_RETENTION_TRASH_DIR/$expired" ]] &&
    grep -Fq "DRY-RUN Aufbewahrungskandidat: $expired" "$log_file"; then
    pass "$name"
  else
    fail "$name"
  fi
}

test_retention_falls_back_to_local_quarantine() {
  local name="retention quarantines candidates when system trash is unavailable"
  local expired status
  prepare_test_environment
  expired="$(create_version '2025-06-01T12-00-00+0000' 14)"

  run_backup "GDRIVE_BACKUP_RETENTION_TRASH_BIN=$TEST_HOME/missing-trash"
  status=$?

  if [[ "$status" == "0" && ! -e "$VERSIONS_ROOT/$expired" &&
        -d "$VERSIONS_ROOT/.retention-trash/$expired" ]]; then
    pass "$name"
  else
    fail "$name"
  fi
}

test_retention_retries_legacy_quarantine() {
  local name="retention retries quarantined versions when Trash becomes available"
  local expired status
  prepare_test_environment
  expired="$(create_version '2025-06-01T12-00-00+0000' 18)"

  run_backup "GDRIVE_BACKUP_RETENTION_TRASH_BIN=$TEST_HOME/missing-trash"
  status=$?
  if [[ "$status" != "0" || ! -d "$VERSIONS_ROOT/.retention-trash/$expired" ]]; then
    fail "$name (initial quarantine failed)"
    return
  fi

  run_backup
  status=$?
  if [[ "$status" == "0" &&
        ! -e "$VERSIONS_ROOT/.retention-trash/$expired" &&
        -d "$FAKE_RETENTION_TRASH_DIR/$expired" ]]; then
    pass "$name"
  else
    fail "$name (quarantine was not retried)"
  fi
}

test_retention_merges_sparse_deltas_before_pruning() {
  local name="retention preserves newest per-file versions when thinning sparse runs"
  local oldest middle keeper status
  prepare_test_environment

  oldest="$(create_version '2026-07-09T08-00-00+0000' 30)"
  middle="$(create_version '2026-07-09T16-00-00+0000' 31)"
  keeper="$(create_version '2026-07-09T20-00-00+0000' 32)"
  mkdir -p "$VERSIONS_ROOT/$oldest/My Drive" \
    "$VERSIONS_ROOT/$middle/My Drive" \
    "$VERSIONS_ROOT/$keeper/My Drive"
  printf '%s\n' 'only in oldest' >"$VERSIONS_ROOT/$oldest/My Drive/old-only.txt"
  printf '%s\n' 'older shared version' >"$VERSIONS_ROOT/$oldest/My Drive/shared.txt"
  printf '%s\n' 'only in middle' >"$VERSIONS_ROOT/$middle/My Drive/middle-only.txt"
  printf '%s\n' 'newest shared version' >"$VERSIONS_ROOT/$middle/My Drive/shared.txt"
  printf '%s\n' 'already newest' >"$VERSIONS_ROOT/$keeper/My Drive/keeper.txt"

  run_backup
  status=$?

  if [[ "$status" == "0" &&
        "$(<"$VERSIONS_ROOT/$keeper/My Drive/old-only.txt")" == "only in oldest" &&
        "$(<"$VERSIONS_ROOT/$keeper/My Drive/middle-only.txt")" == "only in middle" &&
        "$(<"$VERSIONS_ROOT/$keeper/My Drive/shared.txt")" == "newest shared version" &&
        "$(<"$VERSIONS_ROOT/$keeper/My Drive/keeper.txt")" == "already newest" &&
        -d "$FAKE_RETENTION_TRASH_DIR/$oldest" &&
        -d "$FAKE_RETENTION_TRASH_DIR/$middle" ]]; then
    pass "$name"
  else
    fail "$name"
  fi
}

test_retention_stops_after_merge_failure() {
  local name="retention stops before older deltas after a merge failure"
  local oldest middle keeper status merge_calls
  prepare_test_environment

  oldest="$(create_version '2026-07-09T08-00-00+0000' 33)"
  middle="$(create_version '2026-07-09T16-00-00+0000' 34)"
  keeper="$(create_version '2026-07-09T20-00-00+0000' 35)"
  mkdir -p "$VERSIONS_ROOT/$oldest/My Drive" \
    "$VERSIONS_ROOT/$middle/My Drive" \
    "$VERSIONS_ROOT/$keeper/My Drive"
  printf '%s\n' older >"$VERSIONS_ROOT/$oldest/My Drive/file.txt"
  printf '%s\n' newer >"$VERSIONS_ROOT/$middle/My Drive/file.txt"

  run_backup FAKE_RETENTION_MERGE_STATUS=1
  status=$?
  merge_calls="$(/usr/bin/awk -F '\t' '$1 == "copy" && $0 ~ /--ignore-existing/ { count++ } END { print count + 0 }' "$FAKE_RCLONE_LOG")"

  if [[ "$status" == "1" && "$merge_calls" == "1" &&
        -d "$VERSIONS_ROOT/$middle" && -d "$VERSIONS_ROOT/$oldest" &&
        ! -e "$FAKE_RETENTION_TRASH_DIR/$middle" &&
        ! -e "$FAKE_RETENTION_TRASH_DIR/$oldest" ]]; then
    pass "$name"
  else
    fail "$name"
  fi
}

test_retention_age_boundaries() {
  local name="retention applies strict 24-hour, 30-day, and 52-week boundaries"
  local at_24 over_24 at_30 over_30 at_52 over_52 status
  prepare_test_environment

  at_24="$(create_version '2026-07-10T12-00-00+0000' 20)"
  over_24="$(create_version '2026-07-10T11-00-00+0000' 21)"
  at_30="$(create_version '2026-06-11T12-00-00+0000' 22)"
  over_30="$(create_version '2026-06-11T11-59-59+0000' 23)"
  at_52="$(create_version '2025-07-12T12-00-00+0000' 24)"
  over_52="$(create_version '2025-07-12T11-59-59+0000' 25)"

  run_backup
  status=$?

  if [[ "$status" == "0" &&
        -d "$VERSIONS_ROOT/$at_24" &&
        -d "$VERSIONS_ROOT/$at_30" &&
        -d "$VERSIONS_ROOT/$over_30" &&
        -d "$VERSIONS_ROOT/$at_52" &&
        -d "$FAKE_RETENTION_TRASH_DIR/$over_24" &&
        -d "$FAKE_RETENTION_TRASH_DIR/$over_52" ]]; then
    pass "$name"
  else
    fail "$name"
  fi
}

test_run_ids_are_unique_for_the_same_timestamp() {
  local name="versioning run IDs stay unique across Macs or repeated timestamps"
  local first_dir fourth_dir prefix first_run_id second_run_id
  prepare_test_environment

  run_backup
  run_backup
  first_dir="$(backup_dirs | sed -n '1p')"
  fourth_dir="$(backup_dirs | sed -n '4p')"
  prefix="$DEST_ROOT/.gdrive-versions/"
  first_run_id="${first_dir#"$prefix"}"
  first_run_id="${first_run_id%/My Drive}"
  second_run_id="${fourth_dir#"$prefix"}"
  second_run_id="${second_run_id%/My Drive}"

  if [[ -n "$first_run_id" && -n "$second_run_id" && "$first_run_id" != "$second_run_id" ]]; then
    pass "$name"
  else
    fail "$name (run IDs collided: $first_run_id)"
  fi
}

test_versioning_is_enabled_by_default
test_versioning_can_be_disabled
test_invalid_versioning_toggle_is_rejected
test_unsafe_version_subdirs_are_rejected
test_retention_never_uses_destructive_rclone_commands
test_run_ids_are_unique_for_the_same_timestamp
test_default_retention_policy
test_retention_can_be_disabled
test_invalid_retention_toggle_is_rejected
test_retention_runs_only_after_successful_backup
test_retention_dry_run_only_logs_candidates
test_retention_falls_back_to_local_quarantine
test_retention_retries_legacy_quarantine
test_retention_merges_sparse_deltas_before_pruning
test_retention_stops_after_merge_failure
test_retention_age_boundaries

if (( failures > 0 )); then
  printf '%s test(s) failed.\n' "$failures"
  exit 1
fi

printf 'All backup versioning tests passed.\n'
