---
name: gdrive-backup-google-setup
description: >
  Set up GDrive Tiger Backup (the "Drive Backup" Omarchy plugin and the
  gdrive-tiger-backup command) for the user: walk them through creating their
  own Google client in the Google Cloud console, connect Google Drive read-only,
  choose a backup disk, run a dry run. Triggers: set up Drive Backup, connect
  Google Drive backup, gdrive-tiger-backup setup, back up my Google Drive.
---

# Setting up Google Drive Backup

You help a person connect their Google Drive to `gdrive-tiger-backup` and get a
first backup going. Most of the work is theirs to click in Google's console:
Google offers no API for creating the sign-in client. Your job is to make that
easy: one page at a time, exact values, and you do everything that can run in
the terminal.

Done means: `gdrive-tiger-backup status` shows the destination, and a dry run
(`gdrive-tiger-backup check`) has finished without errors.

## Rules

- Never ask for, type or handle the user's Google password. They sign in to
  Google themselves in the browser.
- Never print, `cat`, copy into the chat or upload the Google client file
  (`client_secret_*.json`) or `~/.config/rclone/rclone.conf`. Check the client
  file only with the `jq` command below, which prints one word.
- Do not edit rclone's configuration by hand; `gdrive-tiger-backup connect`
  does it.
- Never format, partition or mount a disk unless the user asks you to, and say
  what it would erase first. `sudo` only with the user's explicit yes.
- Give one console step at a time and wait until the user says it is done or
  shows a screenshot. Keep each message short.
- If you can control a browser, you may do the console clicks yourself, but the
  user signs in to Google.

## 0. Where are we?

```bash
command -v gdrive-tiger-backup rclone jq
gdrive-tiger-backup status
rclone listremotes
rclone config show gdrive 2>/dev/null | grep -c '^client_id = .' # 1 = own client already set
```

- `gdrive-tiger-backup` missing: it is installed from
  <https://github.com/AlexanderSmyslowski/gdrive-tiger-backup> with
  `packaging/linux/install.sh`; on Arch/Omarchy first
  `sudo pacman -S rclone jq` (ask before using sudo).
- Remote `gdrive:` with its own client already: skip to step 3.
- A `client_secret_*.json` already in `~/Downloads` from an earlier attempt:
  check it (step 2) before sending the user through the console again.

## 1. Google's console (the user clicks)

Before the first page: the user must be signed in with the Google account whose
Drive should be backed up. Tell them to check the round profile picture at the
top right of the console. Banners such as "Start your free trial" are not
needed; nothing here needs billing.

1. **Project:** <https://console.cloud.google.com/projectcreate>. Project name
   `drive-backup`, **Create**. Afterwards the project picker at the top must
   show `drive-backup`.
2. **Drive API:** <https://console.cloud.google.com/apis/library/drive.googleapis.com>,
   **Enable**. Status then reads "Enabled".
3. **Google sign-in:** <https://console.cloud.google.com/auth/overview>,
   **Get started** (in German "Erste Schritte"):
   - App name `Drive Backup`, user support email: their address
   - Audience: **External** for a private Gmail account. A Google Workspace
     account may choose **Internal** and then skips step 4.
   - Contact email: their address; agree; **Create**
4. **Publish (External only).** Otherwise Google signs the backup out every
   7 days.
   - <https://console.cloud.google.com/auth/branding>: App home page
     `https://github.com/AlexanderSmyslowski/gdrive-tiger-backup`, privacy policy
     `https://github.com/AlexanderSmyslowski/gdrive-tiger-backup/blob/main/PRIVACY.md`,
     authorized domain `github.com` if asked. **Save**.
   - <https://console.cloud.google.com/auth/audience>: **Publish app**,
     **Confirm**. Status then reads "In production".
5. **Client:** <https://console.cloud.google.com/auth/clients/create>.
   Application type **Desktop app**, **Create**, then **Download JSON** in the
   dialog that follows.

## 2. Find and check the downloaded file

```bash
file="$(ls -t "${XDG_DOWNLOAD_DIR:-$HOME/Downloads}"/client_secret_*.json 2>/dev/null | head -n 1)"
jq -r 'keys[0]' "$file"   # must print: installed
```

`web` means the wrong client type was chosen in step 5: create a new client of
type **Desktop app**. Anything else is not a Google client file.

## 3. Connect Google Drive

```bash
printf '\n' | gdrive-tiger-backup connect
```

It picks up the newest client file, keeps a private copy and opens the browser
for Google's sign-in. The command waits until the user is done (allow at least
five minutes before a timeout). Tell the user what they will see:

- choose the same Google account as in step 1
- "Google hasn't verified this app": **Continue**. It is their own app.
- allow read-only access to Google Drive

It ends with "Google Drive connected with your own client." On a machine
without a browser the user connects from their computer with
`ssh -L 53682:127.0.0.1:53682 <machine>` and opens the link that rclone prints.

## 4. Backup destination

The backup must go to a separate disk or network share, never the system disk.
Show what is mounted and let the user choose:

```bash
findmnt -rno TARGET,FSTYPE,SIZE,AVAIL | grep -vE '^/(boot|efi|proc|sys|dev|run|tmp)|^/ |^/home ' | grep -vE ' (tmpfs|devtmpfs|overlay|squashfs|proc|sysfs|cgroup2|efivarfs|vfat|autofs) '
```

Check that the free space is roughly larger than the Drive
(`rclone about gdrive:`). Ask whether they want the daily automatic backup
(recommended). Then, with their folder and answer (`y` or `n`):

```bash
printf '%s\n%s\n' "/path/on/the/disk/GoogleDrive-Backup" "y" | gdrive-tiger-backup setup
```

## 5. Dry run, then the first backup

```bash
gdrive-tiger-backup check
```

The dry run copies nothing and lists what would be copied. A large Drive takes
a while (about 15 minutes for 100 GB); say so. If it ends with "Fertig ohne
Fehler", offer `gdrive-tiger-backup run` for the first real backup. On Omarchy,
also offer `gdrive-tiger-backup omarchy-menu` for a Drive Backup submenu.

## When something goes wrong

- **"Access blocked" / no Continue button:** the app is still in *Testing* and
  this account is not a test user. Finish step 4, or add the account under
  Audience, Test users.
- **"redirect_uri_mismatch" or the setup refuses a web client:** the client is
  not of type Desktop app; redo step 5.
- **403 "Drive API has not been used":** step 2 was done in a different
  project; enable the API in `drive-backup`.
- **"a backup is running":** wait until it finishes, then run `connect` again.
- **Signed out after 7 days:** the app was never published; do step 4, then
  `gdrive-tiger-backup connect` again.
