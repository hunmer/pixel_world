# The flash lobes, spark, smoke wisp and casing recipes are adapted from Sprite Fusion's open-source
# muzzle-flash (https://www.spritefusion.com/pixel-art-vfx/muzzle-flash), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/projectiles/muzzle-smg.js@f0c6a5696fe02db15ab2480bef7e1b7455dcef39
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "SMG burst",
	"desc": "Sustained fire at twelve rounds a second: each shot a different spiky flash with a white core, sparks, smoke wisps piling up and drifting, brass casings bouncing on the floor.",
	"tags": ["projectile", "muzzle", "gun", "automatic", "flash", "smoke", "casing", "directional", "loop"],
	"size": [112, 72],
	"origin": [56, 66],
	"duration": 1,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"options": {
		"palette": ["#4a1712", "#8a1f17", "#c9281f", "#f2561d", "#ff8a2a", "#ffc23d", "#ffe26b", "#fff3a6", "#ffffff"],
		"brass": ["#4a2e10", "#8c5c1c", "#d9a441", "#ffe39a"],
		"smoke": ["#26222e", "#3b3644", "#544e5e", "#6f6979", "#8c8596", "#aca5b5", "#cbc4d2"],
		"height": 26,
		"seed": 6,
	},
}

const SHOTS := 12
const F1 := 1.0 / 30.0


# every live copy of every shot: fn(s, age) for shot s fired at s * D / SHOTS, while age < life
static func shots(t: float, D: float, life: float, fn: Callable) -> void:
	for s in SHOTS:
		var age := Px.wrap(t - (s * D) / SHOTS + 1e-7, D)
		while age < life:
			fn.call(s, age)
			age += D


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var F := Px.fit(o.palette, 9)
	var B := Px.fit(o.brass, 4)
	var SM := Px.fit(o.smoke, 7)
	var S: float = o.seed
	var D: float = meta.duration
	var H: float = o.height
	var MX := 0.0
	var MY := -H
	var SP := [F[7], F[6], F[4], F[3]]
	var top: float = -meta.origin[1] + 1.0
	# the latest shot's pop of light, for the smoke it lights up
	var pop := [0.0]
	shots(t, D, 0.2, func(_s: int, age: float) -> void: pop[0] = maxf(pop[0], exp(-(age + 0.008) / 0.035)))

	# smoke: every shot leaves a few wisps that push forward, slow, swell and rise, piling up into a drifting haze
	var puffs := []
	shots(t, D, 2.2, func(s: int, age: float) -> void:
		for j in 3:
			var r := Px.rng(S, s, j, 3)
			var life := r.range(1.5, 2.2)
			var dl := j * 0.03
			if age < dl or age - dl >= life:
				continue
			var a := age - dl
			var k := a / life
			var port := j == 2
			# a push forward that dies fast, then the warm gas lifts it and the air drifts it back over the gun
			var vx := r.range(-12.0, 6.0) if port else r.range(45.0, 100.0) * (1.0 - j * 0.4)
			var vy := -r.range(14.0, 26.0) if port else -r.range(4.0, 16.0)
			var x := (-7.0 if port else MX + 3.0) + (vx * (1.0 - exp(-3.2 * a))) / 3.2 - r.range(3.0, 7.0) * a * a + sin(a * 2.1 + r.range(0.0, TAU)) * a * 2.5
			var y := (MY - 2.0 if port else MY) + (vy * (1.0 - exp(-2.4 * a))) / 2.4 - 0.5 * r.range(9.0, 16.0) * a * a
			var rad := (1.0 if port else 1.2) + r.range(2.0, 4.5) * (1.0 - exp(-1.4 * a))
			if y - rad < top + 1.0:
				continue
			var edge := minf(1.0, (y - rad - top) / 12.0)
			puffs.append({"x": x, "y": y, "r": rad, "a": minf(1.0, a * 10.0) * pow(1.0 - k, 1.6) * (0.24 if port else 0.34) * edge, "b": Px.clamp(0.92 - k * 0.6), "w": pop[0] * exp(-Px.hypot(x - MX, y - MY) / 9.0)}))
	Lib.cloud(p, puffs, SM, [SM[0], Px.mix(F[1], SM[1], 0.5), Px.mix(F[2], SM[2], 0.4), F[3], F[4], F[5], F[7]], {"dens": 1.4, "max": 0.7, "lit": 1.3})

	# casings: thrown up and back out of the ejection port, tumbling, bouncing on the floor, then lying a moment
	shots(t, D, D, func(s: int, age: float) -> void:
		var r := Px.rng(S, s, 7)
		var k := Lib.casing(-7.0, MY - 1.0, -r.range(18.0, 48.0), -r.range(85.0, 135.0), r.sign() * r.range(20.0, 32.0), age, 850.0, -0.5, 0.42, r.range(0.0, TAU))
		Lib.drawCasing(p, k, B, Px.clamp((D - age) / 0.25)))

	# the flash: a hero frame with a white core, then a cooler, smaller one; every shot its own shape
	shots(t, D, 2.0 * F1, func(s: int, age: float) -> void:
		var r := Px.rng(S, s)
		var f := 1 if age < F1 else 2
		var tilt := r.range(-0.06, 0.06)
		var L := Lib.flashShape(r, f, {"size": r.range(0.95, 1.2), "spike": [12.0, 21.0], "diag": [6.0, 11.0], "cross": [4.0, 7.5], "back": [2.5, 5.0]})
		var C := [WHITE, F[7], F[6], F[3]] if f == 1 else [F[7], F[6], F[4], F[2]]
		Lib.flash(p, MX, MY, tilt, L, C, s * 7 + f))

	# sparks and unburnt grains spat forward with each shot, dropping as they slow
	shots(t, D, 0.3, func(s: int, age: float) -> void:
		for j in 5:
			var r := Px.rng(S, s, j, 11)
			var life := r.range(0.05, 0.16) * (1.8 if j > 2 else 1.0)
			if age >= life:
				continue
			var a := r.range(-0.3, 0.3)
			var sp := r.range(170.0, 380.0) * (0.5 if j > 2 else 1.0)
			var xy := Px.fly(MX + 2.0, MY, cos(a) * sp, sin(a) * sp, age, 420.0, 2.2)
			var v := Px.flyV(cos(a) * sp, sin(a) * sp, age, 420.0, 2.2)
			if j > 2:
				p.px(xy[0], xy[1], F[6] if age / life < 0.5 else F[4])
			else:
				Lib.spark(p, xy[0], xy[1], v[0], v[1], 1.0 - age / life, SP, 0.45, 0.011))

	# light: a hot pop at the muzzle on every shot, the floor and smoke catching it
	shots(t, D, 0.15, func(_s: int, age: float) -> void:
		var k := exp(-(age + 0.008) / 0.03)
		p.glow(MX + 4.0, MY, 26.0, F[4], 0.8 * k)
		p.glow(MX + 2.0, MY, 7.0, WHITE, 0.45 * k)
		p.glow(MX + 2.0, 0.0, 12.0, F[4], 0.16 * k))
