#!/usr/bin/env bash
# Story 005: sequential bot races for the sink count. Usage: tools/bot_sink_batch.sh <outdir> <track> <races>
# Each race is a fresh host (new random race seed), 11 bots, 3 laps, SCALE=4, one Godot at a time.
set -u
OUT="$1"; TRACK="$2"; N="$3"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
for i in $(seq 1 "$N"); do
	PORT="${PORT:-24691}" SCALE=4 QUIT="${QUIT:-170}" bash "$ROOT/tools/bot_race_test.sh" "$OUT/$TRACK-$i" "$TRACK" 11 3 0 > /dev/null 2>&1
	python -I "$ROOT/tools/bot_log_summary.py" "$OUT/$TRACK-$i" | grep -E "SEED|SINKS|^bots finished|^bots with|per location" | sed "s/^/[$TRACK-$i] /"
done
