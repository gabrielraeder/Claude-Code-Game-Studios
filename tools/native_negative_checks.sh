#!/usr/bin/env bash
# Negative runs of the native toolchain guards (core-rebuild story 066). Each case damages something on purpose,
# shows the guard FAILING with the expected message, and puts the exact bytes back. A case PASSES when the guard
# catches the damage. Run by tools/regression.sh as the check `native_negative`; repeatable on its own:
#   tools/native_negative_checks.sh [outdir]
# Needs no Godot process to be open (it starts its own, one at a time, and waits for them). Exit 1 when any case
# is FAIL or NOT RUN. It changes, and restores before it ends (also on an abort, through a trap):
#   native/src/core/dogworks_core.cpp, the debug DLL, .godot/extension_list.cfg, addons/dogworks_core/bin/bench.lock.
# Scratch files live in native/obj/negative_tmp (ignored by git and by Godot).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 2
OUT="${1:-$ROOT/native/obj/logs/negative}"
TMP="$ROOT/native/obj/negative_tmp"
mkdir -p "$OUT" "$TMP"
: > "$ROOT/native/obj/.gdignore"
GODOT="${GODOT:-C:/Godot/Godot_v4.8-beta3_win64_console.exe}"
BIN=addons/dogworks_core/bin
DBG=$BIN/dogworks_core.windows.template_debug.x86_64.dll
BEN=$BIN/dogworks_core.windows.bench.x86_64.dll
SRC=native/src/core/dogworks_core.cpp
EXT=.godot/extension_list.cfg
BUILD="bash tools/build_native.sh"
fails=0
sha() { sha256sum "$1" | cut -d' ' -f1; }

# Backups and their expected hashes (the integrity check at the end compares against these).
cp "$SRC" "$TMP/src.orig"; SRC_SHA=$(sha "$SRC")
cp "$DBG" "$TMP/debug.orig"; DBG_SHA=$(sha "$DBG")
[ -f "$EXT" ] && cp "$EXT" "$TMP/extension_list.orig"
restore_all() {
	cp "$TMP/src.orig" "$SRC"
	cp "$TMP/debug.orig" "$DBG" 2>/dev/null
	[ -f "$TMP/extension_list.orig" ] && [ ! -f "$EXT" ] && cp "$TMP/extension_list.orig" "$EXT"
	[ -f "$BIN/bench.lock" ] && [ -f "$BIN/backup/$(basename "$DBG")" ] && $BUILD --restore >/dev/null 2>&1
}
trap restore_all EXIT

# case_run NAME WANT_EXIT REGEX CMD... : PASS when the command exits WANT_EXIT and its output matches REGEX.
case_run() {
	local name="$1" want="$2" rx="$3" out rc
	shift 3
	out="$("$@" 2>&1)"; rc=$?
	printf '%s\n' "$out" > "$OUT/$name.txt"
	if [ "$rc" = "$want" ] && printf '%s' "$out" | grep -qE "$rx"; then
		echo "PASS native_negative $name (exit $rc, output matches '$rx')"
	else
		echo "FAIL native_negative $name (exit $rc, wanted $want; pattern '$rx'; see $OUT/$name.txt)"
		printf '%s\n' "$out" | head -4 | cut -c1-200 | sed 's/^/    /'
		fails=$((fails + 1))
	fi
}

# Nothing of ours may be running; a case that needs "no Godot open" would otherwise lie.
open="$($BUILD --probe-godot 2>&1)"
if [ -n "$open" ]; then
	echo "NOT RUN native_negative (a Godot process is open, close it first): $(printf '%s' "$open" | head -2 | tr '\n' ' ')"
	trap - EXIT
	exit 1
fi

echo "== bad DLLs"
printf '// stale-dll negative run\n' >> "$SRC"
case_run stale_dll 1 'FAIL debug: stale DLL' $BUILD --check
echo "-- the same stale source seen by the other callers"
case_run stale_boot_check 3 "stale native DLL.*tools/build_native.sh" "$GODOT" --headless --path . -s res://tools/native_boot_check_run.gd
case_run stale_test_helper 100 "stale native DLL.*tools/build_native.sh" "$GODOT" --headless -s -d --remote-debug tcp://127.0.0.1:24690 res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/unit/native/native_toolchain_test.gd --ignoreHeadlessMode
case_run stale_editor_plugin 0 "ERROR: dogworks_core: stale native DLL.*tools/build_native.sh" "$GODOT" --headless --path . --import
cp "$TMP/src.orig" "$SRC"
stale_gate() { printf '%s
' '// stale' >> "$SRC"; $BUILD --check && echo GDUNIT_STARTED; local rc=$?; cp "$TMP/src.orig" "$SRC"; return $rc; }
case_run stale_test_command_stops_before_gdunit 1 'FAIL debug: stale DLL' stale_gate

cp "$BEN" "$DBG"
case_run bench_dll_in_debug_slot 1 "bench DLL is in the debug slot" $BUILD --check
cp "$TMP/debug.orig" "$DBG"

grep -aoE 'DOGWORKS_BUILD:[a-z]+:[0-9a-f]{64}:[0-9a-f]{64}:END' "$DBG" > "$TMP/marker.txt"
cat "$TMP/marker.txt" >> "$DBG"
case_run marker_count_2 1 "found 2 build markers" $BUILD --check
cp "$TMP/debug.orig" "$DBG"
LC_ALL=C sed -i 's/DOGWORKS_BUILD:debug/XOGWORKS_BUILD:debug/' "$DBG"
case_run marker_count_0 1 "found 0 build markers" $BUILD --check
cp "$TMP/debug.orig" "$DBG"

mv "$EXT" "$TMP/extension_list.moved"
case_run missing_extension_list 1 "without extension_list.cfg.*tools/build_native.sh" $BUILD --check
mv "$TMP/extension_list.moved" "$EXT"

echo "== bench swap"
case_run bench_swap 0 "bench.lock written" $BUILD --bench
case_run check_fails_while_bench_lock_exists 1 "bench.lock exists" $BUILD --check
case_run bench_restore 0 "bench.lock removed" $BUILD --restore
case_run check_passes_after_restore 0 "CHECK PASS" $BUILD --check
[ "$(sha "$DBG")" = "$DBG_SHA" ] && echo "PASS native_negative debug_dll_identical_after_restore" || { echo "FAIL native_negative debug_dll_identical_after_restore"; fails=$((fails + 1)); }

echo "== a Godot process is open (my own headless hold, 12 s)"
"$GODOT" --headless --path . -s res://tools/native_probe_runs.gd -- --mode=hold --seconds=12 > "$OUT/hold.txt" 2>&1 &
hold_pid=$!
sleep 5
case_run bench_refused_while_godot_open 2 "a Godot process is open" $BUILD --bench
case_run build_refused_while_dll_held 2 "a Godot process holds the DLL" $BUILD
wait "$hold_pid"

echo "== the process probe cannot answer"
case_run probe_failed_powershell_missing 2 "PROBE_FAILED" env POWERSHELL=no_such_powershell_for_this_test $BUILD --bench
case_run probe_failed_forced_throw_bench 2 "PROBE_FAILED" env DOG_FORCE_PROBE_THROW=1 $BUILD --bench
case_run probe_failed_forced_throw_build 2 "PROBE_FAILED" env DOG_FORCE_PROBE_THROW=1 $BUILD

echo "== bad hash list (both bash here; the GDScript side is in native_hash_parity_test.gd)"
printf 'bogus native/SConstruct\n' > "$TMP/list_unknown_kind.txt"
printf 'file native/does_not_exist.txt\n' > "$TMP/list_missing_file.txt"
printf 'tree native/no_such_dir\n' > "$TMP/list_missing_tree.txt"
mkdir -p "$TMP/emptytree"; printf 'tree native/obj/negative_tmp/emptytree\n' > "$TMP/list_empty_tree.txt"
mkdir -p "$TMP/dottree"; : > "$TMP/dottree/.only_dotfile"; printf 'tree native/obj/negative_tmp/dottree\n' > "$TMP/list_dot_only_tree.txt"
printf '# nothing\n' > "$TMP/list_empty.txt"
case_run hash_list_unknown_kind 1 "unknown line kind" env HASH_LIST="$TMP/list_unknown_kind.txt" $BUILD --hashes
case_run hash_list_missing_file 1 "listed file is missing" env HASH_LIST="$TMP/list_missing_file.txt" $BUILD --hashes
case_run hash_list_missing_tree 1 "listed tree is missing" env HASH_LIST="$TMP/list_missing_tree.txt" $BUILD --hashes
case_run hash_list_empty_tree 1 "tree holds no files" env HASH_LIST="$TMP/list_empty_tree.txt" $BUILD --hashes
case_run hash_list_dot_only_tree 1 "tree holds no files" env HASH_LIST="$TMP/list_dot_only_tree.txt" $BUILD --hashes
case_run hash_list_empty 1 "lists nothing" env HASH_LIST="$TMP/list_empty.txt" $BUILD --hashes

echo "== forbidden compiler flags"
printf 'cl /Fox.obj /c x.cpp /MT /fp:precise /O2\n' > "$TMP/flags_ok.txt"
printf 'cl /Fox.obj /c x.cpp /MT /fp:precise /fp:fast\n' > "$TMP/flags_fast.txt"
printf 'cl /Fox.obj /c x.cpp /MT /fp:precise /arch:AVX2\n' > "$TMP/flags_arch.txt"
printf 'cl /Fox.obj /c x.cpp /MD /fp:precise\n' > "$TMP/flags_md.txt"
printf 'cl /Fox.obj /c x.cpp /MT /O2\n' > "$TMP/flags_noprecise.txt"
case_run flag_scan_accepts_pinned_flags 0 "PASS flag scan" $BUILD --scan-flags "$TMP/flags_ok.txt"
case_run flag_scan_rejects_fp_fast 1 "forbidden flag" $BUILD --scan-flags "$TMP/flags_fast.txt"
case_run flag_scan_rejects_arch 1 "forbidden flag" $BUILD --scan-flags "$TMP/flags_arch.txt"
case_run flag_scan_rejects_md 1 "forbidden flag" $BUILD --scan-flags "$TMP/flags_md.txt"
case_run flag_scan_rejects_missing_fp_precise 1 "lacks /fp:precise" $BUILD --scan-flags "$TMP/flags_noprecise.txt"

echo "== boot check with the extension absent (scratch project without the extension)"
A="$TMP/absent"; mkdir -p "$A/addons/dogworks_core" "$A/src/core"
printf 'config_version=5\n\n[application]\nconfig/name="boot-absent"\n\n[physics]\ncommon/physics_ticks_per_second=60\n' > "$A/project.godot"
cp addons/dogworks_core/source_hash.gd "$A/addons/dogworks_core/"
cp src/core/native_boot_check.gd "$A/src/core/"
cp tools/native_boot_check_run.gd "$A/run_boot.gd"
case_run boot_extension_absent 3 "native extension is not loaded.*tools/build_native.sh" "$GODOT" --headless --path "$A" -s res://run_boot.gd

echo "== core_greps native-suite rule on scratch trees"
G="$TMP/greps"
mk_tree() {  # name registered(1/0) suite_text
	local d="$G/$1"
	mkdir -p "$d/native/src/collision" "$d/tests/unit/native" "$d/src/core"
	# Story 067: the per-tick-region rule FAILS on a tree with no region, so every scratch tree carries an empty one.
	printf '// PER_TICK_BEGIN
// PER_TICK_END
' > "$d/native/src/collision/stub.cpp"
	if [ "$2" = 1 ]; then printf 'GDREGISTER_CLASS(DogworksCore);\n' > "$d/native/src/register_types.cpp"; fi
	if [ "$2" = 0 ]; then printf '// nothing registered\n' > "$d/native/src/register_types.cpp"; fi
	if [ -n "$3" ]; then printf '%b' "$3" > "$d/tests/unit/native/x_test.gd"; fi
}
mk_tree empty_list 0 'extends GdUnitTestSuite\nfunc test_x() -> void:\n\tvar n: int = DogworksCore.sim_hz()\n'
mk_tree no_register_file 2 ''
mk_tree no_suites 1 ''
mk_tree comment_only 1 'extends GdUnitTestSuite\n# native_test_guard is called elsewhere: DogworksCore\nfunc before() -> void:\n\tpass\nfunc test_x() -> void:\n\tvar n: int = DogworksCore.sim_hz()\n'
mk_tree name_only 1 'extends GdUnitTestSuite\nconst _GUARD = preload("res://tests/unit/native/native_test_guard.gd")\nfunc test_x() -> void:\n\tvar n: int = DogworksCore.sim_hz()\n'
mk_tree real_call 1 'extends GdUnitTestSuite\nconst _GUARD = preload("res://tests/unit/native/native_test_guard.gd")\nfunc before() -> void:\n\tassert_str(_GUARD.problem()).is_empty()\nfunc test_x() -> void:\n\tvar n: int = DogworksCore.sim_hz()\n'
case_run greps_empty_class_list 1 "FAIL native suites call the shared hash helper \(no GDREGISTER" bash tools/core_greps.sh "$G/empty_list"
case_run greps_missing_register_types 1 "FAIL native suites call the shared hash helper \(native/src/register_types.cpp is missing" bash tools/core_greps.sh "$G/no_register_file"
case_run greps_zero_suites_is_not_run 1 "NOT RUN: no suite" bash tools/core_greps.sh "$G/no_suites"
case_run greps_comment_only_mention 1 "FAIL native suites call the shared hash helper .*does not preload" bash tools/core_greps.sh "$G/comment_only"
case_run greps_name_without_call 1 "FAIL native suites call the shared hash helper .*does not preload" bash tools/core_greps.sh "$G/name_only"
case_run greps_real_call_passes 0 "PASS native suites call the shared hash helper" bash tools/core_greps.sh "$G/real_call"

echo "== story 067: the native core_greps rules fail on planted violations, and a clean tree passes"
P="$TMP/plants"
mk_plant() {  # name relpath content(%b): a scratch tree with the register list and an empty per-tick region
	local d="$P/$1"
	mkdir -p "$d/native/src/collision" "$d/tests/unit/native" "$d/src/core"
	printf 'GDREGISTER_CLASS(CollisionQuery);\n' > "$d/native/src/register_types.cpp"
	printf '// PER_TICK_BEGIN\n// PER_TICK_END\n' > "$d/native/src/collision/stub.cpp"
	if [ -n "${2:-}" ]; then mkdir -p "$(dirname "$d/$2")"; printf '%b' "$3" > "$d/$2"; fi
}
# Every case here wants exit 1: the scratch tree has no suites, so the native-suite rule fails whatever the plant.
mk_plant clean "" ""
case_run plant_clean_tree_per_tick_rule_passes 1 "PASS no allocation, \*_create\( or String" bash tools/core_greps.sh "$P/clean"
tick_n=0
while IFS= read -r snippet; do
	tick_n=$((tick_n + 1))
	mk_plant "tick$tick_n" native/src/collision/planted.cpp "// PER_TICK_BEGIN\nvoid f() {\n\t$snippet\n}\n// PER_TICK_END\n"
	case_run "plant_per_tick_$tick_n" 1 "FAIL no allocation, .*per-tick regions" bash tools/core_greps.sh "$P/tick$tick_n"
done <<'SNIPPETS'
auto a = memnew(Foo);
auto a = new Foo();
String s;
StringName n;
Variant v;
Dictionary d;
Array a;
TypedArray<RID> a;
x.instantiate();
ERR_PRINT("x");
print_line("x");
UtilityFunctions::print("x");
auto b = ps->body_create();
v.push_back(1);
v.emplace_back(1);
v.assign(a, b);
v.insert(it, 1);
std::vector<int> v;
auto p = std::make_unique<int>();
v.resize(3);
v.reserve(3);
std::unordered_map<int, int> m;
int r = rand();
SNIPPETS
mk_plant dict native/src/collision/planted.cpp "void g() { state->intersect_ray(params); }\n"
case_run plant_dictionary_query_form 1 "FAIL no Dictionary query forms in native" bash tools/core_greps.sh "$P/dict"
mk_plant ctor native/src/collision/planted.cpp "void g() { Ref<CollisionQuery> q = memnew(CollisionQuery); }\n"
case_run plant_collision_query_construction 1 "FAIL CollisionQuery is constructed only" bash tools/core_greps.sh "$P/ctor"
mk_plant keypos native/src/kart/planted.cpp "int g() { return key_pos; }\n"
case_run plant_key_pos_outside_collision 1 "FAIL mover keys" bash tools/core_greps.sh "$P/keypos"
mk_plant clash src/planted.gd "class_name CollisionQuery\nextends RefCounted\n"
case_run plant_class_name_clash_register_list 1 "FAIL no class_name under src" bash tools/core_greps.sh "$P/clash"
mk_plant gdcreate src/planted.gd "func f():\n\tCollisionQuery.create({})\n"
case_run plant_gdscript_collision_query_create 1 "FAIL CollisionQuery.new\( / .create\(" bash tools/core_greps.sh "$P/gdcreate"
"$GODOT" --headless --path . -s res://tools/native_class_list.gd > "$OUT/native_classes_from_classdb.txt" 2>&1
case_run classdb_list_lists_the_native_classes 0 "NATIVE_CLASS CollisionQuery" cat "$OUT/native_classes_from_classdb.txt"
case_run classdb_fed_greps_on_the_real_tree_pass 0 "PASS no class_name under src/ or tests/ matches a native class name .*ClassDB" env NATIVE_CLASSES_FILE="$OUT/native_classes_from_classdb.txt" bash tools/core_greps.sh
mk_plant clash_classdb src/planted.gd "class_name GroundHit\nextends RefCounted\n"
case_run plant_class_name_clash_classdb_fed 1 "FAIL no class_name under src" env NATIVE_CLASSES_FILE="$OUT/native_classes_from_classdb.txt" bash tools/core_greps.sh "$P/clash_classdb"

echo "== exit-safety check that cannot run is NOT RUN, never PASS"
case_run exit_safety_missing_godot_is_not_run 1 "NOT RUN native_exit exit_clean" env GODOT=C:/no/such/godot.exe TIMEOUT=5 bash tools/native_exit_safety.sh "$OUT/exit_safety_missing"

echo "== integrity: everything damaged is back"
[ "$(sha "$SRC")" = "$SRC_SHA" ] && echo "PASS native_negative source_restored_identical" || { echo "FAIL native_negative source_restored_identical"; fails=$((fails + 1)); }
cp "$TMP/src.orig" "$SRC"
[ "$(sha "$DBG")" = "$DBG_SHA" ] && echo "PASS native_negative debug_dll_restored_identical" || { echo "FAIL native_negative debug_dll_restored_identical"; fails=$((fails + 1)); }
[ ! -e "$BIN/bench.lock" ] && echo "PASS native_negative no_bench_lock_left" || { echo "FAIL native_negative no_bench_lock_left"; fails=$((fails + 1)); }
case_run final_check_passes 0 "CHECK PASS" $BUILD --check
[ $fails = 0 ]
