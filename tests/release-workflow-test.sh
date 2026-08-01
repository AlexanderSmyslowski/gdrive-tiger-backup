#!/bin/bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INFO_PLIST="$ROOT/macos/GDriveBackupTiger/Info.plist"
VALIDATOR="$ROOT/scripts/validate-release.sh"
NOTES_EXTRACTOR="$ROOT/scripts/changelog-release-notes.sh"
WORKFLOW="$ROOT/.github/workflows/release.yml"
PKG_VERIFIER="$ROOT/packaging/verify-pkg.sh"
failures=0

check_contains() {
  local file="$1"
  local expected="$2"
  local description="$3"
  if [[ -f "$file" ]] && /usr/bin/grep -Fq -- "$expected" "$file"; then
    printf 'ok - %s\n' "$description"
  else
    printf 'not ok - %s\n' "$description"
    failures=$((failures + 1))
  fi
}

check_executable() {
  local file="$1"
  local description="$2"
  if [[ -x "$file" ]]; then
    printf 'ok - %s\n' "$description"
  else
    printf 'not ok - %s\n' "$description"
    failures=$((failures + 1))
  fi
}

version="$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$INFO_PLIST")"
tag="v${version}"

check_executable "$VALIDATOR" "release metadata validator is executable"
check_executable "$NOTES_EXTRACTOR" "changelog release-note extractor is executable"

if [[ -x "$VALIDATOR" ]]; then
  if "$VALIDATOR" "$tag" >/dev/null; then
    printf 'ok - matching release tag passes validation\n'
  else
    printf 'not ok - matching release tag passes validation\n'
    failures=$((failures + 1))
  fi

  if "$VALIDATOR" "v999.0.0" >/dev/null 2>&1; then
    printf 'not ok - mismatched release tag is rejected\n'
    failures=$((failures + 1))
  else
    printf 'ok - mismatched release tag is rejected\n'
  fi

  if "$VALIDATOR" "$version" >/dev/null 2>&1; then
    printf 'not ok - malformed release tag is rejected\n'
    failures=$((failures + 1))
  else
    printf 'ok - malformed release tag is rejected\n'
  fi
fi

if [[ -x "$NOTES_EXTRACTOR" ]]; then
  notes="$("$NOTES_EXTRACTOR" "$tag" 2>/dev/null)"
  if [[ "$notes" == *"## v${version} "* && "$notes" != *"## v2.4.3 "* ]]; then
    printf 'ok - extractor returns only the requested changelog section\n'
  else
    printf 'not ok - extractor returns only the requested changelog section\n'
    failures=$((failures + 1))
  fi

  if [[ "$notes" == *"accountless/guest SMB remounting without Keychain lookup or UI"* ]]; then
    printf 'ok - v2.4.4 notes describe guest SMB remounting without Keychain or UI\n'
  else
    printf 'not ok - v2.4.4 notes describe guest SMB remounting without Keychain or UI\n'
    failures=$((failures + 1))
  fi

  if [[ "$notes" == *"older than or equal to that success"* &&
        "$notes" == *"newer persistent same-profile failure alert"* ]]; then
    printf 'ok - v2.4.4 notes preserve newer persistent failure alerts\n'
  else
    printf 'not ok - v2.4.4 notes preserve newer persistent failure alerts\n'
    failures=$((failures + 1))
  fi

  if [[ "$notes" == *"unknown-total progress indeterminate"* &&
        "$notes" == *"durable terminal status publication"* ]]; then
    printf 'ok - v2.4.4 notes describe truthful unknown-total progress\n'
  else
    printf 'not ok - v2.4.4 notes describe truthful unknown-total progress\n'
    failures=$((failures + 1))
  fi
fi

check_contains "$WORKFLOW" "tags:" "release workflow is triggered by version tags"
check_contains "$WORKFLOW" "'v*'" "release workflow accepts semantic version tags"
check_contains "$WORKFLOW" "contents: write" "release workflow may create the GitHub release"
check_contains "$WORKFLOW" "scripts/validate-release.sh" \
  "release workflow validates tag and source metadata"
check_contains "$WORKFLOW" "make test" "release workflow reruns the complete test suite"
check_contains "$WORKFLOW" "packaging/build-pkg.sh" \
  "release workflow builds the installer from the tagged source"
check_contains "$WORKFLOW" "packaging/verify-pkg.sh --expect-unsigned" \
  "release workflow verifies the unsigned installer explicitly"
check_contains "$WORKFLOW" "shasum -a 256" "release workflow publishes a SHA-256 digest"
check_contains "$WORKFLOW" "SHA256SUMS.txt" \
  "release workflow uses one portable checksum manifest"
check_contains "$WORKFLOW" "scripts/changelog-release-notes.sh" \
  "release workflow derives notes from the versioned changelog"
check_contains "$WORKFLOW" "gh release create" "release workflow creates the GitHub release"
check_contains "$PKG_VERIFIER" \
  "Packaged app must not carry the restricted time-sensitive notification entitlement." \
  "package verification rejects a launch-blocking entitlement independently of package signing"

if (( failures > 0 )); then
  printf '%s release workflow check(s) failed.\n' "$failures"
  exit 1
fi

printf 'All release workflow checks passed.\n'
