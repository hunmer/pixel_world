# The banded light (posterized steps from a hot core to the edges, fine strands through it, light laid over the top)
# is adapted from Sprite Fusion's open-source holy light (https://www.spritefusion.com/pixel-art-vfx/holy-light),
# MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/weather/god-rays.js@5902f1d614ec621a4516cf3bccfa5d1a8ecb3c5a
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")

static var meta := {
	"name": "God rays",
	"desc": "Shafts of light slant down from high on the left, breathing and swaying, pooling on the floor, as drifting dust motes light up whenever they cross a beam.",
	"tags": ["weather", "god rays", "light", "sunbeam", "dust", "ambient", "loop"],
	"size": [320, 180],
	"origin": [160, 170],
	"duration": 10.0,
	"loop": true,
	"fps": 30,
	"bg": "sky",
	"options": {
		"palette": ["#1a1208", "#3a2810", "#7a5a24", "#c89a44", "#f2d27a", "#fff2c4", "#ffffff"],
		"seed": 3,
	},
}

const D := 10.0
const W := 320
const SX := -230.0
const SY := -300.0
# the fan's axis (down and to the right) and its normal; a pixel's place across the fan is its angle from it
static var AX := cos(0.94)
static var AY := sin(0.94)
static var NX := -AY
static var NY := AX
# the shafts: angle off the axis, half width (radians), strength, breathing (cycles a loop), sway
const SHAFTS := [
	{"c": -0.27, "h": 0.03, "k": 0.65, "b": 1.0, "sw": 0.006},
	{"c": -0.17, "h": 0.022, "k": 0.55, "b": 2.0, "sw": 0.005},
	{"c": -0.07, "h": 0.05, "k": 1.0, "b": 1.0, "sw": 0.008},
	{"c": 0.03, "h": 0.018, "k": 0.6, "b": 3.0, "sw": 0.004},
	{"c": 0.12, "h": 0.042, "k": 0.85, "b": 2.0, "sw": 0.007},
	{"c": 0.23, "h": 0.026, "k": 0.6, "b": 1.0, "sw": 0.005},
]
static var STR := _f32(512)


static func _f32(n: int) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(n)
	return a


# light at a point: the shafts it's in, softened at their edges, fading with distance, threaded with strands
static func lightAt(x: float, y: float, sh: Array) -> float:
	var dx := x - SX
	var dy := y - SY
	var r := dx * AX + dy * AY
	var ang := (dx * NX + dy * NY) / r
	var e := 0.0
	for s: Dictionary in sh:
		var q: float = absf(ang - s.c) / s.h
		if q < 1:
			e += s.k * pow(1 - q * q, 1.5)
	if e <= 0:
		return 0.0
	var strand := STR[int(Px.clamp(floorf((ang + 0.36) * 700), 0, 511))]
	var fall := Px.clamp(1.25 - (r - 230) / 420)
	return e * fall * (0.7 + 0.45 * strand)


static func drawBack(p: Px.Painter, t: float, o: Dictionary) -> void:
	var q := Lib.clip(p, meta)
	var S: float = o.seed
	var C := Px.fit(o.palette, 7)
	var sh := shafts(t, S)
	# dark air the light falls through, a dark floor it lands on; each beam posterized into a white-hot core, a
	# gold body and a soft translucent edge, brightest near the sun and fading as it falls
	var L := C.map(func(c): return Px.mix(C[0], c, 0.75))
	var n := sh.size()
	var SC := _f32(n)
	var SI := _f32(n)
	var SK := _f32(n)
	for j in n:
		var s: Dictionary = sh[j]
		SC[j] = s.c
		SI[j] = 1 / s.h
		SK[j] = s.k
	var C0: int = C[0]
	var C4: int = C[4]
	var str_ := STR
	var ax := AX
	var ay := AY
	var nx_ := NX
	var ny := NY
	Lib.rows(p, meta, -170, 9, func(y: float, R: Lib.Row) -> void:
		var Rc := R.c
		var Ra := R.a
		var Rl := R.l
		var Rk := R.k
		var floor_ := y > 0
		var dy := y - SY
		var air := 0.8 if floor_ else 0.66
		var boost := 1.6 if floor_ else 1.0
		var r := (-160 + 0.5 - SX) * ax + dy * ay
		var nn := (-160 + 0.5 - SX) * nx_ + dy * ny
		R.a.fill(air)
		R.b.fill(1)
		R.c.fill(C0)
		for i in W:
			var ri := r
			var ni := nn
			r += ax
			nn += nx_
			var ang := ni / ri
			var e := 0.0
			for j in n:
				var q2 := (ang - SC[j]) * SI[j]
				if q2 > -1 and q2 < 1:
					var w := 1 - q2 * q2
					e += SK[j] * w * sqrt(w)
			if e <= 0:
				continue
			var fall := 1.35 - (ri - 200) / 330
			var si := int((ang + 0.36) * 700)
			e *= (1.0 if fall > 1 else (0.0 if fall < 0 else fall)) * (0.7 + 0.45 * str_[0 if si < 0 else (511 if si > 511 else si)]) * boost
			if e < 0.06:
				continue
			var lv := 6 if e > 1.05 else (5 if e > 0.78 else (4 if e > 0.52 else (3 if e > 0.3 else 2)))
			Rc[i] = C[lv] if floor_ else L[lv]
			Ra[i] = 0.85 if floor_ else minf(0.78, 0.12 + e * 0.5)
			Rl[i] = C4
			Rk[i] = e * (0.32 if floor_ else 0.26))
	# the sun's glare where the beams come in
	q.glow(-168, -178, 130, C[3], 0.3)
	q.glow(-168, -178, 50, C[5], 0.35)
	motes(q, t, S, C, sh, false)


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var q := Lib.clip(p, meta)
	var S: float = o.seed
	var C := Px.fit(o.palette, 7)
	motes(q, t, S, C, shafts(t, S), true)


# each shaft breathes and sways on whole cycles; the strands drift slowly across the beams
static func shafts(t: float, S: float) -> Array:
	for i in 512:
		var a := i / 512.0
		STR[i] = 0.5 + 0.5 * sin(a * 190 + sin((TAU * t) / D) * 2 + S) * sin(a * 77 - (TAU * t) / D + S * 2)
	var out := []
	for i in SHAFTS.size():
		var s: Dictionary = SHAFTS[i]
		out.append({"c": s.c + s.sw * sin((TAU * t) / D + i * 1.3), "h": s.h * (1 + 0.15 * sin((TAU * s.b * t) / D + i)), "k": s.k * (0.72 + 0.28 * sin((TAU * s.b * t) / D + i * 2.1))})
	return out


# dust motes drifting slowly, invisible in the dark, catching the light as they cross a beam
static func motes(q: Px.Painter, t: float, S: float, C: Array, sh: Array, front: bool) -> void:
	for i in range(0 if front else 50, 50 if front else 160):
		var R := func(k): return Px.rand(S, i, k)
		var n1: float = 1 + floorf(R.call(1) * 2)
		var n2: float = 1 + floorf(R.call(2) * 2)
		var x: float = -170 + R.call(3) * 340 + (8 + R.call(4) * 14) * sin((TAU * n1 * t) / D + R.call(5) * TAU)
		var y: float = -170 + R.call(6) * 172 + (6 + R.call(7) * 10) * sin((TAU * n2 * t) / D + R.call(8) * TAU) + 4 * sin((TAU * 3 * t) / D + i)
		var e := lightAt(x, y, sh)
		if e < 0.12:
			continue
		var big: bool = front and R.call(9) < 0.5
		var k := minf(1, e)
		q.px(x, y, Px.WHITE if k > 0.6 else (C[5] if k > 0.3 else C[4]))
		if big and k > 0.5:
			q.px(x + 1, y, C[4])
			q.px(x, y + 1, C[4])
		q.glow(x, y, 6 if big else 4, C[4], 0.4 * k)
