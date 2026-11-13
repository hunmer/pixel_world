# The crescent and its cooling ramp are adapted from Sprite Fusion's open-source slash
# (https://www.spritefusion.com/pixel-art-vfx/slash), and the impact star, dust, grit and embers from his
# impact and explosion (https://www.spritefusion.com/pixel-art-vfx), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/melee/heavy-cleave.js@5dc5a393287494e1524774c012384187994ae26e
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const PF := Px.PF
const B := Px.B
const WHITE := Px.WHITE

static var meta := {
	"name": "Heavy cleave",
	"desc": "A glint over the head, then a thick ember arc accelerates over the top into the floor: a white slam, glowing cracks, dust rolling both ways, grit and rising embers.",
	"tags": ["melee", "slash", "cleave", "axe", "heavy", "ground", "fire", "combat", "directional", "one-shot"],
	"size": [208, 116],
	"origin": [68, 96],
	"duration": 1.9,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {
		"palette": ["#2a0c10", "#5c1414", "#a3241a", "#e0481c", "#ff8a2a", "#ffc23d", "#fff0a0", "#ffffff"],
		"stone": "#4a3f69",
		"seed": 5,
	},
}

static var REST_ := Px.merge(Px.READY, {"weapon": "greatsword", "two": true, "sa": -1, "fx": 11, "fy": -21})
static var OVER := Px.merge(REST_, {"x": -4, "crouch": 2, "lean": -2, "fx": 1, "fy": -42, "sa": -2.45, "ffx": 8, "fbx": -7})
static var FLOOR := Px.merge(REST_, {"x": 0, "crouch": 7, "lean": 6, "fx": 17, "fy": -21, "sa": 0.72, "ffx": 11, "fbx": -10, "toeB": true})
static var act := {
	"target": {"x": 66},
	"poses": [
		[-0.42, Px.merge(REST_, {"x": -4})],
		[-0.3, Px.merge(REST_, {"x": -3, "crouch": 4, "fx": 13, "fy": -29, "sa": -1.3})],
		[-0.12, Px.merge(OVER, {"crouch": 4})],
		[0.2, Px.merge(OVER, {"crouch": 3})],
		[0.27, Px.merge(REST_, {"x": -1, "y": -2, "crouch": 0, "lean": 2, "fx": 11, "fy": -42, "sa": -1.45, "ffx": 10, "ghost": 1}), "snap"],
		[0.31, Px.merge(REST_, {"x": 0, "y": -1, "crouch": 3, "lean": 4, "fx": 18, "fy": -33, "sa": -0.45, "ffx": 12, "ghost": 1}), "snap"],
		[0.335, FLOOR, "snap"],
		[0.85, Px.merge(FLOOR, {"crouch": 6, "lean": 5})],
		[1.3, Px.merge(REST_, {"x": -2, "crouch": 4, "lean": 2, "fx": 15, "fy": -23, "sa": 0.1})],
		[1.7, Px.merge(REST_, {"x": -4})],
	],
	"hits": [{"t": 0.335, "stop": 0.2, "shake": 0.34, "amp": 3, "push": 3.2, "straw": 28, "y": -8}],
	"dust": [{"t": 0.335, "x": 18, "n": 8, "dir": 1}, {"t": 0.335, "x": -12, "n": 5, "dir": -1}],
}

const RAISE := 0.2  # the glint over the head
const SWING := 0.135  # the arc accelerates over the top
const HIT := RAISE + SWING
const HOLD := 0.05
const TRAIL := 0.22
static func head(t_: float) -> float:
	return Px.Ease.inQuad(Px.clamp((t_ - RAISE) / SWING))  # fraction of the arc the edge has made
static func passedAt(f: float) -> float:
	return RAISE + SWING * sqrt(Px.clamp(f))  # when the edge passed fraction f


var C: Array
var n: int
var R: Px.Rng
var st: Dictionary
var ps: Px.Particles
var bits: Px.Bits
var lights: Px.Lights
var A: Dictionary
var U1 := 0.0
var E: Dictionary
var W := 16.0
var WE := 5.0
var X: float
var GLINT: Array
var lines: Array
var spikes: Array
var shards: Array
var t := 0.0
var hit := false


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	n = C.size()
	R = Px.Rng.new(o.seed)
	st = Lib.stone(o.stone)
	var floor_ := func(): return 0.0
	ps = Px.Particles.new({"rng": R, "ground": floor_, "sparks": [C[6], C[5], C[4], C[3]]})
	bits = Px.Bits.new({"ground": floor_})
	lights = Px.Lights.new()
	# the arc: from behind the head, over the top, down into the floor in front
	A = Lib.swing({"cx": 3.0, "cy": -22.0, "R": 37.0, "sy": 0.88, "rot": 0.32, "a0": -2.45, "dir": 1.0})
	U1 = 0.0
	while Lib.onSwing(A, A.R, U1)[1] < -0.5 and U1 < 4.0:
		U1 += 0.005
	E = Px.merge(A, {"R": A.R * 0.76})
	X = Lib.onSwing(A, A.R - 2.0, U1)[0]
	GLINT = Lib.onSwing(A, A.R - 3.0, 0.0)
	lines = Lib.cracks(R, X, 4, 40.0, 7.0, 0.4)
	# the impact star: long spikes along the floor, shorter ones up
	spikes = []
	var as_ := [-PI, -2.7, -2.15, -1.62, -1.05, -0.45, 0.0]
	for i in as_.size():
		var a: float = as_[i]
		spikes.append({"a": a + R.range(-0.08, 0.08), "len": (20.0 if i == 0 or i == 6 else (15.0 if i == 3 else 9.0)) + R.range(0.0, 4.0), "w": 1.6 + R.range(0.0, 0.6)})
	shards = [-2.5, -1.9, -1.2, -0.6].map(func(a): return {"a": a + R.range(-0.15, 0.15), "r": 8.0 + R.range(0.0, 3.0), "v": R.range(80.0, 130.0), "arc": R.range(0.35, 0.6)})


func arc(p: Px.Painter, s: Dictionary, w0: float, lag: float, rim: bool) -> void:
	var tt := t - lag
	var U := U1 * head(tt)
	var T := U1 * Px.smooth(HIT + HOLD, HIT + HOLD + TRAIL, tt)
	if U < 0.02 or T >= U - 0.02:
		return
	var gone := Px.smooth(HIT + HOLD, HIT + HOLD + TRAIL, tt)
	var shrink := 1.0 - 0.75 * gone
	var U1_ := U1
	var C_ := C
	var n_ := n
	Lib.smear(p, s, T, U, w0, func(u, r, out):
		var age := maxf(0.0, tt - passedAt(u / U1_))
		var v: float = (u - T) / (U - T)
		var w := w0 * shrink * pow(sin(PI * pow(v, 2.2)), 0.6)
		if w < 0.4:
			return
		var q: float = (s.R - r) / w
		if q < 0.0 or q > 1.0:
			return
		var ci := 0.0 if (rim and q < 0.22 and age < 0.12) else Px.round(q * (n_ - 1) * 0.62 + age * 7.0 + maxf(0.0, tt - HIT) * 10.0 - v * 0.8 + (0.7 if rim else 1.7))
		out.c = C_[n_ - 1 - int(Px.clamp(ci, 0.0, n_ - 1))]
		out.a = minf(1.0, v / 0.35) * (1.2 - gone))
	if rim:
		Lib.glowAlong(p, s, s.R - w0 * 0.4, T, U, 7.0 + w0 * 0.5, C[4], func(u): return 0.26 * exp(-maxf(0.0, tt - passedAt(u / U1_)) / 0.2) * ((u - T) / (U - T)))


func update(dt: float) -> void:
	t += dt
	# heat gathers to the raised blade
	if t < RAISE - 0.04 and R.chance(0.35):
		var a := R.range(0.0, TAU)
		var D := R.range(14.0, 26.0)
		var T := R.range(0.14, 0.2)
		var v := (D * 3.0) / (exp(3.0 * T) - 1.0)
		ps.spawn(P.STREAK, GLINT[0] + cos(a) * D, GLINT[1] + sin(a) * D, -cos(a) * v, -sin(a) * v, T, C[5] if R.chance(0.5) else C[4])
	# embers shed off the edge as it comes over
	if t > RAISE and t < HIT and R.chance(0.7):
		var u := U1 * head(t) * R.range(0.6, 1.0)
		var xy := Lib.onSwing(A, A.R - R.range(0.0, 6.0), u)
		ps.spawn(P.EMBER, xy[0], xy[1], R.range(-20.0, 20.0), R.range(-40.0, -10.0), R.range(0.5, 1.1), C[4], R.range(1.0, 2.0))
	if not hit and t >= HIT:
		hit = true
		lights.add(X, -6.0, 26.0, WHITE, 0.9, 0.1)
		lights.add(X, -12.0, 64.0, C[4], 0.5, 0.8)
		# sparks fan up off the floor, most of them forward
		for i in 26:
			var a := -PI / 2.0 + R.range(-1.2, 1.35)
			var sp := R.range(140.0, 360.0)
			ps.spawn(P.SPARK, X, -1.0, cos(a) * sp, sin(a) * sp - 40.0, R.range(0.15, 0.5))
		# dust rolls out both ways along the floor
		for i in 20:
			var s := -1.0 if i % 2 else 1.0
			ps.spawn(P.SMOKE, X + s * R.range(0.0, 8.0), -R.range(2.0, 6.0), s * R.range(45.0, 135.0), -R.range(2.0, 12.0), R.range(1.0, 1.45), st.dust, R.range(5.0, 8.5), R.range(0.0, 0.07), PF.BIG)
		for i in 4:
			ps.spawn(P.SMOKE, X + R.range(-4.0, 4.0), -R.range(3.0, 8.0), R.range(-15.0, 15.0), -R.range(40.0, 90.0), R.range(1.0, 1.45), st.dust, R.range(4.0, 6.5), R.range(0.02, 0.1), PF.BIG)
		for i in 8:
			ps.spawn(P.DUST, X + R.range(-4.0, 4.0), -R.range(1.0, 4.0), R.range(-60.0, 60.0), -R.range(8.0, 30.0), R.range(0.35, 0.7), st.dust, R.range(2.0, 3.5))
		# grit and a few stones thrown up, forward
		for i in 44:
			var a := -PI / 2.0 + R.range(-0.7, 1.0)
			var sp := R.range(60.0, 230.0)
			ps.spawn(P.GRIT, X + R.range(-3.0, 3.0), -1.0, cos(a) * sp, sin(a) * sp, R.range(1.0, 1.5), R.pick([st.light, st.body, st.body, st.shade]), 2.0 if R.chance(0.35) else 1.0)
		for i in 6:
			bits.add({"kind": B.CHUNK, "x": X + R.range(-3.0, 3.0), "y": -2.0, "vx": R.range(-50.0, 110.0), "vy": -R.range(120.0, 260.0), "g": 1.0, "drag": 0.4, "bounce": 0.3, "life": R.range(1.15, 1.5), "a": R.range(0.0, TAU), "va": R.range(-14.0, 14.0), "s": float(R.int_(1, 2))})
		# embers lift off the cut
		for i in 16:
			ps.spawn(P.EMBER, X + R.range(-8.0, 8.0), -R.range(1.0, 6.0), R.range(-50.0, 60.0), -R.range(30.0, 110.0), R.range(0.7, 1.5), C[4], R.range(1.0, 2.0))
	# the cracks breathe embers while they're hot
	if hit and t < HIT + 0.6 and R.chance(0.12):
		var c: Dictionary = R.pick(lines)
		var pt: Array = R.pick(c.pts)
		ps.spawn(P.EMBER, pt[0], pt[1] - 1.0, R.range(-12.0, 12.0), -R.range(20.0, 50.0), R.range(0.5, 0.9), C[4], 1.0)
	bits.update(dt)
	for b: Dictionary in bits.list:
		if b.rest and not b.get("dusted", false):
			b.dusted = true
			for i in 2:
				ps.spawn(P.DUST, b.x + R.range(-1.5, 1.5), -0.5, R.sign() * R.range(8.0, 30.0), -R.range(2.0, 12.0), R.range(0.3, 0.6), st.dust, R.range(1.3, 2.4))
	ps.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	var q := t - HIT
	if q >= 0.0:
		# the floor under the blade: white hot, cooling through the ramp to soot
		var fade := 1.0 - Px.smooth(1.0, 1.5, q)
		for y in range(0, 3):
			for x in range(-9, 10):
				var d := Px.hypot((x + 0.5) / 9.0, (y + 0.5) / 3.5)
				if d > 1.0:
					continue
				var T := pow(Px.clamp(1.0 - q / 0.8), 1.4) * (1.2 - d) - Px.rand(x, y, 3) * 0.3
				if T > 0.08:
					p.dot(X + x, y, C[int(Px.clamp(Px.round(T * 9.0), 1.0, 7.0))], fade)
				else:
					p.dot(X + x, y, st.dark if d < 0.5 else st.shade, (1.0 if d < 0.9 - Px.rand(x, y, 9) * 0.3 else 1.0 - d) * fade)
		# the shock runs out along the floor: the far half behind the fighter
		var k := q / 0.45
		if k < 1.0:
			Px.band(p, X, 0.5, 6.0 + 46.0 * Px.Ease.outCubic(k), 0.16, maxf(1.0, 3.0 * (1.0 - k)), 1.15 - k, [st.body, st.light, C[4], C[6]], func(g): return sin(g) < 0.0)
	ps.draw(p, "back")


func draw(p: Px.Painter) -> void:
	var q := t - HIT
	# the glint over the head: the raised blade catching the light
	if t < RAISE + 0.03:
		var g := Px.Ease.outBack(Px.clamp(t / 0.1)) * (1.0 + 0.15 * sin(t * 60.0)) * (1.0 - (t - RAISE) / 0.03 if t > RAISE else 1.0)
		Px.sparkle(p, GLINT[0], GLINT[1], 1.0 + 7.0 * g, C[6], C[4], 0.5)
		p.glow(GLINT[0], GLINT[1], 22.0, C[4], 0.3 * g)
	if q >= 0.0:
		# cracks race out from the cut and split down into the floor: white hot, cooling down the ramp to dark
		var heat := pow(Px.clamp(1.0 - q / 1.2), 1.2)
		var fade := 1.0 - Px.smooth(1.15, 1.5, q)
		var C_ := C
		for c: Dictionary in lines:
			var reach := 40.0 * Px.Ease.outCubic(Px.clamp((q - c.at * 0.1) / 0.13)) * (0.3 if c.fork else 1.0)
			if reach <= 0.0:
				continue
			Lib.along(c.pts, reach, func(x0, y0, x1, y1, d):
				var h: float = heat * (1.0 - d / 46.0) - (0.12 if c.fork else 0.0)
				var col: int = WHITE if h > 0.72 else (C_[int(Px.clamp(Px.round(h * 8.0), 1.0, 6.0))] if h > 0.08 else st.dark)
				if y1 > 0.5:
					p.line(x0 + 1.0, y0, x1 + 1.0, y1, st.dark, fade)
				p.line(x0, y0, x1, y1, col, fade)
				if h > 0.25 and int(d) % 6 < 2:
					p.glow(x1, y1, 6.0, C_[4], 0.2 * h * fade))
		if heat > 0.0:
			p.glow(X, -2.0, 34.0, C[4], 0.32 * heat * fade)
		# the near half of the shock ring
		var k := q / 0.45
		if k < 1.0:
			Px.band(p, X, 0.5, 6.0 + 46.0 * Px.Ease.outCubic(k), 0.16, maxf(1.0, 3.0 * (1.0 - k)), 1.15 - k, [st.body, st.light, C[4], C[6]], func(g): return sin(g) >= 0.0)
	# the arc and its echo, then a dotted trace of embers where it has been
	arc(p, E, WE, 0.02, false)
	arc(p, A, W, 0.0, true)
	var tail := U1 * Px.smooth(HIT + HOLD, HIT + HOLD + TRAIL, t)
	var th := 0.8 * (1.0 - Px.clamp((t - HIT - HOLD) / (TRAIL + 0.25)))
	if tail > 0.02 and th > 0.0:
		var U1_ := U1
		Lib.trace(p, A, A.R - 0.5, 0.0, tail, C[3], func(u): return th * (0.4 + 0.6 * u / U1_))
	if t > RAISE and t < HIT + 0.05:
		var xy := Lib.onSwing(A, A.R - 5.0, U1 * head(t))
		p.glow(xy[0], xy[1], 40.0, C[4], 0.5)
	# the white slam: an impact star flat on the floor, then slivers flying off and a hot pool
	if q >= 0.0 and q < 0.035:
		Lib.star(p, X, -1.0, spikes, 1.0, 1.0, WHITE, C[6], C[7], C[5])
	elif q >= 0.035 and q < 0.07:
		Lib.star(p, X, -1.0, spikes, 1.25, 0.55, C[7], C[6], C[6], C[4])
	if q >= 0.05 and q < 0.16:
		var k := (q - 0.05) / 0.11
		for s: Dictionary in shards:
			Lib.sliver(p, X, -1.0, s.a, s.r + s.v * (q - 0.05), s.arc * (1.0 - 0.4 * k), C[6] if k < 0.4 else (C[5] if k < 0.7 else C[4]), 1.0 - k)
	if q >= 0.0 and q < 0.2:
		var pop := exp(-q / 0.05)
		p.glow(X, -6.0, 30.0, C[5], 0.8 * pop)
		p.glow(X, -2.0, 10.0, WHITE, 0.7 * pop)
	for b: Dictionary in bits.list:
		Lib.rock(p, b, st)
	ps.draw(p, "front")
	lights.draw(p)
