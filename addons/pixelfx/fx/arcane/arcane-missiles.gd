# The bolt and its pop (a layered head with spinning rays, a flash disc, a cross, a ring, plasma sparks and stars)
# are adapted from Sprite Fusion's open-source energy bolt (https://www.spritefusion.com/pixel-art-vfx/energy),
# MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/arcane/arcane-missiles.js@e992bce1af5fd7f2f8013cf428458528392d225b
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const P := Px.P
const WHITE := Px.WHITE

const HX := 15.0
const HY := -24.0
const TX := 152.0
const TY := -22.0
const N := 5
const TRAIL := 18

static var meta := {
	"name": "Arcane missiles",
	"desc": "A volley of violet bolts fans out of the hand, curls round on twisting ribbons and pops on the target one after another.",
	"tags": ["arcane", "missile", "projectile", "homing", "volley", "magic", "directional", "one-shot"],
	"size": [240, 116],
	"origin": [26, 88],
	"duration": 1.75,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {"palette": Px.PAL.arcane, "seed": 3},
}

static var OPEN := Px.merge(Px.READY, {"x": -3, "crouch": 4, "lean": 4, "fx": 18, "fy": -24, "bx": -6, "by": -22, "ffx": 11, "fbx": -9})
static var KICK := Px.merge(OPEN, {"fx": 15, "fy": -26, "lean": 2})
static var GATHER := Px.merge(Px.READY, {"x": -3, "crouch": 4, "lean": -2, "fx": 6, "fy": -24, "bx": 8, "by": -24, "ffx": 9, "fbx": -7})
static var act := {
	"target": {"x": 152},
	"poses": [
		[-0.52, Px.merge(Px.READY, {"x": -3})],
		[-0.24, GATHER],
		[0, Px.merge(GATHER, {"crouch": 5})],
		[0.05, KICK, "snap"],
		[0.1, OPEN, "snap"],
		[0.15, KICK, "snap"],
		[0.2, OPEN, "snap"],
		[0.25, KICK, "snap"],
		[0.29, OPEN, "snap"],
		[0.33, KICK, "snap"],
		[0.38, OPEN, "snap"],
		[0.43, KICK, "snap"],
		[0.48, OPEN, "snap"],
		[1.2, Px.merge(OPEN, {"crouch": 3})],
		[1.7, Px.merge(Px.READY, {"x": -3})],
	],
	"hits": [
		{"t": 0.77, "stop": 0.02, "push": 0.7, "straw": 4, "y": -24, "flash": 0.03},
		{"t": 0.85, "stop": 0.02, "push": 0.7, "straw": 4, "y": -24, "flash": 0.03},
		{"t": 0.95, "stop": 0.02, "push": 0.7, "straw": 4, "y": -24, "flash": 0.03},
		{"t": 1.08, "stop": 0.02, "push": 0.7, "straw": 4, "y": -24, "flash": 0.03},
		{"t": 1.2, "stop": 0.07, "shake": 0.14, "amp": 1, "push": 1.4, "straw": 9, "y": -24},
	],
}


var C: Array
var R: Px.Rng
var ps: Px.Particles
var lights: Px.Lights
var bolts: Array
var pops := []
var t := 0.0


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	R = Px.Rng.new(o.seed)
	ps = Px.Particles.new({"rng": R, "ground": func(): return 0.0, "sparks": [WHITE, C[6], C[5], C[4]]})
	lights = Px.Lights.new()
	# each bolt leaves the hand on its own heading, then homes in harder and faster until it lands
	var fan := [-1.05, 0.7, -0.5, 1.1, -1.4]
	bolts = []
	for i in fan.size():
		var a: float = fan[i]
		a += R.range(-0.12, 0.12)
		var sp := R.range(130.0, 165.0)
		bolts.append({"t0": 0.05 + i * 0.1, "x": HX, "y": HY, "vx": cos(a) * sp, "vy": sin(a) * sp, "trail": [], "hit": -1.0, "on": false, "tx": TX + R.range(-3.0, 3.0), "ty": TY + R.range(-6.0, 6.0), "tw": R.range(0.0, TAU), "acc": 0.0})


func ribbon(p: Px.Painter, b: Dictionary) -> void:
	var pts: Array = b.trail
	var n := pts.size()
	var fade: float = 1.0 if b.hit < 0.0 else 1.0 - Px.clamp((t - b.hit) / 0.16)
	if n < 2 or fade <= 0.0:
		return
	for i in n - 1:
		var x0: float = pts[i][0]
		var y0: float = pts[i][1]
		var x1: float = pts[i + 1][0]
		var y1: float = pts[i + 1][1]
		var L := Px.hypot(x1 - x0, y1 - y0)
		if not L:
			L = 1.0
		var nx := -(y1 - y0) / L
		var ny := (x1 - x0) / L
		var d := 0.0
		while d < L:
			var u := (i + d / L) / (n - 1)
			var x := x0 + ((x1 - x0) * d) / L
			var y := y0 + ((y1 - y0) * d) / L
			var a := (1.0 - u) * 1.7 * fade
			# the body: a capsule that tapers down the tail, white along its middle near the head, cooling outward
			var w := 2.6 * pow(1.0 - u, 0.8) + 0.3
			var q := -w
			while q <= w:
				var v := absf(q) / w
				p.dot(x + nx * q, y + ny * q, (WHITE if u < 0.25 else C[6]) if v < 0.35 else ((C[6] if u < 0.4 else C[5]) if v < 0.7 else (C[5] if u < 0.5 else C[4])), a * (1.0 if v < 0.7 else 0.75))
				q += 0.5
			# two strands twisting round it: bright where they come round the front, dim behind
			for s in [0.0, PI]:
				var ph: float = u * 10.0 - t * 26.0 + b.tw + s
				var off := sin(ph) * (w + 1.4)
				if cos(ph) > -0.2:
					p.dot(x + nx * off, y + ny * off, (WHITE if u < 0.35 else C[6]) if cos(ph) > 0.4 else C[4], a)
			d += 0.5
		if i % 3 == 0:
			p.glow(x0, y0, 9.0 * (1.0 - float(i) / n) + 3.0, C[5], 0.3 * (1.0 - float(i) / n) * fade)


func head(p: Px.Painter, b: Dictionary) -> void:
	var x: float = b.x
	var y: float = b.y
	for i in 4:
		var a: float = t * 24.0 + (i * TAU) / 4.0 + b.tw
		var l := 5.5 + 1.5 * sin(t * 50.0 + i)
		p.line(x + cos(a) * 3.2, y + sin(a) * 3.2, x + cos(a) * l, y + sin(a) * l, C[6])
	p.circle(x, y, 3.8, C[4])
	p.circle(x, y, 3.0, C[5])
	p.circle(x, y, 2.1, C[6])
	p.circle(x, y, 1.2, WHITE)
	p.glow(x, y, 24.0, C[5], 0.6)
	p.glow(x, y, 7.0, WHITE, 0.4)


func pop(p: Px.Painter, q: float, x: float, y: float) -> void:
	if q < 0.16:
		var r := 9.0 * (1.0 - q / 0.16) + 1.5
		p.circle(x, y, r + 1.5, C[5])
		p.circle(x, y, r, WHITE)
	if q < 0.4:
		var l := 15.0 * (1.0 - q / 0.4) + 3.0
		var d := -l
		while d <= l:
			var a := absf(d) / l
			var c: int = WHITE if a < 0.3 else (C[6] if a < 0.65 else C[5])
			p.dot(x + d, y, c, 1.15 - a)
			p.dot(x, y + d * 0.7, c, 1.15 - a)
			d += 1.0
	var rr := 3.0 + 18.0 * Px.Ease.outCubic(q)
	p.ring(x, y, rr + 0.5, maxf(1.0, 3.0 * (1.0 - q)), WHITE if q < 0.3 else C[6], 1.2 - q)


# the lock: four brackets close on the target and pulse as each bolt lands
func lock(p: Px.Painter) -> void:
	var k := Px.smooth(0.0, 0.22, t) * (1.0 - Px.smooth(1.15, 1.45, t))
	if k <= 0.0:
		return
	var kick := 0.0
	for q: Dictionary in pops:
		kick = maxf(kick, exp(-pow((t - q.t) / 0.06, 2.0)))
	var r := 9.0 + 10.0 * (1.0 - Px.Ease.outCubic(Px.smooth(0.0, 0.22, t))) + 3.0 * kick
	var spin := t * 1.5
	for i in 4:
		var a0 := spin + (i * TAU) / 4.0 - 0.38
		var a := a0
		while a <= a0 + 0.76:
			p.dot(TX + cos(a) * r, TY + sin(a) * r, WHITE if kick > 0.4 else C[5], k)
			a += 0.06
	p.glow(TX, TY, 12.0, C[4], 0.2 * k)


func update(dt: float) -> void:
	t += dt
	for b: Dictionary in bolts:
		if t < b.t0 or b.hit >= 0.0:
			continue
		if not b.on:
			b.on = true
			lights.add(HX, HY, 28.0, C[5], 0.7, 0.14)
			for i in 4:
				ps.spawn(P.MOTE, HX, HY, cos(atan2(b.vy, b.vx) + R.range(-0.6, 0.6)) * R.range(60.0, 140.0), sin(atan2(b.vy, b.vx) + R.range(-0.6, 0.6)) * R.range(60.0, 140.0), R.range(0.12, 0.25), C[6], 0.6)
		var age: float = t - b.t0
		var dx: float = b.tx - b.x
		var dy: float = b.ty - b.y
		var d := Px.hypot(dx, dy)
		if not d:
			d = 1.0
		var sp := 150.0 + 560.0 * age * age
		var steer := minf(1.0, (1.4 + 15.0 * age) * dt)
		b.vx += ((dx / d) * sp - b.vx) * steer
		b.vy += ((dy / d) * sp - b.vy) * steer
		b.x += b.vx * dt
		b.y += b.vy * dt
		b.trail.push_front([b.x, b.y])
		if b.trail.size() > TRAIL:
			b.trail.pop_back()
		b.acc += dt
		if b.acc > 0.012:
			b.acc = 0.0
			if R.chance(0.6):
				ps.spawn(P.MOTE, b.x, b.y, -b.vx * 0.08 + R.range(-25.0, 25.0), -b.vy * 0.08 + R.range(-25.0, 25.0), R.range(0.2, 0.4), C[6] if R.chance(0.5) else C[5], 0.55)
		if d < 3.0 or age > 1.3:
			b.hit = t
			pops.append({"t": t, "x": b.x, "y": b.y})
			lights.add(b.x, b.y, 70.0, C[5], 0.9, 0.3)
			lights.add(b.x, b.y, 24.0, WHITE, 0.85, 0.09)
			for i in 16:
				var a := R.range(0.0, TAU)
				var v := R.range(80.0, 230.0)
				ps.spawn(P.SPARK, b.x, b.y, cos(a) * v, sin(a) * v - 40.0, R.range(0.15, 0.45))
			for i in 7:
				var a := R.range(-PI, 0.3)
				var v := R.range(40.0, 140.0)
				ps.spawn(P.STAR if i % 2 else P.MOTE, b.x, b.y, cos(a) * v, sin(a) * v, R.range(0.25, 0.48), R.pick([WHITE, C[6], C[5]]), R.range(0.8, 1.6))
	ps.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	# the floor catches the light of each pop
	for q: Dictionary in pops:
		var k := 1.0 - Px.clamp((t - q.t) / 0.5)
		if k > 0.0:
			p.glow(q.x, -1.0, 22.0, C[5], 0.25 * k * k)


func draw(p: Px.Painter) -> void:
	lock(p)
	for b: Dictionary in bolts:
		if b.on:
			ribbon(p, b)
	for b: Dictionary in bolts:
		if b.on and b.hit < 0.0:
			head(p, b)
	for q: Dictionary in pops:
		var k: float = (t - q.t) / 0.35
		if k < 1.0:
			pop(p, k, q.x, q.y)
	if t < 0.55:
		Px.sparkle(p, HX, HY, 3.0 + 2.0 * sin(t * 40.0), C[6], C[5], 0.45 * (1.0 - t / 0.55))
	ps.draw(p)
	lights.draw(p)
