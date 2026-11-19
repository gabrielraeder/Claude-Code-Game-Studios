#!/usr/bin/env bash
# Summarizes a stress-test output dir: every [net-summary] line, then averages / worst
# values, whether all clients saw the same lead-change sequence, and any errors in the logs.
# Usage: tools/net_stress_summary.sh <dir>
DIR="${1:?usage: net_stress_summary.sh <dir>}"
cd "$DIR" || exit 2
echo "== [net-summary] lines =="
grep -h "^\[net-summary\]" *.log | sed 's/^\[net-summary\] //'
N=$(grep -h "^\[net-summary\]" *.log | wc -l)
echo
echo "processes with a summary: $N"
field() { # field <regex-with-one-group>
	grep -h "^\[net-summary\]" *.log | sed -nE "s#.*$1.*#\1#p"
}
avg() { awk '{s+=$1; n++} END {if (n) printf "%.3f", s/n; else print "n/a"}'; }
max() { awk 'BEGIN{m=-1} {if ($1>m) m=$1} END {if (m>=0) printf "%.3f", m; else print "n/a"}'; }
echo "extrap %      avg $(field 'extrap=([0-9.]+)%' | avg)   max $(field 'extrap=([0-9.]+)%' | max)"
echo "pred_err avg  avg $(field 'pred_err avg=([0-9.]+)m' | avg) m   max-of-avgs $(field 'pred_err avg=([0-9.]+)m' | max) m"
echo "pred_err max  worst $(field 'max=([0-9.]+)m \|' | max) m"
echo "rtt avg (ms)  avg $(field 'rtt_avg=([0-9]+)ms' | avg)   rtt max worst $(field 'rtt_max=([0-9]+)ms' | max)"
echo "view delay ms avg $(field 'view_delay=([0-9]+)ms' | avg)   max $(field 'view_delay=([0-9]+)ms' | max)"
echo "snaps/s       avg $(field 'snaps/s=([0-9.]+)' | avg)"
echo "kb_out/s      host $(grep -h 'role=host' *.log | sed -nE 's/.*kb_out\/s=([0-9.]+).*/\1/p')   client avg $(grep -h 'role=client' *.log | sed -nE 's/.*kb_out\/s=([0-9.]+).*/\1/p' | avg)"
echo "kb_in/s       host $(grep -h 'role=host' *.log | sed -nE 's/.*kb_in\/s=([0-9.]+).*/\1/p')   client avg $(grep -h 'role=client' *.log | sed -nE 's/.*kb_in\/s=([0-9.]+).*/\1/p' | avg)"
echo
echo "== lead-change agreement =="
grep -h "^\[net-summary\]" *.log | sed -nE 's/.*lead_changes=([0-9]+) lead_seq=([^ ]+).*/\1 \2/p' | sort | uniq -c
echo "(distinct 'lead_changes lead_seq' values above; one line = all processes agree)"
echo
echo "== finished places =="
grep -h "^\[net-summary\]" *.log | sed -nE 's/.*place=([0-9]+) finish=([0-9.-]+).*/\1 \2/p' | sort -n | tr '\n' ';'
echo
echo
echo "== errors / warnings in logs =="
grep -iHn "ERROR\|SCRIPT ERROR\|Parse Error\|WARNING" *.log | head -20
echo "(count: $(grep -ic "ERROR" *.log | awk -F: '{s+=$2} END {print s+0}'))"
