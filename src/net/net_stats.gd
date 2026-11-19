class_name NetStats
extends RefCounted
## Network quality numbers: adaptive view delay, round-trip time, snapshot counts,
## extrapolated frames and prediction error. Keeps a one-second window (for the net log)
## and race totals (for the [net-summary] line). Pure data, no nodes.

## Seconds remote karts are drawn behind the newest data (lateness + 2*deviation + one send interval).
var view_delay: float = 0.1
var late_avg: float = 0.0
var late_dev: float = 0.0
## Smoothed and worst round-trip time, seconds.
var rtt: float = 0.0
var rtt_max: float = 0.0
var rtt_sum: float = 0.0
var rtt_n: int = 0
var race_seconds: int = 0
var race_snaps: int = 0
var race_frames: int = 0
var race_extrap: int = 0
var race_err_sum: float = 0.0
var race_err_n: int = 0
var race_err_max: float = 0.0
var win_snaps: int = 0
var win_frames: int = 0
var win_extrap: int = 0
var win_err_sum: float = 0.0
var win_err_n: int = 0
var win_err_max: float = 0.0


## Clears race totals and the window (keeps rtt and view delay, which carry over from the lobby).
func reset_race() -> void:
	race_seconds = 0
	race_snaps = 0
	race_frames = 0
	race_extrap = 0
	race_err_sum = 0.0
	race_err_n = 0
	race_err_max = 0.0
	rtt_max = rtt
	rtt_sum = 0.0
	rtt_n = 0
	close_window()


## Records one snapshot that is [param lateness] seconds old on arrival.
func record_snapshot(lateness: float, cfg: NetConfig) -> void:
	race_snaps += 1
	win_snaps += 1
	late_avg = lateness if late_avg == 0.0 else lerpf(late_avg, lateness, cfg.view_delay_smoothing)
	late_dev = lerpf(late_dev, absf(lateness - late_avg), cfg.view_delay_smoothing)
	view_delay = clampf(late_avg + 2.0 * late_dev + 1.0 / cfg.send_hz,
			cfg.view_delay_min, cfg.view_delay_max)


## Records how far the previous snapshot's velocity prediction was from the new position.
func record_error(meters: float) -> void:
	race_err_sum += meters
	race_err_n += 1
	race_err_max = maxf(race_err_max, meters)
	win_err_sum += meters
	win_err_n += 1
	win_err_max = maxf(win_err_max, meters)


## Records one interpolation step of one remote kart.
func record_frame(extrapolated: bool) -> void:
	race_frames += 1
	win_frames += 1
	if extrapolated:
		race_extrap += 1
		win_extrap += 1


## Records a round-trip sample (seconds).
func record_rtt(sample: float, cfg: NetConfig) -> void:
	rtt = sample if rtt == 0.0 else lerpf(rtt, sample, cfg.rtt_smoothing)
	rtt_max = maxf(rtt_max, sample)
	rtt_sum += sample
	rtt_n += 1


## Returns the last window's numbers and starts a new window.
func close_window() -> Dictionary:
	var w: Dictionary = {
		"snaps": win_snaps,
		"extrap_pct": 100.0 * win_extrap / maxi(win_frames, 1),
		"err_avg": win_err_sum / maxi(win_err_n, 1),
		"err_max": win_err_max,
	}
	win_snaps = 0
	win_frames = 0
	win_extrap = 0
	win_err_sum = 0.0
	win_err_n = 0
	win_err_max = 0.0
	return w
