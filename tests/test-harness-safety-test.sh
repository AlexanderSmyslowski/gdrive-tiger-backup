#!/bin/bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAKEFILE="$ROOT/Makefile"
failures=0

default_goal="$(make -C "$ROOT" -pn 2>/dev/null |
  /usr/bin/awk -F' := ' '$1 == ".DEFAULT_GOAL" { print $2; exit }')"
if [[ "$default_goal" != "test-adhoc" ]]; then
  printf 'not ok - bare make changed from test-adhoc to %s\n' "$default_goal"
  failures=$((failures + 1))
fi

while IFS= read -r line; do
  [[ "$line" == *'_TEST_BIN='* ]] || continue
  if [[ "$line" == $'\t@set -e; '* ]]; then
    continue
  fi
  printf 'not ok - compiled test recipe does not fail fast: %s\n' "${line#*$'\t@'}"
  failures=$((failures + 1))
done <"$MAKEFILE"

if (( failures > 0 )); then
  printf '%s test harness safety check(s) failed.\n' "$failures"
  exit 1
fi

printf '%s\n' 'ok - every compiled test recipe fails on its first compiler or test error'
