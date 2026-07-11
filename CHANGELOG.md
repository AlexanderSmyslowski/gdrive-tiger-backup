# Changelog

## Unreleased

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
