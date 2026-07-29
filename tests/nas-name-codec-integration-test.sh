#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RCLONE_BIN="${RCLONE_BIN:-$(command -v rclone || true)}"
if [[ -z "$RCLONE_BIN" || ! -x "$RCLONE_BIN" ]]; then
  printf '%s\n' 'not ok - rclone is required for the NAS name codec integration test'
  exit 1
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/gdrive-nas-codec-test.XXXXXX")"
# Invoked through the EXIT trap below.
# shellcheck disable=SC2329
cleanup() {
  "$ROOT/scripts/trash-path.sh" "$WORK" >/dev/null 2>&1 || true
}
trap cleanup EXIT

SOURCE="$WORK/source"
DESTINATION="$WORK/backup/My Drive"
VERSIONS="$WORK/backup/.gdrive-versions/run-1/My Drive"
SHARED_SOURCE="$WORK/shared-source"
SHARED_DESTINATION="$WORK/backup/Shared Drives/__gdt0__Team (drive-1)"
SHARED_VERSIONS="$WORK/backup/.gdrive-versions/run-1/Shared Drives/__gdt0__Team (drive-1)"
REPORT="$WORK/combined.txt"
PREFIX="__gdt0__"
DOT_BIN_MARKER="__gdt0__dotbin_000"
DOT_BIN_UPPER_MARKER="__gdt0__dotbin_111"
MARKER_FILE="__gdt0__dotbin_000"
MARKER_DIRECTORY="__gdt0__marker-directory"
UPPERCASE_DIRECTORY="__GDT0__uppercase-directory"
# The literal ${1} belongs to rclone's replacement expression.
# shellcheck disable=SC2016
ESCAPE_TRANSFORM='all,regex=(?i)^(__gdt0__.*)$/__gdt0__${1}'
DOT_BIN_TRANSFORMS=(
  'dir,regex=^\.bin$/__gdt0__dotbin_000'
  'dir,regex=^\.biN$/__gdt0__dotbin_001'
  'dir,regex=^\.bIn$/__gdt0__dotbin_010'
  'dir,regex=^\.bIN$/__gdt0__dotbin_011'
  'dir,regex=^\.Bin$/__gdt0__dotbin_100'
  'dir,regex=^\.BiN$/__gdt0__dotbin_101'
  'dir,regex=^\.BIn$/__gdt0__dotbin_110'
  'dir,regex=^\.BIN$/__gdt0__dotbin_111'
)
CODEC_ARGS=(--name-transform "$ESCAPE_TRANSFORM")
for transform in "${DOT_BIN_TRANSFORMS[@]}"; do
  CODEC_ARGS+=(--name-transform "$transform")
done

mkdir -p "$SOURCE/.bin" "$SOURCE/case-variant/.BIN" "$SOURCE/nested/$MARKER_DIRECTORY" \
  "$SOURCE/$UPPERCASE_DIRECTORY" "$SHARED_SOURCE/.bin"
printf '%s\n' 'old tool' >"$SOURCE/.bin/tool"
printf '%s\n' 'old marker file' >"$SOURCE/$MARKER_FILE"
printf '%s\n' 'old marker directory' >"$SOURCE/nested/$MARKER_DIRECTORY/file"
printf '%s\n' 'uppercase marker directory' >"$SOURCE/$UPPERCASE_DIRECTORY/file"
printf '%s\n' 'old shared tool' >"$SHARED_SOURCE/.bin/shared-tool"

"$RCLONE_BIN" copy "$SOURCE" "$DESTINATION" \
  "${CODEC_ARGS[@]}" \
  --create-empty-src-dirs --retries 1
"$RCLONE_BIN" copy "$SHARED_SOURCE" "$SHARED_DESTINATION" \
  "${CODEC_ARGS[@]}" \
  --create-empty-src-dirs --retries 1

printf '%s\n' 'new tool' >"$SOURCE/.bin/tool"
printf '%s\n' 'new marker file' >"$SOURCE/$MARKER_FILE"
printf '%s\n' 'new marker directory' >"$SOURCE/nested/$MARKER_DIRECTORY/file"
printf '%s\n' 'new shared tool' >"$SHARED_SOURCE/.bin/shared-tool"
"$RCLONE_BIN" copy "$SOURCE" "$DESTINATION" \
  --backup-dir "$VERSIONS" \
  "${CODEC_ARGS[@]}" \
  --create-empty-src-dirs --retries 1
"$RCLONE_BIN" copy "$SHARED_SOURCE" "$SHARED_DESTINATION" \
  --backup-dir "$SHARED_VERSIONS" \
  "${CODEC_ARGS[@]}" \
  --create-empty-src-dirs --retries 1

"$RCLONE_BIN" copy "$SOURCE" "$DESTINATION" \
  "${CODEC_ARGS[@]}" \
  --create-empty-src-dirs --dry-run --retries 1 --combined "$REPORT"

if [[ "$(<"$DESTINATION/$DOT_BIN_MARKER/tool")" == "new tool" &&
      -d "$DESTINATION/case-variant/$DOT_BIN_UPPER_MARKER" &&
      "$(<"$DESTINATION/$PREFIX$MARKER_FILE")" == "new marker file" &&
      "$(<"$DESTINATION/nested/$PREFIX$MARKER_DIRECTORY/file")" == "new marker directory" &&
      "$(<"$DESTINATION/$PREFIX$UPPERCASE_DIRECTORY/file")" == "uppercase marker directory" &&
      "$(<"$VERSIONS/$PREFIX$DOT_BIN_MARKER/tool")" == "old tool" &&
      "$(<"$VERSIONS/$PREFIX$PREFIX$MARKER_FILE")" == "old marker file" &&
      "$(<"$VERSIONS/nested/$PREFIX$PREFIX$MARKER_DIRECTORY/file")" == "old marker directory" &&
      -d "$WORK/backup/Shared Drives/__gdt0__Team (drive-1)" &&
      "$(<"$SHARED_DESTINATION/$DOT_BIN_MARKER/shared-tool")" == "new shared tool" &&
      "$(<"$SHARED_VERSIONS/$PREFIX$DOT_BIN_MARKER/shared-tool")" == "old shared tool" ]] &&
   ! grep -Eq '^[+*!] ' "$REPORT"; then
  printf '%s\n' 'ok - real rclone preserves .bin, collisions, versions, and repeatability'
  exit 0
fi

printf '%s\n' 'not ok - real rclone NAS name codec integration'
exit 1
