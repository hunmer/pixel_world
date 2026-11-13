# The column of light (banded across, strands wandering in it, pulses and halos climbing it, stars thrown off,
# rings shocking out across the floor) is adapted from Sprite Fusion's open-source holy light
# (https://www.spritefusion.com/pixel-art-vfx/holy-light), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/arcane/magic-circle-cast.js@c95d98a086eae877fb894717d3c2931d8bcf7e58
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE

# the circle on the floor (plane px; the floor squashes depth by SY), the column, the beats
const R := 40.0
const R2 := 35.0
const RI := 24.0
const RR := 30.0
const SY := 0.3
const TOP := 192.0
const W := 11.0
const NRUNE := 8
const PEN := [0.04, 0.42]
const PEN2 := [0.1, 0.48]
const INNER := [0.3, 0.6]
const STAR := [0.52, 0.88]
const RUNES := [0.9, 1.3]
const FLASH := 1.52
const BREAK := 2.42
const GONE := 3.45
const END := 3.9

static var meta := {
	"name": "Magic circle cast",
	"desc": "A circle draws itself on the floor, runes ignite one by one, it flashes, and a column of light fires up and breaks apart into glints.",
	"tags": ["arcane", "magic", "circle", "rune", "cast", "column", "summon", "ground", "one-shot"],
	"size": [200, 220],
	"origin": [100, 192],
	"duration": END,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": Px.PAL.arcane, "seed": 6},
}

static func wrapA(a: float) -> float:
	return fmod(fmod(a, TAU) + TAU, TAU)

static func fromFront(g: float) -> float:
	return absf(atan2(sin(g - PI / 2.0), cos(g - PI / 2.0)))

# when the pens pass angle g: the outer rings are drawn from the front round both sides to the back, the inner
# ring from the back all the way round
static func outerAt(g: float, w: Array) -> float:
	return w[0] + (fromFront(g) / PI) * (w[1] - w[0])

static func innerAt(g: float) -> float:
	return INNER[0] + (wrapA(g + PI / 2.0) / TAU) * (INNER[1] - INNER[0])

static func runeAngle(k: int) -> float:
	return -PI / 2.0 + ((k + 0.5) * TAU) / NRUNE

static func runeLit(k: int) -> float:
	return RUNES[0] + (k * (RUNES[1] - RUNES[0])) / (NRUNE - 1)

static func runeOut(k: int) -> float:
	return BREAK + 0.2 + k * 0.08


# how bright the drawn circle burns: settled while it's drawn, swelling as the runes light, white at the flash
static func level(t: float) -> float:
	if t < RUNES[0]:
		return 0.55
	if t < FLASH:
		return 0.55 + 0.4 * Px.smooth(RUNES[0], FLASH, t)
	if t < FLASH + 0.07:
		return 1.2
	if t < BREAK:
		return 0.92
	return 0.92 * (1.0 - Px.smooth(BREAK, GONE, t))


var C: Array
var S: float
var Rg: Px.Rng
var ps: Px.Particles
var lights: Px.Lights
var COL: Array
var strands: Array
var edges := []
var t := 0.0
var flashed := false
var broke := false
var out := []


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	S = o.seed
	Rg = Px.Rng.new(S)
	ps = Px.Particles.new({"rng": Rg, "ground": func(): return 0.0, "sparks": [WHITE, C[6], C[5], C[4]]})
	lights = Px.Lights.new()
	COL = [WHITE, C[6], C[5], C[4], C[3]]
	strands = Px.arr(9, func(_i): return {"o": Rg.range(-0.85, 0.85), "w": Rg.range(0.04, 0.1), "f": Rg.range(1.0, 3.0)})
	# the hexagram: two triangles inside the inner ring, each drawn edge by edge
	var tri := func(a0: float) -> Array: return [0, 1, 2].map(func(k): return a0 + (k * TAU) / 3.0).map(func(a): return [cos(a) * RI, sin(a) * RI])
	var A: Array = tri.call(-PI / 2.0)
	var Bt: Array = tri.call(PI / 2.0)
	for k in 3:
		for T: Array in [A, Bt]:
			edges.append({"p0": T[k], "p1": T[(k + 1) % 3], "t0": STAR[0] + (k * (STAR[1] - STAR[0])) / 3.0, "dur": (STAR[1] - STAR[0]) / 3.0})
	out.resize(NRUNE)
	out.fill(false)


func lineCol(lvl: float, age: float) -> int:
	return WHITE if age < 0.05 else (C[6] if age < 0.16 else (WHITE if lvl > 1.0 else (C[6] if lvl > 0.8 else (C[5] if lvl > 0.45 else (C[4] if lvl > 0.28 else C[3])))))

func lineA(lvl: float) -> float:
	return Px.clamp(lvl / 0.3)


# a straight line on the floor plane, drawn by a pen from p0 to p1 over [t0, t0 + dur]; only the far (v < 0) or near part
func planeLine(p: Px.Painter, p0: Array, p1: Array, t0: float, dur: float, lvl: float, far: bool) -> void:
	var s := Px.clamp((t - t0) / dur)
	if s <= 0.0:
		return
	var u0 := 0.0
	var u1 := s
	var v0: float = p0[1]
	var v1: float = p1[1]
	if (v0 < 0.0) != (v1 < 0.0):
		var uc := v0 / (v0 - v1)
		if (v0 < 0.0) == far:
			u1 = minf(u1, uc)
		else:
			u0 = uc
	elif (v0 < 0.0) != far:
		return
	if u1 <= u0:
		return
	var Pt := func(u: float) -> Array: return [p0[0] + (p1[0] - p0[0]) * u, (v0 + (v1 - v0) * u) * SY]
	var a: Array = Pt.call(u0)
	var b: Array = Pt.call(u1)
	p.line(a[0], a[1], b[0], b[1], func(q: float) -> int: return lineCol(lvl, t - (t0 + (u0 + (u1 - u0) * q) * dur)), lineA(lvl))


func circle(p: Px.Painter, far: bool) -> void:
	if t >= GONE:
		return
	var lvl := level(t)
	var keep := (func(g: float) -> bool: return sin(g) < 0.0) if far else (func(g: float) -> bool: return sin(g) >= 0.0)
	var a := lineA(lvl)
	var ring := func(r: float, when: Callable, chase: Variant) -> void:
		Lib.floorRing(p, 0.0, 0.0, r, SY, func(g: float) -> int: return WHITE if (chase != null and chase.call(g)) else lineCol(lvl, t - when.call(g)), func(g: float) -> float: return 0.0 if t < when.call(g) else a, keep)
	# from the moment the runes start to light, two sparks of light chase round the outer ring, faster and faster
	var run: Variant = (t - RUNES[0]) * 5.0 + pow(t - RUNES[0], 2.0) * 4.0 if (t > RUNES[0] and t < BREAK) else null
	var chase: Variant = null if run == null else func(g: float) -> bool: return [0.0, PI].any(func(o): return absf(atan2(sin(g - run - o), cos(g - run - o))) < 0.22)
	ring.call(R, func(g: float) -> float: return outerAt(g, PEN), chase)
	ring.call(R2, func(g: float) -> float: return outerAt(g, PEN2), null)
	ring.call(RI, func(g: float) -> float: return innerAt(g), null)
	# ticks across the band between the two outer rings
	for j in 32:
		var g := ((j + 0.5) * TAU) / 32.0
		if (sin(g) < 0.0) != far:
			continue
		var when := outerAt(g, PEN2) + 0.03
		if t < when:
			continue
		p.line(cos(g) * R2, sin(g) * R2 * SY, cos(g) * R, sin(g) * R * SY, lineCol(lvl, t - when), a * (0.6 if j % 2 else 1.0))
	for e: Dictionary in edges:
		planeLine(p, e.p0, e.p1, e.t0, e.dur, lvl, far)


# the runes stand on the circle; dim when the inner pen passes, lit one by one, out one by one
func runes(p: Px.Painter, far: bool) -> void:
	for k in NRUNE:
		var g := runeAngle(k)
		if (sin(g) < 0.0) != far:
			continue
		var x := cos(g) * RR
		var y0 := sin(g) * RR * SY
		var lit := t - runeLit(k)
		var gone := Px.clamp((t - runeOut(k)) / 0.25)
		if t < innerAt(g) or gone >= 1.0:
			continue
		if lit < 0.0:
			Lib.glyph(p, k, x, y0 - 1.0, C[3])
			continue
		var rise := 3.0 * Px.Ease.outBack(Px.clamp(lit / 0.2), 2.4)
		var bob := sin(t * 5.0 + k) * 0.5 if lit > 0.2 else 0.0
		var y := y0 - 1.0 - rise + bob
		var hot := lit < 0.07 or (t > FLASH and t < FLASH + 0.07)
		var lvl := level(t)
		Lib.glyph(p, k, x, y, WHITE if hot else (WHITE if lvl > 0.8 else C[6]), 1.0 - gone, C[6] if hot else C[4])
		if lit < 0.1:
			Px.sparkle(p, x, y - 2.0, 4.0 * (1.0 - lit / 0.1) + 1.0, C[6], C[5], 0.5)
		p.glow(x, y - 2.0, 8.0, C[5], (0.3 + 0.3 * lvl) * (1.0 - gone))
		p.glow(x, y0, 6.0, C[4], 0.2 * (1.0 - gone))


# the column of light: the thread that climbs first, then the beam that fires up, holds and breaks apart
func column(p: Px.Painter) -> void:
	if t < FLASH - 0.22 or t > BREAK + 0.6:
		return
	if t < FLASH:
		var a := Px.smooth(FLASH - 0.22, FLASH - 0.04, t)
		var top := -(TOP - 10.0) * Px.Ease.outCubic(a)
		var yy := -1
		while yy >= top:
			p.dot(0.0, yy, C[6] if yy > top + 6.0 else WHITE, a * (0.35 + 0.65 * (1.0 + yy / TOP)))
			yy -= 1
		p.glow(0.0, top, 9.0, C[6], 0.5 * a)
		p.glow(0.0, -6.0, 24.0, C[5], 0.4 * a)
		return
	var u := t - FLASH
	var brk := Px.clamp((t - BREAK) / 0.45)
	var top := -TOP * Px.Ease.outExpo(Px.clamp(u / 0.09))
	var w := W * (1.0 + 0.38 * exp(-u * 9.0)) if t < BREAK else W * (1.0 - Px.Ease.outCubic(brk) * 0.85)
	var fade := 1.0 - Px.smooth(BREAK + 0.25, BREAK + 0.55, t)
	var white := u < 0.067
	if fade <= 0.0:
		return
	var y := 3
	while y >= ceilf(top):
		var h := -y
		var ww := w * (1.0 + 0.5 * exp(-maxf(0.0, h) / 6.0))
		var pulse := 1 if Px.fract(h * 0.022 - u * 2.6) < 0.07 else 0
		for x in range(floori(-ww * 1.3), ceili(ww * 1.3) + 1):
			var q := absf(x + 0.5) / ww
			# as it breaks, holes open and grow and drift upward until only shards are left
			if brk > 0.0 and Px.noise2(x * 0.32, h * 0.11 - (t - BREAK) * 6.0, S) * 0.5 + 0.5 < brk * 1.25 - 0.1:
				continue
			var lv := 0 if q < 0.2 else (1 if q < 0.42 else (2 if q < 0.66 else (3 if q < 0.88 else 4)))
			for s: Dictionary in strands:
				if absf((x + 0.5) / ww - s.o - 0.05 * sin(t * s.f + s.o * 9.0)) < s.w:
					lv = maxi(0, lv - 1)
			lv = 0 if white else maxi(0, lv - pulse)
			var a := (1.0 if q < 0.88 else (1.3 - q) / 0.42) * fade
			if a <= Lib.bayer(x, y) * (0.2 if q < 0.66 else 1.0):
				continue
			p.px(x, y, COL[lv])
		if (h & 7) == 0 and h < TOP - ww * 2.4 - 8.0:
			p.glow(0.0, y, ww * 2.4 + 6.0, C[5], 0.3 * fade)
		y -= 1
	# halos climbing it
	for i in 6:
		var k := (t - (FLASH + 0.08 + i * 0.16)) / 0.8
		if k < 0.0 or k > 1.0:
			continue
		var rx := w * 1.4 * (1.0 + k * 0.35)
		var ry := rx * 0.3
		var yc := -3.0 - Px.Ease.outQuad(k) * 120.0
		var n := ceili(rx * 7.0)
		for j in n:
			var g := (float(j) / n) * TAU
			p.dot(cos(g) * rx, yc + sin(g) * ry, WHITE if k < 0.3 else C[6], (1.0 - k) * fade * (0.6 if sin(g) < 0.0 else 1.0))
	# white-hot where it meets the floor
	p.glow(0.0, -4.0, 34.0, C[6], 0.45 * fade)
	p.glow(0.0, -60.0, 70.0, C[4], 0.25 * fade)


func shock(p: Px.Painter, far: bool) -> void:
	for e: Array in [[0.0, R * 0.6, R * 2.0, 6.0, 0.5], [0.08, R * 0.4, R * 1.4, 3.0, 0.4]]:
		var d: float = e[0]
		var r0: float = e[1]
		var r1: float = e[2]
		var th: float = e[3]
		var dur: float = e[4]
		var k := (t - FLASH - d) / dur
		if k < 0.0 or k >= 1.0:
			continue
		Px.band(p, 0.0, 0.0, r0 + (r1 - r0) * Px.Ease.outCubic(k), SY, maxf(1.0, th * (1.0 - k)), 1.15 - k, [C[3], C[5], C[6], WHITE], func(g: float) -> bool: return (sin(g) < 0.0) == far, k < 0.2)


func update(dt: float) -> void:
	t += dt
	# the pens shed glitter as they write
	if t > PEN[0] and t < STAR[1] and Rg.chance(0.5):
		var x: float
		var y: float
		if t < PEN[1]:
			var g: float = PI / 2.0 + Rg.sign() * ((t - PEN[0]) / (PEN[1] - PEN[0])) * PI
			x = cos(g) * R
			y = sin(g) * R * SY
		elif t < INNER[1]:
			var g: float = -PI / 2.0 + ((t - INNER[0]) / (INNER[1] - INNER[0])) * TAU
			x = cos(g) * RI
			y = sin(g) * RI * SY
		else:
			var live := edges.filter(func(e): return t >= e.t0 and t < e.t0 + e.dur)
			var e: Dictionary
			if live.is_empty():
				Rg.next()  # JS: pick() of an empty list draws a number, gives undefined, `?? edges[0]`
				e = edges[0]
			else:
				e = Rg.pick(live)
			var s := Px.clamp((t - e.t0) / e.dur)
			x = e.p0[0] + (e.p1[0] - e.p0[0]) * s
			y = (e.p0[1] + (e.p1[1] - e.p0[1]) * s) * SY
		ps.spawn(P.EMBER, x, y - 1.0, Rg.range(-12.0, 12.0), Rg.range(-30.0, -8.0), Rg.range(0.25, 0.55), C[6], 1.0)
	# gathering: light rushes in along the floor to the heart of the circle
	if t > RUNES[1] - 0.1 and t < FLASH - 0.05 and Rg.chance(0.7):
		var g := Rg.range(0.0, TAU)
		var D := Rg.range(R * 0.7, R * 1.1)
		var T := Rg.range(0.16, 0.24)
		var v := (D * 3.0) / (exp(3.0 * T) - 1.0)
		var x := cos(g) * D
		var y := sin(g) * D * SY - 1.0
		var l := Px.hypot(x, y + 2.0)
		if not l:
			l = 1.0
		ps.spawn(P.STREAK, x, y, (-x / l) * v, ((-2.0 - y) / l) * v, T, C[6] if Rg.chance(0.5) else C[5])
	if not flashed and t >= FLASH:
		flashed = true
		lights.add(0.0, -56.0, 104.0, C[5], 0.9, 0.6)
		lights.add(0.0, -5.0, 36.0, WHITE, 0.8, 0.14)
		for i in 36:
			var s := Rg.sign()
			var sp := Rg.range(80.0, 175.0)
			ps.spawn(P.SPARK, s * Rg.range(0.0, R * 0.5), -1.0, s * sp, -Rg.range(30.0, 180.0), Rg.range(0.25, 0.7))
		for i in 26:
			ps.spawn(P.STAR, Rg.range(-R, R), -Rg.range(1.0, 6.0), Rg.range(-20.0, 20.0), -Rg.range(40.0, 130.0), Rg.range(0.5, 1.1), Rg.pick([WHITE, C[6], C[5]]), Rg.range(0.8, 2.3))
		# and a spray of twinkles flung out low across the floor
		for i in 34:
			var s := Rg.sign()
			ps.spawn(P.STAR, s * Rg.range(0.0, 14.0), -Rg.range(1.0, 4.0), s * Rg.range(50.0, 140.0), -Rg.range(10.0, 90.0), Rg.range(0.4, 0.95), Rg.pick([WHITE, C[6], C[6], C[5]]), Rg.range(0.7, 2.2))
	# glints pop along the burning circle
	if t > RUNES[0] and t < BREAK + 0.2 and Rg.chance(0.12):
		var g := Rg.range(0.0, TAU)
		var r: float = Rg.pick([R, R2, RI])
		ps.spawn(P.STAR, cos(g) * r, sin(g) * r * SY - 0.5, 0.0, -Rg.range(2.0, 8.0), Rg.range(0.25, 0.45), Rg.pick([WHITE, C[6]]), Rg.range(0.8, 2.0))
	# the column throws off stars, and light streams up inside it
	if t > FLASH and t < BREAK:
		if Rg.chance(0.5):
			ps.spawn(P.STAR, Rg.range(-1.0, 1.0) * W * 1.5, -Rg.range(0.0, 120.0), Rg.range(-10.0, 10.0), -Rg.range(30.0, 85.0), Rg.range(0.5, 1.1), Rg.pick([WHITE, C[6], C[5]]), Rg.range(0.7, 2.0))
		if Rg.chance(0.35):
			ps.spawn(P.MOTE, Rg.range(-1.0, 1.0) * W * 0.8, -Rg.range(0.0, 50.0), 0.0, -Rg.range(160.0, 300.0), Rg.range(0.2, 0.35), WHITE if Rg.chance(0.5) else C[6], 0.8)
	# it breaks apart into glints that twinkle as they drift up
	if not broke and t >= BREAK:
		broke = true
		for i in 46:
			ps.spawn(P.STAR, Rg.range(-1.0, 1.0) * W * 0.9, -Rg.range(2.0, TOP * 0.8), Rg.range(-12.0, 12.0), -Rg.range(8.0, 40.0), Rg.range(0.5, 1.15), Rg.pick([WHITE, WHITE, C[6], C[5]]), Rg.range(0.6, 2.4))
	if t > BREAK and t < BREAK + 0.4 and Rg.chance(0.8):
		ps.spawn(P.STAR, Rg.range(-1.0, 1.0) * W * 0.7, -Rg.range(2.0, TOP * 0.78), Rg.range(-8.0, 8.0), -Rg.range(10.0, 50.0), Rg.range(0.4, 0.9), Rg.pick([WHITE, C[6], C[5]]), Rg.range(0.6, 1.8))
		if Rg.chance(0.4):
			ps.spawn(P.MOTE, Rg.range(-1.0, 1.0) * W * 0.5, -Rg.range(2.0, TOP * 0.7), 0.0, -Rg.range(60.0, 140.0), Rg.range(0.2, 0.4), C[6], 0.7)
	# the runes go out one by one, each in a little puff of glints
	for k in NRUNE:
		if not out[k] and t >= runeOut(k):
			out[k] = true
			var g := runeAngle(k)
			var x := cos(g) * RR
			var y := sin(g) * RR * SY - 5.0
			for i in 4:
				ps.spawn(P.STAR, x + Rg.range(-2.0, 2.0), y + Rg.range(-2.0, 2.0), Rg.range(-14.0, 14.0), -Rg.range(10.0, 40.0), Rg.range(0.3, 0.55), Rg.pick([WHITE, C[6]]), Rg.range(0.6, 1.6))
	ps.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	var lvl := level(t)
	if t < GONE:
		var k := lvl * Px.smooth(PEN[0], PEN[1] + 0.2, t)
		p.glow(0.0, 0.0, R * 1.3, C[4], 0.28 * k)
		for s in [-1.0, 1.0]:
			p.glow(s * R * 0.6, 1.0, R * 0.7, C[5], 0.12 * k)
	shock(p, true)
	circle(p, true)
	runes(p, true)
	column(p)
	ps.draw(p, "back")


func draw(p: Px.Painter) -> void:
	shock(p, false)
	circle(p, false)
	runes(p, false)
	# the pens: white points running round, writing light
	var pen := func(x: float, y: float) -> void:
		Px.sparkle(p, x, y, 2.0, C[6], C[5], 0.5)
		p.glow(x, y, 7.0, C[6], 0.45)
	if t > PEN[0] and t < PEN[1]:
		for s in [-1.0, 1.0]:
			var g: float = PI / 2.0 + s * ((t - PEN[0]) / (PEN[1] - PEN[0])) * PI
			pen.call(cos(g) * R, sin(g) * R * SY)
	if t > INNER[0] and t < INNER[1]:
		var g: float = -PI / 2.0 + ((t - INNER[0]) / (INNER[1] - INNER[0])) * TAU
		pen.call(cos(g) * RI, sin(g) * RI * SY)
	for e: Dictionary in edges:
		if t > e.t0 and t < e.t0 + e.dur:
			var s: float = (t - e.t0) / e.dur
			pen.call(e.p0[0] + (e.p1[0] - e.p0[0]) * s, (e.p0[1] + (e.p1[1] - e.p0[1]) * s) * SY)
	# the flash
	if t >= FLASH and t < FLASH + 0.24:
		var a := (t - FLASH) / 0.24
		Px.flare(p, 0.0, -8.0, 34.0 * pow(1.0 - a, 1.5), 1.0 - a, C)
		p.glow(0.0, -26.0, 56.0, WHITE, 0.5 * (1.0 - a))
	ps.draw(p, "front")
	lights.draw(p)
