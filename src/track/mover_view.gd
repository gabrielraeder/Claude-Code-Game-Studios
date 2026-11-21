class_name MoverView
extends Node3D
## Draws the timed moving hazards of a track (story 009): for a drawbridge the movable deck that
## rotates up on a hinge at the gatehouse end, its chains, and the gate posts with the signal
## lantern (green = open, flashing amber = warning, red = raised); for a portcullis the iron grille
## that drops in its stone frame, with the same lanterns on the frame; for a barrel the rolling
## wooden barrel with iron bands, in its lane on the road surface; for a lava burst a glowing vent
## in the road edge that brightens and pulses in the warning and a lava column that shoots up out
## of it; for the mine cart an ore cart on its rails with turning wheels. It only reads the HazardManager's
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

class PortcullisView extends RefCounted:
	var mover: TrackMover
	var base: Vector3 = Vector3.ZERO
	var grille: Node3D
	var lantern_mat: Array[StandardMaterial3D] = []

class BarrelView extends RefCounted:
	var mover: TrackMover
	var body: Node3D

class BurstView extends RefCounted:
	var mover: TrackMover
	var vent_mat: StandardMaterial3D
	var column: Node3D

class CartView extends RefCounted:
	var mover: TrackMover
	var road: TrackModel.Path
	var body: Node3D
	var wheels: Array[Node3D] = []

## Radial segments of the barrel's cylinders (low poly).
const BARREL_SEGMENTS: int = 10
## Barrel shape relative to its radius / length (pure geometry of the model): end radius, iron band
## width, band radius and positions along the barrel, the dark stave that shows the roll.
const BARREL_END_SCALE: float = 0.85
const BAND_WIDTH: float = 0.09
const BAND_RADIUS_SCALE: float = 1.04
const BAND_AT: PackedFloat32Array = [-0.36, 0.36]
const STAVE_WIDTH: float = 0.16
## Portcullis frame pillar thickness and lintel height in meters.
const PILLAR_SIZE: float = 0.9
const LINTEL_HEIGHT: float = 0.7
## Horizontal bars of the grille.
const GRILLE_RAILS: int = 4
## Seconds ahead used to find a barrel's direction of travel.
const HEADING_DT: float = 0.05
## Radial segments of the burst's vent disc and column, and the vent disc's thickness (low poly).
const BURST_SEGMENTS: int = 8
const VENT_THICKNESS: float = 0.1
## Height of the vent's top above the road, so it does not flicker with the road surface.
const VENT_LIFT: float = 0.03
## Burst column shape (pure geometry of the model): top radius relative to the bottom, how far it
## reaches below the vent (into the lava beside the road), the blob on top relative to the radius.
const COLUMN_TOP_SCALE: float = 0.55
const COLUMN_SINK: float = 1.5
const COLUMN_BLOB_SCALE: float = 1.15
## Ore cart shape relative to its size (pure geometry of the model): wheel inset from the ends,
## wheel width, the iron bands' positions along the body and thickness, the ore heap's height.
const CART_WHEEL_INSET: float = 0.22
const CART_WHEEL_WIDTH: float = 0.16
const CART_BAND_AT: PackedFloat32Array = [-0.38, 0.38]
const CART_BAND_SIZE: float = 0.08
const CART_ORE_HEIGHT: float = 0.45
const CART_WHEEL_SEGMENTS: int = 8

var _hazards: HazardManager
var _gates: Array[GateView] = []
var _portcullises: Array[PortcullisView] = []
var _barrels: Array[BarrelView] = []
var _bursts: Array[BurstView] = []
var _carts: Array[CartView] = []


## Builds the views for every gate mover of [param track]; [param hazards] supplies the state.
func setup(track: TrackModel, hazards: HazardManager) -> void:
	_hazards = hazards
	for i in hazards.count():
		var m: TrackMover = hazards.mover(i)
		if m.visual == &"barrel":
			_build_barrel(m)
			continue
		if m.visual == &"burst":
			_build_burst(m)
			continue
		if m.visual == &"cart":
			_build_cart(track.path_of(hazards.path_index(i)), m)
			continue
		if m.kind != &"gate" or hazards.path_index(i) < 0:
			continue
		if m.visual == &"portcullis":
			_build_portcullis(track, m)
		else:
			_build_gate(track, i, m)
	set_process(not _gates.is_empty() or not _portcullises.is_empty() or not _barrels.is_empty()
			or not _bursts.is_empty() or not _carts.is_empty())


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
		_set_lanterns(m, t, g.lantern_mat)
	for pv in _portcullises:
		var pm: TrackMover = pv.mover
		pv.grille.position = pv.base + Vector3.UP * (1.0 - _hazards.progress_at(pm, t)) * pm.lift_height
		_set_lanterns(pm, t, pv.lantern_mat)
	for bv in _barrels:
		_place_barrel(bv, t)
	for uv in _bursts:
		_place_burst(uv, t)
	for cv in _carts:
		_place_cart(cv, t)


# Lantern color of a gate at time [param t]: red while blocked or moving, flashing amber during the
# warning, green when open.
func _set_lanterns(m: TrackMover, t: float, mats: Array[StandardMaterial3D]) -> void:
	var phase: int = _hazards.phase_at(m, t)
	var col: Color = m.color_open
	if _hazards.is_active(m, t) or phase == HazardManager.Phase.RISING or phase == HazardManager.Phase.FALLING:
		col = m.color_blocked
	elif phase == HazardManager.Phase.WARNING:
		var on: bool = fmod(t * m.warn_blink_hz, 1.0) < 0.5
		col = m.color_warn if on else m.color_warn.darkened(0.7)
	for mat in mats:
		mat.albedo_color = col
		mat.emission = col


# A rolling barrel: hidden while idle; during its warning it rises at the top of its run until it
# is solid and waits there; then it rolls on the road surface in its lane, turning about the axis across its
# path by the distance rolled over its radius, and shrinks into the street at the end of its run.
func _place_barrel(bv: BarrelView, t: float) -> void:
	var m: TrackMover = bv.mover
	var phase: int = _hazards.phase_at(m, t)
	var d: float = _hazards.distance_at(m, t)
	var grow: float = clampf((m.path_to - d) / maxf(m.appear_distance, HazardManager.EPSILON), 0.0, 1.0)
	if phase == HazardManager.Phase.WARNING:
		var since: float = m.warning_lead - _hazards.time_to_start(m, t)
		grow = clampf(since / maxf(m.warning_lead - m.solid_lead, HazardManager.EPSILON), 0.0, 1.0)
	bv.body.visible = (phase == HazardManager.Phase.ACTIVE or phase == HazardManager.Phase.WARNING) \
			and grow > HazardManager.EPSILON
	if not bv.body.visible:
		return
	var pose: Vector3 = _hazards.pose_at(m, t)
	var ahead: Vector3 = _hazards.pose_at(m, t + HEADING_DT) - pose
	var tang := Vector3(ahead.x, 0.0, ahead.z)
	tang = tang.normalized() if tang.length_squared() > 0.0 else Vector3.FORWARD
	# Rolling without slipping turns about UP x travel by distance / radius.
	var axis: Vector3 = Vector3.UP.cross(tang).normalized()
	# Local Y (the cylinder axis) across the road, local X along the travel.
	var b0 := Basis(tang, axis, tang.cross(axis))
	var roll: float = (d - m.path_from) / maxf(m.body_radius, HazardManager.EPSILON)
	var b: Basis = Basis(axis, roll) * b0
	bv.body.transform = Transform3D(b.scaled_local(Vector3.ONE * grow), pose + Vector3.UP * m.body_radius * grow)


func _build_barrel(m: TrackMover) -> void:
	var bv := BarrelView.new()
	bv.mover = m
	bv.body = Node3D.new()
	add_child(bv.body)
	var wood := _flat(m.body_color)
	var iron := _flat(m.band_color)
	bv.body.add_child(_cylinder(m.body_radius * BARREL_END_SCALE, m.body_length, wood, 0.0))
	# The bulge: a wider short cylinder in the middle.
	bv.body.add_child(_cylinder(m.body_radius, m.body_length * 0.5, wood, 0.0))
	for at in BAND_AT:
		bv.body.add_child(_cylinder(m.body_radius * BAND_RADIUS_SCALE, m.body_length * BAND_WIDTH, iron, m.body_length * at))
	# A dark stave along the barrel shows it turning.
	var stave := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(m.body_radius * STAVE_WIDTH * 2.0, m.body_length * 0.5, m.body_radius * STAVE_WIDTH * 0.5)
	stave.mesh = sm
	stave.material_override = _flat(m.body_color.darkened(m.stave_darken))
	# On the bulge, sunk to half its thickness (a darker stave, not a plank sticking out).
	stave.position = Vector3(0.0, 0.0, m.body_radius)
	bv.body.add_child(stave)
	bv.body.visible = false
	_barrels.append(bv)


# A lava burst: the vent glows dull while idle, pulses brighter through the warning (it is about to
# blow) while a lava dome bubbles out of it, and burns bright while the column is up; the column grows out of the vent with the burst's
# progress (rise, full, fall) and is hidden while idle.
func _place_burst(uv: BurstView, t: float) -> void:
	var m: TrackMover = uv.mover
	var phase: int = _hazards.phase_at(m, t)
	var progress: float = _hazards.progress_at(m, t)
	var heat: float = 0.0
	if phase == HazardManager.Phase.WARNING:
		var lead: float = maxf(m.warning_lead, HazardManager.EPSILON)
		var ramp: float = clampf(1.0 - _hazards.time_to_start(m, t) / lead, 0.0, 1.0)
		var pulse: float = 0.5 + 0.5 * sin(t * m.warn_blink_hz * TAU)
		heat = ramp * (0.5 + 0.5 * pulse)
	elif phase != HazardManager.Phase.IDLE:
		heat = 1.0
	uv.vent_mat.albedo_color = m.vent_idle_color.lerp(m.vent_hot_color, heat)
	uv.vent_mat.emission = uv.vent_mat.albedo_color
	uv.vent_mat.emission_energy_multiplier = lerpf(m.vent_glow_idle, m.vent_glow_warn, heat)
	var rise: float = progress
	if phase == HazardManager.Phase.WARNING:
		rise = m.warn_dome * heat
	uv.column.visible = rise > HazardManager.EPSILON
	if uv.column.visible:
		uv.column.scale = Vector3(1.0, rise, 1.0)


func _build_burst(m: TrackMover) -> void:
	var uv := BurstView.new()
	uv.mover = m
	var base := Vector3(m.vent_center.x, m.vent_height, m.vent_center.y)
	var vent := MeshInstance3D.new()
	var vm := CylinderMesh.new()
	vm.top_radius = m.vent_radius
	vm.bottom_radius = m.vent_radius
	vm.height = VENT_THICKNESS
	vm.radial_segments = BURST_SEGMENTS
	vm.rings = 1
	vent.mesh = vm
	uv.vent_mat = StandardMaterial3D.new()
	uv.vent_mat.emission_enabled = true
	uv.vent_mat.albedo_color = m.vent_idle_color
	uv.vent_mat.emission = m.vent_idle_color
	uv.vent_mat.emission_energy_multiplier = m.vent_glow_idle
	vent.material_override = uv.vent_mat
	vent.position = base + Vector3.UP * (VENT_LIFT - VENT_THICKNESS * 0.5)
	add_child(vent)
	# The column: opaque and unshaded (a solid cartoon jet, no transparent overdraw), its pivot at
	# the vent so scaling Y grows it upward.
	uv.column = Node3D.new()
	uv.column.position = base
	add_child(uv.column)
	var hot := StandardMaterial3D.new()
	hot.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hot.albedo_color = m.column_color
	hot.emission_enabled = true
	hot.emission = m.column_color
	hot.emission_energy_multiplier = m.column_glow
	var cm := CylinderMesh.new()
	cm.bottom_radius = m.column_radius
	cm.top_radius = m.column_radius * COLUMN_TOP_SCALE
	cm.height = m.column_height + COLUMN_SINK
	cm.radial_segments = BURST_SEGMENTS
	cm.rings = 1
	var col := MeshInstance3D.new()
	col.mesh = cm
	col.material_override = hot
	col.position = Vector3.UP * ((m.column_height - COLUMN_SINK) * 0.5)
	uv.column.add_child(col)
	var blob := MeshInstance3D.new()
	var bm := SphereMesh.new()
	bm.radius = m.column_radius * COLUMN_BLOB_SCALE
	bm.height = m.column_radius * COLUMN_BLOB_SCALE * 2.0
	bm.radial_segments = BURST_SEGMENTS
	bm.rings = BURST_SEGMENTS / 2
	blob.mesh = bm
	var bright := hot.duplicate() as StandardMaterial3D
	bright.albedo_color = m.vent_hot_color
	bright.emission = m.vent_hot_color
	blob.material_override = bright
	blob.position = Vector3.UP * m.column_height
	uv.column.add_child(blob)
	uv.column.visible = false
	_bursts.append(uv)


# The ore cart stands on its rails in its lane, lined up with the rail (it is the same both ways
# round, so it never turns), wheels turning by the distance it has gone over their radius.
func _place_cart(cv: CartView, t: float) -> void:
	var m: TrackMover = cv.mover
	var d: float = _hazards.distance_at(m, t)
	var pose: Vector3 = _hazards.pose_at(m, t)
	var tn: Vector2 = cv.road.tangent_at(d)
	var fwd := Vector3(tn.x, 0.0, tn.y)
	var side: Vector3 = Vector3.UP.cross(fwd).normalized()
	cv.body.transform = Transform3D(Basis(side, Vector3.UP, fwd), pose)
	var turn: float = (d - m.path_from) / maxf(m.wheel_radius, HazardManager.EPSILON)
	for w in cv.wheels:
		w.basis = Basis(Vector3.RIGHT, turn) * Basis(Vector3.BACK, PI * 0.5)


func _build_cart(road: TrackModel.Path, m: TrackMover) -> void:
	var cv := CartView.new()
	cv.mover = m
	cv.road = road
	cv.body = Node3D.new()
	add_child(cv.body)
	var wood := _flat(m.body_color)
	var iron := _flat(m.band_color)
	var ore := _flat(m.ore_color)
	var floor_y: float = m.wheel_radius * 2.0
	# Local X across the rail, Y up, Z along it.
	_add_box(cv.body, Transform3D(Basis.IDENTITY, Vector3.UP * (floor_y + m.cart_height * 0.5)),
			Vector3(m.cart_width, m.cart_height, m.cart_length), wood)
	for at in CART_BAND_AT:
		_add_box(cv.body, Transform3D(Basis.IDENTITY, Vector3(0.0, floor_y + m.cart_height * 0.5, m.cart_length * at)),
				Vector3(m.cart_width + CART_BAND_SIZE, m.cart_height + CART_BAND_SIZE, CART_BAND_SIZE * 2.0), iron)
	# The ore heaped above the rim: a low wide box turned 45 degrees under a smaller ridge.
	var top: float = floor_y + m.cart_height
	_add_box(cv.body, Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3.UP * (top + CART_ORE_HEIGHT * 0.25)),
			Vector3(m.cart_width * 0.7, CART_ORE_HEIGHT * 0.5, m.cart_width * 0.7), ore)
	_add_box(cv.body, Transform3D(Basis.IDENTITY, Vector3.UP * (top + CART_ORE_HEIGHT * 0.5)),
			Vector3(m.cart_width * 0.5, CART_ORE_HEIGHT * 0.5, m.cart_length * 0.45), ore)
	for zs in [-1.0, 1.0]:
		for xs in [-1.0, 1.0]:
			var w := Node3D.new()
			w.position = Vector3(xs * m.cart_width * 0.5, m.wheel_radius, zs * (m.cart_length * 0.5 - CART_WHEEL_INSET))
			cv.body.add_child(w)
			var mi := MeshInstance3D.new()
			var wm := CylinderMesh.new()
			wm.top_radius = m.wheel_radius
			wm.bottom_radius = m.wheel_radius
			wm.height = CART_WHEEL_WIDTH
			wm.radial_segments = CART_WHEEL_SEGMENTS
			wm.rings = 1
			mi.mesh = wm
			mi.material_override = iron
			w.add_child(mi)
			cv.wheels.append(w)
	_carts.append(cv)


func _cylinder(radius: float, length: float, mat: StandardMaterial3D, at: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = length
	cm.radial_segments = BARREL_SEGMENTS
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = mat
	mi.position = Vector3.UP * at
	return mi


# The portcullis: two stone pillars beside the passage walls with a lintel above, the iron grille
# between them (it slides up by lift_height), and a lantern on the approach face of each pillar.
func _build_portcullis(track: TrackModel, m: TrackMover) -> void:
	var bi: int = track.branch_index(m.path)
	if bi < 0:
		return
	var road: TrackModel.Path = track.branches[bi]
	var line: float = (m.path_from + m.path_to) * 0.5
	var st: Vector2 = road.seg_t_at(line)
	var p: Vector2 = road.point_at(line)
	var tn: Vector2 = road.tangent_at(line)
	var y: float = road.height_at(int(st.x), st.y)
	var t3 := Vector3(tn.x, 0.0, tn.y)
	var n3 := Vector3(-tn.y, 0.0, tn.x)
	var basis := Basis(n3, Vector3.UP, n3.cross(Vector3.UP))
	var half: float = road.wall_offset
	var top: float = m.lift_height + m.grille_height + LINTEL_HEIGHT
	var pv := PortcullisView.new()
	pv.mover = m
	pv.base = Vector3(p.x, y, p.y)
	var stone := _flat(m.frame_color)
	for side in [1.0, -1.0]:
		var c: Vector3 = pv.base + n3 * side * (half + PILLAR_SIZE * 0.5)
		_add_box(self, Transform3D(basis, c + Vector3.UP * top * 0.5), Vector3(PILLAR_SIZE, top, PILLAR_SIZE), stone)
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
		lamp.position = c - t3 * (PILLAR_SIZE + LANTERN_SIZE) * 0.5 + Vector3.UP * m.signal_height
		add_child(lamp)
		pv.lantern_mat.append(mat)
	_add_box(self, Transform3D(basis, pv.base + Vector3.UP * (top - LINTEL_HEIGHT * 0.5)),
			Vector3((half + PILLAR_SIZE) * 2.0, LINTEL_HEIGHT, PILLAR_SIZE), stone)
	pv.grille = Node3D.new()
	pv.grille.position = pv.base
	add_child(pv.grille)
	var iron := _flat(m.grille_color)
	var bars: int = maxi(int(half * 2.0 / maxf(m.bar_spacing, HazardManager.EPSILON)), 1)
	for k in bars + 1:
		var x: float = lerpf(-half, half, float(k) / float(bars))
		_add_box(pv.grille, Transform3D(basis, n3 * x + Vector3.UP * m.grille_height * 0.5),
				Vector3(m.bar_size, m.grille_height, m.bar_size), iron)
	for k in GRILLE_RAILS:
		var h: float = m.grille_height * (float(k) + 0.5) / float(GRILLE_RAILS)
		_add_box(pv.grille, Transform3D(basis, Vector3.UP * h), Vector3(half * 2.0, m.bar_size, m.bar_size), iron)
	_portcullises.append(pv)


func _add_box(parent: Node3D, xf: Transform3D, size: Vector3, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.transform = xf
	parent.add_child(mi)


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
