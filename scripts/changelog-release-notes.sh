#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [[ $# -ne 1 || ! "$1" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  printf 'Usage: %s vMAJOR.MINOR.PATCH\n' "$0" >&2
  exit 64
fi

tag="$1"

/usr/bin/awk -v prefix="## ${tag} " '
  /^## / {
    if (found) {
      exit
    }
    if (index($0, prefix) == 1) {
      found = 1
    }
  }
  found { print }
  END {
    if (!found) {
      exit 1
    }
  }
' "$ROOT/CHANGELOG.md"
