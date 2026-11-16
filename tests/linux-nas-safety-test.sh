#!/bin/bash
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/platform-linux.sh
source "$ROOT/lib/platform-linux.sh"
failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1"; failures=$((failures + 1)); }
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/gdrive-linux-nas.XXXXXX")"
cleanup() {
  if [[ -x /usr/bin/trash ]]; then
    /usr/bin/trash "$WORK_DIR"
  else
    printf 'Test fixtures retained: %s\n' "$WORK_DIR"
  fi
}
trap cleanup EXIT
NAS_MOUNT="$WORK_DIR/backup share"
mkdir "$NAS_MOUNT"
fixture=''
mount_exists=1
findmnt() {
  if [[ " $* " == *' --mountpoint '* ]]; then
    [[ "$mount_exists" == 1 ]] || return 1
  elif [[ " $* " == *' --target '* ]]; then
    # A containing filesystem still exists when the intended mount is gone.
    :
  fi
  printf '%s' "$fixture"
}
fixture="$(jq -nc --arg target "$NAS_MOUNT" '{filesystems:[
  {source:"//server/wrong",target:"/wrong",fstype:"cifs"},
  {source:"//server/backup",target:$target,fstype:"cifs"}]}')"
if [[ "$(find_nas_mount_for_url smb://server/backup)" == "$NAS_MOUNT" ]]; then pass 'discovery selects the requested share and preserves spaces'; else fail 'share discovery'; fi
if [[ -z "$(find_nas_mount_for_url smb://server/absent)" ]]; then pass 'discovery rejects a different share on the same host'; else fail 'missing share'; fi
fixture="$(printf '%s' "$fixture" | jq '.filesystems += [.filesystems[1]]')"
if [[ -z "$(find_nas_mount_for_url smb://server/backup)" ]]; then pass 'discovery rejects ambiguous mounts'; else fail 'ambiguous mount'; fi
fixture='{"filesystems":[{"source":"server:/exports/backup","target":"/nfs","fstype":"nfs4"}]}'
if [[ "$(find_nas_mount_for_url nfs://server/exports/backup)" == /nfs ]]; then pass 'NFS discovery matches the complete export'; else fail 'NFS export'; fi
fixture="$(jq -nc --arg target "$NAS_MOUNT" '{filesystems:[
  {id:42,source:"//server/backup",target:$target,fstype:"cifs"}]}')"
NAS_URL=smb://server/backup
LINUX_NAS_MOUNT_IDENTITY=''
if nas_mount_is_verified; then pass 'exact network mount accepted'; else fail 'valid mount'; fi
mount_exists=0
if nas_mount_is_verified; then fail 'lost mount accepted'; else pass 'lost mount rejected despite underlying filesystem'; fi
mount_exists=1
fixture="$(printf '%s' "$fixture" | jq '.filesystems[0].id=43')"
if (nas_mount_is_verified); then fail 'remount accepted by child'; else pass 'child inherits identity and rejects replacement mount'; fi
if nas_mount_is_verified; then fail 'remount accepted'; else pass 'replacement mount ID rejected'; fi
LINUX_NAS_MOUNT_IDENTITY=''
NAS_URL=smb://server/wrong
if nas_mount_is_verified; then fail 'wrong source accepted'; else pass 'configured URL mismatch rejected'; fi
NAS_URL=''
fixture="$(printf '%s' "$fixture" | jq '.filesystems[0].fstype="ext4"')"
if nas_mount_is_verified; then fail 'local disk accepted'; else pass 'local filesystem rejected'; fi
fixture='invalid json'
if nas_mount_is_verified; then fail 'malformed mount data accepted'; else pass 'malformed mount data rejected'; fi
(( failures == 0 ))
