# APFS Volume UUID Idempotence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Spec:** `docs/superpowers/specs/2026-09-05-apfs-volume-uuid-idempotence.md`

**Goal:** Prevent duplicate APFS backup-volume creation and make every
successful external-volume run UUID-bound and repeatable.

**Architecture:** Keep the existing UUID resolver authoritative. Strengthen
the path-binding and pre-create setup paths: distinguish visible interactive
setup from every other trigger, discover one eligible external APFS container,
evaluate and refresh its named UUID set before mutation, recover a unique
existing volume, and fail closed on ambiguity. Persist the resolved identity
and rebased destination atomically with the existing config writer.

**Tech stack:** macOS Bash 3.2, `diskutil` property lists, `plutil`, `jq`, shell
test doubles, Objective-C release application.

## Global Constraints

- Work only in the clean isolated worktree based on the verified `origin/main`.
- Preserve the dirty canonical worktree and all unknown user changes exactly.
- Never use `rm`; cleanup must remain recoverable through the project trash
  helper or `/usr/bin/trash`.
- Do not mutate, create, rename, unmount, erase, or delete any live disk or
  volume. All mutation tests use fakes and temporary directories.
- Never add volume deletion, erasure, repartitioning, rename, or unmount code.
- Never expose UUIDs in user-facing dialogs; technical UUIDs may remain in
  private configuration and diagnostic logs where already documented.
- Do not let `BACKUP_ASSUME_YES` authorize APFS volume creation.
- Do not let configuration files establish an invocation trigger or one-run
  APFS creation authority.
- Tests assert observable behavior, not source-code text.

## Task 1: Reproduce and fix the pre-create identity gap

**Files:**
- Modify: `tests/backup-encryption-test.sh`
- Modify: `bin/backup-google-drive.sh`

- [ ] Extend the fake APFS inventory and `diskutil info` mapping to represent
      zero, one, or multiple existing named volume UUIDs and multiple external
      containers without touching a real disk.
- [ ] Add a RED test in which a stale configured path and empty UUID encounter
      exactly one existing named volume. Run the same config twice and require
      both copies to use its UUID-resolved mount with zero `addVolume` calls.
- [ ] Add a RED ambiguity test that runs twice and requires exit 69, unchanged
      config and canaries, an actionable log message, and zero disk mutation,
      privileged helper, or rclone copy calls.
- [ ] Add a RED test requiring multiple eligible external APFS containers to
      abort instead of selecting by mtime.
- [ ] Add a RED test proving scheduled/retry `BACKUP_ASSUME_YES=1` cannot
      authorize a new APFS volume. Prove that schedule, retry, mount,
      overview/menu-bar, and unknown triggers cannot create or prompt even if
      approval variables are set, while distinct interactive setup can.
- [ ] Add a RED path-only test: noninteractive runs fail closed, while visible
      setup validates and persists an exact external APFS UUID before copying.
- [ ] Add a RED confirmation-race test in which an exact-name volume appears
      before mutation; recover it or abort without calling `addVolume`.
- [ ] Add RED inventory tests that scope matching to the selected container
      and reject an exact-name record whose UUID is absent or malformed.
- [ ] Implement deterministic single-container discovery, pre-create UUID-set
      evaluation and refresh, UUID-based recovery/persistence for one
      candidate, fail-closed ambiguity handling, and setup-only authorization.
- [ ] Persist a rebased nested `GDRIVE_BACKUP_DEST_ROOT` with the resolved UUID
      and mount path.
- [ ] Snapshot and validate invocation trigger and creation approval before
      sourcing configuration; a profile may establish neither capability.
- [ ] Route only the visible app setup action through the `setup` trigger,
      preserve its foreground progress, and keep overview/menu-bar, mount,
      schedule, and retry launches non-capable.
- [ ] Preserve post-create partial-success detection and UUID/device/path
      revalidation.
- [ ] Run `bash tests/backup-encryption-test.sh` twice consecutively and
      `bash -n bin/backup-google-drive.sh tests/backup-encryption-test.sh`.
- [ ] Commit the reviewed engine and regression-test change.

## Task 2: Document the safety contract and prepare the patch release

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`
- Modify: `docs/version-history.md`
- Modify: `macos/GDriveBackupTiger/Info.plist`
- Modify: release metadata tests as required by their existing contract

- [ ] Document unique-container selection, UUID recovery, ambiguity aborts,
      and the fact that automatic approval cannot create a volume.
- [ ] State explicitly that the routine never deletes, erases, repartitions,
      renames, or unmounts a volume.
- [ ] Bump the patch release and build consistently across application,
      README, changelog, history, and release tests.
- [ ] Run release metadata/workflow tests and commit the documentation/release
      metadata change.

## Task 3: Whole-branch verification and safe publication

**Files:** No functional source changes expected.

- [ ] Run the full test suite and shell/static validation from the clean
      worktree.
- [ ] Review the complete branch diff for spec compliance and code quality.
- [ ] Verify the live Toshiba configuration read-only: its saved UUID still
      resolves the intended current mount despite the stale historical path.
- [ ] Build and verify the release package from the exact reviewed commit,
      including app version/build, architectures, signature, and checksums.
- [ ] Commit any generated release notes required by the repository contract,
      push the reviewed branch, merge through the repository's established
      workflow, tag, publish, and verify the GitHub release and CI.
- [ ] Install only the verified release artifact with a dated rollback copy;
      do not alter profiles, schedules, backup data, or any disk layout.
- [ ] Verify installed helper hash/syntax, app version/build, active profile,
      schedule/controller state, and UUID-based Toshiba resolution.
- [ ] Finish the Central Agent Data Hub review run.
