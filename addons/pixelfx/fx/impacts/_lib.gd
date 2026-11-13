# Shared by the impacts: the hit star, a ring that breaks into flying arcs, floor cracks that glow and cool,
# standing shock fronts, soft lumpy dust rings, faceted tumbling rocks, and the stone colors they share.
# The star and flying-arc recipes are adapted from Sprite Fusion's open-source impact
# (https://www.spritefusion.com/pixel-art-vfx/impact), and the stone colors from its explosion
# (https://www.spritefusion.com/pixel-art-vfx/explosion), MIT License, Copyright (c) 2026 Hugo Duprez.
# Files starting with _ are helpers, not effects.
# port-of: src/fx/impacts/_lib.js@3f042cb27f2e07a149d6f4fbf19615f7ec5f0a93
extends RefCounted

const Px := preload("../../core/px.gd")
const WHITE := Px.WHITE

static var SOOT := Px.hex("#0d0a12")
static var OUTLINE := Px.hex("#1a1422")
static var LIGHT := atan2(-1.0, -1.0)  # light comes from the top left


## Stone colors from one body color: light, body, shade, dust (lighter and greyer), lip (a lit broken edge).
static func stone(c: Variant) -> Dictionary:
	var cc := Px.hex(c)
	return {"light": Px.mix(Px.scale(cc, 1.35), WHITE, 0.08), "body": cc, "shade": Px.scale(cc, 0.64), "dust": Px.mix(Px.scale(cc, 1.2), Px.rgb(150, 140, 150), 0.3), "lip": Px.mix(Px.scale(cc, 1.55), WHITE, 0.12)}


## Spikes for a hit star: n of them round the circle, longer towards aim (fwd) and a little behind it (back).
## len and w: [min, max] base length and root half-width; jag scales every other spike (short teeth between).
static func spikes(R: Px.Rng, n: float, aim: float, opts: Dictionary = {}) -> Array:
	var ln: Array = opts.get("len", [7.0, 10.0])
	var w: Array = opts.get("w", [1.5, 2.1])
	var fwd: float = opts.get("fwd", 1.8)
	var back: float = opts.get("back", 0.6)
	var jag: float = opts.get("jag", 1.0)
	var jit: float = opts.get("jit", 0.18)
	return Px.arr(n, func(i: int):
		var a := aim + (i / n) * TAU + R.range(-jit, jit)
		var cb := cos(a - aim)
		var L := R.range(ln[0], ln[1]) * (1.0 + fwd * pow(maxf(0.0, cb), 3.0) + back * pow(maxf(0.0, -cb), 3.0)) * (jag if i % 2 else 1.0)
		return {"a": a, "len": L, "w": R.range(w[0], w[1]) * (sqrt(jag) if i % 2 else 1.0)})


## A hit star: tapered spikes in three passes (a rim, a body that's paler near the root, a hot core) round a
## hot heart. sc stretches the spikes, th thins them, cols [rim, body, inner, core], a dithers it out.
static func star(p: Px.Painter, x: float, y: float, list: Array, sc: float, th: float, cols: Array, a: float = 1.0, heart: float = 2.4) -> void:
	var rim: int = cols[0]
	var body: int = cols[1]
	var inner: int = cols[2]
	var core: int = cols[3]
	for pass_ in 3:
		for s: Dictionary in list:
			var c := cos(s.a)
			var sn := sin(s.a)
			var L: float = s.len * sc
			var d := 0.0
			while d <= L:
				if pass_ == 2 and d > L * 0.55:
					break
				var hw0: float = s.w * th * (1.0 - d / L) * minf(1.0, 0.5 + d / 3.0)
				var hw := hw0 + 0.8 if pass_ == 0 else (hw0 if pass_ == 1 else hw0 * 0.45)
				var col := rim if pass_ == 0 else ((inner if d < L * 0.35 else body) if pass_ == 1 else core)
				var o := -hw
				while o <= hw:
					p.dot(x + c * d - sn * o, y + sn * d + c * o, col, a)
					o += 0.5
				d += 0.5
	var r := heart * sc * sqrt(th)
	p.circle(x, y, r + 0.8, inner, a)
	p.circle(x, y, r, core, a)


## A ring that breaks into arcs: segs [{ a (centre angle), gap (0..1), dr (how fast it flies out), w (thickness
## scale, default 1) }] evenly round the ring. brk 0 draws a whole ring th thick; as brk grows each arc shrinks,
## tapers at both ends into a crescent and drifts out at its own speed. c is the outer edge's color, c2 the
## inner's; sy squashes it onto a plane; nothing is drawn below maxY (a floor).
static func brokenRing(p: Px.Painter, x: float, y: float, r: float, th: float, segs: Array, brk: float, c: int, c2: Variant = null, k: float = 1.0, sy: float = 1.0, maxY: float = INF) -> void:
	if c2 == null:
		c2 = c
	if r <= 0.0 or k <= 0.0:
		return
	var full := TAU / segs.size()
	for s: Dictionary in segs:
		var span: float = full * (1.0 - s.gap * brk) + 0.02
		var rr: float = r * (1.0 + s.dr * brk)
		var m := maxf(4.0, ceilf(rr * span * 1.8))
		var j := 0.0
		while j <= m:
			var u := j / m
			var ang: float = s.a + (u - 0.5) * span
			var sw: float = s.w if s.get("w") != null else 1.0
			var w := maxf(0.5, th * sw * (1.0 - brk * pow(absf(2.0 * u - 1.0), 1.6)))
			var ca := cos(ang)
			var sa := sin(ang)
			var o := -w / 2.0
			while o <= w / 2.0 + 0.01:
				if y + sa * (rr + o) * sy < maxY:
					p.dot(x + ca * (rr + o), y + sa * (rr + o) * sy, c if o > -0.26 else c2, k)
				o += 0.5
			j += 1.0


# a jagged walk from (x, y) heading a for L px; each point is [x, y, distance along]
static func walk(R: Px.Rng, x: float, y: float, a: float, L: float, opts: Dictionary = {}) -> Array:
	var jit: float = opts.get("jit", 0.55)
	var steer: float = opts.get("steer", 0.45)
	var step: Array = opts.get("step", [2.0, 4.0])
	var maxY: float = opts.get("maxY", INF)
	var d0: float = opts.get("d0", 0.0)
	var pts := [[x, y, d0]]
	var d := 0.0
	var cur := a
	while d < L - 0.01:
		var s := minf(L - d, R.range(step[0], step[1]))
		cur += R.range(-jit, jit) + (a - cur) * steer
		x += cos(cur) * s
		y = Px.clamp(y + sin(cur) * s, 0.5, maxY)
		d += s
		pts.append([x, y, d0 + d])
	return pts


## Cracks in the floor face below (0, 0): n jagged lines, alternately left and right, mostly shallow, a few
## diving steeply, some forked. len [min, max], maxY how deep they may go, forks 0..1.
static func makeCracks(R: Px.Rng, n: int, opts: Dictionary = {}) -> Array:
	var ln: Array = opts.get("len", [14.0, 40.0])
	var dive: float = opts.get("dive", 0.85)
	var maxY: float = opts.get("maxY", 22.0)
	var forks: float = opts.get("forks", 0.5)
	var x0: Array = opts.get("x0", [1.0, 5.0])
	var out := []
	for i in n:
		var side := 1.0 if i % 2 else -1.0
		var dip := 0.06 + pow(R.next(), 1.7) * dive
		var L := R.range(ln[0], ln[1]) * (1.0 - (0.5 * dip) / (dive + 0.06))
		var a := dip if side > 0.0 else PI - dip
		var pts := walk(R, side * R.range(x0[0], x0[1]), R.range(0.5, 1.5), a, L, {"maxY": maxY})
		var c := {"pts": pts, "len": L, "t0": R.range(0.0, 0.035), "kids": []}
		for j in range(2, pts.size() - 1):
			if R.chance(forks * 0.4):
				var fx: float = pts[j][0]
				var fy: float = pts[j][1]
				var fd: float = pts[j][2]
				c.kids.append(walk(R, fx, fy, a + R.sign() * R.range(0.45, 1.0), R.range(3.0, 9.0) * (1.0 - (0.5 * j) / pts.size()), {"maxY": maxY, "d0": fd, "jit": 0.7, "step": [1.5, 3.0]}))
		out.append(c)
	return out


## Draw cracks grown to g(c) px of their length. heat(d) 0..1 at distance d along a crack lights it from the
## hot ramp (bright to dark) before it cools to dark; lip is the lit lower edge; k dithers them out.
## Returns nothing; adds a glow along the hot parts.
static func drawCracks(p: Px.Painter, cracks: Array, g: Callable, heat: Callable, hot: Array, dark: int, lip: int, k: float = 1.0) -> void:
	if k <= 0.0:
		return
	var col := func(d: float) -> int:
		var h: float = heat.call(d)
		return hot[0] if h > 0.75 else (hot[1] if h > 0.5 else (hot[2] if h > 0.3 else (hot[3] if h > 0.12 else dark)))
	for c: Dictionary in cracks:
		var G: float = g.call(c)
		if G <= 0.0:
			continue
		for path: Array in [c.pts] + c.kids:
			for i in range(1, path.size()):
				var x0: float = path[i - 1][0]
				var y0: float = path[i - 1][1]
				var d0: float = path[i - 1][2]
				var x1: float = path[i][0]
				var y1: float = path[i][1]
				var d1: float = path[i][2]
				if d0 >= G:
					break
				var f := (G - d0) / (d1 - d0) if d1 > G else 1.0
				var ex := x0 + (x1 - x0) * f
				var ey := y0 + (y1 - y0) * f
				p.line(x0, y0 + 1.0, ex, ey + 1.0, lip, func(u): return k * 0.8 if Px.rand(Px.round(x0 + (ex - x0) * u), Px.round(y0 + (ey - y0) * u), 5) < 0.3 else 0.0)
				p.line(x0, y0, ex, ey, func(u): return col.call(d0 + (d1 - d0) * f * u), k)
				var h: float = heat.call(d0)
				if h > 0.12:
					p.glow((x0 + ex) / 2.0, (y0 + ey) / 2.0, 4.0 + h * 4.0, hot[2], 0.22 * h * k)


## A standing crescent shock front on the floor (y = 0): it leans back from a leading edge low at x, dir 1
## racing right ")", -1 left "(". h tall, w thick at its widest (thick where it meets the floor, a point at
## the top); cols [edge, body, back] bright to dark; k dithers it out.
static func frontCrescent(p: Px.Painter, x: float, dir: float, h: float, w: float, cols: Array, k: float = 1.0) -> void:
	if h < 1.0 or w < 0.3 or k <= 0.0:
		return
	var ry := h * 0.8
	var cy := -h * 0.2
	var rx := maxf(2.0, h * 0.55)
	var x0 := x - rx - w - 1.0 if dir > 0.0 else x - 1.0
	var x1 := x + 1.0 if dir > 0.0 else x + rx + w + 1.0
	p.shade(x0, -h - 1.0, x1, 0.0, func(px, py, out):
		if py > 0.0:
			return
		var ey: float = (py - cy) / ry
		if ey <= -1.0 or ey >= 1.0:
			return
		var e2 := 1.0 - ey * ey
		var edge := rx * sqrt(e2) - rx
		var wt := w * pow(e2, 0.45)
		var q: float = (edge - (px - x) * dir) / maxf(0.5, wt)
		if q < 0.0 or q > 1.0:
			return
		out.c = cols[0] if q < 0.28 else (cols[1] if q < 0.62 else cols[2])
		out.a = k * (0.7 if ey < -0.8 else 1.0) * (1.25 - q * 0.8 if q > 0.7 else 1.0))


## A soft, lumpy ring of dust round (cx, cy): radius r, w thick (lumps swell it), alpha k, translucent and lit
## on its upper side. sy squashes it onto the floor; brk 0..1 tears it into clumps as it thins; ph varies it;
## nothing is drawn below maxY; half -1 draws only the far half (above cy), 1 only the near half.
static func dustRing(p: Px.Painter, cx: float, cy: float, r: float, w: float, k: float, c: int, opts: Dictionary = {}) -> void:
	var sy: float = opts.get("sy", 1.0)
	var ph: float = opts.get("ph", 0.0)
	var brk: float = opts.get("brk", 0.0)
	var lit: float = opts.get("lit", 0.35)
	var maxY: float = opts.get("maxY", INF)
	var half: float = opts.get("half", 0.0)
	if k <= 0.01 or r <= 0.0:
		return
	var W := w * 1.6
	var lite := Px.mix(c, WHITE, lit)
	var y := floorf(cy - (r + W) * sy) - 1.0
	while y <= minf(maxY - 1.0, ceilf(cy + (r + W) * sy) + 1.0):
		var x := floorf(cx - r - W) - 1.0
		while x <= ceilf(cx + r + W) + 1.0:
			var dx := x + 0.5 - cx
			var dy := (y + 0.5 - cy) / sy
			var d := Px.hypot(dx, dy)
			var g := atan2(dy, dx)
			if (half < 0.0 and dy >= 0.0) or (half > 0.0 and dy < 0.0):
				x += 1.0
				continue
			var lumpy := 0.6 + 0.3 * sin(5.0 * g + ph) + 0.18 * sin(11.0 * g + ph * 2.1) + 0.12 * sin(17.0 * g + ph * 0.7)
			var wt := w * lumpy
			var off := absf(d - r - w * 0.25 * sin(7.0 * g + ph))
			if off >= wt:
				x += 1.0
				continue
			var tear := Px.clamp((0.55 + 0.45 * sin(6.0 * g + ph * 1.7) - brk) / 0.25) if brk > 0.0 else 1.0
			var a := k * (1.0 - pow(off / wt, 2.0)) * tear
			if a > 0.01:
				p.blend(x, y, lite if (dy < 0.0 and d > r - wt * 0.3) else c, a)
			x += 1.0
		y += 1.0


## A rock's outline: n vertex radii round its centre.
static func rockShape(R: Px.Rng, n: float = 6) -> Array:
	return Px.arr(n, func(_i): return R.range(0.7, 1.12))


## A faceted rock tumbling at angle b.a: every facet shaded by how it faces the light, a lit top face, a dark
## outline, dithering out over its last half second. b: { x, y, a, s (1..3), life, pts }, st: stone().
static func rock(p: Px.Painter, b: Dictionary, st: Dictionary) -> void:
	var r: float = 0.75 + b.s * 0.8
	var n: int = b.pts.size()
	var fade := minf(1.0, b.life / 0.5)
	var ca := cos(b.a)
	var sa := sin(b.a)
	var pts: Array = b.pts
	var bx: float = b.x
	var by: float = b.y
	var ba: float = b.a
	var outline := OUTLINE
	var light := LIGHT
	p.shade(bx - r - 2.0, by - r - 2.0, bx + r + 2.0, by + r + 2.0, func(x, y, out):
		var dx: float = x - bx
		var dy: float = y - by
		var u := dx * ca + dy * sa
		var v := -dx * sa + dy * ca
		var d := Px.hypot(u, v)
		var ang := atan2(v, u)
		if ang < 0.0:
			ang += TAU
		var f := (ang / TAU) * n
		var i := floori(f) % n
		var w := f - floorf(f)
		var edge: float = r * (pts[i] * (1.0 - w) + pts[(i + 1) % n] * w)
		if d > edge + 0.85:
			return
		out.a = fade
		if d > edge:
			return outline
		var lit := cos(((i + 0.5) / n) * TAU + ba - light)
		if d < edge * 0.42:
			return st.light if lit > 0.55 else st.body
		return st.light if lit > 0.35 else (st.shade if lit < -0.4 else st.body))
