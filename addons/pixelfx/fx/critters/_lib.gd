# The critters' kit. A creature is built in a small offscreen grid from shaded parts, given a 1 px outline
# (picked per side, so it can be darker in shadow and break into a highlight), then put on the painter, opaque
# or translucent. Pure loops also get loop-safe noise, springs, closed-form flight with a floor, and the
# toolkit's own particle looks for particles whose state is a function of time.
# The flame tongue and fire puff recipes are adapted from Sprite Fusion's open-source fire
# (https://www.spritefusion.com/pixel-art-vfx/fire), and the bubble from its open-source bubbles
# (https://www.spritefusion.com/pixel-art-vfx/bubbles), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/critters/_lib.js@4505e39fe72adae06dcb3f36e195ddb6f7f6ab7c
extends RefCounted

const Px := preload("../../core/px.gd")
const Self := preload("_lib.gd")
const WHITE := Px.WHITE
const SQRT2 := 1.4142135623730951


## The loop time for this critter: seeds other than 1 start it at a different point in its loop, so a crowd of
## the same critter doesn't move in lockstep.
static func shift(t: float, D: float, seed: float = 1.0) -> float:
	return Px.wrap(t + (seed - 1.0) * 0.618 * D, D)


## A curve through keyframes [[x, value], ...] that doesn't wrap: held flat before the first and after the last.
static func curve(x: float, list: Array) -> float:
	if x <= list[0][0]:
		return float(list[0][1])
	for i in range(1, list.size()):
		var x0: float = list[i - 1][0]
		var v0: float = list[i - 1][1]
		var x1: float = list[i][0]
		var v1: float = list[i][1]
		if x <= x1:
			var dx := x1 - x0
			var u := (x - x0) / (dx if dx else 1.0)
			return v0 + (v1 - v0) * u * u * (3.0 - 2.0 * u)
	return float(list[list.size() - 1][1])


## Smooth noise in -1..1 that repeats every D seconds: F bumps a loop (a whole number), off shifts it along,
## so lnoise(t, D, F, r * 0.4) wobbles along a flame and still loops.
static func lnoise(t: float, D: float, F: float, off: float = 0.0, seed: Variant = 0) -> float:
	return Px.tileNoise((t / D) * F + off, 0.5, F, 0.0, seed)


## A damped spring's swing after a kick: 1 at age 0, ringing at hz, dying at rate damp.
static func spring(age: float, hz: float, damp: float) -> float:
	return 0.0 if age < 0.0 else exp(-age * damp) * cos(age * hz * TAU)


## A ballistic body thrown from (x, y) at (vx, vy) px/s under gravity g, stopping on the floor y = floor.
## Returns { x, y, vx, vy, landed, at (time it landed), lx (where) }.
static func toss(x: float, y: float, vx: float, vy: float, age: float, g: float, floor_: float = 0.0) -> Dictionary:
	var tl := (-vy + sqrt(maxf(0.0, vy * vy + 2.0 * g * (floor_ - y)))) / g if g > 0.0 else INF
	if age < tl:
		return {"x": x + vx * age, "y": y + vy * age + 0.5 * g * age * age, "vx": vx, "vy": vy + g * age, "landed": false, "at": tl, "lx": x + vx * tl}
	return {"x": x + vx * tl, "y": floor_, "vx": 0.0, "vy": 0.0, "landed": true, "at": tl, "lx": x + vx * tl}


# Calls fn with as many of (a, b, c, d, e) as it declares (JS callbacks may take fewer arguments).
static func call5(fn: Callable, n: int, a: Variant, b: Variant = null, c: Variant = null, d: Variant = null, e: Variant = null) -> Variant:
	match n:
		0: return fn.call()
		1: return fn.call(a)
		2: return fn.call(a, b)
		3: return fn.call(a, b, c)
		4: return fn.call(a, b, c, d)
	return fn.call(a, b, c, d, e)


## A creature-sized canvas in local coordinates: cells [x0, x0 + w) x [y0, y0 + h), each a color and an alpha.
class Grid extends RefCounted:
	var x0: int
	var y0: int
	var w: int
	var h: int
	var c: PackedInt32Array
	var a: PackedFloat32Array
	var tag: PackedByteArray
	var o := {"a": 1.0, "t": 0}
	var d: Variant = null

	func _init(x0_: float, y0_: float, w_: int, h_: int) -> void:
		x0 = floori(x0_)
		y0 = floori(y0_)
		w = w_
		h = h_
		c = PackedInt32Array()
		c.resize(w * h)
		c.fill(0)
		a = PackedFloat32Array()
		a.resize(w * h)
		a.fill(0.0)
		tag = PackedByteArray()
		tag.resize(w * h)
		tag.fill(0)

	func idx(x: float, y: float) -> int:
		var ix := floori(x) - x0
		var iy := floori(y) - y0
		return -1 if (ix < 0 or iy < 0 or ix >= w or iy >= h) else iy * w + ix

	## Paint a cell: color c, alpha a (below 1 is drawn translucent), tag (any 0..255 label for later passes). (JS: set)
	func setc(x: float, y: float, col: Variant, al: float = 1.0, tg: int = 0) -> void:
		var i := idx(x, y)
		if i >= 0 and col:
			c[i] = col
			a[i] = al
			tag[i] = tg

	## (JS: get) Unsigned, like a Uint32Array read.
	func getc(x: float, y: float) -> int:
		var i := idx(x, y)
		return 0 if i < 0 else (c[i] & 0xFFFFFFFF)

	func tagAt(x: float, y: float) -> int:
		var i := idx(x, y)
		return 0 if i < 0 else tag[i]

	func erase(x: float, y: float) -> void:
		var i := idx(x, y)
		if i >= 0:
			c[i] = 0

	## fn(x, y, out) at each cell center in the box returns a color (or 0 / undefined to leave it); it may set
	## out.a (alpha) and out.t (tag).
	func shade(x0_: float, y0_: float, x1: float, y1: float, fn: Callable) -> void:
		var oo := o
		var na := fn.get_argument_count()
		for y in range(floori(y0_), floori(y1) + 1):
			for x in range(floori(x0_), floori(x1) + 1):
				oo.a = 1.0
				oo.t = 0
				var col: Variant = fn.call(x + 0.5, y + 0.5, oo) if na >= 3 else fn.call(x + 0.5, y + 0.5)
				if col:
					setc(x, y, col, oo.a, oo.t)

	## Filled ellipse; c may be fn(nx, ny) of the normalized offset (-1..1), returning a color.
	func ellipse(cx: float, cy: float, rx: float, ry: float, col: Variant, al: float = 1.0) -> void:
		if rx <= 0.0 or ry <= 0.0:
			return
		var cf := col is Callable
		var cn: int = col.get_argument_count() if cf else 0
		shade(cx - rx, cy - ry, cx + rx, cy + ry, func(x, y, oo):
			var nx: float = (x - cx) / rx
			var ny: float = (y - cy) / ry
			if nx * nx + ny * ny > 1.0:
				return 0
			oo.a = al
			return Self.call5(col, cn, nx, ny) if cf else col)

	## 1 px line; c may be fn(u).
	func line(x0_: float, y0_: float, x1: float, y1: float, col: Variant, al: float = 1.0) -> void:
		var n := maxf(1.0, ceilf(maxf(absf(x1 - x0_), absf(y1 - y0_))))
		var cf := col is Callable
		var cn: int = col.get_argument_count() if cf else 0
		var i := 0.0
		while i <= n:
			setc(x0_ + ((x1 - x0_) * i) / n, y0_ + ((y1 - y0_) * i) / n, Self.call5(col, cn, i / n) if cf else col, al)
			i += 1.0

	## A line of discs, r may be fn(u): tails, tentacles, legs. c may be fn(u, v) with v 0 center .. 1 edge.
	func tube(pts: Array, r: Variant, col: Variant, al: float = 1.0) -> void:
		var rf := r is Callable
		var cf := col is Callable
		var cn: int = col.get_argument_count() if cf else 0
		for k in range(1, pts.size()):
			var ax: float = pts[k - 1][0]
			var ay: float = pts[k - 1][1]
			var bx: float = pts[k][0]
			var by: float = pts[k][1]
			var L := maxf(1.0, Px.hypot(bx - ax, by - ay))
			var s := 0.0
			while s <= L:
				var u := (k - 1 + s / L) / (pts.size() - 1)
				var rr: float = r.call(u) if rf else r
				var x := ax + ((bx - ax) * s) / L
				var y := ay + ((by - ay) * s) / L
				if rr < 0.75:
					setc(x, y, Self.call5(col, cn, u, 0.0) if cf else col, al)
					s += 0.5
					continue
				shade(x - rr, y - rr, x + rr, y + rr, func(px, py, oo):
					var dd: float = Px.hypot(px - x, py - y) / rr
					oo.a = al
					return 0 if dd > 1.0 else (Self.call5(col, cn, u, dd) if cf else col))
				s += 0.5

	## Filled polygon (even-odd); c may be fn(x, y).
	func poly(pts: Array, col: Variant, al: float = 1.0) -> void:
		var px0 := INF
		var py0 := INF
		var px1 := -INF
		var py1 := -INF
		for q in pts:
			var x: float = q[0]
			var y: float = q[1]
			px0 = minf(px0, x)
			px1 = maxf(px1, x)
			py0 = minf(py0, y)
			py1 = maxf(py1, y)
		var n := pts.size()
		var cf := col is Callable
		var cn: int = col.get_argument_count() if cf else 0
		shade(px0, py0, px1, py1, func(x, y, oo):
			var inside := false
			var j := n - 1
			for i in n:
				var xi: float = pts[i][0]
				var yi: float = pts[i][1]
				var xj: float = pts[j][0]
				var yj: float = pts[j][1]
				if (yi > y) != (yj > y) and x < ((xj - xi) * (y - yi)) / (yj - yi) + xi:
					inside = not inside
				j = i
			oo.a = al
			return (Self.call5(col, cn, x, y) if cf else col) if inside else 0)

	## A sprite from strings, its pixel (ax, ay) placed at (X, Y). opts: { sx, sy (scale), rot, flip }.
	## Scaled or turned sprites are resampled nearest-neighbour, so they stay hard pixels.
	func sprite(rows: Array, pal: Dictionary, X: float, Y: float, opts: Dictionary = {}) -> void:
		var ax: float = opts.get("ax", 0.0)
		var ay: float = opts.get("ay", 0.0)
		var sx: float = opts.get("sx", 1.0)
		var sy: float = opts.get("sy", 1.0)
		var rot: float = opts.get("rot", 0.0)
		var flip: bool = opts.get("flip", false)
		var H := rows.size()
		var W: int = String(rows[0]).length()
		var cache := {}
		var col := func(ch: String) -> Variant:
			if cache.has(ch):
				return cache[ch]
			cache[ch] = 0 if pal.get(ch) == null else Px.hex(pal[ch])
			return cache[ch]
		if sx == 1.0 and sy == 1.0 and rot == 0.0:
			for r in H:
				for q in W:
					var ch: String = String(rows[r])[W - 1 - q if flip else q]
					if ch == "." or ch == " ":
						continue
					var cc: Variant = col.call(ch)
					if cc:
						setc(Px.round(X - ((W - 1 - ax) if flip else ax)) + q, Px.round(Y - ay) + r, cc)
			return
		var cs := cos(rot)
		var sn := sin(rot)
		var R := Px.hypot(maxf(ax, W - ax) * absf(sx), maxf(ay, H - ay) * absf(sy)) + 1.0
		shade(X - R, Y - R, X + R, Y + R, func(x, y):
			var dx: float = x - X
			var dy: float = y - Y
			var u := (dx * cs + dy * sn) / sx
			var v := (-dx * sn + dy * cs) / sy
			var q := floori(ax + u)
			var r := floori(ay + v)
			if q < 0 or r < 0 or q >= W or r >= H:
				return 0
			if flip:
				q = W - 1 - q
			var ch: String = String(rows[r])[q]
			return 0 if (ch == "." or ch == " ") else col.call(ch))

	## How deep each filled cell sits: 1 on the edge (next to an empty cell, 4-neighbour), 2 one in, ... up to max.
	## Returns a Uint8Array over the grid (0 where empty); depth(x, y) reads it.
	func depths(max_: int = 4) -> PackedByteArray:
		var dd := PackedByteArray()
		dd.resize(w * h)
		dd.fill(0)
		var q := PackedInt32Array()
		for i in w * h:
			if not c[i]:
				continue
			var x := i % w
			var y := int(float(i) / w)
			if x == 0 or y == 0 or x == w - 1 or y == h - 1 or not c[i - 1] or not c[i + 1] or not c[i - w] or not c[i + w]:
				dd[i] = 1
				q.append(i)
		var k := 0
		while k < q.size():
			var i := q[k]
			var v := dd[i]
			k += 1
			if v >= max_:
				continue
			for j in [i - 1, i + 1, i - w, i + w]:
				if j >= 0 and j < w * h and c[j] and not dd[j]:
					dd[j] = v + 1
					q.append(j)
		for i in w * h:
			if c[i] and not dd[i]:
				dd[i] = max_
		d = dd
		return dd

	func depth(x: float, y: float) -> int:
		var i := idx(x, y)
		return 0 if (i < 0 or d == null) else d[i]

	## Wrap everything drawn so far in a 1 px outline (4-neighbour). c is a color, or fn(x, y, nx, ny) with
	## (nx, ny) the outward direction there (summed from the filled neighbours), so the outline can be picked
	## per side: darker under the light, broken where a highlight touches it. Return 0 to leave a gap.
	func outline(col: Variant, al: float = 1.0) -> void:
		var src := c.duplicate()
		var fn := col is Callable
		var cn: int = col.get_argument_count() if fn else 0
		for y in h:
			for x in w:
				var i := y * w + x
				if src[i]:
					continue
				var l: bool = x > 0 and src[i - 1] != 0
				var r: bool = x < w - 1 and src[i + 1] != 0
				var u: bool = y > 0 and src[i - w] != 0
				var dn: bool = y < h - 1 and src[i + w] != 0
				if not (l or r or u or dn):
					continue
				var cc: Variant = Self.call5(col, cn, float(x0 + x), float(y0 + y), (1.0 if l else 0.0) - (1.0 if r else 0.0), (1.0 if u else 0.0) - (1.0 if dn else 0.0)) if fn else col
				if cc:
					c[i] = cc
					a[i] = al
					tag[i] = 255

	## Rework every filled cell: fn(x, y, color, alpha, tag) returns its new color (0 erases it).
	func recolor(fn: Callable) -> void:
		var na := fn.get_argument_count()
		for i in w * h:
			if not c[i]:
				continue
			var v: Variant = Self.call5(fn, na, float(x0 + (i % w)), float(y0 + int(float(i) / w)), c[i], a[i], tag[i])
			c[i] = v if v else 0

	## Put the grid on the painter, moved by (dx, dy): opaque cells dithered by fade, translucent ones blended.
	func draw(p: Px.Painter, fade: float = 1.0, dx: float = 0.0, dy: float = 0.0) -> void:
		var X := x0 + Px.round(dx)
		var Y := y0 + Px.round(dy)
		for y in h:
			for x in w:
				var i := y * w + x
				var cc := c[i]
				if not cc:
					continue
				var al := a[i]
				if al >= 0.999:
					p.dot(X + x, Y + y, cc, fade)
				else:
					p.blend(X + x, Y + y, cc, al * fade)

	func clear():
		c.fill(0)
		tag.fill(0)
		d = null
		return self


## The toolkit's particle looks for particles whose state is a function of time (pure loops): begin(t), then
## add(kind, x, y, vx, vy, age, life, color, size, flag, seed) for each one alive now, then draw(p, layer).
## opts as for core Particles: { sparks: [head..tail], haze }.
class Swarm extends RefCounted:
	var ps: Px.Particles

	func _init(opts: Dictionary = {}) -> void:
		ps = Px.Particles.new(Px.merge({"rng": Px.Rng.new(1)}, opts))

	func begin(t: float):
		ps.list.clear()
		ps.t = t
		return self

	func add(k: int, x: float, y: float, vx: float, vy: float, age: float, life: float, col: Variant = WHITE, size: float = 1.0, flag: int = 0, seed: float = 0.0) -> void:
		if age < 0.0 or age >= life:
			return
		ps.list.append({"k": k, "x": x, "y": y, "vx": vx, "vy": vy, "life": life - age, "max": life, "col": Px.hex(col) if col else 0, "size": size, "seed": seed, "delay": 0.0, "flag": flag})

	func draw(p: Px.Painter, layer: Variant = null) -> void:
		ps.draw(p, layer)


# Hugo's flame layers: [width, height, ramp step] from the widest dark outer flame to the white-hot heart
const LAYERS := [[1.0, 1.0, 6], [0.76, 0.86, 4], [0.54, 0.68, 2], [0.3, 0.42, 0]]


## A tongue of flame standing on (x, y), h tall, w half-wide at its root, its tip swaying sx px; four nested
## layers down a 9-step fire ramp given bright-first (heat[0] white). n seeds its flicker; t, D keep it looping.
## only: draw just that layer (0 outer .. 3 heart), so a bunch of tongues can be laid down layer by layer and
## merge into one flame with one dark rim.
static func tongue(p: Px.Painter, x: float, y: float, h: float, w: float, sx: float, t: float, D: float, n: float, heat: Array, only: int = -1) -> void:
	if h < 1.0:
		return
	var F1 := maxf(1.0, Px.round(9.0 * D))
	var F2 := maxf(1.0, Px.round(4.0 * D))
	for li in LAYERS.size():
		if only >= 0 and li != only:
			continue
		var lw: float = LAYERS[li][0]
		var lh: float = LAYERS[li][1]
		var ri: int = LAYERS[li][2]
		var H := h * lh
		var col: int = heat[ri]
		var r := 0.0
		while r <= H:
			var u := r / maxf(1.0, H)
			var half := w * lw * pow(1.0 - u, 0.85) * minf(1.0, (r + 1.5) / 3.5) + lnoise(t, D, F1, r * 0.45, n) * 0.5
			var cx := x + sx * u * u * lh + lnoise(t, D, F2, r * 0.2, n + 7.0) * u * 1.1
			if half < 0.3:
				r += 1.0
				continue
			var px := Px.round(cx - half)
			while px <= Px.round(cx + half):
				p.px(px, Px.round(y - r), col)
				px += 1.0
			r += 1.0


## A puff of flame k of its life left (1 new .. 0 gone), size px, cooling down heat (bright-first, 9 steps):
## a darker rim, a lit core, a tongue on top, light.
static func firePuff(p: Px.Painter, x: float, y: float, k: float, size: float, seed: float, heat: Array) -> void:
	var age := 1.0 - k
	var n := heat.size()
	var hot := minf(0.999, pow(age, 0.62) + fmod(seed, 1.0) * 0.1)
	var idx := mini(n - 2, floori(hot * (n - 1)))
	var r := size * (0.55 + 0.45 * minf(1.0, age * 7.0)) * (1.0 - age * 0.55)
	var c: int = heat[idx]
	if idx >= n - 2:
		p.disc(x, y, r, c, minf(1.0, k * 3.0) * 0.85)
		return
	p.circle(x, y, r, heat[mini(n - 1, idx + 2)])
	p.circle(x - r * 0.16, y - r * 0.22, r * 0.78, c)
	if r > 1.6:
		p.circle(x, y - r * 0.9, r * 0.42, c)
	if idx <= 3 and r > 1.8:
		p.circle(x - r * 0.28, y - r * 0.34, r * 0.36, heat[maxi(0, idx - 1)])
	if idx < 6:
		p.glow(x, y, r * 2.4 + 2.0, c, 0.18 * k)


## A bubble of radius r: a rim lit top-left and shaded bottom-right, a faint fill, a white glint, light.
## cols: [highlight, lit, rim, shade]. Adapted from Sprite Fusion's open-source bubbles
## (https://www.spritefusion.com/pixel-art-vfx/bubbles), MIT License, Copyright (c) 2026 Hugo Duprez.
static func bubble(p: Px.Painter, cx: float, cy: float, r: float, cols: Array, a: float = 1.0, wob: float = 0.0) -> void:
	var HI: int = cols[0]
	var LIT: int = cols[1]
	var RIM: int = cols[2]
	var SHADE: int = cols[3]
	if r < 0.9:
		p.dot(cx, cy, RIM if r < 0.7 else LIT, a)
		return
	if r < 1.5:
		var px := floorf(cx)
		var py := floorf(cy)
		p.dot(px, py, HI, a)
		p.dot(px + 1.0, py, LIT, a)
		p.dot(px, py + 1.0, RIM, a)
		p.dot(px + 1.0, py + 1.0, SHADE, a)
		p.glow(cx + 0.5, cy + 0.5, 3.0, LIT, 0.12 * a)
		return
	var rx := r * (1.0 + wob)
	var ry := r * (1.0 - wob)
	var y := floorf(cy - ry - 1.0)
	while y <= ceilf(cy + ry + 1.0):
		var x := floorf(cx - rx - 1.0)
		while x <= ceilf(cx + rx + 1.0):
			var dx := (x + 0.5 - cx) / rx
			var dy := (y + 0.5 - cy) / ry
			var d := sqrt(dx * dx + dy * dy) * r
			if d > r + 0.5:
				x += 1.0
				continue
			var l := (-dx - dy) / SQRT2 / maxf(0.01, d / r)
			if d > r - 0.6:
				p.dot(x, y, LIT if l > 0.45 else (SHADE if l < -0.55 else RIM), a)
			x += 1.0
		y += 1.0
	var hx := Px.round(cx - rx * 0.45)
	var hy := Px.round(cy - ry * 0.45)
	p.dot(hx, hy, HI, a)
	if r >= 2.5:
		p.dot(hx + 1.0, hy, LIT, a)
		p.dot(hx, hy + 1.0, LIT, a)
	if r >= 2.0:
		p.dot(Px.round(cx + rx * 0.5), Px.round(cy + ry * 0.5), LIT, a)
	p.glow(cx, cy, r * 2.4 + 2.0, RIM, 0.14 * a)


## A soft shadow: an ellipse blended over what's there, a alpha at the center fading to nothing at the rim.
static func shadow(p: Px.Painter, cx: float, cy: float, rx: float, ry: float, c: int, a: float) -> void:
	if rx <= 0.0 or ry <= 0.0 or a <= 0.0:
		return
	var y := floorf(cy - ry)
	while y <= ceilf(cy + ry):
		var x := floorf(cx - rx)
		while x <= ceilf(cx + rx):
			var d := ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2
			if d < 1.0:
				p.blend(x, y, c, a * (1.0 - d) ** 0.7)
			x += 1.0
		y += 1.0


## A ballistic body thrown from (x, y) at (vx, vy) under gravity g that bounces on the floor y = floor, keeping
## e of its speed each bounce (and 70% of its run), until it rests. Returns { x, y, vx, vy, hops, rest }.
static func bounce(x: float, y: float, vx: float, vy: float, age: float, g: float, floor_: float = 0.0, e: float = 0.45) -> Dictionary:
	var hops := 0
	while hops < 6:
		var f := toss(x, y, vx, vy, age, g, floor_)
		if not f.landed:
			return {"x": f.x, "y": f.y, "vx": f.vx, "vy": f.vy, "hops": hops, "rest": false}
		var vl: float = vy + g * f.at
		age -= f.at
		x = f.lx
		y = floor_ - 0.01
		vx *= 0.7
		vy = -vl * e
		if absf(vy) < 25.0:
			break
		hops += 1
	return {"x": x, "y": floor_ - 0.25, "vx": 0.0, "vy": 0.0, "hops": hops, "rest": true}
