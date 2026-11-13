# The particle recipe (fire puffs that cool into smoke, sparks, embers, burning brands, grit, rocks, scorch) is
# adapted from Sprite Fusion's open-source explosion (https://www.spritefusion.com/pixel-art-vfx/explosion),
# MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/explosions/small-explosion.js@64b98a2976bf623829fe4bc9bdfc2b4ae894672a
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const P := Px.P
const PF := Px.PF
const B := Px.B
const WHITE := Px.WHITE

static var meta := {
	"name": "Explosion",
	"desc": "A ground blast: a white flash and shock rings, fire that cools into a rolling smoke column, sparks, burning brands that land and keep burning, tumbling rocks and a glowing scorch.",
	"tags": ["explosion", "fire", "smoke", "debris", "impact", "one-shot"],
	"size": [300, 240],
	"origin": [150, 196],
	"duration": 5.4,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": ["#4a1712", "#c9281f", "#f2561d", "#ff8a2a", "#ffc23d", "#ffe26b", "#fff3a6", "#ffffff"], "stone": "#4a3f69", "size": 1, "seed": 7},
}

static var SOOT := Px.hex("#0d0a12")
static var SOOT2 := Px.hex("#17121d")
static var OUTLINE := Px.hex("#1a1422")
static var WARM := Px.rgb(255, 176, 96)


static func stone(c: Variant) -> Dictionary:
	var h := Px.hex(c)
	return {"light": Px.mix(Px.scale(h, 1.35), WHITE, 0.08), "body": h, "shade": Px.scale(h, 0.64), "dust": Px.mix(Px.scale(h, 1.2), Px.rgb(150, 140, 150), 0.3)}


# the floor under the blast: white-hot, cooling through the fire ramp to soot
static func scorch(p: Px.Painter, F: Array, t: float, rx0: float, cool: float, fade: float) -> void:
	if fade <= 0.0:
		return
	var rx := rx0 * minf(1.0, t / 0.08)
	var ry := 4.0
	var heat := F.duplicate()
	heat.reverse()
	for y in 3:
		for x in range(floori(-rx), ceili(rx) + 1):
			var dx := (x + 0.5) / rx
			var dy := (y + 0.5) / ry
			var d := sqrt(dx * dx + dy * dy)
			if d > 1.0:
				continue
			var k := Px.rand(x * 31 + y, 3)
			var T := pow(Px.clamp(1.0 - t / cool), 1.4) * (1.25 - d) - k * 0.35
			if T > 0.06:
				var c: int = heat[mini(heat.size() - 1, floori((1.0 - minf(1.0, T)) * (heat.size() - 1)))]
				p.dot(x, y, c, fade)
				if (x & 3) == 0:
					p.glow(x + 0.5, y, 6.0, c, 0.18 * T * fade)
			else:
				p.dot(x, y, SOOT if d < 0.5 else SOOT2, (1.0 if d < 0.95 - k * 0.3 else 1.0 - d) * fade)


# a rock: a lit side, a shaded side, an outline, spinning
static func rock(p: Px.Painter, b: Dictionary, st: Dictionary) -> void:
	var r: float = 0.6 + b.s * 0.75
	var fade := minf(1.0, b.life / 0.5)
	var lx: float = cos(b.a) * r * 0.4
	var ly: float = sin(b.a) * r * 0.4
	p.shade(b.x - r - 1.0, b.y - r - 1.0, b.x + r + 1.0, b.y + r + 1.0, func(x: float, y: float, out):
		var dx: float = x - b.x
		var dy: float = y - b.y
		var d := Px.hypot(dx * 1.15, dy)
		if d > r + 0.9:
			return
		var lit := dx * lx + dy * ly
		out.c = OUTLINE if d > r else (st.light if lit < -0.4 else (st.shade if lit > 0.6 else st.body))
		out.a = fade)


var F: Array
var S: float
var RAD: float
var POWER: float
var EARTH := 1.6
var st: Dictionary
var R: Px.Rng
var blazes: Px.Blazes
var ps: Px.Particles
var rocks: Px.Bits
var lights: Px.Lights
var flashes := []
var rings := []
var Y: float
var t := 0.0


func create(o: Dictionary) -> void:
	F = Px.fit(o.palette, 8)
	S = o.size
	RAD = 18.0 * S
	POWER = 0.9 * pow(S, 0.8)
	st = stone(o.stone)
	R = Px.Rng.new(o.seed)
	var floor_ := func(): return 0.0
	ps = Px.Particles.new({"rng": R, "ground": floor_, "sparks": [F[6], F[5], F[3], F[2]], "onLand": func(x, y): blazes.add(x, y - 0.25, R.range(0.9, 1.5), R.range(0.55, 0.85))})
	blazes = Px.Blazes.new(ps)
	rocks = Px.Bits.new({"ground": floor_})
	lights = Px.Lights.new()
	Y = -RAD * 0.3

	# the fireball
	flashes.append({"r": RAD * 1.05, "life": 0.06, "max": 0.06})
	rings.append({"r0": RAD * 0.45, "r1": RAD * 2.7, "life": 0.34, "max": 0.34, "thick": 3.0, "c": F[5]})
	rings.append({"r0": RAD * 0.3, "r1": RAD * 1.6, "life": 0.22, "max": 0.22, "thick": 1.8, "c": F[3]})
	lights.add(0.0, Y, RAD * 3.4, WARM, 0.6 * POWER, 0.7)
	lights.add(0.0, Y, RAD * 1.6, WHITE, 0.6, 0.08)
	for i in 5:
		ps.spawn(P.FIRE, R.range(-2.5, 2.5), Y + R.range(-2.5, 2.5), R.range(-20.0, 20.0), R.range(-40.0, -10.0), R.range(0.18, 0.3), 0, R.range(RAD * 0.4, RAD * 0.55))
	for i in Px.roundi(28.0 * POWER):
		var a := R.range(0.0, TAU)
		var d := R.range(0.0, RAD * 0.55)
		var sp := R.range(40.0, 210.0) * POWER
		ps.spawn(P.FIRE, cos(a) * d, Y + sin(a) * d, cos(a) * sp, sin(a) * sp * 0.8 - 40.0, R.range(0.55, 1.15), 0, R.range(RAD * 0.22, RAD * 0.46), 0.0, (PF.SMOKES | PF.BIG) if R.chance(0.45) else 0)
	for i in 5:
		var a := R.range(0.0, TAU)
		var d := R.range(RAD * 0.1, RAD * 0.5)
		ps.spawn(P.SMOKE, cos(a) * d, Y + sin(a) * d, cos(a) * 30.0, sin(a) * 20.0 - 30.0, R.range(0.9, 1.5), Px.rgb(34, 29, 38), R.range(RAD * 0.15, RAD * 0.26), R.range(0.06, 0.2), PF.BIG)
	for i in 5:
		ps.spawn(P.FIRE, R.range(-RAD * 0.25, RAD * 0.25), Y, R.range(-12.0, 12.0), R.range(-180.0, -100.0), R.range(0.8, 1.3), 0, R.range(RAD * 0.24, RAD * 0.36), R.range(0.0, 0.1), (PF.SMOKES | PF.BIG) if R.chance(0.6) else 0)
	for i in Px.roundi(10.0 * POWER):
		var a := R.range(0.0, TAU)
		var d := R.range(0.0, RAD * 0.7)
		var sp := R.range(15.0, 100.0)
		ps.spawn(P.SMOKE, cos(a) * d, Y + sin(a) * d, cos(a) * sp, sin(a) * sp * 0.6 - 35.0, R.range(1.8, 2.8), 0, R.range(RAD * 0.26, RAD * 0.44), R.range(0.12, 0.45), PF.BIG)
	for i in Px.roundi(80.0 * POWER):
		var a := R.range(0.0, TAU)
		var sp := R.range(140.0, 380.0) * POWER
		ps.spawn(P.SPARK, 0.0, Y, cos(a) * sp, sin(a) * sp - 70.0, R.range(0.18, 0.6))
	for i in Px.roundi(40.0 * POWER):
		var a := R.range(0.0, TAU)
		var sp := R.range(30.0, 150.0)
		ps.spawn(P.EMBER, cos(a) * RAD * 0.4, Y + sin(a) * RAD * 0.4, cos(a) * sp, sin(a) * sp - 75.0, R.range(1.2, 2.6), F[3])
	# (JS re-evaluates the loop condition, drawing a fresh R.range every pass)
	var nb := 0
	while nb < Px.round(R.range(9.0, 14.0) * maxf(0.0, POWER - 0.55)):
		var a := -PI / 2.0 + R.range(-1.35, 1.35)
		var sp := R.range(170.0, 330.0)
		ps.spawn(P.BRAND, 0.0, Y, cos(a) * sp, sin(a) * sp, R.range(0.7, 1.3))
		nb += 1
	# the ground's part: dust rolling out along the floor, rocks and grit thrown up, a dust column
	for i in Px.roundi(RAD * 0.5):
		var s := R.sign()
		ps.spawn(P.SMOKE, s * R.range(0.0, RAD * 0.6), -R.range(1.0, 5.0 + RAD * 0.04), s * R.range(3.0, 9.5) * RAD, -R.range(2.0, 15.0), R.range(1.1, 2.0), st.dust, R.range(4.0, 7.0) + RAD / 6.0, R.range(0.0, 0.06), PF.BIG)
	var i := 0
	while i < 26.0 * minf(1.5, S):
		rocks.add({"kind": B.CHUNK, "x": R.range(-0.4, 0.4) * RAD, "y": -3.0, "vx": R.range(-9.0, 9.0) * RAD * 0.25, "vy": -R.range(7.0, 16.0) * RAD * 0.9, "g": 1.0, "drag": 0.4, "bounce": 0.3, "life": R.range(1.8, 2.6), "a": R.range(0.0, TAU), "va": R.range(-16.0, 16.0), "s": R.int_(1, 3)})
		i += 1
	for j in Px.roundi(EARTH * RAD * 4.0):
		var u := R.range(-1.0, 1.0)
		var a := -PI / 2.0 + u * 0.5
		var sp := R.range(5.0, 15.0) * RAD * (1.0 - 0.45 * absf(u))
		ps.spawn(P.GRIT, u * 0.25 * RAD, -1.0, cos(a) * sp, sin(a) * sp, R.range(1.2, 2.2), R.pick([st.light, st.body, st.body, st.shade]), 2.0 if R.chance(0.45) else 1.0)
	for j in Px.roundi(EARTH * 12.0):
		ps.spawn(P.SMOKE, R.range(-0.3, 0.3) * RAD, -R.range(2.0, RAD * 0.6), R.range(-15.0, 15.0), -R.range(60.0, 190.0) * EARTH * 0.6, R.range(1.6, 2.6), st.dust, R.range(5.0, 9.0) * sqrt(S) + RAD / 7.0, R.range(0.0, 0.15), PF.BIG)


func update(dt: float) -> void:
	t += dt
	for a in [flashes, rings]:
		var i: int = a.size() - 1
		while i >= 0:
			a[i].life -= dt
			if a[i].life <= 0.0:
				a.remove_at(i)
			i -= 1
	rocks.update(dt)
	# rocks that hit hard kick up dust
	for b in rocks.list:
		if b.rest and not b.get("dusted", false):
			b.dusted = true
			for i in 3:
				ps.spawn(P.DUST, b.x + R.range(-1.5, 1.5), -0.5, R.sign() * R.range(10.0, 55.0) * 0.6, -R.range(2.0, 22.0), R.range(0.3, 0.65), st.dust, R.range(1.3, 2.8))
	blazes.update(dt)
	ps.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	scorch(p, F, t, 22.0 * S, 1.2 + RAD / 14.0, 1.0 - Px.smooth(meta.duration - 1.2, meta.duration - 0.2, t))
	ps.draw(p, "back")
	blazes.drawBack(p)
	var k := t / 0.5
	if k < 1.0:
		Px.band(p, 0.0, 0.5, 80.0 * S * Px.Ease.outCubic(k), 0.16, maxf(1.0, (2.0 + RAD / 9.0) * (1.0 - k)), 1.15 - k, [st.body, st.light, F[3], F[6]], func(g): return sin(g) < 0.0)


func draw(p: Px.Painter) -> void:
	var k := t / 0.5
	if k < 1.0:
		Px.band(p, 0.0, 0.5, 80.0 * S * Px.Ease.outCubic(k), 0.16, maxf(1.0, (2.0 + RAD / 9.0) * (1.0 - k)), 1.15 - k, [st.body, st.light, F[3], F[6]], func(g): return sin(g) >= 0.0)
	for b in rocks.list:
		rock(p, b, st)
	ps.draw(p, "front")
	for f in flashes:
		var k2: float = f.life / f.max
		var r: float = f.r * (0.8 + 0.2 * k2)
		p.circle(0.0, Y, r + 1.2, F[2])
		p.circle(0.0, Y, r, F[6] if k2 > 0.45 else F[5])
		p.circle(0.0, Y, r * 0.6, WHITE if k2 > 0.45 else F[6])
	for r in rings:
		var k2: float = r.life / r.max
		var e := 1.0 - pow(k2, 3.0)
		p.ring(0.0, Y, r.r0 + (r.r1 - r.r0) * e, maxf(1.0, r.thick * k2 + 0.4), r.c, minf(1.0, k2 * 1.6))
	lights.draw(p)
