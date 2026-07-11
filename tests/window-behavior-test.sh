#!/bin/bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAIN_SOURCE="$ROOT/macos/GDriveBackupTiger/main.m"
failures=0

startup_method="$(/usr/bin/awk '
  /^- \(void\)applicationDidFinishLaunching:/ { in_method = 1 }
  in_method { print }
  in_method && /^}$/ { exit }
' "$MAIN_SOURCE")"
completion_method="$(/usr/bin/awk '
  /^- \(void\)showCompletionAndQuit/ { in_method = 1 }
  in_method { print }
  in_method && /^}$/ { exit }
' "$MAIN_SOURCE")"

check_contains() {
  local expected="$1"
  local description="$2"
  if [[ "$startup_method" == *"$expected"* ]]; then
    printf 'ok - %s\n' "$description"
  else
    printf 'not ok - %s\n' "$description"
    failures=$((failures + 1))
  fi
}

check_absent() {
  local forbidden="$1"
  local description="$2"
  if [[ "$startup_method" != *"$forbidden"* ]]; then
    printf 'ok - %s\n' "$description"
  else
    printf 'not ok - %s\n' "$description"
    failures=$((failures + 1))
  fi
}

check_contains \
  'self.window.level = self.confirmMode ? NSFloatingWindowLevel : NSNormalWindowLevel;' \
  'only confirmation windows use the floating level'
check_absent \
  'self.window.level = NSFloatingWindowLevel;' \
  'normal progress startup does not unconditionally float the window'

confirmation_activation=$'if (self.confirmMode) {\n        [NSApp activateIgnoringOtherApps:YES];\n    }'
check_contains "$confirmation_activation" \
  'forced activation is limited to confirmation startup'

activation_count="$(/usr/bin/grep -Fc '[NSApp activateIgnoringOtherApps:YES];' <<<"$startup_method")"
if [[ "$activation_count" == "1" ]]; then
  printf '%s\n' 'ok - progress startup has no second unconditional activation'
else
  printf 'not ok - expected one guarded startup activation, found %s\n' "$activation_count"
  failures=$((failures + 1))
fi

if [[ "$completion_method" != *'activateIgnoringOtherApps:YES'* &&
      "$completion_method" != *'orderFrontRegardless'* &&
      "$completion_method" == *'[self.window orderFront:nil];'* ]]; then
  printf '%s\n' 'ok - completion appears without stealing focus or forcing front order'
else
  printf '%s\n' 'not ok - completion still steals focus or forces front order'
  failures=$((failures + 1))
fi

if (( failures > 0 )); then
  printf '%s window behavior regression check(s) failed.\n' "$failures"
  exit 1
fi

printf '%s\n' 'All window behavior regression checks passed.'
