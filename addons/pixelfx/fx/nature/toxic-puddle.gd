# port-of: src/fx/nature/toxic-puddle.js@0b2c48177c9583fc2209d40d7ef2a14a39eb69d4
extends RefCounted

const Px := preload("../../core/px.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Toxic puddle",
	"desc": "Black tar lit from inside by chartreuse veins and a glowing rim, an oily sheen drifting on it; glossy bubbles dome, stretch and pop, vapour curls up in fraying ribbons.",
	"tags": ["nature", "poison", "toxic", "sludge", "tar", "puddle", "hazard", "ground", "loop"],
	"size": [176, 100],
	"origin": [88, 86],
	"duration": 4.0,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"options": {
		"palette": ["#06070a", "#0c100c", "#141a10", "#1e2814", "#2e3c18", "#5a7a1c", "#a6d42a", "#ecff86"],
		"sheen": ["#2a1648", "#5a2e8e", "#1e7a86", "#6adccc"],
		"width": 42,
		"seed": 2,
	},
}

static var D: float = meta.duration


# the surface height above the floor at x: a heavy lens of tar, slow swells rolling through it
static func surf(x: float, W: float, t: float) -> float:
	var d := minf(1.0, absf(x) / W)
	var ph := (TAU * t) / D
	var lens := sqrt(1.0 - d * d) * 6.6 + (1.6 * Px.smooth(0.8, 0.9, d) if d > 0.8 else 0.0)
	var swell := pow(maxf(0.0, sin(x * 0.09 - ph)), 6.0) * 1.2 + pow(maxf(0.0, sin(x * 0.06 + ph * 2.0 + 1.0)), 8.0) * 0.9
	return -Px.round(lens + swell * (1.0 - d))


# the pool: an oily skin with a violet and teal sheen sliding over it, black depths threaded with veins of light,
# a chartreuse rim glowing where the tar meets the floor
static func pool(p: Px.Painter, C: Array, Sh: Array, W: float, t: float, seed: float) -> void:
	var ph := t / D
	for x in range(floori(-W - 1.0), ceili(W + 1.0) + 1):
		var d := absf(x + 0.5) / W
		if d > 1.03:
			continue
		var top := int(surf(x + 0.5, W, t))
		var oil := 0.6 * Px.tileNoise(x * 0.08, ph * 4.0, 0.0, 4.0, seed) + 0.6 * Px.tileNoise(x * 0.11 - ph * 4.0, 1.0, 4.0, 0.0, seed + 1.0)
		var hue := Px.tileNoise(x * 0.05, ph * 2.0 + 7.0, 0.0, 2.0, seed + 3.0)
		for y in range(top, 3):
			if (y == 2 and d > 0.75) or (y == 1 and d > 0.9):
				continue
			var c: int
			if d > 0.93 and y <= 0:
				c = C[7] if y == top else C[6]
			elif y == top:
				# the skin catches light along its top: a lit edge, the sheen sliding over it, specular glints running along
				var glint := absf(fmod(fmod(x * 0.07 - ph * 3.0, 1.0) + 1.0, 1.0) - 0.5) < 0.012 or Px.rand(x, floori(t * 10.0)) < 0.015
				c = WHITE if glint else ((Sh[3] if hue > 0.0 else Sh[2]) if oil > 0.55 else ((Sh[1] if hue > 0.0 else C[5]) if oil > 0.15 else C[5]))
				if glint:
					p.light(x, y, C[7], 0.5)
			elif y == top + 1:
				c = Sh[0] if oil > 0.4 else C[3]
			elif y >= 1:
				c = C[0]
			else:
				# cracks of light under the crust, writhing slowly and swelling brighter and dimmer in a slow pulse
				var pulse := 0.5 + 0.5 * sin((TAU * t) / D + x * 0.03)
				var v := absf(Px.tileNoise(x * 0.09, y * 0.75 + ph * 4.0, 0.0, 4.0, seed + 7.0) + 0.2 * sin((TAU * t * 2.0) / D + x * 0.15))
				var w := 0.6 + 0.6 * pulse
				c = C[7] if v < 0.035 * w else (C[6] if v < 0.08 * w else (C[4] if v < 0.14 * w else C[1]))
				if v < 0.08 * w:
					p.light(x, y, C[6], 0.25 + 0.3 * pulse)
			p.px(x, y, c)
		if d > 0.9 and d <= 1.03:
			p.px(x, top - 1, C[1])
	# the glow bleeding out onto the floor at both lips
	for s in [-1, 1]:
		for k in range(1, 7):
			p.dot(s * (W + k), 0.0, C[6] if k < 3 else C[5], 1.0 - k / 7.0)


# fat bubbles: dome up dark and glossy, stretch thin as light shows through their tops, pop in a ripple ring
# and a spatter of tar, and loose a ribbon of vapour
static func bubbles(p: Px.Painter, C: Array, Sh: Array, W: float, t: float, seed: float) -> void:
	Px.cycle(t, D, 8, seed, func(g): return g.range(2.4, 3.2), func(age: float, L: float, R: Px.Rng):
		var swell := R.range(1.0, 1.6)
		var x := R.range(-0.7, 0.7) * W
		var rmax := R.range(4.5, 8.0)
		var sy := surf(x, W, t) + 0.5
		if age < swell:
			var k := age / swell
			var st := Px.smooth(0.65, 1.0, k)
			var gr := Px.Ease.outCubic(minf(1.0, k * 1.3))
			var rx := rmax * gr * (1.0 - 0.18 * st)
			var ry := rmax * gr * (1.0 + 0.5 * st)
			var X := Px.round(x)
			var Y := Px.round(sy)
			var inner := 0.35 + 0.65 * k
			for j in range(-ceili(ry) - 1, 1):
				for i in range(-ceili(rx) - 1, ceili(rx) + 2):
					var dd := Px.hypot(i / maxf(0.6, rx), j / maxf(0.6, ry))
					if dd > 1.1:
						continue
					# a dark glossy skin with chartreuse light glowing up through it, strongest low in the middle
					var c: int
					if dd > 0.9:
						c = C[0]
					elif dd < 0.55 * inner and j > -ry * 0.75:
						c = C[6] if dd < 0.3 * inner else C[5]
					elif dd < 0.8 * inner:
						c = C[4]
					else:
						c = C[2] if j < -ry * 0.5 else C[3]
					p.px(X + i, Y + j, c)
			# the gloss: a curved band of sheen on its upper left, a bright highlight
			if rx > 1.8:
				var a := 3.5
				while a < 4.7:
					p.px(X + cos(a) * rx * 0.68, Y + sin(a) * ry * 0.68, Sh[3] if a < 3.9 else (C[7] if a < 4.3 else Sh[1]))
					a += 0.16
			if rx > 1.2:
				p.px(X - Px.round(rx * 0.35), Y - Px.round(ry * 0.62), WHITE)
				p.px(X - Px.round(rx * 0.35) + 1.0, Y - Px.round(ry * 0.62), C[7])
			p.glow(x, sy - ry * 0.5, 7.0 + rx * 1.4, C[6], (0.2 + 0.35 * st) * gr)
			return
		var e := age - swell
		# the pop: a ring rippling out flat across the tar, a flash of the light inside, spatter
		if e < 0.3:
			var k := e / 0.3
			var rr := 2.0 + 14.0 * Px.Ease.outCubic(k)
			var a := 0.0
			while a < TAU:
				var rx2 := x + cos(a) * rr
				var ry2 := sy + sin(a) * rr * 0.22
				if absf(rx2) < W * 0.95:
					p.dot(rx2, ry2, WHITE if k < 0.4 else (C[7] if k < 0.7 else C[6]), (1.0 - k) * 1.4)
				a += 0.5 / rr
			p.glowRing(x, sy, rr, 3.0, C[6], 0.35 * (1.0 - k))
			if e < 0.1:
				p.glow(x, sy - 2.0, 18.0, C[6], 0.7 * (1.0 - e / 0.1))
		for j in 7:
			var vx := (Px.rand(j, seed, Px.round(x * 10.0)) - 0.5) * 80.0
			var vy := -45.0 - Px.rand(j, seed + 3.0, Px.round(x * 10.0)) * 70.0
			var dxy := Px.fly(x, sy - 2.0, vx, vy, e, 420.0)
			var dx: float = dxy[0]
			var dy: float = dxy[1]
			if dy < sy and e < 0.6:
				p.px(dx, dy, C[1])
				p.px(dx, dy - 1.0, Sh[3] if j & 1 else C[6])
		ribbon(p, C, x, sy - 2.0, e, L - swell, R, 0.9))


# vapour: a thin ribbon that curls up off the tar, then frays into wisps that wander apart and fade
static func ribbon(p: Px.Painter, C: Array, x0: float, y0: float, age: float, life: float, R: Px.Rng, k: float) -> void:
	var u := age / life
	var len := R.range(16.0, 26.0)
	var rise := R.range(9.0, 14.0)
	var amp := R.range(2.0, 4.5)
	var w := R.range(0.18, 0.3)
	var ph := R.range(0.0, TAU)
	var head := rise * age
	var tail := maxf(0.0, head - len)
	var fray := Px.smooth(0.35, 0.85, u)
	var fade := Px.smooth(0.0, 0.12, u) * (1.0 - Px.smooth(0.5, 1.0, u)) * k
	if fade < 0.02:
		return
	var GREY := Px.hex("#b4b8ae")
	var n := 3 if fray > 0.05 else 1
	var h := tail
	while h <= head:
		var s := (h - tail) / maxf(1.0, head - tail)
		var cx := x0 + amp * sin(h * w + ph + age * 1.6) * (0.3 + s)
		var y := y0 - h
		var a := fade * sin(PI * s) * 0.45
		# lit from below by the pool: green and bright low down, greying as it climbs and frays
		var lit := maxf(0.0, 1.0 - h / 22.0) * (1.0 - 0.6 * fray)
		var VAP := Px.mix(GREY, C[6], 0.75 * lit)
		for q in n:
			# each wisp wanders off on its own slow curl as the ribbon frays
			var off := 0.0 if n == 1 else fray * s * (q - 1) * 3.0 + fray * 2.5 * sin(h * (0.35 + q * 0.17) + ph * (q + 1) + age * 2.0)
			p.blend(cx + off, y, VAP, a * (1.0 if n == 1 else 0.65 - 0.25 * fray) * (0.8 + 0.4 * lit))
		h += 0.5


static func drawBack(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var Sh := Px.fit(o.sheen, 4)
	var W: float = o.width
	var pulse := 0.85 + 0.15 * sin((TAU * t * 2.0) / D)
	# the light comes from inside the pool and its rim
	p.glow(0.0, -3.0, W * 1.25, C[5], 0.22 * pulse)
	p.glow(0.0, -10.0, W * 1.1, C[6], 0.1 * pulse)
	for s in [-1, 1]:
		p.glow(s * W, -1.0, 12.0, C[6], 0.35 * pulse)
	pool(p, C, Sh, W, t, o.seed)


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var Sh := Px.fit(o.sheen, 4)
	var W: float = o.width
	bubbles(p, C, Sh, W, t, o.seed * 7.0 + 1.0)
	# a steady breath of vapour ribbons off the whole pool
	Px.cycle(t, D, 9, o.seed * 13.0 + 4.0, func(g): return g.range(2.4, 3.4), func(age: float, L: float, R: Px.Rng):
		var x := R.range(-0.85, 0.85) * W
		ribbon(p, C, x, surf(x, W, t) - 1.0, age, L, R, 0.75))
