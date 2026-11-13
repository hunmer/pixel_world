# The crescent, echo, trail, glint and spark recipe is adapted from Sprite Fusion's open-source slash
# (https://www.spritefusion.com/pixel-art-vfx/slash), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/melee/sword-slash.js@8e9258f474a2461b85a2992d4d58c354f27054da
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const P := Px.P

static var meta := {
	"name": "Sword slash",
	"desc": "A tilted crescent whips round in two frames, cools from white to deep blue as it trails off, glints at the tip and throws sparks.",
	"tags": ["melee", "slash", "sword", "combat", "directional", "one-shot"],
	"size": [136, 104],
	"origin": [44, 92],
	"duration": 0.75,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {
		"palette": ["#212f6b", "#2c58aa", "#3a8bd8", "#62c8f4", "#b8c9e8", "#e8f1ff", "#ffffff"],
		"sparks": ["#fff3a6", "#ffe26b", "#ff8a2a", "#f2561d"],
		"radius": 42,
		"seed": 2,
	},
}

static var GUARD := Px.merge(Px.READY, {"weapon": "sword", "fx": 12, "fy": -21, "sa": -0.85})
# the blade goes back past his head, then lags behind the hand on the way through, so the wrist breaks and it whips
static var WIND := Px.merge(GUARD, {"x": -8, "crouch": 4, "lean": -4, "fx": -7, "fy": -35, "sa": -2.65, "bx": 9, "by": -25, "armsFront": true, "ffx": 9, "fbx": -8})
static var CUT := Px.merge(GUARD, {"x": 0, "crouch": 2, "lean": 3, "fx": 16, "fy": -37, "sa": -1.45, "bx": -7, "by": -24, "ffx": 11, "fbx": -10, "ghost": 1})
static var DOWN := Px.merge(GUARD, {"x": 2, "crouch": 5, "lean": 5, "fx": 20, "fy": -21, "sa": 0.62, "bx": -9, "by": -24, "ffx": 13, "fbx": -10, "toeB": true})
static var act := {
	"target": {"x": 58},
	"poses": [
		[-0.55, Px.merge(GUARD, {"x": -8})],
		[-0.3, WIND],
		[-0.08, Px.merge(WIND, {"crouch": 5, "lean": -5})],
		[0, CUT, "snap"],
		[0.06, DOWN, "snap"],
		[0.3, Px.merge(DOWN, {"x": 3, "crouch": 6})],
		[0.58, Px.merge(GUARD, {"x": 1, "crouch": 3, "fx": 15, "fy": -21, "sa": 0.1, "bx": -5, "by": -21, "ffx": 9, "fbx": -7})],
		[0.86, Px.merge(GUARD, {"x": -8})],
	],
	"hits": [{"t": 0.06, "stop": 0.14, "shake": 0.18, "amp": 2, "push": 2.8, "straw": 18}],
	"dust": [{"t": 0.06, "x": 16, "n": 7, "dir": 1}, {"t": 0.06, "x": -11, "n": 4, "dir": -1}],
}


# a point on the slash's tilted ellipse
static func onArc(s: Dictionary, r: float, a: float) -> Array:
	var lx := cos(a) * r
	var ly: float = sin(a) * r * s.sy
	var c := cos(s.rot)
	var n := sin(s.rot)
	return [s.cx + lx * c - ly * n, s.cy + lx * n + ly * c]


# the smear: thickest just behind the leading edge, tapering to a hair at the tail, white on the outer rim,
# cooling down the ramp with age and towards the tail; the tail dissolves through the dither
static func crescent(p: Px.Painter, s: Dictionary, ta: float, L: float, W: float, age: float) -> void:
	if absf(L) < 0.02 or W < 0.3:
		return
	var R: Array = s.ramp
	var n := R.size()
	var dir := Px.sign(L)
	var span := absf(L)
	var c := cos(s.rot)
	var sn := sin(s.rot)
	var B: float = s.R + 2.0
	p.shade(s.cx - B, s.cy - B, s.cx + B, s.cy + B, func(x, y, out):
		var dx: float = x - s.cx
		var dy: float = y - s.cy
		var lx := dx * c + dy * sn
		var ly: float = (-dx * sn + dy * c) / s.sy
		var r := Px.hypot(lx, ly)
		if r > s.R + 0.5 or r < s.R - W - 1.0:
			return
		var u := fmod(dir * (atan2(ly, lx) - ta), TAU)
		if u < 0.0:
			u += TAU
		if u > span:
			return
		var v := u / span
		var w := W * pow(sin(PI * pow(v, 2.2)), 0.6)
		if w < 0.35:
			return
		var q: float = (s.R - r) / w
		if q < 0.0 or q > 1.0:
			return
		# brightest step at the rim while it's young, then darker steps inward, with age and towards the tail
		var ci := 0.0 if (q < 0.22 and age < 0.5) else Px.round(q * (n - 1) * 0.75 + age * 2.4 - v * 0.8 + 0.4)
		out.c = R[n - 1 - int(Px.clamp(ci, 0.0, n - 1))]
		out.a = minf(1.0, v / 0.4))
	var u := 0.0
	while u <= span:
		var xy := onArc(s, s.R - W * 0.4, ta + dir * u)
		p.glow(xy[0], xy[1], 5.0 + W, R[n - 3], 0.22 * (1.0 - age) * (u / span))
		u += 0.3


static func drawSlash(p: Px.Painter, s: Dictionary, t: float) -> void:
	var u: float = t - s.t0
	if u < 0.0:
		return
	var span: float = s.a1 - s.a0
	var head := Px.Ease.outExpo(Px.clamp(u / s.sweep))
	var tail := Px.smooth(s.sweep + s.hold, s.sweep + s.hold + s.trail, u)
	var age := Px.clamp(u / (s.sweep + s.hold + s.trail))
	if tail < 1.0:
		crescent(p, s, s.a0 + span * tail, span * (head - tail), s.W * (1.0 - tail * 0.55), age)
	# a dotted trace of the blade's path lingers where the smear has already gone
	var th := 0.7 * (1.0 - Px.clamp((u - s.sweep - s.hold) / (s.trail + 0.2)))
	if tail > 0.02 and th > 0.0:
		var k := 0.0
		while k <= tail:
			var xy := onArc(s, s.R - 0.5, s.a0 + span * k)
			p.dot(xy[0], xy[1], s.ramp[1], th * (0.4 + 0.6 * k))
			k += 0.6 / (absf(span) * s.R)


static func tipOf(s: Dictionary) -> Dictionary:
	var a := onArc(s, s.R - s.W * 0.3, s.a1)
	var b := onArc(s, s.R - s.W * 0.3, s.a1 + Px.sign(s.a1 - s.a0) * 0.05)
	var x: float = a[0]
	var y: float = a[1]
	var x2: float = b[0]
	var y2: float = b[1]
	var l := Px.hypot(x2 - x, y2 - y)
	if not l:
		l = 1.0
	return {"x": x, "y": y, "dx": (x2 - x) / l, "dy": (y2 - y) / l}


var C: Array
var Rg: Px.Rng
var ps: Px.Particles
var a0 := -2.55
var a1 := 0.95
var A: Dictionary
var E: Dictionary
var tip: Dictionary
var t := 0.0
var landed := false


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 7)
	Rg = Px.Rng.new(o.seed)
	ps = Px.Particles.new({"rng": Rg, "ground": func(): return 0.0, "sparks": o.sparks})
	var R0: float = o.radius
	# the main smear, and a thinner echo just inside it a beat behind
	A = {"cx": 6.0, "cy": -26.0, "R": R0, "sy": 0.6, "rot": -0.38, "a0": a0, "a1": a1, "W": 12.0, "t0": 0.0, "sweep": 0.06, "hold": 0.06, "trail": 0.24, "ramp": C}
	E = Px.merge(A, {"R": R0 * (33.0 / 42.0), "W": R0 * (4.5 / 42.0), "a0": a0 + (a1 - a0) * 0.1, "a1": a1 - (a1 - a0) * (0.15 / 3.5), "t0": 0.017, "hold": 0.03, "trail": 0.2, "ramp": C.slice(0, 6)})
	tip = tipOf(A)


func update(dt: float) -> void:
	t += dt
	if not landed and t >= A.sweep:
		landed = true
		# sparks off the edge where it stops, and bright shavings flung off the arc
		for i in 10:
			var a: float = atan2(tip.dy, tip.dx) + Rg.range(-0.5, 0.5)
			var sp := Rg.range(150.0, 400.0)
			ps.spawn(P.SPARK, tip.x, tip.y, cos(a) * sp, sin(a) * sp, Rg.range(0.12, 0.35))
		for i in 16:
			var a := a0 + (a1 - a0) * Rg.range(0.3, 1.0)
			var xy := onArc(A, A.R, a)
			var ox: float = xy[0] - A.cx
			var oy: float = xy[1] - A.cy
			var l := Px.hypot(ox, oy)
			if not l:
				l = 1.0
			var sp := Rg.range(30.0, 100.0)
			ps.spawn(P.MOTE, xy[0], xy[1], (ox / l) * sp, (oy / l) * sp - 10.0, Rg.range(0.25, 0.55), C[4 + Rg.int_(0, 1)], 0.6)
	ps.update(dt)


func draw(p: Px.Painter) -> void:
	drawSlash(p, E, t)
	drawSlash(p, A, t)
	# the tip glints as the edge arrives
	var g: float = t - A.sweep * 0.6
	if g > 0.0 and g < 0.22:
		Px.sparkle(p, tip.x, tip.y, 9.0 * Px.Ease.outBack(minf(1.0, g / 0.05)) * (1.0 - g / 0.22), C[5], C[3], 0.6)
	# light rides the head of the swing
	if t < 0.3:
		var xy := onArc(A, A.R - 4.0, A.a0 + (A.a1 - A.a0) * Px.Ease.outExpo(Px.clamp(t / A.sweep)))
		p.glow(xy[0], xy[1], 40.0, C[3], 0.5 * (1.0 - t / 0.3))
	ps.draw(p)
