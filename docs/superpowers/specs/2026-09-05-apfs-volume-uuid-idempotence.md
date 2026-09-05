# APFS Volume UUID Idempotence Specification

## Problem

Repeated GDrive Backup Tiger runs must never create duplicate APFS backup
volumes merely because macOS changed a mount-path suffix or a previous setup
attempt did not persist its result. The reported failure manifested as three
APFS volumes named `GoogleDrive-Backup`, followed by Time Machine error
`BACKUP_FAILED_DUPLICATE_VOLNAMES (24)`.

## Required behavior

- A configured APFS volume UUID is authoritative. Resolve its current mount
  point through `diskutil`; never fall back to a name or stale mount path.
- Before any `diskutil apfs addVolume`, inspect the selected external APFS
  container for existing volumes with the requested logical name.
- If exactly one existing named volume is present, validate it in the same
  external container, resolve it by UUID, and persist that UUID and current
  mount point before copying.
- If more than one existing named volume is present, abort before any backup
  or disk mutation. Log that multiple candidates exist, that the user must
  select the intended volume explicitly, and that nothing was created or
  deleted.
- If more than one eligible external APFS container is present, abort instead
  of choosing one by mount-directory modification time.
- Only a zero-candidate, one-container setup may create a volume. Automatic
  schedule/retry approval must not count as human approval for APFS volume
  creation.
- The routine contains no deletion, erasure, repartitioning, rename, or
  unmount operation. No such operation may be introduced.
- Repeated runs are idempotent: after identity is recovered or created once,
  the next run reuses the persisted UUID and creates no additional volume.

## Verification

- Behavior-level regression tests exercise one existing volume, multiple
  existing volumes, multiple source containers, creation authorization, and
  two consecutive runs.
- Ambiguity tests preserve configuration and canary files and prove that no
  `addVolume`, delete/erase command, privileged helper, or rclone copy ran.
- Run the focused regression suite twice consecutively, followed by the full
  project test suite.
- Live Toshiba inspection remains read-only. Existing volumes and their data
  are never changed or deleted by this work.

