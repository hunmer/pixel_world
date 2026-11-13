# The basin's caustic light (two warped sine nets, light where they cross zero) is adapted from Sprite Fusion's
# open-source bubbles (https://www.spritefusion.com/pixel-art-vfx/bubbles), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/water/fountain.js@a18a8879e80d33752169912d064bcf8d8a2b6db6
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Fountain",
	"desc": "A stone basin; a jet rises from its spout and blooms into glassy arcs that break into beads, fall back and plink into the water with rings.",
	"tags": ["water", "fountain", "jet", "basin", "prop", "ambient", "loop"],
	"size": [120, 104],
	"origin": [60, 96],
	"duration": 2,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": Lib.WATER, "seed": 3},
}

static var D: float = meta.duration
const SY := 0.34
const G := 600.0
const RIM := 10.0
const RX := 36.0
const IN := 29.5
const JET := 54.0
const ARCS := 12
# the basin stands on the floor: its base ellipse touches y = 0 at the front; heights are measured from that plane
const BY := -RX * SY
const LEVEL := RIM - 1.2


# the arcs: water thrown out of the top of the jet in every direction, each a parabola back down to the basin
static func arcs(S: float) -> Array:
	return Px.arr(ARCS, func(i: int):
		var a := ((i + 0.5) / ARCS) * TAU + Px.rand(i, S) * 0.25
		var vr := 38.0 + 14.0 * Px.rand(i, S + 1.0)
		var vh := 30.0 + 26.0 * Px.rand(i, S + 2.0)
		var tl := (vh + sqrt(vh * vh + 2.0 * G * (JET - LEVEL))) / G
		return {"a": a, "vr": vr, "vh": vh, "tl": tl, "ca": cos(a), "sa": sin(a)})


# a point along an arc tau seconds into its flight: screen x, y and the height above the floor
static func along(q: Dictionary, tau: float) -> Array:
	var r: float = q.vr * tau
	var h: float = JET + q.vh * tau - 0.5 * G * tau * tau
	return [q.ca * r, BY + q.sa * r * SY - h, h]


# the stone basin: a wide rim lit toward the light with a dark line round both edges, a wall of stone blocks
# below its near side (lit left, shaded right) standing on the floor
static func inEll(x: float, y: float, rx: float, cy: float) -> bool:
	return pow(x / rx, 2.0) + pow((y - cy) / (rx * SY), 2.0) <= 1.0


static func basin(p: Px.Painter, ST: Array, half: float) -> void:
	var cy := BY - RIM
	var ry := RX * SY
	p.shade(-RX - 1.0, cy - ry - 1.0, RX + 1.0, 1.0, func(x: float, y: float, out):
		if inEll(x, y, RX, cy):
			if inEll(x, y, IN, cy):
				return
			var near := y > cy
			if near != (half > 0.0):
				return
			var outer := not inEll(x, y - 1.0, RX, cy) or not inEll(x, y + 1.0, RX, cy) or not inEll(x - 1.0, y, RX, cy) or not inEll(x + 1.0, y, RX, cy)
			var inner := inEll(x, y - 1.0, IN, cy) or inEll(x, y + 1.0, IN, cy) or inEll(x - 1.0, y, IN, cy) or inEll(x + 1.0, y, IN, cy)
			var a := atan2((y - cy) / ry, x / RX)
			var lit := -cos(a) * 0.65 - sin(a) * 0.45
			out.c = ST[0] if outer else ((ST[2] if y < cy else ST[1]) if inner else (ST[5] if lit > 0.4 else (ST[4] if lit > -0.05 else (ST[3] if lit > -0.45 else ST[2]))))
			return
		# the wall, under the near half of the rim
		if half < 0.0 or absf(x) >= RX:
			return
		var dx := x / RX
		var top := cy + sqrt(1.0 - dx * dx) * ry
		var base := top + RIM
		if y < top or y > base:
			return
		var u := asin(Px.clamp(dx)) * RX * 0.62
		var _block := fmod(fmod((u + 40.0) / 9.0, 1.0) + 1.0, 1.0)
		var row := y - top
		var course := 1.0 if row > RIM * 0.5 else 0.0
		var joint := fmod(fmod((u + 40.0 + course * 4.5) / 9.0, 1.0) + 1.0, 1.0) < 0.1
		out.c = ST[0] if (y > base - 1.0 or absf(x) > RX - 1.0 or row < 1.0) else (ST[1] if (joint or absf(row - RIM * 0.5) < 0.5) else (ST[4] if dx < -0.4 else (ST[3] if dx < 0.3 else ST[2])))
		if row >= 1.0 and row < 2.0 and not joint:
			out.c = ST[2] if dx < 0.0 else ST[1])


# the water in the basin: dark and see-through, a lit band at the far side, caustic light swimming in it
static func pool(p: Px.Painter, C: Array, ph: float) -> void:
	var rx := IN
	var ry := rx * SY
	var cy := BY - LEVEL
	var T := ph * TAU
	var Y := floorf(cy - ry)
	while Y < cy + ry:
		var X := -ceilf(rx)
		while X < rx:
			var x := X + 0.5
			var y := Y + 0.5
			var dx := x / rx
			var dy := (y - cy) / ry
			var d := dx * dx + dy * dy
			if d > 1.0:
				X += 1.0
				continue
			p.blend(x, y, C[3] if dy < -0.55 else C[1], 0.8 if dy < -0.55 else 0.85)
			var u := x * 0.25 + 1.6 * sin(y * 0.6 + T)
			var w := y * 0.7 + 1.6 * sin(x * 0.14 - T * 2.0)
			var f := maxf(0.0, 1.0 - absf(sin(u) + sin(w)) * 2.6) * (1.0 - d)
			if f > 0.35:
				p.light(x, y, C[5], 0.3 * f)
			X += 1.0
		Y += 1.0


static func drawBack(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var ph := t / D
	var S: float = o.seed
	var ST := Lib.rock()
	var Q := arcs(S)
	basin(p, ST, -1.0)
	pool(p, C, ph)
	# the arcs on the far side, dimmer, behind the jet
	for q: Dictionary in Q:
		if q.sa < 0:
			arc(p, C, q, ph, true)


# one arc: a glassy stream that thins as it falls and breaks into beads at the end; beads slide down it
static func arc(p: Px.Painter, C: Array, q: Dictionary, ph: float, back: bool) -> void:
	var prev: Variant = null
	var tau := 0.0
	while tau <= q.tl:
		var xy := along(q, tau)
		var x: float = xy[0]
		var y: float = xy[1]
		var u: float = tau / q.tl
		if prev and u < 0.66:
			p.line(prev[0], prev[1], x, y, ((C[5] if u < 0.25 else C[4]) if back else (WHITE if u < 0.2 else (C[6] if u < 0.45 else C[5]))))
		prev = [x, y]
		tau += 0.012
	# the beads it breaks into, sliding down at the water's own speed
	for k in 6:
		var u := fmod(ph * 2.0 + k / 6.0, 1.0) * 0.42 + 0.58
		var tau2: float = u * q.tl
		var xy := along(q, tau2)
		var x: float = xy[0]
		var y: float = xy[1]
		var vy: float = (q.vh - G * tau2) * -1.0 + q.sa * q.vr * SY
		Lib.bead(p, x, y, q.ca * q.vr, vy, 1.0 if back else (2.0 if k % 3 == 0 else 1.0), [C[0], C[1], C[2], C[2], C[3], C[4], C[5], C[5]] if back else C)
	# and the ones sliding along the stream itself catch the light
	var g: float = fmod(ph * 4.0 + q.a, 1.0) * 0.6
	var gxy := along(q, g * q.tl)
	var gx: float = gxy[0]
	var gy: float = gxy[1]
	p.px(gx, gy, WHITE)
	if not back:
		p.glow(gx, gy, 3.0, C[5], 0.3)


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var ph := t / D
	var S: float = o.seed
	var ST := Lib.rock()
	var Q := arcs(S)
	var T := ph * TAU
	# the spout: a little stone stem in the middle of the basin
	p.shade(-3.5, BY - 16.0, 3.5, BY - LEVEL + 0.5, func(x: float, y: float, out):
		var w := 3.4 if y < BY - 14.0 else 2.2
		if absf(x) > w:
			return
		out.c = ST[0] if (absf(x) > w - 0.8 or y < BY - 15.5) else (ST[4] if x < -0.6 else (ST[3] if x < 0.8 else ST[2])))
	# the jet: a glassy column, white down its middle, wobbling a little at the top
	p.shade(-3.0, BY - JET - 1.0, 3.0, BY - 16.0, func(x: float, y: float, out):
		var v := (BY - 16.0 - y) / (JET - 16.0)
		var sway := sin(T * 2.0 + v * 5.0) * 0.5 * v
		var w := 1.3 + 0.5 * v + 0.3 * sin(T * 3.0 + y * 0.4)
		var q := (x - sway) / w
		if absf(q) > 1.0:
			return
		var n := Px.tileNoise(x * 0.9, y * 0.15 + ph * 16.0, 0.0, 16.0, S)
		out.c = C[6] if q < -0.4 else ((WHITE if n > -0.3 else C[6]) if q < 0.35 else C[5]))
	# the bloom where it opens out at the top
	p.circle(0.0, BY - JET - 1.0, 2.4, C[6])
	p.circle(-0.4, BY - JET - 1.5, 1.4, WHITE)
	p.glow(0.0, BY - JET, 22.0, C[5], 0.46 + 0.06 * sin(T * 4.0))
	p.glow(0.0, BY - JET - 1.0, 8.0, WHITE, 0.3)
	# glints wink along the arcs
	Px.cycle(t, D, 10, S + 30.0, func(g: Px.Rng): return g.range(0.2, 0.35), func(age: float, life: float, r: Px.Rng):
		var q: Dictionary = Q[floori(r.next() * ARCS)]
		var xy := along(q, r.range(0.1, 0.7) * q.tl)
		var x: float = xy[0]
		var y: float = xy[1]
		var k := sin((PI * age) / life)
		if q.sa < -0.3:
			return
		p.px(x, y, WHITE)
		if k > 0.6:
			for dd: Array in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
				p.px(x + dd[0], y + dd[1], C[6])
		p.glow(x, y, 5.0, C[5], 0.4 * k))
	# foam where the jet leaves the spout
	for i in 4:
		p.px(sin(T * 3.0 + i * 1.7) * 2.5, BY - 16.0 - (i % 2), C[6] if i % 2 else WHITE)
	# the arcs on the near side, in front of the jet
	for q: Dictionary in Q:
		if q.sa >= 0:
			arc(p, C, q, ph, false)
	# where they come down: near halves of the rings, flecks and tiny crowns thrown up, light on the water
	for i in Q.size():
		var q: Dictionary = Q[i]
		var f := fmod(ph * 2.0 + Px.rand(i, S + 9.0), 1.0)
		var xy := along(q, q.tl)
		var x: float = xy[0]
		var y: float = xy[1]
		Lib.ring(p, x, y, 2.0 + f * 8.0, SY, 0.8 * pow(1.0 - f, 1.3), C, {"n": 1.0, "half": 1.0, "seed": i})
		var g := fmod(ph * 6.0 + Px.rand(i, S + 10.0), 1.0)
		if g < 0.15:
			p.px(x, y - 1.0, WHITE)
		if g < 0.3 and q.sa > -0.2:
			p.line(x, y - 1.0, x + (Px.rand(i, S + 11.0) - 0.5) * 2.0, y - 1.0 - 3.0 * (1.0 - g / 0.3), C[6])
		p.glow(x, y, 6.0, C[5], 0.18 * (1.0 - g))
	basin(p, ST, 1.0)
	# a fine mist hangs round the bloom
	Px.cycle(t, D, 16, S + 20.0, func(g: Px.Rng): return g.range(0.8, 1.4), func(age: float, life: float, r: Px.Rng):
		var k := age / life
		var a := r.range(0.0, TAU)
		var rr := r.range(4.0, 20.0) + k * 6.0
		var x := cos(a) * rr
		var y := BY - JET + r.range(-4.0, 16.0) + k * 10.0
		if k > 0.75 and r.next() < (k - 0.75) * 4.0:
			return
		p.px(x, y, WHITE if r.next() < 0.4 else C[6]))
	# light: the jet, and the basin water lit from above
	p.glowLine(0.0, BY - 16.0, 0.0, BY - JET, 10.0, C[5], 0.18)
	p.glow(0.0, BY - LEVEL - 2.0, 46.0, C[4], 0.26 + 0.03 * sin(T * 2.0))
	p.glow(0.0, BY - LEVEL - 20.0, 30.0, C[5], 0.12)
