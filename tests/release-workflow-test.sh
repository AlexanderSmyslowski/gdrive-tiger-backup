#!/bin/bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INFO_PLIST="$ROOT/macos/GDriveBackupTiger/Info.plist"
VALIDATOR="$ROOT/scripts/validate-release.sh"
NOTES_EXTRACTOR="$ROOT/scripts/changelog-release-notes.sh"
WORKFLOW="$ROOT/.github/workflows/release.yml"
PKG_VERIFIER="$ROOT/packaging/verify-pkg.sh"
FIXTURE_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/gdrive-release-workflow-test.XXXXXX")" || exit 1
FIXTURE_VALIDATOR="$FIXTURE_ROOT/scripts/validate-release.sh"
failures=0

cleanup() {
  local exit_status=$?
  trap - EXIT
  if [[ -d "$FIXTURE_ROOT" ]] && ! "$ROOT/scripts/trash-path.sh" "$FIXTURE_ROOT"; then
    printf 'not ok - unable to move release-workflow fixture to Trash: %s\n' \
      "$FIXTURE_ROOT" >&2
    exit_status=1
  fi
  exit "$exit_status"
}
trap cleanup EXIT

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

write_fixture_changelog() {
  local unreleased_entry="$1"
  {
    printf '# Changelog\n\n## Unreleased\n\n'
    if [[ -n "$unreleased_entry" ]]; then
      printf -- '- %s\n\n' "$unreleased_entry"
    fi
    printf '## %s - 2026-08-01\n\n- Fixture release notes.\n' "$tag"
  } >"$FIXTURE_ROOT/CHANGELOG.md"
}

check_executable "$VALIDATOR" "release metadata validator is executable"
check_executable "$NOTES_EXTRACTOR" "changelog release-note extractor is executable"

if [[ -x "$VALIDATOR" ]]; then
  # The validator resolves metadata from its own location, so a copied
  # production script can exercise release-ready inputs without mutating the
  # active development tree.
  /bin/mkdir -p "$FIXTURE_ROOT/scripts" "$FIXTURE_ROOT/macos/GDriveBackupTiger"
  /bin/cp "$VALIDATOR" "$FIXTURE_VALIDATOR"
  /bin/cp "$INFO_PLIST" "$FIXTURE_ROOT/macos/GDriveBackupTiger/Info.plist"
  # Backticks are literal Markdown delimiters in the fixture README.
  # shellcheck disable=SC2016
  printf 'Current release: `%s`\nGDrive-Backup-Tiger-%s.pkg\n' \
    "$tag" "$version" >"$FIXTURE_ROOT/README.md"
  write_fixture_changelog ""

  if "$FIXTURE_VALIDATOR" "$tag" >/dev/null; then
    printf 'ok - matching release tag passes validation in a release-ready fixture\n'
  else
    printf 'not ok - matching release tag passes validation in a release-ready fixture\n'
    failures=$((failures + 1))
  fi

  # Candidate metadata must be verifiable before any public release exists.
  # shellcheck disable=SC2016
  printf 'Current release candidate: `%s`\nGDrive-Backup-Tiger-%s.pkg\n' \
    "$tag" "$version" >"$FIXTURE_ROOT/README.md"
  if "$FIXTURE_VALIDATOR" "$tag" >/dev/null 2>&1; then
    printf 'ok - explicitly labelled release candidate passes metadata validation\n'
  else
    printf 'not ok - explicitly labelled release candidate passes metadata validation\n'
    failures=$((failures + 1))
  fi

  if "$FIXTURE_VALIDATOR" "v999.0.0" >/dev/null 2>&1; then
    printf 'not ok - mismatched release tag is rejected in the fixture\n'
    failures=$((failures + 1))
  else
    printf 'ok - mismatched release tag is rejected in the fixture\n'
  fi

  if "$FIXTURE_VALIDATOR" "$version" >/dev/null 2>&1; then
    printf 'not ok - malformed release tag is rejected in the fixture\n'
    failures=$((failures + 1))
  else
    printf 'ok - malformed release tag is rejected in the fixture\n'
  fi

  write_fixture_changelog "Pending fixture work."
  if "$FIXTURE_VALIDATOR" "$tag" >/dev/null 2>&1; then
    printf 'not ok - fixture metadata with Unreleased entries is rejected\n'
    failures=$((failures + 1))
  else
    printf 'ok - fixture metadata with Unreleased entries is rejected\n'
  fi
fi

if [[ -x "$NOTES_EXTRACTOR" ]]; then
  notes="$("$NOTES_EXTRACTOR" "$tag" 2>/dev/null)"
  previous_notes="$("$NOTES_EXTRACTOR" "v2.4.5" 2>/dev/null)"
  identity_notes="$("$NOTES_EXTRACTOR" "v2.4.6" 2>/dev/null)"
  destination_notes="$("$NOTES_EXTRACTOR" "v2.5.1" 2>/dev/null)"
  heading_count="$(printf '%s\n' "$notes" | /usr/bin/grep -Ec '^## v')"
  if [[ "$notes" == *"## v${version} "* && "$heading_count" == "1" ]]; then
    printf 'ok - extractor returns only the requested changelog section\n'
  else
    printf 'not ok - extractor returns only the requested changelog section\n'
    failures=$((failures + 1))
  fi

  if [[ "$previous_notes" == *"physical disk name"* &&
        "$previous_notes" == *"logical volume name"* ]]; then
    printf 'ok - v2.4.5 historical notes describe readable physical and logical disk identity\n'
  else
    printf 'not ok - v2.4.5 historical notes describe readable physical and logical disk identity\n'
    failures=$((failures + 1))
  fi

  if [[ "$destination_notes" == *"single manual backup directly in the main window"* &&
        "$destination_notes" == *"volume UUID"* &&
        "$destination_notes" == *"manual results separately"* &&
        "$destination_notes" == *"compact manual-destination dialog"* &&
        "$destination_notes" == *"Defer automatic NAS retries"* &&
        "$destination_notes" == *"unpublished v2.5.0"* ]]; then
    printf 'ok - v2.5.1 public notes include the unpublished destination picker and retry fix\n'
  else
    printf 'not ok - v2.5.1 public notes include the unpublished destination picker and retry fix\n'
    failures=$((failures + 1))
  fi

  if [[ "$previous_notes" == *"UUIDs, serial numbers, BSD device identifiers, and mount paths"* &&
        "$previous_notes" == *"exact UUID/device revalidation"* ]]; then
    printf 'ok - v2.4.5 historical notes preserve private display and exact device validation\n'
  else
    printf 'not ok - v2.4.5 historical notes preserve private display and exact device validation\n'
    failures=$((failures + 1))
  fi

  if [[ "$previous_notes" == *"quiet recovery confirmation"* &&
        "$previous_notes" == *"opt-in and silent"* ]]; then
    printf 'ok - v2.4.5 historical notes describe quiet successful-backup notifications\n'
  else
    printf 'not ok - v2.4.5 historical notes describe quiet successful-backup notifications\n'
    failures=$((failures + 1))
  fi

  if [[ "$previous_notes" == *"macOS 15"* &&
        "$previous_notes" == *"checked/listed counters"* &&
        "$previous_notes" == *"destination free space"* ]]; then
    printf 'ok - v2.4.5 historical notes describe portable disk identity and truthful aggregate activity\n'
  else
    printf 'not ok - v2.4.5 historical notes describe portable disk identity and truthful aggregate activity\n'
    failures=$((failures + 1))
  fi

  if [[ "$identity_notes" == *"GDRIVE_BACKUP_APPROVE_VOLUME_CREATION=1"* &&
        "$identity_notes" == *"process-only authorization for one setup invocation"* &&
        "$identity_notes" == *"BACKUP_ASSUME_YES"* &&
        "$identity_notes" == *"before confirmation UI, privileged helpers, disk mutation, or copy"* ]]; then
    printf 'ok - v2.4.6 notes restrict APFS creation to explicit one-run approval\n'
  else
    printf 'not ok - v2.4.6 notes restrict APFS creation to explicit one-run approval\n'
    failures=$((failures + 1))
  fi

  if [[ "$identity_notes" == *"every successful APFS run to be UUID-bound"* &&
        "$identity_notes" == *"Legacy path-only targets fail closed outside setup"* &&
        "$identity_notes" == *"Rediscover the sole eligible source container and exact-name UUID inventory"* &&
        "$identity_notes" == *"multiple eligible containers"* &&
        "$identity_notes" == *"numeric-family names such as \`GoogleDrive-Backup 1\` fail closed"* &&
        "$identity_notes" == *"never deletes, erases, repartitions, renames, or unmounts volumes"* ]]; then
    printf 'ok - v2.4.6 notes describe fail-closed APFS identity and non-destructive boundaries\n'
  else
    printf 'not ok - v2.4.6 notes describe fail-closed APFS identity and non-destructive boundaries\n'
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
