# Security policy

GDrive Backup Tiger handles access to your Google Drive and writes to your
disks and NAS, so security reports are taken seriously.

## Reporting a vulnerability

Please report security problems **privately** through
[GitHub's private vulnerability reporting](https://github.com/AlexanderSmyslowski/gdrive-tiger-backup/security/advisories/new),
not as a public issue. Include the app version, macOS version, and steps to
reproduce. Do not include real credentials or personal data.

You can expect a first answer within a few days. Fixes are released through
the in-app updater, and the advisory is published once a fixed version is
available.

## Supported versions

Only the latest release receives security fixes. The app checks for updates
daily and can install them from the menu bar.

## What the app does and does not do

- Google Drive access is read-only (`drive.readonly`); the app never changes or
  deletes files in Google Drive.
- Credentials stay in rclone's configuration and the macOS Keychain; the app
  does not send data anywhere except to Google (through rclone) and to GitHub
  (update checks).
- Updates are installed only after the package matches the SHA-256 checksum
  published with the same GitHub release, and only through the macOS
  administrator prompt.
