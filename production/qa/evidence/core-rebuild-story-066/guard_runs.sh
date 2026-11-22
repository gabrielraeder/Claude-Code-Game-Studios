#!/usr/bin/env bash
# Story 066: boot check, source-hash callers, core_greps rule (positive and negative runs).
# Usage: guard_runs.sh <scratch dir outside the repo>
# One Godot process at a time. The one hashed file it touches is restored byte for byte (sha256 shown).
set -u
cd "$(dirname "$0")/../../../.." || exit 2
S="$1"; mkdir -p "$S"
G=C:/Godot/Godot_v4.8-beta3_win64_console.exe
SRC=native/src/core/dogworks_core.cpp
sha() { sha256sum "$1" | cut -d' ' -f1; }
strip() { sed 's/\x1b\[[0-9;]*m//g'; }
RUNBOOT='res://tools/native_boot_check_run.gd'

echo "== A. boot check, fresh DLL (positive)"
timeout 120 $G --headless --path . -s $RUNBOOT 2>&1 | grep -E "BOOT_CHECK"; echo "   exit=${PIPESTATUS[0]}"

echo "== B. boot check with the extension absent (scratch project, no extension)"
(cd "$S/absent" && timeout 120 $G --headless --path . -s res://run_boot.gd 2>&1 | grep -E "BOOT_CHECK"; echo "   exit=${PIPESTATUS[0]}")

echo "== C. source hash mismatch: a hashed file changed and not rebuilt"
cp "$SRC" "$S/dogworks_core.cpp.orig"; before=$(sha "$SRC")
printf '// stale negative run\n' >> "$SRC"
echo "-- C1 native_boot_check.gd"
timeout 120 $G --headless --path . -s $RUNBOOT 2>&1 | grep -E "BOOT_CHECK" | cut -c1-260; echo "   exit=${PIPESTATUS[0]}"
echo "-- C2 shared test helper (before() of the native suite)"
timeout 300 $G --headless -s -d --remote-debug tcp://127.0.0.1:24690 res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/unit/native --ignoreHeadlessMode 2>&1 | strip | grep -E "stale native DLL|Statistics|Exit code" | cut -c1-300 | head -4
cp "$S/dogworks_core.cpp.orig" "$SRC"; echo "   source restored: $([ "$(sha "$SRC")" = "$before" ] && echo identical || echo DIFFERENT)"

echo "== D. core_greps rule"
echo "-- D1 positive (real tree)"
bash tools/core_greps.sh 2>&1 | tail -4 | cut -c1-200; echo "   exit=${PIPESTATUS[0]}"
echo "-- D2 negative (scratch tree: a suite names DogworksCore and does not call the helper)"
mkdir -p "$S/greps/native/src" "$S/greps/tests/unit/native" "$S/greps/src"
cp native/src/register_types.cpp "$S/greps/native/src/"
printf 'extends GdUnitTestSuite\nfunc test_x() -> void:\n\tvar n: int = DogworksCore.sim_hz()\n' > "$S/greps/tests/unit/native/bad_native_test.gd"
bash tools/core_greps.sh "$S/greps" 2>&1 | grep -A3 "native suites"; echo "   exit=${PIPESTATUS[0]}"
