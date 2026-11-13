# The crescent, trace, glint and spark recipe is adapted from Sprite Fusion's open-source slash
# (https://www.spritefusion.com/pixel-art-vfx/slash), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/melee/dagger-flurry.js@03a5906d812a90c92533f98713497158a3deb008
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Dagger flurry",
	"desc": "A flurry of small quick crescents at every angle in front of the fighter, each with a flick of sparks, finished by one big cut that glints and bursts.",
	"tags": ["melee", "slash", "dagger", "combo", "flurry", "fast", "combat", "directional", "one-shot"],
	"size": [148, 104],
	"origin": [36, 86],
	"duration": 0.95,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {
		"palette": ["#1b1630", "#3a2f63", "#6150a3", "#9480d8", "#c7b8f5", "#efe9ff", "#ffffff"],
		"sparks": ["#ffffff", "#efe9ff", "#c7b8f5", "#9480d8"],
		"seed": 12,
	},
}

static var BASE := Px.merge(Px.READY, {"weapon": "dagger", "offWeapon": "dagger", "sa": -0.5, "sb": -0.9, "crouch": 4, "lean": 3, "ffx": 11, "fbx": -9, "fx": 12, "fy": -24, "bx": 9, "by": -24})
# a stab with one hand while the other comes back to the chest; the shoulders turn into each one
static func near(fx: Variant, fy: Variant, sa: Variant, o: Dictionary = {}) -> Dictionary:
	return Px.merge(Px.merge(BASE, {"fx": fx, "fy": fy, "sa": sa, "bx": 4, "by": -24, "sb": -1}), o)
static func far(bx: Variant, by: Variant, sb: Variant, o: Dictionary = {}) -> Dictionary:
	return Px.merge(Px.merge(BASE, {"bx": bx, "by": by, "sb": sb, "fx": 1, "fy": -23, "sa": -1}), o)
static var act := {
	"target": {"x": 60},
	"poses": [
		[-0.4, Px.merge(BASE, {"x": -4})],
		[-0.14, Px.merge(BASE, {"x": -6, "lean": -2, "crouch": 5, "fx": 2, "fy": -22, "sa": -1.2, "bx": 2, "by": -26, "sb": -1.5})],
		[-0.03, Px.merge(BASE, {"x": -6, "lean": -3, "crouch": 6, "fx": 1, "fy": -21, "sa": -1.2, "bx": 1, "by": -25, "sb": -1.5})],
		[0, near(20, -31, -0.5, {"x": 2, "ghost": 1}), "snap"],
		[0.055, far(21, -23, 0.5, {"x": 3}), "snap"],
		[0.11, near(18, -36, -1, {"x": 4}), "snap"],
		[0.165, far(22, -31, -0.6, {"x": 5}), "snap"],
		[0.22, near(20, -22, 0.2, {"x": 5}), "snap"],
		[0.275, far(21, -27, 0.05, {"x": 6}), "snap"],
		[0.33, Px.merge(BASE, {"x": 4, "lean": -3, "crouch": 5, "fx": -1, "fy": -33, "sa": -2.5, "bx": 2, "by": -23, "sb": -1.2}), "snap"],
		[0.37, Px.merge(BASE, {"x": 7, "lean": 2, "crouch": 4, "fx": 16, "fy": -34, "sa": -1, "bx": -7, "by": -24, "sb": -2.4, "ghost": 1}), "snap"],
		[0.43, Px.merge(BASE, {"x": 9, "lean": 6, "crouch": 6, "fx": 22, "fy": -23, "sa": 0.15, "bx": -9, "by": -24, "sb": -2.6, "ffx": 13, "fbx": -10, "toeB": true}), "snap"],
		[0.68, Px.merge(BASE, {"x": 9, "lean": 5, "crouch": 5, "fx": 21, "fy": -22, "sa": 0.2, "bx": -8, "by": -24, "sb": -2.6})],
		[1.05, Px.merge(BASE, {"x": -4})],
	],
	"hits": [
		{"t": 0.05, "stop": 0.015, "push": 0.5, "straw": 3, "flash": 0.02},
		{"t": 0.105, "stop": 0.015, "push": -0.3, "straw": 3, "flash": 0.02},
		{"t": 0.16, "stop": 0.015, "push": 0.5, "straw": 3, "flash": 0.02},
		{"t": 0.215, "stop": 0.015, "push": -0.3, "straw": 3, "flash": 0.02},
		{"t": 0.27, "stop": 0.015, "push": 0.5, "straw": 3, "flash": 0.02},
		{"t": 0.325, "stop": 0.015, "push": -0.3, "straw": 3, "flash": 0.02},
		{"t": 0.42, "stop": 0.12, "shake": 0.18, "amp": 2, "push": 2.6, "straw": 16},
	],
	"dust": [{"t": 0.43, "x": 20, "n": 7, "dir": 1}, {"t": 0, "x": -6, "n": 3, "dir": -1}],
}

const EVERY := 0.055
# small cuts: where, how they're turned, which way they go
const CUTS := [
	[21.0, -27.0, -0.5, 1.0], [33.0, -16.0, 0.9, -1.0], [26.0, -38.0, 2.4, 1.0], [37.0, -30.0, -1.8, -1.0], [19.0, -17.0, 0.2, 1.0], [30.0, -24.0, 1.4, -1.0],
]


var C: Array
var Rg: Px.Rng
var ps: Px.Particles
var lights: Px.Lights
var small: Array
var big: Dictionary
var all: Array
var ends: Array
var done: Array
var slivers: Array
var t := 0.0


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 7)
	Rg = Px.Rng.new(o.seed)
	ps = Px.Particles.new({"rng": Rg, "ground": func(): return 0.0, "sparks": o.sparks})
	lights = Px.Lights.new()
	small = []
	for i in CUTS.size():
		var x: float = CUTS[i][0]
		var y: float = CUTS[i][1]
		var rot: float = CUTS[i][2]
		var dir: float = CUTS[i][3]
		small.append(Lib.swing({"cx": x, "cy": y, "R": Rg.range(12.0, 15.0), "sy": Rg.range(0.55, 0.75), "rot": rot, "a0": Rg.range(-2.8, -2.2), "dir": dir, "span": Rg.range(2.3, 2.8), "W": Rg.range(5.2, 6.4), "t0": i * EVERY, "sweep": 0.035, "hold": 0.03, "trail": 0.13, "ramp": C}))
	# the finisher: one wide flat cut right across the front, left to right
	big = Lib.swing({"cx": 24.0, "cy": -26.0, "R": 30.0, "sy": 0.36, "k": 0.24, "rot": 0.12, "a0": 3.0, "dir": -1.0, "span": 2.85, "W": 11.0, "t0": small.size() * EVERY + 0.04, "sweep": 0.055, "hold": 0.06, "trail": 0.24, "ramp": C})
	all = small + [big]
	ends = all.map(func(s): return Lib.slashEnd(s))
	done = all.map(func(_s): return false)
	slivers = [-2.6, -1.5, -0.4, 0.7].map(func(a): return {"a": a + Rg.range(-0.2, 0.2), "r": Rg.range(4.0, 7.0), "v": Rg.range(70.0, 110.0), "arc": Rg.range(0.4, 0.7)})


func update(dt: float) -> void:
	t += dt
	for i in all.size():
		var s: Dictionary = all[i]
		if done[i] or t < s.t0 + s.sweep:
			continue
		done[i] = true
		var e: Dictionary = ends[i]
		var last := is_same(s, big)
		lights.add(e.x, e.y, 56.0 if last else 26.0, C[3], 0.6 if last else 0.4, 0.4 if last else 0.14)
		if last:
			lights.add(e.x, e.y, 16.0, WHITE, 0.7, 0.08)
		for k in (12 if last else 3):
			var a: float = atan2(e.dy, e.dx) + Rg.range(-0.5, 0.5)
			var sp := Rg.range(100.0, 340.0 if last else 220.0)
			ps.spawn(P.SPARK, e.x, e.y, cos(a) * sp, sin(a) * sp, Rg.range(0.1, 0.35 if last else 0.22))
		Lib.shavings(ps, Rg, s, 14 if last else 4, [C[4], C[5]])
		if last:
			for k in 5:
				ps.spawn(P.STAR, s.cx + Rg.range(-22.0, 22.0), s.cy + Rg.range(-14.0, 14.0), 0.0, -4.0, Rg.range(0.2, 0.45), C[5] if Rg.chance(0.5) else WHITE, Rg.range(1.0, 2.2), Rg.range(0.05, 0.25))
	ps.update(dt)
	lights.update(dt)


func draw(p: Px.Painter) -> void:
	for s: Dictionary in all:
		Lib.slash(p, s, t)
	for i in all.size():
		var s: Dictionary = all[i]
		var e: Dictionary = ends[i]
		var g: float = t - s.t0 - s.sweep * 0.6
		var last := is_same(s, big)
		var life := 0.24 if last else 0.12
		if g > 0.0 and g < life:
			Px.sparkle(p, e.x, e.y, (10.0 if last else 4.0) * Px.Ease.outBack(minf(1.0, g / 0.04)) * (1.0 - g / life), C[5], C[3], 0.6 if last else 0.35)
		# light rides each edge while it's moving
		var u: float = t - s.t0
		if u > 0.0 and u < s.sweep + 0.1:
			var h := Lib.slashEnd(Px.merge(s, {"span": s.span * Px.Ease.outExpo(Px.clamp(u / s.sweep))}))
			p.glow(h.x, h.y, 40.0 if last else 22.0, C[3], (0.5 if last else 0.35) * (1.0 - u / (s.sweep + 0.1)))
	# the finisher throws slivers off its end
	var q: float = t - big.t0 - big.sweep
	if q > 0.02 and q < 0.14:
		var k := (q - 0.02) / 0.12
		var e: Dictionary = ends[ends.size() - 1]
		for s: Dictionary in slivers:
			Lib.sliver(p, e.x, e.y, s.a + atan2(e.dy, e.dx), s.r + s.v * (q - 0.02), s.arc * (1.0 - 0.4 * k), C[6] if k < 0.4 else (C[5] if k < 0.7 else C[4]), 1.0 - k)
	ps.draw(p)
	lights.draw(p)
