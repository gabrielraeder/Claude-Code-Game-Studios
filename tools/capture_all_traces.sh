#!/usr/bin/env bash
# Captures every golden trace of the frozen 2.5D game (core-rebuild story 001) into OUTDIR,
# one CSV per run, sequentially. REGRESSION TOOL: it runs the real main scene through
# tools/capture_traces.gd, headless with one physics tick per frame (--fixed-fps 60).
#
# Usage: tools/capture_all_traces.sh <outdir (must not exist)>
# Env: GODOT (console exe), PORT (default 24690, never 24680), RACE_SEED (bot races, default 1001),
#      RUN_TIMEOUT (real seconds per run before it is stopped, default 300).
# Runs: autopilot 1 lap on castle_circuit and dungeon_depths with the cart and the bike, and one
# bot race per track (host autopilot + 11 bots, 1 lap, fixed race seed). Exit 1 if any run fails.
set -u
OUT="$1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-C:/Godot/Godot_v4.8-beta3_win64_console.exe}"
PORT="${PORT:-24690}"
SEED="${RACE_SEED:-1001}"
if [ "$PORT" = 24680 ]; then echo "port 24680 is reserved" >&2; exit 2; fi
if [ -e "$OUT" ]; then echo "outdir exists: $OUT" >&2; exit 2; fi
mkdir -p "$OUT"; cd "$ROOT" || exit 2
OUT_ABS="$(cd "$OUT" && pwd)"
fail=0
run() {  # run NAME game-args...
	local name="$1"; shift
	timeout "${RUN_TIMEOUT:-300}" "$GODOT" --headless --fixed-fps 60 --path . -s res://tools/capture_traces.gd -- \
		--trace-out="$OUT_ABS/$name.csv" "$@" > "$OUT_ABS/$name.log" 2>&1
	local code=$?
	if [ $code -ne 0 ] || [ ! -s "$OUT_ABS/$name.csv" ]; then
		echo "capture $name: FAILED (exit $code, see $OUT_ABS/$name.log)"; fail=1
	else
		echo "capture $name: $(($(wc -l < "$OUT_ABS/$name.csv") - 1)) rows"
	fi
}
for track in castle_circuit dungeon_depths; do
	for veh in cart bike; do
		run "solo_${track}_${veh}" --autopilot --quit-after-race --laps=1 --track="$track" --vehicle="$veh"
	done
	run "bots_${track}" --host --port="$PORT" --players=1 --bots=11 --autopilot --quit-after-race --laps=1 \
		--track="$track" --race-seed="$SEED"
done
exit $fail
