# The flash lobes, spark, smoke and casing recipes are adapted from Sprite Fusion's open-source
# muzzle-flash (https://www.spritefusion.com/pixel-art-vfx/muzzle-flash), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/projectiles/muzzle-shotgun.js@248ae511a1090ab181c0a9835bb6af9426233553
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Shotgun blast",
	"desc": "A shotgun blast from a muzzle `height` px above the floor (the origin): a wide ragged fan of flame, pellet streaks, a heavy rolling smoke cloud, a red shell kicked out on the pump.",
	"tags": ["projectile", "muzzle", "gun", "shotgun", "flash", "smoke", "casing", "directional", "one-shot"],
	"size": [160, 88],
	"origin": [44, 82],
	"duration": 3.2,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"options": {
		"palette": ["#4a1712", "#8a1f17", "#c9281f", "#f2561d", "#ff8a2a", "#ffc23d", "#ffe26b", "#fff3a6", "#ffffff"],
		"smoke": ["#221e2a", "#36313f", "#4e4858", "#6a6474", "#888192", "#a8a1b1", "#c8c1cf"],
		"shell": ["#4a0f14", "#9a1e22", "#d8423a", "#8c5c1c", "#e9b54a"],
		"height": 26,
		"seed": 5,
	},
}

const F1 := 1.0 / 30.0


# the fan: a fat fireball at the muzzle and a spray of ragged tongues across the cone, each its own length
static func fan(R: Array, f: int) -> Array:
	var k := 1.0 if f == 1 else (0.82 if f == 2 else 0.55)
	var w := 1.0 if f == 1 else 1.25
	var L := [{"off": 0.5, "a": 0.0, "len": 11.0 * k, "wid": 3.6 * w, "core": 0.5}]
	for i in 9:
		var u := i / 8.0 - 0.5
		var a: float = u * 1.15 + R[i * 3] * 0.12
		var len: float = (17.0 + 11.0 * (1.0 - absf(u) * 1.4) + R[i * 3 + 1] * 7.0) * k
		L.append({"off": 2.0, "a": a, "len": len, "wid": (1.7 + R[i * 3 + 2]) * w, "core": 0.32 if f == 1 else 0.0})
	if f == 1:
		for s in [-1.0, 1.0]:
			L.append({"off": 1.0, "a": s * (1.6 + R[27 + (1 if s > 0.0 else 0)] * 0.4), "len": 5.0 + R[29] * 3.0, "wid": 1.2, "core": 0.0})
	return L


var F: Array
var SM: Array
var SH: Array
var MY: float
var R: Px.Rng
var ps: Px.Particles
var smoke: Lib.Smoke
var right: float
var jit: Array
var pellets: Array
var shell: Dictionary
var t := 0.0


func create(o: Dictionary) -> void:
	F = Px.fit(o.palette, 9)
	SM = Px.fit(o.smoke, 7)
	SH = Px.fit(o.shell, 5)
	var H: float = o.height
	MY = -H
	R = Px.Rng.new(o.seed)
	ps = Px.Particles.new({"rng": R, "ground": func(): return 0.0, "sparks": [F[7], F[6], F[4], F[3]]})
	smoke = Lib.Smoke.new(R)
	right = meta.size[0] - meta.origin[0] - 2.0
	jit = Px.arr(32, func(_i): return R.next())
	# pellets: a tight spray, gone off the canvas in a few frames, each dragging a hot streak
	pellets = Px.arr(10, func(_i): return {"a": R.range(-0.13, 0.13), "v": R.range(900.0, 1150.0), "d0": R.range(0.0, 4.0)})
	# sparks and burning wad, flung wide
	for i in 16:
		var a := R.range(-0.55, 0.55)
		var sp := R.range(180.0, 460.0)
		ps.spawn(P.SPARK, 4.0, MY, cos(a) * sp, sin(a) * sp - 20.0, R.range(0.08, 0.3))
	for i in 7:
		var a := R.range(-0.5, 0.3)
		var sp := R.range(70.0, 200.0)
		ps.spawn(P.EMBER, 4.0, MY, cos(a) * sp, sin(a) * sp, R.range(0.4, 0.9), F[5])
	# the smoke: a heavy shove of gas forward that slows, rolls, swells and lifts; the first of it lit by the blast
	for i in 26:
		var a := R.range(-0.45, 0.35)
		var sp := R.range(60.0, 230.0) * (1.15 if i < 8 else 0.8)
		smoke.add({"x": 4.0 + R.range(0.0, 4.0), "y": MY + R.range(-1.5, 1.5), "vx": cos(a) * sp, "vy": sin(a) * sp, "r0": R.range(2.5, 3.5), "r1": R.range(7.0, 12.5), "life": R.range(2.1, 2.9), "a": R.range(0.55, 0.72), "b": R.range(0.9, 1.0), "drag": R.range(2.6, 3.6), "rise": R.range(9.0, 15.0), "grow": R.range(1.8, 2.8), "warm": 1.0, "delay": R.range(0.0, 0.04)})
	for i in 6:
		smoke.add({"x": 2.0, "y": MY, "vx": R.range(15.0, 50.0), "vy": -R.range(10.0, 25.0), "r0": 1.5, "r1": R.range(4.0, 6.0), "life": R.range(1.8, 2.4), "a": 0.5, "b": 1.0, "drag": 2.0, "rise": 10.0, "curl": -R.range(1.5, 3.0), "warm": 0.6, "delay": 0.08 + i * 0.05})
	# the pump throws the spent shell a beat later
	shell = {"t0": 0.42, "vx": -R.range(30.0, 55.0), "vy": -R.range(110.0, 150.0), "va": R.sign() * R.range(16.0, 24.0), "a0": R.range(0.0, 6.28)}
	t = 0.0


func update(dt: float) -> void:
	t += dt
	ps.update(dt)
	smoke.update(dt)


func draw(p: Px.Painter) -> void:
	var pop := exp(-(t + 0.008) / 0.05)
	var list := smoke.puffs()
	for q: Dictionary in list:
		q.w *= 0.25 + pop * 1.2
	Lib.cloud(p, list, SM, [SM[0], Px.mix(F[1], SM[1], 0.5), Px.mix(F[2], SM[2], 0.4), F[3], F[4], F[5], F[7]], {"dens": 1.4, "max": 0.86, "lit": 1.4})

	# the shell: red hull, brass head, tumbling up and back, bouncing, lying a moment
	if t > shell.t0 and t < meta.duration - 0.05:
		var k := Lib.casing(-9.0, MY, shell.vx, shell.vy, shell.va, t - shell.t0, 850.0, -1.0, 0.35, shell.a0)
		var ca: float = cos(k.a)
		var sa: float = sin(k.a)
		var fade := Px.clamp((meta.duration - 0.05 - t) / 0.3)
		var d := -1.5
		while d <= 1.5:
			p.dot(k.x + ca * d, k.y + sa * d - 0.5, (SH[4] if d > 1.2 else SH[3]) if d > 0.8 else (SH[2] if d > -0.6 else SH[1]), fade)
			d += 0.5
		d = -1.0
		while d <= 1.0:
			p.dot(k.x + ca * d - sa, k.y + sa * d + ca - 0.5, SH[3] if d > 0.6 else SH[0], fade)
			d += 0.5
		if k.hit >= 0.0 and k.hit < 0.07:
			p.glow(k.x, k.y, 5.0, SH[4], 0.5 * (1.0 - k.hit / 0.07))

	# the flash: a white-hot hero frame, then the fan cooling and spreading as the gas balloons
	if t < 3.0 * F1:
		var f := 1 if t < F1 else (2 if t < 2.0 * F1 else 3)
		Lib.flash(p, 0.0, MY, 0.0, fan(jit, f), [WHITE, F[7], F[6], F[3]] if f == 1 else ([F[7], F[6], F[4], F[2]] if f == 2 else [F[5], F[4], F[3], F[1]]), f + 9)
	# the pellets: hot heads with tails that cool to orange, clipped at the canvas edge
	if t < 0.2:
		for q: Dictionary in pellets:
			var head: float = 6.0 + q.d0 + q.v * t
			var tail := maxf(4.0, head - 26.0)
			var ca: float = cos(q.a)
			var sa: float = sin(q.a)
			var d := tail
			while d <= head:
				var x := ca * d
				if x > right:
					break
				var u := (d - tail) / maxf(1.0, head - tail)
				p.dot(x, MY + sa * d, WHITE if u > 0.85 else (F[6] if u > 0.5 else F[4]), 1.0 if u > 0.3 else u / 0.3)
				d += 0.5
			if ca * head < right:
				p.glow(ca * head, MY + sa * head, 4.0, F[6], 0.5)
	ps.draw(p)
	# light: a big pop that floods the floor, a white heart
	p.glow(8.0, MY, 46.0, F[4], 0.95 * pop)
	p.glow(4.0, MY, 12.0, WHITE, 0.6 * pop)
	p.glow(10.0, 0.0, 30.0, F[4], 0.28 * pop)
