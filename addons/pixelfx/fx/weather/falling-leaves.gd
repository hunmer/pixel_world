# The falling leaf (a pendulum swing that speeds through the bottom of each arc, a tilt that follows it, a flip
# by squashing across, a rest on the ground, a litter of fallen leaves) is adapted from Sprite Fusion's
# open-source falling leaves (https://www.spritefusion.com/pixel-art-vfx/falling-leaves), MIT License,
# Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/weather/falling-leaves.js@d758e3b1cee0272df06280d928cde1d3e6452bf0
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")

static var meta := {
	"name": "Falling leaves",
	"desc": "Autumn leaves swing down through the air, tilting and flipping to show their pale backs, ride a gust, land flat in the litter and fade.",
	"tags": ["weather", "leaves", "autumn", "fall", "wind", "nature", "ambient", "loop"],
	"size": [320, 180],
	"origin": [160, 170],
	"duration": 10.0,
	"loop": true,
	"fps": 30,
	"bg": "sky",
	"options": {
		"palette": ["#4a1d0c", "#8a3a14", "#c8621e", "#f0982e", "#ffcf72", "#fff0c4"],
		"reds": ["#40101a", "#7c1c22", "#b8302a", "#e85a3c", "#ff9a72", "#ffd8c4"],
		"golds": ["#3e300c", "#7a5c14", "#b8901e", "#e8c23a", "#fff09a", "#fffbe0"],
		"seed": 8,
	},
}

const D := 10.0
const FLOOR := 1.0


static func gust(t: float) -> float:
	return 16 * sin((TAU * t) / D - 1.2) + 5 * sin((TAU * 3 * t) / D)


# ∫|cos| from the start of a swing: speeds up through the bottom of each arc, so the drop does too
static func Hc(th: float) -> float:
	var k := floorf((th + PI / 2) / PI)
	return 2 * k + 1 + sin(th - k * PI)


# a leaf's outline in its own frame: u along it (-1 stem .. 1 tip), v across; 0 inside, > 1 outside
static var SHAPES := [
	func(u: float, v: float) -> float: return 9.0 if absf(u) >= 1 else (v * v) / (0.36 * (1 - u * u) * (1.15 - 0.3 * u)),  # a beech: a long oval, pointed tip
	func(u: float, v: float) -> float:
		var r := Px.hypot(u, v * 1.1)
		var a := atan2(v, u)
		return r / (0.62 + 0.38 * pow(absf(cos(2.5 * a)), 1.5)),  # a maple: five lobes
	func(u: float, v: float) -> float: return 9.0 if absf(u) >= 1 else (v * v) / (0.16 * (1 - u * u)),  # a willow: long and thin
]


static func drawBack(p: Px.Painter, t: float, o: Dictionary) -> void:
	var q := Lib.clip(p, meta)
	var S: float = o.seed
	var R3 := ramps(o)
	var C: Array = R3[0]
	# a faint dusk haze, warmer low down, that keeps the sky's stars out of the leaves' way
	var top := Px.hex("#0e0a12")
	var low := Px.mix(Px.hex("#140c14"), C[0], 0.3)
	Lib.rows(p, meta, -170, 9, func(y: float, R: Lib.Row) -> void:
		var k := (y + 170) / 180
		var c := Px.mix(top, low, k * k)
		R.c.fill(c)
		R.a.fill(0.32 + 0.1 * k)
		R.b.fill(1))
	litter(q, S, R3)
	leaves(q, t, S, R3, false)


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	leaves(Lib.clip(p, meta), t, o.seed, ramps(o), true)


static func ramps(o: Dictionary) -> Array:
	return [Px.fit(o.palette, 6), Px.fit(o.reds, 6), Px.fit(o.golds, 6)]


static func leaves(q: Px.Painter, t: float, S: float, R3: Array, front: bool) -> void:
	Lib.trips(t, D, 62, S * 19, 2, 3, func(u: float, k: float, m: float, i: int) -> void:
		var j := Px.wrap(k, m)
		var R := func(n): return Px.rand(S * 19, i, j, n)
		var near: bool = R.call(1) < 0.35
		if near != front:
			return
		var dur := D / m
		var air := 0.72
		var tf := dur * air
		var a := minf(u * dur, tf)
		var rest := u * dur - tf
		var w: float = 1.7 + R.call(2) * 1.2
		var ph0: float = R.call(3) * TAU
		var amp: float = (14 if near else 8) + R.call(4) * 10
		var x0: float = -180 + R.call(5) * 340
		var y0 := -186.0
		# the drop speed that lands it on the floor just as its time in the air runs out
		var path := func(aa: float) -> float: return 0.45 * aa + (0.9 * (Hc(w * aa + ph0) - Hc(ph0))) / w
		var vy: float = (FLOOR - y0) / path.call(tf)
		var born := t - u * dur
		var xAt := func(aa: float) -> float: return x0 + 7 * aa + sin(w * aa + ph0) * amp + (gust(born + aa) - gust(born)) * (1.0 if near else 0.7)
		var size: float = (5.8 if near else 4.2) + R.call(6) * 1.6
		var shape := floori(R.call(7) * 3)
		var col: Array = R3[floori(R.call(8) * 3)]
		if rest > 0:
			# lying flat in the litter, fading
			var fade := 1 - rest / (dur - tf)
			leaf(q, xAt.call(tf), FLOOR - 1, size, (R.call(9) - 0.5) * 0.5, 0.42, shape, col, fade)
			return
		var x: float = xAt.call(a)
		var y: float = y0 + vy * path.call(a)
		var tilt := cos(w * a + ph0) * 0.75 + (0.0 if near else 0.3)
		var flip := cos(R.call(10) * TAU + a * (5.0 if R.call(11) < 0.3 else 1.2))
		leaf(q, x, y, size, tilt, flip, shape, col, 1)
		# a leaf turned full face to the light catches it for a moment
		if flip > 0.86:
			var kk := (flip - 0.86) / 0.14
			var hx := x - cos(tilt) * size * 0.3
			var hy := y - sin(tilt) * size * 0.3 - 1
			q.px(hx, hy, col[5])
			q.glow(hx, hy, 5 + size * 0.5, col[4], 0.22 * kk))


# draw a leaf: squash it across by `flip` (the sign says which face shows), tilt it, outline it, a midrib down
# the middle, the face lit on one side; the back face is paler and duller
static func leaf(q: Variant, x: float, y: float, size: float, ang: float, flip: float, shape: int, col: Array, a: float) -> void:
	# like a card turning: never thinner than a third, and the back shows only past edge-on
	var back := flip < -0.25
	var fs := 0.35 + 0.65 * absf(flip)
	var c := cos(ang)
	var s := sin(ang)
	var L := size
	var Wd := size * 0.9
	var ext := L + 1.5
	var shapeFn: Callable = SHAPES[shape]
	var face: Array = [Px.mix(col[1], Px.hex("#9c8a78"), 0.2), Px.mix(col[2], Px.hex("#c8b49c"), 0.22), Px.mix(col[3], Px.hex("#e0d0b8"), 0.22)] if back else [col[2], col[3], col[4]]
	var rim: int = col[0]
	var vein: int = Px.mix(col[2], Px.hex("#e8dcc8"), 0.5) if back else col[1]
	q.shade(x - ext, y - ext, x + ext, y + ext, func(px: float, py: float, out) -> void:
		var dx := px - x
		var dy := py - y
		var lu := (dx * c + dy * s) / L
		var lv := (-dx * s + dy * c) / (Wd * fs)
		var d: float = shapeFn.call(lu, lv)
		if lu < -1.25 or lu > 1.1:
			return
		# the stem pokes out past the base
		if lu < -0.92 and absf(lv * Wd * fs) < 0.5:
			out.c = rim
			out.a = a
			return
		if d > 1.32:
			return
		out.a = a
		if d > 1:
			out.c = rim
		elif absf(lv * Wd * fs) < 0.45 and lu > -0.9 and lu < 0.75:
			out.c = vein
		else:
			out.c = face[2] if lv < -0.15 else (face[1] if lv < 0.35 else face[0]))


# JS litter()'s `rec`: a stand-in painter whose shade() records the pixels instead of drawing them
class Rec:
	var px: Array

	func _init(out: Array) -> void:
		px = out

	func shade(x0: float, y0: float, x1: float, y1: float, fn: Callable) -> void:
		var o := {"c": 0, "a": 1.0}
		for y in range(floori(y0), ceili(y1) + 1):
			for x in range(floori(x0), ceili(x1) + 1):
				o.c = 0
				o.a = 1.0
				var ret: Variant = fn.call(x + 0.5, y + 0.5, o)
				var c: Variant = ret if ret else o.c
				if c:
					px.append(x + 0.5)
					px.append(y + 0.5)
					px.append(c)
					px.append(o.a)


# fallen leaves lying in a band along the floor, overlapping. They never move, so they're shaded once per seed
# and palette and the pixels replayed
static var LITTER := {}


static func litter(q: Px.Painter, S: float, R3: Array) -> void:
	var flat := []
	for r: Array in R3:
		flat.append_array(r)
	var key := var_to_str(S) + ",".join(flat.map(func(c): return str(c)))
	var px: Variant = LITTER.get(key)
	if not px:
		px = []
		var rec := Rec.new(px)
		for i in 64:
			var x := -164 + Px.rand(S, i, 91) * 328
			var y := FLOOR - 2 + floorf(Px.rand(S, i, 92) * 4) * 2
			var col: Array = R3[floori(Px.rand(S, i, 93) * 3)]
			leaf(rec, x, y, 3.6 + Px.rand(S, i, 94) * 1.8, (Px.rand(S, i, 95) - 0.5) * 0.7, 0.45 + Px.rand(S, i, 96) * 0.25, floori(Px.rand(S, i, 97) * 3), col.map(func(c): return Px.mix(c, col[0], 0.12)), 1)
		LITTER[key] = px
	var i := 0
	while i < px.size():
		q.dot(px[i], px[i + 1], px[i + 2], px[i + 3])
		i += 4
