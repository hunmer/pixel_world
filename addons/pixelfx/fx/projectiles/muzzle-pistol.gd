# The flash lobes, spark, smoke and casing recipes are adapted from Sprite Fusion's open-source
# muzzle-flash (https://www.spritefusion.com/pixel-art-vfx/muzzle-flash), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/projectiles/muzzle-pistol.js@44e57bc92b0f17d9f74c16f68ff10c6baa6f7fce
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Pistol shot",
	"desc": "One pistol shot from a muzzle `height` px above the floor (the origin): a spiky white-cored flash, sparks, a curl of smoke hooking up and back, a casing that bounces and settles.",
	"tags": ["projectile", "muzzle", "gun", "pistol", "flash", "smoke", "casing", "directional", "one-shot"],
	"size": [96, 72],
	"origin": [44, 66],
	"duration": 1.8,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"options": {
		"palette": ["#4a1712", "#8a1f17", "#c9281f", "#f2561d", "#ff8a2a", "#ffc23d", "#ffe26b", "#fff3a6", "#ffffff"],
		"brass": ["#4a2e10", "#8c5c1c", "#d9a441", "#ffe39a"],
		"smoke": ["#26222e", "#3b3644", "#544e5e", "#6f6979", "#8c8596", "#aca5b5", "#cbc4d2"],
		"height": 26,
		"seed": 3,
	},
}

const F1 := 1.0 / 30.0

var o: Dictionary
var F: Array
var B: Array
var SM: Array
var MY: float
var R: Px.Rng
var ps: Px.Particles
var smoke: Lib.Smoke
var shapeSeed: int
var tilt: float
var shell: Dictionary
var t := 0.0


func create(o_: Dictionary) -> void:
	o = o_
	F = Px.fit(o.palette, 9)
	B = Px.fit(o.brass, 4)
	SM = Px.fit(o.smoke, 7)
	var H: float = o.height
	MY = -H
	R = Px.Rng.new(o.seed)
	ps = Px.Particles.new({"rng": R, "ground": func(): return 0.0, "sparks": [F[7], F[6], F[4], F[3]]})
	smoke = Lib.Smoke.new(R)
	# the flash's shape, fixed for this shot
	shapeSeed = R.int_(0, 1e6)
	tilt = R.range(-0.05, 0.05)
	# sparks spat forward, a few grains of unburnt powder that drop
	for i in 6:
		var a := R.range(-0.3, 0.3)
		var sp := R.range(180.0, 400.0)
		ps.spawn(P.SPARK, 3.0, MY, cos(a) * sp, sin(a) * sp, R.range(0.06, 0.16))
	for i in 5:
		var a := R.range(-0.35, 0.25)
		var sp := R.range(60.0, 160.0)
		ps.spawn(P.EMBER, 3.0, MY, cos(a) * sp, sin(a) * sp, R.range(0.25, 0.5), F[5])
	# a puff of gas forward, then a chain of wisps that push out, slow and curl up and back over the muzzle
	for i in 3:
		smoke.add({"x": 3.0, "y": MY, "vx": R.range(70.0, 120.0), "vy": R.range(-12.0, 6.0), "r0": 1.6, "r1": R.range(4.5, 6.0), "life": R.range(0.8, 1.05), "a": 0.55, "drag": 3.5, "rise": 10.0, "warm": 0.9, "delay": i * 0.012})
	for i in 14:
		var k := i / 13.0
		smoke.add({"x": 2.0, "y": MY, "vx": 115.0 - 75.0 * k + R.range(-12.0, 12.0), "vy": -6.0 - 10.0 * k + R.range(-5.0, 5.0), "r0": 1.4, "r1": (3.6 + k * 2.6) * R.range(0.75, 1.25), "life": 1.15 + k * 0.3, "a": 0.62, "b": R.range(0.85, 1.0), "drag": 2.2, "rise": 6.0, "curl": -4.4 + k * 1.8 + R.range(-0.5, 0.5), "grow": 1.6, "warm": 0.7, "delay": 0.02 + i * 0.022})
	smoke.add({"x": -7.0, "y": MY - 2.0, "vx": -6.0, "vy": -18.0, "r0": 1.2, "r1": 4.0, "life": 1.05, "a": 0.4, "rise": 8.0, "delay": 0.03})
	shell = {"vx": -R.range(25.0, 45.0), "vy": -R.range(95.0, 130.0), "va": R.sign() * R.range(22.0, 32.0), "a0": R.range(0.0, 6.28)}
	t = 0.0


func update(dt: float) -> void:
	t += dt
	ps.update(dt)
	smoke.update(dt)


func draw(p: Px.Painter) -> void:
	var pop := exp(-(t + 0.008) / 0.035)
	var list := smoke.puffs()
	for q: Dictionary in list:
		q.w *= 0.4 + pop
	Lib.cloud(p, list, SM, [SM[0], Px.mix(F[1], SM[1], 0.5), Px.mix(F[2], SM[2], 0.4), F[3], F[4], F[5], F[7]], {"dens": 1.5, "max": 0.8, "lit": 1.4})
	# the casing: out of the port, up and back, tumbling, a bounce or two, then it lies there and fades
	if t < meta.duration:
		Lib.drawCasing(p, Lib.casing(-7.0, MY - 1.0, shell.vx, shell.vy, shell.va, t, 850.0, -0.5, 0.42, shell.a0), B, minf(1.0, (meta.duration - 0.05 - t) / 0.3))
	# the flash: the hero frame with a white core, then one cooler, smaller frame
	if t < 2.0 * F1:
		var f := 1 if t < F1 else 2
		var L := Lib.flashShape(Px.rng(shapeSeed), f, {"size": 1.15, "spike": [15.0, 22.0], "diag": [7.0, 12.0], "cross": [4.5, 8.0], "back": [3.0, 5.5]})
		Lib.flash(p, 0.0, MY, tilt, L, [WHITE, F[7], F[6], F[3]] if f == 1 else [F[7], F[6], F[4], F[2]], f + o.seed)
	ps.draw(p)
	# light: the pop, its warm pool, a touch on the floor below
	p.glow(4.0, MY, 30.0, F[4], 0.85 * pop)
	p.glow(2.0, MY, 8.0, WHITE, 0.5 * pop)
	p.glow(4.0, 0.0, 16.0, F[4], 0.2 * pop)
