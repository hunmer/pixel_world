# The shaded, outlined letters are
# adapted from Sprite Fusion's open-source heal (https://www.spritefusion.com/pixel-art-vfx/heal),
# MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/status/sleep.js@c0048fcc7b959011fccee93dce8a5ed24be3f213
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")

static var meta := {
	"name": "Sleep",
	"desc": "Fast asleep: eyes shut, soft outlined Zs float up off the head one after another, swaying and growing as they rise, dream motes drift, a slow breathing glow.",
	"tags": ["status", "sleep", "zzz", "rest", "debuff", "loop"],
	"size": [60, 82],
	"origin": [26, 74],
	"duration": 2.4,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {"palette": ["#1a1636", "#3c3a7a", "#6f78c8", "#a9b8f0", "#dfe6ff", "#ffffff"], "seed": 3},
}

static var NOD := {"turn": 0.9, "crouch": 1, "lean": 1, "hy": 2, "fx": -6, "fy": -14, "bx": 7, "by": -14, "ffx": -2, "fbx": 3}
static var act := {
	"onBody": true,
	"poses": [[0, NOD], [1.2, Px.merge(NOD, {"crouch": 2, "lean": 2, "hy": 3})], [2.4, NOD]],
}

static var D: float = meta.duration
const NZ := 3
# the letter at four sizes: it grows a step at a time as it rises
static var ZS := [
	["#####", "...#.", "..#..", ".#...", "#####"],
	["#######", ".....#.", "....#..", "...#...", "..#....", ".#.....", "#######"],
	[".#######.", "#########", "......##.", ".....##..", "....##...", "...##....", "..##.....", "#########", ".#######."],
	[".#########.", "###########", ".......###.", "......###..", ".....###...", "....###....", "...###.....", "..###......", ".###.......", "###########", ".#########."],
].map(func(rows): return Lib.bitmap(rows))


# a Z at age u (0..1): where it is, how big, how solid
static func zAt(a: Dictionary, i: int, u: float) -> Dictionary:
	var side := 1.0 if i % 2 else 0.6
	var x0: float = a.x + a.w * 0.78
	var y0: float = a.y + 7
	var x := x0 + 13.0 * side * u + 2.5 * sin(TAU * 1.1 * u + i * 2.1)
	var y := y0 - 32.0 * (1.0 - pow(1.0 - u, 1.35))
	var size := 0 if u < 0.18 else (1 if u < 0.42 else (2 if u < 0.68 else 3))
	var k := minf(1.0, u / 0.06)
	return {"x": x, "y": y, "size": size, "k": k}


# shut the eyes: paint them over with skin and draw a soft lid line
static func shut(p: Px.Painter, a: Dictionary) -> void:
	for e: Dictionary in Lib.eyes(a):
		for xy: Array in e.px:
			p.px(a.x + xy[0], a.y + xy[1], e.skin)
		var lid := Lib.colorAt(a, e.x0 - 1, e.y0 - 4)
		if not lid:
			lid = Lib.colorAt(a, e.px[0][0], e.px[0][1])
		var y: int = a.y + e.y1 - 1
		for x in range(e.x0, e.x1 + 1):
			p.px(a.x + x, y, 0xff1f1726)
		p.px(a.x + e.x0 - 1, y - 1, 0xff1f1726)
		p.px(a.x + e.x1 + 1, y - 1, 0xff1f1726)


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 6)
	var a: Dictionary = o.actor
	var breath := 0.5 + 0.5 * sin((t / D) * TAU * 2.0)
	shut(p, a)
	# a slow breathing glow round the head, and soft dream light drifting about it
	p.glow(0.0, a.y + 10.0, 24.0, C[3], 0.1 + 0.1 * breath)
	Px.cycle(t, D, 5, o.seed + 6, D, func(age, life, r):
		var u: float = age / life
		var x: float = a.x + a.w * r.range(0.3, 1.1) + sin(u * TAU + r.next() * TAU) * 3.0
		var y: float = a.y + r.range(-6.0, 8.0) - u * 10.0
		var rad: float = r.range(3.0, 5.0) * (0.8 + 0.4 * u)
		var k := sin(PI * u)
		p.glow(x, y, rad * 2.4, C[3], 0.1 * k))
	# dream motes drifting up
	Px.cycle(t, D, 14, o.seed + 4, func(r): return r.range(1.2, 2.0), func(age, life, r):
		var u: float = age / life
		var x: float = a.x + a.w * r.range(0.4, 1.1) + sin(age * 2.0 + r.next() * TAU) * 2.0
		var y: float = a.y + r.range(0.0, 10.0) - age * r.range(10.0, 18.0)
		var tw: float = sin(PI * u) * (0.6 + 0.4 * sin(age * 9.0 + r.next() * TAU))
		if tw < 0.15:
			return
		Px.sparkle(p, x, y, 1.0 if (tw > 0.7 and r.next() < 0.4) else 0.0, C[4], C[3], 0.3 * tw)
		p.dot(x, y, C[5] if tw > 0.6 else C[4], tw * 1.3))
	# the Zs, oldest (biggest) first so the young ones sit on top
	var zs := []
	for i in NZ:
		zs.append({"i": i, "u": fmod(fmod(t - (i * D) / NZ, D) + D, D) / D})
	Px.sort(zs, func(p1, p2): return p2.u - p1.u)
	for zi: Dictionary in zs:
		var i: int = zi.i
		var u: float = zi.u
		var z := zAt(a, i, u)
		if u > 0.9:
			# it pops into motes
			var k := (u - 0.9) / 0.1
			for j in 7:
				var an := (j / 7.0) * TAU + i
				var d := 3.0 + 6.0 * sqrt(k)
				p.dot(z.x + cos(an) * d, z.y + sin(an) * d * 0.8, C[4] if j % 2 else C[5], 1.2 - k)
			p.glow(z.x, z.y, 10.0, C[3], 0.25 * (1.0 - k))
			continue
		# a dotted trail where it has been
		for j in range(1, 7):
			var q := zAt(a, i, maxf(0.0, u - j * 0.025))
			if j % 2 == 0 or u - j * 0.025 < 0.05:
				continue
			p.dot(q.x - 1.0, q.y + 4.0 + q.size, C[3], (1.0 - j / 7.0) * 0.9)
		# it dims down the ramp as it gets old
		var old := 1 if u > 0.78 else 0
		var R := [C[0], C[1], C[2], C[3]] if old else [C[1], C[2], C[3], C[4]]
		Lib.icon(p, z.x, z.y, 7, ZS[z.size], R, z.k)
		if not old:
			p.px(z.x - 2.0 - z.size, z.y - 2.0 - z.size * 0.8, C[5])
		p.glow(z.x, z.y, 7.0 + z.size * 3.0, C[3], (0.12 if old else 0.26) * z.k)
