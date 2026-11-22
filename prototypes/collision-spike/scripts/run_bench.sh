#!/usr/bin/env bash
# PROTOTYPE - NOT FOR PRODUCTION. Collision spike. Runs the Q3 matrix; log in out/bench_log.txt.
set -u
G=/c/Godot/Godot_v4.8-beta3_win64_console.exe
cd "$(dirname "$0")/.."
REPEATS=3
LOG=out/bench_log.txt
: > "$LOG"
run() { # $1 = face_index setting (true/false), rest = bench args
  local fi=$1; shift
  if [ "$fi" = true ]; then printf '[physics]\n\njolt_physics_3d/queries/enable_ray_cast_face_index=true\n' > override.cfg; else rm -f override.cfg; fi
  for r in $(seq 1 $REPEATS); do
    echo "### run $r faceidx=$fi $*" >> "$LOG"
    "$G" --headless --path . -s res://scripts/bench.gd -- "$@" >> "$LOG" 2>&1
  done
  rm -f override.cfg
}
for size in 50k 150k; do
  run true  backend=face  api=into size=$size
  run true  backend=face  api=dict size=$size
  run false backend=shape api=into size=$size
  run false backend=shape api=dict size=$size
  run true  backend=shape api=into size=$size
  for c in 1.0 2.0 4.0; do run false backend=grid cell=$c size=$size; done
done
