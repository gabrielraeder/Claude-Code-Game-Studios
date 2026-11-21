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
##   --track=ID           track to race on (castle_circuit, dungeon_depths, test_loop); the host's choice online
##   --shortcut=ID        the autopilot takes a branch: drawbridge, secret_passage, hall_left,
##                        hall_right, mine_rail, lava_gap
##   --overview-shot      one top-down picture of the whole track into --shots=, then quit
##   --side-shot=S        one picture from the side of the road at main-loop distance S (elevation check), then quit
##   --side-dist=M        that camera's distance from the road (default 40; negative = the other side)
##   --side-lift=M        that camera's height above the road (default 3; higher looks down on it)
##   --grid-shot          fixed camera above the start grid (picture during the countdown)
##   --shot-s=A,B,C       pictures when the kart first passes these main-loop distances
##   --racer=N            the local kart's dog, 0..7 (default 0, the mascot); works for host and clients
##   --vehicle=cart|bike  the local kart's vehicle (also 0/1); works for host and clients
##   --lineup=DIR         build a line-up of all 8 dogs on both vehicles, save pictures into DIR, quit
##   --ui-shot=NAME      photograph a menu screen with sample data into --shots=, then quit
##   --auto-ui=host|join:ADDR  click through menu and lobby by script (--auto-pick=R,V --auto-track= --auto-bots= --auto-laps= --auto-races=)
##   --dunk-at=S          the autopilot steers off the first open edge once from distance S
##                        (pictures of the sinking or falling kart and of its respawn)
##   --height-log=PATH    CSV of the local kart's height against the surface every tick, plus
##                        [air] lines for takeoffs, landings, tricks and falls (story 008)
##                        (--height-log=every-tick instead: a [height] line per kart per tick online)
##   --no-trick           the autopilot does not hop before ramp lips (no trick boosts)

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
## Camera pitch below the horizon (degrees) of that picture: 90 = straight down; less shows the
## track's height from an angle (--overview-tilt=DEG, story 008 part 4).
var overview_tilt: float = 90.0
## Main-loop distance of a side-on picture of the road and its supports (--side-shot=S, needs --shots=), -1 = off.
var side_shot: float = -1.0
## Side picture camera: meters to the road's normal side (negative = other side) and above the road
## (--side-dist=, --side-lift=; story 008 part 5, the Barbican Spiral pictures).
var side_dist: float = 40.0
var side_lift: float = 3.0
## Fixed camera above the start grid, one picture during the countdown (--grid-shot).
var grid_shot: bool = false
## Main-loop distances where a picture is saved on the first lap (--shot-s=a,b,c).
var shot_s: PackedFloat32Array = PackedFloat32Array()
## Main-loop distance where the autopilot drives into the moat once (--dunk-at=), -1 = off.
var dunk_s: float = -1.0
## Per-tick height CSV of the local kart (--height-log=PATH), "" = off.
var height_log: String = ""
## The autopilot never hops before a ramp lip (--no-trick).
var no_trick: bool = false
## Racer index from --racer= (-1 = not given, the mascot).
var racer: int = -1
## Vehicle token from --vehicle= ("" = not given, the cart): an id or an index.
var vehicle: String = ""
## Folder for the line-up pictures (--lineup=), "" = off.
var lineup_dir: String = ""
## Menu screen to photograph with sample data, then quit (--ui-shot=menu|lobby|lobby-client|results|results-client|results-solo|pause; needs --shots=).
var ui_shot: String = ""
## Scripted menu presses (--auto-ui=host or --auto-ui=join:ADDRESS): opens the main menu and clicks through it.
var auto_ui: String = ""
## Racer,vehicle indices the scripted lobby picks by pressing the cycle rows (--auto-pick=3,1), "" = keep.
var auto_pick: String = ""
## Track id, bot count and laps the scripted host sets in the lobby (--auto-track= --auto-bots= --auto-laps=).
var auto_track: String = ""
var auto_bots: int = -1
var auto_laps: int = 0
## Races the scripted flow plays (the first and rematches) before it quits (--auto-races=, default 2).
var auto_races: int = 2
## Item the local kart starts with and keeps getting refilled with (--give-item=horn|stone|spill|falcon|shield).
var give_item: String = ""
## Seconds between automatic item uses by the autopilot (--item-interval=), 0 = off.
var item_interval: float = 0.0
## Controls file to load and save instead of user://controls.cfg (--controls-file=PATH; tests
## and screenshots use it so they never touch the player's own bindings).
var controls_file: String = ""


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
		elif a.begins_with("--overview-tilt="):
			o.overview_tilt = clampf(a.substr("--overview-tilt=".length()).to_float(), 10.0, 90.0)
		elif a.begins_with("--side-shot="):
			o.side_shot = a.substr("--side-shot=".length()).to_float()
		elif a.begins_with("--side-dist="):
			o.side_dist = a.substr("--side-dist=".length()).to_float()
		elif a.begins_with("--side-lift="):
			o.side_lift = a.substr("--side-lift=".length()).to_float()
		elif a == "--grid-shot":
			o.grid_shot = true
		elif a.begins_with("--shot-s="):
			for part in a.substr("--shot-s=".length()).split(","):
				o.shot_s.append(part.to_float())
		elif a.begins_with("--height-log="):
			o.height_log = a.substr("--height-log=".length())
		elif a == "--no-trick":
			o.no_trick = true
		elif a.begins_with("--dunk-at="):
			o.dunk_s = a.substr("--dunk-at=".length()).to_float()
		elif a.begins_with("--give-item="):
			o.give_item = a.substr("--give-item=".length())
		elif a.begins_with("--item-interval="):
			o.item_interval = a.substr("--item-interval=".length()).to_float()
		elif a.begins_with("--racer="):
			var racer_text: String = a.substr("--racer=".length())
			if racer_text.is_valid_int():
				o.racer = racer_text.to_int()
			else:
				push_warning("--racer=%s is not a number; using the mascot." % racer_text)
		elif a.begins_with("--vehicle="):
			o.vehicle = a.substr("--vehicle=".length())
		elif a.begins_with("--lineup="):
			o.lineup_dir = a.substr("--lineup=".length())
		elif a.begins_with("--ui-shot="):
			o.ui_shot = a.substr("--ui-shot=".length())
		elif a.begins_with("--auto-ui="):
			o.auto_ui = a.substr("--auto-ui=".length())
		elif a.begins_with("--auto-pick="):
			o.auto_pick = a.substr("--auto-pick=".length())
		elif a.begins_with("--auto-track="):
			o.auto_track = a.substr("--auto-track=".length())
		elif a.begins_with("--auto-bots="):
			o.auto_bots = a.substr("--auto-bots=".length()).to_int()
		elif a.begins_with("--auto-laps="):
			o.auto_laps = a.substr("--auto-laps=".length()).to_int()
		elif a.begins_with("--controls-file="):
			o.controls_file = a.substr("--controls-file=".length())
		elif a.begins_with("--auto-races="):
			o.auto_races = a.substr("--auto-races=".length()).to_int()
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
	return shots_dir != "" or quit_after_race or quit_after_seconds > 0.0 or log_path != "" or verbose 			or height_log != ""
