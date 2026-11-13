# The flame-puff, smoke and spark recipe is adapted from Sprite Fusion's open-source explosion
# (https://www.spritefusion.com/pixel-art-vfx/explosion), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/fire/fireball.js@cacac879984d9ffb8a8ed34d0770744eb0f57fb6
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE
const LAYERS := Lib.LAYERS

static var meta := {
	"name": "Fireball",
	"desc": "A fireball flying right: a churning white-hot head with a corona of flame, a long torn tail of flame puffs cooling into smoke, embers shed behind.",
	"tags": ["fire", "fireball", "projectile", "magic", "directional", "loop"],
	"size": [136, 56],
	"origin": [112, 28],
	"duration": 1.2,
	"loop": true,
	"fps": 30,
	"bg": "dark",
	"options": {
		"palette": ["#4a1712", "#8a1f17", "#c9281f", "#f2561d", "#ff8a2a", "#ffc23d", "#ffe26b", "#fff3a6", "#ffffff"],
		"radius": 5,
		"speed": 120,
		"seed": 5,
	},
}

static var D: float = meta.duration
static var NL: Callable = Lib.noiseFor(D)
static var SMOKE1 := Px.hex("#5b5566")
# the comet body: tongues rooted in the head streaming back, the longest behind [length, half-width, y offset]
const BODY := [[30.0, 4.2, 0.0], [23.0, 4.4, -1.6], [22.0, 4.4, 1.6], [15.0, 4.6, 0.0]]
# the corona: thin licks peeling back off the head [angle on the head (0 is the nose), length, half-width]
const CORONA := [[-1.3, 6.0, 1.1], [-1.8, 8.0, 1.2], [-2.3, 7.0, 1.1], [1.3, 6.0, 1.1], [1.8, 8.0, 1.2], [2.3, 7.0, 1.1]]


# the head: a ball whose outline churns and whose heat swirls in a spiral, white at the heart, swept back
static func head(p: Px.Painter, H: Array, t: float, R0: float, S: float, hx: float, hy: float) -> void:
	var ph := t / D
	p.shade(hx - R0 * 2.4, hy - R0 * 1.7, hx + R0 * 1.5, hy + R0 * 1.7, func(x, y, _out):
		x -= hx
		y -= hy
		var d := Px.hypot(x, y)
		var th := atan2(y, x)
		var back := maxf(0.0, -cos(th))
		var a := th / TAU
		var bump := 0.55 * Lib.pnoise(a * 9.0 + ph * 9.0, 9.0, S) + 0.35 * Lib.pnoise(a * 5.0 - ph * 10.0, 5.0, S + 1.0)
		var rim := R0 * (1.0 + 0.55 * back * back) + bump
		if d > rim:
			return
		var swirl := Lib.pnoise(a * 5.0 - ph * 10.0 + d * 0.45, 5.0, S + 2.0)
		var h := 1.0 - d / rim + 0.26 * swirl + 0.1 * (1.0 - back)
		# the leading edge: a crisp hot rim where it cuts the air
		if rim - d < 1.0 and back < 0.3:
			return H[3] if h > 0.3 else H[5]
		return H[0] if h > 0.74 else (H[1] if h > 0.58 else (H[2] if h > 0.42 else (H[4] if h > 0.27 else (H[5] if h > 0.13 else H[6])))))


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var F := Px.fit(o.palette, 9)
	var H := Lib.hotFirst(F)
	var S: float = o.seed
	var R0: float = o.radius
	var V: float = o.speed
	var N := func(rate: float, seed: Variant = 0, off: float = 0.0) -> float: return NL.call(t, rate, seed, off)
	var GLOW := Px.mix(Px.mix(H[3], H[4], 0.5), WHITE, 0.25)
	var SMOKE := Px.mix(SMOKE1, H[6], 0.3)
	var SPARKS := [H[1], H[2], H[4], H[5]]
	var EMB := [H[1], H[2], H[4], H[6]]
	# the head bobs a hair as it flies
	var hx: float = N.call(3.0, S + 50.0) * 0.5
	var hy: float = N.call(2.5, S + 51.0) * 0.7

	# the tail: flame puffs thrown off the back that the head leaves behind; they cool, swell, rise and some
	# burn out into smoke. Positions are relative to the head, which outruns them.
	var fire := []
	var smoke := []
	Lib.looped(t, D, 130, S + 100.0, func(r: Px.Rng) -> Dictionary:
		var fl := r.range(0.22, 0.55)
		var sm := r.chance(0.55)
		var x := -r.range(2.0, 24.0)
		return {"x": x, "y": r.range(-1.0, 1.0) * (R0 - 0.1 * -x), "v": V * r.range(0.3, 0.6), "vy": r.range(-16.0, 16.0), "fl": fl, "sm": sm, "sl": r.range(0.25, 0.45), "s": r.range(1.3, 2.9), "f": r.next() * 0.5 + 0.5 * (-x / 24.0), "life": fl + (0.45 if sm else 0.0)}, func(q: Dictionary, age: float) -> void:
		var ta := minf(age, q.fl)
		var e := Lib.drift(0.0, q.y, q.v, q.vy, ta, 0.0, -70.0, 4.5, 3.0)
		var wx: float = e[0]
		var y: float = e[1]
		var wvx: float = e[2]
		var vy: float = e[3]
		var x: float = q.x + wx - V * ta
		if age < q.fl:
			fire.append([age, x, y, q])
			return
		if not q.sm or age - q.fl > q.sl:
			return
		var sa: float = age - q.fl
		var sxy := Lib.drift(x, y, wvx - V, vy * 0.6 - 6.0, sa, V * 2.0, -30.0, 2.0, 1.2)
		smoke.append([sa, sxy[0], sxy[1], q]))
	for sm: Array in smoke:
		var q: Dictionary = sm[3]
		Lib.smokePuff(p, sm[1], sm[2], 1.0 - sm[0] / q.sl, q.s * 0.9, SMOKE)
	Px.sort(fire, func(a, b): return b[0] - a[0])
	for fi: Array in fire:
		var age: float = fi[0]
		var q: Dictionary = fi[3]
		var u: float = age / q.fl
		Lib.firePuff(p, fi[1], fi[2], 1.0 - u, q.s * (1.0 + 1.3 * u), q.f, H, 0.07, -0.86, -0.5)

	# the body: tongues of flame rooted in the head streaming back, and a corona licking round it
	for i in BODY.size():
		var len: float = BODY[i][0]
		var w: float = BODY[i][1]
		var dy: float = BODY[i][2]
		var n := (S * 5.0 + i) * 17.0
		var L: float = len * (0.82 + 0.25 * N.call(4.0, n)) * (1.0 + 0.3 * maxf(0.0, N.call(2.4, n + 3.0)))
		Lib.flameBlade(p, hx + 1.0, hy + dy * 0.5, -1.0, dy * 0.02, L, w * R0 / 5.0, N.call(3.0, n + 5.0) * 3.0 + dy, N, n, H, LAYERS, 0.5, 1.1 + L * 0.05)
	for i in CORONA.size():
		var a: float = CORONA[i][0]
		var len: float = CORONA[i][1]
		var w: float = CORONA[i][2]
		var n := (S * 5.0 + i + 20.0) * 17.0
		var L: float = len * (0.7 + 0.4 * (0.5 + 0.5 * N.call(6.0, n)))
		var ox := cos(a) * R0 * 0.85
		var oy := sin(a) * R0 * 0.85
		var dx := cos(a) * 0.55 - 1.0
		var dy := sin(a) * 0.55
		var l := Px.hypot(dx, dy)
		Lib.flameBlade(p, hx + ox, hy + oy, dx / l, dy / l, L, w, -Px.sign(a) * 1.5, N, n, H, LAYERS)
	head(p, H, t, R0, S, hx, hy)

	# motes flicked off the head's skin: short hot streaks that die at once
	Lib.looped(t, D, 26, S + 200.0, func(r: Px.Rng) -> Dictionary: return {"a": r.range(-2.4, 2.4), "v": r.range(30.0, 70.0), "life": r.range(0.08, 0.18)}, func(q: Dictionary, age: float) -> void:
		var ca: float = cos(q.a)
		var sa: float = sin(q.a)
		var d: float = R0 * 0.9 + q.v * age
		var x := hx + ca * d - V * 0.4 * age
		var y := hy + sa * d
		var k: float = 1.0 - age / q.life
		var L := 1.0 + 2.0 * k
		p.line(x - ca * L + V * 0.02, y - sa * L, x, y, H[1] if k > 0.5 else H[3])
		p.glow(x, y, 3.0, H[2], 0.4 * k))
	# embers left behind: streaks that the head outruns, falling as they cool
	Lib.looped(t, D, 30, S + 300.0, func(r: Px.Rng) -> Dictionary: return {"x": -r.range(2.0, 16.0), "y": r.range(-3.0, 3.0), "v": V * r.range(0.3, 0.8), "vy": r.range(-20.0, 20.0), "life": r.range(0.25, 0.55), "big": r.chance(0.25), "ph": r.range(0.0, 6.3)}, func(q: Dictionary, age: float) -> void:
		var e := Lib.drift(0.0, q.y, q.v, q.vy, age, 0.0, 50.0, 3.0, 2.0)
		var x: float = q.x + e[0] - V * age
		var k: float = 1.0 - age / q.life
		if q.big:
			Lib.ember(p, x, e[1], k, 2.0, EMB, age * 40.0 + q.ph)
		else:
			Lib.spark(p, x, e[1], e[2] - V, e[3], k, SPARKS))

	# light: a hot heart, a warm halo, light running down the tail
	var fl: float = 0.85 + 0.15 * N.call(9.0, S + 7.0)
	p.glowLine(hx - 6.0, hy, -50.0, -2.0, 12.0, GLOW, 0.2 * fl)
	p.glow(hx - 2.0, hy, 42.0, GLOW, 0.42 * fl)
	p.glow(hx, hy, 13.0, H[1], 0.3 * fl)
