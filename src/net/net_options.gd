class_name NetOptions
extends RefCounted
## Command-line switches for online play, read from the user args after "--".
##   --host              host a race on the configured port
##   --join=IP[:PORT]    join a host (a Tailscale 100.x address works)
##   --players=N         humans (host included) the host waits for before starting (default 2)
##   --bots=N            bots the host adds (default: NetConfig.default_bots)
##   --laps=N            laps for the race (also used offline)
##   --lag=MS --jitter=MS --loss=PCT   fake network (loss hits position updates only)
##   --netlog=PATH       per-second net log CSV

var host: bool = false
var join: String = ""
var players: int = 2
var bots: int = -1
var laps: int = 0
var lag_ms: float = 0.0
var jitter_ms: float = 0.0
var loss_pct: float = 0.0
var netlog_path: String = ""


## Parses [param args] (normally OS.get_cmdline_user_args()).
static func parse(args: PackedStringArray) -> NetOptions:
	var o := NetOptions.new()
	for a in args:
		if a == "--host":
			o.host = true
		elif a.begins_with("--join="):
			o.join = a.substr("--join=".length())
		elif a.begins_with("--players="):
			o.players = a.substr("--players=".length()).to_int()
		elif a.begins_with("--bots="):
			o.bots = a.substr("--bots=".length()).to_int()
		elif a.begins_with("--laps="):
			o.laps = a.substr("--laps=".length()).to_int()
		elif a.begins_with("--lag="):
			o.lag_ms = a.substr("--lag=".length()).to_float()
		elif a.begins_with("--jitter="):
			o.jitter_ms = a.substr("--jitter=".length()).to_float()
		elif a.begins_with("--loss="):
			o.loss_pct = a.substr("--loss=".length()).to_float()
		elif a.begins_with("--netlog="):
			o.netlog_path = a.substr("--netlog=".length())
	return o
