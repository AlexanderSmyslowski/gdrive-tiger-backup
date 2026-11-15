# Native scheduled backup migration and rollback

This is an operator procedure for a reviewed candidate, not installation approval.
A staged build or passing fixture tests do not establish unattended NAS access.
The worker changes only the parent of daily/hourly/login runs. The menu-bar
controller continues to own mount handling, notifications and its existing
30-minute retry. Do not run the staged candidate against the installed engine.

## Before an authorized installation window

1. Obtain independent acceptance of the exact candidate source/artifact hashes,
   the universal build and tests. Record the installed app version/build and
   signature identity, exact destination identity, active profile, configured
   schedule mode/timing and pause state without exporting secrets or raw logs.
2. Wait for every current backup/retry to reach a terminal state. Confirm the
   engine PID/process group and lock are inactive. Do not terminate an active
   copy, infer inactivity from a disappearing window, or force/remove a lock.
   If a retry becomes eligible during preparation, stop and reassess the window.
3. Make protected, recoverable copies of the installed app, engine, schedule
   plist and controller plist. Preserve ownership/modes, original hashes and
   the actual prior loaded/enabled state of both launchd jobs. Preserve the
   active-profile pointer, saved profile/config files and pause setting in the
   protected rollback location; never paste their contents into chat or Git.
   Do not export Keychain material or alter TCC databases.
4. Inspect the exact schedule plist and launchd manager environment for one-shot
   target/UUID/creation approvals. The worker rejects their presence; resolve any
   unexpected entries through a separately reviewed operator decision. Do not
   use an override to make a failing backup appear successful.

## Scoped installation and schedule replacement

1. With production approval and rollback copies verified, quiesce the existing
   schedule and controller jobs using their recorded identities. Confirm no
   engine is running before replacing the app. Do not run the general source
   installer/package postinstall as a shortcut: it has broader side effects.
2. Replace only the reviewed installed app at `/Applications/GDrive Backup
   Tiger.app`, preserving expected installation ownership/modes. Keep the
   installed engine unchanged unless a separate approved change requires it.
   Verify the installed files against the accepted build and validate its
   signature. A new ad-hoc code identity may need renewed scoped native consent.
3. If there was an automatic schedule, edit a protected copy of its plist:
   set `ProgramArguments` to the installed app's
   `Contents/MacOS/GDriveBackupTiger` followed only by
   `--run-scheduled-backup`; set `AssociatedBundleIdentifiers` to
   `[com.commcats.gdrivebackup.tiger]`. Preserve all original timing keys,
   schedule mode and relevant job properties. Validate with `plutil -lint`,
   install that exact plist and verify its owner/mode and resulting arguments.
   If scheduling was manual/disabled, do not create or enable a schedule.
4. Restore the controller's exact previous `--menubar` definition and its prior
   enabled/loaded state; do not create a second controller. Restore the schedule
   only to its previous enabled/loaded state. Loading a login schedule can run
   immediately: count that as the single authorized validation run below.
   Recheck that the active profile, saved destination and pause state match the
   recorded originals. Preserve pause; a paused job must remain skipped.

## Installed validation and acceptance

Use only the installed native identity and an explicitly authorized launchd run.
If macOS requires consent, use the existing scoped native authorization flow and
repeat its no-UI check; never reset permissions or broaden grants to shell tools.
Do not start another run if one is active, already triggered at job load, or
pending through the existing retry controller. If paused, report the skipped
result and obtain a separate decision before any copy verification.

For the intended NAS profile, verify native worker -> fixed Bash engine ancestry,
engine PID == process-group ID, unchanged destination identity, verified mount,
manifest/content checks and truthful terminal state. Acceptance of unattended
recovery requires a successful actual NAS run and the next natural scheduled
execution under the installed identity. A successful APFS run, an accessible
manifest in a different process context, or a fixture success is insufficient.
Record outcomes without customer filenames, credentials or raw private logs.

## Rollback

If installation, consent, launch or destination validation fails, keep the
candidate unaccepted. Stop scheduling additional attempts and wait for any
in-flight engine to finish or use its normal validated cancellation, then verify
the terminal state and inactive lock. Quiesce only the recorded schedule and
controller. Restore the protected original app and schedule/controller plists
with their original metadata and verify their hashes. Restore original
loaded/enabled states, schedule timing, active profile and pause state; retain
manual/disabled scheduling where it existed. Restore config only if this window
actually changed it, preserving unrelated legitimate changes.

Keep the failed candidate and evidence recoverable. Use Trash for any cleanup.
Do not remove backup data, versions, lock artifacts, credentials or permission
grants as rollback cleanup. If the older schedule had the original NAS failure,
report that limitation explicitly: restoring old files does not prove recovery.
