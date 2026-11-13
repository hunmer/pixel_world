# The shaded, outlined hearts are
# adapted from Sprite Fusion's open-source heal (https://www.spritefusion.com/pixel-art-vfx/heal),
# MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/status/charmed.js@4b49304cc5da9538e1adfbf880d20c04e9a8e975
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")

static var meta := {
	"name": "Charmed",
	"desc": "Smitten: a big heart beats over the head, throwing a ring and a flush of light with every beat, little hearts float up, the eyes go pink and the cheeks blush.",
	"tags": ["status", "charm", "love", "hearts", "debuff", "loop"],
	"size": [60, 76],
	"origin": [30, 68],
	"duration": 2.4,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {"palette": ["#3a0a1e", "#7a1238", "#c4245a", "#f04e86", "#ff8ab0", "#ffc8da", "#ffffff"], "seed": 8},
}

static var SWOON := {"turn": 1.1, "fx": -2, "fy": -28, "bx": 2, "by": -28, "armsFront": true, "ffx": -3, "fbx": 4}
static var act := {
	"onBody": true,
	"poses": [[0, Px.merge(SWOON, {"lean": -2})], [0.6, Px.merge(SWOON, {"lean": 0, "crouch": 1})], [1.2, Px.merge(SWOON, {"lean": 2})], [1.8, Px.merge(SWOON, {"lean": 0, "crouch": 1})], [2.4, Px.merge(SWOON, {"lean": -2})]],
}

static var D: float = meta.duration
static var BEAT := D / 2.0
static var HEART5 := Lib.bitmap([".#.#.", "#####", "#####", ".###.", "..#.."])
static var HEART7 := Lib.bitmap([".##.##.", "#######", "#######", ".#####.", "..###..", "...#..."])
# a heartbeat: a strong lub and a softer dub
static func thump(ph: float) -> float:
	return exp(-pow((ph - 0.04) / 0.07, 2.0)) + 0.6 * exp(-pow((ph - 0.26) / 0.07, 2.0))


# little hearts drifting up (half of them behind the character)
static func hearts(p: Px.Painter, C: Array, a: Dictionary, t: float, seed: float, back: bool) -> void:
	Px.cycle(t, D, 12, seed + 4.0, func(r): return r.range(1.3, 1.9), func(age, life, r, i):
		if (i % 3 == 0) != back:
			return
		var u: float = age / life
		var side := -1.0 if r.next() < 0.5 else 1.0
		var ph: float = r.range(0.0, TAU)
		var big: bool = r.next() < 0.3
		var x: float = side * r.range(4.0, 15.0) + sin(age * 4.0 + ph) * 2.2
		var y: float = a.y + r.range(8.0, 30.0) - age * r.range(14.0, 22.0)
		var k := minf(1.0, u * 6.0)
		if u > 0.88:
			# it pops into a twinkle
			var q := (u - 0.88) / 0.12
			Px.sparkle(p, x, y, Px.round(2.0 * (1.0 - q)), C[5], C[4], 0.4 * (1.0 - q))
			return
		var R := [C[0], C[1], C[2], C[3]] if back else [C[0], C[2], C[3], C[4]]
		Lib.icon(p, x, y, 4, HEART7 if big else HEART5, R, k)
		if not back:
			p.px(x - (2.0 if big else 1.0), y - 1.0, C[6])
		p.glow(x, y, 6.0, C[3], (0.12 if back else 0.22) * k))


static func drawBack(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 7)
	var a: Dictionary = o.actor
	var ph := fmod(fmod(t, BEAT) + BEAT, BEAT)
	var th := thump(ph)
	p.glow(0.0, a.y - 8.0, 26.0 + 8.0 * th, C[3], 0.16 + 0.22 * th)
	hearts(p, C, a, t, o.seed, true)


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 7)
	var a: Dictionary = o.actor
	var ph := fmod(fmod(t, BEAT) + BEAT, BEAT)
	var th := thump(ph)
	# lovestruck: pink eyes with a bright catchlight, flushed cheeks
	for e: Dictionary in Lib.eyes(a):
		for xy: Array in e.px:
			p.px(a.x + xy[0], a.y + xy[1], C[3] if xy[1] == e.y0 else C[2])
		p.px(a.x + e.x0, a.y + e.y0 + 1, C[6])
		var blush := Px.mix(e.skin, C[3], 0.55)
		var out := -1 if e.x0 < a.w / 2.0 else 1
		var bx: int = e.x0 - 1 if out < 0 else e.x1
		p.px(a.x + bx, a.y + e.y1 + 1, blush)
		p.px(a.x + bx + 1, a.y + e.y1 + 1, blush)
	hearts(p, C, a, t, o.seed, false)
	# the big heart, beating
	var hx := 0.0
	var hy: float = a.y - 10.0
	var s := 5.6 * (1.0 + 0.24 * th)
	# a heart-shaped ring thrown off with each beat
	for tk: Array in [[0.04, 1.0], [0.26, 0.6]]:
		var t0: float = tk[0]
		var kk: float = tk[1]
		var u := (ph - t0) / 0.5
		if u < 0.0 or u > 1.0:
			continue
		var S1 := 5.6 * (1.25 + 1.3 * u)
		var outer := Lib.shaped(Lib.heartShape, S1)
		var inner := Lib.shaped(Lib.heartShape, S1 - 1.3)
		var E := ceili(S1 * 1.2) + 1
		for dy in range(-E, E + 1):
			for dx in range(-E, E + 1):
				if outer.call(dx, dy) and not inner.call(dx, dy):
					p.dot(hx + dx, hy + dy, C[5] if u < 0.3 else C[4], (1.0 - u) * kk * 1.3)
	Lib.icon(p, hx, hy, 9, Lib.shaped(Lib.heartShape, s), [C[0], C[2], C[3], C[4]])
	# a glint on the left lobe
	p.px(hx - Px.round(s * 0.55), hy - Px.round(s * 0.45), C[6])
	p.px(hx - Px.round(s * 0.55) + 1.0, hy - Px.round(s * 0.45), C[5])
	p.px(hx - Px.round(s * 0.55), hy - Px.round(s * 0.45) + 1.0, C[5])
	p.glow(hx, hy, 12.0 + 6.0 * th, C[4], 0.3 + 0.4 * th)
	if th > 0.5:
		Px.sparkle(p, hx + s * 0.9, hy - s * 0.8, Px.round(3.0 * th), C[5], C[4], 0.4 * th)
	# twinkles round the heart
	Px.cycle(t, D, 8, o.seed + 2, func(r): return r.range(0.3, 0.5), func(age, life, r):
		var an: float = r.range(0.0, TAU)
		var d: float = r.range(8.0, 15.0)
		var u: float = age / life
		Px.sparkle(p, hx + cos(an) * d, hy + sin(an) * d * 0.8, Px.round(1.6 * sin(PI * u)), C[5], C[4], 0.3 * sin(PI * u)))
