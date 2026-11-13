# The shaded, outlined question marks are
# adapted from Sprite Fusion's open-source heal (https://www.spritefusion.com/pixel-art-vfx/heal),
# MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/status/confused.js@127974548645b8685f14f2b8c980cf2f88316fe6
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")

static var meta := {
	"name": "Confused",
	"desc": "Head in a spin: a glowing spiral whirls over the head, question marks pop up round it and bob, the eyes dart left and right.",
	"tags": ["status", "confused", "confusion", "dizzy", "debuff", "loop"],
	"size": [60, 78],
	"origin": [30, 70],
	"duration": 2.4,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {
		"palette": ["#1e0f2e", "#4b2070", "#8a3ab0", "#c66ae0", "#f0a8ff", "#ffffff"],
		"marks": ["#2a1608", "#b0701a", "#ffd84a", "#fff4b8"],
		"seed": 6,
	},
}

static var SHRUG := {"turn": 1, "fx": -13, "fy": -26, "bx": 14, "by": -26, "ffx": -3, "fbx": 4}
static var act := {
	"onBody": true,
	"poses": [
		[0, Px.merge(SHRUG, {"x": 0, "lean": -2})],
		[0.6, Px.merge(SHRUG, {"x": 1, "lean": 1, "crouch": 1, "fy": -23, "by": -29, "fbx": 5, "fby": -6})],
		[1.2, Px.merge(SHRUG, {"x": 2, "lean": 2})],
		[1.8, Px.merge(SHRUG, {"x": 1, "lean": -1, "crouch": 1, "fy": -29, "by": -23, "ffx": -4, "ffy": -6})],
		[2.4, Px.merge(SHRUG, {"x": 0, "lean": -2})],
	],
}

static var D: float = meta.duration
static var QS := [
	[".###.", "#...#", "....#", "...#.", "..#..", ".....", "..#.."],
	[".####.", "##..##", "....##", "...##.", "..##..", "..##..", "......", "..##..", "..##.."],
	[".#####.", "##...##", "##...##", ".....##", "....##.", "...##..", "...##..", ".......", "...##..", "...##.."],
].map(func(rows): return Lib.bitmap(rows))
# three marks round the spiral: where they sit, when they pop, how big they get
const MARKS := [
	{"x": -12.0, "y": -5.0, "t0": 0.0, "big": 2},
	{"x": 12.0, "y": -8.0, "t0": 0.8, "big": 1},
	{"x": 1.0, "y": -17.0, "t0": 1.6, "big": 2},
]


# the spiral, seen from the front: an arm winding out from its heart, spinning
static func spiral(p: Px.Painter, C: Array, cx: float, cy: float, t: float) -> void:
	var rot := (t / D) * TAU * 2.0
	var turns := 1.8
	var n := 72.0
	var breathe := 1.0 + 0.08 * sin((t / D) * TAU * 4.0)
	var at := func(u: float) -> Array:
		var th := u * turns * TAU - rot
		var r := (0.8 + 6.6 * u) * breathe
		return [cx + cos(th) * r, cy + sin(th) * r * 0.9]
	# a dark underlay on the outer arm so it reads against anything, then the arm brightening as it winds out
	for i in range(1, int(n) + 1):
		var u := i / n
		var p0: Array = at.call((i - 1) / n)
		var p1: Array = at.call(u)
		if u > 0.45:
			p.line(p0[0] + 0.5, p0[1] + 0.7, p1[0] + 0.5, p1[1] + 0.7, C[1])
	for i in range(1, int(n) + 1):
		var u := i / n
		var p0: Array = at.call((i - 1) / n)
		var p1: Array = at.call(u)
		p.line(p0[0], p0[1], p1[0], p1[1], C[5] if u > 0.88 else (C[4] if u > 0.62 else (C[3] if u > 0.3 else C[2])))
		if i % 6 == 0:
			p.light(p1[0], p1[1], C[3], 0.4 * u)
	var hxy: Array = at.call(1.0)
	Px.sparkle(p, hxy[0], hxy[1], 2.0, C[4], C[3], 0.5)
	p.glow(cx, cy, 13.0, C[3], 0.28)


static func drawBack(p: Px.Painter, _t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 6)
	var a: Dictionary = o.actor
	p.glow(0.0, a.y - 7.0, 16.0, C[3], 0.22)


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 6)
	var M := Px.fit(o.marks, 4)
	var a: Dictionary = o.actor
	# the eyes dart from side to side
	var look := 1 if floori((t / D) * 6.0) % 2 else -1
	for e: Dictionary in Lib.eyes(a):
		for xy: Array in e.px:
			p.px(a.x + xy[0], a.y + xy[1], 0xff17121f)
		p.px(a.x + (e.x0 if look < 0 else e.x1), a.y + e.y0, 0xffffffff)
	spiral(p, C, 0.0, a.y - 7.0, t)
	# the question marks pop up, bob, and shrink away
	for m: Dictionary in MARKS:
		var age := fmod(fmod(t - m.t0, D) + D, D)
		var life := 1.9
		if age > life:
			continue
		var u := age / life
		var pop := Px.Ease.outBack(Px.clamp(age / 0.16), 3.0)
		var out := Px.clamp((u - 0.82) / 0.18)
		var size := maxf(0.0, Px.round(m.big * pop * (1.0 - out) + (1.0 if pop > 1.1 else 0.0)))
		var bob: float = sin(age * 5.0 + m.t0 * 3.0) * 1.6
		var tilt: float = sin(age * 3.3 + m.t0) * 0.8
		if pop < 0.3 or (out > 0.0 and size == 0.0 and out > 0.6):
			continue
		var x: float = m.x + tilt
		var y: float = a.y + m.y + bob - age * 2.0
		# it pops in with a burst of short rays and a flash
		if age < 0.2:
			var k := age / 0.2
			for j in 8:
				var an := (j / 8.0) * TAU + 0.2
				var d0 := 4.0 + 7.0 * k
				var d1 := d0 + 3.0 * (1.0 - k)
				p.line(x + cos(an) * d0, y + sin(an) * d0, x + cos(an) * d1, y + sin(an) * d1, M[2] if j % 2 else M[3], 1.0 - k)
			p.glow(x, y, 16.0, M[2], 0.45 * (1.0 - k))
		Lib.icon(p, x, y, 7, QS[mini(2, int(size))], [M[0], M[1], M[2], M[3]])
		p.glow(x, y, 10.0 + size * 2.0, M[2], 0.28 * (1.0 - out))
	# glitter flicking off the spiral
	Px.cycle(t, D, 10, o.seed + 2, func(r): return r.range(0.35, 0.6), func(age, life, r):
		var th: float = r.range(0.0, TAU)
		var u: float = age / life
		var d: float = 6.0 + age * r.range(12.0, 22.0)
		var x := cos(th) * d
		var y: float = a.y - 7.0 + sin(th) * d * 0.8
		if sin(PI * u) > 0.6 and r.next() < 0.5:
			Px.sparkle(p, x, y, 1.0, C[4], C[3], 0.3)
		else:
			p.dot(x, y, C[5] if u < 0.5 else C[4], 1.2 - u))
