## Scratch probe for ADR-0006 V1 (half floats, u24 position, smallest-three quaternion).
## PROTOTYPE - NOT FOR PRODUCTION. Run: godot --headless --path prototypes/collision-spike -s res://scripts/probe_adr6_codec.gd
extends SceneTree

const OUT: String = "res://out/probe_adr6_codec.txt"
const INV_SQRT2: float = 0.70710678118654752
var _lines: PackedStringArray = []


func _p(s: String) -> void:
	print(s)
	_lines.append(s)


func _half(v: float) -> float:
	var b := PackedByteArray()
	b.resize(2)
	b.encode_half(0, v)
	return b.decode_half(0)


func _half_bits(v: float) -> int:
	var b := PackedByteArray()
	b.resize(2)
	b.encode_half(0, v)
	return b.decode_u16(0)


func _initialize() -> void:
	_p("engine %s" % Engine.get_version_info().string)
	var pb := PackedByteArray([0, 0])
	_p("encode_half/decode_half: script parsed with static calls, so both exist (statically resolved on PackedByteArray)")
	_v1_half_specific()
	_v1_half_random()
	_v1_pos()
	_v1_quat()
	_v1_half_rne()
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string("\n".join(_lines) + "\n")
	f.close()
	quit()


func _v1_half_specific() -> void:
	_p("--- half: specific values (value -> bits -> decoded; RN-even expectation)")
	var cases: Array = [
		[1.0, "1.0"],
		[1.0 + pow(2, -11), "tie 1+2^-11 (RNE -> 1.0, 0x3C00)"],
		[1.0 + pow(2, -11) + pow(2, -20), "just above half ULP (RN -> 1+2^-10, 0x3C01; trunc -> 0x3C00)"],
		[1.0 + 3.0 * pow(2, -11), "tie 1+3*2^-11 (RNE -> 1+2^-9, 0x3C02; trunc -> 0x3C01)"],
		[1.0 + 0.9 * pow(2, -10), "1+0.9 ULP (RN -> 0x3C01; trunc -> 0x3C00)"],
		[33.3, "33.3"],
		[-33.3, "-33.3"],
		[65504.0, "max finite"],
		[65519.0, "65519 (RN -> 65504)"],
		[65520.0, "65520 (RN -> inf)"],
		[70000.0, "70000 (RN -> inf)"],
		[-70000.0, "-70000 (RN -> -inf)"],
		[1.0e6, "1e6"],
		[1.0e-5, "1e-5 subnormal"],
		[6.0e-8, "6e-8 ~ smallest subnormal"],
		[1.0e-9, "1e-9 underflow"],
		[-0.0, "-0.0"],
		[INF, "inf"],
		[-INF, "-inf"],
		[NAN, "nan"],
	]
	for c: Array in cases:
		var v: float = c[0]
		var bits: int = _half_bits(v)
		var d: float = _half(v)
		_p("  %-55s in=%.10f bits=0x%04X out=%.10f finite=%s" % [c[1], v, bits, d, is_finite(d)])


func _v1_half_random() -> void:
	_p("--- half: random round trip, 1e6 uniform samples in [-128, 128], seed 6")
	var rng := RandomNumberGenerator.new()
	rng.seed = 6
	var b := PackedByteArray()
	b.resize(2)
	var max_lo: float = 0.0  # |v| < 64
	var max_hi: float = 0.0  # 64 <= |v| < 128
	var max_rel: float = 0.0
	var sum_signed_mag: float = 0.0  # sum of (|out| - |in|): negative => toward zero
	var n: int = 1000000
	var toward_zero: int = 0
	var away: int = 0
	for i in n:
		var v: float = rng.randf_range(-128.0, 128.0)
		b.encode_half(0, v)
		var d: float = b.decode_half(0)
		var e: float = absf(d - v)
		if absf(v) < 64.0:
			max_lo = maxf(max_lo, e)
		else:
			max_hi = maxf(max_hi, e)
		if absf(v) > 1.0:
			max_rel = maxf(max_rel, e / absf(v))
		var dm: float = absf(d) - absf(v)
		sum_signed_mag += dm
		if dm < 0.0:
			toward_zero += 1
		elif dm > 0.0:
			away += 1
	_p("  max abs err |v|<64: %.6f m/s (ADR states <= 0.016; RN bound 2^-6=0.015625, trunc bound 2^-5=0.03125)" % max_lo)
	_p("  max abs err 64<=|v|<128: %.6f m/s (ADR states <= 0.031; RN bound 0.03125, trunc bound 0.0625)" % max_hi)
	_p("  max rel err (|v|>1): %.10f (RN bound 2^-11=%.10f, trunc bound 2^-10=%.10f)" % [max_rel, pow(2, -11), pow(2, -10)])
	_p("  mean (|out|-|in|): %.10f ; toward zero %d, away %d (RN ~ balanced, trunc all toward zero)" % [sum_signed_mag / n, toward_zero, away])


func _enc_pos(buf: PackedByteArray, off: int, p: float) -> bool:
	var q: int = roundi((p + 2048.0) * 4096.0)
	var clamped: bool = q < 0 or q > 16777215
	q = clampi(q, 0, 16777215)
	buf.encode_u16(off, q & 0xFFFF)
	buf.encode_u8(off + 2, (q >> 16) & 0xFF)
	return clamped


func _dec_pos(buf: PackedByteArray, off: int) -> float:
	var q: int = buf.decode_u16(off) | (buf.decode_u8(off + 2) << 16)
	return float(q) / 4096.0 - 2048.0


func _v1_pos() -> void:
	_p("--- position u24: 1e6 random float32 positions in [-2000, 2000] (through Vector3), seed 7")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var buf := PackedByteArray()
	buf.resize(3)
	var max_e: float = 0.0
	for i in 1000000:
		var v := Vector3(rng.randf_range(-2000.0, 2000.0), 0, 0)  # float32 storage
		_enc_pos(buf, 0, v.x)
		var o := Vector3(_dec_pos(buf, 0), 0, 0)
		max_e = maxf(max_e, absf(o.x - v.x))
	_p("  max err %.10f m (ADR 0.122 mm = %.10f; 2^-13)" % [max_e, pow(2, -13)])
	for p: float in [-2048.0, -2000.0, 0.0, 1999.9999, 2047.9997, 2048.0, 2100.0, -2100.0]:
		var v := Vector3(p, 0, 0)
		var c: bool = _enc_pos(buf, 0, v.x)
		var o := Vector3(_dec_pos(buf, 0), 0, 0)
		_p("  edge in=%.7f out=%.7f clamped=%s" % [v.x, o.x, c])
	var f32 := PackedFloat32Array([2000.0])
	var bb := f32.to_byte_array()
	var bits: int = bb.decode_u32(0)
	bb.encode_u32(0, bits + 1)
	_p("  float32 ULP at 2000 m = %.10f (2^-13 = %.10f; ADR text says 2^-12)" % [bb.decode_float(0) - 2000.0, pow(2, -13)])


func _canon(q: Quaternion) -> Quaternion:
	return -q if q.w < 0.0 else q


func _enc_rot(b: Basis) -> int:
	var q: Quaternion = _canon(b.orthonormalized().get_rotation_quaternion().normalized())
	var c: Array[float] = [q.x, q.y, q.z, q.w]
	var big: int = 0
	for i in range(1, 4):
		if absf(c[i]) > absf(c[big]):
			big = i
	var s: float = -1.0 if c[big] < 0.0 else 1.0
	var bits: int = big << 30
	var shift: int = 20
	for i in 4:
		if i == big:
			continue
		var v: float = c[i] * s
		var k: int = clampi(roundi((v + INV_SQRT2) / (2.0 * INV_SQRT2) * 1023.0), 0, 1023)
		bits |= k << shift
		shift -= 10
	return bits


func _dec_rot(bits: int) -> Quaternion:
	var big: int = (bits >> 30) & 3
	var c: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var shift: int = 20
	var ss: float = 0.0
	for i in 4:
		if i == big:
			continue
		var k: int = (bits >> shift) & 1023
		var v: float = float(k) / 1023.0 * (2.0 * INV_SQRT2) - INV_SQRT2
		c[i] = v
		ss += v * v
		shift -= 10
	c[big] = sqrt(maxf(0.0, 1.0 - ss))
	return _canon(Quaternion(c[0], c[1], c[2], c[3]).normalized())


func _ang(a: Quaternion, b: Quaternion) -> float:
	var d: Quaternion = a.inverse() * b
	return 2.0 * atan2(Vector3(d.x, d.y, d.z).length(), absf(d.w))


func _rand_q(rng: RandomNumberGenerator) -> Quaternion:
	return Quaternion(rng.randfn(), rng.randfn(), rng.randfn(), rng.randfn()).normalized()


func _v1_quat() -> void:
	_p("--- smallest-three 2+3x10 bits: random uniform rotations, 300k, seed 8")
	var rng := RandomNumberGenerator.new()
	rng.seed = 8
	var max_a: float = 0.0
	var sum_a: float = 0.0
	var neg_w: int = 0
	var worst := Quaternion()
	var n: int = 300000
	for i in n:
		var q: Quaternion = _rand_q(rng)
		var bits: int = _enc_rot(Basis(q))
		var o: Quaternion = _dec_rot(bits)
		if o.w < 0.0:
			neg_w += 1
		var a: float = _ang(q, o)
		sum_a += a
		if a > max_a:
			max_a = a
			worst = _canon(q)
	_p("  max %.4f deg, mean %.4f deg, decoded w<0: %d (ADR states ~0.14 deg, test asserts < 0.2 deg)" % [rad_to_deg(max_a), rad_to_deg(sum_a / n), neg_w])
	_p("  worst input %s" % worst)
	_p("--- adversarial: 300k rotations near q=(.5,.5,.5,.5)-type corners (dropped component ~0.5), seed 9")
	rng.seed = 9
	var max_b: float = 0.0
	var worst_b := Quaternion()
	for i in 300000:
		var base := Quaternion(0.5 * (1 if rng.randi() & 1 else -1), 0.5 * (1 if rng.randi() & 1 else -1),
				0.5 * (1 if rng.randi() & 1 else -1), 0.5)
		var q := Quaternion(base.x + rng.randf_range(-0.01, 0.01), base.y + rng.randf_range(-0.01, 0.01),
				base.z + rng.randf_range(-0.01, 0.01), base.w + rng.randf_range(-0.01, 0.01)).normalized()
		var o: Quaternion = _dec_rot(_enc_rot(Basis(q)))
		var a: float = _ang(q, o)
		if a > max_b:
			max_b = a
			worst_b = q
	_p("  max %.4f deg; worst input %s" % [rad_to_deg(max_b), worst_b])
	var e: float = sqrt(2.0) / 1023.0 / 2.0
	_p("  analytic: half-step e=%.8f; ADR formula 2*asin(sqrt3*e)=%.4f deg; corner case 2*asin(sqrt12*e)=%.4f deg" % [
			e, rad_to_deg(2.0 * asin(sqrt(3.0) * e)), rad_to_deg(2.0 * asin(sqrt(12.0) * e))])
	_p("  at 1 m half-length: %.2f mm (random max), %.2f mm (adversarial max)" % [max_a * 1000.0, max_b * 1000.0])


## Candidate fix: pre-round the float32 bits to 10 mantissa bits (RNE), clamp to +-65504, then let
## the truncating encode_half drop the low 13 bits.
func _half_rne(buf: PackedByteArray, off: int, v: float) -> void:
	var f := PackedByteArray()
	f.resize(4)
	f.encode_float(0, clampf(v, -65504.0, 65504.0))
	var b: int = f.decode_u32(0)
	b = (b + 0x0FFF + ((b >> 13) & 1)) & 0xFFFFFFFF
	f.encode_u32(0, b)
	buf.encode_half(off, clampf(f.decode_float(0), -65504.0, 65504.0))


func _v1_half_rne() -> void:
	_p("--- candidate fix _half_rne (pre-round + clamp): same 1e6 samples, seed 6")
	var rng := RandomNumberGenerator.new()
	rng.seed = 6
	var b := PackedByteArray()
	b.resize(2)
	var max_lo: float = 0.0
	var max_hi: float = 0.0
	var sum_dm: float = 0.0
	for i in 1000000:
		var v: float = rng.randf_range(-128.0, 128.0)
		_half_rne(b, 0, v)
		var d: float = b.decode_half(0)
		var e: float = absf(d - v)
		if absf(v) < 64.0:
			max_lo = maxf(max_lo, e)
		else:
			max_hi = maxf(max_hi, e)
		sum_dm += absf(d) - absf(v)
	_p("  max abs err |v|<64: %.6f, 64-128: %.6f, mean (|out|-|in|): %.10f" % [max_lo, max_hi, sum_dm / 1000000.0])
	for v: float in [1.0 + pow(2, -11), 1.0 + pow(2, -11) + pow(2, -20), 1.0 + 3.0 * pow(2, -11), 65519.0, 70000.0, -1.0e6]:
		_half_rne(b, 0, v)
		_p("  in=%.10f bits=0x%04X out=%.10f" % [v, b.decode_u16(0), b.decode_half(0)])
