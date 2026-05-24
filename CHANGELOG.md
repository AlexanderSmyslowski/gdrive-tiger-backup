# Changelog

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
