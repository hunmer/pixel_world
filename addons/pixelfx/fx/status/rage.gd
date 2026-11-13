# The shaded, outlined anger mark and the embers are
# adapted from Sprite Fusion's open-source heal and fire (https://www.spritefusion.com/pixel-art-vfx/heal),
# MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/status/rage.js@171b95ca44b8303b29e172f9ad24058948b2b731
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")

static var meta := {
	"name": "Rage",
	"desc": "Seething: the body judders on every heartbeat, an anger mark throbs at the temple, eyes burn, steam jets off the head, stress lines flash out and the floor cracks hot underfoot.",
	"tags": ["status", "rage", "berserk", "anger", "buff", "loop"],
	"size": [80, 80],
	"origin": [40, 70],
	"duration": 1.2,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {
		"palette": ["#1a0208", "#4a0612", "#8a0c1c", "#c81828", "#ff3040", "#ff7a7a", "#ffc8c8", "#ffffff"],
		"heat": ["#5a0a0a", "#c8281a", "#ff7a2a", "#ffd27a"],
		"steam": "#f2e8ee",
		"seed": 6,
	},
}

static var SEETHE := {"turn": 1, "crouch": 4, "fx": -13, "fy": -19, "bx": 13, "by": -19, "ffx": -8, "fbx": 9}
static var THUD := Px.merge(SEETHE, {"crouch": 6, "fy": -23, "by": -23})
static var act := {
	"onBody": true,
	"poses": [[0, SEETHE], [0.05, THUD, "snap"], [0.17, SEETHE, "snap"], [0.29, Px.merge(THUD, {"crouch": 5}), "snap"], [0.4, SEETHE, "snap"], [1.2, SEETHE]],
}

static var D: float = meta.duration
const LUB := 0.05
const DUB := 0.29
const G := 760.0
static func pulse(t: float, at: float, w: float = 0.06) -> float:
	return exp(-pow((fmod(fmod(t - at, D) + D + D / 2.0, D) - D / 2.0) / w, 2.0))
static func beat(t: float) -> float:
	return pulse(t, LUB) + 0.65 * pulse(t, DUB)
# how long after the last lub or dub it is
static func since(t: float, at: float) -> float:
	return fmod(fmod(t - at, D) + D, D)
# the body judders for a moment on each beat
static func shaking(t: float) -> bool:
	return since(t, LUB - 0.02) < 0.13 or since(t, DUB - 0.02) < 0.09

## The stand-in is hidden while the body judders: the effect draws it, shaken.
static func actorAlpha(t: float, _o: Dictionary) -> float:
	return 0.0 if shaking(t) else 1.0

# the anger mark: four curves round a cross-shaped gap, at two sizes for the throb
static var MARK := [
	Lib.bitmap(["..#.#..", "..#.#..", "##...##", ".......", "##...##", "..#.#..", "..#.#.."]),
	Lib.bitmap(["...#.#...", "...#.#...", "..##.##..", "###...###", ".........", "###...###", "..##.##..", "...#.#...", "...#.#..."]),
]

# cracks in the floor round the feet, worked out once per seed: jagged runs out from under each foot
static var CRACKS := {}
static func cracks(a: Dictionary, seed: float) -> Array:
	if CRACKS.has(seed):
		return CRACKS[seed]
	var S := Lib.shape(a)
	var flr: Array = S.rows[S.h - 1]
	var fl: int = flr[0]
	var fr: int = flr[1]
	var R := Px.Rng.new(seed * 31.0 + 7.0)
	var out := []
	for xd: Array in [[a.x + fl + 2, -1], [a.x + fr - 1, 1], [a.x + (fl + fr) / 2.0, -1], [a.x + (fl + fr) / 2.0 + 1.0, 1]]:
		var x: float = xd[0]
		var dir: int = xd[1]
		var y := 0.5
		var pts := [[x, y]]
		var n := R.int_(5, 9)
		for i in n:
			x += dir * R.range(1.2, 2.4)
			y = Px.clamp(y + R.range(-0.9, 0.9), 0.0, 2.5)
			pts.append([x, y])
			if i > 1 and R.chance(0.3):
				out.append([[x, y], [x + dir * R.range(1.0, 2.0), Px.clamp(y + R.sign() * R.range(0.6, 1.4), 0.0, 3.0)]])
		out.append(pts)
	CRACKS[seed] = out
	return out


static func drawBack(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var Hh := Px.fit(o.heat, 4)
	var a: Dictionary = o.actor
	var b := beat(t)
	var stamp := exp(-since(t, LUB) / 0.18)
	# dark-red heat shimmering up round the body
	Px.cycle(t, D, 9, o.seed + 2, func(r): return r.range(0.7, 1.1), func(age, life, r):
		var u: float = age / life
		var x0: float = r.range(-16.0, 16.0)
		var y: float = a.y + r.range(10.0, 40.0) - age * r.range(14.0, 22.0)
		var len: float = r.range(6.0, 11.0)
		var ph: float = r.range(0.0, TAU)
		var k := sin(PI * u) * 0.55
		var d := 0
		while d < len:
			p.dot(x0 - len / 2.0 + d, y + Px.round(sin(d * 0.9 + ph + age * 12.0) * 0.8), C[2] if d % 3 else C[1], k * (1.0 - absf(d / len - 0.5) * 1.4))
			d += 1)
	# the floor: red light pooling, cracks under the feet glowing hot on each stamp and cooling between
	p.shade(-30.0, -4.0, 30.0, 8.0, func(x, y, out):
		var d := Px.hypot(x / 28.0, (y - 0.5) / 4.5)
		if d < 1.0:
			out.l = C[3]
			out.k = (0.2 + 0.3 * b) * (1.0 - d) * (1.0 - d))
	var heat := 0.25 + 0.75 * stamp
	for pts: Array in cracks(a, o.seed):
		for i in range(1, pts.size()):
			var x0: float = pts[i - 1][0]
			var y0: float = pts[i - 1][1]
			var x1: float = pts[i][0]
			var y1: float = pts[i][1]
			var far := i / float(pts.size())
			p.line(x0, y0, x1, y1, Hh[3] if heat * (1.0 - far * 0.6) > 0.6 else (Hh[2] if heat * (1.0 - far * 0.5) > 0.35 else Hh[1]))
			if i % 2:
				p.glow(x1, y1, 4.0, Hh[2], 0.25 * heat * (1.0 - far * 0.5))


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var Hh := Px.fit(o.heat, 4)
	var a: Dictionary = o.actor
	var S := Lib.shape(a)
	var b := beat(t)
	var steam := Px.hex(o.steam)
	var shake := shaking(t)
	var dx := (1 if floori(t * 60.0) % 2 else -1) if shake else 0
	var dy := -1 if (shake and since(t, LUB - 0.02) < 0.06) else 0
	# the body: shaken while the beat lands, the face flushing red with it
	for bd: Array in S.body:
		var mx: int = bd[0]
		var my: int = bd[1]
		var c := Lib.colorAt(a, mx, my)
		var l := Px.luma(c)
		var skin := l > 0.55 and (c & 255) > ((c >> 16) & 255) + 30
		if skin:
			p.px(a.x + mx + dx, a.y + my + dy, Px.mix(c, C[4], 0.22 + 0.3 * b))
		elif shake:
			p.px(a.x + mx + dx, a.y + my + dy, c)
	# burning eyes under angry brows
	for e: Dictionary in Lib.eyes(a):
		var ex: int = a.x + dx
		var ey: int = a.y + dy
		var inner := 1 if (e.x0 + e.x1) / 2.0 < a.w / 2.0 else -1
		for xy: Array in e.px:
			p.px(ex + xy[0], ey + xy[1], C[7] if xy[1] == e.y0 else (C[6] if xy[1] == e.y0 + 1 else C[4]))
		var xi: int = e.x1 if inner > 0 else e.x0
		var xo: int = e.x0 if inner > 0 else e.x1
		p.px(ex + xo - inner, ey + e.y0 - 2, 0xff1f1726)
		p.px(ex + xo, ey + e.y0 - 2, 0xff1f1726)
		p.px(ex + xi, ey + e.y0 - 1, 0xff1f1726)
		p.glow(ex + (e.x0 + e.x1 + 1) / 2.0, ey + e.y0 + 1, 5.0, C[5], 0.35 + 0.35 * b)
	# the anger mark throbbing at the temple: big on the lub, smaller on the dub
	var big := pulse(t, LUB + 0.02, 0.05) > 0.35 or pulse(t, DUB + 0.02, 0.04) > 0.6
	var mx: float = a.x + a.w * 0.86 + dx
	var my: float = a.y + 3 + dy
	Lib.icon(p, mx, my, 5, MARK[1 if big else 0], [C[0], C[3], C[4], C[5]])
	p.px(mx - (3.0 if big else 2.0), my - (3.0 if big else 2.0), C[6])
	p.glow(mx, my, 8.0, C[4], 0.25 + 0.4 * b)
	# steam jetting off the head in short bursts after each beat
	for anp: Array in [[LUB + 0.04, 7, 1.0], [DUB + 0.04, 4, 0.75]]:
		var at: float = anp[0]
		var n: int = anp[1]
		var power: float = anp[2]
		for side: int in [-1, 1]:
			for i in n:
				var age := since(t, at + i * 0.016)
				var life := 0.22 + 0.12 * Px.rand(i, side, 3)
				if age >= life:
					continue
				var u := age / life
				var ang := -PI / 2.0 + side * (0.5 + 0.2 * Px.rand(i, side, 5))
				var sp := (90.0 + 40.0 * Px.rand(i, side, 7)) * power
				var x: float = side * a.w * 0.36 + cos(ang) * Lib.travel(sp, 0.0, 7.0, age)
				var y: float = a.y + 3 + sin(ang) * Lib.travel(sp, 0.0, 7.0, age) - 8.0 * age
				var rad := (1.0 + 3.2 * sqrt(u)) * (0.8 + 0.4 * Px.rand(i, side, 9))
				var k := minf(1.0, u * 12.0) * pow(1.0 - u, 2.0)
				p.disc(x, y, rad, steam, 0.7 * k)
				p.disc(x - rad * 0.2, y - rad * 0.25, rad * 0.6, 0xffffffff, 0.6 * k)
				if u < 0.3:
					p.dot(x, y, 0xffffffff, 1.0 - u / 0.3)
	# jagged stress lines flashing out round the head on the beat
	for anl: Array in [[LUB, 8, 7.0], [DUB, 6, 5.0]]:
		var at: float = anl[0]
		var n: int = anl[1]
		var len: float = anl[2]
		var age := since(t, at)
		if age > 0.2:
			continue
		var k := age / 0.2
		for i in n:
			var ang := -PI / 2.0 + ((i + 0.5) / n - 0.5) * 4.4
			var r0 := 15.0 + 6.0 * k
			var ca := cos(ang)
			var sa := sin(ang)
			var cx := 0.0
			var cy: float = a.y + 12
			var pts := []
			for j in range(0, 4):
				var r := r0 + (j / 3.0) * len
				var off := 1.3 if j % 2 else -0.4
				pts.append([cx + ca * r - sa * off, cy + sa * r + ca * off])
			p.polyline(pts, func(u): return C[7] if u > 0.66 else (C[5] if u > 0.33 else C[4]), 1.2 - k)
			p.glowLine(pts[0][0], pts[0][1], pts[3][0], pts[3][1], 3.0, C[4], 0.3 * (1.0 - k))
	# the stamp: embers spat up out of the cracks, grit hopping
	var st := since(t, LUB)
	for i in 10:
		var life := 0.5 + 0.5 * Px.rand(i, 11)
		var age := st - 0.02 * Px.rand(i, 12)
		if age < 0.0 or age > life:
			continue
		var x := (Px.rand(i, 13) - 0.5) * 30.0 + sin(age * 9.0 + i) * 1.5 * age
		var y := -1.0 + Lib.travel(-(40.0 + 50.0 * Px.rand(i, 14)), -20.0, 1.6, age)
		Lib.ember(p, x, y, age / life, [Hh[3], Hh[2], Hh[1]], age + i)
	for i in 12:
		var vx := (Px.rand(i, 21) - 0.5) * 90.0
		var vy := -(40.0 + 70.0 * Px.rand(i, 22))
		var tt := st
		var x := (Px.rand(i, 23) - 0.5) * 18.0 + vx * tt
		var y := -1.0 + vy * tt + 0.5 * G * tt * tt
		if tt > 0.6 or y > 0.0:
			continue
		p.px(x, y, C[2] if i % 3 else 0xff6a5e72)
	# the beat flares red light round the head and down onto the floor
	p.glow(0.0, a.y + 10.0, 26.0, C[4], 0.12 + 0.4 * b)
	p.glow(0.0, a.y + 22.0, 34.0, C[3], 0.08 + 0.18 * b)
