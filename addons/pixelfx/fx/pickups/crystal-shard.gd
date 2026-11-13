# The crystal shading (a lit ridge, bright faces turned to the light, a dark rim) and the orbiting motes
# follow Sprite Fusion's open-source ice crystals and pickup (https://www.spritefusion.com/pixel-art-vfx/ice),
# MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/pickups/crystal-shard.js@71f91a951640f64a9c3b5eaaf007572ac482984c
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Crystal shard",
	"desc": "A broken amber shard hovers and sways: chipped uneven faces, its top sheared off, light pulsing up through glowing cracks and flaring out of the break; splinters orbit it.",
	"tags": ["pickup", "crystal", "shard", "relic", "broken", "loop"],
	"size": [64, 76],
	"origin": [32, 68],
	"duration": 3.2,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": ["#1a0a04", "#3e1606", "#702a08", "#a8480c", "#e07818", "#ffa838", "#ffd890", "#ffffff"], "seed": 8},
}

const HALF := 6.0
const TILT := 0.18
const LEAN := 0.2


static func roll(v: Array) -> Array:
	var x: float = v[0]
	var y: float = v[1]
	var z: float = v[2]
	return [x * cos(LEAN) - y * sin(LEAN), x * sin(LEAN) + y * cos(LEAN), z]


static func unit(x: float, y: float, z: float) -> Array:
	var l := Px.hypot(x, y, z)
	return [x / l, y / l, z / l]


# the broken shard as a convex solid: an uneven six-sided body, a point on top sheared off on one side by a
# fracture, a lopsided point below, two corners chipped away
static func _solid() -> Dictionary:
	var planes := []
	var deg := PI / 180.0
	var jit := [0.0, 8.0, -6.0, 4.0, -9.0, 5.0]
	var rr := [1.0, 0.86, 1.08, 0.94, 0.82, 1.04]
	var low := [6.5, 5.5, 7.0, 6.0, 5.0, 6.8]
	for k in 6:
		var a: float = (k * 60.0 + jit[k]) * deg
		var r: float = 4.8 * rr[k]
		var ct := atan2(13.0, r)
		var cb := atan2(low[k], r)
		planes.append({"n": [cos(a), 0.0, sin(a)], "d": r, "kind": 6})
		planes.append({"n": [sin(ct) * cos(a), cos(ct), sin(ct) * sin(a)], "d": sin(ct) * r + cos(ct) * HALF, "kind": 7})
		planes.append({"n": [sin(cb) * cos(a), -cos(cb), sin(cb) * sin(a)], "d": sin(cb) * r + cos(cb) * HALF, "kind": 8})
	var shear := unit(0.7, 0.62, 0.34)
	planes.append({"n": shear, "d": shear[1] * 7.2 + shear[0] * -0.6, "kind": 9})
	for nd: Array in [[unit(-0.7, -0.25, 0.65), 4.0], [unit(0.75, 0.15, 0.6), 3.9], [unit(-0.55, 0.5, 0.3), 6.8]]:
		planes.append({"n": nd[0], "d": nd[1], "kind": 10})
	# the whole shard leans off upright
	for q: Dictionary in planes:
		q.n = roll(q.n)
	return {"planes": planes, "r": 8.0, "top": HALF + 13.0, "bottom": HALF + 8.0}

static var SOLID := _solid()
# cracks running through it, in its own frame (y up): they turn with it
const CRACKS := [
	[[0.5, -9.0, 0.3], [-0.8, -5.0, 0.5], [0.6, -1.0, 0.2], [-0.4, 3.0, 0.6], [1.4, 6.5, 0.4], [2.2, 8.5, 0.6]],
	[[0.6, -1.0, 0.2], [2.4, 1.5, 1.0], [3.4, 4.2, 1.2]],
	[[-0.4, 3.0, 0.6], [-2.0, 6.5, 0.4], [-2.6, 10.5, 0.2], [-2.4, 14.5, 0.1]],
	[[-0.8, -5.0, 0.5], [-2.8, -3.0, 0.8]],
]
static var L := Lib.Layer.new(32, 52)
static var SL := Lib.Layer.new(16, 16)
const HOVER := 27.0
const RX := 15.0
const RY := 3.8


static func pose(ph: float) -> Dictionary:
	return {"y": -HOVER - 1.8 * sin(ph * TAU), "spin": 0.3 + 0.62 * sin(ph * TAU)}


# a pulse of light climbing the cracks, twice a loop: where it is, from below the shard (-0.3) to past its top
static func climb(ph: float) -> float:
	return fmod(ph * 2.0, 1.0) * 1.7 - 0.3


# where a point of the shard lands on screen, turned by spin and seen from a little above
static func project(pt: Array, spin: float, cy: float) -> Array:
	var v := roll(pt)
	var x: float = v[0]
	var y: float = v[1]
	var z: float = v[2]
	var xr := x * cos(spin) - z * sin(spin)
	var zr := x * sin(spin) + z * cos(spin)
	return [xr, cy - (y * cos(TILT) - zr * sin(TILT))]


static func cracks(p: Px.Painter, C: Array, spin: float, cy: float, ph: float) -> void:
	var s0 := climb(ph)
	var rim := Px.u32(C[0])
	for crack: Array in CRACKS:
		for i in range(1, crack.size()):
			var a := project(crack[i - 1], spin, cy)
			var b := project(crack[i], spin, cy)
			var x0: float = a[0]
			var y0: float = a[1]
			var x1: float = b[0]
			var y1: float = b[1]
			var n := ceilf(Px.hypot(x1 - x0, y1 - y0) * 2.0)
			for j in int(n) + 1:
				var u := j / n
				var x := x0 + (x1 - x0) * u
				var y := y0 + (y1 - y0) * u
				var h: float = crack[i - 1][1] + (crack[i][1] - crack[i - 1][1]) * u
				var c := L.getc(x, y)
				if not c or c == rim:
					continue
				# light runs up the crack: brightest where the pulse is
				var bb := 0.3 + Px.exp(-pow(((h + 9.0) / 22.0 - s0) / 0.14, 2))
				p.px(x, y, WHITE if bb > 0.9 else (C[6] if bb > 0.55 else C[5]))
				if j % 4 == 0 and bb > 0.5:
					p.glow(x + 0.5, y + 0.5, 2.0 + 3.0 * bb, C[5], 0.16 * bb)


# a splinter: a little two-tone sliver with a dark rim, turned to angle a
static func splinter(p: Px.Painter, C: Array, x: float, y: float, len: float, a: float, far: bool) -> void:
	var ca := cos(a)
	var sa := sin(a)
	var X := Px.round(x)
	var Y := Px.round(y)
	SL.begin(X - 7.0, Y - 7.0)
	SL.fill(X - 7.0, Y - 7.0, X + 6.0, Y + 6.0, func(px: float, py: float) -> Variant:
		var dx := px - X
		var dy := py - Y
		var u := dx * ca + dy * sa
		var v := -dx * sa + dy * ca
		if absf(u) / len + absf(v) / (1.7 if u > 0.0 else 1.1) > 1.0:
			return 0
		var lit := -(ca * 0.6 + sa * 0.8) * Px.sign(v if v else 1.0)
		return (C[4] if v < 0.0 else C[3]) if far else (WHITE if (absf(v) < 0.5 and u < 0.0) else (C[6] if (v < 0.0) == (lit > 0.0) else C[4])))
	SL.outline(C[1 if far else 0]).draw(p)


# the splinters on their tilted ring; back draws the far half, front the near half
static func splinters(p: Px.Painter, C: Array, ph: float, cy: float, back: bool) -> void:
	for i in 3:
		var a := ph * TAU + (i * TAU) / 3.0
		var s := sin(a)
		if (s < 0.0) != back:
			continue
		var x := cos(a) * RX
		var y := cy + 1.0 + s * RY - cos(a) * 1.5
		var near := (s + 1.0) / 2.0
		splinter(p, C, x, y, 3.0 + 1.6 * near, a * 2.0 + i * 1.7, back)
		p.glow(x, y, 6.0 + 3.0 * near, C[5], (0.18 if back else 0.32) * (0.6 + 0.4 * near))
		if not back and s > 0.92:
			Lib.glint(p, x - 1.0, y - 1.0, (2.5 * (s - 0.92)) / 0.08, WHITE, 0.4)


static func drawBack(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var D: float = meta.duration
	var ph := t / D
	var y: float = pose(ph).y
	Lib.blobShadow(p, 0.0, 6.0, 0.75)
	Lib.pool(p, 0.0, 0.5, 20.0, 3.5, C[4], 0.3)
	p.glowRing(0.0, y, 7.0, 20.0, C[4], 0.22)
	splinters(p, C, ph, y, true)


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var D: float = meta.duration
	var ph := t / D
	var ps := pose(ph)
	var y: float = ps.y
	var spin: float = ps.spin
	var s0 := climb(ph)
	Lib.drawGem(L, p, SOLID, 0.0, y, spin, C, {"tilt": TILT, "gain": 0.6})
	cracks(p, C, spin, y, ph)
	# lit from within, brighter while the pulse is inside it
	var inside := Px.exp(-pow((s0 - 0.45) / 0.45, 2))
	p.glow(0.0, y, 10.0, C[5], 0.2 * inside)
	splinters(p, C, ph, y, false)
	# when the pulse reaches the break it flares out of the sheared face and throws up embers
	var fxy := project([1.8, 8.4, 0.9], spin, y)
	var fx: float = fxy[0]
	var fy: float = fxy[1]
	var out := Px.clamp(1.0 - absf(s0 - 1.05) / 0.18)
	if out > 0.0:
		Lib.glint(p, fx, fy, 3.5 * out, WHITE, 0.55 * out)
		p.glow(fx, fy, 12.0, C[5], 0.4 * out)
	var P2 := D / 2.0
	var burst := ((1.05 + 0.3) / 1.7) * P2
	for i in 7:
		var born := burst + Px.rand(i, o.seed, 1) * 0.12
		var at := fmod(fmod(t - born, P2) + P2, P2)
		var life := 0.6 + Px.rand(i, o.seed, 2) * 0.45
		if at > life:
			continue
		var k := 1.0 - at / life
		var x := fx + (Px.rand(i, o.seed, 3) - 0.5) * 4.0 + sin(at * 5.0 + i) * 2.0 * (at / life)
		var yy := fy - at * (14.0 + Px.rand(i, o.seed, 4) * 14.0)
		p.px(x, yy, WHITE if k > 0.6 else (C[6] if k > 0.3 else C[5]))
		p.glow(x + 0.5, yy + 0.5, 3.0, C[5], 0.35 * k)
