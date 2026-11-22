#!/usr/bin/env bash
# PROTOTYPE - NOT FOR PRODUCTION. Runs every measurement, one Godot process at a time. No compiling meanwhile.
cd "$(dirname "$0")"
OUT=out/bench_results.txt
: > $OUT  # READ_WRITE in bench.gd appends
for part in mover static; do
  for r in 1 2 3; do ./run.sh debug --part=$part --mode=gd --ticks=600 --out=$OUT > /dev/null 2>&1; done
  for fl in debug release; do
    for mode in cpp_call cpp_batch; do
      for r in 1 2 3; do ./run.sh $fl --part=$part --mode=$mode --ticks=600 --out=$OUT > /dev/null 2>&1; done
    done
  done
done
echo DONE >> $OUT
