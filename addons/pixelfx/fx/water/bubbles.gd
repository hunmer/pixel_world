# The bubble shading (a lit rim top-left, a shaded rim bottom-right, a see-through body, a highlight and a
# refraction fleck, 2x2 and 1 px forms when small) and the surface line are adapted from Sprite Fusion's
# open-source bubbles (https://www.spritefusion.com/pixel-art-vfx/bubbles), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/water/bubbles.js@6ba609c5b2ee85100e075a515c75264678ec1911
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE
const SQRT2 := 1.4142135623730951

static var meta := {
	"name": "Bubbles",
	"desc": "Bubbles stream up from a vent of pebbles, wobbling and swelling as they rise, flare as they cross shafts of light from the surface, then dome up and pop there.",
	"tags": ["water", "bubbles", "underwater", "vent", "ambient", "loop"],
	"size": [104, 112],
	"origin": [52, 104],
	"duration": 4,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": Lib.WATER, "seed": 4},
}

static var D: float = meta.duration
const TOP := -92.0
const HALF := 48


# the surface: a wavy lit line, a darker band under it
static func surfaceY(x: float, ph: float) -> float:
	return TOP + sin(x * 0.13 + ph * TAU * 2.0) * 1.1 + sin(x * 0.051 - ph * TAU) * 1.3


# light shafts slanting down from the surface, drifting: how much of one a point is in
static func shaft(x: float, y: float, ph: float) -> float:
	var u := x + (y - TOP) * 0.32
	var s := sin(u * 0.16 + ph * TAU) * 0.6 + sin(u * 0.07 - ph * TAU + 1.0) * 0.4
	return maxf(0.0, s - 0.35) / 0.65


# one bubble at (x, y), radius r, squash q: tiny ones a pixel or a shaded 2x2, bigger ones a lit rim round a
# see-through body with a highlight and a fleck of light refracted through it
static func bubble(p: Px.Painter, C: Array, x: float, y: float, r: float, q: float, lit: float) -> void:
	if r < 0.9:
		p.px(x, y, WHITE if lit > 0.3 else (C[5] if r < 0.7 else C[6]))
		return
	if r < 1.5:
		var X := floorf(x)
		var Y := floorf(y)
		p.px(X, Y, WHITE)
		p.px(X + 1.0, Y, C[6])
		p.px(X, Y + 1.0, C[5])
		p.px(X + 1.0, Y + 1.0, C[4])
		p.glow(x + 0.5, y + 0.5, 3.0, C[5], 0.12 + 0.2 * lit)
		return
	var rx := r * (1.0 + q)
	var ry := r * (1.0 - q)
	p.shade(x - rx - 1.0, y - ry - 1.0, x + rx + 1.0, y + ry + 1.0, func(px: float, py: float, out):
		var dx := (px - x) / rx
		var dy := (py - y) / ry
		var d := Px.hypot(dx, dy) * r
		if d > r + 0.5:
			return
		var l := (-dx - dy) / SQRT2 / maxf(0.01, d / r)
		if d > r - 0.6:
			out.c = C[6] if l > 0.45 else (C[3] if l < -0.55 else C[4])
		else:
			p.blend(px, py, C[5], 0.16 + 0.2 * lit))
	p.px(Px.round(x - rx * 0.45), Px.round(y - ry * 0.45), WHITE)
	if r >= 2.5:
		p.px(Px.round(x - rx * 0.45) + 1.0, Px.round(y - ry * 0.45), C[6])
	if r >= 2.0:
		p.px(Px.round(x + rx * 0.5), Px.round(y + ry * 0.5), C[6])
	p.glow(x, y, r * 2.4 + 2.0, C[5], 0.12 + 0.3 * lit)


# the bubbles, from the vent's three mouths: each rises faster the bigger it is, swells as the pressure drops,
# wobbles side to side, and pops at the surface
const MOUTHS := [-5.0, 1.0, 6.0]


static func each(t: float, S: float, fn: Callable) -> void:
	Px.cycle(t, D, 46, S, func(g: Px.Rng): return g.range(2.2, 3.4), func(age: float, life: float, r: Px.Rng, i: int):
		var m: float = MOUTHS[i % 3]
		var r0 := r.range(0.5, 1.4) if r.next() < 0.7 else r.range(1.6, 2.6)
		var vy := 30.0 + 9.0 * r0 + r.range(-4.0, 4.0)
		var wf := r.range(3.0, 6.0)
		var wa := 0.8 + r0 * 1.2
		var ph0 := r.range(0.0, TAU)
		var drift := r.range(-4.0, 4.0)
		var y := -2.0 - vy * age
		var k := Px.clamp(-y / -TOP)
		var x := m + drift * k + sin(age * wf + ph0) * wa * k
		fn.call({"x": x, "y": y, "r": r0 * (1.0 + 0.45 * k), "q": 0.12 * sin(age * wf * 2.0 + ph0) * minf(1.0, r0 / 2.0), "i": i, "age": age, "vy": vy}))


static func drawBack(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var ph := t / D
	# the water: deeper toward the floor, light falling through it in shafts
	var Y := TOP - 2.0
	while Y < 0.0:
		for X in range(-HALF, HALF):
			var x := X + 0.5
			var y := Y + 0.5
			var sy := surfaceY(x, ph)
			if y < sy:
				continue
			var e := 1.0 - Px.smooth(HALF - 14, HALF, absf(x))
			var depth := (y - TOP) / -TOP
			p.blend(x, y, C[1], (0.22 + 0.22 * depth) * e)
			var s := shaft(x, y, ph) * (1.0 - depth * 0.7) * e
			if s > 0.05:
				p.light(x, y, C[4], 0.2 * s)
		Y += 1.0
	# where the shafts reach the floor, caustic light dances on it
	for X in range(-HALF, HALF):
		var x := X + 0.5
		var e := 1.0 - Px.smooth(HALF - 14, HALF, absf(x))
		var s := shaft(x, -2.0, ph)
		var c := maxf(0.0, 1.0 - absf(sin(x * 0.42 + sin(x * 0.11 + ph * TAU * 2.0) * 2.2)) * 2.4)
		if s * c * e > 0.05:
			p.light(x, -1.0, C[5], 0.5 * s * c * e)
			p.light(x, -2.0, C[4], 0.25 * s * c * e)
			p.light(x, 0.0, C[4], 0.3 * s * c * e)
	# the vent: a little heap of pebbles round a dark mouth
	var ST := Lib.rock()
	for v: Array in [[-9.0, -1.5, 2.4], [-4.0, -1.0, 1.8], [3.5, -1.2, 2.2], [9.0, -1.4, 2.6], [0.0, -0.6, 1.4], [-12.5, -0.8, 1.6]]:
		var x: float = v[0]
		var y: float = v[1]
		var rr: float = v[2]
		p.shade(x - rr - 1.0, y - rr - 1.0, x + rr + 1.0, y + rr + 1.0, func(px: float, py: float, out):
			var dx := px - x
			var dy := py - y
			var d := Px.hypot(dx * 1.1, dy)
			if d > rr + 0.7 or py > 0.0:
				return
			out.c = ST[0] if d > rr else (ST[5] if dx + dy < -rr * 0.6 else (ST[3] if dx + dy < rr * 0.3 else ST[2])))
	for m: float in MOUTHS:
		p.px(m, -1.0, ST[0])


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var ph := t / D
	var S: float = o.seed
	# specks drifting in the water, flaring in the light
	Px.cycle(t, D, 26, S + 7.0, D, func(age: float, life: float, r: Px.Rng):
		var x := r.range(-HALF + 6, HALF - 6) + sin((age / D) * TAU + r.range(0.0, TAU)) * 3.0
		var y := TOP + 6.0 + fmod(r.range(0.0, 86.0) + age * 4.0, 86.0)
		var s := shaft(x, y, ph)
		var tw := sin((age / D) * TAU * 3.0 + r.range(0.0, TAU))
		if tw < -0.3 and s < 0.2:
			return
		p.px(x, y, WHITE if s > 0.4 else (C[5] if tw > 0.6 else C[4]))
		if s > 0.4:
			p.glow(x, y, 3.0, C[5], 0.25 * s))
	# the bubbles; when one reaches the surface it domes up, then pops with a ring and a couple of flecks
	each(t, S, func(b: Dictionary):
		var sy := surfaceY(b.x, ph)
		if b.y > sy + b.r:
			bubble(p, C, b.x, b.y, b.r, b.q, shaft(b.x, b.y, ph))
		else:
			var since: float = (sy + b.r - b.y) / b.vy
			if since < 0.12 and b.r >= 1.4:
				var a := PI
				while a <= TAU + 0.01:
					p.px(b.x + cos(a) * b.r, sy + sin(a) * b.r * 0.9, C[6])
					a += 0.4 / b.r
				p.px(b.x - b.r * 0.4, sy - b.r * 0.6, WHITE)
			elif since < (0.32 if b.r >= 1.4 else 0.2):
				var k := Px.clamp((since - (0.12 if b.r >= 1.4 else 0.0)) / 0.2)
				var w := maxf(1.0, b.r + 1.0 + k * 4.0)
				var a := 0.0
				while a < PI:
					if sin(a) > 0.15:
						p.dot(b.x + cos(a) * w, sy + sin(a) * w * 0.3, WHITE if k < 0.4 else C[5], 1.2 - k)
					a += 0.5 / w
				if b.r >= 1.4 and k < 0.6:
					p.px(b.x - 2.0, sy - 2.0 - k * 4.0, C[6])
					p.px(b.x + 2.0, sy - 3.0 - k * 5.0, C[6]))
	# the surface: a lit line with glints running along it, a darker band under it
	for X in range(-HALF, HALF):
		var x := X + 0.5
		var y := surfaceY(x, ph)
		var e := 1.0 - Px.smooth(HALF - 12, HALF, absf(x))
		var glint := sin(x * 0.37 - ph * TAU * 3.0) * sin(x * 0.13 + ph * TAU) > 0.55
		p.dot(X, y, WHITE if glint else C[5], e * 1.3)
		p.dot(X, y + 1.0, C[3], e * 1.3)
		if (X & 3) == 0:
			p.glow(x, y + 1.0, 7.0, C[5], (0.22 if glint else 0.1) * e)
