# Automatic Retry Progress Design

## Goal

Make an automatic retry observable without opening or activating a window. A
user must be able to distinguish a retry that is waiting, running, successful,
or finally failed, and must be able to inspect live per-phase progress from the
normal overview and menu bar.

## Problem

The current `BACKUP_PROGRESS_FOREGROUND` flag controls two unrelated concerns:
whether a progress window is shown and whether a progress file is created.
Automatic runs correctly disable the foreground window, but consequently emit
no progress data. The durable run summary identifies `schedule-retry` as
running, yet it contains no phase or percentage. The preliminary notification
therefore remains visible with the stale promise that a retry will start in 30
minutes even after that retry has started.

## User Experience

### Waiting for the retry

The existing persistent notification remains visible and states that the NAS
is not ready and that one automatic retry will start in 30 minutes. The normal
overview shows the failed run and the planned retry time.

### Retry running

When the retry process is accepted and publishes a matching running state, the
existing notification is updated once in place:

- Title: `Automatischer Wiederholungsversuch läuft`
- Body: `GDrive wird erneut gesichert. Öffne GDrive Backup Tiger, um den Fortschritt zu sehen.`
- Action: open the normal GDrive Backup Tiger overview

No window is opened or activated automatically. Full-screen applications and
the user's current Space remain undisturbed.

The normal overview displays:

- `Automatischer Wiederholungsversuch läuft` instead of the generic running
  label;
- the retry start time;
- a native progress bar;
- the current phase as `Bereich N von M`;
- the current phase percentage, transferred size, speed, and ETA when rclone
  provides them;
- an indeterminate bar and `Wird vorbereitet …` during preflight or between
  measurable copy phases.

The percentage is explicitly the percentage of the current phase. The product
must not present it as a global backup percentage because calculating that
would require an expensive complete pre-scan.

The menu bar uses the same snapshot and shows a compact disabled status row,
for example `Retry läuft · Bereich 3 von 5 · 63 %`. Selecting `GDrive Backup
Tiger öffnen` reveals the full overview.

### Retry success

A terminal `success` with exit code 0 and a matching automatic trigger clears
the persistent warning and the live-progress record. The overview returns to
the existing completed state.

### Retry failure or interruption

A terminal failure replaces the running notification with the existing final
retry-failure notification and remains visible until a newer automatic success
or explicit human dismissal. An interrupted process is treated as a terminal
problem, never as indefinitely running progress.

## Progress Data Contract

Every real backup owner creates a private, profile-scoped progress file after
acquiring the backup lock, regardless of whether a foreground progress window
is allowed. The file lives next to the profile's `last-run.status`, is mode
`0600`, and is replaced atomically.

The protocol contains only aggregate status data:

```text
protocol=1
profile_id=default
pid=12345
started_at=1785522633
trigger=schedule-retry
retry_attempt=1
label=Shared Drive
phase=3/5
percent=63
detail=1.2 GiB / 1.9 GiB, 12.4 MiB/s, ETA 58s
updated_at=1785523000
```

It must not contain file names, directory names from individual transfers,
credentials, remote configuration, or raw log lines. Shared Drive names are
also omitted from background progress; only the generic area type and phase
count are exposed.

Readers accept the progress record only when all of these conditions hold:

- protocol, PID, start time, trigger, and profile ID are valid;
- PID and start time match the current validated `running` summary;
- the process still exists;
- `updated_at` is not in the future and is recent enough for a live run;
- phase and percentage pass strict bounds checks.

Invalid or stale progress falls back to an indeterminate running state. It can
never turn a terminal summary back into a running state.

## Architecture

The shell script separates progress telemetry from foreground presentation:

1. After lock ownership, it derives the profile progress path and creates the
   first atomic `preparing` record.
2. Existing rclone statistics parsing writes sanitized aggregate updates to
   that durable file.
3. A manual foreground helper may additionally read the same data; automatic
   runs never open the helper.
4. Terminal cleanup removes or invalidates the live record only after the
   terminal run summary is safely written.

The persistent controller already refreshes every two seconds while a run is
active. It reads and validates the progress record alongside `last-run.status`,
adds the fields to one overview snapshot, and feeds both the overview and menu
bar from that snapshot.

Notification policy gains an explicit `retry-running` state. It updates the
preliminary failure notification once after a matching retry is running. The
unresolved issue latch remains active, so the warning is still cleared only by
a newer automatic success or human dismissal.

## Safety and Compatibility

- Scheduled and retry runs remain headless and never activate the app.
- The current foreground and full-screen nonintrusion contracts remain intact.
- The existing profile isolation and atomic summary protocol remain intact.
- Legacy or missing progress files degrade to the current generic running UI.
- No change may restart the installed controller, replace the installed app or
  script, or alter configuration while a backup is running.
- The installed update is staged and verified first, then applied only after
  the active backup reaches a terminal state.
- All seven supported languages receive complete retry-running and progress
  copy, including accessibility labels.

## Test Strategy

Tests are written before production changes and must first fail for the missing
behavior. Coverage includes:

- shell tests proving headless automatic runs create atomic, private,
  aggregate-only progress records without opening a window;
- parser tests for matching, stale, malformed, cross-profile, mismatched-PID,
  out-of-range, and terminal progress records;
- overview tests for indeterminate preparation, determinate current-phase
  progress, retry-specific copy, disabled concurrent backup action, and menu
  bar parity;
- notification policy and integration tests proving the preliminary alert is
  updated once when the retry runs, is cleared on success, and is replaced on
  final failure;
- accessibility tests for the native progress indicator and localized labels;
- regression tests preserving headless automatic execution, passive window
  behavior, full-screen safety, failure persistence, and deduplication.

The complete existing test suite, syntax checks, Universal 2 build, code-sign
verification, and isolated app-launch check must pass before installation.

## Non-Goals

- No global percentage across all Google Drive areas.
- No periodic notification for every percentage change.
- No automatic foreground window, Dock activation, or Space switching.
- No change to backup contents, version retention, NAS mounting, credentials,
  schedule, or retry count.
