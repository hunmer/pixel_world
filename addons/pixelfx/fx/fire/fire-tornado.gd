# The flame-puff, smoke and ember recipe is adapted from Sprite Fusion's open-source fire
# (https://www.spritefusion.com/pixel-art-vfx/fire), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/fire/fire-tornado.js@97f818d4fed54128218e3393e32fd60e5c3d889b
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE
const LAYERS := Lib.LAYERS
const BACK_LAYERS := Lib.BACK_LAYERS

static var meta := {
	"name": "Fire tornado",
	"desc": "A spinning funnel of fire: spiral bands turning round it, licks flung off its sides, a ring of flame whirling at its foot, embers orbiting it in and out of view.",
	"tags": ["fire", "tornado", "vortex", "spell", "aoe", "loop"],
	"size": [120, 152],
	"origin": [60, 136],
	"duration": 2,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"options": {
		"palette": ["#4a1712", "#8a1f17", "#c9281f", "#f2561d", "#ff8a2a", "#ffc23d", "#ffe26b", "#fff3a6", "#ffffff"],
		"height": 80,
		"seed": 4,
	},
}

static var D: float = meta.duration
static var NL: Callable = Lib.noiseFor(D)
static var SMOKE1 := Px.hex("#5b5566")
const SPIN := 3.0 # turns of the surface a loop


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var F := Px.fit(o.palette, 9)
	var H := Lib.hotFirst(F)
	var S: float = o.seed
	var HT: float = o.height
	var ph := t / D
	var N := func(rate: float, seed: Variant = 0, off: float = 0.0) -> float: return NL.call(t, rate, seed, off)
	var GLOW := Px.mix(Px.mix(H[3], H[4], 0.5), WHITE, 0.25)
	var SMOKE := Px.mix(SMOKE1, H[6], 0.25)
	var EMB := [H[1], H[2], H[4], H[6]]
	# the funnel: narrow at the foot, flaring at the top, its spine snaking as it turns
	# (JS: tt defaults to t; every call here passes it)
	var cx := func(v: float, tt: float) -> float: return 3.2 * sin(v * 4.2 - (tt / D) * TAU * 2.0) * v + 2.0 * sin((tt / D) * TAU) * v
	var rad := func(v: float) -> float: return 3.5 + 15.0 * pow(v, 1.35)
	var spin := func(v: float, tt: float) -> float: return (tt / D) * TAU * SPIN + v * 5.5 # the surface turns, twisted up the column

	# embers orbiting: behind the column first, in front after it
	var orbit := []
	Lib.looped(t, D, 30, S + 500.0, func(r: Px.Rng) -> Dictionary: return {"v0": r.range(0.02, 0.7), "rise": r.range(0.12, 0.3), "a": r.range(0.0, TAU), "w": r.range(4.0, 7.0), "out": r.range(4.0, 12.0), "life": r.range(1.2, 2.4), "big": r.chance(0.2)}, func(q: Dictionary, age: float) -> void:
		var v: float = q.v0 + q.rise * age
		var R: float = rad.call(minf(1.0, v)) + q.out + age * 4.0
		var a: float = q.a + q.w * age
		var k: float = 1.0 - age / q.life
		var x: float = cx.call(minf(1.0, v), t) + cos(a) * R
		var y := -v * HT + sin(a) * R * 0.28
		var z := sin(a)
		orbit.append({"x": x, "y": y, "z": z, "k": k, "vx": -sin(a) * R * q.w, "vy": cos(a) * R * q.w * 0.28, "big": q.big}))
	var embers := func(front: bool) -> void:
		for e: Dictionary in orbit:
			if (e.z >= 0.0) != front or e.k <= 0.0:
				continue
			var sp := Px.hypot(e.vx, e.vy)
			if not sp:
				sp = 1.0
			var L := minf(5.0, 1.0 + sp * 0.025)
			var c: int = EMB[0] if e.k > 0.6 else (EMB[1] if e.k > 0.3 else EMB[2])
			p.line(e.x - (e.vx / sp) * L, e.y - (e.vy / sp) * L, e.x, e.y, func(u): return c if u > 0.6 else (EMB[3] if front else H[7]))
			if front:
				p.glow(e.x, e.y, 4.0, c, 0.4 * e.k)
			else:
				p.glow(e.x, e.y, 3.0, c, 0.15 * e.k)
	# the ring of flame whirling at the foot: tongues round an ellipse, the far half dimmer
	var ring := func(front: bool) -> void:
		for i in 12:
			var a := (i / 12.0) * TAU + (t / D) * TAU * 2.0
			var z := sin(a)
			if (z >= 0.0) != front:
				continue
			var n := (S * 3.0 + i) * 19.0
			var R: float = 12.0 + 2.0 * N.call(2.0, n)
			var x := cos(a) * R
			var y := z * R * 0.25
			var h: float = (5.0 + 5.0 * (0.5 + 0.5 * N.call(5.0, n + 1.0))) * (1.0 if front else 0.8)
			Lib.flameTongue(p, x, y, h, 1.6, -cos(a + PI / 2.0) * 3.0, N, n, H, LAYERS if front else BACK_LAYERS)

	# smoke spiralling off the top
	Lib.looped(t, D, 20, S + 300.0, func(r: Px.Rng) -> Dictionary: return {"a": r.range(0.0, TAU), "life": r.range(1.2, 2.0), "s": r.range(2.5, 4.0), "vy": -r.range(12.0, 22.0)}, func(q: Dictionary, age: float) -> void:
		var R: float = rad.call(1.0) * (0.8 + age * 0.5)
		var a: float = q.a + age * 3.0
		var x: float = cx.call(1.0, t - age) + cos(a) * R
		var y: float = -HT - 2.0 + q.vy * age + sin(a) * R * 0.25
		Lib.smokePuff(p, x, y, 1.0 - age / q.life, q.s, SMOKE))
	Lib.floorLight(p, 0.0, 0.5, 40.0, 8.0, GLOW, 0.4)
	embers.call(false)
	ring.call(false)

	# the column: each pixel's place round the funnel picks its heat; spiral bands turn up it; licks at its edges
	var fl: float = 0.85 + 0.15 * N.call(7.0, S + 1.0)
	var y := 0
	while y >= -HT * 1.2:
		var v := -y / HT
		var vv := minf(1.0, v)
		var c: float = cx.call(vv, t)
		var r: float = rad.call(vv) * (1.0 + 0.08 * N.call(3.0, S + 2.0, y * 0.1))
		var sp: float = spin.call(v, t)
		# near the top the funnel comes apart into spiral strands of flame climbing past its rim
		var cut := Px.clamp((v - 0.72) / 0.42)
		var lickL := 0.3 * maxf(0.0, Lib.pnoise(-y * 0.22 + ph * 18.0, 18.0, S + 3.0))
		var lickR := 0.3 * maxf(0.0, Lib.pnoise(-y * 0.22 + ph * 18.0 + 9.0, 18.0, S + 4.0))
		for xi in range(int(floorf(c - r * 1.35)), int(ceilf(c + r * 1.35)) + 1):
			var x := float(xi)
			var dx := (x + 0.5 - c) / r
			var edge := 1.0 + (lickL if dx < 0.0 else lickR)
			if absf(dx) > edge:
				continue
			var th := asin(Px.clamp(dx, -1.0, 1.0))
			var depth := cos(th)
			var tear := 0.18 * Lib.pnoise(y * 0.45 + dx * 2.0 - ph * 30.0, 30.0, S + 6.0)
			var band := 0.5 + 0.5 * sin((th + sp + tear) * 3.0)
			var streak := band * band * band
			if cut > 0.0 and band < 0.35 + cut * 0.6 + 0.1 * Lib.pnoise(x * 0.7 + ph * 20.0, 20.0, S + 5.0):
				continue
			# a darker body with thin bright streaks spiralling up it, hottest where it faces us, cooling up the column
			var heat := 0.22 + 0.36 * depth + 0.5 * streak - 0.22 * vv + 0.1 * (1.0 - vv) - 0.25 * cut
			if absf(dx) > 1.0:
				heat = 0.3 - (absf(dx) - 1.0) * 1.5
			heat *= fl
			var col: int = H[0] if heat > 0.95 else (H[1] if heat > 0.82 else (H[2] if heat > 0.7 else (H[3] if heat > 0.58 else (H[4] if heat > 0.46 else (H[5] if heat > 0.34 else (H[6] if heat > 0.2 else H[7]))))))
			p.px(x, y, col)
		if y % 10 == 0 and v <= 1.0:
			p.glow(c, y, r * 2.0 + 8.0, GLOW, 0.22 * fl)
		y -= 1

	# flame flung off the spinning sides, cooling as it flies, some into smoke
	Lib.looped(t, D, 70, S + 200.0, func(r: Px.Rng) -> Dictionary: return {"v": r.range(0.05, 0.95), "side": r.sign(), "sp": r.range(20.0, 50.0), "life": r.range(0.25, 0.5), "s": r.range(1.4, 2.8), "f": r.next()}, func(q: Dictionary, age: float) -> void:
		var tb := t - age
		var x0: float = cx.call(q.v, tb) + q.side * rad.call(q.v)
		var y0: float = -q.v * HT
		var xy := Lib.drift(x0, y0, q.side * q.sp, -q.sp * 0.6, age, 0.0, -60.0, 3.0, 3.0)
		Lib.firePuff(p, xy[0], xy[1], 1.0 - age / q.life, q.s, q.f, H, 0.1, -q.side * 0.6, -0.8))
	ring.call(true)
	embers.call(true)
	# light: the column's own glow and a wash round it
	p.glow(0.0, -HT * 0.5, 80.0, GLOW, 0.28 * fl)
	p.glow(0.0, -6.0, 18.0, H[2], 0.3 * fl)
