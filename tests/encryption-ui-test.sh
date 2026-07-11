#!/bin/bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAIN_SOURCE="$ROOT/macos/GDriveBackupTiger/main.m"
LOCALIZATION_SOURCE="$ROOT/macos/GDriveBackupTiger/Localization.m"
failures=0

check_contains() {
  local file="$1"
  local expected="$2"
  local description="$3"
  if /usr/bin/grep -Fq "$expected" "$file"; then
    printf 'ok - %s\n' "$description"
  else
    printf 'not ok - %s\n' "$description"
    failures=$((failures + 1))
  fi
}

check_absent() {
  local file="$1"
  local forbidden="$2"
  local description="$3"
  if /usr/bin/grep -Fq "$forbidden" "$file"; then
    printf 'not ok - %s\n' "$description"
    failures=$((failures + 1))
  else
    printf 'ok - %s\n' "$description"
  fi
}

check_contains "$MAIN_SOURCE" '@property(nonatomic, strong) NSButton *encryptionCheckbox;' \
  'setup owns an APFS encryption checkbox'
check_contains "$MAIN_SOURCE" 'config[@"GDRIVE_BACKUP_ENCRYPTION"]' \
  'setup restores the encryption mode from config'
check_contains "$MAIN_SOURCE" 'self.encryptionCheckbox.buttonType = NSButtonTypeSwitch;' \
  'encryption control is a checkbox'
check_contains "$MAIN_SOURCE" 'self.encryptionCheckbox.title = T(self.language, @"encryptionAPFS");' \
  'checkbox title is localized'
check_contains "$MAIN_SOURCE" 'self.encryptionCheckbox.toolTip = T(self.language, @"encryptionAPFSTip");' \
  'no-password explanation is exposed as a localized tooltip'
check_contains "$MAIN_SOURCE" 'self.encryptionCheckbox.accessibilityHelp = self.encryptionCheckbox.toolTip;' \
  'VoiceOver receives the same no-password explanation'
check_contains "$MAIN_SOURCE" 'self.targetPopup.action = @selector(targetChanged:);' \
  'target changes refresh dependent controls'
check_contains "$MAIN_SOURCE" 'BOOL preserveConfiguredAPFSTarget = [configuredTarget isEqualToString:@"apfs"];' \
  'setup distinguishes an explicitly saved APFS target from a default'
check_contains "$MAIN_SOURCE" '[self refreshMountedNASAllowingTargetAutoSelection:!preserveConfiguredAPFSTarget];' \
  'initial discovery preserves an explicitly saved APFS target'
check_contains "$MAIN_SOURCE" 'if (allowAutomaticTargetSelection && !currentMount.length && wantedHost.length && [volumeHost isEqualToString:wantedHost]) {' \
  'host-based NAS auto-selection obeys the initial preservation guard'
check_contains "$MAIN_SOURCE" 'if (allowAutomaticTargetSelection && !currentMount.length && !autoSelection && volumes.count == 1) {' \
  'single-NAS auto-selection obeys the initial preservation guard'
check_contains "$MAIN_SOURCE" 'self.encryptionCheckbox.enabled = isAPFSTarget;' \
  'NAS disables the APFS-only checkbox'

update_target_method="$(/usr/bin/awk '
  /^- \(void\)updateTargetControls/ { in_method = 1 }
  in_method { print }
  in_method && /^}$/ { exit }
' "$MAIN_SOURCE")"
if [[ "$update_target_method" != *'self.encryptionCheckbox.state = NSControlStateValueOff;'* ]]; then
  printf '%s\n' 'ok - temporary NAS selection preserves the APFS protection choice'
else
  printf '%s\n' 'not ok - temporary NAS selection silently clears the APFS protection choice'
  failures=$((failures + 1))
fi
check_contains "$MAIN_SOURCE" 'BOOL requiresEncryptedAPFS = [target isEqualToString:@"apfs"] && self.encryptionCheckbox.state == NSControlStateValueOn;' \
  'the checked state can request encryption only for an APFS target'
check_contains "$MAIN_SOURCE" 'updates[@"GDRIVE_BACKUP_ENCRYPTION"] = requiresEncryptedAPFS ? @"apfs" : @"none";' \
  'setup persists only the supported apfs and none modes'

for key in encryptionAPFS encryptionAPFSTip; do
  occurrence_count="$(/usr/bin/grep -Fc "@\"${key}\":" "$LOCALIZATION_SOURCE")"
  if [[ "$occurrence_count" == "7" ]]; then
    printf 'ok - %s is translated in all seven languages\n' "$key"
  else
    printf 'not ok - expected seven %s translations, found %s\n' "$key" "$occurrence_count"
    failures=$((failures + 1))
  fi
done

check_absent "$MAIN_SOURCE" 'NSSecureTextField' \
  'setup adds no password field'
check_absent "$MAIN_SOURCE" 'GDRIVE_BACKUP_PASSWORD' \
  'setup never reads or writes a password setting'

if (( failures > 0 )); then
  printf '%s encryption UI regression check(s) failed.\n' "$failures"
  exit 1
fi

printf '%s\n' 'All encryption UI regression checks passed.'
