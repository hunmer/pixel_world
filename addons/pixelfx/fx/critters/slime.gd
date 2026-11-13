# The puddle (a domed wet surface with glints sliding along it, bubbles that swell and pop) is adapted from
# Sprite Fusion's open-source poison puddle (https://www.spritefusion.com/pixel-art-vfx/poison),
# MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/critters/slime.js@a1a6d37a2f7da3b6d7a29b4f08aedc67198458b8
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")

static var meta := {
	"name": "Slime",
	"desc": "A glossy slime hops in place: it squashes to wind up, stretches into the jump, rounds out in the air, splats down flinging droplets that creep back, then wobbles and blinks.",
	"tags": ["critter", "slime", "monster", "hop", "goo", "loop"],
	"size": [112, 88],
	"origin": [56, 72],
	"duration": 1.8,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": ["#061412", "#0b2f2b", "#12594a", "#1f8f4f", "#47c752", "#a6f06a", "#f0ffd2"], "hop": 24, "seed": 1},
}

static var GRID := Lib.Grid.new(-30, -64, 60, 66)
static var D: float = meta.duration
const T_SQ := 0.5
const T_UP := 0.84
const T_LIFT := 0.9
const T_LAND := 1.44
const SNAP := 0.965
const W0 := 30.0
const H0 := 22.0
const VC := 0.4
const G := 640.0
const NDROP := 12


# the body's shape and squash at loop time t: s > 0 stretched tall, s < 0 squashed flat
static func pose(t: float, hop: float) -> Dictionary:
	var age := Px.wrap(t - T_LAND, D)
	var s := 0.0
	var by := 0.0
	var lean := 0.0
	var round_ := 0.1
	var q := -1.0
	if t >= T_LIFT and t < T_LAND:
		q = (t - T_LIFT) / (T_LAND - T_LIFT)
		by = -hop * 4.0 * q * (1.0 - q)
		s = Lib.curve(q, [[0.0, 0.36], [0.4, 0.02], [0.55, -0.05], [0.85, 0.08], [1.0, 0.16]])
		round_ = 0.1 + 0.8 * Px.smooth(0.0, 0.16, q) * (1.0 - Px.smooth(0.86, 1.0, q))
	elif t >= T_UP and t < T_LIFT:
		s = Px.lerp(-0.3, 0.36, Px.Ease.outCubic(Px.seg(t, T_UP, T_LIFT)))
	elif t >= T_SQ and t < T_UP:
		var u := Px.seg(t, T_SQ, T_UP)
		s = -0.3 * Px.Ease.inOutSine(u) + 0.018 * sin(t * TAU * 16.0) * Px.smooth(0.55, 1.0, u)
	else:
		# the splat holds for a beat, then rings out into a wobble; the top sways a little as it settles
		s = -0.46 if age < 0.06 else -0.46 * Lib.spring(age - 0.06, 2.1, 4.6)
		lean = 0.07 * exp(-age * 4.0) * sin(age * TAU * 1.9)
		if t < T_SQ:
			s += 0.02 * sin((t / T_SQ) * TAU)
	return {"s": s, "by": by, "lean": lean, "round": round_, "q": q, "age": age, "W": W0 / sqrt(1.0 + s), "H": H0 * (1.0 + s)}


# half the body's width at height v (0 base .. 1 top): a dome over a soft foot with rounded corners
static func halfW(v: float, P: Dictionary) -> float:
	if v < 0.0 or v > 1.0:
		return -1.0
	var W: float = P.W
	var H: float = P.H
	var round_: float = P.round
	if v >= VC:
		var q := (v - VC) / (1.0 - VC)
		return (W / 2.0) * sqrt(1.0 - q * q)
	var q := (VC - v) / VC
	var hb := v * H
	var rc := 3.0
	var hw := (W / 2.0) * sqrt(maxf(0.0, 1.0 - round_ * q * q))
	if hb < rc:
		hw -= rc - sqrt(rc * rc - (rc - hb) ** 2)
	return hw


static func inside(P: Dictionary, x: float, y: float) -> bool:
	var v: float = (P.by - 1.0 - y) / P.H
	var hw := halfW(v, P)
	return hw >= 0.0 and absf(x - P.lean * v * P.H) <= hw


# shaded the way a pixel artist shades jelly: a dark dome over light pooling low inside the body, a shadow
# crescent (the rim the body leaves bare when nudged toward the light), a glossy streak hugging the top-left
# contour with a hot spot under it, light bounced up off the floor caught just inside the lower rim
static func body(g: Lib.Grid, C: Array, P: Dictionary) -> void:
	var yb: float = P.by - 1.0
	var half: float = P.W / 2.0 + 3.0
	var cx: float = P.lean * 0.45 * P.H
	var cy: float = yb - P.H * 0.5
	var lx: float = cx - P.W * 0.24
	var ly: float = cy - P.H * 0.36
	var lit := func(x: float, y: float, k: float) -> bool: return inside(P, lx + (x - lx) / k, ly + (y - ly) / k)
	g.clear()
	g.shade(-half, yb - P.H - 1.0, half, yb, func(x, y, o):
		if not inside(P, x, y):
			return 0
		o.t = 1
		o.a = 0.92
		var i := 5 if lit.call(x, y, 0.42) else (4 if lit.call(x, y, 0.7) else 3)
		# light pooled in the jelly along the bottom, brightest just inside the rim
		var v: float = (yb - y) / P.H
		if v < 0.3 and inside(P, x, y + 1.4):
			i = 5 if not inside(P, x, y + 2.4) else (4 if v < 0.2 else i)
		if not inside(P, x + 2.0, y + 2.4):
			i = 2
			o.a = 1.0
		var ang := atan2(y - cy, (x - cx) * (P.H / P.W))
		if not inside(P, x - 1.6, y - 1.6) and inside(P, x - 0.7, y - 0.7) and ang > -2.75 and ang < -1.55:
			i = 6 if (ang > -2.45 and ang < -1.8) else 5
			o.a = 1.0
		if i == 2 and inside(P, x + 1.0, y + 1.2) and not inside(P, x + 2.0, y + 2.4) and ang > 0.3 and ang < 1.5:
			i = 4
		return C[i])
	# the hot spot: a tiny bright window reflection under the streak
	var hx := Px.round(cx - P.W * 0.27)
	var hy := Px.round(cy - P.H * 0.14)
	if inside(P, hx - 1.0, hy) and inside(P, hx + 1.0, hy + 1.0):
		g.setc(hx, hy, C[6])
		g.setc(hx, hy + 1.0, C[5])


# the eyes ride the squash: squint while winding up, wide in the air, screwed shut on the splat, a blink at rest
static func face(g: Lib.Grid, C: Array, P: Dictionary, t: float) -> void:
	var yb: float = P.by - 1.0
	var ev := 0.47
	var ey := Px.round(yb - P.H * ev)
	var ex := maxf(3.0, Px.round(P.W * 0.16))
	var xc := Px.round(P.lean * ev * P.H)
	var air: bool = P.q >= 0.0
	var shut: bool = P.age < 0.16 and not air
	var blink := t > 0.22 and t < 0.29
	var wind := Px.seg(t, T_SQ, T_UP) if (t >= T_SQ and t < T_LIFT) else 0.0
	var look := ((-1.0 if P.q < 0.45 else (1.0 if P.q > 0.7 else 0.0))) if air else 0.0
	var eh := Px.clamp(Px.round(4.0 * (1.0 + P.s * 0.8) - wind * 2.0 + (1.0 if (air and P.q < 0.6) else 0.0)), 1.0, 5.0)
	for side in [-1.0, 1.0]:
		var x: float = xc + side * ex - (1.0 if side > 0.0 else 0.0)
		if shut:
			var a := 0.0 if side < 0.0 else 1.0
			var b := 1.0 - a
			g.setc(x + a, ey - 1.0, C[0])
			g.setc(x + b, ey, C[0])
			g.setc(x + a, ey + 1.0, C[0])
			continue
		if blink:
			g.setc(x, ey + 1.0, C[0])
			g.setc(x + 1.0, ey + 1.0, C[0])
			continue
		var top := ey + 2.0 - eh + look
		var k := 0.0
		while k < eh:
			g.setc(x, top + k, C[0])
			g.setc(x + 1.0, top + k, C[0])
			k += 1.0
		g.setc(x + (1.0 if look > 0.0 else 0.0), top + (1.0 if look > 0.0 else 0.0), C[6])
		if eh >= 4.0:
			g.setc(x + 1.0, top + eh - 1.0, C[2])
	var my := Px.round(yb - P.H * 0.31)
	if air and P.q < 0.75:
		g.setc(xc, my, C[0])
		g.setc(xc - 1.0, my, C[0])
		g.setc(xc, my + 1.0, C[1])
		g.setc(xc - 1.0, my + 1.0, C[1])
	elif not shut:
		g.setc(xc, my, C[1])
		g.setc(xc - 1.0, my, C[1])


# a bubble works its way up through the jelly while it rests and pops at the top
const POP := 0.4


static func bubbleIn(g: Lib.Grid, C: Array, P: Dictionary, t: float) -> void:
	if t > POP:
		return
	var v := Px.lerp(0.18, 0.86, Px.Ease.inQuad(t / POP))
	var hw := halfW(v, P)
	var x: float = P.lean * v * P.H - hw * Px.lerp(0.35, 0.05, t / POP)
	var y: float = P.by - 1.0 - v * P.H
	g.setc(x, y, C[6])
	g.setc(x + 1.0, y, C[5])
	g.setc(x, y + 1.0, C[5])
	g.setc(x + 1.0, y + 1.0, C[4])


# droplets flung off the splat: they arc, land with a little splat, and creep back to the body to rejoin it
static func droplet(i: int, o: Dictionary, age: float) -> Dictionary:
	var r := Px.rng(o.seed, i, 7)
	var a := -PI / 2.0 + r.range(-1.2, 1.2)
	var sp := r.range(60.0, 118.0)
	var size := 1 if r.chance(0.35) else (2 if r.chance(0.7) else 3)
	var fa := a + PI / 2.0
	var x0 := sin(fa) * 21.0
	var y0 := -1.0 - cos(fa) * 12.5
	var f := Lib.toss(x0, y0, cos(a) * sp * 0.75, sin(a) * sp, age, G, -1.0)
	f.size = size
	if f.landed:
		var home: float = Px.sign(f.lx if f.lx else 1.0) * (W0 / 2.0 - 2.0)
		var dur := minf(0.55, 0.22 + absf(f.lx - home) / 60.0)
		var u := Px.seg(age - f.at - 0.14, 0.0, dur)
		f.x = Px.lerp(f.lx, home, Px.Ease.inOutSine(u))
		f.k = 1.0 - u
		f.gone = u >= 1.0
		f.splat = Px.clamp(1.0 - (age - f.at) / 0.14)
	return f


# the wet patch it sits in: wider while squashed, splashed out on landing, left behind while it jumps
static func puddleR(t: float, P: Dictionary) -> float:
	if P.q >= 0.0:
		return (W0 / sqrt(1.36) / 2.0 + 3.0) * (1.0 - 0.22 * P.q)
	return P.W / 2.0 + 3.0 + 9.0 * exp(-P.age * 5.0) * (1.0 - exp(-P.age * 40.0)) * (1.0 if (t >= T_LAND or t < T_SQ) else 0.0)


static func draw(p: Px.Painter, time: float, o: Dictionary) -> void:
	var t := Lib.shift(time, D, o.seed)
	var C := Px.fit(o.palette, 7)
	var P := pose(t, o.hop)
	var yb: float = P.by - 1.0
	var age: float = P.age
	var g := GRID
	body(g, C, P)
	face(g, C, P, t)
	bubbleIn(g, C, P, t)
	g.outline(func(x, y, nx, ny): return C[1] if (ny < 0.0 and nx <= 0.0 and y < yb - P.H * 0.5) else C[0])
	g.draw(p)

	# the bubble pops out of the top: a ring and two flecks
	if t >= POP and t < POP + 0.16:
		var k := (t - POP) / 0.16
		var x: float = P.lean * P.H - halfW(0.86, P) * 0.05
		var y: float = yb - P.H - 0.5
		var a := 0.0
		while a < TAU:
			p.dot(x + cos(a) * (1.0 + k * 3.0), y + sin(a) * (1.0 + k * 3.0) * 0.7, C[6], 1.2 - k)
			a += 0.6
		for s in [-1.0, 1.0]:
			p.dot(x + s * (1.0 + k * 4.0), y - 1.0 - k * 6.0 + k * k * 4.0, C[5], 1.3 - k)
		p.glow(x, y, 6.0, C[5], 0.4 * (1.0 - k))
	# droplets in flight
	for i in NDROP:
		var f := droplet(i, o, age)
		if f.landed or inside(P, f.x, f.y):
			continue
		var sv := Px.hypot(f.vx, f.vy)
		if not sv:
			sv = 1.0
		var ux: float = f.vx / sv
		var uy: float = f.vy / sv
		var L := minf(2.5, sv / 50.0)
		p.line(f.x - ux * L, f.y - uy * L, f.x, f.y, C[3])
		if f.size >= 2:
			p.px(f.x - 1.0, f.y, C[4])
			p.px(f.x - 1.0, f.y + 1.0, C[3])
			p.px(f.x, f.y + 1.0, C[2])
		if f.size >= 3:
			p.px(f.x + 1.0, f.y, C[3])
			p.px(f.x - 1.0, f.y - 1.0, C[4])
			p.px(f.x, f.y - 1.0, C[5])
		p.px(f.x, f.y, C[6] if f.size >= 2 else C[5])
		p.glow(f.x, f.y, 5.0 + f.size, C[4], 0.32)
	# spores drifting up out of the puddle, glowing
	Px.cycle(t, D, 7, o.seed * 13 + 1, func(r): return r.range(1.2, 1.8), func(ag, L, r, i):
		var k: float = ag / L
		var x: float = r.range(-24.0, 24.0) + sin(ag * 2.1 + i * 1.7) * 3.0
		var y: float = -2.0 - r.range(9.0, 17.0) * ag - 5.0 * ag * ag
		var a := minf(1.0, k * 4.0) * minf(1.0, (1.0 - k) * 2.5)
		var tw: float = 0.6 + 0.4 * sin(ag * 7.0 + i * 2.3)
		var big: bool = r.chance(0.35)
		p.dot(x, y, C[6] if tw > 0.8 else C[5], a)
		if big:
			p.dot(x + 1.0, y, C[5], a)
			p.dot(x, y + 1.0, C[4], a)
			p.dot(x + 1.0, y + 1.0, C[4], a * 0.6)
		p.glow(x, y, 9.0 if big else 6.0, C[5], (0.45 if big else 0.32) * a * tw))
	# drips let go of its underside while it's in the air and plop into the puddle
	for q in DRIPS:
		var t0: float = q[0]
		var dx: float = q[1]
		var a2 := Px.wrap(t - t0, D)
		if a2 > 0.6:
			continue
		var P0 := pose(t0, o.hop)
		var f := Lib.toss(dx, P0.by - 0.5, 0.0, 12.0, a2, G, -1.0)
		if not f.landed:
			p.px(dx, f.y, C[5])
			p.px(dx, f.y - 1.0, C[4])
			p.glow(dx, f.y, 4.0, C[4], 0.3)
		elif a2 - f.at < 0.14:
			var k: float = (a2 - f.at) / 0.14
			for s2 in [-1.0, 1.0]:
				p.dot(dx + s2 * (1.0 + k * 3.0), -2.0 - k * 3.0 + k * k * 3.0, C[5], 1.2 - k)
	# a glint on the dome at the top of the hop
	if P.q > 0.4 and P.q < 0.64:
		var k := sin(PI * Px.seg(P.q, 0.4, 0.64))
		Px.sparkle(p, P.lean * 0.8 * P.H - P.W * 0.21, yb - P.H * 0.8, 1.0 + 2.5 * k, C[6], C[5], 0.5 * k)
	# light: the slime glows through and tints the air round it, the puddle lights the floor, a flash on the splat
	var cx: float = P.lean * P.H * 0.4
	var cy: float = yb - P.H * 0.45
	var near := Px.clamp(1.0 + P.by / (o.hop * 1.1))
	var R := puddleR(t, P)
	var br := 0.9 + 0.1 * sin((t / D) * TAU * 2.0)
	p.glow(cx * 0.5, -14.0, 64.0, C[3], 0.3 * br)
	p.glow(cx, cy, 30.0 + P.W * 0.3, C[4], 0.2)
	p.glow(cx, cy + 3.0, 14.0, C[5], 0.16)
	p.glow(0.0, -2.0, R * 1.3 + 6.0, C[4], 0.12 + 0.08 * near)
	if t >= T_LAND or t < T_SQ:
		p.glow(0.0, -3.0, 40.0, C[5], 0.42 * exp(-age * 9.0))


const DRIPS := [[1.02, -4.0], [1.18, 3.0]]


static func drawBack(p: Px.Painter, time: float, o: Dictionary) -> void:
	var t := Lib.shift(time, D, o.seed)
	var C := Px.fit(o.palette, 7)
	var P := pose(t, o.hop)
	var age: float = P.age
	# the puddle: a low dome of goo, lit along its top with glints sliding over it, darker where it meets the floor
	var R := puddleR(t, P)
	var hp := minf(2.4, 0.9 + R * 0.06)
	var x := floorf(-R)
	while x <= ceilf(R):
		var d := absf(x + 0.5) / R
		if d > 1.0:
			x += 1.0
			continue
		var top := -1.0 - Px.round(sqrt(1.0 - d * d) * hp)
		var y := top
		while y <= 0.0:
			var c: int = C[5] if y == top else (C[2] if y == 0.0 else C[4])
			if d > 0.88:
				c = C[4] if y == top else C[3]
			if y == top and d < 0.88:
				var n := Lib.lnoise(t, D, 7.0, x * 0.18, 3) + Lib.lnoise(t, D, 4.0, x * 0.07, 4) * 0.6
				if n > 0.55:
					c = C[6]
			elif y == top + 1.0 and d < 0.8 and Lib.lnoise(t, D, 3.0, x * 0.12, 5) > 0.3:
				c = C[5]
			p.px(x, y, c)
			y += 1.0
		if d > 0.96:
			p.px(x, top - 1.0, C[1])
		x += 1.0
	# bubbles swell out of the puddle and pop, flicking flecks
	Px.cycle(t, D, 4, o.seed * 17 + 3, func(r): return r.range(0.45, 0.75), func(ag, L, r):
		var bx: float = r.range(-0.85, 0.85) * R
		var k: float = ag / L
		var rb: float = r.range(1.4, 2.6) * (0.3 + 0.7 * Px.Ease.outCubic(minf(1.0, k * 1.25)))
		if absf(bx) < P.W / 2.0 + 1.0 and P.q < 0.0:
			return
		var sy := -1.0 - Px.round(sqrt(maxf(0.0, 1.0 - (bx / R) ** 2)) * hp)
		if k < 0.85:
			var y := floorf(sy - rb)
			while y <= sy:
				var xx := floorf(bx - rb - 1.0)
				while xx <= ceilf(bx + rb + 1.0):
					var dx := xx + 0.5 - bx
					var dy := y + 0.5 - sy
					var dd := Px.hypot(dx, dy)
					if dd > rb + 0.5:
						xx += 1.0
						continue
					if dd > rb - 0.7:
						p.px(xx, y, C[6] if (dx < 0.0 and dy < -rb * 0.3) else C[4])
					else:
						p.blend(xx, y, C[5], 0.3)
					xx += 1.0
				y += 1.0
			p.glow(bx, sy - rb * 0.5, rb * 2.0 + 3.0, C[5], 0.2)
		else:
			var q := (k - 0.85) / 0.15
			for dxy in [[1.0, 0.0], [-1.0, 0.0], [0.6, -0.7], [-0.6, -0.7], [0.0, -1.0]]:
				p.dot(bx + dxy[0] * (2.0 + 3.0 * q), sy + dxy[1] * (2.0 + 3.0 * q), C[6], 1.2 - q))
	# landed droplets: a flattened splat, then a bead of goo creeping home, a wet trail behind it
	for i in NDROP:
		var f := droplet(i, o, age)
		if not f.landed or f.gone:
			continue
		var fx := Px.round(f.x)
		var w: int = f.size + (1 if f.splat > 0.0 else 0)
		for j in w:
			p.px(fx - (w >> 1) + j, -1.0, C[5] if j == 0 else C[4])
		if f.size >= 2 and f.splat <= 0.0:
			p.px(fx, -2.0, C[5])
			p.px(fx - 1.0, -2.0, C[4])
		p.px(fx, 0.0, C[3])
		var dir := Px.sign(f.lx - f.x)
		var j := 1.0
		while j < minf(8.0, absf(f.lx - f.x)):
			p.dot(fx + dir * j, 0.0, C[2], 0.7 - j * 0.08)
			j += 1.0
		p.glow(fx, -1.0, 5.0, C[4], 0.25 * f.k + 0.1)
	# the goo string it pulls off the floor as it leaves; when it snaps, a drip falls back and the rest pulls up
	if t >= T_LIFT and t < SNAP:
		var bot: float = P.by - 1.0
		var u := (t - T_LIFT) / (SNAP - T_LIFT)
		var y := floorf(bot)
		while y < 0.0:
			var m := sin(((y - bot) / -bot) * PI)
			p.px(-1.0, y, C[4])
			if m * u < 0.45:
				p.px(0.0, y, C[3])
			y += 1.0
	elif t >= SNAP and t < SNAP + 0.3:
		var a2 := t - SNAP
		var ys: float = pose(SNAP, o.hop).by - 1.0
		var f := Lib.toss(-1.0, ys * 0.45, 0.0, 0.0, a2, G * 1.3, -2.0)
		if not f.landed:
			p.px(-1.0, f.y, C[5])
			p.px(-1.0, f.y - 1.0, C[3])
		var nub := 3.0 * (1.0 - a2 / 0.12)
		var j := 0.0
		while j < nub:
			p.px(-1.0, P.by + j, C[3] if j == 0.0 else C[4])
			j += 1.0
