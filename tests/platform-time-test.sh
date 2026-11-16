#!/bin/bash
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
failures=0
# Load only the scheduling calculation; never execute the backup entrypoint.
eval "$(awk '/^daily_window_start_epoch\(\)/ {copy=1} copy {print} copy && /^}/ {exit}' "$ROOT/bin/backup-google-drive.sh")"
check() {
  local expected="$1" label="$2" actual
  shift 2
  if actual="$("$@" 2>/dev/null)" && [[ "$actual" == "$expected" ]]; then
    printf 'ok - %s\n' "$label"
  else
    printf 'not ok - %s (expected %s, got %s)\n' "$label" "$expected" "$actual"
    failures=$((failures + 1))
  fi
}
run_time_checks() {
  check 1767225600 'timestamp with UTC offset' platform_date_parse '%Y-%m-%dT%H-%M-%S%z' '2026-01-01T02-00-00+0200' '+%s'
  check 1767225600 'timestamp with negative offset' platform_date_parse '%Y-%m-%dT%H-%M-%S%z' '2025-12-31T19-00-00-0500' '+%s'
  check 2024-02-29T12-00-00 'leap-day calendar round trip' platform_date_parse '%Y-%m-%dT%H-%M-%S' '2024-02-29T12-00-00' '+%Y-%m-%dT%H-%M-%S'
  check 2026-W01 'ISO week across year boundary' platform_date_parse '%Y-%m-%d' '2025-12-29' '+%G-W%V'
  check 2026-01-01 'epoch to local calendar day' platform_date_from_epoch 1767225600 '+%Y-%m-%d'
  check 1767301200 'daily window calendar to epoch' platform_date_parse '%Y-%m-%d %H:%M:%S' '2026-01-01 21:00:00' '+%s'
  export TZ=Europe/Berlin
  check 1767225600 'explicit offset is independent of local timezone' platform_date_parse '%Y-%m-%dT%H-%M-%S%z' '2026-01-01T02-00-00+0200' '+%s'
  # Read by the engine function loaded above.
  # shellcheck disable=SC2034
  DAILY_WINDOW_HOUR=21
  check 1774728000 'catch-up before boundary across spring clock change' daily_window_start_epoch 1774807200
  check 1774810800 'catch-up at spring boundary' daily_window_start_epoch 1774810800
  check 1792868400 'catch-up before boundary across autumn clock change' daily_window_start_epoch 1792954800
  check 1792958400 'catch-up at autumn boundary' daily_window_start_epoch 1792958400
  export TZ=UTC
  local value
  value="$(platform_date_parse '%Y-%m-%dT%H-%M-%S' '2026-02-30T12-00-00' '+%Y-%m-%dT%H-%M-%S' 2>/dev/null)" || value=''
  if [[ "$value" != '2026-02-30T12-00-00' ]]; then
    printf 'ok - invalid calendar cannot survive round-trip validation\n'
  else
    printf 'not ok - invalid calendar survives round-trip validation\n'
    failures=$((failures + 1))
  fi
}
export TZ=UTC
case "$(uname -s)" in
  Darwin)
    source "$ROOT/lib/platform-macos.sh"
    run_time_checks
    if command -v gdate >/dev/null; then
      # Exercise the GNU implementation locally without pretending to run Linux.
      date() { gdate "$@"; }
      source "$ROOT/lib/platform-linux.sh"
      run_time_checks
    fi
    ;;
  Linux)
    source "$ROOT/lib/platform-linux.sh"
    run_time_checks
    ;;
esac
(( failures == 0 ))
