class_name Pennant
extends Node3D
## The racer pennant (story 006): a tall pole with a gold finial and a swallowtail flag in the
## kart's identity colour plus one pattern shape (art bible section 4: solid, stripe, chevron,
## dots, checker, cross, split, diamond, border, star, wave, tri-band). Built entirely in code
## from a PennantStyle; the flag texture is generated (flat colours, nearest filtering) and a
## small shader waves the cloth, more with speed. Presentation only.
## Implements design/game-brief.md, Features item 6 ("each vehicle flies its racer's pennant").

const FLAG_SHADER: Shader = preload("res://src/vehicle/spatial_vehicle_pennant_flag.gdshader")

## Palette ids returned by [method pattern_at].
const BASE: int = 0
const ACCENT: int = 1
const SECONDARY: int = 2

var _style: PennantStyle
var _flag_mat: ShaderMaterial
var _pole_height: float = 1.0
static var _tex_cache: Dictionary = {}
static var _flag_cache: Dictionary = {}
static var _pole_cache: Dictionary = {}
static var _pole_parts_cache: Dictionary = {}
var _slot: int = 0
var _color: Color = Color.WHITE
var _identity_set: bool = false


## Builds the pole and flag. [param pole_length] is the pole length in meters from this node.
func build(style: PennantStyle, pole_length: float, slot: int, color: Color) -> void:
	_style = style
	_pole_height = pole_length
	var pole := MeshInstance3D.new()
	pole.mesh = _pole_mesh_cached(style, pole_length)
	pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(pole)
	_flag_mat = ShaderMaterial.new()
	_flag_mat.shader = FLAG_SHADER
	_flag_mat.set_shader_parameter("wave_cycles", style.wave_cycles)
	_flag_mat.set_shader_parameter("wave_amp", style.wave_amp_idle)
	_flag_mat.set_shader_parameter("wave_rate", style.wave_rate_idle)
	var flag := MeshInstance3D.new()
	flag.mesh = _flag_mesh_cached(style)
	flag.material_override = _flag_mat
	flag.position = Vector3(0, pole_length - style.top_inset - style.flag_height, 0)
	flag.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flag.rotation.y = deg_to_rad(style.flag_yaw_deg)
	add_child(flag)
	apply_identity(slot, color)


## Pole length in meters.
func pole_height() -> float:
	return _pole_height


## Sets the slot colour and pattern (regenerates the flag texture).
func apply_identity(slot: int, color: Color) -> void:
	if _flag_mat == null:
		_slot = slot
		return
	if _identity_set and slot == _slot and color == _color:
		return
	_identity_set = true
	_slot = slot
	_color = color
	_flag_mat.set_shader_parameter("pattern", make_texture(_style, slot, color))
	_flag_mat.set_shader_parameter("phase", float(slot) * 1.7)


## Wave strength follows [param speed_fraction] (0 standstill, 1 top speed or more).
func set_speed(speed_fraction: float) -> void:
	if _flag_mat == null:
		return
	var f: float = clampf(absf(speed_fraction), 0.0, 1.5)
	_flag_mat.set_shader_parameter("wave_amp", lerpf(_style.wave_amp_idle, _style.wave_amp_fast, minf(f, 1.0)))
	_flag_mat.set_shader_parameter("wave_rate", lerpf(_style.wave_rate_idle, _style.wave_rate_fast, minf(f, 1.0)))


## The flag texture for [param slot]: [param color] as the base, one pattern in the accent colour
## (cream on dark colours, ink on light ones), flat colours only. Cached per style, slot and color,
## so a texture is generated once per run however many karts share it.
static func make_texture(style: PennantStyle, slot: int, color: Color) -> ImageTexture:
	var key: String = "%d_%d_%s" % [style.get_instance_id(), posmod(slot, 12), color.to_html()]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var w: int = style.texture_width
	var h: int = style.texture_height
	var light: bool = color.get_luminance() > style.light_threshold
	var accent: Color = style.accent_on_light if light else style.accent_on_dark
	var secondary: Color = style.accent_on_dark if light else style.accent_on_light
	var palette: Array[PackedByteArray] = []
	for c: Color in [color, accent, secondary]:
		palette.append(PackedByteArray([c.r8, c.g8, c.b8]))
	var bytes := PackedByteArray()
	bytes.resize(w * h * 3)
	var at: int = 0
	for y in h:
		for x in w:
			# Image row 0 is the top of the flag (UV.y 0); the pattern y is measured from the top.
			var rgb: PackedByteArray = palette[pattern_at(slot, x, y, w, h)]
			bytes[at] = rgb[0]
			bytes[at + 1] = rgb[1]
			bytes[at + 2] = rgb[2]
			at += 3
	var tex: ImageTexture = ImageTexture.create_from_image(Image.create_from_data(w, h, false, Image.FORMAT_RGB8, bytes))
	_tex_cache[key] = tex
	return tex


## Generates (and caches) the textures of [param colors], one per slot, the flag mesh and the pole
## building blocks ahead of a race, so no kart pays for them at the start.
static func prewarm(style: PennantStyle, colors: PackedColorArray) -> void:
	for slot in colors.size():
		make_texture(style, slot, colors[slot])
	_flag_mesh_cached(style)
	_pole_parts(style)


# Pole and finial are one surface (vertex colors under the shared material): one draw call.
# Cached per style and length. Every vehicle and dog pair has its own pole length, so the
# cylinder is NOT a new CylinderMesh per length (creating a PrimitiveMesh costs ~0.5 ms with a
# renderer, measured in the story 006 perf pass): a unit-height cylinder made once per style is
# stretched in y. With equal top and bottom radii its side normals do not depend on the height,
# so the vertices and normals are those of a CylinderMesh of that height.
static func _pole_mesh_cached(style: PennantStyle, pole_length: float) -> ArrayMesh:
	var key: String = "%d_%.3f" % [style.get_instance_id(), pole_length]
	if _pole_cache.has(key):
		return _pole_cache[key]
	var parts: Array = _pole_parts(style)
	var cyl: Array = (parts[0] as Array).duplicate()
	var unit_v: PackedVector3Array = cyl[Mesh.ARRAY_VERTEX]
	var stretched := PackedVector3Array()
	stretched.resize(unit_v.size())
	for j in unit_v.size():
		var v: Vector3 = unit_v[j]
		stretched[j] = Vector3(v.x, v.y * pole_length, v.z)
	cyl[Mesh.ARRAY_VERTEX] = stretched
	var flat: Dictionary = ModelBatcher.new_flat()
	ModelBatcher.append_flat(flat, cyl, style.pole_color, Vector3(0, pole_length * 0.5, 0))
	ModelBatcher.append_flat(flat, parts[1], style.finial_color, Vector3(0, pole_length, 0))
	var mesh: ArrayMesh = ModelBatcher.flat_to_mesh(flat)
	_pole_cache[key] = mesh
	return mesh


# The pole's building blocks for [param style], made once: [unit-height cylinder arrays,
# finial sphere arrays] (Mesh.surface_get_arrays layout).
static func _pole_parts(style: PennantStyle) -> Array:
	var key: int = style.get_instance_id()
	if _pole_parts_cache.has(key):
		return _pole_parts_cache[key]
	var cyl := CylinderMesh.new()
	cyl.top_radius = style.pole_radius
	cyl.bottom_radius = style.pole_radius
	cyl.height = 1.0
	cyl.radial_segments = 6
	cyl.rings = 1
	var ball := SphereMesh.new()
	ball.radius = style.finial_radius
	ball.height = style.finial_radius * 2.0
	ball.radial_segments = 8
	ball.rings = 4
	var parts: Array = [cyl.get_mesh_arrays(), ball.get_mesh_arrays()]
	_pole_parts_cache[key] = parts
	return parts


static func _flag_mesh_cached(style: PennantStyle) -> ArrayMesh:
	var key: int = style.get_instance_id()
	if not _flag_cache.has(key):
		_flag_cache[key] = _flag_mesh(style)
	return _flag_cache[key]


## Palette id (BASE, ACCENT or SECONDARY) of the pixel [param x], [param y] (y from the top) of
## the pattern for [param slot] on a [param w] by [param h] texture. Slots repeat after 12.
static func pattern_at(slot: int, x: int, y: int, w: int, h: int) -> int:
	var u: float = (float(x) + 0.5) / float(w)
	var v: float = (float(y) + 0.5) / float(h)
	var px: float = u * 2.0  # pixel-like units so shapes stay round on the 2:1 texture
	var py: float = v
	var on: bool = false
	match posmod(slot, 12):
		0:  # solid
			on = false
		1:  # stripe: one horizontal band
			on = absf(v - 0.5) < 0.14
		2:  # chevron: a V pointing at the pole
			on = absf((u - 0.12) - absf(v - 0.5) * 0.9 - 0.2) < 0.09
		3:  # dots: three round dots
			for cx: float in [0.2, 0.4, 0.6]:
				if Vector2(px - cx * 2.0, py - 0.5).length() < 0.15:
					on = true
		4:  # checker
			on = u < 0.78 and ((int(u * 8.0 / 0.78) + int(v * 4.0)) % 2 == 0)
		5:  # cross: a plus sign
			on = (absf(v - 0.5) < 0.12 and u > 0.1 and u < 0.7) or (absf(u - 0.4) < 0.07 and v > 0.1 and v < 0.9)
		6:  # split: the tail half
			on = u > 0.45
		7:  # diamond
			on = absf(px - 0.8) + absf(py - 0.5) * 1.5 < 0.5
		8:  # border: a frame
			on = v < 0.14 or v > 0.86 or u < 0.07
		9:  # star: five points
			var d := Vector2(px - 0.8, py - 0.5)
			var a: float = fposmod(d.angle() + PI * 0.5, TAU / 5.0) / (TAU / 5.0)
			var tri: float = absf(a - 0.5) * 2.0
			on = d.length() < lerpf(0.17, 0.46, tri)
		10:  # wave: a sine band
			on = absf(v - 0.5 - 0.2 * sin(u * TAU * 1.4)) < 0.1
		11:  # tri-band: accent, base, secondary
			return ACCENT if v < 0.333 else (BASE if v < 0.667 else SECONDARY)
	return ACCENT if on else BASE


# Swallowtail flag in the YZ plane, extending back (+Z) from the pole at x = 0. y runs from 0
# (bottom) to flag_height at the pole. UV.x is 0 at the pole and 1 at the tail tips; UV.y is 0 at
# the top edge and 1 at the bottom (matching image rows).
static func _flag_mesh(style: PennantStyle) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var length: float = style.flag_length
	var height: float = style.flag_height
	var notch_u: float = 1.0 - style.notch_depth
	var segs: int = maxi(style.segments, 2)
	var cy: float = height * 0.5
	# Half height of the cloth at u (tapers to the tail).
	var half: Callable = func(u: float) -> float:
		return cy * lerpf(1.0, style.tail_taper, u)
	var cols: Array[float] = []
	for i in segs + 1:
		cols.append(notch_u * float(i) / float(segs))
	for i in segs:
		var u0: float = cols[i]
		var u1: float = cols[i + 1]
		var t0: Vector3 = Vector3(0, cy + half.call(u0), u0 * length)
		var b0: Vector3 = Vector3(0, cy - half.call(u0), u0 * length)
		var t1: Vector3 = Vector3(0, cy + half.call(u1), u1 * length)
		var b1: Vector3 = Vector3(0, cy - half.call(u1), u1 * length)
		_tri(st, t0, Vector2(u0, 0), b0, Vector2(u0, 1), t1, Vector2(u1, 0))
		_tri(st, b0, Vector2(u0, 1), b1, Vector2(u1, 1), t1, Vector2(u1, 0))
	# The fork: two tail points and a notch in the middle.
	var un: float = notch_u
	var tn: Vector3 = Vector3(0, cy + half.call(un), un * length)
	var bn: Vector3 = Vector3(0, cy - half.call(un), un * length)
	var mid: Vector3 = Vector3(0, cy, un * length)
	var tip_t: Vector3 = Vector3(0, cy + half.call(1.0), length)
	var tip_b: Vector3 = Vector3(0, cy - half.call(1.0), length)
	_tri(st, tn, Vector2(un, 0), mid, Vector2(un, 0.5), tip_t, Vector2(1, 0))
	_tri(st, mid, Vector2(un, 0.5), bn, Vector2(un, 1), tip_b, Vector2(1, 1))
	return st.commit()


static func _tri(st: SurfaceTool, a: Vector3, ua: Vector2, b: Vector3, ub: Vector2, c: Vector3, uc: Vector2) -> void:
	for pair: Array in [[a, ua], [b, ub], [c, uc]]:
		st.set_uv(pair[1])
		st.add_vertex(pair[0])
