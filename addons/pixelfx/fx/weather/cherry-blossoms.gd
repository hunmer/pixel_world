# Things that flutter down (a fall timed to land as their time in the air runs out, a flip by squashing across,
# a rest on the ground and a fade) after Sprite Fusion's open-source falling leaves
# (https://www.spritefusion.com/pixel-art-vfx/falling-leaves), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/weather/cherry-blossoms.js@768097439f72fb08a6a6f969e65761321d9bc763
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")

static var meta := {
	"name": "Cherry blossoms",
	"desc": "Pink petals flutter down on a spring breeze, tumbling in little spirals and flashing as they catch the light, with a few whole blossoms spinning among them.",
	"tags": ["weather", "cherry blossom", "sakura", "petals", "spring", "wind", "ambient", "loop"],
	"size": [320, 180],
	"origin": [160, 170],
	"duration": 10.0,
	"loop": true,
	"fps": 30,
	"bg": "sky",
	"options": {
		"palette": ["#4a1832", "#8e3460", "#d26a94", "#f2a2c0", "#ffd2e2", "#fff4f8"],
		"seed": 12,
	},
}

const D := 10.0
const FLOOR := 1.0


static func gust(t: float) -> float:
	return 22 * sin((TAU * t) / D + 0.4) + 7 * sin((TAU * 2 * t) / D - 1)


static func drawBack(p: Px.Painter, t: float, o: Dictionary) -> void:
	var q := Lib.clip(p, meta)
	var S: float = o.seed
	var C := Px.fit(o.palette, 6)
	# a soft plum dusk, so the sky's stars don't read as petals
	var top := Px.hex("#0e0a14")
	var low := Px.mix(Px.hex("#1a0e1a"), C[0], 0.4)
	Lib.rows(p, meta, -170, 9, func(y: float, R: Lib.Row) -> void:
		var k := (y + 170) / 180
		R.c.fill(Px.mix(top, low, k * k))
		R.a.fill(0.3 + 0.12 * k)
		R.b.fill(1))
	scatter(q, S, C)
	petals(q, t, S, C, 0)


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var q := Lib.clip(p, meta)
	var S: float = o.seed
	var C := Px.fit(o.palette, 6)
	petals(q, t, S, C, 1)
	blossoms(q, t, S, C)


# petals: each tumbles in a little spiral as it falls and drifts on the breeze, flipping fast; turned full face
# to the light it flashes
static func petals(q: Px.Painter, t: float, S: float, C: Array, near: int) -> void:
	var n := 54 if near else 90
	var sd := S * 7 + near
	Lib.trips(t, D, n, sd, 1, 2, func(u: float, k: float, m: float, i: int) -> void:
		var j := Px.wrap(k, m)
		var R := func(c): return Px.rand(sd, i, j, c)
		var dur := D / m
		var tf := dur * 0.84
		var a := minf(u * dur, tf)
		var rest := u * dur - tf
		var born := t - u * dur
		var x0: float = -200 + R.call(1) * 330
		var y0 := -184.0
		var vy := (FLOOR + (2 if near else 0) - y0) / tf
		var vx: float = 9 + R.call(2) * 10
		var rho: float = (3 if near else 2) + R.call(3) * 3
		var w: float = 2.2 + R.call(4) * 2.8
		var ph: float = R.call(5) * TAU
		var gk := 1.0 if near else 0.6
		var at := func(aa: float) -> Array: return [x0 + vx * aa + (gust(born + aa) - gust(born)) * gk + rho * cos(w * aa + ph), y0 + vy * aa + rho * 0.6 * sin(w * aa + ph)]
		var len_: float = (3.6 if near else 2.6) + R.call(6) * 1.1
		if rest > 0:
			var xy: Array = at.call(tf)
			# a landed petal settles and shrinks away (no dither, so the ground stays clean)
			var fade := 1 - rest / (dur - tf)
			if fade > 0.15:
				petal(q, xy[0], xy[1], len_ * (0.35 + 0.65 * fade), (R.call(7) - 0.5) * 1.2, 0.5, C, 1)
			return
		var xy: Array = at.call(a)
		var x: float = xy[0]
		var y: float = xy[1]
		var flip := cos(R.call(8) * TAU + a * (3 + R.call(9) * 5))
		var ang: float = R.call(10) * TAU + a * (R.call(11) - 0.5) * 3
		petal(q, x, y, len_, ang, flip, C, 1)
		if flip > 0.9:
			var g := (flip - 0.9) / 0.1
			q.px(x, y - 1, Px.WHITE)
			q.glow(x, y, 7 if near else 5, C[4], (0.32 if near else 0.22) * g))


# a petal: a little notched teardrop, squashed across as it flips; its pale face or its deeper back
static func petal(q: Variant, x: float, y: float, len_: float, ang: float, flip: float, C: Array, a: float) -> void:
	var fs := 0.3 + 0.7 * absf(flip)
	var back := flip < -0.2
	var c := cos(ang)
	var s := sin(ang)
	var e := len_ + 1
	# deeper at the base, palest at the tip, lit on one side; the back is a step deeper all over
	var face: Array = [C[1], C[2], C[3]] if back else [C[2], C[3], C[4]]
	var tip: int = C[3] if back else C[5]
	q.shade(x - e, y - e, x + e, y + e, func(px: float, py: float, out) -> void:
		var dx := px - x
		var dy := py - y
		var u := (dx * c + dy * s) / len_
		var v := (-dx * s + dy * c) / (len_ * fs)
		if u < -1 or u > 1:
			return
		var hw := 0.55 * sqrt(1 - u * u) * (1 + 0.35 * u)
		if absf(v) > hw or (u > 0.7 and absf(v) < 0.12):
			return
		out.c = tip if (u > 0.45 and v < 0.1) else (face[0] if u < -0.45 else (face[2] if v < 0 else face[1]))
		out.a = a)


# a whole blossom: five petals round a gold heart, spinning slowly as it sinks
static func blossoms(q: Px.Painter, t: float, S: float, C: Array) -> void:
	Lib.trips(t, D, 7, S * 31, 1, 1, func(u: float, _k: float, _m: float, i: int) -> void:
		var R := func(c): return Px.rand(S * 31, i, c)
		var y := -190 + (FLOOR + 2 + 190) * minf(1, u / 0.9)
		var born := t - u * D
		if u > 0.9:
			return
		var x: float = -190 + R.call(1) * 330 + 14 * u * D * 0.1 + (gust(t) - gust(born)) + 6 * sin(u * TAU * 2 + R.call(2) * 6)
		var rot: float = R.call(3) * TAU + u * D * (R.call(4) - 0.5) * 2
		var r: float = 3.6 + R.call(5) * 1.2
		for p in 5:
			var an := rot + (p * TAU) / 5
			petal(q, x + cos(an) * r * 0.75, y + sin(an) * r * 0.75, r * 0.7, an, 1, C, 1)
		q.px(x, y, Px.hex("#ffe08a"))
		q.glow(x, y, 8, C[4], 0.2))


# JS scatter()'s `rec`: a stand-in painter whose shade() records the pixels instead of drawing them
class Rec:
	var px: Array

	func _init(out: Array) -> void:
		px = out

	func shade(x0: float, y0: float, x1: float, y1: float, fn: Callable) -> void:
		var o := {"c": 0, "a": 1.0}
		for y in range(floori(y0), ceili(y1) + 1):
			for x in range(floori(x0), ceili(x1) + 1):
				o.c = 0
				var ret: Variant = fn.call(x + 0.5, y + 0.5, o)
				var c: Variant = ret if ret else o.c
				if c:
					px.append(x + 0.5)
					px.append(y + 0.5)
					px.append(c)
					px.append(o.a)


# petals already fallen, scattered along the floor; they never move, so they're shaded once and replayed
static var SCATTER := {}


static func scatter(q: Px.Painter, S: float, C: Array) -> void:
	var key := var_to_str(S) + ",".join(C.map(func(c): return str(c)))
	var px: Variant = SCATTER.get(key)
	if not px:
		px = []
		var rec := Rec.new(px)
		for i in 46:
			petal(rec, -164 + Px.rand(S, i, 71) * 328, FLOOR + floorf(Px.rand(S, i, 72) * 3) * 2, 2.6 + Px.rand(S, i, 73), (Px.rand(S, i, 74) - 0.5) * 1.2, 0.5, C, 1)
		SCATTER[key] = px
	var i := 0
	while i < px.size():
		q.dot(px[i], px[i + 1], px[i + 2], px[i + 3])
		i += 4
