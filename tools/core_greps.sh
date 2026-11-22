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

if [ $fails != 0 ]; then exit 1; fi
exit 0
