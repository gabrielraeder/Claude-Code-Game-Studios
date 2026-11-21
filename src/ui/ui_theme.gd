class_name UiTheme
extends Resource
## Look and wording of the menu, lobby, results and pause screens (story 007, part 1).
## Every colour, size and string of those screens lives here (assets/data/ui/ui_theme.tres),
## following art bible section 7 (parchment banners) and section 4 (palette). The screens only
## ask this resource for a Theme, for ready-made nodes and for text by key.

@export_group("Colours")
## Panel and banner fill (Parchment).
@export var parchment: Color = Color("F3E6C4")
## Slightly darker parchment for alternate rows and the secondary-button pressed state.
@export var parchment_dark: Color = Color("E3D3A8")
## Text and outline colour (Ink).
@export var ink: Color = Color("2A1E26")
## Softer ink for secondary text.
@export var ink_soft: Color = Color("5B4A52")
## Primary button fill (Red-Orange) and the highlight of your own row.
@export var primary: Color = Color("E8452C")
## Primary button pressed fill.
@export var primary_dark: Color = Color("B8331E")
## Disabled button fill.
@export var disabled: Color = Color("B8AE96")
## Keyboard / controller focus ring (Gold).
@export var focus_ring: Color = Color("F5C542")
## Full-screen dim behind the menu and lobby.
@export var backdrop: Color = Color(0.1, 0.07, 0.1, 0.92)
## Lighter dim behind the pause menu and the results over the race.
@export var dim: Color = Color(0.1, 0.07, 0.1, 0.62)
## Place colours in the results: 1st, 2nd, 3rd and everybody else (cream).
@export var place_first: Color = Color("F5C542")
@export var place_second: Color = Color("C8D3E0")
@export var place_third: Color = Color("C98A4B")
@export var place_other: Color = Color("F3E6C4")
## Colour of "Ready" and of "Not ready" in the roster.
@export var ready_color: Color = Color("2E7D4F")
@export var not_ready_color: Color = Color("9A3B2B")

@export_group("Sizes")
## Window height the layout is designed for; screens scale up or down from it.
@export var base_height: float = 720.0
@export var title_font: int = 46
@export var heading_font: int = 30
@export var body_font: int = 22
@export var small_font: int = 18
@export var button_font: int = 26
## Smallest size of a button.
@export var button_min: Vector2 = Vector2(300, 52)
@export var small_button_min: Vector2 = Vector2(300, 38)
## Height of the cycle rows (racer, vehicle, track, bots, laps) in the lobby.
@export var cycle_height: float = 44.0
## Smallest height of a roster / results row.
@export var row_height: float = 30.0
@export var panel_margin: int = 18
@export var border_width: int = 4
@export var focus_width: int = 5
@export var corner_radius: int = 8
@export var gap: int = 14
## Size of the 3D dog-on-vehicle preview in the lobby, in base pixels.
@export var preview_size: Vector2i = Vector2i(400, 160)
## Preview spin in degrees per second (0 = still, for players who dislike motion).
@export var preview_spin: float = 30.0
## CanvasLayer order of the screens (above the HUD).
@export var screen_layer: int = 10

@export_group("Race HUD")
## Base-pixel sizes of the race HUD (designed at base_height, scaled with the window like the screens).
## Gap from the screen edges.
@export var hud_margin: float = 14.0
## Place numeral, its ordinal suffix and the "/12" total (art bible 7: 96 px numeral at 1080p).
@export var hud_place_font: int = 64
@export var hud_place_suffix_font: int = 30
@export var hud_place_total_font: int = 28
## Countdown numbers and GO (160 px at 1080p).
@export var hud_countdown_font: int = 107
## Centre messages (PERFECT START!, SPUN OUT!, the finish panel, lobby text).
@export var hud_message_font: int = 34
## Lap pill (36 px at 1080p), time pill and the small best-lap / item-name text.
@export var hud_lap_font: int = 24
@export var hud_time_font: int = 22
@export var hud_small_font: int = 17
## Control hints line and the network status line (never below 20 px at 1080p).
@export var hud_hint_font: int = 15
## Ink outline of cream text drawn straight over the world.
@export var hud_outline: int = 6
## Ink outline of the place numeral.
@export var hud_place_outline: int = 8
## Ink outline width of badges (item circle, pills).
@export var hud_badge_border: int = 3
## Extra weight given to the fallback font for numerals (FontVariation embolden).
@export var hud_numeral_embolden: float = 0.7
## Cream used for text over the world.
@export var hud_cream: Color = Color("F6EBD0")
## Badge fill (pills and the item circle), slightly see-through parchment.
@export var hud_badge_fill: Color = Color(0.9529, 0.902, 0.7686, 0.94)
## Item circle radius and the radius of the icon inside it.
@export var hud_item_radius: float = 40.0
@export var hud_item_icon_radius: float = 26.0
## Vertical gap between the badges of the left column.
@export var hud_column_gap: int = 8
## Pill inner padding (left/right) and height.
@export var hud_pill_pad: int = 14
@export var hud_pill_height: float = 34.0
## Drift meter: pip size, gap, tier colours (art bible 4: T1 blue, T2 orange, T3 purple),
## unlit pip and the boost colour (all pips while a boost runs).
@export var hud_pip_size: float = 14.0
@export var hud_pip_gap: float = 5.0
@export var hud_drift_tier_colors: PackedColorArray = PackedColorArray([Color("3FA9FF"), Color("FF9A1F"), Color("A64DFF")])
@export var hud_pip_off: Color = Color(0.1647, 0.1176, 0.149, 0.18)
@export var hud_boost_color: Color = Color("F2A33A")
## Colour of "GO!".
@export var hud_go_color: Color = Color("F5C542")
## Place numeral pop when the place changes: peak scale and duration (0 = no pop).
@export var hud_place_pop_scale: float = 1.2
@export var hud_place_pop_time: float = 0.2
## Minimap: tile size (square, bottom right), inner padding, corner radius.
@export var hud_minimap_size: float = 210.0
@export var hud_minimap_pad: float = 16.0
@export var hud_minimap_corner: int = 16
## Minimap road: ink outer line, inner road colour, widths (main loop, branches), start line.
@export var hud_minimap_road_outer: float = 10.0
@export var hud_minimap_road_inner: float = 5.0
@export var hud_minimap_branch_outer: float = 7.0
@export var hud_minimap_branch_inner: float = 3.0
@export var hud_minimap_road_color: Color = Color("8C919A")
@export var hud_minimap_start_color: Color = Color("E8452C")
## Most points kept per road line (the centerline is thinned to this once per track).
@export var hud_minimap_max_points: int = 200
## Racer pennant triangle: length (tip to back) and half width; local player's cream ring
## radius and width; the leader's gold ring radius.
@export var hud_minimap_dot_len: float = 15.0
@export var hud_minimap_dot_half: float = 8.0
@export var hud_minimap_dot_border: float = 2.0
@export var hud_minimap_local_ring: float = 12.0
@export var hud_minimap_local_ring_width: float = 3.5
@export var hud_minimap_leader_ring: float = 10.0
## CanvasLayer order of the race HUD (below the screens).
@export var hud_layer: int = 1

@export_group("Controls")
## Controls screen (story 007 part 3): size of one binding box, width of the action names,
## gap between the rows.
@export var controls_cell_size: Vector2 = Vector2(290, 34)
@export var controls_action_width: float = 210.0
@export var controls_row_gap: int = 4
## Font size of the binding boxes.
@export var controls_cell_font: int = 20
## Seconds a capture waits for the new input before it gives up.
@export var controls_capture_timeout: float = 8.0
## How far a stick or trigger must move (0..1) to be captured.
@export var controls_axis_threshold: float = 0.6
## Milliseconds after a capture during which stick movement is ignored (the bound stick is still held).
@export var controls_quiet_ms: int = 400

@export_group("Spectating")
## Standings column of a spectator (story 007 part 3): row height, swatch size, name width.
@export var spec_row_height: float = 24.0
@export var spec_swatch: float = 14.0
@export var spec_name_width: float = 150.0

@export_group("Rules")
## Recent hosts kept, the address offered first time, and where they are saved.
@export var recent_max: int = 5
@export var default_address: String = "127.0.0.1"
@export var recent_file: String = "user://recent_hosts.json"
## Track ids the host can pick in the lobby, in order.
@export var lobby_tracks: PackedStringArray = PackedStringArray(["castle_circuit", "dungeon_depths"])
## Fewest and most laps the host can pick.
@export var laps_min: int = 1
@export var laps_max: int = 9
## Seconds a finished solo kart is shown before the results appear.
@export var solo_results_delay: float = 1.5
## Seconds between the scripted presses of --auto-ui (debug).
@export var auto_ui_step: float = 0.6

@export_group("Text")
## Every user-facing string by key. Placeholders use % formatting.
@export var texts: Dictionary = {}

var _built: Theme


## The string for [param key], formatted with [param args] when given. A missing key shows
## the key itself and warns.
func t(key: String, args: Array = []) -> String:
	if not texts.has(key):
		push_warning("ui_theme.tres has no text '%s'." % key)
		return key
	var s: String = str(texts[key])
	return s % args if not args.is_empty() else s


## Place colour for [param place] (1-based).
func place_color(place: int) -> Color:
	match place:
		1:
			return place_first
		2:
			return place_second
		3:
			return place_third
	return place_other


## English ordinal of [param n]: 1st, 2nd, 3rd, 4th.
static func ordinal(n: int) -> String:
	var tail: int = n % 100
	if tail >= 11 and tail <= 13:
		return "%dth" % n
	match n % 10:
		1:
			return "%dst" % n
		2:
			return "%dnd" % n
		3:
			return "%drd" % n
	return "%dth" % n


## A flat parchment-style box: [param fill] with an outline of [param border].
func box(fill: Color, border: Color, border_px: int = -1, margin: int = -1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(border_width if border_px < 0 else border_px)
	sb.set_corner_radius_all(corner_radius)
	var m: int = panel_margin if margin < 0 else margin
	sb.content_margin_left = m
	sb.content_margin_right = m
	sb.content_margin_top = int(m * 0.7)
	sb.content_margin_bottom = int(m * 0.7)
	sb.anti_aliasing = true
	return sb


## The Theme every screen uses (built once): buttons (secondary and "PrimaryButton"), labels,
## line edits and panels, with the gold focus ring.
func build_theme() -> Theme:
	if _built != null:
		return _built
	var th := Theme.new()
	th.default_font_size = body_font
	th.set_font_size(&"font_size", &"Label", body_font)
	th.set_color(&"font_color", &"Label", ink)
	th.set_stylebox(&"panel", &"PanelContainer", box(parchment, ink))
	var ring := StyleBoxFlat.new()
	ring.draw_center = false
	ring.border_color = focus_ring
	ring.set_border_width_all(focus_width)
	ring.set_corner_radius_all(corner_radius + 2)
	ring.set_expand_margin_all(float(focus_width) * 0.6)
	ring.anti_aliasing = true
	_button_styles(th, &"Button", parchment, parchment_dark, ink, ring)
	th.set_type_variation(&"PrimaryButton", &"Button")
	_button_styles(th, &"PrimaryButton", primary, primary_dark, parchment, ring)
	th.set_font_size(&"font_size", &"Button", button_font)
	th.set_font_size(&"font_size", &"PrimaryButton", button_font)
	th.set_stylebox(&"normal", &"LineEdit", box(Color.WHITE.lerp(parchment, 0.6), ink, 3, 10))
	th.set_stylebox(&"focus", &"LineEdit", ring)
	th.set_stylebox(&"read_only", &"LineEdit", box(disabled, ink, 3, 10))
	th.set_color(&"font_color", &"LineEdit", ink)
	th.set_color(&"font_placeholder_color", &"LineEdit", ink_soft)
	th.set_color(&"caret_color", &"LineEdit", ink)
	th.set_color(&"selection_color", &"LineEdit", primary)
	th.set_font_size(&"font_size", &"LineEdit", body_font)
	_built = th
	return th


func _button_styles(th: Theme, type: StringName, fill: Color, pressed: Color, text: Color, ring: StyleBoxFlat) -> void:
	th.set_stylebox(&"normal", type, box(fill, ink, border_width, 14))
	th.set_stylebox(&"hover", type, box(fill.lightened(0.12), ink, border_width, 14))
	th.set_stylebox(&"pressed", type, box(pressed, ink, border_width, 14))
	th.set_stylebox(&"disabled", type, box(disabled, ink_soft, border_width, 14))
	th.set_stylebox(&"focus", type, ring)
	for c in [&"font_color", &"font_hover_color", &"font_pressed_color", &"font_focus_color"]:
		th.set_color(c, type, text)
	th.set_color(&"font_disabled_color", type, ink_soft)


## A Label with [param text]; [param size] 0 = body size, [param color] with alpha 0 = the theme's ink.
func label(text: String, size: int = 0, color: Color = Color(0, 0, 0, 0)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override(&"font_size", size if size > 0 else body_font)
	if color.a > 0.0:
		l.add_theme_color_override(&"font_color", color)
	return l


## A button; [param primary_look] uses the Red-Orange fill, [param small] a shorter size and body font.
func button(text: String, primary_look: bool = false, small: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = small_button_min if small else button_min
	if primary_look:
		b.theme_type_variation = &"PrimaryButton"
	if small:
		b.add_theme_font_size_override(&"font_size", body_font)
	b.focus_mode = Control.FOCUS_ALL
	return b


## A parchment panel holding a VBox. Returns the panel; the VBox is in [param out_box][0].
func panel(separation: int, out_box: Array) -> PanelContainer:
	var p := PanelContainer.new()
	var v := VBoxContainer.new()
	v.add_theme_constant_override(&"separation", separation)
	p.add_child(v)
	out_box.append(v)
	return p
