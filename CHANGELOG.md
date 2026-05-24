# Changelog

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
