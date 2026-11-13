# The crescent, trace and glint recipe is adapted from Sprite Fusion's open-source slash, and the rolling dust and
# grit from his explosion (https://www.spritefusion.com/pixel-art-vfx), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/melee/spear-sweep.js@61979356918fe7ac57e415d82b82736b23b4457d
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const PF := Px.PF

static var meta := {
	"name": "Spear sweep",
	"desc": "A wide low sweep at shin height: a long flat crescent swings from behind the legs round the front, and the wind of it kicks a wake of dust and grit along the floor.",
	"tags": ["melee", "sweep", "spear", "polearm", "low", "aoe", "ground", "dust", "combat", "one-shot"],
	"size": [216, 84],
	"origin": [104, 70],
	"duration": 1.5,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {
		"palette": ["#0f2a2a", "#18504a", "#22806e", "#3fb894", "#8fe6c0", "#dcfff0", "#ffffff"],
		"sparks": ["#fff3a6", "#ffe26b", "#ff8a2a", "#f2561d"],
		"stone": "#4a3f69",
		"seed": 10,
	},
}

# upright in one hand; two hands take it low across the belt, he winds right round, and it whips through the front
static var REST_ := Px.merge(Px.READY, {"weapon": "spear", "sa": -1.42, "fx": 11, "fy": -21, "bx": 7, "by": -16})
static var COCK := Px.merge(REST_, {"two": true, "yaw": 2.5, "crouch": 6, "lean": 2, "fx": 15, "fy": -17, "sa": 0.05, "ffx": 9, "fbx": -8})
static var OUT_ := Px.merge(REST_, {"two": true, "x": 2, "crouch": 6, "lean": 6, "fx": 20, "fy": -15, "sa": 0.04, "ffx": 12, "fbx": -10, "toeB": true})
static var act := {
	"target": {"x": 62},
	"poses": [
		[-0.56, REST_],
		[-0.34, Px.merge(REST_, {"two": true, "crouch": 4, "fx": 14, "fy": -22, "sa": -0.7})],
		[-0.14, COCK],
		[-0.02, Px.merge(COCK, {"crouch": 7, "yaw": 2.7})],
		[0.045, Px.merge(OUT_, {"x": 1, "yaw": 1.3, "ghost": 1}), "snap"],
		[0.09, Px.merge(OUT_, {"ghost": 1}), "snap"],
		[0.14, OUT_, "snap"],
		[0.62, Px.merge(OUT_, {"crouch": 5, "lean": 5})],
		[1.12, Px.merge(REST_, {"two": true, "crouch": 4, "sa": -0.7, "fx": 14, "fy": -22})],
		[1.5, REST_],
	],
	"hits": [{"t": 0.1, "stop": 0.12, "shake": 0.18, "amp": 2, "push": 2.6, "straw": 18, "y": -12}],
	"dust": [{"t": 0.09, "x": 14, "n": 6, "dir": 1}, {"t": 0.09, "x": -10, "n": 5, "dir": -1}],
}


var C: Array
var Rg: Px.Rng
var st: Dictionary
var ps: Px.Particles
var lights: Px.Lights
var A: Dictionary
var end: Dictionary
var t := 0.0
var lastU := 0.0
var done := false


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 7)
	Rg = Px.Rng.new(o.seed)
	st = Lib.stone(o.stone)
	ps = Px.Particles.new({"rng": Rg, "ground": func(): return 0.0, "sparks": o.sparks})
	lights = Px.Lights.new()
	# from behind the left leg, round the front, out to the right; the far part is behind the fighter
	A = Lib.swing({"cx": 2.0, "cy": -12.0, "R": 50.0, "sy": 0.2, "k": 0.19, "rot": -0.04, "a0": PI + 0.55, "dir": -1.0, "span": PI + 0.35, "W": 19.0, "t0": 0.0, "sweep": 0.13, "hold": 0.05, "trail": 0.3, "ramp": C})
	end = Lib.slashEnd(A)


func update(dt: float) -> void:
	t += dt
	# the wind under the blade kicks dust up off the floor as it passes, rolling on the way it goes
	var U: float = A.span * Px.Ease.outExpo(Px.clamp(t / A.sweep))
	var u := lastU
	while u < U:
		var tr := Lib.travel(A, u)
		var near := sin(tr.a) >= 0.0
		var fy := -1.0 if near else -3.0
		var sp := Rg.range(30.0, 90.0)
		ps.spawn(P.SMOKE, tr.x, fy - Rg.range(0.0, 2.0), tr.dx * sp, -Rg.range(4.0, 16.0), Rg.range(0.7, 1.15), st.dust, Rg.range(3.0, 5.5), Rg.range(0.0, 0.05))
		if Rg.chance(0.6):
			ps.spawn(P.GRIT, tr.x, fy, tr.dx * Rg.range(40.0, 120.0) + Rg.range(-20.0, 20.0), -Rg.range(40.0, 130.0), Rg.range(0.6, 1.0), Rg.pick([st.light, st.body, st.shade]), 2.0 if Rg.chance(0.3) else 1.0)
		if Rg.chance(0.35):
			ps.spawn(P.MOTE, tr.x, tr.y, tr.dx * Rg.range(40.0, 100.0), tr.dy * 40.0 - Rg.range(5.0, 20.0), Rg.range(0.2, 0.4), C[4] if Rg.chance(0.5) else C[5], 0.6, 0.0, 0 if near else PF.BACK)
		u += 0.09
	lastU = U
	if not done and t >= A.sweep:
		done = true
		lights.add(end.x, end.y - 4.0, 50.0, C[3], 0.5, 0.35)
		for i in 8:
			var a: float = atan2(end.dy, end.dx) + Rg.range(-0.5, 0.3)
			var sp := Rg.range(120.0, 260.0)
			ps.spawn(P.SPARK, end.x, end.y, cos(a) * sp, sin(a) * sp - 40.0, Rg.range(0.12, 0.3))
		# the wake piles up and rolls on past the tip
		for i in 6:
			ps.spawn(P.SMOKE, end.x + Rg.range(-6.0, 4.0), -Rg.range(1.0, 4.0), Rg.range(30.0, 90.0), -Rg.range(4.0, 14.0), Rg.range(0.9, 1.25), st.dust, Rg.range(4.5, 7.0), Rg.range(0.0, 0.08), PF.BIG)
	ps.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	Lib.slash(p, A, t, -1.0)
	ps.draw(p, "back")


func draw(p: Px.Painter) -> void:
	Lib.slash(p, A, t, 1.0)
	var g: float = t - A.sweep * 0.6
	if g > 0.0 and g < 0.24:
		Px.sparkle(p, end.x, end.y, 9.0 * Px.Ease.outBack(minf(1.0, g / 0.05)) * (1.0 - g / 0.24), C[5], C[3], 0.55)
	# light rides the edge
	if t < A.sweep + 0.12:
		var xy := Lib.onSwing(A, A.R - 5.0, A.span * Px.Ease.outExpo(Px.clamp(t / A.sweep)))
		p.glow(xy[0], xy[1], 36.0, C[3], 0.45 * (1.0 - t / (A.sweep + 0.12)))
	ps.draw(p, "front")
	lights.draw(p)
