# The crescent, trace, glint and spark recipe is adapted from Sprite Fusion's open-source slash
# (https://www.spritefusion.com/pixel-art-vfx/slash), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/melee/double-slash.js@2aa6e6e0918f3e0f3083f611be9a4c5b2bd91962
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Double slash",
	"desc": "A down cut, then an up cut that crosses it: the moment the X closes both strokes flash white, the crossing bursts with light and sparks, and a dotted X lingers.",
	"tags": ["melee", "slash", "combo", "sword", "cross", "combat", "directional", "one-shot"],
	"size": [164, 108],
	"origin": [44, 92],
	"duration": 0.8,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {
		"palette": ["#2a0a22", "#5e1238", "#a01f4e", "#e0386a", "#ff86a6", "#ffd2dd", "#ffffff"],
		"sparks": ["#fff3a6", "#ffe26b", "#ff8a2a", "#f2561d"],
		"seed": 6,
	},
}

static var STANCE := Px.merge(Px.READY, {"weapon": "sword", "fx": 12, "fy": -21, "sa": -0.85})
static var HIGH := Px.merge(STANCE, {"x": -7, "crouch": 4, "lean": -4, "fx": -7, "fy": -35, "sa": -2.65, "bx": 9, "by": -25, "armsFront": true, "ffx": 9, "fbx": -8})
static var LOW := Px.merge(STANCE, {"x": 3, "crouch": 6, "lean": 6, "fx": 22, "fy": -20, "sa": 0.62, "bx": -8, "by": -24, "ffx": 13, "fbx": -10, "toeB": true})
static var act := {
	"target": {"x": 62},
	"poses": [
		[-0.42, Px.merge(STANCE, {"x": -7})],
		[-0.18, HIGH],
		[-0.04, Px.merge(HIGH, {"crouch": 5})],
		[0, Px.merge(STANCE, {"x": 0, "crouch": 2, "lean": 3, "fx": 16, "fy": -37, "sa": -1.45, "bx": -7, "by": -24, "ffx": 11, "fbx": -9, "ghost": 1}), "snap"],
		[0.06, LOW, "snap"],
		[0.14, Px.merge(LOW, {"x": 4, "crouch": 6, "lean": 5, "fx": 20, "fy": -17, "sa": 0.85, "ghost": 1})],
		[0.17, Px.merge(LOW, {"x": 5, "crouch": 3, "lean": 5, "fx": 22, "fy": -28, "sa": 0.1, "by": -18, "toeB": true, "ghost": 1}), "snap"],
		[0.21, Px.merge(LOW, {"x": 6, "crouch": 1, "lean": 6, "fx": 19, "fy": -37, "sa": -0.95, "by": -18, "ffx": 13, "fby": -6}), "snap"],
		[0.5, Px.merge(LOW, {"x": 6, "crouch": 3, "lean": 3, "fx": 18, "fy": -36, "sa": -1.05, "by": -19, "ffx": 12})],
		[0.92, Px.merge(STANCE, {"x": -7})],
	],
	"hits": [
		{"t": 0.06, "stop": 0.05, "shake": 0.08, "amp": 1, "push": 1.4, "straw": 8},
		{"t": 0.16, "stop": 0.14, "shake": 0.2, "amp": 2, "push": 2.8, "straw": 18, "y": -28},
	],
	"dust": [{"t": 0.06, "x": 16, "n": 5, "dir": 1}, {"t": 0.17, "x": -8, "n": 4, "dir": -1}],
}

const UP := 0.14  # the second cut starts
const R0 := 62.0

static func cut(x: float, y: float, th: float, dir: float, span: float, extra: Dictionary) -> Dictionary:
	return Lib.through(x, y, th, dir, R0, span, 0.55, extra)


var C: Array
var Rg: Px.Rng
var ps: Px.Particles
var lights: Px.Lights
var X := 34.0
var Y := -23.0
var down: Dictionary
var up: Dictionary
var ends: Array
var slivers: Array
var CLOSE := UP + 0.012
var t := 0.0
var cut1 := false
var cut2 := false
var closed := false


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 7)
	Rg = Px.Rng.new(o.seed)
	ps = Px.Particles.new({"rng": Rg, "ground": func(): return 0.0, "sparks": o.sparks})
	lights = Px.Lights.new()
	down = cut(X, Y, 0.72, 1.0, 0.84, {"W": 10.0, "t0": 0.0, "sweep": 0.06, "hold": 0.07, "trail": 0.24, "ramp": C, "lens": true})
	up = cut(X, Y, -0.66, -1.0, 0.84, {"W": 11.0, "t0": UP, "sweep": 0.06, "hold": 0.06, "trail": 0.26, "ramp": C, "lens": true})
	ends = [Lib.slashEnd(down), Lib.slashEnd(up)]
	slivers = [-2.4, -1.1, 0.2, 1.6].map(func(a): return {"a": a + Rg.range(-0.2, 0.2), "r": Rg.range(5.0, 8.0), "v": Rg.range(70.0, 120.0), "arc": Rg.range(0.4, 0.7)})


func update(dt: float) -> void:
	t += dt
	if not cut1 and t >= down.sweep:
		cut1 = true
		Lib.shavings(ps, Rg, down, 10, [C[4], C[5]])
		for i in 6:
			var a: float = atan2(ends[0].dy, ends[0].dx) + Rg.range(-0.5, 0.5)
			var sp := Rg.range(120.0, 300.0)
			ps.spawn(P.SPARK, ends[0].x, ends[0].y, cos(a) * sp, sin(a) * sp, Rg.range(0.12, 0.3))
	if not closed and t >= CLOSE:
		closed = true
		lights.add(X, Y, 56.0, C[3], 0.45, 0.4)
		lights.add(X, Y, 18.0, WHITE, 0.6, 0.08)
		for i in 18:
			var a := Rg.range(-PI, PI) * 0.8
			var sp := Rg.range(140.0, 360.0)
			ps.spawn(P.SPARK, X, Y, cos(a) * sp, sin(a) * sp - 40.0, Rg.range(0.14, 0.4))
		for i in 5:
			ps.spawn(P.STAR, X + Rg.range(-14.0, 14.0), Y + Rg.range(-12.0, 12.0), 0.0, -4.0, Rg.range(0.2, 0.4), C[5] if Rg.chance(0.5) else WHITE, Rg.range(1.0, 2.2), Rg.range(0.05, 0.2))
	if not cut2 and t >= UP + up.sweep:
		cut2 = true
		Lib.shavings(ps, Rg, up, 12, [C[4], C[5]])
	ps.update(dt)
	lights.update(dt)


func draw(p: Px.Painter) -> void:
	# both strokes flash white for two frames when the X closes
	var flash := 1.0 if (t >= CLOSE and t < CLOSE + 0.07) else 0.0
	up.hot = flash
	down.hot = up.hot
	Lib.slash(p, down, t)
	Lib.slash(p, up, t)
	# glints at the ends of the strokes
	for se: Array in [[down, ends[0]], [up, ends[1]]]:
		var s: Dictionary = se[0]
		var e: Dictionary = se[1]
		var g: float = t - s.t0 - s.sweep * 0.6
		if g > 0.0 and g < 0.2:
			Px.sparkle(p, e.x, e.y, 7.0 * Px.Ease.outBack(minf(1.0, g / 0.05)) * (1.0 - g / 0.2), C[5], C[3], 0.5)
	# the crossing: a flare, slivers flying off it, light
	var q := t - CLOSE
	if q >= 0.0 and q < 0.26:
		var k := q / 0.26
		Px.flare(p, X, Y, 22.0 * pow(1.0 - k, 1.4), 1.0 - k, C)
		p.glow(X, Y, 34.0, C[4], 0.35 * (1.0 - k))
	if q >= 0.03 and q < 0.15:
		var k := (q - 0.03) / 0.12
		for s: Dictionary in slivers:
			Lib.sliver(p, X, Y, s.a, s.r + s.v * (q - 0.03), s.arc * (1.0 - 0.4 * k), C[6] if k < 0.4 else (C[5] if k < 0.7 else C[4]), 1.0 - k)
	# light rides each edge as it goes
	for s: Dictionary in [down, up]:
		var u: float = t - s.t0
		if u <= 0.0 or u >= 0.25:
			continue
		var e := Lib.slashEnd(Px.merge(s, {"span": s.span * Px.Ease.outExpo(Px.clamp(u / s.sweep))}))
		p.glow(e.x, e.y, 40.0, C[3], 0.5 * (1.0 - u / 0.25))
	ps.draw(p)
	lights.draw(p)
