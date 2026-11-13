# The rocks, grit and dust are adapted from Sprite Fusion's open-source explosion
# (https://www.spritefusion.com/pixel-art-vfx/explosion), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/impacts/heavy-landing.js@673802dfca343b212b8720838b4776998b8e4bcc
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const B := Px.B
const WHITE := Px.WHITE

static var meta := {
	"name": "Heavy landing",
	"desc": "A character lands hard: the floor dents and cracks under their feet, two rings of dust roll out along the floor one after the other, and pebbles hop away.",
	"tags": ["impact", "landing", "ground", "stomp", "dust", "rocks", "actor", "one-shot"],
	"size": [176, 80],
	"origin": [88, 60],
	"duration": 1.6,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {"palette": ["#1c1a24", "#2f2a3a", "#4a4258", "#6b6280", "#9088a4", "#bdb6cc", "#e6e1ee"], "stone": "#4a3f69", "seed": 14},
}

static var FALL := {"turn": 0.8, "y": -46, "crouch": -1, "lean": -1, "fx": -9, "fy": -42, "bx": 10, "by": -42, "ffx": 6, "ffy": -8, "fbx": -3, "fby": -3, "toeB": true, "ghost": 1}
static var HERO_ := {"y": 0, "crouch": 8, "lean": 5, "fx": 13, "fy": -8, "bx": -6, "by": -23, "ffx": 11, "fbx": -10}
static var act := {
	"poses": [
		[-0.26, FALL],
		[-0.01, Px.merge(FALL, {"y": -6}), "in"],
		[0, HERO_, "snap"],
		[0.55, Px.merge(HERO_, {"crouch": 7})],
		[0.95, Px.merge(HERO_, {"crouch": 5, "lean": 3, "fx": 13, "fy": -15, "bx": -5, "by": -20})],
		[1.3, Px.READY],
		[1.6, Px.READY],
	],
	"hits": [{"t": 0.005, "stop": 0.13, "shake": 0.32, "amp": 3}],
}


# the dent: the floor's edge pressed into a shallow dish, scuffed lips either side
static func dent(p: Px.Painter, st: Dictionary, k: float) -> void:
	for x in range(-10, 10):
		var q := absf(x + 0.5) / 10.0
		var dep := Px.round(1.8 * (1.0 - q * q))
		if q < 0.82:
			var y := 0.0
			while y < dep:
				p.dot(x, y, Lib.SOOT, k)
				y += 1.0
			p.dot(x, dep, st.lip, k)
		else:
			p.dot(x, -1.0, st.light if q > 0.92 else st.lip, k)


var C: Array
var st: Dictionary
var R: Px.Rng
var D: float
var back: Px.Particles
var front: Px.Particles
var bits: Px.Bits
var cracks: Array
var DUST: int
var LIT: int
var PH: float
var t := 0.0


# puffs riding each ring out along the floor
func ring(n: int, v0: float, v1: float, size: Array, delay: float) -> void:
	for i in n:
		var g := (float(i) / n) * TAU + R.range(-0.1, 0.1)
		var v := R.range(v0, v1)
		var far := sin(g) < 0.0
		(back if far else front).spawn(P.DUST, cos(g) * 4.0, sin(g) * 0.7 - 1.0, cos(g) * v, sin(g) * v * 0.16 - R.range(2.0, 10.0), R.range(0.45, 0.8), LIT if R.chance(0.45) else DUST, R.range(size[0], size[1]), delay + R.range(0.0, 0.03))


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 7)
	st = Lib.stone(o.stone)
	R = Px.Rng.new(o.seed)
	var floor_ := func(): return 0.0
	D = meta.duration
	# the rings' far halves go behind the character, the near halves and all the debris in front
	back = Px.Particles.new({"rng": R, "ground": floor_})
	front = Px.Particles.new({"rng": R, "ground": floor_})
	bits = Px.Bits.new({"ground": floor_})
	cracks = Lib.makeCracks(R, 6, {"len": [8.0, 20.0], "dive": 0.7, "maxY": 12.0, "forks": 0.4, "x0": [2.0, 6.0]})
	DUST = Px.mix(st.dust, C[5], 0.4)
	LIT = Px.mix(DUST, WHITE, 0.3)
	PH = R.range(0.0, TAU)
	ring(20, 140.0, 190.0, [2.2, 3.4], 0.01)
	ring(18, 70.0, 110.0, [3.4, 5.4], 0.12)
	# and a low cloud at the feet that rises a little and hangs
	for i in 12:
		var s := R.sign()
		var up := i < 6
		(front if i % 2 else back).spawn(P.DUST, s * R.range(2.0, 10.0), -R.range(1.0, 4.0), s * R.range(10.0, 35.0) * (0.6 if up else 1.0), -(R.range(25.0, 60.0) if up else R.range(4.0, 12.0)), R.range(0.55, 0.9), LIT if R.chance(0.5) else DUST, R.range(3.0, 5.0), R.range(0.02, 0.1))
	# pebbles that hop away along the floor, and grit
	for i in 12:
		var s := R.sign()
		var v := R.range(50.0, 130.0)
		bits.add({"kind": B.CHUNK, "x": s * R.range(3.0, 8.0), "y": -1.0, "vx": s * v, "vy": -R.range(140.0, 230.0), "g": 1.0, "drag": 0.5, "bounce": 0.55, "life": R.range(1.0, 1.45), "a": R.range(0.0, TAU), "va": s * R.range(8.0, 16.0), "s": 2.0 if R.chance(0.3) else 1.0, "pts": Lib.rockShape(R)})
	for i in 24:
		var s := R.sign()
		var a := -PI / 2.0 + s * R.range(0.3, 1.2)
		var v := R.range(60.0, 170.0)
		front.spawn(P.GRIT, s * R.range(2.0, 7.0), -1.0, cos(a) * v, sin(a) * v, R.range(0.6, 1.1), R.pick([st.light, st.body, st.lip]), 2.0 if R.chance(0.3) else 1.0)


# the two dust rings themselves: soft bands on the floor, the second slower, lumpier and later
func rings(p: Px.Painter, far: bool) -> void:
	for rg: Array in [[0.01, 0.45, 58.0, 4.5, 0.75, 1], [0.12, 0.85, 42.0, 6.0, 0.8, 0]]:
		var t0: float = rg[0]
		var dur: float = rg[1]
		var r1: float = rg[2]
		var w: float = rg[3]
		var k0: float = rg[4]
		var edge: int = rg[5]
		var g := (t - t0) / dur
		if g <= 0.0 or g >= 1.0:
			continue
		var r := 6.0 + r1 * Px.Ease.outCubic(g)
		Lib.dustRing(p, 0.0, 0.0, r, w * (1.0 + g), k0 * pow(1.0 - g, 1.2) * minf(1.0, g / 0.06), DUST, {"sy": 0.2, "ph": PH + t0 * 10.0, "brk": g * 0.8, "half": -1.0 if far else 1.0})
		# the fast ring's leading edge: a crisp lit band on the floor
		if edge and g < 0.75:
			Px.band(p, 0.0, 0.5, r + 2.0, 0.2, maxf(1.0, 2.5 * (1.0 - g)), 1.1 - g / 0.75, [st.body, st.light, LIT, WHITE], func(a): return (sin(a) < 0.0) == far)


func update(dt: float) -> void:
	t += dt
	for b: Dictionary in bits.list:
		b.pvy = b.vy
	bits.update(dt)
	for b: Dictionary in bits.list:
		if b.pvy > 80.0 and b.vy <= 0.0:
			front.spawn(P.DUST, b.x, -0.5, R.sign() * R.range(6.0, 20.0), -R.range(2.0, 10.0), R.range(0.25, 0.45), DUST, R.range(1.0, 1.8))
			b.pvy = 0.0
	back.update(dt)
	front.update(dt)


func drawBack(p: Px.Painter) -> void:
	var fade := 1.0 - Px.smooth(D - 0.5, D - 0.1, t)
	dent(p, st, fade)
	Lib.drawCracks(p, cracks, func(c): return c.len * Px.Ease.outCubic(Px.clamp((t - c.t0) / 0.08)), func(_d): return 0.0, [WHITE, WHITE, WHITE, WHITE], Lib.SOOT, st.light, fade)
	rings(p, true)
	back.draw(p)


func draw(p: Px.Painter) -> void:
	rings(p, false)
	front.draw(p)
	for b: Dictionary in bits.list:
		Lib.rock(p, b, st)
	# the thud: a flat streak of light along the floor for a frame or two
	if t < 0.035:
		p.ellipse(0.0, 0.0, 15.0, 2.5, func(d): return WHITE if d < 0.55 else C[6])
	elif t < 0.07:
		for x in range(-22, 23):
			p.dot(x, 0.0, WHITE if absi(x) < 10 else C[5], 1.0 - absi(x) / 24.0)
	if t < 0.12:
		p.glowLine(-20.0, 0.0, 20.0, 0.0, 8.0, C[6], 0.45 * (1.0 - t / 0.12))
