# shellcheck shell=bash
# Linux platform layer for backup-google-drive.sh.
#
# The engine sources this file before it reads any configuration. It holds
# every function that talks to Linux-only tools (GNU stat/find, findmnt,
# lsblk, /proc/mounts) or relies on the Linux mount layout. It provides the
# same contract as lib/platform-macos.sh; tests/platform-contract-test.sh
# checks that both files define every name, and tests/platform-linux-test.sh
# exercises the primitives on Linux.
#
# Contract:
#   PLATFORM_VOLUMES_ROOT       where removable volumes appear
#   PLATFORM_REQUIRED_TOOLS     extra commands the engine needs on this OS
#   platform_home_directory     home directory when HOME is unset
#   platform_system_locale      user locale for the language fallback
#   platform_stat_size PATH     size in bytes
#   platform_stat_mtime PATH    modification time, seconds since the epoch
#   platform_stat_owner PATH    numeric owner uid
#   platform_stat_device PATH   device id of the file system holding PATH
#   platform_directory_devices ROOT
#                               device id of every directory below ROOT,
#                               without crossing into other file systems
#   platform_first_symlink ROOT  first symbolic link below ROOT, same file system
#   platform_confirm_dialog_available
#   platform_confirm_dialog TITLE DETAIL PRIMARY SECONDARY
#                               prints "yes" or "no"
#   NAS mounts:   nas_mount_from_url, find_nas_mount_for_url,
#                 nas_mount_is_verified
#   Destinations: find_setup_candidate, capture_setup_source_identity,
#                 capture_named_apfs_volume_uuids,
#                 recover_existing_named_apfs_volume,
#                 inspect_path_only_apfs_binding, create_apfs_backup_volume,
#                 resolve_configured_apfs_volume,
#                 validate_configured_apfs_volume_identity,
#                 validate_configured_apfs_tree,
#                 validate_encrypted_apfs_destination,
#                 external_volume_confirmation_detail,
#                 ioreg_media_name_for_bsd_id
#   Property lists: plist_value, plist_data_value
#
# Linux differences from macOS:
# - There is no APFS. A local destination is any mounted directory whose
#   filesystem UUID (findmnt) matches GDRIVE_BACKUP_VOLUME_UUID; the core
#   keeps using its APFS_* globals for that identity, the names are kept
#   until the generic destination-identity interface lands.
# - Creating or recovering volumes is not offered: the APFS setup functions
#   fail closed, so an unattended run can never reformat or invent a target.
# - There is no desktop confirmation dialog. Unattended runs never prompt;
#   interactive confirmation is a configuration decision (phase 4 TUI).

# The engine reads these after sourcing this file.
# shellcheck disable=SC2034
PLATFORM_VOLUMES_ROOT="/media"
# shellcheck disable=SC2034
PLATFORM_REQUIRED_TOOLS=(findmnt)

platform_home_directory() {
  getent passwd "$(id -un)" 2>/dev/null | awk -F: '{print $6}'
}

platform_system_locale() {
  printf '%s' "${LANG:-}"
}

platform_stat_size() {
  stat -c '%s' "$1"
}

platform_stat_mtime() {
  stat -c '%Y' "$1"
}

platform_stat_owner() {
  stat -c '%u' "$1"
}

platform_stat_device() {
  stat -c '%d' "$1"
}

platform_directory_devices() {
  find "$1" -xdev -type d -exec stat -c '%d' {} +
}

platform_first_symlink() {
  find "$1" -xdev -type l -print -quit
}

platform_confirm_dialog_available() {
  return 1
}

platform_confirm_dialog() {
  printf '%s\n' "no"
}

nas_mount_from_url() {
  # A Linux NAS destination is used through its configured mount point
  # (fstab, systemd .mount or autofs); a URL alone names no local path.
  return 0
}

find_nas_mount_for_url() {
  local url_host source target filesystem source_host
  url_host="$(nas_host_from_url "$1")"
  [[ -n "$url_host" ]] || return 0

  while read -r source target filesystem; do
    case "$filesystem" in
      cifs|smb3|nfs|nfs4) ;;
      *) continue ;;
    esac
    source="${source#//}"
    source="${source#*@}"
    source_host="$(lowercase "${source%%/*}")"
    [[ "$source_host" == "$url_host" ]] || continue
    printf '%s' "$target"
    return 0
  done < <(findmnt -rn -o SOURCE,TARGET,FSTYPE 2>/dev/null)
  return 0
}

nas_mount_is_verified() {
  local filesystem

  [[ -d "$NAS_MOUNT" && ! -L "$NAS_MOUNT" ]] || return 1
  filesystem="$(findmnt -rn --target "$NAS_MOUNT" -o FSTYPE 2>/dev/null || true)"
  case "$filesystem" in
    cifs|smb3|nfs|nfs4) return 0 ;;
  esac
  return 1
}

# --- Destination identity (filesystem UUID instead of APFS volume UUID) ---

linux_filesystem_uuid_for_target() {
  findmnt -rn --target "$1" -o UUID 2>/dev/null || true
}

linux_mount_target_for_uuid() {
  findmnt -rn -S "UUID=$1" -o TARGET 2>/dev/null | head -n 1
}

resolve_configured_apfs_volume() {
  local mount_point resolved_mount configured_volume configured_destination
  local destination_suffix resolved_destination existing_ancestor
  local mount_device destination_device

  [[ "$BACKUP_TARGET" == "apfs" && -n "$BACKUP_VOLUME_UUID" ]] || return 0
  if [[ -L "$CONFIGURED_APFS_VOLUME" ]]; then
    log "FEHLER: Der konfigurierte Zielpfad darf kein symbolischer Link sein."
    return 69
  fi
  if [[ ! "$BACKUP_VOLUME_UUID" =~ ^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$ ]]; then
    log "FEHLER: GDRIVE_BACKUP_VOLUME_UUID ist keine gueltige Dateisystem-UUID."
    return 64
  fi
  mount_point="$(linux_mount_target_for_uuid "$BACKUP_VOLUME_UUID")"
  if [[ -z "$mount_point" ]]; then
    log "FEHLER: Das konfigurierte Backup-Dateisystem ist nicht eingehängt."
    return 69
  fi
  if ! resolved_mount="$(canonical_existing_directory "$mount_point")"; then
    log "FEHLER: Das konfigurierte Backup-Dateisystem ist nicht eingehängt."
    return 69
  fi

  configured_volume="$CONFIGURED_APFS_VOLUME"
  configured_destination="$CONFIGURED_APFS_DEST_ROOT"
  if [[ "$configured_destination" == "$configured_volume" ]]; then
    DEST_ROOT="$resolved_mount"
  elif [[ "$configured_destination" == "$configured_volume/"* ]]; then
    destination_suffix="${configured_destination#"$configured_volume"}"
    case "/${destination_suffix#/}/" in
      *"//"*|*"/./"*|*"/../"*)
        log "FEHLER: Das Ziel enthaelt unsichere Pfadbestandteile."
        return 69
        ;;
    esac
    resolved_destination="${resolved_mount}${destination_suffix}"
    if path_has_existing_symlink_component "$resolved_mount" "$resolved_destination"; then
      log "FEHLER: Das Ziel darf keine symbolisch verknuepfte Pfadkomponente enthalten."
      return 69
    fi
    if ! existing_ancestor="$(canonical_existing_ancestor "$resolved_destination")"; then
      log "FEHLER: Das Ziel kann nicht sicher aufgeloest werden."
      return 69
    fi
    case "$existing_ancestor/" in
      "$resolved_mount/"*) ;;
      *)
        log "FEHLER: Das Ziel verlaesst das konfigurierte Backup-Dateisystem."
        return 69
        ;;
    esac
    if ! mount_device="$(platform_stat_device "$resolved_mount" 2>/dev/null)" ||
       ! destination_device="$(platform_stat_device "$existing_ancestor" 2>/dev/null)" ||
       [[ -z "$mount_device" || "$mount_device" != "$destination_device" ]]; then
      log "FEHLER: Das Ziel liegt nicht auf dem konfigurierten Backup-Dateisystem."
      return 69
    fi
    DEST_ROOT="$resolved_destination"
  else
    log "FEHLER: Das Ziel liegt ausserhalb des konfigurierten Backup-Dateisystems."
    return 69
  fi
  VOLUME="$resolved_mount"
  log "Backup-Dateisystem per UUID aufgeloest: $VOLUME"
  return 0
}

validate_configured_apfs_volume_identity() {
  local current_uuid current_real current_device current_source

  [[ "$BACKUP_TARGET" == "apfs" && -n "$BACKUP_VOLUME_UUID" ]] || return 0
  if ! current_real="$(canonical_existing_directory "$VOLUME")"; then
    log "FEHLER: Das Backup-Dateisystem ist nicht mehr eingehängt."
    return 1
  fi
  current_uuid="$(linux_filesystem_uuid_for_target "$current_real")"
  if [[ -z "$current_uuid" ||
        "$(normalized_apfs_uuid "$current_uuid")" != "$(normalized_apfs_uuid "$BACKUP_VOLUME_UUID")" ]]; then
    log "FEHLER: Identitaet des Backup-Dateisystems stimmt nicht mehr."
    return 1
  fi
  if ! current_device="$(platform_stat_device "$current_real" 2>/dev/null)" ||
     [[ -z "$current_device" ]]; then
    log "FEHLER: Dateisystem-ID des Backup-Dateisystems ist nicht lesbar."
    return 1
  fi
  current_source="$(findmnt -rn --target "$current_real" -o SOURCE 2>/dev/null || true)"

  if [[ -z "$APFS_VOLUME_UUID" ]]; then
    APFS_VOLUME_REAL="$current_real"
    APFS_VOLUME_DEVICE="$current_device"
    APFS_VOLUME_UUID="$current_uuid"
    APFS_VOLUME_IDENTIFIER="$current_source"
  elif [[ "$current_real" != "$APFS_VOLUME_REAL" ||
          "$current_device" != "$APFS_VOLUME_DEVICE" ||
          "$(normalized_apfs_uuid "$current_uuid")" != "$(normalized_apfs_uuid "$APFS_VOLUME_UUID")" ||
          "$current_source" != "$APFS_VOLUME_IDENTIFIER" ]]; then
    log "FEHLER: Das Backup-Dateisystem wurde waehrend des Laufs ausgetauscht."
    return 1
  fi
  return 0
}

validate_configured_apfs_tree() {
  local root="$1"

  [[ "$BACKUP_TARGET" == "apfs" && -n "$BACKUP_VOLUME_UUID" ]] || return 0
  [[ -e "$root" || -L "$root" ]] || return 0
  if ! validate_configured_apfs_paths "$root"; then
    return 1
  fi
  if [[ -L "$root" ]]; then
    log "FEHLER: Symbolischer Link im UUID-gebundenen Ziel ist nicht zulaessig: $(safe_name "$root")"
    return 1
  fi
  # One streamed walk catches both link redirections and nested mount points.
  if ! find "$root" -xdev \
      \( -type l -print \) -o \
      \( -type d -exec /bin/bash -c '
        stat -c "%d" "$@" 2>/dev/null ||
          printf "%s\n" "__GDRIVE_APFS_STAT_FAILED__"
      ' _ {} + \) 2>/dev/null |
      awk -v expected_device="$APFS_VOLUME_DEVICE" '
        $0 != expected_device { unsafe = 1 }
        END { exit unsafe ? 1 : 0 }
      '; then
    log "FEHLER: Zielbaum enthaelt einen symbolischen Link, ein fremdes Dateisystem oder einen unlesbaren Pfad: $(safe_name "$root")"
    return 1
  fi
  return 0
}

validate_encrypted_apfs_destination() {
  # APFS encryption is a macOS property. rclone-crypt is the Linux option;
  # fail closed instead of pretending an APFS check happened.
  [[ "$ENCRYPTION" == "apfs" ]] || return 0
  log "FEHLER: APFS-Verschluesselung wird unter Linux nicht unterstuetzt; bitte rclone-crypt verwenden."
  return 1
}

# --- APFS setup: not offered on Linux, always fails closed ---

find_setup_candidate() {
  return 1
}

capture_setup_source_identity() {
  log "FEHLER: Automatisches Einrichten eines Backup-Volumes wird unter Linux nicht unterstuetzt."
  return 1
}

capture_named_apfs_volume_uuids() {
  return 1
}

recover_existing_named_apfs_volume() {
  return 1
}

inspect_path_only_apfs_binding() {
  return 1
}

create_apfs_backup_volume() {
  log "FEHLER: Automatisches Erstellen eines Backup-Volumes wird unter Linux nicht unterstuetzt."
  return 1
}

external_volume_confirmation_detail() {
  return 1
}

ioreg_media_name_for_bsd_id() {
  return 1
}

# --- Property lists do not exist on Linux ---

plist_value() {
  return 1
}

plist_data_value() {
  return 1
}
