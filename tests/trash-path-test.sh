#!/bin/bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_HOME="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/gdrive-trash-test.XXXXXX")"
SOURCE_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/gdrive-trash-source.XXXXXX")"
SOURCE_PATH="$SOURCE_ROOT/recoverable.txt"
printf 'recover me\n' >"$SOURCE_PATH"

HOME="$TEST_HOME" GDRIVE_FORCE_TRASH_FALLBACK=1 \
  "$ROOT/scripts/trash-path.sh" "$SOURCE_PATH"

shopt -s nullglob
trashed_paths=("$TEST_HOME/.Trash/recoverable.txt."*)
if [[ -e "$SOURCE_PATH" || "${#trashed_paths[@]}" != "1" ]]; then
  printf '%s\n' 'not ok - macOS 13/14 fallback moves one item into the user Trash'
  exit 1
fi
if [[ "$(<"${trashed_paths[0]}")" != "recover me" ]]; then
  printf '%s\n' 'not ok - fallback Trash item retains its contents'
  exit 1
fi

printf '%s\n' 'ok - macOS 13/14 fallback moves one item into the user Trash'
