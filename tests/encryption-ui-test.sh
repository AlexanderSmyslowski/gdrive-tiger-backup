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

check_contains "$MAIN_SOURCE" '@property(nonatomic, strong) NSPopUpButton *encryptionPopup;' \
  'setup owns one native encryption mode popup'
check_contains "$MAIN_SOURCE" '@property(nonatomic, strong) NSTextField *cryptRemoteField;' \
  'setup owns an explicit crypt remote field'
check_contains "$MAIN_SOURCE" 'config[@"GDRIVE_BACKUP_ENCRYPTION"]' \
  'setup restores the encryption mode from config'
check_contains "$MAIN_SOURCE" 'self.encryptionPopup = [[NSPopUpButton alloc]' \
  'encryption modes use a native popup instead of stacked switches'
check_contains "$MAIN_SOURCE" '@[T(self.language, @"encryptionRcloneCrypt"), @"rclone-crypt"]' \
  'rclone crypt is a first-class encryption mode'
check_contains "$MAIN_SOURCE" 'self.cryptRemoteField.toolTip = T(self.language, @"encryptionRcloneTip");' \
  'the crypt remote field explains that rclone owns the key'
check_contains "$MAIN_SOURCE" 'self.cryptRemoteField.accessibilityHelp = self.cryptRemoteField.toolTip;' \
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
check_contains "$MAIN_SOURCE" 'apfsItem.enabled = isAPFSTarget;' \
  'NAS disables only the APFS option while keeping rclone crypt available'

update_target_method="$(/usr/bin/awk '
  /^- \(void\)updateTargetControls/ { in_method = 1 }
  in_method { print }
  in_method && /^}$/ { exit }
' "$MAIN_SOURCE")"
if [[ "$update_target_method" != *'selectItemWithTitle'* &&
      "$update_target_method" != *'selectItemAtIndex:0'* ]]; then
  printf '%s\n' 'ok - temporary NAS selection preserves the APFS protection choice'
else
  printf '%s\n' 'not ok - temporary NAS selection silently clears the APFS protection choice'
  failures=$((failures + 1))
fi
check_contains "$MAIN_SOURCE" 'NSString *encryption = self.encryptionPopup.selectedItem.representedObject ?: @"none";' \
  'setup persists the selected native encryption mode'
check_contains "$MAIN_SOURCE" 'updates[@"GDRIVE_BACKUP_CRYPT_REMOTE"] = self.cryptRemoteField.stringValue ?: @"";' \
  'setup persists only the crypt remote name and no key material'
check_contains "$MAIN_SOURCE" 'BOOL usesRcloneCrypt = [encryption isEqualToString:@"rclone-crypt"];' \
  'dependent crypt controls appear only for the rclone mode'
check_contains "$MAIN_SOURCE" '[GDTCryptRestoreCatalog productionCatalogWithRemoteName:cryptRemote' \
  'restore browser selects the crypt catalog for encrypted profiles'
check_contains "$MAIN_SOURCE" '[GDTCryptRestoreCopier productionCopierWithRemoteName:cryptRemote' \
  'restore browser selects the crypt verifier for encrypted profiles'
check_contains "$MAIN_SOURCE" 'version[@"remotePath"]' \
  'restore actions accept logical crypt paths without exposing physical ciphertext names'

for key in encryptionLabel encryptionNone encryptionAPFS encryptionAPFSTip encryptionRcloneCrypt encryptionRcloneTip cryptRemoteLabel; do
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
check_absent "$MAIN_SOURCE" 'GDRIVE_BACKUP_CRYPT_PASSWORD' \
  'setup never invents a crypt password setting'

if (( failures > 0 )); then
  printf '%s encryption UI regression check(s) failed.\n' "$failures"
  exit 1
fi

printf '%s\n' 'All encryption UI regression checks passed.'
