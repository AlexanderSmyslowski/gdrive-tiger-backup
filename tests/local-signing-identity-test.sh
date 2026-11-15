#!/bin/bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/scripts/local-signing-identity.sh"
failures=0

check() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    printf 'ok - %s\n' "$name"
  else
    printf 'not ok - %s (expected %s, got %s)\n' "$name" "$expected" "$actual"
    failures=$((failures + 1))
  fi
}

check 'forced ad-hoc mode never resolves to a signing identity' '-' \
  "$(GDRIVE_FORCE_ADHOC_SIGNATURE=1 "$SCRIPT" resolve)"
check 'a missing identity falls back to an ad-hoc signature' '-' \
  "$(GDRIVE_LOCAL_SIGN_IDENTITY="GDrive Missing Identity $$" "$SCRIPT" resolve)"

"$SCRIPT" unknown >/dev/null 2>&1
check 'unknown commands are rejected with a usage error' '64' "$?"

for consumer in Makefile install.sh; do
  if /usr/bin/grep -Fq 'local-signing-identity.sh' "$ROOT/$consumer" &&
     ! /usr/bin/grep -Eq 'codesign .*--sign - ' "$ROOT/$consumer"; then
    printf 'ok - %s signs through the identity resolver\n' "$consumer"
  else
    printf 'not ok - %s signs through the identity resolver\n' "$consumer"
    failures=$((failures + 1))
  fi
done

if [[ "$failures" -gt 0 ]]; then
  printf '%d local signing identity test(s) failed.\n' "$failures"
  exit 1
fi
