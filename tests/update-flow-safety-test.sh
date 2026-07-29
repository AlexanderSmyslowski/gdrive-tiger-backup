#!/bin/bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAIN="$ROOT/macos/GDriveBackupTiger/main.m"
SUPPORT="$ROOT/macos/GDriveBackupTiger/UpdateSupport.m"
failures=0
main_contents="$(<"$MAIN")"
support_contents="$(<"$SUPPORT")"

launch_method="$(/usr/bin/awk '
  /^- \(void\)applicationDidFinishLaunching/ { in_method = 1 }
  in_method { print }
  in_method && /^}$/ { exit }
' "$MAIN")"

if [[ "$launch_method" != *'checkForUpdates:'* &&
      "$launch_method" != *'checkCurrentVersion:'* ]]; then
  printf '%s\n' 'ok - application launch never checks for updates automatically'
else
  printf '%s\n' 'not ok - application launch performs an automatic update check'
  failures=$((failures + 1))
fi

if [[ "$main_contents" != *'installer -pkg'* && "$main_contents" != *'/usr/sbin/installer'* &&
      "$main_contents" != *'downloadTaskWithRequest'* && "$support_contents" != *'downloadTaskWithRequest'* ]]; then
  printf '%s\n' 'ok - update flow neither downloads nor launches an installer'
else
  printf '%s\n' 'not ok - update flow contains download or installer behavior'
  failures=$((failures + 1))
fi

if [[ "$main_contents" == *'https://github.com/AlexanderSmyslowski/gdrive-tiger-backup/releases/latest'* &&
      "$support_contents" == *'https://api.github.com/repos/AlexanderSmyslowski/gdrive-tiger-backup/releases/latest'* ]]; then
  printf '%s\n' 'ok - update flow uses only the official repository endpoints'
else
  printf '%s\n' 'not ok - official update endpoints are missing'
  failures=$((failures + 1))
fi

if (( failures > 0 )); then
  printf '%s update flow safety test(s) failed.\n' "$failures"
  exit 1
fi

printf '%s\n' 'All update flow safety tests passed.'
