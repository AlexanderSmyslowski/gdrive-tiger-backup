# Third-Party Onboarding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give a new third-party user a short, destination-neutral first-run setup that clearly separates one automatic daily backup destination from an optional external disk used for on-demand backups, while preserving the existing backup engine, retry behavior, NAS policy, profile format, and launchd services.

**Architecture:** Add a small onboarding support module for persisted first-run state and a native AppKit onboarding view. `AppDelegate` remains the owner of configuration, health checks, schedule installation, and backup launch. On first run it presents the onboarding view inside the existing setup window; advanced setup and explicit unknown-disk setup continue to use the existing expert controls. A successful final save writes the onboarding version together with the existing config transaction. The optional manual disk uses the existing APFS volume identity fields and never changes the automatic target or schedule.

**Tech Stack:** Objective-C/AppKit, Foundation, existing `GDTReadConfigDictionary`/`GDTWriteConfigUpdates`, existing `GDTSetupHealthChecker`, shell-based regression tests, Makefile/installer source lists.

**Status:** Implemented on branch `codex/third-party-onboarding`. Focused onboarding tests, source build, localization, routing, destination-role preservation, and transactional completion checks are green. The full suite's existing GUI smoke test requires a live CoreSimulator/LaunchServices environment and cannot complete in this headless workspace.

## Global Constraints

- Do not change `bin/backup-google-drive.sh`, rclone arguments, retry timing, NAS mount behavior, profile identifiers, launchd labels, or the automatic backup schedule semantics.
- There is exactly one automatic primary destination and one automatic schedule. The optional external disk is retained for explicit `Backup jetzt` use only; it must not create a second scheduled job.
- Unknown disks remain passive: one notification per attachment, no focus stealing, no write, no format, and no automatic backup. Saving an explicitly staged disk may register its UUID while leaving the current NAS target and schedule unchanged.
- All onboarding writes are atomic and recoverable. A failed readiness check or failed save must not mark onboarding complete.
- Use existing localization fallback behavior and provide copy for all seven supported language codes (`de`, `en`, `fr`, `es`, `ja`, `yue`, `ko`).
- Keep the existing expert setup available through an explicit “Erweiterte Einrichtung” action.
- New temporary test binaries and build artifacts are removed only with `scripts/trash-path.sh`/`/usr/bin/trash`.

---

## Task 1: Add first-run state helpers with tests

**Files:** `macos/GDriveBackupTiger/OnboardingSupport.h`, `macos/GDriveBackupTiger/OnboardingSupport.m`, `tests/onboarding-support-test.m`, `Makefile`.

- [ ] Write `tests/onboarding-support-test.m` first. Cover: missing key means onboarding is required; version `1` means it is complete; future/invalid versions still require onboarding; helper reads only the supplied dictionary and does not mutate it.
- [ ] Run the focused test and confirm it fails because the support API does not exist.
- [ ] Add a constant `GDTOnboardingVersion = @"1"` and pure Foundation helpers such as `GDTOnboardingNeedsPresentation(NSDictionary *)` and `GDTOnboardingCompletionUpdate(void)`; treat the persisted value as an exact supported version.
- [ ] Add the new source to the app source list and the focused test recipe in `Makefile`.
- [ ] Run the focused test again and confirm it passes; run `git diff --check`.
- [ ] Commit as `test/onboarding: add first-run state contract` and `feat(onboarding): add persisted first-run state helpers` only after the corresponding red/green checks.

## Task 2: Build a native, accessible three-step onboarding view

**Files:** `macos/GDriveBackupTiger/OnboardingSupport.h`, `macos/GDriveBackupTiger/OnboardingSupport.m`, `tests/onboarding-ui-test.m`, `Makefile`.

- [ ] Write a failing AppKit test that instantiates the view without a window and asserts: three step labels, destination choice controls, automatic/manual role summaries, readiness summary, schedule/notification summary, primary/secondary actions, and accessibility labels for every actionable control.
- [ ] Run the focused UI test and confirm it fails before the view exists.
- [ ] Implement `TigerOnboardingView` as a flipped native `NSView` with explicit step state (`destination`, `readiness`, `schedule`), native controls, and block-based action callbacks. Expose methods to apply the current configuration/readiness snapshot and to move between steps without starting a backup.
- [ ] Render destination-neutral copy: “Automatisch: …, täglich 20:00” and “Manuell: …, wenn verbunden”; make the manual row optional when no external volume is staged.
- [ ] Disable “Weiter” until the current step is valid; keep “Erweiterte Einrichtung” and “Abbrechen” available without changing config.
- [ ] Run the UI test and confirm it passes, including accessibility role/name assertions; run `git diff --check`.
- [ ] Commit as `test(onboarding): define three-step native UI contract` and `feat(onboarding): add accessible onboarding view`.

## Task 3: Route first-run users without changing existing setup flows

**Files:** `macos/GDriveBackupTiger/main.m`, `tests/onboarding-routing-test.sh`, `tests/setup-window-health-test.sh`.

- [ ] Add static regression assertions first: normal first-run entry calls onboarding; menu/settings entry opens expert setup; explicit unknown-volume setup bypasses onboarding; background mount/retry events do not activate the app window.
- [ ] Run the routing test and confirm it fails against the current direct `showSetupWindow` path.
- [ ] Add `onboardingMode`/`onboardingStep` state and a focused `showOnboardingWindow` path that reuses the existing setup window lifecycle. Keep `showSetupWindow` as expert setup and add an explicit action from onboarding to it.
- [ ] On first-run entry, read the active profile config and call `GDTOnboardingNeedsPresentation`; do not infer onboarding from a missing NAS, missing disk, or a transient mount event.
- [ ] Ensure the existing window remains the only foreground window and that notification handlers never call the onboarding route automatically.
- [ ] Run routing, setup-window, and existing window-behavior tests; confirm all pass.
- [ ] Commit as `test(onboarding): lock first-run routing boundaries` and `feat(onboarding): route new users through guided setup`.

## Task 4: Wire destination choice and the two destination roles

**Files:** `macos/GDriveBackupTiger/main.m`, `tests/onboarding-destination-test.m`, `tests/setup-safety-test.m`.

- [ ] Add failing tests for: selecting NAS as the automatic primary destination; selecting an external APFS disk as the automatic primary destination; staging an additional external disk while NAS remains primary; saving the staged disk preserves `GDRIVE_BACKUP_TARGET`, `GDRIVE_BACKUP_SCHEDULE`, and NAS fields; no second schedule key/job is written.
- [ ] Run the focused tests and confirm the new cases fail.
- [ ] Bind the onboarding destination selector to the existing `targetPopup` semantics. Reuse `configuredAPFSVolumePath`/`configuredAPFSVolumeUUID` for the optional manual disk instead of introducing a parallel volume format.
- [ ] Show the optional manual-disk row only when a disk is explicitly staged or already registered; label it as on-demand and connected-only. Do not auto-select it as the primary target.
- [ ] Keep unknown-disk actions transactional: stage in memory, revalidate on the explicit setup action, and let only the existing Save path persist the identity.
- [ ] Run the destination and setup-safety tests plus existing mount-trigger/profile tests; confirm all pass.
- [ ] Commit as `test(onboarding): cover automatic and manual destination roles` and `feat(onboarding): expose dual destination roles safely`.

## Task 5: Reuse readiness checks and make completion transactional

**Files:** `macos/GDriveBackupTiger/main.m`, `tests/onboarding-save-test.m`, `tests/setup-safety-test.m`.

- [ ] Write failing tests for: readiness uses the existing checker; a failed check leaves the onboarding key absent; a successful final save writes `GDRIVE_BACKUP_ONBOARDING_VERSION=1` together with schedule/notification/destination values; a schedule or config write error leaves the key absent; a manual-only schedule disables notification confirmation consistently with expert setup.
- [ ] Run the focused tests and confirm they fail.
- [ ] Feed `runSetupHealthCheck:` snapshots into the onboarding readiness step and reuse `completeSetupHealthCheck:` so the same dependency, Google Drive, and destination checks are shown.
- [ ] Make the final onboarding action call the existing validation and schedule application path, then include `GDRIVE_BACKUP_ONBOARDING_VERSION=1` in the same successful config update. Do not set it when validation, atomic write, or schedule installation fails.
- [ ] After completion, refresh the overview so the user sees the selected automatic target, daily schedule, notification state, and optional manual disk role; retain the existing `Backup jetzt` behavior.
- [ ] Run onboarding-save, setup-safety, notification-integration, and launch-agent-safety tests; confirm all pass.
- [ ] Commit as `test(onboarding): enforce transactional completion` and `feat(onboarding): finish setup only after verified save`.

## Task 6: Localize and polish the public-facing copy

**Files:** `macos/GDriveBackupTiger/Localization.m`, `tests/onboarding-localization-test.sh`, `tests/onboarding-ui-test.m`.

- [ ] Add a failing localization test that checks every onboarding key exists with non-empty values in all seven language dictionaries and that the German copy includes the automatic/manual distinction.
- [ ] Run the test and confirm it fails before the keys exist.
- [ ] Add concise keys for title, purpose/limitations, the three step labels, automatic target, optional manual target, readiness states, schedule/notification confirmation, continue/back, advanced setup, cancel, and first-backup action in every language table.
- [ ] Keep terminology consistent with existing `T(...)` keys (`nas`, `externalVolume`, `scheduleDaily`, `notifyBackupFailures`, `backupNow`).
- [ ] Run localization and UI tests; confirm no key falls back to an empty string.
- [ ] Commit as `test(onboarding): require complete localized copy` and `feat(onboarding): localize third-party first run`.

## Task 7: Build integration, documentation, and release verification

**Files:** `Makefile`, `install.sh`, `README.md`, `CHANGELOG.md`, `docs/version-history.md`, `tests/onboarding-build-integration-test.sh`, `tests/release-metadata-test.sh`.

- [ ] Add a failing integration test that checks the new source is compiled by both Makefile and installer, the onboarding persistence key is documented, and the public README describes NAS plus external-disk choices without promising two automatic schedules.
- [ ] Run the test and confirm it fails.
- [ ] Add the source file to every build/test compile list, update the installer’s source list, and add the onboarding test to `make test`.
- [ ] Document the first-run flow, passive unknown-disk behavior, automatic-primary/manual-secondary roles, and the advanced setup escape hatch. Add a changelog/version-history entry without changing the backup engine or config migration behavior.
- [ ] Run the focused integration test, then `make test`, `make build`, `bash -n`/`shellcheck` targets, `git diff --check`, and the existing release metadata/workflow tests.
- [ ] Verify the built app launches and that an existing profile with `GDRIVE_BACKUP_ONBOARDING_VERSION=1` opens expert setup directly; do not install over `/Applications` or alter NAS data in this branch.
- [ ] Commit as `test(onboarding): cover build and release integration` and `docs(onboarding): explain public first-run setup`.

## Final verification checklist

- [ ] All focused onboarding tests are green.
- [ ] Full repository test suite and build are green.
- [ ] Existing profile, mount-trigger, notification, retry, and launch-agent safety tests remain green.
- [ ] `git diff --check` and shell syntax/lint checks are clean.
- [ ] No backup script, rclone invocation, profile identifier, NAS path, schedule service, or existing user configuration was changed.
- [ ] Worktree contains only onboarding implementation, tests, and documentation changes.
