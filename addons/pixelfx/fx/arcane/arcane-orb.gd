# The orb (a glassy bubble that thickens towards its rim, a hot core, a double rim, a highlight arc and spot,
# motes orbiting in front and behind) is adapted from Sprite Fusion's open-source energy orb
# (https://www.spritefusion.com/pixel-art-vfx/energy), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/arcane/arcane-orb.js@ed84392d5cda7e6eb8bdabf24c8b63b98a721570
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE

const D := 2.4
const RAD := 17.0
const Y0 := -52.0

static var meta := {
	"name": "Arcane orb",
	"desc": "A floating orb of smoky violet glass with a swirl turning round a white-hot heart, two tilted rings of light orbiting behind and in front.",
	"tags": ["arcane", "orb", "sphere", "magic", "floating", "loop"],
	"size": [136, 112],
	"origin": [68, 104],
	"duration": D,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": Px.PAL.arcane, "seed": 6},
}

# two rings, each a circle tilted in depth (sy) and rolled in the picture (rot), beads running round it
const RINGS := [
	{"r": 31.0, "sy": 0.24, "rot": 0.36, "beads": 3, "turn": 2.0, "c": 0.0},
	{"r": 27.0, "sy": 0.3, "rot": -0.55, "beads": 2, "turn": -3.0, "c": 1.0},
]


static func setup(t: float) -> Dictionary:
	var ph := t / D
	return {"ph": ph, "cx": 0.0, "cy": Y0 + sin(ph * TAU) * 2.0}


# one ring's points on the near (z > 0) or far side; beads brighter, with light
static func ring(p: Px.Painter, C: Array, s: Dictionary, R: Dictionary, near: bool) -> void:
	var ph: float = s.ph
	var cx: float = s.cx
	var cy: float = s.cy
	var rot: float = R.rot + 0.12 * sin(ph * TAU + R.c)
	var cr := cos(rot)
	var sr := sin(rot)
	var n := ceili(R.r * TAU * 1.5)
	var pos := func(g: float) -> Array:
		var lx: float = cos(g) * R.r
		var ly: float = sin(g) * R.r * R.sy
		return [cx + lx * cr - ly * sr, cy + lx * sr + ly * cr]
	for j in n:
		var g := (float(j) / n) * TAU
		var z := sin(g)
		if (z > 0.0) != near:
			continue
		var xy: Array = pos.call(g)
		p.dot(xy[0], xy[1], C[5] if near else C[4], 0.7 if near else 0.4)
	for b in R.beads:
		var g: float = ph * TAU * R.turn + (b * TAU) / R.beads
		for k in 7:
			# a bead and its trail along the ring
			var gg := g - Px.sign(R.turn) * k * 0.07
			var z := sin(gg)
			if (z > 0.0) != near:
				continue
			var xy: Array = pos.call(gg)
			p.dot(xy[0], xy[1], WHITE if k == 0 else (C[6] if k < 3 else C[5]), 1.0 if k < 4 else 1.0 - (k - 3) / 4.0)
			if k == 0:
				p.glow(xy[0], xy[1], 7.0 if near else 5.0, C[6], 0.5 if near else 0.25)


# the orb itself: smoky glass, the swirl, the heart, the rim, the highlights
static func orb(p: Px.Painter, C: Array, s: Dictionary) -> void:
	var ph: float = s.ph
	var cx: float = s.cx
	var cy: float = s.cy
	# the glass: translucent, thicker towards the rim
	p.disc(cx, cy, RAD, func(d: float) -> int: return C[2] if d > 0.82 else C[1], func(d: float) -> float: return 0.32 + 0.5 * d * d)
	# the swirl: two bright arms and two faint ones turning round the heart, twice a loop
	# the swirl: two bright arms with a lilac edge, and two faint ones between, turning twice a loop
	for e in [[0.0, 1], [PI, 1], [PI / 2.0, 0], [(3.0 * PI) / 2.0, 0]]:
		var s0: float = e[0]
		var main: int = e[1]
		var u := 0.08
		while u <= 0.85:
			var a := ph * TAU * 2.0 + s0 + u * 3.4
			var r := u * RAD * 0.92
			var x := cx + cos(a) * r
			var y := cy + sin(a) * r
			var fade := 1.0 if u < 0.6 else 1.0 - (u - 0.6) / 0.25
			if not main:
				p.dot(x, y, C[4], fade * 0.8)
				u += 0.012
				continue
			# the arm's lit edge trails just behind it
			var b := a - 0.16
			var xb := cx + cos(b) * r
			var yb := cy + sin(b) * r
			p.dot(xb, yb, C[6] if u < 0.4 else C[5], fade)
			p.dot(x, y, WHITE if u < 0.3 else (C[6] if u < 0.55 else C[5]), fade)
			u += 0.012
	# the heart
	var pulse := 0.85 + 0.15 * sin(ph * TAU * 3.0)
	p.circle(cx, cy, 3.6 * pulse + 1.0, C[5])
	p.circle(cx, cy, 2.8 * pulse, C[6])
	p.circle(cx, cy, 1.7 * pulse, WHITE)
	# the rim: a bright line just inside a dark one, a highlight arc and spot top left, a glint bottom right
	p.ring(cx, cy, RAD + 0.4, 1.0, C[5])
	p.ring(cx, cy, RAD + 1.3, 1.0, C[2], 0.8)
	var a := 3.5
	while a < 4.7:
		p.dot(cx + cos(a) * (RAD - 2.4), cy + sin(a) * (RAD - 2.4), WHITE if (a > 3.85 and a < 4.35) else C[6])
		a += 0.03
	p.circle(cx - RAD * 0.42, cy - RAD * 0.5, 1.3, WHITE)
	p.dot(cx + RAD * 0.52, cy + RAD * 0.55, C[6])
	p.glow(cx, cy, 20.0, C[6], 0.26 * pulse)
	p.glowRing(cx, cy, RAD, 6.0, C[5], 0.25)


# motes orbiting on tilted paths, and sparks drifting off the orb
static func motes(p: Px.Painter, C: Array, s: Dictionary, S: float, near: bool) -> void:
	var ph: float = s.ph
	var cx: float = s.cx
	var cy: float = s.cy
	for i in 8:
		var a := fmod(i * 2.4 + S, TAU) + ph * TAU * (1.0 if i % 2 else -1.0) * (1 + (i % 3))
		var rr := RAD + 5.0 + fmod(i * 0.37, 1.0) * 12.0
		var tilt := (fmod(i * 0.71, 1.0) - 0.5) * 1.4
		var x0 := cos(a) * rr
		var z := sin(a)
		if (z > 0.0) != near:
			continue
		var x := cx + x0 * cos(tilt)
		var y := cy + x0 * sin(tilt) + z * rr * 0.28
		var dir := 1.0 if i % 2 else -1.0
		p.dot(x, y, WHITE if near else C[5])
		p.dot(x - dir, y, C[6] if near else C[4], 1.0 if near else 0.6)
		if near:
			p.dot(x - 2.0 * dir, y, C[4], 0.6)
			p.glow(x, y, 5.0, C[6], 0.35)
	if not near:
		return
	Px.cycle(ph * D, D, 10, S * 3.0 + 1.0, func(g: Px.Rng) -> float: return g.range(0.6, 1.0), func(age: float, life: float, r: Px.Rng) -> void:
		var a := r.range(0.0, TAU)
		var q := age / life
		var d := RAD + 1.0 + q * r.range(8.0, 18.0)
		var x := cx + cos(a) * d
		var y := cy + sin(a) * d - q * 10.0
		Lib.mote(p, x, y, cos(a) * 25.0, sin(a) * 25.0 - 12.0, C[6] if r.chance(0.5) else C[5], 0.6, 1.0 - q, 0.3))


static func drawBack(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var s := setup(t)
	var lift: float = (s.cy - Y0) / 2.0
	# the light it throws on the floor, stronger as it bobs down
	p.glow(0.0, -1.0, 36.0, C[4], 0.26 - 0.04 * lift)
	for x in range(-20, 21):
		var u := absf(x + 0.5) / 20.0
		p.dot(x, 0.0, C[6] if u < 0.3 else C[5], (1.1 - u) * (0.9 - 0.15 * lift))
	p.glow(s.cx, s.cy, 60.0, C[4], 0.36)
	for R in RINGS:
		ring(p, C, s, R, false)
	motes(p, C, s, o.seed, false)


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var s := setup(t)
	orb(p, C, s)
	for R in RINGS:
		ring(p, C, s, R, true)
	motes(p, C, s, o.seed, true)
	Px.sparkle(p, s.cx - RAD * 0.42, s.cy - RAD * 0.5, 1.5 + maxf(0.0, sin(s.ph * TAU * 2.0)) * 2.0, C[6], C[5], 0.3)
