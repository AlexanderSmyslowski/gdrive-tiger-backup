# Backup encryption

GDrive Backup Tiger can require an already unlocked, encrypted APFS destination.
The app never reads or stores the volume password.

## External disks

Create or convert the backup destination as an encrypted APFS volume in Finder
or Disk Utility, then unlock it before a backup starts. Configure the mounted
volume and enable **Require encrypted APFS (already unlocked)** in the setup
window, or set the equivalent config values:

```bash
GDRIVE_BACKUP_TARGET=apfs
GDRIVE_BACKUP_VOLUME=/Volumes/GoogleDrive-Backup
GDRIVE_BACKUP_AUTO_CREATE_VOLUME=0
GDRIVE_BACKUP_ENCRYPTION=apfs
```

With `GDRIVE_BACKUP_ENCRYPTION=apfs`, every run checks that the mounted target
uses APFS and reports `Encryption=true`. A missing, locked, non-APFS, or
unencrypted destination stops the backup before rclone can write anything. The
helper will not auto-create a plain APFS volume while this mode is active.
It also verifies that the configured destination and version paths stay on that
same encrypted volume instead of following a destination override or top-level
or nested symlink to cleartext storage. The volume UUID and device identity are
rechecked after confirmation and before each copy phase.

Keep the recovery password outside this project. macOS can remember the unlock
credential in the user's Keychain if unattended scheduled backups are needed.
If the password and every recovery copy are lost, the encrypted backup cannot
be recovered. Once the volume is unlocked, authorized local processes can read
its cleartext contents normally.

> Disk Utility's erase-and-format workflow destroys existing data. Migrate or
> copy existing backups before reformatting a used destination.

## NAS destinations

The current backup and retention engine works on a mounted POSIX destination.
One compatible encrypted NAS layout is an encrypted APFS disk image stored on
the NAS and mounted on the Mac before the backup. Point
`GDRIVE_BACKUP_VOLUME` at the mounted encrypted image, not at the unencrypted
NAS share. This is configured as a local APFS target, even though the image file
itself lives on a NAS:

```bash
GDRIVE_BACKUP_TARGET=apfs
GDRIVE_BACKUP_VOLUME=/Volumes/GoogleDrive-Encrypted
GDRIVE_BACKUP_DEST_ROOT=/Volumes/GoogleDrive-Encrypted
GDRIVE_BACKUP_ENCRYPTION=apfs
```

Use a reliable connection and always eject the image cleanly.

Mount-triggered jobs intentionally treat a missing configured volume as a
no-op because unrelated disk events must never select a NAS target. Manual and
scheduled runs report a missing or locked encrypted volume as an error.

## rclone crypt

`rclone crypt` encrypts file contents plus file and directory names and works
with either a local APFS destination or a mounted NAS. The app uses the same
crypt remote for the live backup, sparse version deltas, retention merges, and
restore. It stores only the remote name; password creation and storage remain
entirely inside rclone.

Choose one dedicated physical destination. It must exactly match the path shown
as **Exact destination** in setup. Examples:

```text
/Volumes/GoogleDrive-Backup
/Volumes/Backups/GoogleDrive-Backup
```

Create the remote interactively so rclone, not the app, receives the password
and salt:

```bash
rclone config
```

Create a remote such as `backup-crypt`, choose backend `crypt`, and set its
underlying remote to the absolute physical destination above. Use standard file
name encryption, directory name encryption, data encryption, a password, and a
second password/salt. Then make every required policy value explicit:

```bash
rclone config update backup-crypt \
  filename_encryption standard \
  directory_name_encryption true \
  no_data_encryption false \
  show_mapping false
```

Verify that rclone can open it:

```bash
rclone lsd backup-crypt:
```

In GDrive Backup Tiger, choose **rclone crypt** and enter only
`backup-crypt` as the Crypt remote. The system check fails closed unless the
remote is type `crypt`, wraps the exact selected destination, has both password
values, encrypts data and names, and keeps mapping output disabled. The backup
also rejects source/crypt name reuse, symbolic links, and nested foreign file
systems in the physical ciphertext tree, and rechecks the policy immediately
before every copy phase.

Equivalent profile values are:

```bash
GDRIVE_BACKUP_ENCRYPTION=rclone-crypt
GDRIVE_BACKUP_CRYPT_REMOTE=backup-crypt
```

Do not point the crypt remote at an existing cleartext backup and expect it to
become encrypted. Start with a dedicated empty destination or migrate data
through rclone after independently verifying the result. Do not mix cleartext
files with the physical ciphertext tree.

Retention lists logical version runs through the crypt remote and first merges
the newest missing per-file deltas into the daily or weekly keeper. It then asks
the crypt backend for the exact encoded directory and moves only that physical
ciphertext directory to macOS Trash or a ciphertext-only quarantine. It never
uses `rclone delete`, `purge`, or `rmdirs` for retention.

Restore also stays inside the crypt abstraction: the browser lists logical
names, `rclone copyto` decrypts the chosen file into a private temporary
directory, `rclone cryptcheck` compares it with the encrypted source, and a
local SHA-256 is recorded before the collision-safe final file is published.

Protect `rclone.conf`. Rclone's normal password obscuring is reversible.
Rclone supports encrypting the whole config and obtaining its password through
`RCLONE_PASSWORD_COMMAND`, which can be connected to macOS Keychain without
putting a cleartext password into this app's profile or a launchd plist. Keep a
separate tested recovery copy of the config password, crypt password, and salt.
If they are lost, the encrypted backup cannot be recovered.

The local operational log may contain logical file names from rclone. The
backup engine enforces owner-only mode `0600` on that log; treat it as sensitive.
The optional in-app safe diagnostics report never includes log contents, paths,
remote names, credentials, or file names.

Useful upstream references:

- [Apple: Encrypt and protect a storage device](https://support.apple.com/guide/disk-utility/encrypt-protect-a-storage-device-password-dskutl35612/mac)
- [Apple: Create an encrypted disk image](https://support.apple.com/guide/disk-utility/create-a-disk-image-dskutl11888/mac)
- [rclone crypt](https://rclone.org/crypt/)
- [rclone configuration encryption](https://rclone.org/docs/#configuration-encryption)
