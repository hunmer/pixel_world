# port-of: src/fx/nature/poison-cloud.js@f045358ea239e5ba376008fd018b8aa7a4f4eb1f
extends RefCounted

const Px := preload("../../core/px.gd")

static var meta := {
	"name": "Poison cloud",
	"desc": "A miasma hugging the floor: ragged sheets of gas lit yellow-green from within, fading to violet, creep out in tongues that curl over at their tips; plumes twist up as ribbons.",
	"tags": ["nature", "poison", "gas", "cloud", "miasma", "toxic", "area", "ground", "loop"],
	"size": [256, 100],
	"origin": [128, 86],
	"duration": 4.0,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"options": {
		"palette": ["#0e0816", "#24123a", "#3e2056", "#5a3a62", "#6a6a3a", "#96aa30", "#cce040", "#f4ffa0"],
		"spread": 1,
		"seed": 3,
	},
}

static var D: float = meta.duration
# sheets of gas, back to front: how tall, how wide, how thick, how much dimmer, how fast their edges flow
static var SHEETS := [
	{"h": 36.0, "e": 0.84, "a": 0.46, "dim": 2, "flow": 4.0, "n": 2.0, "back": true},
	{"h": 26.0, "e": 0.96, "a": 0.5, "dim": 1, "flow": 8.0, "n": 2.0, "back": true},
	{"h": 16.0, "e": 1.04, "a": 0.56, "dim": 0, "flow": 8.0, "n": 3.0, "back": false},
]


# tongues creeping out along the floor from the middle: where each one's front is, how tall, how far along
static func tongues(sh: Dictionary, si: int, E: float, ph: float) -> Array:
	var out := []
	for s in [-1, 1]:
		for i in int(sh.n):
			var q: float = fmod(ph + i / sh.n + si * 0.17 + (0.5 / sh.n if s > 0 else 0.0), 1.0)
			out.append({"s": s, "q": q, "x": s * E * (0.3 + 0.82 * q), "h": sh.h * (0.75 - 0.45 * q)})
	return out


# a sheet's height above the floor at x: flat through the middle, falling away at its ends, its top torn by
# noise that flows outward, raised behind each tongue's front
static func height(sh: Dictionary, si: int, E: float, x: float, ph: float, T: Array, seed: float) -> float:
	var ax := absf(x)
	var env := 1.0 - Px.smooth(0.5, 1.0, ax / (E * sh.e))
	var r := Px.tileNoise(ax * 0.07 - ph * sh.flow, si * 3.7, sh.flow, 0.0, seed + si)
	var h: float = sh.h * env * (0.55 + 0.45 * r)
	for g: Dictionary in T:
		var behind: float = g.s * (g.x - x)
		if behind < -1.5 or behind > 30.0:
			continue
		h = maxf(h, g.h * sqrt(maxf(0.0, 1.0 - behind / 30.0)) * Px.smooth(-1.5, 1.5, behind) * (1.0 - Px.smooth(0.75, 1.0, g.q)))
	return h


# one sheet: brightest down at the floor where it's lit from within, darkening to violet toward its torn top,
# streaked in thin layers, a pale rim along its edge
static func sheet(p: Px.Painter, C: Array, sh: Dictionary, si: int, E: float, t: float, seed: float) -> void:
	var ph := t / D
	var T := tongues(sh, si, E, ph)
	var d: int = sh.dim
	var X := ceili(E * 1.25)
	for x in range(-X, X + 1):
		var H := height(sh, si, E, x + 0.5, ph, T, seed)
		if H < 0.6:
			continue
		var top := -Px.roundi(H)
		for y in range(top, 2):
			var v := Px.clamp(-y / H)
			var streak := 0.7 + 0.3 * Px.tileNoise(x * 0.05 - ph * sh.flow * Px.sign(x if x else 1), y * 0.55, sh.flow, 0.0, seed + 9.0 + si)
			var lv := v - (streak - 0.7) * 0.6
			var c: int = C[maxi(1, 4 - d)] if y == top else (C[6 - d] if lv < 0.16 else (C[5 - d] if lv < 0.42 else (C[4 - d] if lv < 0.68 else C[maxi(1, 3 - d)])))
			p.blend(x, y, c, sh.a * (0.65 if y == top else (0.6 + 0.4 * (1.0 - v)) * streak))
	# the tongues' leading edges roll over in curls as they creep forward
	for g: Dictionary in T:
		var k := sin(PI * g.q)
		if k < 0.15 or g.h < 4.0:
			continue
		var r: float = 1.8 + g.h * 0.22
		var cx: float = g.x - g.s * r * 0.6
		var cy: float = -g.h * 0.72
		var spin: float = -g.s * g.q * TAU * 2.2
		# a roll of gas: a thick soft band winding in on itself, lighter along its outer edge
		var a := 0.0
		while a < 4.6:
			var rr := r * (1.0 - a * 0.12)
			var px: float = cx + g.s * cos(spin + a) * rr
			var py := cy + sin(spin + a) * rr
			var w := 1.6 * (1.0 - a / 6.0)
			var o := -w
			while o <= w:
				var qx: float = px + g.s * cos(spin + a) * o
				var qy := py + sin(spin + a) * o
				p.blend(qx, qy, C[5 - d] if o > w * 0.4 else C[4 - d], sh.a * 0.75 * k * (1.0 - a / 5.5))
				o += 0.8
			a += 0.1


# plumes: columns that lift off the sheets and twist into ribbons, thinning as they climb
static func plumes(p: Px.Painter, C: Array, E: float, t: float, seed: float) -> void:
	Px.cycle(t, D, 5, seed, func(g): return g.range(2.4, 3.2), func(age: float, L: float, R: Px.Rng):
		var u := age / L
		var x0 := R.range(-0.55, 0.55) * E
		var rise := R.range(13.0, 19.0)
		var len := R.range(34.0, 48.0)
		var ph := R.range(0.0, TAU)
		var amp := R.range(3.0, 5.0)
		var head := 14.0 + rise * age
		var tail := maxf(10.0, head - len)
		var fade := Px.smooth(0.0, 0.15, u) * (1.0 - Px.smooth(0.5, 1.0, u))
		var h := tail
		while h <= head:
			var s := (h - tail) / maxf(1.0, head - tail)
			var tw := cos(h * 0.22 + age * 2.4 + ph)
			var w := 0.6 + 2.2 * absf(tw) * (1.0 - s * 0.5)
			var x := x0 + amp * sin(h * 0.12 + age + ph) * (0.4 + s)
			var a := fade * sin(PI * minf(1.0, s * 1.2)) * 0.32
			var o := -w
			while o <= w:
				p.blend(x + o, -h, ((C[6] if absf(o) < w * 0.5 else C[5]) if tw > 0.0 else (C[3] if absf(o) < w * 0.5 else C[2])), a)
				o += 1.0
			h += 0.7)


# specks drifting out through the gas with its flow, twinkling
static func specks(p: Px.Painter, C: Array, E: float, t: float, seed: float) -> void:
	Px.cycle(t, D, 30, seed, func(g): return g.range(1.5, 2.6), func(age: float, L: float, R: Px.Rng):
		var u := age / L
		var s := R.sign()
		var x := s * (R.range(0.05, 0.7) * E + age * R.range(6.0, 14.0))
		var y := -R.range(2.0, 20.0) - sin(age * R.range(1.5, 3.0) + R.next() * TAU) * 2.0
		var a := minf(1.0, u * 5.0) * minf(1.0, (1.0 - u) * 3.0) * (0.6 + 0.4 * sin(age * R.range(6.0, 10.0) + R.next() * TAU))
		if a < 0.1:
			return
		p.dot(x, y, C[7] if a > 0.7 else C[6], a * 1.3)
		p.glow(x, y, 4.0, C[6], 0.3 * a))


static func drawBack(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var E: float = 96.0 * o.spread
	var pulse := 0.85 + 0.15 * sin((TAU * t * 2.0) / D)
	# lit from within, low down: a soft line of light along the floor under it all
	var x := -E
	while x <= E:
		p.glow(x, -3.0, 30.0, C[5], 0.14 * pulse * (1.0 - absf(x) / (E * 1.3)))
		x += 22.0
	# pockets of light wandering inside it, low down
	for i in 6:
		var R := Px.rng(o.seed, i, 7)
		var px := sin((TAU * t) / D + R.range(0.0, TAU)) * E * R.range(0.2, 0.7) + R.range(-0.3, 0.3) * E
		var k := 0.6 + 0.4 * sin((TAU * t * 3.0) / D + i)
		p.glow(px, -R.range(4.0, 10.0), R.range(14.0, 22.0), C[6], 0.2 * k)
	for i in SHEETS.size():
		var sh: Dictionary = SHEETS[i]
		if sh.back:
			sheet(p, C, sh, i, E, t, o.seed)


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var E: float = 96.0 * o.spread
	plumes(p, C, E, t, o.seed * 7.0 + 2.0)
	for i in SHEETS.size():
		var sh: Dictionary = SHEETS[i]
		if not sh.back:
			sheet(p, C, sh, i, E, t, o.seed)
	specks(p, C, E, t, o.seed * 11.0 + 5.0)
	p.glow(0.0, -6.0, E * 0.9, C[5], 0.1)
