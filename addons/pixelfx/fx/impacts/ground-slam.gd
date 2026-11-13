# The rocks, grit, rolling floor dust and dust column are adapted from Sprite Fusion's open-source explosion
# (https://www.spritefusion.com/pixel-art-vfx/explosion), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/impacts/ground-slam.js@880a0bc93a5926649f3aa5184c71a306afc271b8
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const PF := Px.PF
const B := Px.B
const WHITE := Px.WHITE

static var meta := {
	"name": "Ground slam",
	"desc": "Something lands hard: the floor flashes and cracks, two crescent shock waves race out along it, a dust wave and a tall dust cloud rise, rocks erupt, bounce and settle.",
	"tags": ["impact", "ground", "slam", "shockwave", "quake", "rocks", "dust", "one-shot"],
	"size": [288, 208],
	"origin": [144, 164],
	"duration": 3.2,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": ["#2a1712", "#5e2c1c", "#a4502a", "#e8893a", "#ffc764", "#fff0b4", "#ffffff"], "stone": "#4a3f69", "reach": 104, "seed": 5},
}

const WAVE := 0.6 # seconds for the shock fronts to run out


# the dent: the floor's edge caves into a shallow dish, its bottom glowing while hot, lips thrown up either side
static func crater(p: Px.Painter, st: Dictionary, hot: float, C: Array, k: float) -> void:
	for x in range(-12, 12):
		var q := absf(x + 0.5) / 12.0
		var dep := Px.round(2.6 * (1.0 - q * q))
		if q < 0.84:
			var y := 0.0
			while y < dep:
				p.dot(x, y, Lib.SOOT, k)
				y += 1.0
			p.dot(x, dep, C[5] if hot > 0.5 else (C[4] if hot > 0.2 else st.lip), k)
		else:
			p.dot(x, -1.0, st.light if q > 0.93 else st.lip, k)
			if q < 0.9:
				p.dot(x, -2.0, st.light, k * 0.8)


var C: Array
var st: Dictionary
var REACH: float
var R: Px.Rng
var D: float
var ps: Px.Particles
var bits: Px.Bits
var lights: Px.Lights
var HOT: Array
var dustLit: int
var cracks: Array
var burst: Array
var embers: Array
var t := 0.0
var acc: Array


func front(tt: float) -> float:
	return 7.0 + (REACH - 7.0) * Px.Ease.outCubic(Px.clamp((tt - 0.015) / WAVE))


static func heat(tt: float) -> float:
	return pow(Px.clamp(1.0 - tt / 0.8), 1.4)


# a front's height and thickness
static func crest(u: float) -> Array:
	return [6.0 + 28.0 * pow(1.0 - u, 0.75), 1.5 + 5.0 * pow(1.0 - u, 0.9)]


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 7)
	st = Lib.stone(o.stone)
	REACH = o.reach
	R = Px.Rng.new(o.seed)
	var floor_ := func(): return 0.0
	D = meta.duration
	ps = Px.Particles.new({"rng": R, "ground": floor_, "sparks": [C[6], C[5], C[4], C[3]]})
	bits = Px.Bits.new({"ground": floor_})
	lights = Px.Lights.new()
	HOT = [WHITE, C[5], C[4], C[3]]
	dustLit = Px.mix(st.dust, WHITE, 0.2)
	cracks = Lib.makeCracks(R, 10, {"len": [22.0, 58.0], "dive": 0.55, "maxY": 22.0, "forks": 0.7, "x0": [2.0, 9.0]})
	# the flash: a flat half-star hugging the floor, long rays along it, short ones up
	burst = [
		{"a": -0.07, "len": R.range(34.0, 40.0), "w": 1.9}, {"a": PI + 0.07, "len": R.range(34.0, 40.0), "w": 1.9},
		{"a": -0.42 + R.range(-0.08, 0.08), "len": R.range(15.0, 20.0), "w": 1.5}, {"a": -PI + 0.42 + R.range(-0.08, 0.08), "len": R.range(15.0, 20.0), "w": 1.5},
		{"a": -PI / 2.0 + R.range(-0.15, 0.15), "len": R.range(18.0, 24.0), "w": 1.7},
		{"a": -1.05 + R.range(-0.1, 0.1), "len": R.range(10.0, 14.0), "w": 1.2}, {"a": -PI + 1.05 + R.range(-0.1, 0.1), "len": R.range(10.0, 14.0), "w": 1.2},
	]
	# embers caught in the cracks, flickering as they cool
	embers = []
	for c: Dictionary in cracks:
		for pt: Array in c.pts:
			var x: float = pt[0]
			var y: float = pt[1]
			var d: float = pt[2]
			if d > 3.0 and d < 32.0 and R.chance(0.25):
				embers.append({"x": x, "y": y, "d": d, "life": R.range(0.8, 2.2), "ph": R.range(0.0, TAU)})

	# contact: light floods out, sparks fly off the stone and skitter along the floor
	lights.add(0.0, -12.0, 96.0, C[4], 0.6, 0.6)
	lights.add(0.0, -4.0, 50.0, WHITE, 0.9, 0.14)
	for i in 56:
		var low := i < 14
		var s := R.sign()
		var a := ((-R.range(0.04, 0.6) if s > 0 else PI + R.range(0.04, 0.6)) if low else -PI / 2.0 + R.range(-1.15, 1.15))
		var sp := R.range(150.0, 380.0) if low else R.range(200.0, 500.0)
		ps.spawn(P.SPARK, R.range(-4.0, 4.0), -1.0, cos(a) * sp, sin(a) * sp, R.range(0.2, 0.5) if low else R.range(0.25, 0.65), WHITE, 1.0, 0.0 if low else R.range(0.0, 0.05))
	# rocks erupt from the dent: three heavy ones that barely clear it, the rest thrown high
	for i in 20:
		var s := 4 if i < 3 else R.int_(1, 3)
		var a := -PI / 2.0 + R.range(-0.5, 0.5)
		var sp := R.range(110.0, 190.0) if s > 3 else R.range(170.0, 380.0) * (0.8 if s > 2 else 1.0)
		bits.add({"kind": B.CHUNK, "x": R.range(-7.0, 7.0), "y": -2.0, "vx": cos(a) * sp, "vy": sin(a) * sp, "g": 1.0, "drag": 0.4, "bounce": 0.38, "life": R.range(1.9, 2.7), "a": R.range(0.0, TAU), "va": R.range(-14.0, 14.0), "s": float(s), "pts": Lib.rockShape(R), "pvy": 0.0})
	# grit: a fan of floor bits that bounce once and settle
	for i in 110:
		var u := R.range(-1.0, 1.0)
		var a := -PI / 2.0 + u * 0.65
		var sp := R.range(110.0, 380.0) * (1.0 - 0.35 * absf(u))
		ps.spawn(P.GRIT, u * 6.0, -1.0, cos(a) * sp, sin(a) * sp, R.range(1.0, 2.2), R.pick([st.light, st.body, st.body, st.shade, st.shade, st.lip]), 2.0 if R.chance(0.35) else 1.0)
	# the dust cloud: a column that shoots up and spreads at the top, lit on top, and a heavy bank at its foot
	for i in 28:
		var core := i < 14
		var s := R.sign()
		ps.spawn(P.SMOKE, R.range(-5.0, 5.0) if core else s * R.range(4.0, 12.0), -R.range(2.0, 10.0), R.range(-12.0, 12.0) if core else s * R.range(14.0, 38.0), -R.range(50.0, 130.0) * (1.0 if core else R.range(0.3, 0.6)), R.range(1.9, 2.7), dustLit if R.chance(0.35) else st.dust, R.range(4.5, 9.0) if core else R.range(4.0, 7.5), R.range(0.02, 0.22), PF.BIG)
	for i in 10:
		var s := R.sign()
		ps.spawn(P.SMOKE, s * R.range(2.0, 14.0), -R.range(2.0, 6.0), s * R.range(20.0, 70.0), -R.range(4.0, 20.0), R.range(1.4, 2.3), st.dust, R.range(6.0, 9.0), R.range(0.0, 0.08), PF.BIG)
	# fine dust settling out of the cloud while it hangs
	for i in 26:
		ps.spawn(P.FLAKE, R.range(-22.0, 22.0), -R.range(14.0, 80.0), R.range(-12.0, 12.0), R.range(-10.0, 4.0), R.range(1.2, 2.0), st.lip if R.chance(0.5) else dustLit, R.range(0.5, 1.2), R.range(0.25, 1.0))

	acc = [R.next(), R.next()]


func ring(p: Px.Painter, back: bool) -> void:
	var u := Px.clamp((t - 0.015) / (WAVE + 0.1))
	if t < 0.015 or u >= 0.9:
		return
	Px.band(p, 0.0, 0.5, front(t) + 1.0, 0.16, maxf(1.0, 4.0 * pow(1.0 - u, 0.8)), 1.1 if u < 0.55 else (0.9 - u) / 0.35,
		[C[3], C[4], C[5], C[6]] if u < 0.35 else [st.body, st.light, C[4], C[5]], func(g): return (sin(g) < 0.0) == back, t < 0.09)


func fronts(p: Px.Painter) -> void:
	var u := Px.clamp((t - 0.03) / (WAVE + 0.16))
	if t < 0.03 or u >= 1.0:
		return
	var fr := front(t)
	var hw := crest(u)
	var h: float = hw[0]
	var w: float = hw[1]
	var k := 1.0 if u < 0.7 else (1.0 - u) / 0.3
	var cols: Array = [WHITE, C[6], C[5]] if u < 0.14 else ([C[6], C[5], C[4]] if u < 0.34 else ([C[5], C[4], st.lip] if u < 0.55 else [st.lip, st.light, st.dust]))
	for s: float in [-1.0, 1.0]:
		Lib.frontCrescent(p, s * fr, s, h, w, cols, k)
		p.glow(s * fr, -h * 0.3, 8.0 + h * 0.7, C[4], 0.5 * (1.0 - u) * k)


func update(dt: float) -> void:
	t += dt
	# dust kicked up behind the racing fronts, and spray off their crests
	var u := Px.clamp((t - 0.015) / WAVE)
	if u > 0.0 and u < 1.0:
		var fr := front(t)
		var h: float = crest(u)[0]
		for k in 2:
			var s := 1.0 if k else -1.0
			acc[k] += dt * 120.0 * (1.0 - u * 0.7)
			while acc[k] > 1.0:
				ps.spawn(P.SMOKE, s * (fr - R.range(1.0, 7.0)), -R.range(0.5, 3.0), s * R.range(15.0, 70.0) * (1.0 - u), -R.range(2.0, 12.0), R.range(1.0, 2.1), dustLit if R.chance(0.3) else st.dust, R.range(2.5, 6.5) * (1.0 - 0.4 * u), 0.0, PF.BIG)
				if R.chance(0.5):
					ps.spawn(P.DUST, s * (fr - R.range(0.0, 3.0)), -R.range(0.3, 0.9) * h, s * R.range(-15.0, 25.0), -R.range(8.0, 35.0), R.range(0.3, 0.6), dustLit if R.chance(0.5) else st.dust, R.range(1.2, 2.4))
				if R.chance(0.4):
					ps.spawn(P.GRIT, s * fr, -1.0, s * R.range(10.0, 60.0), -R.range(40.0, 140.0) * (1.0 - u), R.range(0.5, 1.0), R.pick([st.light, st.body, st.lip]), 1.0)
				if u < 0.45 and R.chance(0.2):
					ps.spawn(P.SPARK, s * fr, -1.0, s * R.range(60.0, 200.0), -R.range(30.0, 160.0), R.range(0.12, 0.3))
				acc[k] -= 1.0
	for b: Dictionary in bits.list:
		b.pvy = b.vy
	bits.update(dt)
	# rocks that land hard kick up dust
	for b: Dictionary in bits.list:
		if b.pvy > 70.0 and b.vy <= 0.0:
			var n := 3 if b.pvy > 200.0 else 2
			for i in n:
				ps.spawn(P.DUST, b.x + R.range(-1.5, 1.5), -0.5, R.sign() * R.range(8.0, 35.0), -R.range(2.0, 16.0), R.range(0.3, 0.65), st.dust, R.range(1.3, 2.4) * (0.7 + b.s * 0.25))
			b.pvy = 0.0
	ps.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	var fade := 1.0 - Px.smooth(D - 0.9, D - 0.15, t)
	var H := heat(t)
	if t > 0.02:
		crater(p, st, H, C, fade)
	Lib.drawCracks(p, cracks, func(c): return c.len * Px.Ease.outCubic(Px.clamp((t - c.t0) / 0.1)), func(d): return H * Px.clamp(1.2 - d / 40.0), HOT, Lib.SOOT, st.light, fade)
	for e: Dictionary in embers:
		var k: float = 1.0 - (t - 0.1) / e.life
		if t < 0.1 or k <= 0.0:
			continue
		var f: float = 0.6 + 0.4 * sin(t * 23.0 + e.ph)
		p.px(e.x, e.y, C[5] if k * f > 0.55 else (C[4] if k * f > 0.25 else C[3]))
		p.glow(e.x, e.y, 4.0, C[4], 0.35 * k * f)
	ring(p, true)
	ps.draw(p, "back")


func draw(p: Px.Painter) -> void:
	ring(p, false)
	fronts(p)
	for b: Dictionary in bits.list:
		Lib.rock(p, b, st)
	ps.draw(p, "front")
	if t < 0.035:
		p.ellipse(0.0, 0.0, 30.0, 4.5, func(d): return C[4] if d > 0.8 else (C[6] if d > 0.5 else WHITE))
		Lib.star(p, 0.0, -1.0, burst, 1.0, 1.0, [C[4], C[6], WHITE, WHITE])
	elif t < 0.07:
		Lib.star(p, 0.0, -1.0, burst, 1.25, 0.5, [C[3], C[5], C[6], WHITE])
	# the floor flashes along its length, then the dent glows while the cracks are hot
	if t < 0.14:
		p.glowLine(-80.0, 0.0, 80.0, 0.0, 10.0, C[5], 0.55 * (1.0 - t / 0.14))
	var H := heat(t)
	if H > 0.0:
		p.glow(0.0, 1.0, 46.0, C[4], 0.35 * H)
	lights.draw(p)
