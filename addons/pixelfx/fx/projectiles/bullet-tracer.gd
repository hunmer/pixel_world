# The spark and streak recipes are adapted from Sprite Fusion's open-source impact ricochet
# (https://www.spritefusion.com/pixel-art-vfx/impact), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/projectiles/bullet-tracer.js@75f195d979ad43f1ec19046297fe7e5af1e77f47
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Bullet tracer",
	"desc": "A white-hot slug tearing along, its tracer burning behind it in a long streak that sputters and cools from white through gold to red, shedding sparks and a thread of smoke.",
	"tags": ["projectile", "bullet", "tracer", "gun", "directional", "loop"],
	"size": [200, 40],
	"origin": [184, 18],
	"duration": 0.6,
	"loop": true,
	"fps": 30,
	"bg": "sky",
	"options": {
		"palette": ["#4a1712", "#8a1f17", "#c9281f", "#f2561d", "#ff8a2a", "#ffc23d", "#ffe26b", "#fff3a6", "#ffffff"],
		"smoke": ["#2e2a36", "#46404f", "#625b6b", "#817a8a", "#a39caa"],
		"length": 120,
		"speed": 520,
		"seed": 4,
	},
}

const SLUG := ["..oyyp..", ".ypwwwwp", "ywwwwwww", ".ypwwwwp", "..oyyp.."]


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var F := Px.fit(o.palette, 9)
	var SM := Px.fit(o.smoke, 5)
	var S: float = o.seed
	var D: float = meta.duration
	var L: float = o.length
	var V: float = o.speed
	var fr := floorf(t * 30.0 + 1e-6)
	var ph := (TAU * t) / D
	var left: float = -meta.origin[0] + 2.0

	# a thread of smoke off the cool end of the trace, wavering as it thins
	var puffs := []
	Lib.beat(t, D, 18, S + 7.0, func(r): return r.range(0.5, 0.7), func(age: float, life: float, r: Px.Rng) -> void:
		var k := age / life
		var x := -L * r.range(0.45, 0.8) - age * 90.0
		var y := 0.5 + sin(age * 6.0 + r.range(0.0, TAU)) * age * 3.0 - age * age * 8.0
		if x < left + 6.0:
			return
		puffs.append({"x": x, "y": y, "r": 1.2 + age * 4.0, "a": 0.55 * (1.0 - k) * minf(1.0, age * 8.0) * Px.smooth(left, left + 30.0, x), "b": 0.95 - k * 0.4, "w": 0.0}))
	Lib.cloud(p, puffs, SM, SM, {"dens": 1.2, "max": 0.6})

	# the trace: a tapering body of burning gas near the slug, banded white core, gold, an orange rim; past it a
	# one-pixel line cooling to red. The compound sputters, so brightness ripples back along it, and the cold end
	# breaks into dashes
	var heat := func(d: float) -> float: return 1.0 - pow(d / L, 0.8) + Px.noise(d * 0.12 - t * 40.0, S) * 0.12 + 0.08 * sin(d * 0.35 - ph * 9.0)
	var yAt := func(d: float) -> float: return 0.5 + sin(d * 0.09 + ph * 2.0) * (d / L) * 0.8
	var HOT := L * 0.32
	p.shade(-HOT - 1.0, -4.0, 1.0, 5.0, func(x: float, y: float) -> Variant:
		var d := -x
		var u := d / HOT
		if u < 0.0 or u > 1.0:
			return null
		var w := 0.7 + 2.3 * pow(1.0 - u, 1.4) * (0.9 + 0.1 * sin(d * 0.8 - ph * 12.0))
		var v := absf(y - yAt.call(d)) / w
		if v > 1.0:
			return null
		var h: float = heat.call(d)
		return (WHITE if h > 0.8 else F[7]) if v < 0.38 else ((F[7] if h > 0.75 else (F[6] if h > 0.6 else F[5])) if v < 0.7 else (F[5] if u < 0.5 else F[4])))
	var d := HOT
	while d <= L:
		var u := d / L
		var h: float = heat.call(d)
		if u > 0.55 and Px.rand(floorf(d / 3.0), fr, S) < (u - 0.55) * 1.6:
			d += 0.5
			continue
		var c: int = F[6] if h > 0.55 else (F[5] if h > 0.42 else (F[4] if h > 0.3 else (F[3] if h > 0.18 else (F[2] if h > 0.08 else F[1]))))
		p.dot(-d, yAt.call(d), c, 1.0 if u < 0.85 else (1.0 - u) / 0.15)
		d += 0.5
	p.glowLine(-2.0, 1.0, -L * 0.45, 1.0, 6.0, F[4], 0.35)
	p.glowLine(-2.0, 1.0, -L * 0.2, 1.0, 3.0, F[7], 0.3)

	# sparks of burning compound shed off the trace, dropping and cooling as they fall behind
	var SP := [F[7], F[6], F[4], F[3]]
	Lib.beat(t, D, 16, S + 2.0, func(r): return r.range(0.1, 0.28), func(age: float, life: float, r: Px.Rng) -> void:
		var w := Lib.wake(-r.range(4.0, L * 0.5), 0.5 + r.range(-0.5, 1.0), -r.range(10.0, 80.0), r.range(-60.0, 50.0), age, V * 0.35, 3.0, 260.0)
		var x: float = w[0]
		if x > left + 8.0:
			Lib.spark(p, x, w[1], w[2], w[3], 1.0 - age / life, SP, 0.45, 0.012, 6.0))

	# the slug: a white-hot pointed round, pale-rimmed, its nose a point of light
	p.sprite(SLUG, {"w": WHITE, "p": F[7], "y": F[6], "o": F[5]}, -1.0, -1.0)
	p.glow(2.0, 1.0, 24.0, F[4], 0.5)
	p.glow(3.0, 1.0, 8.0, WHITE, 0.55)
