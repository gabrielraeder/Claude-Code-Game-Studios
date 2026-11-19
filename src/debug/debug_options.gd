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

var autopilot: bool = false
var shots_dir: String = ""
var quit_after_race: bool = false
var quit_after_seconds: float = 0.0
var log_path: String = ""
var time_scale: float = 0.0
var verbose: bool = false
var park: bool = false
var ram: bool = false


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
