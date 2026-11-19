#!/usr/bin/env bash
# Headless online stress test (story 002): one host plus N-1 headless clients on this PC,
# all on autopilot, racing a full grid. Collects the [net-summary] lines.
#
# Usage: tools/net_stress_test.sh [racers=12] [laps=2] [outdir] [extra game args...]
#   racers  humans in the race (host + racers-1 clients); bots = 0
#   laps    laps to race (shorter than the default 3 to keep the run short)
#   outdir  must not exist yet (default: a new timestamped dir under production/qa/evidence/...)
#   extra   passed to every process, e.g. --lag=60 --jitter=20 --loss=3
# Env: GODOT = path to the Godot console exe.
set -u
RACERS="${1:-12}"
LAPS="${2:-2}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${3:-$ROOT/production/qa/evidence/story-002-online-multiplayer/stress-$RACERS-$(date +%H%M%S)}"
shift 3 2>/dev/null || shift $# 2>/dev/null
EXTRA=("$@")
GODOT="${GODOT:-C:/Godot/Godot_v4.8-beta3_win64_console.exe}"

if [ -e "$OUT" ]; then echo "outdir exists: $OUT" >&2; exit 2; fi
mkdir -p "$OUT"
cd "$ROOT" || exit 2

COMMON=(--autopilot --quit-after-race --laps="$LAPS" "${EXTRA[@]}")
echo "host + $((RACERS - 1)) clients, $LAPS laps, out=$OUT"
"$GODOT" --headless --path . -- --host --players="$RACERS" --bots=0 "${COMMON[@]}" \
	--netlog="$OUT/host.csv" > "$OUT/host.log" 2>&1 &
PIDS=($!)
sleep 3
for i in $(seq 1 $((RACERS - 1))); do
	"$GODOT" --headless --path . -- --join=127.0.0.1 "${COMMON[@]}" \
		--netlog="$OUT/client$i.csv" > "$OUT/client$i.log" 2>&1 &
	PIDS+=($!)
	sleep 0.3
done
START=$(date +%s)
# Safety cap: kill everything after 10 minutes.
( sleep 600; kill "${PIDS[@]}" 2>/dev/null ) &
WATCHDOG=$!
wait "${PIDS[@]}"
kill "$WATCHDOG" 2>/dev/null
echo "done in $(( $(date +%s) - START )) s"
"$ROOT/tools/net_stress_summary.sh" "$OUT" | tee "$OUT/summary.txt"
