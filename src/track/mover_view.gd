class_name MoverView
extends Node3D
## Draws the timed moving hazards of a track (story 009): for a "gate" mover the movable deck that
## rotates up on a hinge at the gatehouse end, its chains, and the gate posts with the signal
## lantern (green = open, flashing amber = warning, red = raised). It only reads the HazardManager's
## time, so every PC draws the same state. Nodes are built once; each frame only transforms and the
## lantern color change.
## Implements production/epics/dogworks-racing-kennel-kingdom/story-009-moving-hazards.md.

## Thickness of the deck slab in meters (visual only: the drivable surface is the road's).
const SLAB_THICKNESS: float = 0.35
## Height of the drawn deck top above the road, matching TrackMesh.DECK_Y so it does not flicker.
const DECK_LIFT: float = 0.04
## Chain link thickness in meters.
const CHAIN_SIZE: float = 0.14
## Lantern post thickness in meters and lantern size.
const POST_SIZE: float = 0.35
const LANTERN_SIZE: float = 0.7
## Chain and post color.
const IRON_COLOR: Color = Color(0.2, 0.2, 0.22)
## How much brighter than its albedo the lantern glows.
const LANTERN_GLOW: float = 2.0

class GateView extends RefCounted:
	var index: int = 0
	var mover: TrackMover
	var hinge: Vector3 = Vector3.ZERO
	var axis: Vector3 = Vector3.RIGHT
	var tip_local: Vector3 = Vector3.ZERO
	var lateral: Vector3 = Vector3.ZERO
	var anchor: Vector3 = Vector3.ZERO
	var deck: Node3D
	var chains: Array[MeshInstance3D] = []
	var lantern_mat: Array[StandardMaterial3D] = []

var _hazards: HazardManager
var _gates: Array[GateView] = []


## Builds the views for every gate mover of [param track]; [param hazards] supplies the state.
func setup(track: TrackModel, hazards: HazardManager) -> void:
	_hazards = hazards
	for i in hazards.count():
		var m: TrackMover = hazards.mover(i)
		if m.kind != &"gate" or hazards.path_index(i) < 0:
			continue
		_build_gate(track, i, m)
	set_process(not _gates.is_empty())


func _process(_delta: float) -> void:
	var t: float = _hazards.time
	for g in _gates:
		var m: TrackMover = g.mover
		var angle: float = deg_to_rad(_hazards.angle_deg_at(m, t))
		g.deck.basis = Basis(g.axis, angle)
		var tip: Vector3 = g.hinge + g.deck.basis * g.tip_local
		for k in 2:
			var side: float = 1.0 if k == 0 else -1.0
			_place_chain(g.chains[k], tip + g.deck.basis * (g.lateral * side), g.anchor + g.lateral * side)
		var phase: int = _hazards.phase_at(m, t)
		var col: Color = m.color_open
		if _hazards.is_active(m, t) or phase == HazardManager.Phase.RISING or phase == HazardManager.Phase.FALLING:
			col = m.color_blocked
		elif phase == HazardManager.Phase.WARNING:
			var on: bool = fmod(t * m.warn_blink_hz, 1.0) < 0.5
			col = m.color_warn if on else m.color_warn.darkened(0.7)
		for mat in g.lantern_mat:
			mat.albedo_color = col
			mat.emission = col


func _build_gate(track: TrackModel, index: int, m: TrackMover) -> void:
	var bi: int = _hazards.path_index(index)
	var road: TrackModel.Path = track.branches[bi]
	var seg: Vector2i = m.deck_segments(road)
	if seg.x < 0:
		return
	var g := GateView.new()
	g.index = index
	g.mover = m
	var end_pt: Vector2 = road.points[seg.y + 1]
	var end_y: float = road.y[seg.y + 1]
	g.hinge = Vector3(end_pt.x, end_y, end_pt.y)
	var tang: Vector2 = (road.points[seg.y + 1] - road.points[seg.y]).normalized()
	var t3 := Vector3(tang.x, 0.0, tang.y)
	g.axis = (-t3).cross(Vector3.UP).normalized()
	g.lateral = t3.cross(Vector3.UP).normalized() * m.deck_half_width * 0.9
	var start_pt: Vector2 = road.points[seg.x]
	g.tip_local = Vector3(start_pt.x, road.y[seg.x], start_pt.y) - g.hinge
	g.anchor = g.hinge + t3 * m.chain_anchor_beyond + Vector3.UP * m.chain_anchor_height
	# The deck: the road's own segments in the hinge frame, as slabs with alternating planks.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(seg.x, seg.y + 1):
		var a: Vector2 = road.points[i]
		var b: Vector2 = road.points[i + 1]
		var col: Color = m.deck_color if i % 2 == 0 else m.deck_alt_color
		_slab(st, Vector3(a.x, road.y[i], a.y) - g.hinge, Vector3(b.x, road.y[i + 1], b.y) - g.hinge,
				m.deck_half_width + road.curb, col)
	g.deck = Node3D.new()
	g.deck.position = g.hinge
	add_child(g.deck)
	g.deck.add_child(_instance(st.commit()))
	for k in 2:
		var chain := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(CHAIN_SIZE, CHAIN_SIZE, 1.0)
		chain.mesh = bm
		chain.material_override = _flat(IRON_COLOR)
		add_child(chain)
		g.chains.append(chain)
	_build_signal(track, bi, m, g)
	_gates.append(g)


# Two posts either side of the road at m.signal_along, each with a lantern on top.
func _build_signal(_track: TrackModel, bi: int, m: TrackMover, g: GateView) -> void:
	var road: TrackModel.Path = _track.branches[bi]
	var st: Vector2 = road.seg_t_at(m.signal_along)
	var p: Vector2 = road.point_at(m.signal_along)
	var tn: Vector2 = road.tangent_at(m.signal_along)
	var nrm := Vector2(-tn.y, tn.x)
	var y: float = road.height_at(int(st.x), st.y)
	for side in [1.0, -1.0]:
		var base: Vector2 = p + nrm * (m.deck_half_width + road.curb + 0.6) * side
		var post := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(POST_SIZE, m.signal_height, POST_SIZE)
		post.mesh = pm
		post.material_override = _flat(IRON_COLOR)
		post.position = Vector3(base.x, y + m.signal_height * 0.5, base.y)
		add_child(post)
		var lamp := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(LANTERN_SIZE, LANTERN_SIZE, LANTERN_SIZE)
		lamp.mesh = lm
		var mat := StandardMaterial3D.new()
		mat.emission_enabled = true
		mat.emission_energy_multiplier = LANTERN_GLOW
		mat.albedo_color = m.color_open
		mat.emission = m.color_open
		lamp.material_override = mat
		lamp.position = Vector3(base.x, y + m.signal_height + LANTERN_SIZE * 0.5, base.y)
		add_child(lamp)
		g.lantern_mat.append(mat)


func _place_chain(chain: MeshInstance3D, from: Vector3, to: Vector3) -> void:
	var d: Vector3 = to - from
	var len: float = d.length()
	if len < 0.01:
		return
	var dir: Vector3 = d / len
	var up: Vector3 = Vector3.UP if absf(dir.y) < 0.99 else Vector3.RIGHT
	var b: Basis = Basis.looking_at(dir, up) * Basis.from_scale(Vector3(1.0, 1.0, len))
	chain.transform = Transform3D(b, (from + to) * 0.5)


func _flat(col: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	return mat


func _instance(mesh: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	return mi


# A slab from [param a] to [param b] (relative to the hinge), half width [param hw]: top at
# DECK_LIFT above the road, SLAB_THICKNESS thick, flat normals, one color.
func _slab(st: SurfaceTool, a: Vector3, b: Vector3, hw: float, col: Color) -> void:
	var d := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
	var side: Vector3 = d.cross(Vector3.UP) * hw
	var top: Vector3 = Vector3.UP * DECK_LIFT
	var bot: Vector3 = top - Vector3.UP * SLAB_THICKNESS
	var c: Array[Vector3] = [a + side + top, a - side + top, b - side + top, b + side + top,
			a + side + bot, a - side + bot, b - side + bot, b + side + bot]
	st.set_color(col)
	_quad(st, c[0], c[1], c[2], c[3], Vector3.UP)
	_quad(st, c[7], c[6], c[5], c[4], Vector3.DOWN)
	_quad(st, c[4], c[5], c[1], c[0], -d)
	_quad(st, c[3], c[2], c[6], c[7], d)
	_quad(st, c[0], c[3], c[7], c[4], side.normalized())
	_quad(st, c[5], c[6], c[2], c[1], -side.normalized())


func _quad(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, n: Vector3) -> void:
	st.set_normal(n)
	for p in [p0, p1, p2, p0, p2, p3]:
		st.add_vertex(p)
