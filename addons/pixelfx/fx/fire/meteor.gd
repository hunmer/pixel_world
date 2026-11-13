# The impact's particle recipe (fire puffs that cool into smoke, sparks, embers, burning brands that land and
# keep burning, rocks, grit, dust, scorch) is adapted from Sprite Fusion's open-source explosion
# (https://www.spritefusion.com/pixel-art-vfx/explosion), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/fire/meteor.js@8b88172ce84b477c859cafe32755a2f72c75a250
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const PF := Px.PF
const B := Px.B
const WHITE := Px.WHITE
const LAYERS := Lib.LAYERS

static var meta := {
	"name": "Meteor",
	"desc": "A burning rock streaks in from the upper left in a comet of fire and smashes into the floor: a white flash, a fireball, rocks and brands thrown, a glowing crater that cools.",
	"tags": ["fire", "meteor", "impact", "explosion", "spell", "debris", "one-shot"],
	"size": [272, 232],
	"origin": [150, 208],
	"duration": 5,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"options": {
		"palette": ["#4a1712", "#8a1f17", "#c9281f", "#f2561d", "#ff8a2a", "#ffc23d", "#ffe26b", "#fff3a6", "#ffffff"],
		"stone": "#4a3f69",
		"rock": ["#120e16", "#2a2230", "#463a4a", "#6a5a66"],
		"seed": 9,
	},
}

const HIT := 0.62
const FROM := [-112.0, -142.0]
static var SOOT := Px.hex("#0d0a12")
static var SOOT2 := Px.hex("#17121d")
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
var RK: Array
var st: Dictionary
var R: Px.Rng
var S: float
var blazes: Px.Blazes
var ps: Px.Particles
var bits: Px.Bits
var lights: Px.Lights
var GLOW: int
var len: float
var ux: float
var uy: float
var t := 0.0
var hit := false
var last: Array


# the flight: speeding up a touch as it falls
func pos(tt: float) -> Array:
	var k := Px.Ease.inQuad(Px.clamp(tt / HIT)) * 0.35 + Px.clamp(tt / HIT) * 0.65
	return [FROM[0] * (1.0 - k), FROM[1] * (1.0 - k)]


func create(o: Dictionary) -> void:
	var F := Px.fit(o.palette, 9)
	H = Lib.hotFirst(F)
	RK = Px.fit(o.rock, 4)
	st = stone(o.stone)
	R = Px.Rng.new(o.seed)
	var floor_ := func(): return 0.0
	S = o.seed * 11.0
	ps = Px.Particles.new({"rng": R, "ground": floor_, "sparks": [H[1], H[2], H[4], H[5]], "onLand": func(x, y): blazes.add(x, y - 0.25, R.range(0.9, 1.6), R.range(0.5, 0.85))})
	blazes = Px.Blazes.new(ps)
	bits = Px.Bits.new({"ground": floor_})
	lights = Px.Lights.new()
	GLOW = Px.mix(Px.mix(H[3], H[4], 0.5), WHITE, 0.25)
	len = Px.hypot(FROM[0], FROM[1])
	ux = -FROM[0] / len
	uy = -FROM[1] / len
	last = pos(0.0)


# the meteor: a lumpy rock, white-hot on its leading face, cracks glowing over the dark back, an outline
func meteor(p: Px.Painter, x: float, y: float, R0: float, cool: float, alpha: float = 1.0) -> void:
	p.shade(x - R0 - 2.0, y - R0 - 2.0, x + R0 + 2.0, y + R0 + 2.0, func(px_, py, out):
		out.a = alpha
		var dx: float = px_ - x
		var dy: float = py - y
		var d := Px.hypot(dx, dy)
		var a := atan2(dy, dx)
		var rr := R0 * (1.0 + 0.18 * Px.noise(a * 2.2 + 3.0, S) + 0.1 * Px.noise(a * 5.0, S + 1.0))
		if d > rr + 1.0:
			return
		if d > rr:
			return OUTLINE
		var face := (dx * ux + dy * uy) / maxf(1.0, d)
		var heat := (1.0 - cool) * (face * 0.6 + 0.5 - (d / rr) * 0.25)
		if heat > 0.62:
			return H[0] if heat > 0.85 else (H[1] if heat > 0.74 else H[2])
		if heat > 0.42:
			return H[4]
		var h := Px.rand(floorf(px_ - x), floorf(py - y), S + 3.0)
		if h < 0.22 * (1.0 - cool * 0.7):
			return H[4] if (1.0 - cool) > 0.5 else H[6]
		return RK[2] if dx * -0.6 + dy * -0.8 > 0.0 else (RK[0] if d / rr > 0.6 else RK[1]))


# the crater: hot rock pooled in the dent cooling to soot, a lip of broken floor
func crater(p: Px.Painter) -> void:
	if t < HIT:
		return
	var a := t - HIT
	var end := 1.0 - Px.smooth(meta.duration - 1.0, meta.duration - 0.15, t)
	var rx := 36.0 * minf(1.0, a / 0.08)
	var ry := 6.0
	for y in range(-1, 4):
		for x in range(floori(-rx), ceili(rx) + 1):
			var dx := (x + 0.5) / rx
			var dy := (y + 0.5) / ry
			var d := sqrt(dx * dx + dy * dy)
			if d > 1.0:
				continue
			var k := Px.rand(x * 31 + y, S + 5.0)
			var T := pow(Px.clamp(1.0 - a / 2.6), 1.3) * (1.25 - d) - k * 0.35
			if T > 0.06:
				var ramp := [H[0], H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]]
				var c: int = ramp[mini(8, floori((1.0 - minf(1.0, T)) * 8.0))]
				p.dot(x, y, c, end)
				if (x & 3) == 0:
					p.glow(x + 0.5, y, 7.0, c, 0.2 * T * end)
			else:
				p.dot(x, y, SOOT if d < 0.55 else SOOT2, (1.0 if d < 0.95 - k * 0.3 else 1.0 - d) * end)
	# the lip: broken floor heaped round the edge, lit by the glow inside
	for x in range(-40, 41):
		var e := absi(x) / 40.0
		var hh := 0.0 if e < 0.7 else Px.round(2.4 * sin(((e - 0.7) / 0.3) * PI) * (0.6 + 0.4 * Px.rand(x, S + 7.0)))
		var j := 0
		while j < hh:
			p.dot(x, -1 - j, Px.mix(st.light, H[4], 0.5 * Px.clamp(1.0 - a / 2.0)) if j == hh - 1.0 else st.shade, end)
			j += 1
		if hh:
			p.dot(x, 0.0, OUTLINE, end)


func update(dt: float) -> void:
	t += dt
	if t < HIT:
		# the flight: a comet of fire shed behind, smoke, sparks, embers
		var xy := pos(t)
		var x: float = xy[0]
		var y: float = xy[1]
		var vx: float = (x - last[0]) / dt
		var vy: float = (y - last[1]) / dt
		last = [x, y]
		for i in 3:
			if not R.chance(0.8 * dt * 60.0):
				continue
			ps.spawn(P.FIRE, x - ux * R.range(2.0, 8.0) + R.range(-3.0, 3.0), y - uy * R.range(2.0, 8.0) + R.range(-3.0, 3.0), vx * 0.15 + R.range(-20.0, 20.0), vy * 0.15 + R.range(-30.0, 10.0), R.range(0.3, 0.6), 0, R.range(3.0, 6.0), 0.0, (PF.SMOKES | PF.BIG) if R.chance(0.65) else 0)
		if R.chance(0.6 * dt * 60.0):
			ps.spawn(P.SPARK, x, y, vx * 0.35 + R.range(-80.0, 80.0), vy * 0.35 + R.range(-80.0, 40.0), R.range(0.2, 0.5))
		if R.chance(0.3 * dt * 60.0):
			ps.spawn(P.EMBER, x, y, vx * 0.1 + R.range(-30.0, 30.0), vy * 0.1 + R.range(-40.0, 0.0), R.range(0.8, 1.6), H[3], 2.0 if R.chance(0.2) else 1.0)
	elif not hit:
		hit = true
		# the impact: flash, fireball thrown up and forward with the rock's momentum, a column, smoke, sparks
		lights.add(0.0, -40.0, 100.0, WARM, 0.95, 0.9)
		lights.add(0.0, -20.0, 46.0, WHITE, 0.9, 0.12)
		for i in 34:
			var a := -PI / 2.0 + R.range(-1.3, 1.3) + 0.25
			var sp := R.range(50.0, 210.0)
			ps.spawn(P.FIRE, R.range(-6.0, 6.0), -R.range(2.0, 10.0), cos(a) * sp, sin(a) * sp * 0.75 - 30.0, R.range(0.5, 1.1), 0, R.range(5.0, 9.0), 0.0, (PF.SMOKES | PF.BIG) if R.chance(0.5) else 0)
		for i in 9:
			ps.spawn(P.FIRE, R.range(-6.0, 6.0), -6.0, R.range(-14.0, 14.0), -R.range(130.0, 220.0), R.range(0.8, 1.2), 0, R.range(6.0, 8.5), R.range(0.0, 0.12), PF.SMOKES | PF.BIG)
		for i in 20:
			var a := R.range(-PI, 0.0)
			var d := R.range(4.0, 18.0)
			ps.spawn(P.SMOKE, cos(a) * d, -R.range(6.0, 24.0), cos(a) * R.range(10.0, 40.0), -R.range(30.0, 110.0), R.range(1.8, 2.8), 0, R.range(8.0, 12.0), R.range(0.15, 0.5), PF.BIG)
		for i in 16:
			var s := R.sign()
			ps.spawn(P.SMOKE, s * R.range(4.0, 18.0), -R.range(1.0, 5.0), s * R.range(60.0, 130.0) + 10.0, -R.range(2.0, 12.0), R.range(1.2, 2.0), st.dust, R.range(5.0, 8.0), R.range(0.0, 0.06), PF.BIG)
		for i in 90:
			var a := -PI / 2.0 + R.range(-1.3, 1.3) + 0.15
			var sp := R.range(100.0, 300.0)
			ps.spawn(P.SPARK, 0.0, -4.0, cos(a) * sp, sin(a) * sp, R.range(0.2, 0.7))
		for i in 36:
			var a := R.range(0.0, TAU)
			var sp := R.range(40.0, 150.0)
			ps.spawn(P.EMBER, cos(a) * 8.0, -8.0 + sin(a) * 6.0, cos(a) * sp, sin(a) * sp - 70.0, R.range(1.2, 2.6), H[3])
		for i in 10:
			var a := -PI / 2.0 + R.range(-1.0, 1.05)
			var sp := R.range(130.0, 240.0)
			ps.spawn(P.BRAND, 0.0, -6.0, cos(a) * sp, sin(a) * sp, R.range(0.7, 1.3))
		for i in 28:
			bits.add({"kind": B.CHUNK, "x": R.range(-8.0, 8.0), "y": -3.0, "vx": R.range(-80.0, 110.0), "vy": -R.range(140.0, 340.0), "g": 1.0, "drag": 0.4, "bounce": 0.3, "life": R.range(1.8, 2.8), "a": R.range(0.0, TAU), "va": R.range(-16.0, 16.0), "s": R.int_(1, 3), "ramp": [OUTLINE, st.shade, st.body, st.light, Px.mix(st.light, WHITE, 0.3)]})
		for i in 80:
			var u := R.range(-1.0, 1.0)
			var a := -PI / 2.0 + u * 0.7 + 0.15
			var sp := R.range(90.0, 270.0) * (1.0 - 0.4 * absf(u))
			ps.spawn(P.GRIT, u * 6.0, -1.0, cos(a) * sp, sin(a) * sp, R.range(1.2, 2.2), R.pick([st.light, st.body, st.body, st.shade]), 2.0 if R.chance(0.45) else 1.0)
	bits.update(dt)
	for b: Dictionary in bits.list:
		if b.rest and not b.get("dusted", false):
			b.dusted = true
			for i in 3:
				ps.spawn(P.DUST, b.x + R.range(-1.5, 1.5), -0.5, R.sign() * R.range(8.0, 35.0), -R.range(2.0, 18.0), R.range(0.3, 0.6), st.dust, R.range(1.3, 2.6))
	blazes.update(dt)
	ps.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	crater(p)
	Lib.simDraw(p, ps, H, "back")
	blazes.drawBack(p)
	var k := (t - HIT) / 0.5
	if k > 0.0 and k < 1.0:
		Px.band(p, 0.0, 0.5, 110.0 * Px.Ease.outCubic(k), 0.16, maxf(1.0, 5.0 * (1.0 - k)), 1.15 - k, [st.body, st.light, H[4], H[1]], func(g): return sin(g) < 0.0)


func draw(p: Px.Painter) -> void:
	var k := (t - HIT) / 0.5
	if k > 0.0 and k < 1.0:
		Px.band(p, 0.0, 0.5, 110.0 * Px.Ease.outCubic(k), 0.16, maxf(1.0, 5.0 * (1.0 - k)), 1.15 - k, [st.body, st.light, H[4], H[1]], func(g): return sin(g) >= 0.0, k < 0.12)
	for b: Dictionary in bits.list:
		rock(p, b, st)
	if t < HIT:
		# the comet: tongues of flame streaming back off the rock, the rock, its light; the floor lights up below
		var xy := pos(t)
		var x: float = xy[0]
		var y: float = xy[1]
		var NZ := func(rate: float, seed: Variant = 0, off: float = 0.0) -> float: return Px.noise(t * rate + off, seed)
		Lib.floorLight(p, 0.0, 0.5, 30.0 + 40.0 * (t / HIT), 7.0, GLOW, 0.5 * pow(t / HIT, 2.0))
		var tails := [[36.0, 7.0, 0.0], [26.0, 7.5, -2.5], [26.0, 7.5, 2.5], [16.0, 8.0, 0.0]]
		for i in tails.size():
			var L: float = tails[i][0]
			var w: float = tails[i][1]
			var off: float = tails[i][2]
			var n := (S + i) * 13.0
			Lib.flameBlade(p, x - uy * off, y + ux * off, -ux, -uy, L * (0.85 + 0.25 * NZ.call(5.0, n)), w, NZ.call(3.0, n + 3.0) * 3.0, NZ, n, H, LAYERS, 0.5, 1.6)
		meteor(p, x, y, 6.5, 0.0)
		p.glow(x, y, 46.0, GLOW, 0.55)
		p.glow(x, y, 12.0, H[1], 0.4)
	else:
		# the core of the meteor sits half-buried in the crater, cooling
		var a := t - HIT
		var cool := Px.clamp(a / 2.8)
		var end := 1.0 - Px.smooth(meta.duration - 1.1, meta.duration - 0.2, t)
		if end > 0.0:
			meteor(p, 0.0, 0.0, 5.5, cool, end)
			p.glow(0.0, -2.0, 22.0, GLOW, 0.4 * (1.0 - cool) * end)
	Lib.simDraw(p, ps, H, "front")
	# the hero frame: a white-hot flash and a flare of rays
	var f := (t - HIT) / 0.08
	if f > 0.0 and f < 1.0:
		p.circle(0.0, -6.0, 11.0 * (1.0 - f * 0.3) + 1.5, H[3])
		p.circle(0.0, -6.0, 11.0 * (1.0 - f * 0.3), H[1] if f < 0.5 else H[2])
		p.circle(0.0, -6.0, 7.0 * (1.0 - f * 0.3), WHITE if f < 0.5 else H[1])
	var fr := (t - HIT) / 0.24
	if fr > 0.0 and fr < 1.0:
		Px.flare(p, 0.0, -6.0, 44.0 * pow(1.0 - fr, 1.4), 1.0 - fr, [H[6], H[4], H[2], H[1]])
	lights.draw(p)
