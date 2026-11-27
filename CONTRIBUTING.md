# Contributing

Thanks for your interest! Bug reports, ideas and pull requests are welcome.

## Reporting problems

Use the issue templates. For bugs, the app's **safe diagnostics report**
(menu bar icon › Diagnostics › Copy safe report) helps most and contains no
paths, account names or file names. Security problems go through
[private reporting](SECURITY.md).

## Building and testing

Requirements: macOS 13 or later with the Xcode command line tools, plus
`rclone`, `jq` and `shellcheck` (for example from Homebrew).

```bash
make build   # builds the app into build/
make test    # runs the full test suite (engine, app, packaging)
```

The backup engine is `bin/backup-google-drive.sh` with platform files in
`lib/`; the app is Objective-C/AppKit in `macos/GDriveBackupTiger/`. The
[technical reference](docs/reference.md) explains how the parts work together.

## Pull requests

- Keep each pull request focused on one change and describe why it is needed.
- Add or update tests; `make test` must pass.
- Never commit real names of NAS devices, shares, accounts, paths or file
  names. Tests and docs use neutral examples such as `nas-example` and
  `/Volumes/backup-share`.
- Safety first: a change must not let the engine write to an unverified
  destination, delete data, or hide a failed backup.
- User-facing text exists in seven languages (`Localization.m`); add new
  strings to all of them.
