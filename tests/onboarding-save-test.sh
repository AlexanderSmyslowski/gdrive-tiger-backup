#!/bin/bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/macos/GDriveBackupTiger/main.m"
method="$(
  /usr/bin/awk '
    /^- \(void\)finishOnboarding/ { in_method = 1 }
    in_method { print }
    in_method && /^}$/ { exit }
  ' "$SOURCE"
)"
failures=0

check_order() {
  local first="$1"
  local second="$2"
  local description="$3"
  local first_line second_line
  first_line="$(/usr/bin/awk -v needle="$first" 'index($0, needle) { print NR; exit }' <<<"$method")"
  second_line="$(/usr/bin/awk -v needle="$second" 'index($0, needle) { print NR; exit }' <<<"$method")"
  if [[ -n "$first_line" && -n "$second_line" ]] && (( first_line < second_line )); then
    printf '%s\n' "ok - $description"
  else
    printf '%s\n' "not ok - $description"
    failures=$((failures + 1))
  fi
}

check_order 'GDTWriteConfigUpdates(updates' 'applySchedule:@"daily"' 'configuration writes precede schedule installation'
check_order 'applySchedule:@"daily"' 'GDTWriteConfigUpdates(GDTOnboardingCompletionUpdate' 'onboarding is marked complete only after the schedule succeeds'

if [[ "$method" == *'GDTOnboardingCompletionUpdate()'* ]]; then
  printf '%s\n' 'ok - completion uses the single versioned onboarding marker'
else
  printf '%s\n' 'not ok - completion marker is not written explicitly'
  failures=$((failures + 1))
fi

if (( failures > 0 )); then
  printf '%s onboarding save test(s) failed.\n' "$failures"
  exit 1
fi
printf '%s\n' 'All onboarding save tests passed.'
