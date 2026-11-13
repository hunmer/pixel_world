# The stream's build (a white core banded out to darker edges, surges running along it, light down its length, a
# flare where it leaves the source) follows Sprite Fusion's open-source energy beam
# (https://www.spritefusion.com/pixel-art-vfx/energy), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/water/water-jet.js@8bb38c280df5adefa7909eb8570d03407af4b1b2
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Water jet",
	"desc": "A pressurised stream blasts right: a tight glassy rod with surges running down it that swells, roughens, bends under its weight and breaks into chunks, spray and mist.",
	"tags": ["water", "jet", "stream", "hose", "spray", "directional", "loop"],
	"size": [188, 80],
	"origin": [14, 32],
	"duration": 1,
	"loop": true,
	"fps": 30,
	"bg": "dark",
	"options": {"palette": Lib.WATER, "length": 118, "seed": 3},
}

static var D: float = meta.duration
const G := 520.0
const SPEED := 260.0


# the stream's centre line drops as it goes, and how thick it is there
static func drop(x: float, L: float) -> float:
	return pow(x / L, 2.0) * 9.0


static func thick(x: float, L: float) -> float:
	return 2.6 + 5.4 * pow(x / L, 1.1)


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var ph := t / D
	var L: float = o.length
	var S: float = o.seed
	var T := ph * TAU
	# the stream, column by column: white down its core, banded out to blue edges, shadowed underneath; streaks race
	# along it and surges bulge through; past halfway it roughens, and its far end tears into chunks with gaps
	var X := 0.0
	while X <= L + 3.0:
		var x := X + 0.5
		var u := x / L
		if u > 1.0:
			break
		var yc := drop(x, L)
		var rough := Px.smooth(0.25, 1.0, u)
		var sd := fmod(fmod(x - ph * SPEED * 2.0, 130.0) + 130.0, 130.0) - 65.0
		var w0 := thick(x, L) + Px.exp(-(sd * sd) / 90.0) * 1.4 * (1.0 - u * 0.5)
		var up := w0 + Px.tileNoise(x * 0.18 - ph * 30.0, 9.0, 30.0, 0.0, S + 1.0) * 2.2 * rough
		var dn := w0 + Px.tileNoise(x * 0.18 - ph * 30.0, 3.0, 30.0, 0.0, S + 1.0) * 2.2 * rough
		var Y := floorf(yc - up)
		while Y <= ceilf(yc + dn):
			var y := Y + 0.5
			var q := (y - yc) / maxf(0.8, up if y < yc else dn)
			var aq := absf(q)
			if aq > 1.0:
				Y += 1.0
				continue
			if u > 0.55 and Px.tileNoise(x * 0.12 - ph * 25.0, (y - yc) * 0.25, 25.0, 0.0, S + 2.0) < -0.9 + 1.6 * Px.smooth(0.55, 1.0, u):
				Y += 1.0
				continue
			var streak := Px.tileNoise(x * 0.06 - ph * 40.0, floorf(y - yc + 20.0) * 1.7, 40.0, 0.0, S)
			var lvl := 0 if aq < 0.2 else (1 if aq < 0.48 else (2 if aq < 0.78 else 3))
			if streak > 0.35:
				lvl = maxi(0, lvl - 1)
			if q > 0.4:
				lvl = mini(3, lvl + 1)
			p.px(X, Y, [WHITE, C[6], C[5], C[4]][lvl])
			if lvl == 0:
				p.light(x, y, C[5], 0.12)
			Y += 1.0
		X += 1.0
	# the nozzle flare: a white burst where it leaves, ringed with light
	var fl := 0.85 + 0.15 * sin(T * 6.0)
	p.circle(0.0, 0.0, 4.4 * fl, C[5])
	p.circle(0.0, 0.0, 3.4 * fl, C[6])
	p.circle(0.0, 0.0, 2.2 * fl, WHITE)
	var a := 0.0
	while a < TAU:
		p.dot(cos(a + T * 2.0) * 5.2 * fl, sin(a + T * 2.0) * 5.2 * fl, C[5], 0.6)
		a += 0.35
	p.glow(0.0, 0.0, 24.0, C[5], 0.6 * fl)
	p.glow(0.0, 0.0, 8.0, WHITE, 0.4 * fl)
	# where it pinches apart: beads strung out along the end of the stream, racing on
	for k in 6:
		var x := L * 0.82 + fmod(k * 13 + ph * SPEED, 78.0)
		var y := drop(minf(x, L), L) + (pow((x - L) / 60.0, 2.0) * 10.0 if x > L else 0.0) + sin(k * 2.1) * 1.5
		if x < L + 34.0:
			Lib.bead(p, x, y, SPEED, 40.0, 3.0 if k % 3 == 0 else 2.0, C)
	# spray: a widening cone of drops shed from the stream and torn off its end, arcing down
	Px.cycle(t, D, 70, S + 3.0, func(g: Px.Rng): return g.range(0.2, 0.42), func(age: float, life: float, r: Px.Rng):
		var f := sqrt(r.next())
		var x0 := L * (0.3 + 0.7 * f)
		var y0 := drop(x0, L) + r.range(-1.0, 1.0) * thick(x0, L)
		var vx := r.range(150.0, 270.0) * (0.55 + 0.45 * f)
		var vy := r.range(-1.0, 1.0) * 110.0 * f + r.range(-10.0, 20.0)
		var x := x0 + vx * age
		var y := y0 + vy * age + 0.5 * G * age * age
		var k := age / life
		if x > L + 50.0 or y > 40.0 or y < -28.0 or (k > 0.75 and r.next() < (k - 0.75) * 4.0):
			return
		if r.next() < 0.45:
			p.px(x, y, WHITE if k < 0.5 else C[6])
		else:
			Lib.bead(p, x, y, vx, vy + G * age, 2.0 if r.next() < 0.2 else 1.0, C))
	# mist blooming off the end
	Px.cycle(t, D, 12, S + 4.0, func(g: Px.Rng): return g.range(0.7, 1.0), func(age: float, life: float, r: Px.Rng):
		var k := age / life
		var x := L * r.range(0.7, 1.0) + age * r.range(20.0, 45.0)
		var y := drop(minf(x, L), L) + r.range(-5.0, 5.0) + age * r.range(4.0, 14.0)
		var rad := r.range(3.0, 5.0) + k * r.range(5.0, 9.0)
		var a_ := r.range(0.1, 0.18) * minf(1.0, k / 0.15) * pow(1.0 - k, 1.5)
		p.disc(x, y, rad, C[6], func(d: float): return a_ * (1.0 - d * d)))
	# light: down the core, brightest near the nozzle
	var x := 0.0
	while x < L:
		p.glow(x, drop(x, L), 14.0 + x * 0.1, C[4], 0.26 * (1.0 - (x / L) * 0.5))
		x += 10.0
	p.glow(L * 0.9, drop(L * 0.9, L), 26.0, C[5], 0.22)
