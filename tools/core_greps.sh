#!/usr/bin/env bash
# Boundary greps of the core rebuild (core-rebuild story 006; later stories append rules here).
# Prints one "PASS <rule>" or "FAIL <rule> (...)" line per rule, followed by the matching lines (or
# the grep error) of each failing rule. Observations per rule, not a verdict on any story.
# Exit 0 when every rule passes, 1 when any rule fails, 2 on bad usage.
#
# Usage: tools/core_greps.sh [root]
#   root: the tree to scan (default: the repo root). A scratch tree is used to watch a rule fail.
# Comment lines (first non-blank character '#', so '##' doc comments too) are not matched. A code
# line with a trailing "# ..." comment that names a forbidden form IS matched: a false FAIL, accepted
# because it fails safe (move the mention to its own comment line).
# A grep error (bad regex, unreadable file: grep exit >= 2) is a FAIL with the error, never a PASS.
set -u
ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
if [ ! -d "$ROOT" ]; then echo "root not found: $ROOT" >&2; exit 2; fi
# Grep relative paths from inside the root, so a drive letter (C:/...) never adds a colon before
# the "file:line:" prefix the comment filter reads.
cd "$ROOT" || exit 2
fails=0

# rule_absent NAME REGEX SKIP DIR... : PASS when no non-comment line of a .gd file under the DIRs
# that exist matches the extended REGEX. SKIP is an extended regex of file paths (relative to the
# root) whose matches are allowed, or "" for none. Names the scanned and the missing dirs.
rule_absent() {
	local name="$1" regex="$2" skip="$3"
	shift 3
	local dirs=() scanned="" missing="" d
	for d in "$@"; do
		if [ -d "$d" ]; then dirs+=("$d"); scanned="$scanned $d"; else missing="$missing $d"; fi
	done
	if [ ${#dirs[@]} = 0 ]; then
		echo "FAIL $name (none of the dirs exist:$missing)"
		fails=$((fails + 1))
		return
	fi
	local note="scanned:$scanned"
	[ -n "$missing" ] && note="$note; absent:$missing"
	[ -n "$skip" ] && note="$note; allowed in: $skip"
	local raw rc
	raw=$(grep -rnE --include='*.gd' "$regex" "${dirs[@]}" 2>&1); rc=$?
	if [ $rc -ge 2 ]; then
		echo "FAIL $name (grep error, exit $rc; $note)"
		printf '%s\n' "$raw" | sed 's/^/  /'
		fails=$((fails + 1))
		return
	fi
	local hits
	hits=$(printf '%s\n' "$raw" | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' | grep -v '^$')
	if [ -n "$skip" ] && [ -n "$hits" ]; then
		hits=$(printf '%s\n' "$hits" | grep -vE "^($skip):[0-9]+:")
	fi
	if [ -z "$hits" ]; then
		echo "PASS $name ($note)"
	else
		echo "FAIL $name ($(printf '%s\n' "$hits" | wc -l | tr -d ' ') lines; $note)"
		printf '%s\n' "$hits" | sed 's/^/  /'
		fails=$((fails + 1))
	fi
}

# ADR-0002 Validation Criteria / Implementation Guidelines: per-tick collision code uses the 4.8
# `_into` methods; the Dictionary / allocating query forms and the parameter create() helpers are
# forbidden under src/core/ and src/gameplay/ (allowed in tools/).
rule_absent "no Dictionary query forms in src/core src/gameplay (ADR-0002)" \
	'\b(intersect_ray|intersect_point|intersect_shape|cast_motion|get_rest_info|collide_shape)[[:space:]]*\(|Physics(Ray|Point)QueryParameters3D\.create[[:space:]]*\(' \
	"" src/core src/gameplay

# Story 006 LP review: every CollisionQuery is built through CollisionBootCheck.checked_query(),
# which runs the load check and disposes a query that fails it, so no unchecked query exists.
# Tests and tools are outside src/ and may build queries directly.
rule_absent "CollisionQuery.new( / .create( only in CollisionBootCheck under src (story 006, 067)" \
	'\bCollisionQuery\.(new|create)[[:space:]]*\(' \
	"src/core/collision/collision_boot_check\.gd" src

# Story 066 (ADR-0007 section 7, "The editor-panel gap is closed"): a gdUnit4 suite under tests/unit/
# that names a native class (the GDREGISTER_*CLASS list of native/src/register_types.cpp) must preload the
# shared source-hash helper, tests/unit/native/native_test_guard.gd, and call its problem() inside before(),
# so a suite started from the editor panel refuses a stale DLL. The helper itself is exempt. A rule that
# cannot read the class list, or finds no suite to check, FAILS (it checked nothing).
native_rule="native suites call the shared hash helper"
if [ ! -f native/src/register_types.cpp ]; then
	echo "FAIL $native_rule (native/src/register_types.cpp is missing, so the class list cannot be read)"
	fails=$((fails + 1))
else
	native_classes=$(grep -ohE 'GDREGISTER[A-Z_]*CLASS\([A-Za-z0-9_]+\)' native/src/register_types.cpp | sed -E 's/.*\(([A-Za-z0-9_]+)\)/\1/' | paste -sd'|' -)
	if [ -z "$native_classes" ]; then
		echo "FAIL $native_rule (no GDREGISTER_*CLASS in native/src/register_types.cpp: the class list is empty)"
		fails=$((fails + 1))
	else
		suites=$(grep -rlE --include='*.gd' "\b($native_classes)\b" tests/unit 2>/dev/null | grep -v '/native_test_guard\.gd$')
		if [ -z "$suites" ]; then
			echo "FAIL $native_rule (NOT RUN: no suite under tests/unit names a native class, so the rule checked nothing; classes: $native_classes)"
			fails=$((fails + 1))
		else
			missing=""
			for f in $suites; do
				ok_preload=0; ok_call=0
				grep -vE '^[[:space:]]*#' "$f" | grep -qF 'preload("res://tests/unit/native/native_test_guard.gd")' && ok_preload=1
				awk '/^func before\(/ { inb = 1; next } /^func / { inb = 0 } inb && $0 !~ /^[[:space:]]*#/ && /\.problem\(/ { found = 1 } END { exit(found ? 0 : 1) }' "$f" && ok_call=1
				[ $ok_preload = 1 ] && [ $ok_call = 1 ] || missing="$missing $f"
			done
			if [ -z "$missing" ]; then
				echo "PASS $native_rule ($(printf '%s\n' "$suites" | grep -c .) suite(s); classes: $native_classes)"
			else
				echo "FAIL $native_rule (a suite names a native class and does not preload native_test_guard.gd and call .problem( inside before())"
				for f in $missing; do echo "  $f"; done
				fails=$((fails + 1))
			fi
		fi
	fi
fi

# Story 066: the deliberate native crash is for tools/crash_repro.sh runs only; no test may call it.
rule_absent "ToolchainProbe.crash_for_test is not called from tests (story 066)" 'crash_for_test' "" tests

# Story 008 (ADR-0004 section 15; ADR-0001 section 9 as amended 2026-11-22): tools may run or read the
# frozen game, but nothing under src/ outside src/legacy/ may load the legacy tools, their output or
# src/legacy/. Two checks over every .gd, .tscn and .tres under src/ outside src/legacy/:
#  - paths: res://src/legacy/, the three story-008 tools and build/legacy_tracks (strings included,
#    since load() takes a string; .gd comment lines skipped);
#  - class names declared under src/legacy/ (class_name lines), in .gd code with comment lines and
#    "..." string literals removed (so a display string such as "Racer" does not count).
legacy_rule="nothing under src/ outside src/legacy/ loads the legacy tools, their output or src/legacy/ (story 008)"
if [ ! -d src/legacy ]; then
	echo "PASS $legacy_rule (src/legacy/ is gone: nothing left to load)"
else
	legacy_paths='src/legacy/|legacy_track_export|legacy_test_bake|spline_mesh_equivalence|legacy_tracks'
	raw=$(grep -rnE --include='*.gd' --include='*.tscn' --include='*.tres' "$legacy_paths" src 2>&1); rc=$?
	hits=""
	if [ $rc -ge 2 ]; then
		hits="grep error (exit $rc): $raw"
	else
		hits=$(printf '%s\n' "$raw" | grep -v '^src/legacy/' | grep -vE '^[^:]+\.gd:[0-9]+:[[:space:]]*#' | grep -v '^$')
	fi
	legacy_classes=$(grep -rhoE '^class_name[[:space:]]+[A-Za-z0-9_]+' src/legacy --include='*.gd' | awk '{print $2}' | sort -u | paste -sd'|' -)
	if [ -z "$legacy_classes" ]; then
		hits="$hits
class list empty: no class_name under src/legacy/ could be read"
	else
		class_hits=$(find src -name '*.gd' -not -path 'src/legacy/*' -print0 | xargs -0 awk -v re="(^|[^A-Za-z0-9_])($legacy_classes)([^A-Za-z0-9_]|\$)" '
			/^[[:space:]]*#/ { next }
			{ line = $0; gsub(/"([^"\\]|\\.)*"/, "\"\"", line); sub(/#.*$/, "", line); if (line ~ re) print FILENAME ":" FNR ": " $0 }')
		[ -n "$class_hits" ] && hits="$hits
$class_hits"
	fi
	hits=$(printf '%s\n' "$hits" | grep -v '^$')
	if [ -z "$hits" ]; then
		echo "PASS $legacy_rule (scanned: src outside src/legacy; $(printf '%s' "$legacy_classes" | tr '|' '\n' | grep -c .) legacy class names)"
	else
		echo "FAIL $legacy_rule ($(printf '%s\n' "$hits" | wc -l | tr -d ' ') lines)"
		printf '%s\n' "$hits" | sed 's/^/  /'
		fails=$((fails + 1))
	fi
fi

# ---------------------------------------------------------------------------------------------------
# Story 067 (ADR-0007 Migration Plan step 2, Implementation Guidelines, section 5): rules over native/ and
# the oracle move. native_scan NAME REGEX SKIPFILES : PASS when no non-comment line of a .cpp/.h under
# native/src matches the extended REGEX (files matching SKIPFILES, an extended regex of paths, are allowed).
native_scan() {
	local name="$1" regex="$2" skip="$3" raw rc hits
	if [ ! -d native/src ]; then echo "FAIL $name (native/src is missing)"; fails=$((fails + 1)); return; fi
	raw=$(grep -rnE --include='*.cpp' --include='*.h' "$regex" native/src 2>&1); rc=$?
	if [ $rc -ge 2 ]; then echo "FAIL $name (grep error, exit $rc)"; printf '%s\n' "$raw" | sed 's/^/  /'; fails=$((fails + 1)); return; fi
	hits=$(printf '%s\n' "$raw" | grep -vE '^[^:]+:[0-9]+:[[:space:]]*(//|/\*|\*)' | grep -v '^$')
	if [ -n "$skip" ] && [ -n "$hits" ]; then hits=$(printf '%s\n' "$hits" | grep -vE "^($skip):[0-9]+:"); fi
	if [ -z "$hits" ]; then echo "PASS $name (scanned: native/src)"; else
		echo "FAIL $name ($(printf '%s\n' "$hits" | wc -l | tr -d ' ') lines)"; printf '%s\n' "$hits" | sed 's/^/  /'; fails=$((fails + 1)); fi
}

native_scan "no Dictionary query forms in native/ (ADR-0002, story 067)" \
	'(intersect_ray|intersect_point|intersect_shape|cast_motion|get_rest_info|collide_shape)[[:space:]]*\(|Physics(Ray|Point|Shape)QueryParameters3D::create' ""

native_scan "CollisionQuery is constructed only in collision_query.cpp (story 067)" \
	'Ref<CollisionQuery>[^;]*instantiate|memnew[[:space:]]*\(CollisionQuery|CollisionQuery::create[[:space:]]*\(' \
	"native/src/collision/collision_query\.(cpp|h)"

# Per-tick regions: the code between "// PER_TICK_BEGIN" and "// PER_TICK_END" in a native .cpp is the per-tick
# path. No allocation (new / memnew / String / Variant / Dictionary / Array / container growth), no *_create(
# call (server RIDs, parameter objects) and no unordered container or random source (ADR-0007 section 4).
# The regex uses POSIX bracket expressions only (no GNU \y), so any POSIX awk reads it the same; an awk error
# FAILS the rule (never a silent PASS). A rule that finds no region FAILS (it checked nothing).
# ALLOW-LIST (named exceptions, none flagged because they sit outside the regions): report_cap_error, called
# once per query when the Newton cap fails closed (it builds one message; documented at its call site).
# The rule also scans for the tokens: instantiate(, .assign(, .insert(, std::vector, std::make_*, ERR_PRINT,
# print_line and UtilityFunctions::print; tools/native_negative_checks.sh plants one of each.
tick_rule="no allocation, *_create( or String/Variant/Dictionary in native per-tick regions (story 067)"
tick_words='memnew|new|String|StringName|Variant|Dictionary|Array|TypedArray|instantiate|ERR_PRINT|print_line|vformat'
tick_regex='_create[[:space:]]*\(|(^|[^A-Za-z0-9_])('"$tick_words"')([^A-Za-z0-9_]|$)|push_back|emplace_back|\.assign[[:space:]]*\(|\.insert[[:space:]]*\(|\.resize[[:space:]]*\(|\.reserve[[:space:]]*\(|std::(vector|string|map|set|unordered_[a-z]+|function|random_device|make_[a-z_]+)|(^|[^A-Za-z0-9_])rand[[:space:]]*\(|<random>|UtilityFunctions::print'
if [ ! -d native/src ]; then
	echo "FAIL $tick_rule (native/src is missing)"; fails=$((fails + 1))
else
	regions=$(grep -rlE --include='*.cpp' '^// PER_TICK_BEGIN' native/src 2>/dev/null | wc -l | tr -d ' ')
	if [ "$regions" = 0 ]; then
		echo "FAIL $tick_rule (NOT RUN: no // PER_TICK_BEGIN region under native/src, so nothing was checked)"; fails=$((fails + 1))
	else
		tick_files=$(find native/src -name '*.cpp')
		hits=$(TICK_RE="$tick_regex" awk '
			/^\/\/ PER_TICK_BEGIN/ { inr = 1; next }
			/^\/\/ PER_TICK_END/ { inr = 0; next }
			inr && $0 !~ /^[[:space:]]*(\/\/|\/\*|\*)/ { line = $0; sub(/\/\/.*$/, "", line); gsub(/"([^"\\]|\\.)*"/, "\"\"", line); if (line ~ ENVIRON["TICK_RE"]) print FILENAME ":" FNR ": " $0 }' $tick_files 2>&1); tick_rc=$?
		if [ $tick_rc != 0 ]; then hits="awk failed (exit $tick_rc): $hits"; fi
		if [ -z "$hits" ]; then echo "PASS $tick_rule ($regions file(s) with a region)"; else
			echo "FAIL $tick_rule ($(printf '%s\n' "$hits" | wc -l | tr -d ' ') lines)"; printf '%s\n' "$hits" | sed 's/^/  /'; fails=$((fails + 1)); fi
	fi
fi

# The AC-15 scan, moved here from collision_movers_test.gd: mover key arrays are read only by the collision
# code (src/core/collision for GDScript, native/src/collision for C++).
key_rule="mover keys (key_pos) are read only inside the collision code (story 067)"
if [ -d src ] && [ -d native/src ]; then
	hits=$( { grep -rnE --include='*.gd' '\bkey_pos\b' src 2>/dev/null | grep -vE '^src/core/collision/|^src/legacy/'; grep -rnE --include='*.cpp' --include='*.h' '\bkey_pos\b' native/src 2>/dev/null | grep -vE '^native/src/collision/'; } | grep -vE '^[^:]+:[0-9]+:[[:space:]]*(#|//)' )
	if [ -z "$hits" ]; then echo "PASS $key_rule"; else echo "FAIL $key_rule"; printf '%s\n' "$hits" | sed 's/^/  /'; fails=$((fails + 1)); fi
else
	echo "FAIL $key_rule (src or native/src is missing)"; fails=$((fails + 1))
fi

# No class_name under src/ or tests/ matches a native class name ("hides a native class"). The class list comes
# from ClassDB in a headless run: NATIVE_CLASSES_FILE is the output of `godot --headless -s res://tools/native_class_list.gd`
# (lines "NATIVE_CLASS <name>"); when unset, the GDREGISTER list of native/src/register_types.cpp stands in.
clash_rule="no class_name under src/ or tests/ matches a native class name (story 067)"
if [ -n "${NATIVE_CLASSES_FILE:-}" ]; then
	native_names=$(grep -h '^NATIVE_CLASS ' "$NATIVE_CLASSES_FILE" 2>/dev/null | awk '{print $2}' | paste -sd'|' -)
	clash_src="ClassDB ($NATIVE_CLASSES_FILE)"
else
	native_names=$(grep -ohE 'GDREGISTER[A-Z_]*CLASS\([A-Za-z0-9_]+\)' native/src/register_types.cpp 2>/dev/null | sed -E 's/.*\(([A-Za-z0-9_]+)\)/\1/' | paste -sd'|' -)
	clash_src="register_types.cpp"
fi
if [ -z "$native_names" ]; then
	echo "FAIL $clash_rule (NOT RUN: the native class list is empty; source: $clash_src)"; fails=$((fails + 1))
else
	hits=$(grep -rnE --include='*.gd' "^class_name[[:space:]]+($native_names)([^A-Za-z0-9_]|\$)" src tests 2>/dev/null)
	if [ -z "$hits" ]; then echo "PASS $clash_rule (class list from $clash_src: $(printf '%s' "$native_names" | tr '|' '\n' | grep -c .) names)"; else
		echo "FAIL $clash_rule"; printf '%s\n' "$hits" | sed 's/^/  /'; fails=$((fails + 1)); fi
fi

if [ $fails != 0 ]; then exit 1; fi
exit 0
