# Native scheduled backup implementation plan

Spec: ../specs/2026-10-16-native-scheduled-backup.md

## Global constraints

Use this existing isolated dirty runtime-source worktree at HEAD 91a5241adcb2afb2de5d032d7f9685e89f4df4be. Preserve all prior WIP; never build into /Applications. New global ADH retirement overrides legacy repo Hub prerequisite; keep writer lock and all review/data gates. No deployment, copy run, secret reads, TCC/Keychain edits or unrelated source changes. Accepted dirty state must be hashed. Use Trash for deletion.

## Task 1: Native worker, schedule generator and regression tests

One bounded implementer owns the coherent worker/generator/lifecycle change with TDD. Allowed: main.m, focused ScheduledBackupSupport.h/m if needed, Makefile and explicit build-input lists if new module needed, relevant tests/new scheduled-worker tests, concise README documentation and migration/rollback runbook. Do not change engine/data/auth behavior or existing retry controller. First run baseline appropriate suites and preserve evidence. Add meaningful failing regression tests, implement fixed native worker with safe process/signal/env contract, update generator for daily/hourly/login, and verify focused tests, safety suites/full make test and staged universal build. Preserve source originals/fingerprint. Report real commands, exits, RED/GREEN evidence and any existing failures. No committing unrelated WIP.

## Task 2: Independent task review and final acceptance

Coordinator packages task-only diff against preserved baseline and candidate hashes; fresh strong reviewer assesses spec and quality/risk. Fix load-bearing findings through implementer, affected tests and independent re-review. Final broad independent review evaluates all task changes and migration/rollback procedure, bound to candidate fingerprint. Preserve evidence and update existing runtime handoff truthfully. Candidate approval does not equal live recovery; installed app and existing schedule remain untouched until separate authorized installation gate.
