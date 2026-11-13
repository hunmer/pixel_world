# The banded body, travelling pulses and spiralling sparks follow Sprite Fusion's open-source energy beam
# (https://www.spritefusion.com/pixel-art-vfx/energy), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/projectiles/laser-bolt.js@a503d9efc797355af967151e4edf957b3d00f280
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Laser bolt",
	"desc": "A red laser bolt: a white-hot core in a rounded head, red bands tapering back, pulses racing down it, a tail that shimmers apart into wavering dashes.",
	"tags": ["projectile", "laser", "energy", "sci-fi", "directional", "loop"],
	"size": [128, 32],
	"origin": [108, 16],
	"duration": 0.5,
	"loop": true,
	"fps": 30,
	"bg": "sky",
	"options": {"palette": ["#2a0610", "#5c0d1c", "#9a1428", "#d8243a", "#ff4d5e", "#ff8a94", "#ffd0d4", "#ffffff"], "length": 40, "seed": 2},
}


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var L: float = o.length
	var S: float = o.seed
	var D: float = meta.duration
	var ph := t / D
	var fr := floorf(t * 30.0 + 1e-6)
	var left: float = -meta.origin[0] + 2.0

	# the shimmering tail: dashes shed off the bolt's end, wavering, flickering and cooling as they fall behind
	Lib.beat(t, D, 14, S, func(r): return r.range(0.18, 0.3), func(age: float, life: float, r: Px.Rng) -> void:
		var k := age / life
		var x0 := -L * 0.8 - age * r.range(150.0, 230.0)
		var len := r.range(3.0, 7.0) * (1.0 - k * 0.5)
		var y := 0.5 + sin(x0 * 0.25 + ph * TAU * 2.0) * (0.5 + k * 1.5) + r.range(-0.6, 0.6) * k
		if x0 - len < left or Px.rand(fr, r.int_(0, 999)) < k * 0.5:
			return
		p.line(x0, y, x0 - len, y, C[5] if k < 0.3 else (C[4] if k < 0.6 else C[3]))
		if k < 0.4:
			p.glow(x0 - len / 2.0, y, 4.0, C[4], 0.3 * (1.0 - k)))

	# the body: bands round a white core, thickest just behind the rounded head and tapering to a thread, a
	# pulse running back down it every so often; the edge breaks up a little as the light shimmers
	p.shade(-L - 1.0, -5.0, 4.0, 6.0, func(x: float, y: float) -> Variant:
		var d := -x + 3.0
		var u := d / (L + 3.0)
		if u < 0.0 or u > 1.0:
			return null
		var head := sqrt(maxf(0.0, 1.0 - pow((3.0 - d) / 3.0, 2.0))) if d < 3.0 else 1.0
		var w := (3.4 * pow(1.0 - u, 0.9) + 0.5) * head * (1.0 + 0.08 * sin(d * 0.9 - ph * TAU * 4.0))
		var v := absf(y - 0.5) / w
		if v > 1.2:
			return null
		if v > 1.0 and (u > 0.5 or Px.rand(floorf(x), fr) > 0.6):
			return null
		var pulse := 1 if fmod(fmod(d * 0.05 - ph * 3.0, 1.0) + 1.0, 1.0) < 0.12 else 0
		var lvl := (7 if u < 0.6 else 6) if v < 0.22 else ((6 - (1 if u > 0.5 else 0)) if v < 0.45 else (4 if v < 0.72 else (3 if v <= 1.0 else 2)))
		return C[mini(7, lvl + (pulse if v < 0.72 else 0))])
	# sparks spiralling round the core, a bright one on the near side and a dim one behind
	for s in [0.0, PI]:
		var d := 2.0
		while d < L * 0.7:
			var a: float = d * 0.45 - ph * TAU * 3.0 + s
			var y := 0.5 + sin(a) * (2.2 * (1.0 - d / L) + 0.6)
			if cos(a) > 0.3:
				p.dot(-d, y, WHITE if cos(a) > 0.8 else C[6])
			d += 1.0
	# the head's glint, flickering, and the light
	var g := 0.75 + 0.25 * sin(ph * TAU * 2.0)
	Px.sparkle(p, 1.0, 0.5, 3.0 + Px.round(g * 2.0), C[6], C[4], 0.5)
	p.glowLine(1.0, 0.5, -L, 0.5, 9.0, C[3], 0.4)
	p.glow(-2.0, 0.5, 20.0, C[3], 0.5 * g)
	p.glow(1.0, 0.5, 6.0, WHITE, 0.25)
