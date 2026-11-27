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

- [~] Updater in the app (PR #21): daily check (can be turned off), offer,
  verified download from the official release (SHA-256, payload), install
  through the macOS administrator prompt, never during a running backup.
- [ ] Release as v2.9.0 and install it once by hand on the maintainer's Mac.
- [ ] First real run of the updater with the following release (v2.9.1 or
  later): offer, password prompt, restart, confirmation. Fix whatever breaks
  before anyone else relies on it.

## 2. Apple Developer ID (maintainer decision, about 99 USD per year)

- [ ] Enroll in the Apple Developer Program.
- [ ] Create `Developer ID Application` and `Developer ID Installer`
  certificates and a notarization profile (see `docs/signing-and-release.md`).
- [ ] Switch the release workflow to signed and notarized packages; remove the
  Gatekeeper instructions from the README only then.
- [ ] Set `GDTUpdateTrustedTeamID` in `UpdateSupport.m`, so the updater accepts
  only packages signed by the project's team.

## 3. First run on a Mac that is not the maintainer's

- [ ] Fresh macOS user account or virtual machine, no Homebrew, no rclone:
  install the package, connect Google, choose a disk or NAS, run a backup,
  restore a file, all without help and without the Terminal. Write down every
  stumble and fix it.
- [ ] Repeat on the oldest supported macOS (13 Ventura) and on Intel if
  possible.
- [ ] Own Google OAuth client ID instead of rclone's shared one, so many users
  do not run into its rate limits. Read access to Drive is a sensitive scope:
  plan time for Google's verification (privacy policy page, app description,
  possibly a security review).

## 4. Shop window

- [ ] Short README: the core message, three screenshots, a 30-second GIF of
  setup and the overview, then the quick start; move the long technical
  reference (engine, safety rules, release history) into `docs/`.
- [ ] Social preview image for links (GitHub repository settings).
- [ ] Simple landing page via GitHub Pages with the same message and download.
- [ ] Reconsider the name: "Tiger" refers to the visual style but suggests an
  old Mac OS X version; decide whether to keep it before the launch.
- [ ] Issue templates (bug report with the diagnostics report, feature
  request), `CONTRIBUTING.md`, `SECURITY.md`.

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
