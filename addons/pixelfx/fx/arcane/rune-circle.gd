# The floor glow and the specks rising off it follow Sprite Fusion's open-source mana heal
# (https://www.spritefusion.com/pixel-art-vfx/heal), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/arcane/rune-circle.js@6520ffdb3ed1da3cd00a1e69677b18da3d815c05
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE

# turning a quarter a loop keeps every part seamless: 16 ticks, a square, and 12 runes in a pattern of three
const D := 4.0
const R := 46.0
const RR := 39.0
const RI := 23.0
const RC := 7.0
const SY := 0.3
const NR := 12

static var meta := {
	"name": "Rune circle",
	"desc": "A rune circle turns on the floor in perspective: a carousel of runes lit by chasing light, a turning square, ticks, motes rising off it.",
	"tags": ["arcane", "rune", "circle", "magic", "aura", "ground", "loop"],
	"size": [136, 100],
	"origin": [68, 80],
	"duration": D,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": Px.PAL.arcane, "seed": 8},
}


static func at(g: float, r: float) -> Array:
	return [cos(g) * r, sin(g) * r * SY]

static func gap(a: float, b: float) -> float:
	return absf(atan2(sin(a - b), cos(a - b)))


static func circle(p: Px.Painter, C: Array, t: float, far: bool) -> void:
	var ph := t / D
	var spin := (ph * TAU) / 4.0
	var keep := (func(g: float) -> bool: return sin(g) < 0.0) if far else (func(g: float) -> bool: return sin(g) >= 0.0)
	# two sparks of light chase round the outer ring, twice a loop
	var chase := ph * TAU * 2.0
	var lit := func(g: float, w: float) -> bool: return gap(g, chase) < w or gap(g, chase + PI) < w
	var tone := func(g: float, hi: int, lo: int) -> int: return lo if sin(g) < 0.0 else hi
	Lib.floorRing(p, 0.0, 0.0, R, SY, func(g: float) -> int: return WHITE if lit.call(g, 0.22) else (C[6] if lit.call(g, 0.5) else tone.call(g, C[6], C[5])), 1.0, keep)
	Lib.floorRing(p, 0.0, 0.0, RI, SY, func(g: float) -> int: return tone.call(g, C[5], C[4]), 1.0, keep)
	Lib.floorRing(p, 0.0, 0.0, RC, SY, func(g: float) -> int: return tone.call(g, C[6], C[5]), 1.0, keep)
	# studs set round the outside of the ring, turning with it
	for j in 16:
		var g := spin + ((j + 0.5) * TAU) / 16.0
		if (sin(g) < 0.0) != far:
			continue
		var xy := at(g, R + 3.5)
		var x: float = xy[0]
		var y: float = xy[1]
		var hot: bool = lit.call(g, 0.3)
		p.px(x, y, WHITE if hot else tone.call(g, C[5] if j % 2 else C[6], C[4]))
		if j % 2 == 0:
			for d in [[1, 0], [-1, 0]]:
				p.px(x + d[0], y + d[1], C[6] if hot else tone.call(g, C[4], C[3]))
	# a square turning the other way inside the inner ring, its corners touching it
	var pts := [0, 1, 2, 3].map(func(k): return at(-spin + (k * TAU) / 4.0 + PI / 4.0, RI))
	for k in 4:
		var ax: float = pts[k][0]
		var ay: float = pts[k][1]
		var bx: float = pts[(k + 1) % 4][0]
		var by: float = pts[(k + 1) % 4][1]
		if (ay < 0.0) != (by < 0.0):
			var u := ay / (ay - by)
			var mx := ax + (bx - ax) * u
			if (ay < 0.0) == far:
				bx = mx
				by = 0.0
			else:
				ax = mx
				ay = 0.0
		elif (ay < 0.0) != far:
			continue
		p.line(ax, ay, bx, by, C[4] if far else C[5])
	# the runes stand in the band, riding round; bright at the front, dim behind, flaring as the light passes
	var gs := range(NR).map(func(k): return [k, spin + ((k + 0.5) * TAU) / NR]).filter(func(e): return (sin(e[1]) < 0.0) == far)
	Px.sort(gs, func(a, b): return sin(a[1]) - sin(b[1]))
	for e in gs:
		var k: int = e[0]
		var g: float = e[1]
		var xy := at(g, RR)
		var x: float = xy[0]
		var y: float = xy[1]
		var hot: bool = lit.call(g, 0.2)
		var bob := sin(ph * TAU * 4.0 + 4.0 * g) * 0.5
		Lib.glyph(p, [0, 3, 5][k % 3], x, y - 1.0 + bob, WHITE if hot else (C[5] if far else C[6]), 1.0, C[5] if hot else (C[2] if far else C[3]))
		p.glow(x, y - 3.0, 10.0 if hot else 6.0, C[5], 0.5 if hot else (0.12 if far else 0.22))
		p.glow(x, y, 5.0, C[4], 0.15)


# motes rising off the circle on a slow helix round its axis, swaying in; twinkles hanging over it
static func motes(p: Px.Painter, C: Array, t: float, S: float, far: bool) -> void:
	Px.cycle(t, D, 76, S * 5.0 + 1.0, func(g: Px.Rng) -> float: return g.range(1.1, 1.9), func(age: float, life: float, r: Px.Rng) -> void:
		var g0 := r.range(0.0, TAU)
		var r0: float = r.pick([R, R, RR, RR, RI])
		var q := age / life
		var g := g0 + q * r.range(0.6, 1.4)
		if (sin(g) < 0.0) != far:
			return
		var rr := r0 * (1.0 - 0.35 * q)
		var h := 2.0 + Px.Ease.outQuad(q) * r.range(26.0, 52.0)
		var x := cos(g) * rr
		var y := sin(g) * rr * SY - h
		var a := minf(1.0, q * 5.0) * (1.0 - Px.smooth(0.65, 1.0, q))
		var big := r.chance(0.2)
		Lib.mote(p, x, y, -sin(g) * rr * 0.8, -36.0 * (1.0 - q) - 10.0, WHITE if r.chance(0.3) else (C[6] if r.chance(0.6) else C[5]), 1.1 if big else r.range(0.55, 0.9), a, 0.5 if big else 0.3))
	Px.cycle(t, D, 14, S * 5.0 + 2.0, 0.45, func(age: float, life: float, r: Px.Rng) -> void:
		var g := r.range(0.0, TAU)
		if (sin(g) < 0.0) != far:
			return
		var rr := r.range(8.0, R)
		var x := cos(g) * rr
		var y := sin(g) * rr * SY - r.range(6.0, 34.0)
		var k := sin((age / life) * PI)
		Px.sparkle(p, x, y, 1.0 + 2.4 * k, C[6], C[5], 0.35 * k))


static func drawBack(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var pulse := 0.85 + 0.15 * sin((t / D) * TAU * 4.0)
	# the floor glows under the circle, and a soft light stands over it
	p.glow(0.0, 0.0, R * 1.4, C[4], 0.24 * pulse)
	for s in [-1, 1]:
		p.glow(s * R * 0.55, 1.0, R * 0.7, C[5], 0.12 * pulse)
	# a soft column of light standing over it, fading as it rises
	for h in range(0, 66, 6):
		p.glow(0.0, -h, 26.0, C[4], 0.11 * pulse * (1.0 - h / 80.0))
	circle(p, C, t, true)
	motes(p, C, t, o.seed, true)


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var chase := (t / D) * TAU * 2.0
	circle(p, C, t, false)
	motes(p, C, t, o.seed, false)
	# the two sparks of light running round the ring
	for g in [chase, chase + PI]:
		var xy := at(g, R)
		Px.sparkle(p, xy[0], xy[1], 2.5 + sin(t * 30.0) * 0.8, C[6], C[5], 0.5)
		p.glow(xy[0], xy[1], 14.0, C[5], 0.4)
