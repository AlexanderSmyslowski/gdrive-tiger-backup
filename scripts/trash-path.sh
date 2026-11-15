#!/bin/bash
set -euo pipefail

if [[ $# -eq 0 ]]; then
  printf 'Usage: %s PATH [...]\n' "$0" >&2
  exit 64
fi

# Build products and test fixtures created under a temporary directory are
# disposable by definition. Deleting them directly keeps hundreds of scratch
# items per test run out of the user's Trash; everything else stays recoverable.
is_temporary_path() {
  local path="$1" parent real root
  parent="$(/usr/bin/dirname "$path")"
  real="$(cd "$parent" 2>/dev/null && /bin/pwd -P)" || return 1
  for root in "${TMPDIR:-}" /tmp /private/tmp /var/folders /private/var/folders; do
    [[ -n "$root" ]] || continue
    root="$(cd "$root" 2>/dev/null && /bin/pwd -P)" || continue
    # Never the temporary root itself, only something strictly inside it.
    if [[ "$real" == "$root" || "$real" == "$root"/* ]]; then
      return 0
    fi
  done
  return 1
}

if [[ "${GDRIVE_FORCE_TRASH_FALLBACK:-0}" != "1" ]]; then
  remaining=()
  for path in "$@"; do
    if [[ ( -e "$path" || -L "$path" ) ]] && is_temporary_path "$path"; then
      /bin/rm -rf -- "$path"
    else
      remaining+=("$path")
    fi
  done
  if (( ${#remaining[@]} == 0 )); then
    exit 0
  fi
  set -- "${remaining[@]}"
  if [[ -x /usr/bin/trash ]]; then
    exec /usr/bin/trash "$@"
  fi
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
