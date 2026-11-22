#!/usr/bin/env bash
# Exit-safety check of the native core (core-rebuild story 066, ADR-0007 Verification Required 4).
# Runs tools/native_probe_runs.gd in its own Godot process per mode, one at a time:
#   exit_clean   a native object held by a GDScript static var at quit      -> exit 0, sentinel seen, NO "ERROR:" line at all
#   exit_rid     the same, and the object owns server RIDs                  -> exit 0, sentinel seen, NO "ERROR:" line at all
#   exit_leak    a deliberately leaked object (negative control)            -> sentinel seen AND the specific leak lines present
# Every run must print the sentinel "PROBE_RAN mode=<mode>". A run without it (timeout, missing DLL, crash before the
# end) is "NOT RUN" and counts as a failure: it is never read as "no leak" and never as "leak caught".
# On Godot 4.8-beta3 a deliberate leak exits 0 and prints "RID allocations ... leaked" / "ObjectDB instance ... leaked"
# lines; it does not crash with 139 (story 066 evidence), so those lines are the failure signal for a clean run.
# Prints one PASS, FAIL or NOT RUN line per run and exits 1 when any run is not PASS.
# Usage: tools/native_exit_safety.sh [outdir]   (default: native/obj/logs/exit_safety)
# Env: GODOT, TIMEOUT (seconds per run, default 120).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2
GODOT="${GODOT:-C:/Godot/Godot_v4.8-beta3_win64_console.exe}"
TIMEOUT="${TIMEOUT:-120}"
OUT="${1:-$ROOT/native/obj/logs/exit_safety}"
mkdir -p "$OUT"
LEAK_LINES='RID allocations .* leaked|ObjectDB instances? .*leaked'
DLL="addons/dogworks_core/bin/dogworks_core.windows.template_debug.x86_64.dll"
bad=0

# run_mode MODE -> sets code, ran (1 when the sentinel was printed), errors (ERROR: lines), leaks (leak lines)
run_mode() {
	timeout "$TIMEOUT" "$GODOT" --headless --path . -s res://tools/native_probe_runs.gd -- --mode="$1" > "$OUT/$1.txt" 2>&1
	code=$?
	ran=$(grep -c "^PROBE_RAN mode=$1\$" "$OUT/$1.txt")
	errors=$(grep -c 'ERROR:' "$OUT/$1.txt")
	leaks=$(grep -cE "$LEAK_LINES" "$OUT/$1.txt")
}

for mode in exit_clean exit_rid exit_leak; do
	if [ ! -f "$DLL" ]; then
		echo "NOT RUN native_exit $mode (the debug DLL is missing: $DLL)"
		bad=$((bad + 1)); continue
	fi
	run_mode "$mode"
	if [ "$ran" != 1 ] || [ "$code" = 124 ]; then
		echo "NOT RUN native_exit $mode (exit $code, sentinel PROBE_RAN not seen$([ "$code" = 124 ] && echo ", timed out after ${TIMEOUT}s"); see $OUT/$mode.txt)"
		bad=$((bad + 1)); continue
	fi
	if [ "$mode" = exit_leak ]; then
		if [ "$leaks" -ge 1 ]; then
			echo "PASS native_exit negative control exit_leak is caught ($leaks leak line(s) in $OUT/exit_leak.txt: $(grep -hE "$LEAK_LINES" "$OUT/exit_leak.txt" | head -1 | cut -c1-90))"
		else
			echo "FAIL native_exit negative control exit_leak was NOT caught: no leak line, so the check cannot fail (see $OUT/exit_leak.txt)"
			bad=$((bad + 1))
		fi
	elif [ "$code" = 0 ] && [ "$errors" = 0 ]; then
		echo "PASS native_exit $mode (exit 0, sentinel seen, no ERROR: line)"
	else
		echo "FAIL native_exit $mode (exit $code, $errors ERROR: line(s), $leaks leak line(s), see $OUT/$mode.txt)"
		bad=$((bad + 1))
	fi
done

# Story 067: a built CollisionQuery, a QueryCursor, a GroundHit and a WallHit held in static vars at quit
# (tools/collision_exit_probe.gd, run with --verbose). Exit 0, the sentinel, no ERROR: line and no leak line.
if [ ! -f "$DLL" ]; then
	echo "NOT RUN native_exit collision (the debug DLL is missing: $DLL)"
	bad=$((bad + 1))
else
	timeout "$TIMEOUT" "$GODOT" --headless --verbose --path . -s res://tools/collision_exit_probe.gd > "$OUT/collision.txt" 2>&1
	code=$?
	ran=$(grep -c '^PROBE_RAN ' "$OUT/collision.txt")
	errors=$(grep -c 'ERROR:' "$OUT/collision.txt")
	leaks=$(grep -cE "$LEAK_LINES" "$OUT/collision.txt")
	if [ "$ran" != 1 ] || [ "$code" = 124 ]; then
		echo "NOT RUN native_exit collision (exit $code, sentinel PROBE_RAN not seen; see $OUT/collision.txt)"
		bad=$((bad + 1))
	elif [ "$code" = 0 ] && [ "$errors" = 0 ] && [ "$leaks" = 0 ]; then
		echo "PASS native_exit collision (exit 0, sentinel seen, no ERROR: line, no leak line; CollisionQuery + QueryCursor + hits held at quit)"
	else
		echo "FAIL native_exit collision (exit $code, $errors ERROR: line(s), $leaks leak line(s), see $OUT/collision.txt)"
		bad=$((bad + 1))
	fi
fi
[ $bad = 0 ]
