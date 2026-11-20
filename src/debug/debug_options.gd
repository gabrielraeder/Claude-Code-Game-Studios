class_name DebugOptions
extends RefCounted
## Command-line debug switches, read from the user args after "--". Debug aid only.
##   --autopilot          a script drives the kart (no menu, no human input)
##   --shots=DIR          save viewport PNGs into DIR during the run (skipped headless)
##   --quit-after-race    quit when the laps are done
##   --quit-after=SECONDS quit after this many real seconds
##   --log=PATH           write a small CSV (lap times, boosts per tier, max speed)
##   --park               the local kart never moves (a bump target)
##   --ram                the local kart drives into the nearest other kart (bump test)
##   --track=ID           track to race on (castle_circuit, test_loop); the host's choice online
##   --shortcut=ID        the autopilot takes drawbridge or secret_passage
##   --overview-shot      one top-down picture of the whole track into --shots=, then quit
##   --grid-shot          fixed camera above the start grid (picture during the countdown)
##   --shot-s=A,B,C       pictures when the kart first passes these main-loop distances
##   --dunk-at=S          the autopilot steers off the open moat edge once from distance S
##                        (pictures of the sinking kart and of its respawn)

var autopilot: bool = false
var shots_dir: String = ""
var quit_after_race: bool = false
var quit_after_seconds: float = 0.0
var log_path: String = ""
var time_scale: float = 0.0
var verbose: bool = false
var park: bool = false
var ram: bool = false
## Track id from --track= ("" = the default, castle_circuit).
var track_id: String = ""
## Shortcut the autopilot takes (--shortcut=drawbridge|secret_passage), "" = main line.
var shortcut: String = ""
## Save one top-down picture of the whole track and quit (--overview-shot, needs --shots=).
var overview_shot: bool = false
## Fixed camera above the start grid, one picture during the countdown (--grid-shot).
var grid_shot: bool = false
## Main-loop distances where a picture is saved on the first lap (--shot-s=a,b,c).
var shot_s: PackedFloat32Array = PackedFloat32Array()
## Main-loop distance where the autopilot drives into the moat once (--dunk-at=), -1 = off.
var dunk_s: float = -1.0


## Parses [param args] (normally OS.get_cmdline_user_args()).
static func parse(args: PackedStringArray) -> DebugOptions:
	var o := DebugOptions.new()
	for a in args:
		if a == "--autopilot":
			o.autopilot = true
		elif a == "--quit-after-race":
			o.quit_after_race = true
		elif a.begins_with("--shots="):
			o.shots_dir = a.substr("--shots=".length())
		elif a.begins_with("--log="):
			o.log_path = a.substr("--log=".length())
		elif a.begins_with("--track="):
			o.track_id = a.substr("--track=".length())
		elif a.begins_with("--shortcut="):
			o.shortcut = a.substr("--shortcut=".length())
		elif a == "--overview-shot":
			o.overview_shot = true
		elif a == "--grid-shot":
			o.grid_shot = true
		elif a.begins_with("--shot-s="):
			for part in a.substr("--shot-s=".length()).split(","):
				o.shot_s.append(part.to_float())
		elif a.begins_with("--dunk-at="):
			o.dunk_s = a.substr("--dunk-at=".length()).to_float()
		elif a == "--park":
			o.park = true
		elif a == "--ram":
			o.ram = true
		elif a == "--verbose":
			o.verbose = true
		elif a.begins_with("--time-scale="):
			o.time_scale = a.substr("--time-scale=".length()).to_float()
		elif a.begins_with("--quit-after="):
			o.quit_after_seconds = a.substr("--quit-after=".length()).to_float()
	return o


## True when any option that needs a DebugHarness node is set.
func needs_harness() -> bool:
	return shots_dir != "" or quit_after_race or quit_after_seconds > 0.0 or log_path != "" or verbose
