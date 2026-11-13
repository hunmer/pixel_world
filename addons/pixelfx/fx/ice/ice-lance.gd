# The projectile recipe (a hot head, a trail that thins behind it, motes shed along the way, light riding the
# head) is adapted from Sprite Fusion's open-source energy bolt (https://www.spritefusion.com/pixel-art-vfx/energy),
# MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/ice/ice-lance.js@f9541cde4698d2c8270776088b0bf2d85c44cd6c
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Ice lance",
	"desc": "A faceted ice spear flying right: a light pulse runs through its core, rings of cold air shear off the tip, frost peels off into a wake and crystals shed behind it.",
	"tags": ["ice", "lance", "spear", "projectile", "directional", "magic", "loop"],
	"size": [176, 64],
	"origin": [146, 32],
	"duration": 0.8,
	"loop": true,
	"fps": 30,
	"bg": "dark",
	"options": {"palette": ["#151a3d", "#212f6b", "#2c58aa", "#3a8bd8", "#62c8f4", "#a6ecff", "#dcfbff", "#ffffff"], "length": 40, "seed": 13},
}


# the spear: a hexagonal shaft seen from the side, row by row (a white top edge, a lit upper facet, a bright
# ridge, a cool lower facet, a deep keel, a dark rim), a long cutting point, a light pulse running through
# its ridge to the tip, a glint sliding back along the top
static func spear(p: Px.Painter, C: Array, L: float, pulse: float, glint: float) -> void:
	var T := 16.0
	var H := 3.5
	var half := func(x: float) -> float: return H * (-x / T) + 0.3 if x > -T else (H * (0.7 + 0.3 * ((x + L) / 3.0)) if x < -L + 3.0 else H)
	p.shade(-L - 1.0, -H - 2.0, 1.0, H + 2.0, func(x: float, y: float, o) -> void:
		if x > 0.0 or x < -L:
			return
		var h: float = half.call(x)
		if absf(y) > h + 0.5:
			if absf(y) < h + 1.5:
				o.c = C[1]
			return
		var v := y / maxf(0.5, h)
		if x > -1.5:
			o.c = WHITE
			return
		# three faces lit from above: a pale top facet, a mid front facet with a bright ridge, a deep underside
		if v > -0.3 and v < 0.35 and absf(x - pulse) < 2.5:
			o.c = WHITE
			return
		if v < -0.3 and absf(x - glint) < 1.0:
			o.c = WHITE
			return
		o.c = WHITE if v < -0.72 else (C[6] if v < -0.36 else (C[7] if v < -0.18 else (C[4] if v < 0.38 else (C[2] if v < 0.78 else C[1])))))


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var D: float = meta.duration
	var S: float = o.seed
	var L: float = o.length
	var ph := t / D
	# the wake: a ribbon of frost narrowing behind the spear, with cold light in it
	p.each(-L - 100.0, -12.0, -L + 4.0, 12.0, func(x: float, y: float, sx: int, sy: int) -> void:
		var u := (-L + 4.0 - x) / 104.0
		var w := 4.5 * pow(1.0 - u, 0.7) + 0.5 + 1.5 * sin(u * 9.0 - ph * TAU * 2.0) * u
		var v := absf(y) / w
		if v >= 1.0:
			return
		var a := (1.0 - v * v) * pow(1.0 - u, 1.4)
		if a < 0.04:
			return
		p.blendPx(sx, sy, C[6] if (v < 0.25 and u < 0.4) else (C[5] if v < 0.6 else C[4]), a * 0.7)
		if a > 0.3:
			p.add(sx, sy, C[5], 0.12 * a))
	p.glowLine(-L - 60.0, 0.0, 0.0, 0.0, 14.0, C[4], 0.22)
	# frost peeling off the shaft into soft puffs left behind
	Px.cycle(t, D, 14, S, func(g: Px.Rng) -> float: return g.range(0.35, 0.55), func(age: float, life: float, r: Px.Rng) -> void:
		var x0 := r.range(-L + 2.0, -8.0)
		var xy := Px.fly(x0, r.range(-2.5, 2.5), -r.range(150.0, 230.0), r.sign() * r.range(8.0, 30.0), age, 0.0, 2.2)
		var x: float = xy[0]
		var y: float = xy[1]
		var k := age / life
		var rad := 1.2 + 5.5 * k
		var a := 0.5 * pow(1.0 - k, 1.3)
		p.disc(x, y, rad, C[6] if k < 0.3 else C[5], func(d: float) -> float: return a * (1.0 - d * d))
		p.glow(x, y, rad * 1.6, C[4], 0.1 * (1.0 - k)))
	# crystals shed along the way: short tumbling shards with a white edge, glinting, falling back
	Px.cycle(t, D, 9, S + 1.0, func(g: Px.Rng) -> float: return g.range(0.4, 0.6), func(age: float, life: float, r: Px.Rng) -> void:
		var xy := Px.fly(r.range(-L, -6.0), r.range(-3.0, 3.0), -r.range(170.0, 260.0), r.range(-35.0, 35.0), age, 60.0, 1.2)
		var x: float = xy[0]
		var y: float = xy[1]
		var k := age / life
		var a := r.range(0.0, TAU) + age * r.range(10.0, 18.0) * r.sign()
		var l := r.range(1.2, 2.2)
		var ca := cos(a)
		var sa := sin(a)
		if k > 0.85 and fmod(age * 30.0, 2.0) < 1.0:
			return
		p.line(x - ca * l, y - sa * l, x + ca * l, y + sa * l, C[5])
		p.px(x + ca * l, y + sa * l, WHITE)
		if cos(a * 2.0) > 0.9:
			for d: Array in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
				p.px(x + d[0], y + d[1], C[6])
			p.glow(x, y, 6.0, C[5], 0.45))
	# speed lines: the air streaming past above and below
	Px.cycle(t, D, 12, S + 2.0, func(g: Px.Rng) -> float: return g.range(0.16, 0.26), func(age: float, life: float, r: Px.Rng) -> void:
		var y := r.sign() * r.range(4.0, 13.0)
		var x := r.range(-20.0, 0.0) - age * r.range(280.0, 380.0)
		var l := r.range(6.0, 16.0)
		var k := age / life
		p.line(x, y, x + l, y, func(u: float) -> int: return C[6] if u > 0.7 else C[4], func(u: float) -> float: return u * (1.0 - k) * 1.4))
	# rings of cold air shearing off the point and sliding back along the shaft: the near arc bright, the far dim
	for i in 3:
		var q := fmod(ph * 3.0 + i / 3.0, 1.0)
		var x := -4.0 - q * (L + 20.0)
		var ry := 4.5 + q * 8.0
		var rx := 1.2 + q * 2.6
		if q > 0.8:
			continue
		for k in 40:
			var an := (k / 40.0) * TAU
			var px := x + cos(an) * rx
			var py := sin(an) * ry
			if absf(py) < 4.6 and px > -L - 2.0:
				continue
			p.px(px, py, (WHITE if q < 0.35 else C[6]) if cos(an) > 0.0 else (C[5] if q < 0.4 else C[4]))
		p.glowRing(x, 0.0, ry * 0.75, 3.0, C[5], 0.14 * (1.0 - q))
	# the ice fletching at the back: three shards fanning out behind the shaft
	for e: Array in [[-1.0, 10.0, 4.0], [1.0, 9.0, 4.0], [-0.2, 6.0, 3.0]]:
		var dy: float = e[0]
		var l: float = e[1]
		var w: float = e[2]
		Lib.blade(p, -L + 3.0, dy * 1.5, -L + 3.0 - l, dy * (2.0 + l * 0.5), w, C)
	# the spear itself, a pulse of light running through it, a glint sliding back along the top
	var pulse := -L + fmod(ph * 2.0, 1.0) * (L + 6.0)
	var glint := -fmod(ph * 2.0 + 0.5, 1.0) * L * 1.2
	spear(p, C, L, pulse, glint)
	p.glowLine(-L, 0.0, 0.0, 0.0, 10.0, C[4], 0.1)
	p.glow(pulse, 0.0, 8.0, C[6], 0.3)
	p.glow(0.0, 0.0, 8.0, WHITE, 0.4)
	p.glow(-L * 0.4, 0.0, 30.0, C[3], 0.16)
