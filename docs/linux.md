# Linux edition (preview)

The backup engine also runs on Linux, without a graphical app, in the style of
[Omarchy](https://omarchy.org) and other keyboard-first setups: a command, a
systemd timer, desktop notifications and a Waybar module. It keeps the same
safety rules as on macOS: read-only Google access, retained versions, catch-up
of missed days, a destination identified by its filesystem UUID, and a
watchdog for vanished network shares and stalled copies.

Status: preview. The engine test suites run on Ubuntu and Arch Linux in CI, and
the installer, setup, timer and status were tried in an Ubuntu 24.04 virtual
machine. A full backup of a real Google Drive on Linux is still to be done;
please report anything that does not work.

## Requirements

- rclone 1.70 or later, jq, util-linux (`findmnt`, `flock`), diffutils (`cmp`)
- a destination that is not the system disk: a mounted external disk
  (ext4, btrfs, xfs, …) or a mounted network share (cifs/smb3, nfs). The
  backup never mounts shares itself and never stores a NAS password; mount it
  with your system's tools (for example a systemd `.mount` unit).
- for the schedule: a systemd user session; for notifications: a notification
  daemon such as mako

Arch / Omarchy:

```bash
sudo pacman -S rclone jq util-linux diffutils
```

Debian / Ubuntu: `sudo apt install jq util-linux diffutils`, and rclone from
<https://rclone.org/install/> (the distribution package is often too old).

## Install

```bash
git clone https://github.com/AlexanderSmyslowski/gdrive-tiger-backup.git
cd gdrive-tiger-backup
packaging/linux/install.sh
gdrive-tiger-backup setup
```

The installer needs no root. It puts the engine into
`~/.local/share/gdrive-tiger-backup`, the command into `~/.local/bin` and the
systemd units into `~/.config/systemd/user`. Run it again to update;
`packaging/linux/install.sh --uninstall` removes the program and keeps your
configuration, history and backups.

`setup` connects Google Drive (read-only, in the browser), asks for the backup
folder and enables the daily schedule.

### Your own Google connection

Google retires the sign-in client built into rclone during 2026, so the backup
signs in with a client in your own Google Cloud project. `setup` lists the five
console pages to open (new project, enable the Drive API, Google sign-in setup,
for a private Gmail account "Publish app", and a client of type **Desktop
app**). Click **Download JSON**; `setup` finds the newest `client_secret_*.json`
in `~/Downloads`, checks it, keeps a private copy in
`~/.config/gdrive-tiger-backup/google-oauth-client.json` and signs in.

An existing remote that still uses rclone's client is offered the switch in
`setup`, or later with `gdrive-tiger-backup connect`. It is switched only after
a temporary remote has signed in and read Drive, and never while a backup runs.

On a machine without a browser, connect over SSH from your computer with
`ssh -L 53682:127.0.0.1:53682 <machine>` and open the link that rclone prints.

## Use

```text
gdrive-tiger-backup status          last run, last success, every destination
gdrive-tiger-backup status --json   the same for scripts
gdrive-tiger-backup check           dry run: show what would be copied
gdrive-tiger-backup run             back up now
gdrive-tiger-backup log             follow the backup log
gdrive-tiger-backup connect         (re)connect Google Drive with your own client
```

The timer starts the engine every hour. From 20:00 it backs up once a day;
later starts only catch up a missed or failed day and otherwise return at
once. Notifications appear for the first failure and when backups work again,
not for every hourly retry.

Files:

- configuration: `~/.config/gdrive-tiger-backup/config`
- log, status and history: `~/.local/state/gdrive-tiger-backup/`

## Waybar

Copy the module from
[`packaging/linux/waybar-module.jsonc`](../packaging/linux/waybar-module.jsonc)
into your Waybar configuration and add `"custom/gdrive-backup"` to a modules
list. It shows `✓ 3h` (hours since the last success), `✕` after a failure,
`↻` while a backup runs and `!` when the last success is older than 36 hours,
with CSS classes `success`, `failure`, `running`, `stale` and `never`.
