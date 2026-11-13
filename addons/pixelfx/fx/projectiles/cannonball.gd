# The flash, spark and smoke recipes are adapted from Sprite Fusion's open-source muzzle-flash and explosion
# (https://www.spritefusion.com/pixel-art-vfx/muzzle-flash), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/projectiles/cannonball.js@d68a7c99e5b0b158bf7b162c76d004afabc1530a
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Cannon shot",
	"desc": "A cannon fires from a muzzle `height` px above the floor (the origin): a white flash, a tongue of flame, the ball arcing off trailing smoke, a big gunsmoke cloud rolling out.",
	"tags": ["projectile", "cannon", "cannonball", "smoke", "flash", "directional", "one-shot"],
	"size": [208, 116],
	"origin": [48, 102],
	"duration": 3.8,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"options": {
		"palette": ["#4a1712", "#8a1f17", "#c9281f", "#f2561d", "#ff8a2a", "#ffc23d", "#ffe26b", "#fff3a6", "#ffffff"],
		"smoke": ["#3a3542", "#55505e", "#736d7c", "#938d9b", "#b3adba", "#d2cdd6", "#ece8ee"],
		"iron": ["#141218", "#2c2a34", "#4c4a58", "#8a8898"],
		"height": 12,
		"seed": 4,
	},
}

const ANG := -0.32
const F1 := 1.0 / 30.0

var F: Array
var SM: Array
var IR: Array
var H: float
var MY: float
var R: Px.Rng
var ps: Px.Particles
var smoke: Lib.Smoke
var lights: Px.Lights
var right: float
var top: float
var ball: Dictionary
var jit: Array
var t := 0.0
var wisp := 0.0


func create(o: Dictionary) -> void:
	F = Px.fit(o.palette, 9)
	SM = Px.fit(o.smoke, 7)
	IR = Px.fit(o.iron, 4)
	H = o.height
	MY = -H
	R = Px.Rng.new(o.seed)
	ps = Px.Particles.new({"rng": R, "ground": func(): return 0.0, "sparks": [F[7], F[6], F[4], F[3]]})
	smoke = Lib.Smoke.new(R)
	lights = Px.Lights.new()
	var ca := cos(ANG)
	var sa := sin(ANG)
	right = meta.size[0] - meta.origin[0] - 3.0
	top = -meta.origin[1] + 3.0
	ball = {"x": 4.0, "y": MY, "vx": ca * 330.0, "vy": sa * 330.0, "out": false}
	jit = Px.arr(16, func(_i): return R.next())
	lights.add(12.0, MY - 2.0, 44.0, Px.hex("#ffb060"), 1.0, 0.35)
	lights.add(6.0, MY, 18.0, WHITE, 0.9, 0.08)
	# burning wadding and sparks thrown out with the shot
	for i in 22:
		var a := ANG + R.range(-0.45, 0.45)
		var sp := R.range(140.0, 380.0)
		ps.spawn(P.SPARK, 6.0, MY, cos(a) * sp, sin(a) * sp, R.range(0.1, 0.4))
	for i in 10:
		var a := ANG + R.range(-0.3, 0.3)
		var sp := R.range(70.0, 170.0)
		ps.spawn(P.SPARK, 6.0, MY, cos(a) * sp, sin(a) * sp, R.range(0.5, 0.9))
	for i in 8:
		var a := ANG + R.range(-0.5, 0.3)
		var sp := R.range(40.0, 110.0)
		ps.spawn(P.EMBER, 8.0, MY, cos(a) * sp, sin(a) * sp, R.range(0.7, 1.4), F[5], 2.0)
	# the gunsmoke: a great white shove of it out of the bore that slows, rolls over itself, swells and lifts
	for i in 34:
		var a := ANG + R.range(-0.4, 0.35)
		var sp := R.range(40.0, 260.0) * (1.1 if i < 12 else 0.75)
		smoke.add({"x": 6.0 + R.range(0.0, 6.0), "y": MY + R.range(-2.0, 2.0), "vx": cos(a) * sp, "vy": sin(a) * sp, "r0": R.range(3.0, 4.5), "r1": R.range(9.0, 16.0), "life": R.range(2.7, 3.5), "a": R.range(0.6, 0.75), "b": R.range(0.9, 1.0), "drag": R.range(2.2, 3.2), "rise": R.range(7.0, 13.0), "grow": R.range(1.5, 2.4), "curl": R.range(-1.2, 0.4), "warm": 1.0, "delay": R.range(0.0, 0.05)})
	t = 0.0
	wisp = 0.0


func update(dt: float) -> void:
	t += dt
	if not ball.out:
		var x0: float = ball.x
		var y0: float = ball.y
		ball.vy += 260.0 * dt
		ball.x += ball.vx * dt
		ball.y += ball.vy * dt
		# the ball leaves a thin wisp of smoke off its hot skin, one puff every two pixels of flight
		wisp += Px.hypot(ball.x - x0, ball.y - y0) / 2.0
		while wisp > 1.0:
			var f := R.next()
			var x: float = x0 + (ball.x - x0) * f
			var y: float = y0 + (ball.y - y0) * f
			if x < right - 8.0 and x > 24.0 and t < 0.6:
				smoke.add({"x": x - 3.0, "y": y, "vx": -ball.vx * 0.04, "vy": -ball.vy * 0.04, "r0": 1.0, "r1": R.range(2.5, 3.6) * (1.0 - t), "life": R.range(0.7, 1.1), "a": 0.5 * (1.0 - t), "b": 0.95, "drag": 2.0, "rise": 5.0, "grow": 2.0})
			wisp -= 1.0
		if ball.x > right or ball.y < top:
			ball.out = true
	ps.update(dt)
	smoke.update(dt)
	lights.update(dt)


func draw(p: Px.Painter) -> void:
	var pop := exp(-(t + 0.008) / 0.06)
	var list := smoke.puffs()
	for q: Dictionary in list:
		q.w *= 0.2 + pop * 1.3
	Lib.cloud(p, list, SM, [SM[0], Px.mix(F[1], SM[1], 0.5), Px.mix(F[2], SM[2], 0.45), F[3], F[4], F[6], F[7]], {"dens": 1.35, "max": 0.86, "lit": 1.3})
	ps.draw(p)
	# the ball: dark iron, a lit crescent, a hot glint where the flash still burns on it
	if not ball.out:
		var x: float = ball.x
		var y: float = ball.y
		p.circle(x, y, 3.2, IR[0])
		p.circle(x, y, 2.6, IR[1])
		p.circle(x - 0.7, y - 0.7, 1.8, IR[2])
		p.px(x - 1.0, y - 1.5, IR[3])
		p.px(x - 2.0, y - 1.0, IR[3])
		p.px(x + 1.5, y + 1.0, F[5] if t < 0.3 else IR[2])
		p.glow(x, y, 6.0, F[4], 0.45 * Px.clamp(1.0 - t / 0.5))
	# the flash: a white ball with a tongue of flame for a frame, then a cooler, bigger burst as the gas spills
	if t < 3.0 * F1:
		var f := 1 if t < F1 else (2 if t < 2.0 * F1 else 3)
		var k := (1.0 if f == 1 else (1.15 if f == 2 else 0.8)) * 1.3
		var L := [{"off": 0.0, "a": 0.0, "len": 12.0 * k, "wid": 5.0 * k, "core": 0.55}, {"off": 2.0, "a": 0.0, "len": (24.0 + jit[0] * 8.0) * k, "wid": 2.2 * k, "core": 0.4}]
		for i in 6:
			var a: float = (-1.0 if i < 3 else 1.0) * (0.4 + (i % 3) * 0.45 + jit[i + 1] * 0.2)
			var down := sin(ANG + a)
			var len: float = (8.0 + jit[i + 7] * 7.0) * k * (0.7 if f == 3 else 1.0)
			if down > 0.1:
				len = minf(len, (H - 3.0) / down)
			L.append({"off": 2.0, "a": a, "len": len, "wid": 1.6 * k, "core": 0.25})
		Lib.flash(p, 4.0, MY, ANG, L, [WHITE, F[7], F[6], F[3]] if f == 1 else ([F[7], F[6], F[4], F[2]] if f == 2 else [F[5], F[4], F[3], F[1]]), f)
		if f == 1:
			p.circle(7.0, MY - 1.0, 6.5, WHITE)
			p.ring(7.0, MY - 1.0, 7.5, 1.0, F[7])
	lights.draw(p)
	p.glow(14.0, 0.0, 22.0, F[4], 0.25 * pop)
