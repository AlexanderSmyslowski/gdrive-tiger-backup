#!/bin/bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/macos/GDriveBackupTiger/main.m"
contents="$(<"$SOURCE")"
failures=0

ok() {
  printf '%s\n' "ok - $1"
}

not_ok() {
  printf '%s\n' "not ok - $1"
  failures=$((failures + 1))
}

if [[ "$contents" == *'GDTOnboardingNeedsPresentation(GDTReadConfigDictionary())'* &&
      "$contents" == *'[self showOnboardingWindow];'* &&
      "$contents" == *'[self showSetupWindow];'* ]]; then
  ok "setup launch chooses onboarding only for incomplete profiles"
else
  not_ok "setup launch does not clearly separate onboarding from expert setup"
fi

if [[ "$contents" == *'if ([mode isEqualToString:@"overview"]'* &&
      "$contents" == *'self.setupMode = YES;'* &&
      "$contents" == *'GDTOnboardingNeedsPresentation(GDTReadConfigDictionary())'* ]]; then
  ok "a new user opening the app sees onboarding before the overview"
else
  not_ok "default app launch can still skip first-run onboarding"
fi

if [[ "$contents" == *'- (void)showOnboardingWindow'* &&
      "$contents" == *'onboardingView.advancedSetupHandler'* &&
      "$contents" == *'strongSelf showSetupWindow'* ]]; then
  ok "onboarding provides an explicit expert setup escape hatch"
else
  not_ok "onboarding can strand users without expert setup"
fi

unknown_method="$(
  /usr/bin/awk '
    /^- \(void\)presentSetupForUnknownExternalVolumeDescriptor:/ { in_method = 1 }
    in_method { print }
    in_method && /^}$/ { exit }
  ' "$SOURCE"
)"
if [[ "$unknown_method" == *'[self showSetupWindow];'* &&
      "$unknown_method" != *'showOnboardingWindow'* ]]; then
  ok "explicit unknown-volume setup bypasses the first-run flow"
else
  not_ok "unknown-volume setup was routed through onboarding"
fi

mount_method="$(
  /usr/bin/awk '
    /^- \(void\)workspaceVolumeDidMount:/ { in_method = 1 }
    in_method { print }
    in_method && /^}$/ { exit }
  ' "$SOURCE"
)"
if [[ "$mount_method" != *'showOnboardingWindow'* ]]; then
  ok "mount events do not activate onboarding"
else
  not_ok "mount events can steal focus for onboarding"
fi

if (( failures > 0 )); then
  printf '%s onboarding routing test(s) failed.\n' "$failures"
  exit 1
fi
printf '%s\n' 'All onboarding routing tests passed.'
