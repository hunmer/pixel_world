# The caustic light and the bubbles are adapted from Sprite Fusion's open-source bubbles
# (https://www.spritefusion.com/pixel-art-vfx/bubbles), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/critters/fish-school.js@7b626afa3f515a87fb6be2e0fb2b6d637071df4f
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")

static var meta := {
	"name": "Fish school",
	"desc": "A school of fish holds station in two depth rows: bodies wag into swinging tails, one darts ahead now and then, bubbles rise and caustic light ripples over them.",
	"tags": ["critter", "fish", "school", "sea", "underwater", "swim", "loop"],
	"size": [136, 80],
	"origin": [68, 40],
	"duration": 4.8,
	"loop": true,
	"fps": 30,
	"bg": "dark",
	"options": {
		"palette": ["#0a1a2a", "#123552", "#1d5a7e", "#2f8aa8", "#62bccc", "#bfe8e6", "#f4fff8"],
		"stripe": ["#5a1e14", "#d8582a", "#ffa04a"],
		"seed": 1,
	},
}

static var D: float = meta.duration
static var GRID := Lib.Grid.new(-28, -12, 34, 24)
# the school: [x, y, size, back row?, phase]
const SCHOOL := [
	[-34.0, -16.0, 0.72, true, 0.1], [2.0, -20.0, 0.68, true, 0.55], [30.0, -10.0, 0.7, true, 0.3],
	[-22.0, 4.0, 1.0, false, 0.8], [12.0, -4.0, 1.0, false, 0.2], [-40.0, -2.0, 0.95, false, 0.45], [26.0, 14.0, 0.96, false, 0.65],
]


# one fish, its nose at (0, 0), facing right, its body trailing back to the left
static func fish(g: Lib.Grid, C: Array, Sp: Array, s: float, t: float, ph: float, dart: float) -> void:
	g.clear()
	var L := 15.0 * s
	var H := 8.0 * s
	var beats := 12.0 + (6.0 if dart > 0.0 else 0.0)
	var w := (t / D) * TAU * beats + ph * TAU
	var amp := (1.3 + 1.2 * dart) * s
	var bend := func(u: float) -> float: return amp * u ** 1.8 * sin(w - 4.0 * u)
	var prof := func(u: float) -> float: return sqrt(u / 0.3) if u < 0.3 else 1.0 - ((u - 0.3) / 0.7) ** 1.5 * 0.72
	var hh := func(u: float) -> float: return (H / 2.0) * prof.call(u)
	# body: dark back, lighter flank, silver belly; a stripe down the side; light rippling on its back
	g.shade(-L, -H, 0.0, H, func(x, y, o):
		var u: float = -x / L
		var dy: float = y - bend.call(u)
		var h: float = hh.call(u)
		if u < 0.0 or u > 1.0 or absf(dy) > h:
			return 0
		var v := dy / h
		if v > -0.12 and v < 0.12 and u > 0.22 and u < 0.92:
			return Sp[1] if u < 0.3 else Sp[2 if v < 0.0 else 1]
		if v < -0.6:
			return C[3] if (u < 0.5 and v < -0.8) else C[2]
		if v < -0.12:
			return C[3]
		if v < 0.5:
			return C[4]
		return C[4] if v > 0.86 else C[5])
	# the tail: a forked fin swinging off the end of the wave, lit along its upper lobe
	var tb: float = bend.call(1.0)
	var ta := atan(amp * 1.8 * 0.9 * cos(w - 4.0)) * 0.8
	var TL := 6.0 * s
	var hb: float = hh.call(1.0)
	var rot := func(dx: float, dy: float) -> Array: return [-(L + dx * cos(ta) - dy * sin(ta)), tb + dx * sin(ta) + dy * cos(ta)]
	g.poly([rot.call(-0.5, -hb), rot.call(TL, -hb - 3.4 * s), rot.call(TL * 0.62, 0.0), rot.call(TL, hb + 3.4 * s), rot.call(-0.5, hb)], func(x, y): return C[4] if y < tb - 1.0 else C[3], 0.88)
	# the dorsal fin: swept back, ribbed; a pectoral fin paddling, the gill, the eye
	var d0 := 0.34
	var d1 := 0.66
	g.poly([[-d0 * L, bend.call(d0) - hh.call(d0) + 0.5], [-(d0 + 0.08) * L, bend.call(d0) - hh.call(d0) - 3.6 * s], [-d1 * L, bend.call(d1) - hh.call(d1) + 0.5]], func(x): return C[3] if Px.roundi(x) % 2 else C[4], 0.85)
	var pf := sin(w * 0.5) * 1.2
	g.setc(-0.34 * L, bend.call(0.34) + 1.5 * s + pf * 0.3, C[4], 0.85)
	g.setc(-0.34 * L - 1.0, bend.call(0.34) + 2.0 * s + pf * 0.6, C[4], 0.85)
	for y in range(-2, 2):
		g.setc(-0.26 * L, bend.call(0.26) + y * s, C[2])
	var ex := -0.13 * L - 1.0
	var ey: float = bend.call(0.13) - 0.25 * H
	g.setc(ex, ey, C[0])
	g.setc(ex + 1.0, ey, C[0])
	g.setc(ex, ey + 1.0, C[1])
	g.setc(ex + 1.0, ey + 1.0, C[0])
	g.setc(ex + 1.0, ey, C[6])
	g.outline(C[0])


# where a fish is: holding station in the current, swaying; one darts ahead and drifts back once a loop
static func place(f: Array, i: int, t: float) -> Dictionary:
	var bx: float = f[0]
	var by: float = f[1]
	var ph: float = f[4]
	var a := (t / D) * TAU
	var dt := Px.wrap(t - fmod(i * 0.71 * D, D), D)
	var dart := ((Px.Ease.outCubic(dt / 0.25) if dt < 0.25 else (1.0 - Px.Ease.inOutSine((dt - 0.25) / 1.35) if dt < 1.6 else 0.0))) if i == 4 else 0.0
	return {"x": bx + 3.0 * sin(a + ph * TAU) + 8.0 * dart, "y": by + 1.8 * sin(2.0 * a + ph * 5.0), "dart": 1.0 - dt / 0.6 if (i == 4 and dt < 0.6) else 0.0}


# caustics: the light that comes down through rippling water, as bright crossing lines
static func caustics(p: Px.Painter, C: Array, t: float) -> void:
	var a := (t / D) * TAU
	for yi in range(-38, 38):
		var y := float(yi)
		for xi in range(-66, 66):
			var x := float(xi)
			var fall := Px.clamp(1.0 - ((x / 64.0) ** 2 + (y / 40.0) ** 2)) * (0.6 + 0.4 * Px.clamp(-y / 40.0 + 0.6))
			if fall <= 0.0:
				continue
			var u := x * 0.16 + 1.9 * sin(y * 0.12 + a)
			var v := y * 0.19 + 1.9 * sin(x * 0.1 - a)
			var n1 := sin(u) + sin(v)
			var sh := 0.75 + 0.25 * sin(x * 0.05 - y * 0.04 + 2.0 * a)
			var f := maxf(0.0, 1.0 - absf(n1) * 5.0) * fall * sh
			if f > 0.55:
				p.light(x, y, C[4], 0.3)
			elif f > 0.25:
				p.light(x, y, C[3], 0.14)


static func draw(p: Px.Painter, time: float, o: Dictionary) -> void:
	var t := Lib.shift(time, D, o.seed)
	var C := Px.fit(o.palette, 7)
	var Sp := Px.fit(o.stripe, 3)
	var g := GRID
	# shafts of light slanting down through the water
	for q in [[-30.0, 10.0, 0.0], [14.0, 7.0, 2.1], [44.0, 12.0, 4.0]]:
		var x0: float = q[0]
		var w: float = q[1]
		var ph: float = q[2]
		var sw := sin((t / D) * TAU + ph) * 4.0
		p.glowLine(x0 + sw - 12.0, -40.0, x0 + sw + 8.0, 40.0, w, C[4], 0.05)
	# the back row first, dimmed into the water; then the front row
	for back in [true, false]:
		for i in SCHOOL.size():
			var f: Array = SCHOOL[i]
			if f[3] != back:
				continue
			var P := place(f, i, t)
			fish(g, C, Sp, f[2], t, f[4], P.dart)
			if back:
				g.recolor(func(x, y, c): return Px.mix(c, C[1], 0.42))
			g.draw(p, 1.0, P.x, P.y)
	# bubbles let go from their mouths now and then
	Px.cycle(t, D, 9, o.seed * 13 + 1, func(r): return r.range(1.6, 2.6), func(age, L, r, i):
		var f: Array = SCHOOL[i % SCHOOL.size()]
		var P := place(f, i % SCHOOL.size(), Px.wrap(t - age, D))
		var rad: float = r.range(0.6, 1.6) * f[2]
		var ph: float = r.next() * TAU
		var x: float = P.x + 1.0 + sin(age * (4.0 + 2.0 / rad) + ph) * (0.5 + rad * 0.7)
		var y: float = P.y - 1.0 - (16.0 + 12.0 * rad) * age
		if y < -38.0:
			return
		Lib.bubble(p, x, y, rad, [C[6], C[5], C[4], C[3]], minf(minf(minf(1.0, age * 4.0), (L - age) * 3.0), (y + 38.0) / 4.0)))
	caustics(p, C, t)
	p.glow(0.0, -8.0, 74.0, C[2], 0.2)
	p.glow(-6.0, -18.0, 40.0, C[3], 0.1)
