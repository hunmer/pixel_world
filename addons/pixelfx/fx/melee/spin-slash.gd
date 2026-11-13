# The crescent shading, cooling ramp, dotted trace, glint and spark recipe is adapted from Sprite Fusion's
# open-source slash (https://www.spritefusion.com/pixel-art-vfx/slash), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/melee/spin-slash.js@59ccca78edd514d81c9f87bbc024d55e660b4a34
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const PF := Px.PF
const WHITE := Px.WHITE

static var meta := {
	"name": "Spin slash",
	"desc": "The blade whirls once round the waist on a tilted plane, behind the body and back in front; the closed ring flares white, dissolves into a dotted trace and throws sparks.",
	"tags": ["melee", "slash", "spin", "sword", "aoe", "combat", "one-shot"],
	"size": [208, 104],
	"origin": [104, 84],
	"duration": 0.8,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {
		"palette": ["#16224a", "#1f4a86", "#2a7fc0", "#48b8ec", "#9fe2ff", "#e2f7ff", "#ffffff"],
		"sparks": ["#fff3a6", "#ffe26b", "#ff8a2a", "#f2561d"],
		"radius": 46,
		"seed": 3,
	},
}

static var STANCE := Px.merge(Px.READY, {"weapon": "sword", "fx": 12, "fy": -21, "sa": -0.85})
# he really turns: forward, away from us, facing back, towards us, and round to the front
static var WOUND := Px.merge(STANCE, {"crouch": 6, "lean": -2, "yaw": 1.1, "fx": 13, "fy": -20, "sa": 0.3, "bx": 6, "by": -24, "ffx": 8, "fbx": -8})
static var WIDE := Px.merge(STANCE, {"crouch": 5, "lean": 3, "fx": 21, "fy": -21, "sa": 0.05, "bx": -9, "by": -23, "ffx": 11, "fbx": -11})
static var act := {
	"target": {"x": 60},
	"poses": [
		[-0.46, STANCE],
		[-0.2, WOUND],
		[-0.02, Px.merge(WOUND, {"crouch": 7, "yaw": 1.3})],
		[0, Px.merge(WIDE, {"sa": -0.1, "ghost": 1}), "snap"],
		[0.05, Px.merge(WIDE, {"yaw": -1.57, "ghost": 1}), "snap"],
		[0.09, Px.merge(WIDE, {"yaw": -3.14, "ghost": 1}), "snap"],
		[0.13, Px.merge(WIDE, {"yaw": -4.71, "ghost": 1}), "snap"],
		[0.17, WIDE, "snap"],
		[0.56, Px.merge(WIDE, {"crouch": 4, "lean": 2})],
		[0.92, STANCE],
	],
	"hits": [{"t": 0.17, "stop": 0.12, "shake": 0.16, "amp": 2, "push": 2.4, "straw": 16}],
	"dust": [{"t": 0, "x": 0, "n": 6}, {"t": 0.17, "x": 12, "n": 6, "dir": 1}],
}

const SW := 0.17  # the edge goes once round
const FLARE := 0.3  # the closed ring flares and dissolves
static func turn(t_: float) -> float:
	return 1.0 - pow(1.0 - Px.clamp(t_ / SW), 1.6)  # fraction of the turn the edge has made
static func passedAt(f: float) -> float:
	return SW * (1.0 - pow(1.0 - Px.clamp(f), 1.0 / 1.6))  # when the edge passed fraction f


var C: Array
var n: int
var Rg: Px.Rng
var R0: float
var ps: Px.Particles
var lights: Px.Lights
var A: Dictionary
var E: Dictionary
var W := 16.0
var WE := 5.0
var DIM: Array
var t := 0.0
var closed := false
var lastU := 0.0


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 7)
	n = C.size()
	Rg = Px.Rng.new(o.seed)
	R0 = o.radius
	ps = Px.Particles.new({"rng": Rg, "ground": func(): return 0.0, "sparks": o.sparks})
	lights = Px.Lights.new()
	# the spin starts front-right, goes up the right side, behind the body, down the left and back across the front
	A = Lib.swing({"cx": 0.0, "cy": -17.0, "R": R0, "sy": 0.27, "rot": -0.1, "a0": 0.5, "dir": -1.0, "k": 0.15})
	# a thinner echo just inside, a beat behind
	E = Px.merge(A, {"R": R0 * 0.8, "k": 0.1})
	# the far half sits deeper in the ramp
	DIM = [C[0], C[0], C[1], C[2], C[3], C[4], C[5]]


# the smear: thickest just behind the edge, thinning and cooling where the edge passed longer ago
func body(p: Px.Painter, s: Dictionary, w0: float, lag: float, half: float, rim: bool) -> void:
	var U := TAU * turn(t - lag)
	var ramp: Array = DIM if half < 0.0 else C
	if U < 0.02 or t - lag > SW + 0.02:
		return
	var t_ := t
	var n_ := n
	Lib.smear(p, s, 0.0, U, w0, func(u, r, out):
		var age: float = t_ - lag - passedAt(u / TAU)
		var lead: float = U - u
		var w: float = w0 * pow(Px.clamp(lead / 0.85), 0.5) * (0.3 + 0.7 * exp(-age / 0.075)) * pow(Px.clamp(u / 1.3), 0.7)
		if w < 0.45:
			return
		var q: float = (s.R - r) / w
		if q < 0.0 or q > 1.0:
			return
		# white rim while fresh, then darker steps inward, with age and towards the tail
		var ci := 0.0 if (rim and q < 0.26 and age < 0.06) else Px.round(q * (n_ - 1) * 0.7 + age * 13.0 + (0.4 if rim else 1.4))
		out.c = ramp[n_ - 1 - int(Px.clamp(ci, 0.0, n_ - 1))]
		out.a = minf(1.0, u / 1.1 + 0.2), half)


func ring(p: Px.Painter, half: float) -> void:
	# the swept smear and its echo
	body(p, E, WE, 0.025, half, false)
	body(p, A, W, 0.0, half, true)
	var t_ := t
	if t < SW + 0.04:
		Lib.glowAlong(p, A, A.R - 5.0, 0.0, TAU * turn(t), 14.0, C[3], func(u): return (0.2 if half < 0.0 else 0.3) * exp(-(t_ - passedAt(u / TAU)) / 0.08), half)
	if t < SW:
		return
	# closed: the ring flares white, swells a little, thins, cools and breaks into dots
	var f := (t - SW) / FLARE
	var ramp: Array = DIM if half < 0.0 else C
	if f < 1.0:
		var R: float = A.R + 6.0 * Px.Ease.outCubic(f)
		var th := 9.0 if f < 0.13 else maxf(1.0, 6.0 * pow(1.0 - f, 1.5) + 0.5)
		var S := Px.merge(A, {"R": R})
		var step := 6 if f < 0.13 else (5 if f < 0.3 else (4 if f < 0.55 else 3))
		Lib.smear(p, S, 0.0, TAU, th, func(_u, r, out):
			var q: float = (R - r) / th
			if q < 0.0 or q > 1.0:
				return
			out.c = (WHITE if q < 0.6 else ramp[5]) if f < 0.13 else (ramp[step] if q < 0.45 else ramp[step - 1])
			out.a = 1.0 if f < 0.4 else 1.3 - f, half)
		Lib.glowAlong(p, S, R - 2.0, 0.0, TAU, 14.0, C[4], 0.32 * (1.0 - f) * (1.0 - f), half)
	# a dotted trace of the blade's path lingers where the ring was, fading
	var k := 1.0 - Px.clamp((t - SW - 0.06) / 0.4)
	if k > 0.0:
		Lib.trace(p, A, A.R - 0.5, 0.0, TAU, ramp[4], func(u): return Px.clamp(k * 1.5 - Px.rand(floorf(u * 30.0), 5) * 0.8) * 0.95, half)


func update(dt: float) -> void:
	t += dt
	var U := TAU * turn(t)
	# shavings peel off the edge as it goes round, flung along its path
	if t < SW:
		var u := lastU
		while u < U:
			var tr := Lib.travel(A, u)
			var ox: float = tr.x - A.cx
			var oy: float = tr.y - A.cy
			var l := Px.hypot(ox, oy)
			if not l:
				l = 1.0
			var sp := Rg.range(40.0, 120.0)
			ps.spawn(P.MOTE, tr.x, tr.y, tr.dx * sp + (ox / l) * sp * 0.35, tr.dy * sp * 0.6 - Rg.range(5.0, 30.0), Rg.range(0.22, 0.45), C[4 + Rg.int_(0, 1)], 0.55, 0.0, PF.BACK if sin(tr.a) < 0.0 else 0)
			u += 0.3
		lastU = U
	if not closed and t >= SW:
		closed = true
		lights.add(A.cx, A.cy + 4.0, 90.0, C[3], 0.4, 0.4)
		# sparks off the edge where it closes, and all round the ring along its turn
		var end := Lib.travel(A, TAU)
		for i in 9:
			var a: float = atan2(end.dy, end.dx) + Rg.range(-0.45, 0.35)
			var sp := Rg.range(160.0, 360.0)
			ps.spawn(P.SPARK, end.x, end.y, cos(a) * sp, sin(a) * sp - Rg.range(20.0, 70.0), Rg.range(0.14, 0.36))
		for i in 16:
			var u := Rg.range(0.0, TAU)
			var tr := Lib.travel(A, u)
			var sp := Rg.range(110.0, 260.0)
			ps.spawn(P.SPARK, tr.x, tr.y, tr.dx * sp, tr.dy * sp - Rg.range(20.0, 80.0), Rg.range(0.12, 0.32), 0, 1.0, 0.0, PF.BACK if sin(tr.a) < 0.0 else 0)
		# and twinkles left hanging on the ring
		for i in 6:
			var u := Rg.range(0.0, TAU)
			var xy := Lib.onSwing(A, A.R + Rg.range(-1.0, 3.0), u)
			ps.spawn(P.STAR, xy[0], xy[1], 0.0, -Rg.range(2.0, 8.0), Rg.range(0.25, 0.5), C[5] if Rg.chance(0.5) else WHITE, Rg.range(1.2, 2.6), Rg.range(0.04, 0.16), PF.BACK if sin(A.a0 + A.dir * u) < 0.0 else 0)
	ps.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	ring(p, -1.0)
	ps.draw(p, "back")


func draw(p: Px.Painter) -> void:
	ring(p, 1.0)
	# the blade catches the light as it sets off, and glints again where the ring closes
	if t < 0.06:
		var xy := Lib.onSwing(A, A.R - 3.0, 0.0)
		Px.sparkle(p, xy[0], xy[1], 7.0 * (1.0 - t / 0.06), C[5], C[3], 0.5)
	var g := t - SW * 0.85
	var tip := Lib.onSwing(A, A.R - 3.0, TAU)
	if g > 0.0 and g < 0.24:
		Px.sparkle(p, tip[0], tip[1], 10.0 * Px.Ease.outBack(minf(1.0, g / 0.05)) * (1.0 - g / 0.24), C[5], C[3], 0.6)
	# light rides the edge
	if t < SW + 0.05:
		var U := TAU * turn(t)
		var xy := Lib.onSwing(A, A.R - 5.0, U)
		var far := sin(A.a0 + A.dir * U) < 0.0
		p.glow(xy[0], xy[1], 26.0 if far else 38.0, C[3], (0.3 if far else 0.5) * (1.0 - Px.smooth(SW - 0.04, SW + 0.05, t)))
	ps.draw(p, "front")
	lights.draw(p)
