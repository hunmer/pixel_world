# The cracks walking out from a point and the burst into tumbling shards, glints and light are adapted from
# Sprite Fusion's open-source ice shatter (https://www.spritefusion.com/pixel-art-vfx/ice), MIT License,
# Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/arcane/time-stop.js@c617f57cccb3b6a7b9128179a0506da8b5042086
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const P := Px.P
const B := Px.B
const WHITE := Px.WHITE

const CY := -42.0
const RC := 26.0
const OPEN := 0.3
const FREEZE := 1.75
const CRACK := 2.2
const SHATTER := 2.42
# the second hand ticks, each wait longer than the last, until time stops
const TICKS := [0.36, 0.46, 0.57, 0.7, 0.85, 1.03, 1.24, 1.49]

static var meta := {
	"name": "Time stop",
	"desc": "A clock face springs open, ticks slower and slower, freezes drained of colour, cracks, then shatters into falling shards.",
	"tags": ["arcane", "time", "clock", "freeze", "stop", "shatter", "magic", "one-shot"],
	"size": [196, 136],
	"origin": [98, 118],
	"duration": 3.6,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": Px.PAL.arcane, "seed": 14},
}


# how far the hand has gone: a snap with a little overshoot at each tick
static func hand(t: float) -> float:
	var a := 0.0
	for tk: float in TICKS:
		if t > tk:
			a += Px.Ease.outBack(Px.clamp((t - tk) / 0.07), 3.0)
	return -PI / 2.0 + a * (TAU / 12.0)

# how fast time flows: full speed, slowing to nothing at the freeze
static func flow(t: float) -> float:
	return 1.0 if t < OPEN else pow(maxf(0.0, 1.0 - (t - OPEN) / (FREEZE - OPEN)), 1.6)

# the motes' clock: time itself, slowing down (integrated flow)
static func clockTime(t: float) -> float:
	var s := 0.0
	var u := 0.0
	while u < minf(t, FREEZE):
		s += flow(u) / 120.0
		u += 1.0 / 120.0
	return s


var C: Array
var R: Px.Rng
var G: Array
var ps: Px.Particles
var bits: Px.Bits
var lights: Px.Lights
var motes: Array
var ix: float
var iy: float
var cracks := []
var t := 0.0
var tc := 0.0
var ticked := 0
var shattered := false
var frozen := false


# cracks: jagged walks out from a point on the face
func walk(x: float, y: float, a: float, ln: float, depth: int) -> void:
	var pts := [[x, y]]
	var s := 0
	while s < ln:
		a += R.range(-0.55, 0.55)
		x += cos(a) * R.range(1.6, 2.6)
		y += sin(a) * R.range(1.6, 2.6)
		if Px.hypot(x, y) > RC - 0.5:
			break
		pts.append([x, y])
		if depth < 1 and pts.size() > 3 and R.chance(0.14):
			walk(x, y, a + R.sign() * R.range(0.6, 1.1), ln / 2.0, depth + 1)
		s += 1
	cracks.append(pts)


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	R = Px.Rng.new(o.seed)
	# the drained ramp: each step's own lightness, cold grey
	G = C.map(func(c):
		var l := Px.luma(c) * 255.0
		return Px.rgb(l * 0.92, l * 0.96, minf(255.0, l * 1.06)))
	ps = Px.Particles.new({"rng": R, "ground": func(): return 0.0, "sparks": [WHITE, C[6], C[5], C[4]]})
	bits = Px.Bits.new({"ground": func(): return 0.0})
	lights = Px.Lights.new()
	motes = Px.arr(14, func(i): return {"a": R.range(0.0, TAU), "r": RC + R.range(5.0, 14.0), "w": R.range(1.4, 2.6) * (1.0 if i % 2 else -1.0), "tilt": R.range(-0.5, 0.5), "c": R.pick([WHITE, C[6], C[5]])})
	ix = R.range(-6.0, 6.0)
	iy = R.range(-6.0, 6.0)
	for i in 7:
		walk(ix, iy, (i / 7.0) * TAU + R.range(-0.3, 0.3), 16.0, 0)


# the face, in ramp K: glass, rims, ticks and dots, hands, hub
func face(p: Px.Painter, K: Array, s: float, cracked: float) -> void:
	var cy := CY
	var r := RC * s
	if r < 1.0:
		return
	p.disc(0.0, cy, r, K[1], func(d: float) -> float: return 0.3 + 0.35 * d * d)
	p.ring(0.0, cy, r + 0.5, 1.0, K[6])
	p.ring(0.0, cy, r - 1.5, 1.0, K[4])
	p.ring(0.0, cy, r + 2.0, 1.0, K[3], 0.6)
	# minute dots and hour ticks; the quarters long and bright
	for i in 60:
		var a := (i / 60.0) * TAU
		if i % 5:
			p.dot(cos(a) * (r - 3.5), cy + sin(a) * (r - 3.5), K[4], 0.8)
		else:
			var q := i % 15 == 0
			var r0 := r - (8.0 if q else 6.5)
			p.line(cos(a) * r0, cy + sin(a) * r0, cos(a) * (r - 3.0), cy + sin(a) * (r - 3.0), K[7] if q else K[6])
	p.ring(0.0, cy, r * 0.3, 1.0, K[4], 0.8)
	# the hour hand, then the second hand with its tail, then the hub
	var ha := -PI / 2.0 + (hand(t) + PI / 2.0) / 12.0 + 0.9
	var sa := hand(t) + (sin(t * 70.0) * 0.012 if frozen else 0.0)
	p.beam(0.0, cy, cos(ha) * r * 0.48, cy + sin(ha) * r * 0.48, 2.6, func(_u: float, v: float) -> int: return K[6] if v < 0.5 else K[4])
	p.line(-cos(sa) * 5.0, cy - sin(sa) * 5.0, cos(sa) * (r - 4.0), cy + sin(sa) * (r - 4.0), func(u: float) -> int: return K[7] if u > 0.75 else K[6])
	p.line(-cos(sa) * 5.0 + 0.5, cy - sin(sa) * 5.0, -cos(sa) * 2.0, cy - sin(sa) * 2.0, K[5])
	p.circle(0.0, cy, 2.2, K[5])
	p.circle(0.0, cy, 1.2, K[7])
	if cracked > 0.0:
		for pts: Array in cracks:
			var n := floori(pts.size() * cracked)
			for i in n:
				var x: float = pts[i][0]
				var y: float = pts[i][1]
				var fresh := i > n - 3 and cracked < 1.0
				p.px(x, cy + y, WHITE if fresh else K[7])
				if not fresh:
					p.px(x, cy + y - 1.0, K[2])


func update(dt: float) -> void:
	t += dt
	tc = clockTime(t)
	# each tick sends a ripple and a spark off the hand's tip
	while ticked < TICKS.size() and t >= TICKS[ticked]:
		ticked += 1
		var a := hand(t + 0.1)
		lights.add(cos(a) * (RC - 4.0), CY + sin(a) * (RC - 4.0), 22.0, C[6], 0.6, 0.12)
		for i in 3:
			ps.spawn(P.STAR, cos(a) * (RC + 1.0), CY + sin(a) * (RC + 1.0), cos(a) * 30.0 + R.range(-15.0, 15.0), sin(a) * 30.0 + R.range(-15.0, 15.0), R.range(0.2, 0.4), R.pick([WHITE, C[6]]), R.range(0.7, 1.3))
	if not frozen and t >= FREEZE:
		frozen = true
		lights.add(0.0, CY, 70.0, WHITE, 0.7, 0.2)
	if not shattered and t >= SHATTER:
		shattered = true
		lights.add(0.0, CY, 80.0, WHITE, 0.8, 0.16)
		lights.add(0.0, CY, 100.0, C[5], 0.6, 0.6)
		# the face bursts into shards and chunks, cold grey; colour sparks back into the world around them
		for i in 64:
			var a := R.range(0.0, TAU)
			var d := R.range(0.0, RC)
			var x := cos(a) * d
			var y := CY + sin(a) * d
			var sp := R.range(40.0, 140.0)
			var dx := x - ix
			var dy := y - CY - iy
			var l := Px.hypot(dx, dy)
			if not l:
				l = 1.0
			bits.add({"kind": B.SHARD, "x": x, "y": y, "vx": (dx / l) * sp + R.range(-25.0, 25.0), "vy": (dy / l) * sp * 0.7 - R.range(40.0, 120.0), "g": 0.9, "drag": 0.5, "bounce": 0.25, "life": R.range(0.8, 1.15), "a": R.range(0.0, TAU), "va": R.range(-22.0, 22.0), "s": R.range(1.5, 3.6), "c": R.pick([G[7], G[6], G[6], G[5]])})
		for i in 10:
			var a := R.range(0.0, TAU)
			var sp := R.range(40.0, 110.0)
			bits.add({"kind": B.CHUNK, "x": cos(a) * RC * 0.6, "y": CY + sin(a) * RC * 0.6, "vx": cos(a) * sp, "vy": sin(a) * sp * 0.6 - R.range(60.0, 130.0), "g": 1.0, "drag": 0.4, "bounce": 0.3, "life": R.range(0.9, 1.15), "a": R.range(0.0, TAU), "va": R.range(-14.0, 14.0), "s": R.range(1.6, 3.0), "ramp": [G[1], G[3], G[4], G[6], G[7]]})
		for i in 26:
			var a := R.range(0.0, TAU)
			var sp := R.range(30.0, 110.0)
			ps.spawn(P.STAR if i % 2 else P.MOTE, 0.0, CY, cos(a) * sp, sin(a) * sp, R.range(0.4, 0.8), R.pick([WHITE, C[6], C[5]]), R.range(0.8, 1.8))
		for i in 18:
			var a := R.range(0.0, TAU)
			var sp := R.range(90.0, 200.0)
			ps.spawn(P.SPARK, 0.0, CY, cos(a) * sp, sin(a) * sp, R.range(0.2, 0.45))
		# the stopped time it held lifts away as a cold vapour
		for i in 12:
			var a := R.range(0.0, TAU)
			var d := R.range(0.0, RC * 0.8)
			ps.spawn(P.VAPOUR, cos(a) * d, CY + sin(a) * d, cos(a) * R.range(10.0, 40.0), sin(a) * R.range(10.0, 30.0) - R.range(5.0, 20.0), R.range(0.6, 1.0), G[5] if R.chance(0.5) else C[4], R.range(3.0, 6.0))
	bits.update(dt)
	ps.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	# the floor lit beneath the clock while it stands
	var k := Px.smooth(0.0, OPEN, t) * (1.0 - Px.smooth(SHATTER, SHATTER + 0.5, t))
	var cold := t >= FREEZE
	if k > 0.0:
		p.glow(0.0, -1.0, 40.0, G[5] if cold else C[4], 0.25 * k)
	# the motes behind the face
	if t < SHATTER:
		for m: Dictionary in motes:
			drawMote(p, m, true)


func draw(p: Px.Painter) -> void:
	var cold := t >= FREEZE
	var s := Px.Ease.outBack(t / OPEN, 2.6) if t < OPEN else 1.0
	if t < SHATTER:
		# white for a beat as it freezes, then cold grey; white again in the moment it bursts
		var white := (t >= FREEZE and t < FREEZE + 0.06) or t >= SHATTER - 0.05
		face(p, G.map(func(_c): return WHITE) if white else (G if cold else C), s, Px.clamp((t - CRACK) / 0.18))
		p.glow(0.0, CY, RC * 1.9, G[5] if cold else C[4], 0.32 * s)
		p.glowRing(0.0, CY, RC, 7.0, G[6] if cold else C[5], 0.28 * s)
		for m: Dictionary in motes:
			drawMote(p, m, false)
	# springing open: a ring thrown out and a flare
	if t < 0.35:
		var q := t / 0.35
		p.ring(0.0, CY, RC * (0.4 + 1.2 * Px.Ease.outCubic(q)), maxf(1.0, 3.0 * (1.0 - q)), WHITE if q < 0.3 else C[6], 1.2 - q)
		if q < 0.5:
			Px.flare(p, 0.0, CY, 26.0 * (1.0 - q * 2.0) + 2.0, 1.0 - q * 2.0, C)
	# a ripple of time off each tick; ripples run on the clock's own slowing time, so they drag to a halt and
	# hang there, drained, until it all breaks
	if t < SHATTER:
		for tk: float in TICKS:
			if t < tk:
				continue
			var q := (tc - clockTime(tk)) / 0.32
			if q >= 1.0:
				continue
			p.ring(0.0, CY, RC + 3.0 + 24.0 * Px.Ease.outCubic(q), 1.0, G[5] if cold else C[5], (0.6 if cold else 0.8) * pow(1.0 - q, 1.6))
	if t >= SHATTER and t < SHATTER + 0.2:
		var q := (t - SHATTER) / 0.2
		Px.flare(p, 0.0, CY, 34.0 * (1.0 - q) + 2.0, 1.0 - q, C)
		p.ring(0.0, CY, RC + 30.0 * Px.Ease.outCubic(q), maxf(1.0, 3.0 * (1.0 - q)), WHITE, 1.2 - q)
	bits.draw(p)
	ps.draw(p)
	lights.draw(p)


# a mote circling the clock on a tilted orbit, slowing with time; drained and still once it stops
func drawMote(p: Px.Painter, m: Dictionary, back: bool) -> void:
	var a: float = m.a + m.w * tc
	var z := sin(a)
	if (z < 0.0) != back:
		return
	var x: float = cos(a) * m.r
	var y: float = CY + cos(a) * m.r * m.tilt + z * m.r * 0.3
	var cold := t >= FREEZE
	var v: float = flow(t) * m.w
	var c: int = G[6] if cold else m.c
	p.dot(x, y, c, 0.6 if back else 1.0)
	# a tail while it still moves
	if absf(v) > 0.2:
		for k in range(1, 4):
			var b: float = a - Px.sign(m.w) * k * 0.05 * minf(1.0, absf(v))
			p.dot(cos(b) * m.r, CY + cos(b) * m.r * m.tilt + sin(b) * m.r * 0.3, C[5] if k < 2 else C[4], (0.5 if back else 0.9) * (1.0 - k / 4.0))
	if not back:
		p.glow(x, y, 5.0, G[6] if cold else C[6], 0.3)
