# Automatic Retry Progress Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a truthful, passive, live per-phase progress state for automatic GDrive retries while replacing the stale “retry in 30 minutes” notification and never opening a foreground window.

**Architecture:** The backup shell writes a private atomic `current-progress.status` beside the active profile's `last-run.status` for every real lock-owning run. A small Objective-C support module validates that telemetry against the current run summary, and the persistent controller feeds one shared snapshot to the overview, menu bar, and retry-running notification. Foreground presentation remains a separate decision, so scheduled work stays headless.

**Tech Stack:** Bash 3.2-compatible shell, Objective-C with Cocoa/Foundation/UserNotifications, launchd, rclone statistics, Make, shell and Objective-C executable tests, Universal 2 macOS build.

## Global Constraints

- Scheduled and retry runs remain headless and never activate the app.
- No global percentage across all Google Drive areas; every percentage is labeled as the current phase.
- No notification is emitted for each percentage update.
- Progress telemetry contains no file names, source directory names, credentials, remote configuration, Shared Drive names, or raw log lines.
- Every persistent write is private (`0600`) and atomic.
- Invalid, stale, cross-profile, mismatched-PID, or terminal progress can only fall back to an indeterminate state.
- The unresolved failure remains latched until a newer successful automatic run or explicit human dismissal.
- All seven supported languages and VoiceOver receive complete strings and semantics.
- No installed app, installed script, controller, LaunchAgent, profile, schedule, credential, NAS data, or active backup process may be changed while a backup is running.
- The existing untracked `AGENTS.md` and `tests/package-entitlement-safety-test 2.sh` are not product inputs and must not be staged by this plan.

---

### Task 1: Preserve the reviewed v2.4.3 baseline and isolate v2.4.4 work

**Files:**
- Review and commit only the existing v2.4.3 product changes in `CHANGELOG.md`, `Makefile`, `README.md`, `bin/backup-google-drive.sh`, `docs/version-history.md`, `install.sh`, `macos/GDriveBackupTiger/ConfigSupport.h`, `macos/GDriveBackupTiger/ConfigSupport.m`, `macos/GDriveBackupTiger/Info.plist`, `macos/GDriveBackupTiger/NetworkMountSupport.h`, `macos/GDriveBackupTiger/NetworkMountSupport.m`, `macos/GDriveBackupTiger/NotificationSupport.m`, `macos/GDriveBackupTiger/main.m`, `tests/backup-control-test.sh`, `tests/backup-outcome-test.sh`, `tests/nas-mount-url-test.m`, `tests/network-mount-support-test.m`, `tests/notification-integration-test.m`, `tests/notification-support-test.m`, and `tests/release-metadata-test.sh`.
- Preserve without staging: `AGENTS.md`, `tests/package-entitlement-safety-test 2.sh`.

**Interfaces:**
- Consumes: the current dirty v2.4.3 Build 27 working tree and commit `2074718` containing the approved design.
- Produces: a clean, reviewable v2.4.3 baseline commit and branch `codex/automatic-retry-progress-v2-4-4` for the feature tasks.

- [ ] **Step 1: Load reviewed project memory before implementation**

```bash
/Users/alexandersmyslowski/Projects/central-agent-data-hub/scripts/agent_start.sh \
  --project gdrive-tiger-backup \
  --query "implement passive automatic retry progress and persistent dismissal semantics" \
  --review
```

Expected: reviewed, non-sensitive project context is available. If the Hub is
unavailable, record that limitation and continue from the committed design and
plan only; do not guess, import another project's memory, or write unreviewed
claims.

- [ ] **Step 2: Prove the installed backup is still isolated from repository work**

```bash
backup_process_snapshot() {
  local excluded="," pid
  pid="$(/bin/sh -c 'printf "%s" "$PPID"')"
  while [[ "$pid" =~ ^[0-9]+$ && "$pid" -gt 1 ]]; do
    excluded="${excluded}${pid},"
    pid="$(ps -p "$pid" -o ppid= | tr -d ' ')"
  done
  ps -axo pid=,ppid=,command= | awk -v excluded="$excluded" '
    index(excluded, "," $1 ",") == 0 &&
    /backup-google-drive|\/rclone( |$)/ && $0 !~ /awk/ {print}'
}
sed -n -E '/^(status|pid|started_at|finished_at|exit_code|trigger)=/p' \
  "$HOME/Library/Application Support/GDrive Backup Tiger/profiles/default/last-run.status"
backup_process_snapshot
```

Expected: if `status=running` or a matching process exists, continue only with repository edits and tests; do not run `make install`, `install.sh`, `launchctl bootout`, or copy to `/Applications` or `/usr/local/bin`.

- [ ] **Step 3: Review the exact baseline scope**

```bash
git status --short
git diff --check
git diff --stat -- \
  CHANGELOG.md Makefile README.md bin/backup-google-drive.sh docs/version-history.md \
  install.sh macos/GDriveBackupTiger tests
```

Expected: no conflict markers or whitespace errors; `AGENTS.md` and the duplicate `* 2.sh` file remain outside the staged set.

- [ ] **Step 4: Run the existing v2.4.3 regression suite before recording the baseline**

```bash
make test
```

Expected: exit 0. A failure must be diagnosed as a baseline defect before any retry-progress production code is written.

- [ ] **Step 5: Commit only the reviewed v2.4.3 product state**

```bash
git add CHANGELOG.md Makefile README.md bin/backup-google-drive.sh \
  docs/version-history.md install.sh \
  macos/GDriveBackupTiger/ConfigSupport.h \
  macos/GDriveBackupTiger/ConfigSupport.m \
  macos/GDriveBackupTiger/Info.plist \
  macos/GDriveBackupTiger/NetworkMountSupport.h \
  macos/GDriveBackupTiger/NetworkMountSupport.m \
  macos/GDriveBackupTiger/NotificationSupport.m \
  macos/GDriveBackupTiger/main.m \
  tests/backup-control-test.sh tests/backup-outcome-test.sh \
  tests/nas-mount-url-test.m tests/network-mount-support-test.m \
  tests/notification-integration-test.m tests/notification-support-test.m \
  tests/release-metadata-test.sh
git diff --cached --check
git commit -m "feat: mount NAS backups silently in v2.4.3"
```

Expected: one baseline commit; unrelated untracked files remain untracked.

- [ ] **Step 6: Create the feature branch**

```bash
git switch -c codex/automatic-retry-progress-v2-4-4
```

Expected: the current branch is `codex/automatic-retry-progress-v2-4-4` and the baseline product files are clean.

---

### Task 2: Add a private profile-scoped progress protocol

**Files:**
- Create: `macos/GDriveBackupTiger/BackupProgressSupport.h`
- Create: `macos/GDriveBackupTiger/BackupProgressSupport.m`
- Create: `tests/progress-support-test.m`
- Modify: `Makefile`
- Modify: `tests/backup-outcome-test.sh`
- Modify: `bin/backup-google-drive.sh`

**Interfaces:**
- Consumes: `last-run.status` fields `protocol`, `status`, `pid`, `started_at`, `trigger`, and `retry_attempt`; existing rclone progress lines; existing `cleanup_temp_file` and atomic-write patterns.
- Produces: `GDTBackupProgressPathForSummaryPath`, `GDTReadBackupProgressAtPath`, and `GDTValidatedBackupProgressForValues`; an atomic `current-progress.status` protocol for every real backup owner.

- [ ] **Step 1: Declare the wished-for Objective-C API in the failing test**

Create `tests/progress-support-test.m` with real parser and validator expectations:

```objc
#import <Foundation/Foundation.h>
#include <unistd.h>
#import "BackupProgressSupport.h"

static int failures = 0;
static void Assert(BOOL condition, NSString *message) {
    if (condition) printf("ok - %s\n", message.UTF8String);
    else { printf("not ok - %s\n", message.UTF8String); failures++; }
}

int main(void) {
    @autoreleasepool {
        NSTimeInterval now = NSDate.date.timeIntervalSince1970;
        NSString *pid = [NSString stringWithFormat:@"%d", getpid()];
        NSString *started = [NSString stringWithFormat:@"%.0f", now - 10];
        NSDictionary *summary = @{
            @"protocol": @"1", @"status": @"running", @"pid": pid,
            @"started_at": started, @"trigger": @"schedule-retry",
            @"retry_attempt": @"1"
        };
        NSDictionary *progress = @{
            @"protocol": @"1", @"profile_id": @"default", @"pid": pid,
            @"started_at": started, @"trigger": @"schedule-retry",
            @"retry_attempt": @"1", @"label": @"Shared Drive",
            @"phase": @"3/5", @"percent": @"63",
            @"detail": @"1.2 GiB / 1.9 GiB, 12.4 MiB/s, ETA 58s",
            @"updated_at": [NSString stringWithFormat:@"%.0f", now]
        };
        NSDictionary *accepted = GDTValidatedBackupProgressForValues(
            progress, summary, @"running", @"default", now);
        Assert([accepted[@"percent"] isEqualToString:@"63"] &&
               [accepted[@"phase"] isEqualToString:@"3/5"],
               @"matching live progress is accepted");
        Assert([GDTBackupProgressPathForSummaryPath(@"/tmp/default/last-run.status")
                   isEqualToString:@"/tmp/default/current-progress.status"],
               @"progress path stays beside the profile summary");

        NSMutableDictionary *crossProfile = [progress mutableCopy];
        crossProfile[@"profile_id"] = @"archive";
        Assert(GDTValidatedBackupProgressForValues(
                   crossProfile, summary, @"running", @"default", now) == nil,
               @"cross-profile progress is rejected");

        NSMutableDictionary *wrongProtocol = [progress mutableCopy];
        wrongProtocol[@"protocol"] = @"2";
        Assert(GDTValidatedBackupProgressForValues(
                   wrongProtocol, summary, @"running", @"default", now) == nil,
               @"unknown progress protocols are rejected");

        NSMutableDictionary *stale = [progress mutableCopy];
        stale[@"updated_at"] = [NSString stringWithFormat:@"%.0f", now - 61];
        Assert(GDTValidatedBackupProgressForValues(
                   stale, summary, @"running", @"default", now) == nil,
               @"stale progress is rejected");

        NSMutableDictionary *wrongPID = [progress mutableCopy];
        wrongPID[@"pid"] = @"99999999";
        Assert(GDTValidatedBackupProgressForValues(
                   wrongPID, summary, @"running", @"default", now) == nil,
               @"mismatched process progress is rejected");

        NSMutableDictionary *deadSummary = [summary mutableCopy];
        deadSummary[@"pid"] = @"99999999";
        Assert(GDTValidatedBackupProgressForValues(
                   wrongPID, deadSummary, @"running", @"default", now) == nil,
               @"matching telemetry for a dead process is rejected");

        NSMutableDictionary *wrongStart = [progress mutableCopy];
        wrongStart[@"started_at"] = [NSString stringWithFormat:@"%lld",
            started.longLongValue - 1];
        Assert(GDTValidatedBackupProgressForValues(
                   wrongStart, summary, @"running", @"default", now) == nil,
               @"mismatched start times are rejected");

        NSMutableDictionary *wrongTrigger = [progress mutableCopy];
        wrongTrigger[@"trigger"] = @"schedule";
        Assert(GDTValidatedBackupProgressForValues(
                   wrongTrigger, summary, @"running", @"default", now) == nil,
               @"mismatched triggers are rejected");

        NSMutableDictionary *wrongRetry = [progress mutableCopy];
        wrongRetry[@"retry_attempt"] = @"2";
        Assert(GDTValidatedBackupProgressForValues(
                   wrongRetry, summary, @"running", @"default", now) == nil,
               @"mismatched retry attempts are rejected");

        NSMutableDictionary *future = [progress mutableCopy];
        future[@"updated_at"] = [NSString stringWithFormat:@"%.0f", now + 2];
        Assert(GDTValidatedBackupProgressForValues(
                   future, summary, @"running", @"default", now) == nil,
               @"future progress is rejected");

        NSMutableDictionary *missingIdentity = [progress mutableCopy];
        [missingIdentity removeObjectForKey:@"started_at"];
        Assert(GDTValidatedBackupProgressForValues(
                   missingIdentity, summary, @"running", @"default", now) == nil,
               @"missing identity fields are rejected");

        NSMutableDictionary *unsafe = [progress mutableCopy];
        unsafe[@"detail"] = @"file-name.pdf\nsecret";
        Assert(GDTValidatedBackupProgressForValues(
                   unsafe, summary, @"running", @"default", now) == nil,
               @"multiline detail is rejected");

        NSMutableDictionary *rawLogDetail = [progress mutableCopy];
        rawLogDetail[@"detail"] = @"secret-file.pdf: Failed to copy";
        Assert(GDTValidatedBackupProgressForValues(
                   rawLogDetail, summary, @"running", @"default", now) == nil,
               @"arbitrary rclone log text is rejected");

        NSMutableDictionary *outOfRange = [progress mutableCopy];
        outOfRange[@"percent"] = @"101";
        Assert(GDTValidatedBackupProgressForValues(
                   outOfRange, summary, @"running", @"default", now) == nil,
               @"out-of-range percentages are rejected");

        NSMutableDictionary *impossiblePhase = [progress mutableCopy];
        impossiblePhase[@"phase"] = @"6/5";
        Assert(GDTValidatedBackupProgressForValues(
                   impossiblePhase, summary, @"running", @"default", now) == nil,
               @"impossible phases are rejected");

        NSMutableDictionary *unknownLabel = [progress mutableCopy];
        unknownLabel[@"label"] = @"THE ONE";
        Assert(GDTValidatedBackupProgressForValues(
                   unknownLabel, summary, @"running", @"default", now) == nil,
               @"source names cannot become public progress labels");

        NSMutableDictionary *preparing = [progress mutableCopy];
        preparing[@"label"] = @"preparing";
        [preparing removeObjectForKey:@"phase"];
        [preparing removeObjectForKey:@"percent"];
        [preparing removeObjectForKey:@"detail"];
        Assert(GDTValidatedBackupProgressForValues(
                   preparing, summary, @"running", @"default", now) != nil,
               @"a valid preparation record remains indeterminate");

        NSString *fixtureRoot = NSProcessInfo.processInfo.environment[
            @"GDRIVE_PROGRESS_TEST_DIR"];
        NSString *validPath = [fixtureRoot
            stringByAppendingPathComponent:@"valid.status"];
        NSMutableString *validContent = [NSMutableString string];
        for (NSString *key in @[@"protocol", @"profile_id", @"pid",
                                 @"started_at", @"trigger", @"retry_attempt",
                                 @"label", @"phase", @"percent", @"detail",
                                 @"updated_at"]) {
            [validContent appendFormat:@"%@=%@\n", key, progress[key]];
        }
        [validContent writeToFile:validPath atomically:YES
                         encoding:NSUTF8StringEncoding error:nil];
        [NSFileManager.defaultManager setAttributes:
            @{NSFilePosixPermissions: @0600} ofItemAtPath:validPath error:nil];
        Assert([GDTReadBackupProgressAtPath(validPath)[@"percent"]
                   isEqualToString:@"63"],
               @"a private valid progress record is parsed");

        NSString *duplicatePath = [fixtureRoot
            stringByAppendingPathComponent:@"duplicate.status"];
        NSString *duplicateContent = [validContent
            stringByAppendingString:@"protocol=1\n"];
        [duplicateContent writeToFile:duplicatePath
            atomically:YES encoding:NSUTF8StringEncoding error:nil];
        [NSFileManager.defaultManager setAttributes:
            @{NSFilePosixPermissions: @0600} ofItemAtPath:duplicatePath error:nil];
        Assert(GDTReadBackupProgressAtPath(duplicatePath) == nil,
               @"duplicate keys are rejected while parsing");

        NSString *missingPath = [fixtureRoot
            stringByAppendingPathComponent:@"missing.status"];
        NSString *missingContent = [validContent
            stringByReplacingOccurrencesOfString:
                [NSString stringWithFormat:@"updated_at=%@\n", progress[@"updated_at"]]
                                      withString:@""];
        [missingContent writeToFile:missingPath atomically:YES
                           encoding:NSUTF8StringEncoding error:nil];
        [NSFileManager.defaultManager setAttributes:
            @{NSFilePosixPermissions: @0600} ofItemAtPath:missingPath error:nil];
        Assert(GDTReadBackupProgressAtPath(missingPath) == nil,
               @"missing required parser keys are rejected");

        NSString *publicPath = [fixtureRoot
            stringByAppendingPathComponent:@"public.status"];
        [validContent writeToFile:publicPath atomically:YES
                         encoding:NSUTF8StringEncoding error:nil];
        [NSFileManager.defaultManager setAttributes:
            @{NSFilePosixPermissions: @0644} ofItemAtPath:publicPath error:nil];
        Assert(GDTReadBackupProgressAtPath(publicPath) == nil,
               @"group/world-readable progress is rejected");

        NSString *symlinkPath = [fixtureRoot
            stringByAppendingPathComponent:@"linked.status"];
        [NSFileManager.defaultManager createSymbolicLinkAtPath:symlinkPath
            withDestinationPath:validPath error:nil];
        Assert(GDTReadBackupProgressAtPath(symlinkPath) == nil,
               @"symlinked progress is rejected without following it");

        Assert(GDTValidatedBackupProgressForValues(
                   progress, summary, @"success", @"default", now) == nil,
               @"terminal summaries cannot expose live progress");
    }
    return failures ? 1 : 0;
}
```

- [ ] **Step 2: Add the test build command and verify RED**

Add this exact target body to `Makefile`'s `test` recipe before UI integration tests:

```make
	@set -e; PROGRESS_SUPPORT_TEST_BIN="$$(/usr/bin/mktemp "$${TMPDIR:-/tmp}/gdrive-progress-support-test.XXXXXX")"; \
		PROGRESS_SUPPORT_TEST_DIR="$$(/usr/bin/mktemp -d "$${TMPDIR:-/tmp}/gdrive-progress-support-fixtures.XXXXXX")"; \
		COMPILE_STATUS=0; clang $(OBJC_FLAGS) -framework Foundation -I macos/GDriveBackupTiger \
			tests/progress-support-test.m macos/GDriveBackupTiger/BackupProgressSupport.m \
			-o "$$PROGRESS_SUPPORT_TEST_BIN" || COMPILE_STATUS=$$?; \
		TEST_STATUS="$$COMPILE_STATUS"; \
		if [ "$$COMPILE_STATUS" -eq 0 ]; then \
			GDRIVE_PROGRESS_TEST_DIR="$$PROGRESS_SUPPORT_TEST_DIR" \
				"$$PROGRESS_SUPPORT_TEST_BIN" || TEST_STATUS=$$?; \
		fi; \
		./scripts/trash-path.sh "$$PROGRESS_SUPPORT_TEST_BIN" \
			"$$PROGRESS_SUPPORT_TEST_DIR"; \
		exit "$$TEST_STATUS"
```

Run:

```bash
make test
```

Expected RED: compilation fails because `BackupProgressSupport.h/.m` and the declared API do not exist.

- [ ] **Step 3: Implement the minimal parser and validator**

Create `macos/GDriveBackupTiger/BackupProgressSupport.h`:

```objc
#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSString *GDTBackupProgressPathForSummaryPath(NSString *summaryPath);
FOUNDATION_EXPORT NSDictionary<NSString *, NSString *> * _Nullable
    GDTReadBackupProgressAtPath(NSString *path);
FOUNDATION_EXPORT NSDictionary<NSString *, NSString *> * _Nullable
    GDTValidatedBackupProgressForValues(
        NSDictionary<NSString *, NSString *> *progress,
        NSDictionary<NSString *, NSString *> *summary,
        NSString *summaryStatus,
        NSString *profileID,
        NSTimeInterval nowTimestamp);
```

Implement `BackupProgressSupport.m` with these exact acceptance rules:

```objc
// Accept protocol 1 only; parse the same first '=' key/value format as the
// run summary; reject duplicate keys, missing required keys, CR/LF/NUL, and
// values longer than 512 UTF-16 code units.
// Open with O_RDONLY | O_NOFOLLOW, then use fstat and read from that same file
// descriptor to avoid a path-swap race. Accept only a regular file owned by
// the current user with no group/world permission bits. A live record requires protocol, profile_id,
// pid, started_at, trigger, label, and updated_at. retry_attempt is required
// exactly when the matching summary has it. A preparing label may omit phase,
// percent, and detail; other live labels require a valid phase.
// Require summaryStatus == "running".
// Require progress.profile_id == profileID.
// Require progress.pid == summary.pid and progress.started_at == summary.started_at.
// Require progress.trigger == summary.trigger and retry_attempt equality when present.
// Require kill(pid, 0) == 0 or errno == EPERM.
// Require updated_at <= now + 1 and now - updated_at <= 60.
// Accept label only from preparing, My Drive, Shared with me, Shared Drive.
// Accept phase only as ^[1-9][0-9]*/[1-9][0-9]*$ with current <= total <= 9999.
// Accept percent only as an integer from 0 through 100; it may be absent while preparing.
// Accept detail only when single-line, <= 256 characters, and an exact match
// for the reconstructed aggregate grammar below. Never accept an arbitrary
// rclone or log line:
// ^[0-9]+([.][0-9]+)? ([KMGTPE]i)?B / [0-9]+([.][0-9]+)? ([KMGTPE]i)?B, [0-9]+([.][0-9]+)? ([KMGTPE]i)?B/s, ETA (-|[0-9]+[dhms]([0-9]+[dhms])*)$
```

The shell must parse only a matching rclone `Transferred:` statistics line and
reconstruct `transferred / total, speed, ETA value`. It never persists the raw
line.

- [ ] **Step 4: Verify the Objective-C protocol test is GREEN**

```bash
make test
```

Expected: the new progress support test passes; any later failure is an existing regression to diagnose before continuing.

- [ ] **Step 5: Add failing shell integration cases for headless telemetry**

Extend `tests/backup-outcome-test.sh` with these executable tests and a fake
`mv` spy that records only state-file basenames, never file contents:

```bash
enable_state_publish_order_spy() {
  cat >"$FAKE_BIN/mv" <<'SH'
#!/bin/bash
destination=""
for argument in "$@"; do destination="$argument"; done
case "$destination" in
  */last-run.status|*/current-progress.status)
    if [[ -n "${GDRIVE_BACKUP_STATE_PUBLISH_TEST_LOG:-}" ]]; then
      printf '%s\n' "${destination##*/}" >>"$GDRIVE_BACKUP_STATE_PUBLISH_TEST_LOG"
    fi
    ;;
esac
exec /bin/mv "$@"
SH
  chmod +x "$FAKE_BIN/mv"
}

last_terminal_publish_order() {
  tail -n 2 "$1" 2>/dev/null | paste -sd, -
}

test_headless_retry_publishes_private_progress() {
  local name="headless retry publishes private aggregate progress"
  local progress content summary mode status backup_pid attempt
  local summary_pid summary_started progress_updated
  prepare_test_environment
  progress="$TEST_HOME/profiles/default/current-progress.status"
  mkdir -p "${progress%/*}"

  FAKE_RCLONE_COPY_OUTPUT=$'INFO : secret-file.pdf: Copied\nTransferred: 1.200 GiB / 1.900 GiB, 63%, 12.400 MiB/s, ETA 58s' \
  FAKE_RCLONE_SLEEP_SECONDS=3 \
    run_backup \
      "GDRIVE_BACKUP_TRIGGER=schedule-retry" \
      "GDRIVE_BACKUP_RETRY_ORIGIN_STARTED_AT=1785520805" \
      "GDRIVE_BACKUP_RETRY_ATTEMPT=1" \
      "GDRIVE_BACKUP_PROFILE_ID=default" \
      "GDRIVE_BACKUP_PROGRESS_STATE_FILE=$progress" \
      "BACKUP_PROGRESS_FOREGROUND=0" &
  backup_pid=$!

  for attempt in {1..100}; do
    content="$(cat "$progress" 2>/dev/null || true)"
    [[ "$content" == *$'percent=63\n'* ]] && break
    sleep 0.05
  done
  mode="$(stat -f '%Lp' "$progress" 2>/dev/null || true)"
  content="$(cat "$progress" 2>/dev/null || true)"
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"
  summary_pid="$(awk -F= '$1 == "pid" {print $2}' "$SUMMARY_STATE_FILE")"
  summary_started="$(awk -F= '$1 == "started_at" {print $2}' "$SUMMARY_STATE_FILE")"
  progress_updated="$(awk -F= '$1 == "updated_at" {print $2}' "$progress")"
  wait "$backup_pid"
  status=$?

  if [[ "$status" == "0" && "$mode" == "600" &&
        "$content" == *$'protocol=1\n'* &&
        "$content" == *$'profile_id=default\n'* &&
        "$summary" == *$'status=running\n'* &&
        "$summary_pid" =~ ^[0-9]+$ &&
        "$summary_started" =~ ^[0-9]+$ &&
        "$content" == *"pid=$summary_pid"* &&
        "$content" == *"started_at=$summary_started"* &&
        "$content" == *$'trigger=schedule-retry\n'* &&
        "$content" == *$'retry_attempt=1\n'* &&
        "$content" == *$'label=My Drive\n'* &&
        "$content" == *$'phase=1/2\n'* &&
        "$content" == *$'percent=63\n'* &&
        "$content" == *$'detail=1.200 GiB / 1.900 GiB, 12.400 MiB/s, ETA 58s\n'* &&
        "$progress_updated" =~ ^[0-9]+$ &&
        "$content" != *'secret-file.pdf'* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status mode=$mode progress=${content//$'\n'/,})"
  fi
}

test_headless_retry_never_opens_progress_window() {
  local name="headless retry telemetry remains passive"
  local progress status open_args terminal
  prepare_test_environment
  progress="$TEST_HOME/profiles/default/current-progress.status"
  mkdir -p "${progress%/*}" "$TEST_HOME/GDrive Backup Tiger.app"

  BACKUP_DISABLE_ANIMATION=0 \
    run_backup \
      "GDRIVE_BACKUP_TRIGGER=schedule-retry" \
      "GDRIVE_BACKUP_RETRY_ORIGIN_STARTED_AT=1785520805" \
      "GDRIVE_BACKUP_RETRY_ATTEMPT=1" \
      "GDRIVE_BACKUP_PROFILE_ID=default" \
      "GDRIVE_BACKUP_PROGRESS_STATE_FILE=$progress" \
      "GDRIVE_BACKUP_ANIMATION_APP=$TEST_HOME/GDrive Backup Tiger.app" \
      "GDRIVE_BACKUP_OPEN_BIN=$FAKE_BIN/open" \
      "BACKUP_PROGRESS_FOREGROUND=0"
  status=$?
  open_args="$(cat "$OPEN_LOG" 2>/dev/null || true)"
  terminal="$(cat "$progress" 2>/dev/null || true)"

  if [[ "$status" == "0" && -z "$open_args" &&
        "$terminal" == *$'status=finished\n'* &&
        "$terminal" != *$'percent='* ]]; then
    pass "$name"
  else
    fail "$name (exit=$status open=${open_args//$'\n'/,} progress=${terminal//$'\n'/,})"
  fi
}

test_terminal_outcomes_invalidate_durable_progress() {
  local name="terminal summaries invalidate durable progress"
  local progress status success_summary success_progress
  local failure_summary failure_progress success_order failure_order
  local order_log success_ok=0

  prepare_test_environment
  enable_state_publish_order_spy
  order_log="$TEST_HOME/state-publish-order.log"
  progress="$TEST_HOME/profiles/default/current-progress.status"
  mkdir -p "${progress%/*}"
  run_backup \
    "GDRIVE_BACKUP_PROFILE_ID=default" \
    "GDRIVE_BACKUP_STATE_PUBLISH_TEST_LOG=$order_log" \
    "GDRIVE_BACKUP_PROGRESS_STATE_FILE=$progress"
  status=$?
  success_summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"
  success_progress="$(cat "$progress" 2>/dev/null || true)"
  success_order="$(last_terminal_publish_order "$order_log")"
  if [[ "$status" == "0" &&
        "$success_summary" == *$'status=success\n'* &&
        "$success_summary" == *$'exit_code=0\n'* &&
        "$success_progress" == *$'status=finished\n'* &&
        "$success_progress" != *$'percent='* &&
        "$success_order" == "last-run.status,current-progress.status" ]]; then
    success_ok=1
  fi

  prepare_test_environment
  enable_state_publish_order_spy
  order_log="$TEST_HOME/state-publish-order.log"
  progress="$TEST_HOME/profiles/default/current-progress.status"
  mkdir -p "${progress%/*}"
  FAKE_RCLONE_COPY_STATUS=23 run_backup \
    "GDRIVE_BACKUP_PROFILE_ID=default" \
    "GDRIVE_BACKUP_STATE_PUBLISH_TEST_LOG=$order_log" \
    "GDRIVE_BACKUP_PROGRESS_STATE_FILE=$progress"
  status=$?
  failure_summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"
  failure_progress="$(cat "$progress" 2>/dev/null || true)"
  failure_order="$(last_terminal_publish_order "$order_log")"

  if [[ "$success_ok" == "1" && "$status" == "1" &&
        "$failure_summary" == *$'status=failure\n'* &&
        "$failure_summary" == *$'exit_code=1\n'* &&
        "$failure_progress" == *$'status=finished\n'* &&
        "$failure_progress" != *$'percent='* &&
        "$failure_order" == "last-run.status,current-progress.status" ]]; then
    pass "$name"
  else
    fail "$name (success=${success_summary//$'\n'/,}; failure=${failure_summary//$'\n'/,}; progress=${failure_progress//$'\n'/,})"
  fi
}

# Add all three calls immediately before the final `if (( failures > 0 ))` block.
test_headless_retry_publishes_private_progress
test_headless_retry_never_opens_progress_window
test_terminal_outcomes_invalidate_durable_progress
```

Also pass these variables through `start_backup_async`'s `env` block:

```bash
GDRIVE_BACKUP_PROFILE_ID="${GDRIVE_BACKUP_PROFILE_ID:-default}" \
GDRIVE_BACKUP_PROGRESS_STATE_FILE="${GDRIVE_BACKUP_PROGRESS_STATE_FILE:-}" \
GDRIVE_BACKUP_STATE_PUBLISH_TEST_LOG="${GDRIVE_BACKUP_STATE_PUBLISH_TEST_LOG:-}" \
```

Replace the existing TERM test with the same test plus durable-summary checks:

```bash
test_term_signal_publishes_cancellation() {
  local name="TERM publishes cancellation and invalidates live progress"
  local backup_pid status state summary terminal started_file progress
  local order_log terminal_order
  prepare_test_environment
  enable_state_publish_order_spy
  started_file="$TEST_HOME/rclone-started"
  progress="$TEST_HOME/profiles/default/current-progress.status"
  order_log="$TEST_HOME/state-publish-order.log"
  mkdir -p "${progress%/*}"

  GDRIVE_BACKUP_PROGRESS_STATE_FILE="$progress" \
  GDRIVE_BACKUP_STATE_PUBLISH_TEST_LOG="$order_log" \
    start_backup_async "$started_file"
  backup_pid="$ASYNC_BACKUP_PID"
  for _ in {1..60}; do
    [[ -e "$started_file" ]] && break
    /bin/sleep 0.05
  done
  kill -TERM "$backup_pid" 2>/dev/null || true
  wait "$backup_pid"
  status=$?
  state="$(cat "$RUN_STATE_FILE" 2>/dev/null || true)"
  summary="$(cat "$SUMMARY_STATE_FILE" 2>/dev/null || true)"
  terminal="$(cat "$progress" 2>/dev/null || true)"
  terminal_order="$(last_terminal_publish_order "$order_log")"

  if [[ "$status" == "143" && "$state" == *$'status=cancelled\n'* &&
        "$state" == *$'signal=TERM\n'* && "$state" == *'exit_code=143'* &&
        "$summary" == *$'status=cancelled\n'* &&
        "$terminal" == *$'status=finished\n'* &&
        "$terminal" != *$'percent='* &&
        "$terminal_order" == "last-run.status,current-progress.status" ]]; then
    pass "$name"
  else
    fail "$name (exit=$status state=${state//$'\n'/,} summary=${summary//$'\n'/,} progress=${terminal//$'\n'/,})"
  fi
}
```

Run:

```bash
bash tests/backup-outcome-test.sh
```

Expected RED: the headless run creates no progress file.

- [ ] **Step 6: Separate telemetry creation from foreground presentation in the shell**

Modify `bin/backup-google-drive.sh` with these concrete responsibilities:

```bash
DURABLE_PROGRESS_FILE="${GDRIVE_BACKUP_PROGRESS_STATE_FILE:-}"
PROGRESS_PROFILE_ID="${GDRIVE_BACKUP_PROFILE_ID:-${ACTIVE_PROFILE_ID:-legacy}}"

initialize_durable_progress() {
  [[ "$DRY_RUN" == "0" && "$SETUP_UI" == "0" ]] || return 0
  [[ "$PROGRESS_PROFILE_ID" =~ ^[a-z0-9][a-z0-9-]{0,63}$ ]] || return 0
  if [[ -z "$DURABLE_PROGRESS_FILE" ]]; then
    DURABLE_PROGRESS_FILE="${SUMMARY_STATE_FILE%/*}/current-progress.status"
  fi
  write_durable_progress "preparing" "" "" ""
}

public_progress_label() {
  case "$1" in
    "My Drive") printf 'My Drive' ;;
    "Shared with me") printf 'Shared with me' ;;
    *) printf 'Shared Drive' ;;
  esac
}

parse_rclone_progress_fields() {
  local line="$1"
  local pattern='^Transferred:[[:space:]]*([0-9][0-9.]*[[:space:]]+([KMGTPE]i)?B)[[:space:]]+/[[:space:]]+([0-9][0-9.]*[[:space:]]+([KMGTPE]i)?B),[[:space:]]+([0-9]{1,3})%,[[:space:]]+([0-9][0-9.]*[[:space:]]+([KMGTPE]i)?B/s),[[:space:]]+ETA[[:space:]]+(-|([0-9]+[dhms])+)$'
  [[ "$line" =~ $pattern ]] || return 1
  RCLONE_PROGRESS_TRANSFERRED="${BASH_REMATCH[1]}"
  RCLONE_PROGRESS_TOTAL="${BASH_REMATCH[3]}"
  RCLONE_PROGRESS_PERCENT="${BASH_REMATCH[5]}"
  RCLONE_PROGRESS_SPEED="${BASH_REMATCH[6]}"
  RCLONE_PROGRESS_ETA="${BASH_REMATCH[8]}"
  [[ "${RCLONE_PROGRESS_TRANSFERRED%% *}" =~ ^[0-9]+([.][0-9]+)?$ &&
     "${RCLONE_PROGRESS_TOTAL%% *}" =~ ^[0-9]+([.][0-9]+)?$ &&
     "${RCLONE_PROGRESS_SPEED%% *}" =~ ^[0-9]+([.][0-9]+)?$ &&
     "$RCLONE_PROGRESS_PERCENT" -le 100 ]] || return 1
  RCLONE_PROGRESS_DETAIL="$RCLONE_PROGRESS_TRANSFERRED / $RCLONE_PROGRESS_TOTAL, $RCLONE_PROGRESS_SPEED, ETA $RCLONE_PROGRESS_ETA"
}

write_durable_progress() {
  local label="${1:-preparing}" percent="${2:-}" detail="${3:-}" phase="${4:-}"
  local directory temporary existing_owner phase_current phase_total
  [[ -n "$DURABLE_PROGRESS_FILE" ]] || return 0
  case "$label" in preparing|"My Drive"|"Shared with me"|"Shared Drive") ;; *) return 1 ;; esac
  [[ -z "$phase" || "$phase" =~ ^[1-9][0-9]*/[1-9][0-9]*$ ]] || return 1
  if [[ -n "$phase" ]]; then
    phase_current="${phase%/*}"
    phase_total="${phase#*/}"
    [[ "$phase_current" -le "$phase_total" && "$phase_total" -le 9999 ]] || return 1
  fi
  [[ -z "$percent" || ( "$percent" =~ ^[0-9]+$ && "$percent" -le 100 ) ]] || return 1
  if [[ -n "$detail" && "$detail" != "${RCLONE_PROGRESS_DETAIL:-}" ]]; then return 1; fi
  [[ ! -L "$DURABLE_PROGRESS_FILE" ]] || return 1
  [[ ! -e "$DURABLE_PROGRESS_FILE" || -f "$DURABLE_PROGRESS_FILE" ]] || return 1
  if [[ -e "$DURABLE_PROGRESS_FILE" ]]; then
    existing_owner="$(stat -f '%u' "$DURABLE_PROGRESS_FILE")" || return 1
    [[ "$existing_owner" == "$(id -u)" ]] || return 1
  fi
  directory="${DURABLE_PROGRESS_FILE%/*}"
  (umask 077 && mkdir -p "$directory") || return 1
  temporary="$(umask 077; mktemp "${DURABLE_PROGRESS_FILE}.tmp.XXXXXX")" || return 1
  if ! (umask 077; {
      printf 'protocol=1\nprofile_id=%s\npid=%s\nstarted_at=%s\ntrigger=%s\n' \
        "$PROGRESS_PROFILE_ID" "$$" "$RUN_STARTED_AT" "$BACKUP_TRIGGER"
      [[ -n "$RETRY_ATTEMPT" ]] && printf 'retry_attempt=%s\n' "$RETRY_ATTEMPT"
      printf 'label=%s\n' "$label"
      [[ -n "$phase" ]] && printf 'phase=%s\n' "$phase"
      [[ -n "$percent" ]] && printf 'percent=%s\n' "$percent"
      [[ -n "$detail" ]] && printf 'detail=%s\n' "$detail"
      printf 'updated_at=%s\n' "$(date +%s)"
    } >"$temporary" && chmod 600 "$temporary"); then
    cleanup_temp_file "$temporary"
    return 1
  fi
  mv -f "$temporary" "$DURABLE_PROGRESS_FILE"
}
```

`write_durable_progress` must use `umask 077`, an adjacent
`mktemp "${DURABLE_PROGRESS_FILE}.tmp.XXXXXX"` file, `chmod 600`, and
`mv -f`. It writes protocol, profile ID, PID, start time,
trigger, retry attempt, public label, phase, bounded percent, reconstructed
aggregate detail, and `updated_at`. It rejects symlinks, non-regular existing
paths, and files not owned by the current user.

Call `initialize_durable_progress` immediately after lock ownership and after
`RUN_STARTED_AT`, trigger, profile, and retry identity are fixed, but before
slow NAS/remote preflight. Keep `start_animation` unchanged as the foreground
window gate. Keep `write_progress` for its current foreground file only. In
`update_progress_from_rclone_line`, call
`parse_rclone_progress_fields "$line"`; only on success call
`write_durable_progress "$(public_progress_label "$label")"
"$RCLONE_PROGRESS_PERCENT" "$RCLONE_PROGRESS_DETAIL" "$phase"`. At the
start of each copy phase publish its public label and phase without a detail;
never pass localized foreground text or a raw rclone line to the durable
writer. A telemetry-write failure logs one generic warning and degrades the UI
to indeterminate without changing the backup outcome.

In `cleanup`, first call `finish_run_state` and only after it returns atomically
replace the durable record with `protocol=1`, matching profile/PID/start/
trigger/retry identity, `status=finished`, and `updated_at`; omit label, phase,
percent, and detail, and do not unlink the file.

- [ ] **Step 7: Verify GREEN and commit the protocol**

```bash
bash -n bin/backup-google-drive.sh
bash tests/backup-outcome-test.sh
make test
git add Makefile bin/backup-google-drive.sh \
  macos/GDriveBackupTiger/BackupProgressSupport.h \
  macos/GDriveBackupTiger/BackupProgressSupport.m \
  tests/progress-support-test.m tests/backup-outcome-test.sh
git diff --cached --check
git commit -m "feat: persist private backup progress telemetry"
```

Expected: all tests pass and one focused protocol commit is created.

---

### Task 3: Render retry-specific progress in the overview and menu bar

**Files:**
- Modify: `Makefile`
- Modify: `install.sh`
- Modify: `macos/GDriveBackupTiger/main.m`
- Modify: `macos/GDriveBackupTiger/Localization.m`
- Modify: `tests/release-metadata-test.sh`
- Modify: `tests/overview-ui-test.m`
- Modify: `tests/tiger-accessibility-test.m`

**Interfaces:**
- Consumes: Task 2's `GDTBackupProgressPathForSummaryPath`, `GDTReadBackupProgressAtPath`, and `GDTValidatedBackupProgressForValues`.
- Produces: snapshot keys `trigger`, `retryRunning`, `progressVisible`, `progressLabel`, `progressPhase`, `progressPercent`, and `progressDetail`; one native overview progress indicator; one compact menu status row.

- [ ] **Step 1: Write failing snapshot and menu assertions**

In `tests/overview-ui-test.m`, add a running retry summary and validated progress dictionary:

```objc
NSDictionary *dailyNAS = @{
    @"GDRIVE_BACKUP_PROFILE_ID": @"default",
    @"GDRIVE_BACKUP_TARGET": @"nas",
    @"GDRIVE_BACKUP_NAS_MOUNT": @"/Volumes/alexander",
    @"GDRIVE_BACKUP_NAS_SUBDIR": @"GoogleDrive-Backup",
    @"GDRIVE_BACKUP_SCHEDULE": @"daily"
};
NSDictionary *retrySummary = @{
    @"protocol": @"1", @"status": @"running", @"pid": @"123",
    @"started_at": @"1785522633", @"trigger": @"schedule-retry",
    @"retry_origin_started_at": @"1785520805", @"retry_attempt": @"1"
};
NSDictionary *retryProgress = @{
    @"label": @"Shared Drive", @"phase": @"3/5", @"percent": @"63",
    @"detail": @"1.2 GiB / 1.9 GiB, 12.4 MiB/s, ETA 58s"
};
NSDictionary *retrySnapshot = [delegate overviewSnapshotForConfig:dailyNAS
    summary:retrySummary status:@"running" progress:retryProgress
    now:now calendar:calendar];
NSString *phaseText = [NSString stringWithFormat:T(@"en", @"progressAreaFormat"),
    @"3", @"5"];
NSString *retryStart = [[delegate overviewDateFormatterWithCalendar:calendar]
    stringFromDate:[NSDate dateWithTimeIntervalSince1970:1785522633]];
Assert([retrySnapshot[@"retryRunning"] isEqualToString:@"1"] &&
       [retrySnapshot[@"lastRun"] isEqualToString:T(@"en", @"automaticRetryRunning")] &&
       [retrySnapshot[@"lastRunDetail"] isEqualToString:retryStart] &&
       [retrySnapshot[@"progressPhase"] isEqualToString:phaseText] &&
       [retrySnapshot[@"progressPercent"] isEqualToString:@"63"] &&
       [retrySnapshot[@"progressDetail"] isEqualToString:
           @"1.2 GiB / 1.9 GiB, 12.4 MiB/s, ETA 58s"],
       @"running automatic retry has explicit phase progress");

NSMenu *retryMenu = [delegate statusMenuForSnapshot:retrySnapshot];
NSString *retryMenuText = [[retryMenu.itemArray valueForKey:@"title"]
    componentsJoinedByString:@" "];
NSMenuItem *retryProgressItem = nil;
for (NSMenuItem *item in retryMenu.itemArray) {
    if ([item.title containsString:T(@"en", @"automaticRetryRunningShort")]) {
        retryProgressItem = item;
        break;
    }
}
NSMenuItem *retryBackup = [retryMenu itemWithTitle:T(@"en", @"backupNow")];
NSMenuItem *retryOpen = [retryMenu itemWithTitle:T(@"en", @"overviewOpen")];
Assert([retryMenuText containsString:T(@"en", @"automaticRetryRunningShort")] &&
       [retryMenuText containsString:phaseText] &&
       [retryMenuText containsString:@"63 %"] &&
       retryProgressItem != nil && !retryProgressItem.enabled &&
       retryBackup != nil && !retryBackup.enabled &&
       retryOpen != nil && retryOpen.enabled,
       @"menu bar exposes compact retry progress");
```

Add a second assertion with `progress:nil` requiring `progressVisible=1`, an
empty percentage, `progressDetail=T(@"en", @"progressPreparing")`, and no
invented phase or transfer detail.

- [ ] **Step 2: Write failing native progress and accessibility assertions**

In `tests/tiger-accessibility-test.m`, after creating its `AppDelegate`,
instantiate a separate `TigerOverviewView`, apply a retry snapshot, and assert:

```objc
TigerOverviewView *overviewView = [[TigerOverviewView alloc]
    initWithFrame:NSMakeRect(0, 0, 620, 420)];
[delegate applyOverviewSnapshot:@{
    @"status": @"running", @"retryRunning": @"1",
    @"progressVisible": @"1",
    @"progressLabel": T(@"en", @"automaticRetryRunning"),
    @"progressPhase": @"Area 3 of 5", @"progressPercent": @"63",
    @"progressDetail": @"1.2 GiB / 1.9 GiB, 12.4 MiB/s, ETA 58s"
} toView:overviewView];
Assert(overviewView.progressIndicator != nil &&
       !overviewView.progressIndicator.hidden &&
       !overviewView.progressIndicator.indeterminate &&
       overviewView.progressIndicator.doubleValue == 63 &&
       [overviewView.progressPercentLabel.stringValue isEqualToString:@"63 %"] &&
       [overviewView.progressDetailLabel.stringValue isEqualToString:
           @"1.2 GiB / 1.9 GiB, 12.4 MiB/s, ETA 58s"] &&
       overviewView.progressDetailLabel.frame.size.width >= 400 &&
       !overviewView.backupButton.enabled,
       @"retry overview exposes visible percent and full aggregate detail");
Assert([overviewView.progressIndicator.accessibilityRole
           isEqualToString:NSAccessibilityProgressIndicatorRole] &&
       [overviewView.progressIndicator.accessibilityLabel
           isEqualToString:T(@"en", @"backupProgressCurrentPhase")],
       @"retry progress is announced as current-phase progress");
```

Repeat for no percentage and require `indeterminate == YES`.

- [ ] **Step 3: Run the UI tests and verify RED**

```bash
make test
```

Expected RED: the extended snapshot selector, overview progress properties,
and localization keys do not exist.

- [ ] **Step 4: Add the progress support module to every app and UI-test link**

Define `PROGRESS_SUPPORT_SOURCE := macos/GDriveBackupTiger/BackupProgressSupport.m`
in `Makefile`, add `$(PROGRESS_SUPPORT_SOURCE)` to `APP_SOURCES`, and append it
to each of the ten inline test links that includes `main.m`: run-state,
accessibility, notification integration, diagnostics integration, setup-health
UI, overview UI, setup safety, mount trigger, profile UI, and update UI. Verify
the count with:

```bash
test "$(rg -n '\$\(PROGRESS_SUPPORT_SOURCE\)' Makefile | wc -l | tr -d ' ')" = "11"
```

Add `"$ROOT/macos/GDriveBackupTiger/BackupProgressSupport.m"` to the explicit
source-installer `clang` list in `install.sh`, and add
`BackupProgressSupport.m` to the source-linkage loop in
`tests/release-metadata-test.sh`. Import the header from `main.m`:

```objc
#import "BackupProgressSupport.h"
```

- [ ] **Step 5: Extend the overview view with a passive native indicator**

Add these properties to `TigerOverviewView`:

```objc
@property(nonatomic) BOOL progressVisible;
@property(nonatomic) CGFloat progressPercent;
@property(nonatomic, copy) NSString *progressSummary;
@property(nonatomic, copy) NSString *progressDetail;
@property(nonatomic, strong) NSProgressIndicator *progressIndicator;
@property(nonatomic, strong) NSTextField *progressSummaryLabel;
@property(nonatomic, strong) NSTextField *progressPhaseLabel;
@property(nonatomic, strong) NSTextField *progressPercentLabel;
@property(nonatomic, strong) NSTextField *progressDetailLabel;
```

Place the summary at `NSMakeRect(116, 174, 440, 18)`, the localized phase at
`NSMakeRect(116, 194, 110, 18)`, the bar at
`NSMakeRect(232, 196, 200, 14)`, the visible percentage at
`NSMakeRect(440, 193, 52, 18)`, and the full aggregate detail at
`NSMakeRect(116, 216, 440, 18)`. Hide all five outside a running state. The
detail label is single-line but must be wide enough for the tested aggregate
string without truncation. A negative `progressPercent` selects indeterminate
animation and an empty percent label; `0...100` selects determinate mode and
formats the visible label as `N %`. Set the accessibility role to
`NSAccessibilityProgressIndicatorRole` and label to
`T(language, @"backupProgressCurrentPhase")`.

- [ ] **Step 6: Build a single retry-aware snapshot**

Add the overload:

```objc
- (NSDictionary<NSString *, NSString *> *)overviewSnapshotForConfig:
    (NSDictionary<NSString *, NSString *> *)config
    summary:(NSDictionary<NSString *, NSString *> *)summary
    status:(NSString *)status
    progress:(NSDictionary<NSString *, NSString *> * _Nullable)progress
    now:(NSDate *)now
    calendar:(NSCalendar *)calendar;
```

Keep the existing selector as a compatibility wrapper that passes `nil`.
When `status=running` and `trigger=schedule-retry`, emit:

```objc
@"trigger": @"schedule-retry",
@"retryRunning": @"1",
@"progressVisible": @"1",
@"progressLabel": T(language, @"automaticRetryRunning"),
@"progressPhase": GDTLocalizedProgressPhase(progress[@"phase"], language),
@"progressPercent": progress[@"percent"] ?: @"",
@"progressDetail": progress[@"detail"] ?: T(language, @"progressPreparing")
```

Set `lastRun` to `automaticRetryRunning` and continue using `started_at` for
`lastRunDetail`, so the retry start time remains visible. Implement
`GDTLocalizedProgressPhase` by splitting only the already-validated `N/M` and
formatting `progressAreaFormat`; never display the raw label as a Shared Drive
name. `applyOverviewSnapshot` updates the view, exposes the aggregate detail,
and keeps the Backup button disabled. `statusMenuForSnapshot` adds one disabled
compact row only while `retryRunning=1`.

In `refreshOverviewStatus`, read the progress path beside the captured profile
summary on the utility queue, validate it against the already-read summary and
status, and pass the validated dictionary to the new overload. Do not perform
file or process checks on the main thread.

- [ ] **Step 7: Localize all new user-visible strings**

Add complete values in `Localization.m` for German, English, French, Spanish,
Japanese, Cantonese, and Korean:

```text
automaticRetryRunning
automaticRetryRunningShort
backupProgressCurrentPhase
progressAreaFormat
progressPreparing
```

Use these reviewed values in the key order above:

```text
de: Automatischer Wiederholungsversuch läuft | Retry läuft | Fortschritt des aktuellen Bereichs | Bereich %1$@ von %2$@ | Wird vorbereitet …
en: Automatic retry is running | Retry running | Current area progress | Area %1$@ of %2$@ | Preparing …
fr: Nouvelle tentative automatique en cours | Nouvelle tentative en cours | Progression de la zone actuelle | Zone %1$@ sur %2$@ | Préparation…
es: Reintento automático en curso | Reintento en curso | Progreso del área actual | Área %1$@ de %2$@ | Preparando…
ja: 自動再試行を実行中 | 再試行中 | 現在の領域の進行状況 | 領域 %1$@ / %2$@ | 準備中…
yue: 自動重試進行中 | 重試中 | 目前區域嘅進度 | 區域 %1$@ / %2$@ | 準備中…
ko: 자동 재시도 실행 중 | 재시도 중 | 현재 영역 진행률 | 영역 %1$@/%2$@ | 준비 중…
```

Append the five keys to `overviewKeys` in `tests/overview-ui-test.m`, and in
the existing `SupportedLanguageCodes()` loop assert that every value is
nonempty, differs from its key, and that formatting `progressAreaFormat` with
`@"3", @"5"` contains both numbers.

- [ ] **Step 8: Verify GREEN and commit the passive UI**

```bash
make test
git add Makefile macos/GDriveBackupTiger/main.m \
  macos/GDriveBackupTiger/Localization.m \
  install.sh tests/release-metadata-test.sh \
  tests/overview-ui-test.m tests/tiger-accessibility-test.m
git diff --cached --check
git commit -m "feat: show automatic retry progress in the overview"
```

Expected: overview, menu, accessibility, and full-screen regression tests pass.

---

### Task 4: Replace the stale notification when the retry starts

**Files:**
- Modify: `macos/GDriveBackupTiger/NotificationSupport.m`
- Modify: `macos/GDriveBackupTiger/main.m`
- Modify: `macos/GDriveBackupTiger/Localization.m`
- Modify: `tests/notification-support-test.m`
- Modify: `tests/notification-integration-test.m`

**Interfaces:**
- Consumes: a validated summary with `status=running`, `trigger=schedule-retry`, `retry_origin_started_at`, and `started_at`; the existing failure notification identifier and active-issue latch.
- Produces: one `retry-running` notification decision with the same persistent identifier and a distinct delivery revision; a retry-running menu bar alert state that does not clear the failure latch.

- [ ] **Step 1: Write the failing notification policy test**

Add to `tests/notification-support-test.m`:

```objc
NSMutableDictionary *retryRunningSummary = [nasNotReady mutableCopy];
retryRunningSummary[@"status"] = @"running";
retryRunningSummary[@"trigger"] = @"schedule-retry";
retryRunningSummary[@"retry_origin_started_at"] = failedSummary[@"started_at"];
retryRunningSummary[@"retry_attempt"] = @"1";
retryRunningSummary[@"started_at"] = [NSString stringWithFormat:@"%.0f",
    Date(calendar, 21, 20, 56).timeIntervalSince1970];
[retryRunningSummary removeObjectForKey:@"finished_at"];
[retryRunningSummary removeObjectForKey:@"exit_code"];
NSDictionary *retryRunning = Decision(
    policyClass, daily, retryRunningSummary, @"running",
    Date(calendar, 21, 20, 57), calendar);
Assert([retryRunning[@"kind"] isEqualToString:@"retry-running"] &&
       [retryRunning[@"identifier"] isEqualToString:retryPlanned[@"identifier"]] &&
       [retryRunning[@"revision"] hasSuffix:retryRunningSummary[@"started_at"]] &&
       [retryRunning[@"titleKey"] isEqualToString:@"backupNotificationRetryRunningTitle"] &&
       [retryRunning[@"bodyKey"] isEqualToString:@"backupNotificationRetryRunningBody"],
       @"a running retry updates the preliminary alert in place");

NSTimeInterval originStart =
    Date(calendar, 21, 20, 0).timeIntervalSince1970;
NSTimeInterval originFinish =
    Date(calendar, 21, 20, 5).timeIntervalSince1970;
NSMutableDictionary *differentTimes = [failedSummary mutableCopy];
differentTimes[@"trigger"] = @"schedule";
differentTimes[@"started_at"] = [NSString stringWithFormat:@"%.0f", originStart];
differentTimes[@"finished_at"] = [NSString stringWithFormat:@"%.0f", originFinish];
NSDictionary *originalFailure = Decision(
    policyClass, daily, differentTimes, @"failure",
    Date(calendar, 21, 20, 6), calendar);
Assert([originalFailure[@"issueTimestamp"] doubleValue] == originFinish &&
       [originalFailure[@"issueOriginTimestamp"] doubleValue] == originStart &&
       [originalFailure[@"identifier"] hasSuffix:
           [NSString stringWithFormat:@".%.0f", originStart]],
       @"an original failure uses run start as canonical origin, not finish time");

NSMutableDictionary *finalRetry = [differentTimes mutableCopy];
finalRetry[@"trigger"] = @"schedule-retry";
finalRetry[@"retry_origin_started_at"] =
    [NSString stringWithFormat:@"%.0f", originStart];
finalRetry[@"started_at"] = [NSString stringWithFormat:@"%.0f",
    Date(calendar, 21, 20, 40).timeIntervalSince1970];
finalRetry[@"finished_at"] = [NSString stringWithFormat:@"%.0f",
    Date(calendar, 21, 20, 45).timeIntervalSince1970];
NSDictionary *finalRetryDecision = Decision(
    policyClass, daily, finalRetry, @"failure",
    Date(calendar, 21, 20, 46), calendar);
Assert([finalRetryDecision[@"issueOriginTimestamp"] doubleValue] == originStart,
       @"the final retry inherits the original run-start origin");
```

- [ ] **Step 2: Write failing integration assertions for one-time replacement**

Extend `tests/notification-integration-test.m` with a revision-bearing running
decision that reuses the preliminary identifier:

```objc
static void HandleBackupAction(id delegate, NSString *action,
                               NSString *category, NSDictionary *userInfo,
                               NSString *identifier) {
    SEL selector = NSSelectorFromString(
        @"handleBackupNotificationActionIdentifier:categoryIdentifier:userInfo:notificationIdentifier:");
    typedef void (*ActionMethod)(id, SEL, NSString *, NSString *,
                                 NSDictionary *, NSString *);
    ActionMethod method = [delegate respondsToSelector:selector]
        ? (ActionMethod)[delegate methodForSelector:selector] : NULL;
    if (method) method(delegate, selector, action, category, userInfo, identifier);
}

NSMutableDictionary *retryRunningDecision = [preliminary mutableCopy];
retryRunningDecision[@"kind"] = @"retry-running";
retryRunningDecision[@"revision"] = @"retry-running.430";
retryRunningDecision[@"issueOriginTimestamp"] = @"400";
retryRunningDecision[@"titleKey"] = @"backupNotificationRetryRunningTitle";
retryRunningDecision[@"bodyKey"] = @"backupNotificationRetryRunningBody";
Process(replacement, preliminary);
Process(replacement, retryRunningDecision);
Process(replacement, retryRunningDecision);
Assert(replacement.deliveryCalls == 2 &&
       replacement.removedNotificationIdentifiers == nil,
       @"retry start updates one identifier once without a duplicate alert");

NotificationTestDelegate *restarted = [[NotificationTestDelegate alloc] init];
restarted.testDefaults = [[NSUserDefaults alloc]
    initWithSuiteName:[suiteName stringByAppendingString:@".replacement"]];
restarted.deliverySucceeds = YES;
Process(restarted, retryRunningDecision);
Assert(restarted.deliveryCalls == 0,
       @"a controller restart does not repeat the running revision");
```

Then process final retry failure and assert the running/preliminary identifier
is retired only after macOS accepts the final notification. Add a rejected
delivery case proving `lastDeliveredRevision` is not advanced on failure.

Assert that the `GDT_BACKUP_ALERT` category carries
`UNNotificationCategoryOptionCustomDismissAction`. Add an overridable
`handleBackupNotificationActionIdentifier:categoryIdentifier:userInfo:notificationIdentifier:`
seam and invoke it with `UNNotificationDismissActionIdentifier`,
`GDT_BACKUP_ALERT`,
`profileID=office`, `issueOriginTimestamp=400`, and the preliminary request ID.
Assert that this explicit action records `dismissedIssueAt=400`, clears the
active issue latch, and removes that exact delivered and pending request. A
final retry failure carrying `issueOriginTimestamp=400` must remain suppressed;
a later independent failure with `issueOriginTimestamp=500` must still deliver.
Merely returning an empty delivered-notification list must *not* acknowledge an
issue, because macOS expiry or state lag is not proof of a human dismissal.

Finally, invoke the same action seam with `GDT_OPEN_BACKUP_OVERVIEW` and the
same content metadata. Assert that it records the same explicit
acknowledgement, removes that exact request, opens the normal overview once,
and does not launch a backup. Also assert that an unrelated category or missing
validated issue metadata cannot mutate acknowledgement state.

Add this explicit stale-response race after the matching-dismiss case:

```objc
NSString *activeAtKey = @"GDTBackupNotification.office.activeIssueAt";
NSString *activeIDKey = @"GDTBackupNotification.office.activeIssueIdentifier";
NSString *dismissedKey = @"GDTBackupNotification.office.dismissedIssueAt";
NSString *oldID = @"com.commcats.gdrivebackup.office.failure.400";
NSString *newID = @"com.commcats.gdrivebackup.office.failure.500";
[replacement.testDefaults setDouble:400 forKey:activeAtKey];
[replacement.testDefaults setObject:oldID forKey:activeIDKey];
HandleBackupAction(replacement, UNNotificationDismissActionIdentifier,
    @"GDT_BACKUP_ALERT",
    @{@"profileID": @"office", @"issueOriginTimestamp": @"400"}, oldID);
Assert([replacement.testDefaults doubleForKey:dismissedKey] == 400 &&
       [replacement.testDefaults objectForKey:activeAtKey] == nil &&
       [replacement.testDefaults objectForKey:activeIDKey] == nil &&
       [replacement.removedNotificationIdentifiers containsObject:oldID],
       @"an explicit matching dismiss acknowledges and retires one issue");

[replacement.testDefaults setDouble:500 forKey:activeAtKey];
[replacement.testDefaults setObject:newID forKey:activeIDKey];
HandleBackupAction(replacement, UNNotificationDismissActionIdentifier,
    @"GDT_BACKUP_ALERT",
    @{@"profileID": @"office", @"issueOriginTimestamp": @"400"}, oldID);
Assert([replacement.testDefaults doubleForKey:dismissedKey] == 400 &&
       [replacement.testDefaults doubleForKey:activeAtKey] == 500 &&
       [[replacement.testDefaults stringForKey:activeIDKey] isEqualToString:newID],
       @"a late dismissal retires only its old issue and cannot clear a newer latch");

SEL refreshAlertSelector = NSSelectorFromString(
    @"backupAlertStatusForConfig:summary:rawStatus:decision:");
typedef NSString *(*RefreshAlertStatusMethod)(id, SEL, NSDictionary *, NSDictionary *,
                                              NSString *, NSDictionary *);
RefreshAlertStatusMethod refreshAlertStatus =
    [replacement respondsToSelector:refreshAlertSelector]
        ? (RefreshAlertStatusMethod)[replacement methodForSelector:refreshAlertSelector]
        : NULL;
[replacement.testDefaults removeObjectForKey:activeAtKey];
[replacement.testDefaults removeObjectForKey:activeIDKey];

NSInteger deliveriesBeforeRefresh = replacement.deliveryCalls;
NSMutableDictionary *sameIssueFinal = [finalRetryFailure mutableCopy];
sameIssueFinal[@"issueTimestamp"] = @"430";
sameIssueFinal[@"issueOriginTimestamp"] = @"400";
if (refreshAlertStatus) {
    (void)refreshAlertStatus(replacement, refreshAlertSelector,
        @{@"GDRIVE_BACKUP_PROFILE_ID": @"office"},
        @{@"started_at": @"410", @"finished_at": @"430",
          @"trigger": @"schedule-retry"}, @"failure", sameIssueFinal);
}
Assert([replacement.testDefaults objectForKey:activeAtKey] == nil &&
       [replacement.testDefaults objectForKey:activeIDKey] == nil,
       @"refresh cannot relatch a human-acknowledged origin");
Process(replacement, sameIssueFinal);
Assert(replacement.deliveryCalls == deliveriesBeforeRefresh,
       @"refresh cannot resurrect a dismissed origin under a later finish time");

NSMutableDictionary *newFailure = [finalRetryFailure mutableCopy];
newFailure[@"identifier"] = newID;
newFailure[@"issueTimestamp"] = @"500";
newFailure[@"issueOriginTimestamp"] = @"500";
if (refreshAlertStatus) {
    (void)refreshAlertStatus(replacement, refreshAlertSelector,
        @{@"GDRIVE_BACKUP_PROFILE_ID": @"office"},
        @{@"started_at": @"500", @"finished_at": @"530",
          @"trigger": @"schedule"}, @"failure", newFailure);
}
Process(replacement, newFailure);
Assert(replacement.deliveryCalls == deliveriesBeforeRefresh + 1 &&
       [replacement.testDefaults doubleForKey:activeAtKey] == 500 &&
       [[replacement.testDefaults stringForKey:activeIDKey] isEqualToString:newID],
       @"a later independent issue still delivers and remains latched");
```

Add the equivalent `GDT_OPEN_BACKUP_OVERVIEW` call with a matching active issue
and assert `overviewShowCalls == 1`, acknowledgement persisted, the exact
request retired, and `backupLaunchCalls == 0`. Repeat with
`categoryIdentifier=@"GDT_UNKNOWN_EXTERNAL_VOLUME"` and with missing origin
metadata; neither may mutate acknowledgement or latch state. These assertions
prevent timestamp drift or an unrelated action from resurrecting or clearing
the wrong issue.

- [ ] **Step 3: Run notification tests and verify RED**

```bash
make test
```

Expected RED: running status currently produces no decision and identifier-only dedup prevents an in-place content update.

- [ ] **Step 4: Add the retry-running policy decision**

In `GDTBackupNotificationPolicy`, before terminal failure handling, accept only
a structurally valid running retry:

```objc
BOOL retryRunning = [status isEqualToString:@"running"] &&
    [trigger isEqualToString:@"schedule-retry"];
NSTimeInterval retryOrigin = GDTTimestamp(summary[@"retry_origin_started_at"]);
NSTimeInterval retryStarted = GDTTimestamp(summary[@"started_at"]);
if (retryRunning && retryOrigin > 0 && retryStarted > retryOrigin &&
    [summary[@"retry_attempt"] isEqualToString:@"1"]) {
    return @{
        @"identifier": [NSString stringWithFormat:
            @"com.commcats.gdrivebackup.%@.failure.%.0f", profileID, retryOrigin],
        @"revision": [NSString stringWithFormat:@"retry-running.%.0f", retryStarted],
        @"kind": @"retry-running",
        @"profileID": profileID,
        @"issueTimestamp": [NSString stringWithFormat:@"%.0f", retryOrigin],
        @"issueOriginTimestamp": [NSString stringWithFormat:@"%.0f", retryOrigin],
        @"titleKey": @"backupNotificationRetryRunningTitle",
        @"bodyKey": @"backupNotificationRetryRunningBody"
    };
}
```

- [ ] **Step 5: Make notification dedup revision-aware**

In `appNotificationCategories`, register `GDT_BACKUP_ALERT` with
`UNNotificationCategoryOptionCustomDismissAction`. In
`processBackupNotificationDecision`, add a per-profile
`lastDeliveredRevision` defaults key. Existing decisions without `revision`
retain identifier-only dedup. A decision with `revision` is suppressed only
when both identifier and revision match. Key pending work by
`identifier + "\n" + revision` instead of identifier alone. Persist the new
revision only after `UNUserNotificationCenter` accepts delivery; rejected
delivery remains retryable. When a later non-revision decision is accepted,
or a newer automatic success clears the issue, remove the stored revision.
Keep the original failure identifier in `deliveredFailureIdentifiers` so
automatic success still clears it. Do not alter the active issue timestamp or
kind merely because `retry-running` was delivered.

Put `profileID` and `issueOriginTimestamp` into `GDT_BACKUP_ALERT` content
`userInfo`. Route both `UNNotificationDismissActionIdentifier` and
`GDT_OPEN_BACKUP_OVERVIEW` from `didReceiveNotificationResponse` through one
validated acknowledgement helper that also receives and requires the exact
`GDT_BACKUP_ALERT` category. Only those explicit responses may persist
`dismissedIssueAt=issueOriginTimestamp` and remove the exact safe
delivered/pending request. Clear `activeIssueAt`, `activeIssueKind`, and the new
`activeIssueIdentifier` only when both the stored active origin and identifier
equal the response metadata; a late response for origin 400 must not mutate an
active origin 500. Missing delivered notifications remain a non-authoritative
observation and must never acknowledge an issue.

Canonicalize every notification policy result: original failure, missed run,
retry-planned, retry-running, and final retry-failure all carry
`issueOriginTimestamp`. For an original failure it equals the `runTimestamp`
derived from `summary.started_at` and used in the failure identifier, while
`issueTimestamp` may remain the later completion time. For a missed run the
origin is its due timestamp. Every retry state inherits
`retry_origin_started_at`, even when its own start or finish timestamp differs.
`backupAlertStatusForConfig` and delivery bookkeeping
must compare and persist only this canonical origin, check it against
`dismissedIssueAt` *before* creating or advancing a latch, and persist the
matching notification identifier beside `activeIssueAt`. Suppress every later
decision whose origin is `<= dismissedIssueAt`; a genuinely newer independent
failure uses its own start time and remains visible. Newer automatic success
clears identifier, revision, dismissal, and latch keys together.

In `backupAlertStatusForConfig`, return `retry-running` for a validated raw
running retry while leaving the stored failure latch intact. Add a non-red
running symbol and spoken status in `updateStatusItemPresentationForSnapshot`.

- [ ] **Step 6: Localize the updated notification**

Add all seven translations for:

```text
backupNotificationRetryRunningTitle
backupNotificationRetryRunningBody
```

Use these title/body pairs:

```text
de: Automatischer Wiederholungsversuch läuft | GDrive wird erneut gesichert. Öffne GDrive Backup Tiger, um den Fortschritt zu sehen.
en: Automatic backup retry is running | GDrive is being backed up again. Open GDrive Backup Tiger to view progress.
fr: Nouvelle tentative de sauvegarde automatique en cours | Une nouvelle sauvegarde de GDrive est en cours. Ouvrez GDrive Backup Tiger pour suivre la progression.
es: Reintento automático de copia de seguridad en curso | Se está realizando de nuevo la copia de seguridad de GDrive. Abre GDrive Backup Tiger para ver el progreso.
ja: 自動バックアップを再試行中 | GDrive をもう一度バックアップしています。進行状況を確認するには GDrive Backup Tiger を開いてください。
yue: 自動備份重試進行中 | GDrive 正在再次備份。請開啟 GDrive Backup Tiger 查看進度。
ko: 자동 백업 재시도 실행 중 | GDrive를 다시 백업하고 있습니다. 진행 상황을 보려면 GDrive Backup Tiger를 여십시오.
```

Append both keys to the existing all-language notification-key loop and require
every translation to be nonempty and unequal to its key.

- [ ] **Step 7: Verify GREEN and commit notification state**

```bash
make test
git add macos/GDriveBackupTiger/NotificationSupport.m \
  macos/GDriveBackupTiger/main.m macos/GDriveBackupTiger/Localization.m \
  tests/notification-support-test.m tests/notification-integration-test.m
git diff --cached --check
git commit -m "fix: update the alert when an automatic retry starts"
```

Expected: retry notification updates once, restart dedup works, final failure
still supersedes it, and newer automatic success still clears it.

---

### Task 5: Version, document, and verify v2.4.4 Build 28

**Files:**
- Modify: `macos/GDriveBackupTiger/Info.plist`
- Modify: `README.md`
- Modify: `CHANGELOG.md`
- Modify: `docs/version-history.md`
- Modify: `tests/release-metadata-test.sh`

**Interfaces:**
- Consumes: the completed protocol, UI, and notification commits.
- Produces: v2.4.4 Build 28 release metadata and user documentation that accurately describes passive automatic retry progress.

- [ ] **Step 1: Write the failing release metadata expectation**

Update `tests/release-metadata-test.sh` to require:

```bash
EXPECTED_VERSION="2.4.4"
EXPECTED_BUILD="28"

if [[ "$version" != "$EXPECTED_VERSION" || "$build" != "$EXPECTED_BUILD" ]]; then
  printf 'not ok - expected app version %s build %s, got %s build %s\n' \
    "$EXPECTED_VERSION" "$EXPECTED_BUILD" "$version" "$build"
  failures=$((failures + 1))
else
  printf 'ok - app version and build match the release plan\n'
fi

check_contains "$ROOT/README.md" "GDrive-Backup-Tiger-${EXPECTED_VERSION}.pkg" \
  "README names the exact release installer"
```

Run:

```bash
bash tests/release-metadata-test.sh
```

Expected RED: `Info.plist` and documentation still report v2.4.3 Build 27.

- [ ] **Step 2: Record the exact release behavior**

Set `CFBundleShortVersionString` to `2.4.4` and `CFBundleVersion` to `28`.
Add release notes stating:

```text
- Automatic retries now replace the stale waiting alert with a truthful running state.
- The overview and menu bar show private, per-phase progress without opening a foreground window.
- Progress is explicitly current-phase progress; scheduled and retry runs remain passive in full-screen Spaces.
```

Update README status behavior and version history with the same contract; do
not claim a global percentage or notification-embedded progress bar. Set
`Current release: \`v2.4.4\`` and name
`GDrive-Backup-Tiger-2.4.4.pkg` exactly, move all v2.4.4 entries out of
`Unreleased`, add `## v2.4.4 - 2026-08-01` to `CHANGELOG.md`, and add
`| v2.4.4 | 28 | ... |` to `docs/version-history.md` so
`scripts/validate-release.sh v2.4.4` can pass.

- [ ] **Step 3: Run focused and complete verification**

```bash
bash -n bin/backup-google-drive.sh
git diff --check
make test
scripts/validate-release.sh v2.4.4
```

Expected: all commands exit 0 with no warnings treated as errors.

- [ ] **Step 4: Build an isolated Universal 2 app without touching `/Applications`**

This implementation-time check was completed before the release-safety review.
Do not rerun the obsolete mutable-worktree staging snippet: Task 6 now performs
the authoritative build from a verified `git archive` of `v2.4.4^{commit}` and
uses strict, parsed entitlement extraction. Its retained stage and printed hash
replace any shell-local artifact from this earlier checkpoint.

- [ ] **Step 5: Commit the release metadata**

```bash
git add macos/GDriveBackupTiger/Info.plist README.md CHANGELOG.md \
  docs/version-history.md tests/release-metadata-test.sh
git diff --cached --check
git commit -m "chore: prepare v2.4.4 retry progress release"
```

Expected: one release-preparation commit and a clean tracked worktree.

---

### Task 6: Review, publish, and install only after a successful terminal backup

**Files:**
- Review: every commit in `e948ec29910210a53d587f0a8b9c309ea6238cef...HEAD`
- Publish: Git branch, pull request, CI, tag `v2.4.4`, installer, and checksum manifest
- Install after terminal state: a fresh build from the merged `v2.4.4` commit and `bin/backup-google-drive.sh`

**Interfaces:**
- Consumes: reviewed v2.4.4 Build 28 source, successful GitHub CI/release, a successful terminal live backup state, and user-granted `/Applications` and `/usr/local/bin` installation authority.
- Produces: merged and published history, verified installed v2.4.4, loaded controller and unchanged 20:00 schedule, and unchanged profile/NAS configuration.

- [ ] **Step 1: Invoke the required review skills**

Use `superpowers:requesting-code-review` for the complete branch diff and
`superpowers:verification-before-completion` before any success claim. Resolve
each validated finding with a failing regression test, the minimal fix, and a
focused commit.

- [ ] **Step 2: Re-run final branch verification**

```bash
git status --short --branch
git log --oneline --decorate --max-count=12
git diff --check origin/main...HEAD
bash -n bin/backup-google-drive.sh
make test
scripts/validate-release.sh v2.4.4
```

Expected: all feature commits are present, tests pass, release metadata is
consistent, and the isolated publication worktree is completely clean. The
untracked `AGENTS.md` and duplicate
`tests/package-entitlement-safety-test 2.sh` belong only to the original user
checkout and are not present in this publication worktree.

- [ ] **Step 3: Push, review, merge, tag, and verify the published release**

The block deliberately publishes the missing v2.4.3 history first. Its
installer is a retrospective exact-tag build and is verified before v2.4.4 is
allowed to become the latest release. Run it once from the reviewed, clean
feature branch.

<!-- GDT-RUNBOOK-PUBLISH:BEGIN -->
```bash
#!/bin/bash
set -euo pipefail
readonly BASE_SHA="e948ec29910210a53d587f0a8b9c309ea6238cef"
readonly V243_SHA="ddbfe24250149e4da177d23d8d1476dbbc3873eb"
BRANCH="codex/automatic-retry-progress-v2-4-4"
REVIEWED_HEAD="$(git rev-parse 'HEAD^{commit}')"
readonly REVIEWED_HEAD
REPOSITORY="$(gh repo view --json nameWithOwner --jq '.nameWithOwner')"
readonly REPOSITORY

test -z "$(git status --porcelain)"
test "$(git rev-parse 'origin/main^{commit}')" = "$BASE_SHA"
git merge-base --is-ancestor "$BASE_SHA" "$REVIEWED_HEAD"
git merge-base --is-ancestor "$V243_SHA" "$REVIEWED_HEAD"
test "$REVIEWED_HEAD" != "$BASE_SHA"
for tag in v2.4.3 v2.4.4; do
  if git show-ref --verify --quiet "refs/tags/$tag" ||
     git ls-remote --exit-code --tags origin "refs/tags/$tag" >/dev/null 2>&1; then
    printf 'Refusing to replace existing tag %s.\n' "$tag" >&2
    exit 1
  fi
done

# Push the reviewed object, not whatever the branch name might resolve to
# after review.
git push origin "${REVIEWED_HEAD}:refs/heads/${BRANCH}"
# An object-to-ref push does not materialize a local remote-tracking ref. Fetch
# that exact ref explicitly, then pin both views. Do not rely on
# `--set-upstream-to`: repositories with a deliberately narrow
# remote.origin.fetch reject it even when this exact ref exists locally.
git fetch --no-tags origin "refs/heads/${BRANCH}:refs/remotes/origin/${BRANCH}"
test "$(git rev-parse "refs/remotes/origin/${BRANCH}^{commit}")" = \
  "$REVIEWED_HEAD"
test "$(git ls-remote origin "refs/heads/${BRANCH}" | /usr/bin/awk '{print $1}')" = \
  "$REVIEWED_HEAD"
PR_URL="$(gh pr create --base main --head "$BRANCH" \
  --title "Show passive progress for automatic backup retries" \
  --body $'## Summary\n- persist private per-phase backup progress\n- show passive retry progress in the overview and menu bar\n- preserve guest SMB remounts and newer failure alerts\n- keep progress publication fail closed\n\n## Validation\n- bash -n bin/backup-google-drive.sh\n- make test\n- scripts/validate-release.sh v2.4.4')"
PR_NUMBER="${PR_URL##*/}"
[[ "$PR_NUMBER" =~ ^[0-9]+$ ]]
PR_BASE="$(gh pr view "$PR_NUMBER" --json baseRefOid --jq '.baseRefOid')"
PR_HEAD="$(gh pr view "$PR_NUMBER" --json headRefOid --jq '.headRefOid')"
test "$PR_BASE" = "$BASE_SHA"
test "$PR_HEAD" = "$REVIEWED_HEAD"
gh pr checks "$PR_NUMBER" --watch

# Re-read both immutable PR ends after CI, then make GitHub reject a merge if
# the reviewed head changed between the check and this command.
PR_BASE="$(gh pr view "$PR_NUMBER" --json baseRefOid --jq '.baseRefOid')"
PR_HEAD="$(gh pr view "$PR_NUMBER" --json headRefOid --jq '.headRefOid')"
test "$PR_BASE" = "$BASE_SHA"
test "$PR_HEAD" = "$REVIEWED_HEAD"
gh pr merge "$PR_NUMBER" --merge --match-head-commit "$REVIEWED_HEAD"
MERGED_SHA="$(gh pr view "$PR_NUMBER" \
  --json mergeCommit --jq '.mergeCommit.oid')"
[[ "$MERGED_SHA" =~ ^[0-9a-f]{40}$ ]]
git fetch origin main
test "$(git rev-parse 'origin/main^{commit}')" = "$MERGED_SHA"
test "$(git rev-parse "$MERGED_SHA^1")" = "$BASE_SHA"
test "$(git rev-parse "$MERGED_SHA^2")" = "$REVIEWED_HEAD"
test "$(git rev-list --parents -n 1 "$MERGED_SHA" | /usr/bin/awk '{print NF}')" = "3"
git merge-base --is-ancestor "$REVIEWED_HEAD" "$MERGED_SHA"

# Wait for the push-triggered main run by immutable commit, not merely PR checks.
MAIN_CI_RUN=""
for _ in {1..60}; do
  MAIN_CI_RUN="$(gh run list --workflow ci.yml --commit "$MERGED_SHA" --limit 1 \
    --json databaseId --jq '.[0].databaseId // empty')"
  [[ -n "$MAIN_CI_RUN" ]] && break
  /bin/sleep 2
done
test -n "$MAIN_CI_RUN"
gh run watch "$MAIN_CI_RUN" --exit-status

RELEASE_EVIDENCE_ROOT="$(/usr/bin/mktemp -d \
  "${TMPDIR:-/tmp}/gdrive-release-evidence.XXXXXX")"
test -d "$RELEASE_EVIDENCE_ROOT" && test ! -L "$RELEASE_EVIDENCE_ROOT"
report_publish_evidence() {
  local status=$?
  trap - EXIT
  printf 'LEFTOVER_RELEASE_EVIDENCE=%s\n' "$RELEASE_EVIDENCE_ROOT" >&2
  exit "$status"
}
trap report_publish_evidence EXIT

publish_release() {
  local tag="$1"
  local commit="$2"
  local version="${tag#v}"
  local release_dir="$RELEASE_EVIDENCE_ROOT/$tag"
  local source_dir="$release_dir/source"
  local archive="$release_dir/source.tar"
  local release_run=""
  local assets expected_assets latest_tag="" remote_tag

  test ! -e "$release_dir" && test ! -L "$release_dir"
  /bin/mkdir "$release_dir"
  test ! -e "$source_dir" && test ! -L "$source_dir"
  /bin/mkdir "$source_dir"
  test ! -e "$archive" && test ! -L "$archive"
  git archive --format=tar --output="$archive" "$commit"
  test "$(git get-tar-commit-id <"$archive")" = "$commit"
  /usr/bin/tar -xf "$archive" -C "$source_dir"
  make -C "$source_dir" test
  "$source_dir/scripts/validate-release.sh" "$tag"

  git tag -a "$tag" "$commit" -m "GDrive Backup Tiger $tag"
  test "$(git cat-file -t "refs/tags/$tag")" = "tag"
  test "$(git rev-parse "$tag^{commit}")" = "$commit"
  git push origin "refs/tags/$tag:refs/tags/$tag"

  for _ in {1..60}; do
    release_run="$(gh run list --workflow release.yml --branch "$tag" \
      --commit "$commit" --limit 1 \
      --json databaseId --jq '.[0].databaseId // empty')"
    [[ -n "$release_run" ]] && break
    /bin/sleep 2
  done
  test -n "$release_run"
  gh run watch "$release_run" --exit-status

  remote_tag="$(git ls-remote origin "refs/tags/$tag^{}" |
    /usr/bin/awk '{print $1}')"
  test "$remote_tag" = "$commit"
  gh release download "$tag" --dir "$release_dir" \
    --pattern "GDrive-Backup-Tiger-${version}.pkg" \
    --pattern 'SHA256SUMS.txt'
  (
    cd "$release_dir"
    /usr/bin/shasum -a 256 -c SHA256SUMS.txt
  )
  "$source_dir/packaging/verify-pkg.sh" --expect-unsigned \
    "$release_dir/GDrive-Backup-Tiger-${version}.pkg"
  assets="$(gh release view "$tag" --json assets --jq '.assets[].name' |
    LC_ALL=C /usr/bin/sort)"
  expected_assets="$(printf '%s\n%s\n' \
    "GDrive-Backup-Tiger-${version}.pkg" 'SHA256SUMS.txt' |
    LC_ALL=C /usr/bin/sort)"
  test "$assets" = "$expected_assets"
  test "$(gh release view "$tag" --json tagName --jq '.tagName')" = "$tag"
  for _ in {1..60}; do
    latest_tag="$(gh api "repos/$REPOSITORY/releases/latest" --jq '.tag_name')"
    [[ "$latest_tag" = "$tag" ]] && break
    /bin/sleep 2
  done
  test "$latest_tag" = "$tag"
}

publish_release v2.4.3 "$V243_SHA"
publish_release v2.4.4 "$MERGED_SHA"
printf 'Published merge=%s reviewed_head=%s\n' "$MERGED_SHA" "$REVIEWED_HEAD"
```
<!-- GDT-RUNBOOK-PUBLISH:END -->

Expected: PR checks and merged-main CI pass; the merge has exactly the pinned
base and reviewed head as parents; v2.4.3 is an annotated tag of `ddbfe24…`
with verified assets and is temporarily `latest`; only then v2.4.4 is tagged
at the merge commit, published, checksum-verified, package-verified, and becomes
`latest`. The printed evidence directory is intentionally retained.

- [ ] **Step 4: Enforce the successful terminal-backup installation gate**

Run this one block only after both releases above are verified. It performs the
pre-build gate, immutable export and build, locked transaction, rollback, and
all final checks. It intentionally retains and prints every stage, rollback,
previous-version, or quarantine path instead of depending on a Trash binary.

<!-- GDT-RUNBOOK-INSTALL:BEGIN -->
```bash
#!/bin/bash
set -euo pipefail

readonly RELEASE_TAG="v2.4.4"
readonly EXPECTED_VERSION="2.4.4"
readonly EXPECTED_BUILD="28"
readonly SAFE_PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
DOMAIN="gui/$(/usr/bin/id -u)"
readonly DOMAIN
readonly CONTROLLER_SERVICE="$DOMAIN/com.commcats.gdrivebackup"
readonly SCHEDULE_SERVICE="$DOMAIN/com.commcats.gdrivebackup.schedule"

REPO_ROOT="$(git rev-parse --show-toplevel)"
RELEASE_COMMIT="$(git rev-parse "$RELEASE_TAG^{commit}")"
REPOSITORY="$(gh repo view --json nameWithOwner --jq '.nameWithOwner')"
CURRENT_UID="$(/usr/bin/id -u)"
CURRENT_GID="$(/usr/bin/id -g)"
APP_FINAL="/Applications/GDrive Backup Tiger.app"
SCRIPT_FINAL="/usr/local/bin/backup-google-drive.sh"
CONTROLLER_PLIST="$HOME/Library/LaunchAgents/com.commcats.gdrivebackup.plist"
SCHEDULE_PLIST="$HOME/Library/LaunchAgents/com.commcats.gdrivebackup.schedule.plist"
CONFIG_DIR="$HOME/.config/gdrive-tiger-backup"
ACTIVE_PROFILE_FILE="$CONFIG_DIR/active-profile"
PROFILES_DIR="$CONFIG_DIR/profiles"
PROFILE_CONFIG="$PROFILES_DIR/default.conf"
STATE_ROOT="$HOME/Library/Application Support/GDrive Backup Tiger"
ROLLBACK_PARENT="$STATE_ROOT/rollbacks"
STAGE_PARENT="$STATE_ROOT/install-staging"

STAGE=""
ROLLBACK=""
APP_TXN=""
SCRIPT_TXN=""
APP_INCOMING=""
SCRIPT_INCOMING=""
APP_PREVIOUS=""
SCRIPT_PREVIOUS=""
APP_QUARANTINE=""
SCRIPT_QUARANTINE=""
OLD_APP_HASH=""
OLD_SCRIPT_HASH=""
APP_HASH=""
SCRIPT_HASH=""
EFFECTIVE_STATUS=""
RECOVERY_ARMED=0

assert_absolute_single_line_path() {
  local value="$1"
  [[ "$value" = /* && "$value" != *$'\n'* && "$value" != *$'\r'* ]]
}

assert_user_regular_file() {
  local path="$1"
  local expected_mode="$2"
  test -f "$path" && test ! -L "$path"
  test "$(/usr/bin/stat -f '%u' "$path")" = "$CURRENT_UID"
  test "$(/usr/bin/stat -f '%Lp' "$path")" = "$expected_mode"
}

assert_default_profile_selection() {
  local profile_id profile_config profile_id_matches=0 profile_line
  assert_user_regular_file "$ACTIVE_PROFILE_FILE" "600"
  profile_id="$(<"$ACTIVE_PROFILE_FILE")"
  [[ "$profile_id" =~ ^[a-z0-9][a-z0-9-]{0,63}$ ]]
  test "$profile_id" = "default"
  test -d "$PROFILES_DIR" && test ! -L "$PROFILES_DIR"
  profile_config="$PROFILES_DIR/$profile_id.conf"
  test "$profile_config" = "$PROFILE_CONFIG"
  assert_user_regular_file "$profile_config" "600"
  while IFS= read -r profile_line || [[ -n "$profile_line" ]]; do
    case "$profile_line" in
      "GDRIVE_BACKUP_PROFILE_ID=$profile_id"|"GDRIVE_BACKUP_PROFILE_ID='$profile_id'"|"GDRIVE_BACKUP_PROFILE_ID=\"$profile_id\"")
        profile_id_matches=1
        break
        ;;
    esac
  done <"$profile_config"
  test "$profile_id_matches" = "1"
}

assert_safe_user_plist() {
  local path="$1"
  local mode mode_value
  test -f "$path" && test ! -L "$path"
  test "$(/usr/bin/stat -f '%u' "$path")" = "$CURRENT_UID"
  mode="$(/usr/bin/stat -f '%Lp' "$path")"
  [[ "$mode" =~ ^[0-7]{3,4}$ ]]
  mode_value=$((8#$mode))
  (( (mode_value & 8#022) == 0 ))
  /usr/bin/plutil -lint "$path" >/dev/null
}

reject_service_path_overrides() {
  local plist key
  for plist in "$CONTROLLER_PLIST" "$SCHEDULE_PLIST"; do
    for key in \
      GDRIVE_BACKUP_CONFIG \
      GDRIVE_BACKUP_CONFIG_DIR \
      GDRIVE_BACKUP_LOCK \
      GDRIVE_BACKUP_SUMMARY_STATE_FILE \
      GDRIVE_BACKUP_PROGRESS_STATE_FILE; do
      if /usr/bin/plutil -extract "EnvironmentVariables.$key" raw -o - \
          "$plist" >/dev/null 2>&1; then
        printf 'Refusing service override %s in %s.\n' "$key" "$plist" >&2
        return 1
      fi
    done
  done
}

assert_manager_environment_clean() {
  # The point-query command reports success even for an unset variable on
  # supported macOS versions. Parse the domain stream and never retain values.
  if ! /bin/launchctl print "$DOMAIN" | /usr/bin/awk '
      /^[[:space:]]*(GDRIVE_BACKUP_CONFIG|GDRIVE_BACKUP_CONFIG_DIR|GDRIVE_BACKUP_LOCK|GDRIVE_BACKUP_SUMMARY_STATE_FILE|GDRIVE_BACKUP_PROGRESS_STATE_FILE)[[:space:]]*=>/ {
        forbidden = 1
      }
      END { exit(forbidden ? 1 : 0) }
    '; then
    printf '%s\n' 'Refusing a launchd manager path override.' >&2
    return 1
  fi
}

assert_loaded_service_contract() {
  local service="$1"
  local expected_plist="$2"
  local expected_program="$3"
  local expected_arg_count="$4"
  local expected_arg0="$5"
  local expected_arg1="$6"
  local expected_arg2="$7"
  local expected_home="$8"
  local expected_path="$9"
  local expected_trigger="${10}"
  local expected_assume="${11}"

  # Only the parser sees launchctl's complete output. It compares approved
  # fields in-stream and emits neither environment values nor a persisted copy.
  /bin/launchctl print "$service" | /usr/bin/awk \
    -v expected_plist="$expected_plist" \
    -v expected_program="$expected_program" \
    -v expected_arg_count="$expected_arg_count" \
    -v expected_arg0="$expected_arg0" \
    -v expected_arg1="$expected_arg1" \
    -v expected_arg2="$expected_arg2" \
    -v expected_home="$expected_home" \
    -v expected_path="$expected_path" \
    -v expected_trigger="$expected_trigger" \
    -v expected_assume="$expected_assume" '
      function trim(value) {
        sub(/^[[:space:]]+/, "", value)
        sub(/[[:space:]]+$/, "", value)
        return value
      }
      {
        normalized = trim($0)
        normalized_separator = index(normalized, " => ")
        if (normalized_separator) {
          normalized_key = substr(normalized, 1, normalized_separator - 1)
          if (normalized_key == "GDRIVE_BACKUP_CONFIG" ||
              normalized_key == "GDRIVE_BACKUP_CONFIG_DIR" ||
              normalized_key == "GDRIVE_BACKUP_LOCK" ||
              normalized_key == "GDRIVE_BACKUP_SUMMARY_STATE_FILE" ||
              normalized_key == "GDRIVE_BACKUP_PROGRESS_STATE_FILE") forbidden++
        }
      }
      /^[[:space:]]*path = / {
        path_count++
        value = $0
        sub(/^[[:space:]]*path = /, "", value)
        if (value == expected_plist) path_ok++
        else bad = 1
        next
      }
      /^[[:space:]]*program = / {
        program_count++
        value = $0
        sub(/^[[:space:]]*program = /, "", value)
        if (value == expected_program) program_ok++
        else bad = 1
        next
      }
      /^[[:space:]]*arguments = \{/ {
        argument_blocks++
        in_arguments = 1
        next
      }
      in_arguments && /^[[:space:]]*\}/ { in_arguments = 0; next }
      in_arguments { arguments[argument_count++] = trim($0); next }
      /^[[:space:]]*environment = \{/ {
        environment_blocks++
        in_environment = 1
        next
      }
      in_environment && /^[[:space:]]*\}/ { in_environment = 0; next }
      in_environment {
        line = trim($0)
        separator = index(line, " => ")
        if (!separator) next
        key = substr(line, 1, separator - 1)
        value = substr(line, separator + 4)
        if (key == "HOME") {
          home_count++
          if (value == expected_home) home_ok++
        }
        if (key == "PATH") {
          path_environment_count++
          if (value == expected_path) path_environment_ok++
        }
        if (key == "GDRIVE_BACKUP_TRIGGER") {
          trigger_count++
          if (value == expected_trigger) trigger_ok++
        }
        if (key == "BACKUP_ASSUME_YES") {
          assume_count++
          if (value == expected_assume) assume_ok++
        }
      }
      END {
        ok = !bad && !in_arguments && !in_environment &&
          path_count == 1 && path_ok == 1 &&
          program_count == 1 && program_ok == 1 &&
          argument_blocks == 1 && environment_blocks == 1 && forbidden == 0 &&
          argument_count == expected_arg_count &&
          arguments[0] == expected_arg0 && arguments[1] == expected_arg1 &&
          home_count == 1 && home_ok == 1 &&
          path_environment_count == 1 && path_environment_ok == 1
        if (expected_arg_count == 3) ok = ok && arguments[2] == expected_arg2
        if (expected_trigger == "") ok = ok && trigger_count == 0
        else ok = ok && trigger_count == 1 && trigger_ok == 1
        if (expected_assume == "") ok = ok && assume_count == 0
        else ok = ok && assume_count == 1 && assume_ok == 1
        exit(ok ? 0 : 1)
      }
    '
}

derive_effective_state() {
  local output="$1"
  test ! -e "$output" && test ! -L "$output"
  # The quoted program is evaluated by the sanitized child Bash, not this
  # shell. Scheduler variables match the already verified launchd contract.
  # shellcheck disable=SC2016
  /usr/bin/env -i \
    HOME="$HOME" \
    PATH="$SAFE_PATH" \
    GDRIVE_BACKUP_TRIGGER="$SCHEDULE_TRIGGER" \
    BACKUP_ASSUME_YES="$SCHEDULE_ASSUME_YES" \
    /bin/bash -c '
      set -euo pipefail
      # shellcheck source=/dev/null
      source "$1" >/dev/null
      test "$HOME" = "$2"
      test "${GDRIVE_BACKUP_PROFILE_ID:-}" = "default"
      test "${GDRIVE_BACKUP_TRIGGER:-}" = "$3"
      test "${BACKUP_ASSUME_YES:-}" = "$4"
      effective_lock="${GDRIVE_BACKUP_LOCK:-$HOME/Library/Logs/gdrive-backup.lock}"
      if [[ -n "${GDRIVE_BACKUP_SUMMARY_STATE_FILE:-}" ]]; then
        effective_status="$GDRIVE_BACKUP_SUMMARY_STATE_FILE"
      else
        effective_status="$HOME/Library/Application Support/GDrive Backup Tiger/profiles/default/last-run.status"
      fi
      effective_progress="${GDRIVE_BACKUP_PROGRESS_STATE_FILE:-${effective_status%/*}/current-progress.status}"
      printf "EFFECTIVE_CONFIG=%q\n" "$1"
      printf "EFFECTIVE_LOCK=%q\n" "$effective_lock"
      printf "EFFECTIVE_STATUS=%q\n" "$effective_status"
      printf "EFFECTIVE_PROGRESS=%q\n" "$effective_progress"
      printf "PROFILE_TARGET=%q\n" "${GDRIVE_BACKUP_TARGET:-}"
      printf "PROFILE_SCHEDULE=%q\n" "${GDRIVE_BACKUP_SCHEDULE:-}"
      printf "PROFILE_NOTIFY_FAILURES=%q\n" "${GDRIVE_BACKUP_NOTIFY_FAILURES:-}"
      printf "PROFILE_NAS_MOUNT=%q\n" "${GDRIVE_BACKUP_NAS_MOUNT:-}"
      printf "PROFILE_NAS_URL=%q\n" "${GDRIVE_BACKUP_NAS_URL:-}"
    ' _ "$PROFILE_CONFIG" "$HOME" "$SCHEDULE_TRIGGER" \
      "$SCHEDULE_ASSUME_YES" >"$output"
  /bin/chmod 600 "$output"
}

status_value_from_file() {
  local key="$1"
  test "$(/usr/bin/awk -F= -v key="$key" \
    '$1 == key {count++} END {print count + 0}' "$EFFECTIVE_STATUS")" = "1"
  /usr/bin/awk -F= -v key="$key" \
    '$1 == key {print substr($0, index($0, "=") + 1)}' "$EFFECTIVE_STATUS"
}

backup_process_snapshot() {
  local excluded="," pid
  pid="$(/bin/sh -c 'printf "%s" "$PPID"')"
  while [[ "$pid" =~ ^[0-9]+$ && "$pid" -gt 1 ]]; do
    excluded="${excluded}${pid},"
    pid="$(/bin/ps -p "$pid" -o ppid= | /usr/bin/tr -d ' ')"
  done
  /bin/ps -axo pid=,ppid=,command= | /usr/bin/awk -v excluded="$excluded" '
    index(excluded, "," $1 ",") == 0 &&
    /backup-google-drive|(^|[[:space:]\/])rclone([[:space:]]|$)/ &&
      $0 !~ /awk/ {print}'
}

assert_successful_terminal_backup_and_no_processes() {
  local status started_at finished_at last_success_at exit_code active
  assert_user_regular_file "$EFFECTIVE_STATUS" "600"
  test "$(status_value_from_file protocol)" = "1"
  status="$(status_value_from_file status)"
  started_at="$(status_value_from_file started_at)"
  finished_at="$(status_value_from_file finished_at)"
  last_success_at="$(status_value_from_file last_success_at)"
  exit_code="$(status_value_from_file exit_code)"
  test "$status" = "success" && test "$exit_code" = "0"
  [[ "$started_at" =~ ^[0-9]+$ && "$finished_at" =~ ^[0-9]+$ &&
     "$last_success_at" =~ ^[0-9]+$ ]]
  (( finished_at >= started_at && last_success_at >= started_at ))
  active="$(backup_process_snapshot)"
  test -z "$active"
}

canonical_config_manifest() {
  local root="$1"
  local output="$2"
  local paths="${output}.paths"
  local path relative type uid gid mode size digest
  test -d "$root" && test ! -L "$root"
  test ! -e "$output" && test ! -L "$output"
  test ! -e "$paths" && test ! -L "$paths"
  /usr/bin/find "$root" -print0 >"$paths"
  : >"$output"
  /bin/chmod 600 "$output" "$paths"
  while IFS= read -r -d '' path; do
    if [[ "$path" = "$root" ]]; then
      relative="."
    else
      relative="${path#"$root"/}"
    fi
    if [[ "$relative" == *'|'* || "$relative" == *$'\n'* ||
          "$relative" == *$'\r'* ]]; then
      printf 'Refusing unsafe manifest path: %s\n' "$relative" >&2
      return 1
    fi
    if [[ -L "$path" ]]; then
      printf 'Refusing unexpected symbolic link in configuration: %s\n' "$relative" >&2
      return 1
    elif [[ -f "$path" ]]; then
      type="file"
      digest="$(/usr/bin/shasum -a 256 "$path" | /usr/bin/awk '{print $1}')"
    elif [[ -d "$path" ]]; then
      type="directory"
      digest="-"
    else
      printf 'Refusing special configuration entry: %s\n' "$relative" >&2
      return 1
    fi
    uid="$(/usr/bin/stat -f '%u' "$path")"
    gid="$(/usr/bin/stat -f '%g' "$path")"
    mode="$(/usr/bin/stat -f '%Lp' "$path")"
    size="$(/usr/bin/stat -f '%z' "$path")"
    printf 'type=%s|path=%s|uid=%s|gid=%s|mode=%s|size=%s|sha256=%s\n' \
      "$type" "$relative" "$uid" "$gid" "$mode" "$size" "$digest"
  done < <(LC_ALL=C /usr/bin/sort -z "$paths") >"${output}.unsorted"
  LC_ALL=C /usr/bin/sort "${output}.unsorted" >"$output"
  /bin/chmod 600 "$output"
}

assert_runtime_snapshot_matches_prebuild() {
  local manifest="$1"
  local effective_state="$2"
  canonical_config_manifest "$CONFIG_DIR" "$manifest"
  /usr/bin/cmp -s "$PREBUILD_CONFIG_MANIFEST" "$manifest"
  assert_default_profile_selection
  assert_safe_user_plist "$CONTROLLER_PLIST"
  assert_safe_user_plist "$SCHEDULE_PLIST"
  test "$(/usr/bin/shasum -a 256 "$CONTROLLER_PLIST" |
    /usr/bin/awk '{print $1}')" = "$CONTROLLER_PLIST_HASH"
  test "$(/usr/bin/shasum -a 256 "$SCHEDULE_PLIST" |
    /usr/bin/awk '{print $1}')" = "$SCHEDULE_PLIST_HASH"
  reject_service_path_overrides
  assert_loaded_service_contract \
    "$CONTROLLER_SERVICE" "$CONTROLLER_PLIST" "$CONTROLLER_PROGRAM" 2 \
    "$CONTROLLER_PROGRAM" "$CONTROLLER_ARGUMENT" "" \
    "$CONTROLLER_HOME" "$CONTROLLER_PATH" "" ""
  assert_loaded_service_contract \
    "$SCHEDULE_SERVICE" "$SCHEDULE_PLIST" "$SCHEDULE_PROGRAM" 3 \
    "$SCHEDULE_PROGRAM" "$SCHEDULE_SCRIPT" "$SCHEDULE_ARGUMENT" \
    "$SCHEDULE_HOME" "$SCHEDULE_PATH" "$SCHEDULE_TRIGGER" \
    "$SCHEDULE_ASSUME_YES"
  assert_manager_environment_clean
  derive_effective_state "$effective_state"
  /usr/bin/cmp -s "$PREBUILD_EFFECTIVE_STATE" "$effective_state"
  # shellcheck source=/dev/null
  source "$effective_state"
  test "$EFFECTIVE_CONFIG" = "$PREBUILD_EFFECTIVE_CONFIG"
  test "$EFFECTIVE_LOCK" = "$PREBUILD_EFFECTIVE_LOCK"
  test "$EFFECTIVE_STATUS" = "$PREBUILD_EFFECTIVE_STATUS"
  test "$EFFECTIVE_PROGRESS" = "$PREBUILD_EFFECTIVE_PROGRESS"
  test "$PROFILE_TARGET" = "$PREBUILD_PROFILE_TARGET"
  test "$PROFILE_SCHEDULE" = "$PREBUILD_PROFILE_SCHEDULE"
  test "$PROFILE_NOTIFY_FAILURES" = "$PREBUILD_PROFILE_NOTIFY_FAILURES"
  test "$PROFILE_NAS_MOUNT" = "$PREBUILD_PROFILE_NAS_MOUNT"
  test "$PROFILE_NAS_URL" = "$PREBUILD_PROFILE_NAS_URL"
}

extract_entitlements() {
  local app="$1"
  local output="$2"
  local stderr_file="${output}.stderr"
  test ! -e "$output" && test ! -L "$output"
  test ! -e "$stderr_file" && test ! -L "$stderr_file"
  /usr/bin/codesign -d --entitlements :- "$app" >"$output" 2>"$stderr_file"
  if [[ ! -s "$output" ]]; then
    printf '%s\n' \
      '<?xml version="1.0" encoding="UTF-8"?>' \
      '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
      '<plist version="1.0"><dict/></plist>' >"$output"
  fi
  /usr/bin/plutil -lint "$output" >/dev/null
  if /usr/bin/plutil -extract \
      com.apple.developer.usernotifications.time-sensitive raw -o - \
      "$output" >/dev/null 2>&1; then
    printf '%s\n' 'Refusing restricted time-sensitive entitlement.' >&2
    return 1
  fi
}

reload_services() {
  /bin/launchctl bootstrap "$DOMAIN" "$CONTROLLER_PLIST"
  /bin/launchctl enable "$CONTROLLER_SERVICE"
  /bin/launchctl bootstrap "$DOMAIN" "$SCHEDULE_PLIST"
  /bin/launchctl enable "$SCHEDULE_SERVICE"
  /bin/launchctl print "$CONTROLLER_SERVICE" >/dev/null
  /bin/launchctl print "$SCHEDULE_SERVICE" >/dev/null
}

recover_previous_install() {
  local recovery_status=0 current_hash=""

  # These best-effort bootouts are recovery-only: they prevent either service
  # from observing a partially restored pair.
  /bin/launchctl bootout "$DOMAIN" "$SCHEDULE_PLIST" >/dev/null 2>&1 || true
  /bin/launchctl bootout "$DOMAIN" "$CONTROLLER_PLIST" >/dev/null 2>&1 || true

  if [[ -d "$APP_FINAL" && ! -L "$APP_FINAL" ]]; then
    current_hash="$(/usr/bin/shasum -a 256 \
      "$APP_FINAL/Contents/MacOS/GDriveBackupTiger" | /usr/bin/awk '{print $1}')"
    if [[ "$current_hash" = "$APP_HASH" ]]; then
      test ! -e "$APP_QUARANTINE" && test ! -L "$APP_QUARANTINE" || recovery_status=1
      if (( recovery_status == 0 )); then
        /usr/bin/sudo /bin/mv "$APP_FINAL" "$APP_QUARANTINE" || recovery_status=1
      fi
    elif [[ "$current_hash" != "$OLD_APP_HASH" ]]; then
      recovery_status=1
    fi
  elif [[ -e "$APP_FINAL" || -L "$APP_FINAL" ]]; then
    recovery_status=1
  fi
  if [[ ! -d "$APP_FINAL" && -d "$APP_PREVIOUS" && ! -L "$APP_PREVIOUS" ]]; then
    test "$(/usr/bin/shasum -a 256 \
      "$APP_PREVIOUS/Contents/MacOS/GDriveBackupTiger" | /usr/bin/awk '{print $1}')" = \
      "$OLD_APP_HASH" || recovery_status=1
    if (( recovery_status == 0 )); then
      /usr/bin/sudo /bin/mv "$APP_PREVIOUS" "$APP_FINAL" || recovery_status=1
    fi
  elif [[ ! -d "$APP_FINAL" && $recovery_status -eq 0 ]]; then
    /usr/bin/sudo /usr/bin/ditto "$ROLLBACK/GDrive Backup Tiger.app" \
      "$APP_FINAL" || recovery_status=1
  fi

  current_hash=""
  if [[ -f "$SCRIPT_FINAL" && ! -L "$SCRIPT_FINAL" ]]; then
    current_hash="$(/usr/bin/shasum -a 256 "$SCRIPT_FINAL" | /usr/bin/awk '{print $1}')"
    if [[ "$current_hash" = "$SCRIPT_HASH" ]]; then
      test ! -e "$SCRIPT_QUARANTINE" && test ! -L "$SCRIPT_QUARANTINE" || recovery_status=1
      if (( recovery_status == 0 )); then
        /usr/bin/sudo /bin/mv "$SCRIPT_FINAL" "$SCRIPT_QUARANTINE" || recovery_status=1
      fi
    elif [[ "$current_hash" != "$OLD_SCRIPT_HASH" ]]; then
      recovery_status=1
    fi
  elif [[ -e "$SCRIPT_FINAL" || -L "$SCRIPT_FINAL" ]]; then
    recovery_status=1
  fi
  if [[ ! -f "$SCRIPT_FINAL" && -f "$SCRIPT_PREVIOUS" && ! -L "$SCRIPT_PREVIOUS" ]]; then
    test "$(/usr/bin/shasum -a 256 "$SCRIPT_PREVIOUS" | /usr/bin/awk '{print $1}')" = \
      "$OLD_SCRIPT_HASH" || recovery_status=1
    if (( recovery_status == 0 )); then
      /usr/bin/sudo /bin/mv "$SCRIPT_PREVIOUS" "$SCRIPT_FINAL" || recovery_status=1
    fi
  elif [[ ! -f "$SCRIPT_FINAL" && $recovery_status -eq 0 ]]; then
    /usr/bin/sudo /usr/bin/install -o 0 -g 0 -m 755 \
      "$ROLLBACK/backup-google-drive.sh" \
      "$SCRIPT_FINAL" || recovery_status=1
  fi

  if (( recovery_status == 0 )); then
    test "$(/usr/bin/shasum -a 256 \
      "$APP_FINAL/Contents/MacOS/GDriveBackupTiger" | /usr/bin/awk '{print $1}')" = \
      "$OLD_APP_HASH" || recovery_status=1
    test "$(/usr/bin/shasum -a 256 "$SCRIPT_FINAL" | /usr/bin/awk '{print $1}')" = \
      "$OLD_SCRIPT_HASH" || recovery_status=1
    test "$(/usr/bin/stat -f '%u:%g:%Lp' "$SCRIPT_FINAL")" = \
      "0:0:755" || recovery_status=1
  fi
  if (( recovery_status == 0 )); then
    reload_services || recovery_status=1
  fi
  if (( recovery_status != 0 )); then
    /bin/launchctl bootout "$DOMAIN" "$SCHEDULE_PLIST" >/dev/null 2>&1 || true
    /bin/launchctl bootout "$DOMAIN" "$CONTROLLER_PLIST" >/dev/null 2>&1 || true
  fi
  return "$recovery_status"
}

report_install_leftovers() {
  [[ -z "$STAGE" ]] || printf 'LEFTOVER_STAGE=%s\n' "$STAGE" >&2
  [[ -z "$ROLLBACK" ]] || printf 'LEFTOVER_ROLLBACK=%s\n' "$ROLLBACK" >&2
  [[ -z "$APP_TXN" ]] || printf 'LEFTOVER_APP_TRANSACTION=%s\n' "$APP_TXN" >&2
  [[ -z "$SCRIPT_TXN" ]] || printf 'LEFTOVER_SCRIPT_TRANSACTION=%s\n' "$SCRIPT_TXN" >&2
}

on_install_exit() {
  local status=$?
  trap - EXIT
  # RECOVERY_SIGNAL_GUARD
  trap '' HUP INT TERM
  if (( status != 0 && RECOVERY_ARMED == 1 )); then
    if ! recover_previous_install; then
      printf '%s\n' \
        'CRITICAL: hash-aware rollback failed; both services remain unloaded.' >&2
      status=1
    fi
  fi
  report_install_leftovers
  exit "$status"
}

handle_install_signal() {
  printf '%s\n' 'Installation interrupted; entering the guarded exit path.' >&2
  exit 130
}

assert_final_install_state() {
  local architectures new_controller_pid final_manifest final_entitlements
  local final_effective_state
  test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    "$APP_FINAL/Contents/Info.plist")" = "$EXPECTED_VERSION"
  test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
    "$APP_FINAL/Contents/Info.plist")" = "$EXPECTED_BUILD"
  architectures="$(/usr/bin/lipo -archs \
    "$APP_FINAL/Contents/MacOS/GDriveBackupTiger")"
  [[ " $architectures " == *" arm64 "* && " $architectures " == *" x86_64 "* ]]
  /usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_FINAL"
  test "$(/usr/bin/shasum -a 256 \
    "$APP_FINAL/Contents/MacOS/GDriveBackupTiger" | /usr/bin/awk '{print $1}')" = \
    "$APP_HASH"
  test "$(/usr/bin/shasum -a 256 "$SCRIPT_FINAL" | /usr/bin/awk '{print $1}')" = \
    "$SCRIPT_HASH"
  test "$(/usr/bin/stat -f '%u:%g:%Lp' "$SCRIPT_FINAL")" = "0:0:755"
  /bin/bash -n "$SCRIPT_FINAL"

  final_entitlements="$STAGE/final-entitlements.plist"
  extract_entitlements "$APP_FINAL" "$final_entitlements"

  # FINAL_RUNTIME_REVALIDATION
  final_manifest="$STAGE/config-after.manifest"
  canonical_config_manifest "$CONFIG_DIR" "$final_manifest"
  /usr/bin/cmp -s "$PREBUILD_CONFIG_MANIFEST" "$final_manifest"
  /usr/bin/cmp -s "$ROLLBACK/config-before.manifest" "$final_manifest"
  assert_default_profile_selection
  assert_safe_user_plist "$CONTROLLER_PLIST"
  assert_safe_user_plist "$SCHEDULE_PLIST"
  test "$(/usr/bin/shasum -a 256 "$CONTROLLER_PLIST" | /usr/bin/awk '{print $1}')" = \
    "$CONTROLLER_PLIST_HASH"
  test "$(/usr/bin/shasum -a 256 "$SCHEDULE_PLIST" | /usr/bin/awk '{print $1}')" = \
    "$SCHEDULE_PLIST_HASH"
  reject_service_path_overrides
  assert_loaded_service_contract \
    "$CONTROLLER_SERVICE" "$CONTROLLER_PLIST" "$CONTROLLER_PROGRAM" 2 \
    "$CONTROLLER_PROGRAM" "$CONTROLLER_ARGUMENT" "" \
    "$CONTROLLER_HOME" "$CONTROLLER_PATH" "" ""
  assert_loaded_service_contract \
    "$SCHEDULE_SERVICE" "$SCHEDULE_PLIST" "$SCHEDULE_PROGRAM" 3 \
    "$SCHEDULE_PROGRAM" "$SCHEDULE_SCRIPT" "$SCHEDULE_ARGUMENT" \
    "$SCHEDULE_HOME" "$SCHEDULE_PATH" "$SCHEDULE_TRIGGER" \
    "$SCHEDULE_ASSUME_YES"
  assert_manager_environment_clean
  final_effective_state="$STAGE/final-effective-state.sh"
  derive_effective_state "$final_effective_state"
  /usr/bin/cmp -s "$PREBUILD_EFFECTIVE_STATE" "$final_effective_state"
  # This refresh makes every remaining assertion use post-reload state rather
  # than values retained from before the build.
  # shellcheck source=/dev/null
  source "$final_effective_state"
  test "$EFFECTIVE_CONFIG" = "$PREBUILD_EFFECTIVE_CONFIG"
  test "$EFFECTIVE_LOCK" = "$PREBUILD_EFFECTIVE_LOCK"
  test "$EFFECTIVE_STATUS" = "$PREBUILD_EFFECTIVE_STATUS"
  test "$EFFECTIVE_PROGRESS" = "$PREBUILD_EFFECTIVE_PROGRESS"
  test "$PROFILE_TARGET" = "$PREBUILD_PROFILE_TARGET"
  test "$PROFILE_SCHEDULE" = "$PREBUILD_PROFILE_SCHEDULE"
  test "$PROFILE_NOTIFY_FAILURES" = "$PREBUILD_PROFILE_NOTIFY_FAILURES"
  test "$PROFILE_NAS_MOUNT" = "$PREBUILD_PROFILE_NAS_MOUNT"
  test "$PROFILE_NAS_URL" = "$PREBUILD_PROFILE_NAS_URL"
  assert_user_regular_file "$ACTIVE_PROFILE_FILE" "600"
  test "$(/usr/bin/stat -f '%z' "$ACTIVE_PROFILE_FILE")" = "$ACTIVE_PROFILE_SIZE"
  test "$(/usr/bin/od -An -tx1 -v "$ACTIVE_PROFILE_FILE" |
    /usr/bin/tr -d ' \n')" = "64656661756c740a"
  test "$PROFILE_TARGET" = "nas"
  test "$PROFILE_SCHEDULE" = "daily"
  test "$PROFILE_NOTIFY_FAILURES" = "1"
  test -n "$PROFILE_NAS_MOUNT$PROFILE_NAS_URL"
  test "$(/usr/bin/plutil -extract StartCalendarInterval.Hour raw -o - \
    "$SCHEDULE_PLIST")" = "20"
  test "$(/usr/bin/plutil -extract StartCalendarInterval.Minute raw -o - \
    "$SCHEDULE_PLIST")" = "0"
  new_controller_pid="$(/bin/launchctl print "$CONTROLLER_SERVICE" |
    /usr/bin/awk '/pid =/ {print $3; exit}')"
  [[ "$new_controller_pid" =~ ^[0-9]+$ ]]
  test "$new_controller_pid" != "$OLD_CONTROLLER_PID"
  # FINAL_STATUS_PROCESS_GATE
  assert_successful_terminal_backup_and_no_processes
}

test "$REPO_ROOT" = "$(pwd -P)"
test "$(git cat-file -t "refs/tags/$RELEASE_TAG")" = "tag"
test "$(git ls-remote origin "refs/tags/$RELEASE_TAG^{}" |
  /usr/bin/awk '{print $1}')" = "$RELEASE_COMMIT"
test "$(gh release view "$RELEASE_TAG" --json tagName --jq '.tagName')" = \
  "$RELEASE_TAG"
test "$(gh api "repos/$REPOSITORY/releases/latest" --jq '.tag_name')" = \
  "$RELEASE_TAG"
test "$(gh run list --workflow release.yml --branch "$RELEASE_TAG" \
  --commit "$RELEASE_COMMIT" --status completed --limit 1 \
  --json conclusion --jq '.[0].conclusion // empty')" = "success"
assert_absolute_single_line_path "$HOME"
test -d "$STATE_ROOT" && test ! -L "$STATE_ROOT"
test "$(/usr/bin/stat -f '%u' "$STATE_ROOT")" = "$CURRENT_UID"
for parent in "$ROLLBACK_PARENT" "$STAGE_PARENT"; do
  if [[ ! -e "$parent" && ! -L "$parent" ]]; then
    /bin/mkdir "$parent"
  fi
  test -d "$parent" && test ! -L "$parent"
  test "$(/usr/bin/stat -f '%u' "$parent")" = "$CURRENT_UID"
done

STAGE="$(/usr/bin/mktemp -d "$STAGE_PARENT/v2.4.4.XXXXXX")"
test -d "$STAGE" && test ! -L "$STAGE"
test "$(/usr/bin/stat -f '%u' "$STAGE")" = "$CURRENT_UID"
trap on_install_exit EXIT
trap 'handle_install_signal' HUP INT TERM

test -d "$CONFIG_DIR" && test ! -L "$CONFIG_DIR"
test "$(/usr/bin/stat -f '%u' "$CONFIG_DIR")" = "$CURRENT_UID"
assert_user_regular_file "$ACTIVE_PROFILE_FILE" "600"
ACTIVE_PROFILE_SIZE="$(/usr/bin/stat -f '%z' "$ACTIVE_PROFILE_FILE")"
test "$ACTIVE_PROFILE_SIZE" = "8"
ACTIVE_PROFILE_HEX="$(/usr/bin/od -An -tx1 -v "$ACTIVE_PROFILE_FILE" |
  /usr/bin/tr -d ' \n')"
test "$ACTIVE_PROFILE_HEX" = "64656661756c740a"
test -d "$PROFILES_DIR" && test ! -L "$PROFILES_DIR"
test "$(/usr/bin/stat -f '%u' "$PROFILES_DIR")" = "$CURRENT_UID"
assert_user_regular_file "$PROFILE_CONFIG" "600"
assert_default_profile_selection

assert_safe_user_plist "$CONTROLLER_PLIST"
assert_safe_user_plist "$SCHEDULE_PLIST"
CONTROLLER_LABEL="$(/usr/bin/plutil -extract Label raw -o - "$CONTROLLER_PLIST")"
CONTROLLER_PROGRAM="$(/usr/bin/plutil -extract ProgramArguments.0 raw -o - \
  "$CONTROLLER_PLIST")"
CONTROLLER_ARGUMENT="$(/usr/bin/plutil -extract ProgramArguments.1 raw -o - \
  "$CONTROLLER_PLIST")"
CONTROLLER_HOME="$(/usr/bin/plutil -extract EnvironmentVariables.HOME raw -o - \
  "$CONTROLLER_PLIST")"
CONTROLLER_PATH="$(/usr/bin/plutil -extract EnvironmentVariables.PATH raw -o - \
  "$CONTROLLER_PLIST")"
SCHEDULE_LABEL="$(/usr/bin/plutil -extract Label raw -o - "$SCHEDULE_PLIST")"
SCHEDULE_PROGRAM="$(/usr/bin/plutil -extract ProgramArguments.0 raw -o - \
  "$SCHEDULE_PLIST")"
SCHEDULE_SCRIPT="$(/usr/bin/plutil -extract ProgramArguments.1 raw -o - \
  "$SCHEDULE_PLIST")"
SCHEDULE_ARGUMENT="$(/usr/bin/plutil -extract ProgramArguments.2 raw -o - \
  "$SCHEDULE_PLIST")"
SCHEDULE_HOME="$(/usr/bin/plutil -extract EnvironmentVariables.HOME raw -o - \
  "$SCHEDULE_PLIST")"
SCHEDULE_PATH="$(/usr/bin/plutil -extract EnvironmentVariables.PATH raw -o - \
  "$SCHEDULE_PLIST")"
SCHEDULE_TRIGGER="$(/usr/bin/plutil -extract \
  EnvironmentVariables.GDRIVE_BACKUP_TRIGGER raw -o - "$SCHEDULE_PLIST")"
SCHEDULE_ASSUME_YES="$(/usr/bin/plutil -extract \
  EnvironmentVariables.BACKUP_ASSUME_YES raw -o - "$SCHEDULE_PLIST")"
test "$CONTROLLER_LABEL" = \
  "com.commcats.gdrivebackup"
test "$CONTROLLER_PROGRAM" = "$APP_FINAL/Contents/MacOS/GDriveBackupTiger"
test "$CONTROLLER_ARGUMENT" = "--menubar"
test "$CONTROLLER_HOME" = "$HOME"
test "$CONTROLLER_PATH" = "$SAFE_PATH"
test "$SCHEDULE_LABEL" = \
  "com.commcats.gdrivebackup.schedule"
test "$SCHEDULE_PROGRAM" = "/bin/bash"
test "$SCHEDULE_SCRIPT" = "$SCRIPT_FINAL"
test "$SCHEDULE_ARGUMENT" = "--run"
test "$SCHEDULE_HOME" = "$HOME"
test "$SCHEDULE_PATH" = "$SAFE_PATH"
test "$SCHEDULE_TRIGGER" = "schedule"
test "$SCHEDULE_ASSUME_YES" = "1"
reject_service_path_overrides
assert_loaded_service_contract \
  "$CONTROLLER_SERVICE" "$CONTROLLER_PLIST" "$CONTROLLER_PROGRAM" 2 \
  "$CONTROLLER_PROGRAM" "$CONTROLLER_ARGUMENT" "" \
  "$CONTROLLER_HOME" "$CONTROLLER_PATH" "" ""
assert_loaded_service_contract \
  "$SCHEDULE_SERVICE" "$SCHEDULE_PLIST" "$SCHEDULE_PROGRAM" 3 \
  "$SCHEDULE_PROGRAM" "$SCHEDULE_SCRIPT" "$SCHEDULE_ARGUMENT" \
  "$SCHEDULE_HOME" "$SCHEDULE_PATH" "$SCHEDULE_TRIGGER" \
  "$SCHEDULE_ASSUME_YES"
assert_manager_environment_clean
OLD_CONTROLLER_PID="$(/bin/launchctl print "$CONTROLLER_SERVICE" |
  /usr/bin/awk '/pid =/ {print $3; exit}')"
[[ "$OLD_CONTROLLER_PID" =~ ^[0-9]+$ ]]

# PREBUILD_SNAPSHOT
PREBUILD_EFFECTIVE_STATE="$STAGE/prebuild-effective-state.sh"
PREBUILD_CONFIG_MANIFEST="$STAGE/config-prebuild.manifest"
derive_effective_state "$PREBUILD_EFFECTIVE_STATE"
# shellcheck source=/dev/null
source "$PREBUILD_EFFECTIVE_STATE"
test "$EFFECTIVE_CONFIG" = "$PROFILE_CONFIG"
for effective_path in \
  "$EFFECTIVE_CONFIG" "$EFFECTIVE_LOCK" "$EFFECTIVE_STATUS" "$EFFECTIVE_PROGRESS"; do
  assert_absolute_single_line_path "$effective_path"
done
test "$PROFILE_TARGET" = "nas"
test "$PROFILE_SCHEDULE" = "daily"
test "$PROFILE_NOTIFY_FAILURES" = "1"
test -n "$PROFILE_NAS_MOUNT$PROFILE_NAS_URL"
PREBUILD_EFFECTIVE_CONFIG="$EFFECTIVE_CONFIG"
PREBUILD_EFFECTIVE_LOCK="$EFFECTIVE_LOCK"
PREBUILD_EFFECTIVE_STATUS="$EFFECTIVE_STATUS"
PREBUILD_EFFECTIVE_PROGRESS="$EFFECTIVE_PROGRESS"
PREBUILD_PROFILE_TARGET="$PROFILE_TARGET"
PREBUILD_PROFILE_SCHEDULE="$PROFILE_SCHEDULE"
PREBUILD_PROFILE_NOTIFY_FAILURES="$PROFILE_NOTIFY_FAILURES"
PREBUILD_PROFILE_NAS_MOUNT="$PROFILE_NAS_MOUNT"
PREBUILD_PROFILE_NAS_URL="$PROFILE_NAS_URL"
canonical_config_manifest "$CONFIG_DIR" "$PREBUILD_CONFIG_MANIFEST"
CONTROLLER_PLIST_HASH="$(/usr/bin/shasum -a 256 "$CONTROLLER_PLIST" |
  /usr/bin/awk '{print $1}')"
SCHEDULE_PLIST_HASH="$(/usr/bin/shasum -a 256 "$SCHEDULE_PLIST" |
  /usr/bin/awk '{print $1}')"

# A terminal/no-process gate before archive extraction keeps even the build
# outside an active backup window. The definitive race-free checks follow
# under the exact effective lock.
# PREBUILD_GATE
assert_successful_terminal_backup_and_no_processes

SOURCE_ARCHIVE="$STAGE/source.tar"
SOURCE_EXPORT="$STAGE/source"
STAGED_APP="$STAGE/build/GDrive Backup Tiger.app"
STAGED_BINARY="$STAGED_APP/Contents/MacOS/GDriveBackupTiger"
STAGED_SCRIPT="$SOURCE_EXPORT/bin/backup-google-drive.sh"
ENTITLEMENTS_PLIST="$STAGE/staged-entitlements.plist"
test ! -e "$SOURCE_ARCHIVE" && test ! -L "$SOURCE_ARCHIVE"
test ! -e "$SOURCE_EXPORT" && test ! -L "$SOURCE_EXPORT"
test ! -e "${STAGED_APP%/*}" && test ! -L "${STAGED_APP%/*}"
/bin/mkdir "$SOURCE_EXPORT" "${STAGED_APP%/*}"
git archive --format=tar --output="$SOURCE_ARCHIVE" "$RELEASE_TAG^{commit}"
test "$(git get-tar-commit-id <"$SOURCE_ARCHIVE")" = "$RELEASE_COMMIT"
/usr/bin/tar -xf "$SOURCE_ARCHIVE" -C "$SOURCE_EXPORT"
make -C "$SOURCE_EXPORT" test
"$SOURCE_EXPORT/scripts/validate-release.sh" "$RELEASE_TAG"
make -C "$SOURCE_EXPORT" APP_DIR="$STAGED_APP" build
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$STAGED_APP/Contents/Info.plist")" = "$EXPECTED_VERSION"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
  "$STAGED_APP/Contents/Info.plist")" = "$EXPECTED_BUILD"
architectures="$(/usr/bin/lipo -archs "$STAGED_BINARY")"
[[ " $architectures " == *" arm64 "* && " $architectures " == *" x86_64 "* ]]
/usr/bin/codesign --verify --deep --strict --verbose=2 "$STAGED_APP"
extract_entitlements "$STAGED_APP" "$ENTITLEMENTS_PLIST"
/usr/bin/plutil -lint "$ENTITLEMENTS_PLIST" >/dev/null
/bin/bash -n "$STAGED_SCRIPT"
APP_HASH="$(/usr/bin/shasum -a 256 "$STAGED_BINARY" | /usr/bin/awk '{print $1}')"
SCRIPT_HASH="$(/usr/bin/shasum -a 256 "$STAGED_SCRIPT" | /usr/bin/awk '{print $1}')"
[[ "$APP_HASH" =~ ^[0-9a-f]{64}$ && "$SCRIPT_HASH" =~ ^[0-9a-f]{64}$ ]]

FLOCK_BIN="$(command -v flock)"
test -x "$FLOCK_BIN"
LOCK_PARENT="${PREBUILD_EFFECTIVE_LOCK%/*}"
test -d "$LOCK_PARENT" && test ! -L "$LOCK_PARENT"
test "$(/usr/bin/stat -f '%u' "$LOCK_PARENT")" = "$CURRENT_UID"
if [[ -e "$PREBUILD_EFFECTIVE_LOCK" || -L "$PREBUILD_EFFECTIVE_LOCK" ]]; then
  test -f "$PREBUILD_EFFECTIVE_LOCK" && test ! -L "$PREBUILD_EFFECTIVE_LOCK"
  test "$(/usr/bin/stat -f '%u' "$PREBUILD_EFFECTIVE_LOCK")" = "$CURRENT_UID"
fi
exec 8>"$PREBUILD_EFFECTIVE_LOCK"
test "$(/usr/bin/stat -f '%u' "$PREBUILD_EFFECTIVE_LOCK")" = "$CURRENT_UID"
/bin/chmod 600 "$PREBUILD_EFFECTIVE_LOCK"
"$FLOCK_BIN" -n 8

test -d "/Applications" && test ! -L "/Applications"
test -d "/usr/local/bin" && test ! -L "/usr/local/bin"
test -d "$APP_FINAL" && test ! -L "$APP_FINAL"
test -f "$SCRIPT_FINAL" && test ! -L "$SCRIPT_FINAL" && test -x "$SCRIPT_FINAL"
test "$(/usr/bin/stat -f '%u:%g:%Lp' "$SCRIPT_FINAL")" = "0:0:755"
OLD_APP_HASH="$(/usr/bin/shasum -a 256 \
  "$APP_FINAL/Contents/MacOS/GDriveBackupTiger" | /usr/bin/awk '{print $1}')"
OLD_SCRIPT_HASH="$(/usr/bin/shasum -a 256 "$SCRIPT_FINAL" | /usr/bin/awk '{print $1}')"

STAMP="$(/bin/date -u '+%Y%m%dT%H%M%SZ')"
ROLLBACK="$(/usr/bin/mktemp -d "$ROLLBACK_PARENT/v2.4.4-$STAMP.XXXXXX")"
test -d "$ROLLBACK" && test ! -L "$ROLLBACK"
test "$(/usr/bin/stat -f '%u' "$ROLLBACK")" = "$CURRENT_UID"
canonical_config_manifest "$CONFIG_DIR" "$ROLLBACK/config-before.manifest"
/usr/bin/cmp -s "$PREBUILD_CONFIG_MANIFEST" \
  "$ROLLBACK/config-before.manifest"
/usr/bin/shasum -a 256 "$ROLLBACK/config-before.manifest" > \
  "$ROLLBACK/config-before.manifest.sha256"
/usr/bin/ditto "$APP_FINAL" "$ROLLBACK/GDrive Backup Tiger.app"
/usr/bin/sudo /usr/bin/install -o 0 -g 0 -m 755 "$SCRIPT_FINAL" \
  "$ROLLBACK/backup-google-drive.sh"
test "$(/usr/bin/shasum -a 256 \
  "$ROLLBACK/GDrive Backup Tiger.app/Contents/MacOS/GDriveBackupTiger" |
  /usr/bin/awk '{print $1}')" = "$OLD_APP_HASH"
test "$(/usr/bin/shasum -a 256 "$ROLLBACK/backup-google-drive.sh" |
  /usr/bin/awk '{print $1}')" = "$OLD_SCRIPT_HASH"
test "$(/usr/bin/stat -f '%u:%g:%Lp' "$ROLLBACK/backup-google-drive.sh")" = \
  "0:0:755"

APP_TXN="$(/usr/bin/sudo /usr/bin/mktemp -d "/Applications/.gdrive-v2.4.4-txn.XXXXXX")"
SCRIPT_TXN="$(/usr/bin/sudo /usr/bin/mktemp -d "/usr/local/bin/.gdrive-v2.4.4-txn.XXXXXX")"
/usr/bin/sudo /usr/sbin/chown "$CURRENT_UID:$CURRENT_GID" "$APP_TXN"
/bin/chmod 700 "$APP_TXN"
/usr/bin/sudo /usr/sbin/chown 0:0 "$SCRIPT_TXN"
/usr/bin/sudo /bin/chmod 755 "$SCRIPT_TXN"
test -d "$APP_TXN" && test ! -L "$APP_TXN"
test -d "$SCRIPT_TXN" && test ! -L "$SCRIPT_TXN"
test "$(/usr/bin/stat -f '%u' "$APP_TXN")" = "$CURRENT_UID"
test "$(/usr/bin/stat -f '%Lp' "$APP_TXN")" = "700"
test "$(/usr/bin/stat -f '%u:%g:%Lp' "$SCRIPT_TXN")" = "0:0:755"
test "$(/usr/bin/stat -f '%d' "$APP_TXN")" = "$(/usr/bin/stat -f '%d' /Applications)"
test "$(/usr/bin/stat -f '%d' "$SCRIPT_TXN")" = "$(/usr/bin/stat -f '%d' /usr/local/bin)"
APP_INCOMING="$APP_TXN/incoming.app"
SCRIPT_INCOMING="$SCRIPT_TXN/incoming"
APP_PREVIOUS="$APP_TXN/previous.app"
SCRIPT_PREVIOUS="$SCRIPT_TXN/previous"
APP_QUARANTINE="$APP_TXN/quarantine-new.app"
SCRIPT_QUARANTINE="$SCRIPT_TXN/quarantine-new"
test ! -e "$APP_INCOMING" && test ! -L "$APP_INCOMING"
test ! -e "$SCRIPT_INCOMING" && test ! -L "$SCRIPT_INCOMING"
test ! -e "$APP_PREVIOUS" && test ! -L "$APP_PREVIOUS"
test ! -e "$SCRIPT_PREVIOUS" && test ! -L "$SCRIPT_PREVIOUS"
test ! -e "$APP_QUARANTINE" && test ! -L "$APP_QUARANTINE"
test ! -e "$SCRIPT_QUARANTINE" && test ! -L "$SCRIPT_QUARANTINE"
/usr/bin/ditto "$STAGED_APP" "$APP_INCOMING"
/usr/bin/sudo /usr/bin/install -o 0 -g 0 -m 755 "$STAGED_SCRIPT" "$SCRIPT_INCOMING"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_INCOMING"
/bin/bash -n "$SCRIPT_INCOMING"
test "$(/usr/bin/shasum -a 256 \
  "$APP_INCOMING/Contents/MacOS/GDriveBackupTiger" | /usr/bin/awk '{print $1}')" = \
  "$APP_HASH"
test "$(/usr/bin/shasum -a 256 "$SCRIPT_INCOMING" | /usr/bin/awk '{print $1}')" = \
  "$SCRIPT_HASH"
test "$(/usr/bin/stat -f '%u:%g:%Lp' "$SCRIPT_INCOMING")" = "0:0:755"

# The EXIT and signal traps already see RECOVERY_ARMED before the first
# service mutation. Any signal from here enters hash-aware recovery.
# LOCKED_SNAPSHOT_REVALIDATION
assert_runtime_snapshot_matches_prebuild "$STAGE/config-locked.manifest" "$STAGE/locked-effective-state.sh"
# LOCKED_PRE_BOOTOUT_GATE
assert_successful_terminal_backup_and_no_processes
RECOVERY_ARMED=1
# FIRST_SERVICE_MUTATION
/bin/launchctl bootout "$DOMAIN" "$SCHEDULE_PLIST"
/bin/launchctl bootout "$DOMAIN" "$CONTROLLER_PLIST"
# POST_QUIESCE_GATE
assert_successful_terminal_backup_and_no_processes

/usr/bin/sudo /bin/mv "$APP_FINAL" "$APP_PREVIOUS"
/usr/bin/sudo /bin/mv "$APP_INCOMING" "$APP_FINAL"
/usr/bin/sudo /bin/mv "$SCRIPT_FINAL" "$SCRIPT_PREVIOUS"
/usr/bin/sudo /bin/mv "$SCRIPT_INCOMING" "$SCRIPT_FINAL"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_FINAL"
/bin/bash -n "$SCRIPT_FINAL"
test "$(/usr/bin/shasum -a 256 \
  "$APP_FINAL/Contents/MacOS/GDriveBackupTiger" | /usr/bin/awk '{print $1}')" = \
  "$APP_HASH"
test "$(/usr/bin/shasum -a 256 "$SCRIPT_FINAL" | /usr/bin/awk '{print $1}')" = \
  "$SCRIPT_HASH"
reload_services

# FINAL_VERIFICATION_UNDER_LOCK
assert_final_install_state
RECOVERY_ARMED=0
"$FLOCK_BIN" -u 8
exec 8>&-
trap - EXIT HUP INT TERM
report_install_leftovers
printf 'Installed %s build %s from %s.\n' \
  "$EXPECTED_VERSION" "$EXPECTED_BUILD" "$RELEASE_COMMIT"
```
<!-- GDT-RUNBOOK-INSTALL:END -->

Expected: the immutable tagged export passes its complete test suite and
release validator before build. The effective scheduled-profile lock remains
held from the last pre-mutation gate through service, configuration, version,
entitlement, and process verification. On failure or interruption, only known
hashes are moved and the old pair is restored before services reload; an
ambiguous rollback leaves both services unloaded and reports a critical state.
All printed `LEFTOVER_*` paths remain recoverable for inspection.

- [ ] **Step 5: Finish project memory and report recoverable artifacts**

```bash
/Users/alexandersmyslowski/Projects/central-agent-data-hub/scripts/agent_finish.sh \
  --project gdrive-tiger-backup --review
git status --short --branch
git log --oneline --decorate --max-count=12
gh release view v2.4.4 --json tagName,url,assets
```

If the Hub remains unavailable, report that separately and do not claim memory
writeback. Do not delete rollback copies, NAS data, profiles, or unrelated user
files.
