# The streaks falling in (a dim body, a bright head) follow Sprite Fusion's open-source rain
# (https://www.spritefusion.com/pixel-art-vfx/rain), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/water/rain-splash.js@fc0377abdffa8813dd7b738c614238958149c5e6
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Rain splash",
	"desc": "A low close-up on one puddle in the rain: big drops land in crowns that throw beads and a rebound jet, rings spread and interfere, a lamp's reflection wobbles on the water.",
	"tags": ["water", "rain", "splash", "puddle", "close-up", "ambient", "loop"],
	"size": [176, 80],
	"origin": [88, 50],
	"duration": 2.4,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": Lib.WATER, "seed": 9},
}

static var D: float = meta.duration
const SY := 0.3
const RX := 92.0
const G := 640.0
const N := 8
const LAMP := 34.0


# the big drops: where each lands on the puddle (x across, z into it), when, how tall its crown stands
static func drops(S: float) -> Array:
	return Px.arr(N, func(i: int): return {
		"x": (Px.rand(i, S) - 0.5) * 120.0, "z": (Px.rand(i, S + 1.0) - 0.5) * 50.0, "t0": ((i + 0.25 * Px.rand(i, S + 2.0)) / N) * D,
		"H": 10.0 + 4.0 * Px.rand(i, S + 3.0), "J": 7.0 + 4.0 * Px.rand(i, S + 4.0), "spin": Px.rand(i, S + 5.0) * TAU, "i": i,
	})


static func ageOf(t: float, t0: float) -> float:
	return fmod(fmod(t - t0, D) + D, D)


# a ring's radius and strength at age a
static func ringR(a: float) -> float:
	return 3.0 + 34.0 * pow(a / 1.8, 0.7)


static func ringK(a: float) -> float:
	return 1.3 * pow(1.0 - a / 1.8, 1.3) * minf(1.0, a / 0.06) if a < 1.8 else 0.0


# the crown at age a: how high its walls stand and how wide its foot is
static func crownH(a: float, H: float) -> float:
	return H * pow(sin(PI * Px.clamp(a / 0.3)), 0.8) * (1.0 if a < 0.3 else 0.0)


static func crownR(a: float) -> float:
	return 1.5 + 4.5 * sqrt(Px.clamp(a / 0.3))


# the rebound jet: up and back down after the crown has fallen
static func jetH(a: float, J: float) -> float:
	return J * sin((PI * (a - 0.26)) / 0.3) if (a > 0.26 and a < 0.56) else 0.0


# the water's height at a point: every ring's swell summed, so where two cross they add and cancel
static func field(x: float, z: float, list: Array) -> float:
	var h := 0.0
	for q: Dictionary in list:
		var dx: float = x - q.x
		if dx > q.R + 10 or dx < -q.R - 10:
			continue
		var d: float = Px.hypot(dx, z - q.z) - q.R
		var w: float = 3.6 + q.a * 3.0
		if d > 2.0 * w or d < -3.0 * w:
			continue
		h += q.k * cos(d * 1.1) * Px.exp(-(pow(d / w, 2.0)))
	return h


static func drawBack(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var S: float = o.seed
	var ry := RX * SY
	var ph := t / D
	var list := drops(S).map(func(q: Dictionary): return Px.merge(q, {"a": ageOf(t, q.t0)})).filter(func(q: Dictionary): return q.a < 1.8).map(func(q: Dictionary): return Px.merge(q, {"R": ringR(q.a), "k": ringK(q.a)}))
	var Y := floorf(-ry)
	while Y < ry:
		var y := Y + 0.5
		var z := y / SY
		var act := list.filter(func(q: Dictionary): return absf(z - q.z) <= q.R + 12)
		var far := (y + ry) / (2.0 * ry)
		# the lamp's reflection on this row: a dash of light, its width shimmering, pushed about by the swell
		var dashW := (1.5 + far * 4.0) * (0.35 + 0.65 * (0.5 + 0.5 * sin(Y * 1.73 + ph * TAU * 3.0 + sin(Y * 0.61) * 3.0)))
		var hPrev := 0.0
		for X in range(-88, 88):
			var x := X + 0.5
			var d := pow(x / RX, 2.0) + pow(y / ry, 2.0)
			if d > 1.0:
				continue
			var edge := minf(1.0, (1.0 - d) * 6.0)
			# the puddle: dark see-through water, the far part holding a little of the sky
			p.blend(x, y, C[0], (0.62 + 0.2 * far) * edge)
			if far < 0.45:
				p.blend(x, y, C[2], 0.3 * (1.0 - far / 0.45) * edge)
			# its swell: every ring summed, so crests catch the light, troughs go dark, and crossings beat
			var h := field(x, z, act) if act.size() else 0.0
			var hx := h - hPrev
			hPrev = h
			if h > 0.24:
				p.blend(x, y, C[5] if h > 0.75 else C[4], minf(0.95, (h - 0.24) * 2.2) * edge)
			elif h < -0.4:
				p.blend(x, y, C[0], minf(0.85, (-h - 0.4) * 1.8) * edge)
			if x < LAMP - 14.0 or x > LAMP + 14.0:
				continue
			var lx := absf(x - LAMP - hx * 9.0 - sin(y * 0.8 + ph * TAU * 2.0) * 1.4)
			if lx < dashW:
				var k := (1.0 - lx / dashW) * edge
				p.px(X, Y, WHITE if k > 0.72 else (C[6] if k > 0.35 else C[5]))
				p.light(x, y, C[5], 0.2 * k)
		Y += 1.0
	# the far rim of the puddle catches the light
	for X in range(-82, 82):
		var x := X + 0.5
		var y := -sqrt(maxf(0.0, 1.0 - pow(x / RX, 2.0))) * ry
		p.px(X, y + 0.5, C[6] if absf(x - LAMP) < 10.0 else C[3])
	# the back halves of the crowns, behind their own front walls
	for q: Dictionary in drops(S):
		crown(p, C, q, ageOf(t, q.t0), true)


# a crown: a ring of fingers thrown up round the drop's hole, a bead on each tip until they tear away
static func crown(p: Px.Painter, C: Array, q: Dictionary, a: float, back: bool) -> void:
	var h := crownH(a, q.H)
	if h < 1.0:
		return
	var r0 := crownR(a)
	var cy: float = q.z * SY
	for f in 10:
		var ang: float = q.spin + (f / 10.0) * TAU
		var s := sin(ang)
		if (s < 0.0) != back:
			continue
		var tip := h * (0.75 + 0.25 * Px.rand(q.i, f, 7))
		var lean := 0.35 * tip
		var x0: float = q.x + cos(ang) * r0
		var y0 := cy + s * r0 * SY
		var x1: float = q.x + cos(ang) * (r0 + lean)
		var y1 := cy + s * (r0 + lean) * SY - tip
		p.line(x0, y0, x1, y1, (func(u: float): return C[5] if u > 0.7 else C[3]) if back else (func(u: float): return WHITE if u > 0.75 else (C[6] if u > 0.35 else C[5])))
		if a > 0.08 and a < 0.17:
			p.px(x1, y1 - 1.0, C[5] if back else WHITE)
	if not back:
		p.glow(q.x, cy - h * 0.6, 6.0 + h * 0.6, C[5], 0.3 * (h / q.H))


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var S: float = o.seed
	for q: Dictionary in drops(S):
		var a := ageOf(t, q.t0)
		var cy: float = q.z * SY
		# falling in: a streak dropping into the frame just before it lands
		var pre := D - a
		if pre < 0.14 and cy - pre * 520.0 - 10.0 > -48.0:
			var y := cy - pre * 520.0
			p.line(q.x, y - 10.0, q.x, y - 4.0, C[4])
			p.line(q.x, y - 4.0, q.x, y, C[6])
		# the hit: a white fleck and a flash of light, then the crown
		if a < 0.05:
			p.px(q.x, cy, WHITE)
			p.glow(q.x, cy - 2.0, 12.0, C[5], 0.5 * (1.0 - a / 0.05))
		crown(p, C, q, a, false)
		# beads torn off the crown's tips arc out and fall back, each with a fleck and a little ring
		if a > 0.16 and a < 0.8:
			for f in range(0, 10, 2):
				var ang: float = q.spin + (f / 10.0) * TAU
				var tip := crownH(0.16, q.H) * (0.75 + 0.25 * Px.rand(q.i, f, 7))
				var r0 := crownR(0.16) + tip * 0.35
				var v := 22.0 + 18.0 * Px.rand(q.i, f, 8)
				var vh := 40.0 + 30.0 * Px.rand(q.i, f, 9)
				var tt := a - 0.16
				var hh := tip + vh * tt - 0.5 * G * tt * tt
				var bx: float = q.x + cos(ang) * (r0 + v * tt)
				var bz: float = q.z + sin(ang) * (r0 + v * tt)
				var by := bz * SY
				if hh > 0.0:
					Lib.bead(p, bx, by - hh, cos(ang) * v, -(vh - G * tt) + sin(ang) * v * SY, 2.0 if Px.rand(q.i, f, 10) < 0.4 else 1.0, C)
				else:
					var land := (vh + sqrt(vh * vh + 2.0 * G * tip)) / G
					var since := tt - land
					if since < 0.05:
						p.px(bx, by, WHITE)
					if since < 0.35:
						Lib.ring(p, bx, by, 1.0 + since * 12.0, SY, 1.0 - since / 0.35, C, {"n": 1.0, "half": 1.0, "seed": q.i * 10 + f})
		# the rebound jet, with a bead that pinches off its top and drops back
		var jh := jetH(a, q.J)
		if jh > 0.8:
			p.line(q.x, cy - 1.0, q.x, cy - jh, func(u: float): return WHITE if u > 0.6 else C[6])
			p.px(q.x + 1.0, cy - 1.0, C[5])
			if a < 0.41:
				p.circle(q.x, cy - jh - 0.5, 1.2, C[6])
			p.glow(q.x, cy - jh * 0.6, 6.0, C[5], 0.3)
		var ba := a - 0.41
		var bh: float = q.J + 1.0 + 24.0 * ba - 0.5 * G * ba * ba
		if ba > 0.0 and bh > 0.0:
			p.circle(q.x, cy - bh, 1.1, C[6])
			p.px(q.x, cy - bh - 1.0, WHITE)
	# the near halves of the main rings, crisp, so each splash has its own edge in the swell
	for q: Dictionary in drops(S):
		var a := ageOf(t, q.t0)
		if a < 1.8:
			Lib.ring(p, q.x, q.z * SY, ringR(a), SY, 0.75 * ringK(a), C, {"n": 1.0, "half": 1.0, "hot": a < 0.1, "seed": q.i, "wob": 0.5 + a})
	# finer rain dimpling the water, and a few streaks falling past
	Px.cycle(t, D, 16, S + 20.0, 0.5, func(age: float, life: float, r: Px.Rng):
		var x := r.range(-80.0, 80.0)
		var z := r.range(-26.0, 26.0)
		var y := z * SY
		var s := age - 0.1
		if s < 0.0:
			var yy := y - (0.1 - age) * 600.0
			if yy - 6.0 < -48.0:
				return
			p.line(x, yy - 6.0, x, yy, func(u: float): return C[5] if u > 0.6 else C[3])
		elif s < 0.4 and pow(x / RX, 2.0) + pow(y / (RX * SY), 2.0) < 0.9:
			if s < 0.04:
				p.px(x, y, C[6])
			Lib.ring(p, x, y, 1.0 + s * 9.0, SY, 0.8 * (1.0 - s / 0.4), C, {"n": 1.0, "half": 1.0, "seed": 40.0}))
	# the lamp's glow on the water
	p.glow(LAMP, -6.0, 30.0, C[4], 0.16)
