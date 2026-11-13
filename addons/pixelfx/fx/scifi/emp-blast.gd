# The pop (a white disc, a fast ring, sparks bursting, short arcs crawling the area as it dies away) follows
# Sprite Fusion's open-source lightning impact (https://www.spritefusion.com/pixel-art-vfx/lightning),
# MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/scifi/emp-blast.js@77abd6a70a1981082d5bb7da665563fae4756128
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "EMP blast",
	"desc": "A disc charge ticks, pops white, and a bubble of rolling scanlines swells out with arcs crawling its skin; it strobes, tears and shorts out into falling dead pixels.",
	"tags": ["scifi", "emp", "pulse", "shockwave", "electric", "grenade", "glitch", "one-shot"],
	"size": [152, 116],
	"origin": [76, 84],
	"duration": 3.2,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"options": {
		"palette": ["#0d0820", "#1c1658", "#2d2aa0", "#3f55e8", "#5a8eff", "#9cc4ff", "#dceaff", "#ffffff"],
		"fringe": "#ff5ad8",
		"radius": 56,
		"seed": 33,
	},
}

# the beats: it ticks, pops, the bubble swells and holds, strobes, breaks
const POP := 0.42
const GROW := 0.32
const STROBE := 1.25
const BREAK := 1.58


var C: Array
var F: int
var RM: float
var R: Px.Rng
var seed: float
var ps: Px.Particles
var lights: Px.Lights
var arcs: Array = []
var dead: Array = []
var t := 0.0
var popped := false
var broke := false
var nextArc := 0.0
var star: Array = []
var starAt := -1


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	F = Px.hex(o.fringe)
	RM = o.radius
	R = Px.Rng.new(o.seed)
	seed = o.seed
	ps = Px.Particles.new({"rng": R, "ground": func(): return 0.0, "sparks": [WHITE, C[6], C[5], C[4]], "haze": C[5]})
	lights = Px.Lights.new()


func radius() -> float:
	return 0.0 if t < POP else RM * (0.12 + 0.88 * Px.Ease.outExpo(Px.clamp((t - POP) / GROW))) * (1.0 + 0.04 * Px.clamp((t - POP - GROW) / 0.8))


# which frames the bubble cuts out in while it fails
func off() -> bool:
	return t > STROBE and t < BREAK and Px.rand(seed, floori(t * 30.0)) < 0.2 + 0.5 * ((t - STROBE) / (BREAK - STROBE))


# the charge: a mote of light just off the floor, swelling, blinking faster, crackling
func charge(p: Px.Painter) -> void:
	if t >= POP:
		return
	var k := t / POP
	var r := 1.0 + 3.2 * k * k
	var tick := sin(TAU * (2.0 * t + 10.0 * t * t)) > 0.0
	p.circle(0.0, -7.0, r + 1.0, C[4])
	p.circle(0.0, -7.0, r, WHITE if tick else C[6])
	var f := floori(t * 30.0)
	var rr := Px.Rng.new(seed * 97.0 + f)
	for i in 1 + floori(k * 3.0):
		var a := rr.range(0.0, TAU)
		var l := r + 2.0 + rr.range(2.0, 6.0) * k
		Lib.strokeArc(p, Px.bolt(rr, cos(a) * r, -7.0 + sin(a) * r, cos(a) * l, -7.0 + sin(a) * l, {"jag": 0.4, "depth": 2}), [C[2], C[5], C[4]], 0.7, 0.5)
	p.glow(0.0, -7.0, 8.0 + 16.0 * k, C[4], 0.4 + 0.5 * k * (1.0 if tick else 0.6))


# the bubble: thin glass, brighter toward its rim, interference lines rolling down it, tears across it
func bubble(p: Px.Painter, near: bool) -> void:
	var r := radius()
	if r <= 1.0 or t >= BREAK or off():
		return
	var age := t - POP
	var slot := floori(t * 30.0)
	var roll := age * 40.0
	var ry := r * 0.16
	# the tears: a few rows this frame shifted sideways and burning bright
	var tears := {}
	for i in 2 + (4 if t > STROBE else 0):
		tears[floori(-Px.rand(seed, slot, i) * r)] = (-1 if Px.rand(seed, slot, i, 1) < 0.5 else 1) * (2 + floori(Px.rand(seed, slot, i, 2) * 4.0))
	for y in range(floori(-r), ceili(ry) + 1):
		var shift: int = tears.get(y, 0)
		for x in range(floori(-r), ceili(r) + 1):
			var sx := x - shift
			var d := Px.hypot(sx + 0.5, y + 0.5 if y < 0 else 0.0) / r
			# a split edge just outside the rim, as if the signal's colors had slipped
			if d > 1.0:
				if near and y < 0 and d < 1.0 + 1.4 / r and (x + y) % 2 == 0:
					p.px(x, y, F)
				continue
			# the dome above the floor, the floor disc below it only as its rim
			if y >= 0:
				var e := Px.hypot((sx + 0.5) / r, (y + 0.5) / ry)
				if e > 1.0 or e < 0.92 or (y > 0) != near:
					continue
				p.px(x, y, C[6] if e > 0.97 else C[4])
				continue
			if not near:
				continue
			var rim := pow(d, 6.0)
			var line := fmod(fmod(y - roll, 4.0) + 4.0, 4.0) < 1.0
			var band := fmod(fmod(y - roll * 0.5, 22.0) + 22.0, 22.0) < 4.0
			if d > 0.965:
				p.px(x, y, WHITE if shift else (WHITE if (-y > r * 0.55 and sx < 0) else C[6]))
			elif d > 0.93:
				p.px(x, y, C[4])
			elif shift:
				p.px(x, y, F if absi(sx) > r * 0.8 else (C[6] if (x & 1) else C[5]))
			else:
				p.blend(x + 0.5, y + 0.5, C[6] if (line and band) else (C[5] if line else (C[4] if band else C[3])), 0.06 + 0.42 * rim + (0.14 + 0.24 * rim if line else 0.0) + (0.16 if band else 0.0))
		if shift and near:
			p.glowLine(-r, y, r, y, 4.0, C[5], 0.3)
	if near:
		var a := 0.15
		while a < PI - 0.1:
			p.glow(cos(a) * r, -sin(a) * r, 8.0, C[4], 0.12)
			a += 0.35
		# junk blocks flicker on inside it
		for i in 3:
			var k := Px.rand(seed, slot, i, 7)
			if k > 0.5:
				continue
			var ja := Px.rand(seed, slot, i, 8) * PI
			var d := Px.rand(seed, slot, i, 9) * r * 0.85
			var bx := Px.round(cos(ja) * d)
			var by := Px.round(-sin(ja) * d)
			p.rect(bx, by, 2.0 + floorf(k * 8.0), 1.0 + floorf(k * 4.0), WHITE if k < 0.2 else C[5])


func update(dt: float) -> void:
	t += dt
	# charging: energy streaks in to the puck
	if t < POP - 0.05 and R.chance(0.6):
		var a := R.range(-PI, 0.0)
		var D := R.range(16.0, 40.0)
		var T := R.range(0.14, 0.22)
		var v := (D * 3.0) / (exp(3.0 * T) - 1.0)
		ps.spawn(P.STREAK, cos(a) * D, -5.0 + sin(a) * D * 0.7, -cos(a) * v, -sin(a) * v * 0.7, T, C[6] if R.chance(0.5) else C[5])
	# the discharge: a star of thick arcs out of the pop, jittering each frame as it shrinks
	var sa := t - POP
	var sf := floori(t * 30.0)
	if sa >= 0.0 and sa < 0.26 and sf != starAt:
		starAt = sf
		var len := Px.Ease.outBack(sa / 0.05, 2.0) if sa < 0.05 else 1.0 - (sa - 0.05) / 0.26
		star = []
		for i in 7:
			var a := -PI + (i / 6.0) * PI + Px.rand(seed, i, 3) * 0.3 - 0.15 + R.range(-0.1, 0.1)
			var L := (20.0 + 16.0 * Px.rand(seed, i, 5)) * maxf(0.15, len)
			star.append(Px.bolt(R, 0.0, -7.0, cos(a) * L, minf(-1.0, -7.0 + sin(a) * L), {"jag": 0.28, "depth": 4}))
	if sa >= 0.26:
		star = []
	if t >= POP and not popped:
		popped = true
		for i in 16:
			var a := R.range(-PI, 0.0)
			var sp := R.range(50.0, 150.0)
			ps.spawn(P.MOTE, 0.0, -7.0, cos(a) * sp, sin(a) * sp, R.range(0.3, 0.6), R.pick([WHITE, C[6], C[5]]), 0.8)
		lights.add(0.0, -20.0, 72.0, C[4], 0.9, 0.5)
		lights.add(0.0, -7.0, 30.0, WHITE, 0.9, 0.12)
		for i in 60:
			var a := R.range(-PI, 0.0)
			var sp := R.range(90.0, 220.0)
			ps.spawn(P.SPARK, 0.0, -7.0, cos(a) * sp, sin(a) * sp, R.range(0.2, 0.6))
		for i in 6:
			ps.spawn(P.SMOKE, R.range(-3.0, 3.0), -4.0, R.range(-12.0, 12.0), -R.range(10.0, 24.0), R.range(1.0, 1.6), Px.hex("#3c3a52"), R.range(2.5, 4.0), R.range(0.05, 0.3))
	# arcs crawl over the bubble's skin, faster as it fails
	if popped and not broke and t >= nextArc:
		nextArc = t + (R.range(0.02, 0.05) if t > STROBE else R.range(0.05, 0.11))
		var r := radius()
		var a0 := R.range(0.1, PI - 0.1)
		var a1 := a0 + R.sign() * R.range(0.25, 0.6)
		var rr := r * R.range(0.92, 1.0)
		var pts := Px.bolt(R, cos(a0) * rr, -sin(a0) * rr, cos(a1) * rr, -maxf(0.05, sin(a1)) * rr, {"jag": 0.3, "depth": 4})
		var life := R.range(0.05, 0.1)
		arcs.append({"t": t, "pts": pts, "life": life})
		if R.chance(0.35):
			ps.spawn(P.SPARK, cos(a1) * rr, -maxf(0.05, sin(a1)) * rr, R.range(-80.0, 80.0), R.range(-90.0, 10.0), R.range(0.15, 0.3))
	if t >= BREAK and not broke:
		broke = true
		# it shorts out: the skin bursts into dead pixels, a last crackle, the charge smokes
		var r := radius()
		lights.add(0.0, -r * 0.4, r * 1.3, C[5], 0.8, 0.3)
		for i in 70:
			var a := R.range(0.05, PI - 0.05)
			var d := r * R.range(0.6, 1.0)
			var vx := cos(a) * R.range(5.0, 25.0)
			var vy := -R.range(0.0, 20.0)
			var life := R.range(0.4, 1.0)
			var s := 2.0 if R.chance(0.3) else 1.0
			var c: int = R.pick([WHITE, C[6], C[5], C[4]])
			var ph := R.range(0.0, 9.0)
			dead.append({"x": cos(a) * d, "y": -sin(a) * d, "vx": vx, "vy": vy, "life": life, "max": 1.0, "s": s, "c": c, "ph": ph})
		for i in 6:
			var a0 := R.range(0.1, PI - 0.1)
			var a1 := a0 + R.range(-0.5, 0.5)
			arcs.append({"t": t, "pts": Px.bolt(R, cos(a0) * r, -sin(a0) * r, cos(a1) * r * 0.6, -maxf(0.05, sin(a1)) * r * 0.6, {"jag": 0.35, "depth": 4}), "life": 0.1})
		for i in 8:
			ps.spawn(P.SMOKE, R.range(-3.0, 3.0), -4.0, R.range(-6.0, 6.0), -R.range(8.0, 18.0), R.range(0.8, 1.2), Px.hex("#2f2c3c"), R.range(2.0, 3.4), R.range(0.0, 0.35))
	# the dead charge fizzes now and then
	if broke and t < meta.duration - 0.8 and R.chance(0.05):
		ps.spawn(P.SPARK, R.range(-3.0, 3.0), -3.0, R.range(-60.0, 60.0), -R.range(40.0, 120.0), R.range(0.15, 0.3))
	var i := arcs.size() - 1
	while i >= 0:
		if t - arcs[i].t > arcs[i].life:
			arcs.remove_at(i)
		i -= 1
	i = dead.size() - 1
	while i >= 0:
		var d: Dictionary = dead[i]
		d.life -= dt
		if d.life <= 0.0:
			dead.remove_at(i)
		d.vy += 60.0 * dt
		d.x += d.vx * dt
		d.y = minf(-1.0, d.y + d.vy * dt)
		i -= 1
	ps.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	bubble(p, false)
	ps.draw(p, "back")


func draw(p: Px.Painter) -> void:
	charge(p)
	bubble(p, true)
	# the pop: a white disc, a ring racing out ahead of the bubble, a flare
	var a := t - POP
	if a >= 0.0 and a < 0.06:
		p.circle(0.0, -7.0, 12.0 * (1.0 - a / 0.06) + 3.0, C[6])
		p.circle(0.0, -7.0, 9.0 * (1.0 - a / 0.06) + 1.0, WHITE)
	if a >= 0.0 and a < 0.4:
		var k := a / 0.4
		var rr := 6.0 + (RM + 14.0) * Px.Ease.outCubic(k)
		Px.band(p, 0.0, 0.0, rr, 0.16, maxf(1.0, 3.0 * (1.0 - k)), 1.2 - k, [C[3], C[5], C[6], WHITE], func(_g: float) -> bool: return true, k < 0.3)
	if a >= 0.0 and a < 0.16:
		Px.sparkle(p, 0.0, -7.0, 10.0 * (1.0 - a / 0.16), C[6], C[5], 0.6)
	for b: Array in star:
		Lib.strokeArc(p, b, [C[3], C[6], C[5]], 1.0 - (t - POP) / 0.3, 1.3)
	for c: Dictionary in arcs:
		Lib.strokeArc(p, c.pts, [C[2], C[5], C[4]], 1.0 - (t - c.t) / (c.life + 0.03), 0.8)
	# dead pixels: drifting down, blinking, going out
	for d: Dictionary in dead:
		if sin(t * 40.0 + d.ph) < -0.3 and d.life < 0.6:
			continue
		p.rect(d.x, d.y, d.s, d.s, d.c if d.life > 0.5 else C[3])
	ps.draw(p, "front")
	lights.draw(p)
