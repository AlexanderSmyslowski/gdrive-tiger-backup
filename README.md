# gdrive-tiger-backup

[![CI](https://github.com/AlexanderSmyslowski/gdrive-tiger-backup/actions/workflows/ci.yml/badge.svg)](https://github.com/AlexanderSmyslowski/gdrive-tiger-backup/actions/workflows/ci.yml)

macOS launchd backup setup for Google Drive, powered by `rclone`, with a tiny Mac OS X Tiger-inspired status window. “Tiger” describes the visual style; the app requires macOS 13 Ventura or later and does not run on Mac OS X 10.4 Tiger.

Current release: `v1.8.0` with a downloadable macOS installer package, verified file recovery, a guided system check, a persistent backup overview, a menu bar status, settings, and language selection.

It backs up:

- My Drive
- all Shared Drives
- Shared with me
- Google Docs, Sheets, and Slides exported as `docx`, `xlsx`, and `pptx`

The backup is read-only from Google Drive's perspective. It uses `rclone copy`, so it does not delete, mutate, or reorganize anything in Drive.

## How It Works

- A user LaunchAgent starts the lightweight menu bar controller at login.
- The controller observes macOS mount events and reacts only when the exact saved APFS backup volume was newly mounted. Unrelated disks and NAS mounts are ignored.
- The overview shows the last verified run, configured schedule, exact local destination, and available destination capacity.
- On first use, if the backup volume does not exist yet, the helper can ask to create a dedicated APFS volume on the newly attached external APFS disk.
- In parallel, the setup window can configure a mounted NAS share, for example SMB, AFP, or NFS under `/Volumes`.
- The setup window can select already mounted NAS shares, run a small Bonjour search, show the exact resolved destination, save a schedule, and start a backup manually. Its system check verifies the required tools, Google Drive access, and destination before a run. Backup actions never save edited form values implicitly.
- A `flock` lock prevents two backup jobs from running at the same time.
- Before a real backup starts, the Tiger helper asks whether this volume or NAS destination should be used.
- External disks and NAS targets are independent: plugging in the configured external disk still opens the confirmation dialog even when NAS backups are configured.
- The native AppKit helper appears while the backup runs, but uses the normal
  window level so other apps can cover it.
- During each `rclone copy`, the helper shows live progress, percent, transferred size, speed, and ETA when rclone reports it.
- Native close and minimize controls behave like standard macOS controls; closing the overview leaves its menu bar status available.
- The overview and menu bar open a native restore browser that combines the live backup with every actually available retained per-file version.
- A restored file is copied to a user-selected folder outside the backup, never silently overwrites an existing file, and is published only after its SHA-256 digest matches the selected backup copy.
- When the backup finishes, the helper briefly shows completion without taking
  focus from the app currently in use.

## Requirements

- macOS 13 Ventura or later
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

### Install from GitHub release

For most users, download the latest installer from the GitHub releases page:

1. Open <https://github.com/AlexanderSmyslowski/gdrive-tiger-backup/releases/latest>
2. Download `GDrive-Backup-Tiger-1.8.0.pkg` from `Assets`.
3. Double-click the package and follow the macOS Installer.
4. Open `/Applications/GDrive Backup Tiger.app` to choose language, external disk, NAS, and schedule settings.

The package installs:

- `/Applications/GDrive Backup Tiger.app`
- `/usr/local/bin/backup-google-drive.sh`
- `~/Library/LaunchAgents/com.commcats.gdrivebackup.plist` for the currently logged-in user

The package is currently unsigned because the project does not yet have an Apple Developer ID Installer certificate. If macOS says it cannot verify the package:

1. Click `Done`, not `Move to Trash`.
2. Open `System Settings > Privacy & Security`.
3. Scroll to `Security` and click `Open Anyway` for `GDrive-Backup-Tiger-1.8.0.pkg`.
4. Confirm with `Open Anyway`, then install the package.

Advanced users can also remove the download quarantine flag before opening:

```bash
xattr -d com.apple.quarantine "$HOME/Downloads/GDrive-Backup-Tiger-1.8.0.pkg"
```

### Install from source

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

### Install for a NAS

Mount the NAS share once in Finder and save the credentials in Keychain. Then install with a NAS target:

```bash
BACKUP_TARGET=nas \
NAS_MOUNT="/Volumes/Backups" \
NAS_SUBDIR="GoogleDrive-Backup" \
./install.sh
```

You can also let the script ask macOS to mount the share when it is not already mounted:

```bash
BACKUP_TARGET=nas \
NAS_URL="smb://nas.local/Backups" \
NAS_MOUNT="/Volumes/Backups" \
NAS_SUBDIR="GoogleDrive-Backup" \
./install.sh
```

The tool does not ask for or store NAS usernames or passwords; use Finder or Keychain for credentials and do not embed them in `NAS_URL`. The config file is kept at owner-only mode `0600` because mount URLs and paths may still be private.

After installation, open the setup UI from `/Applications/GDrive Backup Tiger.app` or run:

```bash
/usr/local/bin/backup-google-drive.sh --setup
```

The setup window can:

- choose the target for app-started and scheduled backups
- select an already mounted NAS volume from `/Volumes`
- run a best-effort Bonjour search for SMB and AFP services
- open a NAS URL in Finder so macOS can mount it through Keychain
- save manual, login, hourly, or daily launchd start modes
- start a backup immediately or run an optional no-copy check

The installer writes:

- `/usr/local/bin/backup-google-drive.sh`
- `/Applications/GDrive Backup Tiger.app`
- `~/Library/LaunchAgents/com.commcats.gdrivebackup.plist`
- `~/.config/gdrive-tiger-backup/config`

The default config keeps confirmation enabled:

```bash
GDRIVE_BACKUP_TARGET=apfs
GDRIVE_BACKUP_LANG=en
GDRIVE_BACKUP_CONFIRM=1
GDRIVE_BACKUP_AUTO_CREATE_VOLUME=1
GDRIVE_BACKUP_VERSIONING=1
GDRIVE_BACKUP_VERSIONS_SUBDIR=.gdrive-versions
GDRIVE_BACKUP_RETENTION=1
GDRIVE_BACKUP_ENCRYPTION=none
```

For NAS backups, the config looks like this:

```bash
GDRIVE_BACKUP_TARGET=nas
GDRIVE_BACKUP_NAS_MOUNT=/Volumes/Backups
GDRIVE_BACKUP_NAS_URL=smb://nas.local/Backups
GDRIVE_BACKUP_NAS_SUBDIR=GoogleDrive-Backup
GDRIVE_BACKUP_SCHEDULE=manual
```

Supported values for `GDRIVE_BACKUP_LANG` are `de`, `en`, `fr`, `es`, `ja`, `yue`, and `ko`.
Supported values for `GDRIVE_BACKUP_TARGET` are `apfs` and `nas`.
Supported values for `GDRIVE_BACKUP_SCHEDULE` are `manual`, `login`, `hourly`, and `daily`.
Set `GDRIVE_BACKUP_CONFIRM=0` only if you deliberately want fully automatic backups whenever the configured volume is mounted.
Set `GDRIVE_BACKUP_AUTO_CREATE_VOLUME=0` if you want to create the backup volume yourself.
Set `GDRIVE_BACKUP_NAS_START_ON_MOUNT=1` only if mount events should also start the configured NAS backup; the default `0` reserves mount-triggered runs for the external APFS target.
Set `GDRIVE_BACKUP_VERSIONING=0` only if overwritten destination files should not be preserved. Versioning is enabled by default and moves the previous content into `.gdrive-versions/<timestamp>/<backup area>` through rclone's `--backup-dir` support.
`GDRIVE_BACKUP_VERSIONS_SUBDIR` must remain a safe relative path outside `My Drive`, `Shared with me`, and `Shared Drives`.

## Version retention

Version retention is enabled by default and follows a Time Machine-like cadence:

- keep every version run from the last 24 hours
- from 24 hours through 30 days, keep the newest run for each calendar day
- from 30 days through 52 weeks, keep the newest run for each ISO week
- retire versions older than 52 weeks

Thinning runs only after every copy phase has completed successfully. A dry run
only logs candidates. Retired folders are moved to the macOS Trash when that is
available. On macOS 13 and 14, the packaged app provides the same recoverable
Foundation Trash operation because `/usr/bin/trash` is not present there. If no
Trash method is available, candidates remain recoverable in
`.gdrive-versions/.retention-trash` and are retried on later successful runs.
Unknown or malformed version folder names are always kept. Set
`GDRIVE_BACKUP_RETENTION=0` to disable automatic thinning.

These version directories contain the older copies of files that were replaced
in that run. Before a redundant daily or weekly run is retired, its newest
per-file versions are merged into that bucket's retained run without
overwriting newer entries. The trees remain space-efficient deltas, not complete
point-in-time snapshots like Time Machine. Restoring a file means selecting its
newest suitable copy from the live backup or the retained version trees.

## Restore files

Open **Restore files** from the overview or the menu bar. Browse the backup
areas, select a file, and then select one of the copies that actually exists.
The current backup appears first; retained older copies follow newest-first.
Because the retained trees are sparse deltas, the browser does not claim that
every timestamp is a complete point-in-time snapshot.

Choose a destination folder outside the backup tree. If a file with the same
name already exists, the app creates a new `restored` name instead of
overwriting it. The selected source is hashed before and after copying, the
temporary restored copy is hashed again, and the file receives its final name
only when all SHA-256 values match. Symbolic links, traversal paths, quarantine
data, outside sources, and restore destinations inside the backup are rejected.

## Encryption

Set `GDRIVE_BACKUP_ENCRYPTION=apfs` to require an already unlocked, encrypted
APFS destination. The backup fails closed before rclone writes anything if the
volume is missing, non-APFS, or not encrypted. The app never reads or stores the
volume passphrase and will not auto-create an unencrypted volume in this mode.
The same setting is available in the setup window as **Require encrypted APFS
(already unlocked)** and is disabled for NAS targets.

For setup steps, encrypted disk images on a NAS, and the separate `rclone crypt`
design considerations, see [`docs/encryption.md`](docs/encryption.md).

The app includes setup UI translations for Deutsch, English, Français, Español, 日本語, 粵語, and 한국어. Open `/Applications/GDrive Backup Tiger.app`, then use `GDrive Backup Tiger > Settings` to change the language.

## Optional Safety Check

You can run an optional check before the first real backup. In the setup UI this is called `Check backup` / `Backup prüfen`; it does not copy files.

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

Thunderbolt, USB, SD-card, and other directly attached disks appear as mounted volumes to macOS. The menu bar controller compares each mount notification with the exact saved APFS destination before offering a backup, so unrelated media cannot trigger repeated prompts. NAS and Ethernet storage usually appear as network volumes under `/Volumes`; because they may stay mounted for a long time, NAS backups use manual or scheduled starts. These modes can be used together: the saved external disk remains mount-aware, while NAS backups run from the app or schedule.

## rclone Community

This project is intended as a small companion helper for rclone, not as a replacement. A ready-to-submit rclone Wiki entry and forum post are in [`docs/rclone-community-submission.md`](docs/rclone-community-submission.md).

## Maintainer Packaging

Run the complete local test suite:

```bash
make test
```

Build a local installer package:

```bash
make pkg
```

The package is written to `dist/GDrive-Backup-Tiger-<version>.pkg`.

Verify its payload, permissions, metadata, and ad-hoc app signature:

```bash
./packaging/verify-pkg.sh --expect-unsigned dist/GDrive-Backup-Tiger-*.pkg
```

Developer ID signing and Apple notarization are supported through environment
variables without storing credentials in the repository. See
[`docs/signing-and-release.md`](docs/signing-and-release.md) for the secure
release checklist.

## License

MIT
