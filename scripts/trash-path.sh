#!/bin/bash
set -euo pipefail

if [[ $# -eq 0 ]]; then
  printf 'Usage: %s PATH [...]\n' "$0" >&2
  exit 64
fi

if [[ "${GDRIVE_FORCE_TRASH_FALLBACK:-0}" != "1" && -x /usr/bin/trash ]]; then
  exec /usr/bin/trash "$@"
fi

# macOS 13 and 14 do not provide /usr/bin/trash. Moving items into the user's
# Trash keeps cleanup recoverable on those supported systems.
if [[ -z "${HOME:-}" || ! -d "$HOME" ]]; then
  printf '%s\n' 'Cannot locate the user Trash because HOME is unavailable.' >&2
  exit 69
fi

trash_dir="$HOME/.Trash"
/bin/mkdir -p "$trash_dir"

for path in "$@"; do
  [[ -e "$path" ]] || continue
  name="$(/usr/bin/basename "$path")"
  unique_id="$(/usr/bin/uuidgen | /usr/bin/tr '[:upper:]' '[:lower:]')"
  destination="$trash_dir/${name}.${unique_id}"
  if [[ -e "$destination" ]]; then
    printf 'Refusing to overwrite an existing Trash item: %s\n' "$destination" >&2
    exit 73
  fi
  /bin/mv "$path" "$destination"
done
