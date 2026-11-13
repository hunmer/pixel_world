# The snow recipe (depth layers falling at their own speeds with a sway, a gusty wind, flakes that settle on a
# drift for a while) is adapted from Sprite Fusion's open-source snow (https://www.spritefusion.com/pixel-art-vfx/snow),
# MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/weather/snow.js@b1307a4f4a41ea4efaada42895d2f3df1561afa8
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")

static var meta := {
	"name": "Snow",
	"desc": "Snow at three depths in a gusty breeze: far specks, drifting flakes, big near crystals that spin and glow; they settle on a sparkling drift and melt away.",
	"tags": ["weather", "snow", "winter", "cold", "ambient", "loop"],
	"size": [320, 180],
	"origin": [160, 170],
	"duration": 12.0,
	"loop": true,
	"fps": 30,
	"bg": "sky",
	"options": {
		"palette": ["#0c1020", "#161d36", "#24304f", "#3a4a72", "#5f74a3", "#93abd6", "#cfe0fa", "#ffffff"],
		"seed": 6,
	},
}

const D := 12.0


# the drift's top edge, and the gusts: a sway of the whole snowfall, periodic so the loop closes
static func bank(x: float) -> float:
	return -3 + 1.6 * sin(x * 0.045 + 1.3) + 1.1 * sin(x * 0.12 + 0.4) + 0.6 * sin(x * 0.31 + 2)


static func gust(t: float) -> float:
	return 10 * sin((TAU * t) / D + 0.6) + 4 * sin((TAU * 2 * t) / D + 2.1)


# far to near: how many, falls a loop, share of a fall spent in the air (the rest lying on the drift), sway, wind
const LAYERS := [
	{"n": 230.0, "m": [1.0, 2.0], "air": 1.0, "sway": [1.0, 3.0], "wind": 3.0, "gust": 0.4},
	{"n": 140.0, "m": [2.0, 3.0], "air": 0.8, "sway": [3.0, 7.0], "wind": 6.0, "gust": 0.7},
	{"n": 24.0, "m": [2.0, 3.0], "air": 0.74, "sway": [8.0, 15.0], "wind": 9.0, "gust": 1.0},
]


static func drawBack(p: Px.Painter, t: float, o: Dictionary) -> void:
	var q := Lib.clip(p, meta)
	var S: float = o.seed
	var C := Px.fit(o.palette, 8)
	# a cold haze, thicker low down, so the sky's stars don't read as snow
	var haze := Px.mix(C[1], C[2], 0.4)
	Lib.pass_(p, meta, -170, 9, func(_x: float, y: float, out: Lib.Out) -> void:
		out.c = haze
		out.a = 0.26 + 0.22 * Px.smooth(-170, 0, y)
		out.b = 1)
	layer(q, t, S, C, 0)
	drift(q, t, S, C)
	layer(q, t, S, C, 1)


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var q := Lib.clip(p, meta)
	var S: float = o.seed
	var C := Px.fit(o.palette, 8)
	layer(q, t, S, C, 2)


static func layer(q: Px.Painter, t: float, S: float, C: Array, L: int) -> void:
	var Ly: Dictionary = LAYERS[L]
	var sd := S * 13 + L
	Lib.trips(t, D, Ly.n, sd, Ly.m[0], Ly.m[1], func(u: float, k: float, m: float, i: int) -> void:
		var j := Px.wrap(k, m)
		var dur := D / m
		var R := func(n): return Px.rand(sd, i, j, n)
		var tf: float = dur * Ly.air
		var age := minf(u * dur, tf)
		var sw: float = Ly.sway[0] + R.call(3) * (Ly.sway[1] - Ly.sway[0])
		var f: float = 0.25 + R.call(4) * 0.35
		var ph: float = R.call(5) * TAU
		var xAt := func(a: float) -> float: return -175 + R.call(2) * 350 + Ly.wind * a + (gust(t - u * dur + a) - gust(t - u * dur)) * Ly.gust + sw * sin(TAU * f * a + ph)
		var x: float = xAt.call(age)
		var xl: float = xAt.call(tf)
		var y0 := -176.0
		var y1: float = bank(xl) - 0.5 if L else -110 + R.call(1) * 106
		var y := y0 + (y1 - y0) * (age / tf)
		var rest := u * dur - tf
		if L == 0:
			# far: a speck, thinning out before it's gone
			var a := minf(1, (1 - u) * 6)
			q.dot(x, y, C[4] if R.call(6) < 0.5 else C[5], a)
			return
		var fade := 1 - rest / (dur - tf) if rest > 0 else 1.0
		if L == 1:
			# a drifting flake: a point with a smaller one beside it, a plus when it's big
			var big: bool = R.call(6) < 0.3
			if rest > 0:
				q.dot(xl, y1, C[7], fade * 0.9)
				return
			q.px(x, y, Px.WHITE if big else C[7])
			if big:
				for dd: Array in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
					q.px(x + dd[0], y + dd[1], C[5])
			else:
				q.px(x + 1, y, C[6])
				q.px(x, y + 1, C[6])
				q.px(x + 1, y + 1, C[5])
			return
		# a near crystal: six arms with side branches, spinning, a white heart, a cold glow; it lies down on the drift
		var r := 3 if R.call(6) < 0.4 else (4 if R.call(6) < 0.8 else 5)
		var spin: float = 1.5 + R.call(7) * 2.5
		if rest > 0:
			q.dot(xl - 1, y1, C[6], fade)
			q.dot(xl, y1, Px.WHITE, fade)
			q.dot(xl + 1, y1, C[6], fade)
			q.glow(xl, y1, 5, C[5], 0.25 * fade)
			return
		crystal(q, x, y, r, int(floorf(age * spin + R.call(8) * 2)) % 2, C))


# a near crystal, kept crisp: long arms on one set of four directions, short ones on the other, nubs near the
# tips; turning means trading which set is long. Plates are a ring round a bright heart.
const AXIS := [[1, 0], [-1, 0], [0, 1], [0, -1]]
const DIAG := [[1, 1], [-1, -1], [1, -1], [-1, 1]]


static func crystal(q: Px.Painter, x: float, y: float, r: int, turn: int, C: Array) -> void:
	var X := Px.round(x)
	var Y := Px.round(y)
	var long: Array = DIAG if turn else AXIS
	var short: Array = AXIS if turn else DIAG
	var R := r - 1 if turn else r
	# long arms with a white-blue tip; nubs only where they can't touch the next arm, so the gaps stay open
	for dd: Array in long:
		var dx: int = dd[0]
		var dy: int = dd[1]
		for d in range(1, R + 1):
			q.px(X + dx * d, Y + dy * d, Px.WHITE if d == R else C[6])
		var nubs: Array = ([R - 1] if R >= 3 else []) if turn else ([R - 1, R - 2] if R >= 5 else ([R - 1] if R >= 4 else []))
		for n: int in nubs:
			var ox := dx if turn else dy
			var oy := -dy if turn else -dx
			q.px(X + dx * n + (0 if turn else ox), Y + dy * n + (oy if turn else oy), C[4])
			q.px(X + dx * n + (-dx if turn else -ox) + (dx if turn else 0), Y + dy * n + (dy * 0 if turn else -oy), C[4])
	for dd: Array in short:
		var dx: int = dd[0]
		var dy: int = dd[1]
		for d in range(1, (1 if turn else maxi(1, floori(R / 2.0))) + 1):
			q.px(X + dx * d, Y + dy * d, C[6] if d == 1 else C[5])
	q.px(X, Y, Px.WHITE)
	# a faint halo, wide enough not to fill the gaps between the arms
	q.glow(X + 0.5, Y + 0.5, r * 2.5 + 5, C[5], 0.13)
	q.light(X, Y, C[6], 0.4)


# the drift on the floor: a lumpy bank with a white crest, blue shade below, and glints that twinkle
static func drift(q: Px.Painter, t: float, S: float, C: Array) -> void:
	var C4: int = C[4]
	var C5: int = C[5]
	var C6: int = C[6]
	var C7: int = C[7]
	Lib.pass_(q, meta, -7, 9, func(x: float, y: float, out: Lib.Out) -> void:
		var top := bank(x)
		var d := y - top
		if d < 0:
			return
		out.c = Px.WHITE if d < 1 else (C7 if d < 2 else (C6 if d < 3.5 else (C5 if d < 6 else C4)))
		if d < 1:
			out.l = C6
			out.k = 0.12)
	for i in 18:
		var x := -156 + Px.rand(S, i, 81) * 312
		var c := 1 + floorf(Px.rand(S, i, 82) * 3)
		var tw := sin((TAU * c * t) / D + Px.rand(S, i, 83) * TAU)
		if tw < 0.55:
			continue
		var y := ceilf(bank(x)) + floorf(Px.rand(S, i, 84) * 3)
		var k := (tw - 0.55) / 0.45
		q.px(x, y, Px.WHITE)
		if k > 0.5:
			for dd: Array in [[1, 0], [-1, 0], [0, -1]]:
				q.px(x + dd[0], y + dd[1], C[6])
		q.glow(x + 0.5, y + 0.5, 6, C[6], 0.35 * k)
