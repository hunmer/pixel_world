# The earth recipe (grit thrown in a fan, rocks that bounce and kick up dust, a dust column and dust rolling out along
# the floor) is adapted from Sprite Fusion's open-source explosion (https://www.spritefusion.com/pixel-art-vfx/explosion),
# MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/explosions/dirt-explosion.js@98730262d42acee9259c349636706e9bc9dd6012
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const PF := Px.PF
const B := Px.B
const WHITE := Px.WHITE

static var meta := {
	"name": "Dirt explosion",
	"desc": "A buried charge goes off: a flash under the floor, a V of dirt clods and grit thrown high, a brown dust plume that billows and settles, and a crater left behind.",
	"tags": ["explosion", "dirt", "earth", "dust", "debris", "ground", "one-shot"],
	"size": [260, 240],
	"origin": [130, 206],
	"duration": 3.6,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"options": {
		"palette": ["#1c1610", "#33281c", "#4f3f2c", "#6e5a40", "#927a58", "#b89f78", "#dcc8a2"],
		"fire": ["#4a1712", "#c9281f", "#f2561d", "#ff8a2a", "#ffc23d", "#ffe26b", "#fff3a6", "#ffffff"],
		"seed": 3,
	},
}


var E: Array
var F: Array
var R: Px.Rng
var W: int
var H: int
var OX: int
var OY: int
var X0: float
var X1: float
var Y0: float
var Y1: float
var clod: Dictionary
var DUST: int
var SOIL: int
var DARK: int
var ps: Px.Particles
var lights: Px.Lights
var clods: Px.Bits
var t := 0.0


func create(o: Dictionary) -> void:
	E = Px.fit(o.palette, 7)
	F = Px.fit(o.fire, 8)
	R = Px.Rng.new(o.seed)
	var floor_ := func(): return 0.0
	W = meta.size[0]
	H = meta.size[1]
	OX = meta.origin[0]
	OY = meta.origin[1]
	X0 = -OX + 3
	X1 = W - OX - 3
	Y0 = -OY + 3
	Y1 = H - OY - 3
	clod = {"light": E[5], "body": E[3], "shade": E[2]}
	DUST = Px.mix(E[4], Px.rgb(150, 140, 150), 0.2)
	SOIL = Px.mix(E[3], Px.rgb(90, 80, 90), 0.2)
	DARK = Px.mix(E[2], Px.rgb(60, 52, 60), 0.3)
	ps = Px.Particles.new({"rng": R, "ground": floor_, "sparks": [F[6], F[5], F[3], F[2]]})
	lights = Px.Lights.new()
	clods = Px.Bits.new({"ground": floor_})

	lights.add(0.0, -10.0, 56.0, F[4], 0.7, 0.22)
	lights.add(0.0, -4.0, 26.0, WHITE, 0.6, 0.06)
	# the charge: a few sparks out of the hole
	for i in 14:
		var a := -PI / 2.0 + R.range(-0.7, 0.7)
		var sp := R.range(160.0, 320.0)
		ps.spawn(P.SPARK, 0.0, -2.0, cos(a) * sp, sin(a) * sp, R.range(0.15, 0.35))
	# the fountain: grit in a V, clods thrown high, a few pebbles
	for i in 300:
		var side := R.sign()
		var a := -PI / 2.0 + side * R.range(0.05, 0.62)
		var sp := R.range(150.0, 470.0) * (1.0 - 0.3 * absf(a + PI / 2.0))
		ps.spawn(P.GRIT, R.range(-4.0, 4.0), -1.0, cos(a) * sp, sin(a) * sp, R.range(1.2, 2.2), R.pick([E[1], E[2], E[2], E[3], E[3], E[4], E[5]]), 2.0 if R.chance(0.45) else 1.0, R.range(0.0, 0.06))
	for i in 30:
		var side := R.sign()
		var a := -PI / 2.0 + side * R.range(0.1, 0.6)
		var sp := R.range(200.0, 430.0)
		clods.add({"kind": B.CHUNK, "x": R.range(-5.0, 5.0), "y": -2.0, "vx": cos(a) * sp, "vy": sin(a) * sp, "g": 1.0, "drag": 0.35, "bounce": 0.25, "life": R.range(2.2, 3.0), "a": R.range(0.0, TAU), "va": R.range(-12.0, 12.0), "s": R.range(2.6, 3.8) if i < 12 else R.range(1.4, 2.4)})
	# the dust: a plume punched straight up, two lobes riding the V, and a skirt rolling out along the floor
	for i in 22:
		ps.spawn(P.SMOKE, R.range(-7.0, 7.0), -R.range(2.0, 12.0), R.range(-25.0, 25.0), -R.range(70.0, 180.0), R.range(1.8, 2.6), SOIL if R.chance(0.6) else DUST, R.range(9.0, 14.0), R.range(0.0, 0.14), PF.BIG)
	for i in 14:
		var side := R.sign()
		var a := -PI / 2.0 + side * R.range(0.35, 0.6)
		var sp := R.range(110.0, 210.0)
		ps.spawn(P.SMOKE, side * R.range(2.0, 8.0), -R.range(2.0, 8.0), cos(a) * sp, sin(a) * sp, R.range(1.6, 2.4), SOIL if R.chance(0.5) else DUST, R.range(8.0, 12.0), R.range(0.02, 0.1), PF.BIG)
	for i in 16:
		var s := R.sign()
		ps.spawn(P.SMOKE, s * R.range(4.0, 16.0), -R.range(1.0, 5.0), s * R.range(70.0, 200.0), -R.range(2.0, 12.0), R.range(1.4, 2.2), DUST, R.range(6.0, 9.0), R.range(0.02, 0.1), PF.BIG)
	# dark soil thrown up with it, heavier and lower
	for i in 8:
		ps.spawn(P.SMOKE, R.range(-8.0, 8.0), -R.range(2.0, 8.0), R.range(-40.0, 40.0), -R.range(40.0, 110.0), R.range(1.2, 1.8), DARK, R.range(6.0, 9.0), R.range(0.0, 0.05))


func update(dt: float) -> void:
	t += dt
	for b in clods.list:
		b.pvy = b.vy
	clods.update(dt)
	# clods thud down: a puff of dust and a spray of crumbs where they land, the big ones break up
	var i := clods.list.size() - 1
	while i >= 0:
		var b: Dictionary = clods.list[i]
		i -= 1
		if b.x < X0 + 4.0 or b.x > X1 - 4.0:
			clods.list.remove_at(i + 1)
			continue
		var landed: bool = (b.pvy > 0.0 and b.vy <= 0.0) or (b.rest and not b.get("thud", false))
		if not landed or b.pvy < 80.0:
			if b.rest:
				b.thud = true
			continue
		b.thud = b.rest
		for j in 2 + Px.roundi(b.s):
			ps.spawn(P.DUST, b.x + R.range(-2.0, 2.0), -0.5, R.sign() * R.range(15.0, 55.0), -R.range(4.0, 22.0), R.range(0.35, 0.7), DUST, R.range(1.6, 1.2 + b.s))
		for j in Px.roundi(b.s * 3.0):
			ps.spawn(P.GRIT, b.x, -1.0, R.range(-70.0, 70.0), -R.range(40.0, 140.0), R.range(0.8, 1.4), R.pick([E[2], E[3], E[4]]), 1.0)
		if b.s > 2.2 and b.pvy > 200.0:
			b.s *= 0.6
	ps.update(dt)
	Lib.cull(ps, X0, Y0, X1, Y1)
	Lib.fadeEdges(ps, X0, X1, 24.0, Y1)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	Lib.crater(p, E, 0.0, 28.0, Px.Ease.outCubic(minf(1.0, t / 0.12)), 1.0 - Px.smooth(meta.duration - 0.7, meta.duration - 0.1, t))
	var k := t / 0.45
	if k < 1.0:
		Px.band(p, 0.0, 0.5, 90.0 * Px.Ease.outCubic(k), 0.16, maxf(1.0, 3.0 * (1.0 - k)), 1.1 - k, [E[2], E[4], E[5], E[6]], func(g): return sin(g) < 0.0)
	Lib.drawDirt(p, ps, "back")


func draw(p: Px.Painter) -> void:
	var k := t / 0.45
	if k < 1.0:
		Px.band(p, 0.0, 0.5, 90.0 * Px.Ease.outCubic(k), 0.16, maxf(1.0, 3.0 * (1.0 - k)), 1.1 - k, [E[2], E[4], E[5], E[6]], func(g): return sin(g) >= 0.0)
	# the flash out of the ground: a squat dome of white-hot air for a frame or two
	if t < 0.09:
		Lib.dome(p, F, 0.0, 15.0 * (1.0 - t * 3.0), 1.0 - t / 0.09)
	for b in clods.list:
		Lib.rock(p, b, clod, F)
	Lib.drawDirt(p, ps, "front")
	Lib.pool(p, 0.0, 1.0, 60.0, 10.0, F[3], 0.5 * maxf(0.0, 1.0 - t / 0.3))
	lights.draw(p)
