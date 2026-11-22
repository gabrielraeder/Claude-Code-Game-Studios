#!/usr/bin/env bash
# One regression command for the frozen 2.5D game (core-rebuild story 001).
# Runs, sequentially: track_check on both tracks, the shell tests (bot race, online items,
# kart bump, a short online stress race), the golden-trace capture and the trace compare.
# Prints one "PASS <check>" or "FAIL <check> (reason)" line per check and a final RESULT line;
# exits 1 when any check fails.
#
# Usage: tools/regression.sh [outdir (must not exist)]
#   default outdir: production/qa/regression/<date>-<time> (logs of every check)
# Env: GODOT (console exe), PORT (default 24690; 24680 is refused), GOLDEN (trace folder to
#      compare with, default the story-001 golden set), RACE_SEED (bot races in the capture),
#      CHECKS (space-separated subset of: track_check bot_race item_net bump net_stress traces;
#      default all; a full run takes about 10 minutes, so a subset helps when time-boxed).
# Only starts its own Godot processes, and only the shell tests' own watchdogs stop them.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2
export GODOT="${GODOT:-C:/Godot/Godot_v4.8-beta3_win64_console.exe}"
export PORT="${PORT:-24690}"
if [ "$PORT" = 24680 ]; then echo "port 24680 is reserved for play sessions" >&2; exit 2; fi
OUT="${1:-$ROOT/production/qa/regression/$(date +%Y%m%d-%H%M%S)}"
if [ -e "$OUT" ]; then echo "outdir exists: $OUT" >&2; exit 2; fi
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
GOLDEN="${GOLDEN:-$ROOT/production/qa/evidence/core-rebuild-story-001/golden}"
# Real seconds a track_check run may take before it counts as failed.
TRACK_CHECK_TIMEOUT=600
# Lines in a Godot log that mean a script broke.
SCRIPT_ERRORS='SCRIPT ERROR|Parse Error|Failed to load script'
CHECKS="${CHECKS:-track_check bot_race item_net bump net_stress traces}"
fails=0
want() { case " $CHECKS " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }
result() {  # result NAME OK(0/1) REASON
	if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 ($3)"; fails=$((fails + 1)); fi
}
script_errors() {  # script_errors FILES... -> count of broken-script lines
	cat "$@" 2>/dev/null | grep -cE "$SCRIPT_ERRORS"
}

echo "regression: out=$OUT port=$PORT golden=$GOLDEN checks=$CHECKS"

if want track_check; then
for track in castle_circuit dungeon_depths; do
	timeout "$TRACK_CHECK_TIMEOUT" "$GODOT" --headless --path . -s res://tools/track_check.gd -- --track="$track" \
		> "$OUT/track_check_$track.log" 2>&1
	code=$?
	result "track_check $track" $([ $code = 0 ] && echo 0 || echo 1) \
		"exit $code; $(grep -c '^FAIL' "$OUT/track_check_$track.log") FAIL lines, see track_check_$track.log"
done
fi

if want bot_race; then
QUIT=180 bash tools/bot_race_test.sh "$OUT/bot_race" castle_circuit 11 1 0 > "$OUT/bot_race.txt" 2>&1
code=$?; errs=$(script_errors "$OUT"/bot_race/*.log)
ok=1; [ $code = 0 ] && [ "$errs" = 0 ] && grep -q '^bots finished:' "$OUT/bot_race.txt" && ok=0
result "bot_race_test (11 bots, 1 lap)" $ok "exit $code, script errors $errs, see bot_race.txt"
fi

if want item_net; then
bash tools/item_net_test.sh "$OUT/item_net" castle_circuit 1 > "$OUT/item_net.txt" 2>&1
code=$?; errs=$(script_errors "$OUT"/item_net/*.log)
same=$(grep -c ': IDENTICAL' "$OUT/item_net.txt")
ok=1; [ $code = 0 ] && [ "$errs" = 0 ] && [ "$same" = 2 ] && ok=0
result "item_net_test (host + 2 clients, 1 lap)" $ok "exit $code, script errors $errs, $same/2 clients agree on hits"
fi

if want bump; then
bash tools/bump_test.sh "$OUT/bump" "--park" "--ram" 30 none > "$OUT/bump.txt" 2>&1
code=$?; errs=$(script_errors "$OUT"/bump/*.txt)
summaries=$(grep -c 'bump-summary' "$OUT/bump.txt")
ok=1; [ $code = 0 ] && [ "$errs" = 0 ] && [ "$summaries" = 2 ] && ok=0
result "bump_test (park vs ram, 30 s)" $ok "exit $code, script errors $errs, $summaries/2 bump summaries"
fi

if want net_stress; then
bash tools/net_stress_test.sh 4 1 "$OUT/net_stress" > "$OUT/net_stress.txt" 2>&1
code=$?; errs=$(script_errors "$OUT"/net_stress/*.log)
procs=$(sed -nE 's/^processes with a summary: ([0-9]+)/\1/p' "$OUT/net_stress.txt")
agree=$(sed -n '/== lead-change agreement ==/,/^(distinct/p' "$OUT/net_stress.txt" | grep -cE '^ +[0-9]+ ')
ok=1; [ $code = 0 ] && [ "$errs" = 0 ] && [ "${procs:-0}" = 4 ] && [ "$agree" = 1 ] && ok=0
result "net_stress_test (4 racers, 1 lap)" $ok "exit $code, script errors $errs, ${procs:-0}/4 summaries, $agree distinct lead sequences"
fi

if want traces; then
bash tools/capture_all_traces.sh "$OUT/traces" > "$OUT/capture.txt" 2>&1
code=$?
result "trace capture (6 runs)" $code "see capture.txt"

python -I tools/compare_traces.py "$GOLDEN" "$OUT/traces" > "$OUT/compare.txt" 2>&1
code=$?
result "trace compare vs golden" $([ $code = 0 ] && echo 0 || echo 1) "$(grep -m1 '^DIVERGED' "$OUT/compare.txt")"
fi

if [ $fails = 0 ]; then echo "RESULT PASS (out=$OUT)"; exit 0; fi
echo "RESULT FAIL: $fails check(s) failed (out=$OUT)"
exit 1
