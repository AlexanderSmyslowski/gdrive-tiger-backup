# First run on a fresh Mac: test checklist

Goal: a person who has never seen the app installs it, connects Google Drive,
backs up, and restores a file, without help and without the Terminal. Every
stumble is a bug, even when the app "technically works". This is step 3 of the
[public launch plan](public-launch-plan.md).

## Setup

Use one of these, never the maintainer's everyday account:

- a new macOS user account (System Settings › Users & Groups), or
- a macOS virtual machine (for example UTM or Parallels on Apple silicon).

The account must have no Homebrew, no rclone, no earlier GDrive Backup Tiger
and no `~/.config/gdrive-tiger-backup`. Use a Google test account with a few
files: a PDF, a photo, a Google Doc, a Google Sheet, a folder with a name that
contains umlauts, and two files with the same name in one folder.

Write down for every step: what you expected, what happened, how long it took,
and any message that was unclear. Take screenshots.

## Runs

Run the checklist on:

- [ ] the current macOS release, Apple silicon
- [ ] macOS 13 Ventura (oldest supported)
- [ ] an Intel Mac, if one is available

## Checklist

### Install

- [ ] Download the `.pkg` from the latest release page.
- [ ] Open it. Note exactly what macOS shows (Gatekeeper warning while
      unsigned; no warning once signed and notarized).
- [ ] Installer finishes; the app opens with "Not set up yet" and
      "Set up backup …" highlighted.

### Set up

- [ ] **Connect Google** opens the own-client assistant; following its five
      console steps works, the downloaded JSON file is picked up without
      choosing it, the browser sign-in requests read-only access, and the setup
      check turns green (not **!**) afterwards.
- [ ] Choose an external disk: the disk is offered by its device name; nothing
      is formatted without a clear confirmation.
- [ ] Alternatively choose a NAS: discovery or address entry works with the
      plain-language labels.
- [ ] Choose a schedule and **Save**; the overview shows destination and next
      run.

### Back up

- [ ] **Start backup**: progress is visible and understandable.
- [ ] macOS permission prompts (removable volume, network volume, Keychain)
      appear at a moment that makes sense and can be answered correctly
      without explanation.
- [ ] The backup completes; the overview shows "Last completed" for that
      destination, with the device name.
- [ ] On the disk, Google Docs/Sheets arrived as Office files, umlaut names and
      same-name files are intact.

### Restore

- [ ] **Restore files**: find the PDF, pick an earlier version after changing
      the file in Google Drive and running a second backup, restore it, open it.

### Failure cases

- [ ] Disconnect the disk during a backup: the run stops cleanly and the
      overview says why.
- [ ] Turn off Wi-Fi during a NAS backup: same.
- [ ] Next scheduled run after reconnecting catches up.

### Update

- [ ] With an older version installed, **Check for Updates…** offers the latest
      release and installs it; the app confirms the new version.

## After the run

- File one issue per stumble (bug template), with screenshots.
- Fix the blocking ones before the public launch; repeat the run once after the
  fixes.
- Tick the step in `docs/public-launch-plan.md`.
