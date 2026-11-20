#!/usr/bin/env bash
# Story 004: headless online item race, host + 2 clients on autopilot, each PC refilling a
# different item (spill / stone / falcon) every few seconds. Prints a per-PC item log and a
# cross-PC consistency summary of the HIT lines (item seq, victim, time).
#
# Usage: tools/item_net_test.sh <outdir (must not exist)> [track=castle_circuit] [laps=2] [extra args...]
# Env: GODOT, PORT (default 24690), GIVE_HOST/GIVE_C1/GIVE_C2 (item per PC, or 'all'),
# HOST_WINDOWED=1 (host with a window), HOST_EXTRA (extra host args, e.g. --shots=DIR).
set -u
OUT="$1"; TRACK="${2:-castle_circuit}"; LAPS="${3:-2}"
shift 3 2>/dev/null || shift $# 2>/dev/null
EXTRA=("$@")
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-C:/Godot/Godot_v4.8-beta3_win64_console.exe}"
PORT="${PORT:-24690}"
if [ -e "$OUT" ]; then echo "outdir exists: $OUT" >&2; exit 2; fi
mkdir -p "$OUT"; cd "$ROOT" || exit 2
COMMON=(--autopilot --quit-after-race --laps="$LAPS" --track="$TRACK" --item-interval=3 "${EXTRA[@]}")
"$GODOT" $([ "${HOST_WINDOWED:-0}" = 1 ] || echo --headless) --path . -- --host --port="$PORT" --players=3 --bots=0 "${COMMON[@]}" ${HOST_EXTRA:-} --give-item=${GIVE_HOST:-spill} > "$OUT/host.log" 2>&1 &
PIDS=($!)
sleep 3
"$GODOT" --headless --path . -- --join=127.0.0.1:"$PORT" "${COMMON[@]}" --give-item=${GIVE_C1:-stone} > "$OUT/client1.log" 2>&1 &
PIDS+=($!)
sleep 0.3
"$GODOT" --headless --path . -- --join=127.0.0.1:"$PORT" "${COMMON[@]}" --give-item=${GIVE_C2:-falcon} > "$OUT/client2.log" 2>&1 &
PIDS+=($!)
( sleep 420; kill "${PIDS[@]}" 2>/dev/null ) &
WD=$!
wait "${PIDS[@]}"
kill "$WD" 2>/dev/null
{
for f in host client1 client2; do
	echo "== $f: uses=$(grep -c '\] t=.* USE ' "$OUT/$f.log") box_events=$(grep -c ' BOX ' "$OUT/$f.log") hits=$(grep -c ' HIT ' "$OUT/$f.log") errors=$(grep -ciE 'error|SCRIPT ERROR' "$OUT/$f.log")"
	grep -E '\] t=.* (USE|HIT|END) ' "$OUT/$f.log" | sed 's/^\[item\] //'
	grep -E ' HIT ' "$OUT/$f.log" | sed -E 's/^\[item\] t=[0-9.-]+ //' | sort > "$OUT/$f.hits"
done
echo "== cross-PC hit consistency"
for f in client1 client2; do
	if diff -q "$OUT/host.hits" "$OUT/$f.hits" >/dev/null; then echo "host vs $f: IDENTICAL ($(wc -l < "$OUT/host.hits") hits)"; else echo "host vs $f: DIFFERENT"; diff "$OUT/host.hits" "$OUT/$f.hits"; fi
done
} | tee "$OUT/item-summary.txt"
