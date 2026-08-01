# gdrive-tiger-backup

[![CI](https://github.com/AlexanderSmyslowski/gdrive-tiger-backup/actions/workflows/ci.yml/badge.svg)](https://github.com/AlexanderSmyslowski/gdrive-tiger-backup/actions/workflows/ci.yml)

macOS launchd backup setup for Google Drive, powered by `rclone`, with a tiny Mac OS X Tiger-inspired status window. “Tiger” describes the visual style; the app requires macOS 13 Ventura or later and does not run on Mac OS X 10.4 Tiger.

Current release: `v2.4.3` with silent automatic SMB mounting, one current persistent automatic-failure alert, a safe retry for transient NAS read failures, passive handling of unknown external disks, verified APFS and NAS identity, one coherent Dock presence, optional end-to-end `rclone crypt` backups, retained versions, verified recovery, named profiles, diagnostics, and a persistent menu bar overview.

It backs up:

- My Drive
- all Shared Drives
- Shared with me
- Google Docs, Sheets, and Slides exported as `docx`, `xlsx`, and `pptx`

The backup is read-only from Google Drive's perspective. It uses `rclone copy`, so it does not delete, mutate, or reorganize anything in Drive.

Google Docs, Sheets, and Slides are recoverable Office exports of their state at
backup time. Retained app versions can keep older exports from later runs, but
the backup does not preserve Google Drive's native document revision history.

## How It Works

- A user LaunchAgent starts the lightweight menu bar controller at login.
- Automatic schedule and mount-triggered runs can be paused from the menu bar without changing the saved schedule; manual backups remain available.
- The controller observes macOS mount events. When an APFS volume UUID is saved, a changed `/Volumes/… 2` suffix is resolved automatically and a merely same-name disk cannot trigger a backup. Older path-only profiles remain available for manual and scheduled use, but a mount event is treated as unknown until a human explicitly binds the disk's UUID.
- A previously unknown directly attached physical disk produces at most one passive notification per attachment. Mounting it never opens a window, takes focus, formats or writes to the disk, or starts a backup. **Set up as backup destination** revalidates the same disk and only stages it in setup; **Save** registers the disk while leaving the currently selected primary target and schedule as shown, so a NAS target is never replaced silently. **Ignore** makes no change. A dismissal remains remembered if the controller restarts during the same attachment, while fully unplugging the disk clears the notice and makes a later attachment eligible again. UUIDs retained by any named profile suppress the unknown-disk notice for that whole physical disk.
- The overview shows the last verified run, configured schedule, exact local destination, and available destination capacity.
- With notifications enabled, macOS reports a failed automatic run immediately and a daily 20:00 run that is still missing at 21:00. A transient NAS mount/readiness or fail-closed destination-read failure gets exactly one controller-managed retry after 30 minutes; after sleep it remains eligible until the next wake within 24 hours. If that retry fails, its final alert replaces the preliminary “retry in 30 minutes” alert. The controller restarts after a crash, alerts are deduplicated per profile and run, and only a newer successful automatic backup removes the current delivered failure alert for that profile.
- Scheduled, mount-triggered, and menu-bar-only runs stay headless. Their live and final state remains available through the menu bar, with a macOS notification for automatic failures.
- Named profiles keep distinct destinations, schedules, encryption policies, and last-run histories while making the one active profile explicit in setup, the overview, and the menu bar.
- On first use, if the backup volume does not exist yet, the helper can ask to create a dedicated APFS volume on the newly attached external APFS disk.
- In parallel, the setup window can configure a mounted NAS share, for example SMB, AFP, or NFS under `/Volumes`. A writable directory alone never counts as a NAS: the setup check and backup engine both require a verified network file-system mount.
- After macOS mounts a configured NAS automatically, the engine waits up to 60 seconds for the verified share to become writable. This avoids treating the short interval between “mounted” and “ready for I/O” as a permanent failure.
- The setup window can select already mounted NAS shares, run a small Bonjour search, show the exact resolved destination, save a schedule, and start a backup manually. Its system check verifies the required tools, Google Drive access, and destination before a run. Backup actions never save edited form values implicitly.
- A `flock` lock prevents two backup jobs from running at the same time.
- Before a real mount-triggered backup starts, the Tiger helper asks whether this volume should be used. The question stays visible on its normal Space without activating the app or appearing over another application's fullscreen Space.
- External disks and NAS targets are independent: plugging in the configured external disk still opens the confirmation dialog even when NAS backups are configured.
- A direct manual start from the visible overview or setup can open the native
  AppKit helper. It stays on its original Space, never joins another app's
  fullscreen Space, and hides when another app becomes active.
- During each `rclone copy`, the helper shows live progress, percent, transferred size, speed, and ETA when rclone reports it.
- Native close and minimize controls behave like standard macOS controls; closing the overview leaves its menu bar status available.
- The overview and menu bar open a native restore browser that combines the live backup with every actually available retained per-file version.
- A restored file is copied to a user-selected folder outside the backup, never silently overwrites an existing file, and is published only after its SHA-256 digest matches the selected backup copy.
- Optional `rclone crypt` mode encrypts file contents plus file and directory names. Active data, version deltas, thinning, and restore all address the same checked crypt remote; the app stores only its name and never reads a crypt password.
- The app and menu bar open one native diagnostics window for tools, Google Drive, destination, schedule, services, and the last run. Its optional support report omits paths, credentials, file names, and log contents and is copied or saved only after an explicit click.
- When the backup finishes, an already active helper briefly shows completion.
  A hidden or inactive helper stays hidden and never takes focus back.

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
2. Download `GDrive-Backup-Tiger-2.4.3.pkg` from `Assets`.
3. Double-click the package and follow the macOS Installer.
4. Open `/Applications/GDrive Backup Tiger.app` to choose language, external disk, NAS, and schedule settings.

The complete source-version and publication chronology is recorded in
[`docs/version-history.md`](docs/version-history.md).

The package installs:

- `/Applications/GDrive Backup Tiger.app`
- `/usr/local/bin/backup-google-drive.sh`
- `~/Library/LaunchAgents/com.commcats.gdrivebackup.plist` for the currently logged-in user

The package is currently unsigned because the project does not yet have an Apple Developer ID Installer certificate. If macOS says it cannot verify the package:

1. Click `Done`, not `Move to Trash`.
2. Open `System Settings > Privacy & Security`.
3. Scroll to `Security` and click `Open Anyway` for `GDrive-Backup-Tiger-2.4.3.pkg`.
4. Confirm with `Open Anyway`, then install the package.

Advanced users can also remove the download quarantine flag before opening:

```bash
xattr -d com.apple.quarantine "$HOME/Downloads/GDrive-Backup-Tiger-2.4.3.pkg"
```

### Install from source

Pick or create a writable backup volume, for example:

```bash
BACKUP_VOLUME="/Volumes/GoogleDrive-Backup 2"
BACKUP_VOLUME_UUID="$(
  /usr/sbin/diskutil info -plist "$BACKUP_VOLUME" |
    /usr/bin/plutil -extract VolumeUUID raw -o - -
)"
GDRIVE_BACKUP_VOLUME_UUID="$BACKUP_VOLUME_UUID" \
  BACKUP_VOLUME="$BACKUP_VOLUME" \
  ./install.sh
```

Use the exact mounted path shown by Finder. The UUID is deliberately supplied
by the installer caller and verified against that mount. An upgrade updates the
legacy config and the active profile atomically per file; it never guesses an
identity from a same-name volume.

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

You can also install first and let the helper create a dedicated APFS volume the first time an external APFS disk is attached. The app will ask before it does anything. This is non-destructive: it uses `diskutil apfs addVolume` to add a sibling APFS volume in the same APFS container. It does not erase or repartition the disk. The helper compares the container's UUID set before and after creation, accepts exactly one new volume, resolves its actual mount point, and stops if the result is ambiguous.

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

You can also let the native helper mount the share silently when it is not already mounted. Include the SMB account, but never a password:

```bash
BACKUP_TARGET=nas \
NAS_URL="smb://backup-user@nas.local/Backups" \
NAS_MOUNT="/Volumes/Backups" \
NAS_SUBDIR="GoogleDrive-Backup" \
./install.sh
```

The account name is stored in `NAS_URL`; the password remains only in the macOS login Keychain and is never put in configuration, arguments, environment, or logs. After Finder has saved the SMB password, authorize the installed helper once:

```bash
"/Applications/GDrive Backup Tiger.app/Contents/MacOS/GDriveBackupTiger" \
  --authorize-network-url "smb://backup-user@nas.local/Backups"
```

Enter the login-Keychain password and choose **Always Allow**. The next no-UI check must succeed before the schedule is considered unattended. Because unsigned release builds have no stable Developer ID identity, macOS may require this one-time authorization again after an app update. Automatic runs themselves disable all Keychain and mount UI and fail safely instead of opening a dialog.

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
- enable or disable macOS failure and missed-daily-run notifications
- start a backup immediately or run an optional no-copy check

The installer writes:

- `/usr/local/bin/backup-google-drive.sh`
- `/Applications/GDrive Backup Tiger.app`
- `~/Library/LaunchAgents/com.commcats.gdrivebackup.plist`
- `~/.config/gdrive-tiger-backup/config`

The default config keeps confirmation enabled:

```bash
GDRIVE_BACKUP_TARGET=apfs
GDRIVE_BACKUP_VOLUME=/Volumes/GoogleDrive-Backup
GDRIVE_BACKUP_VOLUME_NAME=GoogleDrive-Backup
GDRIVE_BACKUP_VOLUME_UUID=11111111-2222-3333-4444-555555555555
GDRIVE_BACKUP_LANG=en
GDRIVE_BACKUP_CONFIRM=1
GDRIVE_BACKUP_AUTO_CREATE_VOLUME=1
GDRIVE_BACKUP_VERSIONING=1
GDRIVE_BACKUP_VERSIONS_SUBDIR=.gdrive-versions
GDRIVE_BACKUP_RETENTION=1
GDRIVE_BACKUP_ENCRYPTION=none
GDRIVE_BACKUP_PAUSED=0
GDRIVE_BACKUP_NOTIFY_FAILURES=1
```

For NAS backups, the config looks like this:

```bash
GDRIVE_BACKUP_TARGET=nas
GDRIVE_BACKUP_NAS_MOUNT=/Volumes/Backups
GDRIVE_BACKUP_NAS_URL=smb://backup-user@nas.local/Backups
GDRIVE_BACKUP_NAS_SUBDIR=GoogleDrive-Backup
GDRIVE_BACKUP_SCHEDULE=manual
```

Supported values for `GDRIVE_BACKUP_LANG` are `de`, `en`, `fr`, `es`, `ja`, `yue`, and `ko`.
Supported values for `GDRIVE_BACKUP_TARGET` are `apfs` and `nas`.
Supported values for `GDRIVE_BACKUP_SCHEDULE` are `manual`, `login`, `hourly`, and `daily`.
`GDRIVE_BACKUP_VOLUME_UUID` is the APFS volume UUID recorded for the external target. When it is present, it is authoritative: the engine asks `diskutil` for the volume's current mount point and never falls back to a same-name path. The UUID and device identity are revalidated after confirmation, before and after every copy, and before retention changes. Destination overrides, child trees, and version trees must stay on that volume and cannot cross `..`, symbolic links, or nested file systems.

Legacy profiles without the key retain exact-path behavior. Merely opening setup or changing an unrelated setting never guesses an identity from whichever same-name volume currently occupies that path. A safely auto-created volume stores its UUID automatically; an existing target should be migrated only after its exact APFS volume UUID has been verified.
Saved schedules run unattended after the script verifies the configured destination. `GDRIVE_BACKUP_CONFIRM=1` still protects mount-triggered runs with a prompt. Set it to `0` only if you also deliberately want those mount-triggered backups to start unattended whenever the configured volume is mounted.
Set `GDRIVE_BACKUP_PAUSED=1` to silence schedule and mount-triggered runs without changing the saved schedule. The menu bar toggles this setting; **Backup now** always remains manual and available.
Set `GDRIVE_BACKUP_NOTIFY_FAILURES=0` to disable macOS alerts for automatic failures and missed daily runs. The menu bar and overview continue to show backup status even when alerts are disabled or macOS notification permission is denied.
To keep a failure visible until a person dismisses it or a later automatic backup succeeds, set the macOS notification style for **GDrive Backup Tiger** to **Persistent** (`System Settings` → `Notifications` → `GDrive Backup Tiger`). macOS controls this presentation setting; the app never opens a modal window or takes foreground focus for an automatic failure. A manual success deliberately leaves the alert in place. The public unsigned package uses normal active notification delivery and therefore does not bypass Focus. A future properly provisioned signed build may elevate the same alert to time-sensitive delivery only when macOS confirms the required protected entitlement.
For NAS targets, `GDRIVE_BACKUP_NAS_MOUNT_TIMEOUT_SECONDS` bounds the macOS mount request (default `90`, range `1`–`300`) and `GDRIVE_BACKUP_NAS_READY_TIMEOUT_SECONDS` bounds the subsequent verified-writable readiness wait (default `60`, range `0`–`300`).
Set `GDRIVE_BACKUP_AUTO_CREATE_VOLUME=0` if you want to create the backup volume yourself.
Set `GDRIVE_BACKUP_NAS_START_ON_MOUNT=1` only if mount events should also start the configured NAS backup; the default `0` reserves mount-triggered runs for the external APFS target.
Set `GDRIVE_BACKUP_VERSIONING=0` only if overwritten destination files should not be preserved. Versioning is enabled by default and moves the previous content into `.gdrive-versions/<timestamp>/<backup area>` through rclone's `--backup-dir` support.
`GDRIVE_BACKUP_VERSIONS_SUBDIR` must remain a safe relative path outside `My Drive`, `Shared with me`, and `Shared Drives`.
Supported values for `GDRIVE_BACKUP_ENCRYPTION` are `none`, `apfs`, and
`rclone-crypt`. Crypt mode also requires a safe remote name in
`GDRIVE_BACKUP_CRYPT_REMOTE`; the remote must wrap the exact physical app
destination. It must not be the Google Drive source remote.

## Backup profiles

The setup window can create, rename, switch, and delete named profiles. Each
profile is a complete saved configuration for its destination, schedule,
encryption policy, and rclone remote. The overview and menu bar prefix the exact
destination with the active profile name, and every profile has a separate
last-run status so results cannot bleed between destinations.

Exactly one profile is active. Switching profiles updates the launchd schedule
but never starts a backup. Unsaved setup edits block a switch until the user
explicitly chooses to discard them; if the new schedule cannot be activated,
the app rolls back to the previous profile. Scheduled and app-started runs use
the active profile, so profiles do not create concurrent background jobs.

On the first v2 launch, the app copies the existing
`~/.config/gdrive-tiger-backup/config` into a private `Default` profile and
leaves the original file unchanged as a fallback. New profile IDs are generated
independently of their display names, profile files use mode `0600`, and unsafe
IDs or symbolic links are rejected. Deleting a profile moves only its config to
the macOS Trash; it does not delete any backup data.

## Incremental behavior

Every run lists and compares the source with the destination, but `rclone copy`
transfers only new or changed files. Unchanged files are checked but not copied
again. A changed file is transferred as a complete file, not as changed blocks,
and its previous complete version is retained under `.gdrive-versions` when
versioning is enabled.

Because the backup deliberately uses `copy` rather than `sync`, a file deleted
from Google Drive is not deleted from the backup destination. A rename or move
therefore creates the new path while the old path remains recoverable. This
protects against accidental source deletion but means the destination can grow
over time.

## NAS names and duplicate Drive entries

Some NAS servers reject a directory whose exact name is `.bin`. On verified NAS
destinations, the backup therefore applies a reversible name codec to `.bin`
directories and escapes names that would otherwise look like codec markers. A
versioned `.gdrive-name-codec` manifest records the physical layout. The restore
browser validates that manifest and presents the original logical names instead
of the internal NAS-safe names; an unknown or damaged codec layout is rejected.

Google Drive can contain multiple objects with the same exact name in the same
parent folder. When rclone reports such a collision, the backup inventories the
matching provider IDs and stores every object separately in an internal,
ID-addressed `.gdrive-collisions` archive with a group manifest. The run is
reported as successful only after all IDs in the reported group have been
archived. This preserves those exact-name duplicates without renaming or
deduplicating anything in Drive. The internal collision archive is hidden from
ordinary restore browsing and remains available for controlled recovery through
its manifests and per-ID object trees.

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

In `rclone crypt` mode, the same cadence is evaluated through the logical crypt
remote. Sparse deltas are merged through that remote first. Only then is the
exact encoded physical version directory resolved and moved to recoverable
Trash or a ciphertext-only quarantine; active encrypted directories are never
removed by a destructive rclone command.

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

For `rclone crypt`, the browser reads logical names through the crypt remote.
The selected file is decrypted into a private temporary directory, checked
against the encrypted source with `rclone cryptcheck`, hashed locally with
SHA-256, and only then published under its collision-safe final name.

## Safe diagnostics

Open **Diagnostics** from the application menu or menu bar to check the required
tools, Google Drive access, backup destination, schedule, menu bar controller,
backup engine, and last run. The checks run away from the main UI thread and
show explicit ready, failed, blocked, or unknown states.

**Copy safe report** and **Save safe report…** are manual actions. The app does
not send a report or contact a support service. The stable text report contains
only allowlisted status values, app and macOS versions, architecture, schedule
mode, tool names, timestamps, exit code, trigger, and two safe failure reasons.
It excludes local and NAS paths, URLs, account names, credentials, remote names,
file names, provider output, and log contents. Saved reports use owner-only
permissions (`0600`).

## Manual update checks

Choose **Check for Updates…** in the application menu or menu bar. The app makes
one unauthenticated request to the fixed GitHub API endpoint for this repository
and accepts only a stable numeric release version from that exact endpoint.
Cookies, cached responses, stored web credentials, foreign redirects, oversized
responses, prereleases, and malformed version strings are rejected.

The app never checks automatically at launch, downloads no package, and never
opens macOS Installer. If a newer version exists, the result offers one explicit
button to open the fixed official GitHub releases page in the browser. Download
and installation remain separate manual user actions.

## Encryption

The setup window offers three modes: no encryption requirement, an already
unlocked encrypted APFS destination, or `rclone crypt`. APFS mode fails closed
if the volume is missing, non-APFS, locked, or unencrypted. Crypt mode requires
a separately configured crypt remote whose physical root exactly matches the
selected app destination and whose content, file-name, and directory-name
encryption options satisfy the app's policy. The app saves only the remote name;
it never reads or stores either kind of password.

For exact setup steps, NAS layouts, rclone config protection, migration limits,
and recovery cautions, see [`docs/encryption.md`](docs/encryption.md).

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

Thunderbolt, USB, SD-card, and other directly attached disks appear as mounted volumes to macOS. The menu bar controller compares each mount notification with every retained external-volume UUID. A configured volume can offer the normal mount backup; an unknown physical disk can produce one passive setup notification but cannot start a backup or change configuration by itself. Internal disks, network mounts, disk images, duplicate mount events, and sibling volumes of the same physical disk do not create repeated notices. An explicit Save in setup requests macOS notification permission when it has not been decided yet; the app never opens that permission prompt merely because a disk was attached. NAS and Ethernet storage usually appear as network volumes under `/Volumes`; because they may stay mounted for a long time, NAS backups use manual or scheduled starts. These modes can be used together: the saved external disk remains mount-aware, while NAS backups run from the app or schedule.

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
