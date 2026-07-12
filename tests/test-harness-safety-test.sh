#!/bin/bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAKEFILE="$ROOT/Makefile"
failures=0

while IFS= read -r line; do
  [[ "$line" == *'_TEST_BIN='* ]] || continue
  if [[ "$line" == $'\t@set -e; '* ]]; then
    continue
  fi
  printf 'not ok - compiled test recipe does not fail fast: %s\n' "${line#*$'\t@'}"
  failures=$((failures + 1))
done <"$MAKEFILE"

if (( failures > 0 )); then
  printf '%s compiled test recipe(s) can hide compiler or test failures.\n' "$failures"
  exit 1
fi

printf '%s\n' 'ok - every compiled test recipe fails on its first compiler or test error'
