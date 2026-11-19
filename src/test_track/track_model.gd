class_name TrackModel
extends RefCounted
## Geometry of a looping track built from TrackData: centerline samples, distance along
## the loop, nearest-point queries and wall offset. Pure math, no nodes.
## Implements design/game-brief.md, Features item 1 (test loop with walls by clamping).

## Spacing (meters) used to estimate the tangent at a distance.
const TANGENT_STEP: float = 1.0

## Result of [method query].
class Query extends RefCounted:
	## Index of the centerline segment the point is nearest to.
	var segment: int = 0
	## Distance along the centerline.
	var s: float = 0.0
	## Signed sideways offset from the centerline (left positive).
	var lateral: float = 0.0
	var tangent: Vector2 = Vector2.ZERO
	## Left-pointing unit normal.
	var normal: Vector2 = Vector2.ZERO

var data: TrackData
## Centerline samples as (x, z).
var points: PackedVector2Array = PackedVector2Array()
## Cumulative distance at each sample; one extra entry holds the full length.
var cumulative: PackedFloat32Array = PackedFloat32Array()
## Total loop length in meters.
var length: float = 0.0
## Distance from the centerline to the wall.
var wall_offset: float = 0.0


func _init(track_data: TrackData) -> void:
	data = track_data
	wall_offset = data.road_half_width + data.curb_width
	var ctrl: PackedVector2Array = data.control_points
	var n: int = ctrl.size()
	for i in n:
		var p0: Vector2 = ctrl[(i - 1 + n) % n]
		var p1: Vector2 = ctrl[i]
		var p2: Vector2 = ctrl[(i + 1) % n]
		var p3: Vector2 = ctrl[(i + 2) % n]
		for k in data.samples_per_segment:
			points.append(_catmull_rom(p0, p1, p2, p3, float(k) / data.samples_per_segment))
	cumulative.resize(points.size() + 1)
	cumulative[0] = 0.0
	for i in points.size():
		cumulative[i + 1] = cumulative[i] + points[i].distance_to(points[(i + 1) % points.size()])
	length = cumulative[points.size()]


## Nearest centerline info for [param p]. Searches near [param hint] (a previous segment
## index) or the whole loop when [param hint] is negative.
func query(p: Vector2, hint: int) -> Query:
	var n: int = points.size()
	var best_i: int = maxi(hint, 0)
	var best_d: float = INF
	var best_t: float = 0.0
	var window: int = data.query_window if hint >= 0 else n
	var start: int = hint if hint >= 0 else 0
	for o in range(-window, window + 1):
		var i: int = posmod(start + o, n)
		var a: Vector2 = points[i]
		var ab: Vector2 = points[(i + 1) % n] - a
		var t: float = clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var d: float = p.distance_squared_to(a + ab * t)
		if d < best_d:
			best_d = d
			best_i = i
			best_t = t
	var a2: Vector2 = points[best_i]
	var b2: Vector2 = points[(best_i + 1) % n]
	var q := Query.new()
	q.segment = best_i
	q.tangent = (b2 - a2).normalized()
	q.normal = Vector2(-q.tangent.y, q.tangent.x)
	q.s = cumulative[best_i] + a2.distance_to(b2) * best_t
	q.lateral = (p - a2.lerp(b2, best_t)).dot(q.normal)
	return q


## Point on the centerline at [param dist] meters (wraps around the loop).
func point_at(dist: float) -> Vector2:
	var sv: float = fposmod(dist, length)
	var lo: int = 0
	var hi: int = points.size() - 1
	while lo < hi:
		var mid: int = (lo + hi + 1) >> 1
		if cumulative[mid] <= sv:
			lo = mid
		else:
			hi = mid - 1
	var a: Vector2 = points[lo]
	var b: Vector2 = points[(lo + 1) % points.size()]
	return a.lerp(b, (sv - cumulative[lo]) / (cumulative[lo + 1] - cumulative[lo]))


## Unit direction of travel at [param dist].
func tangent_at(dist: float) -> Vector2:
	return (point_at(dist + TANGENT_STEP) - point_at(dist - TANGENT_STEP)).normalized()


## Left-pointing unit normal at [param dist].
func normal_at(dist: float) -> Vector2:
	var t: Vector2 = tangent_at(dist)
	return Vector2(-t.y, t.x)


func _catmull_rom(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2: float = t * t
	var t3: float = t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
			+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)
