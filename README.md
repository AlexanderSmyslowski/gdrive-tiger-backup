# gdrive-tiger-backup

macOS launchd backup setup for Google Drive, powered by `rclone`, with a tiny Mac OS X Tiger-inspired status window.

It backs up:

- My Drive
- all Shared Drives
- Shared with me
- Google Docs, Sheets, and Slides exported as `docx`, `xlsx`, and `pptx`

The backup is read-only from Google Drive's perspective. It uses `rclone copy`, so it does not delete, mutate, or reorganize anything in Drive.

## How It Works

- A user LaunchAgent starts on every volume mount via `StartOnMount`.
- The shell script checks whether the configured backup volume exists.
- A `flock` lock prevents two backup jobs from running at the same time.
- Before a real backup starts, the Tiger helper asks whether this volume should be used.
- The native AppKit helper appears while the backup runs.
- The yellow Tiger-style button minimizes the helper into the Dock.
- Clicking the Dock icon restores the helper.
- When the backup finishes, the helper pops back up even if it was minimized.

## Requirements

- macOS with Command Line Tools
- Homebrew
- `rclone`
- `flock`
- `jq`

Install dependencies:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew install rclone flock jq
```

## Configure rclone

Create a Google Drive remote named `gdrive`:

```bash
rclone config
```

Recommended OAuth scope: `drive.readonly`.

Run a quick check:

```bash
rclone lsd gdrive:
```

## Install

Pick or create a writable backup volume, for example:

```bash
BACKUP_VOLUME="/Volumes/GoogleDrive-Backup" ./install.sh
```

To install Homebrew dependencies as part of the installer:

```bash
INSTALL_DEPS=1 BACKUP_VOLUME="/Volumes/GoogleDrive-Backup" ./install.sh
```

The installer writes:

- `/usr/local/bin/backup-google-drive.sh`
- `~/Applications/GDrive Backup Tiger.app`
- `~/Library/LaunchAgents/com.commcats.gdrivebackup.plist`
- `~/.config/gdrive-tiger-backup/config`

The default config keeps confirmation enabled:

```bash
GDRIVE_BACKUP_CONFIRM=1
```

Set `GDRIVE_BACKUP_CONFIRM=0` only if you deliberately want fully automatic backups whenever the configured volume is mounted.

## Test First

Always run a dry-run before the first real backup:

```bash
/usr/local/bin/backup-google-drive.sh --dry-run
```

Run manually:

```bash
/usr/local/bin/backup-google-drive.sh --run
```

Watch logs:

```bash
tail -f ~/Library/Logs/gdrive-backup.log
```

## launchd

Load or reload the LaunchAgent:

```bash
launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.commcats.gdrivebackup.plist" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.commcats.gdrivebackup.plist"
launchctl enable "gui/$(id -u)/com.commcats.gdrivebackup"
```

Check status:

```bash
launchctl print "gui/$(id -u)/com.commcats.gdrivebackup"
```

## Notes

Time Machine backup volumes can be protected by macOS ACLs. If the root of your Time Machine disk is not writable, create a separate APFS volume such as `/Volumes/GoogleDrive-Backup` in the same APFS container and use that as `BACKUP_VOLUME`.

## License

MIT
