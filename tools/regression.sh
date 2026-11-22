#!/usr/bin/env bash
# One regression command for the frozen 2.5D game (core-rebuild story 001).
# Runs, sequentially: track_check on both tracks, the shell tests (bot race, online items,
# kart bump, a short online stress race), the golden-trace capture and the trace compare.
# Prints one "PASS <check>" or "FAIL <check> (reason)" line per check, a "WARN ..." line for a
# known intermittent behaviour of the frozen game, and a final RESULT line:
#   RESULT PASS (6/6 checks) warnings=W              every check ran and passed (exit 0)
#   RESULT PARTIAL PASS (n/6: names) warnings=W      a CHECKS subset ran and passed (exit 0)
#   RESULT FAIL: k check(s) failed (n/6: names) warnings=W                       (exit 1)
# Exit 2 on bad usage (unknown CHECKS name, existing outdir, reserved port).
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
# Every check this script knows, in run order.
ALL_CHECKS="track_check bot_race item_net bump net_stress traces"
TOTAL_CHECKS=6
CHECKS="${CHECKS:-$ALL_CHECKS}"
bad=""
n_checks=0
for c in $CHECKS; do
	n_checks=$((n_checks + 1))
	case " $ALL_CHECKS " in *" $c "*) ;; *) bad="$bad $c" ;; esac
done
if [ -n "$bad" ]; then echo "unknown CHECKS name(s):$bad; known: $ALL_CHECKS" >&2; exit 2; fi
if [ $n_checks = 0 ]; then echo "CHECKS names no check; known: $ALL_CHECKS" >&2; exit 2; fi
OUT="${1:-$ROOT/production/qa/regression/$(date +%Y%m%d-%H%M%S)}"
if [ -e "$OUT" ]; then echo "outdir exists: $OUT" >&2; exit 2; fi
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
GOLDEN="${GOLDEN:-$ROOT/production/qa/evidence/core-rebuild-story-001/golden}"
# Golden traces the compare must find (capture_all_traces.sh: 2 tracks x cart, bike, bots).
GOLDEN_FILES=6
# Real seconds a track_check run may take before it counts as failed.
TRACK_CHECK_TIMEOUT=600
# Lines in a Godot log that mean a script, or a resource or file it needs, broke.
SCRIPT_ERRORS='SCRIPT ERROR|Parse Error|Failed to load script|Failed loading resource|Cannot open file'
# Label of the known intermittent net_stress lead-sequence divergence (frozen game, not fixed here).
KNOWN_LEAD_DIVERGENCE='known: TD-011 frozen near-tie lead divergence'
fails=0
warnings=0
ran=0
ran_names=""
want() {  # want NAME -> true when NAME is selected; counts it as run
	case " $CHECKS " in
		*" $1 "*) ran=$((ran + 1)); ran_names="$ran_names $1"; return 0 ;;
		*) return 1 ;;
	esac
}
result() {  # result NAME OK(0/1) REASON
	if [ "$2" = 0 ]; then echo "PASS $1"; else echo "FAIL $1 ($3)"; fails=$((fails + 1)); fi
}
script_errors() {  # script_errors FILES... -> count of broken-script lines
	cat "$@" 2>/dev/null | grep -cE "$SCRIPT_ERRORS"
}

echo "regression: out=$OUT port=$PORT golden=$GOLDEN checks=$CHECKS"

if want track_check; then
for track in castle_circuit dungeon_depths; do
	log="$OUT/track_check_$track.log"
	timeout "$TRACK_CHECK_TIMEOUT" "$GODOT" --headless --path . -s res://tools/track_check.gd -- --track="$track" \
		> "$log" 2>&1
	code=$?; errs=$(script_errors "$log")
	all_pass=$(grep -cx '== ALL PASS ==' "$log")
	ok=1; [ $code = 0 ] && [ "$errs" = 0 ] && [ "$all_pass" = 1 ] && ok=0
	result "track_check $track" $ok \
		"exit $code, script errors $errs, $(grep -c '^FAIL' "$log") FAIL lines, $all_pass '== ALL PASS ==' lines, see track_check_$track.log"
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
# Each process must have logged at least one hit: two empty .hits files are trivially identical.
hit_files=0
for f in host client1 client2; do
	lines=$(grep -c . "$OUT/item_net/$f.hits" 2>/dev/null)
	[ "${lines:-0}" -ge 1 ] && hit_files=$((hit_files + 1))
done
ok=1; [ $code = 0 ] && [ "$errs" = 0 ] && [ "$same" = 2 ] && [ "$hit_files" = 3 ] && ok=0
result "item_net_test (host + 2 clients, 1 lap)" $ok \
	"exit $code, script errors $errs, $same/2 clients agree on hits, $hit_files/3 .hits files with a hit"
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
# Error lines net_stress_summary.sh counted in the logs ("(count: N)").
log_errs=$(sed -n '/== errors \/ warnings in logs ==/,$p' "$OUT/net_stress.txt" | sed -nE 's/^\(count: ([0-9]+)\)$/\1/p')
# Places the 4 processes report for their own kart: must be 1 2 3 4, each once.
places=$(sed -n '/== finished places ==/{n;p;}' "$OUT/net_stress.txt" | tr ';' '\n' | awk 'NF {print $1}' | tr '\n' ' ')
ok=1; [ $code = 0 ] && [ "$errs" = 0 ] && [ "${log_errs:-x}" = 0 ] && [ "${procs:-0}" = 4 ] \
	&& [ "$places" = "1 2 3 4 " ] && [ "$agree" -ge 1 ] && ok=0
result "net_stress_test (4 racers, 1 lap)" $ok \
	"exit $code, script errors $errs, log errors ${log_errs:-none}, ${procs:-0}/4 summaries, places '$places', $agree distinct lead sequences"
# Lead-sequence disagreement alone is a known intermittent of the frozen game: warn, do not fail.
if [ $ok = 0 ] && [ "$agree" != 1 ]; then
	echo "WARN net_stress_test lead sequences: $agree distinct ($KNOWN_LEAD_DIVERGENCE), see net_stress.txt"
	warnings=$((warnings + 1))
fi
fi

if want traces; then
bash tools/capture_all_traces.sh "$OUT/traces" > "$OUT/capture.txt" 2>&1
code=$?; errs=$(script_errors "$OUT"/traces/*.log)
ok=1; [ $code = 0 ] && [ "$errs" = 0 ] && ok=0
result "trace capture (6 runs)" $ok "exit $code, script errors $errs, see capture.txt"

python -I tools/compare_traces.py "$GOLDEN" "$OUT/traces" --expect "$GOLDEN_FILES" > "$OUT/compare.txt" 2>&1
code=$?
result "trace compare vs golden" $([ $code = 0 ] && echo 0 || echo 1) "exit $code; $(grep -m1 '^DIVERGED' "$OUT/compare.txt")"
new_only=$(grep -c '^WARN' "$OUT/compare.txt")
if [ "$new_only" != 0 ]; then grep '^WARN' "$OUT/compare.txt"; warnings=$((warnings + new_only)); fi
fi

ran_names="${ran_names# }"
if [ $fails != 0 ]; then
	echo "RESULT FAIL: $fails check(s) failed ($ran/$TOTAL_CHECKS: $ran_names) warnings=$warnings (out=$OUT)"
	exit 1
fi
if [ $ran = $TOTAL_CHECKS ]; then
	echo "RESULT PASS ($ran/$TOTAL_CHECKS checks) warnings=$warnings (out=$OUT)"
else
	echo "RESULT PARTIAL PASS ($ran/$TOTAL_CHECKS: $ran_names) warnings=$warnings (out=$OUT)"
fi
exit 0
