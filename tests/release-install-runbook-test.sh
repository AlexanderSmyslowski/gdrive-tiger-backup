#!/bin/bash
# The assertions intentionally compare literal shell fragments from the
# extracted runbook; dollar signs and trailing backslashes must not expand.
# shellcheck disable=SC1003,SC2016
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLAN="$ROOT/docs/superpowers/plans/2026-08-01-automatic-retry-progress.md"
WORK_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/gdrive-runbook-test.XXXXXX")"
PUBLISH_BLOCK="$WORK_DIR/publish.sh"
INSTALL_BLOCK="$WORK_DIR/install.sh"

cleanup() {
  local status=$?
  trap - EXIT
  if [[ -d "$WORK_DIR" ]] && ! "$ROOT/scripts/trash-path.sh" "$WORK_DIR"; then
    printf 'not ok - unable to move runbook-test workspace to Trash: %s\n' "$WORK_DIR" >&2
    status=1
  fi
  exit "$status"
}
trap cleanup EXIT

extract_shell_block() {
  local begin_marker="$1"
  local end_marker="$2"
  local destination="$3"
  /usr/bin/awk -v begin_marker="$begin_marker" -v end_marker="$end_marker" '
    $0 == begin_marker {
      begin_count++
      inside = 1
      next
    }
    $0 == end_marker {
      end_count++
      inside = 0
      next
    }
    inside && $0 == "```bash" {
      fence_count++
      in_fence = 1
      next
    }
    inside && $0 == "```" {
      in_fence = 0
      next
    }
    inside && in_fence { print }
    END {
      if (begin_count != 1 || end_count != 1 || fence_count != 1 || in_fence) {
        exit 65
      }
    }
  ' "$PLAN" >"$destination"
}

assert_contains() {
  local file="$1"
  local expected="$2"
  local description="$3"
  if /usr/bin/grep -Fq -- "$expected" "$file"; then
    printf 'ok - %s\n' "$description"
  else
    printf 'not ok - %s\n' "$description" >&2
    exit 1
  fi
}

assert_not_contains() {
  local file="$1"
  local rejected="$2"
  local description="$3"
  if /usr/bin/grep -Fq -- "$rejected" "$file"; then
    printf 'not ok - %s\n' "$description" >&2
    exit 1
  fi
  printf 'ok - %s\n' "$description"
}

line_number() {
  local file="$1"
  local literal="$2"
  /usr/bin/awk -v literal="$literal" 'index($0, literal) { print NR; exit }' "$file"
}

assert_before() {
  local file="$1"
  local first="$2"
  local second="$3"
  local description="$4"
  local first_line second_line
  first_line="$(line_number "$file" "$first")"
  second_line="$(line_number "$file" "$second")"
  if [[ "$first_line" =~ ^[0-9]+$ && "$second_line" =~ ^[0-9]+$ ]] &&
     (( first_line < second_line )); then
    printf 'ok - %s\n' "$description"
  else
    printf 'not ok - %s\n' "$description" >&2
    exit 1
  fi
}

assert_next_line() {
  local file="$1"
  local marker="$2"
  local expected="$3"
  local description="$4"
  local marker_line actual
  marker_line="$(line_number "$file" "$marker")"
  if [[ ! "$marker_line" =~ ^[0-9]+$ ]]; then
    printf 'not ok - %s\n' "$description" >&2
    exit 1
  fi
  actual="$(/usr/bin/sed -n "$((marker_line + 1))p" "$file")"
  if [[ "$actual" == "$expected" ]]; then
    printf 'ok - %s\n' "$description"
  else
    printf 'not ok - %s\n' "$description" >&2
    exit 1
  fi
}

if ! extract_shell_block '<!-- GDT-RUNBOOK-PUBLISH:BEGIN -->' \
    '<!-- GDT-RUNBOOK-PUBLISH:END -->' "$PUBLISH_BLOCK"; then
  printf '%s\n' 'not ok - publication runbook has one extractable shell block' >&2
  exit 1
fi
if ! extract_shell_block '<!-- GDT-RUNBOOK-INSTALL:BEGIN -->' \
    '<!-- GDT-RUNBOOK-INSTALL:END -->' "$INSTALL_BLOCK"; then
  printf '%s\n' 'not ok - installation runbook has one extractable shell block' >&2
  exit 1
fi
printf '%s\n' 'ok - runbook shell blocks are uniquely extractable'

/bin/bash -n "$PUBLISH_BLOCK" "$INSTALL_BLOCK"
SHELLCHECK_BIN="$(command -v shellcheck)"
test -n "$SHELLCHECK_BIN" && test -x "$SHELLCHECK_BIN"
"$SHELLCHECK_BIN" -x "$PUBLISH_BLOCK" "$INSTALL_BLOCK"
printf '%s\n' 'ok - extracted runbook shell blocks pass bash -n and shellcheck'

assert_contains "$PUBLISH_BLOCK" 'readonly BASE_SHA=' \
  'publication pins the reviewed base commit'
assert_contains "$PUBLISH_BLOCK" \
  'readonly V243_SHA="ddbfe24250149e4da177d23d8d1476dbbc3873eb"' \
  'publication pins v2.4.3 to its reviewed historical commit'
assert_contains "$PUBLISH_BLOCK" \
  'git merge-base --is-ancestor "$V243_SHA" "$REVIEWED_HEAD"' \
  'publication proves v2.4.3 is in the reviewed branch history'
assert_contains "$PUBLISH_BLOCK" 'readonly REVIEWED_HEAD' \
  'publication captures an immutable reviewed head'
assert_contains "$PUBLISH_BLOCK" '"${REVIEWED_HEAD}:refs/heads/${BRANCH}"' \
  'publication pushes the reviewed object explicitly'
assert_contains "$PUBLISH_BLOCK" \
  'git fetch --no-tags origin "refs/heads/${BRANCH}:refs/remotes/origin/${BRANCH}"' \
  'publication materializes the exact remote-tracking ref after an object push'
assert_before "$PUBLISH_BLOCK" 'git push origin' 'git fetch --no-tags origin' \
  'publication fetches tracking state only after the immutable object push'
assert_not_contains "$PUBLISH_BLOCK" 'git branch --set-upstream-to=' \
  'publication does not depend on the repository-wide fetch refspec'
assert_contains "$PUBLISH_BLOCK" \
  'git rev-parse "refs/remotes/origin/${BRANCH}^{commit}"' \
  'publication verifies the fetched remote-tracking object'
assert_contains "$PUBLISH_BLOCK" 'headRefOid' \
  'publication verifies the pull-request head object'
assert_contains "$PUBLISH_BLOCK" 'baseRefOid' \
  'publication verifies the pull-request base object'
assert_contains "$PUBLISH_BLOCK" '--match-head-commit "$REVIEWED_HEAD"' \
  'merge is pinned to the reviewed head object'
assert_contains "$PUBLISH_BLOCK" '"$MERGED_SHA^1"' \
  'publication verifies the first merge parent'
assert_contains "$PUBLISH_BLOCK" '"$MERGED_SHA^2"' \
  'publication verifies the second merge parent'
assert_before "$PUBLISH_BLOCK" 'publish_release v2.4.3' 'publish_release v2.4.4' \
  'v2.4.3 is published and verified before v2.4.4'
assert_contains "$PUBLISH_BLOCK" '/releases/latest' \
  'publication verifies GitHub latest-release state'
assert_contains "$PUBLISH_BLOCK" 'GDrive-Backup-Tiger-${version}.pkg' \
  'each release verifies its exact installer asset'
assert_contains "$PUBLISH_BLOCK" 'SHA256SUMS.txt' \
  'each release verifies its checksum manifest'
assert_contains "$PUBLISH_BLOCK" 'make -C "$source_dir" test' \
  'each exact-tag export passes the complete test suite'
assert_contains "$PUBLISH_BLOCK" 'latest_tag=' \
  'latest-release verification is propagation-aware'
assert_before "$PUBLISH_BLOCK" 'publish_release v2.4.3' 'publish_release v2.4.4' \
  'release assets and latest state are checked sequentially'

assert_contains "$INSTALL_BLOCK" 'git archive --format=tar' \
  'installation exports immutable tagged source'
assert_contains "$INSTALL_BLOCK" 'git get-tar-commit-id' \
  'installation proves the export commit identity'
assert_before "$INSTALL_BLOCK" 'git get-tar-commit-id' 'APP_DIR="$STAGED_APP" build' \
  'tag identity is proven before the app build'
assert_contains "$INSTALL_BLOCK" 'ACTIVE_PROFILE_FILE' \
  'installation validates the active-profile selector'
assert_contains "$INSTALL_BLOCK" 'stat -f '\''%u'\''' \
  'installation validates active-profile ownership'
assert_contains "$INSTALL_BLOCK" 'stat -f '\''%Lp'\''' \
  'installation validates active-profile mode'
assert_contains "$INSTALL_BLOCK" 'ACTIVE_PROFILE_SIZE' \
  'installation enforces the exact default profile selector bytes'
assert_contains "$INSTALL_BLOCK" '64656661756c740a' \
  'installation requires the exact default profile value and trailing newline'
assert_contains "$INSTALL_BLOCK" 'GDRIVE_BACKUP_CONFIG_DIR' \
  'installation rejects a config-directory service override'
assert_contains "$INSTALL_BLOCK" 'GDRIVE_BACKUP_CONFIG \' \
  'installation rejects an explicit config-file service override'
assert_contains "$INSTALL_BLOCK" 'GDRIVE_BACKUP_LOCK \' \
  'installation rejects a lock-file service override'
assert_contains "$INSTALL_BLOCK" 'GDRIVE_BACKUP_SUMMARY_STATE_FILE' \
  'installation resolves or rejects summary-state overrides'
assert_contains "$INSTALL_BLOCK" 'GDRIVE_BACKUP_PROGRESS_STATE_FILE' \
  'installation resolves or rejects progress-state overrides'
assert_contains "$INSTALL_BLOCK" '/usr/bin/env -i' \
  'profile configuration is evaluated in a sanitized environment'
assert_contains "$INSTALL_BLOCK" 'canonical_config_manifest' \
  'installation records a canonical configuration manifest'
assert_contains "$INSTALL_BLOCK" 'unexpected symbolic link' \
  'canonical configuration manifests reject symbolic links'
assert_contains "$INSTALL_BLOCK" 'type=%s|path=%s|uid=%s|gid=%s|mode=%s|size=%s|sha256=%s' \
  'canonical manifest records type, path, ownership, mode, size, and content hash'
assert_contains "$INSTALL_BLOCK" '/usr/bin/find "$root" -print0' \
  'canonical manifest includes the configuration root itself'
assert_not_contains "$INSTALL_BLOCK" 'find "$root" -mindepth 1' \
  'canonical manifest does not omit configuration-root metadata'
assert_contains "$INSTALL_BLOCK" 'test ! -e "$APP_INCOMING" && test ! -L "$APP_INCOMING"' \
  'incoming app path rejects existing and dangling links'
assert_contains "$INSTALL_BLOCK" 'test ! -e "$SCRIPT_INCOMING" && test ! -L "$SCRIPT_INCOMING"' \
  'incoming script path rejects existing and dangling links'
assert_contains "$INSTALL_BLOCK" 'mktemp -d "$STAGE_PARENT/' \
  'installation creates an exclusive validated staging directory'
assert_contains "$INSTALL_BLOCK" 'mktemp -d "$ROLLBACK_PARENT/' \
  'installation creates an exclusive persistent rollback directory'
assert_contains "$INSTALL_BLOCK" 'stat -f '\''%d'\'' "$APP_TXN"' \
  'the app transaction is proven to share the destination filesystem'
assert_contains "$INSTALL_BLOCK" 'stat -f '\''%d'\'' "$SCRIPT_TXN"' \
  'the script transaction is proven to share the destination filesystem'
assert_contains "$INSTALL_BLOCK" \
  '/usr/bin/sudo /usr/bin/install -o 0 -g 0 -m 755 "$STAGED_SCRIPT" "$SCRIPT_INCOMING"' \
  'the incoming privileged script is installed root-owned'
assert_contains "$INSTALL_BLOCK" 'stat -f '\''%u:%g:%Lp'\'' "$SCRIPT_INCOMING"' \
  'incoming script ownership and mode are verified'
assert_contains "$INSTALL_BLOCK" 'stat -f '\''%u:%g:%Lp'\'' "$SCRIPT_FINAL"' \
  'final script ownership and mode are verified'
assert_contains "$INSTALL_BLOCK" 'stat -f '\''%u:%g:%Lp'\'' "$ROLLBACK/backup-google-drive.sh"' \
  'rollback script ownership and mode are verified'
assert_contains "$INSTALL_BLOCK" 'RECOVERY_ARMED=1' \
  'recovery is armed before service mutation'
assert_before "$INSTALL_BLOCK" 'RECOVERY_ARMED=1' '# FIRST_SERVICE_MUTATION' \
  'recovery state is trap-visible before the first bootout'
assert_next_line "$INSTALL_BLOCK" '# FIRST_SERVICE_MUTATION' \
  '/bin/launchctl bootout "$DOMAIN" "$SCHEDULE_PLIST"' \
  'the marked first service mutation is the schedule bootout'
assert_before "$INSTALL_BLOCK" '"$FLOCK_BIN" -n 8' '# FIRST_SERVICE_MUTATION' \
  'the effective backup lock is acquired before service mutation'
assert_contains "$INSTALL_BLOCK" 'assert_successful_terminal_backup_and_no_processes' \
  'terminal state and process absence share one fail-closed gate'
gate_count="$(/usr/bin/grep -Fc -- 'assert_successful_terminal_backup_and_no_processes' "$INSTALL_BLOCK")"
if (( gate_count >= 4 )); then
  printf '%s\n' 'ok - process/status gate covers pre-build, locked pre-bootout, post-quiesce, and final state'
else
  printf '%s\n' 'not ok - process/status gate covers pre-build, locked pre-bootout, post-quiesce, and final state' >&2
  exit 1
fi
assert_next_line "$INSTALL_BLOCK" '# PREBUILD_GATE' \
  'assert_successful_terminal_backup_and_no_processes' \
  'the pre-build gate runs before immutable source export'
assert_before "$INSTALL_BLOCK" '# PREBUILD_GATE' 'git archive --format=tar' \
  'the pre-build gate precedes archive extraction and build'
assert_next_line "$INSTALL_BLOCK" '# LOCKED_PRE_BOOTOUT_GATE' \
  'assert_successful_terminal_backup_and_no_processes' \
  'the locked terminal/process gate runs before service mutation'
assert_before "$INSTALL_BLOCK" '# LOCKED_PRE_BOOTOUT_GATE' '# FIRST_SERVICE_MUTATION' \
  'the locked gate precedes the first service bootout'
assert_next_line "$INSTALL_BLOCK" '# POST_QUIESCE_GATE' \
  'assert_successful_terminal_backup_and_no_processes' \
  'the terminal/process gate repeats after both services quiesce'
assert_before "$INSTALL_BLOCK" '# FIRST_SERVICE_MUTATION' '# POST_QUIESCE_GATE' \
  'post-quiesce verification follows the service bootouts'
assert_contains "$INSTALL_BLOCK" 'derive_effective_state' \
  'effective scheduled configuration is derived by one reusable contract'
derive_count="$(/usr/bin/grep -Fc -- 'derive_effective_state' "$INSTALL_BLOCK")"
if (( derive_count >= 4 )); then
  printf '%s\n' 'ok - effective state is derived before build, under lock, and after reload'
else
  printf '%s\n' 'not ok - effective state is derived before build, under lock, and after reload' >&2
  exit 1
fi
assert_contains "$INSTALL_BLOCK" '# PREBUILD_SNAPSHOT' \
  'configuration and plists are bound before the long build'
assert_before "$INSTALL_BLOCK" '# PREBUILD_SNAPSHOT' 'git archive --format=tar' \
  'the immutable pre-build snapshot precedes archive tests and build'
assert_contains "$INSTALL_BLOCK" '# LOCKED_SNAPSHOT_REVALIDATION' \
  'configuration, plists, loaded jobs, and effective paths are rebound under lock'
assert_before "$INSTALL_BLOCK" '# LOCKED_SNAPSHOT_REVALIDATION' '# FIRST_SERVICE_MUTATION' \
  'locked snapshot validation completes before service mutation'
assert_next_line "$INSTALL_BLOCK" '# LOCKED_SNAPSHOT_REVALIDATION' \
  'assert_runtime_snapshot_matches_prebuild "$STAGE/config-locked.manifest" "$STAGE/locked-effective-state.sh"' \
  'the complete runtime binding runs at the final pre-mutation snapshot'
locked_snapshot_line="$(line_number "$INSTALL_BLOCK" '# LOCKED_SNAPSHOT_REVALIDATION')"
recovery_armed_line="$(line_number "$INSTALL_BLOCK" 'RECOVERY_ARMED=1')"
first_mutation_line="$(line_number "$INSTALL_BLOCK" '# FIRST_SERVICE_MUTATION')"
if (( recovery_armed_line == locked_snapshot_line + 4 &&
      first_mutation_line == locked_snapshot_line + 5 )); then
  printf '%s\n' 'ok - only the terminal gate and recovery arm separate binding from bootout'
else
  printf '%s\n' 'not ok - only the terminal gate and recovery arm separate binding from bootout' >&2
  exit 1
fi
assert_contains "$INSTALL_BLOCK" 'assert_loaded_service_contract' \
  'loaded launchd definitions are checked without trusting disk plists alone'
loaded_contract_count="$(/usr/bin/grep -Fc -- 'assert_loaded_service_contract' "$INSTALL_BLOCK")"
if (( loaded_contract_count >= 7 )); then
  printf '%s\n' 'ok - both loaded jobs are checked before build, under lock, and after reload'
else
  printf '%s\n' 'not ok - both loaded jobs are checked before build, under lock, and after reload' >&2
  exit 1
fi
assert_contains "$INSTALL_BLOCK" 'assert_manager_environment_clean' \
  'launchd manager environment overrides are checked without reading values'
assert_not_contains "$INSTALL_BLOCK" 'launchctl getenv' \
  'manager environment validation does not trust launchctl getenv exit status'
manager_environment_count="$(/usr/bin/grep -Fc -- \
  'assert_manager_environment_clean' "$INSTALL_BLOCK")"
if (( manager_environment_count >= 4 )); then
  printf '%s\n' 'ok - manager environment is checked before build, under lock, and after reload'
else
  printf '%s\n' 'not ok - manager environment is checked before build, under lock, and after reload' >&2
  exit 1
fi
assert_contains "$INSTALL_BLOCK" '# FINAL_RUNTIME_REVALIDATION' \
  'reloaded services and effective state are rebound during final verification'
assert_before "$INSTALL_BLOCK" '# FINAL_RUNTIME_REVALIDATION' \
  '# FINAL_STATUS_PROCESS_GATE' \
  'final runtime rebinding precedes the final status and process gate'
assert_next_line "$INSTALL_BLOCK" '# FINAL_STATUS_PROCESS_GATE' \
  '  assert_successful_terminal_backup_and_no_processes' \
  'the final process gate uses the refreshed effective status path'
assert_contains "$INSTALL_BLOCK" 'GDRIVE_BACKUP_TRIGGER="$SCHEDULE_TRIGGER"' \
  'sanitized evaluation receives the verified schedule trigger'
assert_contains "$INSTALL_BLOCK" 'BACKUP_ASSUME_YES="$SCHEDULE_ASSUME_YES"' \
  'sanitized evaluation receives the verified assume-yes value'
assert_not_contains "$INSTALL_BLOCK" \
  "/usr/bin/grep -Fxq 'GDRIVE_BACKUP_PROFILE_ID=default'" \
  'valid shell-quoted default profile ids are not rejected textually'
assert_contains "$INSTALL_BLOCK" 'assert_default_profile_selection' \
  'the runbook mirrors the backup script profile-selection contract'
profile_selection_count="$(/usr/bin/grep -Fc -- \
  'assert_default_profile_selection' "$INSTALL_BLOCK")"
if (( profile_selection_count >= 4 )); then
  printf '%s\n' 'ok - profile selection is rechecked before build, under lock, and after reload'
else
  printf '%s\n' 'not ok - profile selection is rechecked before build, under lock, and after reload' >&2
  exit 1
fi
assert_contains "$INSTALL_BLOCK" '"GDRIVE_BACKUP_PROFILE_ID=$profile_id"' \
  'profile selection accepts the exact unquoted generated form'
assert_contains "$INSTALL_BLOCK" "\"GDRIVE_BACKUP_PROFILE_ID='\$profile_id'\"" \
  'profile selection accepts the exact single-quoted generated form'
assert_contains "$INSTALL_BLOCK" '"GDRIVE_BACKUP_PROFILE_ID=\"$profile_id\""' \
  'profile selection accepts the exact double-quoted generated form'
assert_contains "$INSTALL_BLOCK" '(^|[[:space:]/])rclone([[:space:]]|$)' \
  'process gate detects bare and path-qualified rclone commands'
assert_contains "$INSTALL_BLOCK" 'codesign -d --entitlements :-' \
  'entitlements are extracted explicitly'
assert_contains "$INSTALL_BLOCK" 'plutil -lint "$ENTITLEMENTS_PLIST"' \
  'the extracted entitlement plist is parsed'
assert_contains "$INSTALL_BLOCK" 'LEFTOVER' \
  'recoverable transaction artifacts are reported'
assert_not_contains "$INSTALL_BLOCK" '/usr/bin/trash' \
  'installation and recovery do not depend on /usr/bin/trash'
entitlement_line="$(line_number "$INSTALL_BLOCK" 'codesign -d --entitlements :-')"
if /usr/bin/sed -n "${entitlement_line}p" "$INSTALL_BLOCK" | /usr/bin/grep -Fq -- '|| true'; then
  printf '%s\n' 'not ok - entitlement extraction fails closed' >&2
  exit 1
fi
printf '%s\n' 'ok - entitlement extraction fails closed'
assert_before "$INSTALL_BLOCK" '# FINAL_VERIFICATION_UNDER_LOCK' '"$FLOCK_BIN" -u 8' \
  'the effective backup lock remains held through final verification'
assert_next_line "$INSTALL_BLOCK" '# FINAL_VERIFICATION_UNDER_LOCK' \
  'assert_final_install_state' \
  'the marked under-lock step executes the complete final verifier'
assert_before "$INSTALL_BLOCK" 'trap '\''handle_install_signal'\'' HUP INT TERM' 'RECOVERY_ARMED=1' \
  'signal recovery is installed before it is armed'
assert_next_line "$INSTALL_BLOCK" '# RECOVERY_SIGNAL_GUARD' \
  "  trap '' HUP INT TERM" \
  'recovery ignores follow-up termination signals until rollback completes'

assert_contains "$PLAN" \
  'Review: every commit in `e948ec29910210a53d587f0a8b9c309ea6238cef...HEAD`' \
  'Task 6 states the complete reviewed diff truthfully'

printf '%s\n' 'All release/install runbook checks passed.'
