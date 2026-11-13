# The rain recipe (depth layers of two-tone streaks, far drops that end in the air, near ones that splash and
# throw droplets, mist low on the ground) is adapted from Sprite Fusion's open-source rain
# (https://www.spritefusion.com/pixel-art-vfx/rain), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/weather/rain.js@20fe94ba69d0262151a65e38ff8a0bf90b043b75
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")

static var meta := {
	"name": "Rain",
	"desc": "Slanted rain at four depths: far drops fade into the dark, near ones glint and splash, drops ring the puddles and a low mist drifts over the wet floor.",
	"tags": ["weather", "rain", "storm", "water", "ambient", "loop"],
	"size": [320, 180],
	"origin": [160, 170],
	"duration": 8.0,
	"loop": true,
	"fps": 30,
	"bg": "sky",
	"options": {
		"palette": ["#0e1322", "#1a2440", "#283a5e", "#3a5482", "#5674a8", "#84a6d6", "#c0dcf8", "#f2f8ff"],
		"density": 1,
		"seed": 4,
	},
}

const D := 8.0
const SLANT := -0.2
static var UX := SLANT / Px.hypot(SLANT, 1)
static var UY := 1 / Px.hypot(SLANT, 1)
# the depths, far to near: how many, falls a loop (speed), streak length, colors (tail, body, head), where
# they end (in the air, or on the floor at depth z), how big their splash
const LAYERS := [
	{"n": 200.0, "m": [10.0, 13.0], "len": 2.0, "col": [2, 2, 3], "stop": [-80.0, -6.0]},
	{"n": 150.0, "m": [14.0, 17.0], "len": 4.0, "col": [2, 3, 4], "stop": [-45.0, -2.0]},
	{"n": 96.0, "m": [19.0, 23.0], "len": 7.0, "col": [3, 4, 5], "z": [0.0, 1.4], "size": [0.15, 0.4]},
	{"n": 42.0, "m": [25.0, 29.0], "len": 13.0, "col": [3, 5, 7], "z": [2.0, 6.5], "size": [0.6, 1.0], "near": true},
]


# puddles on the wet floor: long thin strips that hold the sky, at depth y, from x0 to x1
static func pools(S: float) -> Array:
	return Px.arr(5, func(i: int):
		var x := -150 + i * 66 + Px.rand(S, i, 61) * 30
		var w := 16 + Px.rand(S, i, 63) * 26
		return {"x0": x, "x1": x + w, "y": 3 + floorf(Px.rand(S, i, 62) * 3)})


static func poolAt(P: Array, x: float, y: float) -> Variant:
	for p: Dictionary in P:
		if x >= p.x0 + 2 and x <= p.x1 - 2 and absf(y - p.y) < 1.5:
			return p
	return null


static func drawBack(p: Px.Painter, t: float, o: Dictionary) -> void:
	t = Px.round(t * 3e4) / 3e4
	var q := Lib.clip(p, meta)
	var S: float = o.seed
	var C := Px.fit(o.palette, 8)
	var P := pools(S)
	# an overcast haze, thicker toward the ground, that hides the stars
	var haze := Px.mix(C[0], C[1], 0.6)
	Lib.pass_(p, meta, -170, -0.5, func(_x: float, y: float, out: Lib.Out) -> void:
		out.c = haze
		out.a = 0.3 + 0.26 * Px.smooth(-170, 0, y)
		out.b = 1)
	floor_(q, t, S, C, P)
	for L in 3:
		layer(q, t, S, C, P, L, o.density)
	mist(p, t, S, C)


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	t = Px.round(t * 3e4) / 3e4
	var q := Lib.clip(p, meta)
	var S: float = o.seed
	var C := Px.fit(o.palette, 8)
	var P := pools(S)
	layer(q, t, S, C, P, 3, o.density)


# one depth of rain: each slot falls a whole number of times a loop, somewhere new each time
static func layer(q: Px.Painter, t: float, S: float, C: Array, P: Array, L: int, density: float) -> void:
	var Ly: Dictionary = LAYERS[L]
	var sd := S * 11 + L
	var c0: int = C[Ly.col[0]]
	var c1: int = C[Ly.col[1]]
	var c2: int = C[Ly.col[2]]
	var len_: float = Ly.len
	var n := Px.round(Ly.n * density)
	var G := Lib.field(S + 21, 256, 128, [4, 8, 16])
	var sweep := (256 * t) / D
	var hasZ := Ly.has("z")
	var near: bool = Ly.get("near", false)
	var ux := UX
	var uy := UY
	Lib.trips(t, D, n, sd, Ly.m[0], Ly.m[1], func(u: float, k: float, m: float, i: int) -> void:
		var j := Px.wrap(k, m)
		# gusts: sheets of heavier and lighter rain sweep across with the wind
		if L < 2 and Px.rand(sd, i, j, 7) > 0.35 + 1.3 * (Lib.sample(G, (-166 + Px.rand(sd, i, j, 2) * 332) * 0.8 + sweep, 9 + L * 40) - 0.32):
			return
		var end: float = Ly.z[0] + Px.rand(sd, i, j, 1) * (Ly.z[1] - Ly.z[0]) if hasZ else Ly.stop[0] + Px.rand(sd, i, j, 1) * (Ly.stop[1] - Ly.stop[0])
		var y0 := -172 - len_
		var y := y0 + (end - y0) * u
		var x := -166 + Px.rand(sd, i, j, 2) * 332 - (end - y) * SLANT
		# far drops thin out before they end; near ones are whole
		var a := 1.0 if hasZ else minf(1, (1 - u) * 5)
		if len_ <= 2:
			q.dot(x, y, c2, a)
			q.dot(x - ux, y - uy, c1, a * 0.8)
		else:
			q.line(x - ux * len_, y - uy * len_, x - ux * len_ * 0.45, y - uy * len_ * 0.45, c0, func(v): return a * (0.35 + 0.65 * v))
			q.line(x - ux * len_ * 0.45, y - uy * len_ * 0.45, x - ux, y - uy, c1, a)
			q.dot(x, y, c2, a)
		# near drops catch the light
		if near:
			q.glow(x, y - 2, 4, C[5], 0.12)
		if not hasZ:
			return
		# the drops before this one landed: a crown on the ground, or rings sliding apart along a puddle
		var dur := D / m
		for back in range(1, 4):
			var age := u * dur + (back - 1) * dur
			if age > 0.7:
				break
			var jp := Px.wrap(k - back, m)
			var z: float = Ly.z[0] + Px.rand(sd, i, jp, 1) * (Ly.z[1] - Ly.z[0])
			var xp := -166 + Px.rand(sd, i, jp, 2) * 332
			if Px.rand(sd, i, jp, 5) > (1.0 if near else 0.7):
				continue
			var size: float = Ly.size[0] + ((z - Ly.z[0]) / (Ly.z[1] - Ly.z[0])) * (Ly.size[1] - Ly.size[0])
			var pool: Variant = poolAt(P, xp, z) if near else null
			if pool:
				rings(q, xp, pool, age, C)
			elif Lib.crown(q, xp, z, age, size, {"hot": C[6], "cool": C[4], "white": Px.WHITE}, Px.rand(sd, i, jp, 4)) and near and age < 0.1:
				q.glow(xp, z - 1, 5, C[5], 0.3 * (1 - age / 0.1)))


# a drop in a puddle: a bright point, then rings seen edge-on, so two short dashes sliding apart, twice
static func rings(q: Px.Painter, x: float, pool: Dictionary, age: float, C: Array) -> void:
	var X := Px.round(x)
	var y: float = pool.y
	if age < 0.05:
		q.px(X, y, C[7])
	for r in 2:
		var a := age - r * 0.16
		var u := a / 0.5
		if u <= 0 or u >= 1:
			continue
		var w := Px.round(1 + 7 * sqrt(u))
		var c: int = C[6] if (u < 0.4 and not r) else C[5]
		for s: int in [-1, 1]:
			for d in (2 if u < 0.6 else 1):
				var px := X + s * (w - d)
				if px > pool.x0 and px < pool.x1:
					q.px(px, y, c)


# the wet floor: a clean wet edge (a lit lip over a dark line), a dark sheen, puddle strips holding the sky
static func floor_(q: Px.Painter, t: float, _S: float, C: Array, P: Array) -> void:
	var C0: int = C[0]
	var C1: int = C[1]
	var C3: int = C[3]
	var C4: int = C[4]
	var C5: int = C[5]
	Lib.pass_(q, meta, 0, 9.5, func(x: float, y: float, out: Lib.Out) -> void:
		if y < 1:
			out.c = C4
			out.l = C5
			out.k = 0.08
			return
		if y < 2:
			out.c = C1
			return
		out.c = C0
		out.a = 0.55
		out.b = 1
		for p: Dictionary in P:
			if x >= p.x0 and x < p.x1 and floorf(y) == p.y:
				var edge: bool = x < p.x0 + 2 or x >= p.x1 - 2
				out.c = C3 if edge else C4
				out.a = 1
				out.b = 0
				out.l = C5
				out.k = 0.06)
	# a glint that slides slowly along each puddle
	for i in P.size():
		var p: Dictionary = P[i]
		var gx := Px.round(p.x0 + 3 + (p.x1 - p.x0 - 6) * (0.5 + 0.5 * sin((PI * 2 * t) / D + i * 1.9)))
		q.px(gx, p.y, C[6])
		q.glow(gx, p.y, 4, C[5], 0.2)


# mist kicked up by the rain, drifting low along the ground: soft bands with lit crests
static func mist(p: Px.Painter, t: float, S: float, C: Array) -> void:
	var M := Lib.field(S + 9, 256, 128, [4, 8, 16, 32])
	var drift := (256 * t) / D
	var crest := Px.mix(C[4], C[5], 0.5)
	var C3: int = C[3]
	var C4: int = C[4]
	Lib.pass_(p, meta, -20, 9, func(x: float, y: float, out: Lib.Out) -> void:
		var d := dens(M, drift, x, y)
		if d < 0.28:
			return
		var th := Lib.bayer(x, y) * 0.06
		out.b = 1
		if d > 0.46 + th and dens(M, drift, x, y - 1) < 0.43:
			out.c = crest
			out.a = 0.5
		else:
			out.c = C4 if d > 0.58 + th else C3
			out.a = Px.clamp((d - 0.28) * 1.6) * 0.5
		out.l = C4
		out.k = (d - 0.3) * 0.1)


# mist()'s dens(x, y)
static func dens(M: Lib.Field, drift: float, x: float, y: float) -> float:
	var prof := Px.smooth(-22, -4, y) * (1 - Px.smooth(7, 10, y))
	return prof * (0.62 + (Lib.sample(M, x * 0.45 + drift, y * 4 + 30) - 0.5) * 2)
