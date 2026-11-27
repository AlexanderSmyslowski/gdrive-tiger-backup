#!/bin/bash
# Checks the split between the portable engine core and the macOS platform
# layer: the platform file provides every name of its contract, the primitives
# report what BSD stat/find report, the engine refuses to run without the
# platform file, and the core gains no new direct macOS tool calls.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENGINE="$ROOT/bin/backup-google-drive.sh"
PLATFORM="$ROOT/lib/platform-macos.sh"
PLATFORM_LINUX="$ROOT/lib/platform-linux.sh"
WORK_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/gdrive-platform-test.XXXXXX")"
failures=0

cleanup() {
  "$ROOT/scripts/trash-path.sh" "$WORK_DIR" >/dev/null 2>&1 || true
}
trap cleanup EXIT

pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1"; failures=$((failures + 1)); }

contract_names() {
  /usr/bin/awk '
    /^# Contract:/ { inside = 1; next }
    inside && !/^#/ { exit }
    inside {
      line = $0
      sub(/^#[[:space:]]*/, "", line)
      sub(/^[A-Za-z ]+:[[:space:]]+/, "", line)
      n = split(line, words, /[ ,]+/)
      for (i = 1; i <= n; i++) {
        if (words[i] ~ /^(platform_[a-z_]+|PLATFORM_[A-Z_]+|[a-z]+(_[a-z0-9]+)+)$/) print words[i]
      }
    }' "$PLATFORM" | /usr/bin/sort -u
}

test_contract_is_defined() {
  local names missing
  names="$(contract_names)"
  [[ "$(printf '%s\n' "$names" | /usr/bin/wc -l | /usr/bin/tr -d ' ')" -ge 25 ]] ||
    { fail "contract list is parsed (got: $names)"; return; }
  # One name per word; the split is intended (bash 3.2 has no mapfile).
  # shellcheck disable=SC2086
  missing="$(/bin/bash -c '
    source "$1"; shift
    for name; do
      if [[ "$name" == PLATFORM_* ]]; then
        declare -p "$name" >/dev/null 2>&1 || printf "%s\n" "$name"
      else
        declare -F "$name" >/dev/null || printf "%s\n" "$name"
      fi
    done' _ "$PLATFORM" $names)"
  if [[ -z "$missing" ]]; then
    pass "platform file defines every contract name"
  else
    fail "platform file lacks: $missing"
  fi
}

test_primitives_match_bsd_tools() {
  local file="$WORK_DIR/data.bin" tree="$WORK_DIR/tree" result
  printf '12345' >"$file"
  /usr/bin/touch -t 202601020304.05 "$file"
  /bin/mkdir -p "$tree/a/b"
  /bin/ln -s "$file" "$tree/a/link"

  result="$(/bin/bash -c '
    source "$1"
    printf "%s|%s|%s|%s|%s|%s\n" \
      "$(platform_stat_size "$2")" \
      "$(platform_stat_mtime "$2")" \
      "$(platform_stat_owner "$2")" \
      "$(platform_stat_device "$2")" \
      "$(platform_directory_devices "$3" | /usr/bin/sort -u | /usr/bin/tr "\n" ,)" \
      "$(platform_first_symlink "$3")"' _ "$PLATFORM" "$file" "$tree")"
  local device
  device="$(/usr/bin/stat -f '%d' "$file")"
  local expected
  expected="5|$(/usr/bin/stat -f '%m' "$file")|$(/usr/bin/id -u)|$device|$device,|$tree/a/link"
  if [[ "$result" == "$expected" ]]; then
    pass "stat and find primitives report size, mtime, owner, device and links"
  else
    fail "primitives: expected '$expected', got '$result'"
  fi
}

test_engine_requires_platform_file() {
  local copy="$WORK_DIR/checkout/bin" output status
  /bin/mkdir -p "$copy"
  /bin/cp "$ENGINE" "$copy/backup-google-drive.sh"
  output="$(HOME="$WORK_DIR" /bin/bash "$copy/backup-google-drive.sh" --dry-run 2>&1)"
  status=$?
  if [[ "$status" == "69" && "$output" == *"Plattformdatei fehlt"* ]]; then
    pass "engine stops with exit 69 when the platform file is missing"
  else
    fail "missing platform file: status $status, output: $output"
  fi
}

test_capabilities_need_no_platform_file() {
  local copy="$WORK_DIR/caps/bin" output
  /bin/mkdir -p "$copy"
  /bin/cp "$ENGINE" "$copy/backup-google-drive.sh"
  output="$(/bin/bash "$copy/backup-google-drive.sh" --capabilities 2>&1)"
  if [[ "$output" == $'adhoc-target-v1\nrun-history-v1' ]]; then
    pass "--capabilities answers before the platform file is loaded"
  else
    fail "--capabilities: $output"
  fi
}

test_platform_symlink_is_refused() {
  local checkout="$WORK_DIR/linked" output status
  /bin/mkdir -p "$checkout/bin" "$checkout/lib"
  /bin/cp "$ENGINE" "$checkout/bin/backup-google-drive.sh"
  /bin/ln -s "$PLATFORM" "$checkout/lib/platform-macos.sh"
  output="$(HOME="$WORK_DIR" /bin/bash "$checkout/bin/backup-google-drive.sh" --dry-run 2>&1)"
  status=$?
  if [[ "$status" == "69" ]]; then
    pass "engine refuses a symlinked platform file"
  else
    fail "symlinked platform file: status $status, output: $output"
  fi
}

test_core_has_no_direct_macos_calls() {
  local hits
  # The *_BIN defaults stay in the core because they are configuration.
  hits="$(/usr/bin/grep -nE 'diskutil|plutil|ioreg|osascript|stat -f|find -x|dscl|/Volumes' "$ENGINE" |
    /usr/bin/grep -vE '^[0-9]+:#|^[0-9]+:(DISKUTIL|IOREG|OSASCRIPT)_BIN=')"
  if [[ -z "$hits" ]]; then
    pass "engine core calls no macOS-only tool directly"
  else
    fail "macOS-only calls in the core:
$hits"
  fi
}

test_linux_contract_is_defined() {
  local names missing hits
  names="$(contract_names)"
  # One name per word; the split is intended (bash 3.2 has no mapfile).
  # shellcheck disable=SC2086
  missing="$(/bin/bash -c '
    source "$1"; shift
    for name; do
      if [[ "$name" == PLATFORM_* ]]; then
        declare -p "$name" >/dev/null 2>&1 || printf "%s\n" "$name"
      else
        declare -F "$name" >/dev/null || printf "%s\n" "$name"
      fi
    done' _ "$PLATFORM_LINUX" $names)"
  if [[ -z "$missing" ]]; then
    pass "linux platform file defines every contract name"
  else
    fail "linux platform file lacks: $missing"
  fi
  hits="$(/usr/bin/grep -nwE 'diskutil|plutil|ioreg|osascript|dscl' "$PLATFORM_LINUX" || true)"
  if [[ -z "$hits" ]] && /usr/bin/grep -Fq 'Linux) GDT_PLATFORM="linux"' "$ENGINE"; then
    pass "linux platform file calls no macOS-only tool and the engine selects it"
  else
    fail "macOS-only calls in the linux platform file:
$hits"
  fi
}

test_device_info_describes_the_whole_disk() {
  local fake="$WORK_DIR/fake-diskutil" result
  cat >"$fake" <<'FAKE'
#!/bin/bash
key_plist() { printf '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict>%s</dict></plist>' "$1"; }
case "$3" in
  /Volumes/Backup) key_plist '<key>VolumeUUID</key><string>5861298E-D6FE-445F-A407-71EC3C8DE30B</string><key>APFSPhysicalStores</key><array><dict><key>APFSPhysicalStore</key><string>disk6s2</string></dict></array>' ;;
  disk6s2) key_plist '<key>ParentWholeDisk</key><string>disk6</string>' ;;
  disk6) key_plist '<key>IORegistryEntryName</key><string>Samsung PSSD T7 Media</string><key>TotalSize</key><integer>1000204886016</integer><key>SolidState</key><true/><key>BusProtocol</key><string>USB</string>' ;;
  *) exit 1 ;;
esac
FAKE
  /bin/chmod 755 "$fake"
  result="$(/bin/bash -c '
    source "$1"
    for f in run_with_timeout display_metadata_value first_nonempty_display_value; do
      eval "$(/usr/bin/awk -v f="$f" '"'"'$0 == f"() {" {p=1} p {print} p && /^}$/ {exit}'"'"' "$2")"
    done
    DISKUTIL_BIN="$3"
    platform_destination_device_info /Volumes/Backup' _ "$PLATFORM" "$ENGINE" "$fake")"
  if [[ "$result" == $'5861298E-D6FE-445F-A407-71EC3C8DE30B\tSamsung PSSD T7\t1000204886016\tyes\tUSB' ]]; then
    pass "device info names the physical disk, its size, SSD and bus"
  else
    fail "device info: ${result//$'\t'/|}"
  fi
}

test_contract_is_defined
test_device_info_describes_the_whole_disk
test_linux_contract_is_defined
test_primitives_match_bsd_tools
test_engine_requires_platform_file
test_capabilities_need_no_platform_file
test_platform_symlink_is_refused
test_core_has_no_direct_macos_calls

if (( failures > 0 )); then
  printf '%d platform contract check(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'platform contract: all checks passed\n'
