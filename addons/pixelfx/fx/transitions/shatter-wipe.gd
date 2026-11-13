# The impact flash, cracks racing out from the impact, the white flash before the burst, and the glass
# splinters, glints and cold light of the burst are adapted from Sprite Fusion's open-source ice shatter
# (https://www.spritefusion.com/pixel-art-vfx/ice), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/transitions/shatter-wipe.js@ab23b72a030c19a49243b179b18069c867d90996
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const B := Px.B
const WHITE := Px.WHITE
const W := Lib.W
const H := Lib.H

static var meta := Lib.screenMeta({
	"name": "Shatter wipe",
	"desc": "A dark glass pane drops over the screen and bounces; cracks race out from an impact with a flash, then it bursts into tumbling glass shards with lit edges that fall away.",
	"tags": ["shatter", "glass", "break", "shards", "wipe"],
	"duration": 2.8,
	"options": {"palette": ["#0c1430", "#162c5c", "#1f4f94", "#2f7fcc", "#58b4ec", "#9bdcff", "#d8f4ff", "#ffffff"], "seed": 2},
})

static var D: float = meta.duration
const LAND := 0.55
const GP := (2.0 * H) / (LAND * LAND)
const REST := 0.3
const CRACK := 1.32
const BREAK := 1.62
const WAVE := 520.0
const LX := -0.6  # light comes from the top left
const LY := -0.8
const L3 := [-0.42, -0.56, 0.71]  # and a little from the front, for the faces
const RING := [0.0, 9.0, 21.0, 37.0, 58.0, 86.0, 122.0, 168.0, 232.0]


# the pane's top edge over time: it falls from above the screen, lands, bounces twice and settles
static var BOUNCES := _bounces()


static func _bounces() -> Array:
	var out := []
	var t0 := LAND
	var v := GP * LAND * REST
	for k in 3:
		out.append({"t0": t0, "v": v, "T": (2.0 * v) / GP})
		t0 += (2.0 * v) / GP
		v *= REST
	return out


static func paneY(t: float) -> float:
	if t < LAND:
		return -H + 0.5 * GP * t * t
	for b: Dictionary in BOUNCES:
		if t < b.t0 + b.T:
			return -(b.v * (t - b.t0) - 0.5 * GP * (t - b.t0) ** 2)
	return 0.0


static func _jag(R: Px.Rng, A: Array, Bp: Array) -> Array:
	var dx: float = Bp[0] - A[0]
	var dy: float = Bp[1] - A[1]
	var L := Px.hypot(dx, dy)
	if not L:
		L = 1.0
	var n := 2 if L > 18.0 else 1
	var out := [A]
	for k in range(1, n + 1):
		var f := k / float(n + 1) + R.range(-0.08, 0.08)
		var off := R.range(-1, 1) * minf(3.0, L * 0.07)
		out.append([A[0] + dx * f - (dy / L) * off, A[1] + dy * f + (dx / L) * off])
	out.append(Bp)
	return out


static func _reach(Ix: float, Iy: float, speed: Array, i: int, x: float, y: float) -> float:
	return CRACK + Px.hypot(x - Ix, y - Iy) / speed[i]


static func _trace(cracks: Array, pts: Array, when: Callable) -> void:
	for k in range(1, pts.size()):
		var ax: float = pts[k - 1][0]
		var ay: float = pts[k - 1][1]
		var bx: float = pts[k][0]
		var by: float = pts[k][1]
		var n := ceilf(Px.hypot(bx - ax, by - ay) * 2.0)
		var s := 0.0
		while s < n:
			var x := ax + ((bx - ax) * s) / n
			var y := ay + ((by - ay) * s) / n
			if x >= 0.0 and y >= 0.0 and x < W and y < H:
				cracks.append({"x": floorf(x), "y": floorf(y), "t0": when.call(x, y)})
			s += 1.0


# the break: jagged rays out of the impact crossed by rings, every crack shared by the two cells it splits
static func pattern(R: Px.Rng) -> Dictionary:
	var Ix := W * R.range(0.4, 0.6)
	var Iy := H * R.range(0.36, 0.54)
	var NR := 13
	var ang := Px.arr(NR, func(i): return ((i + R.range(-0.3, 0.3)) / NR) * TAU)
	var speed := ang.map(func(_a): return R.range(800, 1300))
	var V := []
	for a in ang:
		var row := []
		for j in RING.size():
			if not j:
				row.append([Ix, Iy])
				continue
			var rr: float = RING[j] * R.range(0.84, 1.16)
			var aa: float = a + R.range(-0.07, 0.07)
			row.append([Ix + cos(aa) * rr, Iy + sin(aa) * rr])
		V.append(row)
	var rad := []
	for v: Array in V:
		var es := []
		for j in v.size() - 1:
			es.append(_jag(R, v[j], v[j + 1]))
		rad.append(es)
	var ring := []
	for i in V.size():
		var es := []
		for j in V[i].size():
			es.append(_jag(R, V[i][j], V[(i + 1) % NR][j]) if j else null)
		ring.append(es)
	# real glass breaks into long wedges: rings near the impact are whole, further out they're broken arcs
	var keep := []
	for v in V:
		var ks := []
		for j in RING.size():
			ks.append(j <= 2 or j == RING.size() - 1 or R.chance(0.78 - 0.07 * j))
		keep.append(ks)
	# when a crack gets to each pixel: rays race out at their own speed, rings snap across once both rays pass
	var cracks := []
	for i in NR:
		for e: Array in rad[i]:
			_trace(cracks, e, func(x, y): return _reach(Ix, Iy, speed, i, x, y))
	for i in NR:
		for j in range(1, RING.size() - 1):
			if not keep[i][j]:
				continue
			var i2 := (i + 1) % NR
			var e: Array = ring[i][j]
			var start := maxf(_reach(Ix, Iy, speed, i, V[i][j][0], V[i][j][1]), _reach(Ix, Iy, speed, i2, V[i2][j][0], V[i2][j][1])) + R.range(0.02, 0.07)
			var ax: float = e[0][0]
			var ay: float = e[0][1]
			_trace(cracks, e, func(x, y): return start + Px.hypot(x - ax, y - ay) / 420.0)
	Px.sort(cracks, func(a, b): return a.t0 - b.t0)
	var cells := []
	for i in NR:
		var j := 0
		while j < RING.size() - 1:
			# a wedge from ring j out to the next ring crack that's there
			var jb := j
			while not keep[i][jb + 1]:
				jb += 1
			var j0 := j
			j = jb + 1
			var i2 := (i + 1) % NR
			var side := func(r: int) -> Array:
				var o := []
				var es: Array = rad[r].slice(j0, jb + 1)
				for k in es.size():
					o.append_array(es[k].slice(1) if k else es[k])
				return o
			var pts: Array = side.call(i)
			pts.append_array(ring[i][jb + 1].slice(1))
			var s2: Array = side.call(i2)
			s2.reverse()
			pts.append_array(s2.slice(1))
			if j0:
				var rv: Array = ring[i][j0].duplicate()
				rv.reverse()
				pts.append_array(rv.slice(1, rv.size() - 1))
			else:
				pts.pop_back()
			var x0 := INF
			var y0 := INF
			var x1 := -INF
			var y1 := -INF
			var cx := 0.0
			var cy := 0.0
			for q in pts:
				x0 = minf(x0, q[0])
				x1 = maxf(x1, q[0])
				y0 = minf(y0, q[1])
				y1 = maxf(y1, q[1])
				cx += q[0]
				cy += q[1]
			if x1 < 0.0 or y1 < 0.0 or x0 >= W or y0 >= H:
				continue
			# a shard of what's on screen: centered on the visible part, so it spins about what you see
			cx = (Px.clamp(x0, 0.0, W) + Px.clamp(x1, 0.0, W)) / 2.0
			cy = (Px.clamp(y0, 0.0, H) + Px.clamp(y1, 0.0, H)) / 2.0
			var d := Px.hypot(cx - Ix, cy - Iy)
			var lp := []
			for q in pts:
				lp.append([q[0] - cx, q[1] - cy])
			cells.append({"pts": pts, "lp": lp, "cx": cx, "cy": cy, "d": d, "r": Px.hypot(x1 - x0, y1 - y0) / 2.0, "tb": BREAK + d / WAVE + R.range(0, 0.04), "broke": false, "gone": false})
	return {"Ix": Ix, "Iy": Iy, "cracks": cracks, "cells": cells}


var C: Array
var ink: int
var R: Px.Rng
var pat: Dictionary
var Ix: float
var Iy: float
var ps: Px.Particles
var bits: Px.Bits
var lights: Px.Lights
var t := 0.0
var bounce := -1
var struck := false
var burst := false
var end: float


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	ink = Px.hex(o.color)
	R = Px.Rng.new(o.seed)
	pat = pattern(R)
	Ix = pat.Ix
	Iy = pat.Iy
	ps = Px.Particles.new({"rng": R, "sparks": [C[7], C[6], C[5], C[4]], "haze": C[5]})
	bits = Px.Bits.new()
	lights = Px.Lights.new()
	t = 0.0
	bounce = -1
	struck = false
	burst = false
	end = D - 0.05


# glass splinters thrown from (x, y): little white-tipped streaks that tumble and fall
func splinters(x: float, y: float, n: int, vx: float, vy: float, spread: float, sp0: float, sp1: float) -> void:
	for i in n:
		var a := atan2(vy, vx) + R.range(-spread, spread)
		var sp := R.range(sp0, sp1)
		var life := minf(R.range(0.6, 1.2), end - t)
		if life > 0.2:
			bits.add({"kind": B.SHARD, "x": x, "y": y, "vx": cos(a) * sp, "vy": sin(a) * sp, "g": 0.8, "drag": 0.6, "life": life, "a": R.range(0, TAU), "va": R.range(-20, 20), "s": R.range(1.5, 3.5), "c": R.pick([C[7], C[6], C[5]])})


func glint(x: float, y: float, s: Variant = null) -> void:
	if s == null:
		s = R.range(1, 2.4)
	ps.spawn(P.STAR, x, y, R.range(-8, 8), R.range(-10, 4), minf(R.range(0.3, 0.6), end - t), WHITE if R.chance(0.5) else C[6], s)


func update(dt: float) -> void:
	t += dt
	# each landing: chips spring off the bottom edge, glints, a cold flash along it
	while bounce + 1 < BOUNCES.size() and t >= BOUNCES[bounce + 1].t0:
		bounce += 1
		var k: float = BOUNCES[bounce].v / BOUNCES[0].v
		if k < 0.05:
			continue
		for i in 5:
			lights.add(W * (i + 0.5) / 5.0, H - 2, 70, C[5], 0.5 * k, 0.35)
		for i in int(Px.round(26.0 * k)):
			splinters(R.range(4, W - 4), H - 1, 1, R.range(-0.4, 0.4), -1, 0.5, 120.0 * k, 330.0 * k)
		for i in int(Px.round(9.0 * k)):
			glint(R.range(8, W - 8), H - R.range(2, 10))
	if not struck and t >= CRACK:
		# the blow: a white flash at the point of impact, a puff of splinters back off the glass
		struck = true
		lights.add(Ix, Iy, 90, C[5], 0.8, 0.35)
		lights.add(Ix, Iy, 34, WHITE, 0.9, 0.1)
		splinters(Ix, Iy, 16, 0, -1, PI, 60, 240)
		for i in 5:
			ps.spawn(P.VAPOUR, Ix, Iy, R.range(-40, 40), R.range(-40, 30), R.range(0.35, 0.6), C[6], R.range(2, 3.5))
	# while the cracks run, glints chase their tips
	if t > CRACK and t < BREAK and R.chance(0.12):
		var c: Dictionary = pat.cracks[R.int_(0, pat.cracks.size() - 1)]
		if c.t0 < t:
			glint(c.x, c.y, R.range(0.6, 1.6))
	if not burst and t >= BREAK:
		# the burst: a cold flash, a spray of splinters and a breath of glass dust out of the impact
		burst = true
		lights.add(Ix, Iy, 170, C[4], 0.55, 0.5)
		lights.add(Ix, Iy, 60, WHITE, 0.8, 0.14)
		splinters(Ix, Iy, 46, 0, -1, PI, 90, 340)
		for i in 14:
			var a := R.range(0, TAU)
			var sp := R.range(30, 110)
			ps.spawn(P.VAPOUR, Ix + cos(a) * 4.0, Iy + sin(a) * 4.0, cos(a) * sp, sin(a) * sp, R.range(0.45, 0.8), C[6] if R.chance(0.6) else C[5], R.range(3, 6))
	# the pane bursts outward from the impact: each shard flies off, tumbling, and falls away from the screen
	for s: Dictionary in pat.cells:
		if not s.broke and t >= s.tb:
			s.broke = true
			var dx: float = s.cx - Ix
			var dy: float = s.cy - Iy
			var d := Px.hypot(dx, dy)
			if not d:
				d = 1.0
			var sp: float = R.range(40, 130) * (1.15 - minf(1.0, s.d / 260.0))
			s.vx = (dx / d) * sp + R.range(-15, 15)
			s.vy = (dy / d) * sp * 0.6 - R.range(20, 90)
			s.a = 0.0
			s.va = R.range(-2.5, 2.5) * (1.0 + 20.0 / (s.r + 10.0))
			s.phi = 0.0
			s.vphi = R.sign() * R.range(3, 9)
			s.psi = R.range(0, TAU)
			s.z = 0.0
			s.vz = R.range(0.25, 0.7)
			s.g = R.range(0.85, 1.1)
			s.edgeOn = false
			splinters(s.cx, s.cy, 4 if s.r > 24.0 else 2, s.vx, s.vy, 1.2, 60, 220)
			if R.chance(0.15):
				glint(s.cx + R.range(-4, 4), s.cy + R.range(-4, 4))
		if not s.broke or s.gone:
			continue
		s.vy += 950.0 * s.g * dt
		s.vx -= s.vx * 0.3 * dt
		s.cx += s.vx * dt
		s.cy += s.vy * dt
		s.a += s.va * dt
		s.phi += s.vphi * dt
		s.z += s.vz * dt
		# turning edge-on to us it flashes: a glint where the light catches the glass
		var on := absf(cos(s.phi)) < 0.2
		if on and not s.edgeOn and t < end - 0.3:
			glint(s.cx, s.cy, R.range(1.4, 2.6))
		s.edgeOn = on
		if s.cy - s.r / (1.0 + s.z) > H + 2.0:
			s.gone = true
	ps.update(dt)
	bits.update(dt)
	lights.update(dt)


func draw(p0: Px.Painter) -> void:
	var p := Lib.clipTo(p0)
	if t < BREAK:
		# the pane: dark glass, a lit bevel along its falling edge, faint reflections that fade once it settles
		var yb := paneY(t) + H
		var r1 := minf(H, floorf(yb))
		if r1 > 0.0:
			Lib.rect(p0, 0.0, 0.0, W, r1, ink)
			var shine := 1.0 - Px.smooth(0.98, 1.22, t)
			var y0 := yb - H
			if shine > 0.0:
				for oa: Array in [[0.0, 16.0, 0.05], [22.0, 3.0, 0.1], [30.0, 1.0, 0.12]]:
					var off: float = oa[0]
					var w: float = oa[1]
					var a: float = oa[2]
					for y in int(r1):
						var xc := W * 0.18 + off + (H - (y - y0)) * 0.7
						for x in range(int(maxf(0.0, floorf(xc - w / 2.0))), int(minf(W, ceilf(xc + w / 2.0)))):
							p0.blend(x + 0.5, y + 0.5, C[6], a * shine)
				var st := 0 if shine > 0.66 else (1 if shine > 0.33 else 2)
				for dc: Array in [[1.0, C[6 - st * 2]], [2.0, C[4 - st]], [3.0, C[maxi(1, 2 - st)]]]:
					var dy: float = dc[0]
					if r1 - dy >= 0.0 and r1 - dy < H:
						Lib.rect(p0, 0.0, r1 - dy, W, 1.0, dc[1])
				# light runs along the edge as it falls, and spills onto the picture below it
				var gx := W * Px.clamp(t / (LAND + 0.25)) * 1.2 - 20.0
				for x in W:
					var k := maxf(0.0, 1.0 - absf(x - gx) / 28.0)
					if k > 0.0 and r1 - 1.0 < H:
						p0.px(x, r1 - 1.0, WHITE if k > 0.5 else C[6])
						p0.light(x, r1 - 1.0, C[6], 0.5 * k)
					var d := 0
					while d < 14 and r1 + d < H:
						p0.light(x, r1 + d, C[5], 0.3 * shine * (1.0 - d / 14.0) ** 2 * (0.6 + 0.8 * k))
						d += 1
				if t < LAND + 0.25 and gx > 0.0 and gx < W and r1 - 1.0 < H:
					Px.sparkle(p, gx, r1 - 1.0, 6.0, C[6], C[4], 0.5)
		# the cracks race out from the impact: white at the tip, cooling to ice, each with its shadow
		if t >= CRACK:
			for c: Dictionary in pat.cracks:
				if c.t0 > t:
					break
				var age: float = t - c.t0
				if c.x + 1.0 < W and c.y + 1.0 < H:
					p0.px(c.x + 1.0, c.y + 1.0, C[1])
				p0.px(c.x, c.y, WHITE if age < 0.04 else (C[6] if age < 0.18 else C[5]))
				if age < 0.3:
					p0.light(c.x, c.y, C[5], 0.55 * (1.0 - age / 0.3))
			var u := (t - CRACK) / 0.22
			if u < 1.0:
				Px.flare(p, Ix, Iy, 30.0 * pow(1.0 - u, 1.5), 1.0 - u, C)
				p.glow(Ix, Iy, 50.0, WHITE, 0.7 * (1.0 - u))
			# a beat before the burst, the cracks flare white
			var w := (t - (BREAK - 0.07)) / 0.07
			if w > 0.0:
				for c: Dictionary in pat.cracks:
					p0.px(c.x, c.y, WHITE)
					p0.light(c.x, c.y, C[6], 0.4 * w)
	else:
		# shards still in place first (the pane breaking up outward), then the falling ones, nearest last
		var fall: Array = Px.sort(pat.cells.filter(func(s): return s.broke and not s.gone), func(a, b): return b.z - a.z)
		for s: Dictionary in pat.cells:
			if not s.broke:
				drawShard(p, p0, s, C, ink, true)
		for s: Dictionary in fall:
			drawShard(p, p0, s, C, ink, false)
	bits.draw(p)
	ps.draw(p)
	lights.draw(p)


# a shard: dark glass that tumbles about an axis in its plane (squashing as it turns, a bright sliver
# edge-on), its edges lit where they face the light, its face catching a cool sheen as it turns to it
static func drawShard(p: Px.Painter, p0: Px.Painter, s: Dictionary, C: Array, ink: int, still: bool) -> void:
	var pts: Array
	var face := ink
	var sliver := false
	var gl := 0.0
	if still:
		pts = s.pts
	else:
		var cp := cos(s.phi)
		var sp := sin(s.phi)
		var ci := cos(s.psi)
		var si := sin(s.psi)
		var ca := cos(s.a)
		var sa := sin(s.a)
		var k: float = 1.0 / (1.0 + s.z)
		var cx: float = s.cx
		var cy: float = s.cy
		pts = []
		for q: Array in s.lp:
			var x: float = q[0]
			var y: float = q[1]
			var u := x * ci + y * si
			var v := (-x * si + y * ci) * cp
			var qx := u * ci - v * si
			var qy := u * si + v * ci
			pts.append([cx + (qx * ca - qy * sa) * k, cy + (qx * sa + qy * ca) * k])
		# the face's normal, turned by the tumble and the spin, against the light
		var nx0 := si * sp
		var ny0 := -ci * sp
		var nz := cp
		var nx := nx0 * ca - ny0 * sa
		var ny := nx0 * sa + ny0 * ca
		var d := absf(nx * L3[0] + ny * L3[1] + nz * L3[2])
		gl = pow(d, 6.0)
		# turning toward edge-on the glass reflects more (a grazing sheen), and a hairline sliver goes bright
		var graze := Px.clamp(1.0 - absf(cp) / 0.3) ** 2
		face = Px.mix(Px.mix(ink, C[2], 0.12 + 0.4 * gl), C[3], 0.55 * graze)
		sliver = absf(cp) < 0.2
		if absf(cp) * s.r < 1.5:
			face = C[5]
	Lib.fillConvex(p0, pts, face)
	var a2 := 0.0
	var j := pts.size() - 1
	for i in pts.size():
		a2 += pts[j][0] * pts[i][1] - pts[i][0] * pts[j][1]
		j = i
	var sg := 1.0 if a2 > 0.0 else -1.0
	j = pts.size() - 1
	for i in pts.size():
		var ax: float = pts[j][0]
		var ay: float = pts[j][1]
		var bx: float = pts[i][0]
		var by: float = pts[i][1]
		j = i
		var dx := bx - ax
		var dy := by - ay
		var L := Px.hypot(dx, dy)
		if L < 0.5:
			continue
		var mx := (dy / L) * sg
		var my := (-dx / L) * sg
		var el := mx * LX + my * LY
		if still:
			# a crack in the pane: lit fracture line, its shadow below
			p.line(ax, ay, bx, by, C[5] if el > 0.0 else C[4])
			continue
		if el > 0.2 or sliver:
			p.line(ax - mx, ay - my, bx - mx, by - my, C[4])
			p.line(ax, ay, bx, by, WHITE if gl > 0.5 or sliver else C[6])
			p.glow((ax + bx) / 2.0, (ay + by) / 2.0, minf(12.0, 4.0 + L * 0.3), C[5], 0.12 + 0.3 * gl)
		else:
			p.line(ax, ay, bx, by, C[4] if el > -0.3 else C[2])
