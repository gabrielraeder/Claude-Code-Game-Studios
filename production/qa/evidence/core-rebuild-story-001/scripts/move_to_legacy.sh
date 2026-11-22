#!/usr/bin/env bash
# Story core-rebuild-001, move commit (ADR-0001 section 9 step 1): git mv only, no content edits.
# Every tracked file under src/ (scripts with their .uid sidecars, scenes, resources, the shader)
# goes to src/legacy/<same path>, except the shared data class scripts, which go to src/data/<name>.
# src/CLAUDE.md and src/.gitkeep stay. Writes the old -> new map to move_map.tsv beside this script.
# Usage: bash move_to_legacy.sh   (from anywhere; works on the repo root)
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
cd "$ROOT"
# ADR-0001 section 9: the shared data class scripts (VehicleStats, VehicleVisualStats, SurfaceSet,
# SurfaceType, ItemDef, ItemSet, RacerDef, RacerSet, BotPersonality, NetConfig, AudioEventDef,
# AudioSet, UiTheme, HitSlowdownProfile, PennantStyle).
DATA="vehicle/vehicle_stats.gd vehicle/vehicle_visual_stats.gd track/surface_set.gd track/surface_type.gd
items/item_def.gd items/item_set.gd vehicle/racer_def.gd vehicle/racer_set.gd ai/bot_personality.gd
net/net_config.gd audio/audio_event_def.gd audio/audio_set.gd ui/ui_theme.gd
vehicle/hit_slowdown_profile.gd vehicle/pennant_style.gd"
MAP="$HERE/move_map.tsv"
: > "$MAP"
git ls-files src | while read -r f; do
	rel="${f#src/}"
	case "$rel" in CLAUDE.md|.gitkeep) continue ;; esac
	base="${rel%.uid}"
	dest="src/legacy/$rel"
	for d in $DATA; do
		if [ "$base" = "$d" ]; then dest="src/data/$(basename "$rel")"; fi
	done
	mkdir -p "$(dirname "$dest")"
	git mv "$f" "$dest"
	printf '%s\t%s\n' "$f" "$dest" >> "$MAP"
done
echo "moved $(wc -l < "$MAP") files; map: $MAP"
