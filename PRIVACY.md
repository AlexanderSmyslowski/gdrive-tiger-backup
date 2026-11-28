# Privacy

GDrive Tiger Backup copies your Google Drive to a disk or network share you
choose. It runs entirely on your own computer. There is no server of this
project, no account with us, no analytics and no telemetry.

## What it accesses

- **Google Drive, read-only.** You sign in with a Google client in your own
  Google Cloud project. The backup asks only for the read-only Drive scope
  (`drive.readonly`) and never changes, moves or deletes anything in your
  Drive.
- **Your backup destination.** Files are written only to the disk or network
  share you configured.

## What it stores, and where

Everything stays on your computer:

- the rclone configuration with the Google sign-in token
  (`~/.config/rclone/rclone.conf`),
- a private copy of your Google client file (macOS:
  `~/Library/Application Support/GDrive Backup Tiger/`, Linux:
  `~/.config/gdrive-tiger-backup/`),
- settings, logs, status and a run history (macOS: `~/Library/Logs` and
  `~/Library/Application Support/GDrive Backup Tiger/`, Linux:
  `~/.local/state/gdrive-tiger-backup/`),
- the backup itself on your destination.

Removing the program leaves these in place; delete them yourself if you want
them gone. You can revoke the backup's access to Google Drive at any time under
<https://myaccount.google.com/connections>.

## What leaves your computer

- Requests to Google's Drive API, made by rclone with your own Google client,
  to read your files.
- On macOS, a daily check of this project's GitHub releases for updates.
  GitHub sees an ordinary download request; the app sends no identifier.
- A support report only when you explicitly copy or save it. It leaves out
  paths, credentials, file names and log contents.

Nothing else is sent anywhere.

## Contact

Questions or concerns: open an issue at
<https://github.com/AlexanderSmyslowski/gdrive-tiger-backup/issues>, or see
[SECURITY.md](SECURITY.md) for anything security related.
