# Shared by the melee effects: swings on a tilted circle (the smear, its dotted trace), floor cracks, rocks.
# The crescent and trace recipe is adapted from Sprite Fusion's open-source slash
# (https://www.spritefusion.com/pixel-art-vfx/slash), MIT License, Copyright (c) 2026 Hugo Duprez.
# Files starting with _ are helpers, not effects.
# port-of: src/fx/melee/_lib.js@29f91783deeaf07635202ce2005fc3bee644cefb
extends RefCounted

const Px := preload("../../core/px.gd")
const P := Px.P
const WHITE := Px.WHITE


## A swing: a circle of radius R around (cx, cy), squashed to sy across its plane (1 stands up facing us, 0.16
## lies on the floor) and turned by rot, swept from angle a0 in direction dir (+1 turns clockwise on screen).
## k lifts the band into a shallow cone: a point dr inside the rim sits k * dr higher, so a level ring shows its
## near half broad and its far half thin, like a blade angled down from the hilt (keep k below sy).
## Positions along it are u, radians from a0 in the swing's direction.
static func swing(o: Dictionary) -> Dictionary:
	return Px.merge({"cx": 0.0, "cy": 0.0, "R": 30.0, "sy": 1.0, "rot": 0.0, "a0": 0.0, "dir": 1.0, "k": 0.0}, o)


## A swing on radius R whose arc passes through (x, y) heading along angle th, that point `at` of the way along span.
static func through(x: float, y: float, th: float, dir: float, R: float, span: float, at: float = 0.55, extra: Dictionary = {}) -> Dictionary:
	var a := th - (dir * PI) / 2.0
	return swing(Px.merge({"cx": x - cos(a) * R, "cy": y - sin(a) * R, "R": R, "sy": 1.0, "rot": 0.0, "a0": a - dir * span * at, "dir": dir, "span": span}, extra))


## The screen point at plane radius r, u radians along the swing.
static func onSwing(s: Dictionary, r: float, u: float) -> Array:
	var a: float = s.a0 + s.dir * u
	var lx := cos(a) * r
	var ly: float = sin(a) * r * s.sy - s.k * (s.R - r)
	var c := cos(s.rot)
	var n := sin(s.rot)
	return [s.cx + lx * c - ly * n, s.cy + lx * n + ly * c]


## The on-screen unit direction the swing travels at u, and the in-plane angle there (sin < 0 is the far half).
static func travel(s: Dictionary, u: float) -> Dictionary:
	var p0 := onSwing(s, s.R, u)
	var p1 := onSwing(s, s.R, u + 0.01)
	var x0: float = p0[0]
	var y0: float = p0[1]
	var x1: float = p1[0]
	var y1: float = p1[1]
	var l := Px.hypot(x1 - x0, y1 - y0)
	if not l:
		l = 1.0
	return {"x": x0, "y": y0, "dx": (x1 - x0) / l, "dy": (y1 - y0) / l, "a": s.a0 + s.dir * u}


## The plane radius and angle under a screen point (inverts onSwing, cone included).
static func plane(s: Dictionary, x: float, y: float) -> Array:
	var c := cos(s.rot)
	var n := sin(s.rot)
	var dx: float = x - s.cx
	var dy: float = y - s.cy
	var lx := dx * c + dy * n
	var ly := -dx * n + dy * c
	if not s.k:
		return [Px.hypot(lx, ly / s.sy), atan2(ly / s.sy, lx)]
	# r sin(a) sy = m - k r, r cos(a) = lx  =>  r^2 (sy^2 - k^2) + 2 m k r - (lx^2 sy^2 + m^2) = 0
	var m: float = ly + s.k * s.R
	var A: float = s.sy * s.sy - s.k * s.k
	var B: float = 2.0 * m * s.k
	var Cc: float = lx * lx * s.sy * s.sy + m * m
	var r := (-B + sqrt(B * B + 4.0 * A * Cc)) / (2.0 * A)
	return [r, atan2((m - s.k * r) / s.sy, lx)]


## Shade a swing's band from u0 to u1 (u1 - u0 at most a full turn), plane radius R + pad down to R - wMax - 1.
## fn(u, r, out, a) shades each pixel: u along the swing, r its plane radius, a the in-plane angle. half: 0 the
## whole band, -1 only the far half (behind a character), 1 only the near half.
static func smear(p: Px.Painter, s: Dictionary, u0: float, u1: float, wMax: float, fn: Callable, half: float = 0.0, pad: float = 1.0) -> void:
	if u1 - u0 < 0.005:
		return
	var c := cos(s.rot)
	var n := sin(s.rot)
	var A: float = s.R + pad + 1.0
	var Bn: float = A * s.sy + s.k * (wMax + 2.0)
	var hx := Px.hypot(A * c, Bn * n) + 1.0
	var hy := Px.hypot(A * n, Bn * c) + 1.0
	var rIn: float = s.R - wMax - 1.0
	# each half only needs its side of the centre (plus what the tilt and the cone lift can reach across)
	var over: float = absf(n) * A + s.k * (wMax + 2.0) + 2.0
	var y0: float = s.cy - over if half > 0.0 else s.cy - hy
	var y1: float = s.cy + over if half < 0.0 else s.cy + hy
	var fna := fn.get_argument_count()
	p.shade(s.cx - hx, y0, s.cx + hx, y1, func(x, y, out):
		var ra := plane(s, x, y)
		var r: float = ra[0]
		var a: float = ra[1]
		if r > s.R + pad or r < rIn:
			return
		if half and (-1.0 if sin(a) < 0.0 else 1.0) != half:
			return
		var u := fmod(s.dir * (a - s.a0), TAU)
		if u < 0.0:
			u += TAU
		while u < u0:
			u += TAU
		if u > u1:
			return
		return Px.call4(fn, fna, u, r, out, a))


## Dots along a swing at plane radius r from u0 to u1, every `step` px, alpha a(u) (dithered into a dotted trace).
static func trace(p: Px.Painter, s: Dictionary, r: float, u0: float, u1: float, c: Variant, a: Variant, half: float = 0.0, step: float = 0.6) -> void:
	var du := step / maxf(4.0, r)
	var u := u0
	while u <= u1:
		var g: float = s.a0 + s.dir * u
		if half and (-1.0 if sin(g) < 0.0 else 1.0) != half:
			u += du
			continue
		var xy := onSwing(s, r, u)
		var k: float = a.call(u) if a is Callable else a
		if k > 0.0:
			p.dot(xy[0], xy[1], c.call(u) if c is Callable else c, k)
		u += du


## Glow riding a swing from u0 to u1 (light along the arc).
static func glowAlong(p: Px.Painter, s: Dictionary, r: float, u0: float, u1: float, rad: float, c: int, k: Variant, half: float = 0.0, step: float = 0.35) -> void:
	var u := u0
	while u <= u1:
		var g: float = s.a0 + s.dir * u
		if half and (-1.0 if sin(g) < 0.0 else 1.0) != half:
			u += step
			continue
		var xy := onSwing(s, r, u)
		var kk: float = k.call(u) if k is Callable else k
		if kk > 0.004:
			p.glow(xy[0], xy[1], rad, c, kk)
		u += step


## A slash crescent along swing s (Sprite Fusion's recipe): the edge whips out over s.span radians in s.sweep s,
## holds, then the tail follows over s.trail, thinning and cooling down s.ramp (dark to bright); a dotted trace
## lingers where it passed. s: a swing plus { span, W, t0, sweep, hold, trail, ramp, hot (0..1 flashes it white),
## lens (thickest in the middle, not just behind the edge) }.
static func slash(p: Px.Painter, s: Dictionary, t: float, half: float = 0.0) -> void:
	var u: float = t - s.t0
	if u < 0.0:
		return
	var R: Array = s.ramp
	var n := R.size()
	var life: float = s.sweep + s.hold + s.trail
	var hot: float = s.hot if s.get("hot") != null else 0.0
	var lens: bool = true if s.get("lens") else false
	var head := Px.Ease.outExpo(Px.clamp(u / s.sweep))
	var tail := Px.smooth(s.sweep + s.hold, life, u)
	var age := Px.clamp(u / life)
	var U: float = s.span * head
	var T: float = s.span * tail
	var W: float = s.W * (1.0 - tail * 0.55)
	if tail < 1.0 and U - T > 0.01:
		smear(p, s, T, U, W, func(uu, r, out):
			var v: float = (uu - T) / (U - T)
			var w := W * pow(sin(PI * pow(v, 1.0 if lens else 2.2)), 0.75 if lens else 0.6)
			if w < 0.35:
				return
			var q: float = (s.R - r) / w
			if q < 0.0 or q > 1.0:
				return
			var ci := 0.0 if ((q < 0.22 and age < 0.5) or q < hot * 0.7) else Px.round(q * (n - 1) * 0.75 + age * 2.4 - v * 0.8 + 0.4 - hot * 3.0)
			out.c = R[n - 1 - int(Px.clamp(ci, 0.0, n - 1))]
			out.a = minf(1.0, v / (0.1 if lens else 0.4)), half)
		glowAlong(p, s, s.R - W * 0.4, T, U, 5.0 + W, R[n - 3], func(uu): return (0.22 + hot * 0.3) * (1.0 - age) * ((uu - T) / (U - T)), half, 0.3)
	var th := 0.7 * (1.0 - Px.clamp((u - s.sweep - s.hold) / (s.trail + 0.2)))
	if tail > 0.02 and th > 0.0:
		trace(p, s, s.R - 0.5, 0.0, T, R[2], func(uu): return th * (0.4 + 0.6 * uu / s.span), half)


## Where a slash's edge ends up, and which way it's travelling there.
static func slashEnd(s: Dictionary) -> Dictionary:
	return travel(Px.merge(s, {"R": s.R - s.W * 0.3}), s.span)


## Shavings flung off a slash's edge, outward from its circle (Sprite Fusion's slash).
static func shavings(ps: Px.Particles, R: Px.Rng, s: Dictionary, n: float, colors: Array, from: float = 0.3) -> void:
	var i := 0
	while i < n:
		var xy := onSwing(s, s.R, s.span * R.range(from, 1.0))
		var x: float = xy[0]
		var y: float = xy[1]
		var ox: float = x - s.cx
		var oy: float = y - s.cy
		var l := Px.hypot(ox, oy)
		if not l:
			l = 1.0
		var sp := R.range(30.0, 100.0)
		ps.spawn(P.MOTE, x, y, (ox / l) * sp, minf(25.0, (oy / l) * sp) - 10.0, R.range(0.25, 0.55), R.pick(colors), 0.6)
		i += 1


## Stone shades for rocks, grit and dust from one body color (as Sprite Fusion's explosion does).
static func stone(c: Variant) -> Dictionary:
	var h := Px.hex(c)
	return {"light": Px.mix(Px.scale(h, 1.35), WHITE, 0.08), "body": h, "shade": Px.scale(h, 0.64), "dust": Px.mix(Px.scale(h, 1.2), Px.rgb(150, 140, 150), 0.3), "dark": Px.scale(h, 0.42)}


static var OUTLINE := Px.hex("#1a1422")
## A tumbling rock (a Bits CHUNK): a lit side, a shaded side, an outline, fading at the end of its life.
static func rock(p: Px.Painter, b: Dictionary, st: Dictionary) -> void:
	var r: float = 0.6 + b.s * 0.75
	var fade: float = minf(1.0, b.life / 0.5)
	var lx: float = cos(b.a) * r * 0.4
	var ly: float = sin(b.a) * r * 0.4
	var outline := OUTLINE
	p.shade(b.x - r - 1.0, b.y - r - 1.0, b.x + r + 1.0, b.y + r + 1.0, func(x, y, out):
		var dx: float = x - b.x
		var dy: float = y - b.y
		var d := Px.hypot(dx * 1.15, dy)
		if d > r + 0.9:
			return
		var lit := dx * lx + dy * ly
		out.c = outline if d > r else (st.light if lit < -0.4 else (st.shade if lit > 0.6 else st.body))
		out.a = fade)


## Jagged cracks splitting the floor from x0: each runs out along the floor's edge and zig-zags down into its
## face (y from 0 to about depth), with short forks. n cracks alternate sides (bias > 0 sends more forward).
## Returns [{ pts, at (0..1 how far out it starts), fork }]. Built once from an Rng.
static func cracks(R: Px.Rng, x0: float, n: float, reach: float, depth: float = 7.0, bias: float = 0.3) -> Array:
	var out := []
	var i := 0
	while i < n:
		var side := 1.0 if R.chance(0.5 + bias * 0.5) else -1.0
		var L := reach * R.range(0.45, 1.0) * (1.0 if i < 2 else 0.7)
		var pts := [[x0 + side * R.range(0.0, 1.5), 0.0]]
		var x: float = pts[0][0]
		var y := 0.0
		while absf(x - x0) < L and y < depth:
			x += side * R.range(1.5, 3.5)
			y = minf(depth, maxf(0.0, y + R.range(-0.6, 1.6) * (1.0 if absf(x - x0) > 3.0 else 0.3)))
			pts.append([Px.round(x), Px.round(y)])
			if R.chance(0.18) and pts.size() > 3 and y < depth - 2.0:
				var f := [[Px.round(x), Px.round(y)]]
				var fx := x
				var fy := y
				var j := R.int_(1, 3)
				while j > 0:
					fx += side * R.range(1.0, 3.0)
					fy += R.range(0.8, 2.0)
					f.append([Px.round(fx), Px.round(minf(depth + 1.0, fy))])
					j -= 1
				out.append({"pts": f, "at": absf(x - x0) / reach, "fork": true})
		out.append({"pts": pts, "at": 0.0, "fork": false})
		i += 1
	return out


## An impact star (after Sprite Fusion's impact): tapered spikes [{ a, len, w }] around (x, y), drawn in three
## passes (rim, body, core) with a hot disc in the middle. sc stretches, th thins.
static func star(p: Px.Painter, x: float, y: float, spikes: Array, sc: float, th: float, core: Variant, body: Variant, inner: Variant, rim: Variant) -> void:
	for pass_ in [0, 1, 2]:
		for s: Dictionary in spikes:
			var c := cos(s.a)
			var sn := sin(s.a)
			var L: float = s.len * sc
			var d := 0.0
			while d <= L:
				var hw0: float = s.w * th * (1.0 - d / L) * minf(1.0, 0.5 + d / 3.0)
				var hw := hw0 + 0.8 if pass_ == 0 else (hw0 if pass_ == 1 else hw0 * 0.45)
				if pass_ == 2 and d > L * 0.55:
					break
				var o := -hw
				while o <= hw:
					p.px(x + c * d - sn * o, y + sn * d + c * o, rim if pass_ == 0 else ((inner if d < L * 0.35 else body) if pass_ == 1 else core))
					o += 0.5
				d += 0.5
	var r := 2.4 * sc * sqrt(th)
	p.circle(x, y, r + 0.8, inner)
	p.circle(x, y, r, core)


## A thin arc flying out from (x, y): a sliver at radius r around angle a, arc radians long, dithered by k.
static func sliver(p: Px.Painter, x: float, y: float, a: float, r: float, arc: float, c: Variant, k: float) -> void:
	var n := ceilf(r * arc * 2.2)
	var j := 0
	while j <= n:
		var u := j / n - 0.5
		var th := a + u * arc
		var w := 1.4 * (1.0 - absf(u) * 2.0)
		var o := -w * 0.5
		while o <= w * 0.5 + 0.01:
			p.dot(x + cos(th) * (r + o), y + sin(th) * (r + o), c, k)
			o += 0.5
		j += 1


## Part of a polyline: the first `len` px of it. Calls fn(x0, y0, x1, y1, d) for each piece (d: distance along).
static func along(pts: Array, len: float, fn: Callable) -> void:
	var fna := fn.get_argument_count()
	var d := 0.0
	var i := 1
	while i < pts.size() and d < len:
		var x0: float = pts[i - 1][0]
		var y0: float = pts[i - 1][1]
		var x1: float = pts[i][0]
		var y1: float = pts[i][1]
		var l := Px.hypot(x1 - x0, y1 - y0)
		var f := minf(1.0, (len - d) / l)
		if fna >= 5:
			fn.call(x0, y0, x0 + (x1 - x0) * f, y0 + (y1 - y0) * f, d)
		else:
			Px.call4(fn, fna, x0, y0, x0 + (x1 - x0) * f, y0 + (y1 - y0) * f)
		d += l
		i += 1
