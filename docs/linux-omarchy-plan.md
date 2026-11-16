# Plan: Linux edition for Omarchy and a local MCP server for AI assistants

Status: proposal, not started. Written 2026-11-16 after v2.7.0.

## Goal

Bring the backup engine to Linux without a graphical app, in the style of
Omarchy (Arch Linux, Hyprland, Waybar, keyboard- and terminal-first). The value
for technical users is safety by default, not hiding the terminal:
retained versions instead of silent overwrites, verified restore, catch-up of
missed runs, watchdogs for vanished NAS mounts and stalled copies, and honest
status.

Non-goals: a GTK/Qt app, a Linux port of the macOS UI, inclusion in Omarchy
itself (that is the Omarchy maintainers' decision).

## Starting point

- `bin/backup-google-drive.sh` has 115 functions; 31 call macOS-only tools or
  paths (`diskutil`, `plutil`, `ioreg`, `osascript`, `open`, `stat -f`,
  `/Volumes`). Most of them belong to the APFS destination setup and identity
  checks, plist-based state, interactive confirmation and mount discovery.
- rclone and jq are cross-platform. The run lock already works without `flock`
  but Linux has `flock(1)` in util-linux anyway.
- The macOS app (about 16,000 lines of Objective-C/AppKit) is not portable and
  is out of scope.

## Phases

### 1. Split the engine into core and platform parts (also benefits macOS)

- Move platform-specific functions behind a small interface, e.g.
  `platform_mount_nas`, `platform_destination_identity`,
  `platform_confirm`, `platform_free_space`, `platform_notify`, in
  `lib/platform-macos.sh` and `lib/platform-linux.sh`, selected by `uname`.
- Keep the copy, versioning, retention, catch-up and watchdog logic in the
  shared core.
- Replace plist reads in the core with the existing key=value config format.
- Acceptance: the full macOS test suite stays green without behavior changes.

### 2. Linux platform layer

- Destinations: any mounted directory (ext4, btrfs, xfs) identified by
  filesystem UUID from `findmnt`/`lsblk` instead of the APFS volume UUID; NAS
  via an existing `cifs` mount or a systemd `.mount` unit, never by storing a
  password in the config.
- Confirmation prompts become config values; unattended runs never prompt.
- Free space via `df --output`, identity via `stat -c`.
- Acceptance: the engine test suite runs on Linux in CI (GitHub Actions
  `ubuntu-latest`, plus an Arch container) with the same fakes as on macOS.

### 3. Scheduling and status in the Omarchy style

- systemd user units: `gdrive-tiger-backup.service` and a `.timer` with
  `Persistent=true` (catch-up after the machine was off) and the existing
  window logic.
- `gdrive-tiger-backup status --json` for scripts and a Waybar custom module
  (icon plus "last backup 3 h ago", warning state on failure).
- Notifications through `notify-send` (shown by mako in Omarchy) for failures
  and recovery, same rules as on macOS.

### 4. Terminal UI

- `gdrive-tiger-backup` without arguments opens a small TUI: status, start
  backup, connect Google (`rclone config create … scope=drive.readonly`),
  choose destination, browse and restore versions.
- Implementation options: plain bash with `gum`, or a small Go binary. Decide
  after phase 1; prefer the option with the fewest runtime dependencies.

### 5. Packaging and documentation

- AUR package `gdrive-tiger-backup` (engine, units, Waybar snippet, man page).
- README section "Linux / Omarchy" with a three-step quick start and the
  Waybar module configuration.

## Effort and order (rough)

| Phase | Size | Notes |
| --- | --- | --- |
| 1 Engine split | medium | Highest risk; must not change macOS behavior |
| 2 Linux layer + CI | medium | Mostly destination identity and mounts |
| 3 systemd, Waybar, notifications | small | |
| 4 TUI | medium | Can start minimal (status + backup now + restore) |
| 5 AUR + docs | small | |

Phases 1–3 give a usable headless edition; 4 and 5 make it pleasant.

## Part B: local MCP server, packaged as a Codex plugin

Codex (app, CLI, VS Code) supports plugins that bundle skills, app
integrations and MCP servers, and plugin extensions add UI surfaces such as a
side panel. Codex runs on the user's Mac, so a local MCP server works without
a tunnel or cloud relay. The same server also works in Claude Code and Claude
Desktop.

- **Server** (`gdrive-tiger-backup mcp`, stdio):
  - read-only by default: status, last backup, next run, diagnostics summary
    (same privacy rules as the diagnostics report: no paths, file names,
    credentials or log contents);
  - opt-in tools: search versions of a file and restore it (with confirmation
    in the app), start a backup now.
- **Skill:** how to interpret backup states and which actions the agent may
  suggest or take.
- **Extension panel:** a small status view beside the conversation, in the
  style of the overview window. Depends on details of plugin extensions that
  still need to be confirmed from OpenAI's documentation (local execution,
  distribution, review).
- **Privacy:** anything the agent reads reaches the model provider, so the
  read-only, path-free mode stays the default.
- **Order:** after Linux phase 1, because both need the same clean status and
  diagnostics interface of the engine (`status --json`).

## Open decisions

- TUI technology (bash + gum or Go).
- Whether Linux gets the same version numbers as macOS or its own track.
- Who maintains the AUR package.
- Which assistant to target first for the MCP server (Codex plugin or Claude).
