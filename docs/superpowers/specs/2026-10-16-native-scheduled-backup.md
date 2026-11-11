# Native scheduled backup: bounded correction

User authorized diagnosis and repair of NAS automatic backups. Historical evening runs failed before NetFS with Keychain -25293 despite home-network availability. Scoped native Keychain consent repaired silent mounting. A controlled existing launchd run on 2026-10-16 failed destination_unreadable: direct Bash launch cannot read the known NAS manifest (EPERM), while ordinary tool context can. A read-only diagnostic reproduced EPERM with and without AssociatedBundleIdentifiers. Do not assert the exact TCC decision or successful restoration yet.

## Required behavior

The bundled native app handles exactly --run-scheduled-backup with no extra arguments before NSApplication/UI initialization. It remains alive as responsible parent of the fixed /bin/bash /usr/local/bin/backup-google-drive.sh --run child until completion. The child receives a minimal trusted environment, trusted user HOME/PATH, schedule trigger, assume-yes and no foreground animation. Strip shell startup/function exports and environment-controlled engine/config/helper/test paths; reject automatic one-shot destination/UUID/creation approvals. Saved profile remains authoritative. No shipping test-engine override.

Establish the engine process group required by existing cancellation; forward HUP/INT/TERM safely, reap children, preserve exit failure/signal semantics and terminal state. No Objective-C in asynchronous handlers or unsafe PID/group signaling.

Change only the daily/hourly/login schedule generator in main.m, preserving timing and mode and associating the bundle. Preserve separate --menubar controller and existing 30-minute retry, notifications, lock, pause/profile logic, read-only source, destination identity/content checks, versioning and encryption. No new scheduler/lock, no data-check bypass, no Keychain/TCC reset or broad grant.

## Acceptance and boundaries

Fresh independent specification review approved this bounded candidate conditionally on 2026-10-16 (review_scheduler_design, gpt-6-astra/high). Meaningful regression tests cover strict/no-UI CLI handling, fixed command/environment, launch/exit errors, cancellation/subprocess cleanup, all schedule modes, profile/pause/overlap and retry linkage. Existing relevant suites and universal staged build are required. Build only with explicit nonproduction APP_DIR. Preserve preexisting dirty work; no commits unless task-only scope can be proven. Independently review the exact candidate fingerprint.

Installation/migration is a separate gate. Prepare a scoped migration and rollback preserving schedule, pause, controller and originals; changed ad-hoc identity may require new scoped native consent. Do not deploy or launch full backups from test/staged contexts. Only authorized live installed launchd verification can establish NAS access and successful unattended backup.
