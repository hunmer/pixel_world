# The crescent recipe is adapted from Sprite Fusion's open-source slash, and the star from his impact
# (https://www.spritefusion.com/pixel-art-vfx), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/melee/uppercut.js@70c719906577a24a1aeb37278a85cc818d1057af
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Uppercut",
	"desc": "A crescent rises from the floor past the face, and at the top a comic impact star bursts: bold outline, hot core, burst lines, twinkles and sparks.",
	"tags": ["melee", "uppercut", "punch", "rising", "launcher", "comic", "combat", "directional", "one-shot"],
	"size": [132, 128],
	"origin": [48, 110],
	"duration": 0.85,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {
		"palette": ["#3a1408", "#7a2a10", "#c4501a", "#f08a2a", "#ffc94a", "#fff2a8", "#ffffff"],
		"outline": "#2a0a08",
		"sparks": ["#fff3a6", "#ffe26b", "#ff8a2a", "#f2561d"],
		"seed": 11,
	},
}

static var FISTS := Px.merge(Px.READY, {"fx": 12, "fy": -25, "bx": 9, "by": -27, "crouch": 3, "lean": 1})
static var COIL := Px.merge(FISTS, {"crouch": 7, "lean": 3, "fx": 8, "fy": -11, "bx": 8, "by": -27, "ffx": 10, "fbx": -9})
static var TOP := Px.merge(FISTS, {"x": 1, "y": -11, "crouch": -1, "lean": 2, "fx": 12, "fy": -42, "bx": -6, "by": -21, "ffx": 8, "ffy": -8, "fbx": -3, "fby": -2, "toeB": true, "ghost": 1})
static var act := {
	"target": {"x": 44},
	"poses": [
		[-0.42, FISTS],
		[-0.16, COIL],
		[0, Px.merge(COIL, {"crouch": 8})],
		[0.03, Px.merge(FISTS, {"y": -4, "crouch": 1, "lean": 4, "fx": 18, "fy": -27, "bx": -5, "by": -23, "ffx": 9, "fbx": -7, "toeB": true, "ghost": 1}), "snap"],
		[0.076, TOP, "snap"],
		[0.3, Px.merge(TOP, {"y": -13, "ghost": null})],
		[0.56, Px.merge(TOP, {"y": 0, "crouch": 2, "fx": 13, "fy": -31, "ffx": 7, "ffy": -6, "fbx": -5, "fby": -5, "ghost": null}), "in"],
		[0.6, Px.merge(FISTS, {"y": 0, "crouch": 7, "lean": 3, "fx": 12, "fy": -14, "bx": -6, "by": -16, "ffx": 10, "fbx": -9}), "snap"],
		[0.98, FISTS],
	],
	"hits": [{"t": 0.076, "stop": 0.13, "shake": 0.18, "amp": 2, "push": -2.6, "straw": 18, "y": -34}],
	"dust": [{"t": 0.03, "x": 8, "n": 6}, {"t": 0.6, "x": 0, "n": 6}],
}


var C: Array
var INK: int
var Rg: Px.Rng
var ps: Px.Particles
var lights: Px.Lights
var A: Dictionary
var top: Dictionary
var SX: float
var SY: float
var HIT: float
var spikes: Array
var bursts: Array
var t := 0.0
var hit := false
var kicked := false


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 7)
	INK = Px.hex(o.outline)
	Rg = Px.Rng.new(o.seed)
	ps = Px.Particles.new({"rng": Rg, "ground": func(): return 0.0, "sparks": o.sparks})
	lights = Px.Lights.new()
	# up from the floor in front, bowing forward past the face, to the top
	A = Lib.swing({"cx": 8.0, "cy": -25.0, "R": 27.0, "sy": 1.0, "rot": 0.0, "a0": 1.08, "dir": -1.0, "span": 2.5, "W": 13.0, "t0": 0.02, "sweep": 0.07, "hold": 0.05, "trail": 0.22, "ramp": C})
	top = Lib.slashEnd(A)
	SX = top.x + 3.0
	SY = top.y - 5.0
	HIT = A.t0 + A.sweep * 0.8
	spikes = Px.arr(10, func(i): return {"a": (i / 10.0) * TAU + Rg.range(-0.12, 0.12) - PI / 2.0, "len": (7.0 if i % 2 else 13.0) + Rg.range(0.0, 4.0), "w": 2.2 if i % 2 else 3.0})
	bursts = Px.arr(8, func(i): return {"a": (i / 8.0) * TAU + 0.2 + Rg.range(-0.15, 0.15), "r0": Rg.range(15.0, 18.0), "L": Rg.range(5.0, 9.0)})


func update(dt: float) -> void:
	t += dt
	if not kicked:
		kicked = true
		# the fist comes up off the floor
		for i in 4:
			ps.spawn(P.DUST, 18.0 + Rg.range(-4.0, 4.0), -1.0, Rg.range(-30.0, 30.0), -Rg.range(5.0, 20.0), Rg.range(0.3, 0.55), "#6a6080", Rg.range(1.5, 2.6))
	if not hit and t >= HIT:
		hit = true
		lights.add(SX, SY, 56.0, C[4], 0.6, 0.4)
		lights.add(SX, SY, 18.0, WHITE, 0.7, 0.08)
		for i in 16:
			var a := -PI / 2.0 + Rg.range(-1.6, 1.6)
			var sp := Rg.range(120.0, 320.0)
			ps.spawn(P.SPARK, SX, SY, cos(a) * sp, sin(a) * sp, Rg.range(0.15, 0.45))
		for i in 6:
			var a := Rg.range(0.0, TAU)
			var d := Rg.range(14.0, 24.0)
			ps.spawn(P.STAR, SX + cos(a) * d, SY + sin(a) * d, cos(a) * 20.0, sin(a) * 20.0 - 10.0, Rg.range(0.25, 0.5), C[5] if Rg.chance(0.5) else WHITE, Rg.range(1.4, 2.6), Rg.range(0.04, 0.18))
	ps.update(dt)
	lights.update(dt)


func draw(p: Px.Painter) -> void:
	Lib.slash(p, A, t)
	# speed lines rising beside the crescent while it goes up
	var u: float = t - A.t0
	if u > 0.0 and u < 0.16:
		for dyL: Array in [[A.cx + A.R + 7.0, -16.0, 18.0], [A.cx + A.R + 11.0, -30.0, 12.0], [A.cx - 4.0, -40.0, 10.0]]:
			var dx: float = dyL[0]
			var y0: float = dyL[1]
			var L: float = dyL[2]
			var k := u / 0.16
			var y := y0 - 30.0 * k
			var d := 0.0
			while d < L:
				p.dot(dx, y + d, WHITE if d < 3.0 else (C[5] if d < L * 0.5 else C[3]), (1.0 - d / L) * (1.0 - k))
				d += 1.0
	if u > 0.0 and u < A.sweep + 0.06:
		var xy := Lib.onSwing(A, A.R - 5.0, A.span * Px.Ease.outExpo(Px.clamp(u / A.sweep)))
		p.glow(xy[0], xy[1], 34.0, C[3], 0.45 * (1.0 - u / (A.sweep + 0.06)))
	# the comic star: pops past full size, holds, then shrinks away turning, with burst lines round it
	var q := t - HIT
	if q >= 0.0 and q < 0.36:
		var pop := Px.Ease.outBack(Px.clamp(q / 0.05), 2.6)
		var out := 1.0 - Px.smooth(0.16, 0.36, q)
		var sc := pop * (0.35 + 0.65 * out)
		var turn := q * 1.2
		var sp := spikes.map(func(s): return Px.merge(s, {"a": s.a + turn}))
		if sc > 0.08:
			Lib.star(p, SX, SY, sp, sc * 1.12, 1.0, INK, INK, INK, INK)
			Lib.star(p, SX, SY, sp, sc, 1.0, WHITE if q < 0.05 else C[6], C[4], C[3], C[2])
		p.glow(SX, SY, 30.0, C[4], 0.45 * out)
	if q >= 0.02 and q < 0.24:
		# a ring bursts out round the star, white to orange, breaking into dots
		var k := (q - 0.02) / 0.22
		var r := 7.0 + 17.0 * Px.Ease.outCubic(k)
		var th := maxf(1.0, 2.2 * (1.0 - k))
		var col: int = WHITE if k < 0.25 else (C[5] if k < 0.5 else (C[4] if k < 0.75 else C[3]))
		var a := 0.0
		while a < TAU:
			var o := 0.0
			while o < th:
				p.dot(SX + cos(a) * (r - o), SY + sin(a) * (r - o), col, 1.15 - k)
				o += 0.5
			a += 0.6 / r
	if q >= 0.02 and q < 0.2:
		var k := (q - 0.02) / 0.18
		for b: Dictionary in bursts:
			var r0: float = b.r0 + 10.0 * Px.Ease.outCubic(k)
			var ca := cos(b.a)
			var sa := sin(b.a)
			p.line(SX + ca * r0, SY + sa * r0, SX + ca * (r0 + b.L * (1.0 - k)), SY + sa * (r0 + b.L * (1.0 - k)), WHITE if k < 0.4 else C[5], 1.1 - k)
	ps.draw(p)
	lights.draw(p)
