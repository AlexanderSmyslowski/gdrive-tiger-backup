#!/bin/bash
# Exercises lib/platform-linux.sh on a real Linux system (CI ubuntu-latest).
# On any other OS it reports a skip and passes, so `make test` on macOS
# stays meaningful without pretending to test GNU tools it does not have.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLATFORM="$ROOT/lib/platform-linux.sh"
ENGINE="$ROOT/bin/backup-google-drive.sh"
failures=0

pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1"; failures=$((failures + 1)); }

if [[ "$(uname -s)" != "Linux" ]]; then
  printf 'platform linux: skipped (not Linux)\n'
  exit 0
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/gdrive-platform-linux-test.XXXXXX")"
cleanup() {
  if [[ -x /usr/bin/trash ]]; then
    /usr/bin/trash "$WORK_DIR"
  else
    printf "Test fixtures retained: %s\n" "$WORK_DIR"
  fi
}
trap cleanup EXIT

test_primitives_match_gnu_tools() {
  local file="$WORK_DIR/data.bin" tree="$WORK_DIR/tree" result device expected
  printf '12345' >"$file"
  touch -d '2026-01-02 03:04:05' "$file"
  mkdir -p "$tree/a/b"
  ln -s "$file" "$tree/a/link"

  result="$(bash -c '
    source "$1"
    printf "%s|%s|%s|%s|%s|%s|%s\n" \
      "$(platform_stat_size "$2")" \
      "$(platform_stat_mtime "$2")" \
      "$(platform_stat_owner "$2")" \
      "$(platform_stat_device "$2")" \
      "$(platform_directory_devices "$3" | sort -u | tr "\n" ,)" \
      "$(platform_first_symlink "$3")" \
      "$(platform_confirm_dialog "t" "d" "y" "n")"' _ "$PLATFORM" "$file" "$tree")"
  device="$(stat -c '%d' "$file")"
  expected="5|$(stat -c '%Y' "$file")|$(id -u)|$device|$device,|$tree/a/link|no"
  if [[ "$result" == "$expected" ]]; then
    pass "stat and find primitives report size, mtime, owner, device and links"
  else
    fail "primitives: expected '$expected', got '$result'"
  fi
}

test_engine_selects_linux_platform() {
  local output
  # shellcheck disable=SC2016
  printf '%s\n' 'printf "%s|%s" "$GDT_PLATFORM" "$(platform_stat_size "$CONFIG_FILE")"; exit 0' >"$WORK_DIR/init.conf"
  output="$(GDRIVE_BACKUP_CONFIG="$WORK_DIR/init.conf" bash "$ENGINE" 2>&1)"
  if [[ "$output" == "linux|$(stat -c '%s' "$WORK_DIR/init.conf")" ]]; then
    pass "engine loads the Linux platform before reading configuration"
  else
    fail "Linux initialization: $output"
  fi
}

test_filesystem_uuid_identity_when_available() {
  local uuid
  uuid="$(findmnt -rn --target "$WORK_DIR" -o UUID 2>/dev/null || true)"
  if [[ -z "$uuid" ]]; then
    pass "filesystem UUID identity (skipped: test filesystem has no UUID)"
    return
  fi
  if bash -c '
    log() { :; }
    safe_name() { printf "%s" "$1"; }
    normalized_apfs_uuid() { printf "%s" "$1" | tr "[:lower:]" "[:upper:]"; }
    canonical_existing_directory() { (cd "$1" 2>/dev/null && pwd -P); }
    BACKUP_TARGET="apfs"
    VOLUME="$2"
    BACKUP_VOLUME_UUID="$1"
    APFS_VOLUME_UUID=""
    APFS_VOLUME_REAL=""
    APFS_VOLUME_DEVICE=""
    APFS_VOLUME_IDENTIFIER=""
    source "$3"
    validate_configured_apfs_volume_identity' _ "$uuid" "$WORK_DIR" "$PLATFORM"; then
    pass "filesystem UUID identity validates the test directory"
  else
    fail "filesystem UUID identity rejects the test directory (uuid $uuid)"
  fi
}

test_primitives_match_gnu_tools
test_engine_selects_linux_platform
test_filesystem_uuid_identity_when_available

if (( failures > 0 )); then
  printf '%d platform linux check(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'platform linux: all checks passed\n'
