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
no-op because macOS fires `StartOnMount` for unrelated disks too. Manual and
scheduled runs report a missing or locked encrypted volume as an error.

`rclone crypt` is also a strong fit for NAS storage: it can encrypt file data
and file and directory names. It is not wired into this release because copy,
versioning, restore, and retention must all address the same crypt remote; only
changing the copy destination would make retention incomplete and unsafe.

When a future crypt-remote mode is enabled, protect `rclone.conf` as well.
Rclone's normal password obscuring is reversible. Rclone supports encrypting
the whole config and retrieving its password from macOS Keychain with
`RCLONE_PASSWORD_COMMAND`, so no cleartext password needs to live in a launchd
plist or this project's config.

Useful upstream references:

- [Apple: Encrypt and protect a storage device](https://support.apple.com/guide/disk-utility/encrypt-protect-a-storage-device-password-dskutl35612/mac)
- [Apple: Create an encrypted disk image](https://support.apple.com/guide/disk-utility/create-a-disk-image-dskutl11888/mac)
- [rclone crypt](https://rclone.org/crypt/)
- [rclone configuration encryption](https://rclone.org/docs/#configuration-encryption)
