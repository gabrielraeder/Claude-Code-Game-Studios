class_name PennantStyle
extends Resource
## Shape, colours and wave of the racer pennant (story 006). One resource for every kart; the
## colour and pattern come from the kart's slot (art bible section 4: 12 patterns).

## Names of the 12 slot patterns, in slot order (the index is the pattern id).
@export var pattern_names: PackedStringArray = PackedStringArray([
	"solid", "stripe", "chevron", "dots", "checker", "cross",
	"split", "diamond", "border", "star", "wave", "tri-band"])
@export_group("Pole")
@export var pole_color: Color = Color(0.965, 0.922, 0.816)
@export var pole_radius: float = 0.04
@export var finial_color: Color = Color(0.961, 0.773, 0.259)
@export var finial_radius: float = 0.085
@export_group("Flag")
## Flag length (along the pole's back) and height at the pole, in meters.
@export var flag_length: float = 1.4
@export var flag_height: float = 0.8
## Degrees the flag is turned from straight back toward the side, so the chase camera sees its
## face instead of its edge (0 = straight back).
@export var flag_yaw_deg: float = 55.0
## Height at the tail as a fraction of flag_height (the flag tapers).
@export var tail_taper: float = 0.6
## Depth of the swallowtail notch as a fraction of the length.
@export var notch_depth: float = 0.28
## Distance from the pole top to the flag top, in meters.
@export var top_inset: float = 0.06
## Length segments of the cloth (more = a smoother wave).
@export var segments: int = 8
@export_group("Pattern")
## Pattern texture size in pixels.
@export var texture_width: int = 64
@export var texture_height: int = 32
## Pattern accent on dark colours, and on light ones (when luminance is above the threshold).
@export var accent_on_dark: Color = Color(0.965, 0.922, 0.816)
@export var accent_on_light: Color = Color(0.165, 0.118, 0.149)
@export var light_threshold: float = 0.6
@export_group("Wave")
## Sideways wave size in meters at standstill and at full speed.
@export var wave_amp_idle: float = 0.025
@export var wave_amp_fast: float = 0.1
## Wave speed in rad/s at standstill and at full speed.
@export var wave_rate_idle: float = 3.0
@export var wave_rate_fast: float = 14.0
## Wave cycles along the cloth.
@export var wave_cycles: float = 1.2
