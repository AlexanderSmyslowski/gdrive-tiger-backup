# Changelog

## Unreleased

- Offer optional app-wide daily GitHub version checks after an explicit visible-overview choice; add compact update settings to both menus. Refusal, consent and daily attempt timing survive restarts.
- Show silent, passive, per-version update notices and a menu fallback when system notifications are unavailable. Update actions open only the official release page; downloads and installation remain manual. Backup settings and notifications are unchanged.

## v2.5.1 - 2026-09-05

This is the first public release of the destination picker developed in the unpublished v2.5.0 intermediate milestone. It includes all of those changes as well as the NAS retry fix below.

- Choose the destination for a single manual backup directly in the main window. Saved NAS and external APFS destinations are listed by readable identity; the automatic profile and schedule remain unchanged.
- Recheck the selected external volume UUID immediately before launch and inside the engine. Disconnected, read-only, ambiguous and Time Machine backup volumes cannot be selected. Repeated runs reuse the saved volume without creating or formatting volumes.
- Show manual progress and the actual destination in the main window. Store manual results separately so an external backup cannot clear a scheduled NAS failure, and prefer newer automatic results over older manual results.
- Add an existing external APFS volume through a compact manual-destination dialog, with explicit selection and no profile activation. The installed app and engine must both support the one-run destination protocol.
- Defer automatic NAS retries while another backup holds the shared backup lock. A contended process launch no longer consumes the single retry; the original failed schedule remains eligible until a real retry starts or a newer run supersedes it.
- Recover retry markers left by earlier app versions when the durable status still proves that no retry ran. Keep duplicate-start protection while waiting for the running backup to finish.

Validation scope: fresh-account installation and dry-run tests on macOS 13 and the current macOS release have not yet been completed. Automated checks cover the test suite, package contents, deployment metadata and both binary architectures; they do not replace those runtime tests.

## v2.5.0 - 2026-09-05

Unpublished intermediate source milestone, included in the public v2.5.1 release.

- Choose the destination for a single manual backup directly in the main window. Saved NAS and external APFS destinations are listed by readable identity; the automatic profile and schedule remain unchanged.
- Recheck the selected external volume UUID immediately before launch and inside the engine. Disconnected, read-only, ambiguous and Time Machine backup volumes cannot be selected. Repeated runs reuse the saved volume without creating or formatting volumes.
- Show manual progress and the actual destination in the main window. Store manual results separately so an external backup cannot clear a scheduled NAS failure, and prefer newer automatic results over older manual results.
- Add an existing external APFS volume through a compact manual-destination dialog, with explicit selection and no profile activation. The installed app and engine must both support the one-run destination protocol.

## v2.4.6 - 2026-09-05

- Make the process-supplied `setup` trigger the only authority that can create or bind an APFS volume. `GDRIVE_BACKUP_APPROVE_VOLUME_CREATION=1` is a narrow process-only authorization for one setup invocation; config files cannot persist it or forge setup authority, and `BACKUP_ASSUME_YES` never authorizes `diskutil apfs addVolume`.
- Reject overview/manual, scheduled, retry, mount-triggered, menu-bar-only, and unknown creation attempts before confirmation UI, privileged helpers, disk mutation, or copy. Pausing automatic backups does not block a visible setup action.
- Require every successful APFS run to be UUID-bound. Legacy path-only targets fail closed outside setup; setup validates the exact name, UUID, container, mount, device, media safety and required encryption before and after human confirmation, then atomically persists the complete resolved identity and nested destination.
- Rediscover the sole eligible source container and exact-name UUID inventory immediately before creation and, after administrator authorization, once more inside the privileged operation immediately before `addVolume`. Recover one valid exact-name volume that appeared earlier, while multiple eligible containers, duplicate requested-container records, multiple or malformed exact-name UUID records, and numeric-family names such as `GoogleDrive-Backup 1` fail closed without mutation or copy; matching names in unrelated containers do not affect the requested container.
- Reject nested APFS destinations with any existing symbolic-link component before creating directories, copying data, or persisting the resolved destination, including links that remain on the same volume.
- Keep the setup window's backup action on its distinct foreground trigger while overview and menu-bar starts remain manual. The routine never deletes, erases, repartitions, renames, or unmounts volumes.

## v2.4.5 - 2026-09-04

- Identify an external backup destination in the confirmation dialog by its physical disk name, decimal capacity, connection type, and logical volume name instead of showing an ambiguous macOS mount-path suffix.
- Count APFS physical stores without an out-of-range key-path probe, so that the same single-disk identity works on macOS 15 and newer releases.
- Keep UUIDs, serial numbers, BSD device identifiers, and mount paths out of that user-facing identity while preserving exact UUID/device revalidation before and after confirmation.
- Show transferred bytes and speed—or increasing aggregate checked/listed counters—while rclone works on an area with no trustworthy byte total, instead of calling that active work “Preparing”.
- Label destination free space explicitly as capacity rather than implying that it is backup progress.
- Publish transient progress and run-state updates through private, unpredictable sibling files before each atomic replacement.
- Add one quiet recovery confirmation after a resolved automatic backup issue while keeping routine successful automatic backups opt-in and silent.

## v2.4.4 - 2026-08-01

- Automatic retries now replace the stale waiting alert with a truthful running state.
- The overview and menu bar show private, per-phase progress without opening a foreground window.
- Progress is explicitly current-phase progress; scheduled and retry runs remain passive in full-screen Spaces.
- Restore accountless/guest SMB remounting without Keychain lookup or UI while leaving authenticated SMB behavior unchanged.
- Limit delayed success cleanup to issue origins older than or equal to that success, so it can never erase a newer persistent same-profile failure alert.
- Keep unknown-total progress indeterminate, remove stale or invented percentages, and show completion only after durable terminal status publication.

## v2.4.3 - 2026-07-30

- Mount a configured SMB backup target through a bounded native NetFS helper before scheduled work starts, using the Finder-saved password only in memory and explicitly prohibiting Finder, AppleScript, Keychain, or mount authentication UI during automatic runs.
- Preserve the authenticated SMB account when setup learns a mounted share, discard any password from legacy mount metadata, and provide an explicit one-time Keychain authorization mode for unattended access.
- Replace the preliminary “retry in 30 minutes” alert after a failed automatic retry has been accepted by macOS, while retaining the final alert until a newer automatic success or a human dismissal and healing an interrupted cleanup after controller restart.
- Make NAS mount tests inject every UI-capable executable and verify the native helper path, preventing test hostnames from reaching Finder.

## v2.4.2 - 2026-07-29

- Remove the protected time-sensitive notification entitlement from ad-hoc, unsigned-package, and Developer ID build paths until a provisioning profile can authorize it; this fixes the macOS `OS_REASON_EXEC` launch rejection introduced in v2.4.1.
- Keep automatic-backup failures audible and compatible with macOS's persistent alert style, and elevate them to time-sensitive only when the running app can prove that its signature actually carries the authorized entitlement.
- Add a real isolated menu-bar launch smoke test and a mutated-package regression test, so both macOS execution and release verification reject the exact launch-blocking v2.4.1 failure shape.

## v2.4.1 - 2026-07-29

- Mark automatic-backup failure alerts as time-sensitive and preserve the required signing entitlement across source installs, local builds, and release packages, so Focus may present the warning without the app taking focus or opening a window.
- Treat the fail-closed `destination_unreadable` NAS codec preflight as eligible for the same single delayed automatic retry as transient mount-readiness failures, while continuing to exclude permissions, damaged manifests, name collisions, unsupported tooling, and unclassified exit codes.
- Tell the user when this transient NAS read failure will be retried and verify the notification entitlement in both isolated app builds and packaged release artifacts.

## v2.4.0 - 2026-07-29

- Offer a previously unknown directly attached physical disk once per attachment through a passive macOS notification, without opening a window, taking focus, writing, formatting, changing settings, or starting a backup; setup begins only after an explicit, revalidated action and preserves the active NAS target and schedule until Save.
- Group multi-volume media by physical disk, suppress the unknown-media notice when any named profile already retains one of its volume UUIDs, rebuild attachment state after a controller restart, keep one banner usable when a sibling volume leaves, remember a human dismissal across controller restarts in the same boot session, and clear that state after the disk fully disconnects.
- Request notification permission only after an explicit setup save, retry one transient unknown-media delivery failure, and bind asynchronous delivery state to both disk and volume identity so reused macOS disk numbers cannot suppress another attachment.
- Wait for an automatically mounted NAS to become both verified and writable instead of failing in the short post-mount readiness interval.
- Retry one transient scheduled NAS mount/readiness failure after 30 minutes, revalidate it immediately before launch, retain it across sleep for up to 24 hours, restart the controller after a crash, and issue a distinct alert if that retry also fails.
- Keep delivered automatic-failure alerts associated with their profile and remove them only after manual dismissal by the user or a newer successful automatic backup; document macOS's required **Persistent** notification style.
- Preserve the new retry trigger and safe NAS readiness reasons in the status UI and privacy-filtered diagnostics.
- Reuse one in-process setup window from the persistent controller, present it before network discovery, and drain command output without deadlocking or spawning extra Dock instances.
- Retry transient NAS codec-manifest read errors and report a persistently unreadable destination separately from a genuinely invalid manifest.
- Keep passive mount confirmations visible and clickable without activating the app or entering another application's fullscreen Space.
- Bind external APFS targets to their stable volume UUID, resolve the current macOS mount path before every run, and reject same-name or swapped volumes before Drive access.
- Refuse APFS path traversal, symbolic-link escapes, nested foreign file systems, post-confirmation swaps, and retention operations whose UUID or device identity changes.
- Identify an automatically created APFS volume by the one new UUID in its container instead of assuming an unsuffixed `/Volumes` name, and atomically replace stale or empty saved identity fields.
- Keep legacy path-only profiles available for manual and scheduled runs but prevent them from starting a mount backup until a human explicitly identifies the volume; opening or saving unrelated setup settings never binds whichever same-name volume currently owns that path.
- Let source-based upgrades verify and atomically persist a caller-supplied APFS path, name, and UUID in both the legacy config and active profile instead of inferring identity from a volume name.
- Open the visible overview when Finder reopens the already-running menu bar controller.
- Let saved launchd schedules run unattended after the backup engine verifies the exact configured destination.
- Link every required application source file from the source installer so local upgrades build successfully.
- Add opt-out macOS notifications for failed automatic backups and daily 20:00 runs still missing at 21:00, deduplicated per profile and run.
- Keep the menu bar warning active until a newer successful backup clears the reported problem.
- Read each durable run summary once per refresh so the overview and notification watchdog evaluate the same state.
- Preserve a per-profile last-success timestamp so later manual failures cannot make an already successful daily run appear missing.
- Run scheduled, mount-triggered, and menu-bar-only backups without opening a progress window.
- Keep progress and passive confirmation windows out of unrelated fullscreen Spaces, avoid forced front ordering, and never reshow hidden progress at completion.
- Allow foreground confirmation only when a manual backup was requested from an already visible app window.
- Apply a reversible, manifest-backed NAS name codec for exact `.bin` directories and reserved codec-like names that some network file systems reject.
- Present codec-backed files and folders under their original logical names in restore browsing, and reject malformed or mismatched physical layers instead of guessing.
- Detect exact-name Google Drive collisions that rclone would otherwise ignore, including duplicates at a Drive root, preserve every verified provider ID in a separate internal archive, and fail the run if that archive is incomplete.
- Render app icons into fixed-size bitmap targets so Retina build hosts produce valid `AppIcon.icns` and asset catalogs, covered by an isolated signed Universal 2 build test.
- Document that each run checks the source while transferring only new or changed files, and that Google Docs, Sheets, and Slides are Office exports rather than copies of Drive's native revision history.

## v2.3.2 - 2026-07-12

- Let the persistent overview controller yield its Dock presence after a successful manual start so the foreground progress window is the app’s only Dock icon.
- Keep the overview’s Dock icon when process launch fails, preserving a reliable retry path.

## v2.3.1 - 2026-07-12

- Keep **Check backup** visibly busy while its no-copy process runs and prevent duplicate starts.
- Show a localized success, unavailable-destination, or generic failure result when the check finishes instead of leaving the setup window at “started.”
- Restore setup actions after every terminal check result while keeping concurrent system checks and real backup starts mutually exclusive.

## v2.3.0 - 2026-07-12

- Require a configured NAS destination to be an actual SMB, AFP, or NFS mount before setup reports it ready or the backup engine writes anything.
- Revalidate the network mount before each copy phase so a disconnected share cannot fall back to a plain folder on the internal disk.
- Add a localized menu-bar action to pause or resume schedule and mount-triggered backups without changing the saved schedule or blocking manual backups.
- Keep paused automatic attempts silent, preserve the last real backup result, and reject damaged pause settings instead of silently enabling automation.

## v2.2.2 - 2026-07-12

- Show preparation and disable repeated clicks before macOS can block process launch on a first network-volume permission prompt.
- Bring the existing Tiger progress window and its Dock presence forward exactly once for manual backups while scheduled and mount-triggered runs stay passive.
- Add a localized, keyboard- and VoiceOver-accessible **Cancel backup…** action to the progress window.
- Cancel only after the sentinel and versioned run state agree on one live process-group leader, then send `TERM` to that isolated backup group so `rclone` children stop and the durable result becomes `cancelled`.

## v2.2.1 - 2026-07-12

- Identify menu bar and overview destinations by device type, NAS host, and backup folder instead of relying on an ambiguous mounted-volume path.
- Keep meaningful profile names while removing the generic `Default` prefix from the compact destination summary.
- Parse NAS URLs into credential-free display components so legacy SMB user names and passwords can never enter the status UI.

## v2.2.0 - 2026-07-12

- Add an optional `rclone crypt` mode that encrypts contents plus file and directory names while keeping all passwords inside rclone.
- Require one safe named crypt remote bound to the exact physical app destination, with password, salt, standard name encryption, directory encryption, content encryption, and mapping output disabled.
- Revalidate the crypt policy and physical ciphertext tree before each copy, rejecting source-remote reuse, symbolic links, nested file systems, path redirection, and weakened settings.
- Send live backups and `--backup-dir` version deltas through the same crypt remote without creating cleartext backup-area directories.
- Thin encrypted history with the existing hourly/daily/weekly cadence, merging sparse deltas first and then moving only the deterministically mapped ciphertext directory to recoverable Trash or quarantine.
- Browse current and sparse historical encrypted copies through logical names and publish a restore only after `rclone cryptcheck` plus a local SHA-256 succeeds.
- Replace the APFS-only checkbox with one native encryption-mode popup and a conditional crypt-remote field, localized and accessible in all seven languages.
- Verify crypt readiness in the setup health check without returning remote names, command output, or key material in diagnostics.
- Make every compiled test recipe fail fast so compiler or test failures can no longer be reported as a successful suite.

## v2.1.0 - 2026-07-12

- Add a manual **Check for Updates…** action to the application menu and menu bar in all seven supported languages.
- Compare stable numeric versions from the exact official GitHub API endpoint without cookies, credentials, cached responses, or authentication tokens.
- Reject foreign redirects, malformed and prerelease versions, oversized bodies, non-200 responses, and untrusted release URLs.
- Open only the hard-coded official GitHub releases page after a second explicit user action.
- Never check on launch, download a package, start macOS Installer, or install an update automatically.

## v2.0.0 - 2026-07-12

- Add native create, rename, switch, and delete controls for named backup profiles in setup.
- Copy the existing configuration into a private default profile without modifying the legacy source file.
- Keep each profile’s destination, schedule, encryption policy, remote, and last-run summary separate while identifying the active profile in the overview and menu bar.
- Block profile switches when setup has unsaved edits unless the user explicitly discards them, and roll back activation if launchd cannot apply the new schedule.
- Resolve profiles through path-safe generated IDs, reject traversal and symbolic links for the config directory, config files, and active-pointer file, and keep files owner-only.
- Let the backup engine source exactly the active trusted profile while preserving explicit config overrides and the legacy fallback.

## v1.9.0 - 2026-07-12

- Add one native diagnostics window to the application menu and menu bar for tools, Google Drive, destination, schedule, services, backup engine, and the last run.
- Run diagnostics asynchronously with explicit ready, failed, blocked, unknown, and refreshing states in all seven supported languages.
- Generate a stable allowlist-only support report without paths, URLs, credentials, remote names, file names, provider output, or log contents.
- Copy or save the report only after an explicit user action; never send it automatically and save it with owner-only permissions.
- Keep the diagnostics window at the normal macOS window level so other applications can cover it, and leave the menu bar controller running when it closes.

## v1.8.0 - 2026-07-12

- Add a native restore browser reachable from both the overview and menu bar.
- Merge the live backup with sparse retained version trees so deleted or replaced files remain discoverable without presenting them as full snapshots.
- List the current copy and every actually available older copy newest-first, with localized dates and sizes.
- Restore only to a user-selected folder outside the backup tree, preserve existing files with a new name, and never overwrite silently.
- Verify the source before and after copying and compare the restored file with SHA-256 before publishing it under its final name.
- Reject traversal, symbolic links, sources outside the configured backup, retired quarantine data, and destinations inside the independent backup.
- Provide native keyboard and VoiceOver navigation, explicit loading and empty states, and a Finder reveal action after verified recovery.

## v1.7.0 - 2026-07-11

- Add an in-app system check for required tools, the configured Google Drive remote, and the exact local or NAS destination.
- Keep setup checks asynchronous, accessible, localized, and free of command output or credentials.
- Detect a NAS share that disappears during copying, stop later copy phases, and show a specific reconnect-and-retry explanation.
- Expand and reflow the setup window so the system check, destination controls, schedule, and actions never overlap.
- Preserve the manual-start contract: a launched backup closes setup exactly once, while a process launch failure stays explicitly retryable.

## v1.6.1 - 2026-07-11

- Show the real progress window as soon as a manual run owns the backup lock, before slow remote and destination checks.
- Close the setup window after a successful launch, block duplicate clicks there, and keep it open when the process cannot be launched.
- Treat transiently missing or partial run-state reads as pending while the verified owner process is alive, preventing premature failure screens.
- Serialize NAS writes and disable multi-threaded destination streams for compatibility with SMB servers that reject concurrent file and directory creation.
- Classify destination permission failures without persisting private paths and show a specific localized permissions explanation.
- Open setup only on a first package installation; upgrades keep the single refreshed menu bar controller instead of launching a duplicate overview process.

## v1.6.0 - 2026-07-11

> Historical note: this internal milestone was never tagged or released. The
> app metadata moved directly from v1.5.0/build 10 to v1.6.1/build 12, which
> incorporated these changes.

- Add a persistent overview and menu bar controller showing the last verified run, next configured schedule, exact destination, and destination capacity.
- Replace the broad launchd `StartOnMount` job with exact-volume mount handling in the menu bar controller, including duplicate-event debouncing.
- Stop `Backup now` and `Check backup` from silently saving edited setup values; unsaved changes now block the action with a localized explanation.
- Show the full resolved external-disk or NAS destination in setup and preserve it for VoiceOver and pointer users even when visually truncated.
- Persist a private, atomic last-run summary with explicit running, success, failure, and cancellation state for the overview.
- Use native close, minimize, buttons, text, progress, keyboard focus, VoiceOver announcements, and Reduce Motion behavior while retaining the Tiger visual signature.

- Preserve overwritten destination files in timestamped `.gdrive-versions` trees by default, with an explicit opt-out.
- Thin successful version runs with a Time Machine-like hourly, daily, and weekly cadence; coalesce sparse per-file deltas before moving retired runs to recoverable Trash or retriable quarantine.
- Let ordinary progress windows fall behind other applications while keeping confirmation prompts visible.
- Add a fail-closed mode for already unlocked encrypted APFS destinations without storing volume passphrases.
- Make the NAS mount-trigger opt-in effective and return a failure status when manual or scheduled backups have no available target.
- Add hermetic backup-control, rclone command, NAS parsing, config roundtrip, release metadata, and package payload tests.
- Split configuration and localization responsibilities out of the AppKit entry point.
- Harden config roundtrips for Unicode and shell quoting, preserve unreadable files, and enforce owner-only permissions.
- Surface schedule serialization and launchctl failures instead of reporting a false successful save.
- Add macOS GitHub Actions for tests, app linking, package construction, payload verification, and unsigned artifact upload.
- Add optional Developer ID application/installer signing and Apple notarization support without storing credentials in the repository.
- Build and verify Universal 2 app binaries with an explicit macOS 13 deployment target.
- Clarify that the Tiger name describes the visual style and that the app requires macOS 13 or later.

## v1.5.0 - 2026-05-24

- Add a reproducible macOS `.pkg` build for GitHub releases.
- Install the app into `/Applications`, the backup script into `/usr/local/bin`, and the mount LaunchAgent for the currently logged-in user.
- Open the setup UI after package installation so users can choose language, external disk, NAS, and schedule settings.
- Add release-download instructions and maintainer packaging docs.

## v1.4.0 - 2026-05-24

- Make the setup app a normal macOS app with its own menu bar.
- Add About and Settings menu items.
- Add in-app language switching.
- Complete setup UI translations for Deutsch, English, Français, Español, 日本語, 粵語, and 한국어.

## v1.3.1 - 2026-05-24

- Add explicit modern bundle icon metadata so Finder and LaunchServices reliably show the app icon in `/Applications`.

## v1.3.0 - 2026-05-24

- Install the helper app into the global `/Applications` folder by default.
- Keep external-disk mount backups active even when NAS backups are configured.
- Treat the setup UI target as the app/scheduled backup target, so external disks and NAS can be used in parallel.

## v1.2.2 - 2026-05-24

- Rename the setup UI `Dry Run` action to `Backup prüfen` / `Check backup`.
- Clarify that the check is optional and does not copy files.

## v1.2.1 - 2026-05-24

- Detect SMB, AFP, and NFS mounts directly from macOS `mount` output so already mounted NAS shares appear reliably in the setup UI.
- Auto-select a matching mounted NAS share after Finder mounts it.
- Avoid guessing a bogus mount path from server-only URLs such as `smb://nas.local`.

## v1.2.0 - 2026-05-24

- Add a Tiger-style setup window for external disk and NAS backup targets.
- Let users select already mounted NAS shares from `/Volumes`.
- Add best-effort Bonjour discovery for SMB and AFP services.
- Add setup UI actions for saving config, opening NAS URLs in Finder, dry-runs, and starting a backup now.
- Add optional NAS schedules: manual, login, hourly, or daily at 20:00.
- Prevent NAS configs from running on every unrelated `StartOnMount` event by default.

## v1.1.1 - 2026-05-24

- Make the backup script robust when launchd starts it without an explicit `HOME` environment variable.

## v1.1.0 - 2026-05-24

- Add NAS destination support with `GDRIVE_BACKUP_TARGET=nas`.
- Support mounted SMB, AFP, or NFS shares under `/Volumes`.
- Add optional `GDRIVE_BACKUP_NAS_URL` so macOS can mount a share through Finder/Keychain.
- Keep NAS credentials out of the project config.
- Fix language detection on the system Bash version shipped with macOS.

## v1.0.0 - 2026-05-24

- Initial open-source release.
- Back up My Drive, Shared Drives, and Shared with me through read-only `rclone copy`.
- Export Google Docs, Sheets, and Slides as Office files.
- Add launchd `StartOnMount`, lockfile protection, logs, dry-run mode, and Tiger-style progress helper.
