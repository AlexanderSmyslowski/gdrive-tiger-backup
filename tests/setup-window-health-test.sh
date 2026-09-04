#!/bin/bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/macos/GDriveBackupTiger/main.m"
HEALTH_SOURCE="$ROOT/macos/GDriveBackupTiger/SetupHealthSupport.m"
failures=0
source_contents="$(<"$SOURCE")"
health_source_contents="$(<"$HEALTH_SOURCE")"

run_command="$(/usr/bin/awk '
  /^static NSString \*RunCommand/ { in_function = 1 }
  in_function { print }
  in_function && /^}$/ { exit }
' "$SOURCE")"

show_backup_setup="$(/usr/bin/awk '
  /^- \(void\)showBackupSetup:/ { in_method = 1 }
  in_method { print }
  in_method && /^}$/ { exit }
' "$SOURCE")"

show_setup="$(/usr/bin/awk '
  /^- \(void\)showSetupWindow/ { in_method = 1; first_line = 1 }
  in_method && !first_line && /^- \(/ { exit }
  in_method { print }
  first_line = 0
' "$SOURCE")"

read_line="$(/usr/bin/awk '/readDataToEndOfFile/ { print NR; exit }' <<<"$run_command")"
wait_line="$(/usr/bin/awk '/waitUntilExit/ { print NR; exit }' <<<"$run_command")"
if [[ -n "$read_line" && -n "$wait_line" ]] && (( read_line < wait_line )); then
  printf '%s\n' 'ok - command output is drained before waiting for child exit'
else
  printf '%s\n' 'not ok - command output can fill its pipe and deadlock setup'
  failures=$((failures + 1))
fi

if [[ "$show_backup_setup" == *'[self showSetupWindow];'* &&
      "$show_backup_setup" != *'NSTask'* &&
      "$show_backup_setup" != *'/usr/bin/open'* &&
      "$show_backup_setup" != *'@"-n"'* ]]; then
  printf '%s\n' 'ok - overview presents setup in its existing app process'
else
  printf '%s\n' 'not ok - every setup click can still create another app process'
  failures=$((failures + 1))
fi

presentation_line="$(/usr/bin/awk '/makeKeyAndOrderFront/ { line = NR } END { print line }' <<<"$show_setup")"
discovery_line="$(/usr/bin/awk '/refreshMountedNASAllowingTargetAutoSelection/ { print NR; exit }' <<<"$show_setup")"
if [[ "$show_setup" == *'if (self.setupWindow)'* &&
      "$show_setup" == *'[self.setupWindow deminiaturize:nil];'* &&
      -n "$presentation_line" && -n "$discovery_line" ]] &&
      (( presentation_line < discovery_line )); then
  printf '%s\n' 'ok - one reusable setup window appears before network discovery'
else
  printf '%s\n' 'not ok - setup can duplicate or remain invisible behind network discovery'
  failures=$((failures + 1))
fi

if [[ "$show_setup" == *'NSMakeSize(650, 720)'* ]]; then
  printf '%s\n' 'ok - setup window reserves space for profiles, the system check, and both notification choices'
else
  printf '%s\n' 'not ok - setup window is too short for both notification choices'
  failures=$((failures + 1))
fi

if [[ "$show_setup" == *'[self installProfileControlsInContentView:content];'* &&
      "$show_setup" == *'[self installSetupHealthViewInContentView:content];'* ]]; then
  printf '%s\n' 'ok - visible setup installs profiles and the system check'
else
  printf '%s\n' 'not ok - system check is not installed in the visible setup'
  failures=$((failures + 1))
fi

if [[ "$show_setup" == *'NSMakeRect(26, 678, 270, 20)'* &&
      "$source_contents" == *'NSMakeRect(18, 562, NSWidth(bounds) - 36, 106)'* &&
      "$show_setup" == *'NSMakeRect(164, 608, 440, 24)'* &&
      "$show_setup" == *'NSMakeRect(164, 636, 440, 24)'* &&
      "$show_setup" == *'self.successNotificationCheckbox.title = T(self.language, @"notifyBackupSuccesses");'* &&
      "$source_contents" == *'NSMakeRect(18, 76, NSWidth(bounds) - 36, 44)'* ]]; then
  printf '%s\n' 'ok - footer, schedule, and both notification preferences have separate rows below the setup sections'
else
  printf '%s\n' 'not ok - the second notification preference can overlap setup controls'
  failures=$((failures + 1))
fi

if [[ "$health_source_contents" == *'NSDate *killDeadline'* &&
      "$health_source_contents" == *'if (task.running) {'* &&
      "$health_source_contents" == *'dispatch_async(dispatch_get_global_queue'* &&
      "$health_source_contents" == *'[taskToReap waitUntilExit];'* ]]; then
  printf '%s\n' 'ok - setup health returns after a bounded post-KILL wait'
else
  printf '%s\n' 'not ok - setup health can still wait forever after SIGKILL'
  failures=$((failures + 1))
fi

if (( failures > 0 )); then
  printf '%s setup window health test(s) failed.\n' "$failures"
  exit 1
fi

printf '%s\n' 'All setup window health tests passed.'
