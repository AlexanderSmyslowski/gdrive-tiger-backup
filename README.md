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
- On first use, if the backup volume does not exist yet, the helper can ask to create a dedicated APFS volume on the newly attached external APFS disk.
- A `flock` lock prevents two backup jobs from running at the same time.
- Before a real backup starts, the Tiger helper asks whether this volume should be used.
- The native AppKit helper appears while the backup runs.
- During each `rclone copy`, the helper shows live progress, percent, transferred size, speed, and ETA when rclone reports it.
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

On first install, the installer asks which language the helper should use:

- Deutsch
- English
- Français
- Español
- 日本語
- 粵語
- 한국어

For unattended installs, set it explicitly:

```bash
GDRIVE_BACKUP_LANG=en BACKUP_VOLUME="/Volumes/GoogleDrive-Backup" ./install.sh
```

You can also install first and let the helper create a dedicated APFS volume the first time an external APFS disk is attached. The app will ask before it does anything. This is non-destructive: it uses `diskutil apfs addVolume` to add a sibling APFS volume in the same APFS container. It does not erase or repartition the disk.

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
GDRIVE_BACKUP_LANG=en
GDRIVE_BACKUP_CONFIRM=1
GDRIVE_BACKUP_AUTO_CREATE_VOLUME=1
```

Supported values for `GDRIVE_BACKUP_LANG` are `de`, `en`, `fr`, `es`, `ja`, `yue`, and `ko`.
Set `GDRIVE_BACKUP_CONFIRM=0` only if you deliberately want fully automatic backups whenever the configured volume is mounted.
Set `GDRIVE_BACKUP_AUTO_CREATE_VOLUME=0` if you want to create the backup volume yourself.

## Test First

Always run a dry-run before the first real backup:

```bash
/usr/local/bin/backup-google-drive.sh --dry-run
```

Run manually:

```bash
/usr/local/bin/backup-google-drive.sh --run
```

The progress bar reflects the currently active copy phase, for example `My Drive`, `Shared with me`, or one Shared Drive. It also shows the phase count, such as `3/5`. A single global percentage across all Drive areas would require an expensive pre-scan of every source.

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

The built-in first-use setup does exactly that for APFS disks after confirmation. For non-APFS disks, create or format a suitable APFS volume yourself first.

## License

MIT
