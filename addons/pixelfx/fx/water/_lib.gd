# Shared by the water effects: the water ramp, droplets that fly over a water surface seen at a low angle and
# land with rings, ripple trains, lacy foam, foam billows, wet stone. Files starting with _ are helpers.
# The droplet sprites (a pixel, a shaded 2x2, a round bead with a highlight, each trailing a tail along its
# motion) are adapted from Sprite Fusion's open-source blood (https://www.spritefusion.com/pixel-art-vfx/blood),
# MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/water/_lib.js@86fed1780753d72210930aa703a308e477987edf
extends RefCounted

const Px := preload("../../core/px.gd")
const Self := preload("_lib.gd")
const WHITE := Px.WHITE

## Water, deep to white: deep color only in shadow, tinted middles, white crests.
const WATER := ["#0a1630", "#123063", "#1b5596", "#2a7fc4", "#45a9e3", "#86d3f5", "#cdf1ff", "#ffffff"]
## Wet stone for props (lips, basins, vents), outline to highlight.
const ROCK := ["#141219", "#221f2b", "#34303f", "#4a4558", "#655f74", "#8a8498"]


## A droplet at (x, y) moving at (vx, vy) px/s: s 1 is a pixel, 2 a shaded 2x2, 3 a round bead with a
## highlight; a tail trails back along its motion, longer the faster it goes. C: an 8-step water ramp.
static func bead(p: Px.Painter, x: float, y: float, vx: float, vy: float, s: float, C: Array, a: float = 1.0) -> void:
	var sp := Px.hypot(vx, vy)
	if not sp:
		sp = 1.0
	var ux := vx / sp
	var uy := vy / sp
	var tail := minf(5.0, sp * 0.011)
	if tail >= 1.0:
		p.line(x - ux * (tail + 1.0), y - uy * (tail + 1.0), x - ux * 1.2, y - uy * 1.2, func(u: float): return C[3] if u < 0.45 else (C[5] if s > 1.0 else C[4]), a)
	if s >= 3.0:
		p.circle(x, y, 1.75, C[4], a)
		p.circle(x - 0.25, y - 0.25, 1.15, C[6], a)
		p.dot(x - 0.7, y - 0.7, WHITE, a)
	elif s >= 2.0:
		var X := floorf(x)
		var Y := floorf(y)
		p.dot(X, Y, WHITE, a)
		p.dot(X + 1.0, Y, C[6], a)
		p.dot(X, Y + 1.0, C[5], a)
		p.dot(X + 1.0, Y + 1.0, C[4], a)
	else:
		p.dot(x, y, C[6] if sp > 160.0 else C[5], a)


## Droplets in flight over a flat surface seen at a low angle: x across, z into the screen (negative is far),
## h height above the surface; on screen they sit at (x, z * sy - h). Gravity pulls h down; when a drop
## reaches the surface it calls onLand(drop) and is gone. add({ x, z, h, vx, vz, vh, s (1..3), life, delay }).
class Drops extends RefCounted:
	var sy: float
	var g: float
	var drag: float
	var onLand: Variant
	var list: Array = []
	var count: int:
		get: return list.size()

	func _init(opts: Dictionary = {}) -> void:
		sy = opts.get("sy", 0.22)
		g = opts.get("g", 820.0)
		drag = opts.get("drag", 0.35)
		onLand = opts.get("onLand")
		list = []

	func add(d: Dictionary) -> void:
		var life: float = d.life if d.get("life") != null else 4.0
		var q := {"x": 0.0, "z": 0.0, "h": 0.0, "vx": 0.0, "vz": 0.0, "vh": 0.0, "s": 1.0, "delay": 0.0}
		q.merge(d, true)
		q.life = life
		q.max = life
		list.append(q)

	func update(dt: float) -> void:
		var k := drag * dt
		var i := list.size() - 1
		while i >= 0:
			var d: Dictionary = list[i]
			if d.delay > 0:
				d.delay -= dt
				i -= 1
				continue
			d.life -= dt
			if d.life <= 0:
				list.remove_at(i)
				i -= 1
				continue
			d.vh -= g * dt
			d.vx -= d.vx * k
			d.vz -= d.vz * k
			d.vh -= d.vh * k * 0.5
			d.x += d.vx * dt
			d.z += d.vz * dt
			d.h += d.vh * dt
			if d.h <= 0 and d.vh < 0:
				d.h = 0.0
				list.remove_at(i)
				if onLand != null:
					onLand.call(d)
			i -= 1

	## Draw the drops behind z = 0 ("back"), in front of it ("front"), or all.
	func draw(p: Px.Painter, C: Array, layer: String = "") -> void:
		for d: Dictionary in list:
			if d.delay > 0 or (layer == "back" and d.z >= 0) or (layer == "front" and d.z < 0):
				continue
			var x: float = d.x
			var y: float = d.z * sy - d.h
			Self.bead(p, x, y, d.vx, d.vz * sy - d.vh, d.s, C, minf(1.0, d.life / 0.2))
			p.glow(x, y, 2.5 + d.s, C[5], 0.1 + 0.05 * d.s)


## A ripple on a surface seen at a low angle: a train of n crests gap px apart around (cx, cy), squashed by sy,
## the outer crest brightest. k 0..1+ strength: a crisp 1 px crest that steps down the ramp as k falls and
## only breaks into dashes at the very end. half: 0 the whole ring, -1 the far half (draw it behind things),
## 1 the near half. hot: a white crest. glint: a white catch-light on the near side. wob: px the crest wanders
## in and out round the ring, so it isn't a perfect ellipse.
static func ring(p: Px.Painter, cx: float, cy: float, r: float, sy: float, k: float, C: Array, opts: Dictionary = {}) -> void:
	var n: float = opts.get("n", 2.0)
	var gap: float = opts.get("gap", 3.0)
	var half: float = opts.get("half", 0.0)
	var hot: bool = opts.get("hot", false)
	var glint: float = opts.get("glint", 0.0)
	var seed: float = opts.get("seed", 0.0)
	var wob: float = opts.get("wob", 0.0)
	if k <= 0.02 or r < 0.5:
		return
	var j := 0
	while j < n:
		var rr := r - j * gap
		if rr < 0.6:
			break
		var kj := k * (1.0 - j * 0.42)
		var m := maxf(6.0, ceilf(rr * TAU * 1.3))
		var need := 1.15 - 2.3 * minf(1.0, kj * 1.25)
		var i := 0
		while i < m:
			var a := (i / m) * TAU
			var s := sin(a)
			var near := s > 0.0
			if (half > 0.0 and not near) or (half < 0.0 and near):
				i += 1
				continue
			# as it weakens the crest breaks into glinting dashes (whole pixels, no dither), fixed to the ring
			if Px.noise(a * 4.7 + seed * 13.1 + j * 5.3, seed) * 0.65 + Px.noise(a * 11.3 + seed * 7.7, seed + 3.0) * 0.35 < need:
				i += 1
				continue
			# the near side and the side toward the light (upper left) read brighter
			var lit := kj * (1.0 if near else 0.7) * (0.88 - 0.12 * cos(a))
			var c: int = WHITE if (hot and near and j == 0) else C[6 if lit > 0.7 else (5 if lit > 0.38 else 4)]
			var ra := (rr + wob * Px.noise(a * 2.6 + seed * 1.9 + j, seed + 11.0)) if wob else rr
			var x := cx + cos(a) * ra
			var y := cy + s * ra * sy
			p.dot(x, y, c)
			if j == 0:
				p.light(x, y, C[4], 0.3 * lit)
			i += 1
		j += 1
	if glint > 0.0 and half >= 0.0:
		var x := cx + cos(2.05) * r
		var y := cy + sin(2.05) * r * sy
		p.px(x, y, WHITE)
		p.glow(x, y, 3.0 + glint * 2.0, C[5], 0.35 * glint)


## Ripples that spread and fade: add(x, z, r0, r1, life, { n, gap, k, hot (seconds of white crest), glint, delay }).
## update(dt); draw(p, C, half) with half as in ring().
class Ripples extends RefCounted:
	var sy: float
	var list: Array = []
	var seq: Variant = null
	var count: int:
		get: return list.size()

	func _init(opts: Dictionary = {}) -> void:
		sy = opts.get("sy", 0.22)
		list = []

	func add(x: float, z: float, r0: float, r1: float, life: float, o: Dictionary = {}) -> void:
		seq = (seq if seq != null else 0) + 1
		list.append({"x": x, "z": z, "r0": r0, "r1": r1, "life": life, "age": -(o.delay if o.get("delay") != null else 0.0), "k": o.k if o.get("k") != null else 1.0, "n": o.n if o.get("n") != null else 2.0, "gap": o.gap if o.get("gap") != null else 3.0, "hot": o.hot if o.get("hot") != null else 0.1, "glint": o.glint if o.get("glint") != null else 0.0, "seed": seq})

	func update(dt: float) -> void:
		var i := list.size() - 1
		while i >= 0:
			list[i].age += dt
			if list[i].age >= list[i].life:
				list.remove_at(i)
			i -= 1

	func draw(p: Px.Painter, C: Array, half: float = 0.0) -> void:
		for q: Dictionary in list:
			if q.age < 0:
				continue
			var u: float = q.age / q.life
			var r: float = q.r0 + (q.r1 - q.r0) * (1.0 - pow(1.0 - u, 2.6))
			var k: float = q.k * pow(1.0 - u, 1.7)
			Self.ring(p, q.x, q.z * sy, r, sy, k, C, {"n": q.n, "gap": q.gap * (0.55 + 0.6 * u), "half": half, "hot": q.age < q.hot, "glint": q.glint * k, "seed": q.seed})


## Lacy foam floating on the surface around (cx, cy), over an rx x ry patch: the crests of a noise field make
## a white net with holes, thinning out as k falls (1 thick, 0 gone). t drifts it; seed picks the pattern.
static func lace(p: Px.Painter, cx: float, cy: float, rx: float, ry: float, k: float, C: Array, t: float, seed: float = 0.0) -> void:
	if k <= 0.01 or rx < 1.0:
		return
	var sy := ry / rx
	p.shade(cx - rx, cy - ry, cx + rx, cy + ry, func(x: float, y: float, o):
		var dx := (x - cx) / rx
		var dy := (y - cy) / ry
		var d := dx * dx + dy * dy
		if d > 1.0:
			return
		var u := (x - cx) * 0.36
		var v := ((y - cy) / sy) * 0.36
		var n := Px.noise2(u + seed * 7.13, v - t * 0.35, seed)
		var m := Px.noise2(u * 2.2 - t * 0.3, v * 2.2 + seed * 3.1, seed + 9.0)
		var net := 1.0 - absf(n) * 4.6 + m * 0.3
		var need := 1.02 - k * (1.15 - d * 0.9)
		if net < need:
			return
		o.c = WHITE if net > need + 0.4 else C[6])


## Mist: soft puffs with no hard edge (alpha falls off to the rim), lit on top, that swell, drift on a slowing
## push and thin away. add(x, y, vx, vy, r0, r1, life, color, a, delay); update(dt); draw(p, haze).
class Mist extends RefCounted:
	var list: Array = []
	var count: int:
		get: return list.size()

	func _init() -> void:
		list = []

	func add(x: float, y: float, vx: float, vy: float, r0: float, r1: float, life: float, c: Variant, a: float = 0.25, delay: float = 0.0) -> void:
		list.append({"x": x, "y": y, "vx": vx, "vy": vy, "r0": r0, "r1": r1, "life": life, "max": life, "c": Px.hex(c), "a": a, "delay": delay})

	func update(dt: float) -> void:
		var i := list.size() - 1
		while i >= 0:
			var m: Dictionary = list[i]
			if m.delay > 0:
				m.delay -= dt
				i -= 1
				continue
			m.life -= dt
			if m.life <= 0:
				list.remove_at(i)
				i -= 1
				continue
			m.vx -= m.vx * 2.4 * dt
			m.vy -= m.vy * 2.4 * dt + 7.0 * dt
			m.x += m.vx * dt
			m.y += m.vy * dt
			i -= 1

	func draw(p: Px.Painter, haze: Variant = null) -> void:
		for m: Dictionary in list:
			if m.delay > 0:
				continue
			var age: float = 1.0 - m.life / m.max
			var r: float = m.r0 + (m.r1 - m.r0) * (1.0 - pow(1.0 - age, 2.2))
			var a: float = m.a * minf(1.0, age / 0.12) * pow(1.0 - age, 1.4)
			if a < 0.01:
				continue
			p.disc(m.x, m.y, r, m.c, func(d: float): return a * (1.0 - d * d) * (1.0 - d * 0.5))
			p.disc(m.x - r * 0.2, m.y - r * 0.32, r * 0.55, WHITE, func(d: float): return a * 0.25 * (1.0 - d) * (1.0 - d))
			if haze:
				p.glow(m.x, m.y, r * 1.5, haze, (0.16 * a) / m.a * minf(1.0, m.a * 3.0))


## A billow of churning foam: a shadowed underside, a white body, a lit cap. a < 1 dithers it away.
static func billow(p: Px.Painter, x: float, y: float, r: float, C: Array, a: float = 1.0) -> void:
	if r < 0.9:
		p.dot(x, y, C[6], a)
		return
	p.circle(x + r * 0.12, y + r * 0.2, r, C[4], a)
	p.circle(x, y, r * 0.84, C[6], a)
	if r > 1.6:
		p.circle(x - r * 0.3, y - r * 0.32, r * 0.46, WHITE, a)


## A pebble or rock: lit upper left, shaded lower right, a dark rim. ST: a 6-step stone ramp (ROCK).
static func pebble(p: Px.Painter, x: float, y: float, r: float, ST: Array) -> void:
	p.shade(x - r - 1.0, y - r - 1.0, x + r + 1.0, y + r + 1.0, func(px: float, py: float, o):
		var dx := px - x
		var dy := py - y
		var d := Px.hypot(dx * 1.1, dy)
		if d > r + 0.8:
			return
		var lit := (dx + dy) / maxf(0.5, r)
		o.c = ST[0] if d > r else (ST[5] if lit < -0.7 else (ST[4] if lit < 0.2 else (ST[3] if lit < 0.8 else ST[2]))))


static func rock() -> Array:
	return ROCK.map(func(c): return Px.hex(c))
