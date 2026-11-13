# The banded after-images, the dotted speed lines with bright heads and the kicked-up dust are
# adapted from Sprite Fusion's open-source movement dash (https://www.spritefusion.com/pixel-art-vfx/movement),
# MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/status/haste.js@d2aed910ebdf4925e2bbd2568af5aa6d049e88d6
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")

static var meta := {
	"name": "Haste",
	"desc": "Sped up: striped after-images stream out behind, speed lines whip past, dust kicks off the heels and the leading edge catches the wind. Faces right.",
	"tags": ["status", "haste", "speed", "fast", "buff", "directional", "loop"],
	"size": [100, 56],
	"origin": [64, 48],
	"duration": 1.2,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {"palette": ["#4c25ab", "#773ae4", "#5b6cff", "#5eb0ff", "#a3dcff", "#ccf6ff", "#ffffff"], "dust": "#8a8090", "seed": 4},
}

static var RUN := {"turn": 0.25, "lean": 4}
static var R1 := Px.merge(RUN, {"crouch": 3, "ffx": 12, "ffy": -5, "fbx": -10, "fby": -8, "toeB": true, "fx": -7, "fy": -19, "bx": 12, "by": -27})
static var R2 := Px.merge(RUN, {"crouch": 1, "ffx": 4, "ffy": -8, "fbx": -1, "fby": -5, "fx": 3, "fy": -18, "bx": 5, "by": -19})
static var R3 := Px.merge(RUN, {"crouch": 3, "ffx": -10, "ffy": -8, "toeF": true, "fbx": 12, "fby": -5, "fx": 14, "fy": -27, "bx": -5, "by": -19})
static var R4 := Px.merge(RUN, {"crouch": 1, "ffx": -1, "ffy": -5, "fbx": 4, "fby": -8, "fx": 5, "fy": -19, "bx": 3, "by": -18})
static var act := {
	"onBody": true,
	"follow": 0,
	"poses": [[0, R1], [0.1, R2, "snap"], [0.2, R3, "snap"], [0.3, R4, "snap"], [0.4, R1, "snap"], [0.5, R2, "snap"], [0.6, R3, "snap"], [0.7, R4, "snap"], [0.8, R1, "snap"], [0.9, R2, "snap"], [1, R3, "snap"], [1.1, R4, "snap"], [1.2, R1, "snap"]],
}

static var D: float = meta.duration

# the character's shading in three levels (dark outline, mid, light), for the after-images
static var LEVELS := {}
static func levels(a: Dictionary) -> Array:
	var l: Variant = LEVELS.get(a.mask.id)
	if l != null:
		return l
	var S := Lib.shape(a)
	l = S.body.map(func(xy):
		var v := Px.luma(Lib.colorAt(a, xy[0], xy[1]))
		return [xy[0], xy[1], 1 if v < 0.24 else (2 if v < 0.66 else 3)])
	LEVELS[a.mask.id] = l
	return l


static func drawBack(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 7)
	var a: Dictionary = o.actor
	var L := levels(a)
	var S := Lib.shape(a)
	var f := floori(t * 30.0)
	# three after-images trailing back, each a step colder and cut into thinner stripes that scroll, jittering
	for g: int in [3, 2, 1]:
		var dx := -g * 14 - Px.round(Px.rand(f >> 1, g, 3) * 1.6)
		var every: int = [0, 3, 4, 0][g]
		# its outline, solid near, broken further back, and a few scrolling stripes across it
		p.outline(a.mask, a.x + dx, a.y, func(mx, my): return 0 if (g == 3 and (mx + my) % 2) else C[5 - g])
		if every:
			for lv: Array in L:
				var x: int = lv[0]
				var y: int = lv[1]
				var v: int = lv[2]
				if ((y + f) % every + every) % every:
					continue
				p.px(a.x + x + dx, a.y + y, C[maxi(0, mini(6, 5 - g + v - 2))])
		p.glow(a.x + a.w / 2.0 + dx, a.y + a.h * 0.45, 16.0, C[3], 0.12 * (1.0 - g * 0.25))
	# a smear streaming off the trailing edge
	for sd: Array in S.side:
		var x: int = sd[0]
		var y: int = sd[1]
		var dir: int = sd[2]
		if dir > 0 or (y + (f >> 1)) % 3:
			continue
		var len := 3 + floori(Px.rand(y, f >> 1, 5) * 6.0)
		for d in range(1, len + 1):
			p.dot(a.x + x - d, a.y + y, C[5] if d < 3 else C[4], 1.0 - d / float(len + 1))
	# speed lines whipping past behind
	lines(p, C, a, t, o.seed, false)
	# dust kicked off the heels, rolling away behind
	var dust := Px.hex(o.dust)
	Px.cycle(t, D, 12, o.seed + 5, func(r): return r.range(0.45, 0.7), func(age, life, r, i):
		var u: float = age / life
		var foot := -7.0 if i % 2 else 3.0
		var x: float = foot + Lib.travel(-r.range(50.0, 100.0), 0.0, 3.5, age)
		var y: float = -1.5 - Lib.travel(r.range(6.0, 18.0), 0.0, 3.5, age)
		var rad: float = r.range(2.6, 4.6) * (0.6 + 1.0 * u)
		var k := pow(1.0 - u, 1.2) * minf(1.0, u * 10.0)
		p.disc(x, y, rad, dust, k * 0.5)
		p.disc(x + rad * 0.05, y + rad * 0.08, rad * 0.74, dust, k * 0.62)
		p.disc(x - rad * 0.22, y - rad * 0.3, rad * 0.5, C[5], k * 0.25))


# streaks: a bright head, a coloured body, a dotted tail thinning out behind (some cut across the body in front)
static func lines(p: Px.Painter, C: Array, a: Dictionary, t: float, seed: float, front: bool) -> void:
	Px.cycle(t, D, 5 if front else 11, seed + (9.0 if front else 7.0), func(r): return r.range(0.12, 0.26), func(age, life, r):
		var u: float = age / life
		var y: float = a.y + r.range(2.0, a.h - 3.0)
		var len: float = r.range(10.0, 26.0) * (0.7 if front else 1.0)
		var x: float = r.range(-14.0, 4.0) - age * r.range(160.0, 240.0)
		var d := 0
		while d < len:
			if d > len * 0.45 and d % 2:
				d += 1
				continue
			p.dot(x + d, y, C[6] if d < 2 else (C[5] if d < len * 0.4 else C[3]), (1.0 - d / len) * (1.0 - u) * (0.7 if front else 1.1))
			d += 1
		p.light(x, y, C[4], 0.4 * (1.0 - u)))


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 7)
	var a: Dictionary = o.actor
	var S := Lib.shape(a)
	# the leading edge catches the wind: a bright rim, flickering
	for sd: Array in S.side:
		var x: int = sd[0]
		var y: int = sd[1]
		var dir: int = sd[2]
		if dir > 0 and Px.rand(x, y, floorf(t * 15.0)) < 0.85:
			p.px(a.x + x, a.y + y, C[6] if Px.rand(y, floorf(t * 15.0), 2) < 0.3 else C[5])
	lines(p, C, a, t, seed_(o), true)
	# a cool glow streaming off the back
	p.glow(-6.0, a.y + a.h * 0.5, 22.0, C[3], 0.16)
	p.glow(0.0, a.y + a.h * 0.45, 30.0, C[3], 0.16)
	p.glow(a.x + a.w, a.y + a.h * 0.5, 10.0, C[5], 0.12 + 0.06 * sin((t / D) * TAU * 3.0))
# (JS: seed, which is a GDScript built-in)
static func seed_(o: Dictionary) -> float:
	return o.seed
