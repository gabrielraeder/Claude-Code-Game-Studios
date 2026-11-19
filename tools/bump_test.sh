#!/usr/bin/env bash
# Kart-bump test (story 002): a host and one client race on this PC with chosen debug
# drivers, then each prints a [bump-summary] line (what its own screen showed).
# Usage: tools/bump_test.sh OUTDIR "HOST ARGS" "CLIENT ARGS" [SECONDS=30] [WINDOWED=host|client|none]
# Example: tools/bump_test.sh out/a "--park" "--ram" 30 host
set -u
# Uses UDP port 24690 (PORT env to change) so a game you are playing on 24680 is left alone.
OUT="$1"; HOST_ARGS="$2"; CLIENT_ARGS="$3"; SECS="${4:-30}"; WIN="${5:-none}"
GODOT="${GODOT:-C:/Godot/Godot_v4.8-beta3_win64_console.exe}"
if [ -e "$OUT" ]; then echo "outdir exists: $OUT" >&2; exit 2; fi
mkdir -p "$OUT/shots"
hh="--headless"; ch="--headless"; hs=""; cs=""
[ "$WIN" = host ] && hh="" && hs="--shots=$OUT/shots"
[ "$WIN" = client ] && ch="" && cs="--shots=$OUT/shots"
"$GODOT" $hh --path . -- --host --port=${PORT:-24690} --players=2 --bots=${BOTS:-0} --quit-after=$SECS $hs $HOST_ARGS > "$OUT/host.txt" 2>&1 &
sleep 2
"$GODOT" $ch --path . -- --join=127.0.0.1:${PORT:-24690} --quit-after=$((SECS - 2)) $cs $CLIENT_ARGS > "$OUT/client.txt" 2>&1
wait
grep -h "bump-summary" "$OUT/host.txt" "$OUT/client.txt"
grep -hcE "ERROR|SCRIPT ERROR" "$OUT/host.txt" "$OUT/client.txt" | paste -sd' ' | sed 's/^/errors host,client: /'
