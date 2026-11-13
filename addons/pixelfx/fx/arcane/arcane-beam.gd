# The beam (banded across, pulses running down it, sine strands that brighten in front, a source flare with
# spinning rays, an end flare spraying rays and sparks) is adapted from Sprite Fusion's open-source energy beam
# (https://www.spritefusion.com/pixel-art-vfx/energy), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/arcane/arcane-beam.js@7ac65ffe9f01a05aba85be08dc31c2c836f0cd33
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE

const D := 1.2
const HX := 15.0
const HY := -24.0
const L := 168.0
const W := 6.0

static var meta := {
	"name": "Arcane beam",
	"desc": "A beam fires right from the hand: a white core, strands twisting round it, pulses running down it, a flaring source and an end that sprays sparks.",
	"tags": ["arcane", "beam", "laser", "ray", "magic", "directional", "loop"],
	"size": [264, 100],
	"origin": [26, 84],
	"duration": D,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {"palette": Px.PAL.arcane, "seed": 10},
}

static var AIM := Px.merge(Px.READY, {"x": -3, "crouch": 4, "lean": 4, "fx": 18, "fy": -24, "bx": 13, "by": -20, "ffx": 11, "fbx": -9, "toeB": true})
static var PULL := Px.merge(Px.READY, {"x": -3, "crouch": 4, "lean": -3, "fx": 1, "fy": -20, "bx": 4, "by": -22, "ffx": 9, "fbx": -7})
static var act := {
	"target": {"x": 186},
	"poses": [
		[-0.62, Px.merge(Px.READY, {"x": -3})],
		[-0.3, PULL],
		[-0.04, Px.merge(PULL, {"crouch": 5, "lean": -4})],
		[0, Px.merge(AIM, {"crouch": 3}), "snap"],
		[0.3, AIM],
		[0.6, Px.merge(AIM, {"crouch": 5, "lean": 3})],
		[0.9, AIM],
		[1.2, Px.merge(AIM, {"crouch": 3})],
	],
	"hits": [{"t": 0.1, "push": 0.5, "straw": 3, "flash": 0.02, "y": -24}, {"t": 0.7, "push": 0.5, "straw": 3, "flash": 0.02, "y": -24}],
	"dust": [{"t": 0, "x": -10, "n": 5, "dir": -1}],
}


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var ph := t / D
	var S: float = o.seed
	var EX := HX + L
	# the body, built across from a white core out to a dithered violet edge, wobbling and pulsing as it goes
	var LV := [WHITE, C[6], C[5], C[4], C[3], C[2]]
	var d := 0.0
	while d <= L:
		var x := HX + d
		var w := W * (1.0 + 0.12 * sin(d * 0.35 - ph * TAU * 8.0)) * minf(1.0, (d + 3.0) / 7.0)
		var pulse := 1 if Px.fract(d * 0.025 - ph * 4.0) < 0.07 else 0
		var q0 := -w * 1.3
		while q0 <= w * 1.3:
			var q := absf(q0) / w
			var y := HY + q0
			var lv := 0 if q < 0.2 else (1 if q < 0.4 else (2 if q < 0.62 else (3 if q < 0.85 else (4 if q < 1.0 else 5))))
			lv = maxi(0, lv - pulse)
			if lv == 5 and Lib.bayer(x, y) > (1.3 - q) / 0.3:
				q0 += 0.5
				continue
			p.px(x, y, LV[lv])
			q0 += 0.5
		# three strands twisting round it: bright on the near side, gone behind
		for s in 3:
			var a := d * 0.17 - ph * TAU * 6.0 + (s * TAU) / 3.0
			var off := sin(a) * w * 1.05
			if cos(a) > -0.15:
				p.dot(x, HY + off, WHITE if cos(a) > 0.55 else C[6])
		if (Px.roundi(d * 2.0) & 11) == 0:
			p.glow(x, HY, w * 2.2 + 4.0, C[5], 0.2)
		d += 0.5

	# the source: a flickering flare with spinning rays at the hand
	var fr := 4.2 + sin(ph * TAU * 10.0) * 0.6
	for i in 4:
		var a := ph * TAU * 2.5 + (i * TAU) / 4.0
		var l := 7.0 + 3.0 * sin(ph * TAU * 6.0 + i)
		p.line(HX, HY, HX + cos(a) * l, HY + sin(a) * l, func(u: float) -> int: return WHITE if u < 0.5 else C[6], func(u: float) -> float: return 1.0 if u < 0.6 else 1.6 - u)
	p.circle(HX, HY, fr + 1.5, C[4])
	p.circle(HX, HY, fr, C[6])
	p.circle(HX, HY, fr * 0.6, WHITE)
	p.glow(HX, HY, 32.0, C[5], 0.8)
	# energy drawn into the hand
	Px.cycle(t, D, 10, S * 3.0 + 1.0, 0.18, func(age: float, life: float, r: Px.Rng) -> void:
		var a := r.range(0.0, TAU)
		var dd := 16.0 * (1.0 - age / life) + 3.0
		var x := HX + cos(a) * dd
		var y := HY + sin(a) * dd
		p.dot(x, y, WHITE if age / life > 0.6 else C[6]))

	# the end: a hot flare spraying rays, rings shocking out, sparks thrown back and falling
	var ir := 5.0 + sin(ph * TAU * 12.0) * 0.8
	for i in 7:
		var a := PI + (i - 3) * 0.36
		var l := 8.0 + 8.0 * absf(Px.loopNoise(ph, 4.0, S * 7.0 + i))
		p.line(EX, HY, EX + cos(a) * l, HY + sin(a) * l, func(u: float) -> int: return WHITE if u < 0.4 else (C[5] if i % 2 else C[6]), func(u: float) -> float: return 1.0 if u < 0.6 else 1.6 - u)
	for k in 3:
		var q := Px.fract(ph * 3.0 + k / 3.0)
		p.ring(EX, HY, 3.0 + 15.0 * Px.Ease.outCubic(q), maxf(1.0, 2.0 * (1.0 - q)), WHITE if q < 0.25 else C[5], 1.1 - q)
	p.circle(EX, HY, ir + 1.5, C[4])
	p.circle(EX, HY, ir, C[6])
	p.circle(EX, HY, ir * 0.55, WHITE)
	p.glow(EX, HY, 40.0, C[5], 0.9)
	p.glow(EX, HY, 12.0, WHITE, 0.6)
	# a fountain of sparks thrown up and back off the end, arcing down
	Px.cycle(t, D, 220, S * 3.0 + 2.0, func(g: Px.Rng) -> float: return g.range(0.18, 0.5), func(age: float, life: float, r: Px.Rng) -> void:
		var a := PI * 1.5 + r.range(-1.7, 0.45)
		var sp := r.range(70.0, 260.0)
		var vx := cos(a) * sp
		var vy := sin(a) * sp - 30.0
		var xy := Px.fly(EX, HY, vx, vy, age, 480.0, 2.2)
		var uv := Px.flyV(vx, vy, age, 480.0, 2.2)
		var x: float = xy[0]
		var y: float = xy[1]
		var ux: float = uv[0]
		var uy: float = uv[1]
		var k := 1.0 - age / life
		if y > -1.0:
			return
		var head: int = WHITE if k > 0.6 else (C[6] if k > 0.3 else C[5])
		var sp2 := Px.hypot(ux, uy)
		if not sp2:
			sp2 = 1.0
		var ln := minf(8.0, 1.0 + sp2 * 0.022)
		p.line(x - (ux / sp2) * ln, y - (uy / sp2) * ln, x, y, func(u: float) -> int: return head if u > 0.5 else C[4])
		p.glow(x, y, 3.0, head, 0.45 * k))
	Px.cycle(t, D, 6, S * 3.0 + 3.0, 0.3, func(age: float, life: float, r: Px.Rng) -> void:
		var k := sin((age / life) * PI)
		Px.sparkle(p, EX + r.range(-12.0, 4.0), HY + r.range(-12.0, 12.0), 1.0 + 2.5 * k, C[6], C[5], 0.4 * k))
	# violet vapour lifting off the end
	Px.cycle(t, D, 7, S * 3.0 + 5.0, func(g: Px.Rng) -> float: return g.range(0.8, 1.2), func(age: float, life: float, r: Px.Rng) -> void:
		var q := age / life
		var x := EX + r.range(-8.0, 4.0) - q * 6.0
		var y := HY - 4.0 - q * r.range(14.0, 24.0)
		var rad := r.range(3.0, 5.0) * (0.7 + 0.8 * q)
		p.disc(x, y, rad, C[4], func(dd: float) -> float: return 0.28 * sin(q * PI) * (1.0 - dd * dd)))
	# motes shed along the beam
	Px.cycle(t, D, 16, S * 3.0 + 4.0, func(g: Px.Rng) -> float: return g.range(0.3, 0.6), func(age: float, life: float, r: Px.Rng) -> void:
		var q := age / life
		var x := HX + r.range(10.0, L - 10.0) + q * 20.0
		var y := HY + r.sign() * (W + 1.0 + q * r.range(4.0, 10.0))
		Lib.mote(p, x, y, 40.0, (y - HY) * 1.5, C[6] if r.chance(0.5) else C[5], 0.6, 1.0 - q, 0.3))
	# the floor beneath catches the light
	p.glow(EX, -1.0, 30.0, C[5], 0.25)
	p.glow(HX + L / 2.0, -1.0, 60.0, C[4], 0.12)
