# The tangent spark streaks are adapted from Sprite Fusion's open-source energy and impact effects
# (https://www.spritefusion.com/pixel-art-vfx/energy), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/projectiles/energy-disc.js@e46a4755323461d7918f479da876af02302291e4
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Energy disc",
	"desc": "A sawblade of crackling energy spinning flat out as it flies: hooked teeth bright on their leading edges, a white hub, spiral arms churning, sparks flung off the teeth.",
	"tags": ["projectile", "disc", "saw", "energy", "sci-fi", "directional", "loop"],
	"size": [120, 52],
	"origin": [92, 26],
	"duration": 0.5,
	"loop": true,
	"fps": 30,
	"bg": "sky",
	"options": {"palette": ["#0a0f2e", "#172a78", "#2550d0", "#3f8cff", "#7cc8ff", "#c8f0ff", "#ffffff"], "size": 9, "teeth": 8, "speed": 220, "seed": 5},
}


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 7)
	var R: float = o.size
	var N: float = o.teeth
	var V: float = o.speed
	var S: float = o.seed
	var D: float = meta.duration
	var left: float = -meta.origin[0] + 2.0
	var rot := (TAU * 3.0 * t) / D
	var seg := TAU / N
	var frac := func(x: float) -> float: return x - floorf(x)

	# speed lines peeling off the rim, top and bottom, stretching back and cooling
	Lib.beat(t, D, 8, S + 4.0, func(r): return r.range(0.12, 0.22), func(age: float, life: float, r: Px.Rng) -> void:
		var k := age / life
		var side := -1.0 if r.chance(0.5) else 1.0
		var x0 := -2.0 - age * r.range(180.0, 260.0)
		var len := r.range(8.0, 16.0) * (0.5 + k)
		var y := side * (R + r.range(0.5, 3.0))
		if x0 - len < left:
			return
		p.line(x0, y, x0 - len, y, C[5] if k < 0.35 else (C[4] if k < 0.7 else C[3]), func(u): return 1.0 if u < 0.65 else (1.0 - u) / 0.35))
	p.glowLine(-2.0, 0.0, -26.0, 0.0, 8.0, C[3], 0.35)

	# sparks flung off the tooth tips along the spin, then left behind in the air
	var SP := [WHITE, C[5], C[4], C[3]]
	Lib.beat(t, D, 20, S, func(r): return r.range(0.12, 0.3), func(age: float, life: float, r: Px.Rng) -> void:
		var a := rot - r.range(0.0, TAU) * 0.0 + r.range(0.0, TAU)
		var tip := R + 3.5
		var x0 := cos(a) * tip
		var y0 := sin(a) * tip
		var v := r.range(120.0, 230.0)
		var w := Lib.wake(x0, y0, -sin(a) * v, cos(a) * v, age, V * 0.6, 2.4, 60.0)
		var x: float = w[0]
		var y: float = w[1]
		if x > left + 8.0 and absf(y) < 23.0:
			Lib.spark(p, x, y, w[2], w[3], 1.0 - age / life, SP, 0.45, 0.014, 7.0))

	# the disc: a white hub in a dark collar, spiral arms of energy churning, a bright rim; past the rim, hooked
	# teeth that run white on their leading faces, and a dim blur ring where the teeth have just been
	p.shade(-R - 5.0, -R - 5.0, R + 5.0, R + 5.0, func(x: float, y: float) -> Variant:
		var r := Px.hypot(x, y)
		var th := atan2(y, x)
		if r > R + 4.6:
			return null
		if r <= R:
			if r < 1.8:
				return WHITE
			if r < 2.9:
				return C[1]
			if r > R - 1.1:
				return C[5]
			var arm := sin(3.0 * (th - rot * 0.5) - r * 0.85)
			return C[5] if arm > 0.65 else (C[4] if arm > 0.2 else (C[3] if arm > -0.3 else C[2]))
		var ph: float = frac.call((th - rot) / seg)
		var h := 4.2 * pow(ph, 1.4)
		if r - R < h:
			return WHITE if ph > 0.86 else (C[6] if ph > 0.6 else (C[5] if ph > 0.35 else C[4]))
		if r - R < 1.6:
			return C[2]
		return null)
	# filaments of energy crackling from the hub to the rim, new every frame
	var fr := floorf(t * 30.0 + 1e-6)
	for j in 3:
		var g := Px.rng(fr, j, S)
		var a0 := g.range(0.0, TAU)
		var pts := []
		for i in 5:
			var rr := 2.5 + ((R - 3.0) * i) / 4.0
			var a := a0 + i * 0.25 + (g.range(-0.35, 0.35) if i else 0.0)
			pts.append([cos(a) * rr, sin(a) * rr])
		p.polyline(pts, C[6] if j else WHITE)
	p.ring(0.0, 0.0, R + 0.5, 1.0, C[6])
	# light: a soft pool, a hot hub, a glint riding the top of the rim
	p.glow(0.0, 0.0, 30.0, C[3], 0.4)
	p.glow(0.0, 0.0, 6.0, C[5], 0.35)
	p.glow(cos(rot) * R, sin(rot) * R, 5.0, C[6], 0.4)
