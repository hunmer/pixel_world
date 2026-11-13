# The beam's build (the ramp across it, a hot core, light along it) is adapted from Sprite Fusion's open-source
# energy beam (https://www.spritefusion.com/pixel-art-vfx/energy), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/scifi/laser-grid.js@88ba1f3225d30dea6ec6ed64690e7eb7a4cf94bb
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Laser grid",
	"desc": "Security lasers between two steel posts: red beams slide and scissor across, dust and haze light up only where they cut through, and the floor sweepers scorch and spark.",
	"tags": ["scifi", "laser", "security", "trap", "hazard", "beam", "ground", "loop"],
	"size": [128, 84],
	"origin": [64, 76],
	"duration": 3,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"options": {
		"palette": ["#1a0408", "#4a0a12", "#8a1020", "#d01c2a", "#ff4a4a", "#ff9a90", "#ffe4e0", "#ffffff"],
		"metal": ["#0e0d14", "#1e1c27", "#312e3e", "#4b4759", "#6f6a82", "#9d98b0"],
		"seed": 31,
	},
}

static var D: float = meta.duration
const PX := 48.0
const TOP := -64.0
const IN := PX - 4.0  # posts at ±PX, TOP high; beams leave their inner faces
# the sliding beams: [middle height, swing, sweeps a loop, phase]
const SLIDE := [[-14.0, 8.0, 1.0, 0.0], [-31.0, 12.0, 2.0, 1.3], [-48.0, 9.0, 1.0, 3.6]]


# the sweepers: from each post's head down to a spot on the floor that runs to and fro
static func sweepX(t: float, s: float) -> float:
	return s * (34.0 - 68.0 * (0.5 - 0.5 * cos(TAU * (t / D) + (0.0 if s > 0.0 else 1.9))))


static func slideY(t: float, b: Array) -> float:
	var y: float = b[0]
	var a: float = b[1]
	var n: float = b[2]
	var f: float = b[3]
	return y + a * sin(TAU * n * (t / D) + f)


static func beams(t: float) -> Array:
	var out := []
	for b: Array in SLIDE:
		out.append([-IN, slideY(t, b), IN, slideY(t, b)])
	for s: float in [-1.0, 1.0]:
		out.append([s * IN, TOP + 6.0, sweepX(t, s), 0.0])
	return out


# a laser: a white-hot core, a red body either side, a dithered fringe, haze lighting up along it
static func laser(p: Px.Painter, b: Array, C: Array, t: float, seed: float) -> void:
	var x0: float = b[0]
	var y0: float = b[1]
	var x1: float = b[2]
	var y1: float = b[3]
	var steep := absf(y1 - y0) > absf(x1 - x0)
	var ox := 1.0 if steep else 0.0
	var oy := 0.0 if steep else 1.0
	for s: float in [-1.0, 1.0]:
		p.line(x0 + s * ox, y0 + s * oy, x1 + s * ox, y1 + s * oy, C[4] if s < 0.0 else C[3])
	p.line(x0, y0, x1, y1, func(u: float): return C[6] if fmod(fmod(u * 5.0 - t * 3.0, 1.0) + 1.0, 1.0) < 0.12 else WHITE)
	# the haze it passes through scatters its light, so its glow is uneven and drifts
	var L := Px.hypot(x1 - x0, y1 - y0)
	var d := 0.0
	while d <= L:
		var x := Px.lerp(x0, x1, d / L)
		var y := Px.lerp(y0, y1, d / L)
		var h := 0.5 + 0.5 * Px.tileFbm(x / 14.0 + (t / D) * 4.0, y / 10.0, 4.0, 0.0, seed)
		p.glow(x, y, 6.0 + 4.0 * h, C[3], 0.14 + 0.3 * h * h)
		d += 5.0


# where two beams cross, if they do
static func cross(a: Array, b: Array) -> Variant:
	var x1: float = a[0]
	var y1: float = a[1]
	var x2: float = a[2]
	var y2: float = a[3]
	var x3: float = b[0]
	var y3: float = b[1]
	var x4: float = b[2]
	var y4: float = b[3]
	var d := (x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4)
	if absf(d) < 1e-6:
		return null
	var u := ((x1 - x3) * (y3 - y4) - (y1 - y3) * (x3 - x4)) / d
	var v := -((x1 - x2) * (y1 - y3) - (y1 - y2) * (x1 - x3)) / d
	return [x1 + u * (x2 - x1), y1 + u * (y2 - y1)] if (u >= 0.0 and u <= 1.0 and v >= 0.0 and v <= 1.0) else null


static func near(b: Array, x: float, y: float) -> float:
	var x0: float = b[0]
	var y0: float = b[1]
	var x1: float = b[2]
	var y1: float = b[3]
	var dx := x1 - x0
	var dy := y1 - y0
	var u := Px.clamp(((x - x0) * dx + (y - y0) * dy) / (dx * dx + dy * dy))
	var ex := x0 + dx * u - x
	var ey := y0 + dy * u - y
	return sqrt(ex * ex + ey * ey)


# a steel post: a lit edge, a shaded side, a groove the emitters ride in, red light where the beams meet it
static func post(p: Px.Painter, s: float, H: Array, C: Array, t: float) -> void:
	var x0 := s * PX - 4.0
	var B := []
	for b: Array in SLIDE:
		B.append(slideY(t, b))
	var y := TOP + 4.0
	while y < 0.0:
		var glint := -INF
		for by: float in B:
			glint = maxf(glint, exp(-(pow((y - by) / 2.5, 2.0))))
		for i in 8:
			var x := x0 + i
			var inner := i >= 6 if s < 0.0 else i <= 1
			var c: int = H[0] if (i == 0 or i == 7) else (H[4] if i == 1 else (H[3] if i == 2 else (H[1] if i == 4 else (H[2] if i == 6 else H[3]))))
			if inner and i != 0 and i != 7 and glint > 0.35:
				c = C[5] if glint > 0.75 else C[3]
			p.px(x, y, c)
		y += 1.0
	# bolts down the post, the head with its lens, the foot plate
	y = TOP + 12.0
	while y < -4.0:
		p.px(x0 + 3.0, y, H[5])
		y += 9.0
	y = TOP
	while y < TOP + 10.0:
		for i in range(-1, 9):
			p.px(x0 + i, y, H[0] if (i == -1 or i == 8 or y == TOP or y == TOP + 9.0) else (H[5] if y == TOP + 1.0 else (H[4] if i < 3 else H[2])))
		y += 1.0
	p.px(s * IN, TOP + 6.0, WHITE)
	p.px(s * IN, TOP + 5.0, C[5])
	p.px(s * IN, TOP + 7.0, C[4])
	for i in range(-3, 11):
		p.px(x0 + i, -2.0, H[0] if (i == -3 or i == 10) else H[4])
		p.px(x0 + i, -1.0, H[0] if (i == -3 or i == 10) else H[2])
		p.px(x0 + i, 0.0, H[1])
	# a carriage for each sliding beam, riding the groove
	for by: float in B:
		var yy := Px.round(by)
		for j in range(-2, 3):
			for i in 4:
				p.px(x0 + 5.0 + i if s < 0.0 else x0 - 1.0 + i, yy + j, H[0] if (absi(j) == 2 or i == (3 if s < 0.0 else 0)) else (H[5] if j < 0 else H[3]))
		p.px(s * IN, yy, WHITE)
		p.glow(s * IN, yy, 7.0, C[4], 0.55)
	p.glow(s * IN, TOP + 6.0, 8.0, C[4], 0.55)


static var cache := {}


static func ghosts(o: Dictionary, C: Array) -> Lib.Ghosts:
	var key := "%s:%s" % [o.seed, o.palette]
	if cache.has(key):
		return cache[key]
	var rn := Px.Rng.new(o.seed)
	var g := Lib.Ghosts.new(D, {"ground": func(): return 0.0, "sparks": [WHITE, C[6], C[4], C[3]], "box": [-62.0, -80.0, 62.0, 7.0]})
	# the sweepers kick up sparks and wisps of smoke where they burn the floor
	for i in 36:
		var tb := (i / 36.0) * D + rn.range(0.0, 0.05)
		var s := 1.0 if i % 2 else -1.0
		var x := sweepX(tb, s)
		var dir := Px.sign(sweepX(tb + 0.02, s) - x)
		if not dir:
			dir = 1.0
		var a := -PI / 2.0 - dir * rn.range(0.2, 1.1)
		g.add(tb, P.SPARK, x, -1.0, cos(a) * rn.range(50.0, 140.0), sin(a) * rn.range(50.0, 140.0), rn.range(0.2, 0.45))
		if i % 4 == 0:
			g.add(tb, P.SMOKE, x, -2.0, rn.range(-4.0, 4.0), -rn.range(6.0, 14.0), rn.range(0.8, 1.2), Px.hex("#3a2a30"), rn.range(1.6, 2.4))
	cache[key] = g
	return g


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var H := Px.fit(o.metal, 6)
	var B := beams(t)
	var S: float = o.seed
	# the floor where the sweepers have just been: a scorch that cools from white to deep red
	for s: float in [-1.0, 1.0]:
		for k in 14:
			var ago := k * 0.025
			var x := sweepX(t - ago, s)
			var c: int = WHITE if k < 2 else (C[6] if k < 5 else (C[4] if k < 9 else C[3]))
			p.dot(x, 0.0, c, 1.0 - k / 14.0)
			p.dot(x, 1.0, C[3], 0.6 - k / 24.0)
	# a low red pool on the floor under it all
	var gx := -40.0
	while gx <= 40.0:
		p.glow(gx, -2.0, 20.0, C[3], 0.12)
		gx += 20.0
	# haze hanging in the air, thickest low down, seen only where a beam passes through it and lights it red
	var ph := t / D
	for yi in range(-60, 0):
		var y := float(yi)
		var x := -IN + 1.0
		while x < IN:
			var d := 99.0
			for b: Array in B:
				d = minf(d, near(b, x + 0.5, y + 0.5))
			if d > 11.0:
				x += 1.0
				continue
			var low := 0.35 + 0.65 * Px.clamp((y + 60.0) / 50.0)
			var n := 0.5 + 0.5 * Px.tileFbm((x + 0.5) / 18.0 + ph * 3.0, (y + 0.5) / 7.0 + 0.4 * sin(TAU * ph), 3.0, 0.0, S + 7.0, 2)
			var dens := Px.clamp((n - 0.42) * 2.2) * low
			if dens <= 0.02:
				x += 1.0
				continue
			var lit := exp(-d / 4.5)
			p.blend(x + 0.5, y + 0.5, C[4] if lit > 0.5 else (C[3] if lit > 0.15 else C[1]), dens * 0.8 * lit)
			x += 1.0
	for s: float in [-1.0, 1.0]:
		post(p, s, H, C, t)
	for b: Array in B:
		laser(p, b, C, t, S)
	# dust and haze motes, invisible until a beam catches them
	for i in 90:
		var x := (Px.rand(S, i) * 2.0 - 1.0) * (IN - 3.0) + 4.0 * sin(TAU * (t / D) + i)
		var y := -2.0 - Px.rand(S, i, 1) * 62.0 + 3.0 * sin(TAU * 2.0 * (t / D) + i * 1.7)
		var d := 9.0
		for b: Array in B:
			d = minf(d, near(b, x, y))
		if d < 1.6:
			p.px(x, y, WHITE if d < 0.9 else C[6])
			p.glow(x, y, 3.0, C[5], 0.45)
	# where beams cross, the haze between them flares
	for i in B.size():
		for j in range(i + 1, B.size()):
			var c: Variant = cross(B[i], B[j])
			if not c:
				continue
			p.glow(c[0], c[1], 9.0, C[5], 0.4)
			Px.sparkle(p, c[0], c[1], 2.0, C[6], C[5], 0.3)
	# the sweepers' hot spots on the floor
	for s: float in [-1.0, 1.0]:
		var x := sweepX(t, s)
		p.px(x, -1.0, WHITE)
		p.px(x - 1.0, 0.0, C[6])
		p.px(x + 1.0, 0.0, C[6])
		p.glow(x, -1.0, 10.0, C[4], 0.55)
		p.glow(x, -1.0, 4.0, WHITE, 0.35)
	ghosts(o, C).at(t).draw(p)
