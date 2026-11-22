#!/usr/bin/env bash
# Runs tools/bench_collision.gd RUNS times per layout, one Godot process at a time (the timings
# depend on it), and prints the median across runs of each run's median and p95 (whole block and per
# section). Observations only: it prints numbers, never a verdict.
#
# Usage: bash tools/bench_collision.sh OUTDIR LABEL [RUNS] [LAYOUT...]
#   OUTDIR  where each run's summary goes (LABEL-LAYOUT-N.txt) and LABEL-aggregate.txt
#   RUNS    default 3; LAYOUT default: castle worst
# GODOT overrides the binary (default C:/Godot/Godot_v4.8-beta3_win64_console.exe).
set -u
GODOT="${GODOT:-C:/Godot/Godot_v4.8-beta3_win64_console.exe}"
OUTDIR="${1:?outdir}"; LABEL="${2:?label}"; RUNS="${3:-3}"
shift 3 2>/dev/null || shift $#
LAYOUTS="${*:-castle worst}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$OUTDIR"
OUTABS="$(cd "$OUTDIR" && pwd)"
win() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
for layout in $LAYOUTS; do
	for n in $(seq 1 "$RUNS"); do
		out="$OUTABS/$LABEL-$layout-$n.txt"
		echo "== $LABEL $layout run $n"
		(cd "$ROOT" && "$GODOT" --headless --path . -s res://tools/bench_collision.gd -- \
			--layout="$layout" --out="$(win "$out")") > "$OUTABS/$LABEL-$layout-$n.log" 2>&1
		echo "   exit $?"
	done
done
agg="$OUTABS/$LABEL-aggregate.txt"
{
	echo "# $LABEL: median across $RUNS runs of each run's median_us and p95_us"
	for layout in $LAYOUTS; do
		cat "$OUTABS/$LABEL-$layout-"*.txt | grep -E '^(BENCH|SECTION) ' | awk -v L="$layout" '
			$2 == "layout=" L {
				split($3, s, "="); split($4, m, "="); split($5, p, "=")
				key = s[2]; if (!(key in seen)) { seen[key] = 1; order[++n] = key }
				meds[key] = meds[key] " " m[2]; p95s[key] = p95s[key] " " p[2]
			}
			function med(str,   a, k, i, j, t) {
				k = split(str, a, " ")
				for (i = 1; i <= k; i++) for (j = i + 1; j <= k; j++) if (a[j] + 0 < a[i] + 0) { t = a[i]; a[i] = a[j]; a[j] = t }
				return a[int((k + 1) / 2)]
			}
			END { for (i = 1; i <= n; i++) printf "AGG layout=%s section=%s median_of_medians_us=%s median_of_p95_us=%s runs_median=[%s ] runs_p95=[%s ]\n", L, order[i], med(meds[order[i]]), med(p95s[order[i]]), meds[order[i]], p95s[order[i]] }'
		grep -h '^ALLOC OBJECT_COUNT\|^VERDICT_INPUTS' "$OUTABS/$LABEL-$layout-"*.txt | sed "s/^/$layout: /"
	done
} > "$agg"
cat "$agg"
