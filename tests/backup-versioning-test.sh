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
  NAS_MOUNT="$TEST_HOME/nas"
  DEST_ROOT="$NAS_MOUNT/backup"
  mkdir -p "$FAKE_BIN" "$NAS_MOUNT"

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
    exit 0
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
else
  /bin/date "$@"
fi
SH

  local tool
  for tool in flock diskutil plutil; do
    cat >"$FAKE_BIN/$tool" <<'SH'
#!/bin/bash
exit 0
SH
  done

  chmod +x "$FAKE_BIN/rclone" "$FAKE_BIN/jq" "$FAKE_BIN/date" \
    "$FAKE_BIN/flock" "$FAKE_BIN/diskutil" "$FAKE_BIN/plutil"
}

run_backup() {
  env \
    HOME="$TEST_HOME" \
    GDRIVE_BACKUP_PATH="$FAKE_BIN:/usr/bin:/bin:/usr/sbin:/sbin" \
    FAKE_RCLONE_LOG="$FAKE_RCLONE_LOG" \
    MOUNT_SETTLE_SECONDS=0 \
    GDRIVE_BACKUP_TARGET=nas \
    GDRIVE_BACKUP_NAS_MOUNT="$NAS_MOUNT" \
    GDRIVE_BACKUP_DEST_ROOT="$DEST_ROOT" \
    GDRIVE_BACKUP_CONFIRM=0 \
    GDRIVE_BACKUP_LOCK="$TEST_HOME/backup.lock" \
    BACKUP_DISABLE_ANIMATION=1 \
    RCLONE_REMOTE=tdd-remote \
    "$@" \
    "$BACKUP_SCRIPT" --run
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

test_no_automatic_retention_is_run() {
  local name="versioning never runs destructive retention implicitly"
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
test_no_automatic_retention_is_run
test_run_ids_are_unique_for_the_same_timestamp

if (( failures > 0 )); then
  printf '%s test(s) failed.\n' "$failures"
  exit 1
fi

printf 'All backup versioning tests passed.\n'
