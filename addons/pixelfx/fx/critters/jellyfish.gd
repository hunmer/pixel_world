# The bubbles are adapted from Sprite Fusion's open-source bubbles (https://www.spritefusion.com/pixel-art-vfx/bubbles),
# MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/critters/jellyfish.js@4b4ae31b79407a7054ea105af99e7affba32b61a
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")

static var meta := {
	"name": "Jellyfish",
	"desc": "A see-through jellyfish pulses: its bell squeezes to shove it up and relaxes as it sinks, frilled arms and long tentacles trailing, a glow inside, bubbles drifting by.",
	"tags": ["critter", "jellyfish", "sea", "underwater", "glow", "swim", "loop"],
	"size": [96, 120],
	"origin": [48, 38],
	"duration": 3.2,
	"loop": true,
	"fps": 30,
	"bg": "dark",
	"options": {
		"palette": ["#140b2b", "#2a1650", "#4b2386", "#7a3cb8", "#b066e0", "#e09cf5", "#ffd6ff", "#ffffff"],
		"glow": ["#0b3550", "#1f7fa8", "#4fd2e8", "#b8fbff"],
		"seed": 1,
	},
}

static var D: float = meta.duration
static var BEAT := D / 2.0
static var GRID := Lib.Grid.new(-22, -28, 44, 36)
const W0 := 32.0
const H0 := 18.0


# the bell's squeeze (1 squeezed, below 0 flared out past rest) and its height through one beat
static func squeeze(u: float) -> float:
	if u < 0.16:
		return Px.Ease.outCubic(u / 0.16)
	if u < 0.22:
		return 1.0
	if u < 0.72:
		return Px.lerp(1.0, -0.14, Px.Ease.inOutSine((u - 0.22) / 0.5))
	return Px.lerp(-0.14, 0.0, Px.Ease.inOutSine((u - 0.72) / 0.28))


static func lift(u: float) -> float:
	return -6.0 * Px.Ease.outCubic(Px.seg(u, 0.04, 0.42)) if u < 0.42 else -6.0 + 6.0 * Px.Ease.inOutSine((u - 0.42) / 0.58)


# the bell at loop time t: rim center (x, y), width, height, squeeze
static func bell(t: float) -> Dictionary:
	t = Px.wrap(t, D)
	var u := fmod(t, BEAT) / BEAT
	var c := squeeze(u)
	return {"x": 2.0 * sin((t / D) * TAU), "y": lift(u), "c": c, "W": W0 * (1.0 - 0.3 * c), "H": H0 * (1.0 + 0.24 * c)}


# the bell's half-width h px above its rim: a dome whose margin pulls in as it squeezes
static func halfW(h: float, B: Dictionary) -> float:
	if h > B.H:
		return -1.0
	var hw: float = (B.W / 2.0) * sqrt(maxf(0.0, 1.0 - (maxf(0.0, h) / B.H) ** 2))
	if h < B.H * 0.3:
		hw -= B.c * 2.4 * (1.0 - h / (B.H * 0.3))
	return hw


# the margin hangs in little scallops
static func scallop(dx: float, B: Dictionary) -> float:
	return 1.1 * maxf(0.0, sin((dx / (B.W / 2.0)) * PI * 4.0 + PI / 2.0))


static func drawBell(p: Px.Painter, C: Array, G: Array, B: Dictionary, t: float) -> void:
	var g: Lib.Grid = GRID.clear()
	var bx := Px.round(B.x)
	var by := Px.round(B.y)
	var inside := func(x: float, y: float) -> bool:
		var dx: float = x - B.x
		var h: float = B.y - y
		if h < -scallop(dx, B):
			return false
		var hw := halfW(maxf(0.0, h), B)
		return hw >= 0.0 and absf(dx) <= hw
	g.shade(-20.0, -26.0, 20.0, 3.0, func(x, y, o):
		var X: float = x + bx
		var Y: float = y + by
		if not inside.call(X, Y):
			return 0
		o.t = 1
		return C[3])
	g.depths(4)
	# the subumbrella: the hollow under the bell, seen through it as a fainter inner dome
	var iw: float = B.W * 0.36
	var ih: float = B.H * 0.66
	var lx: float = B.x - B.W * 0.22
	var ly: float = B.y - B.H * 0.78
	g.recolor(func(x, y, c, a, tag):
		if tag != 1:
			return c
		var X: float = x + bx + 0.5
		var Y: float = y + by + 0.5
		var d := g.depth(x, y)
		var dx: float = X - B.x
		var h: float = B.y - Y
		var v: float = h / B.H
		var i := g.idx(x, y)
		var col: int = C[3]
		var al := 0.26 + 0.2 * Px.clamp(v)
		var ie := (dx / iw) ** 2 + (maxf(0.0, h) / ih) ** 2
		if ie > 0.8 and ie < 1.12 and h > 0.5:
			col = C[4]
			al = 0.55
		if h < 1.0:
			col = C[5]
			al = 0.85
		if d == 2:
			col = C[5] if (v > 0.5 and dx < 0.0) else C[4]
			al = 0.75
		if d == 1:
			col = C[6] if (dx < 0.0 and v > 0.25) else C[5]
			al = 0.92
		# the gloss on the top-left of the dome
		var gx := X - lx
		var gy := Y - ly
		if d == 2 and dx < -1.0 and v > 0.45 and gx * gx + gy * gy < 26.0:
			col = C[7]
			al = 1.0
		g.a[i] = al
		return col)
	# radial canals running down from the crown
	for s in [-0.62, 0.62]:
		var h := 2.0
		while h < B.H - 2.0:
			var hw := halfW(h, B)
			var x: float = B.x + s * hw * 0.9
			var y: float = B.y - h
			if g.depth(x - bx, y - by) >= 3:
				g.setc(x - bx, y - by, C[4], 0.5)
			h += 1.0
	# the stomach and gonads: a soft glowing mass hung in the bell, brighter as it squeezes
	var pulse: float = 0.5 + 0.5 * B.c
	var cy: float = B.y - B.H * 0.42
	var rx: float = B.W * 0.2
	var ry: float = B.H * 0.2
	var y := floorf(cy - ry)
	while y <= cy + ry:
		var x := floorf(B.x - rx)
		while x <= B.x + rx:
			var d: float = ((x + 0.5 - B.x) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2
			if d > 1.0 or g.depth(x - bx, y - by) < 2:
				x += 1.0
				continue
			g.setc(x - bx, y - by, C[6] if d < 0.3 else (C[5] if d < 0.65 else C[4]), 0.9 if d < 0.3 else 0.6)
			x += 1.0
		y += 1.0
	g.outline(func(x, y, nx, ny): return 0 if ny > 0.0 else C[1], 0.9)
	g.draw(p, 1.0, bx, by)
	# the light inside, and the little lamps round the margin
	p.glow(B.x, B.y - B.H * 0.45, 30.0 + 6.0 * B.c, C[4], 0.22 + 0.12 * pulse)
	p.glow(B.x, B.y - B.H * 0.45, 11.0, C[6], 0.14 + 0.16 * pulse)
	for s in [-1.0, 1.0]:
		for q in [0.14, 0.42, 0.78]:
			var x: float = B.x + s * halfW(0.5, B) * q
			var yy: float = B.y + 1.0
			var tw: float = 0.6 + 0.4 * sin((t / D) * TAU * 3.0 + q * 9.0 + s)
			p.px(x, yy, G[3] if tw > 0.85 else G[2])
			p.glow(x, yy, 4.0, G[2], 0.4 * tw)


# a strand hanging from the bell: each point follows where its root was a moment ago, so the strand trails
# behind every thrust and billows as the bell sinks; a slow wave runs down it
static func strand(t: float, off: Callable, len_: float, step: float, lag: float, sway: float, ph: float, pull: float) -> Array:
	var pts := []
	var B1 := bell(t)
	var o1: Array = off.call(B1)
	var s := 0.0
	while s <= len_:
		var B := bell(t - s * lag)
		var relax := 1.0 - Px.clamp(B.c)
		var ox := Px.lerp(o1[0], off.call(B)[0], 0.4)
		var w := (0.3 + s * sway) * (0.55 + 0.65 * relax) * sin((t / D) * TAU * 2.0 - s * 0.11 + ph)
		pts.append([B.x + ox + w + ox * s * (0.009 * relax - 0.005 * pull * B.c), B.y + o1[1] + s * (0.88 + 0.05 * B.c)])
		s += step
	return pts


static func drawTentacle(p: Px.Painter, C: Array, G: Array, pts: Array, back: bool, t: float, i: int) -> void:
	var n := pts.size()
	for k in range(1, n):
		var u := k / float(n - 1)
		var x0: float = pts[k - 1][0]
		var y0: float = pts[k - 1][1]
		var x1: float = pts[k][0]
		var y1: float = pts[k][1]
		var c: int = (C[3] if u < 0.3 else (C[2] if u < 0.7 else C[1])) if back else (C[5] if u < 0.2 else (C[4] if u < 0.45 else (C[3] if u < 0.78 else C[2])))
		p.line(x0, y0, x1, y1, c)
	# stinging cells glinting along it
	if back:
		return
	var k := 3
	while k < n:
		var tw := sin((t / D) * TAU * 2.0 - k * 0.5 + i * 1.7)
		if tw < 0.3:
			k += 4
			continue
		var x: float = pts[k][0]
		var y: float = pts[k][1]
		p.px(x, y, G[3] if tw > 0.8 else G[2])
		p.glow(x, y, 3.5, G[2], 0.35 * tw)
		k += 4


# a frilled oral arm: a ribbon lit down its left edge, darker on its right, ruffled along both sides
static var ARMS := Lib.Grid.new(-40, -40, 80, 100)


static func drawArms(p: Px.Painter, C: Array, list: Array, back: bool) -> void:
	var g: Lib.Grid = ARMS.clear()
	var a := 0.6 if back else 0.88
	for arm: Dictionary in list:
		if arm.back != back:
			continue
		var pts: Array = arm.pts
		var n := pts.size()
		var lastRow := -1e9
		for k in range(1, n):
			var x0: float = pts[k - 1][0]
			var y0: float = pts[k - 1][1]
			var x1: float = pts[k][0]
			var y1: float = pts[k][1]
			var m := maxf(1.0, ceilf(absf(y1 - y0) * 2.0))
			var j := 0.0
			while j < m:
				var q := j / m
				var x := Px.lerp(x0, x1, q)
				var y := Px.lerp(y0, y1, q)
				var u := (k - 1 + q) / (n - 1)
				var wd := Px.lerp(2.2, 0.6, u)
				var i := -ceilf(wd)
				while i <= ceilf(wd):
					if absf(i) > wd + 0.2:
						i += 1.0
						continue
					g.setc(x + i, y, C[4 if back else 6] if i < 0.0 else (C[2 if back else 4] if i > 0.0 else C[3 if back else 5]), a)
					i += 1.0
				var row := floorf(y)
				if row != lastRow and fmod(row, 3.0) == 0.0 and u < 0.85:
					g.setc(x + ((-wd - 1.2) if fmod(row / 3.0, 2.0) != 0.0 else (wd + 1.2)), y, C[4 if back else 6], a)
				lastRow = row
				j += 1.0
	g.draw(p)


static func draw(p: Px.Painter, time: float, o: Dictionary) -> void:
	var t := Lib.shift(time, D, o.seed)
	var C := Px.fit(o.palette, 8)
	var G := Px.fit(o.glow, 4)
	var B := bell(t)
	# specks drifting in the water
	Px.cycle(t, D, 16, o.seed * 5 + 1, D, func(age, L, r):
		var x: float = r.range(-42.0, 42.0) + sin(age * 0.8 + r.next() * 6.0) * 3.0
		var y: float = r.range(-34.0, 66.0) + age * r.range(1.0, 4.0)
		var tw: float = sin(age * 2.2 + r.next() * 6.0)
		var a: float = minf(minf(1.0, age * 2.0), (L - age) * 2.0) * (0.35 + 0.35 * tw)
		p.dot(x, y, G[2] if tw > 0.8 else C[3], a))
	var tents := []
	var arms := []
	for i in 9:
		var r := Px.rng(o.seed, i, 4)
		var q := -0.88 + (1.76 * i) / 8.0 + r.range(-0.05, 0.05)
		var back := i % 2 == 1
		tents.append({"back": back, "i": i, "pts": strand(t, func(b): return [q * halfW(0.5, b), 0.5], r.range(36.0, 50.0), 1.5, 0.022, 0.065, r.range(0.0, TAU), 1.0)})
	for i in 4:
		var r := Px.rng(o.seed, i, 9)
		var q: float = [-0.32, -0.1, 0.12, 0.3][i]
		var back := i == 1 or i == 2
		arms.append({"back": back, "pts": strand(t, func(b): return [q * b.W * 0.5, -1.0], r.range(20.0, 27.0), 1.0, 0.03, 0.06, r.range(0.0, TAU) + i, 0.4)})
	# each squeeze shoves a ring of water out under the bell: a soft swirl of light that swells and thins
	for b in 2:
		var age := Px.wrap(t - b * BEAT - 0.05, D)
		if age > 0.9:
			continue
		var B0 := bell(b * BEAT + 0.05)
		var e := Px.Ease.outCubic(age / 0.9)
		var k := 1.0 - age / 0.9
		var cx: float = B0.x
		var cy: float = B0.y + 3.0 + 14.0 * e
		var rx: float = B0.W * 0.32 + 9.0 * e
		var ry := 1.5 + 2.5 * e
		for j in 8:
			var a := (j / 8.0) * TAU + e * 0.8
			p.glow(cx + cos(a) * rx, cy + sin(a) * ry, 5.0 + 3.0 * e, C[5], 0.14 * k)
		# plankton caught in the swirl, glinting as it spins
		for j in 7:
			var a := (j / 7.0) * TAU + e * 2.4 + b
			var x := cx + cos(a) * rx * 1.05
			var y := cy + sin(a) * ry * 1.4 - cos(a * 2.0) * 0.6
			if k < 0.15 and j % 2:
				continue
			p.dot(x, y, G[3] if sin(a) > 0.0 else G[2], minf(1.0, k * 2.5))
			p.glow(x, y, 3.0, G[2], 0.3 * k)
		# and a few bubbles squeezed out of the margin
		for i in 4:
			var r := Px.rng(o.seed, b, i, 13)
			var L := r.range(1.4, 2.2)
			var ag := Px.wrap(t - b * BEAT - 0.08 - i * 0.04, D)
			if ag > L:
				continue
			var rad := r.range(0.6, 1.5)
			var sx := r.sign()
			var x: float = B0.x + sx * (B0.W * 0.4 + r.range(0.0, 4.0) + ag * r.range(4.0, 10.0))
			var y: float = B0.y + 2.0 - (14.0 + 10.0 * rad) * ag + 6.0 * exp(-ag * 4.0)
			if y < -33.0:
				continue
			Lib.bubble(p, x + sin(ag * 5.0 + i) * 0.8, y, rad, [G[3], G[3], G[2], G[1]], minf(minf(minf(1.0, ag * 6.0), (L - ag) * 3.0), (y + 33.0) / 6.0))
	for a: Dictionary in tents:
		if a.back:
			drawTentacle(p, C, G, a.pts, true, t, a.i)
	drawArms(p, C, arms, true)
	drawBell(p, C, G, B, t)
	drawArms(p, C, arms, false)
	for a: Dictionary in tents:
		if not a.back:
			drawTentacle(p, C, G, a.pts, false, t, a.i)
	# bubbles wobbling up past it
	Px.cycle(t, D, 7, o.seed * 5 + 2, func(r): return r.range(1.8, 3.0), func(age, L, r):
		var rad: float = r.range(0.6, 1.4) if r.chance(0.6) else r.range(1.6, 2.6)
		var x0: float = r.range(-30.0, 30.0)
		var y0: float = r.range(10.0, 70.0)
		var v := 20.0 + 13.0 * rad
		var end := minf(L, (y0 + 30.0) / v)
		if age > end:
			return
		var ph: float = r.next() * TAU
		var x := x0 + sin(age * (4.0 + 2.0 / rad) + ph) * (0.6 + rad * 0.8)
		var y: float = y0 - v * age
		Lib.bubble(p, x, y, rad, [G[3], G[3], G[2], G[1]], minf(minf(1.0, age * 3.0), (end - age) * 3.0), 0.1 * sin(age * 9.0 + ph)))
	# a soft cool glow all round
	p.glow(B.x, B.y + 6.0, 58.0, C[3], 0.14)
