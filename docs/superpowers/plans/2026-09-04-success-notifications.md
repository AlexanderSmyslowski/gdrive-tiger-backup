# Successful Backup Notifications Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a quiet, deduplicated recovery notification after a resolved automatic-backup problem and an opt-in notification for routine automatic successes.

**Architecture:** Keep pure eligibility and identifier validation in `GDTBackupNotificationPolicy`. Add a separate success-delivery path in the persistent controller so the hardened persistent-failure lifecycle remains unchanged; capture the active issue before the existing success cleanup clears it. Persist the independent routine-success preference through setup and both installers.

**Tech Stack:** Objective-C/AppKit/UserNotifications, shell installers, native Objective-C and shell regression harnesses.

**Spec:** `docs/superpowers/specs/2026-09-04-success-notifications-design.md`

## Global Constraints

- Routine automatic-success notifications default to off.
- Recovery notifications are quiet, visible once, and enabled with automatic-failure notifications.
- Success notifications never use sound, time-sensitive interruption, modal UI, application activation, paths, file names, accounts, remotes, or credentials.
- Only validated `schedule` and structurally valid first `schedule-retry` successes are eligible.
- Manual success never notifies and never clears an automatic failure.
- Existing failure cleanup remains independent and cannot erase a newer issue.
- Preserve the dirty canonical worktree; work only in the isolated `codex/success-notifications` worktree.
- Stage only the explicit feature allow-list; never stage unrelated files.

---

### Task 1: Success eligibility and controller delivery

**Files:**
- Modify: `macos/GDriveBackupTiger/NotificationSupport.h`
- Modify: `macos/GDriveBackupTiger/NotificationSupport.m`
- Modify: `macos/GDriveBackupTiger/main.m`
- Test: `tests/notification-support-test.m`
- Test: `tests/notification-integration-test.m`

**Interfaces:**
- Consumes: validated summary status from `GDTBackupSummaryStatusForValues`, the profile's captured active issue timestamp, and the captured success-monitor timestamp.
- Produces: `+successDecisionForConfig:summary:status:activeIssueTimestamp:now:` and a controller path that delivers a canonical `kind=success` decision once per profile and finish timestamp.

- [ ] **Step 1: Write policy tests that fail because success decisions do not exist**

Add literal fixtures and assertions covering: recovery after a normal scheduled failure; recovery after a valid first retry; routine success only with `GDRIVE_BACKUP_NOTIFY_SUCCESSES=1`; rejection of manual, stale, future, malformed, paused, disabled, wrong-attempt, and non-advancing outcomes. The desired decision has this observable shape:

```objective-c
@{
  @"identifier": @"com.commcats.gdrivebackup.office.success.1788550200",
  @"kind": @"success",
  @"profileID": @"office",
  @"eventTimestamp": @"1788550200",
  @"titleKey": @"backupNotificationSuccessTitle",
  @"bodyKey": @"backupNotificationRetrySuccessBody"
}
```

- [ ] **Step 2: Run the focused policy harness and verify RED**

Run:

```bash
make -s test-notification-support
```

If no focused target exists, compile and run the exact `NOTIFICATION_SUPPORT_TEST_BIN` recipe from `make test`. Expected failure: success-policy selector or assertions are unavailable while all pre-existing assertions still run.

- [ ] **Step 3: Implement the minimal pure success policy**

Expose and implement:

```objective-c
+ (NSDictionary<NSString *, NSString *> * _Nullable)
    successDecisionForConfig:(NSDictionary<NSString *, NSString *> *)config
                     summary:(NSDictionary<NSString *, NSString *> *)summary
                      status:(NSString *)status
        activeIssueTimestamp:(NSTimeInterval)activeIssueTimestamp
                         now:(NSDate *)now;
```

Validate the exact trust boundary in the spec, select the recovery/retry/routine body key, and emit only safe profile/timestamp metadata.

- [ ] **Step 4: Run the focused policy harness and verify GREEN**

Run the same command or exact recipe from Step 2. Expected: all notification-policy assertions pass.

- [ ] **Step 5: Write controller tests that fail because success delivery is absent**

Extend the integration harness to assert real observable effects: accepted delivery is persisted only after completion, repeated refresh/restart does not deliver again, refusal remains retryable, a newer accepted success removes one older canonical success identifier, success content is `GDT_BACKUP_SUCCESS` with `sound=nil` and normal non-time-sensitive interruption, foreground presentation excludes sound, and failure cleanup still occurs whether delivery succeeds or fails.

- [ ] **Step 6: Run the focused integration harness and verify RED**

Compile and run the exact `NOTIFICATION_INTEGRATION_TEST_BIN` recipe from `make test`. Expected failure: the success processing selector/content/lifecycle behavior is absent.

- [ ] **Step 7: Implement minimal controller delivery and refresh integration**

Add a success-specific processor with monotonic per-profile state. Capture `activeIssueAt` before background summary evaluation, compute the pure success decision off the main thread, clear eligible old failure state exactly as before, then process the success decision. Add a `GDT_BACKUP_SUCCESS` category. Branch content and foreground presentation by decision/category so success stays silent and never time-sensitive.

- [ ] **Step 8: Run both focused notification harnesses and verify GREEN**

Run both exact native recipes. Expected: all policy and integration assertions pass without compiler warnings.

- [ ] **Step 9: Commit Task 1**

Stage only the five files listed above and commit:

```bash
git commit -m "feat: confirm recovered automatic backups"
```

### Task 2: Optional routine-success preference and public documentation

**Files:**
- Modify: `macos/GDriveBackupTiger/main.m`
- Modify: `macos/GDriveBackupTiger/Localization.m`
- Modify: `install.sh`
- Modify: `packaging/scripts/postinstall`
- Modify: `README.md`
- Modify: `CHANGELOG.md`
- Test: `tests/setup-safety-test.m`
- Test: `tests/setup-window-health-test.sh`
- Test: `tests/notification-integration-test.m`
- Test: `tests/release-metadata-test.sh`

**Interfaces:**
- Consumes: `GDRIVE_BACKUP_NOTIFY_SUCCESSES` from Task 1's policy; missing values mean disabled.
- Produces: one native setup checkbox, persisted `0`/`1`, independent authorization behavior, installer default `0`, seven-language copy, and user-facing configuration documentation.

- [ ] **Step 1: Write failing setup, installer, authorization, and localization tests**

Assert that setup exposes a second native checkbox titled by `notifyBackupSuccesses`, saves `GDRIVE_BACKUP_NOTIFY_SUCCESSES`, defaults a missing key to off without false unsaved changes, disables both notification switches for a manual schedule, and requests notification authorization when either preference is enabled. Assert both installers create/migrate the explicit `0` default. Assert these keys resolve in all seven languages:

```text
notifyBackupSuccesses
backupNotificationSuccessTitle
backupNotificationSuccessBody
backupNotificationRecoverySuccessBody
backupNotificationRetrySuccessBody
```

- [ ] **Step 2: Run the affected harnesses and verify RED**

Run the setup-safety native recipe plus:

```bash
bash tests/setup-window-health-test.sh
bash tests/release-metadata-test.sh
```

Expected failures name the missing control, config default, installer migration, authorization branch, or localization keys.

- [ ] **Step 3: Implement the setup preference and localized copy**

Add `successNotificationCheckbox`, place it below the existing failure switch without overlap, persist `1` or `0`, add the default `0` to comparison logic, and enable it only for automatic schedules. Add reviewed translations for every key in German, English, French, Spanish, Japanese, Cantonese, and Korean. Change authorization gating to treat either notification preference as enabled.

- [ ] **Step 4: Add backward-compatible installer defaults**

New configuration blocks write:

```text
GDRIVE_BACKUP_NOTIFY_SUCCESSES=0
```

Existing configurations receive the key only when absent. Never overwrite an existing value.

- [ ] **Step 5: Run the affected harnesses and verify GREEN**

Run the same commands from Step 2 and the focused notification integration recipe. Expected: all assertions pass without warnings.

- [ ] **Step 6: Document the behavior**

Add one `Unreleased` changelog entry and update README configuration/behavior text: recovery confirmations are quiet and automatic; routine success notifications are explicitly opt-in; failures remain persistent and success cleanup remains independent.

- [ ] **Step 7: Commit Task 2**

Stage only the ten files listed above and commit:

```bash
git commit -m "feat: make routine success notices optional"
```

### Task 3: Full verification and publication-ready branch

**Files:**
- Verify only: all feature files and existing release metadata.

**Interfaces:**
- Consumes: the complete Task 1 and Task 2 implementation.
- Produces: a reviewed branch ready for GitHub pull-request publication; this task does not tag or publish a release.

- [ ] **Step 1: Run the complete regression suite**

```bash
make test
```

Expected: exit code `0`, no failed assertions, compiler warnings, shellcheck findings, or plist errors.

- [ ] **Step 2: Verify build and branch hygiene**

```bash
git status --short
git diff --check origin/main...HEAD
git log --oneline origin/main..HEAD
```

Expected: only the approved plan/spec and feature files differ; no secrets, generated packages, or unrelated changes exist.

- [ ] **Step 3: Review the complete diff**

Perform specification and code-quality review against the design, including the notification race boundaries and config migration behavior. Resolve every load-bearing finding before publication.

- [ ] **Step 4: Prepare GitHub publication**

Push `codex/success-notifications` and open a pull request only after all review and verification gates pass. Do not create a release tag or installer in this task.

