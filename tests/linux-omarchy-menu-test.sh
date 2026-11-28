#!/bin/bash
# "gdrive-tiger-backup omarchy-menu" adds a Drive Backup submenu to the user's
# Omarchy menu extension file once, keeps the file valid for Omarchy's parser
# (whole-line comments dropped, trailing commas tolerated) and never runs twice.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMMAND="$ROOT/packaging/linux/gdrive-tiger-backup"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/gdrive-linux-menu.XXXXXX")"
failures=0
trap '"$ROOT/scripts/trash-path.sh" "$WORK" >/dev/null 2>&1 || true' EXIT

pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1"; failures=$((failures + 1)); }

if ! command -v jq >/dev/null 2>&1; then
  printf 'ok - jq unavailable here # SKIP\n'
  exit 0
fi

mkdir -p "$WORK/share/bin"
printf '#!/bin/bash\nexit 0\n' >"$WORK/share/bin/backup-google-drive.sh"
chmod +x "$WORK/share/bin/backup-google-drive.sh"

run_menu() {
  env HOME="$1" GDRIVE_TIGER_SHARE_DIR="$WORK/share" /bin/bash "$COMMAND" omarchy-menu 2>&1
}
menu_file() { printf '%s/.config/omarchy/extensions/omarchy-menu.jsonc' "$1"; }
# Omarchy's reading of the file: drop whole-line comments and trailing commas.
omarchy_parse() {
  grep -v '^[[:space:]]*//' "$1" | tr -d '\n' | sed -E 's/,[[:space:]]*([]}])/\1/g' | jq -e . 2>/dev/null
}
has_rows() { omarchy_parse "$1" | jq -e '."drive-backup" and ."drive-backup.run".action == "gdrive-tiger-backup run"' >/dev/null; }

# 1. No extension file yet: it is created with the submenu.
H="$WORK/home-new"; mkdir -p "$H/.config/omarchy"
output="$(run_menu "$H")"
if has_rows "$(menu_file "$H")" && [[ "$output" == *"Added the Drive Backup submenu"* ]]; then
  pass "a missing extension file is created with the submenu"
else
  fail "new file: $output"
fi

# 2. Omarchy's shipped template (only comments) and a user entry without a
#    trailing comma: the rows are inserted, the entry keeps working, a second
#    run changes nothing.
H="$WORK/home-existing"; F="$(menu_file "$H")"; mkdir -p "${F%/*}"
cat >"$F" <<'EOF'
{
  // Extend the Quickshell Omarchy menu with JSONC.
  // "personal": {"icon":"","label":"Personal"},
  "personal.notes": {"icon":"N","label":"Notes","action":"omarchy-launch-editor ~/notes"}
  // trailing comment
}
EOF
chmod 640 "$F"
run_menu "$H" >/dev/null
first="$(cat "$F")"
output="$(run_menu "$H")"
if has_rows "$F" &&
   omarchy_parse "$F" | jq -e '."personal.notes".label == "Notes"' >/dev/null &&
   [[ "$(cat "$F")" == "$first" && "$output" == *"already has the Drive Backup submenu"* ]] &&
   [[ "$(stat -c '%a' "$F" 2>/dev/null || stat -f '%Lp' "$F")" == 640 ]] &&
   [[ "$(grep -c '"drive-backup":' "$F")" == 1 ]]; then
  pass "rows are added to an existing file once; existing entries and permissions stay"
else
  fail "existing file: $output / $(cat "$F")"
fi

# 3. A file without a closing brace is left untouched and the rows are printed.
H="$WORK/home-broken"; F="$(menu_file "$H")"; mkdir -p "${F%/*}"
printf '{\n  "a": {"label":"A"},\n' >"$F"
before="$(cat "$F")"
output="$(run_menu "$H")"; status=$?
if (( status != 0 )) && [[ "$(cat "$F")" == "$before" && "$output" == *'"drive-backup.run"'* ]] &&
   [[ -z "$(find "${F%/*}" -name 'omarchy-menu.jsonc.*')" ]]; then
  pass "a file without a closing brace is left unchanged and the rows are printed"
else
  fail "broken file: $output"
fi

# 4. Without Omarchy nothing is written.
H="$WORK/home-none"; mkdir -p "$H"
output="$(run_menu "$H")"; status=$?
if (( status != 0 )) && [[ ! -e "$H/.config/omarchy" && "$output" == *"Omarchy not found"* ]]; then
  pass "without Omarchy nothing is written"
else
  fail "no Omarchy: $output"
fi

if (( failures > 0 )); then
  printf '%d Linux Omarchy menu test(s) failed.\n' "$failures"
  exit 1
fi
printf 'All Linux Omarchy menu tests passed.\n'
