# Plan: from working app to an app other people use

Status: agreed 2026-11-27 after v2.8.0. Status markers: `[ ]` open, `[~]` in
progress, `[x]` done. Update this file when a step changes; it is the single
place for this plan.

## Where we stand (2026-11-27)

- Technically solid: retained versions, verified restore, catch-up of missed
  runs, NAS watchdogs, honest status, setup without the Terminal, seven
  languages, about 1,400 automated checks, Linux engine tests in CI.
- Nobody outside the project uses it yet: 0 stars, a handful of downloads per
  release, almost no visitors.
- The core message: **Google Drive syncs your files. This app backs them up.**
  Drive for desktop mirrors deletions and ransomware damage; few simple Mac
  tools keep an independent, versioned copy on a disk or NAS.

## Rule

No public promotion before steps 1–3 are done. The first users decide the
reputation; a failed first setup or a frightening Gatekeeper warning costs more
than a late launch.

## 1. Automatic updates

- [x] Updater in the app (PR #21, released in v2.9.0): daily check (can be turned off), offer,
  verified download from the official release (SHA-256, payload), install
  through the macOS administrator prompt, never during a running backup.
- [x] Release as v2.9.0 and install it once by hand on the maintainer's Mac.
- [x] First real run of the updater (2026-11-27, v2.9.0 to v2.9.1): offer,
  verified download, password prompt, installation and restart worked. Found:
  the restarted app missed the result written two seconds later, so the
  confirmation was skipped and the download stayed (fixed afterwards; confirm
  with the next update). The macOS prompt names "bash" and warns about
  malware, because the script is unsigned; replace it with a prompt in the
  app's name once the project has a Developer ID (step 2).
- [~] Until releases are signed, every update looks like a new app to macOS:
  it asks again for access to removable volumes and re-registers the
  background items. Once (2026-11-27, update to v2.8.0) it also blocked the
  first hourly schedule start ("Launch Constraint Violation"). The installer
  now re-registers the schedule agent too (confirmed working in the update to
  v2.9.1); check after the next hourly start that none is blocked. Only step 2
  removes the cause.

## 2. Apple Developer ID (maintainer decision, about 99 USD per year)

More urgent since the updater: without a stable signature every automatic
update costs the user permission prompts and can block a scheduled start.

- [~] Enroll in the Apple Developer Program (paid 2026-11-27; Apple's
  identity verification is pending).
- [ ] Create `Developer ID Application` and `Developer ID Installer`
  certificates and a notarization profile (see `docs/signing-and-release.md`).
- [ ] Switch the release workflow to signed and notarized packages; remove the
  Gatekeeper instructions from the README only then.
- [ ] Set `GDTUpdateTrustedTeamID` in `UpdateSupport.m`, so the updater accepts
  only packages signed by the project's team.

## 3. First run on a Mac that is not the maintainer's

- [ ] Fresh macOS user account or virtual machine, no Homebrew, no rclone
  (checklist: `docs/fresh-mac-test.md`):
  install the package, connect Google, choose a disk or NAS, run a backup,
  restore a file, all without help and without the Terminal. Write down every
  stumble and fix it.
- [ ] Repeat on the oldest supported macOS (13 Ventura) and on Intel if
  possible.
- [~] Own Google OAuth client instead of rclone's shared one, which Google is
  retiring during 2026. Decided 2026-11-28: each user creates their own client
  with the app's assistant (PR #29, v2.10.0) instead of one project client,
  because read access to Drive is a restricted scope whose verification needs
  a yearly paid security assessment, and an embedded secret would be public in
  this open-source app. Open: click the assistant through once with a private
  Gmail account (audience External, app published) in the fresh-Mac test.

## 4. Shop window

- [x] Short README with the core message, overview screenshots (neutral demo
  data), why/what, quick start; the long reference moved to
  `docs/reference.md`.
- [ ] A 30-second GIF of setup and the first backup (needs a real recording on
  a test account, see step 3).
- [~] Social preview image: `docs/images/social-preview.png` exists; upload it
  in GitHub › Settings › General › Social preview (no API for this).
- [ ] Simple landing page via GitHub Pages with the same message and download.
- [ ] Reconsider the name: "Tiger" refers to the visual style but suggests an
  old Mac OS X version; decide whether to keep it before the launch.
- [x] Issue templates (bug report with the diagnostics report, feature
  request), `CONTRIBUTING.md`, `SECURITY.md`.
- [ ] Turn on private vulnerability reporting in the repository settings, so
  the link in `SECURITY.md` works.

## 5. Launch

- [ ] "Show HN" on Hacker News.
- [ ] Reddit: r/macapps, r/DataHoarder, r/synology or r/selfhosted (NAS).
- [ ] Listings: AlternativeTo, MacUpdate.
- [ ] German Mac sites: Mac & i (heise), iFun, Macwelt.
- [ ] rclone community: wiki entry and forum post
  (`docs/rclone-community-submission.md`).
- [ ] Homebrew cask once releases are signed.
- [ ] Answer every issue and comment in the first weeks quickly.

## 6. Later

- [ ] Linux edition for Omarchy (`docs/linux-omarchy-plan.md`), which reaches a
  second audience that likes trying new tools.
- [ ] Local MCP server and Codex plugin (same document, part B).

## Decisions for the maintainer

- Apple Developer Program enrollment (step 2).
- Own Google OAuth client and its verification (step 3).
- Keep or change the name (step 4).
- Launch date, once steps 1–3 are done.
