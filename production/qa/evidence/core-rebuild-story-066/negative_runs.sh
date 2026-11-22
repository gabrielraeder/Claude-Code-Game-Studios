#!/usr/bin/env bash
# Negative runs of tools/build_native.sh --check, and the bench swap/restore (story 066).
# Each run damages something on purpose, shows --check failing, and puts the exact bytes back (verified by sha256).
# Usage: negative_runs.sh <backup dir outside the repo>
# Starts one Godot process at a time, and only its own.
set -u
cd "$(dirname "$0")/../../../.." || exit 2
BK="$1"; mkdir -p "$BK"
BIN=addons/dogworks_core/bin
DBG=$BIN/dogworks_core.windows.template_debug.x86_64.dll
BEN=$BIN/dogworks_core.windows.bench.x86_64.dll
SRC=native/src/core/dogworks_core.cpp
G=C:/Godot/Godot_v4.8-beta3_win64_console.exe
sha() { sha256sum "$1" | cut -d' ' -f1; }
run_check() { bash tools/build_native.sh --check 2>&1 | sed 's/^/    /'; echo "    exit=${PIPESTATUS[0]}"; }

echo "== 0. fresh build passes"
run_check

echo "== 1. stale DLL: a hashed source changed and not rebuilt"
cp "$SRC" "$BK/dogworks_core.cpp.orig"; before=$(sha "$SRC")
printf '// stale-dll negative run\n' >> "$SRC"
run_check
cp "$BK/dogworks_core.cpp.orig" "$SRC"; echo "  source restored: $([ "$(sha "$SRC")" = "$before" ] && echo identical || echo DIFFERENT)"

echo "== 2. bench-target marker in the debug slot (no bench.lock)"
cp "$DBG" "$BK/debug.dll.orig"; before=$(sha "$DBG")
cp "$BEN" "$DBG"
run_check
cp "$BK/debug.dll.orig" "$DBG"; echo "  debug DLL restored: $([ "$(sha "$DBG")" = "$before" ] && echo identical || echo DIFFERENT)"

echo "== 3. marker count 2 (marker appended once more)"
grep -aoE 'DOGWORKS_BUILD:[a-z]+:[0-9a-f]{64}:[0-9a-f]{64}:END' "$DBG" >> "$DBG"
run_check
cp "$BK/debug.dll.orig" "$DBG"; echo "  debug DLL restored: $([ "$(sha "$DBG")" = "$before" ] && echo identical || echo DIFFERENT)"

echo "== 4. marker count 0 (first marker byte changed)"
LC_ALL=C sed -i 's/DOGWORKS_BUILD:debug/XOGWORKS_BUILD:debug/' "$DBG"
run_check
cp "$BK/debug.dll.orig" "$DBG"; echo "  debug DLL restored: $([ "$(sha "$DBG")" = "$before" ] && echo identical || echo DIFFERENT)"

echo "== 5. --bench refuses while a Godot process is open (own headless process, 14 s)"
($G --headless --path . -s res://tools/native_probe_runs.gd -- --mode=hold --seconds=14 > "$BK/hold.txt" 2>&1 &)
sleep 6
bash tools/build_native.sh --bench 2>&1 | sed 's/^/    /'; echo "    exit=${PIPESTATUS[0]}"
echo "  waiting for my own process to finish"; sleep 12

echo "== 6. --bench with no Godot open: backup, swap, bench.lock"
bash tools/build_native.sh --bench 2>&1 | sed 's/^/    /'
ls $BIN | sed 's/^/    bin: /'
echo "  --check while bench.lock exists:"
run_check
echo "  the bench DLL loads through the windows.debug entry (one headless process, 1 s):"
$G --headless --path . -s res://tools/native_probe_runs.gd -- --mode=hold --seconds=1 2>&1 | grep hold: | sed 's/^/    /'

echo "== 7. restore (copies the backup back, never rebuilds)"
bash tools/build_native.sh --restore 2>&1 | sed 's/^/    /'
echo "  debug DLL after restore: $([ "$(sha "$DBG")" = "$before" ] && echo identical-to-original || echo DIFFERENT)"
ls $BIN | sed 's/^/    bin: /'
run_check
