#!/usr/bin/env bash
# Headless crash repro (core-rebuild story 066; ADR-0007 Risks "A native crash during tests").
# Runs ONE named Godot command in its own process, with a timeout, and reports the exit code and a
# stack when one can be had. Observations only.
#
# Usage: tools/crash_repro.sh <label> <outdir> -- <godot arguments...>
#   e.g. tools/crash_repro.sh unit-native out -- --headless --path . -s -d res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/unit/native --ignoreHeadlessMode
#   e.g. tools/crash_repro.sh one-scene out -- --headless --path . res://tests/scenes/some.tscn --quit-after 5
# Env: GODOT (console exe), TIMEOUT (seconds, default 120), CDB (path to cdb.exe; default
#      C:/Program Files (x86)/Windows Kits/10/Debuggers/x64/cdb.exe when that file exists).
# Output: <outdir>/<label>.log, <outdir>/<label>.stack.txt, and a summary on stdout:
#   exit code, whether it is a crash code (139, or a Windows 0xC0000005/0xC00000FD style code) and the stack frames:
#   from cdb (native frames resolved against the PDB beside the DLL) when cdb exists, otherwise only Godot's own
#   "Dumping the backtrace" frames when its crash handler printed any.
# Exit code of this script: the Godot exit code (124 when the timeout hit).
set -u
LABEL="${1:?label}"; OUT="${2:?outdir}"; shift 2
[ "${1:-}" = "--" ] && shift
GODOT="${GODOT:-C:/Godot/Godot_v4.8-beta3_win64_console.exe}"
TIMEOUT="${TIMEOUT:-120}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$OUT"
LOG="$OUT/$LABEL.log"; STACK="$OUT/$LABEL.stack.txt"
cd "$ROOT" || exit 2
DEFAULT_CDB="C:/Program Files (x86)/Windows Kits/10/Debuggers/x64/cdb.exe"
CDB="${CDB:-}"
if [ -z "$CDB" ] && [ -x "$DEFAULT_CDB" ]; then CDB="$DEFAULT_CDB"; fi
# Lines that are real stack frames or the exception record, not any line that happens to mention a file.
FRAME_RE='^[0-9a-fA-F`]{8,}[[:space:]]+:.*![^[:space:]]+|^[A-Za-z0-9_]+![^[:space:]]+\+0x[0-9a-fA-F]+:|Access violation|ExceptionCode|ExceptionAddress'

if [ -n "$CDB" ] && [ -x "$CDB" ]; then
	# cdb runs the process and its child processes (-o: the console exe starts the real Godot as a child), skips the
	# initial and final breakpoints (-g -G), and on the first access violation prints the stack (kb) and quits. The
	# symbol path holds the DLL folder, so the native frames resolve against addons/dogworks_core/bin/*.pdb.
	timeout "$TIMEOUT" "$CDB" -o -g -G -c "kb 40;q" -y "$ROOT/addons/dogworks_core/bin;$ROOT/native/obj/debug/dist" "$GODOT" "$@" > "$LOG" 2>&1
	code=$?
	grep -E "$FRAME_RE" "$LOG" > "$STACK"
	how="cdb"
else
	timeout "$TIMEOUT" "$GODOT" "$@" > "$LOG" 2>&1
	code=$?
	sed -n '/Dumping the backtrace/,$p' "$LOG" | grep -E '^\s*\[[0-9]+\] ' | head -40 > "$STACK"
	how="godot-log"
fi
crashed=0
grep -q 'Access violation' "$LOG" && crashed=1
[ "$crashed" = 1 ] && code=139
echo "label=$LABEL exit=$code stack_source=$how timeout=${TIMEOUT}s log=$LOG"
case "$code" in
	0) echo "result: clean exit" ;;
	124) echo "result: TIMEOUT after ${TIMEOUT}s (a hang; the process was stopped by timeout, which this script started)" ;;
	139|134|3221225477|-1073741819) echo "result: CRASH (segmentation fault or access violation)" ;;
	*) echo "result: non-zero exit $code" ;;
esac
if [ -s "$STACK" ]; then echo "stack ($how):"; head -40 "$STACK" | sed 's/^/  /'; else echo "stack: none available ($([ "$how" = cdb ] || echo 'cdb.exe not found: install the Windows SDK Debugging Tools and set CDB; ')Godot printed no backtrace in the log)"; fi
exit $code
