# Shared by the nature effects: faceted stones that tumble and break, the stone spike they break from, leaves,
# droplets, bubbles and gas. The gas (puffs that drift off their push, rise, swell and thin, a lit cap) is adapted
# from Sprite Fusion's open-source poison (https://www.spritefusion.com/pixel-art-vfx/poison), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/nature/_lib.js@e773ce96af094c90ce01d0f476de1348d7645cb6
extends RefCounted

const Px := preload("../../core/px.gd")
const Self := preload("_lib.gd")
const WHITE := Px.WHITE
const GRAVITY := Px.GRAVITY


## Corners of an irregular stone, unit size, in angular order.
static func stoneShape(R: Px.Rng, n_: Variant = null) -> Array:
	var n: int = R.int_(5, 7) if n_ == null else int(n_)
	var pts := []
	var a0 := R.range(0.0, TAU)
	var squash := R.range(0.7, 1.0)
	for i in n:
		var a := a0 + ((i + R.range(-0.28, 0.28)) * TAU) / n
		var r := R.range(0.72, 1.12)
		pts.append([cos(a) * r, sin(a) * r * squash])
	return pts


const LX := -0.6
const LY := -0.8


static func inPoly(V: Array, x: float, y: float) -> bool:
	var inside := false
	var i := 0
	var j := V.size() - 1
	while i < V.size():
		var xi: float = V[i][0]
		var yi: float = V[i][1]
		var xj: float = V[j][0]
		var yj: float = V[j][1]
		if (yi > y) != (yj > y) and x < ((xj - xi) * (y - yi)) / (yj - yi) + xi:
			inside = not inside
		j = i
		i += 1
	return inside


const ROWS := 400
static var MASK := _bytes(64 * 64)
static var FACE := _ints(64 * 64)
static var RL := _f32(ROWS)
static var RR := _f32(ROWS)
static var RU := _f32(ROWS)


static func _bytes(n: int) -> PackedByteArray:
	var a := PackedByteArray()
	a.resize(n)
	a.fill(0)
	return a


static func _ints(n: int) -> PackedInt32Array:
	var a := PackedInt32Array()
	a.resize(n)
	a.fill(0)
	return a


static func _f32(n: int) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(n)
	a.fill(0.0)
	return a


static func _at(i: int, j: int, N: int) -> bool:
	return i >= 0 and j >= 0 and i < N and j < N and MASK[j * 64 + i] == 1


## A faceted stone at (x, y): corners pts (from stoneShape) scaled by s and turned by a. Each wedge between
## neighbouring corners is a facet, lit by how squarely it faces the top left; edges facing the light catch a
## bright rim, a dark rim goes round the rest. S: stone ramp, dark to bright (7+ steps). alpha dithers it out.
static func drawRock(p: Px.Painter, x: float, y: float, s: float, a: float, pts: Array, S: Array, alpha: float = 1.0, white: bool = false) -> void:
	var n := S.size()
	var top := n - 2
	var ca := cos(a)
	var sa := sin(a)
	if s < 1.4:
		p.dot(x, y, S[top - 1], alpha)
		p.dot(x + 1.0, y, S[top - 3], alpha)
		return
	var V := []
	for q in pts:
		var u: float = q[0]
		var v: float = q[1]
		V.append([(u * ca - v * sa) * s, (u * sa + v * ca) * s])
	var ang := []
	for q in V:
		ang.append(atan2(q[1], q[0]))
	# each facet's light: its edge's outward normal against the light
	var lit := []
	for i in V.size():
		var ax: float = V[i][0]
		var ay: float = V[i][1]
		var bx: float = V[(i + 1) % V.size()][0]
		var by: float = V[(i + 1) % V.size()][1]
		var ex := bx - ax
		var ey := by - ay
		var l := Px.hypot(ex, ey)
		if not l:
			l = 1.0
		var nx := ey / l
		var ny := -ex / l
		if nx * (ax + bx) + ny * (ay + by) < 0.0:
			nx = -nx
			ny = -ny
		lit.append(nx * LX + ny * LY)
	var X0 := floori(x) - ceili(s * 1.25) - 1
	var Y0 := floori(y) - ceili(s * 1.25) - 1
	var N := mini(62, 2 * ceili(s * 1.25) + 3)
	for j in N:
		for i in N:
			var dx := X0 + i + 0.5 - x
			var dy := Y0 + j + 0.5 - y
			var k := j * 64 + i
			MASK[k] = 1 if inPoly(V, dx, dy) else 0
			if not MASK[k]:
				continue
			var g := atan2(dy, dx)
			var f := 0
			for q in ang.size():
				var a0: float = ang[q]
				var a1: float = ang[(q + 1) % ang.size()]
				var d := fmod(g - a0, TAU)
				var span := fmod(a1 - a0, TAU)
				if d < 0.0:
					d += TAU
				if span < 0.0:
					span += TAU
				if d <= span:
					f = q
					break
			FACE[k] = f
	for j in range(-1, N + 1):
		for i in range(-1, N + 1):
			var X := X0 + i
			var Y := Y0 + j
			if not _at(i, j, N):
				if _at(i - 1, j, N) or _at(i + 1, j, N) or _at(i, j - 1, N) or _at(i, j + 1, N):
					p.dot(X, Y, S[0], alpha)
				continue
			if white:
				p.dot(X, Y, WHITE, alpha)
				continue
			var L: float = lit[FACE[j * 64 + i]]
			var edge := not _at(i - 1, j, N) or not _at(i + 1, j, N) or not _at(i, j - 1, N) or not _at(i, j + 1, N)
			var c: int = S[top] if L > 0.55 else (S[top - 1] if L > 0.15 else (S[top - 2] if L > -0.3 else S[top - 3]))
			if edge:
				c = S[top + 1] if L > 0.3 else (S[maxi(1, top - 4)] if L < -0.2 else c)
			p.dot(X, Y, c, alpha)


static func _hw(u: float, side: int, w: float, sp: Dictionary) -> float:
	var v := (w / 2.0) * pow(maxf(0.0, 1.0 - u), 0.85) + 0.3
	for n in sp.notches:
		if n.side == side and u > n.u and u < n.u + 0.07:
			v -= n.d * (1.0 - u * 0.5)
	return maxf(0.0, v)


static func _spikeIn(px: int, py: int, Y0: int, NR: int, clip: float, half: float) -> bool:
	var k := py - Y0
	var fx := px + 0.5
	if k < 0 or k >= NR or fx < RL[k] or fx > RR[k]:
		return false
	if clip < 1.0 and RU[k] > clip + (Px.rand(px, 77) - 0.5) * 0.07:
		return false
	if not half:
		return true
	var q := ((fx - RL[k]) / maxf(0.5, RR[k] - RL[k])) * 2.0 - 1.0
	return q < -0.18 if half < 0.0 else q >= -0.18


## A faceted stone spike standing on (x, base): h tall, w wide at the base, its tip `lean` px over. A ridge
## splits a lit left face from a shaded right face; strata step across both; notches chip the edges; a dark
## rim goes round it. sp: { notches: [{ u, side, d }], strata: [u], slope } from spikeLook(). S: stone ramp
## (8 steps). opts: { a, white, glint (0..1 height of a sweeping highlight, or -1), clip (draw only u < clip, with a
## ragged edge), half (-1 or 1: only the part left or right of the ridge), floor (draw nothing below this y),
## cracks: [[[u, v], ...], ...] with crack (0..1 of each drawn), heat (0..1: cracks glow) and glowRamp }.
static func drawSpike(p: Px.Painter, x: float, base: float, h: float, w: float, lean: float, sp: Dictionary, S: Array, opts: Dictionary = {}) -> void:
	if h < 1.5:
		return
	var a: float = opts.get("a", 1.0)
	var white: bool = opts.get("white", false)
	var glint: float = opts.get("glint", -1.0)
	var clip: float = opts.get("clip", 1.0)
	var floorY: float = opts.get("floor", INF)
	var half: float = opts.get("half", 0.0)
	var Y0 := floori(base - h) - 2
	var NR := mini(ROWS, ceili(base) - Y0 + 2)
	# each row's edges, once
	for k in NR:
		var u := (base - (Y0 + k + 0.5)) / h
		RU[k] = u
		if u < 0.0 or u > 1.0 or Y0 + k + 0.5 > floorY:
			RL[k] = INF
			RR[k] = -INF
		else:
			RL[k] = x + lean * u - _hw(u, -1, w, sp)
			RR[k] = x + lean * u + _hw(u, 1, w, sp)
	var X0 := floori(x - w / 2.0 - absf(lean) - 2.0)
	var X1 := ceili(x + w / 2.0 + absf(lean) + 2.0)
	var nS := S.size()
	for py in range(floori(base - h) - 1, ceili(base)):
		for px in range(X0, X1 + 1):
			if not _spikeIn(px, py, Y0, NR, clip, half):
				if py + 0.5 <= floorY and (_spikeIn(px - 1, py, Y0, NR, clip, half) or _spikeIn(px + 1, py, Y0, NR, clip, half) or _spikeIn(px, py + 1, Y0, NR, clip, half) or (_spikeIn(px, py - 1, Y0, NR, clip, half) and py < base - 1.0)):
					p.dot(px, py, S[0], a)
				continue
			if white:
				p.dot(px, py, WHITE, a)
				continue
			var k0 := py - Y0
			var u: float = RU[k0]
			var c := x + lean * u
			var l: float = RL[k0]
			var r: float = RR[k0]
			var fx := px + 0.5
			# which stratum this row sits in: facets jog sideways at each bedding plane, like stacked rock
			var band := 0
			var st := false
			for s in sp.strata:
				var d: float = u * h - s * h - sp.slope * (fx - c)
				if d > 0.0:
					band += 1
				if absf(d) < 0.5:
					st = true
			var jog := (Px.rand(band, sp.seed) - 0.5) * 0.3
			var q := ((fx - l) / maxf(0.5, r - l)) * 2.0 - 1.0
			var qr := -0.18 + jog
			var i: int
			if u > 0.93:
				i = 7 if q < qr + 0.3 else 5
			elif absf(q - qr) < maxf(0.09, 0.55 / maxf(1.0, r - l)):
				i = 7
			elif q < qr:
				i = 7 if fx - l < 1.0 else (6 if q < -0.5 + jog else 5)
			else:
				i = 3 if r - fx < 1.0 else (4 if q < 0.38 + jog else 2)
			if st and i < 7:
				i -= 1
			var fleck := Px.rand(px * 7 + 3, py * 13 + 5)
			if fleck < 0.035:
				i = 7 if q < qr else i - 1
			elif fleck > 0.965:
				i -= 1
			if glint >= 0.0 and q < qr + 0.1:
				var g := absf(u - glint)
				if g < 0.035:
					i = 8
				elif g < 0.07:
					i = maxi(i, 7)
			p.dot(px, py, WHITE if i >= 8 else S[int(Px.clamp(i, 0.0, nS - 1.0))], a)
	# cracks spreading over it, a lit lip on one side of each
	if opts.get("cracks") != null and opts.get("crack", 0.0) > 0.0:
		for path: Array in opts.cracks:
			var m := maxi(1, floori(path.size() * opts.crack))
			for k in range(1, m):
				var u0: float = path[k - 1][0]
				var v0: float = path[k - 1][1]
				var u1: float = path[k][0]
				var v1: float = path[k][1]
				var ax := x + lean * u0 + v0 * _hw(u0, -1 if v0 < 0.0 else 1, w, sp)
				var ay := base - u0 * h
				var bx := x + lean * u1 + v1 * _hw(u1, -1 if v1 < 0.0 else 1, w, sp)
				var by := base - u1 * h
				if u1 > clip:
					break
				if not _spikeIn(floori(ax), floori(ay), Y0, NR, clip, half) or not _spikeIn(floori(bx), floori(by), Y0, NR, clip, half):
					continue
				var hot: float = opts.get("heat", 0.0)
				var Gl: Variant = opts.get("glowRamp")
				if hot > 0.05 and Gl:
					# a seam of light inside the crack, a dark lip below it
					p.line(ax + 1.0, ay, bx + 1.0, by, S[0], a)
					p.line(ax, ay, bx, by, Gl[4] if hot > 0.7 else (Gl[3] if hot > 0.4 else (Gl[2] if hot > 0.2 else Gl[1])), a)
					if k % 2 == 0:
						p.glow(bx, by, 7.0, Gl[2], 0.35 * hot)
				else:
					p.line(ax, ay, bx, by, S[0], a)
					p.dot(bx + 1.0, by - 1.0, S[6], a * 0.7)


## The random look of one spike: notches on its edges, strata across it.
static func spikeLook(R: Px.Rng) -> Dictionary:
	var notches := []
	var strata := []
	var n := R.int_(3, 5)
	for i in n:
		var u := R.range(0.1, 0.8)
		var side := R.sign()
		var d := R.range(0.8, 1.8)
		notches.append({"u": u, "side": side, "d": d})
	n = R.int_(2, 4)
	for i in n:
		strata.append(R.range(0.12, 0.8))
	var slope := R.range(-0.25, 0.25)
	var seed := R.int_(1, 9999)
	return {"notches": notches, "strata": strata, "slope": slope, "seed": seed}


## A crack that branches up a spike: points [u (height 0..1), v (-1 left edge..1 right edge)].
static func spikeCrack(R: Px.Rng, u0: float, v0: float, dir: float) -> Array:
	var pts := [[u0, v0]]
	var u := u0
	var v := v0
	for i in 9:
		u += R.range(0.03, 0.08)
		v += dir * R.range(0.05, 0.28) + R.range(-0.12, 0.12)
		if u > 0.95 or absf(v) > 1.0:
			break
		pts.append([u, v])
	return pts


## A jagged floor crack from x = 0 out to side * len: points [x, y], y 0..3 into the floor.
static func floorCrack(R: Px.Rng, side: float, len: float) -> Array:
	var pts := [[0.0, 0.0]]
	var x := 0.0
	while absf(x) < len:
		x += side * R.range(2.0, 5.0)
		pts.append([x, float(R.int_(0, 2))])
	return pts


static func _leafIn(i: int, j: int, ca: float, sa: float, len: float, w: float) -> int:
	var u := (i + 0.5) * ca + (j + 0.5) * sa + len / 2.0
	var v := -(i + 0.5) * sa + (j + 0.5) * ca
	if u < 0.0 or u > len:
		return 0
	var half := w * pow(sin((PI * u) / len), 0.75)
	return (1 if v < 0.0 else 2) if absf(v) <= half else 0


## A leaf len px long and wid px across at its widest, centered on (x, y), turned by ang and flipping about its
## midrib by fl (radians: edge on at pi/2, its paler underside showing past it). A pointed blade, lit along its
## upper half and shaded along the lower, a darker midrib, a stem, a dark rim. pal: [dark, shade, body, light]
## (dark to bright). alpha dithers it out.
static func drawLeaf(p: Px.Painter, x: float, y: float, len: float, wid: float, ang: float, fl: float, pal: Array, alpha: float = 1.0) -> void:
	var ca := cos(ang)
	var sa := sin(ang)
	var sq := cos(fl)
	var w := maxf(0.55, absf(sq) * wid)
	var under := sq < 0.0
	var R := ceili(len / 2.0 + 2.0)
	var X := Px.round(x)
	var Y := Px.round(y)
	for j in range(-R, R + 1):
		for i in range(-R, R + 1):
			var s := _leafIn(i, j, ca, sa, len, w)
			if not s:
				if _leafIn(i - 1, j, ca, sa, len, w) or _leafIn(i + 1, j, ca, sa, len, w) or _leafIn(i, j - 1, ca, sa, len, w) or _leafIn(i, j + 1, ca, sa, len, w):
					p.dot(X + i, Y + j, pal[0], alpha)
				continue
			var u := (i + 0.5) * ca + (j + 0.5) * sa + len / 2.0
			var v := -(i + 0.5) * sa + (j + 0.5) * ca
			var rib := absf(v) < 0.5 and u > len * 0.12 and u < len * 0.88 and w > 1.2
			p.dot(X + i, Y + j, pal[1] if rib else (pal[3] if (s == 1) != under else pal[2]), alpha)
	# the stem trails off the base
	p.dot(X - ca * (len / 2.0 + 1.0), Y - sa * (len / 2.0 + 1.0), pal[1], alpha)


## Droplets of liquid: arc under gravity with a little drag, drawn as a bright bead with a short tail along
## their motion, and land on the floor (onLand(d, y) in update, then they're gone). add(x, y, vx, vy, s, delay).
class Drops extends RefCounted:
	var list: Array
	var ground: Callable
	var _gn: int

	func _init(ground_: Variant = null) -> void:
		list = []
		ground = ground_ if ground_ != null else func(): return 0.0
		_gn = ground.get_argument_count()

	func add(x: float, y: float, vx: float, vy: float, s: float = 1.0, delay: float = 0.0) -> void:
		list.append({"x": x, "y": y, "vx": vx, "vy": vy, "s": s, "delay": delay})

	func update(dt: float, onLand: Variant = null) -> void:
		var i := list.size() - 1
		while i >= 0:
			var d: Dictionary = list[i]
			if d.delay > 0.0:
				d.delay -= dt
				i -= 1
				continue
			var drag: float = 0.6 / d.s
			var py: float = d.y
			d.vy += GRAVITY * dt
			d.vx -= d.vx * drag * dt
			d.vy -= d.vy * drag * 0.5 * dt
			d.x += d.vx * dt
			d.y += d.vy * dt
			var g: float = ground.call(d.x) if _gn >= 1 else ground.call()
			if d.vy > 0.0 and py <= g and d.y >= g:
				if onLand != null:
					var fn: Callable = onLand
					Px.call4(fn, fn.get_argument_count(), d, g)
				list.remove_at(i)
			i -= 1

	## C: the liquid's ramp, dark to bright (5+ steps).
	func draw(p: Px.Painter, C: Array) -> void:
		var n := C.size()
		for d: Dictionary in list:
			if d.delay > 0.0:
				continue
			var sp := Px.hypot(d.vx, d.vy)
			if not sp:
				sp = 1.0
			var ux: float = d.vx / sp
			var uy: float = d.vy / sp
			var len := minf(5.0, 0.5 + sp * 0.012)
			p.line(d.x - ux * len, d.y - uy * len, d.x - ux, d.y - uy, C[n - 4])
			p.px(d.x, d.y, C[n - 1])
			if d.s > 1.0:
				p.px(d.x - ux, d.y - uy, C[n - 2])
				p.px(d.x + 1.0, d.y, C[n - 3])
			p.glow(d.x, d.y, 3.0 + d.s * 1.5, C[n - 2], 0.3)


## A puff of gas: a darker belly hanging low, a body, a denser core, a lit cap up and to the left (hi: a rim).
static func gasPuff(p: Px.Painter, x: float, y: float, r: float, a: float, belly: int, body: int, cap: int, hi: int = 0) -> void:
	if a < 0.02 or r < 0.6:
		return
	p.disc(x + r * 0.06, y + r * 0.28, r * 0.9, belly, a * 0.55)
	p.disc(x, y, r, body, a * 0.45)
	p.disc(x + r * 0.03, y - r * 0.02, r * 0.76, body, a * 0.5)
	p.disc(x - r * 0.2, y - r * 0.34, r * 0.52, cap, a * 0.45)
	if hi:
		p.disc(x - r * 0.3, y - r * 0.55, r * 0.26, hi, a * 0.32)


## A bubble of radius r centered at (x, y): a 1 px skin (lit c1 on its upper left, c2 elsewhere), a
## translucent belly, a white glint. dome: only the part above y (a bubble swelling on a surface).
static func bubble(p: Px.Painter, x: float, y: float, r: float, c1: int, c2: int, fill: int, a: float = 1.0, dome: bool = false) -> void:
	var R := ceili(r) + 1
	var X := Px.round(x)
	var Y := Px.round(y)
	for j in range(-R, (0 if dome else R) + 1):
		for i in range(-R, R + 1):
			var d := Px.hypot(i, j)
			if d > r + 0.45:
				continue
			if d > r - 0.6:
				p.dot(X + i, Y + j, c1 if (i < 0 and j < -r * 0.2) else c2, a)
			else:
				p.blend(X + i, Y + j, fill, 0.3 * a)
	if r >= 1.5:
		p.dot(X - Px.round(r * 0.45), Y - Px.round(r * 0.5), WHITE, a)


## Puffs of gas with their own clock: add(t, x, y, vx, vy, r0, r1, end, rise) launches one at time t that drifts
## off its push (fading drag), rises at `rise` px/s, sways, swells from r0 to r1 and thins out by `end`. Draw
## them with draw(p, t, belly, body, cap, hi, k): layered translucent puffs, a little light on the big ones.
class Gas extends RefCounted:
	var list: Array
	var n: int

	func _init() -> void:
		list = []
		n = 0

	func add(t: float, x: float, y: float, vx: float, vy: float, r0: float, r1: float, end: float, rise: float = 0.0) -> void:
		var seed := fmod(n * 37.7, 100.0)
		n += 1
		list.append({"x": x, "y": y, "vx": vx, "vy": vy, "r0": r0, "r1": r1, "t0": t, "end": end, "rise": rise, "seed": seed})

	func prune(t: float) -> void:
		var i := list.size() - 1
		while i >= 0:
			if t > list[i].end:
				list.remove_at(i)
			i -= 1

	func at(q: Dictionary, t: float) -> Dictionary:
		var age: float = t - q.t0
		var e := 1.0 - Px.exp(-age * 2.2)
		var sw := minf(1.0, age)
		var x: float = q.x + (q.vx / 2.2) * e + sin(t * 1.7 + q.seed) * 2.5 * sw
		var y: float = q.y + (q.vy / 2.2) * e - q.rise * age + sin(t * 1.3 + q.seed * 2.0) * 1.5 * sw
		var u := Px.clamp(age / maxf(0.01, q.end - q.t0))
		var r: float = q.r0 + (q.r1 - q.r0) * (1.0 - pow(1.0 - minf(1.0, age / 1.2), 3.0))
		return {"x": x, "y": y, "r": r, "a": Px.clamp(age / 0.15) * (1.0 - Px.clamp((u - 0.4) / 0.6)), "u": u}

	func draw(p: Px.Painter, t: float, belly: int, body: int, cap: int, hi: int = 0, k: float = 1.0, glow: int = 0) -> void:
		for q: Dictionary in list:
			var g := at(q, t)
			if g.a <= 0.02:
				continue
			Self.gasPuff(p, g.x, g.y, g.r, g.a * k, belly, body, cap, hi if g.u < 0.5 else 0)
			if glow and g.r > 4.0:
				p.glow(g.x, g.y, g.r * 1.6, glow, 0.07 * g.a * k)
