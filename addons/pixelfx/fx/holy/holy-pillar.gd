# port-of: src/fx/holy/holy-pillar.js@0bb153e1bc9959fcbc492c18cf6689260bff39db
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Holy pillar",
	"desc": "Light breaks through from above: a sun opens at the top and a fan of shafts converges on the mark, pulsing, while a sigil burns on the floor; then the fan folds shut.",
	"tags": ["holy", "pillar", "light", "rays", "aoe", "sigil", "ground", "one-shot"],
	"size": [192, 232],
	"origin": [96, 204],
	"duration": 3.5,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": Lib.GOLD, "shafts": 7, "seed": 3},
}

const TOP := -204.0
const PY := -1.0
const SUN := TOP + 38.0
const SY := 0.24
const RX := 26.0
# the sun opens, the fan unfolds and pours down, it holds and pulses, folds shut, the light lifts away
const OPEN := 0.3
const HIT := 0.66
const FOLD := 2.05
const SHUT := 2.45
const LIFT := 2.75

static func frac(x: float) -> float:
	return x - floorf(x)


var C: Array
var N: int
var R: Px.Rng
var mid: float
var WING: Array
var ps: Px.Particles
var lights: Px.Lights
var feathers: Lib.Feathers
var shafts: Array
var motes: Array
var DMAX := PY - TOP
var row := PackedFloat32Array()
var core := PackedByteArray()
var t := 0.0
var hit := false
var shut := false
var glinted := false


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	N = maxi(3, Px.i32(o.shafts))
	R = Px.Rng.new(o.seed)
	mid = (N - 1) / 2.0
	WING = [C[2], C[3], C[4], C[5], C[6], WHITE]
	ps = Px.Particles.new({"rng": R, "ground": func(): return 0.0, "sparks": [WHITE, C[6], C[5], C[3]]})
	lights = Px.Lights.new()
	feathers = Lib.Feathers.new(R, 0.0)
	# the shafts: spread angle, how fast each widens, how bright, its pulse offset
	shafts = Px.arr(N, func(i: int):
		var off := i - mid
		var far := absf(off) / mid
		return {"th": off * (0.4 / mid) + R.range(-0.02, 0.02), "spread": R.range(0.05, 0.085) * (1.0 - far * 0.25), "b": (1.0 - far * 0.35) * R.range(0.8, 1.0), "ph": R.range(0.0, 1.0), "far": far})
	motes = Px.arr(72, func(_i): return {"x": R.range(-80.0, 80.0), "y": R.range(0.0, 1.0), "v": R.range(7.0, 18.0), "amp": R.range(0.5, 2.5), "f": R.range(0.6, 1.5), "ph": R.range(0.0, TAU)})
	for i in 6:
		feathers.add({"x": R.range(-46.0, 46.0), "y": R.range(-150.0, -100.0), "vx": R.range(-8.0, 8.0), "vy": R.range(0.0, 8.0), "a": R.range(-0.4, 0.4), "len": R.range(7.0, 9.0), "wid": R.range(1.9, 2.3), "life": R.range(1.4, 1.7), "sink": R.range(26.0, 36.0), "back": i % 3 == 0, "delay": HIT + 0.1 + i * 0.16 + R.range(0.0, 0.08)})
	DMAX = PY - TOP
	row = PackedFloat32Array()
	row.resize(192)
	core = PackedByteArray()
	core.resize(192)


# each shaft's angle now: unfolding from the middle with an overshoot, folding back shut at the end
func angle(s: Dictionary, tt: float) -> float:
	var st: float = s.far * 0.1
	var open := Px.Ease.outBack(Px.seg(tt, OPEN + st, OPEN + st + 0.42), 1.5)
	var fold := Px.Ease.inOutCubic(Px.seg(tt, FOLD - s.far * 0.1, SHUT))
	return s.th * open * (1.0 - fold)


# how far down each shaft the light reaches (it pours from the sky), and where it lifts away at the end
func frontD(s: Dictionary, tt: float) -> float:
	return DMAX * (1.0 - Px.Ease.inQuad(Px.seg(tt, OPEN + s.far * 0.06, HIT + s.far * 0.06)))


func liftD(tt: float) -> float:
	return DMAX * Px.Ease.inQuad(Px.seg(tt, SHUT + 0.05, LIFT))


func fade(tt: float) -> float:
	return Px.smooth(OPEN, OPEN + 0.1, tt) * (1.0 - Px.smooth(LIFT - 0.05, LIFT + 0.05, tt))


func width(s: Dictionary, d: float, tt: float) -> float:
	return (1.4 + d * s.spread) * Px.lerp(1.0, 0.25, Px.smooth(SHUT, LIFT, tt))


# brightness along a shaft: a pulse of light runs down each one, one after another
func pulse(s: Dictionary, d: float, tt: float) -> float:
	if tt < HIT or tt > SHUT:
		return 1.0
	var D := DMAX * (1.0 - frac((tt - HIT) / 0.6 + s.ph))
	return 1.0 + 0.9 * exp(-(pow((d - D) / 12.0, 2.0)))


# light of all the shafts at a point (for motes)
func lightAt(x: float, y: float) -> float:
	var dy := PY - y
	if dy <= 0.0:
		return 0.0
	var I := 0.0
	for s: Dictionary in shafts:
		var a := angle(s, t)
		var d := dy / cos(a)
		var xc := tan(a) * dy
		var hw := width(s, d, t) / 2.0 / cos(a)
		if d < liftD(t) or d < frontD(s, t):
			continue
		var v := (x - xc) / hw
		if absf(v) < 1.0:
			I += (1.0 - v * v) * s.b
	return I * fade(t)


func fan(p: Px.Painter) -> void:
	var k := fade(t)
	if k <= 0.0:
		return
	var lift := liftD(t)
	var y := ceilf(TOP)
	while y < PY:
		var dy := PY - (y + 0.5)
		row.fill(0.0)
		core.fill(0)
		var any := false
		for s: Dictionary in shafts:
			var a := angle(s, t)
			var ca := cos(a)
			var d := dy / ca
			if d < lift or d < frontD(s, t) - 6.0:
				continue
			var xc := tan(a) * dy
			var hw := width(s, d, t) / 2.0 / ca
			var soft := Px.smooth(frontD(s, t) - 6.0, frontD(s, t) + 4.0, d) * Px.smooth(lift, lift + 6.0, d)
			var I0: float = s.b * pulse(s, d, t) * soft * k
			for x in range(floori(xc - hw), ceili(xc + hw) + 1):
				var v := (x + 0.5 - xc) / hw
				var i := x + 96
				if i < 0 or i >= 192 or absf(v) >= 1.0:
					continue
				row[i] += I0 * pow(1.0 - v * v, 1.3)
				any = true
			var ci := Px.roundi(xc - 0.5) + 96
			if ci >= 0 and ci < 192:
				core[ci] = int(maxf(core[ci], minf(255.0, I0 * 200.0)))
		if not any:
			y += 1.0
			continue
		for i in 192:
			var I := row[i]
			if I < 0.02:
				continue
			var x := i - 96
			p.blend(x, y, C[6], minf(0.6, I * 0.38))
			p.light(x, y, C[4], minf(0.9, I * 0.32))
			# a fine bright line runs down the middle of each shaft
			if core[i]:
				p.dot(x, y, WHITE if core[i] > 150 else C[6], minf(1.0, core[i] / 180.0))
		y += 1.0
	# where the shafts converge, the light gathers to a point
	if t > HIT - 0.05:
		p.glow(0.0, PY - 3.0, 20.0, C[5], 0.5 * k)


# the sun: a halo that opens at the top like an iris, rays ticking round it, then closes with a glint
func sun(p: Px.Painter) -> void:
	var r := 15.0 * Px.Ease.outBack(Px.seg(t, 0.02, 0.45), 1.8) * (1.0 - Px.Ease.inBack(Px.seg(t, SHUT, LIFT + 0.1), 1.5))
	if r > 0.5:
		var spin := t * 0.6
		var CC := C
		p.glow(0.0, SUN, minf(32.0, r * 3.0), C[4], 0.5)
		p.glow(0.0, SUN, r * 1.4, WHITE, 0.35)
		p.circle(0.0, SUN, r * 0.45, WHITE)
		Lib.oval(p, 0.0, SUN, r * 0.62, r * 0.62, C[6], 1.0)
		Lib.oval(p, 0.0, SUN, r, r, func(g): return WHITE if sin(g * 6.0 + spin * 4.0) > 0.5 else CC[5], 1.0)
		for j in 16:
			var g := spin + (j * TAU) / 16.0
			var l := 3.0 if j % 2 else 6.0
			p.line(cos(g) * (r + 2.0), SUN + sin(g) * (r + 2.0), cos(g) * (r + 2.0 + l), SUN + sin(g) * (r + 2.0 + l), func(u): return CC[6] if u < 0.4 else CC[4], func(u): return 1.1 - u)
	if t > LIFT and t < LIFT + 0.3:
		Px.sparkle(p, 0.0, SUN, 10.0 * (1.0 - (t - LIFT) / 0.3), WHITE, C[5], 0.6)


# the sigil burning on the floor: two rings and a turning band of marks; white-hot, then gold, then cooling
func sigil(p: Px.Painter, back: bool) -> void:
	if t < HIT:
		return
	var u := Px.seg(t, HIT, HIT + 0.2)
	var heat := 1.0 - Px.smooth(SHUT, SHUT + 0.8, t)
	var out := 1.0 - Px.smooth(SHUT + 0.4, SHUT + 1.0, t)
	if out <= 0.0:
		return
	var keep: Callable = (func(g): return sin(g) < 0.0) if back else (func(g): return sin(g) >= 0.0)
	# it burns in round from the front, both ways
	var burnt := func(g: float) -> bool: return absf(fmod(fmod(g - PI / 2.0 + PI, TAU) + TAU, TAU) - PI) <= u * PI + 0.01
	var CC := C
	var tt := t
	var col := func(g: float, hot: bool) -> int:
		if not burnt.call(g):
			return 0
		var flick := Px.rand(Px.round(g * 40.0), floorf(tt * 20.0)) < 0.18
		return WHITE if (tt < HIT + 0.08 or (flick and heat > 0.4)) else ((CC[6] if hot else CC[5]) if heat > 0.6 else (CC[4] if heat > 0.3 else (CC[3] if heat > 0.1 else CC[2])))
	Lib.oval(p, 0.0, 0.0, RX, RX * SY, func(g): return col.call(g, true), out, func(g): return keep.call(g) and burnt.call(g))
	Lib.oval(p, 0.0, 0.0, RX * 0.72, RX * 0.72 * SY, func(g): return col.call(g, false), out, func(g): return keep.call(g) and burnt.call(g))
	# marks between the rings, turning slowly
	for j in 12:
		var g := t * 0.35 + (j * TAU) / 12.0
		if not keep.call(g) or not burnt.call(g):
			continue
		var c: int = col.call(g, j % 2 == 0)
		var r0 := RX * 0.78
		var r1 := RX * (0.95 if j % 3 == 0 else 0.88)
		if c:
			p.line(cos(g) * r0, sin(g) * r0 * SY, cos(g) * r1, sin(g) * r1 * SY, c, out)
	if not back:
		for i in range(-2, 3):
			p.glow(i * RX * 0.45, -2.0, 16.0, C[4], (0.34 - absi(i) * 0.05) * out * (0.5 + 0.5 * heat))
		p.glow(0.0, -1.0, 10.0, WHITE, 0.3 * heat * out)


func update(dt: float) -> void:
	t += dt
	# light gathers to the sun as it opens
	if t < OPEN + 0.1 and R.chance(0.5):
		var a := R.range(0.0, TAU)
		var D := R.range(22.0, 34.0)
		var x := cos(a) * D
		var y := SUN + sin(a) * D
		var T := R.range(0.18, 0.28)
		var v := ((D - 10.0) * 3.0) / (exp(3.0 * T) - 1.0)
		ps.spawn(P.STREAK, x, y, (-x / D) * v, ((SUN - y) / D) * v, T, C[6] if R.chance(0.5) else C[5])
	if not hit and t >= HIT:
		hit = true
		lights.add(0.0, -30.0, 64.0, C[5], 0.85, 0.5)
		lights.add(0.0, -6.0, 30.0, WHITE, 0.8, 0.12)
		for i in 26:
			var a := -PI / 2.0 + R.range(-1.2, 1.2)
			var sp := R.range(70.0, 190.0)
			ps.spawn(P.SPARK, R.range(-3.0, 3.0), -2.0, cos(a) * sp, sin(a) * sp, R.range(0.25, 0.6))
	# while it holds: embers off the burning sigil, a few feathers drifting down through the shafts
	if t > HIT and t < SHUT + 0.1 and R.chance(0.35):
		var g := R.range(0.0, TAU)
		var r := RX * (1.0 if R.chance(0.5) else 0.72)
		ps.spawn(P.EMBER, cos(g) * r, sin(g) * r * SY - 1.0, R.range(-6.0, 6.0), -R.range(12.0, 30.0), R.range(0.5, 0.8), C[5], 1.0, 0.0, 4 if sin(g) < 0.0 else 0)
	if t > HIT and t < FOLD and R.chance(0.05):
		ps.spawn(P.STAR, R.range(-1.0, 1.0) * 40.0, -R.range(20.0, 160.0), 0.0, R.range(2.0, 8.0), R.range(0.3, 0.6), WHITE if R.chance(0.5) else C[6], R.range(0.8, 1.8))
	# the fan snaps shut on the mark: a flash where the shafts become one
	if not shut and t >= SHUT:
		shut = true
		lights.add(0.0, -60.0, 70.0, C[5], 0.7, 0.35)
		for i in 12:
			ps.spawn(P.STAR, R.range(-4.0, 4.0), -R.range(10.0, 170.0), R.range(-25.0, 25.0), R.range(-10.0, 10.0), R.range(0.4, 0.8), WHITE if R.chance(0.5) else C[6], R.range(0.8, 2.0))
	if not glinted and t >= LIFT:
		glinted = true
		lights.add(0.0, SUN, 40.0, WHITE, 0.6, 0.2)
	ps.update(dt)
	feathers.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	fan(p)
	sigil(p, true)
	feathers.draw(p, WING, "back")
	ps.draw(p, "back")


func draw(p: Px.Painter) -> void:
	sigil(p, false)
	# dust motes drifting down, lit only where a shaft catches them
	for m: Dictionary in motes:
		var y := TOP + fmod(fmod(m.y * DMAX + t * m.v, DMAX) + DMAX, DMAX)
		var x: float = m.x + sin(t * m.f + m.ph) * m.amp
		var I := lightAt(x, y)
		if I < 0.2:
			continue
		p.dot(x, y, WHITE if I > 0.7 else C[6], minf(1.0, I * 1.3))
		p.light(x, y, C[5], 0.4 * minf(1.0, I))
	sun(p)
	if t > HIT - 0.02 and t < HIT + 0.25:
		Px.sparkle(p, 0.0, PY - 2.0, 12.0 * (1.0 - (t - HIT) / 0.25), WHITE, C[5], 0.7)
	if t > SHUT and t < SHUT + 0.2:
		Px.sparkle(p, 0.0, PY - 2.0, 8.0 * (1.0 - (t - SHUT) / 0.2), WHITE, C[5], 0.5)
	feathers.draw(p, WING, "front")
	ps.draw(p, "front")
	lights.draw(p)
