# The flame puff (after sim.js's FIRE) and the swirling pull (attract) are adapted from Sprite Fusion's
# open-source black-hole (https://www.spritefusion.com/pixel-art-vfx/black-hole),
# MIT License, Copyright (c) 2026 Hugo Duprez.
#
# Shared bits for the shadow effects (files starting with _ are helpers, not effects): the void palette,
# light that black shapes cut, smoke lit from one side, violet flame, obsidian slivers, ink drops.
# port-of: src/fx/shadow/_lib.js@656b0e570c2ac558f9ad04a7f410c81e1f9687f4
extends RefCounted

const Px := preload("../../core/px.gd")
const WHITE := Px.WHITE
const GRAVITY := Px.GRAVITY

## Dark magic, dark to bright: void black, deep violet, a white-lilac edge.
const VOID := ["#06040b", "#150c26", "#2a1150", "#461a84", "#6f2cc0", "#9d5cec", "#cfa6ff", "#f6eaff"]


## Take the light back off every pixel in a local box where dark(x, y) is true, keeping a share keep (0..1):
## call it last, so black shapes stay black under every glow, spark and ring drawn before.
static func unlight(p: Px.Painter, x0: float, y0: float, x1: float, y1: float, dark: Callable, keep: float = 0.0) -> void:
	var L := p.L
	var w := p.w
	var ox := p.ox
	var oy := p.oy
	p.each(x0, y0, x1, y1, func(x, y, sx, sy):
		if not dark.call(x, y):
			return
		var i: int = (sy - oy) * w + (sx - ox)
		var d: int = L[i]
		if not d:
			return
		if keep <= 0.0:
			L[i] = 0
		else:
			L[i] = -16777216 | (int(((d >> 16) & 255) * keep) << 16) | (int(((d >> 8) & 255) * keep) << 8) | int((d & 255) * keep))


# the pixel cells of the annulus r0 <= d < r1 round (x, y), row by row, jumping the hole: fn(cx, cy, d)
static func annulus(x: float, y: float, r0: float, r1: float, fn: Callable) -> void:
	var r02 := r0 * r0 if r0 > 0.0 else -1.0
	var r12 := r1 * r1
	var py := floorf(y - r1)
	while py <= ceilf(y + r1):
		var cy := py + 0.5
		var dy := cy - y
		var dy2 := dy * dy
		if dy2 >= r12:
			py += 1.0
			continue
		var xo := sqrt(r12 - dy2)
		var xi := sqrt(r02 - dy2) if dy2 < r02 else 0.0
		var px := floorf(x - xo)
		var x1 := ceilf(x + xo)
		while px <= x1:
			var cx := px + 0.5
			var dx := cx - x
			if xi > 0.0 and dx > -xi and dx < xi:
				px = maxf(px, floorf(x + xi) - 1.0)
				px += 1.0
				continue
			var d2 := dx * dx + dy2
			if d2 < r12 and d2 >= r02:
				fn.call(cx, cy, sqrt(d2))
			px += 1.0
		py += 1.0


## A ring from radius r - w out to r round (x, y), like p.ring (c and a may be Callables of v: 0 inner to 1
## outer, and angle) but visiting only the band's own pixels, so a big thin shock ring stays cheap.
static func ringFast(p: Px.Painter, x: float, y: float, r: float, w: float, c: Variant, a: Variant = 1.0) -> void:
	if r <= 0.0:
		return
	var r0 := maxf(0.0, r - w)
	var fc := c is Callable
	var fa := a is Callable
	var cn: int = c.get_argument_count() if fc else 0
	var an: int = a.get_argument_count() if fa else 0
	var span := r - r0
	annulus(x, y, r0, r, func(cx, cy, d):
		var v: float = (d - r0) / (span if span else 1.0)
		var ang: float = atan2(cy - y, cx - x) if (fc or fa) else 0.0
		p.dot(cx, cy, Px.call4(c, cn, v, ang) if fc else c, Px.call4(a, an, v, ang) if fa else a))


## Light hugging a circle of radius R at (x, y), falling off over w either side, only where keep(x, y).
static func ringLight(p: Px.Painter, x: float, y: float, R: float, w: float, c: Variant, k: float, keep: Variant = null) -> void:
	if w < 1.0 or k <= 0.004:
		return
	var col := Px.hex(c)
	var has_keep := keep is Callable
	annulus(x, y, maxf(0.0, R - w), R + w, func(cx, cy, d):
		if has_keep and not keep.call(cx, cy):
			return
		var f: float = 1.0 - absf(d - R) / w
		p.light(cx, cy, col, f * f * k))


## A ring of light hugging a black disc: k at radius r0, falling to nothing at r1, and none inside r0.
static func halo(p: Px.Painter, x: float, y: float, r0: float, r1: float, c: Variant, k: float) -> void:
	if r1 <= r0 or k <= 0.004:
		return
	var col := Px.hex(c)
	var w := r1 - r0
	annulus(x, y, maxf(0.0, r0), r1, func(cx, cy, d):
		var f: float = 1.0 - (d - r0) / w
		p.light(cx, cy, col, f * f * k))


## A black star rasterized once: four long arms (L) and four short ones, turned rot, at (0, cy), its cells
## in a grid. { at(x, y) } says if a local point is black; draw(p, c, rim, skip) fills it and burns a rim on
## the cells just outside it (except where skip(x, y)). The arms keep a 1 px black spine to their tips.
static func blackStar(cy: float, L: float, rot: float, short: float = 0.46, q: float = 0.32) -> Star:
	var R0 := ceili(L) + 2
	var n := R0 * 2 + 1
	var data := PackedByteArray()
	data.resize(n * n)
	data.fill(0)
	for j in n:
		for i in n:
			var x := i - R0 + 0.5
			var y := cy + j - R0 + 0.5
			if inStar(x, y, 0.0, cy, L, rot, q) or inStar(x, y, 0.0, cy, L * short, rot + PI / 4.0, q):
				data[j * n + i] = 1
	for a in 4:
		var d := 0.0
		var ca := cos(rot + (a * PI) / 2.0)
		var sa := sin(rot + (a * PI) / 2.0)
		while d < L - 1.0:
			var i := floori(ca * d) + R0
			var j := floori(sa * d) + R0
			data[j * n + i] = 1
			d += 0.5
	return Star.new(cy, R0, n, data)


class Star extends RefCounted:
	var cy: float
	var R0: int
	var n: int
	var data: PackedByteArray

	func _init(cy_: float, R0_: int, n_: int, data_: PackedByteArray) -> void:
		cy = cy_
		R0 = R0_
		n = n_
		data = data_

	func at(x: float, y: float) -> bool:
		var i := floori(x) + R0
		var j := floori(y - cy) + R0
		return i >= 0 and j >= 0 and i < n and j < n and data[j * n + i] == 1

	## take the light off its black cells (call last, like unlight)
	func unlight(p: Px.Painter) -> void:
		var Lb := p.L
		var w := p.w
		var h := p.h
		var ox := p.ox
		var oy := p.oy
		for j in n:
			for i in n:
				if not data[j * n + i]:
					continue
				var x := i - R0 + 0.5
				var y := cy + j - R0 + 0.5
				var sx := p.cellX(x, y) - ox
				var sy := p.cellY(x, y) - oy
				if sx >= 0 and sy >= 0 and sx < w and sy < h:
					Lb[sy * w + sx] = 0

	func draw(p: Px.Painter, c: Variant, rim: Variant, skip: Callable) -> void:
		for j in n:
			for i in n:
				var x := i - R0 + 0.5
				var y := cy + j - R0 + 0.5
				if data[j * n + i]:
					p.px(x, y, c)
				elif rim and not skip.call(x, y) and (at(x - 1.0, y) or at(x + 1.0, y) or at(x, y - 1.0) or at(x, y + 1.0)):
					p.px(x, y, rim)


## Is (x, y) inside a four-point star at (cx, cy), arms L long, turned rot? q < 1 hollows the sides into thin spikes.
static func inStar(x: float, y: float, cx: float, cy: float, L: float, rot: float, q: float = 0.42) -> bool:
	if L <= 0.0:
		return false
	var c := cos(rot)
	var s := sin(rot)
	var dx := x - cx
	var dy := y - cy
	var u := absf(dx * c + dy * s) / L
	var v := absf(-dx * s + dy * c) / L
	# inside needs the smaller of u, v under 0.5^(1/q): most points fail that before any pow
	return u < 1.0 and v < 1.0 and minf(u, v) <= pow(0.5, 1.0 / q) and pow(u, q) + pow(v, q) <= 1.0


## Pull particles (anything with x, y, vx, vy) toward (x, y): gravity softened at r0, a swirl round it, drag
## that grows inside reach. Those that reach r0 are eaten (removed); returns how many. w(q) weighs each one
## (0 leaves it alone).
static func attract(list: Array, x: float, y: float, G: float, reach: float, swirl: float, r0: float, dt: float, w: Variant = null, vmax: float = INF) -> int:
	var eaten := 0
	var wf := w is Callable
	var wn: int = w.get_argument_count() if wf else 0
	for i in range(list.size() - 1, -1, -1):
		var q: Dictionary = list[i]
		var wt: float = Px.call4(w, wn, q) if wf else 1.0
		if not wt or q.delay > 0.0:
			continue
		var dx: float = x - q.x
		var dy: float = y - q.y
		var d2 := dx * dx + dy * dy
		if d2 > reach * reach:
			continue
		var d := sqrt(d2)
		if not d:
			d = 1.0
		if d < r0:
			list.remove_at(i)
			eaten += 1
			continue
		var a := (G / (d2 + r0 * r0)) * minf(1.0, (reach - d) / (reach * 0.25)) * wt * dt
		var ux := dx / d
		var uy := dy / d
		q.vx += (ux - uy * swirl) * a
		q.vy += (uy + ux * swirl) * a
		var drag := minf(0.2, (1.0 - d / reach) * 1.6 * dt)
		q.vx -= q.vx * drag
		q.vy -= q.vy * drag
		var v := Px.hypot(q.vx, q.vy)
		if v > vmax:
			q.vx *= vmax / v
			q.vy *= vmax / v
	return eaten


## Puff kinds: FLAME (a ball of flame cooling down a ramp), SOOT (dark smoke lit on the side facing a light).
const PK := {"FLAME": 0, "SOOT": 1}


## Violet flame and dark smoke. opts: { rng, flame: ramp white-hot to burnt out, soot: [fresh, old] smoke
## colours, cap: the soot's dim lit top, rim: [hot, warm, dim] colours of its lit side, floor: (x) => y }.
## spawn(kind, x, y, vx, vy, life, size, delay, smokes): smokes turns a dying flame into soot.
## draw(p, kind, light): light = { x, y, k, reach } is what the soot's rims face (k 0 leaves them dark).
class Puffs extends RefCounted:
	var R: Px.Rng
	var list: Array = []
	var t := 0.0
	var F: Array
	var soot: Array
	var cap: int
	var rim: Array
	var floor_: Variant = null
	var _fn := 0
	var count: int:
		get: return list.size()

	func _init(o: Dictionary) -> void:
		R = o.rng
		list = []
		t = 0.0
		F = Px.ramp(o.flame)
		soot = Px.ramp(o.soot)
		cap = Px.hex(o.cap)
		rim = Px.ramp(o.rim)
		floor_ = o.get("floor")
		_fn = floor_.get_argument_count() if floor_ is Callable else 0

	func spawn(k: int, x: float, y: float, vx: float, vy: float, life: float, size: float, delay: float = 0.0, smokes: bool = false) -> void:
		list.append({"k": k, "x": x, "y": y, "vx": vx, "vy": vy, "life": life, "max": life, "size": size, "delay": delay, "smokes": smokes, "seed": R.next() * 100.0})

	func update(dt: float) -> void:
		t += dt
		var tt := t
		for i in range(list.size() - 1, -1, -1):
			var q: Dictionary = list[i]
			if q.delay > 0.0:
				q.delay -= dt
				continue
			q.life -= dt
			if q.life <= 0.0:
				if q.k == PK.FLAME and q.smokes:
					spawn(PK.SOOT, q.x, q.y - 1.0, q.vx * 0.5, q.vy * 0.5 - 6.0, R.range(0.9, 1.6), q.size * 1.25)
				list.remove_at(i)
				continue
			if q.k == PK.FLAME:
				q.vy -= 95.0 * dt
				q.vx += sin(tt * 17.0 + q.seed) * 30.0 * dt
				q.vx -= q.vx * 5.0 * dt
				q.vy -= q.vy * 3.2 * dt
			else:
				q.vy -= 18.0 * dt
				q.vx += sin(tt * 1.3 + q.seed) * 8.0 * dt
				q.vx -= q.vx * 1.6 * dt
				q.vy -= q.vy * 1.3 * dt
			q.x += q.vx * dt
			q.y += q.vy * dt
			# smoke rolls along the floor rather than through it
			if floor_ != null and q.k == PK.SOOT:
				var f: float = (floor_.call(q.x) if _fn >= 1 else floor_.call()) - q.size * 0.6
				if q.y > f:
					q.y = f
					q.vy = minf(0.0, q.vy)
					q.vx *= 1.0 - 2.0 * dt

	func draw(p: Px.Painter, kind: int, light: Variant = null) -> void:
		var n := F.size()
		for q: Dictionary in list:
			if q.delay > 0.0 or q.k != kind:
				continue
			var k: float = q.life / q.max
			var age := 1.0 - k
			var x: float = q.x
			var y: float = q.y
			if q.k == PK.FLAME:
				# a ball of flame: a darker rim, a lit core up and left, a tongue on top, a hot heart while young
				var heat := minf(0.999, pow(age, 0.62) + fmod(q.seed, 1.0) * 0.1)
				var idx := mini(n - 2, floori(heat * (n - 1)))
				var rf: float = q.size * (0.55 + 0.45 * minf(1.0, age * 7.0)) * (1.0 - age * 0.55)
				var c: int = F[idx]
				if idx >= n - 3:
					p.disc(x, y, rf, c, minf(1.0, k * 3.0) * 0.8)
				else:
					p.circle(x, y, rf, F[mini(n - 1, idx + 2)])
					p.circle(x - rf * 0.16, y - rf * 0.22, rf * 0.78, c)
					if rf > 1.6:
						p.circle(x, y - rf * 0.9, rf * 0.42, c)
					if idx <= 3 and rf > 1.8:
						p.circle(x - rf * 0.28, y - rf * 0.34, rf * 0.36, F[maxi(0, idx - 1)])
					if idx < 6:
						p.glow(x, y, rf * 2.4 + 2.0, c, 0.2 * k)
				continue
			# soot: a soft body and a denser core, a dim cap on top, and lit from the side facing the light by two
			# discs pushed toward it (a soft wash over the near half, a brighter lip at its edge)
			var r: float = q.size * (0.65 + minf(1.0, age * 2.5) * 0.45 + age * 0.45)
			var a := minf(1.0, age * 10.0) * minf(1.0, k * 2.2) * 0.72
			var body := Px.mix(soot[0], soot[1], age)
			# one pass for the body: thinner at the edge, denser in the core (two layers' worth)
			var edge := a * 0.5
			var core := 1.0 - (1.0 - a * 0.5) * (1.0 - a * 0.62)
			p.disc(x, y + r * 0.06, r, body, func(d): return core if d < 0.72 else edge)
			var lk: float = light.k if light != null else 0.0
			if lk < 0.5:
				p.disc(x - r * 0.2, y - r * 0.32, r * 0.48, cap, a * 0.32 * (1.0 - age * 0.7) * (1.0 - lk * 2.0))
			if lk <= 0.02:
				continue
			var lx: float = light.x - x
			var ly: float = light.y - y
			var dl := sqrt(lx * lx + ly * ly)
			if not dl:
				dl = 1.0
			var ux := lx / dl
			var uy := ly / dl
			var lit := minf(1.0, light.k * Px.clamp(1.3 - dl / light.reach)) * a
			if lit <= 0.02:
				continue
			var hot: int = rim[0]
			var warm: int = rim[1]
			var dim: int = rim[2]
			p.disc(x + ux * r * 0.26, y + uy * r * 0.26, r * 0.72, dim, lit * 0.55)
			p.disc(x + ux * r * 0.5, y + uy * r * 0.5, r * 0.46, warm, lit * 0.5)
			if r > 3.0:
				p.disc(x + ux * r * 0.68, y + uy * r * 0.68, r * 0.24, hot, lit * 0.4)


## An obsidian shard from core Bits ({ x, y, a, s, life }): a thin triangle pointing along its spin angle, a
## dark violet body, the long edge facing the light at (lx, ly) lit (brighter with lk), the other in shadow,
## a white glint at the tip while the light is strong. C is an 8-step palette.
static func shard(p: Px.Painter, b: Dictionary, C: Array, lx: float, ly: float, lk: float) -> void:
	var fa := minf(1.0, b.life / 0.4)
	var ca := cos(b.a)
	var sa := sin(b.a)
	var L := maxf(2.0, b.s)
	var W := maxf(2.0, L * 0.55)
	var bx: float = b.x
	var by: float = b.y
	var side := 1.0 if -sa * (lx - bx) + ca * (ly - by) > 0.0 else -1.0
	var rim: int = C[6] if lk > 0.6 else (C[5] if lk > 0.3 else (C[4] if lk > 0.08 else C[3]))
	var E := L / 2.0 + 1.5
	p.shade(bx - E, by - E, bx + E, by + E, func(x, y, out):
		var dx: float = x - bx
		var dy: float = y - by
		var u := dx * ca + dy * sa
		var v := (-dx * sa + dy * ca) * side
		if u < -L / 2.0 - 0.4 or u > L / 2.0 + 0.4:
			return null
		var half := ((W / 2.0) * (L / 2.0 - u)) / L + 0.4
		if absf(v) > half:
			return null
		out.a = fa
		if u > L / 2.0 - 1.3 and lk > 0.3:
			return WHITE
		if v > half - 1.0:
			return rim if u > -L / 4.0 else C[maxi(3, C.find(rim) - 1)]
		return C[1] if v < -half + 1.0 else C[2])
	if lk > 0.04:
		p.glow(bx, by, 3.0 + L * 0.6, C[5], 0.2 * lk * fa)


## Ink drops: fly under gravity, land on the floor (y = floor(x)) and call onLand(x, y, speed).
## add(x, y, vx, vy, size); update(dt); draw(p, body, shine) draws a dark drop with a lit top.
class Drops extends RefCounted:
	var list: Array = []
	var floor_: Callable
	var _fn := 0
	var onLand: Variant = null
	var _ln := 0
	var g := 0.8

	func _init(o: Dictionary = {}) -> void:
		list = []
		floor_ = o.floor if o.get("floor") != null else func(): return 0.0
		_fn = floor_.get_argument_count()
		onLand = o.get("onLand")
		_ln = onLand.get_argument_count() if onLand is Callable else 0
		g = o.g if o.get("g") != null else 0.8

	func add(x: float, y: float, vx: float, vy: float, size: float = 1.0) -> void:
		list.append({"x": x, "y": y, "vx": vx, "vy": vy, "size": size})

	func update(dt: float) -> void:
		for i in range(list.size() - 1, -1, -1):
			var d: Dictionary = list[i]
			d.vy += GRAVITY * g * dt
			d.vx -= d.vx * 0.4 * dt
			d.x += d.vx * dt
			d.y += d.vy * dt
			var f: float = floor_.call(d.x) if _fn >= 1 else floor_.call()
			if d.vy > 0.0 and d.y >= f:
				if onLand is Callable:
					Px.call4(onLand, _ln, d.x, f, d.vy, d.size)
				list.remove_at(i)

	func draw(p: Px.Painter, body: Variant, shine: Variant) -> void:
		for d: Dictionary in list:
			var up: bool = d.vy < 0.0
			p.px(d.x, d.y, body)
			if d.size > 1.4:
				p.px(d.x, d.y + (1.0 if up else -1.0), body)
			p.px(d.x, d.y - (1.0 if (d.size > 1.4 and not up) else 0.0), shine)


## A dark pool opened in the floor, seen at a slant (radius rx, centred on the floor at x = 0): the far lip lit,
## the near lip dark, ripples ({ x, t0, life, w }) running out across it, a sheen along the far side, a wet fringe.
static func floorPool(p: Px.Painter, C: Array, rx: float, t: float, ripples: Array) -> void:
	if rx < 1.0:
		return
	var ry := rx * 0.17 + 0.6
	p.shade(-rx - 3.0, -ry - 2.0, rx + 3.0, ry + 2.0, func(x, y):
		var dx: float = x / rx
		var dy: float = (y - 0.5) / ry
		var d := sqrt(dx * dx + dy * dy)
		if d > 1.18:
			return null
		if d > 1.0:
			if dy < 0.0 and d < 1.09:
				return C[6] if absf(dx) < 0.55 else (C[5] if absf(dx) < 0.85 else C[4])
			if dy >= 0.0 and d < 1.09:
				return C[2]
			return C[1] if (y > -0.5 and Px.noise(x * 0.7, 9) > 0.15) else null
		# ripples: ellipses on the slanted surface, kept about a pixel thick all the way round
		for r: Dictionary in ripples:
			var age: float = t - r.t0
			var rr: float = age * 46.0 * r.w + 1.0
			var ex: float = x - r.x
			var ey: float = (y - 0.5) / 0.17
			var e := sqrt(ex * ex + ey * ey)
			if not e:
				e = 1.0
			var g := sqrt(ex * ex + pow(ey / 0.17, 2.0)) / e
			if absf(e - rr) < 0.55 * g and age < r.life:
				return C[4] if age < r.life * 0.5 else C[3]
		if dy < -0.55 and dy > -0.85 and Px.noise(x * 0.25 + t * 1.3, 4) > 0.2:
			return C[5] if Px.noise(x * 0.6 - t * 2.0, 6) > 0.55 else C[2]
		# the far inner wall catches the glow from below: violet just under the lip, falling to black
		if dy < -0.35 and d > 0.72:
			return C[3] if d > 0.9 else C[2]
		return C[1] if d > 0.86 else C[0])
