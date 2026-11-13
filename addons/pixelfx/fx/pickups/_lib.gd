# Helpers for the pickups: a scratch layer to build outlined sprites in, floor shadows, twinkles and bobs.
# Not an effect (the file name starts with _).
# port-of: src/fx/pickups/_lib.js@15cb3479fd36d1700b4f987ee11cbe4123e9895d
extends RefCounted

const Px := preload("../../core/px.gd")
const Self := preload("_lib.gd")
const WHITE := Px.WHITE


## The palette as at least n color steps, dark to bright, so effects can index C[0]..C[n-1] whatever ramp a
## caller passes: a 7-step ramp repeats its brightest step, a short one is stretched step by step (no blending).
static func fit(palette: Variant, n: int = 8) -> Array:
	var r := Px.ramp(palette)
	if not r.size():
		var out := []
		out.resize(n)
		out.fill(WHITE)
		return out
	if r.size() >= n - 1:
		while r.size() < n:
			r.append(r[r.size() - 1])
		return r
	return Px.arr(n, func(i): return r[Px.roundi(float(i * (r.size() - 1)) / (n - 1))])


## A scratch layer: draw a sprite into it with its own painter (same local coordinates as the effect), give
## it a dark outline, recolor it, then stamp it onto the frame. Lets a procedural shape get a hand-made
## 1 px outline and lets shines sweep across exactly the sprite's pixels.
class Layer extends RefCounted:
	var f: Px.Frame
	var q: Px.Painter
	var tmp: PackedInt32Array

	func _init(w: int = 64, h: int = 64) -> void:
		f = Px.createFrame(w, h)
		q = Px.Painter.new(f)
		tmp = PackedInt32Array()
		tmp.resize(w * h)

	## Clear it and put its top-left at local (x0, y0). Returns the layer's painter.
	func begin(x0: float, y0: float) -> Px.Painter:
		var fr := f
		fr.ox = floori(x0)
		fr.oy = floori(y0)
		fr.color.fill(0)
		fr.light.fill(0)
		return q.reset().place(0, 0)

	func idx(x: float, y: float) -> int:
		var fr := f
		var i := floori(x) - fr.ox
		var j := floori(y) - fr.oy
		return -1 if (i < 0 or j < 0 or i >= fr.w or j >= fr.h) else j * fr.w + i

	## (JS: get) Unsigned, like a Uint32Array read.
	func getc(x: float, y: float) -> int:
		var i := idx(x, y)
		return 0 if i < 0 else (f.color[i] & 0xFFFFFFFF)

	## (JS: set)
	func setc(x: float, y: float, c: Variant) -> void:
		var i := idx(x, y)
		if i >= 0:
			f.color[i] = c

	## Fill each pixel from fn(x, y) at the pixel's center (x + 0.5, y + 0.5): return a color or 0.
	func fill(x0: float, y0: float, x1: float, y1: float, fn: Callable) -> void:
		var y := floori(y0)
		while y <= y1:
			var x := floori(x0)
			while x <= x1:
				var c: Variant = fn.call(x + 0.5, y + 0.5)
				if c:
					setc(x, y, c)
				x += 1
			y += 1

	## A 1 px outline around everything drawn: c is a color or fn(x, y, neighbour color). corners adds diagonals.
	func outline(c: Variant, corners: bool = false):
		var fr := f
		var C := fr.color
		var T := tmp
		var w := fr.w
		var h := fr.h
		T.fill(0)
		var cf := c is Callable
		for j in h:
			for i in w:
				var k := j * w + i
				if C[k]:
					continue
				var n := 0
				if i > 0 and C[k - 1]:
					n = C[k - 1]
				elif i < w - 1 and C[k + 1]:
					n = C[k + 1]
				elif j > 0 and C[k - w]:
					n = C[k - w]
				elif j < h - 1 and C[k + w]:
					n = C[k + w]
				if not n and corners:
					if i > 0 and j > 0 and C[k - w - 1]:
						n = C[k - w - 1]
					elif i < w - 1 and j > 0 and C[k - w + 1]:
						n = C[k - w + 1]
					elif i > 0 and j < h - 1 and C[k + w - 1]:
						n = C[k + w - 1]
					elif i < w - 1 and j < h - 1 and C[k + w + 1]:
						n = C[k + w + 1]
				if n:
					T[k] = c.call(i + fr.ox, j + fr.oy, n & 0xFFFFFFFF) if cf else c
		for k in w * h:
			if T[k]:
				C[k] = T[k]
		return self

	## Recolor every drawn pixel: fn(x, y, c) returns the new color.
	func map(fn: Callable):
		var fr := f
		var C := fr.color
		for k in C.size():
			if C[k]:
				var v: Variant = fn.call((k % fr.w) + fr.ox, floori(k / float(fr.w)) + fr.oy, C[k] & 0xFFFFFFFF)
				C[k] = v if v else C[k]
		return self

	## Stamp the layer onto p, offset by (dx, dy), at alpha a (dithered); clip [x0, x1] keeps x0 <= x < x1.
	func draw(p: Px.Painter, dx: float = 0.0, dy: float = 0.0, a: float = 1.0, clip: Variant = null):
		var fr := f
		var C := fr.color
		var fw := fr.w
		for k in C.size():
			if not C[k]:
				continue
			var x := (k % fw) + fr.ox + dx
			if clip and (x < clip[0] or x >= clip[1]):
				continue
			p.dot(x, floori(k / float(fw)) + fr.oy + dy, C[k], a)
		return self


static var SHADOW := Px.hex("#100e17")
## A floor shadow centered on x, half-width rx: a solid dark band on the floor line (y = 0) and a narrower one
## under it, with dithered ends. Shrink rx as the thing above rises.
static func shadow(p: Px.Painter, x: float, rx: float, k: float = 1.0) -> void:
	if rx < 1.0:
		return
	for row in 2:
		var w := rx - row * 2
		var i := floorf(x - w)
		while i < ceilf(x + w):
			var e := absf(i + 0.5 - x) / w
			if e <= 1.0:
				p.dot(i, row, SHADOW, k if row else k * (1.0 if e < 0.8 else 0.5))
			i += 1.0


## A four-point twinkle of arm length s (whole pixels): white core, bright inner arms, colored tips.
static func twinkle(p: Px.Painter, x: float, y: float, s: float, c: int, mid: Variant = null, core: int = WHITE) -> void:
	var md: int = c if mid == null else mid
	s = Px.round(s)
	if s <= 0.0:
		return
	var d := 1.0
	while d <= s - 1.0:
		var k := md if d < s / 2.0 else c
		p.px(x + d, y, k)
		p.px(x - d, y, k)
		p.px(x, y + d, k)
		p.px(x, y - d, k)
		d += 1.0
	if s >= 4.0:
		p.px(x + 1.0, y + 1.0, c)
		p.px(x - 1.0, y - 1.0, c)
		p.px(x + 1.0, y - 1.0, c)
		p.px(x - 1.0, y + 1.0, c)
	p.px(x, y, core)


## A seamless bob: up-and-down offset in px for loop phase ph (0..1), n bobs a loop.
static func bob(ph: float, amp: float, n: float = 1.0, off: float = 0.0) -> float:
	return -amp * sin((ph * n + off) * TAU)


## Fill a puffy shape into layer L from a signed distance sdf(x, y) in px (negative inside). The surface is
## flat in the middle and rounds over in a bevel px wide at the edge; color(b, e, x, y) gets the light b
## (about -0.3 facing away .. 1 facing the light, 0.62 flat) and the depth e in px from the edge. clip(x, y)
## returning true cuts a pixel away without shading the cut (a break, a bite).
## opts: { bevel = 3, light = [-0.5, -0.6, 0.62], clip = null }
static func pillow(L: Layer, x0: float, y0: float, x1: float, y1: float, sdf: Callable, color: Callable, opts: Dictionary = {}) -> void:
	var bevel: float = opts.get("bevel", 3.0)
	var light: Array = opts.get("light", [-0.5, -0.6, 0.62])
	var clip: Variant = opts.get("clip", null)
	var nc := color.get_argument_count()
	L.fill(x0, y0, x1, y1, func(x: float, y: float) -> Variant:
		var d: float = sdf.call(x, y)
		if d > 0.0 or (clip and clip.call(x, y)):
			return 0
		var e := -d
		var gx: float = sdf.call(x + 0.5, y) - sdf.call(x - 0.5, y)
		var gy: float = sdf.call(x, y + 0.5) - sdf.call(x, y - 0.5)
		var gl := Px.hypot(gx, gy)
		if not gl:
			gl = 1.0
		gx /= gl
		gy /= gl
		var k := maxf(0.0, 1.0 - e / bevel) * 1.25
		var sn := sin(k)
		var cs := cos(k)
		return Px.call4(color, nc, gx * sn * light[0] + gy * sn * light[1] + cs * light[2], e, x, y))


## Signed distance (px, roughly) to a heart of half-width w centered at (cx, cy): the classic sextic curve.
static func heartSdf(x: float, y: float, cx: float, cy: float, w: float, h: Variant = null) -> float:
	var hh: float = w if h == null else h
	var S := w / 1.14
	var X := (x - cx) / S
	var Y := -(y - cy) / (hh / 1.14) + 0.12
	var q := X * X + Y * Y - 1.0
	var f := q * q * q - X * X * Y * Y * Y
	var gx := 6.0 * X * q * q - 2.0 * X * Y * Y * Y
	var gy := 6.0 * Y * q * q - 3.0 * X * X * Y * Y
	return (f / maxf(Px.hypot(gx, gy), 0.6)) * S


# ---- the rebuilt pickups (techniques from Sprite Fusion's open-source pickup and sparkle, MIT, Hugo Duprez)

static var INK := Px.hex("#0b0814")

## A soft floor shadow at x, half-width rx: dithered darkness on the floor line, fuller in the middle, with a
## shorter second row under it. k (0..1) is its strength: lift the thing above and the shadow shrinks and thins.
static func blobShadow(p: Px.Painter, x: float, rx: float, k: float = 1.0, y: float = 0.0) -> void:
	if rx < 0.8 or k <= 0.0:
		return
	var i := floorf(x - rx)
	while i <= ceilf(x + rx):
		var u := absf(i + 0.5 - x) / rx
		if u > 1.0:
			i += 1.0
			continue
		var a := k * (1.0 - u * u)
		p.dot(i, y, INK, a * 1.1)
		if u < 0.6:
			p.dot(i, y + 1.0, INK, a * 0.6)
		i += 1.0


## A four-point star glint: arms of arm px in c, dimmer tips, a white heart, its own light.
static func glint(p: Px.Painter, x: float, y: float, arm: float, c: int, k: float = 0.4, tip: Variant = null) -> void:
	var tp: int = Px.scale(c, 0.8) if tip == null else tip
	var n := Px.round(arm)
	var X := floorf(x)
	var Y := floorf(y)
	if n < 0.0:
		return
	var d := 1.0
	while d <= n:
		var cc := tp if (d == n and n > 1.0) else c
		p.px(X + d, Y, cc)
		p.px(X - d, Y, cc)
		p.px(X, Y + d, cc)
		p.px(X, Y - d, cc)
		d += 1.0
	p.px(X, Y, WHITE if n > 0.0 else c)
	p.glow(X + 0.5, Y + 0.5, 3.0 + n * 2.5, c, k)


## Additive light in an ellipse (a pool of light on the floor): k at the center falling off to the rim.
static func pool(p: Px.Painter, x: float, y: float, rx: float, ry: float, c: int, k: float) -> void:
	if k <= 0.004 or rx < 1.0:
		return
	p.shade(x - rx, y - ry, x + rx, y + ry, func(px: float, py: float, out) -> void:
		var dx := (px - x) / rx
		var dy := (py - y) / ry
		var d := dx * dx + dy * dy
		if d >= 1.0:
			return
		var f := 1.0 - sqrt(d)
		out.l = c
		out.k = f * f * k)


## A coin of radius r tumbling: its face turns by `spin` about an axis at screen angle `ax`, showing its rim
## as it goes edge-on. A lit rim round a face with a shine, built in layer L with a dark outline, lit from the
## top left. C: an 8-step gold ramp. snap puts its center on a pixel corner (even sizes) so it holds its shape
## while it moves; pass snap false and a pixel-center y for odd heights.
static func coin(L: Layer, p: Px.Painter, x: float, y: float, r: float, ax: float, spin: float, C: Array, white: bool = false, a: float = 1.0, snap: bool = true) -> void:
	var X := Px.round(x) if snap else x
	var Y := Px.round(y) if snap else y
	var cs := cos(spin)
	var sn := sin(spin)
	var b := maxf(0.5, r * absf(cs))
	var th := 1.2 * sn * Px.sign(cs if cs else 1.0)
	var ca := cos(ax)
	var sa := sin(ax)
	var face := absf(cs)
	var R := ceilf(r) + 2.0
	L.begin(floorf(X) - R, floorf(Y) - R)
	L.fill(floorf(X) - R, floorf(Y) - R, floorf(X) + R, floorf(Y) + R, func(px: float, py: float) -> Variant:
		var dx := px - X
		var dy := py - Y
		var u := dx * ca + dy * sa
		var w := -dx * sa + dy * ca
		var ef := Px.hypot(u / r, w / b)
		var er := Px.hypot(u / r, (w - th) / b)
		if white and (ef <= 1.0 or er <= 1.0):
			return WHITE
		if ef <= 1.0:
			# in the face's own frame: the raised rim, a recessed ring inside it, a raised middle with a shine
			var lit := -(dx * 0.62 + dy * 0.78) / maxf(1.0, Px.hypot(dx, dy))
			var dim := 1 if face < 0.45 else 0
			if b < 1.1:
				return C[6] if lit > 0.0 else C[4]
			if ef > 0.72:
				return C[(6 if lit > 0.3 else (5 if lit > -0.35 else 3)) - dim]
			if b > 2.2 and ef > 0.42:
				return C[(4 if lit > 0.2 else 5) - dim]
			if face > 0.6 and lit > 0.5:
				return C[7]
			return C[5 - dim]
		if er <= 1.0:
			return C[2] if absf(w - th) < absf(w) else C[3]
		return 0)
	L.outline(C[1]).draw(p, 0.0, 0.0, a)


## A small cut gem of radius r turned to angle `ang` (radians, on screen): a crown with a table over a pointed
## pavilion, its facets lit from the top left, a white glint on the table; G is a ramp dark to bright (6+
## steps). Built in L with a dark outline.
static func gemlet(L: Layer, p: Px.Painter, x: float, y: float, r: float, ang: float, G: Array, white: bool = false, a: float = 1.0) -> void:
	var X := Px.round(x)
	var Y := Px.round(y)
	var ca := cos(ang)
	var sa := sin(ang)
	var n := G.size()
	var R := ceilf(r * 1.4) + 2.0
	var ct := r * 0.75
	var tw := r * 0.5
	var pv := r * 1.3
	L.begin(X - R, Y - R)
	L.fill(X - R, Y - R, X + R - 1.0, Y + R - 1.0, func(px: float, py: float) -> Variant:
		var dx := px - X
		var dy := py - Y
		var u := dx * ca + dy * sa
		var w := -dx * sa + dy * ca
		var facet: int
		if w < 0.0:
			if w < -ct or absf(u) > r - ((-w) / ct) * (r - tw):
				return 0
			facet = 0 if (w < -ct * 0.45 and absf(u) < tw * 0.95) else (1 if u < 0.0 else 2)
		else:
			if w > pv or absf(u) > r * (1.0 - w / pv):
				return 0
			facet = 4 if absf(u) < 0.5 else (3 if u < 0.0 else 5)
		if white:
			return WHITE
		# each facet's normal, turned with the gem; the light comes from the top left of the screen
		var N: Array = [[0.0, -1.0], [-0.7, -0.7], [0.7, -0.7], [-0.6, 0.8], [0.0, 1.0], [0.6, 0.8]][facet]
		var nx: float = N[0] * ca - N[1] * sa
		var ny: float = N[0] * sa + N[1] * ca
		var l := -(nx * 0.62 + ny * 0.78)
		if facet == 0 and l > 0.3 and u < 0.0:
			return WHITE
		return G[n - 1] if l > 0.6 else (G[n - 2] if l > 0.2 else (G[n - 3] if l > -0.2 else (G[n - 4] if l > -0.6 else G[n - 5]))))
	L.outline(G[0]).draw(p, 0.0, 0.0, a)


## A cut gem as a convex solid: facet planes { n: [x, y, z] outward unit normal, d, kind }, y up, z towards
## the viewer, the girdle on y = 0. brilliant() builds a round brilliant: a table, crown facets, a thin
## girdle, pavilion facets down to a point; n facets round (8 by default).
## opts: { r = 7.5, crown = 3.6, table = 0.52, pavilion = 8, girdle = 0.8, n = 8 }
static func brilliant(opts: Dictionary = {}) -> Dictionary:
	var r: float = opts.get("r", 7.5)
	var crown: float = opts.get("crown", 3.6)
	var table: float = opts.get("table", 0.52)
	var pavilion: float = opts.get("pavilion", 8.0)
	var girdle: float = opts.get("girdle", 0.8)
	var n: float = opts.get("n", 8.0)
	var planes := [{"n": [0.0, 1.0, 0.0], "d": crown + girdle / 2.0, "kind": 0}]
	var cs := atan2(crown, r * (1.0 - table))
	var ps := atan2(pavilion, r)
	for i in int(n * 2.0):
		var a := (i * PI) / n
		var half := i % 2
		var c := minf(1.45, cs + 0.22) if half else cs
		var pv := ps - 0.1 if half else ps
		# crown: main facets, and steeper ones between them by the girdle
		planes.append({"n": [sin(c) * cos(a), cos(c), sin(c) * sin(a)], "d": r * sin(c) * (1.012 if half else 1.0) + (girdle / 2.0) * cos(c), "kind": 2 if half else 1})
		# the girdle: a ring of thin upright faces
		planes.append({"n": [cos(a), 0.0, sin(a)], "d": r * (1.0 if half else 1.0), "kind": 3})
		# pavilion: main facets to the point, shallower ones between them by the girdle
		planes.append({"n": [sin(pv) * cos(a), -cos(pv), sin(pv) * sin(a)], "d": r * sin(pv) * (1.03 if half else 1.0) + (girdle / 2.0) * cos(pv), "kind": 5 if half else 4})
	return {"planes": planes, "r": r, "top": crown + girdle / 2.0, "bottom": pavilion + girdle / 2.0}


## A crystal: an n-sided prism (apothem r, half-height half) with a pointed cap of height top and a shorter
## point of height bottom, as facet planes for drawGem (kinds 6 prism, 7 cap, 8 point).
## opts: { r = 4.6, half = 5.5, top = 7.5, bottom = 6, n = 6 }
static func prism(opts: Dictionary = {}) -> Dictionary:
	var r: float = opts.get("r", 4.6)
	var half: float = opts.get("half", 5.5)
	var top: float = opts.get("top", 7.5)
	var bottom: float = opts.get("bottom", 6.0)
	var n: float = opts.get("n", 6.0)
	var planes := []
	var ct := atan2(top, r)
	var cb := atan2(bottom, r)
	for i in int(n):
		var a := (i * TAU) / n
		planes.append({"n": [cos(a), 0.0, sin(a)], "d": r, "kind": 6})
		planes.append({"n": [sin(ct) * cos(a), cos(ct), sin(ct) * sin(a)], "d": sin(ct) * r + cos(ct) * half, "kind": 7})
		planes.append({"n": [sin(cb) * cos(a), -cos(cb), sin(cb) * sin(a)], "d": sin(cb) * r + cos(cb) * half, "kind": 8})
	return {"planes": planes, "r": r / cos(PI / n), "top": half + top, "bottom": half + bottom}


## Draw gem g turned by spin (radians about its upright axis), its center (the girdle) at (x, y), seen from a
## little above (tilt), into layer L with a dark outline. Each pixel finds the facet it looks at; crown facets
## catch the light from the top left, pavilion facets glow with the light bouncing up through the stone.
## C: ramp dark to bright (8). Returns the brightest spot { x, y } for a glint.
## opts: { tilt = 0.32, white = false, a = 1, edges = true, gain = 1 }
static func drawGem(L: Layer, p: Px.Painter, g: Dictionary, x: float, y: float, spin: float, C: Array, opts: Dictionary = {}) -> Dictionary:
	var tilt: float = opts.get("tilt", 0.32)
	var white: bool = opts.get("white", false)
	var a: float = opts.get("a", 1.0)
	var edges: bool = opts.get("edges", true)
	var gain: float = opts.get("gain", 1.0)
	var cs := cos(spin)
	var sn := sin(spin)
	var ct := cos(tilt)
	var st := sin(tilt)
	var P := []
	for q: Dictionary in g.planes:
		P.append({"n": [q.n[0] * cs - q.n[2] * sn, q.n[1], q.n[0] * sn + q.n[2] * cs], "d": q.d, "kind": q.kind})
	# light from the top left, a little in front; the eye looks down the tilted z axis
	var Lx := -0.55
	var Ly := 0.72
	var Lz := 0.42
	var D := [0.0, -st, -ct]
	var V := [0.0, st, ct]
	var Hl := Px.hypot(Lx + V[0], Ly + V[1], Lz + V[2])
	var H := [(Lx + V[0]) / Hl, (Ly + V[1]) / Hl, (Lz + V[2]) / Hl]
	var X := Px.round(x)
	var Y := Px.round(y)
	var R := ceilf(g.r) + 2.0
	var top := ceilf(g.top + 2.0)
	var bot := ceilf(g.bottom + 2.0)
	# best, bx, by: assigned inside the lambda
	var st_ := {"best": -1.0, "bx": X, "by": Y}
	var ids := {}
	var np := P.size()
	var D0: float = D[0]
	var D1: float = D[1]
	var D2: float = D[2]
	var H0: float = H[0]
	var H1: float = H[1]
	var H2: float = H[2]
	L.begin(X - R, Y - top)
	L.fill(X - R, Y - top, X + R, Y + bot, func(px: float, py: float) -> Variant:
		var sx := px - X
		var sy := -(py - Y)
		# the ray through this pixel: origin on the screen plane, straight down the view axis
		var o0 := sx
		var o1 := sy * ct
		var o2 := -sy * st
		var t0 := -1e9
		var t1 := 1e9
		var hit := -1
		for qi in np:
			var q: Dictionary = P[qi]
			var qn: Array = q.n
			var nd: float = qn[0] * D0 + qn[1] * D1 + qn[2] * D2
			var no: float = qn[0] * o0 + qn[1] * o1 + qn[2] * o2
			if absf(nd) < 1e-6:
				if no > q.d:
					return 0
				continue
			var tt: float = (q.d - no) / nd
			if nd < 0.0:
				if tt > t0:
					t0 = tt
					hit = qi
			elif tt < t1:
				t1 = tt
		if hit < 0 or t0 > t1:
			return 0
		if white:
			return WHITE
		ids[(floori(px) + 500) * 1000 + floori(py) + 500] = hit
		var hq: Dictionary = P[hit]
		var kind: int = hq.kind
		var n: Array = hq.n
		var pav := kind == 4 or kind == 5 or kind == 8
		# the pavilion shows light that came in through the crown and bounced back: mirror its normal
		var m: Array = [n[0], -n[1] * 0.6, n[2]] if pav else n
		var ml := Px.hypot(m[0], m[1], m[2])
		var lam := maxf(0.0, (m[0] * Lx + m[1] * Ly + m[2] * Lz) / ml)
		var spec := pow(maxf(0.0, (m[0] * H0 + m[1] * H1 + m[2] * H2) / ml), 18.0)
		var b := 0.02 + 0.72 * pow(lam, 2.4) if pav else (0.12 + 0.4 * lam if kind == 3 else 0.04 + 0.66 * pow(lam, 1.8))
		# a crystal's upright faces are lit by the light's level direction; its cap catches it from above
		if kind == 6:
			b = 0.16 + 0.66 * pow(maxf(0.0, (n[0] * Lx + n[2] * Lz) / Px.hypot(Lx, Lz)), 1.3)
		elif kind == 7:
			b = 0.22 + 0.62 * pow(lam, 1.2)
		# a fracture shows the lit inside of the stone, rough and grainy; chips are small rough facets
		elif kind == 9:
			b = 0.62 + 0.25 * lam
		elif kind == 10:
			b = 0.3 + 0.5 * lam + (Px.rand(floorf(px - X), floorf(py - Y), 43) - 0.5) * 0.08
		if kind != 9:
			b *= gain
		if kind == 0:
			b -= 0.04
		var s := b + spec * 0.6
		if s > st_.best:
			st_.best = s
			st_.bx = px
			st_.by = py
		if spec > 0.8:
			return C[6] if pav else WHITE
		return C[int(maxf(1.0, minf(6.0, Px.round(1.0 + s * 5.6))))])
	# the cut: where two facets meet, a pavilion edge sinks a shade and a crown ridge catches a shade more light
	if not white and edges:
		var out := []
		for key: int in ids:
			var id: int = ids[key]
			var kx := floori(key / 1000.0)
			var ky := key - kx * 1000
			var ex := kx - 500
			var ey := ky - 500
			var r: Variant = ids.get(key + 1000)
			var d: Variant = ids.get(key + 1)
			if (r != null and r != id) or (d != null and d != id):
				var c := L.getc(ex, ey)
				var i := -1
				for ci in C.size():
					if (C[ci] & 0xFFFFFFFF) == c:
						i = ci
						break
				var pav: bool = P[id].kind in [4, 5, 8]
				if i > 0:
					out.append([ex, ey, C[maxi(1, i - 1)] if pav else C[mini(7, i + 1)]])
		for e: Array in out:
			L.setc(e[0], e[1], e[2])
	L.outline(C[0]).draw(p, 0.0, 0.0, a)
	return {"x": st_.bx, "y": st_.by, "k": st_.best}


## A thick coin turning on its upright axis: radius r, thickness th, turned by theta (0 faces you). Each row
## shows the face (squashed by cos theta, a raised rim, a recessed field, an embossed star) and, beside it,
## the reeded edge band (th |sin theta| wide). Lit from the top left; the face flashes white as it squares
## to the light. Built in L with a dark outline. C: 8-step ramp. Returns the flash strength 0..1.
## opts: { a = 1, white = false }
static func coin3d(L: Layer, p: Px.Painter, x: float, y: float, r: float, th: float, theta: float, C: Array, opts: Dictionary = {}) -> float:
	var a: float = opts.get("a", 1.0)
	var white: bool = opts.get("white", false)
	var ct := cos(theta)
	var st := sin(theta)
	var sg := -1.0 if ct < 0.0 else 1.0
	var act := absf(ct)
	var ast := absf(st)
	var xc := (th / 2.0) * st * sg
	var nfx := st * sg
	var Lx := -0.55
	var Ly := 0.45
	var Lz := 0.7
	var Ln := Px.hypot(Lx, Ly, Lz)
	# the face's normal stays level, so its flash comes when it squares to the light's level direction
	var lam := (nfx * Lx + act * Lz) / Ln
	var Hx := Lx / Ln
	var Hz := Lz / Ln + 1.0
	var Hn := Px.hypot(Hx, Hz)
	var base := maxi(2, mini(5, Px.roundi(2.0 + lam * 3.2)))
	var X := Px.round(x)
	var Y := Px.round(y)
	var B := ceilf(r + th) + 2.0
	# flash: assigned inside the lambda
	var fl := [0.0]
	L.begin(X - B, Y - B)
	L.fill(X - B, Y - B, X + B, Y + B, func(px: float, py: float) -> Variant:
		var sx := px - X
		var sy := -(py - Y)
		if absf(sy) > r:
			return 0
		var s := sqrt(1.0 - pow(sy / r, 2))
		var hw := r * s * act
		var xr := -(-1.0 if st < 0.0 else 1.0) * s * r * ct
		var rw := (th / 2.0) * ast
		if white and (absf(sx - xc) <= hw or absf(sx - xr) <= rw + 0.05):
			return WHITE
		if absf(sx - xc) <= hw and act > 0.08:
			# on the face: un-squash to the face's own coordinates
			var fx := (sx - xc) / act
			var fy := sy
			var d := Px.hypot(fx, fy) / r
			# a faint curve across the face makes the flash sweep over it as it turns
			var tx := nfx + (fx / r) * 0.3 * act
			var sp := pow(maxf(0.0, (tx * Hx + act * Hz) / Hn / Px.hypot(tx, act)), 130.0)
			fl[0] = maxf(fl[0], sp)
			# relief in whole ramp steps so it shows at every angle: a raised rim lit on its upper left, a recessed
			# field, a raised diamond with lit and shaded faces
			var lit := (-fx * 0.6 + fy * 0.8) / maxf(0.5, Px.hypot(fx, fy))
			var k: int
			if d > 0.76:
				k = base + (2 if lit > 0.75 else (1 if lit > 0.3 else (-1 if lit < -0.35 else 0)))
			else:
				var q := (absf(fx) + absf(fy)) / (r * 0.52)
				k = base - 1 if q >= 1.0 else (base + 1 if q < 0.45 else (base + 1 if (fx <= 0.0 and fy >= 0.0) else (base - 2 if (fx > 0.0 and fy < 0.0) else base)))
			if sp > 0.5:
				return WHITE if sp > 0.8 else C[mini(7, k + 2)]
			return C[maxi(2, mini(6, k))]
		if absf(sx - xr) <= rw + 0.05:
			# the reeded edge: grooves across the band, lit by the edge's own normal
			var cphi := -s if xr < 0.0 else s
			var n := [cphi * ct, sy / r, -cphi * st]
			var l: float = (n[0] * Lx + n[1] * Ly + n[2] * Lz) / Ln
			var groove := floori((asin(sy / r) + PI) * 9.0) % 2
			var edge := absf(sx - xr) > rw - 0.6 and Px.sign(sx - xr) == Px.sign(xc - xr)
			return C[maxi(1, mini(6, Px.roundi(2.6 + l * 2.6) - groove + (1 if edge else 0)))]
		return 0)
	L.outline(C[1]).draw(p, 0.0, 0.0, a)
	return fl[0]
