#!/bin/bash
# "gdrive-tiger-backup connect" of the Linux edition: reads the user's own
# Google client file, connects a new remote, switches an existing remote only
# after a temporary remote has signed in, and never while a backup runs.
# rclone is replaced by a recording fake; nothing talks to Google.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMMAND="$ROOT/packaging/linux/gdrive-tiger-backup"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/gdrive-linux-connect.XXXXXX")"
failures=0
trap '"$ROOT/scripts/trash-path.sh" "$WORK" >/dev/null 2>&1 || true' EXIT

pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1"; failures=$((failures + 1)); }

if ! command -v flock >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  printf 'ok - flock or jq unavailable here # SKIP\n'
  exit 0
fi

ID="123456789012-abcdefghijklmnop.apps.googleusercontent.com"
SECRET="GOCSPX-testsecret_123"

mkdir -p "$WORK/share/bin" "$WORK/fakebin"
printf '#!/bin/bash\nexit 0\n' >"$WORK/share/bin/backup-google-drive.sh"
chmod +x "$WORK/share/bin/backup-google-drive.sh"

# Fake rclone: one file per remote under $FAKE_RCLONE_DIR holding its settings;
# every call is appended to calls.log. FAKE_RCLONE_FAIL_CREATE=1 makes sign-in fail.
cat >"$WORK/fakebin/rclone" <<'EOF'
#!/bin/bash
dir="$FAKE_RCLONE_DIR"
printf '%s\n' "$*" >>"$dir/calls.log"
case "$1 ${2:-}" in
  "listremotes "*) for f in "$dir"/remotes/*; do [[ -f "$f" ]] && printf '%s:\n' "${f##*/}"; done ;;
  "config show") [[ -f "$dir/remotes/$3" ]] && cat "$dir/remotes/$3" ;;
  "config create")
    [[ "${FAKE_RCLONE_FAIL_CREATE:-0}" == 1 ]] && exit 1
    name="$3"; shift 4
    { printf 'type = drive\n'; for kv in "$@"; do printf '%s = %s\n' "${kv%%=*}" "${kv#*=}"; done
      printf 'token = {"access_token":"new-%s"}\n' "$name"; } >"$dir/remotes/$name" ;;
  "config update")
    name="$3"; shift 3
    for kv in "$@"; do [[ "$kv" == --* ]] && continue; printf '%s = %s\n' "${kv%%=*}" "${kv#*=}"; done >"$dir/remotes/$name" ;;
  "config delete") rm -f "$dir/remotes/$3" ;;
  "about "*) [[ -f "$dir/remotes/${2%:}" ]] ;;
  *) exit 2 ;;
esac
EOF
chmod +x "$WORK/fakebin/rclone"

new_home() {
  HOME_DIR="$WORK/home-$1"
  RC="$WORK/rclone-$1"
  mkdir -p "$HOME_DIR/Downloads" "$RC/remotes"
  : >"$RC/calls.log"
}
run_connect() {
  printf '%s' "${1:-}" | env HOME="$HOME_DIR" PATH="$WORK/fakebin:$PATH" FAKE_RCLONE_DIR="$RC" \
    GDRIVE_TIGER_SHARE_DIR="$WORK/share" FAKE_RCLONE_FAIL_CREATE="${FAIL_CREATE:-0}" \
    /bin/bash "$COMMAND" connect 2>&1
}
desktop_json() { printf '{"installed":{"client_id":"%s","project_id":"p","client_secret":"%s"}}\n' "$ID" "$SECRET"; }

# 1. New remote, client file picked up from Downloads with the default answer.
new_home new
desktop_json >"$HOME_DIR/Downloads/client_secret_42.json"
output="$(run_connect $'\n')"
saved="$HOME_DIR/.config/gdrive-tiger-backup/google-oauth-client.json"
if grep -q "^client_id = $ID$" "$RC/remotes/gdrive" &&
   grep -q '^scope = drive.readonly$' "$RC/remotes/gdrive" &&
   [[ -f "$saved" && "$(stat -c '%a' "$saved" 2>/dev/null || stat -f '%Lp' "$saved")" == 600 ]] &&
   [[ "$output" != *"$SECRET"* ]]; then
  pass "a new remote is created with the own client from Downloads; a private copy is kept; the secret is not printed"
else
  fail "new remote: $output"
fi

# 2. Existing remote on rclone's shared client is switched through a temporary remote.
new_home switch
printf 'type = drive\nscope = drive.readonly\ntoken = {"access_token":"old"}\n' >"$RC/remotes/gdrive"
desktop_json >"$HOME_DIR/Downloads/client_secret_42.json"
output="$(run_connect $'\n')"
if grep -q "^client_id = $ID$" "$RC/remotes/gdrive" &&
   grep -q '^token = {"access_token":"new-gdrive-tiger-new"}$' "$RC/remotes/gdrive" &&
   grep -q 'config_refresh_token=false --non-interactive$' "$RC/calls.log" &&
   [[ ! -e "$RC/remotes/gdrive-tiger-new" ]]; then
  pass "an existing remote takes the token of the signed-in temporary remote, which is removed"
else
  fail "switch: $output"
fi

# 3. A running backup holds the lock: nothing is switched.
new_home busy
printf 'type = drive\ntoken = {"access_token":"old"}\n' >"$RC/remotes/gdrive"
desktop_json >"$HOME_DIR/Downloads/client_secret_42.json"
lock="$HOME_DIR/.local/state/gdrive-tiger-backup/backup.lock"
mkdir -p "${lock%/*}"
flock "$lock" sleep 30 &
holder=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do flock -n "$lock" true 2>/dev/null || break; sleep 0.2; done
output="$(run_connect $'\n')"
kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null
if [[ "$output" == *"a backup is running"* ]] &&
   grep -q '"old"' "$RC/remotes/gdrive" && ! grep -q client_id "$RC/remotes/gdrive" &&
   [[ ! -e "$RC/remotes/gdrive-tiger-new" ]]; then
  pass "while a backup holds the run lock the remote stays unchanged"
else
  fail "busy lock: $output"
fi

# 4. Sign-in fails: the existing remote stays as it was.
new_home failed
printf 'type = drive\ntoken = {"access_token":"old"}\n' >"$RC/remotes/gdrive"
desktop_json >"$HOME_DIR/Downloads/client_secret_42.json"
output="$(FAIL_CREATE=1 run_connect $'\n')"
if [[ "$output" == *"is unchanged"* ]] && grep -q '"old"' "$RC/remotes/gdrive" &&
   [[ ! -e "$RC/remotes/gdrive-tiger-new" ]]; then
  pass "a failed sign-in leaves the existing remote unchanged"
else
  fail "failed sign-in: $output"
fi

# 5. A web client and an unrelated file are refused before any sign-in.
new_home web
printf '{"web":{"client_id":"%s","client_secret":"%s"}}\n' "$ID" "$SECRET" >"$HOME_DIR/Downloads/client_secret_42.json"
output="$(run_connect $'\n')"
printf '{"hello":1}\n' >"$HOME_DIR/other.json"
output2="$(run_connect "$HOME_DIR/other.json"$'\n')"
if [[ "$output" == *'type \"Desktop app\"'* || "$output" == *'type "Desktop app"'* ]] &&
   [[ "$output2" == *"not a Google client file"* ]] &&
   ! grep -q '^config create' "$RC/calls.log"; then
  pass "a web client or an unrelated file is refused before sign-in"
else
  fail "refusal: $output / $output2"
fi

if (( failures > 0 )); then
  printf '%d Linux connect test(s) failed.\n' "$failures"
  exit 1
fi
printf 'All Linux connect tests passed.\n'
