#!/bin/bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/macos/GDriveBackupTiger/main.m"
failures=0
source_contents="$(<"$SOURCE")"

show_setup="$(/usr/bin/awk '
  /^- \(void\)showSetupWindow/ { in_method = 1 }
  in_method { print }
  in_method && /^}$/ { exit }
' "$SOURCE")"

if [[ "$show_setup" == *'NSMakeSize(650, 630)'* ]]; then
  printf '%s\n' 'ok - setup window reserves space for the system check'
else
  printf '%s\n' 'not ok - setup window is still too short for the system check'
  failures=$((failures + 1))
fi

if [[ "$show_setup" == *'[self installSetupHealthViewInContentView:content];'* ]]; then
  printf '%s\n' 'ok - visible setup installs the system check'
else
  printf '%s\n' 'not ok - system check is not installed in the visible setup'
  failures=$((failures + 1))
fi

if [[ "$show_setup" == *'NSMakeRect(26, 588, 270, 20)'* &&
      "$source_contents" == *'NSMakeRect(18, 508, NSWidth(bounds) - 36, 52)'* ]]; then
  printf '%s\n' 'ok - footer and schedule remain below the setup sections'
else
  printf '%s\n' 'not ok - setup controls still overlap the system check'
  failures=$((failures + 1))
fi

if (( failures > 0 )); then
  printf '%s setup window health test(s) failed.\n' "$failures"
  exit 1
fi

printf '%s\n' 'All setup window health tests passed.'
