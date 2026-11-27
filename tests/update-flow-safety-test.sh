#!/bin/bash
# Safety rules for the automatic updater. The detailed checks of URLs,
# checksums and signatures are in update-support-test.m; this test pins the
# structure of the flow so a later change cannot quietly weaken it.
# The checks are evaluated strings, so shellcheck cannot see their variables.
# shellcheck disable=SC2034,SC2016
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAIN="$ROOT/macos/GDriveBackupTiger/main.m"
FLOW="$ROOT/macos/GDriveBackupTiger/UpdateInstallMethods.inc"
SUPPORT="$ROOT/macos/GDriveBackupTiger/UpdateSupport.m"
failures=0
main_contents="$(<"$MAIN")"
flow_contents="$(<"$FLOW")"
support_contents="$(<"$SUPPORT")"

check() {
  if eval "$2"; then
    printf 'ok - %s\n' "$1"
  else
    printf 'not ok - %s\n' "$1"
    failures=$((failures + 1))
  fi
}

method_body() {
  /usr/bin/awk -v start="$2" '
    index($0, start) == 1 { in_method = 1 }
    in_method { print }
    in_method && /^}$/ { exit }
  ' "$1"
}

launch_method="$(method_body "$MAIN" '- (void)applicationDidFinishLaunching')"
schedule_method="$(method_body "$FLOW" '- (void)scheduleAutomaticUpdateChecks')"
install_method="$(method_body "$FLOW" '- (void)installUpdateVersion:')"
problem_method="$(method_body "$FLOW" '- (NSString *)updatePackageProblemAtPath:')"
download_method="$(method_body "$SUPPORT" '- (void)downloadVersion:')"

check "application launch never checks for updates immediately" \
  '[[ "$launch_method" != *"checkForUpdates:"* && "$launch_method" != *"checkCurrentVersion:"* ]]'
check "only the menu bar agent checks automatically, after a delay" \
  '[[ "$schedule_method" == *"if (!self.menubarOnlyMode"* && "$schedule_method" == *"dispatch_after"* ]]'
check "automatic checks can be switched off" \
  '[[ "$flow_contents" == *"automaticUpdateChecksEnabled"* && "$flow_contents" == *"toggleAutomaticUpdateChecks:"* ]]'
check "an update is never installed while a backup runs" \
  '[[ "$install_method" == *"backupIsRunningForUpdate"* ]]'
check "the installer runs only through the macOS administrator prompt" \
  '[[ "$flow_contents" == *"with administrator privileges"* && "$flow_contents" == *"/usr/sbin/installer -pkg"* &&
     "$flow_contents" != *"sudo "* && "$main_contents" != *"/usr/sbin/installer"* ]]'
check "the package path reaches the shell only as an argument" \
  '[[ "$flow_contents" == *"quoted form of (item 1 of argv)"* ]]'
check "the package must contain this app and pass the signature policy" \
  '[[ "$problem_method" == *"--payload-files"* && "$problem_method" == *"GDTUpdateSignatureProblem"* ]]'
check "the package is verified against the release checksum before it is returned" \
  '[[ "$download_method" == *"GDTExpectedSHA256"* && "$download_method" == *"GDTSHA256OfFile"* &&
     "$download_method" == *"checksum_mismatch"* ]]'
check "downloads use only the official repository and GitHub asset hosts" \
  '[[ "$support_contents" == *"/AlexanderSmyslowski/gdrive-tiger-backup/releases/download/"* &&
     "$support_contents" == *"willPerformHTTPRedirection"* &&
     "$support_contents" == *"https://api.github.com/repos/AlexanderSmyslowski/gdrive-tiger-backup/releases/latest"* ]]'

report_method="$(method_body "$FLOW" '- (void)reportInstalledUpdateAttempt:')"
check "the restarted app waits for the installer result instead of missing it" \
  '[[ "$report_method" == *"dispatch_after"* && "$report_method" == *"attempt < 60"* &&
     "$report_method" == *"removeItemAtPath"* ]]'

if (( failures > 0 )); then
  printf '%s update flow safety test(s) failed.\n' "$failures"
  exit 1
fi
printf '%s\n' 'All update flow safety tests passed.'
