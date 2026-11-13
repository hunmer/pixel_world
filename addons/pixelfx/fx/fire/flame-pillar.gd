# The flame-puff, smoke, spark, debris and floor-ring recipe is adapted from Sprite Fusion's open-source explosion
# (https://www.spritefusion.com/pixel-art-vfx/explosion), and the column's levels, pulses and strands from its
# holy light (https://www.spritefusion.com/pixel-art-vfx/holy-light), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/fire/flame-pillar.js@c840c42a7a29e1e7fa7816fe44b6d24a91e3e22f
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const PF := Px.PF
const B := Px.B
const WHITE := Px.WHITE
const LAYERS := Lib.LAYERS

static var meta := {
	"name": "Flame pillar",
	"desc": "The floor cracks and glows, a column of fire erupts white-hot and roars, spewing embers and shedding flame, then collapses into rolling smoke.",
	"tags": ["fire", "pillar", "eruption", "spell", "ground", "one-shot"],
	"size": [184, 256],
	"origin": [92, 232],
	"duration": 5,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"options": {
		"palette": ["#4a1712", "#8a1f17", "#c9281f", "#f2561d", "#ff8a2a", "#ffc23d", "#ffe26b", "#fff3a6", "#ffffff"],
		"stone": "#4a3f69",
		"height": 140,
		"seed": 5,
	},
}

const ERUPT := 0.55
const RISE := 0.12
const FALL := 1.95
const GONE := 2.45
static var SOOT := Px.hex("#0d0a12")
static var OUTLINE := Px.hex("#1a1422")
static var WARM := Px.rgb(255, 176, 96)


static func stone(c: Variant) -> Dictionary:
	var cc := Px.hex(c)
	return {"light": Px.mix(Px.scale(cc, 1.35), WHITE, 0.08), "body": cc, "shade": Px.scale(cc, 0.64), "dust": Px.mix(Px.scale(cc, 1.2), Px.rgb(150, 140, 150), 0.3)}


static func rock(p: Px.Painter, b: Dictionary, st: Dictionary) -> void:
	var r: float = 0.6 + b.s * 0.75
	var fade := minf(1.0, b.life / 0.5)
	var lx: float = cos(b.a) * r * 0.4
	var ly: float = sin(b.a) * r * 0.4
	p.shade(b.x - r - 1.0, b.y - r - 1.0, b.x + r + 1.0, b.y + r + 1.0, func(x, y, out):
		var dx: float = x - b.x
		var dy: float = y - b.y
		var d := Px.hypot(dx * 1.15, dy)
		if d > r + 0.9:
			return
		var lit := dx * lx + dy * ly
		out.c = OUTLINE if d > r else (st.light if lit < -0.4 else (st.shade if lit > 0.6 else st.body))
		out.a = fade)


var H: Array
var HMAX: float
var st: Dictionary
var R: Px.Rng
var ps: Px.Particles
var bits: Px.Bits
var lights: Px.Lights
var GLOW: int
var S: float
var cracks := []
var strands: Array
var t := 0.0
var erupted := false
var fell := false


# the cracks: jagged lines racing out from the middle across the floor (squashed for perspective), with branches
func crack(x: float, y: float, a: float, len: float, t0: float, w: float) -> Array:
	var pts := [[x, y]]
	var d := 0.0
	while d < len:
		a += R.range(-0.55, 0.55)
		x += cos(a) * 2.0
		y += sin(a) * 0.76
		pts.append([x, y])
		d += 2.0
	cracks.append({"pts": pts, "t0": t0, "grow": R.range(0.22, 0.36), "w": w})
	return pts


func height(tt: float) -> float:
	return 0.0 if tt < ERUPT else (HMAX * Px.Ease.outCubic((tt - ERUPT) / RISE) if tt < ERUPT + RISE else (HMAX * (1.0 + 0.05 * Px.noise(tt * 3.0, S)) if tt < FALL else HMAX * (1.0 - Px.Ease.inQuad(Px.clamp((tt - FALL) / (GONE - FALL))))))


func width(tt: float) -> float:
	return 0.0 if tt < ERUPT else (12.0 * (1.0 + 0.45 * exp(-(tt - ERUPT) * 7.0)) * (0.94 + 0.06 * Px.noise(tt * 9.0, S + 1.0)) if tt < FALL else 12.0 * (1.0 - Px.smooth(FALL, GONE, tt)) + 1.5 * (1.0 - Px.smooth(GONE - 0.1, GONE, tt)))


func heat(tt: float) -> float:
	return Px.smooth(0.0, ERUPT, tt) * 0.75 + 0.25 * Px.smooth(ERUPT - 0.05, ERUPT + 0.1, tt) - Px.smooth(GONE - 0.3, meta.duration - 0.6, tt) * 1.05


func create(o: Dictionary) -> void:
	var F := Px.fit(o.palette, 9)
	H = Lib.hotFirst(F)
	HMAX = o.height
	st = stone(o.stone)
	R = Px.Rng.new(o.seed)
	var floor_ := func(): return 0.0
	ps = Px.Particles.new({"rng": R, "ground": floor_, "sparks": [H[1], H[2], H[4], H[5]]})
	bits = Px.Bits.new({"ground": floor_})
	lights = Px.Lights.new()
	GLOW = Px.mix(Px.mix(H[3], H[4], 0.5), WHITE, 0.25)
	S = o.seed * 13.0
	for i in 9:
		var a := (i / 9.0) * TAU + R.range(-0.25, 0.25)
		var pts := crack(R.range(-1.0, 1.0), R.range(-0.3, 0.3), a, R.range(20.0, 40.0), R.range(0.0, 0.16), 1.0)
		var j := 3 + R.int_(0, pts.size() - 6)
		if pts.size() > 8:
			crack(pts[j][0], pts[j][1], a + R.sign() * R.range(0.5, 1.0), R.range(6.0, 14.0), 0.18 + R.range(0.0, 0.15), 0.0)
	# strands of hotter flame running up the column
	strands = Px.arr(7, func(i): return {"o": (Px.rand(i, S, 1) - 0.5) * 1.4, "w": 0.05 + Px.rand(i, S, 2) * 0.06, "f": 1.0 + Px.rand(i, S, 3) * 2.0})


func column(p: Px.Painter) -> void:
	var h := height(t)
	var w0 := width(t)
	if h < 1.0 or w0 < 0.3:
		return
	# a crown of tongues where the column breaks into the air, drawn first so the column flows up into them
	if t < FALL + 0.25:
		var k := Px.clamp(w0 / 12.0)
		var NZ := func(rate: float, seed: Variant, off: float) -> float: return Px.noise(t * rate + off, seed)
		for i in 5:
			var n := (S + i) * 17.0
			var dx := (i - 2) * w0 * 0.4
			var th := (12.0 + 12.0 * (0.5 + 0.5 * Px.noise(t * 3.3 + i, n))) * k * (1.2 if i == 2 else (0.6 if i % 4 == 0 else 0.9))
			Lib.flameTongue(p, dx + Px.noise(t * 2.0, n + 2.0) * 1.5, -h + 12.0, th, 3.4 * k * (0.7 if i % 4 == 0 else 1.0), -dx * 0.3 + Px.noise(t * 2.2, n + 1.0) * 3.0, NZ, n, H, LAYERS)
	var lvlC := [H[0], H[1], H[2], H[3], H[4], H[5], H[6], H[7]]
	var y := 0
	while y >= -h:
		var v := -y / h
		var cx := Px.noise(-y * 0.04 + t * 1.6, S + 2.0) * 1.6 * v
		# licks bulge out of the sides and run up them; a wider splash at the foot; the top thins into tongues
		var foot := 1.0 + 0.7 * pow(maxf(0.0, 1.0 - -y / 12.0), 2.0)
		var top := 1.0 - Px.smooth(0.82, 1.0, v) * 0.7
		var wl := w0 * foot * top * (1.0 + 0.65 * pow(maxf(0.0, Px.noise(y * 0.2 + t * 8.0, S + 3.0)), 1.5))
		var wr := w0 * foot * top * (1.0 + 0.65 * pow(maxf(0.0, Px.noise(y * 0.2 + t * 8.0, S + 4.0)), 1.5))
		var pulse := 1 if fmod(-y * 0.032 + t * 3.6, 1.0) < 0.09 else 0
		for xi in range(int(floorf(cx - wl * 1.15)), int(ceilf(cx + wr * 1.15)) + 1):
			var dx := xi + 0.5 - cx
			var q := absf(dx) / (wl if dx < 0.0 else wr)
			if q > 1.15:
				continue
			var lvl := 0 if q < 0.12 else (1 if q < 0.26 else (2 if q < 0.42 else (3 if q < 0.56 else (4 if q < 0.7 else (5 if q < 0.84 else (6 if q < 0.96 else 7))))))
			for s: Dictionary in strands:
				if absf(dx / w0 - s.o - 0.06 * sin(t * s.f * 3.0 + s.o * 9.0)) < s.w:
					lvl = maxi(0, lvl - 1)
			lvl = maxi(0, lvl - pulse)
			if lvl == 7 and Px.rand(xi, y, floorf(t * 20.0)) < 0.5:
				continue
			p.px(xi, y, lvlC[lvl])
		if y % 12 == 0:
			p.glow(cx, y, w0 * 2.4 + 8.0, GLOW, 0.28 * Px.clamp(w0 / 12.0))
		y -= 1
	p.glow(0.0, -h * 0.45, 92.0, GLOW, 0.3 * Px.clamp(w0 / 12.0))


func cracksDraw(p: Px.Painter) -> void:
	var k := heat(t)
	if k <= -0.05:
		return
	for c: Dictionary in cracks:
		var pts: Array = c.pts
		var n := floori(pts.size() * Px.clamp((t - c.t0) / c.grow))
		for i in range(1, n):
			var u := float(i) / pts.size()
			var hot := k * (1.0 - 0.45 * u)
			var x0: float = pts[i - 1][0]
			var y0: float = pts[i - 1][1]
			var x1: float = pts[i][0]
			var y1: float = pts[i][1]
			if hot < 0.0:
				# cooled: soot that fades away
				var a := 1.0 + hot * 3.0
				if a > 0.0:
					p.line(x0, y0, x1, y1, SOOT, a)
				continue
			var col: int = H[1] if hot > 0.85 else (H[2] if hot > 0.65 else (H[4] if hot > 0.45 else (H[5] if hot > 0.25 else (H[6] if hot > 0.1 else H[7]))))
			# the crack: a hot seam with a darker glowing lip, wider near the middle
			if c.w and i < pts.size() * 0.5 and hot > 0.2:
				p.line(x0, y0 + 1.0, x1, y1 + 1.0, H[5] if hot > 0.6 else H[6])
				p.line(x0, y0 - 1.0, x1, y1 - 1.0, H[7])
			p.line(x0, y0, x1, y1, col)
			if i % 2 == 0:
				p.glow(x1, y1, 5.0 + 7.0 * hot, GLOW, 0.3 * hot)
	# the floor glows from beneath while it's hot
	if k > 0.0:
		Lib.floorLight(p, 0.0, 0.5, 44.0, 8.0, GLOW, 0.35 * k)


func update(dt: float) -> void:
	t += dt
	# the charge: the crust in the middle glows, little flames lick out of it, heat leaks up the cracks
	if t < ERUPT and R.chance(0.6 * dt * 60.0 * Px.smooth(0.15, ERUPT, t)):
		ps.spawn(P.FIRE, R.range(-5.0, 5.0), -1.0, R.range(-6.0, 6.0), -R.range(20.0, 45.0), R.range(0.15, 0.3), 0, R.range(1.0, 2.2))
	if t < ERUPT and R.chance(0.5 * dt * 60.0 * Px.smooth(0.0, ERUPT, t)):
		var c: Dictionary = R.pick(cracks)
		var i := R.int_(0, floori(c.pts.size() * Px.clamp((t - c.t0) / c.grow)) - 1)
		if i >= 0:
			var x: float = c.pts[i][0]
			var y: float = c.pts[i][1]
			if R.chance(0.5):
				ps.spawn(P.FIRE, x, y - 1.0, R.range(-5.0, 5.0), -R.range(15.0, 35.0), R.range(0.15, 0.3), 0, R.range(0.8, 1.6))
			else:
				ps.spawn(P.EMBER, x, y - 1.0, R.range(-15.0, 15.0), -R.range(30.0, 70.0), R.range(0.5, 1.0), H[3], 1.0)
	if not erupted and t >= ERUPT:
		erupted = true
		lights.add(0.0, -40.0, 90.0, WARM, 0.7, 0.6)
		lights.add(0.0, -8.0, 44.0, WHITE, 0.7, 0.1)
		for i in 70:
			var a := -PI / 2.0 + R.range(-1.1, 1.1)
			var sp := R.range(100.0, 260.0)
			ps.spawn(P.SPARK, R.range(-4.0, 4.0), -2.0, cos(a) * sp, sin(a) * sp, R.range(0.25, 0.7))
		for i in 18:
			bits.add({"kind": B.CHUNK, "x": R.range(-6.0, 6.0), "y": -2.0, "vx": R.range(-110.0, 110.0), "vy": -R.range(150.0, 330.0), "g": 1.0, "drag": 0.4, "bounce": 0.3, "life": R.range(1.6, 2.4), "a": R.range(0.0, TAU), "va": R.range(-16.0, 16.0), "s": R.int_(1, 3)})
		for i in 60:
			var a := -PI / 2.0 + R.range(-0.9, 0.9)
			var sp := R.range(80.0, 260.0)
			ps.spawn(P.GRIT, R.range(-5.0, 5.0), -1.0, cos(a) * sp, sin(a) * sp, R.range(1.0, 1.8), R.pick([st.light, st.body, st.body, st.shade]), 2.0 if R.chance(0.4) else 1.0)
		for i in 14:
			var s := R.sign()
			ps.spawn(P.SMOKE, s * R.range(2.0, 10.0), -R.range(1.0, 4.0), s * R.range(40.0, 110.0), -R.range(2.0, 10.0), R.range(1.0, 1.8), st.dust, R.range(4.0, 7.0), R.range(0.0, 0.06), PF.BIG)
	# the roar: flame shed off the sides, a billowing cap, embers spewed high
	var h := height(t)
	var w := width(t)
	if t > ERUPT and t < GONE and h > 4.0:
		if R.chance(0.9 * dt * 60.0):
			var s := R.sign()
			var y := -R.range(4.0, h * 0.9)
			ps.spawn(P.FIRE, s * w * R.range(0.7, 1.1), y, s * R.range(15.0, 40.0), -R.range(30.0, 70.0), R.range(0.25, 0.5), 0, R.range(1.6, 3.2), 0.0, PF.SMOKES if R.chance(0.35) else 0)
		if R.chance(0.7 * dt * 60.0):
			ps.spawn(P.FIRE, R.range(-w, w), -h + R.range(0.0, 6.0), R.range(-20.0, 20.0), -R.range(30.0, 80.0), R.range(0.35, 0.7), 0, R.range(3.0, 5.5), 0.0, (PF.SMOKES | (PF.BIG if t < FALL - 0.3 else 0)) if R.chance(0.6) else 0)
		if t < FALL and R.chance(0.5 * dt * 60.0):
			ps.spawn(P.EMBER, R.range(-w, w) * 0.6, -h + 4.0, R.range(-60.0, 60.0), -R.range(50.0, 110.0), R.range(0.7, 1.3), H[3], 2.0 if R.chance(0.2) else 1.0)
	# the collapse: the falling top breaks into puffs that roll off as smoke
	if t >= FALL and not fell:
		fell = true
	if fell and t < GONE - 0.1 and R.chance(1.6 * dt * 60.0):
		ps.spawn(P.FIRE, R.range(-w - 2.0, w + 2.0), -h - R.range(0.0, 8.0), R.range(-30.0, 30.0), -R.range(10.0, 50.0), R.range(0.4, 0.75), 0, R.range(3.5, 6.5), 0.0, PF.SMOKES)
	bits.update(dt)
	for b: Dictionary in bits.list:
		if b.rest and not b.get("dusted", false):
			b.dusted = true
			for i in 3:
				ps.spawn(P.DUST, b.x + R.range(-1.5, 1.5), -0.5, R.sign() * R.range(8.0, 35.0), -R.range(2.0, 18.0), R.range(0.3, 0.6), st.dust, R.range(1.3, 2.6))
	ps.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	cracksDraw(p)
	Lib.simDraw(p, ps, H, "back")
	var k := (t - ERUPT) / 0.45
	if k > 0.0 and k < 1.0:
		Px.band(p, 0.0, 0.5, 84.0 * Px.Ease.outCubic(k), 0.18, maxf(1.0, 4.0 * (1.0 - k)), 1.15 - k, [st.body, st.light, H[4], H[1]], func(g): return sin(g) < 0.0)


func draw(p: Px.Painter) -> void:
	column(p)
	for b: Dictionary in bits.list:
		rock(p, b, st)
	Lib.simDraw(p, ps, H, "front")
	var k := (t - ERUPT) / 0.45
	if k > 0.0 and k < 1.0:
		Px.band(p, 0.0, 0.5, 84.0 * Px.Ease.outCubic(k), 0.18, maxf(1.0, 4.0 * (1.0 - k)), 1.15 - k, [st.body, st.light, H[4], H[1]], func(g): return sin(g) >= 0.0, k < 0.15)
	# the eruption's white flash at the foot
	var f := (t - ERUPT) / 0.08
	if f > 0.0 and f < 1.0:
		p.ellipse(0.0, -2.0, 16.0 * (1.0 - f * 0.3), 6.0, H[2])
		p.ellipse(0.0, -3.0, 11.0 * (1.0 - f * 0.3), 4.0, WHITE if f < 0.5 else H[1])
	lights.draw(p)
