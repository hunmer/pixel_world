# The impact (rocks thrown up that tumble and bounce and kick up dust where they land, gravel, dust rolling out
# along the floor and climbing, a ring on the floor, a white flash) is adapted from Sprite Fusion's open-source
# explosion (https://www.spritefusion.com/pixel-art-vfx/explosion), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/nature/boulder.js@3152de68568f730da12f1c597b490e0d53717e52
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const PF := Px.PF
const B := Px.B
const WHITE := Px.WHITE

static var meta := {
	"name": "Boulder",
	"desc": "A spinning boulder arcs right shedding dust and pebbles, smashes into the floor in a white flash and bursts into tumbling chunks, gravel and rolling dust.",
	"tags": ["nature", "earth", "rock", "projectile", "impact", "directional", "one-shot"],
	"size": [264, 120],
	"origin": [40, 104],
	"duration": 2.3,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"options": {
		"palette": ["#100e12", "#1e1a22", "#302a36", "#463e4c", "#5e5464", "#7c7080", "#a0949e", "#cec4c8"],
		"sparks": ["#fff3a6", "#ffe26b", "#ff8a2a", "#f2561d"],
		"size": 11,
		"seed": 11,
	},
}

const X0 := 6.0
const Y0 := -26.0
const VX := 220.0
const VY := -170.0
const G := 860.0


# the boulder's own surface, turning with it: a few shallow pits, a mossy rim along one side
static func surface(p: Px.Painter, x: float, y: float, r: float, a: float, S: Array, M: Array) -> void:
	var c := cos(a)
	var s := sin(a)
	var at := func(u: float, v: float) -> Array: return [x + (u * c - v * s) * r, y + (u * s + v * c) * r]
	for uv: Array in [[0.42, 0.12], [-0.3, 0.38]]:
		var pp: Array = at.call(uv[0], uv[1])
		p.px(pp[0], pp[1], S[3])
	for k in 9:
		var g := 3.6 + (k / 8.0) * 1.3
		var rr := 0.78 if k % 3 == 1 else 0.92
		var pp: Array = at.call(cos(g) * rr, sin(g) * rr)
		var py: float = pp[1]
		p.px(pp[0], py, M[0 if k % 3 == 1 else (2 if py < y else 1)])


var S: Array
var R: Px.Rng
var RAD: float
var DUST: int
var DUST2: int
var ps: Px.Particles
var MOSSC: Array
var bits: Px.Bits
var lights: Px.Lights
var shape: Array
var tHit: float
var xHit: float
var t := 0.0
var hit := false
var thrown := false


func create(o: Dictionary) -> void:
	S = Px.fit(o.palette, 8)
	R = Px.Rng.new(o.seed)
	var floor_ := func(): return 0.0
	RAD = o.size
	DUST = Px.mix(S[6], Px.hex("#9a8f86"), 0.4)
	DUST2 = Px.mix(S[5], Px.hex("#7a7068"), 0.35)
	ps = Px.Particles.new({"rng": R, "ground": floor_, "sparks": o.sparks})
	MOSSC = [Px.hex("#1f3a1e"), Px.hex("#3f7a2c"), Px.hex("#7cb83a")]
	bits = Px.Bits.new({"ground": floor_})
	lights = Px.Lights.new()
	shape = Lib.stoneShape(R, 8)
	tHit = (-VY + sqrt(VY * VY - 2.0 * G * (Y0 + RAD * 0.8))) / G
	xHit = X0 + VX * tHit
	t = 0.0
	hit = false
	thrown = false


func at(tt: float) -> Array:
	return [X0 + VX * tt, Y0 + VY * tt + 0.5 * G * tt * tt]


func rock(b: Dictionary) -> void:
	bits.add(Px.merge(b, {"pts": Lib.stoneShape(R)}))


func update(dt: float) -> void:
	t += dt
	var f := minf(1.0, dt * 120.0)
	if not thrown:
		thrown = true
		for i in 6:
			ps.spawn(P.DUST, X0 - R.range(0.0, 6.0), Y0 + R.range(-4.0, 4.0), -R.range(20.0, 70.0), R.range(-20.0, 20.0), R.range(0.4, 0.7), DUST, R.range(2.5, 4.5))
		lights.add(X0, Y0, 30.0, WHITE, 0.3, 0.1)
	if t < tHit:
		# it sheds dust and the odd pebble as it flies
		var xy := at(t)
		var x: float = xy[0]
		var y: float = xy[1]
		if R.chance(0.5 * f):
			ps.spawn(P.DUST, x - R.range(2.0, 6.0), y + R.range(-4.0, 4.0), -R.range(10.0, 40.0), R.range(-10.0, 10.0), R.range(0.3, 0.6), DUST, R.range(2.0, 3.5))
		if R.chance(0.12 * f):
			ps.spawn(P.GRIT, x + R.range(-4.0, 4.0), y + R.range(-2.0, 4.0), VX * 0.3, R.range(-40.0, 20.0), R.range(0.6, 0.9), R.pick([S[5], S[4]]), 2.0 if R.chance(0.3) else 1.0)
	if not hit and t >= tHit:
		hit = true
		var x := xHit
		var y := -RAD * 0.6
		lights.add(x, y, 36.0, WHITE, 0.75, 0.1)
		lights.add(x, y, 60.0, Px.hex("#ffb060"), 0.45, 0.5)
		# big chunks of the boulder, thrown up and on, spinning
		for i in 9:
			var a := -PI / 2.0 + R.range(-1.2, 1.1)
			var sp := R.range(100.0, 240.0)
			rock({"kind": B.CHUNK, "x": x + R.range(-5.0, 5.0), "y": y + R.range(-5.0, 5.0), "vx": cos(a) * sp + 30.0, "vy": sin(a) * sp, "g": 1.0, "drag": 0.7, "bounce": 0.35, "life": R.range(1.3, 1.7), "a": R.range(0.0, TAU), "va": R.range(-14.0, 14.0), "s": R.range(2.8, 5.2)})
		for i in 14:
			var a := -PI / 2.0 + R.range(-1.4, 1.4)
			var sp := R.range(120.0, 280.0)
			rock({"kind": B.CHUNK, "x": x + R.range(-4.0, 4.0), "y": y, "vx": cos(a) * sp + 25.0, "vy": sin(a) * sp, "g": 1.0, "drag": 0.8, "bounce": 0.3, "life": R.range(1.1, 1.5), "a": R.range(0.0, TAU), "va": R.range(-18.0, 18.0), "s": R.range(1.4, 2.6)})
		for i in 60:
			var u := R.range(-1.0, 1.0)
			var a := -PI / 2.0 + u * 1.1
			var sp := R.range(80.0, 300.0) * (1.0 - 0.3 * absf(u))
			ps.spawn(P.GRIT, x + u * 6.0, -1.0, cos(a) * sp + 30.0, sin(a) * sp, R.range(1.0, 1.8), R.pick([S[6], S[5], S[4], S[4], S[3]]), 2.0 if R.chance(0.4) else 1.0)
		for i in 12:
			var a := -PI / 2.0 + R.range(-1.3, 1.3)
			var sp := R.range(150.0, 380.0)
			ps.spawn(P.SPARK, x, y, cos(a) * sp + 40.0, sin(a) * sp, R.range(0.15, 0.4))
		# dust rolling out both ways along the floor, and a cloud climbing off the hit
		for i in 14:
			var sd := R.sign()
			ps.spawn(P.SMOKE, x + sd * R.range(2.0, 10.0), -R.range(1.0, 5.0), sd * R.range(40.0, 140.0) + 10.0, -R.range(4.0, 20.0), R.range(1.1, 1.8), DUST if R.chance(0.5) else DUST2, R.range(4.5, 8.0), R.range(0.0, 0.05), PF.BIG)
		for i in 6:
			ps.spawn(P.SMOKE, x + R.range(-6.0, 6.0), -R.range(4.0, 14.0), R.range(-15.0, 25.0), -R.range(30.0, 80.0), R.range(1.2, 1.8), DUST, R.range(6.0, 9.0), R.range(0.0, 0.1), PF.BIG)
		for i in 3:
			ps.spawn(P.STAR, x + R.range(-8.0, 8.0), y + R.range(-10.0, 4.0), 0.0, -4.0, R.range(0.2, 0.4), S[7], R.range(1.0, 2.0))
	bits.update(dt)
	for b: Dictionary in bits.list:
		if b.rest and not b.get("dusted", false):
			b.dusted = true
			for i in 2:
				ps.spawn(P.DUST, b.x + R.range(-1.5, 1.5), -0.5, R.sign() * R.range(8.0, 35.0), -R.range(2.0, 12.0), minf(R.range(0.3, 0.6), meta.duration - 0.05 - t), DUST2, R.range(1.3, 2.6))
	ps.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	var e := t - tHit
	# the scar it leaves: a dark dent with cracks running from it, fading at the end
	if e > 0.0:
		var fade: float = 1.0 - Px.smooth(meta.duration - 0.6, meta.duration - 0.15, t)
		var w := 10.0 * minf(1.0, e / 0.05)
		var x := floori(-w)
		while x <= w:
			var d := absf(x) / w
			p.dot(xHit + x, 0.0, S[0] if d < 0.6 else S[1], fade)
			if d < 0.5:
				p.dot(xHit + x, 1.0, S[1], fade * 0.8)
			x += 1
		for sd in [-1, 1]:
			for k in 4:
				p.dot(xHit + sd * (w + 2.0 + k * 3.0), 1.0 if (k & 1) else 0.0, S[1], fade * (1.0 - k / 4.0))
		var k := e / 0.45
		if k < 1.0:
			Px.band(p, xHit, 0.5, 46.0 * Px.Ease.outCubic(k), 0.18, maxf(1.0, 3.0 * (1.0 - k)), 1.15 - k, [S[4], S[6], Px.hex("#ffd27a"), WHITE], func(g): return sin(g) < 0.0)
	ps.draw(p, "back")


func draw(p: Px.Painter) -> void:
	if t < tHit:
		var xy := at(t)
		var x: float = xy[0]
		var y: float = xy[1]
		var sp := Px.hypot(VX, VY + G * t)
		var ux := VX / sp
		var uy := (VY + G * t) / sp
		# speed lines trailing it
		for i in 4:
			var off := (i - 1.5) * RAD * 0.55
			var nx := -uy * off
			var ny := ux * off
			var L := 10 + (i % 2) * 6
			p.line(x - ux * (RAD + 2.0) + nx, y - uy * (RAD + 2.0) + ny, x - ux * (RAD + 2.0 + L) + nx, y - uy * (RAD + 2.0 + L) + ny, S[5] if i % 2 else S[6], 0.8)
		Lib.drawRock(p, x, y, RAD, t * 13.0, shape, S)
		surface(p, x, y, RAD * 0.8, t * 13.0, S, MOSSC)
		p.glow(x, y, RAD * 2.0, S[6], 0.12)
	var e := t - tHit
	if e >= 0.0 and e < 0.07:
		# the hero frame: the boulder flashes white as it breaks, lines of force burst out
		Lib.drawRock(p, xHit, -RAD * 0.8, RAD, tHit * 13.0, shape, S, 1.0, true)
		Px.sparkle(p, xHit, -RAD * 0.6, 12.0 * (1.0 - e / 0.07), WHITE, Px.hex("#ffd27a"), 0.6)
	if e >= 0.0 and e < 0.14:
		var k := e / 0.14
		for i in 9:
			var a := -PI + (i / 8.0) * PI
			var r0 := RAD + 4.0 + 16.0 * k
			var r1 := r0 + 8.0 * (1.0 - k)
			p.line(xHit + cos(a) * r0, -RAD * 0.6 + sin(a) * r0, xHit + cos(a) * r1, -RAD * 0.6 + sin(a) * r1, WHITE if k < 0.5 else S[6])
	if e > 0.0:
		var k := e / 0.45
		if k < 1.0:
			Px.band(p, xHit, 0.5, 46.0 * Px.Ease.outCubic(k), 0.18, maxf(1.0, 3.0 * (1.0 - k)), 1.15 - k, [S[4], S[6], Px.hex("#ffd27a"), WHITE], func(g): return sin(g) >= 0.0)
	for b: Dictionary in bits.list:
		Lib.drawRock(p, b.x, b.y, b.s, b.a, b.pts, S, minf(1.0, b.life / 0.4))
	ps.draw(p, "front")
	lights.draw(p)
