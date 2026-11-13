# The flame-puff, smoke and spark recipe is adapted from Sprite Fusion's open-source explosion
# (https://www.spritefusion.com/pixel-art-vfx/explosion), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/fire/flamethrower.js@fd7a2da6ad55ef6fca734298aed7baf819d954ce
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE
const LAYERS := Lib.LAYERS

static var meta := {
	"name": "Flamethrower",
	"desc": "A pressurised jet shooting right: a blue pilot at the nozzle, a tight stream with surges racing down it, a sputter, burning drops falling off, a tip that curls up into smoke.",
	"tags": ["fire", "flamethrower", "stream", "weapon", "directional", "loop"],
	"size": [184, 104],
	"origin": [30, 60],
	"duration": 1.6,
	"loop": true,
	"fps": 30,
	"bg": "dark",
	"options": {
		"palette": ["#4a1712", "#8a1f17", "#c9281f", "#f2561d", "#ff8a2a", "#ffc23d", "#ffe26b", "#fff3a6", "#ffffff"],
		"pilot": ["#1b2a8a", "#3a62e0", "#a8d4ff"],
		"reach": 112,
		"speed": 280,
		"seed": 3,
	},
}

static var D: float = meta.duration
static var NL: Callable = Lib.noiseFor(D)
static var SOOT := Px.hex("#2a2430")
# the sputter: the jet coughs once a loop, then surges back
const COUGH := 0.55


static func flow(te: float) -> float:
	var u := fmod(fmod(te, D) + D, D)
	return 1.0 - Px.smooth(COUGH, COUGH + 0.04, u) * (1.0 - Px.smooth(COUGH + 0.1, COUGH + 0.16, u)) + 0.25 * exp(-(pow((u - COUGH - 0.2) / 0.05, 2.0)))


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var F := Px.fit(o.palette, 9)
	var H := Lib.hotFirst(F)
	var PL := Px.fit(o.pilot, 3)
	var S: float = o.seed
	var L: float = o.reach
	var V: float = o.speed
	var N := func(rate: float, seed: Variant = 0, off: float = 0.0) -> float: return NL.call(t, rate, seed, off)
	var GLOW := Px.mix(Px.mix(H[3], H[4], 0.5), WHITE, 0.25)
	var SPARKS := [H[1], H[2], H[4], H[5]]
	var SMOKE := Px.mix(SOOT, H[7], 0.3)
	# the stream's centre line: dead straight at the nozzle, sagging and wavering as it runs out
	var cy := func(x: float) -> float: return 5.0 * pow(x / L, 2.0) + N.call(1.2, S + 9.0, x * 0.02) * 2.2 * pow(x / L, 1.5)
	var width := func(x: float) -> float: return (2.1 + 5.0 * pow(x / L, 0.7)) * flow(t - x / V)

	# the curl: where the stream runs out of push, burning fuel rolls up and back on itself and turns to smoke
	var fire := []
	var smoke := []
	Lib.looped(t, D, 80, S + 100.0, func(r: Px.Rng) -> Dictionary: return {"a0": r.range(-0.3, 0.5), "R": r.range(9.0, 15.0), "w": r.range(5.0, 7.5), "up": r.range(4.0, 12.0), "dx": r.range(-6.0, 2.0), "fl": r.range(0.38, 0.62), "sl": r.range(0.6, 1.0), "s": r.range(2.4, 4.4), "f": r.next(), "life": 1.6}, func(q: Dictionary, age: float) -> void:
		var tb := t - age
		var k := flow(tb - L / V)
		if k < 0.4:
			return
		# round a curl: forward, up and back over the top, rising as it goes
		var x0: float = L + q.dx
		var y0: float = cy.call(L)
		var a: float = minf(age, q.fl) * q.w + q.a0
		var x: float = x0 + q.R * sin(a)
		var y: float = y0 - q.R * (1.0 - cos(a)) - q.up * age
		if age < q.fl:
			fire.append([age / q.fl, x, y, q, k])
			return
		if age - q.fl < q.sl:
			smoke.append([(age - q.fl) / q.sl, x - (age - q.fl) * 6.0, y - (age - q.fl) * 16.0, q]))
	for sm: Array in smoke:
		var q: Dictionary = sm[3]
		Lib.smokePuff(p, sm[1], sm[2], 1.0 - sm[0], q.s * 1.2, SMOKE, true, 0.85)
	Px.sort(fire, func(a, b): return b[0] - a[0])
	for fi: Array in fire:
		var u: float = fi[0]
		var q: Dictionary = fi[3]
		var k: float = fi[4]
		Lib.firePuff(p, fi[1], fi[2], 1.0 - u, q.s * (0.8 + 1.1 * u) * k, q.f, H, 0.1)

	# flames licking up off the burning fuel, riding along the stream, swept back by the wind of it
	for i in 13:
		var n := (S * 3.0 + i) * 19.0
		var ph := fmod(i * 0.618 + t / D, 1.0)
		var x := 10.0 + ph * (L - 14.0)
		var k := flow(t - x / V)
		if k < 0.35:
			continue
		var h: float = (2.0 + 11.0 * (x / L)) * (0.55 + 0.6 * (0.5 + 0.5 * N.call(5.0, n + 1.0))) * k * minf(1.0, (1.0 - ph) * 6.0)
		Lib.flameTongue(p, x, cy.call(x) - width.call(x) * 0.6, h, 1.1 + 1.6 * (x / L), -h * 0.55, N, n, H, LAYERS)
	# the stream: a white core in yellow, orange and a red skin, surges racing down it
	var P := Px.round(D * 3.0)
	for x in floori(L) + 1:
		var c: float = cy.call(x)
		var w: float = width.call(x) * (1.0 + 0.15 * Lib.pnoise(x * 0.4 - (t / D) * 24.0, 24.0, S + 4.0))
		if w < 0.4:
			continue
		var surge := 1 if fmod(fmod(x * 0.035 - (t / D) * P, 1.0) + 1.0, 1.0) < 0.12 else 0
		for y in range(int(floorf(c - w - 1.0)), int(ceilf(c + w + 1.0)) + 1):
			var q := absf(y + 0.5 - c) / w
			if q > 1.15:
				continue
			# a white core near the nozzle cooling to yellow down the stream; ragged red skin
			var lvl := (0 if q < 0.3 else (1 if q < 0.55 else (2 if q < 0.78 else (3 if q < 1.0 else 4)))) + (1 if x > L * 0.45 and q < 0.55 else 0)
			lvl = maxi(0, mini(4, lvl - surge))
			if lvl == 4 and Lib.pnoise(x * 0.5 + y * 7.3 - (t / D) * 40.0, 40.0, S + 6.0) < 0.0:
				continue
			p.px(x, y, [H[0], H[2], H[4], H[6], H[7]][lvl])
		# two hot strands twisting through the fuel, racing downstream
		for ph: float in [0.0, PI]:
			var a := x * 0.22 - (t / D) * PI * 2.0 * 9.0 + ph
			var sy := c + sin(a) * w * 0.55
			if cos(a) > -0.1 and w > 1.2:
				p.px(x, sy, H[0] if cos(a) > 0.55 else H[1])
	# the pilot at the nozzle: a blue cone of gas where it lights
	var pk := flow(t)
	for x in 6:
		for y in range(-2, 3):
			if absi(y) <= 2 - x * 0.3:
				p.px(x, y, (PL[2] if x < 2 else PL[1]) if absi(y) < 1 else PL[0])
	Lib.solid(p, 1.0, 0.0, 1.6 * pk, WHITE)

	# burning drops shaken off the stream: they arc down trailing flame and burn out
	Lib.looped(t, D, 10, S + 200.0, func(r: Px.Rng) -> Dictionary: return {"d": r.range(20.0, 95.0), "vx": r.range(0.3, 0.6), "vy": r.range(-25.0, 15.0), "life": r.range(0.35, 0.6)}, func(q: Dictionary, age: float) -> void:
		var tb := t - age
		if flow(tb - q.d / V) < 0.5:
			return
		var at := func(a: float) -> Array: return Lib.drift(q.d, cy.call(q.d), V * q.vx, q.vy, a, 0.0, 260.0, 1.2, 0.5)
		var j := 4
		while j >= 1:
			var a := age - j * 0.035
			if a < 0.0:
				j -= 1
				continue
			var xy: Array = at.call(a)
			Lib.firePuff(p, xy[0], xy[1], 1.0 - minf(0.99, j * 0.18 + age / q.life * 0.4), 1.8 - j * 0.25, 0.3, H, 0.06)
			j -= 1
		var xy: Array = at.call(age)
		var k: float = 1.0 - age / q.life
		p.px(xy[0], xy[1], H[0] if k > 0.5 else H[2])
		p.px(xy[0] + 1.0, xy[1], H[3])
		p.glow(xy[0], xy[1], 6.0, H[3], 0.45 * k))
	# the cough: when the jet sputters the nozzle spits sparks and a puff of smoke
	Lib.looped(t, D, 12, S + 300.0, func(r: Px.Rng) -> Dictionary: return {"born": COUGH + r.range(0.0, 0.08), "a": r.range(-0.8, 0.8), "v": r.range(120.0, 240.0), "life": r.range(0.2, 0.45)}, func(q: Dictionary, age: float) -> void:
		var u := fmod(fmod(t - age, D) + D, D)
		if absf(u - q.born) > 0.06:
			return
		var e := Lib.drift(4.0, 0.0, cos(q.a) * q.v, sin(q.a) * q.v, age, 0.0, 300.0, 2.5, 2.5)
		Lib.spark(p, e[0], e[1], e[2], e[3], 1.0 - age / q.life, SPARKS))
	# and spits a few blobs of burning fuel that fall short
	Lib.looped(t, D, 5, S + 350.0, func(r: Px.Rng) -> Dictionary: return {"born": COUGH + r.range(0.01, 0.1), "v": r.range(90.0, 170.0), "vy": r.range(-30.0, 10.0), "life": r.range(0.25, 0.4), "s": r.range(1.6, 2.6)}, func(q: Dictionary, age: float) -> void:
		var u := fmod(fmod(t - age, D) + D, D)
		if absf(u - q.born) > 0.05:
			return
		var xy := Lib.drift(4.0, 0.0, q.v, q.vy, age, 0.0, 200.0, 2.0, 1.0)
		Lib.firePuff(p, xy[0], xy[1], 1.0 - age / q.life, q.s, 0.2, H, 0.1, -0.86, -0.5))
	if true:
		var u := fmod(fmod(t, D) + D, D)
		var a := u - COUGH
		if a > 0.0 and a < 0.7:
			Lib.smokePuff(p, 8.0 + a * 20.0, -a * 18.0, 1.0 - a / 0.7, 3.0, SMOKE, false, 0.8)

	# light: the pilot, the stream, the burning tip
	p.glow(2.0, 0.0, 34.0 * pk, GLOW, 0.8 * pk)
	p.glow(2.0, 0.0, 9.0, PL[2], 0.45 * pk)
	var d := 8
	while d <= L:
		p.glow(d, cy.call(d), 12.0 + d * 0.16, GLOW, 0.3 * flow(t - d / V))
		d += 8
	p.glow(L, cy.call(L) - 10.0, 52.0, GLOW, 0.34 * flow(t - L / V))
