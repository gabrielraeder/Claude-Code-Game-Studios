class_name TrackScenery
extends Node3D
## Props around a track, chosen by TrackTheme.style: for "castle" banners on poles, stone
## towers with cone roofs, a keep, village houses, a start banner arch, branch arches and
## item-box markers. Repeated props are batched with MultiMesh so a race stays cheap.
## Presentation only. A second theme (Dungeon Depths) adds its own style here.
## Implements design/game-brief.md, "Look and references".

const BOX_CLEARANCE: float = 1.5


## Builds the props for [param track] as children of this node.
func build(track: TrackModel) -> void:
	var th: TrackTheme = track.theme
	if th.style == &"castle":
		_build_castle(track, th)
	_build_item_boxes(track, th)


func _build_castle(track: TrackModel, th: TrackTheme) -> void:
	var box_x: Array[Transform3D] = []
	var box_c: Array[Color] = []
	var cyl_x: Array[Transform3D] = []
	var cyl_c: Array[Color] = []
	var cone_x: Array[Transform3D] = []
	var cone_c: Array[Color] = []
	var pyr_x: Array[Transform3D] = []
	var pyr_c: Array[Color] = []

	# Banners on poles along the main road, outside every corridor.
	var pole_x: Array[Transform3D] = []
	var pole_c: Array[Color] = []
	var flag_x: Array[Transform3D] = []
	var flag_c: Array[Color] = []
	var count: int = int(track.length / th.banner_spacing)
	for k in count:
		var s: float = (float(k) + 0.5) * track.length / float(count)
		var t: Vector2 = track.tangent_at(s)
		for side in [1.0, -1.0]:
			var p: Vector2 = track.point_at(s) + track.normal_at(s) * side \
					* (track.wall_offset + th.banner_distance_from_wall)
			if track.excess_at(p) < BOX_CLEARANCE:
				continue
			pole_x.append(Transform3D(_basis_along(t, Vector3(0.3, th.banner_height, 0.3)),
					Vector3(p.x, th.banner_height * 0.5, p.y)))
			pole_c.append(th.banner_pole_color)
			flag_x.append(Transform3D(_basis_along(t, Vector3(1.8, 3.0, 0.08)),
					Vector3(p.x, th.banner_height - 1.7, p.y) - Vector3(t.x, 0.0, t.y) * 1.0))
			flag_c.append(th.banner_color_a if k % 2 == 0 else th.banner_color_b)
	_batch(_unit_box(), pole_x, pole_c)
	_batch(_unit_box(), flag_x, flag_c)

	# Keep: body, top block and four corner towers.
	var kc: Vector2 = th.keep_center
	var ks: Vector3 = th.keep_size
	if kc != Vector2.ZERO:
		box_x.append(Transform3D(Basis.from_scale(ks), Vector3(kc.x, ks.y * 0.5, kc.y)))
		box_c.append(th.tower_color)
		var top: Vector3 = Vector3(ks.x * 0.72, 4.0, ks.z * 0.72)
		box_x.append(Transform3D(Basis.from_scale(top), Vector3(kc.x, ks.y + 2.0, kc.y)))
		box_c.append(th.tower_color.lightened(0.15))
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				_tower(Vector2(kc.x + sx * ks.x * 0.5, kc.y + sz * ks.z * 0.5), th, 1.0,
						cyl_x, cyl_c, cone_x, cone_c)
		_tower(kc, th, 0.0, cyl_x, cyl_c, cone_x, cone_c, ks.y + 4.0)
	for p in th.tower_positions:
		_tower(p, th, 1.0, cyl_x, cyl_c, cone_x, cone_c)
	for p in th.gate_tower_positions:
		_tower(p, th, 1.25, cyl_x, cyl_c, cone_x, cone_c)

	# Village houses: cream walls, red-orange pyramid roofs.
	var hs: Vector3 = th.house_size
	for p in th.house_positions:
		box_x.append(Transform3D(Basis.from_scale(hs), Vector3(p.x, hs.y * 0.5, p.y)))
		box_c.append(th.house_wall_color)
		pyr_x.append(Transform3D(Basis(Vector3.UP, PI * 0.25).scaled(Vector3(hs.x * 0.85, hs.y * 0.7, hs.z * 1.2)),
				Vector3(p.x, hs.y + hs.y * 0.35, p.y)))
		pyr_c.append(th.house_roof_color)

	# Start banner arch over the line at s = 0.
	var p0: Vector2 = track.point_at(0.0)
	var t0: Vector2 = track.tangent_at(0.0)
	var n0: Vector2 = track.normal_at(0.0)
	var reach: float = track.wall_offset + 0.8
	for side in [1.0, -1.0]:
		var pp: Vector2 = p0 + n0 * side * reach
		box_x.append(Transform3D(_basis_along(t0, Vector3(1.2, 9.0, 1.2)), Vector3(pp.x, 4.5, pp.y)))
		box_c.append(th.start_arch_color)
	box_x.append(Transform3D(_basis_along(t0, Vector3(reach * 2.0 + 1.2, 1.6, 1.0)), Vector3(p0.x, 9.0, p0.y)))
	box_c.append(th.banner_color_b)
	box_x.append(Transform3D(_basis_along(t0, Vector3(reach * 1.4, 2.6, 0.1)),
			Vector3(p0.x, 7.0, p0.y) - Vector3(t0.x, 0.0, t0.y) * 0.6))
	box_c.append(th.banner_color_a)

	# Arches at the ends of branches that ask for them.
	for bi in track.branches.size():
		var b: TrackBranch = track.data.branches[bi]
		if not b.arch_ends:
			continue
		var path: TrackModel.Path = track.branches[bi]
		for end in [0, 1]:
			var d: float = _arch_distance(track, path, end == 1)
			var ap: Vector2 = path.point_at(d)
			var at: Vector2 = path.tangent_at(d)
			var an: Vector2 = Vector2(-at.y, at.x)
			var gap: float = path.wall_offset + 0.9
			for side in [1.0, -1.0]:
				var pp2: Vector2 = ap + an * side * gap
				box_x.append(Transform3D(_basis_along(at, Vector3(1.8, b.wall_height + 1.6, 1.8)),
						Vector3(pp2.x, (b.wall_height + 1.6) * 0.5, pp2.y)))
				box_c.append(th.arch_color)
			box_x.append(Transform3D(_basis_along(at, Vector3(gap * 2.0 + 1.8, 1.4, 1.8)),
					Vector3(ap.x, b.wall_height + 1.6 + 0.3, ap.y)))
			box_c.append(th.arch_color.darkened(0.1))

	_batch(_unit_box(), box_x, box_c)
	_batch(_unit_cylinder(1.0), cyl_x, cyl_c)
	_batch(_unit_cylinder(0.0), cone_x, cone_c)
	_batch(_unit_pyramid(), pyr_x, pyr_c)


# A tower: cylinder plus cone roof. [param scale] multiplies radius and roof; [param base_y]
# lifts it (a turret on the keep).
func _tower(p: Vector2, th: TrackTheme, scale: float, cyl_x: Array[Transform3D], cyl_c: Array[Color],
		cone_x: Array[Transform3D], cone_c: Array[Color], base_y: float = 0.0) -> void:
	var sc: float = scale if scale > 0.0 else 0.6
	var r: float = th.tower_radius * sc
	var h: float = th.tower_height * (sc if base_y == 0.0 else 0.4)
	cyl_x.append(Transform3D(Basis.from_scale(Vector3(r, h, r)), Vector3(p.x, base_y + h * 0.5, p.y)))
	cyl_c.append(th.tower_color)
	var rh: float = th.roof_height * sc
	cone_x.append(Transform3D(Basis.from_scale(Vector3(r * 1.3, rh, r * 1.3)),
			Vector3(p.x, base_y + h + rh * 0.5, p.y)))
	cone_c.append(th.roof_color)


# Distance along a branch where it has left the main corridor (start or end side).
func _arch_distance(track: TrackModel, path: TrackModel.Path, from_end: bool) -> float:
	var step: float = 1.0
	var d: float = path.length if from_end else 0.0
	var dir: float = -1.0 if from_end else 1.0
	while d > 0.0 and d < path.length:
		if track.distance_to_path(path.point_at(d), TrackModel.MAIN_PATH) > track.wall_offset + 2.5:
			break
		d += dir * step
	return clampf(d, 0.0, path.length)


func _build_item_boxes(track: TrackModel, th: TrackTheme) -> void:
	var xs: Array[Transform3D] = []
	var cs: Array[Color] = []
	for i in track.data.item_box_spots.size():
		var p: Vector2 = track.item_box_position(i)
		var sz: float = th.item_box_size
		xs.append(Transform3D(Basis(Vector3.UP, PI * 0.25).scaled(Vector3(sz, sz, sz)), Vector3(p.x, sz * 0.9, p.y)))
		cs.append(th.item_box_color)
	_batch(_unit_box(), xs, cs)


# Basis whose local z axis follows [param t] (x, z plane), scaled by [param scale].
func _basis_along(t: Vector2, scale: Vector3) -> Basis:
	var zaxis := Vector3(t.x, 0.0, t.y)
	var xaxis := Vector3(-t.y, 0.0, t.x)
	return Basis(xaxis * scale.x, Vector3.UP * scale.y, zaxis * scale.z)


func _unit_box() -> Mesh:
	var m := BoxMesh.new()
	m.size = Vector3.ONE
	return m


func _unit_cylinder(top_radius: float) -> Mesh:
	var m := CylinderMesh.new()
	m.top_radius = top_radius
	m.bottom_radius = 1.0
	m.height = 1.0
	m.radial_segments = 12
	m.rings = 1
	return m


func _unit_pyramid() -> Mesh:
	var m := CylinderMesh.new()
	m.top_radius = 0.0
	m.bottom_radius = 0.7071
	m.height = 1.0
	m.radial_segments = 4
	m.rings = 1
	return m


# One MultiMeshInstance3D drawing [param mesh] at every transform, tinted per instance.
func _batch(mesh: Mesh, xforms: Array[Transform3D], colors: Array[Color]) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	# Vertex colors are authored in sRGB (like every Color in the theme data).
	mat.vertex_color_is_srgb = true
	mmi.material_override = mat
	add_child(mmi)
