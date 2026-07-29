#!/bin/bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAIN_SOURCE="$ROOT/macos/GDriveBackupTiger/main.m"
failures=0

method_body() {
  local signature="$1"
  /usr/bin/awk -v signature="$signature" '
    index($0, signature) == 1 { in_method = 1; first_line = 1 }
    in_method && !first_line && /^- \(/ { exit }
    in_method { print }
    first_line = 0
  ' "$MAIN_SOURCE"
}

backup_method="$(method_body '- (void)startBackupNow:')"
dry_run_method="$(method_body '- (void)startDryRun:')"
launch_method="$(/usr/bin/awk '
  /^- \(BOOL\)launchBackupWithArgument:/ {
    in_method = 1
    body = ""
  }
  in_method { body = body $0 ORS }
  in_method && /^}$/ {
    if (body ~ /NSTask \*task/) {
      printf "%s", body
      exit
    }
    in_method = 0
    body = ""
  }
' "$MAIN_SOURCE")"

if [[ "$backup_method" == *'self.statusField.stringValue = T(self.language, @"statusBackupPreparing");'* &&
      "$backup_method" == *'if (![self launchBackupWithArgument:@"--run" assumeYes:YES]) {'* &&
      "$backup_method" == *'[self dismissSetupAfterBackupLaunch];'* &&
      "$backup_method" != *'statusBackupStarted'* ]]; then
  printf '%s\n' 'ok - manual backup preserves launch errors and dismisses setup only after launch'
else
  printf '%s\n' 'not ok - manual backup overwrites a launch failure'
  failures=$((failures + 1))
fi

if [[ "$dry_run_method" == *'completion:^(NSInteger terminationStatus)'* &&
      "$dry_run_method" == *'statusDryRunSucceeded'* &&
      "$dry_run_method" == *'statusDryRunTargetUnavailable'* &&
      "$dry_run_method" == *'statusDryRunFailed'* ]]; then
  printf '%s\n' 'ok - check run publishes a visible terminal result'
else
  printf '%s\n' 'not ok - check run never publishes its terminal result'
  failures=$((failures + 1))
fi

if [[ "$launch_method" == *'return NO;'* && "$launch_method" == *'return YES;'* ]]; then
  printf '%s\n' 'ok - launch helper exposes success and failure'
else
  printf '%s\n' 'not ok - launch helper does not expose success and failure'
  failures=$((failures + 1))
fi

if (( failures > 0 )); then
  printf '%s app launch status test(s) failed.\n' "$failures"
  exit 1
fi

printf '%s\n' 'All app launch status tests passed.'
