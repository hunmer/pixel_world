# The hop timing, the link shapes that re-strike every other frame, the glowing nodes and the crawling arcs
# follow Sprite Fusion's open-source lightning (https://www.spritefusion.com/pixel-art-vfx/lightning),
# MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/lightning/chain-lightning.js@3600eb2a1e914fe08e478758092f95d28c70086e
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Chain lightning",
	"desc": "A bolt leaps from the caster's hand through three targets in turn; each flashes, sparks and grounds itself to the floor while the arcs between them flicker, then the chain snaps.",
	"tags": ["lightning", "electric", "chain", "spell", "combat", "directional", "one-shot"],
	"size": [248, 104],
	"origin": [40, 82],
	"duration": 1.8,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {"palette": Lib.VOLT, "sparks": Lib.PLASMA, "seed": 3},
}

static var AIM := Px.merge(Px.READY, {"x": -6, "crouch": 4, "lean": 4, "fx": 16, "fy": -16, "bx": -6, "by": -23, "ffx": 11, "fbx": -9})
static var BACK := Px.merge(Px.READY, {"x": -6, "crouch": 4, "lean": -3, "fx": -5, "fy": -32, "bx": 8, "by": -24, "armsFront": true, "ffx": 9, "fbx": -7})
static func zap(at: int, t_: float, stop: float = 0.03) -> Dictionary:
	return {"t": t_, "at": at, "stop": stop, "push": 1.2, "straw": 6, "skin": "shock", "shiver": 0.7, "y": -22}
static var act := {
	"targets": [{"x": 58}, {"x": 104}, {"x": 150}],
	"poses": [
		[-0.46, Px.merge(Px.READY, {"x": -6})],
		[-0.22, BACK],
		[0, Px.merge(BACK, {"crouch": 5})],
		[0.04, AIM, "snap"],
		[0.7, Px.merge(AIM, {"crouch": 3})],
		[1.35, Px.merge(AIM, {"crouch": 3, "fy": -18})],
		[1.8, Px.merge(Px.READY, {"x": -6})],
	],
	"hits": [
		zap(0, 0.05),
		zap(1, 0.14),
		Px.merge(zap(2, 0.23, 0.07), {"shake": 0.14, "amp": 1}),
		{"t": 1.35, "push": 0, "straw": 0, "flash": 0, "skin": null},
	],
}

const HAND := [10.0, -16.0]
const HOPS := [[58.0, -22.0], [104.0, -30.0], [150.0, -19.0]]
const WIND := 0.12
const LEAP := 0.05
const GAP := 0.075
const HOLD := 0.78
const BREAK := 0.16
static var ASH := Px.hex("#5b5566")
static func on(i: int) -> float: # when link i lands on its target
	return WIND + i * GAP + LEAP
static func off(i: int) -> float: # when it starts to give out
	return HOLD + i * 0.05


# a link's strength: a hard first flash, a restless hum, then it stutters out
static func level(i: int, t_: float) -> float:
	var a := t_ - on(i)
	if a < 0.0:
		return 0.0
	var hf := floori(a * 30.0)
	var hum: float = ([1.0, 0.55, 1.0][hf] if hf < 3 else 1.0) if a < 0.1 else 0.78 + 0.22 * sin(t_ * 61.0 + i) * sin(t_ * 23.0 + i * 2)
	var b := t_ - off(i)
	return hum if b < 0.0 else (hum * (1.0 - b / BREAK) * (0.5 if floori(b * 60.0) % 3 == 1 else 1.0) if b < BREAK else 0.0)


var o: Dictionary
var C: Array
var R: Px.Rng
var ps: Px.Particles
var hot: Px.Particles
var lights: Px.Lights
var pts: Array
var hit: Array
var popped: Array
var ground: Array
var t := 0.0


func create(o_: Dictionary) -> void:
	o = o_
	C = Px.fit(o.palette, 8)
	R = Px.Rng.new(o.seed)
	var floor_ := func(): return 0.0
	ps = Px.Particles.new({"rng": R, "ground": floor_, "sparks": o.sparks})
	hot = Px.Particles.new({"rng": R, "ground": floor_})
	lights = Px.Lights.new()
	pts = [HAND] + HOPS
	hit = HOPS.map(func(_h): return false)
	popped = HOPS.map(func(_h): return false)
	# where each target grounds itself: a spot on the floor below it
	ground = HOPS.map(func(h): return h[0] + R.range(-5.0, 5.0))


func shape(i: int, f: int, salt: int = 0) -> Dictionary:
	var r := Px.rng(o.seed, 31 + salt, i, f)
	var x0: float = pts[i][0]
	var y0: float = pts[i][1]
	var x1: float = pts[i + 1][0]
	var y1: float = pts[i + 1][1]
	var L := Px.hypot(x1 - x0, y1 - y0)
	return Lib.bowed(r, x0, y0, x1, y1, -L * r.range(0.05, 0.15), 0.2, 0.08)


func update(dt: float) -> void:
	t += dt
	# the charge gathers at the hand
	if t < WIND and R.chance(70.0 * dt):
		var a := R.range(0.0, TAU)
		var d := R.range(10.0, 24.0)
		var T := R.range(0.06, 0.1)
		var v := (d * 3.0) / (exp(3.0 * T) - 1.0)
		ps.spawn(P.STREAK, HAND[0] + cos(a) * d, HAND[1] + sin(a) * d, -cos(a) * v, -sin(a) * v, T, C[6] if R.chance(0.5) else C[5])
	for i in HOPS.size():
		var x: float = HOPS[i][0]
		var y: float = HOPS[i][1]
		if not hit[i] and t >= on(i):
			hit[i] = true
			var px: float = pts[i][0]
			var py: float = pts[i][1]
			var dir := atan2(y - py, x - px)
			lights.add(x, y, 56.0, C[4], 0.85, 0.22)
			lights.add(x, y, 16.0, WHITE, 0.7, 0.08)
			if i == 0:
				lights.add(HAND[0], HAND[1], 40.0, C[4], 0.6, 0.15)
			for j in 18:
				var a := dir + R.range(-1.1, 1.1) if R.chance(0.6) else R.range(0.0, TAU)
				var sp := R.range(70.0, 230.0)
				ps.spawn(P.SPARK, x, y, cos(a) * sp, sin(a) * sp - 40.0, R.range(0.15, 0.4))
			for j in 5:
				hot.spawn(P.SPARK, x + R.range(-2.0, 2.0), y + 2.0, R.range(-50.0, 50.0), R.range(-60.0, 20.0), R.range(0.5, 0.9))
			ps.spawn(P.STAR, x + R.range(-4.0, 4.0), y - R.range(3.0, 7.0), 0.0, -6.0, R.range(0.25, 0.4), C[6], R.range(1.5, 2.5))
			for j in 2:
				ps.spawn(P.SMOKE, x + R.range(-4.0, 4.0), y + R.range(-2.0, 3.0), R.range(-6.0, 6.0), -R.range(8.0, 16.0), R.range(0.7, 1.0), Px.mix(ASH, C[2], 0.35), R.range(2.0, 3.5), R.range(0.1, 0.25))
		# while the chain holds: sparks shed off the links, spit from the floor where each target grounds
		if hit[i] and t < off(i):
			if R.chance(9.0 * dt):
				var u := R.next()
				var x0: float = pts[i][0]
				var y0: float = pts[i][1]
				ps.spawn(P.SPARK, Px.lerp(x0, x, u), Px.lerp(y0, y, u) - 2.0, R.range(-60.0, 60.0), R.range(-90.0, 20.0), R.range(0.1, 0.25))
			if R.chance(7.0 * dt):
				ps.spawn(P.SPARK, ground[i], -1.0, R.range(-70.0, 70.0), -R.range(40.0, 140.0), R.range(0.12, 0.3))
			if R.chance(2.0 * dt):
				hot.spawn(P.SPARK, x + R.range(-3.0, 3.0), y + 3.0, R.range(-30.0, 30.0), R.range(-30.0, 10.0), R.range(0.5, 0.8))
		# when it gives out, the target pops once more and smokes
		if not popped[i] and t >= off(i) + BREAK:
			popped[i] = true
			for j in 7:
				var a := R.range(0.0, TAU)
				var sp := R.range(40.0, 140.0)
				ps.spawn(P.SPARK, x, y, cos(a) * sp, sin(a) * sp - 30.0, R.range(0.12, 0.3))
			ps.spawn(P.SMOKE, x, y, R.range(-4.0, 4.0), -R.range(10.0, 16.0), R.range(0.55, 0.7), Px.mix(ASH, C[2], 0.35), R.range(2.5, 3.5))
			lights.add(x, y, 30.0, C[4], 0.5, 0.12)
	ps.update(dt)
	hot.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	# the floor scorches where the targets ground themselves
	for i in HOPS.size():
		var a := t - on(i)
		if a < 0.0:
			continue
		var T0 := minf(1.0, a / 0.2) * pow(Px.clamp(1.0 - (t - off(i)) / 0.7), 1.3) * 0.9
		Lib.scorch(p, ground[i], 0.0, 7.0, T0, 1.0 - Px.smooth(1.35, 1.75, t))
	ps.draw(p, "back")
	hot.draw(p, "back")


func draw(p: Px.Painter) -> void:
	var f := floori(t * 30.0 + 1e-4)
	var f2 := f >> 1
	# the hand: a node that swells while the charge gathers and holds the chain
	var kh := t / WIND if t < WIND else level(0, t)
	if kh > 0.02:
		var r := (1.2 + 1.6 * kh + sin(t * 53.0) * 0.4) * minf(1.0, kh * 1.5)
		p.circle(HAND[0], HAND[1], r + 1.2, C[4])
		p.circle(HAND[0], HAND[1], r, C[6])
		p.circle(HAND[0], HAND[1], r * 0.5, WHITE)
		p.glow(HAND[0], HAND[1], 18.0, C[4], 0.6 * kh)
		if t > WIND * 0.5:
			var r2 := Px.rng(o.seed, 5, f)
			var a := r2.range(0.0, TAU)
			var d := r2.range(4.0, 8.0)
			Lib.crackle(p, Lib.zigzag(r2, HAND[0], HAND[1], HAND[0] + cos(a) * d, HAND[1] + sin(a) * d, 0.4, 0.3), 0.6 * kh, C, 0.3)
	for i in HOPS.size():
		var x: float = HOPS[i][0]
		var y: float = HOPS[i][1]
		var t0 := WIND + i * GAP
		# the leap: the bolt races out from the last node with a hot head
		if t >= t0 and t < on(i):
			var u := Px.Ease.outQuad((t - t0) / LEAP)
			var b := shape(i, -1)
			var trunk := {"paths": [b.paths[0]]}
			Lib.stroke(p, trunk, 1.0, C, 0.75, {"upTo": u})
			var tp: Array = b.paths[0].pts
			var hxy: Array = tp[mini(tp.size() - 1, floori(u * (tp.size() - 1)))]
			var hx: float = hxy[0]
			var hy: float = hxy[1]
			p.circle(hx, hy, 2.0, WHITE)
			p.glow(hx, hy, 16.0, C[5], 0.7)
		var k := level(i, t)
		if k > 0.0:
			Lib.stroke(p, shape(i, f2), k, C, 0.75)
		elif t >= off(i) + BREAK and t < off(i) + BREAK + 0.35:
			# the spent channel: a dotted trace that cools and goes
			var g := 1.0 - (t - off(i) - BREAK) / 0.35
			var b := shape(i, floori((off(i) + BREAK) * 15.0))
			Lib.trace(p, b.paths[0].pts, C[4] if g > 0.5 else C[2], g * 0.9)
		# the target: a flash as the bolt lands, then a node with arcs crawling over it and down to the floor
		var a := t - on(i)
		if a >= 0.0 and a < 0.09:
			var q := a / 0.09
			p.circle(x, y, 6.0 * (1.0 - q) + 1.5, C[5])
			p.circle(x, y, 5.0 * (1.0 - q), WHITE)
			Px.sparkle(p, x, y, Px.round(10.0 * (1.0 - q)), C[6], C[4], 0.6)
		if k > 0.05:
			var r := (2.6 + sin(t * 47.0 + i) * 0.7) * k
			p.circle(x, y, r + 1.5, C[2])
			p.circle(x, y, r + 0.7, C[5])
			p.circle(x, y, r * 0.6, WHITE)
			p.glow(x, y, 26.0, C[4], 0.6 * k)
			p.glow(x, y, 8.0, C[6], 0.5 * k)
			# arcs crawl over the target as if over a body caught in the current
			var r2 := Px.rng(o.seed, 11, i, f)
			var j := 0
			while j < (2 if t - on(i) < 0.12 else 1):
				var a0 := r2.range(0.0, TAU)
				var a1 := a0 + r2.sign() * r2.range(0.5, 1.0)
				var d0 := r2.range(4.0, 6.0)
				var d1 := r2.range(5.0, 8.0)
				Lib.crackle(p, Lib.zigzag(r2, x + cos(a0) * d0, y + sin(a0) * d0, x + cos(a1) * d1, y + sin(a1) * d1, 0.35, 0.0), r2.range(0.45, 0.7) * k, C, 0.25)
				j += 1
			if r2.next() < 0.3 * k:
				var gx: float = ground[i] + r2.range(-3.0, 3.0)
				Lib.crackle(p, Lib.zigzag(r2, x + r2.range(-2.0, 2.0), y + 3.0, gx, -0.5, 0.3, 0.35), 0.75 * k, C, 0.35)
				p.glow(gx, -1.0, 12.0, C[5], 0.5 * k)
				p.px(gx, -1.0, WHITE)
	ps.draw(p, "front")
	hot.draw(p, "front")
	lights.draw(p)
