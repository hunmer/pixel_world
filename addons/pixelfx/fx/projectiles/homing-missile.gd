# The blast's particle recipe (fire that cools, sparks, embers, grit, rocks, scorch, floor ring, lights) is adapted
# from Sprite Fusion's open-source explosion (https://www.spritefusion.com/pixel-art-vfx/explosion),
# MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/projectiles/homing-missile.js@97b9950edf53b3a8cb804ea0027ecea2c1f0dc4d
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const B := Px.B
const WHITE := Px.WHITE

static var meta := {
	"name": "Homing missile",
	"desc": "A missile kicks off, arcs up, rolls over and dives onto its target (the origin), its smoke trail left hanging in the air, and hits in a fiery blast of flame, sparks and rocks.",
	"tags": ["projectile", "missile", "rocket", "homing", "smoke", "explosion", "one-shot"],
	"size": [248, 140],
	"origin": [160, 120],
	"duration": 3.8,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"options": {
		"palette": ["#4a1712", "#8a1f17", "#c9281f", "#f2561d", "#ff8a2a", "#ffc23d", "#ffe26b", "#fff3a6", "#ffffff"],
		"metal": ["#25243a", "#3e4058", "#61667f", "#8e97b0", "#c4cce0"],
		"smoke": ["#26222e", "#3b3644", "#544e5e", "#6f6979", "#8c8596", "#aca5b5", "#cbc4d2"],
		"stone": "#4a3f69",
		"seed": 8,
	},
}

const FLY := 1.15
# the path: up out of the launcher, over the top, and down onto the target, faster all the way
const PATH := [[-130.0, -22.0], [-114.0, -110.0], [-30.0, -120.0], [0.0, 0.0]]


static func at(u: float) -> Array:
	var v := 1.0 - u
	var a := v * v * v
	var b := 3.0 * v * v * u
	var c := 3.0 * v * u * u
	var d := u * u * u
	return [a * PATH[0][0] + b * PATH[1][0] + c * PATH[2][0] + d * PATH[3][0], a * PATH[0][1] + b * PATH[1][1] + c * PATH[2][1] + d * PATH[3][1]]


static func heading(u: float) -> float:
	var v := 1.0 - u
	var d := func(i: int) -> float: return 3.0 * v * v * (PATH[1][i] - PATH[0][i]) + 6.0 * v * u * (PATH[2][i] - PATH[1][i]) + 3.0 * u * u * (PATH[3][i] - PATH[2][i])
	return atan2(d.call(1), d.call(0))


static func progress(tt: float) -> float:
	return pow(Px.clamp(tt / FLY), 1.45)


# the missile, nose right: fins, a body lit on top, a red warhead with a white tip
const MISSILE := ["ff..........", ".fhhhhhhhre.", "nmmmmmmmmrrw", ".fsssssssrd.", "ff.........."]

var F: Array
var M: Array
var SM: Array
var R: Px.Rng
var st: int
var stone: Dictionary
var ps: Px.Particles
var smoke: Lib.Smoke
var rocks: Px.Bits
var lights: Px.Lights
var pal: Dictionary
var t := 0.0
var emit := 0.0
var hit := false


func create(o: Dictionary) -> void:
	F = Px.fit(o.palette, 9)
	M = Px.fit(o.metal, 5)
	SM = Px.fit(o.smoke, 7)
	R = Px.Rng.new(o.seed)
	var floor_ := func(): return 0.0
	st = Px.hex(o.stone)
	stone = {"light": Px.mix(Px.scale(st, 1.35), WHITE, 0.08), "body": st, "shade": Px.scale(st, 0.64), "dust": Px.mix(Px.scale(st, 1.2), Px.hex("#968c96"), 0.3)}
	ps = Px.Particles.new({"rng": R, "ground": floor_, "sparks": [F[7], F[6], F[4], F[3]]})
	smoke = Lib.Smoke.new(R)
	rocks = Px.Bits.new({"ground": floor_})
	lights = Px.Lights.new()
	pal = {"f": M[1], "h": M[4], "m": M[3], "s": M[1], "n": M[0], "r": F[2], "e": F[3], "d": F[1], "w": WHITE}
	t = 0.0
	emit = 0.0
	hit = false
	lights.add(PATH[0][0], PATH[0][1], 30.0, F[4], 0.7, 0.25)
	for i in 6:
		smoke.add({"x": PATH[0][0] + 2.0, "y": PATH[0][1] + 2.0, "vx": R.range(-30.0, 20.0), "vy": R.range(-10.0, 15.0), "r0": 2.0, "r1": R.range(5.0, 7.5), "life": R.range(1.2, 1.8), "a": 0.6, "warm": 1.0, "rise": 8.0})


func blast() -> void:
	var Y := -6.0
	lights.add(0.0, Y - 2.0, 52.0, Px.hex("#ffb060"), 0.8, 0.8)
	lights.add(0.0, Y - 2.0, 30.0, WHITE, 0.75, 0.1)
	for i in 26:
		var a := R.range(0.0, TAU)
		var d := R.range(0.0, 6.0)
		var sp := R.range(30.0, 170.0)
		ps.spawn(P.FIRE, cos(a) * d, Y + sin(a) * d, cos(a) * sp, sin(a) * sp * 0.75 - 40.0, R.range(0.45, 0.95), 0, R.range(3.2, 6.5))
	for i in 5:
		ps.spawn(P.FIRE, R.range(-3.0, 3.0), Y, R.range(-10.0, 10.0), -R.range(90.0, 150.0), R.range(0.7, 1.1), 0, R.range(4.0, 5.5), R.range(0.0, 0.08))
	for i in 70:
		var a := R.range(PI + 0.12, TAU - 0.12)
		var sp := R.range(110.0, 280.0)
		ps.spawn(P.SPARK, 0.0, Y, cos(a) * sp, sin(a) * sp - 40.0, R.range(0.2, 0.65))
	for i in 22:
		var a := R.range(PI, TAU)
		var sp := R.range(30.0, 110.0)
		ps.spawn(P.EMBER, cos(a) * 4.0, Y + sin(a) * 4.0, cos(a) * sp, sin(a) * sp - 50.0, R.range(0.9, 1.6), F[4])
	for i in 16:
		rocks.add({"kind": B.CHUNK, "x": R.range(-5.0, 5.0), "y": -2.0, "vx": R.range(-110.0, 110.0), "vy": -R.range(140.0, 290.0), "g": 1.0, "drag": 0.4, "bounce": 0.3, "life": R.range(1.5, 2.2), "a": R.range(0.0, TAU), "va": R.range(-16.0, 16.0), "s": R.int_(1, 2)})
	for i in 60:
		var u := R.range(-1.0, 1.0)
		var a := -PI / 2.0 + u * 0.55
		var sp := R.range(80.0, 220.0) * (1.0 - 0.4 * absf(u))
		ps.spawn(P.GRIT, u * 4.0, -1.0, cos(a) * sp, sin(a) * sp, R.range(1.0, 1.8), R.pick([stone.light, stone.body, stone.body, stone.shade]), 2.0 if R.chance(0.4) else 1.0)
	# the smoke: a column off the fire and dust rolling out along the floor, lit by the blast at first
	for i in 18:
		var a := R.range(PI * 1.15, PI * 1.85)
		var sp := R.range(20.0, 90.0)
		smoke.add({"x": cos(a) * 4.0, "y": Y + sin(a) * 4.0, "vx": cos(a) * sp * 0.7, "vy": sin(a) * sp - 45.0 * (i / 18.0), "r0": 3.0, "r1": R.range(8.0, 14.0), "life": R.range(1.7, 2.2), "a": 0.62, "b": 0.88, "warm": 1.0, "rise": 30.0 + i * 2.0, "drag": 1.8, "delay": R.range(0.05, 0.35)})
	for i in 12:
		var s := R.sign()
		smoke.add({"x": s * R.range(0.0, 6.0), "y": -3.0, "vx": s * R.range(60.0, 150.0), "vy": -R.range(3.0, 12.0), "r0": 2.5, "r1": R.range(6.0, 9.0), "life": R.range(1.1, 1.7), "a": 0.5, "b": 0.75, "warm": 0.3, "rise": 6.0, "drag": 3.0})


func update(dt: float) -> void:
	t += dt
	if t < FLY:
		# the trail: puffs left behind along the path, hanging where they're dropped, swelling and thinning
		var u := progress(t)
		var xy := at(u)
		var x: float = xy[0]
		var y: float = xy[1]
		var h := heading(u)
		var cx := cos(h)
		var cy := sin(h)
		var pxy := at(progress(maxf(0.0, t - dt)))
		var px: float = pxy[0]
		var py: float = pxy[1]
		# one puff every pixel and a half of flight, wherever along this step it fell, so the trail has no beads
		emit += Px.hypot(x - px, y - py) / 1.5
		while emit > 1.0:
			var f := (emit - 1.0) / maxf(1e-6, Px.hypot(x - px, y - py) / 1.5)
			var ex := x + (px - x) * f
			var ey := y + (py - y) * f
			smoke.add({"x": ex - cx * 7.0 + R.range(-0.6, 0.6), "y": ey - cy * 7.0 + R.range(-0.6, 0.6), "vx": -cx * R.range(10.0, 30.0) + R.range(-6.0, 6.0), "vy": -cy * R.range(10.0, 30.0) + R.range(-6.0, 6.0), "r0": 1.4, "r1": R.range(3.5, 6.0), "life": R.range(1.5, 2.3), "a": 0.5, "b": 0.9, "warm": 0.8, "rise": 4.0, "drag": 3.0, "grow": 1.2})
			emit -= 1.0
		if R.chance(0.35):
			var a := h + PI + R.range(-0.5, 0.5)
			var sp := R.range(40.0, 140.0)
			ps.spawn(P.SPARK, x - cx * 7.0, y - cy * 7.0, cos(a) * sp, sin(a) * sp, R.range(0.15, 0.35))
	elif not hit:
		hit = true
		blast()
	for b: Dictionary in rocks.list:
		if b.rest and not b.get("dusted"):
			b.dusted = true
			for i in 2:
				ps.spawn(P.DUST, b.x + R.range(-1.0, 1.0), -0.5, R.sign() * R.range(8.0, 30.0), -R.range(2.0, 14.0), R.range(0.3, 0.6), stone.dust, R.range(1.2, 2.2))
	ps.update(dt)
	smoke.update(dt)
	rocks.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	# the scorch: white-hot where it hit, cooling through the fire to soot, fading late
	if hit:
		var k := t - FLY
		var fade := 1.0 - Px.smooth(meta.duration - 1.0, meta.duration - 0.2, t)
		var rx := 16.0 * minf(1.0, k / 0.06)
		for y in 3:
			for x in range(floori(-rx), ceili(rx) + 1):
				var d := Px.hypot((x + 0.5) / rx, (y + 0.5) / 4.0)
				if d > 1.0:
					continue
				var T := pow(Px.clamp(1.0 - k / 1.4), 1.4) * (1.25 - d) - Px.rand(x * 31 + y, 3) * 0.35
				p.dot(x, y, F[maxi(1, mini(8, Px.roundi(T * 8.0)))] if T > 0.06 else (Px.hex("#0d0a12") if d < 0.5 else Px.hex("#17121d")), fade)
		var q := k / 0.45
		if q < 1.0:
			Px.band(p, 0.0, 0.5, 60.0 * (1.0 - pow(1.0 - q, 3.0)), 0.16, maxf(1.0, 4.0 * (1.0 - q)), 1.15 - q, [stone.body, stone.light, F[4], F[7]], func(g): return sin(g) < 0.0)


func draw(p: Px.Painter) -> void:
	var list := smoke.puffs()
	Lib.cloud(p, list, SM, [SM[0], Px.mix(F[1], SM[1], 0.5), Px.mix(F[2], SM[2], 0.4), F[3], F[4], F[6], F[7]], {"dens": 1.4, "max": 0.82, "lit": 1.4})
	if hit:
		var q := (t - FLY) / 0.45
		if q < 1.0:
			Px.band(p, 0.0, 0.5, 60.0 * (1.0 - pow(1.0 - q, 3.0)), 0.16, maxf(1.0, 4.0 * (1.0 - q)), 1.15 - q, [stone.body, stone.light, F[4], F[7]], func(g): return sin(g) >= 0.0)
	for b: Dictionary in rocks.list:
		var r: float = 0.6 + b.s * 0.75
		var fade := minf(1.0, b.life / 0.5)
		var lx: float = cos(b.a) * r * 0.4
		var ly: float = sin(b.a) * r * 0.4
		p.shade(b.x - r - 1.0, b.y - r - 1.0, b.x + r + 1.0, b.y + r + 1.0, func(x: float, y: float, out: Variant) -> void:
			var dx: float = x - b.x
			var dy: float = y - b.y
			var d := Px.hypot(dx * 1.15, dy)
			if d > r + 0.9:
				return
			var lit := dx * lx + dy * ly
			out.c = Px.hex("#1a1422") if d > r else (stone.light if lit < -0.4 else (stone.shade if lit > 0.6 else stone.body))
			out.a = fade)
	ps.draw(p)
	if t < FLY:
		var u := progress(t)
		var xy := at(u)
		var x: float = xy[0]
		var y: float = xy[1]
		var h := heading(u)
		var cx := cos(h)
		var cy := sin(h)
		var fr := floorf(t * 30.0)
		# the motor: a short white-hot jet that flickers, the missile riding its heading
		var J := 5.0 + 3.0 * Px.rand(fr, 7)
		var d := 0.0
		while d <= J:
			var v := d / J
			var c: int = WHITE if v < 0.3 else (F[6] if v < 0.6 else F[4])
			p.dot(x - cx * (6.5 + d), y - cy * (6.5 + d), c)
			if v < 0.5:
				p.dot(x - cx * (6.5 + d) - cy * 0.8, y - cy * (6.5 + d) + cx * 0.8, F[5])
			d += 0.5
		Lib.turnSprite(p, MISSILE, pal, x, y, h, 6.0, 2.5)
		p.glow(x - cx * 8.0, y - cy * 8.0, 18.0, F[4], 0.5)
		p.glow(x - cx * 7.0, y - cy * 7.0, 6.0, F[7], 0.5)
	# the hit's flash: a white ball for two frames and a ring of flame
	var k := t - FLY
	if k >= 0.0 and k < 0.07:
		var r := 14.0 * (0.8 + 0.2 * (1.0 - k / 0.07))
		p.circle(0.0, -6.0, r + 1.2, F[3])
		p.circle(0.0, -6.0, r, F[7] if k < 0.035 else F[6])
		p.circle(0.0, -6.0, r * 0.6, WHITE if k < 0.035 else F[7])
	if k >= 0.0 and k < 0.3:
		var rr := 8.0 + 30.0 * (1.0 - pow(1.0 - k / 0.3, 3.0))
		p.ring(0.0, -6.0, rr, maxf(1.0, 2.5 * (1.0 - k / 0.3) + 0.4), F[5], func(_v, ang): return 0.0 if -6.0 + sin(ang) * rr > 0.0 else minf(1.0, (1.0 - k / 0.3) * 1.6))
	lights.draw(p)
