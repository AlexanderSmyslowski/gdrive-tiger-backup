#!/bin/bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAKEFILE="$ROOT/Makefile"
INSTALLER="$ROOT/install.sh"
README="$ROOT/README.md"
SOURCE="$ROOT/macos/GDriveBackupTiger/OnboardingSupport.m"
failures=0

check_contains() {
  local file="$1"
  local needle="$2"
  local description="$3"
  if /usr/bin/grep -Fq "$needle" "$file"; then
    printf '%s\n' "ok - $description"
  else
    printf '%s\n' "not ok - $description"
    failures=$((failures + 1))
  fi
}

# shellcheck disable=SC2016
check_contains "$MAKEFILE" '$(ONBOARDING_SUPPORT_SOURCE)' 'Makefile compiles onboarding support'
check_contains "$INSTALLER" 'OnboardingSupport.m' 'source installer compiles onboarding support'
check_contains "$MAKEFILE" 'onboarding-ui-test.m' 'Makefile runs onboarding UI coverage'
check_contains "$README" 'one automatic primary destination' 'README explains one automatic primary destination'
check_contains "$README" 'never creates a second schedule' 'README explains the manual disk does not create a second schedule'
check_contains "$SOURCE" 'GDTOnboardingVersionKey' 'onboarding completion uses an explicit persisted version key'

if [[ "$(<"$SOURCE")" == *'GDRIVE_BACKUP_SECOND_SCHEDULE'* ]]; then
  printf '%s\n' 'not ok - onboarding introduces a second schedule key'
  failures=$((failures + 1))
else
  printf '%s\n' 'ok - onboarding source has no second schedule key'
fi

if (( failures > 0 )); then
  printf '%s onboarding build integration test(s) failed.\n' "$failures"
  exit 1
fi
printf '%s\n' 'All onboarding build integration tests passed.'
