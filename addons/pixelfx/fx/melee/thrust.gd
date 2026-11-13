# The speed lines are adapted from Sprite Fusion's open-source dash and the ray star from his sparkle
# (https://www.spritefusion.com/pixel-art-vfx), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/melee/thrust.js@9714b58585b79ece12a4be3cb170e2d31f435d63
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Thrust",
	"desc": "A piercing stab: a bundle of streaks shoots out from the hand to a point, a long four-point star flares at the tip with a pierce ring, sparks and speed lines.",
	"tags": ["melee", "thrust", "stab", "spear", "rapier", "pierce", "combat", "directional", "one-shot"],
	"size": [196, 76],
	"origin": [34, 62],
	"duration": 0.75,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {
		"palette": ["#2a1608", "#6b3c10", "#b8701a", "#f0b42e", "#ffe27a", "#fff6cf", "#ffffff"],
		"sparks": ["#fff3a6", "#ffe26b", "#ff8a2a", "#f2561d"],
		"reach": 66,
		"seed": 4,
	},
}

static var STANCE := Px.merge(Px.READY, {"weapon": "sword", "x": -14, "fx": 12, "fy": -21, "sa": -0.3})
# the hand comes back to the hip with the point forward, then the whole arm goes out along the blade
static var BACK := Px.merge(STANCE, {"crouch": 5, "lean": -3, "fx": -3, "fy": -19, "sa": -0.05, "bx": 8, "by": -30, "armsFront": true, "ffx": 10, "fbx": -8})
static var LUNGE := Px.merge(STANCE, {"crouch": 6, "lean": 6, "fx": 23, "fy": -20, "sa": 0, "bx": -8, "by": -24, "ffx": 15, "fbx": -11, "toeB": true})
static var act := {
	"target": {"x": 80},
	"poses": [
		[-0.46, STANCE],
		[-0.24, BACK],
		[-0.05, Px.merge(BACK, {"crouch": 6, "fx": -5})],
		[0, Px.merge(LUNGE, {"ghost": 1}), "snap"],
		[0.07, LUNGE, "snap"],
		[0.3, Px.merge(LUNGE, {"crouch": 5, "lean": 5})],
		[0.7, STANCE],
	],
	"hits": [{"t": 0.07, "stop": 0.12, "shake": 0.14, "amp": 2, "push": 2.8, "straw": 16, "y": -26}],
	"dust": [{"t": 0, "x": -24, "n": 6, "dir": -1}, {"t": 0.07, "x": 1, "n": 6, "dir": 1}],
}

const OUT := 0.07  # the point arrives
const HOLD := 0.06
const PULL := 0.2


# a long four-point star: the forward and back arms long, up and down shorter, thick at the heart
static func longStar(p: Px.Painter, x: float, y: float, L: float, k: float, C: Array) -> void:
	if L < 1.0:
		return
	var arms := [[1.0, 0.0, L], [-1.0, 0.0, L * 0.7], [0.0, -1.0, L * 0.42], [0.0, 1.0, L * 0.42]]
	for arm: Array in arms:
		var dx: float = arm[0]
		var dy: float = arm[1]
		var len_: float = arm[2]
		var d := 1.0
		while d <= len_:
			var u := d / len_
			var c: int = WHITE if u < 0.3 else (C[5] if u < 0.65 else C[4])
			p.dot(x + dx * d, y + dy * d, c, 1.0 if u < 0.7 else 1.0 - (u - 0.7) / 0.35)
			if u < 0.25 and len_ > 6.0:
				p.dot(x + dx * d - dy, y + dy * d + dx, C[5])
				p.dot(x + dx * d + dy, y + dy * d - dx, C[5])
			d += 0.5
	for dxy: Array in [[1.0, 1.0], [1.0, -1.0], [-1.0, 1.0], [-1.0, -1.0]]:
		var dx: float = dxy[0]
		var dy: float = dxy[1]
		var d := 1
		while d <= minf(3.0, L * 0.14):
			p.px(x + dx * d, y + dy * d, C[5] if d < 2 else C[4])
			d += 1
	p.px(x, y, WHITE)
	p.glow(x, y, 6.0 + L * 1.3, C[4], 0.35 * k)
	p.glow(x, y, 3.0 + L * 0.4, WHITE, 0.3 * k)


var C: Array
var Rg: Px.Rng
var ps: Px.Particles
var lights: Px.Lights
var reach: float
var HX := 9.0
var HY := -20.0
var TX: float
var TY: float
var streaks: Array
var lines: Array = []
var t := 0.0
var struck := false


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 7)
	Rg = Px.Rng.new(o.seed)
	ps = Px.Particles.new({"rng": Rg, "ground": func(): return 0.0, "sparks": o.sparks})
	lights = Px.Lights.new()
	reach = o.reach
	TX = HX + reach
	TY = HY
	# the bundle: streaks fanned at the hand, meeting at the point; the middle one hottest
	streaks = [-7.0, -4.0, -2.0, 0.0, 2.0, 4.0, 7.0].map(func(off): return {"off": off, "x0": HX + 1.0 + Rg.range(0.0, 5.0) + absf(off) * 0.6, "t0": Rg.range(0.0, 0.02) + absf(off) * 0.003, "w": 2.0 if off == 0.0 else 1.0, "hot": off == 0.0, "len": Rg.range(0.75, 1.0)})


func update(dt: float) -> void:
	t += dt
	# speed lines race forward beside the bundle while it shoots out and just after
	if t < OUT + 0.08 and Rg.chance(0.5):
		var s := Rg.sign()
		lines.append({"x": HX + Rg.range(0.0, reach * 0.6), "y": HY + s * Rg.range(7.0, 17.0), "l": Rg.range(18.0, 42.0), "v": Rg.range(200.0, 340.0), "t": t})
	var i := lines.size() - 1
	while i >= 0:
		if t - lines[i].t > 0.24:
			lines.remove_at(i)
		i -= 1
	for l: Dictionary in lines:
		l.x += l.v * dt
	if not struck and t >= OUT:
		struck = true
		lights.add(TX, TY, 44.0, C[4], 0.45, 0.3)
		lights.add(TX, TY, 14.0, WHITE, 0.6, 0.06)
		for j in 12:
			var a := Rg.range(-0.55, 0.45)
			var sp := Rg.range(150.0, 330.0)
			ps.spawn(P.SPARK, TX, TY, cos(a) * sp, sin(a) * sp - 30.0, Rg.range(0.12, 0.35))
		for j in 10:
			var a := Rg.range(-0.9, 0.9) + (PI if Rg.chance(0.3) else 0.0)
			var sp := Rg.range(40.0, 120.0)
			ps.spawn(P.MOTE, TX + Rg.range(-6.0, 2.0), TY + Rg.range(-2.0, 2.0), cos(a) * sp, sin(a) * sp, Rg.range(0.25, 0.5), C[5] if Rg.chance(0.5) else C[4], 0.6)
		for j in 4:
			ps.spawn(P.STAR, TX + Rg.range(-10.0, 8.0), TY + Rg.range(-9.0, 9.0), 0.0, -3.0, Rg.range(0.2, 0.4), C[5] if Rg.chance(0.5) else WHITE, Rg.range(1.0, 2.0), Rg.range(0.06, 0.2))
	ps.update(dt)
	lights.update(dt)


func draw(p: Px.Painter) -> void:
	# the point catches the light before it goes
	if t < 0.05:
		Px.sparkle(p, HX + 2.0, HY, 5.0 * (1.0 - t / 0.05) + 1.0, C[5], C[3], 0.4)
	# speed lines: dotted, white at the head, dimming back along their length
	for l: Dictionary in lines:
		var k: float = (t - l.t) / 0.24
		var d := 0
		while d < l.l * (1.0 - k * 0.6):
			p.dot(l.x - d, l.y, WHITE if d < 3 else (C[5] if d < l.l * 0.4 else C[3]), (1.0 - d / l.l) * (1.0 - k))
			d += 1
	# the bundle: each streak shoots from the hand to the point, holds, then is drawn in to the point
	var pull := Px.smooth(OUT + HOLD, OUT + HOLD + PULL, t)
	for s: Dictionary in streaks:
		var u := Px.clamp((t - s.t0) / OUT)
		var head := Px.Ease.outExpo(u)
		if u <= 0.0 or pull >= 1.0:
			continue
		# the outer streaks stop short of the point and trail a little behind, so each reads on its own
		var y0: float = HY + s.off
		var end: float = s.x0 + (TX - s.x0) * s.len
		var x1: float = s.x0 + (end - s.x0) * head
		var xa: float = s.x0 + (end - s.x0) * maxf(pull, head * 0.35 * (1.0 - s.len) * 3.0)
		var TX_ := TX
		var TY_ := TY
		var yAt := func(x: float) -> float: return y0 + (TY_ - y0) * Px.clamp((x - s.x0) / (TX_ - s.x0)) * 0.85
		var x := xa
		while x <= x1:
			var v := (x - xa) / maxf(1.0, x1 - xa)
			var c: int = WHITE if v > 0.88 else (((C[6] if v > 0.35 else C[5])) if s.hot else (C[5] if v > 0.55 else (C[4] if v > 0.25 else C[3])))
			p.dot(x, yAt.call(x), c, v / 0.12 if v < 0.12 else 1.0)
			if s.w > 1 and v > 0.1:
				p.dot(x, yAt.call(x) + 1.0, C[5] if v > 0.6 else C[3], v / 0.2 if v < 0.2 else 1.0)
			x += 0.5
	if t < OUT + HOLD + PULL:
		p.glowLine(HX + (TX - HX) * pull, HY, HX + (TX - HX) * Px.Ease.outExpo(Px.clamp(t / OUT)), TY, 6.0, C[4], 0.22 * (1.0 - pull))
	# the long star at the point, and a pierce ring shed from it
	var q := t - OUT
	if q >= 0.0 and q < 0.4:
		var g := Px.Ease.outBack(Px.clamp(q / 0.04), 2.4) * (1.0 - Px.smooth(0.08, 0.4, q)) * (1.0 + 0.12 * sin(q * 70.0))
		longStar(p, TX, TY, 24.0 * g, 1.0 - q / 0.4, C)
	if q >= 0.0 and q < 0.2:
		var k := q / 0.2
		var rx := 2.0 + 7.0 * Px.Ease.outCubic(k)
		var ry := 4.0 + 12.0 * Px.Ease.outCubic(k)
		var a := 0.0
		while a < TAU:
			p.dot(TX + 4.0 + 10.0 * k + cos(a) * rx, TY + sin(a) * ry, WHITE if k < 0.3 else C[5], 1.15 - k)
			a += 0.05
	ps.draw(p)
	lights.draw(p)
