# The flame-puff, smoke and spark recipe is adapted from Sprite Fusion's open-source explosion
# (https://www.spritefusion.com/pixel-art-vfx/explosion), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/fire/fire-breath.js@70d1a94480248c1d881afcf96f76329b3cb2d9ca
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE
const LAYERS := Lib.LAYERS
const BACK_LAYERS := Lib.BACK_LAYERS

static var meta := {
	"name": "Fire breath",
	"desc": "A roaring cone of fire streaming right from the mouth: white-hot at the lips, billowing out and cooling to red and smoke at its edges, sparks thrown out ahead.",
	"tags": ["fire", "breath", "dragon", "stream", "cone", "directional", "loop"],
	"size": [160, 116],
	"origin": [12, 72],
	"duration": 1.5,
	"loop": true,
	"fps": 30,
	"bg": "dark",
	"options": {
		"palette": ["#4a1712", "#8a1f17", "#c9281f", "#f2561d", "#ff8a2a", "#ffc23d", "#ffe26b", "#fff3a6", "#ffffff"],
		"spread": 0.24,
		"speed": 320,
		"seed": 6,
	},
}

static var D: float = meta.duration
static var NL: Callable = Lib.noiseFor(D)
static var SMOKE1 := Px.hex("#5b5566")
# the dying licks: red and deep orange, no white heart
const COOL_LAYERS := [[1.0, 1.0, 7], [0.72, 0.82, 6], [0.44, 0.58, 5]]
# the jet at the lips: [length, half-width, angle]
const JET := [[42.0, 4.2, 0.0], [32.0, 3.8, -0.08], [30.0, 3.8, 0.08], [20.0, 4.6, 0.0]]


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var F := Px.fit(o.palette, 9)
	var H := Lib.hotFirst(F)
	var S: float = o.seed
	var A: float = o.spread
	var V: float = o.speed
	var N := func(rate: float, seed: Variant = 0, off: float = 0.0) -> float: return NL.call(t, rate, seed, off)
	var GLOW := Px.mix(Px.mix(H[3], H[4], 0.5), WHITE, 0.25)
	var SMOKE := Px.mix(SMOKE1, H[6], 0.3)
	var SPARKS := [H[1], H[2], H[4], H[5]]
	var EMB := [H[1], H[2], H[4], H[6]]
	# the roar: the stream surges and the cone sways a little
	var roar := func(tt: float) -> float: return 0.85 + 0.15 * NL.call(tt, 3.0, S + 1.0)
	var sway := func(tt: float) -> float: return NL.call(tt, 1.3, S + 2.0) * 0.05

	# the cone: puffs of flame blown out of the mouth that slow, swell, rise and cool; those near the edges
	# cool first, and many burn out into rolling smoke
	var fire := []
	var smoke := []
	Lib.looped(t, D, 260, S + 100.0, func(r: Px.Rng) -> Dictionary:
		var e := r.range(-1.0, 1.0)
		var fl := r.range(0.42, 0.8) * (1.0 - 0.3 * absf(e))
		var sm := r.chance(0.2 + 0.4 * absf(e))
		return {"e": e, "sp": r.range(0.75, 1.1), "fl": fl, "sm": sm, "sl": r.range(0.5, 0.85), "s": r.range(3.0, 5.2), "f": r.next(), "ox": r.range(4.0, 10.0), "life": fl + (0.85 if sm else 0.0)}, func(q: Dictionary, age: float) -> void:
		var tb := t - age
		var a: float = q.e * A + sway.call(tb) - 0.04
		var v: float = V * q.sp * roar.call(tb)
		var ta := minf(age, q.fl)
		var e := Lib.drift(q.ox, q.e * 1.5, cos(a) * v, sin(a) * v, ta, 0.0, -100.0, 2.0, 2.4)
		var x: float = e[0]
		var y: float = e[1]
		var vx: float = e[2]
		var vy: float = e[3]
		if age < q.fl:
			fire.append([age, x, y, q])
			return
		if not q.sm or age - q.fl > q.sl:
			return
		var sa: float = age - q.fl
		var sxy := Lib.drift(x, y, vx * 0.5, vy * 0.6 - 8.0, sa, 0.0, -26.0, 1.8, 1.2)
		smoke.append([sa, sxy[0], sxy[1], q]))
	for sm: Array in smoke:
		var q: Dictionary = sm[3]
		Lib.smokePuff(p, sm[1], sm[2], 1.0 - sm[0] / q.sl, q.s * 1.1, SMOKE, true, 0.7)
	Px.sort(fire, func(a, b): return b[0] - a[0])
	for fi: Array in fire:
		var age: float = fi[0]
		var x: float = fi[1]
		var y: float = fi[2]
		var q: Dictionary = fi[3]
		var u: float = age / q.fl
		var edge: float = absf(q.e)
		var size: float = q.s * (0.75 + 1.6 * u)
		# the heart of the stream stays hot longer than its edges
		var heat := minf(0.999, pow(u, 1.5) * (0.85 + 0.2 * edge) + 0.3 * edge * edge)
		# near the mouth the fire rolls in round billows; further out each billow tears into a tongue licking up
		# and back, thinning to a lick as it cools, before the smoke takes it
		var tear := Px.clamp((u - 0.32) / 0.2)
		Lib.firePuff(p, x, y, 1.0 - heat, size * (1.0 - 0.55 * tear), q.f, H, 0.1, -0.5, -0.86)
		if tear > 0.0:
			var n := floorf(q.f * 1e5)
			var h: float = size * (1.5 + 0.5 * N.call(4.0, n)) * (1.2 - heat * 0.6) * tear
			Lib.flameTongue(p, x, y + size * 0.3, h, size * 0.5 * (1.1 - heat * 0.5), -h * 0.4 + N.call(2.5, n + 1.0) * 2.0, N, n, H, LAYERS if heat < 0.45 else (BACK_LAYERS if heat < 0.72 else COOL_LAYERS))
	# licks curling off the edges of the cone
	for i in 6:
		var n := (S * 3.0 + i) * 19.0
		var side := 1.0 if i % 2 else -1.0
		var d: float = 18.0 + (i >> 1) * 16 + N.call(2.0, n) * 4.0
		var L: float = (9.0 + 5.0 * (0.5 + 0.5 * N.call(5.0, n + 1.0))) * (1.0 - d / 120.0)
		var ex := d
		var ey := side * d * A * 0.85 - d * 0.06
		Lib.flameBlade(p, ex, ey, 0.75, side * 0.45 - 0.48, L, 1.6 + L * 0.08, -side * 3.0, N, n, H, LAYERS)
	# the roar: bright streaks racing out through the heart of the cone
	Lib.looped(t, D, 70, S + 250.0, func(r: Px.Rng) -> Dictionary: return {"e": r.range(-0.6, 0.6), "v": r.range(330.0, 470.0), "life": r.range(0.12, 0.26), "l": r.range(4.0, 9.0)}, func(q: Dictionary, age: float) -> void:
		var a: float = q.e * A - 0.03
		var e := Lib.drift(6.0, q.e * 2.0, cos(a) * q.v, sin(a) * q.v, age, 0.0, -60.0, 2.0, 2.0)
		var x: float = e[0]
		var y: float = e[1]
		var vx: float = e[2]
		var vy: float = e[3]
		var sp := Px.hypot(vx, vy)
		var k: float = 1.0 - age / q.life
		var L: float = q.l * (sp / 400.0)
		p.line(x - (vx / sp) * L, y - (vy / sp) * L, x, y, func(u): return ((H[0] if k > 0.5 else H[1]) if u > 0.6 else (H[2] if k > 0.5 else H[3]))))
	# the jet at the lips: white-hot, overlapping tongues that flutter as the breath roars
	for i in JET.size():
		var len: float = JET[i][0]
		var w: float = JET[i][1]
		var a: float = JET[i][2]
		var n := (S * 5.0 + i) * 17.0
		var L: float = len * roar.call(t) * (0.85 + 0.2 * N.call(5.0, n))
		var aa: float = a + sway.call(t)
		Lib.flameBlade(p, 0.0, 0.0, cos(aa), sin(aa), L, w, N.call(3.0, n + 3.0) * 3.0, N, n, H, LAYERS, 0.5, 1.5)

	# sparks flung out ahead and falling; embers lifting off the far end
	Lib.looped(t, D, 40, S + 300.0, func(r: Px.Rng) -> Dictionary: return {"d": r.range(4.0, 60.0), "e": r.range(-1.0, 1.0), "v": r.range(140.0, 280.0), "life": r.range(0.25, 0.55)}, func(q: Dictionary, age: float) -> void:
		var a: float = q.e * A * 1.8 - 0.12
		var e := Lib.drift(q.d, q.e * q.d * A, cos(a) * q.v, sin(a) * q.v - 30.0, age, 0.0, 190.0, 2.0, 2.0)
		Lib.spark(p, e[0], e[1], e[2], e[3], 1.0 - age / q.life, SPARKS))
	Lib.looped(t, D, 18, S + 400.0, func(r: Px.Rng) -> Dictionary: return {"x": r.range(50.0, 100.0), "y": r.range(-14.0, 6.0), "vx": r.range(10.0, 40.0), "vy": -r.range(20.0, 50.0), "life": r.range(0.8, 1.4), "s": 2.0 if r.chance(0.2) else 1.0, "ph": r.range(0.0, 6.3)}, func(q: Dictionary, age: float) -> void:
		var xy := Lib.drift(q.x, q.y, q.vx, q.vy, age, 0.0, -30.0, 1.6, 1.6)
		Lib.ember(p, xy[0] + 5.0 * (sin(age * 2.3 + q.ph) - sin(q.ph)), xy[1], 1.0 - age / q.life, q.s, EMB, age * 40.0 + q.ph))

	# light: a flare at the lips, light all along the cone widening with it, a broad halo
	var k: float = roar.call(t)
	p.glow(3.0, 0.0, 34.0 * k, GLOW, 0.75 * k)
	p.glow(3.0, 0.0, 10.0, H[0], 0.55)
	for d in range(10, 126, 8):
		p.glow(d, -d * 0.1, 10.0 + d * 0.2, GLOW, 0.32 * k * (1.0 - d / 150.0))
	p.glow(64.0, -12.0, 96.0, GLOW, 0.16 * k)
