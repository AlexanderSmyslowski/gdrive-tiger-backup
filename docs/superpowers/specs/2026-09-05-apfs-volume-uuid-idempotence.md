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
- An existing path without a saved UUID is not sufficient for a backup. Only
  the visible interactive setup flow may validate that exact external APFS
  volume, bind its UUID, and atomically persist the resolved volume and
  destination before copying. Every other trigger fails closed.
- Before any `diskutil apfs addVolume`, inspect the selected external APFS
  container for existing volumes with the requested logical name. Scope the
  inventory to that exact container, and treat an exact-name record with a
  missing or invalid UUID as an error rather than as zero candidates.
- If exactly one existing named volume is present, validate it in the same
  external container, resolve it by UUID, and persist that UUID and current
  mount point before copying.
- If more than one existing named volume is present, abort before any backup
  or disk mutation. Log that multiple candidates exist, that the user must
  select the intended volume explicitly, and that nothing was created or
  deleted.
- Treat numeric logical-name variants such as `GoogleDrive-Backup 1`, `2`, and
  `3` as conflicting candidates for automatic creation. Never guess which one
  is intended; require explicit setup selection and do not create another base
  name while any such candidate exists.
- If more than one eligible external APFS container is present, abort instead
  of choosing one by mount-directory modification time.
- Only a zero-candidate, one-container setup may create a volume. Automatic
  schedule/retry approval must not count as human approval for APFS volume
  creation. Creation is available only in the distinct interactive setup
  context; manual overview/menu-bar, mount, schedule, retry, and unknown
  triggers cannot create a volume or open creation UI.
- Immediately after any human confirmation and before `addVolume`, rediscover
  the eligible container and refresh the exact-name UUID inventory. Bind the
  authorization to the source volume UUID, APFS container UUID, and sorted
  physical-store UUID set rather than the reusable `diskN` identifier. Recover
  a newly appeared unique candidate, abort on any identity change or ambiguity,
  and mutate only while that fresh inventory is empty.
- If `addVolume` needs macOS administrator authorization, repeat the container
  identity, physical-store identity, source-volume, and exact-name checks inside
  the authorized command after the password dialog and immediately before the
  privileged mutation. A pre-dialog snapshot or matching `diskN` string is not
  sufficient.
- When one physical disk exposes multiple suitable APFS volumes, the app must
  begin with no selection and keep confirmation disabled until the user chooses
  one explicitly. Cancelling, pressing Return before a choice, or losing the
  selected UUID changes no configuration and never falls through to a sibling.
- Invocation trigger and one-run creation approval are captured before profile
  configuration is loaded. A profile cannot turn an automatic/menu-bar run
  into setup or persist creation authority, and unknown trigger or approval
  values fail before disk access.
- Persist a rebased nested destination together with the UUID and current mount
  path so the next UUID-resolved run cannot inherit a stale destination root.
- The routine contains no deletion, erasure, repartitioning, rename, or
  unmount operation. No such operation may be introduced.
- Repeated runs are idempotent: after identity is recovered or created once,
  the next run reuses the persisted UUID and creates no additional volume.

## Verification

- Behavior-level regression tests exercise one existing volume, multiple
  existing volumes, multiple source containers, path-only profiles, creation
  authorization, missing and malformed inventory UUIDs, foreign or duplicated
  container records, pre-create and administrator-dialog inventory races,
  `diskN` reuse by a different physical store, explicit multi-volume selection,
  nested destinations, and two consecutive runs.
- Ambiguity tests preserve configuration and canary files and prove that no
  `addVolume`, delete/erase command, privileged helper, or rclone copy ran.
- Run the focused regression suite twice consecutively, followed by the full
  project test suite.
- Live Toshiba inspection remains read-only. Existing volumes and their data
  are never changed or deleted by this work.
