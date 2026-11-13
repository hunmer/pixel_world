# Snow driven near-flat by the wind (depth layers of streaks, a gusty wind) after Sprite Fusion's open-source snow
# (https://www.spritefusion.com/pixel-art-vfx/snow), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/weather/blizzard.js@c906269a2a79d4678a323741c8138a0bd447e51f
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")

static var meta := {
	"name": "Blizzard",
	"desc": "Snow driven almost flat by a gale: streaks at three depths race past, gusts throw translucent sheets of snow across the sky and spindrift streams off the drifts.",
	"tags": ["weather", "blizzard", "snow", "wind", "storm", "winter", "ambient", "loop"],
	"size": [320, 180],
	"origin": [160, 170],
	"duration": 8.0,
	"loop": true,
	"fps": 30,
	"bg": "sky",
	"options": {
		"palette": ["#0d111f", "#182035", "#27324d", "#3e4d6e", "#64779c", "#9cb0d0", "#d8e4f6", "#ffffff"],
		"seed": 9,
	},
}

const D := 8.0


# gusts: waves of wind rolling left to right, a whole number a loop
static func gustAt(x: float, t: float) -> float:
	return 0.5 + 0.5 * sin(TAU * ((x + 160) / 400 - (2 * t) / D) + 0.8)


static func bank(x: float) -> float:
	return -2 + 1.2 * sin(x * 0.05 + 2) + 0.8 * sin(x * 0.15 + 1)


# far to near: how many, crossings a loop, streak length, fall while crossing, colors (tail, body, head)
const LAYERS := [
	{"n": 240.0, "m": [3.0, 4.0], "len": [2.0, 4.0], "drop": [10.0, 40.0], "col": [3, 4, 5]},
	{"n": 130.0, "m": [4.0, 5.0], "len": [5.0, 8.0], "drop": [20.0, 60.0], "col": [4, 5, 6]},
	{"n": 34.0, "m": [6.0, 7.0], "len": [10.0, 16.0], "drop": [30.0, 70.0], "col": [4, 6, 7], "near": true},
]


static func drawBack(p: Px.Painter, t: float, o: Dictionary) -> void:
	var q := Lib.clip(p, meta)
	var S: float = o.seed
	var C := Px.fit(o.palette, 8)
	sheets(p, t, S, C, 0)
	streaks(q, t, S, C, 0)
	streaks(q, t, S, C, 1)
	ground(p, q, t, S, C)


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var q := Lib.clip(p, meta)
	var S: float = o.seed
	var C := Px.fit(o.palette, 8)
	sheets(p, t, S, C, 1)
	streaks(q, t, S, C, 2)


# streaks: each slot crosses the canvas a whole number of times a loop at its own height, dipping as it goes;
# the gusts stretch and brighten it
static func streaks(q: Px.Painter, t: float, S: float, C: Array, L: int) -> void:
	var Ly: Dictionary = LAYERS[L]
	var sd := S * 17 + L
	var c0: int = C[Ly.col[0]]
	var c1: int = C[Ly.col[1]]
	var c2: int = C[Ly.col[2]]
	var near: bool = Ly.get("near", false)
	Lib.trips(t, D, Ly.n, sd, Ly.m[0], Ly.m[1], func(u: float, k: float, m: float, i: int) -> void:
		var j := Px.wrap(k, m)
		var R := func(n): return Px.rand(sd, i, j, n)
		var drop: float = Ly.drop[0] + R.call(3) * (Ly.drop[1] - Ly.drop[0])
		var x := -190 + 380 * u
		var y: float = -178 + R.call(1) * 182 + drop * u + 3 * sin(u * TAU * (1 + R.call(5)) + R.call(6) * 6)
		if y > bank(x) - 1:
			return
		var g := gustAt(x, t)
		# between gusts the far snow thins out; in a gust it's everywhere
		if not near and R.call(7) > 0.45 + 0.75 * g:
			return
		var L_: float = (Ly.len[0] + R.call(2) * (Ly.len[1] - Ly.len[0])) * (0.7 + 0.6 * g)
		var dx := 380 / (D / m)
		var dy := drop / (D / m)
		var l := Px.hypot(dx, dy)
		var ux := dx / l
		var uy := dy / l
		q.line(x - ux * L_, y - uy * L_, x - ux * L_ * 0.45, y - uy * L_ * 0.45, c0, func(v): return 0.3 + 0.7 * v)
		q.line(x - ux * L_ * 0.45, y - uy * L_ * 0.45, x - ux, y - uy, c1)
		q.px(x, y, Px.WHITE if g > 0.6 and near else c2)
		if near:
			q.glow(x, y, 5, C[5], 0.12 + 0.12 * g))


# sheets of blown snow: long thin translucent bands racing with the wind, thick in a gust and thin between
static var GX := _f32(320)
static var WV := _f32(320)


static func _f32(n: int) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(n)
	return a


static func sheets(p: Px.Painter, t: float, S: float, C: Array, near: int) -> void:
	var F := Lib.field(S * 3 + 7 + near, 256, 128)
	var shift := (256 * (3 if near else 2) * t) / D
	var c: int = C[6] if near else C[5]
	var y0 := -110.0 if near else -170.0
	var haze := Px.mix(C[2], C[3], 0.5)
	var sy := 4.5 if near else 3.2
	var th := 0.58 if near else 0.54
	for i in 320:
		GX[i] = gustAt(i - 160 + 0.5, t)
		WV[i] = 5 * sin((i - 160) * 0.021 - (TAU * t) / D + near * 2)
	var gx := GX
	var wv := WV
	var C5: int = C[5]
	Lib.rows(p, meta, y0, 4, func(y: float, R: Lib.Row) -> void:
		var Rc := R.c
		var Ra := R.a
		var Rb := R.b
		var Rl := R.l
		var Rk := R.k
		var fade := Px.smooth(-110, -40, y) if near else 1.0
		for i in 320:
			var g := gx[i]
			var n := Lib.sample(F, (i - 160) * 0.16 - shift, (y + wv[i]) * sy + 40)
			var d := (n - th) * 2.2 * (0.35 + g) * fade
			# the far pass is also the whiteout haze behind everything, thicker in a gust
			if near:
				if d <= 0.02:
					continue
				Rc[i] = c
				Ra[i] = minf(0.5, d)
			else:
				Rc[i] = c if d > 0.08 else haze
				Ra[i] = 0.3 + 0.12 * g + minf(0.42, maxf(0, d))
			Rb[i] = 1
			if d > 0.05:
				Rl[i] = C5
				Rk[i] = d * 0.08)


# the ground: a low drift with a white crest, spindrift streaming low along it, plumes blown off the crest
static func ground(p: Px.Painter, q: Px.Painter, t: float, S: float, C: Array) -> void:
	var F := Lib.field(S * 5 + 1, 256, 128)
	var shift := (256 * 4 * t) / D
	for i in 320:
		GX[i] = gustAt(i - 160 + 0.5, t)
		WV[i] = bank(i - 160 + 0.5)
	var gx := GX
	var wv := WV
	var C4: int = C[4]
	var C5: int = C[5]
	var C6: int = C[6]
	Lib.rows(p, meta, -16, 9, func(y: float, R: Lib.Row) -> void:
		var Rc := R.c
		var Ra := R.a
		var Rb := R.b
		var Rl := R.l
		var Rk := R.k
		for i in 320:
			var x := i - 160 + 0.5
			var top := wv[i]
			var d := y - top
			if d >= 0:
				Rc[i] = Px.WHITE if d < 1 else (C6 if d < 2 else (C5 if d < 4 else C4))
				if d < 1:
					Rl[i] = C6
					Rk[i] = 0.1
				continue
			# spindrift: a low, fast, streaky haze hugging the drift
			if y < -14:
				continue
			var n := Lib.sample(F, x * 0.5 - shift, y * 3 + 9)
			var s := (n - 0.5) * 3 * Px.smooth(-14, -1, y) * (0.4 + gx[i])
			if s > 0.02:
				Rc[i] = C6
				Ra[i] = minf(0.55, s)
				Rb[i] = 1)
	# grains skipping along the crest
	Lib.trips(t, D, 40, S * 23, 8, 10, func(u: float, k: float, m: float, i: int) -> void:
		var j := Px.wrap(k, m)
		var x := -175 + 350 * u
		var y := bank(x) - 1 - Px.rand(S, i, j, 1) * 6 * absf(sin(u * 9 + i))
		q.px(x, y, Px.WHITE if Px.rand(S, i, j, 2) < 0.5 else C[6])
		q.px(x - 1, y, C[5]))
