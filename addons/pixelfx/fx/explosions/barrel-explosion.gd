# The blast (fire puffs that cool into smoke, sparks, embers, burning brands that land and keep burning, grit, scorch,
# rings) is adapted from Sprite Fusion's open-source explosion (https://www.spritefusion.com/pixel-art-vfx/explosion),
# MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/explosions/barrel-explosion.js@626b63b7e7ea1969801787b5a96aa53eb7c6d742
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const PF := Px.PF
const B := Px.B
const WHITE := Px.WHITE

static var meta := {
	"name": "Barrel explosion",
	"desc": "An explosive barrel shudders, its lid bulging and spitting flame, then blows: a fireball column, staves and the lid flying, burning fuel splashed over the floor.",
	"tags": ["explosion", "barrel", "fire", "smoke", "debris", "ground", "one-shot"],
	"size": [300, 240],
	"origin": [150, 204],
	"duration": 5.2,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"options": {
		"palette": ["#4a1712", "#c9281f", "#f2561d", "#ff8a2a", "#ffc23d", "#ffe26b", "#fff3a6", "#ffffff"],
		"barrel": ["#1c0a0e", "#4a1218", "#7c1a1e", "#b02a26", "#d8483a", "#f08a70"],
		"seed": 8,
	},
}

const BLOW := 0.8
const BW := 8.0
const BH := 22.0


var F: Array
var FR: Array
var HR: Array
var C: Array
var R: Px.Rng
var W: int
var H: int
var OX: int
var OY: int
var X0: float
var X1: float
var Y0: float
var Y1: float
var blazes: Px.Blazes
var ps: Px.Particles
var lights: Px.Lights
var staves: Px.Bits
var OIL: int
var SOOT: int
var lid: Dictionary
# the fuel splashed over the floor: a puddle and the spots that keep burning in it
var pools := []
var t := 0.0
var blown := false


func create(o: Dictionary) -> void:
	F = Px.fit(o.palette, 8)
	FR = Lib.fireRamp(F)
	HR = Lib.heatRamp(FR)
	C = Px.fit(o.barrel, 6)
	R = Px.Rng.new(o.seed)
	var floor_ := func(): return 0.0
	W = meta.size[0]
	H = meta.size[1]
	OX = meta.origin[0]
	OY = meta.origin[1]
	X0 = -OX + 3
	X1 = W - OX - 3
	Y0 = -OY + 3
	Y1 = H - OY - 3
	ps = Px.Particles.new({"rng": R, "ground": floor_, "sparks": [F[6], F[5], F[3], F[2]], "onLand": func(x, y): blazes.add(x, y - 0.25, R.range(1.2, 2.2), R.range(0.6, 1.0))})
	blazes = Px.Blazes.new(ps)
	lights = Px.Lights.new()
	staves = Px.Bits.new({"ground": floor_})
	OIL = Px.hex("#221a22")
	SOOT = Px.hex("#1f1a24")
	lid = {"x": 0.0, "y": -BH, "vx": 0.0, "vy": 0.0, "a": 0.0, "va": 0.0, "on": false, "rest": false}


func blow() -> void:
	blown = true
	var y := -BH * 0.5
	lights.add(0.0, y - 20.0, 90.0, Px.mix(F[3], F[6], 0.45), 0.85, 0.9)
	lights.add(0.0, y, 44.0, WHITE, 0.7, 0.09)
	# the fireball: bursting out, then a column of fire driven up out of the drum
	for i in 5:
		ps.spawn(P.FIRE, R.range(-3.0, 3.0), y + R.range(-3.0, 3.0), R.range(-20.0, 20.0), R.range(-40.0, -10.0), R.range(0.18, 0.28), 0, R.range(9.0, 12.0))
	for i in 30:
		var a := R.range(-PI - 0.15, 0.15)
		var d := R.range(0.0, 8.0)
		var sp := R.range(50.0, 190.0)
		ps.spawn(P.FIRE, cos(a) * d, y + sin(a) * d, cos(a) * sp, sin(a) * sp * 0.8 - 40.0, R.range(0.55, 1.05), 0, R.range(5.0, 10.0), 0.0, (PF.SMOKES | PF.BIG) if R.chance(0.5) else 0)
	for i in 12:
		ps.spawn(P.FIRE, R.range(-6.0, 6.0), y - R.range(0.0, 10.0), R.range(-14.0, 14.0), -R.range(170.0, 300.0), R.range(0.7, 1.15), 0, R.range(6.0, 10.0), R.range(0.0, 0.12), (PF.SMOKES | PF.BIG) if R.chance(0.7) else 0)
	# oily black smoke
	for i in 12:
		var a := R.range(-PI, 0.0)
		var d := R.range(4.0, 16.0)
		ps.spawn(P.SMOKE, cos(a) * d, y + sin(a) * d, cos(a) * 30.0, -R.range(30.0, 90.0), R.range(1.6, 2.6), SOOT, R.range(8.0, 13.0), R.range(0.1, 0.4), PF.BIG)
	for i in 90:
		var a := R.range(0.0, TAU)
		var sp := R.range(160.0, 400.0)
		ps.spawn(P.SPARK, 0.0, y, cos(a) * sp, sin(a) * sp - 70.0, R.range(0.2, 0.6))
	for i in 40:
		var a := R.range(0.0, TAU)
		var sp := R.range(30.0, 140.0)
		ps.spawn(P.EMBER, cos(a) * 8.0, y + sin(a) * 8.0, cos(a) * sp, sin(a) * sp - 70.0, R.range(1.2, 2.6), F[3])
	# burning fuel flung out in arcs: it lands and keeps burning
	for i in 14:
		var a := -PI / 2.0 + R.range(-1.2, 1.2)
		var sp := R.range(120.0, 300.0)
		ps.spawn(P.BRAND, R.range(-4.0, 4.0), y, cos(a) * sp, sin(a) * sp, R.range(0.8, 1.4))
	# the staves: the drum's plates torn off and thrown out, tumbling
	for i in 9:
		var side := 1.0 if i % 2 else -1.0
		var a := -PI / 2.0 + side * R.range(0.25, 1.15)
		var sp := R.range(170.0, 330.0)
		staves.add({"kind": B.CHUNK, "x": side * R.range(2.0, 6.0), "y": -R.range(4.0, BH - 4.0), "vx": cos(a) * sp, "vy": sin(a) * sp, "g": 1.0, "drag": 0.5, "bounce": 0.35, "life": R.range(3.0, 3.8), "a": R.range(0.0, TAU), "va": R.range(-16.0, 16.0), "s": R.range(9.0, 13.0), "heat": R.range(0.4, 0.9)})
	# the lid, flung high and spinning
	lid.merge({"on": true, "x": 0.0, "y": -BH, "vx": R.range(-40.0, 40.0), "vy": -R.range(430.0, 480.0), "a": 0.0, "va": R.sign() * R.range(10.0, 14.0)}, true)
	# the fuel on the floor, and the floor's own dust and grit
	for i in 7:
		var x := R.range(-34.0, 34.0)
		pools.append({"x": x, "w": R.range(5.0, 10.0)})
		blazes.add(x, -0.25, R.range(2.2, 3.0), R.range(0.8, 1.3))
	for i in 12:
		var s := R.sign()
		ps.spawn(P.SMOKE, s * R.range(0.0, 10.0), -R.range(1.0, 4.0), s * R.range(80.0, 220.0), -R.range(2.0, 12.0), R.range(1.1, 1.8), Px.hex("#7d7280"), R.range(6.0, 9.0), R.range(0.0, 0.05), PF.BIG)
	for i in 60:
		var u := R.range(-1.0, 1.0)
		var a := -PI / 2.0 + u * 0.7
		var sp := R.range(120.0, 330.0) * (1.0 - 0.4 * absf(u))
		ps.spawn(P.GRIT, u * 6.0, -1.0, cos(a) * sp, sin(a) * sp, R.range(1.1, 1.9), R.pick([Px.hex("#5a4f6b"), Px.hex("#3e3650"), Px.hex("#776c88")]), 2.0 if R.chance(0.4) else 1.0)


func update(dt: float) -> void:
	t += dt
	if not blown:
		# the drum strains: flame and smoke spitting from the seam under the lid, quicker as it goes
		var k := t / BLOW
		if R.chance((6.0 + 30.0 * k * k) * dt):
			var s := R.sign()
			ps.spawn(P.FIRE, s * R.range(4.0, 7.0), -BH + 1.0, s * R.range(20.0, 60.0), -R.range(20.0, 60.0), R.range(0.15, 0.3), 0, R.range(1.5, 3.0))
			ps.spawn(P.SPARK, s * 6.0, -BH + 1.0, s * R.range(40.0, 140.0), -R.range(20.0, 120.0), R.range(0.1, 0.25))
		if R.chance(10.0 * dt):
			ps.spawn(P.SMOKE, R.range(-5.0, 5.0), -BH, R.range(-8.0, 8.0), -R.range(15.0, 35.0), R.range(0.8, 1.3), 0, R.range(2.5, 4.0))
		if t >= BLOW:
			blow()
	if lid.on and not lid.rest:
		lid.vy += 950.0 * dt
		lid.vx -= lid.vx * 0.4 * dt
		lid.x += lid.vx * dt
		lid.y += lid.vy * dt
		lid.a += lid.va * dt
		if lid.y >= -1.0 and lid.vy > 0.0:
			# a clank: sparks and dust where it lands, then it bounces flat and settles
			for i in 6:
				ps.spawn(P.SPARK, lid.x, -1.0, R.range(-90.0, 90.0), -R.range(40.0, 140.0), R.range(0.1, 0.25))
			for i in 5:
				ps.spawn(P.DUST, lid.x + R.range(-4.0, 4.0), -0.5, R.sign() * R.range(15.0, 60.0), -R.range(4.0, 18.0), R.range(0.35, 0.7), Px.hex("#7d7280"), R.range(1.8, 3.0))
			lid.y = -1.0
			if lid.vy > 160.0:
				lid.vy *= -0.3
				lid.vx *= 0.5
				lid.va *= 0.5
			else:
				lid.rest = true
				lid.a = PI / 2.0
	staves.update(dt)
	var i := staves.list.size() - 1
	while i >= 0:
		var b: Dictionary = staves.list[i]
		if b.x < X0 + 8.0 or b.x > X1 - 8.0:
			staves.list.remove_at(i)
		elif b.heat > 0.0:
			b.heat = maxf(0.0, b.heat - dt * 0.35)
		i -= 1
	blazes.update(dt)
	ps.update(dt)
	Lib.cull(ps, X0, Y0, X1, Y1)
	Lib.fadeEdges(ps, X0, X1, 24.0, Y1)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	if blown:
		var u := t - BLOW
		var out := 1.0 - Px.smooth(meta.duration - BLOW - 1.0, meta.duration - BLOW - 0.2, u)
		Lib.scorch(p, HR, u, 30.0, 2.2, out, 3.0)
		# the spilled fuel: a dark slick on the floor, lit by its own fire, shrinking as it burns off
		var left := 1.0 - Px.smooth(1.6, 3.4, u)
		if left > 0.0:
			for q in pools:
				for x in range(floori(-q.w * left), ceili(q.w * left) + 1):
					var e: float = absf(x) / (q.w * left + 0.01)
					p.dot(q.x + x, 1.0, F[4] if Px.rand(floorf(q.x + x), floorf(t * 12.0)) < 0.25 else OIL, out * (1.0 if e < 0.8 else 0.6))
					if e < 0.6:
						p.dot(q.x + x, 2.0, OIL, out * 0.8)
		var k := u / 0.45
		if k < 1.0:
			Px.band(p, 0.0, 0.5, 100.0 * Px.Ease.outCubic(k), 0.16, maxf(1.0, 4.5 * (1.0 - k)), 1.15 - k, [Px.hex("#4a3f69"), Px.hex("#6e6390"), F[3], F[6]], func(g): return sin(g) < 0.0)
	Lib.drawPs(p, ps, "back", FR)
	blazes.drawBack(p)


func draw(p: Px.Painter) -> void:
	if not blown:
		# the barrel, shaking harder, its lid bulging
		var k := t / BLOW
		var jx := sin(t * 70.0) * k * k * 1.4
		var jy := absf(sin(t * 53.0)) * k * k * 0.8
		drawBarrel(p, C, jx, -jy, k)
		p.glow(0.0, -BH, 10.0 + 8.0 * k, F[4], 0.25 + 0.35 * k * k * (0.6 + 0.4 * sin(t * 40.0)))
	else:
		var u := t - BLOW
		var k := u / 0.45
		if k < 1.0:
			Px.band(p, 0.0, 0.5, 100.0 * Px.Ease.outCubic(k), 0.16, maxf(1.0, 4.5 * (1.0 - k)), 1.15 - k, [Px.hex("#4a3f69"), Px.hex("#6e6390"), F[3], F[6]], func(g): return sin(g) >= 0.0)
	Lib.drawPs(p, ps, "front", FR)
	for b in staves.list:
		stave(p, b, C, FR)
	if lid.on:
		drawLid(p, C, lid, minf(1.0, (meta.duration - t) / 0.4))
	if blown:
		var u := t - BLOW
		if u < 0.08:
			var k2 := 1.0 - u / 0.08
			var r := 18.0 * (0.85 + 0.15 * k2)
			var y := -BH * 0.5
			p.circle(0.0, y, r + 1.4, F[2])
			p.circle(0.0, y, r, F[6] if k2 > 0.45 else F[5])
			p.circle(0.0, y, r * 0.6, WHITE if k2 > 0.45 else F[6])
		if u < 0.22:
			Px.flare(p, 0.0, -BH * 0.5, 54.0 * pow(1.0 - u / 0.22, 1.4), 1.0 - u / 0.22, F)
		# the burning fuel lights the floor
		Lib.pool(p, 0.0, 1.0, 90.0, 14.0, F[3], 0.5 * maxf(0.0, 1.0 - u / 0.7) + 0.22 * (1.0 - Px.smooth(1.6, 3.4, u)))
	lights.draw(p)


# a steel drum standing on the floor at x: red, two ribs, a lit left side, a dark right side, an outline, a pale
# band; the lid bulges with k
static func drawBarrel(p: Px.Painter, C: Array, x: float, y: float, k: float) -> void:
	var bulge := Px.round(k * k * 2.0)
	p.shade(x - BW - 1.0, y - BH - 3.0, x + BW + 1.0, y + 0.5, func(px: float, py: float):
		var dx := (px - x) / BW
		var v := (y - py) / BH  # dx -1..1 across, v 0 at the floor .. 1 at the top
		if absf(dx) > 1.1 or v < 0.0 or v > 1.05:
			return null
		var edge := absf(dx) > 0.92 or v > 0.97 or v < 0.04
		if edge:
			return Lib.OUTLINE
		var rib := absf(v - 0.33) < 0.035 or absf(v - 0.67) < 0.035
		var ribLit := absf(v - 0.31) < 0.03 or absf(v - 0.65) < 0.03
		var band := v > 0.44 and v < 0.56
		var lit := -dx  # light from the left
		var i := 5 if lit > 0.55 else (4 if lit > 0.15 else (3 if lit > -0.35 else (2 if lit > -0.75 else 1)))
		if band:
			return Px.hex("#e8d8b0") if lit > 0.3 else (Px.hex("#b8a888") if lit > -0.4 else Px.hex("#6e6050"))
		if rib:
			i = maxi(1, i - 2)
		elif ribLit:
			i = mini(5, i + 1)
		return C[i])
	# the lid: a dark ellipse with a lit rim, pushed up as the drum swells
	p.ellipse(x, y - BH - bulge * 0.5, BW - 0.5, 2.2 + bulge * 0.4, func(d: float, a: float): return (C[4] if sin(a) < 0.0 else C[2]) if d > 0.7 else C[1])


# a stave: a curved plate torn from the drum, its painted face and its dark inside showing as it turns; hot edges glow
static func stave(p: Px.Painter, b: Dictionary, C: Array, FR: Array) -> void:
	var fade := minf(1.0, b.life / 0.5)
	var ca: float = cos(b.a)
	var sa: float = sin(b.a)
	var L: float = b.s
	var face: bool = cos(b.a * 1.7) > 0.0
	var d := -L / 2.0
	while d <= L / 2.0:
		var bow := (1.0 - pow(2.0 * d / L, 2.0)) * 1.2
		var x: float = b.x + ca * d - sa * bow
		var y: float = b.y + sa * d + ca * bow
		var hot: bool = b.heat > 0.3 and absf(d) > L / 2.0 - 1.0
		p.dot(x + sa, y - ca, Lib.OUTLINE, fade)
		p.dot(x, y, (FR[3 if b.heat > 0.6 else 5]) if hot else (C[4] if face else C[1]), fade)
		p.dot(x - sa, y + ca, C[2] if face else Lib.OUTLINE, fade)
		d += 0.5
	if b.heat > 0.3:
		p.glow(b.x, b.y, 6.0, FR[4], 0.25 * b.heat * fade)


# the lid: a disc turning as it flies (an ellipse whose width follows its spin), lying flat once it lands
static func drawLid(p: Px.Painter, C: Array, lid_: Dictionary, a: float) -> void:
	var w := maxf(0.8, absf(cos(lid_.a)) * 7.5)
	var h := maxf(1.2, absf(sin(lid_.a)) * 7.5)
	var rx := 7.5 if lid_.rest else w
	var ry := 1.6 if lid_.rest else h
	p.ellipse(lid_.x, lid_.y - (0.5 if lid_.rest else 0.0), rx + 0.8, ry + 0.8, Lib.OUTLINE, a)
	p.ellipse(lid_.x, lid_.y - (0.5 if lid_.rest else 0.0), rx, ry, func(d: float, an: float): return (C[4] if sin(an) < 0.0 else C[2]) if d > 0.65 else C[3], a)
