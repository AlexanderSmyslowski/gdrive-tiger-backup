#!/bin/bash
# Download the pinned rclone and jq releases for both Mac architectures,
# verify their published SHA-256 checksums, and combine each into one
# universal binary. Prints the directory that holds bin/ and licenses/.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=packaging/bundled-tools.conf
source "$ROOT/packaging/bundled-tools.conf"
CACHE_DIR="${GDRIVE_BUNDLED_TOOLS_CACHE:-$ROOT/build/bundled-tools-cache}"
OUT_DIR="${1:?usage: fetch-bundled-tools.sh OUTPUT_DIR}"

mkdir -p "$CACHE_DIR" "$OUT_DIR/bin" "$OUT_DIR/licenses"

sha256_of() { /usr/bin/shasum -a 256 "$1" | /usr/bin/awk '{print $1}'; }

# fetch URL FILE SHA256: reuse a cached file only when its checksum matches.
fetch() {
  local url="$1" file="$CACHE_DIR/$2" expected="$3"
  if [[ ! -f "$file" || "$(sha256_of "$file")" != "$expected" ]]; then
    /usr/bin/curl -fsSL --retry 3 -o "$file.partial" "$url"
    /bin/mv -f "$file.partial" "$file"
  fi
  local actual
  actual="$(sha256_of "$file")"
  if [[ "$actual" != "$expected" ]]; then
    printf 'Checksum mismatch for %s: expected %s, got %s\n' "$2" "$expected" "$actual" >&2
    /bin/rm -f "$file"
    exit 1
  fi
}

work="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/gdrive-bundled-tools.XXXXXX")"
trap '/bin/rm -rf "$work"' EXIT

for arch in arm64 amd64; do
  sha_var="RCLONE_SHA256_$(printf '%s' "$arch" | /usr/bin/tr '[:lower:]' '[:upper:]')"
  zip="rclone-${RCLONE_VERSION}-osx-${arch}.zip"
  fetch "https://downloads.rclone.org/${RCLONE_VERSION}/${zip}" "$zip" "${!sha_var}"
  /usr/bin/ditto -x -k "$CACHE_DIR/$zip" "$work/rclone-$arch"

  sha_var="JQ_SHA256_$(printf '%s' "$arch" | /usr/bin/tr '[:lower:]' '[:upper:]')"
  fetch "https://github.com/jqlang/jq/releases/download/${JQ_VERSION}/jq-macos-${arch}" \
    "jq-${JQ_VERSION}-macos-${arch}" "${!sha_var}"
done

rclone_dir_arm="$work/rclone-arm64/rclone-${RCLONE_VERSION}-osx-arm64"
rclone_dir_amd="$work/rclone-amd64/rclone-${RCLONE_VERSION}-osx-amd64"
/usr/bin/lipo -create "$rclone_dir_arm/rclone" "$rclone_dir_amd/rclone" -output "$OUT_DIR/bin/rclone"
/usr/bin/lipo -create "$CACHE_DIR/jq-${JQ_VERSION}-macos-arm64" "$CACHE_DIR/jq-${JQ_VERSION}-macos-amd64" \
  -output "$OUT_DIR/bin/jq"
/bin/chmod 755 "$OUT_DIR/bin/rclone" "$OUT_DIR/bin/jq"

# License notices come from the tagged sources so they match the shipped
# versions.
/usr/bin/curl -fsSL --retry 3 -o "$OUT_DIR/licenses/rclone-COPYING.txt" \
  "https://raw.githubusercontent.com/rclone/rclone/${RCLONE_VERSION}/COPYING"
/usr/bin/curl -fsSL --retry 3 -o "$OUT_DIR/licenses/jq-COPYING.txt" \
  "https://raw.githubusercontent.com/jqlang/jq/${JQ_VERSION}/COPYING"
printf 'rclone %s (MIT License, https://rclone.org/licence/)\njq %s (MIT License)\n' \
  "$RCLONE_VERSION" "$JQ_VERSION" >"$OUT_DIR/licenses/VERSIONS.txt"

printf '%s\n' "$OUT_DIR"
