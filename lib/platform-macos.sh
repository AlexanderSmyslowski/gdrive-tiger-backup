# shellcheck shell=bash
# macOS platform layer for backup-google-drive.sh.
#
# The engine sources this file before it reads any configuration. It holds
# every function that talks to macOS-only tools (diskutil, ioreg, plutil,
# osascript, BSD stat/find, /sbin/mount) or relies on the /Volumes layout.
# A future platform file (for example platform-linux.sh) has to provide the
# same names; tests/platform-contract-test.sh checks the list below.
#
# Contract:
#   PLATFORM_VOLUMES_ROOT       where removable volumes appear
#   PLATFORM_REQUIRED_TOOLS     extra commands the engine needs on this OS
#   platform_home_directory     home directory when HOME is unset
#   platform_system_locale      user locale for the language fallback
#   platform_date_parse FORMAT VALUE OUTPUT_FORMAT
#   platform_date_from_epoch EPOCH OUTPUT_FORMAT
#   platform_stat_size PATH     size in bytes
#   platform_stat_mtime PATH    modification time, seconds since the epoch
#   platform_stat_owner PATH    numeric owner uid
#   platform_stat_device PATH   device id of the file system holding PATH
#   platform_directory_devices ROOT
#                               device id of every directory below ROOT,
#                               without crossing into other file systems
#   platform_first_symlink ROOT  first symbolic link below ROOT, same file system
#   platform_sha256 [-- FILE]   "<hex digest>  <name>" of FILE or of stdin
#   platform_destination_device_info PATH
#                               "uuid TAB device TAB bytes TAB solid TAB bus"
#                               for the disk holding PATH; solid is yes, no or
#                               empty, unknown fields stay empty
#   platform_notify TITLE BODY URGENCY
#                               desktop notification (URGENCY normal|critical);
#                               a no-op where the app shows notifications
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

# The engine reads these after sourcing this file.
# shellcheck disable=SC2034
PLATFORM_VOLUMES_ROOT="/Volumes"
# shellcheck disable=SC2034
PLATFORM_REQUIRED_TOOLS=(diskutil plutil)

platform_home_directory() {
  /usr/bin/dscl . -read "/Users/$(/usr/bin/id -un)" NFSHomeDirectory 2>/dev/null | /usr/bin/awk '{print $2}'
}

platform_system_locale() {
  local locale="${LANG:-}"
  if command -v defaults >/dev/null 2>&1; then
    locale="$(defaults read -g AppleLocale 2>/dev/null || printf '%s' "$locale")"
  fi
  printf '%s' "$locale"
}

platform_date_parse() {
  LC_ALL=C /bin/date -j -f "$1" "$2" "$3"
}

platform_date_from_epoch() {
  /bin/date -r "$1" "$2"
}

platform_stat_size() {
  /usr/bin/stat -f '%z' "$1"
}

platform_stat_mtime() {
  /usr/bin/stat -f '%m' "$1"
}

# Resolved through PATH like the original call, so tests can substitute it.
platform_stat_owner() {
  stat -f '%u' "$1"
}

platform_stat_device() {
  /usr/bin/stat -f '%d' "$1"
}

platform_directory_devices() {
  /usr/bin/find -x "$1" -type d -exec /usr/bin/stat -f '%d' {} +
}

platform_first_symlink() {
  /usr/bin/find -x "$1" -type l -print -quit
}

platform_sha256() {
  /usr/bin/shasum -a 256 "$@"
}

# Describes the physical disk behind a backup volume for the run history, so
# the app can tell "Samsung PSSD T7 · SSD · 1 TB" from another disk that holds
# a volume with the same name. Uses the whole disk behind the APFS container.
platform_destination_device_info() {
  local volume_plist="" store_plist="" whole_plist="" uuid="" store="" whole=""
  local device="" size="" solid="" bus=""

  volume_plist="$(run_with_timeout 8 "$DISKUTIL_BIN" info -plist "$1" 2>/dev/null)" || return 1
  uuid="$(plist_data_value "$volume_plist" VolumeUUID || true)"
  store="$(plist_data_value "$volume_plist" APFSPhysicalStores.0.APFSPhysicalStore || true)"
  if [[ "$store" =~ ^disk[0-9]+s[0-9]+$ ]]; then
    store_plist="$(run_with_timeout 8 "$DISKUTIL_BIN" info -plist "$store" 2>/dev/null || true)"
    whole="$(plist_data_value "$store_plist" ParentWholeDisk || true)"
  else
    whole="$(plist_data_value "$volume_plist" ParentWholeDisk || true)"
  fi
  if [[ "$whole" =~ ^disk[0-9]+$ ]]; then
    whole_plist="$(run_with_timeout 8 "$DISKUTIL_BIN" info -plist "$whole" 2>/dev/null || true)"
  fi
  [[ -n "$whole_plist" ]] || whole_plist="$volume_plist"

  device="$(plist_data_value "$whole_plist" IORegistryEntryName || true)"
  device="${device% Media}"
  if [[ -z "$device" ]]; then
    device="$(first_nonempty_display_value \
      "$(plist_data_value "$whole_plist" DeviceModel || true)" \
      "$(plist_data_value "$whole_plist" MediaName || true)" || true)"
  fi
  device="$(display_metadata_value "$device")"
  size="$(plist_data_value "$whole_plist" TotalSize || true)"
  [[ "$size" =~ ^[0-9]{1,16}$ ]] || size=""
  case "$(plist_data_value "$whole_plist" SolidState || true)" in
    true) solid="yes" ;;
    false) solid="no" ;;
  esac
  bus="$(display_metadata_value "$(plist_data_value "$whole_plist" BusProtocol || true)")"
  [[ "$uuid" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]] || uuid=""
  printf '%s\t%s\t%s\t%s\t%s\n' "$uuid" "${device//$'\t'/ }" "$size" "$solid" "${bus//$'\t'/ }"
}

# The macOS app shows notifications itself (NotificationSupport); the engine
# stays silent so nothing is announced twice.
platform_notify() {
  return 0
}

platform_confirm_dialog_available() {
  command -v osascript >/dev/null 2>&1
}

platform_confirm_dialog() {
  /usr/bin/osascript - "$1" "$2" "$3" "$4" <<'OSA'
on run argv
  set dialogTitle to item 1 of argv
  set dialogDetail to item 2 of argv
  set primaryButton to item 3 of argv
  set secondaryButton to item 4 of argv
  try
    set answer to display dialog dialogTitle & return & return & dialogDetail with title "Google Drive Backup" buttons {secondaryButton, primaryButton} default button secondaryButton cancel button secondaryButton giving up after 120
    if gave up of answer then return "no"
    if button returned of answer is primaryButton then return "yes"
  end try
  return "no"
end run
OSA
}

nas_mount_from_url() {
  local url="${1%%\?*}"
  local without_scheme path share
  url="${url%/}"

  without_scheme="${url#*://}"
  if [[ "$without_scheme" == "$url" || "$without_scheme" != */* ]]; then
    return 0
  fi

  path="${without_scheme#*/}"
  share="${path%%/*}"
  if [[ -n "$share" ]]; then
    printf '/Volumes/%s' "$share"
  fi
}

find_nas_mount_for_url() {
  local host line source mount_path source_host
  host="$(nas_host_from_url "$1")"
  [[ -n "$host" ]] || return 0

  while IFS= read -r line; do
    [[ "$line" == *" on /Volumes/"* ]] || continue
    [[ "$line" == *" (smbfs,"* || "$line" == *" (afpfs,"* || "$line" == *" (nfs,"* ]] || continue
    source="${line%% on /Volumes/*}"
    source="${source#//}"
    source="${source#*@}"
    source_host="${source%%/*}"
    source_host="$(lowercase "$source_host")"
    [[ "$source_host" == "$host" ]] || continue
    mount_path="${line#* on }"
    mount_path="${mount_path%% (*}"
    printf '%s' "$mount_path"
    return 0
  done < <(/sbin/mount)
}

plist_data_value() {
  local plist_data="$1"
  local key="$2"
  printf '%s' "$plist_data" | /usr/bin/plutil -extract "$key" raw -o - - 2>/dev/null
}

resolve_configured_apfs_volume() {
  local plist_data filesystem mount_point volume_uuid writable_media
  local configured_volume configured_destination resolved_mount destination_suffix
  local resolved_destination existing_ancestor mount_device destination_device

  [[ "$BACKUP_TARGET" == "apfs" && -n "$BACKUP_VOLUME_UUID" ]] || return 0
  if [[ -L "$CONFIGURED_APFS_VOLUME" ]]; then
    log "FEHLER: Der konfigurierte APFS-Volume-Pfad darf kein symbolischer Link sein."
    return 69
  fi
  if [[ ! "$BACKUP_VOLUME_UUID" =~ ^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$ ]]; then
    log "FEHLER: GDRIVE_BACKUP_VOLUME_UUID ist keine gueltige APFS-Volume-UUID."
    return 64
  fi
  if [[ ! -x "$DISKUTIL_BIN" ]]; then
    log "FEHLER: diskutil fuer die APFS-Volume-Identitaet fehlt: $(safe_name "$DISKUTIL_BIN")"
    return 127
  fi
  if ! plist_data="$(run_with_timeout 8 "$DISKUTIL_BIN" info -plist "$BACKUP_VOLUME_UUID" 2>/dev/null)"; then
    log "FEHLER: Das konfigurierte APFS-Backup-Volume ist nicht verfuegbar."
    return 69
  fi

  filesystem="$(plist_data_value "$plist_data" FilesystemType || true)"
  mount_point="$(plist_data_value "$plist_data" MountPoint || true)"
  volume_uuid="$(plist_data_value "$plist_data" VolumeUUID || true)"
  writable_media="$(plist_data_value "$plist_data" WritableMedia || true)"
  if [[ "$filesystem" != "apfs" || -z "$mount_point" ||
        "$(normalized_apfs_uuid "$volume_uuid")" != "$(normalized_apfs_uuid "$BACKUP_VOLUME_UUID")" ||
        "$writable_media" != "true" ]]; then
    log "FEHLER: diskutil bestaetigt nicht das konfigurierte APFS-Backup-Volume."
    return 69
  fi
  if ! resolved_mount="$(canonical_existing_directory "$mount_point")"; then
    log "FEHLER: Das konfigurierte APFS-Backup-Volume ist nicht eingehängt."
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
        log "FEHLER: Das APFS-Ziel enthaelt unsichere Pfadbestandteile."
        return 69
        ;;
    esac
    resolved_destination="${resolved_mount}${destination_suffix}"
    if path_has_existing_symlink_component "$resolved_mount" "$resolved_destination"; then
      log "FEHLER: Das APFS-Ziel darf keine symbolisch verknuepfte Pfadkomponente enthalten."
      return 69
    fi
    if ! existing_ancestor="$(canonical_existing_ancestor "$resolved_destination")"; then
      log "FEHLER: Das APFS-Ziel kann nicht sicher aufgeloest werden."
      return 69
    fi
    case "$existing_ancestor/" in
      "$resolved_mount/"*) ;;
      *)
        log "FEHLER: Das APFS-Ziel verlaesst das konfigurierte Backup-Volume."
        return 69
        ;;
    esac
    if ! mount_device="$(/usr/bin/stat -f '%d' "$resolved_mount" 2>/dev/null)" ||
       ! destination_device="$(/usr/bin/stat -f '%d' "$existing_ancestor" 2>/dev/null)" ||
       [[ -z "$mount_device" || "$mount_device" != "$destination_device" ]]; then
      log "FEHLER: Das APFS-Ziel liegt nicht auf dem konfigurierten Backup-Volume."
      return 69
    fi
    DEST_ROOT="$resolved_destination"
  else
    log "FEHLER: Das APFS-Ziel liegt ausserhalb des konfigurierten Backup-Volumes."
    return 69
  fi
  VOLUME="$resolved_mount"
  VALIDATED_APFS_VOLUME_PLIST="$plist_data"
  log "APFS-Backup-Volume per UUID aufgeloest: $VOLUME"
  return 0
}

validate_configured_apfs_volume_identity() {
  local plist_data filesystem mount_point volume_uuid volume_identifier
  local mount_real current_real current_device

  [[ "$BACKUP_TARGET" == "apfs" && -n "$BACKUP_VOLUME_UUID" ]] || return 0
  if ! plist_data="$(run_with_timeout 8 "$DISKUTIL_BIN" info -plist "$BACKUP_VOLUME_UUID" 2>/dev/null)"; then
    log "FEHLER: Identitaet des APFS-Backup-Volumes ist nicht mehr lesbar."
    return 1
  fi
  filesystem="$(plist_data_value "$plist_data" FilesystemType || true)"
  mount_point="$(plist_data_value "$plist_data" MountPoint || true)"
  volume_uuid="$(plist_data_value "$plist_data" VolumeUUID || true)"
  volume_identifier="$(plist_data_value "$plist_data" DeviceIdentifier || true)"
  if [[ "$filesystem" != "apfs" || -z "$mount_point" || -z "$volume_identifier" ||
        "$(normalized_apfs_uuid "$volume_uuid")" != "$(normalized_apfs_uuid "$BACKUP_VOLUME_UUID")" ]]; then
    log "FEHLER: Identitaet des APFS-Backup-Volumes stimmt nicht mehr."
    return 1
  fi
  if ! current_real="$(canonical_existing_directory "$VOLUME")" ||
     ! mount_real="$(canonical_existing_directory "$mount_point")" ||
     [[ "$current_real" != "$mount_real" ]]; then
    log "FEHLER: Das APFS-Backup-Volume ist nicht mehr am aufgeloesten Mountpunkt."
    return 1
  fi
  if ! current_device="$(/usr/bin/stat -f '%d' "$current_real" 2>/dev/null)" ||
     [[ -z "$current_device" ]]; then
    log "FEHLER: Dateisystem-ID des APFS-Backup-Volumes ist nicht lesbar."
    return 1
  fi

  if [[ -z "$APFS_VOLUME_UUID" ]]; then
    APFS_VOLUME_REAL="$current_real"
    APFS_VOLUME_DEVICE="$current_device"
    APFS_VOLUME_UUID="$volume_uuid"
    APFS_VOLUME_IDENTIFIER="$volume_identifier"
  elif [[ "$current_real" != "$APFS_VOLUME_REAL" ||
          "$current_device" != "$APFS_VOLUME_DEVICE" ||
          "$(normalized_apfs_uuid "$volume_uuid")" != "$(normalized_apfs_uuid "$APFS_VOLUME_UUID")" ||
          "$volume_identifier" != "$APFS_VOLUME_IDENTIFIER" ]]; then
    log "FEHLER: Das APFS-Backup-Volume wurde waehrend des Laufs ausgetauscht."
    return 1
  fi
  VALIDATED_APFS_VOLUME_PLIST="$plist_data"
  return 0
}

validate_encrypted_apfs_destination() {
  local plist_data filesystem encrypted mount_point locked volume_uuid volume_identifier
  local mount_real current_real current_device active_path initial_validation=0

  [[ "$ENCRYPTION" == "apfs" ]] || return 0

  if [[ ! -x "$DISKUTIL_BIN" ]]; then
    log "FEHLER: diskutil fuer die Verschluesselungspruefung fehlt: $(safe_name "$DISKUTIL_BIN")"
    return 1
  fi
  if ! plist_data="$(run_with_timeout 8 "$DISKUTIL_BIN" info -plist "$VOLUME" 2>/dev/null)"; then
    log "FEHLER: Verschluesselungsstatus des Backup-Volumes ist nicht lesbar."
    return 1
  fi

  filesystem="$(plist_data_value "$plist_data" FilesystemType || true)"
  encrypted="$(plist_data_value "$plist_data" Encryption || true)"
  mount_point="$(plist_data_value "$plist_data" MountPoint || true)"
  locked="$(plist_data_value "$plist_data" Locked || true)"
  volume_uuid="$(plist_data_value "$plist_data" VolumeUUID || true)"
  volume_identifier="$(plist_data_value "$plist_data" DeviceIdentifier || true)"
  if [[ "$filesystem" != "apfs" || "$encrypted" != "true" || "$locked" != "false" ||
        -z "$mount_point" || -z "$volume_uuid" || -z "$volume_identifier" ]]; then
    log "FEHLER: Backup-Volume ist nicht verschluesselt oder kein entsperrtes APFS-Volume."
    return 1
  fi

  if ! current_real="$(canonical_existing_directory "$VOLUME")" ||
     ! mount_real="$(canonical_existing_directory "$mount_point")" ||
     [[ "$current_real" != "$mount_real" ]]; then
    log "FEHLER: diskutil bestaetigt nicht den konfigurierten APFS-Mountpunkt."
    return 1
  fi
  if ! current_device="$(/usr/bin/stat -f '%d' "$current_real" 2>/dev/null)" ||
     [[ -z "$current_device" ]]; then
    log "FEHLER: Dateisystem-ID des verschluesselten Volumes ist nicht lesbar."
    return 1
  fi

  if [[ -z "$ENCRYPTED_VOLUME_UUID" ]]; then
    initial_validation=1
    ENCRYPTED_VOLUME_REAL="$current_real"
    ENCRYPTED_VOLUME_DEVICE="$current_device"
    ENCRYPTED_VOLUME_UUID="$volume_uuid"
    ENCRYPTED_VOLUME_IDENTIFIER="$volume_identifier"
  elif [[ "$current_real" != "$ENCRYPTED_VOLUME_REAL" ||
          "$current_device" != "$ENCRYPTED_VOLUME_DEVICE" ||
          "$volume_uuid" != "$ENCRYPTED_VOLUME_UUID" ||
          "$volume_identifier" != "$ENCRYPTED_VOLUME_IDENTIFIER" ]]; then
    log "FEHLER: Identitaet des verschluesselten Backup-Volumes hat sich waehrend des Laufs geaendert."
    return 1
  fi

  if ! path_is_on_encrypted_volume "$DEST_ROOT"; then
    return 1
  fi
  for active_path in \
    "$DEST_ROOT/My Drive" \
    "$DEST_ROOT/Shared with me" \
    "$DEST_ROOT/Shared Drives" \
    "$DEST_ROOT/Shared Drives"/* \
    "$DEST_ROOT/Shared Drives"/.[!.]* \
    "$DEST_ROOT/Shared Drives"/..?*; do
    if [[ -e "$active_path" || -L "$active_path" ]] &&
       ! path_is_on_encrypted_volume "$active_path"; then
      return 1
    fi
  done
  if [[ "$VERSIONING" == "1" ]] &&
     ! path_is_on_encrypted_volume "${DEST_ROOT%/}/$VERSIONS_SUBDIR"; then
    return 1
  fi

  if (( initial_validation == 1 )); then
    log "Verschluesseltes APFS-Ziel bestaetigt: $ENCRYPTED_VOLUME_REAL"
  fi
}

plist_value() {
  local plist="$1"
  local key="$2"
  /usr/bin/plutil -extract "$key" raw -o - "$plist" 2>/dev/null || true
}

ioreg_media_name_for_bsd_id() {
  local disk_id="$1"
  local registry_name=""

  [[ "$disk_id" =~ ^disk[0-9]+s[0-9]+$ ]] || return 1
  [[ -x "$IOREG_BIN" ]] || return 1

  # IOKit exposes the physical-store label immediately, while diskutil may
  # block for several seconds on an otherwise healthy USB disk. Associate the
  # label with the exact validated BSD ID; never print any other registry data.
  registry_name="$(
    run_with_timeout 3 "$IOREG_BIN" -r -c IOMedia -l -w 0 2>/dev/null |
      /usr/bin/awk -v bsd="$disk_id" '
        /<class IOMedia,/ {
          node = $0
          sub(/^.*\+-o[[:space:]]+/, "", node)
          sub(/[[:space:]]+<class IOMedia,.*$/, "", node)
          sub(/@[0-9]+$/, "", node)
        }
        index($0, "\"BSD Name\" = \"" bsd "\"") {
          print node
          exit
        }
      ' || true
  )"
  registry_name="$(display_metadata_value "$registry_name")"
  [[ -n "$registry_name" ]] || return 1
  printf '%s' "$registry_name"
}

external_volume_confirmation_detail() {
  local volume_reference="$VOLUME"
  local volume_plist="" physical_plist="" whole_plist=""
  local volume_name="" physical_store="" physical_store_count="" parent_whole=""
  local vendor="" model="" device_name="" entry_name="" media_name=""
  local physical_name_hint="" physical_size="" physical_bus=""
  local volume_size="" volume_bus=""
  local size="" bus="" capacity="" vendor_lower="" model_lower="" disk_detail=""

  if [[ -n "$BACKUP_VOLUME_UUID" ]]; then
    volume_reference="$BACKUP_VOLUME_UUID"
  fi
  # Reuse the plist accepted by the immediately preceding UUID/device check.
  # A legacy caller without that cache gets the same bounded identity lookup.
  volume_plist="$VALIDATED_APFS_VOLUME_PLIST"
  if [[ -z "$volume_plist" ]]; then
    volume_plist="$(run_with_timeout 8 "$DISKUTIL_BIN" info -plist "$volume_reference" 2>/dev/null || true)"
  fi
  volume_name="$(display_metadata_value "$(plist_data_value "$volume_plist" VolumeName || true)")"
  if [[ -z "$volume_name" ]]; then
    volume_name="$(display_metadata_value "$BACKUP_VOLUME_NAME")"
  fi
  if [[ -z "$volume_name" ]]; then
    volume_name="$(t backup_volume)"
  fi

  physical_store="$(plist_data_value "$volume_plist" APFSPhysicalStores.0.APFSPhysicalStore || true)"
  # Ask plutil for the array cardinality. Probing a missing numeric key path is
  # not portable: macOS 15 can return non-empty output for an out-of-range item.
  physical_store_count="$(plist_data_value "$volume_plist" APFSPhysicalStores || true)"
  volume_size="$(first_valid_size_value \
    "$(plist_data_value "$volume_plist" APFSContainerSize || true)" \
    "$(plist_data_value "$volume_plist" TotalSize || true)" || true)"
  volume_bus="$(display_metadata_value "$(plist_data_value "$volume_plist" BusProtocol || true)")"
  if [[ "$physical_store_count" =~ ^[0-9]+$ ]] &&
     (( physical_store_count > 1 )); then
    device_name="$(t storage_set)"
  elif [[ "$physical_store_count" == "1" &&
          "$physical_store" =~ ^disk[0-9]+s[0-9]+$ ]]; then
    device_name="$(ioreg_media_name_for_bsd_id "$physical_store" || true)"
    if [[ -z "$device_name" || -z "$volume_size" || -z "$volume_bus" ]]; then
      physical_plist="$(run_with_timeout 8 "$DISKUTIL_BIN" info -plist "$physical_store" 2>/dev/null || true)"
      parent_whole="$(plist_data_value "$physical_plist" ParentWholeDisk || true)"
      physical_name_hint="$(first_nonempty_display_value \
        "$(plist_data_value "$physical_plist" DeviceVendor || true)" \
        "$(plist_data_value "$physical_plist" DeviceModel || true)" \
        "$(plist_data_value "$physical_plist" IORegistryEntryName || true)" \
        "$(plist_data_value "$physical_plist" MediaName || true)" || true)"
      physical_size="$(first_valid_size_value \
        "$(plist_data_value "$physical_plist" TotalSize || true)" || true)"
      physical_bus="$(display_metadata_value "$(plist_data_value "$physical_plist" BusProtocol || true)")"
      if [[ "$parent_whole" =~ ^disk[0-9]+$ ]] &&
         [[ ( -z "$device_name" && -z "$physical_name_hint" ) ||
            ( -z "$physical_size" && -z "$volume_size" ) ||
            ( -z "$physical_bus" && -z "$volume_bus" ) ]]; then
        whole_plist="$(run_with_timeout 4 "$DISKUTIL_BIN" info -plist "$parent_whole" 2>/dev/null || true)"
      fi
    fi
  fi

  if [[ -z "$device_name" ]]; then
    vendor="$(first_nonempty_display_value \
      "$(plist_data_value "$whole_plist" DeviceVendor || true)" \
      "$(plist_data_value "$physical_plist" DeviceVendor || true)" || true)"
    model="$(first_nonempty_display_value \
      "$(plist_data_value "$whole_plist" DeviceModel || true)" \
      "$(plist_data_value "$physical_plist" DeviceModel || true)" || true)"
    if [[ -n "$vendor" && -n "$model" ]]; then
      vendor_lower="$(lowercase "$vendor")"
      model_lower="$(lowercase "$model")"
      if [[ "$model_lower" == "$vendor_lower"* ]]; then
        device_name="$model"
      else
        device_name="$vendor $model"
      fi
    elif [[ -n "$model" ]]; then
      device_name="$model"
    elif [[ -n "$vendor" ]]; then
      device_name="$vendor"
    fi
  fi

  if [[ -z "$device_name" ]]; then
    entry_name="$(first_nonempty_display_value \
      "$(plist_data_value "$physical_plist" IORegistryEntryName || true)" \
      "$(plist_data_value "$whole_plist" IORegistryEntryName || true)" || true)"
    entry_name="${entry_name% Media}"
    device_name="$entry_name"
  fi
  if [[ -z "$device_name" ]]; then
    for media_name in \
      "$(plist_data_value "$whole_plist" MediaName || true)" \
      "$(plist_data_value "$physical_plist" MediaName || true)"; do
      media_name="$(display_metadata_value "$media_name")"
      case "$(lowercase "$media_name")" in
        ""|media|external|external_usb|"external usb"|"storage device") ;;
        *) device_name="$media_name"; break ;;
      esac
    done
  fi
  device_name="$(display_metadata_value "$device_name")"
  if [[ -z "$device_name" || "$device_name" == "$volume_name" ]]; then
    device_name="$(t external_disk)"
  fi

  size="$(first_valid_size_value \
    "$(plist_data_value "$whole_plist" TotalSize || true)" \
    "$physical_size" \
    "$volume_size" || true)"
  bus="$(first_nonempty_display_value \
    "$(plist_data_value "$whole_plist" BusProtocol || true)" \
    "$physical_bus" \
    "$volume_bus" || true)"
  capacity="$(decimal_capacity_label "$size")"

  disk_detail="$(t disk_label): $device_name"
  if [[ -n "$capacity" ]]; then
    disk_detail+=" · $capacity"
  fi
  if [[ -n "$bus" ]]; then
    disk_detail+=" · $bus"
  fi
  printf '%s\n%s: %s' "$disk_detail" "$(t volume_label)" "$volume_name"
}

find_setup_candidate() {
  local selected_mount=""
  local selected_container=""
  local selected_name=""
  local mount plist fs external container name system_image writable_media mount_point
  local mount_real reported_mount_real

  for mount in "$VOLUMES_ROOT"/*; do
    [[ -d "$mount" ]] || continue
    [[ "$mount" != "$VOLUME" ]] || continue

    plist="$(mktemp "${TMPDIR:-/tmp}/gdrive-volume-info.XXXXXX")" || continue
    if ! run_with_timeout 6 "$DISKUTIL_BIN" info -plist "$mount" >"$plist"; then
      cleanup_temp_file "$plist" >/dev/null
      continue
    fi

    fs="$(plist_value "$plist" FilesystemType)"
    external="$(plist_value "$plist" RemovableMediaOrExternalDevice)"
    container="$(plist_value "$plist" APFSContainerReference)"
    name="$(plist_value "$plist" VolumeName)"
    system_image="$(plist_value "$plist" SystemImage)"
    writable_media="$(plist_value "$plist" WritableMedia)"
    mount_point="$(plist_value "$plist" MountPoint)"
    cleanup_temp_file "$plist" >/dev/null

    [[ "$fs" == "apfs" ]] || continue
    [[ "$external" == "true" ]] || continue
    [[ -n "$container" ]] || continue
    [[ "$system_image" == "false" ]] || continue
    [[ "$writable_media" == "true" ]] || continue
    mount_real="$(canonical_existing_directory "$mount")" || continue
    reported_mount_real="$(canonical_existing_directory "$mount_point")" || continue
    [[ "$mount_real" == "$reported_mount_real" ]] || continue

    # Several mounted volumes may represent one container; only a second
    # distinct container makes automatic setup ambiguous.
    if [[ -z "$selected_container" ]]; then
      selected_mount="$mount"
      selected_container="$container"
      selected_name="${name:-$(basename "$mount")}"
    elif [[ "$container" != "$selected_container" ]]; then
      return 2
    fi
  done

  [[ -n "$selected_mount" ]] || return 1
  printf '%s\t%s\t%s\n' "$selected_mount" "$selected_container" "$selected_name"
}

capture_setup_source_identity() {
  local source_mount="$1"
  local expected_container="$2"
  local plist_data filesystem mount_point container external writable_media system_image
  local source_real mount_real source_volume_uuid container_plist json_data identity_record
  local container_uuid physical_store_uuids physical_store_uuid
  local exact_count exact_uuids numeric_count exact_uuid
  local -a setup_physical_store_uuids=()
  local -a setup_exact_uuids=()

  SETUP_SOURCE_VOLUME_UUID=""
  SETUP_SOURCE_CONTAINER_UUID=""
  SETUP_SOURCE_PHYSICAL_STORE_UUIDS=""
  SETUP_TARGET_EXACT_COUNT=0
  SETUP_TARGET_EXACT_UUIDS=""
  SETUP_TARGET_NUMERIC_COUNT=0

  if ! plist_data="$(run_with_timeout 8 "$DISKUTIL_BIN" info -plist "$source_mount" 2>/dev/null)"; then
    return 1
  fi
  filesystem="$(plist_data_value "$plist_data" FilesystemType || true)"
  mount_point="$(plist_data_value "$plist_data" MountPoint || true)"
  container="$(plist_data_value "$plist_data" APFSContainerReference || true)"
  external="$(plist_data_value "$plist_data" RemovableMediaOrExternalDevice || true)"
  writable_media="$(plist_data_value "$plist_data" WritableMedia || true)"
  system_image="$(plist_data_value "$plist_data" SystemImage || true)"
  source_volume_uuid="$(plist_data_value "$plist_data" VolumeUUID || true)"
  if [[ "$filesystem" != "apfs" || "$container" != "$expected_container" ||
        "$external" != "true" || "$writable_media" != "true" ||
        "$system_image" != "false" || -z "$mount_point" ||
        ! "$source_volume_uuid" =~ ^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$ ]]; then
    return 1
  fi
  source_real="$(canonical_existing_directory "$source_mount")" || return 1
  mount_real="$(canonical_existing_directory "$mount_point")" || return 1
  [[ "$source_real" == "$mount_real" ]] || return 1

  # diskN and APFS container references are session-local handles. Bind the
  # setup decision to UUIDs from every layer so a newly attached disk cannot
  # inherit a stale handle while the confirmation or password dialog is open.
  if ! container_plist="$(run_with_timeout 8 "$DISKUTIL_BIN" apfs list -plist "$expected_container" 2>/dev/null)" ||
     ! json_data="$(printf '%s' "$container_plist" |
       /usr/bin/plutil -convert json -o - - 2>/dev/null)" ||
     ! identity_record="$(printf '%s' "$json_data" |
       jq -er --arg container "$expected_container" \
         --arg source_uuid "$(normalized_apfs_uuid "$source_volume_uuid")" \
         --arg name "$BACKUP_VOLUME_NAME" '
          [.Containers[]? | select(.ContainerReference == $container)] as $containers |
          if ($containers | length) != 1 then
            error("requested APFS container is not unique")
          else
            $containers[0] as $container_record |
            ($container_record.APFSContainerUUID // "") as $container_uuid |
            ($container_record.PhysicalStores // []) as $stores |
            ([ $container_record.Volumes[]? |
               select((.Name | type) == "string") |
               select(.Name == $name) ]) as $exact_records |
            ([ $container_record.Volumes[]? |
               select((.Name | type) == "string") |
               .Name as $volume_name |
               select(($volume_name | startswith($name + " ")) and
                      (($volume_name | ltrimstr($name + " ")) |
                       test("^[0-9]+$"))) ]) as $numeric_records |
            if (($container_uuid | type) != "string") or
               (($container_uuid | length) == 0) or
               (($stores | type) != "array") or
               (($stores | length) == 0) or
               (any($stores[]; ((.DiskUUID // "") | type) != "string" or
                              ((.DiskUUID // "") | length) == 0)) or
               (($stores | map(.DiskUUID | ascii_upcase) | unique | length) !=
                ($stores | length)) or
               (any($exact_records[]; ((.APFSVolumeUUID // "") | type) != "string" or
                                      ((.APFSVolumeUUID // "") | length) == 0)) or
               ([ $container_record.Volumes[]? |
                  select(((.APFSVolumeUUID // "") | type) == "string") |
                  select((.APFSVolumeUUID | ascii_upcase) == $source_uuid) ] |
                length) != 1 then
              error("APFS source identity is incomplete or ambiguous")
            else
              [($container_uuid | ascii_upcase),
               ($stores | map(.DiskUUID | ascii_upcase) | sort | join(",")),
               ($exact_records | length | tostring),
               (if ($exact_records | length) == 0 then "-"
                else ($exact_records |
                      map(.APFSVolumeUUID | ascii_upcase) | sort | join(",")) end),
               ($numeric_records | length | tostring)] |
              @tsv
            end
          end' 2>/dev/null)"; then
    return 1
  fi
  IFS=$'\t' read -r container_uuid physical_store_uuids exact_count exact_uuids numeric_count <<<"$identity_record"
  if [[ ! "$container_uuid" =~ ^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$ ||
        -z "$physical_store_uuids" || ! "$exact_count" =~ ^[0-9]+$ ||
        ! "$numeric_count" =~ ^[0-9]+$ ]]; then
    return 1
  fi
  IFS=',' read -ra setup_physical_store_uuids <<<"$physical_store_uuids"
  for physical_store_uuid in "${setup_physical_store_uuids[@]}"; do
    if [[ ! "$physical_store_uuid" =~ ^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$ ]]; then
      return 1
    fi
  done
  if [[ "$exact_uuids" == "-" ]]; then
    exact_uuids=""
  else
    IFS=',' read -ra setup_exact_uuids <<<"$exact_uuids"
    for exact_uuid in "${setup_exact_uuids[@]}"; do
      if [[ ! "$exact_uuid" =~ ^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$ ]]; then
        return 1
      fi
    done
  fi

  SETUP_SOURCE_VOLUME_UUID="$(normalized_apfs_uuid "$source_volume_uuid")"
  SETUP_SOURCE_CONTAINER_UUID="$(normalized_apfs_uuid "$container_uuid")"
  SETUP_SOURCE_PHYSICAL_STORE_UUIDS="$(normalized_apfs_uuid "$physical_store_uuids")"
  SETUP_TARGET_EXACT_COUNT="$exact_count"
  SETUP_TARGET_EXACT_UUIDS="$(normalized_apfs_uuid "$exact_uuids")"
  SETUP_TARGET_NUMERIC_COUNT="$numeric_count"
  return 0
}

capture_named_apfs_volume_uuids() {
  local container="$1"
  local output_file="$2"
  local plist_data json_data record_kind uuid invalid_uuid=0 numeric_family=0
  local unsorted_file

  unsorted_file="$(mktemp "${TMPDIR:-/tmp}/gdrive-apfs-uuids.XXXXXX")" ||
    return 1
  : >"$unsorted_file"
  if ! plist_data="$(run_with_timeout 8 "$DISKUTIL_BIN" apfs list -plist "$container" 2>/dev/null)" ||
     ! json_data="$(printf '%s' "$plist_data" |
       /usr/bin/plutil -convert json -o - - 2>/dev/null)" ||
     ! printf '%s' "$json_data" |
       jq -r --arg container "$container" --arg name "$BACKUP_VOLUME_NAME" \
         '[.Containers[]? | select(.ContainerReference == $container)] as $containers |
          if ($containers | length) != 1 then
            error("requested APFS container is not unique")
          else
            $containers[0].Volumes[]? |
            select((.Name | type) == "string") |
            .Name as $volume_name |
            if $volume_name == $name then
              if (has("APFSVolumeUUID") and
                  ((.APFSVolumeUUID | type) == "string") and
                  ((.APFSVolumeUUID | length) > 0)) then
                "exact\t" + .APFSVolumeUUID
              else
                error("exact-name APFS volume has no valid UUID field")
              end
            elif (($volume_name | startswith($name + " ")) and
                  (($volume_name | ltrimstr($name + " ")) |
                    test("^[0-9]+$"))) then
              "numeric-family\t"
            else
              empty
            end
          end' >"$unsorted_file"; then
    cleanup_temp_file "$unsorted_file"
    return 1
  fi

  : >"$output_file"
  while IFS=$'\t' read -r record_kind uuid; do
    case "$record_kind" in
      exact)
        if [[ ! "$uuid" =~ ^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$ ]]; then
          invalid_uuid=1
          continue
        fi
        normalized_apfs_uuid "$uuid" >>"$output_file"
        printf '\n' >>"$output_file"
        ;;
      numeric-family)
        numeric_family=1
        ;;
      "") ;;
      *) invalid_uuid=1 ;;
    esac
  done <"$unsorted_file"
  cleanup_temp_file "$unsorted_file"
  [[ "$invalid_uuid" == "0" ]] || return 1
  if [[ "$numeric_family" == "1" ]]; then
    log "FEHLER: Numerisch umbenannte APFS-Volumes aus derselben Namensfamilie wurden gefunden. Waehle das gewuenschte Volume explizit aus; es wurde nichts automatisch gebunden oder angelegt."
    return 2
  fi
  # Keep duplicate records visible: even a repeated UUID under the exact name
  # is ambiguous inventory and must be rejected by the caller's record count.
  /usr/bin/sort -o "$output_file" "$output_file"
}

recover_existing_named_apfs_volume() {
  local container="$1"
  local candidate_uuid="$2"
  local approved_source_mount="${3:-}"
  local expected_source_volume_uuid="${4:-}"
  local expected_source_container_uuid="${5:-}"
  local expected_source_physical_store_uuids="${6:-}"
  local inventory_file inventory_count inventory_uuid
  local plist_data filesystem mount_point volume_uuid volume_name encrypted locked
  local candidate_container external writable_media system_image volume_identifier
  local resolved_mount resolve_status

  inventory_file="$(mktemp "${TMPDIR:-/tmp}/gdrive-apfs-recover.XXXXXX")" ||
    return 1
  if ! capture_named_apfs_volume_uuids "$container" "$inventory_file"; then
    cleanup_temp_file "$inventory_file"
    log "FEHLER: Gleichnamige APFS-Volumes konnten vor der Bindung nicht sicher erfasst werden."
    return 1
  fi
  inventory_count="$(/usr/bin/wc -l <"$inventory_file" | /usr/bin/tr -d '[:space:]')"
  inventory_uuid="$(cat "$inventory_file")"
  cleanup_temp_file "$inventory_file"
  if [[ "$inventory_count" != "1" ||
        "$(normalized_apfs_uuid "$inventory_uuid")" != "$(normalized_apfs_uuid "$candidate_uuid")" ]]; then
    log "FEHLER: Das gleichnamige APFS-Volume ist vor der Bindung nicht mehr eindeutig."
    return 1
  fi

  if ! plist_data="$(run_with_timeout 8 "$DISKUTIL_BIN" info -plist "$candidate_uuid" 2>/dev/null)"; then
    log "FEHLER: Das vorhandene gleichnamige APFS-Volume konnte nicht per UUID geprueft werden."
    return 1
  fi

  filesystem="$(plist_data_value "$plist_data" FilesystemType || true)"
  mount_point="$(plist_data_value "$plist_data" MountPoint || true)"
  volume_uuid="$(plist_data_value "$plist_data" VolumeUUID || true)"
  volume_name="$(plist_data_value "$plist_data" VolumeName || true)"
  candidate_container="$(plist_data_value "$plist_data" APFSContainerReference || true)"
  external="$(plist_data_value "$plist_data" RemovableMediaOrExternalDevice || true)"
  writable_media="$(plist_data_value "$plist_data" WritableMedia || true)"
  system_image="$(plist_data_value "$plist_data" SystemImage || true)"
  volume_identifier="$(plist_data_value "$plist_data" DeviceIdentifier || true)"
  encrypted="$(plist_data_value "$plist_data" Encryption || true)"
  locked="$(plist_data_value "$plist_data" Locked || true)"
  if [[ "$filesystem" != "apfs" ||
        "$(normalized_apfs_uuid "$volume_uuid")" != "$(normalized_apfs_uuid "$candidate_uuid")" ||
        "$volume_name" != "$BACKUP_VOLUME_NAME" ||
        "$candidate_container" != "$container" ||
        "$external" != "true" || "$writable_media" != "true" ||
        "$system_image" != "false" || -z "$mount_point" ||
        -z "$volume_identifier" ]]; then
    log "FEHLER: diskutil bestaetigt das vorhandene gleichnamige APFS-Volume nicht eindeutig."
    return 1
  fi
  if [[ "$ENCRYPTION" == "apfs" &&
        ( "$encrypted" != "true" || "$locked" != "false" ) ]]; then
    log "FEHLER: Das zu bindende APFS-Volume ist nicht verschluesselt und entsperrt."
    return 1
  fi
  if ! resolved_mount="$(canonical_existing_directory "$mount_point")"; then
    log "FEHLER: Das vorhandene gleichnamige APFS-Volume ist nicht eingehängt."
    return 1
  fi

  BACKUP_VOLUME_UUID="$(normalized_apfs_uuid "$candidate_uuid")"
  resolve_status=0
  resolve_configured_apfs_volume || resolve_status=$?
  if [[ "$resolve_status" != "0" || "$VOLUME" != "$resolved_mount" ]] ||
     ! validate_configured_apfs_volume_identity; then
    log "FEHLER: Das vorhandene gleichnamige APFS-Volume konnte nicht sicher gebunden werden."
    return 1
  fi
  if [[ -n "$approved_source_mount" ]]; then
    local identity_status=0
    setup_source_identity_matches \
      "$approved_source_mount" "$container" \
      "$expected_source_volume_uuid" "$expected_source_container_uuid" \
      "$expected_source_physical_store_uuids" unique "$candidate_uuid" ||
      identity_status=$?
    case "$identity_status" in
      0) ;;
      1)
        log "FEHLER: Die stabile Identitaet des freigegebenen APFS-Ausgangscontainers hat sich vor der Bindung geaendert."
        return 1
        ;;
      *)
        log "FEHLER: Das vorhandene gleichnamige APFS-Volume ist vor dem Speichern nicht mehr eindeutig."
        return 1
        ;;
    esac
  else
    inventory_file="$(mktemp "${TMPDIR:-/tmp}/gdrive-apfs-final-recover.XXXXXX")" ||
      return 1
    if ! capture_named_apfs_volume_uuids "$container" "$inventory_file"; then
      cleanup_temp_file "$inventory_file"
      log "FEHLER: Das APFS-Volume-Inventar konnte vor dem Speichern nicht erneut geprueft werden."
      return 1
    fi
    inventory_count="$(/usr/bin/wc -l <"$inventory_file" | /usr/bin/tr -d '[:space:]')"
    inventory_uuid="$(cat "$inventory_file")"
    cleanup_temp_file "$inventory_file"
    if [[ "$inventory_count" != "1" ||
          "$(normalized_apfs_uuid "$inventory_uuid")" != "$(normalized_apfs_uuid "$candidate_uuid")" ]]; then
      log "FEHLER: Das vorhandene gleichnamige APFS-Volume ist vor dem Speichern nicht mehr eindeutig."
      return 1
    fi
  fi
  if ! persist_volume_config "$BACKUP_VOLUME_UUID"; then
    log "FEHLER: Identitaet des vorhandenen APFS-Volumes konnte nicht gespeichert werden."
    return 1
  fi
  log "Vorhandenes Backup-Volume per UUID gebunden: $VOLUME"
  return 0
}

inspect_path_only_apfs_binding() {
  local path="$1"
  local plist_data filesystem mount_point volume_uuid volume_name container
  local external writable_media system_image volume_identifier encrypted locked
  local path_real mount_real path_device mount_device inventory_file inventory_count inventory_uuid

  if [[ -L "$path" ]]; then
    log "FEHLER: Ein APFS-Volume kann nicht ueber einen symbolischen Link gebunden werden."
    return 1
  fi
  if ! plist_data="$(run_with_timeout 8 "$DISKUTIL_BIN" info -plist "$path" 2>/dev/null)"; then
    log "FEHLER: Das ausgewaehlte APFS-Volume konnte nicht geprueft werden."
    return 1
  fi
  filesystem="$(plist_data_value "$plist_data" FilesystemType || true)"
  mount_point="$(plist_data_value "$plist_data" MountPoint || true)"
  volume_uuid="$(plist_data_value "$plist_data" VolumeUUID || true)"
  volume_name="$(plist_data_value "$plist_data" VolumeName || true)"
  container="$(plist_data_value "$plist_data" APFSContainerReference || true)"
  external="$(plist_data_value "$plist_data" RemovableMediaOrExternalDevice || true)"
  writable_media="$(plist_data_value "$plist_data" WritableMedia || true)"
  system_image="$(plist_data_value "$plist_data" SystemImage || true)"
  volume_identifier="$(plist_data_value "$plist_data" DeviceIdentifier || true)"
  encrypted="$(plist_data_value "$plist_data" Encryption || true)"
  locked="$(plist_data_value "$plist_data" Locked || true)"
  if [[ "$filesystem" != "apfs" ||
        ! "$volume_uuid" =~ ^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$ ||
        "$volume_name" != "$BACKUP_VOLUME_NAME" || -z "$container" ||
        "$external" != "true" || "$writable_media" != "true" ||
        "$system_image" != "false" || -z "$mount_point" ||
        -z "$volume_identifier" ]]; then
    log "FEHLER: Der ausgewaehlte Pfad ist kein eindeutig geeignetes externes APFS-Backup-Volume."
    return 1
  fi
  if [[ "$ENCRYPTION" == "apfs" &&
        ( "$encrypted" != "true" || "$locked" != "false" ) ]]; then
    log "FEHLER: Das ausgewaehlte APFS-Volume ist nicht verschluesselt und entsperrt."
    return 1
  fi
  if ! path_real="$(canonical_existing_directory "$path")" ||
     ! mount_real="$(canonical_existing_directory "$mount_point")" ||
     [[ "$path_real" != "$mount_real" ]] ||
     ! path_device="$(/usr/bin/stat -f '%d' "$path_real" 2>/dev/null)" ||
     ! mount_device="$(/usr/bin/stat -f '%d' "$mount_real" 2>/dev/null)" ||
     [[ -z "$path_device" || "$path_device" != "$mount_device" ]]; then
    log "FEHLER: diskutil bestaetigt den ausgewaehlten APFS-Mountpunkt nicht eindeutig."
    return 1
  fi

  inventory_file="$(mktemp "${TMPDIR:-/tmp}/gdrive-apfs-bind.XXXXXX")" ||
    return 1
  if ! capture_named_apfs_volume_uuids "$container" "$inventory_file"; then
    cleanup_temp_file "$inventory_file"
    log "FEHLER: APFS-Volume-Inventar konnte fuer die Bindung nicht gelesen werden."
    return 1
  fi
  inventory_count="$(/usr/bin/wc -l <"$inventory_file" | /usr/bin/tr -d '[:space:]')"
  inventory_uuid="$(cat "$inventory_file")"
  cleanup_temp_file "$inventory_file"
  if [[ "$inventory_count" != "1" ||
        "$(normalized_apfs_uuid "$inventory_uuid")" != "$(normalized_apfs_uuid "$volume_uuid")" ]]; then
    log "FEHLER: Das gleichnamige APFS-Volume ist nicht eindeutig; es wurde nichts gebunden."
    return 1
  fi

  INSPECTED_BINDING_UUID="$(normalized_apfs_uuid "$volume_uuid")"
  INSPECTED_BINDING_CONTAINER="$container"
  INSPECTED_BINDING_MOUNT="$path_real"
  INSPECTED_BINDING_IDENTIFIER="$volume_identifier"
  INSPECTED_BINDING_DEVICE="$path_device"
  return 0
}

create_apfs_backup_volume() {
  local container="$1"
  local before_file="$2"
  local source_mount="$3"
  local expected_source_volume_uuid="$4"
  local expected_source_container_uuid="$5"
  local expected_source_physical_store_uuids="$6"
  local after_file candidate_uuid detect_status admin_status=0
  local admin_guard

  CREATED_APFS_VOLUME_UUID=""
  # The caller's baseline was captured after confirmation. Close the remaining
  # scheduling gap with an in-function snapshot immediately before addVolume.
  after_file="$(mktemp "${TMPDIR:-/tmp}/gdrive-apfs-before-add.XXXXXX")" ||
    return 1
  if ! capture_named_apfs_volume_uuids "$container" "$after_file"; then
    cleanup_temp_file "$after_file"
    log "FEHLER: APFS-Volumes konnten vor dem Anlegen nicht sicher verglichen werden."
    return 1
  fi
  detect_status=0
  candidate_uuid="$(new_apfs_volume_uuid_since "$before_file" "$after_file")" ||
    detect_status=$?
  cleanup_temp_file "$after_file"
  case "$detect_status" in
    0)
      admit_appeared_apfs_candidate \
        "$candidate_uuid" "$source_mount" "$container" \
        "$expected_source_volume_uuid" "$expected_source_container_uuid" \
        "$expected_source_physical_store_uuids"
      return $?
      ;;
    1) ;;
    *)
      log "FEHLER: Das APFS-Volume ist unmittelbar vor dem Anlegen nicht eindeutig."
      return 1
      ;;
  esac
  local final_identity_status=0
  setup_source_identity_matches \
    "$source_mount" "$container" \
    "$expected_source_volume_uuid" "$expected_source_container_uuid" \
    "$expected_source_physical_store_uuids" absent || final_identity_status=$?
  case "$final_identity_status" in
    0) ;;
    1)
      log "FEHLER: Die stabile Identitaet des APFS-Ausgangscontainers hat sich unmittelbar vor dem Anlegen geaendert. Es wurde kein Volume angelegt."
      return 1
      ;;
    *)
      log "FEHLER: Ein gleichnamiges oder numerisch umbenanntes APFS-Ziel erschien unmittelbar vor dem Anlegen; es wurde nichts angelegt."
      return 1
      ;;
  esac
  if "$DISKUTIL_BIN" apfs addVolume "$container" APFS "$BACKUP_VOLUME_NAME"; then
    return 0
  fi

  # diskutil can create a volume successfully and still report a later mount
  # failure. Confirm the set difference before ever attempting a second add.
  for _ in 1 2 3; do
    after_file="$(mktemp "${TMPDIR:-/tmp}/gdrive-apfs-after.XXXXXX")" ||
      return 1
    if ! capture_named_apfs_volume_uuids "$container" "$after_file"; then
      cleanup_temp_file "$after_file"
      log "FEHLER: APFS-Volumes konnten nach dem fehlgeschlagenen Anlegen nicht sicher verglichen werden."
      return 1
    fi
    detect_status=0
    candidate_uuid="$(new_apfs_volume_uuid_since "$before_file" "$after_file")" ||
      detect_status=$?
    cleanup_temp_file "$after_file"
    case "$detect_status" in
      0)
        admit_appeared_apfs_candidate \
          "$candidate_uuid" "$source_mount" "$container" \
          "$expected_source_volume_uuid" "$expected_source_container_uuid" \
          "$expected_source_physical_store_uuids"
        return $?
        ;;
      1) sleep 1 ;;
      *)
        log "FEHLER: Das neu angelegte APFS-Volume ist nicht eindeutig."
        return 1
        ;;
    esac
  done

  # A sibling process can create the requested name while this process waits
  # between the unprivileged failure and the administrator authorization UI.
  # Take one last UUID snapshot immediately before any privileged mutation.
  log "APFS-Volume konnte ohne Adminrechte nicht angelegt werden; pruefe erneut vor der Administratorfreigabe."
  after_file="$(mktemp "${TMPDIR:-/tmp}/gdrive-apfs-before-admin.XXXXXX")" ||
    return 1
  if ! capture_named_apfs_volume_uuids "$container" "$after_file"; then
    cleanup_temp_file "$after_file"
    log "FEHLER: APFS-Volumes konnten vor dem privilegierten Anlegen nicht sicher verglichen werden."
    return 1
  fi
  detect_status=0
  candidate_uuid="$(new_apfs_volume_uuid_since "$before_file" "$after_file")" ||
    detect_status=$?
  cleanup_temp_file "$after_file"
  case "$detect_status" in
    0)
      admit_appeared_apfs_candidate \
        "$candidate_uuid" "$source_mount" "$container" \
        "$expected_source_volume_uuid" "$expected_source_container_uuid" \
        "$expected_source_physical_store_uuids"
      return $?
      ;;
    1) ;;
    *)
      log "FEHLER: Das APFS-Volume ist vor der Administratorfreigabe nicht eindeutig."
      return 1
      ;;
  esac

  # Authorization can remain open indefinitely. Run the final inventory guard
  # only after macOS grants it, in the same privileged shell that performs the
  # add, so a volume appearing in the authorization window blocks mutation.
  # Expansion is intentionally deferred to that root shell.
  # shellcheck disable=SC2016
  admin_guard='
[ "$#" -eq 6 ] || exit 70
diskutil_bin=$1
container_ref=$2
volume_name=$3
expected_source_volume_uuid=$4
expected_container_uuid=$5
expected_physical_store_uuids=$6
is_uuid() {
  printf "%s\n" "$1" | /usr/bin/grep -Eq "^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$"
}
case "$container_ref" in
  disk*) container_digits=${container_ref#disk} ;;
  *) exit 70 ;;
esac
case "$container_digits" in
  ""|*[!0-9]*) exit 70 ;;
esac
[ -n "$volume_name" ] || exit 70
is_uuid "$expected_source_volume_uuid" || exit 70
is_uuid "$expected_container_uuid" || exit 70
case "$expected_physical_store_uuids" in
  ""|*[!0-9A-Fa-f,-]*) exit 70 ;;
esac
old_ifs=$IFS
IFS=,
for expected_store_uuid in $expected_physical_store_uuids; do
  is_uuid "$expected_store_uuid" || exit 70
done
IFS=$old_ifs
inventory=$("$diskutil_bin" apfs list -plist "$container_ref" 2>/dev/null) || exit 70
container_count=$(printf "%s" "$inventory" | /usr/bin/plutil -extract Containers raw -o - - 2>/dev/null) || exit 70
case "$container_count" in
  ""|*[!0-9]*) exit 70 ;;
esac
container_index=0
requested_container_count=0
requested_container_index=
while [ "$container_index" -lt "$container_count" ]; do
  candidate_container=$(printf "%s" "$inventory" | /usr/bin/plutil -extract "Containers.${container_index}.ContainerReference" raw -o - - 2>/dev/null) || exit 70
  if [ "$candidate_container" = "$container_ref" ]; then
    requested_container_count=$((requested_container_count + 1))
    requested_container_index=$container_index
  fi
  container_index=$((container_index + 1))
done
[ "$requested_container_count" -eq 1 ] || exit 71
current_container_uuid=$(printf "%s" "$inventory" | /usr/bin/plutil -extract "Containers.${requested_container_index}.APFSContainerUUID" raw -o - - 2>/dev/null) || exit 70
is_uuid "$current_container_uuid" || exit 70
current_container_uuid=$(printf "%s" "$current_container_uuid" | /usr/bin/tr "[:lower:]" "[:upper:]")
expected_container_uuid=$(printf "%s" "$expected_container_uuid" | /usr/bin/tr "[:lower:]" "[:upper:]")
[ "$current_container_uuid" = "$expected_container_uuid" ] || exit 74
physical_store_count=$(printf "%s" "$inventory" | /usr/bin/plutil -extract "Containers.${requested_container_index}.PhysicalStores" raw -o - - 2>/dev/null) || exit 70
case "$physical_store_count" in
  ""|*[!0-9]*) exit 70 ;;
esac
[ "$physical_store_count" -gt 0 ] || exit 70
physical_store_index=0
current_physical_store_lines=
while [ "$physical_store_index" -lt "$physical_store_count" ]; do
  current_store_uuid=$(printf "%s" "$inventory" | /usr/bin/plutil -extract "Containers.${requested_container_index}.PhysicalStores.${physical_store_index}.DiskUUID" raw -o - - 2>/dev/null) || exit 70
  is_uuid "$current_store_uuid" || exit 70
  current_store_uuid=$(printf "%s" "$current_store_uuid" | /usr/bin/tr "[:lower:]" "[:upper:]")
  current_physical_store_lines="${current_physical_store_lines}${current_store_uuid}
"
  physical_store_index=$((physical_store_index + 1))
done
current_physical_store_uuids=$(printf "%s" "$current_physical_store_lines" | /usr/bin/sort | /usr/bin/awk "NF { if (seen[\$0]++) exit 2; values = values separator \$0; separator = \",\" } END { print values }") || exit 70
expected_physical_store_uuids=$(printf "%s" "$expected_physical_store_uuids" | /usr/bin/tr "[:lower:]" "[:upper:]")
[ "$current_physical_store_uuids" = "$expected_physical_store_uuids" ] || exit 74
volume_count=$(printf "%s" "$inventory" | /usr/bin/plutil -extract "Containers.${requested_container_index}.Volumes" raw -o - - 2>/dev/null) || exit 70
case "$volume_count" in
  ""|*[!0-9]*) exit 70 ;;
esac
volume_index=0
family_prefix="${volume_name} "
source_volume_match_count=0
while [ "$volume_index" -lt "$volume_count" ]; do
  candidate_name=$(printf "%s" "$inventory" | /usr/bin/plutil -extract "Containers.${requested_container_index}.Volumes.${volume_index}.Name" raw -o - - 2>/dev/null) || exit 70
  candidate_uuid=$(printf "%s" "$inventory" | /usr/bin/plutil -extract "Containers.${requested_container_index}.Volumes.${volume_index}.APFSVolumeUUID" raw -o - - 2>/dev/null) || exit 70
  is_uuid "$candidate_uuid" || exit 70
  candidate_uuid=$(printf "%s" "$candidate_uuid" | /usr/bin/tr "[:lower:]" "[:upper:]")
  expected_source_volume_uuid=$(printf "%s" "$expected_source_volume_uuid" | /usr/bin/tr "[:lower:]" "[:upper:]")
  if [ "$candidate_uuid" = "$expected_source_volume_uuid" ]; then
    source_volume_match_count=$((source_volume_match_count + 1))
  fi
  case "$candidate_name" in
    "$volume_name") exit 72 ;;
    "$family_prefix"*)
      numeric_suffix=${candidate_name#"$family_prefix"}
      case "$numeric_suffix" in
        ""|*[!0-9]*) ;;
        *) exit 73 ;;
      esac
      ;;
  esac
  volume_index=$((volume_index + 1))
done
[ "$source_volume_match_count" -eq 1 ] || exit 74
exec "$diskutil_bin" apfs addVolume "$container_ref" APFS "$volume_name" >/dev/null 2>&1
'
  "$OSASCRIPT_BIN" - "$admin_guard" "$container" "$BACKUP_VOLUME_NAME" \
    "$expected_source_volume_uuid" "$expected_source_container_uuid" \
    "$expected_source_physical_store_uuids" \
    >/dev/null 2>&1 <<'OSA' || admin_status=$?
on run argv
  set guardScript to item 1 of argv
  set containerRef to item 2 of argv
  set volumeName to item 3 of argv
  set sourceVolumeUUID to item 4 of argv
  set containerUUID to item 5 of argv
  set physicalStoreUUIDs to item 6 of argv
  set diskutilPath to "/usr/sbin/diskutil"
  set cmd to "/bin/sh -c " & quoted form of guardScript & " gdrive-apfs-admin " & quoted form of diskutilPath & " " & quoted form of containerRef & " " & quoted form of volumeName & " " & quoted form of sourceVolumeUUID & " " & quoted form of containerUUID & " " & quoted form of physicalStoreUUIDs
  do shell script cmd with administrator privileges
end run
OSA
  if [[ "$admin_status" != "0" ]]; then
    if [[ "$admin_status" == "74" ]] ||
       ! setup_source_identity_matches \
         "$source_mount" "$container" \
         "$expected_source_volume_uuid" "$expected_source_container_uuid" \
         "$expected_source_physical_store_uuids"; then
      log "FEHLER: Die stabile Identitaet des APFS-Ausgangscontainers hat sich waehrend der Administratorfreigabe geaendert. Es wurde kein Volume angelegt."
      return 1
    fi
    # diskutil can create the APFS volume and still report a later mount error.
    # Let the caller compare UUID sets before deciding whether creation failed.
    log "WARNUNG: Der privilegierte APFS-Aufruf meldete Status $admin_status; pruefe die Volume-UUIDs vor einem Abbruch."
  fi
  return 0
}

nas_mount_is_verified() {
  local line mount_path filesystem

  [[ -d "$NAS_MOUNT" && ! -L "$NAS_MOUNT" && -x "$MOUNT_BIN" ]] || return 1
  while IFS= read -r line; do
    [[ "$line" == *" on "* && "$line" == *" ("* ]] || continue
    mount_path="${line#* on }"
    mount_path="${mount_path% (*}"
    [[ "$mount_path" == "$NAS_MOUNT" ]] || continue
    filesystem="${line##* (}"
    filesystem="${filesystem%%,*}"
    case "$filesystem" in
      smbfs|afpfs|nfs) return 0 ;;
    esac
  done < <("$MOUNT_BIN" 2>/dev/null)
  return 1
}

validate_configured_apfs_tree() {
  local root="$1"

  [[ "$BACKUP_TARGET" == "apfs" && -n "$BACKUP_VOLUME_UUID" ]] || return 0
  [[ -e "$root" || -L "$root" ]] || return 0
  if ! validate_configured_apfs_paths "$root"; then
    return 1
  fi
  if [[ -L "$root" ]]; then
    log "FEHLER: Symbolischer Link im UUID-gebundenen APFS-Ziel ist nicht zulaessig: $(safe_name "$root")"
    return 1
  fi
  # One streamed walk catches both link redirections and nested mount points.
  # Device IDs stay bounded by find's argv batches instead of being retained
  # as one shell variable for a potentially very large backup history.
  if ! /usr/bin/find -x "$root" \
      \( -type l -print \) -o \
      \( -type d -exec /bin/bash -c '
        /usr/bin/stat -f "%d" "$@" 2>/dev/null ||
          printf "%s\n" "__GDRIVE_APFS_STAT_FAILED__"
      ' _ {} + \) 2>/dev/null |
      /usr/bin/awk -v expected_device="$APFS_VOLUME_DEVICE" '
        $0 != expected_device { unsafe = 1 }
        END { exit unsafe ? 1 : 0 }
      '; then
    log "FEHLER: APFS-Zielbaum enthaelt einen symbolischen Link, ein fremdes Dateisystem oder einen unlesbaren Pfad: $(safe_name "$root")"
    return 1
  fi
  return 0
}
