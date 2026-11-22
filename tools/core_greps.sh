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
rule_absent "CollisionQuery.new( only in CollisionBootCheck under src (story 006)" \
	'\bCollisionQuery\.new[[:space:]]*\(' \
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

if [ $fails != 0 ]; then exit 1; fi
exit 0
