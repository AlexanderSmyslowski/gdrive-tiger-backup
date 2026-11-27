#!/bin/bash
# Read-only status commands of the engine (--status, --status-json, --waybar)
# on macOS and Linux: built from the last-run summary and the run history,
# printed to the terminal, never written to the log.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENGINE="$ROOT/bin/backup-google-drive.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/gdrive-status-test.XXXXXX")"
failures=0
trap '"$ROOT/scripts/trash-path.sh" "$WORK" >/dev/null 2>&1 || true' EXIT

pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1"; failures=$((failures + 1)); }

now="$(date +%s)"
summary="$WORK/last-run.status"
history="$WORK/run-history.tsv"
cat >"$summary" <<EOS
protocol=1
status=success
started_at=$((now - 7300))
finished_at=$((now - 7200))
last_success_at=$((now - 7200))
trigger=schedule
target=nas
destination=/srv/share/GoogleDrive-Backup
EOS
{
  printf 'v1\t%s\tfailure\tnas\t/srv/share/GoogleDrive-Backup\tschedule\t%s\n' "$((now - 90000))" "$((now - 91000))"
  printf 'v1\t%s\tsuccess\tnas\t/srv/share/GoogleDrive-Backup\tschedule\t%s\n' "$((now - 7200))" "$((now - 7300))"
  printf 'v1\t%s\tsuccess\tapfs\t/media/disk/GoogleDrive-Backup\tmanual\t%s\tUUID-1\tSamsung PSSD T7\t1000204886016\tyes\tUSB\n' \
    "$((now - 200000))" "$((now - 201000))"
} >"$history"

run_engine() {
  env HOME="$WORK/home" GDRIVE_BACKUP_CONFIG=/dev/null GDRIVE_BACKUP_SCHEDULE=daily \
    GDRIVE_BACKUP_SUMMARY_STATE_FILE="$summary" GDRIVE_BACKUP_HISTORY_FILE="$history" \
    GDRIVE_BACKUP_LOG="$WORK/backup.log" GDRIVE_BACKUP_LOCK="$WORK/backup.lock" \
    /bin/bash "$ENGINE" "$@"
}
mkdir -p "$WORK/home"

json="$(run_engine --status-json)"
if [[ "$(jq -r '.status' <<<"$json")" == "success" &&
      "$(jq -r '.last_success_at' <<<"$json")" == "$((now - 7200))" &&
      "$(jq -r '.schedule' <<<"$json")" == "daily" &&
      "$(jq -r '.destinations | length' <<<"$json")" == "2" &&
      "$(jq -r '.destinations[0].target' <<<"$json")" == "nas" &&
      "$(jq -r '.destinations[0].last_failure' <<<"$json")" == "$((now - 90000))" &&
      "$(jq -r '.destinations[1].device' <<<"$json")" == "Samsung PSSD T7" ]]; then
  pass "status JSON combines the summary and the history per destination"
else
  fail "status JSON: $json"
fi

waybar="$(run_engine --waybar)"
if [[ "$(jq -r '.class' <<<"$waybar")" == "success" && "$(jq -r '.text' <<<"$waybar")" == "✓ 2h" &&
      "$(jq -r '.tooltip' <<<"$waybar")" == *"Samsung PSSD T7: success"* ]]; then
  pass "Waybar output has a short text, a CSS class and a tooltip"
else
  fail "Waybar output: $waybar"
fi

text="$(run_engine --status)"
if [[ "$text" == *"Status:        success"* && "$text" == *"Samsung PSSD T7 · /media/disk/GoogleDrive-Backup"* &&
      "$text" == *"/srv/share/GoogleDrive-Backup"* ]]; then
  pass "status text lists every destination"
else
  fail "status text: $text"
fi

if [[ ! -s "$WORK/backup.log" ]]; then
  pass "status commands write nothing to the backup log"
else
  fail "status wrote to the log: $(cat "$WORK/backup.log")"
fi

old="$WORK/stale.status"
printf 'protocol=1\nstatus=success\nfinished_at=%s\nlast_success_at=%s\n' "$((now - 200000))" "$((now - 200000))" >"$old"
stale="$(env HOME="$WORK/home" GDRIVE_BACKUP_CONFIG=/dev/null GDRIVE_BACKUP_SUMMARY_STATE_FILE="$old" \
  GDRIVE_BACKUP_HISTORY_FILE="$WORK/none.tsv" GDRIVE_BACKUP_LOG="$WORK/backup.log" /bin/bash "$ENGINE" --waybar)"
empty="$(env HOME="$WORK/home" GDRIVE_BACKUP_CONFIG=/dev/null GDRIVE_BACKUP_SUMMARY_STATE_FILE="$WORK/none.status" \
  GDRIVE_BACKUP_HISTORY_FILE="$WORK/none.tsv" GDRIVE_BACKUP_LOG="$WORK/backup.log" /bin/bash "$ENGINE" --status-json)"
if [[ "$(jq -r '.class' <<<"$stale")" == "stale" && "$(jq -r '.status' <<<"$empty")" == "never" &&
      "$(jq -r '.destinations | length' <<<"$empty")" == "0" ]]; then
  pass "an old success is stale and a fresh installation reports never"
else
  fail "stale/empty: $stale / $empty"
fi

if (( failures > 0 )); then
  printf '%d status output test(s) failed.\n' "$failures"
  exit 1
fi
printf 'All status output tests passed.\n'
