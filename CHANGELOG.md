# Changelog

## Unreleased

## v2.0.0 - 2026-07-12

- Add native create, rename, switch, and delete controls for named backup profiles in setup.
- Copy the existing configuration into a private default profile without modifying the legacy source file.
- Keep each profile’s destination, schedule, encryption policy, remote, and last-run summary separate while identifying the active profile in the overview and menu bar.
- Block profile switches when setup has unsaved edits unless the user explicitly discards them, and roll back activation if launchd cannot apply the new schedule.
- Resolve profiles through path-safe generated IDs, reject traversal and symbolic links for the config directory, config files, and active-pointer file, and keep files owner-only.
- Let the backup engine source exactly the active trusted profile while preserving explicit config overrides and the legacy fallback.

## v1.9.0 - 2026-07-12

- Add one native diagnostics window to the application menu and menu bar for tools, Google Drive, destination, schedule, services, backup engine, and the last run.
- Run diagnostics asynchronously with explicit ready, failed, blocked, unknown, and refreshing states in all seven supported languages.
- Generate a stable allowlist-only support report without paths, URLs, credentials, remote names, file names, provider output, or log contents.
- Copy or save the report only after an explicit user action; never send it automatically and save it with owner-only permissions.
- Keep the diagnostics window at the normal macOS window level so other applications can cover it, and leave the menu bar controller running when it closes.

## v1.8.0 - 2026-07-12

- Add a native restore browser reachable from both the overview and menu bar.
- Merge the live backup with sparse retained version trees so deleted or replaced files remain discoverable without presenting them as full snapshots.
- List the current copy and every actually available older copy newest-first, with localized dates and sizes.
- Restore only to a user-selected folder outside the backup tree, preserve existing files with a new name, and never overwrite silently.
- Verify the source before and after copying and compare the restored file with SHA-256 before publishing it under its final name.
- Reject traversal, symbolic links, sources outside the configured backup, retired quarantine data, and destinations inside the independent backup.
- Provide native keyboard and VoiceOver navigation, explicit loading and empty states, and a Finder reveal action after verified recovery.

## v1.7.0 - 2026-07-11

- Add an in-app system check for required tools, the configured Google Drive remote, and the exact local or NAS destination.
- Keep setup checks asynchronous, accessible, localized, and free of command output or credentials.
- Detect a NAS share that disappears during copying, stop later copy phases, and show a specific reconnect-and-retry explanation.
- Expand and reflow the setup window so the system check, destination controls, schedule, and actions never overlap.
- Preserve the manual-start contract: a launched backup closes setup exactly once, while a process launch failure stays explicitly retryable.

## v1.6.1 - 2026-07-11

- Show the real progress window as soon as a manual run owns the backup lock, before slow remote and destination checks.
- Close the setup window after a successful launch, block duplicate clicks there, and keep it open when the process cannot be launched.
- Treat transiently missing or partial run-state reads as pending while the verified owner process is alive, preventing premature failure screens.
- Serialize NAS writes and disable multi-threaded destination streams for compatibility with SMB servers that reject concurrent file and directory creation.
- Classify destination permission failures without persisting private paths and show a specific localized permissions explanation.
- Open setup only on a first package installation; upgrades keep the single refreshed menu bar controller instead of launching a duplicate overview process.

## v1.6.0 - 2026-07-11

- Add a persistent overview and menu bar controller showing the last verified run, next configured schedule, exact destination, and destination capacity.
- Replace the broad launchd `StartOnMount` job with exact-volume mount handling in the menu bar controller, including duplicate-event debouncing.
- Stop `Backup now` and `Check backup` from silently saving edited setup values; unsaved changes now block the action with a localized explanation.
- Show the full resolved external-disk or NAS destination in setup and preserve it for VoiceOver and pointer users even when visually truncated.
- Persist a private, atomic last-run summary with explicit running, success, failure, and cancellation state for the overview.
- Use native close, minimize, buttons, text, progress, keyboard focus, VoiceOver announcements, and Reduce Motion behavior while retaining the Tiger visual signature.

- Preserve overwritten destination files in timestamped `.gdrive-versions` trees by default, with an explicit opt-out.
- Thin successful version runs with a Time Machine-like hourly, daily, and weekly cadence; coalesce sparse per-file deltas before moving retired runs to recoverable Trash or retriable quarantine.
- Let ordinary progress windows fall behind other applications while keeping confirmation prompts visible.
- Add a fail-closed mode for already unlocked encrypted APFS destinations without storing volume passphrases.
- Make the NAS mount-trigger opt-in effective and return a failure status when manual or scheduled backups have no available target.
- Add hermetic backup-control, rclone command, NAS parsing, config roundtrip, release metadata, and package payload tests.
- Split configuration and localization responsibilities out of the AppKit entry point.
- Harden config roundtrips for Unicode and shell quoting, preserve unreadable files, and enforce owner-only permissions.
- Surface schedule serialization and launchctl failures instead of reporting a false successful save.
- Add macOS GitHub Actions for tests, app linking, package construction, payload verification, and unsigned artifact upload.
- Add optional Developer ID application/installer signing and Apple notarization support without storing credentials in the repository.
- Build and verify Universal 2 app binaries with an explicit macOS 13 deployment target.
- Clarify that the Tiger name describes the visual style and that the app requires macOS 13 or later.

## v1.5.0 - 2026-05-24

- Add a reproducible macOS `.pkg` build for GitHub releases.
- Install the app into `/Applications`, the backup script into `/usr/local/bin`, and the mount LaunchAgent for the currently logged-in user.
- Open the setup UI after package installation so users can choose language, external disk, NAS, and schedule settings.
- Add release-download instructions and maintainer packaging docs.

## v1.4.0 - 2026-05-24

- Make the setup app a normal macOS app with its own menu bar.
- Add About and Settings menu items.
- Add in-app language switching.
- Complete setup UI translations for Deutsch, English, Français, Español, 日本語, 粵語, and 한국어.

## v1.3.1 - 2026-05-24

- Add explicit modern bundle icon metadata so Finder and LaunchServices reliably show the app icon in `/Applications`.

## v1.3.0 - 2026-05-24

- Install the helper app into the global `/Applications` folder by default.
- Keep external-disk mount backups active even when NAS backups are configured.
- Treat the setup UI target as the app/scheduled backup target, so external disks and NAS can be used in parallel.

## v1.2.2 - 2026-05-24

- Rename the setup UI `Dry Run` action to `Backup prüfen` / `Check backup`.
- Clarify that the check is optional and does not copy files.

## v1.2.1 - 2026-05-24

- Detect SMB, AFP, and NFS mounts directly from macOS `mount` output so already mounted NAS shares appear reliably in the setup UI.
- Auto-select a matching mounted NAS share after Finder mounts it.
- Avoid guessing a bogus mount path from server-only URLs such as `smb://nas.local`.

## v1.2.0 - 2026-05-24

- Add a Tiger-style setup window for external disk and NAS backup targets.
- Let users select already mounted NAS shares from `/Volumes`.
- Add best-effort Bonjour discovery for SMB and AFP services.
- Add setup UI actions for saving config, opening NAS URLs in Finder, dry-runs, and starting a backup now.
- Add optional NAS schedules: manual, login, hourly, or daily at 20:00.
- Prevent NAS configs from running on every unrelated `StartOnMount` event by default.

## v1.1.1 - 2026-05-24

- Make the backup script robust when launchd starts it without an explicit `HOME` environment variable.

## v1.1.0 - 2026-05-24

- Add NAS destination support with `GDRIVE_BACKUP_TARGET=nas`.
- Support mounted SMB, AFP, or NFS shares under `/Volumes`.
- Add optional `GDRIVE_BACKUP_NAS_URL` so macOS can mount a share through Finder/Keychain.
- Keep NAS credentials out of the project config.
- Fix language detection on the system Bash version shipped with macOS.

## v1.0.0 - 2026-05-24

- Initial open-source release.
- Back up My Drive, Shared Drives, and Shared with me through read-only `rclone copy`.
- Export Google Docs, Sheets, and Slides as Office files.
- Add launchd `StartOnMount`, lockfile protection, logs, dry-run mode, and Tiger-style progress helper.
