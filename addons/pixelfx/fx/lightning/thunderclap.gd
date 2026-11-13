# The flash and flare, the bolts and their flicker, the plasma spray, the scorch where bolts land and the dust
# thrown along the floor follow Sprite Fusion's open-source lightning and explosion
# (https://www.spritefusion.com/pixel-art-vfx/lightning), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/lightning/thunderclap.js@6fac4bbf932c9ad91d01085d257b97fcdd309c09
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const PF := Px.PF
const WHITE := Px.WHITE

static var meta := {
	"name": "Thunderclap",
	"desc": "A thunderclap round the caster: a white flash, forked bolts burst out and stab the floor, a heavy shock ring tears across the ground raising dust and grit, sparks streak away.",
	"tags": ["lightning", "electric", "nova", "aoe", "spell", "shockwave", "one-shot"],
	"size": [288, 156],
	"origin": [144, 124],
	"duration": 1.9,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {"palette": Lib.VOLT, "sparks": Lib.PLASMA, "reach": 104, "seed": 6},
}

static var WIDE := {"turn": 1.15, "crouch": 5, "lean": -1, "fx": -15, "fy": -33, "bx": 15, "by": -33, "ffx": -7, "fbx": 8}
static var CLAP_ := {"turn": 1.15, "y": -2, "crouch": 0, "fx": -1, "fy": -45, "bx": 1, "by": -45, "ffx": -3, "ffy": -5, "fbx": 4, "fby": -5}
static var act := {
	"onBody": true,
	"follow": 0,
	"target": {"x": 104},
	"poses": [
		[-0.46, Px.READY],
		[-0.18, WIDE],
		[0.08, Px.merge(WIDE, {"crouch": 6})],
		[0.12, CLAP_, "snap"],
		[0.55, Px.merge(CLAP_, {"y": 0, "ffy": -4, "fby": -4, "crouch": 1})],
		[1.05, {"turn": 1, "crouch": 3, "fx": -10, "fy": -28, "bx": 11, "by": -28, "ffx": -4, "fbx": 5}],
		[1.7, Px.READY],
	],
	"hits": [
		{"t": 0.12, "stop": 0.13, "shake": 0.3, "amp": 3, "target": false},
		{"t": 0.42, "push": 2, "straw": 14, "y": -8, "skin": "shock", "shiver": 0.5},
		{"t": 1.2, "push": 0, "straw": 0, "flash": 0, "skin": null},
	],
}

const CLAP := 0.12
const CY := -22.0
const BK := [1.0, 0.7, 0.95, 0.5, 0.8, 0.3]
static var DUST := Px.hex("#6e6382")
static var STONE := Px.ramp(["#655b7a", "#4a4263", "#342d45"])
static var ASH := Px.hex("#5b5566")


var o: Dictionary
var C: Array
var R: Px.Rng
var REACH: float
var ps: Px.Particles
var hot: Px.Particles
var lights: Px.Lights
var bolts: Array
var t := 0.0
var clapped := false
var landed: Array


func create(o_: Dictionary) -> void:
	o = o_
	C = Px.fit(o.palette, 8)
	R = Px.Rng.new(o.seed)
	REACH = o.reach
	var floor_ := func(): return 0.0
	ps = Px.Particles.new({"rng": R, "ground": floor_, "sparks": o.sparks})
	hot = Px.Particles.new({"rng": R, "ground": floor_})
	lights = Px.Lights.new()
	# eight bolts: the lower ones stab the floor, the upper ones tear into the air
	bolts = Px.arr(8, func(i):
		var down: bool = i % 2 == 0
		var side := -1 if i % 4 < 2 else 1
		var a := ((R.range(0.35, 0.75) if side > 0 else PI - R.range(0.35, 0.75))) if down else (-R.range(0.15, 1.2) if side > 0 else PI + R.range(0.15, 1.2))
		var L := -CY / sin(a) if down else R.range(40.0, 62.0)
		var x1 := cos(a) * L
		var y1 := 0.0 if down else CY + sin(a) * L
		return {"down": down, "x1": x1, "y1": y1, "t0": CLAP + R.range(0.0, 0.06)})
	landed = bolts.map(func(_b): return false)


func front(t_: float) -> float:
	return 0.0 if t_ < CLAP else 8.0 + (REACH - 8.0) * Px.Ease.outCubic(Px.clamp((t_ - CLAP) / 0.5))


func update(dt: float) -> void:
	t += dt
	# the breath before: sparks rush in to the caster's chest
	if t < CLAP and R.chance(60.0 * dt):
		var a := R.range(0.0, TAU)
		var d := R.range(16.0, 30.0)
		var T := R.range(0.07, 0.1)
		var v := (d * 3.0) / (exp(3.0 * T) - 1.0)
		ps.spawn(P.STREAK, cos(a) * d, CY + sin(a) * d * 0.8, -cos(a) * v, -sin(a) * v * 0.8, T, C[6] if R.chance(0.5) else C[5])
	if t >= CLAP and not clapped:
		clapped = true
		lights.add(0.0, CY - 10.0, 100.0, C[4], 0.65, 0.45)
		lights.add(0.0, CY, 26.0, WHITE, 0.5, 0.07)
		for i in 64:
			var a := R.range(0.0, TAU)
			var sp := R.range(170.0, 380.0) * (0.5 if sin(a) > 0.4 else 1.0)
			ps.spawn(P.SPARK, cos(a) * 6.0, CY + sin(a) * 6.0, cos(a) * sp, sin(a) * sp - 40.0, R.range(0.2, 0.55))
		for i in 8:
			ps.spawn(P.SMOKE, R.range(-8.0, 8.0), CY + R.range(-6.0, 6.0), R.range(-25.0, 25.0), -R.range(10.0, 30.0), R.range(0.8, 1.3), Px.mix(ASH, C[4], 0.3), R.range(4.0, 7.0), R.range(0.05, 0.2))
	for i in bolts.size():
		var b: Dictionary = bolts[i]
		if b.down and not landed[i] and t >= b.t0:
			landed[i] = true
			lights.add(b.x1, -4.0, 46.0, C[4], 0.7, 0.25)
			for j in 12:
				var a := -PI / 2.0 + R.range(-1.2, 1.2)
				var sp := R.range(70.0, 240.0)
				ps.spawn(P.SPARK, b.x1, -1.0, cos(a) * sp, sin(a) * sp, R.range(0.2, 0.5))
			for j in 5:
				hot.spawn(P.SPARK, b.x1 + R.range(-2.0, 2.0), -1.0, R.range(-80.0, 80.0), -R.range(60.0, 180.0), R.range(0.4, 0.8))
	# the ring tears the floor up as it passes: dust rolling out, grit tossed
	var fr := front(t)
	if t > CLAP and t < CLAP + 0.5:
		for s in [-1, 1]:
			if R.chance(70.0 * dt):
				ps.spawn(P.SMOKE, s * fr + R.range(-3.0, 3.0), -R.range(1.0, 4.0), s * R.range(10.0, 40.0), -R.range(5.0, 20.0), R.range(0.6, 1.1), DUST, R.range(3.0, 6.0) * (1.0 - 0.4 * (fr / REACH)), 0.0, PF.BIG)
			if R.chance(50.0 * dt):
				ps.spawn(P.GRIT, s * fr, -1.0, s * R.range(10.0, 60.0), -R.range(60.0, 180.0), R.range(0.8, 1.3), R.pick(STONE), 2.0 if R.chance(0.3) else 1.0)
	ps.update(dt)
	hot.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	# scorch where the bolts struck, and the far half of the shock ring
	for b: Dictionary in bolts:
		if b.down and t >= b.t0:
			Lib.scorch(p, b.x1, 0.0, 9.0, pow(Px.clamp(1.0 - (t - b.t0) / 1.1), 1.3), 1.0 - Px.smooth(1.4, 1.85, t))
	var u := (t - CLAP) / 0.5
	if u > 0.0 and u < 1.0:
		Px.band(p, 0.0, 0.5, front(t), 0.18, maxf(2.0, 16.0 * (1.0 - u)), 1.25 - u, [C[1], C[2], C[4], C[6]], func(g): return sin(g) < 0.0, u < 0.15)
	ps.draw(p, "back")
	hot.draw(p, "back")


func draw(p: Px.Painter) -> void:
	var f := floori(t * 30.0 + 1e-4)
	var u := (t - CLAP) / 0.5
	var A: Dictionary = o.actor
	# the flash: the caster lit white for a frame, a flare, a core
	var a := t - CLAP
	if a >= 0.0 and a < 0.07:
		p.mask(A.mask, A.x, A.y, WHITE if a < 0.035 else C[6])
	if a >= 0.0 and a < 0.2:
		var q := a / 0.2
		Px.flare(p, 0.0, CY, 44.0 * pow(1.0 - q, 1.4), 1.0 - q, C)
		if q < 0.35:
			p.circle(0.0, CY, 10.0 * (1.0 - q * 2.0) + 2.0, WHITE)
		p.glow(0.0, CY, 44.0, C[5], 0.32 * (1.0 - q))
	# the bolts: struck, flickering, re-struck every other frame
	for i in bolts.size():
		var b: Dictionary = bolts[i]
		var ba := floori((t - b.t0) * 30.0 + 1e-4)
		if t < b.t0 or ba >= BK.size():
			continue
		var r := Px.rng(o.seed, 3, i, ba >> 1)
		Lib.stroke(p, Lib.zigzag(r, 0.0, CY, b.x1, b.y1, 0.25, 0.5 if b.down else 0.8), BK[ba], C, 1.0 if ba == 0 else 0.8, {"hero": ba == 0})
		if b.down:
			p.circle(b.x1, -1.0, 3.0 * BK[ba] + 1.0, C[5])
			p.px(b.x1, -1.0, WHITE)
			p.glow(b.x1, -3.0, 20.0, C[5], 0.5 * BK[ba])
		elif ba < 2:
			Px.sparkle(p, b.x1, b.y1, 4.0, C[6], C[4], 0.4)
	# the shock: the near half of the floor ring, and a ring in the air that bursts out from the clap
	if u > 0.0 and u < 1.0:
		Px.band(p, 0.0, 0.5, front(t), 0.18, maxf(2.0, 16.0 * (1.0 - u)), 1.25 - u, [C[1], C[2], C[4], C[6]], func(g): return sin(g) >= 0.0, u < 0.15)
		for s in [-1, 1]:
			p.glow(s * front(t), -3.0, 28.0, C[4], 0.45 * (1.0 - u))
		var ua := (t - CLAP) / 0.26
		var ra := 8.0 + 60.0 * Px.Ease.outCubic(ua)
		if ua < 1.0:
			p.ring(0.0, CY, ra, maxf(1.0, 2.0 * (1.0 - ua)), C[5] if ua < 0.25 else (C[4] if ua < 0.6 else C[3]), func(v, g): return 0.0 if CY + sin(g) * ra > -1.0 else 0.85 - 0.85 * ua)
	# the hum after: small arcs crackle round the caster as the charge bleeds away
	if a > 0.2 and a < 0.9:
		var r := Px.rng(o.seed, 9, f)
		var k := 1.0 - (a - 0.2) / 0.7
		if r.next() < 0.8:
			var x0 := r.range(-14.0, 14.0)
			var y0 := r.range(-34.0, -4.0)
			var b := r.range(0.0, TAU)
			var l := r.range(6.0, 13.0)
			Lib.crackle(p, Lib.zigzag(r, x0, y0, x0 + cos(b) * l, y0 + sin(b) * l, 0.4, 0.3), 0.85 * k + 0.1, C, 0.35)
	ps.draw(p, "front")
	hot.draw(p, "front")
	lights.draw(p)
