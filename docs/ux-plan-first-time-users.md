# UX plan: usable by first-time, non-technical users

Source: a walkthrough of the v2.6.0 windows (overview, setup, diagnostics,
restore, menu bar) and the README from the point of view of a non-technical
user, on 2026-11-16. Each item lists what the user sees today and the target.
Status: `[ ]` open, `[x]` done, `[~]` partly done (see note).

## A. Trust in the overview

- [x] **A1 Implausible free space.** A NAS share with a Time Machine size limit
  reports the quota, not the disk, so the overview showed "623.9 GB free of
  623.9 GB" right after a successful backup. Target: when the destination
  reports no used space although a backup exists there, show "Not reliably
  measurable on this share" instead of numbers.
- [x] **A2 Destination in plain language.** "NAS / Network ·
  host.local · share/folder" is truncated in the middle and exposes host
  names. Target: "Network drive (NAS) · GoogleDrive-Backup"; the technical
  address moves into the tooltip.
- [x] **A3 Last backup as one sentence.** "Last backup / Backup completed. /
  15.11.2026, 21:38" repeats itself. Target: relative wording consistent with
  the menu bar ("Yesterday, 21:38").
- [x] **A4 One-run destination picker only when it helps.** With a single
  destination the "Save this backup to" row duplicates the destination.
  Target: hide the row unless there is more than one choice.

## B. First start

- [x] **B1 Clear call to action.** A new user sees "?", "No backup yet", a
  greyed-out picker and a pre-filled "External disk" they never chose.
  Target: "Not set up yet" plus a prominent "Set up backup" button.
- [x] **B2 No "no longer available" for new users.** The one-run picker says
  the chosen destination is "no longer uniquely available" although nothing was
  ever chosen. Target: no such message before the first setup.

## C. Setup window

- [x] **C1 Plain-language labels.** Replace "App/schedule destination",
  "Exact destination", "Mounted NAS", "Mount point", "Tools" with everyday
  wording and short help texts.
- [~] **C2 Advanced section.** Done: all NAS fields are hidden unless the
  destination is a NAS, and each technical field has a plain-language help
  text. Open: collapsing URL and mount point behind "Advanced" for NAS users
  needs a layout rework of the fixed-frame setup window. Technical NAS fields (URL, mount point, Bonjour
  search, exact path) are collapsed behind "Advanced" once a share is detected.
- [x] **C3 Check automatically.** Run the system check when the window opens
  instead of showing "Not checked yet" four times.
- [x] **C4 Clear buttons.** Distinguish "Check setup" from "Test backup" with
  help texts; explain what "Save" does.
- [x] **C5 Explain encryption.** One sentence next to "Encryption: None".

## D. Restore and diagnostics

- [x] **D1 Localized Google folder names.** "My Drive", "Shared Drives",
  "Shared with me" appear in English in every language. Target: Google's own
  localized names for display only; paths stay unchanged.
- [x] **D2 Empty-state hint.** The version column is blank and all buttons are
  disabled. Target: "Select a file on the left to see its versions."
- [x] **D3 Neutral loading state in diagnostics.** While checks run, rows show
  red crosses and "Check failed". Target: neutral "Checking…" until results
  arrive.

## E. Consistency

- [x] **E1 Ellipsis.** Use "…" everywhere (e.g. "Settings ...").

## F. Getting started without the Terminal

- [x] **F1 Connect Google Drive from the app.** Today users must run
  `rclone config` in the Terminal and name the remote exactly `gdrive`.
  Target: a "Connect Google Drive" button that creates the read-only remote and
  opens Google's sign-in in the browser.
- [x] **F2 Missing tools explained in the app.** When rclone, flock or jq are
  missing, show what is missing and a copyable install command instead of a
  generic failure.
- [ ] **F3 Ship the tools with the installer** so Homebrew is not required.
  Open, planned as its own release: download pinned rclone and jq release
  binaries for arm64 and x86_64 in CI, verify their published checksums,
  `lipo` them into universal binaries, build `flock` from pinned source (or
  replace it in the engine with a `mkdir`-based lock), install them under
  `/usr/local/libexec/gdrive-tiger-backup/`, prefer them in the engine's
  `PATH`, and add their licenses (MIT, MIT, ISC) to the package.

## G. Documentation and installer

- [x] **G1 Short quick start** at the top of the README (three steps) and a
  German quick start.
- [x] **G2 Gatekeeper steps up front** next to the download link.
- [ ] **G3 Signed and notarized installer.** Needs an Apple Developer ID
  (maintainer decision, paid account); not solvable in code. Until then the
  quick start explains the Gatekeeper steps next to the download.
