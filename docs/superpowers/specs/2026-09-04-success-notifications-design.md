# Successful Backup Notifications Design

## Goal

Close the feedback gap after an automatic backup problem is resolved, while
keeping routine background backups quiet unless the user explicitly opts in.

## User experience

- A successful automatic backup that is newer than the profile's active
  failure or missed-run issue produces one quiet recovery notification.
- The recovery title is **Backup erfolgreich fertiggestellt** in German.
- A successful retry explains that the automatic retry succeeded and that the
  backup is current again. A later normal scheduled run uses equivalent generic
  recovery wording.
- Recovery notifications are enabled whenever automatic-failure notifications
  are enabled. They are the resolution of an existing warning, not routine
  success reporting.
- A separate setup switch, **Auch erfolgreiche automatische Backups melden**,
  lets a user request a quiet notification for every successful automatic run.
  It defaults to off for new and existing installations.
- Manual, mount-triggered, dry-run, skipped, cancelled, interrupted, malformed,
  stale, and still-running outcomes never create a success notification.
- Success delivery never opens a window, activates the application, makes a
  sound, or requests time-sensitive interruption. A human click may open the
  existing overview.

## Trust boundary

The notification policy accepts a success only when all of these facts agree:

- the resolved status is `success`;
- the durable summary says `status=success` and `exit_code=0`;
- `started_at`, `finished_at`, and `last_success_at` are canonical positive
  integer timestamps with `started_at <= finished_at` and
  `last_success_at >= started_at`;
- the trigger is `schedule` or a structurally valid first `schedule-retry`;
- the event is no more than 24 hours old and not in the future;
- the configured schedule is automatic and not paused;
- a routine notification was enabled before this run finished, or a strictly
  older active issue exists for this profile.

The decision and its notification contain no destination, file name, account,
remote, path, or credential.

## Lifecycle and deduplication

- A success identifier is scoped to the safe profile id and `finished_at`.
- The controller persists a per-profile monotonic delivered-success timestamp
  only after Notification Center accepts the request.
- Repeated refreshes and controller restarts cannot redeliver the same or an
  older success.
- At most one delivered success notification is retained per profile; a newly
  accepted success retires the previous canonical success identifier.
- Failure cleanup remains authoritative and independent of success delivery.
  A successful automatic run clears only older failure notifications, even if
  success notifications are disabled or delivery is refused.
- A human-dismissed issue does not produce a later recovery notification.

## Configuration and compatibility

- `GDRIVE_BACKUP_NOTIFY_SUCCESSES=1` enables routine automatic-success
  notifications; `0` disables them.
- Missing or malformed values fail closed to `0`.
- Source and package installers add `GDRIVE_BACKUP_NOTIFY_SUCCESSES=0` without
  overwriting an existing preference.
- Notification permission is requested after an explicit setup save whenever
  either automatic-failure or routine-success notifications are enabled.
- All visible copy is present in German, English, French, Spanish, Japanese,
  Cantonese, and Korean.

## Verification

Tests must prove policy rejection and acceptance boundaries, per-profile
deduplication across restarts, refused-delivery retryability, retirement of an
older success notice, silent non-time-sensitive content, setup persistence and
defaults, notification authorization routing, and localization coverage.
