# The release (a white disc, a cross, two rings, a big light and a spray of motes and stars) is adapted from
# Sprite Fusion's open-source energy charge (https://www.spritefusion.com/pixel-art-vfx/energy),
# MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/arcane/mana-burst.js@85b6735b58c0b932db53a20953879ea58d1ea26e
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE

const CY := -28.0
const GATHER := 0.22
const N := 9

static var meta := {
	"name": "Mana burst",
	"desc": "Energy rushes into a point and blows out in a white flash and rings, flinging glowing runes that flare and pop into sparks one after another.",
	"tags": ["arcane", "burst", "mana", "rune", "nova", "magic", "ground", "one-shot"],
	"size": [208, 150],
	"origin": [104, 124],
	"duration": 1.8,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": Px.PAL.arcane, "seed": 9},
}


var C: Array
var R: Px.Rng
var ps: Px.Particles
var lights: Px.Lights
var runes: Array
var pops := []
var t := 0.0
var released := false


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	R = Px.Rng.new(o.seed)
	ps = Px.Particles.new({"rng": R, "ground": func(): return 0.0, "sparks": [WHITE, C[6], C[5], C[4]]})
	lights = Px.Lights.new()
	# the runes: flung out round the burst, slowing hard, bobbing while they burn, each popping in its turn
	runes = Px.arr(N, func(i):
		var a := (float(i) / N) * TAU + R.range(-0.25, 0.25) - PI / 2.0
		var sp := R.range(150.0, 210.0)
		# thrown less far downward, so the low ones stay clear of the floor
		return {"g": i, "x": 0.0, "y": CY, "vx": cos(a) * sp, "vy": sin(a) * sp * (0.42 if sin(a) > 0.0 else 0.85), "pop": GATHER + 0.42 + i * 0.065 + R.range(0.0, 0.05), "popped": false, "ph": R.range(0.0, TAU)})


func update(dt: float) -> void:
	t += dt
	if t < GATHER - 0.03:
		# the gather: streaks rush in from all round
		for i in 2:
			var a := R.range(0.0, TAU)
			var D := R.range(24.0, 52.0)
			var T := R.range(0.12, 0.18)
			var v := (D * 3.0) / (exp(3.0 * T) - 1.0)
			var x := cos(a) * D
			var y := minf(-2.0, CY + sin(a) * D * 0.85)
			var l := Px.hypot(x, y - CY)
			if not l:
				l = 1.0
			ps.spawn(P.STREAK, x, y, (-x / l) * v, ((CY - y) / l) * v, T, C[6] if R.chance(0.5) else C[5])
	if t >= GATHER and not released:
		released = true
		lights.add(0.0, CY - 12.0, 96.0, C[5], 1.0, 0.5)
		lights.add(0.0, CY, 40.0, WHITE, 0.9, 0.1)
		# a spray of motes and stars, thrown less hard at the floor
		for i in 96:
			var a := R.range(0.0, TAU)
			var sp := R.range(100.0, 250.0)
			var dn := 0.45 if sin(a) > 0.0 else 1.0
			ps.spawn(P.MOTE if R.chance(0.65) else P.STAR, 0.0, CY, cos(a) * sp, sin(a) * sp * dn, R.range(0.25, 0.55), R.pick([WHITE, C[6], C[5]]), R.range(0.8, 1.8))
		for i in 20:
			var a := R.range(0.0, TAU)
			var sp := R.range(130.0, 280.0)
			ps.spawn(P.SPARK, 0.0, CY, cos(a) * sp, sin(a) * sp, R.range(0.2, 0.45))
	if released:
		for r: Dictionary in runes:
			if r.popped:
				continue
			r.vx -= r.vx * 4.2 * dt
			r.vy -= r.vy * 4.2 * dt + 8.0 * dt
			r.x += r.vx * dt
			r.y += r.vy * dt
			if R.chance(0.35):
				ps.spawn(P.MOTE, r.x + R.range(-1.5, 1.5), r.y, r.vx * 0.2 + R.range(-10.0, 10.0), r.vy * 0.2 - R.range(5.0, 25.0), R.range(0.2, 0.4), C[5], 0.5)
			if t >= r.pop:
				r.popped = true
				pops.append({"t": t, "x": r.x, "y": r.y})
				lights.add(r.x, r.y, 34.0, C[5], 0.9, 0.22)
				lights.add(r.x, r.y, 12.0, WHITE, 0.8, 0.06)
				for i in 9:
					var a := R.range(0.0, TAU)
					var sp := R.range(70.0, 200.0)
					ps.spawn(P.SPARK, r.x, r.y, cos(a) * sp, sin(a) * sp - 40.0, R.range(0.15, 0.4))
				for i in 5:
					var a := R.range(0.0, TAU)
					var sp := R.range(20.0, 80.0)
					ps.spawn(P.STAR if i % 2 else P.MOTE, r.x, r.y, cos(a) * sp, sin(a) * sp - 20.0, R.range(0.3, 0.6), R.pick([WHITE, C[6]]), R.range(0.8, 1.6))
	ps.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	# the floor beneath catches the burst
	var k := 0.4 * (t / GATHER) if t < GATHER else maxf(0.0, 1.0 - (t - GATHER) / 1.1)
	if k > 0.0:
		p.glow(0.0, -1.0, 50.0, C[4], 0.3 * k)


func draw(p: Px.Painter) -> void:
	if t < GATHER:
		# the point it gathers into: a swelling ball with a white heart
		var k := t / GATHER
		var r := 1.0 + 3.5 * k * k
		p.circle(0.0, CY, r + 1.2, C[4])
		p.circle(0.0, CY, r, C[6])
		p.circle(0.0, CY, r * 0.5, WHITE)
		p.glow(0.0, CY, 10.0 + 20.0 * k, C[5], 0.4 + 0.4 * k)
		var q := Px.clamp((t - GATHER * 0.35) / (GATHER * 0.65))
		if q > 0.0 and q < 1.0:
			p.ring(0.0, CY, r + 2.0 + 16.0 * (1.0 - Px.Ease.outCubic(q)), 1.0, WHITE if q > 0.6 else C[6], 1.0 - q * 0.5)
	else:
		var q := (t - GATHER) / 0.6
		if q < 1.0:
			var e := Px.Ease.outCubic(q)
			if q < 0.12:
				p.circle(0.0, CY, 12.0 * (1.0 - q / 0.12) + 2.0, C[5])
				p.circle(0.0, CY, 12.0 * (1.0 - q / 0.12), WHITE)
			if q < 0.32:
				Px.flare(p, 0.0, CY, 30.0 * (1.0 - q / 0.32) + 4.0, 1.0 - q / 0.32, C)
			# the rings, cut off where they meet the floor
			p.ring(0.0, CY, 4.0 + 62.0 * e, maxf(1.0, 5.0 * (1.0 - q)), WHITE if q < 0.2 else C[6], func(_v: float, ang: float) -> float: return 0.0 if CY + sin(ang) * (4.0 + 62.0 * e) > 0.0 else 1.2 - q)
			p.ring(0.0, CY, 2.0 + 38.0 * Px.Ease.outCubic(minf(1.0, q * 1.4)), maxf(1.0, 2.0 * (1.0 - q)), C[5], func(_v: float, ang: float) -> float: return 0.0 if CY + sin(ang) * 40.0 > 0.0 else 1.0 - q)
			p.glow(0.0, CY, 60.0 * (0.4 + 0.6 * e), C[5], 0.9 * (1.0 - q))
	# the runes: white as they fly, settling to lilac, flaring white just before they pop
	for r: Dictionary in runes:
		if not released or r.popped:
			continue
		var left: float = r.pop - t
		var hot := t - GATHER < 0.08 or left < 0.06
		var bob: float = sin(t * 9.0 + r.ph) * 0.6
		Lib.sigil(p, r.g, r.x, r.y + bob, WHITE if hot else C[6], 1.0, C[4] if hot else C[3])
		p.glow(r.x, r.y + bob, 10.0, C[5], 0.7 if hot else 0.35)
		if left < 0.06:
			Px.sparkle(p, r.x, r.y + bob, 3.0 + 4.0 * (1.0 - left / 0.06), C[6], C[5], 0.5)
	# each pop: a small flare and a ring
	for q: Dictionary in pops:
		var k: float = (t - q.t) / 0.32
		if k >= 1.0:
			continue
		if k < 0.35:
			Px.flare(p, q.x, q.y, 11.0 * (1.0 - k / 0.35) + 2.0, 1.0 - k / 0.35, C)
		p.ring(q.x, q.y, 2.0 + 11.0 * Px.Ease.outCubic(k), maxf(1.0, 2.0 * (1.0 - k)), WHITE if k < 0.3 else C[6], 1.15 - k)
	ps.draw(p)
	lights.draw(p)
