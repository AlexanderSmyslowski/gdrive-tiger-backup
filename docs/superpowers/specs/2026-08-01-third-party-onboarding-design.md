# Third-Party Onboarding Design

## Goal

Give a new user a short, trustworthy first-run path to a working Google Drive backup without exposing the full expert setup surface at once. The onboarding must make the destination, safety guarantees, readiness result, schedule, and first backup action unambiguous.

## Scope

The feature is an optional first-run layer inside the existing app process and setup window. It covers first-run explanation, destination selection, readiness checking, schedule/notification confirmation, and handoff to the existing overview. Existing advanced setup, profiles, encryption choices, restore, diagnostics, and manual controls remain available through an explicit “Advanced setup” action.

The feature does not change the backup engine, rclone copy semantics, NAS mount policy, retry policy, profile format, launchd identifiers, or destination defaults.

The onboarding distinguishes one automatic primary destination from an optional manually triggered external-volume destination. It does not introduce two competing automatic schedules.

## User flow

### Step 1: Understand and choose destinations

The window explains in plain language that the app creates an independent copy, never deletes files in Google Drive, and can restore files later. The user chooses the **automatic primary destination**: “NAS / network share” or “External disk”. A separate optional choice can register a directly attached external disk for **manual “Backup now” use**. The two roles are displayed separately so a NAS schedule is never replaced by a newly attached disk. The existing destination controls and identity checks remain the source of truth; the onboarding only presents them in a narrower sequence.

### Step 2: Check readiness

The app runs the existing asynchronous setup-health check. It presents three explicit rows: required tools, Google Drive access, and destination readiness. While checking, the primary action is disabled and the state is announced to VoiceOver. A failure shows one safe, actionable explanation and a retry action; no raw command output or credentials are shown. A successful check enables the next step.

### Step 3: Confirm schedule and first run

The user confirms daily automatic backups for the primary destination, the time (default 20:00), and failure notifications. If a manual external disk was registered, the confirmation shows both roles, for example “Automatic: NAS, daily 20:00” and “Manual: Toshiba_4TB, when connected”. The copy and retry behavior are summarized beside the confirmation. Save remains transactional: no backup starts and no configuration is changed until the user explicitly confirms. After save, the app shows “Ready for first backup”, both resolved destination roles, the next scheduled run, and one explicit “Backup now” action whose target is visible before launch.

## State and persistence

Onboarding completion is stored in the active profile configuration using one versioned key, `GDRIVE_BACKUP_ONBOARDING_VERSION`. Version `1` is written only after a successful save and readiness confirmation. Existing installations without the key continue to open the current setup/overview and are never treated as newly configured solely because a same-name volume is mounted. Reopening onboarding is always available from setup and does not reset saved values.

The onboarding reads and writes through the existing configuration/profile helpers. It must preserve `GDRIVE_BACKUP_TARGET`, the optional retained external-volume identity, NAS configuration, encryption settings, schedule, notification preference, and pause state exactly as the current setup does. A newly attached unknown disk is only staged after explicit user action and is saved only after explicit confirmation; it never silently replaces the automatic primary target.

## Architecture

Add a focused onboarding view/state controller rather than duplicating setup controls. It owns the step index, copy, and navigation buttons; the existing setup delegate remains responsible for destination selection, health checks, save validation, and backup launch. A small snapshot method exposes the current step and readiness state for tests and accessibility. The normal setup window remains one reusable AppKit window and keeps the current activation/Space behavior.

## Error handling and accessibility

- The user can go back without losing unsaved changes.
- Closing the onboarding leaves the saved configuration unchanged.
- A failed check keeps the user on the readiness step and provides Retry plus Advanced setup.
- A missing dependency, inaccessible Drive, unavailable NAS, unsupported external disk, and unsafe encryption state each retain their existing localized safe explanation.
- Every step has a native heading, static explanatory text, one primary action, and an explicit secondary action with VoiceOver labels.
- Automatic checks never activate the app over another full-screen app; only an explicit visible user action requests foreground progress.

## Testing strategy

Add focused tests before implementation:

1. A first-run profile without `GDRIVE_BACKUP_ONBOARDING_VERSION` opens the onboarding path, while an existing completed profile opens the normal setup/overview.
2. Step navigation preserves unsaved values, and closing before save leaves the persisted configuration unchanged.
3. Readiness success enables confirmation; readiness failure exposes a safe retry state and does not start a backup.
4. The automatic primary destination and optional manual external destination remain distinct through staging, save, reopen, and backup launch.
5. Save writes version `1` only after the explicit confirmation and preserves target, schedule, notifications, pause, and encryption values.
6. The onboarding view exposes native accessibility roles and localized labels for all three steps and both destination roles.
7. Existing setup, profile, mount-trigger, notification, and launch-agent regression tests remain green.

## Release constraints

The first implementation should be shipped as a minor product improvement without changing the backup protocol or launchd contract. Release notes must state that the new onboarding is a presentation layer over the existing safety checks and that advanced setup remains available.
