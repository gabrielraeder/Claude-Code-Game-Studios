#!/usr/bin/env bash
# PROTOTYPE - NOT FOR PRODUCTION
# usage: run.sh <debug|release> <script args...>   e.g. run.sh release --part=mover --mode=gd
# Points native_spike.gdextension's windows.debug entry at the chosen dll (the editor binary is a
# debug build, so it only ever reads the "debug" entry), then runs ONE headless Godot process.
set -u
cd "$(dirname "$0")"
FLAVOR="$1"; shift
cat > native_spike.gdextension <<EOT
; PROTOTYPE - NOT FOR PRODUCTION
[configuration]
entry_symbol = "native_spike_init"
compatibility_minimum = "4.8"
reloadable = true

[libraries]
windows.debug.x86_64 = "res://bin/native_spike.windows.template_${FLAVOR}.x86_64.dll"
windows.release.x86_64 = "res://bin/native_spike.windows.template_release.x86_64.dll"
EOT
"C:/Godot/Godot_v4.8-beta3_win64_console.exe" --headless --path . -s res://scripts/bench.gd -- --build=$FLAVOR "$@"
