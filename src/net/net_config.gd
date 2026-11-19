class_name NetConfig
extends Resource
## Network tuning data (story 002). Every number the sync design depends on lives here, not
## in code: send rate, view-delay bounds, extrapolation cap, clock sync, ranking debounce,
## start grid. Loaded from assets/data/net/net_config.tres and injected into Main.

## UDP port the host listens on and clients join.
@export var port: int = 24680
## Racers in one race, humans plus bots.
@export var max_racers: int = 12
## State updates per second sent for each kart a PC owns.
@export var send_hz: float = 30.0
## Lower bound of the adaptive view delay, seconds.
@export var view_delay_min: float = 0.05
## Upper bound of the adaptive view delay, seconds.
@export var view_delay_max: float = 0.35
## Smoothing (0..1 per snapshot) of the lateness average and deviation.
@export var view_delay_smoothing: float = 0.05
## Longest a remote kart is extrapolated past its newest snapshot, seconds.
@export var max_extrapolation: float = 0.25
## Snapshots kept per remote kart.
@export var snapshot_buffer_size: int = 40
## Seconds between ping messages a client sends to the host.
@export var ping_interval: float = 0.5
## Smoothing (0..1 per sample) of the round-trip time.
@export var rtt_smoothing: float = 0.2
## Clock error (seconds) above which the race clock is nudged towards the host's.
@export var clock_correct_threshold: float = 0.02
## Fraction of the clock error corrected per pong.
@export var clock_correct_rate: float = 0.15
## Seconds a kart must stay ahead before positions swap in the shown ranking.
@export var rank_debounce: float = 0.5
## Meters a kart must lead the one shown ahead of it (for the whole debounce time) before
## positions swap, so karts running side by side do not flip places on network noise.
@export var rank_pass_margin: float = 1.0
## Seconds the host waits after the last needed player joined before starting.
@export var start_delay: float = 1.5
## Bots the host adds when --bots is not given.
@export var default_bots: int = 2
## Meters between start grid rows (two karts per row).
@export var grid_row_spacing: float = 8.0
## Sideways offset of the two grid columns, meters.
@export var grid_lateral: float = 2.5
## Seconds a finished PC lingers (so others can finish) before a --quit-after-race exit.
@export var finish_linger: float = 3.0
## Hard cap on that linger, seconds.
@export var finish_timeout: float = 30.0
## Seconds between net log rows.
@export var log_interval: float = 1.0
## Paint colors for karts other than the local one, indexed by kart id.
@export var kart_colors: PackedColorArray = PackedColorArray()
