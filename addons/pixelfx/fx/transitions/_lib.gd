# Shared by the screen transitions: a 320 x 180 screen with its origin at the top-left. Each one covers the
# screen in o.color by about 45% of its duration, holds, then uncovers so the last frame is empty.
# glint() is adapted from Sprite Fusion's open-source sparkle (https://www.spritefusion.com/pixel-art-vfx/sparkle),
# MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/transitions/_lib.js@fe5cf27701e8bb771fab30bd5e2c06435d4e299c
extends RefCounted

const Px := preload("../../core/px.gd")
const WHITE := Px.WHITE

const W := 320
const H := 180


## The meta every transition shares; pass what differs.
static func screenMeta(m: Dictionary) -> Dictionary:
	var tags: Array = ["transition", "screen"] + m.tags + ["one-shot"]
	return {
		"name": m.name, "desc": m.desc, "tags": tags,
		"size": [W, H], "origin": [0, 0], "duration": m.duration, "loop": false, "fps": 30, "bg": "sky",
		"options": Px.merge({"color": "#0b0a10", "seed": 1}, m.options),
	}


# a painter that drops every pixel outside the screen
class Clipped extends Px.Painter:
	func inside(sx: int, sy: int) -> bool:
		var lx := fromX(sx + 0.5, sy + 0.5)
		var ly := fromY(sx + 0.5, sy + 0.5)
		return lx >= 0.0 and ly >= 0.0 and lx < W and ly < H

	func put(sx: int, sy: int, c: Variant, a: float = 1.0) -> void:
		if inside(sx, sy):
			super.put(sx, sy, c, a)

	func add(sx: int, sy: int, c: int, k: float = 1.0) -> void:
		if inside(sx, sy):
			super.add(sx, sy, c, k)

	func blendPx(sx: int, sy: int, c: Variant, a: float) -> void:
		if inside(sx, sy):
			super.blendPx(sx, sy, c, a)



## The painter, clipped to the screen: sparks, smoke and light that fly past an edge are cut there instead of
## spilling outside the canvas. Every drawing call goes through it unchanged. (One per painter, kept in step
## with it, so it stays the same shape of object every frame.)
static func clipTo(p: Px.Painter) -> Px.Painter:
	# kept on the painter itself, so it lives exactly as long as the painter (the JS WeakMap)
	var q: Px.Painter = p.get_meta("pfx_clip") if p.has_meta("pfx_clip") else null
	if q == null:
		q = Clipped.new(p.frame)
		p.set_meta("pfx_clip", q)
	q.reset()
	q.tx = p.tx
	q.ty = p.ty
	q.fx = p.fx
	q.cs = p.cs
	q.sn = p.sn
	q.fade = p.fade
	q.lightK = p.lightK
	q.layer = p.layer
	return q


# screen column of local pixel column x, for an unrotated painter: x maps to b + fx * x
static func unrotated(p: Px.Painter) -> bool:
	return p.sn == 0.0 and p.cs == 1.0

static func col0(p: Px.Painter) -> int:
	return floori(p.tx + 0.5) if p.fx > 0.0 else floori(p.tx - 0.5)


## p.rect(x, y, w, h, c) for opaque fills, mapping each row to the screen once instead of every pixel (the
## transitions fill a lot of screen); through p.rect itself when the painter is rotated.
static func rect(p: Px.Painter, x: float, y: float, w: float, h: float, c: Variant) -> void:
	if not unrotated(p):
		p.rect(x, y, w, h, c)
		return
	var X0 := Px.roundi(x)
	var X1 := Px.roundi(x + w)
	var Y0 := Px.roundi(y)
	var Y1 := Px.roundi(y + h)
	var fx := int(p.fx)
	var b := col0(p)
	for yy in range(Y0, Y1):
		var sy := floori(p.ty + yy + 0.5)
		for xx in range(X0, X1):
			p.put(b + fx * xx, sy, c, 1.0)


## Fill a convex polygon [[x, y], ...] row by row, clipped to the screen. c is a color or fn(x, y) -> color
## (0 skips the pixel); a is the alpha (dithered).
static func fillConvex(p: Px.Painter, pts: Array, c: Variant, a: float = 1.0) -> void:
	var y0 := INF
	var y1 := -INF
	for q in pts:
		var y: float = q[1]
		y0 = minf(y0, y)
		y1 = maxf(y1, y)
	var r0 := maxf(0.0, ceilf(y0 - 0.5))
	var r1 := minf(H - 1.0, floorf(y1 - 0.5))
	var n := pts.size()
	var fc := c is Callable
	var y := r0
	while y <= r1:
		var yc := y + 0.5
		var xl := INF
		var xr := -INF
		var j := n - 1
		for i in n:
			var xi: float = pts[i][0]
			var yi: float = pts[i][1]
			var xj: float = pts[j][0]
			var yj: float = pts[j][1]
			j = i
			if (yi > yc) == (yj > yc):
				continue
			var x := xi + ((yc - yi) * (xj - xi)) / (yj - yi)
			if x < xl:
				xl = x
			if x > xr:
				xr = x
		var c0 := maxf(0.0, ceilf(xl - 0.5))
		var c1 := minf(W - 1.0, floorf(xr - 0.5))
		if unrotated(p):
			var fx := p.fx
			var b := col0(p)
			var sy := floori(p.ty + yc)
			var x := c0
			while x <= c1:
				var col: Variant = c.call(x + 0.5, yc) if fc else c
				if col:
					p.put(int(b + fx * x), sy, col, a)
				x += 1.0
		else:
			var x := c0
			while x <= c1:
				var col: Variant = c.call(x + 0.5, yc) if fc else c
				if col:
					p.dot(x, y, col, a)
				x += 1.0
		y += 1.0


## The part of polygon pts on the side of the line through (cx, cy) that normal (nx, ny) points to.
static func halfPlane(pts: Array, cx: float, cy: float, nx: float, ny: float) -> Array:
	var out := []
	var side := func(q: Array) -> float: return (q[0] - cx) * nx + (q[1] - cy) * ny
	for i in pts.size():
		var a: Array = pts[i]
		var b: Array = pts[(i + 1) % pts.size()]
		var sa: float = side.call(a)
		var sb: float = side.call(b)
		if sa >= 0.0:
			out.append(a)
		if (sa >= 0.0) != (sb >= 0.0):
			var k := sa / (sa - sb)
			out.append([a[0] + (b[0] - a[0]) * k, a[1] + (b[1] - a[1]) * k])
	return out


## A scalar field over the screen from fn(x, y) (pixel centers), plus g: one over its gradient's length, so
## (k - f[i]) * g[i] is roughly the distance in pixels from pixel i to the level set f = k. Returns
## { f, g, ny, lo, hi, order, below }: ny is the gradient's vertical share (-1 rising upward .. 1 downward), order
## lists the pixels from the lowest value to the highest, below(v) (a Callable) how many of them are under v.
static func field(fn: Callable, gmin: float = 0.45, gmax: float = 3.0) -> Dictionary:
	var f := PackedFloat32Array()
	f.resize(W * H)
	var g := PackedFloat32Array()
	g.resize(W * H)
	var ny := PackedFloat32Array()
	ny.resize(W * H)
	var lo := INF
	var hi := -INF
	for y in H:
		for x in W:
			var v: float = fn.call(x + 0.5, y + 0.5)
			f[y * W + x] = v
			if v < lo:
				lo = v
			if v > hi:
				hi = v
	for y in H:
		for x in W:
			var xa := maxi(0, x - 1)
			var xb := mini(W - 1, x + 1)
			var ya := maxi(0, y - 1)
			var yb := mini(H - 1, y + 1)
			var gx := (f[y * W + xb] - f[y * W + xa]) / (xb - xa)
			var gy := (f[yb * W + x] - f[ya * W + x]) / (yb - ya)
			var L := Px.hypot(gx, gy)
			g[y * W + x] = 1.0 / Px.clamp(L, gmin, gmax)
			ny[y * W + x] = gy / L if L > 1e-6 else 0.0
	# JS: Uint32Array 0..n-1 sorted by (a, b) => f[a] - f[b], a stable sort: the same as sorting (f[i], i) pairs.
	# Each pair is packed into one int (the float32's bits made order-preserving, then the index) and sorted natively.
	var n := W * H
	var bits := f.to_byte_array()
	var keys := PackedInt64Array()
	keys.resize(n)
	for i in n:
		var u := bits.decode_u32(i * 4)
		if u == 0x80000000:
			u = 0  # -0 ties with 0
		var m := (~u & 0xFFFFFFFF) if u & 0x80000000 else (u | 0x80000000)
		keys[i] = (m << 16) | i
	keys.sort()
	var order := PackedInt32Array()
	order.resize(n)
	var sorted := PackedFloat32Array()
	sorted.resize(n)
	for k in n:
		var i := keys[k] & 0xFFFF
		order[k] = i
		sorted[k] = f[i]
	# the slice of `order` whose values are below v: pixels f < v are order[0 .. below(v))
	var below := func(v: float) -> int:
		var a := 0
		var b := sorted.size()
		while a < b:
			var m := (a + b) >> 1
			if sorted[m] < v:
				a = m + 1
			else:
				b = m
		return a
	return {"f": f, "g": g, "ny": ny, "lo": lo, "hi": hi, "order": order, "below": below}


## Write whole screen pixels by index fast: at(i) picks pixel i = y * W + x, then put(c, a), add(c, k) and
## blend(c, a) write it. Straight to the frame when the painter is unrotated (the usual case), else through it.
static func pixels(p: Px.Painter) -> Pixels:
	return Pixels.new(p)


class Pixels extends RefCounted:
	var p: Px.Painter
	var fast: bool
	var sx := 0
	var sy := 0
	var i0 := 0
	var tx := 0.0
	var ty := 0.0
	var fx := 1.0

	func _init(pp: Px.Painter) -> void:
		p = pp
		fast = p.sn == 0.0 and p.cs == 1.0
		if fast:
			tx = p.tx
			ty = p.ty
			fx = p.fx

	func at(i: int) -> void:
		if fast:
			sx = floori(tx + ((i % W) + 0.5) * fx)
			sy = floori(ty + floorf(i / float(W)) + 0.5)
		else:
			i0 = i

	func x() -> float:
		return (i0 % W) + 0.5

	func y() -> float:
		return floorf(i0 / float(W)) + 0.5

	func put(c: Variant, a: float = 1.0) -> void:
		if fast:
			p.put(sx, sy, c, a)
		else:
			p.dot(x(), y(), c, a)

	func add(c: int, k: float) -> void:
		if fast:
			p.add(sx, sy, c, k)
		else:
			p.light(x(), y(), c, k)

	func blend(c: Variant, a: float) -> void:
		if fast:
			p.blendPx(sx, sy, c, a)
		else:
			p.blend(x(), y(), c, a)


## A spinning 8-ray glint at (x, y): long rays white at the heart, c1 in the middle and c2 at the tips, short
## diagonals, the long rays thickened near the heart, and two lights. ang spins it; a fades it (dithered).
static func glint(p: Px.Painter, x: float, y: float, L: float, ang: float, c1: int, c2: int, a: float = 1.0) -> void:
	if L < 0.8 or a <= 0.0:
		return
	for i in 8:
		var diag := i % 2 == 1
		var an := ang + (i * TAU) / 8.0
		var ln := L * 0.42 if diag else L
		var ca := cos(an)
		var sa := sin(an)
		var d := 0.0
		while d <= ln:
			var u := d / ln
			var c: int = ((c1 if u < 0.5 else c2) if diag else (WHITE if u < 0.3 else (c1 if u < 0.65 else c2)))
			p.dot(x + ca * d, y + sa * d, c, a * (1.0 if u < 0.7 else 1.0 - (u - 0.7) / 0.35))
			if not diag and u < 0.22 and L > 4.0:
				p.dot(x + ca * d - sa, y + sa * d + ca, c1, a)
				p.dot(x + ca * d + sa, y + sa * d - ca, c1, a)
			d += 0.5
	p.dot(x, y, WHITE, a)
	p.glow(x, y, 4.0 + L * 1.4, c1, 0.5 * a)
	p.glow(x, y, 2.0 + L * 0.5, WHITE, 0.4 * a)


## Particle lives cut so nothing outlives the effect: the smaller of life and what's left before `end`.
static func lifeLeft(life: float, t: float, end: float) -> float:
	return minf(life, end - t)
