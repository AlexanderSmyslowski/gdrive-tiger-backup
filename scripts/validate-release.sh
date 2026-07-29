#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INFO_PLIST="$ROOT/macos/GDriveBackupTiger/Info.plist"

if [[ $# -ne 1 || ! "$1" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  printf 'Usage: %s vMAJOR.MINOR.PATCH\n' "$0" >&2
  exit 64
fi

tag="$1"
version="${tag#v}"
app_version="$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$INFO_PLIST")"
build_number="$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$INFO_PLIST")"

if [[ "$app_version" != "$version" ]]; then
  printf 'Release tag %s does not match app version %s.\n' "$tag" "$app_version" >&2
  exit 1
fi

if [[ ! "$build_number" =~ ^[1-9][0-9]*$ ]]; then
  printf 'App build number is not a positive integer: %s\n' "$build_number" >&2
  exit 1
fi

if ! /usr/bin/grep -Eq "^## ${tag} - [0-9]{4}-[0-9]{2}-[0-9]{2}$" \
  "$ROOT/CHANGELOG.md"; then
  printf 'CHANGELOG.md has no dated section for %s.\n' "$tag" >&2
  exit 1
fi

if /usr/bin/awk '
  $0 == "## Unreleased" { in_unreleased = 1; next }
  in_unreleased && /^## / { exit }
  in_unreleased && /^- / { found = 1 }
  END { exit(found ? 0 : 1) }
' "$ROOT/CHANGELOG.md"; then
  printf 'CHANGELOG.md still contains entries under Unreleased.\n' >&2
  exit 1
fi

if ! /usr/bin/grep -Fq "Current release: \`${tag}\`" "$ROOT/README.md"; then
  printf 'README.md does not identify %s as the current release.\n' "$tag" >&2
  exit 1
fi

if ! /usr/bin/grep -Fq "GDrive-Backup-Tiger-${version}.pkg" "$ROOT/README.md"; then
  printf 'README.md does not name the %s installer.\n' "$version" >&2
  exit 1
fi

printf 'Release metadata is consistent: %s (build %s).\n' "$tag" "$build_number"
