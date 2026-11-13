# The swirl's texture (streaks laid along a differentially wound flow, light on the brightest pixels) is adapted
# from Sprite Fusion's open-source black hole (https://www.spritefusion.com/pixel-art-vfx/black-hole), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/water/whirlpool.js@e1772bb1a31c07713612d34e9a64914486888cfc
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Whirlpool",
	"desc": "Seen from above, dark water winds into a vortex: foam arms spiral in, darkening as they're drawn down into a deep eye with a lit far rim, flecks of foam circling in after them.",
	"tags": ["water", "whirlpool", "vortex", "maelstrom", "swirl", "top-down", "loop"],
	"size": [128, 84],
	"origin": [64, 42],
	"duration": 3,
	"loop": true,
	"fps": 30,
	"bg": "dark",
	"options": {"palette": Lib.WATER, "seed": 5},
}

static var D: float = meta.duration
const R := 60.0
const SY := 0.6
const K := 2.4
const EYE := 0.16


# the flow at radius rho (0 eye, 1 rim), angle th: thin streaks of foam laid along a log spiral that turns once a
# loop (a turning log spiral reads as water drawn inward), dashed and brightest where two sets of streaks cross
static func foam(rho: float, th: float, ph: float) -> float:
	var s := log(maxf(rho, 0.02))
	var a := th + K * s + ph * TAU
	var b := th + K * 1.35 * s + ph * TAU * 2.0
	var one := pow(0.5 + 0.5 * cos(7.0 * a + 0.9 * sin(3.0 * a + s * 4.0)), 26.0)
	var two := pow(0.5 + 0.5 * cos(11.0 * b + 1.3), 34.0) * 0.7
	# finer streaks crowd in near the eye, where the water runs fastest
	var three := pow(0.5 + 0.5 * cos(17.0 * (th + K * 0.8 * s + ph * TAU * 3.0)), 30.0) * 0.8 * maxf(0.0, 1.0 - (rho - EYE) * 2.2)
	var dash := 0.55 + 0.45 * sin(s * 22.0 - ph * TAU * 4.0 + a * 2.0)
	return (one + two + three) * dash


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var ph := t / D
	var ry := R * SY
	p.shade(-R, -ry, R, ry, func(x: float, y: float, out):
		var dx := x / R
		var dy := y / ry
		var rho := Px.hypot(dx, dy)
		if rho > 1.0:
			return
		var th := atan2(dy, dx)
		# the eye: a hole down into the dark, its far wall lit, a ring of foam racing round its lip
		if rho < EYE:
			var far := -dy / rho
			# the far wall of the funnel, lit, falling off into the dark below the lip on the near side
			var wall := (rho / EYE - 0.35) / 0.65
			if far > 0.0:
				out.c = ((C[5] if far > 0.6 else C[4]) if wall > 0.8 else (C[3] if wall > 0.45 else (C[2] if wall > 0.15 else C[0])))
			else:
				out.c = C[2] if (wall > 0.85 and far > -0.5) else C[0]
			return
		var k := (rho - EYE) / (1.0 - EYE)
		var fade := 1.0 - Px.smooth(0.62, 1.0, k)
		# dark see-through water, darker toward the eye, a faint sheen mid-way
		p.blend(x, y, C[0] if k < 0.25 else C[1], (0.75 - 0.25 * k) * (1.0 - Px.smooth(0.8, 1.0, k)))
		if k > 0.3 and k < 0.8:
			p.blend(x, y, C[2], 0.18 * sin(PI * (k - 0.3) / 0.5))
		# the foam ring round the eye
		if k < 0.035:
			var g := 0.5 + 0.5 * cos(th * 9.0 - ph * TAU * 6.0)
			out.c = WHITE if g > 0.7 else (C[6] if g > 0.3 else C[4])
			return
		var I := foam(rho, th, ph) * fade * minf(1.0, (k - 0.08) * 4.0) * (0.45 + 0.55 * sin(PI * minf(1.0, k * 1.25)))
		if I > 0.12:
			out.c = WHITE if I > 0.75 else (C[6] if I > 0.45 else (C[5] if I > 0.25 else C[4]))
			if I > 0.25:
				out.l = C[5]
				out.k = 0.08 + 0.14 * minf(1.0, I))
	# flecks of foam drawn round and in along the arms, each a short streak along its path
	Px.cycle(t, D, 30, o.seed, func(g: Px.Rng): return g.range(1.2, 2.2), func(age: float, life: float, r: Px.Rng):
		var u := age / life
		var rho := 0.8 - 0.62 * u * u
		var a0 := r.range(0.0, TAU)
		var th := a0 - K * log(rho)
		var ang := th - age * (1.5 + 2.2 / rho)
		var x := cos(ang) * rho * R
		var y := sin(ang) * rho * ry
		var ang2 := ang + 0.12 / rho
		var x2 := cos(ang2) * rho * R
		var y2 := sin(ang2) * rho * ry
		if u > 0.85 and r.next() < (u - 0.85) * 6.0:
			return
		p.line(x2, y2, x, y, C[5] if u < 0.2 else (WHITE if u < 0.6 else C[6])))
	# glints winking on the foam
	Px.cycle(t, D, 8, o.seed + 3.0, func(g: Px.Rng): return g.range(0.25, 0.45), func(age: float, life: float, r: Px.Rng):
		var rho := r.range(0.35, 0.8)
		var th := r.range(0.0, TAU) - age * 2.5
		var k := sin((PI * age) / life)
		var x := cos(th) * rho * R
		var y := sin(th) * rho * ry
		if foam(rho, th, ph) < 0.35:
			return
		p.px(x, y, WHITE)
		if k > 0.55:
			for dd: Array in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
				p.px(x + dd[0], y + dd[1], C[6])
		p.glow(x, y, 5.0, C[5], 0.4 * k))
	# light: a cool sheen on the swirl, a glow off the eye's lit rim
	p.glow(0.0, 0.0, R * 0.9, C[4], 0.2)
	p.glow(0.0, 0.0, R * EYE * 1.6 + 6.0, C[5], 0.28)
	p.glow(0.0, -ry * EYE * 0.8, 14.0, C[5], 0.32)
