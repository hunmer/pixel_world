# The flame tongues, embers and thin smoke are
# adapted from Sprite Fusion's open-source fire (https://www.spritefusion.com/pixel-art-vfx/fire),
# MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/status/burning.js@d28f251c8bfae13cd11d1179c849cdbf6f0d7d69
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Burning",
	"desc": "Burning over time: small flames lick from four hot spots, trailing sparks and thin smoke; every 0.6 s they flare, the body flashes white then orange, scorch marks spread.",
	"tags": ["status", "fire", "burn", "dot", "debuff", "loop"],
	"size": [72, 80],
	"origin": [36, 70],
	"duration": 1.2,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {
		"palette": ["#4a1712", "#8a1f17", "#c9281f", "#f2561d", "#ff8a2a", "#ffc23d", "#ffe26b", "#fff3a6", "#ffffff"],
		"char": ["#120c0a", "#2a1a14", "#4a2c1c"],
		"smoke": "#5b5566",
		"seed": 3,
	},
}

static var A_ := {"turn": 1, "crouch": 2, "lean": 2, "fx": -13, "fy": -38, "bx": 12, "by": -17, "ffx": -3, "ffy": -7, "fbx": 5}
static var B_ := {"turn": 0.9, "crouch": 3, "lean": -2, "fx": -12, "fy": -17, "bx": 13, "by": -38, "ffx": -4, "fbx": 4, "fby": -7}
static var act := {
	"onBody": true,
	"poses": [[0, A_], [0.15, B_, "snap"], [0.3, A_, "snap"], [0.45, B_, "snap"], [0.6, A_, "snap"], [0.75, B_, "snap"], [0.9, A_, "snap"], [1.05, B_, "snap"], [1.2, A_, "snap"]],
}

static var D: float = meta.duration
const TICK := 0.6
const WIND := -14.0
static func since(t: float) -> float:
	return fmod(fmod(t, TICK) + TICK, TICK)
static func flare(t: float) -> float:
	return exp(-since(t) / 0.12)
## The stand-in is hidden for the one white frame of each tick (the effect draws the body then).
static func actorAlpha(t: float, _o: Dictionary) -> float:
	return 0.0 if since(t) < 0.034 else 1.0

# the hot spots on the outline: the hair tips, a shoulder, the back, a sleeve; scorch spots near them per tick
static var SPOTS := {}
static func spots(a: Dictionary, seed: float) -> Dictionary:
	var s: Variant = SPOTS.get(a.mask.id)
	if not s:
		s = {}
		SPOTS[a.mask.id] = s
	if s.has(seed):
		return s[seed]
	var S := Lib.shape(a)
	var H: int = S.h
	var W: int = S.w
	var R := Px.Rng.new(seed * 13.0 + 5.0)
	var at := func(q: float, side: int) -> Array:
		var my := Px.roundi(H * q)
		var lr: Array = S.rows[my]
		return [lr[0] if side < 0 else lr[1], my]
	var hairs: Array = Px.sort(S.up.filter(func(xy): return xy[0] < W * 0.42), func(p, q): return (p[1] - q[1]) if (p[1] - q[1]) else (p[0] - q[0]))
	var hair: Variant = hairs[0]
	var sh: Array = Px.sort(S.up.filter(func(xy): return xy[0] > W / 2.0 and xy[1] > H * 0.4 and xy[1] < H * 0.62), func(p, q): return p[1] - q[1])
	var shoulder: Variant = sh[0] if sh.size() else at.call(0.5, 1)
	var list0 := [
		{"at": hair, "side": -1, "n": 3, "h": 4.5},
		{"at": shoulder, "side": 1, "n": 2, "h": 4.0},
		{"at": at.call(0.62, -1), "side": -1, "n": 2, "h": 3.5},
		{"at": at.call(0.6, 1), "side": 1, "n": 2, "h": 3.5},
	]
	var list := []
	for i in list0.size():
		var sp: Dictionary = list0[i]
		var tongues := Px.arr(sp.n, func(j: int): return {"dx": (j - (sp.n - 1) / 2.0) * 1.6 + R.range(-0.4, 0.4), "h": sp.h * R.range(0.8, 1.2), "n": i * 17 + j * 5 + seed})
		list.append(Px.merge(sp, {"x": a.x + sp.at[0] + 0.5, "y": a.y + sp.at[1] + 1.5, "tongues": tongues}))
	# scorch marks: each tick chars two patches on the clothes near the spots
	var scorch := []
	for tick in [0, 1]:
		var row := []
		for k in [0, 1]:
			# on the clothes (mid-tones, where char shows), near a hot spot
			var sp: Dictionary = list[(tick * 2 + k + 1) % list.size()]
			var lum := func(x: int, y: int) -> float: return Px.luma(Lib.colorAt(a, x, y))
			var cand: Array = S.body.filter(func(xy): return Px.hypot(a.x + xy[0] + 0.5 - sp.x, a.y + xy[1] + 0.5 - sp.y) < 9.0 and xy[1] > H * 0.42 and lum.call(xy[0], xy[1]) > 0.3 and lum.call(xy[0], xy[1]) < 0.6)
			if not cand.size():
				cand = S.body.filter(func(xy): return xy[1] > H * 0.45)
			var xy: Array = cand[floori(R.next() * cand.size())]
			row.append({"x": a.x + xy[0] + 0.5, "y": a.y + xy[1] + 0.5, "r": R.range(3.2, 4.4)})
		scorch.append(row)
	var out := {"list": list, "scorch": scorch}
	s[seed] = out
	return out


static func drawBack(p: Px.Painter, t: float, o: Dictionary) -> void:
	var F := Px.fit(o.palette, 9)
	F.reverse()
	var a: Dictionary = o.actor
	var fl := flare(t)
	var flick := 0.8 + 0.2 * Lib.tnoise(t, D, 7.5, 3)
	# warm flicker on the floor
	p.shade(-30.0, -3.0, 30.0, 7.0, func(x, y, out):
		var d := Px.hypot(x / 26.0, (y - 0.5) / 4.5)
		if d < 1.0:
			out.l = Px.mix(F[3], F[4], 0.5)
			out.k = (0.16 + 0.22 * fl) * flick * (1.0 - d) * (1.0 - d))
	# thin smoke drifting up and away from each spot
	var smokeC := Px.mix(Px.hex(o.smoke), F[6], 0.2)
	var list: Array = spots(a, o.seed).list
	Px.cycle(t, D, 16, o.seed + 4, func(r): return r.range(0.8, 1.2), func(age, life, r, i):
		var sp: Dictionary = list[i % list.size()]
		var x: float = sp.x + Lib.travel(WIND * 0.6, WIND * 0.5, 0.8, age) + sin(age * 4.0 + i) * 1.2
		var y: float = sp.y - 3.0 - Lib.travel(18.0, 6.0, 1.0, age)
		Lib.smoke(p, x, y, r.range(1.1, 1.9), age / life, smokeC, 0.9))


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var F := Px.fit(o.palette, 9)
	F.reverse()
	var CH := Px.fit(o.char, 3)
	var a: Dictionary = o.actor
	var S := Lib.shape(a)
	var sp0 := spots(a, o.seed)
	var list: Array = sp0.list
	var scorch: Array = sp0.scorch
	var ph := since(t)
	var tick := floori(t / TICK) % 2
	var fl := flare(t)
	# the tick: the body's own pixels flash white for a frame, then orange, fading
	if ph < 0.034:
		for b: Array in S.body:
			p.px(a.x + b[0], a.y + b[1], WHITE)
	elif ph < 0.22:
		var k := 1.0 - (ph - 0.034) / 0.186
		for b: Array in S.body:
			p.blend(a.x + b[0], a.y + b[1], F[4], 0.55 * k)
	# scorch marks spreading over the clothes from this tick, ember-edged, cooling and fading by the next
	for sc: Dictionary in scorch[tick]:
		var grow := Px.clamp(ph / 0.14)
		var fade := 1.0 - Px.clamp((ph - 0.25) / 0.33)
		var r: float = sc.r * (0.4 + 0.6 * grow)
		if fade <= 0.0:
			continue
		for b: Array in S.body:
			var mx: int = b[0]
			var my: int = b[1]
			var x: float = a.x + mx + 0.5
			var y: float = a.y + my + 0.5
			var d: float = Px.hypot(x - sc.x, (y - sc.y) * 1.2) + Px.rand(mx, my, 7) * 0.9
			if d > r:
				continue
			var edge := d > r - 1.0
			if edge:
				p.dot(x - 0.5, y - 0.5, F[3] if Px.rand(mx, my, floorf(t * 20.0)) < 0.5 else F[4], fade * 1.2)
			else:
				p.dot(x - 0.5, y - 0.5, CH[0] if d < r * 0.5 else CH[1], fade * 1.1)
		p.glow(sc.x, sc.y, 6.0, F[4], 0.3 * fade)
	# the hot spots: little tongues licking up, flaring on the tick
	for sp: Dictionary in list:
		for tg: Dictionary in sp.tongues:
			var h: float = tg.h * (0.85 + 0.25 * Lib.tnoise(t, D, 5.0, tg.n)) * (1.0 + 1.6 * fl)
			Lib.tongue(p, sp.x + tg.dx, sp.y, h, 1.1 + 0.3 * fl, WIND * 0.08 * h / 4.0 + Lib.tnoise(t, D, 3.0, tg.n + 9.0) * 0.8, F, t, D, tg.n)
		p.glow(sp.x, sp.y - 2.0, 9.0 + 6.0 * fl, F[4], 0.22 + 0.35 * fl)
	# sparks streaming up and away
	Px.cycle(t, D, 20, o.seed + 6, func(r): return r.range(0.5, 0.9), func(age, life, r, i):
		var sp: Dictionary = list[i % list.size()]
		var x: float = sp.x + r.range(-1.5, 1.5) + Lib.travel(WIND + r.range(-10.0, 6.0), WIND * 0.6, 1.2, age) + sin(age * 9.0 + i) * 1.2 * age
		var y: float = sp.y - 2.0 + Lib.travel(-r.range(25.0, 55.0), -18.0, 1.4, age)
		Lib.ember(p, x, y, age / life, [F[1], F[3], F[5]], age + i))
	# the tick throws a burst of sparks off every spot
	if ph < 0.3:
		for k in list.size():
			var sp: Dictionary = list[k]
			for j in 4:
				var an := -PI / 2.0 + (Px.rand(k, j, tick) - 0.5) * 2.2
				var v := 50.0 + 50.0 * Px.rand(k, j, 2)
				var x: float = sp.x + cos(an) * Lib.travel(v, 0.0, 3.0, ph)
				var y: float = sp.y - 2.0 + sin(an) * Lib.travel(v, 0.0, 3.0, ph) + 60.0 * ph * ph
				p.px(x, y, F[1] if ph < 0.12 else F[3])
				p.light(x, y, F[3], 0.4 * (1.0 - ph / 0.3))
