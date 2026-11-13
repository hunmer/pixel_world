# The charge (streaks spiralling in, a core that swells with an accelerating pulse, little arcs spitting off
# it) and the release (flash, rings, a spray of motes and stars) follow Sprite Fusion's open-source energy charge
# (https://www.spritefusion.com/pixel-art-vfx/energy), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/lightning/charge-up.js@ef7c5201698fa75c0bc0ebd9abd4aad5cf238513
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Charge up",
	"desc": "Sparks streak and arcs whip in to a crackling core at the caster's hand that swells and pulses faster, then it flashes and bursts: bolts every way, a ring, a spray of sparks.",
	"tags": ["lightning", "electric", "charge", "spell", "power-up", "actor", "one-shot"],
	"size": [272, 184],
	"origin": [124, 148],
	"duration": 2.7,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {"palette": Lib.VOLT, "sparks": Lib.PLASMA, "charge": 1.6, "seed": 4},
}

static var HOLD := Px.merge(Px.READY, {"crouch": 3, "lean": -2, "fx": 15, "fy": -21, "bx": 9, "by": -17, "ffx": 9, "fbx": -7})
static var BURST := {"turn": 1.15, "y": -2, "crouch": 0, "lean": -2, "fx": -13, "fy": -37, "bx": 14, "by": -36, "ffx": -2, "ffy": -6, "fbx": 3, "fby": -6}
static var act := {
	"onBody": true,
	"follow": 0,
	"poses": [
		[-0.36, Px.READY],
		[0, HOLD],
		[0.8, Px.merge(HOLD, {"crouch": 4})],
		[1.4, Px.merge(HOLD, {"crouch": 6, "lean": 0})],
		[1.59, Px.merge(HOLD, {"crouch": 7, "lean": 0})],
		[1.6, BURST, "snap"],
		[1.95, Px.merge(BURST, {"y": 0, "crouch": 2, "fy": -30, "by": -30, "ffy": -4, "fby": -4})],
		[2.7, Px.READY],
	],
	"hits": [{"t": 1.6, "stop": 0.14, "shake": 0.3, "amp": 3}],
	"dust": [{"t": 1.6, "x": 10, "n": 6, "dir": 1}, {"t": 1.6, "x": -10, "n": 6, "dir": -1}],
}

const CX := 15.0
const CY := -21.0
const BK := [1.0, 0.7, 0.95, 0.5, 0.8, 0.35]
static var ASH := Px.hex("#5b5566")
static var edges := {}
static func edgeOf(A: Dictionary) -> Array:
	var e: Variant = edges.get(A.mask.id)
	if e:
		return e
	var m: Dictionary = A.mask
	var on := func(x: int, y: int) -> bool: return x >= 0 and y >= 0 and x < m.w and y < m.h and m.data[y * m.w + x]
	e = []
	for y in m.h:
		for x in m.w:
			if on.call(x, y) and (not on.call(x - 1, y) or not on.call(x + 1, y) or not on.call(x, y - 1) or not on.call(x, y + 1)):
				e.append([A.x + x, A.y + y])
	edges[A.mask.id] = e
	return e


var o: Dictionary
var C: Array
var R: Px.Rng
var REL: float
var ps: Px.Particles
var lights: Px.Lights
var bolts: Array
var arcs: Array = []
var t := 0.0
var released := false
var phase := 0.0
var beats: Array = []


func create(o_: Dictionary) -> void:
	o = o_
	C = Px.fit(o.palette, 8)
	R = Px.Rng.new(o.seed)
	REL = o.charge
	var floor_ := func(): return 0.0
	ps = Px.Particles.new({"rng": R, "ground": floor_, "sparks": o.sparks})
	lights = Px.Lights.new()
	bolts = Px.arr(8, func(i):
		var a: float = (i / 8.0) * TAU + R.range(-0.25, 0.25)
		var L := R.range(44.0, 72.0)
		var x1 := CX + cos(a) * L
		var y1 := minf(0.0, CY + sin(a) * L)
		return {"x1": x1, "y1": y1, "t0": REL + R.range(0.0, 0.05)})


func level() -> float:
	return Px.clamp(t / REL)


func update(dt: float) -> void:
	t += dt
	var k := level()
	var e := k * k
	if t < REL:
		# energy rushes in: long streaks spiralling in from all round, more and more of them
		var acc := (60.0 + 360.0 * e) * dt
		while acc > 0.0:
			if acc < 1.0 and not R.chance(acc):
				break
			var a := R.range(0.0, TAU)
			var d := R.range(30.0, 72.0) * (1.0 - 0.35 * k)
			var life := R.range(0.16, 0.26)
			var sp := (d / life) * 0.95
			ps.spawn(P.MOTE, CX + cos(a) * d, minf(-2.0, CY + sin(a) * d), -cos(a) * sp - sin(a) * sp * 0.4, -sin(a) * sp + cos(a) * sp * 0.4, life, R.pick([C[7], C[6], C[5]]), 1.0)
			acc -= 1.0
		# arcs whip in from the air, more and more of them
		if k > 0.2 and R.chance((2.0 + 16.0 * e) * dt):
			var a := R.range(0.0, TAU)
			var d := R.range(20.0, 40.0)
			arcs.append({"x": CX + cos(a) * d, "y": minf(-3.0, CY + sin(a) * d), "t": t, "seed": R.int_(0, 1e6)})
		# the pulse quickens
		phase += (1.5 + 11.0 * e) * dt
		if phase >= 1.0:
			phase -= 1.0
			beats.append(t)
		if R.chance(4.0 * e * dt):
			ps.spawn(P.STAR, CX + R.range(-14.0, 14.0), CY + R.range(-14.0, 10.0), 0.0, -4.0, R.range(0.2, 0.35), C[6], R.range(1.0, 2.0))
	elif not released:
		released = true
		lights.add(CX, CY, 110.0, C[4], 0.8, 0.5)
		lights.add(CX, CY, 28.0, WHITE, 0.6, 0.08)
		for i in 70:
			var a := R.range(0.0, TAU)
			var sp := R.range(140.0, 330.0) * (0.55 if sin(a) > 0.4 else 1.0)
			ps.spawn(P.MOTE if (sin(a) < -0.2 and R.chance(0.35)) else P.SPARK, CX, CY, cos(a) * sp, sin(a) * sp, R.range(0.25, 0.55), R.pick([C[7], C[6], C[5]]), R.range(0.8, 1.4))
		for i in 10:
			var a := R.range(0.0, TAU)
			var sp := R.range(60.0, 160.0)
			ps.spawn(P.STAR, CX, CY, cos(a) * sp, sin(a) * sp, R.range(0.4, 0.8), C[6] if R.chance(0.5) else C[5], R.range(1.2, 2.4))
		for i in 4:
			ps.spawn(P.SMOKE, CX + R.range(-5.0, 5.0), CY + R.range(-4.0, 4.0), R.range(-12.0, 12.0), -R.range(8.0, 18.0), R.range(0.6, 0.85), Px.mix(ASH, C[4], 0.3), R.range(3.0, 5.0), R.range(0.05, 0.15))
	beats = beats.filter(func(b): return t - b < 0.22)
	var i := arcs.size() - 1
	while i >= 0:
		if t - arcs[i].t > 0.07:
			arcs.remove_at(i)
		i -= 1
	ps.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	var k := level()
	if t < REL:
		p.glow(CX * 0.5, -3.0, 40.0, C[3], 0.3 * k * k)
	ps.draw(p, "back")


func draw(p: Px.Painter) -> void:
	var k := level()
	var e := k * k
	var f := floori(t * 30.0 + 1e-4)
	var A: Dictionary = o.actor
	if t < REL:
		var jit := ((1.0 if f % 2 else -1.0) * ((k - 0.85) / 0.15)) if k > 0.85 else 0.0
		var x := CX + jit
		var y := CY
		var pr := 0.5 + 0.5 * sin(phase * TAU)
		# the body catches the core's light along its near edge
		for ed: Array in edgeOf(A):
			var ex: float = ed[0]
			var ey: float = ed[1]
			var d := Px.hypot(ex + 0.5 - x, ey + 0.5 - y)
			if d < 6.0 + 10.0 * k and e > 0.08:
				p.px(ex, ey, C[6] if (d < 4.0 + 6.0 * k and e > 0.4) else C[4])
		# rings fall inward to the core on every beat
		for b: float in beats:
			var q := (t - b) / 0.22
			p.ring(x, y, 4.0 + 20.0 * (1.0 - Px.Ease.inQuad(q)) * (0.5 + k), 1.0, C[6] if q > 0.6 else C[4], 0.4 + 0.6 * q)
		# arcs whipping in to the core
		for a: Dictionary in arcs:
			Lib.crackle(p, Lib.zigzag(Px.rng(a.seed, f), a.x, a.y, x, y, 0.35, 0.4), 0.85, C, 0.4)
		# the core: swelling, layered, with arcs racing round its skin
		var r := 1.2 + 6.5 * e + pr * (0.5 + 1.2 * k)
		p.circle(x, y, r + 1.3, C[2])
		p.circle(x, y, r, C[4])
		p.circle(x - r * 0.12, y - r * 0.12, r * 0.7, C[5])
		p.circle(x, y, r * 0.38, WHITE)
		if r > 3.0:
			for s: float in [0.0, PI]:
				var a := 0.0
				while a < 1.3:
					var ang := t * 10.0 + s + a
					var rr := r * (0.62 + 0.1 * sin(a * 3.0))
					p.dot(x + cos(ang) * rr, y + sin(ang) * rr, WHITE if a < 0.5 else C[6])
					a += 0.12
		if k > 0.35:
			var q := Px.rng(o.seed, 5, f)
			var a := q.range(0.0, TAU)
			var l := q.range(3.0, 6.0) * (0.5 + k)
			Lib.crackle(p, Lib.zigzag(q, x + cos(a) * r, y + sin(a) * r, x + cos(a) * (r + l), y + sin(a) * (r + l), 0.4, 0.3), 0.7, C, 0.3)
		p.glow(x, y, 12.0 + 30.0 * k, C[4], 0.35 + 0.45 * k)
		p.glow(x, y, 6.0 + 6.0 * k, C[6], 0.25 + 0.3 * k)
	else:
		var a := t - REL
		# the release: the caster flashed white, a flare, a white core blown open
		if a < 0.07:
			p.mask(A.mask, A.x, A.y, WHITE if a < 0.035 else C[6])
		if a < 0.22:
			var q := a / 0.22
			Px.flare(p, CX, CY, 46.0 * pow(1.0 - q, 1.4), 1.0 - q, C)
			if q < 0.3:
				p.circle(CX, CY, 12.0 * (1.0 - q * 2.5) + 1.5, WHITE)
		# bolts every way, struck and flickering
		for i in bolts.size():
			var b: Dictionary = bolts[i]
			var ba := floori((t - b.t0) * 30.0 + 1e-4)
			if t < b.t0 or ba >= BK.size():
				continue
			Lib.stroke(p, Lib.zigzag(Px.rng(o.seed, 3, i, ba >> 1), CX, CY, b.x1, b.y1, 0.25, 0.75), BK[ba], C, 0.95 if ba == 0 else 0.75, {"hero": ba == 0})
			if b.y1 > -1.0:
				p.glow(b.x1, -3.0, 18.0, C[5], 0.5 * BK[ba])
		# a ring bursting out with a fainter echo inside it
		var q := a / 0.45
		if q < 1.0:
			var r := 8.0 + 80.0 * Px.Ease.outCubic(q)
			var hide := func(rr): return func(v, g): return 0.0 if CY + sin(g) * rr > -1.0 else 1.1 - q
			p.ring(CX, CY, r, maxf(1.0, 3.0 * (1.0 - q)), WHITE if q < 0.25 else C[5], hide.call(r))
			var r2 := 6.0 + 56.0 * Px.Ease.outCubic(minf(1.0, q * 1.3))
			p.ring(CX, CY, r2, 1.0, C[4], func(v, g): return 0.0 if CY + sin(g) * r2 > -1.0 else 0.8 - q)
			p.glow(CX, CY - 6.0, minf(r * 0.9, 46.0), C[3], 0.42 * (1.0 - q) * (1.0 - q))
		# the charge bleeds off in a few last crackles at the hand
		if a > 0.15 and a < 0.5:
			var qq := Px.rng(o.seed, 8, f)
			var ang := qq.range(0.0, TAU)
			var l := qq.range(5.0, 10.0)
			Lib.crackle(p, Lib.zigzag(qq, CX, CY, CX + cos(ang) * l, CY + sin(ang) * l, 0.45, 0.3), 0.8 * (1.0 - (a - 0.15) / 0.35) + 0.15, C, 0.3)
	ps.draw(p, "front")
	lights.draw(p)
