#!/usr/bin/env bash
# Story 005: headless bot race. The host (autopilot = the "skilled human" reference, or parked)
# plus N bots, optionally with headless clients, then a per-bot summary from the [bot] log lines.
#
# Usage: tools/bot_race_test.sh <outdir (must not exist)> [track=castle_circuit] [bots=11] [laps=3] [clients=0] [extra args...]
# Env: GODOT, PORT (default 24690, never 24680), QUIT (real seconds before quit, default 300),
#      SCALE (Engine.time_scale, default 1; only safe with clients=0), HOST_DRIVER=autopilot|park
#      (default autopilot), HOST_WINDOWED=1 (host with a window), HOST_EXTRA (extra host args).
set -u
OUT="$1"; TRACK="${2:-castle_circuit}"; BOTS="${3:-11}"; LAPS="${4:-3}"; CLIENTS="${5:-0}"
shift 5 2>/dev/null || shift $# 2>/dev/null
EXTRA=("$@")
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-C:/Godot/Godot_v4.8-beta3_win64_console.exe}"
PORT="${PORT:-24690}"
if [ "$PORT" = 24680 ]; then echo "port 24680 is reserved" >&2; exit 2; fi
if [ -e "$OUT" ]; then echo "outdir exists: $OUT" >&2; exit 2; fi
mkdir -p "$OUT"; cd "$ROOT" || exit 2
DRV="--autopilot"; [ "${HOST_DRIVER:-autopilot}" = park ] && DRV="--park"
SC=""; [ "${SCALE:-1}" != 1 ] && SC="--time-scale=${SCALE}"
COMMON=(--laps="$LAPS" --track="$TRACK" "${EXTRA[@]}")
"$GODOT" $([ "${HOST_WINDOWED:-0}" = 1 ] || echo --headless) --path . -- --host --port="$PORT" --players=$((CLIENTS + 1)) --bots="$BOTS" \
	$DRV --quit-after="${QUIT:-300}" $SC "${COMMON[@]}" ${HOST_EXTRA:-} --netlog="$OUT/host.csv" > "$OUT/host.log" 2>&1 &
PIDS=($!)
for i in $(seq 1 "$CLIENTS"); do
	sleep 1
	"$GODOT" --headless --path . -- --join=127.0.0.1:"$PORT" --autopilot --quit-after="${QUIT:-300}" "${COMMON[@]}" \
		--netlog="$OUT/client$i.csv" > "$OUT/client$i.log" 2>&1 &
	PIDS+=($!)
done
( sleep $(( ${QUIT:-300} + 60 )); kill "${PIDS[@]}" 2>/dev/null ) &
WD=$!
wait "${PIDS[@]}"
kill "$WD" 2>/dev/null
python -I "$ROOT/tools/bot_log_summary.py" "$OUT" | tee "$OUT/summary.txt"
