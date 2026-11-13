# Helpers shared by the weather loops. Weather fills its whole canvas edge to edge, so: clip() keeps every pixel
# and every bit of light inside the canvas; pass() is a fast per-pixel shader over the canvas; field() bakes a
# tiling noise that scrolls a whole tile a loop; trips() rains particles that fall a whole number of times a
# loop, somewhere new each time; tree() is a branching lightning path. All of it is a pure function of t.
# The noise bake and the branching bolt are adapted from Sprite Fusion's open-source fog and lightning
# (https://www.spritefusion.com/pixel-art-vfx/fog), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/weather/_lib.js@717277559cd687a9af0631e83bc9045ff1d5121d
extends RefCounted

const Px := preload("../../core/px.gd")
const Self := preload("_lib.gd")

static var BAYER := PackedFloat64Array([0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5].map(func(v): return (v + 0.5) / 16.0))


## The canvas in local coordinates: x0 <= x < x1, y0 <= y < y1.
static func box(meta: Dictionary) -> Dictionary:
	var W: int = meta.size[0]
	var H: int = meta.size[1]
	var OX: int = meta.origin[0]
	var OY: int = meta.origin[1]
	return {"x0": -OX, "y0": -OY, "x1": W - OX, "y1": H - OY, "w": W, "h": H}


## A painter that draws only inside the effect's canvas: the same API, with color, blends and light outside it
## dropped. Exact under the painter's flip and rotation.
static func clip(p: Px.Painter, meta: Dictionary) -> Clip:
	return Clip.new(p, meta)


## JS clip()'s Object.create(p): p's buffers and placement, with put/add/blendPx/glow kept inside the canvas.
class Clip extends Px.Painter:
	var p: Px.Painter
	var B: Dictionary
	var rot := false
	var sx0 := 0.0
	var sx1 := 0.0
	var sy0 := 0.0
	var sy1 := 0.0
	var bx0 := 0.0
	var by0 := 0.0
	var bx1 := 0.0
	var by1 := 0.0

	func _init(src: Px.Painter, meta: Dictionary) -> void:
		super(src.frame)
		p = src
		w = src.w
		h = src.h
		ox = src.ox
		oy = src.oy
		C = src.C
		L = src.L
		tx = src.tx
		ty = src.ty
		fx = src.fx
		cs = src.cs
		sn = src.sn
		fade = src.fade
		lightK = src.lightK
		layer = src.layer
		B = Self.box(meta)
		bx0 = B.x0
		by0 = B.y0
		bx1 = B.x1
		by1 = B.y1
		if p.sn == 0.0:
			var a := p.toX(bx0, 0.0)
			var b := p.toX(bx1, 0.0)
			sx0 = Px.round(minf(a, b))
			sx1 = Px.round(maxf(a, b))
			sy0 = Px.round(p.toY(0.0, by0))
			sy1 = Px.round(p.toY(0.0, by1))
		else:
			rot = true

	func ok(sx: int, sy: int) -> bool:
		if not rot:
			return sx >= sx0 and sx < sx1 and sy >= sy0 and sy < sy1
		var lx := p.fromX(sx + 0.5, sy + 0.5)
		var ly := p.fromY(sx + 0.5, sy + 0.5)
		return lx >= bx0 and lx < bx1 and ly >= by0 and ly < by1

	func put(sx: int, sy: int, c: Variant, a: float = 1.0) -> void:
		if ok(sx, sy):
			p.put(sx, sy, c, a)

	func add(sx: int, sy: int, c: int, k: float = 1.0) -> void:
		if ok(sx, sy):
			p.add(sx, sy, c, k)

	func blendPx(sx: int, sy: int, c: Variant, a: float) -> void:
		if ok(sx, sy):
			p.blendPx(sx, sy, c, a)

	func glow(x: float, y: float, r: float, c: int, k: float = 0.5) -> void:
		Self.glow(self, B, x, y, r, c, k)


# the painter's glow, with its box cut to the canvas first (big soft lights stay cheap)
static func glow(q: Px.Painter, B: Dictionary, x: float, y: float, r: float, c: int, k: float) -> void:
	if r < 1.0 or k <= 0.004:
		return
	if is_nan(x) or is_nan(y) or is_nan(r):
		return
	var x0 := maxf(B.x0, floorf(x - r))
	var x1 := minf(B.x1 - 1, ceilf(x + r))
	var y0 := maxf(B.y0, floorf(y - r))
	var y1 := minf(B.y1 - 1, ceilf(y + r))
	for py in range(int(y0), int(y1) + 1):
		var dy := (py + 0.5 - y) / r
		for px in range(int(x0), int(x1) + 1):
			var dx := (px + 0.5 - x) / r
			var d := dx * dx + dy * dy
			if d >= 1.0:
				continue
			var f := 1.0 - sqrt(d)
			q.light(px, py, c, f * f * k)


## What a pass() shader writes: c (color), a (alpha), b (1: blend), l (light color), k (light amount).
class Out:
	var c: int = 0
	var a: float = 1.0
	var b: int = 0
	var l: int = 0
	var k: float = 0.0


static var OUT := Out.new()
## A per-pixel shader over the canvas rows y0..y1 (local, clipped to the canvas), much faster than p.shade for
## whole-sky passes. fn(x, y, out) sets out.c (color) with out.a (alpha: dithered, or truly blended when out.b
## is 1), and out.l / out.k (light color and amount). x, y are pixel centers. Falls back to p.shade when rotated.
## (JS: pass, a GDScript keyword.)
static func pass_(p: Px.Painter, meta: Dictionary, y0: float, y1: float, fn: Callable) -> void:
	var B := box(meta)
	var o := OUT
	var bx0: int = B.x0
	var bx1: int = B.x1
	var Y0 := maxi(B.y0, floori(y0))
	var Y1 := mini(B.y1 - 1, ceili(y1))
	if Y0 > Y1:
		return
	if p.sn != 0.0:
		var q := clip(p, meta)
		for y in range(Y0, Y1 + 1):
			for x in range(bx0, bx1):
				o.c = 0
				o.a = 1.0
				o.b = 0
				o.l = 0
				o.k = 0.0
				fn.call(x + 0.5, y + 0.5, o)
				if o.c:
					if o.b:
						q.blend(x, y, o.c, o.a)
					else:
						q.dot(x, y, o.c, o.a)
				if o.k > 0.0:
					q.light(x, y, o.l if o.l else o.c, o.k)
		return
	var C := p.C
	var L := p.L
	var W := p.w
	var fade := p.fade
	var lk := p.lightK * fade
	var fx := p.fx
	var tx := p.tx
	var BY := BAYER
	for y in range(Y0, Y1 + 1):
		var sy := floori(p.ty + y + 0.5)
		var ry := sy - p.oy
		if ry < 0 or ry >= p.h:
			continue
		var row := ry * W
		var by := (sy & 3) << 2
		var sxf := tx + (bx0 + 0.5) * fx
		for x in range(bx0, bx1):
			var sx := floori(sxf)
			sxf += fx
			var rx := sx - p.ox
			if rx < 0 or rx >= W:
				continue
			o.c = 0
			o.a = 1.0
			o.b = 0
			o.l = 0
			o.k = 0.0
			fn.call(x + 0.5, y + 0.5, o)
			var i := row + rx
			if o.c:
				var a := o.a * fade
				if o.b:
					if a > 0.004:
						var d := C[i]
						var da := ((d >> 24) & 255) / 255.0
						var oa := a + da * (1.0 - a)
						var k := a / oa
						var j := 1.0 - k
						var c := o.c
						var r := int((c & 255) * k + (d & 255) * j) & 255
						var g := int(((c >> 8) & 255) * k + ((d >> 8) & 255) * j) & 255
						var b := int(((c >> 16) & 255) * k + ((d >> 16) & 255) * j) & 255
						C[i] = ((int(oa * 255.0) & 255) << 24) | (b << 16) | (g << 8) | r
				elif a >= 1.0 or a > BY[by | (sx & 3)]:
					C[i] = o.c
			if o.k > 0.0:
				var k := o.k * lk
				if k > 0.004:
					var c := o.l if o.l else o.c
					var d := L[i]
					var r := int(minf(255.0, (d & 255) + (c & 255) * k))
					var g := int(minf(255.0, ((d >> 8) & 255) + ((c >> 8) & 255) * k))
					var b := int(minf(255.0, ((d >> 16) & 255) + ((c >> 16) & 255) * k))
					L[i] = -16777216 | (b << 16) | (g << 8) | r


## One canvas row for rows(): c (color, 0 for none), a (alpha), b (1: blend), l / k (light color and amount).
class Row:
	var w := 0
	var c := PackedInt32Array()
	var a := PackedFloat32Array()
	var b := PackedByteArray()
	var l := PackedInt32Array()
	var k := PackedFloat32Array()


static var ROW := Row.new()
## The fastest whole-sky shader: fn(y, R) fills one canvas row at a time (y the row's pixel center), writing
## R.c[i] (color, 0 for none), R.a[i] (alpha, default 1), R.b[i] (1: blend, 0: dither), R.l[i] / R.k[i] (light
## color and amount) for column i = x - box.x0. One call a row, so the effect's inner loop stays tight.
static func rows(p: Px.Painter, meta: Dictionary, y0: float, y1: float, fn: Callable) -> void:
	var B := box(meta)
	var w: int = B.w
	var R := ROW
	if R.w != w:
		R.w = w
		R.c = PackedInt32Array()
		R.c.resize(w)
		R.a = PackedFloat32Array()
		R.a.resize(w)
		R.b = PackedByteArray()
		R.b.resize(w)
		R.l = PackedInt32Array()
		R.l.resize(w)
		R.k = PackedFloat32Array()
		R.k.resize(w)
	var bx0: int = B.x0
	var Y0 := maxi(B.y0, floori(y0))
	var Y1 := mini(B.y1 - 1, ceili(y1))
	var rot := p.sn != 0.0
	var q: Px.Painter = clip(p, meta) if rot else null
	var C := p.C
	var L := p.L
	var W := p.w
	var fade := p.fade
	var lk := p.lightK * fade
	var fx := p.fx
	var Rc := R.c
	var Ra := R.a
	var Rb := R.b
	var Rl := R.l
	var Rk := R.k
	var BY := BAYER
	for y in range(Y0, Y1 + 1):
		Rc.fill(0)
		Rk.fill(0)
		Ra.fill(1)
		Rb.fill(0)
		fn.call(y + 0.5, R)
		if rot:
			for i in w:
				if Rc[i]:
					if Rb[i]:
						q.blend(bx0 + i, y, Rc[i], Ra[i])
					else:
						q.dot(bx0 + i, y, Rc[i], Ra[i])
				if Rk[i] > 0.0:
					q.light(bx0 + i, y, Rl[i] if Rl[i] else Rc[i], Rk[i])
			continue
		var sy := floori(p.ty + y + 0.5)
		var ry := sy - p.oy
		if ry < 0 or ry >= p.h:
			continue
		var row := ry * W
		var by := (sy & 3) << 2
		var sxf := p.tx + (bx0 + 0.5) * fx
		for i in w:
			var sxi := sxf
			sxf += fx
			var c := Rc[i]
			var kk := Rk[i]
			if not c and not (kk > 0.0):
				continue
			var sx := floori(sxi)
			var rx := sx - p.ox
			if rx < 0 or rx >= W:
				continue
			var j := row + rx
			if c:
				var a := Ra[i] * fade
				if Rb[i]:
					if a > 0.004:
						var d := C[j]
						var da := ((d >> 24) & 255) / 255.0
						var oa := a + da * (1.0 - a)
						var k := a / oa
						var m := 1.0 - k
						var r := int((c & 255) * k + (d & 255) * m) & 255
						var g := int(((c >> 8) & 255) * k + ((d >> 8) & 255) * m) & 255
						var b := int(((c >> 16) & 255) * k + ((d >> 16) & 255) * m) & 255
						C[j] = ((int(oa * 255.0) & 255) << 24) | (b << 16) | (g << 8) | r
				elif a >= 1.0 or a > BY[by | (sx & 3)]:
					C[j] = c
			if kk > 0.0:
				var k := kk * lk
				if k > 0.004:
					var lc := Rl[i] if Rl[i] else c
					var d := L[j]
					var r := int(minf(255.0, (d & 255) + (lc & 255) * k))
					var g := int(minf(255.0, ((d >> 8) & 255) + ((lc >> 8) & 255) * k))
					var b := int(minf(255.0, ((d >> 16) & 255) + ((lc >> 16) & 255) * k))
					L[j] = -16777216 | (b << 16) | (g << 8) | r


## Ordered-dither threshold of a local pixel (0..1): `a > bayer(x, y)` draws it.
static func bayer(x: float, y: float) -> float:
	return BAYER[((floori(y) & 3) << 2) | (floori(x) & 3)]


## A baked noise field: w x h values (float32, as the JS Float32Array).
class Field:
	var w: int
	var h: int
	var d: PackedFloat32Array


static var FIELDS := {}
## A baked fractal noise that tiles: w x h cells (powers of two), octaves of `cells` lattice squares across.
## Values 0..1, mostly near 0.5. Scroll it a whole number of tiles a loop and the loop has no seam.
static func field(seed: float, w: int = 256, h: int = 128, cells: Array = [4, 8, 16, 32]) -> Field:
	var key := "%s|%d|%d|%s" % [var_to_str(seed), w, h, ",".join(cells.map(func(v): return str(v)))]
	var F: Field = FIELDS.get(key)
	if F:
		return F
	var d := PackedFloat32Array()
	d.resize(w * h)
	var amp := 0.5
	var total := 0.0
	for n: int in cells:
		var cs := w / float(n)
		var rows_ := maxf(1.0, Px.round(h / cs))
		# at(a, b): the lattice value; tabled once per octave (a pure function, so the same numbers)
		var lat := PackedFloat64Array()
		var nw := n + 1
		lat.resize(nw * (int(rows_) + 1))
		for b in int(rows_) + 1:
			for a in nw:
				lat[b * nw + a] = _at(a, b, n, rows_, seed)
		for y in h:
			for x in w:
				var gx := x / cs
				var gy := (y / float(h)) * rows_
				var ix := floorf(gx)
				var iy := floorf(gy)
				var u := gx - ix
				var v := gy - iy
				var su := u * u * (3.0 - 2.0 * u)
				var sv := v * v * (3.0 - 2.0 * v)
				var o := int(iy) * nw + int(ix)
				var top := lat[o] + (lat[o + 1] - lat[o]) * su
				var bot := lat[o + nw] + (lat[o + nw + 1] - lat[o + nw]) * su
				d[y * w + x] += (top + (bot - top) * sv) * amp
		total += amp
		amp *= 0.5
	for i in d.size():
		d[i] /= total
	F = Field.new()
	F.w = w
	F.h = h
	F.d = d
	FIELDS[key] = F
	return F


# field()'s at(a, b)
static func _at(a: float, b: float, n: float, rows_: float, seed: float) -> float:
	return Px.rand(Px.wrap(a, n), Px.wrap(b, rows_), seed, n)


## A field at (u, v) in its own cells, wrapping, smooth between cells.
static func sample(F: Field, u: float, v: float) -> float:
	var x := floorf(u)
	var y := floorf(v)
	var fx := u - x
	var fy := v - y
	var m := F.w - 1
	var n := F.h - 1
	var D := F.d
	var xi := int(x)
	var yi := int(y)
	var x0 := xi & m
	var x1 := (xi + 1) & m
	var y0 := (yi & n) * F.w
	var y1 := ((yi + 1) & n) * F.w
	var a := D[y0 + x0]
	var b := D[y0 + x1]
	var c := D[y1 + x0]
	var e := D[y1 + x1]
	return a + (b - a) * fx + (c - a + (a - b - c + e) * fx) * fy


## Falling particles for a loop of D seconds: n slots, each falling m times a loop (m whole, from m0 to m1), each
## fall somewhere new. fn(u, k, m, i): u 0..1 through the current fall, k its number (wrap(k, m) names it: use
## rand(seed, i, wrap(k, m), ...) for its own randoms, the same every loop), m, the slot i. A fall lasts D / m s.
## fn must take all four arguments.
static func trips(t: float, D: float, n: float, seed: float, m0: float, m1: float, fn: Callable) -> void:
	var i := 0
	while i < n:
		var m := m0 + floorf(Px.rand(seed, i, 72) * (m1 - m0 + 1.0))
		var s := (t / D) * m + Px.rand(seed, i, 71)
		var k := floorf(s)
		fn.call(s - k, k, m, i)
		i += 1


## A branching lightning path from (x0, y0) to (x1, y1): midpoint displacement down to ~3 px segments, with
## forks (and forks of forks) peeling off. Returns [{ pts: [[x, y], ...], w }], the trunk first with w = 1,
## forks thinner (w < 1). R is an Rng.
static func tree(R: Px.Rng, x0: float, y0: float, x1: float, y1: float, jag: float = 0.3, forks: float = 0.4, w: float = 1.0, depth: int = 0) -> Array:
	var out := []
	var L := Px.hypot(x1 - x0, y1 - y0)
	var pts: Array = [[x0, y0], [x1, y1]]
	var off := L * jag
	while pts.size() < 2 + L / 3.0:
		var nxt: Array = [pts[0]]
		for i in pts.size() - 1:
			var ax: float = pts[i][0]
			var ay: float = pts[i][1]
			var bx: float = pts[i + 1][0]
			var by: float = pts[i + 1][1]
			var l := Px.hypot(bx - ax, by - ay)
			if not l:
				l = 1.0
			var o := R.range(-off, off)
			nxt.append([(ax + bx) / 2.0 + (-(by - ay) / l) * o, (ay + by) / 2.0 + ((bx - ax) / l) * o])
			nxt.append([bx, by])
		pts = nxt
		off *= 0.52
	out.append({"pts": pts, "w": w, "depth": depth})
	if depth < 2:
		for i in range(2, pts.size() - 3):
			if R.chance(forks / (1 + depth) / maxf(4.0, pts.size() / 6.0)):
				var ax: float = pts[i][0]
				var ay: float = pts[i][1]
				var bp: Array = pts[mini(pts.size() - 1, i + 3)]
				var bx: float = bp[0]
				var by: float = bp[1]
				var a := atan2(by - ay, bx - ax) + R.sign() * R.range(0.35, 0.95)
				var l := (L - (i / float(pts.size())) * L) * R.range(0.25, 0.55)
				out.append_array(tree(R, ax, ay, ax + cos(a) * l, ay + sin(a) * l, jag * 1.1, forks, w * 0.55, depth + 1))
	return out


## Whole cycles per loop: a sine with c full turns in D seconds, phase ph (radians). Seamless by construction.
static func wave(t: float, D: float, c: float, ph: float = 0.0) -> float:
	return sin((TAU * c * t) / D + ph)


## A raindrop's splash on the floor, age seconds after it lands at (x, z): a white crown for a frame or two, a
## flat ring spreading (its near arc brighter), and droplets thrown up that fall back. size 0..1 (far to near),
## c = { hot, cool } colors, h a number unique to this drop. Adapted from Sprite Fusion's rain.
static func splash(q: Px.Painter, x: float, z: float, age: float, size: float, c: Dictionary, h: float) -> void:
	var L := 0.3 + 0.12 * size
	var u := age / L
	if u >= 1.0:
		return
	if age < 0.07:
		q.px(x, z - 1.0, c.hot)
		if size > 0.3:
			q.px(x - 1.0, z - 1.0 - (1.0 if age > 0.035 else 0.0), c.hot)
			q.px(x + 1.0, z - 1.0 - (1.0 if age > 0.035 else 0.0), c.hot)
		if size > 0.65 and age > 0.03:
			q.px(x - 2.0, z - 2.0, c.cool)
			q.px(x + 2.0, z - 2.0, c.cool)
	var rx := 1.0 + (1.2 + 3.6 * size) * sqrt(u)
	var ry := maxf(0.5, rx * 0.26)
	var n := ceilf(rx * 6.5)
	for j in int(n):
		var a := (j / n) * TAU
		var s := sin(a)
		if s < -0.25:
			continue
		q.dot(x + cos(a) * rx, z + s * ry, c.hot if (u < 0.3 and s > 0.0) else c.cool, ((1.0 if s > 0.2 else 0.7) if u < 0.45 else (1.0 - u) * 1.6 * (1.0 if s > 0.2 else 0.6)))
	var nd := 3 if size > 0.55 else 2
	var H := floorf(h * 1e6)
	for d in nd:
		var vx := (Px.rand(H, d, 1) - 0.5) * 2.0 * (25.0 + 35.0 * size)
		var vy := -(55.0 + Px.rand(H, d, 2) * 70.0 * (0.5 + size))
		var y := z - 1.0 + vy * age + 475.0 * age * age
		if y > z - 0.5 or age > 0.34:
			continue
		var xx := x + vx * age
		q.px(xx, y, c.hot if age < 0.12 else c.cool)
		if vy + 950.0 * age < -40.0:
			q.dot(xx - vx * 0.012, y + 1.0, c.cool, 0.7)


## A crisp splash on a floor line, age seconds after a drop lands at (x, z): a crown for a few frames (a white
## point, two arms rising), then a flat dash that spreads and breaks into two end dashes, and a droplet or two
## arcing up and back. Solid pixels only (no dither), so a line of them stays clean. size 0..1, c = { hot, cool,
## white }, h a number unique to the drop. Returns false once it's over.
static func crown(q: Px.Painter, x: float, z: float, age: float, size: float, c: Dictionary, h: float) -> bool:
	var L := 0.22 + 0.14 * size
	var u := age / L
	var X := Px.round(x)
	var Z := Px.round(z)
	if u >= 1.0:
		return false
	if age < 0.1:
		var up := 1.0 if age < 0.033 else (2.0 if age < 0.067 else 2.0 + (1.0 if size > 0.5 else 0.0))
		q.px(X, Z - 1.0, c.white if age < 0.05 else c.hot)
		var d := 1
		while d <= minf(up, 3.0 if size > 0.5 else 1.0):
			q.px(X - d, Z - 1.0 - (d - 1 if d > 1 else 0), c.hot if d == 1 else c.cool)
			q.px(X + d, Z - 1.0 - (d - 1 if d > 1 else 0), c.hot if d == 1 else c.cool)
			d += 1
	if u > 0.15:
		var w := Px.round(1.0 + (1.5 + 3.5 * size) * sqrt(u))
		var gap := maxf(0.0, w - 2.0) if u > 0.55 else -1.0
		for d in range(int(-w), int(w) + 1):
			if absf(d) > gap:
				q.px(X + d, Z, c.hot if (absf(d) >= w - 1.0 and u < 0.6) else c.cool)
	var nd := 2 if size > 0.5 else 1
	var H := floorf(h * 1e6)
	for d in nd:
		var vx := (Px.rand(H, d, 1) - 0.5) * 2.0 * (20.0 + 30.0 * size)
		var vy := -(50.0 + Px.rand(H, d, 2) * 60.0 * (0.4 + size))
		var y := Z - 1.0 + vy * age + 475.0 * age * age
		if y < Z - 0.5 and age < 0.3:
			q.px(x + vx * age, y, c.white if age < 0.1 else c.hot)
	return true
