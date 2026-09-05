#!/bin/bash
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INFO_PLIST="$ROOT/macos/GDriveBackupTiger/Info.plist"
EXPECTED_VERSION="2.5.1"
EXPECTED_BUILD="32"
failures=0

check_contains() {
  local file="$1"
  local expected="$2"
  local description="$3"
  if /usr/bin/grep -Fq -- "$expected" "$file"; then
    printf 'ok - %s\n' "$description"
  else
    printf 'not ok - %s\n' "$description"
    failures=$((failures + 1))
  fi
}

check_not_contains() {
  local file="$1"
  local rejected="$2"
  local description="$3"
  if /usr/bin/grep -Fq -- "$rejected" "$file"; then
    printf 'not ok - %s\n' "$description"
    failures=$((failures + 1))
  else
    printf 'ok - %s\n' "$description"
  fi
}

version="$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$INFO_PLIST")"
build="$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$INFO_PLIST")"
minimum_macos="$(/usr/bin/plutil -extract LSMinimumSystemVersion raw -o - "$INFO_PLIST")"

if [[ "$version" != "$EXPECTED_VERSION" || "$build" != "$EXPECTED_BUILD" ]]; then
  printf 'not ok - expected app version %s build %s, got %s build %s\n' \
    "$EXPECTED_VERSION" "$EXPECTED_BUILD" "$version" "$build"
  failures=$((failures + 1))
else
  printf 'ok - app version and build match the release plan\n'
fi

check_contains "$ROOT/README.md" "Current release: \`v${version}\`" \
  "README release matches the app version"
check_not_contains "$ROOT/README.md" "Current release candidate: \`v${version}\`" \
  "README no longer presents the release as a candidate"
check_contains "$ROOT/README.md" "GDrive-Backup-Tiger-${EXPECTED_VERSION}.pkg" \
  "README names the exact release installer"
installer_names="$(
  /usr/bin/grep -Eo 'GDrive-Backup-Tiger-[0-9]+\.[0-9]+\.[0-9]+\.pkg' \
    "$ROOT/README.md" | /usr/bin/sort -u
)"
if [[ "$installer_names" == "GDrive-Backup-Tiger-${EXPECTED_VERSION}.pkg" ]]; then
  printf 'ok - README contains no stale versioned installer name\n'
else
  printf 'not ok - README contains no stale versioned installer name\n'
  failures=$((failures + 1))
fi
check_contains "$ROOT/README.md" \
  "Scheduled, retry, mount-triggered, and menu-bar-only runs stay headless and passive, including in full-screen Spaces." \
  "README explicitly keeps automatic retries passive in full-screen Spaces"
check_contains "$ROOT/README.md" \
  "\`GDRIVE_BACKUP_APPROVE_VOLUME_CREATION=1\` is a narrow process-only authorization for one setup invocation; it is ignored when stored in a config file." \
  "README documents process-only APFS creation authorization"
check_contains "$ROOT/README.md" \
  "BACKUP_ASSUME_YES approves backup start only and never authorizes \`diskutil apfs addVolume\`." \
  "README keeps automatic backup approval separate from APFS creation"
check_contains "$ROOT/README.md" \
  "Overview/manual, scheduled, retry, mount-triggered, menu-bar-only, and unknown triggers cannot create or bind a volume or open volume-creation UI." \
  "README reserves APFS creation and binding for setup"
check_contains "$ROOT/README.md" \
  "one exact-name candidate in one eligible external APFS container" \
  "README documents unique APFS candidate and container selection"
check_contains "$ROOT/README.md" \
  "independently validates it, binds its UUID, resolves its current mount point and nested destination, and atomically persists the complete identity." \
  "README documents APFS identity validation and atomic persistence"
check_contains "$ROOT/README.md" \
  "Multiple named candidates or multiple eligible containers abort without mutation or copy, and prefix-renamed volumes are never guessed." \
  "README documents APFS ambiguity and prefix-name fail-closed behavior"
check_contains "$ROOT/README.md" \
  "The routine never deletes, erases, repartitions, renames, or unmounts volumes." \
  "README documents the non-destructive APFS safety boundary"
check_contains "$ROOT/README.md" \
  "silent authenticated and guest SMB mounting" \
  "README release summary covers authenticated and guest SMB mounting"
check_contains "$ROOT/README.md" \
  "Guest SMB URLs such as \`smb://nas.local/Backups\` bypass Keychain and authentication commands and remain no-UI during automatic runs." \
  "README documents guest SMB without Keychain or UI"
check_contains "$ROOT/README.md" \
  "newer persistent failure for the same profile cannot be erased" \
  "README documents the persistent notification cleanup boundary"
check_contains "$ROOT/README.md" \
  "Routine successful automatic-backup notifications are opt-in" \
  "README documents that routine success notifications stay opt-in"
check_contains "$ROOT/README.md" \
  "A successful automatic backup after an active issue sends one quiet recovery confirmation" \
  "README documents automatic quiet recovery confirmations"
check_contains "$ROOT/README.md" \
  "the progress bar remains indeterminate and no stale or invented percentage is shown" \
  "README documents truthful unknown-total progress"
check_contains "$ROOT/README.md" \
  "increasing aggregate checked/listed counters" \
  "README documents visible aggregate progress without file names"
check_contains "$ROOT/README.md" \
  "capacity clearly labelled as destination free space rather than backup progress" \
  "README distinguishes target capacity from live backup progress"
check_contains "$ROOT/README.md" \
  "Completion appears only after the durable terminal status has been published." \
  "README ties completion to durable terminal status"
check_contains "$ROOT/CHANGELOG.md" "## v${version} " \
  "changelog contains the app version"
check_contains "$ROOT/docs/version-history.md" "| v${version} | ${build} |" \
  "publication history contains the app version and build"
check_contains "$ROOT/docs/version-history.md" \
  "The v2.4.3, v2.4.4, and v2.4.5 installers are built and verified from their exact tags" \
  "publication history explains the exact-tag installer builds"
check_contains "$ROOT/docs/version-history.md" \
  "v2.5.1 is the current release." \
  "publication history identifies v2.5.1 as the current release"
check_contains "$ROOT/docs/version-history.md" \
  "Unpublished intermediate milestone; destination selection first ships publicly in v2.5.1" \
  "publication history does not invent a public v2.5.0 release"
check_contains "$ROOT/docs/version-history.md" \
  "No retrospectively built installer is presented as an original historical artifact." \
  "publication history labels retrospectively built installers honestly"
check_not_contains "$ROOT/docs/version-history.md" \
  "The current release alone receives the installer" \
  "publication history does not claim only the current release receives an installer"
check_contains "$ROOT/README.md" "macOS ${minimum_macos%%.*}" \
  "README states the minimum macOS generation"
check_contains "$ROOT/install.sh" "GDRIVE_BACKUP_RETENTION=1" \
  "source installer enables retention explicitly"
check_contains "$ROOT/install.sh" "GDRIVE_BACKUP_ENCRYPTION=none" \
  "source installer keeps encryption opt-in"
check_contains "$ROOT/install.sh" "GDRIVE_BACKUP_PAUSED=0" \
  "source installer enables automatic backups explicitly"
check_contains "$ROOT/install.sh" "GDRIVE_BACKUP_NOTIFY_FAILURES=1" \
  "source installer enables automatic-backup notifications explicitly"
check_contains "$ROOT/install.sh" "GDRIVE_BACKUP_NOTIFY_SUCCESSES=0" \
  "source installer keeps routine-success notifications opt-in"
check_contains "$ROOT/install.sh" "migrate_notification_success_preferences()" \
  "source installer migrates the legacy and trusted active-profile preferences"
check_contains "$ROOT/install.sh" "if [[ \"\${GDRIVE_BACKUP_VOLUME_UUID+x}\" == \"x\" ]]" \
  "source installer accepts only an explicitly supplied APFS UUID"
check_contains "$ROOT/install.sh" "An explicitly supplied APFS UUID cannot be empty." \
  "source installer rejects an explicitly empty APFS UUID"
check_contains "$ROOT/install.sh" "LC_ALL=C printf 'GDRIVE_BACKUP_VOLUME_UUID=%q\\n' \"\$BACKUP_VOLUME_UUID\"" \
  "source installer persists the explicitly verified APFS UUID"
check_contains "$ROOT/install.sh" "ACTIVE_PROFILE_FILE=\"\$CONFIG_DIR/active-profile\"" \
  "source installer resolves the active profile before UUID migration"
check_contains "$ROOT/install.sh" "upsert_volume_identity \"\$ACTIVE_PROFILE_CONFIG\"" \
  "source installer updates the active runtime profile as well as the legacy config"
check_contains "$ROOT/install.sh" "/usr/sbin/diskutil info -plist \"\$BACKUP_VOLUME\"" \
  "source installer reads the mounted APFS identity"
check_contains "$ROOT/install.sh" "MOUNTED_VOLUME_UUID\" != \"\$BACKUP_VOLUME_UUID\"" \
  "source installer rejects a UUID that belongs to another mounted volume"
check_contains "$ROOT/install.sh" "MOUNTED_FILESYSTEM_TYPE\" != \"apfs\"" \
  "source installer rejects a mounted non-APFS target"
check_contains "$ROOT/install.sh" "MOUNTED_WRITABLE_MEDIA\" != \"true\"" \
  "source installer rejects a read-only APFS target"
check_contains "$ROOT/install.sh" "-framework UserNotifications" \
  "source installer links the macOS notification framework"
check_contains "$ROOT/install.sh" "-framework NetFS" \
  "source installer links the native network mount framework"

GDRIVE_BACKUP_VOLUME_UUID=not-a-uuid \
  BACKUP_TARGET=apfs \
  /bin/bash "$ROOT/install.sh" >/dev/null 2>&1
invalid_uuid_status=$?
if [[ "$invalid_uuid_status" == "64" ]]; then
  printf 'ok - source installer rejects an invalid APFS UUID before installation\n'
else
  printf 'not ok - source installer rejects an invalid APFS UUID before installation\n'
  failures=$((failures + 1))
fi

check_contains "$ROOT/packaging/scripts/postinstall" "GDRIVE_BACKUP_RETENTION=1" \
  "package installer enables retention explicitly"
check_contains "$ROOT/packaging/scripts/postinstall" "GDRIVE_BACKUP_ENCRYPTION=none" \
  "package installer keeps encryption opt-in"
check_contains "$ROOT/packaging/scripts/postinstall" "GDRIVE_BACKUP_PAUSED=0" \
  "package installer enables automatic backups explicitly"
check_contains "$ROOT/packaging/scripts/postinstall" "GDRIVE_BACKUP_NOTIFY_FAILURES=1" \
  "package installer enables automatic-backup notifications explicitly"
check_contains "$ROOT/packaging/scripts/postinstall" "GDRIVE_BACKUP_NOTIFY_SUCCESSES=0" \
  "package installer keeps routine-success notifications opt-in"
check_contains "$ROOT/packaging/scripts/postinstall" \
  "migrate_notification_success_preferences()" \
  "package installer migrates the legacy and trusted active-profile preferences"
check_contains "$ROOT/README.md" \
  "Inactive profiles remain fail-closed until an explicit setup Save writes their preference." \
  "README documents the fail-closed inactive-profile upgrade boundary"
check_contains "$ROOT/CHANGELOG.md" "routine successful automatic backups" \
  "release changelog records the opt-in routine-success behavior"

for source in \
  ProfileSupport.m \
  BackupProgressSupport.m \
  NotificationSupport.m \
  SetupHealthSupport.m \
  RestoreSupport.m \
  RestoreBrowserView.m \
  DiagnosticsSupport.m \
  DiagnosticsView.m \
  UpdateSupport.m \
  NetworkMountSupport.m; do
  check_contains "$ROOT/install.sh" "macos/GDriveBackupTiger/$source" \
    "source installer links $source"
done

extract_shell_function() {
  local file="$1"
  local function_name="$2"
  /usr/bin/awk -v signature="${function_name}() {" '
    $0 == signature { printing = 1 }
    printing { print }
    printing && /^}$/ { exit }
  ' "$file"
}

run_success_notification_migration_fixture() {
  local installer="$1"
  local installer_label="$2"
  local trusted_function
  local path_guard_function
  local config_store_guard_function
  local migration_function
  local orchestration_function
  local runner
  path_guard_function="$(extract_shell_function "$installer" path_has_untrusted_component)"
  config_store_guard_function="$(extract_shell_function "$installer" require_trusted_config_store)"
  trusted_function="$(extract_shell_function "$installer" trusted_active_profile_config)"
  migration_function="$(extract_shell_function "$installer" migrate_success_notification_preference)"
  orchestration_function="$(extract_shell_function "$installer" migrate_notification_success_preferences)"
  if [[ -z "$path_guard_function" || -z "$config_store_guard_function" ||
        -z "$trusted_function" || -z "$migration_function" ||
        -z "$orchestration_function" ]]; then
    printf 'not ok - %s exposes executable success-preference migration helpers\n' \
      "$installer_label"
    failures=$((failures + 1))
    return
  fi

  local fixture_root
  fixture_root="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/gdrive-success-preference-fixture.XXXXXX")"
  runner="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/gdrive-success-preference-runner.XXXXXX")"
  printf '%s\n' "$path_guard_function" "$config_store_guard_function" \
    "$trusted_function" "$migration_function" "$orchestration_function" >"$runner"
  if (
    set -u
    # Run the exact installer helpers in a fresh shell without evaluating a
    # string as code in this test process.
    # shellcheck disable=SC1090
    source "$runner"

    fixture_failures=0
    # These predicates are invoked by name through expect_fixture below.
    # shellcheck disable=SC2329
    preference_is_exactly_once() {
      local target="$1"
      local expected="$2"
      [[ "$(/usr/bin/grep -cx "GDRIVE_BACKUP_NOTIFY_SUCCESSES=$expected" "$target" || true)" == "1" &&
        "$(/usr/bin/grep -c '^GDRIVE_BACKUP_NOTIFY_SUCCESSES=' "$target" || true)" == "1" ]]
    }
    # shellcheck disable=SC2329
    preference_is_absent() {
      local target="$1"
      ! /usr/bin/grep -q '^GDRIVE_BACKUP_NOTIFY_SUCCESSES=' "$target"
    }
    expect_fixture() {
      local description="$1"
      shift
      if "$@"; then
        printf 'ok - %s (%s)\n' "$description" "$installer_label"
      else
        printf 'not ok - %s (%s)\n' "$description" "$installer_label"
        fixture_failures=$((fixture_failures + 1))
      fi
    }
    set_fixture_paths() {
      local directory="$1"
      CONFIG_FILE="$directory/config"
      CONFIG_DIR="$directory"
      ACTIVE_PROFILE_FILE="$directory/active-profile"
      PROFILES_DIR="$directory/profiles"
      # Extracted source and package helpers use different variable names.
      export config_file="$CONFIG_FILE"
      export config_dir="$CONFIG_DIR"
      export active_profile_file="$ACTIVE_PROFILE_FILE"
      export profiles_dir="$PROFILES_DIR"
    }
    create_valid_fixture() {
      local directory="$1"
      local legacy_preference="$2"
      local profile_preference="$3"
      /bin/mkdir -p "$directory/profiles"
      printf 'GDRIVE_BACKUP_PROFILE_ID=legacy\n' >"$directory/config"
      if [[ -n "$legacy_preference" ]]; then
        printf 'GDRIVE_BACKUP_NOTIFY_SUCCESSES=%s\n' "$legacy_preference" >>"$directory/config"
      fi
      printf 'GDRIVE_BACKUP_PROFILE_ID=office\n' >"$directory/profiles/office.conf"
      if [[ -n "$profile_preference" ]]; then
        printf 'GDRIVE_BACKUP_NOTIFY_SUCCESSES=%s\n' "$profile_preference" >>"$directory/profiles/office.conf"
      fi
      printf 'office\n' >"$directory/active-profile"
    }
    run_valid_fixture() {
      local name="$1"
      local legacy_preference="$2"
      local profile_preference="$3"
      local expected_preference="$4"
      local directory="$fixture_root/$name"
      create_valid_fixture "$directory" "$legacy_preference" "$profile_preference"
      set_fixture_paths "$directory"
      if [[ -n "$legacy_preference" ]]; then
        /bin/cp "$directory/config" "$directory/config.expected"
        /bin/cp "$directory/profiles/office.conf" \
          "$directory/profiles/office.conf.expected"
      fi
      migrate_notification_success_preferences
      expect_fixture "$name preserves or writes the legacy preference" \
        preference_is_exactly_once "$directory/config" "$expected_preference"
      expect_fixture "$name preserves or writes the active-profile preference" \
        preference_is_exactly_once "$directory/profiles/office.conf" "$expected_preference"
      if [[ -n "$legacy_preference" ]]; then
        expect_fixture "$name keeps the legacy config byte-identical" \
          /usr/bin/cmp -s "$directory/config.expected" "$directory/config"
        expect_fixture "$name keeps the active profile byte-identical" \
          /usr/bin/cmp -s "$directory/profiles/office.conf.expected" \
          "$directory/profiles/office.conf"
      fi
    }

    run_valid_fixture "missing-preference" "" "" "0"
    run_valid_fixture "existing-zero" "0" "0" "0"
    run_valid_fixture "existing-one" "1" "1" "1"
    run_valid_fixture "existing-malformed" "malformed" "malformed" "malformed"

    symlink_ancestor_root="$fixture_root/symlink-ancestor"
    symlink_ancestor_external="$fixture_root/symlink-ancestor-external/.config/gdrive-tiger-backup"
    /bin/mkdir -p "$symlink_ancestor_root/home" "$symlink_ancestor_external"
    create_valid_fixture "$symlink_ancestor_external" "" ""
    /bin/ln -s "$fixture_root/symlink-ancestor-external/.config" \
      "$symlink_ancestor_root/home/.config"
    set_fixture_paths "$symlink_ancestor_root/home/.config/gdrive-tiger-backup"
    if migrate_notification_success_preferences >/dev/null 2>&1; then
      ancestor_status=0
    else
      ancestor_status=$?
    fi
    expect_fixture "a symlinked config-store ancestor fails closed" \
      test "$ancestor_status" = "73"
    expect_fixture "a symlinked config-store ancestor leaves legacy config untouched" \
      preference_is_absent "$symlink_ancestor_external/config"
    expect_fixture "a symlinked config-store ancestor leaves profile untouched" \
      preference_is_absent "$symlink_ancestor_external/profiles/office.conf"

    missing_store_root="$fixture_root/symlink-ancestor-missing-store"
    missing_store_external="$fixture_root/symlink-ancestor-missing-store-external/.config"
    /bin/mkdir -p "$missing_store_root/home" "$missing_store_external"
    /bin/ln -s "$missing_store_external" "$missing_store_root/home/.config"
    missing_store="$missing_store_root/home/.config/gdrive-tiger-backup"
    if require_trusted_config_store "$missing_store" && /bin/mkdir -p "$missing_store"; then
      missing_store_status=0
    else
      missing_store_status=$?
    fi
    expect_fixture "the pre-mkdir guard rejects a symlinked config ancestor" \
      test "$missing_store_status" = "73"
    expect_fixture "the pre-mkdir guard creates nothing through a symlink" \
      test ! -e "$missing_store_external/gdrive-tiger-backup"

    symlink_home_root="$fixture_root/symlink-home"
    symlink_home_external="$fixture_root/symlink-home-external"
    /bin/mkdir -p "$symlink_home_external"
    /bin/ln -s "$symlink_home_external" "$symlink_home_root"
    if require_trusted_config_store "$symlink_home_root/.config/gdrive-tiger-backup"; then
      symlink_home_status=0
    else
      symlink_home_status=$?
    fi
    expect_fixture "a symlinked configured home fails closed" \
      test "$symlink_home_status" = "73"

    symlink_root_parent="$fixture_root/symlink-config-root"
    symlink_root_external="$fixture_root/symlink-config-root-external"
    /bin/mkdir -p "$symlink_root_parent" "$symlink_root_external"
    create_valid_fixture "$symlink_root_external" "" ""
    /bin/ln -s "$symlink_root_external" "$symlink_root_parent/gdrive-tiger-backup"
    set_fixture_paths "$symlink_root_parent/gdrive-tiger-backup"
    if migrate_notification_success_preferences >/dev/null 2>&1; then
      config_root_status=0
    else
      config_root_status=$?
    fi
    expect_fixture "a symlinked config-store root fails closed" \
      test "$config_root_status" = "73"
    expect_fixture "a symlinked config-store root leaves legacy config untouched" \
      preference_is_absent "$symlink_root_external/config"
    expect_fixture "a symlinked config-store root leaves profile untouched" \
      preference_is_absent "$symlink_root_external/profiles/office.conf"

    pointer_directory="$fixture_root/symlink-pointer"
    create_valid_fixture "$pointer_directory" "" ""
    /bin/mv "$pointer_directory/active-profile" \
      "$pointer_directory/active-profile.original"
    printf 'office\n' >"$pointer_directory/outside-pointer"
    /bin/ln -s "$pointer_directory/outside-pointer" \
      "$pointer_directory/active-profile"
    set_fixture_paths "$pointer_directory"
    if migrate_notification_success_preferences >/dev/null 2>&1; then
      pointer_status=0
    else
      pointer_status=$?
    fi
    expect_fixture "a symlinked active-profile pointer fails closed" test "$pointer_status" = "73"
    expect_fixture "a symlinked active-profile pointer leaves legacy config untouched" \
      preference_is_absent "$pointer_directory/config"
    expect_fixture "a symlinked active-profile pointer leaves profile untouched" \
      preference_is_absent "$pointer_directory/profiles/office.conf"

    profile_symlink_directory="$fixture_root/symlink-profile"
    /bin/mkdir -p "$profile_symlink_directory/profiles"
    printf 'GDRIVE_BACKUP_PROFILE_ID=legacy\n' >"$profile_symlink_directory/config"
    printf 'GDRIVE_BACKUP_PROFILE_ID=office\n' >"$profile_symlink_directory/outside.conf"
    /bin/ln -s "$profile_symlink_directory/outside.conf" \
      "$profile_symlink_directory/profiles/office.conf"
    printf 'office\n' >"$profile_symlink_directory/active-profile"
    set_fixture_paths "$profile_symlink_directory"
    if migrate_notification_success_preferences >/dev/null 2>&1; then
      profile_symlink_status=0
    else
      profile_symlink_status=$?
    fi
    expect_fixture "a symlinked active profile fails closed" test "$profile_symlink_status" = "73"
    expect_fixture "a symlinked active profile leaves legacy config untouched" \
      preference_is_absent "$profile_symlink_directory/config"
    expect_fixture "a symlinked active profile leaves its target untouched" \
      preference_is_absent "$profile_symlink_directory/outside.conf"

    mismatch_directory="$fixture_root/id-mismatch"
    /bin/mkdir -p "$mismatch_directory/profiles"
    printf 'GDRIVE_BACKUP_PROFILE_ID=legacy\n' >"$mismatch_directory/config"
    printf 'GDRIVE_BACKUP_PROFILE_ID=other\n' >"$mismatch_directory/profiles/office.conf"
    printf 'office\n' >"$mismatch_directory/active-profile"
    set_fixture_paths "$mismatch_directory"
    if migrate_notification_success_preferences >/dev/null 2>&1; then
      mismatch_status=0
    else
      mismatch_status=$?
    fi
    expect_fixture "an active-profile identity mismatch fails closed" test "$mismatch_status" = "73"
    expect_fixture "an active-profile identity mismatch leaves legacy config untouched" \
      preference_is_absent "$mismatch_directory/config"
    expect_fixture "an active-profile identity mismatch leaves profile untouched" \
      preference_is_absent "$mismatch_directory/profiles/office.conf"

    run_repeated_profile_id_fixture() {
      local name="$1"
      local second_profile_id="$2"
      local directory="$fixture_root/$name"
      /bin/mkdir -p "$directory/profiles"
      printf 'GDRIVE_BACKUP_PROFILE_ID=legacy\n' >"$directory/config"
      printf 'GDRIVE_BACKUP_PROFILE_ID=office\nGDRIVE_BACKUP_PROFILE_ID=%s\n' \
        "$second_profile_id" >"$directory/profiles/office.conf"
      printf 'office\n' >"$directory/active-profile"
      /bin/cp "$directory/config" "$directory/config.expected"
      /bin/cp "$directory/profiles/office.conf" \
        "$directory/profiles/office.conf.expected"
      set_fixture_paths "$directory"
      if migrate_notification_success_preferences >/dev/null 2>&1; then
        repeated_profile_id_status=0
      else
        repeated_profile_id_status=$?
      fi
      expect_fixture "$name fails closed" test "$repeated_profile_id_status" = "73"
      expect_fixture "$name keeps the legacy config byte-identical" \
        /usr/bin/cmp -s "$directory/config.expected" "$directory/config"
      expect_fixture "$name keeps the active profile byte-identical" \
        /usr/bin/cmp -s "$directory/profiles/office.conf.expected" \
        "$directory/profiles/office.conf"
    }
    run_repeated_profile_id_fixture "a duplicate active-profile identity" "office"
    run_repeated_profile_id_fixture "a conflicting active-profile identity" "other"

    legacy_symlink_directory="$fixture_root/symlink-legacy"
    /bin/mkdir -p "$legacy_symlink_directory"
    printf 'GDRIVE_BACKUP_PROFILE_ID=legacy\n' >"$legacy_symlink_directory/outside.conf"
    /bin/ln -s "$legacy_symlink_directory/outside.conf" "$legacy_symlink_directory/config"
    set_fixture_paths "$legacy_symlink_directory"
    if migrate_notification_success_preferences >/dev/null 2>&1; then
      legacy_symlink_status=0
    else
      legacy_symlink_status=$?
    fi
    expect_fixture "a symlinked legacy config fails closed" test "$legacy_symlink_status" = "73"
    expect_fixture "a symlinked legacy config leaves its target untouched" \
      preference_is_absent "$legacy_symlink_directory/outside.conf"

    [[ "$fixture_failures" == "0" ]]
  ); then
    :
  else
    failures=$((failures + 1))
  fi
  "$ROOT/scripts/trash-path.sh" "$fixture_root" "$runner"
}

run_success_notification_migration_fixture "$ROOT/install.sh" "source installer"
run_success_notification_migration_fixture "$ROOT/packaging/scripts/postinstall" "package installer"

if (( failures > 0 )); then
  printf '%s release metadata check(s) failed.\n' "$failures"
  exit 1
fi

printf 'All release metadata checks passed.\n'
