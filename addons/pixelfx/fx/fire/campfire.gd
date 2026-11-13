# The tongue, lick, flame-puff, smoke and ember recipe is adapted from Sprite Fusion's open-source fire
# (https://www.spritefusion.com/pixel-art-vfx/fire), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/fire/campfire.js@2ff5b492f2751ccc43795044d69b33571fd4eb63
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE
const LAYERS := Lib.LAYERS
const BACK_LAYERS := Lib.BACK_LAYERS

static var meta := {
	"name": "Campfire",
	"desc": "Crossed logs on a bed of coals and a lively fire: tongues that lick and leap, popping sparks, embers drifting up, smoke curling off, a warm pool of light.",
	"tags": ["fire", "campfire", "prop", "light", "smoke", "ambient", "loop"],
	"size": [128, 128],
	"origin": [64, 112],
	"duration": 3,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"options": {
		"palette": ["#4a1712", "#8a1f17", "#c9281f", "#f2561d", "#ff8a2a", "#ffc23d", "#ffe26b", "#fff3a6", "#ffffff"],
		"wood": ["#0e080a", "#24130f", "#3b2216", "#5a3520", "#8a5a34", "#b9884f"],
		"height": 22,
		"seed": 3,
	},
}

static var D: float = meta.duration
static var NL: Callable = Lib.noiseFor(D)
static var SMOKE1 := Px.hex("#5b5566")
static var ASH := [Px.hex("#2a2530"), Px.hex("#4a4350"), Px.hex("#6b6270")]

# the logs, near end first: they cross in an X over the coals, their near ends showing the cut grain and their
# far ends poking out past the flames
const LOGS := [
	[-19.0, 2.0, 15.0, -12.0, 3.4],
	[19.0, 2.0, -15.0, -12.0, 3.4],
]
const CROSS := 0.56
# big tongues keep more orange and a smaller white heart, so the light doesn't wash them out
const BIG_LAYERS := [[1.0, 1.0, 6], [0.8, 0.9, 5], [0.62, 0.78, 4], [0.44, 0.6, 3], [0.26, 0.4, 1], [0.12, 0.22, 0]] # the crossing, as a share of each log's length

# the fire: [x, base, height (share of o.height), half-width, back row?]
const TONGUES := [
	[-7.5, -7.0, 0.42, 1.8, 1],
	[7.5, -7.0, 0.46, 1.8, 1],
	[-3.0, -9.0, 0.78, 2.0, 1],
	[3.2, -9.0, 0.82, 2.0, 1],
	[-12.0, -3.0, 0.14, 1.3, 0],
	[12.5, -3.0, 0.16, 1.3, 0],
	[-9.5, -4.5, 0.3, 1.9, 0],
	[9.5, -4.5, 0.34, 1.9, 0],
	[-5.0, -6.0, 0.6, 2.6, 0],
	[5.2, -6.0, 0.66, 2.6, 0],
	[0.0, -7.0, 1.0, 3.4, 0],
]


# a log from its near end (x0, y0) to its far end, radius r, drawn between u0 and u1 along it: a 1 px dark rim,
# a lit top, grooves running along the grain, a shadowed underside; charred with glowing cracks in the fire
# (JS: log, which is a GDScript built-in)
static func log_(p: Px.Painter, L: Array, W: Array, H: Array, u0: float, u1: float, t: float, S: float) -> void:
	var x0: float = L[0]
	var y0: float = L[1]
	var x1: float = L[2]
	var y1: float = L[3]
	var r: float = L[4]
	var dx := x1 - x0
	var dy := y1 - y0
	var len := Px.hypot(dx, dy)
	var ax := dx / len
	var ay := dy / len
	var nx := -ay
	var ny := ax
	if ny < 0.0:
		nx = -nx
		ny = -ny
	var rim := 1.0 - 1.05 / r
	p.shade(minf(x0, x1) - r - 1.0, minf(y0, y1) - r - 1.0, maxf(x0, x1) + r + 1.0, maxf(y0, y1) + r + 1.0, func(x, y, out):
		var along: float = (x - x0) * ax + (y - y0) * ay
		var u := along / len
		var s: float = ((x - x0) * nx + (y - y0) * ny) / r
		if u < u0 or u > u1 or absf(s) > 1.0:
			return
		var burn := Px.clamp(1.2 - absf(x) / 8.0)
		var lane := Px.round(s * r * 0.85)
		var run := Px.rand(floorf(along / 3.0), lane, S)
		if absf(s) > rim or along > len - 1.0:
			return H[7] if s < 0.0 and burn > 0.4 else W[0]
		if burn > 0.35 and lane < 2.0:
			# charred: black, with embers breathing in the cracks along the grain
			if run < 0.55 and lane > -2.0:
				var g := 0.5 + 0.5 * sin((t / D) * PI * 6.0 + Px.rand(floorf(along / 2.0), lane, S + 1.0) * 6.3)
				out.k = 0.3 * burn * g
				return H[3] if g > 0.72 else (H[4] if g > 0.4 else H[5])
			return W[1] if lane < -1.0 else W[0]
		if lane <= -2.0:
			return W[2] if run < 0.25 else Px.mix(W[3], H[4], 0.45 * burn)
		if lane == -1.0:
			return W[1] if run < 0.45 else W[2]
		if lane == 0.0:
			return W[1] if run < 0.2 else W[2]
		return W[0] if run < 0.4 else W[1])
	# the near end's cut face: a dark rim, pale sapwood, growth rings round a dark heart
	if u0 <= 0.0:
		p.ellipse(x0, y0, r * 0.62, r + 0.2, func(d): return W[0] if d > 0.78 else (W[5] if d > 0.56 else (W[4] if d > 0.32 else W[3])))


# the bed of coals under the logs: coals that breathe in the heat, grey ash round the rim
static func coals(p: Px.Painter, W: Array, H: Array, t: float, S: float) -> void:
	p.shade(-15.0, -3.0, 15.0, 2.0, func(x, y, out):
		var dx: float = x / 14.0
		var dy: float = (y + 0.3) / 2.2
		var d := dx * dx + dy * dy
		if d > 1.0:
			return
		var h := Px.rand(floorf(x / 2.0), floorf(y), S + 20.0)
		if d > 0.55 and h < 0.55:
			return ASH[2 if h < 0.15 else (1 if h < 0.32 else 0)]
		if h > 0.5:
			var g := (0.5 + 0.5 * sin((t / D) * PI * 4.0 + h * 40.0)) * (1.1 - d)
			out.k = 0.35 * g
			return H[2] if g > 0.7 else (H[3] if g > 0.5 else (H[4] if g > 0.3 else H[5]))
		return W[1] if h > 0.3 else W[0])


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var F := Px.fit(o.palette, 9)
	var H := Lib.hotFirst(F)
	var W := Px.fit(o.wood, 6)
	var S: float = o.seed
	var R := Px.Rng.new(S)
	var HC: float = o.height
	var N := func(rate: float, seed: Variant = 0, off: float = 0.0) -> float: return NL.call(t, rate, seed, off)
	var fla := func(tt: float) -> float: return 0.74 + 0.16 * NL.call(tt, 7.3, S + 1.0) + 0.1 * NL.call(tt, 19.0, S + 2.0)
	var fl: float = fla.call(t)
	var GLOW := Px.mix(Px.mix(H[3], H[4], 0.5), WHITE, 0.25)
	var SMOKE := Px.mix(SMOKE1, H[6], 0.25)
	var SPARKS := [H[1], H[2], H[4], H[5]]
	var EMB := [H[1], H[2], H[4], H[6]]

	var T := []
	for i in TONGUES.size():
		var dx: float = TONGUES[i][0]
		var y: float = TONGUES[i][1]
		var h: float = TONGUES[i][2]
		var w: float = TONGUES[i][3]
		var back: Variant = TONGUES[i][4]
		T.append({"dx": dx + R.range(-0.4, 0.4), "y": y, "h": 3.0 + HC * h * R.range(0.92, 1.08), "w": w * R.range(0.9, 1.1), "back": back, "env": h, "n": (S * 7.0 + i) * 13.0})
	var lean := func(tt: float) -> float: return NL.call(tt, 0.67, S + 90.0) * 0.12
	var height := func(i: int, tt: float) -> float:
		var h: float = T[i].h
		var n: float = T[i].n
		var leap: float = maxf(0.0, NL.call(tt, 2.6, n + 70.0) - 0.55) * 1.4
		return (h + 0.25 * h * NL.call(tt, 3.3, n) + h * leap) * (0.9 + 0.1 * fla.call(tt))
	var sweep := func(i: int, tt: float, h: float) -> float: return NL.call(tt, 2.2, T[i].n + 40.0) * (1.0 + h * 0.08) + lean.call(tt) * h * 0.9 - Px.clamp(T[i].dx * 0.3, -2.5, 2.5)
	var tip := func(i: int, tt: float) -> Array:
		var h: float = height.call(i, tt)
		return [T[i].dx + sweep.call(i, tt, h) * 0.85, T[i].y - h * 0.88 + 3.0, h]
	var tongueAt := func(i: int) -> void:
		var dx: float = T[i].dx
		var y: float = T[i].y
		var w: float = T[i].w
		var n: float = T[i].n
		var back: Variant = T[i].back
		var h: float = height.call(i, t)
		Lib.flameTongue(p, dx, y, h, w, sweep.call(i, t, h), N, n, H, BACK_LAYERS if back else (BIG_LAYERS if w > 2.2 else LAYERS), 0.5, 1.1 + h * 0.04)

	# smoke curling off the top, behind everything: each puff keeps the sway the plume had when it left the
	# flames, so the wiggle climbs the plume, and the draught bends it over as it rises
	Lib.looped(t, D, 48, S + 300.0, func(r: Px.Rng) -> Dictionary: return {"x": r.range(-5.0, 5.0), "y": -HC * 0.8 - r.range(0.0, 8.0), "vx": r.range(-2.0, 2.0), "vy": -r.range(10.0, 17.0), "life": r.range(2.0, 2.9), "s": r.range(2.4, 3.8)}, func(q: Dictionary, age: float) -> void:
		var xy := Lib.drift(q.x, q.y, q.vx, q.vy, age, 4.0, -20.0, 1.6, 1.0)
		Lib.smokePuff(p, xy[0] + NL.call(t - age, 0.8, S + 60.0) * (2.0 + 3.0 * age), xy[1], 1.0 - age / q.life, q.s, SMOKE))
	# flame puffs shed from the tips: they burn out above the fire, some into smoke
	var puffs := []
	Lib.looped(t, D, T.size() * 24, S + 200.0, func(r: Px.Rng, j: int) -> Dictionary:
		var i := j % T.size()
		var fire := r.range(0.14, 0.3)
		var smokes := r.chance(0.45)
		return {"i": i, "fire": fire, "smokes": smokes, "sl": r.range(0.8, 1.4), "ox": r.range(-1.0, 1.0), "oy": r.range(0.0, 4.0), "vx": r.range(-4.0, 4.0), "vy": -r.range(15.0, 30.0), "s": r.range(0.8, 1.6) * (0.8 + 0.6 * T[i].env), "f": r.next(), "life": fire + (1.4 if smokes else 0.0)}, func(q: Dictionary, age: float) -> void:
		var txy: Array = tip.call(q.i, t - age)
		var e := Lib.drift(txy[0] + q.ox, txy[1] + q.oy, q.vx, q.vy, minf(age, q.fire), 0.0, -95.0, 5.0, 3.2)
		if age < q.fire:
			puffs.append([e[0], e[1], 1.0 - age / q.fire, q.s, q.f])
			return
		if age - q.fire > q.sl:
			return
		var sxy := Lib.drift(e[0], e[1], e[2] * 0.6, e[3] * 0.6 - 6.0, age - q.fire, 2.0, -16.0, 1.6, 1.2)
		Lib.smokePuff(p, sxy[0], sxy[1], 1.0 - (age - q.fire) / q.sl, q.s * 0.7, 0))

	coals(p, W, H, t, S)
	for L: Array in LOGS:
		log_(p, L, W, H, CROSS, 1.0, t, S + 11.0)
	for i in T.size():
		if T[i].back:
			tongueAt.call(i)
	# flames licking up off the burning wood
	Lib.looped(t, D, 90, S + 210.0, func(r: Px.Rng) -> Dictionary: return {"x": r.range(-10.0, 10.0), "y": -r.range(3.0, 8.0), "vx": r.range(-5.0, 5.0), "vy": -r.range(20.0, 40.0), "life": r.range(0.16, 0.3), "s": r.range(1.0, 1.8), "f": r.next()}, func(q: Dictionary, age: float) -> void:
		var xy := Lib.drift(q.x, q.y, q.vx, q.vy, age, 0.0, -95.0, 5.0, 3.2)
		Lib.firePuff(p, xy[0], xy[1], 1.0 - age / q.life, q.s, q.f, H))
	for i in T.size():
		if not T[i].back:
			tongueAt.call(i)
	# licks torn off the tips, rising and shrinking
	Lib.looped(t, D, T.size() * 12, S + 220.0, func(r: Px.Rng, j: int) -> Dictionary: return {"i": j % T.size(), "vx": r.range(-3.0, 3.0), "vy": -r.range(12.0, 22.0), "s": r.range(0.9, 1.6) * (0.8 + 0.5 * T[j % T.size()].env), "life": 0.26}, func(q: Dictionary, age: float) -> void:
		var txy: Array = tip.call(q.i, t - age)
		Lib.lick(p, txy[0] + q.vx * age, txy[1] - 2.0 + q.vy * age, 1.0 - age / q.life, q.s, H))
	for pf: Array in puffs:
		Lib.firePuff(p, pf[0], pf[1], pf[2], pf[3], pf[4], H)
	for L: Array in LOGS:
		log_(p, L, W, H, 0.0, CROSS, t, S + 11.0)

	# pops: a crack, a flash, and a fistful of sparks thrown up out of the wood that bounce on the floor
	Lib.looped(t, D, 4, S + 400.0, func(r: Px.Rng) -> Dictionary: return {"x": r.range(-9.0, 9.0), "y": -r.range(4.0, 9.0), "n": r.int_(3, 5), "seed": r.int_(0, 1e6), "life": 0.7}, func(q: Dictionary, age: float) -> void:
		if age < 0.08:
			p.px(q.x, q.y, WHITE)
			p.glow(q.x, q.y, 12.0, H[1], 0.7 * (1.0 - age / 0.08))
		var r := Px.Rng.new(q.seed)
		for j in q.n:
			var a := -PI / 2.0 + r.range(-0.8, 0.8)
			var sp := r.range(110.0, 220.0)
			var life := r.range(0.25, 0.6)
			if age >= life:
				continue
			var e := Lib.sparkAt(q.x, q.y, cos(a) * sp, sin(a) * sp, age, 0.0)
			Lib.spark(p, e[0], e[1], e[2], e[3], 1.0 - age / life, SPARKS))
	# embers carried up by the heat, wandering and cooling
	Lib.looped(t, D, 36, S + 500.0, func(r: Px.Rng) -> Dictionary: return {"x": r.range(-7.0, 7.0), "y": -r.range(8.0, 18.0), "vx": r.range(-15.0, 15.0), "vy": -r.range(25.0, 60.0), "life": r.range(1.1, 2.5), "s": 2.0 if r.chance(0.15) else r.range(1.0, 1.6), "a": r.range(0.0, 6.3), "b": r.range(0.0, 6.3)}, func(q: Dictionary, age: float) -> void:
		var xy := Lib.drift(q.x, q.y, q.vx, q.vy, age, 0.0, -30.0, 1.6, 1.6)
		Lib.ember(p, xy[0] + 7.0 * (sin(age * 2.3 + q.a) - sin(q.a)), xy[1] + 2.0 * (sin(age * 3.0 + q.b) - sin(q.b)), 1.0 - age / q.life, q.s, EMB, age * 40.0 + q.a))

	# light: a big warm room light, a hot heart, a pool on the floor, all breathing with the flames
	var br: float = 0.92 + 0.08 * N.call(0.67, S + 3.0)
	var lx: float = lean.call(t) * 12.0
	p.glow(lx, -8.0, 74.0 * br * (0.9 + 0.1 * fl), GLOW, 0.3 * fl)
	for xyk: Array in [[-6.0, -17.0, 0.85], [0.0, -21.0, 1.0], [6.0, -17.0, 0.85]]:
		var x: float = xyk[0]
		var y: float = xyk[1]
		var k: float = xyk[2]
		p.glow(x + lx, y, 46.0 * br, GLOW, 0.3 * k * fl)
		p.glow(x * 0.6, y + 13.0, 15.0, H[2], 0.16 * k * fl)
	p.glow(0.0, -3.0, 9.0, H[0], 0.16 * fl)
	Lib.floorLight(p, 0.0, 0.5, 48.0, 8.0, GLOW, 0.3 * fl)
