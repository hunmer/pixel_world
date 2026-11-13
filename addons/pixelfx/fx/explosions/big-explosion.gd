# The blast recipe (fire puffs that cool into smoke, sparks, embers, burning brands, grit, rocks, scorch, rings) is
# adapted from Sprite Fusion's open-source explosion (https://www.spritefusion.com/pixel-art-vfx/explosion),
# MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/explosions/big-explosion.js@c65b9b28822279573830d7d6eb2ba4afbd7e5de4
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const PF := Px.PF
const B := Px.B
const WHITE := Px.WHITE

static var meta := {
	"name": "Big explosion",
	"desc": "A huge ground blast in three beats: a white dome, a rolling fireball that climbs into a mushrooming smoke column, heavy rocks, and fires left burning.",
	"tags": ["explosion", "fire", "smoke", "debris", "mushroom", "big", "ground", "one-shot"],
	"size": [360, 300],
	"origin": [180, 262],
	"duration": 7.2,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": ["#4a1712", "#c9281f", "#f2561d", "#ff8a2a", "#ffc23d", "#ffe26b", "#fff3a6", "#ffffff"], "stone": "#4a3f69", "seed": 11},
}

const RAD := 30.0
const POWER := 1.45
const EARTH := 1.6
# the plume's smoke, lit on top to sooty underneath
static var SM := Px.ramp(["#83777f", "#6e6470", "#575060", "#3f3947", "#29242f"])
# three detonations, a beat apart, climbing as they go
static var BLASTS := [
	{"t": 0.0, "x": 0.0, "y": -9.0, "rad": RAD, "power": POWER, "main": true},
	{"t": 0.13, "x": -17.0, "y": -30.0, "rad": 17.0, "power": 0.9},
	{"t": 0.25, "x": 15.0, "y": -46.0, "rad": 15.0, "power": 0.8},
]


var F: Array
var FR: Array
var HR: Array
var st: Dictionary
var R: Px.Rng
var WARM: int
var W: int
var H: int
var OX: int
var OY: int
var X0: float
var X1: float
var Y0: float
var Y1: float
var blazes: Px.Blazes
var ps: Px.Particles
var rocks: Px.Bits
var lights: Px.Lights
var flashes := []
var rings := []
var plume: Lib.Plume
var column: Lib.Column
var t := 0.0
var next := 0


func create(o: Dictionary) -> void:
	F = Px.fit(o.palette, 8)
	FR = Lib.fireRamp(F)
	HR = Lib.heatRamp(FR)
	st = Lib.stone(o.stone)
	R = Px.Rng.new(o.seed)
	var floor_ := func(): return 0.0
	WARM = Px.mix(F[3], F[6], 0.45)
	W = meta.size[0]
	H = meta.size[1]
	OX = meta.origin[0]
	OY = meta.origin[1]
	X0 = -OX + 3
	X1 = W - OX - 3
	Y0 = -OY + 3
	Y1 = H - OY - 3
	ps = Px.Particles.new({"rng": R, "ground": floor_, "sparks": [F[6], F[5], F[3], F[2]], "onLand": func(x, y): blazes.add(x, y - 0.25, R.range(3.0, 4.4), R.range(0.7, 1.25))})
	blazes = Px.Blazes.new(ps)
	rocks = Px.Bits.new({"ground": floor_})
	lights = Px.Lights.new()
	plume = Lib.Plume.new(R, {
		"x": 0.0, "y": -34.0, "rise": 118.0, "tau": 1.25, "drift": 4.0, "tube": [9.0, 21.0], "ring": [2.0, 19.0], "grow": 1.0, "n": 42.0, "size": [6.0, 11.0], "swell": 0.9,
		"spin": 2.6, "spinTau": 1.7, "heat": 1.2, "cool": 0.42, "under": 0.5, "tilt": 0.22, "squash": 0.72, "fade": [4.4, 6.4], "spread": 22.0,
	})
	column = Lib.Column.new(R, {"w": 5.0, "foot": 18.0, "speed": 85.0, "size": [7.0, 11.0], "n": 28.0, "sway": 2.5})


func top() -> float:
	var S := plume.shape()
	return S.y + S.tube * 0.45


func blast(bl: Dictionary) -> void:
	var x: float = bl.x
	var y: float = bl.y
	var rad: float = bl.rad
	var power: float = bl.power
	var main: bool = bl.get("main", false)
	# the later beats flash and ring in the air; the first is a dome on the floor (drawn from t)
	if not main:
		flashes.append({"x": x, "y": y, "r": rad * 1.05, "life": 0.06, "max": 0.06})
	if not main:
		rings.append({"x": x, "y": y, "r0": rad * 0.45, "r1": rad * 2.7, "life": 0.36, "max": 0.36, "thick": 3.0, "c": F[5]})
		rings.append({"x": x, "y": y, "r0": rad * 0.3, "r1": rad * 1.6, "life": 0.24, "max": 0.24, "thick": 1.8, "c": F[3]})
	# light: a big warm flare (raised for a ground blast, so it lights the air and the floor gets a pool)
	lights.add(x, y - 24.0 if main else y, 72.0 if main else rad * 3.4, WARM, 0.6 * power, 0.8)
	lights.add(x, y - 12.0 if main else y, 44.0 if main else rad * 1.6, WHITE, 0.6, 0.1)
	var down := 0.25 if main else PI  # a ground blast throws nothing into the floor
	for i in 5:
		ps.spawn(P.FIRE, x + R.range(-2.5, 2.5), y + R.range(-2.5, 2.5), R.range(-20.0, 20.0), R.range(-40.0, -10.0), R.range(0.18, 0.3), 0, R.range(rad * 0.4, rad * 0.55))
	for i in Px.roundi(26.0 * power):
		var a := R.range(-PI - down, down) if main else R.range(0.0, TAU)
		var d := R.range(0.0, rad * 0.55)
		var sp := R.range(40.0, 200.0) * power
		ps.spawn(P.FIRE, x + cos(a) * d, y + sin(a) * d, cos(a) * sp, sin(a) * sp * 0.8 - 40.0, R.range(0.55, 1.15), 0, R.range(rad * 0.22, rad * 0.46), 0.0, (PF.SMOKES | PF.BIG) if R.chance(0.45) else 0)
	for i in 5:
		var a := R.range(-PI, 0.0)
		var d := R.range(rad * 0.1, rad * 0.5)
		ps.spawn(P.SMOKE, x + cos(a) * d, y + sin(a) * d, cos(a) * 30.0, sin(a) * 20.0 - 30.0, R.range(0.9, 1.5), Px.hex("#221d26"), R.range(rad * 0.15, rad * 0.26), R.range(0.06, 0.2), PF.BIG)
	for i in Px.roundi(8.0 * power):
		var a := R.range(-PI, 0.0)
		var d := R.range(0.0, rad * 0.7)
		var sp := R.range(15.0, 90.0)
		ps.spawn(P.SMOKE, x + cos(a) * d, y + sin(a) * d, cos(a) * sp, sin(a) * sp * 0.6 - 35.0, R.range(1.8, 2.8), 0, R.range(rad * 0.26, rad * 0.4), R.range(0.12, 0.45), PF.BIG)
	for i in Px.roundi(80.0 * power):
		var a := R.range(0.0, TAU)
		var sp := R.range(170.0, 470.0 if main else 380.0)
		ps.spawn(P.SPARK, x, y, cos(a) * sp, sin(a) * sp - 70.0, R.range(0.2, 0.65))
	for i in Px.roundi(30.0 * power):
		var a := R.range(0.0, TAU)
		var sp := R.range(30.0, 150.0)
		ps.spawn(P.EMBER, x + cos(a) * rad * 0.4, y + sin(a) * rad * 0.4, cos(a) * sp, sin(a) * sp - 75.0, R.range(1.4, 3.0), F[3])
	if not main:
		return
	# burning brands that land and keep the ground on fire
	for i in 14:
		var a := -PI / 2.0 + R.range(-1.3, 1.3)
		var sp := R.range(160.0, 340.0)
		ps.spawn(P.BRAND, x, y, cos(a) * sp, sin(a) * sp, R.range(0.8, 1.5))
	# the ground's part: dust rolling out along the floor, a dust column, grit and heavy rocks thrown up
	for i in 18:
		var s := R.sign()
		ps.spawn(P.SMOKE, s * R.range(0.0, RAD * 0.6), -R.range(1.0, 6.0), s * R.range(3.0, 9.0) * RAD, -R.range(2.0, 15.0), R.range(1.3, 2.2), st.dust, R.range(8.0, 12.0), R.range(0.0, 0.06), PF.BIG)
	for i in Px.roundi(EARTH * 12.0):
		ps.spawn(P.SMOKE, R.range(-0.3, 0.3) * RAD, -R.range(2.0, RAD * 0.6), R.range(-15.0, 15.0), -R.range(60.0, 190.0) * EARTH * 0.6, R.range(1.6, 2.6), st.dust, R.range(8.0, 12.0), R.range(0.0, 0.15), PF.BIG)
	for i in Px.roundi(EARTH * RAD * 4.0):
		var u := R.range(-1.0, 1.0)
		var a := -PI / 2.0 + u * 0.55
		var sp := R.range(5.0, 15.0) * RAD * (1.0 - 0.45 * absf(u))
		ps.spawn(P.GRIT, u * 0.25 * RAD, -1.0, cos(a) * sp, sin(a) * sp, R.range(1.4, 2.4), R.pick([st.light, st.body, st.body, st.shade]), 2.0 if R.chance(0.45) else 1.0)
	for i in 26:
		var big := i < 10
		var hot := R.chance(0.45)
		var sx := R.sign()
		rocks.add({"kind": B.CHUNK, "x": R.range(-0.4, 0.4) * RAD, "y": -4.0, "vx": sx * R.range(30.0, 120.0 if big else 150.0), "vy": -R.range(280.0 if big else 320.0, 480.0 if big else 560.0), "g": 1.0, "drag": 0.3, "bounce": 0.3, "life": R.range(3.6, 5.0), "a": R.range(0.0, TAU), "va": R.range(-14.0, 14.0), "s": R.range(2.6, 3.8) if big else R.range(1.2, 2.4), "heat": R.range(0.6, 1.0) if hot else 0.0})


func update(dt: float) -> void:
	t += dt
	while next < BLASTS.size() and t >= BLASTS[next].t:
		next += 1
		blast(BLASTS[next - 1])
	if t > 0.08:
		plume.update(dt)
	var S := plume.shape()
	var k := 1.0 - Px.smooth(2.2, 3.1, t)
	# the column: smoke and fire boil up off the floor into the fireball, dust is drawn in along the ground
	if t > 0.2 and t < 3.1:
		if R.chance(8.0 * k * dt):
			ps.spawn(P.SMOKE, R.range(-10.0, 10.0), -R.range(1.0, 6.0), R.range(-8.0, 8.0), -R.range(40.0, 80.0), R.range(1.5, 2.3), st.dust, R.range(5.0, 8.0), 0.0, PF.BIG)
		if t < 1.5 and R.chance(16.0 * dt):
			ps.spawn(P.FIRE, R.range(-6.0, 6.0), -R.range(4.0, 14.0), R.range(-10.0, 10.0), -R.range(90.0, 150.0), R.range(0.5, 0.8), 0, R.range(4.0, 7.5), 0.0, (PF.SMOKES | PF.BIG) if R.chance(0.5) else 0)
		if t > 0.45 and R.chance(12.0 * k * dt):
			var s := R.sign()
			ps.spawn(P.SMOKE, s * R.range(40.0, 120.0), -R.range(1.0, 4.0), -s * R.range(10.0, 30.0), -R.range(0.0, 5.0), R.range(1.3, 1.9), st.dust, R.range(3.5, 5.5), 0.0, PF.BIG)
	# the fireball sheds embers, then ash drifts down out of the cloud
	if t > 0.3 and t < 3.0 and R.chance(10.0 * plume.hot() * dt):
		var a := R.range(0.0, TAU)
		ps.spawn(P.EMBER, S.x + cos(a) * (S.ring + S.tube), S.y + sin(a) * S.tube * 0.5, cos(a) * R.range(40.0, 90.0), -R.range(10.0, 60.0), R.range(1.2, 2.4), F[3])
	if t > 1.4 and t < 4.6 and R.chance(7.0 * dt):
		ps.spawn(P.FLAKE, S.x + R.range(-1.0, 1.0) * (S.ring + S.tube), S.y + S.tube * 0.6, R.range(-6.0, 6.0), R.range(0.0, 10.0), R.range(2.0, 3.0), R.pick([SM[1], SM[2], F[2]]), R.range(0.6, 1.2))
	column.update(dt, top(), 1.0 if (t > 0.22 and t < 2.5) else 0.0)
	Lib.draft(ps, dt, {"x": 0.0, "top": S.y + S.tube * 0.4, "w": 9.0 + 7.0 * minf(1.0, t), "up": 170.0, "pull": 130.0, "low": 12.0, "reach": 130.0, "k": 1.0 - Px.smooth(2.5, 3.8, t)})
	for a in [flashes, rings]:
		var i: int = a.size() - 1
		while i >= 0:
			a[i].life -= dt
			if a[i].life <= 0.0:
				a.remove_at(i)
			i -= 1
	# rocks: molten ones cool and trail smoke and flame; every hard landing kicks up dust
	for b in rocks.list:
		b.pvy = b.vy
	rocks.update(dt)
	var i := rocks.list.size() - 1
	while i >= 0:
		var b: Dictionary = rocks.list[i]
		i -= 1
		if b.x < X0 + 4.0 or b.x > X1 - 4.0:
			rocks.list.remove_at(i + 1)
			continue
		if b.heat > 0.0:
			b.heat = maxf(0.0, b.heat - dt * 0.3)
			if not b.rest and b.heat > 0.25:
				if b.get("pts") == null:
					b.pts = []
				b.pts.append({"x": b.x, "y": b.y, "t": t})
				if R.chance(14.0 * dt):
					ps.spawn(P.FIRE, b.x, b.y, b.vx * 0.1, b.vy * 0.1 - 8.0, R.range(0.16, 0.3), 0, R.range(1.2, 2.2))
			elif b.rest and R.chance(3.0 * b.heat * dt):
				ps.spawn(P.SMOKE, b.x, b.y - 1.0, R.range(-3.0, 3.0), -R.range(5.0, 12.0), R.range(0.8, 1.4), 0, R.range(1.6, 2.6))
		var landed: bool = (b.pvy > 0.0 and b.vy <= 0.0) or (b.rest and not b.get("dusted", false))
		if landed and b.pvy > 60.0:
			for j in 2 + Px.roundi(b.s):
				ps.spawn(P.DUST, b.x + R.range(-1.5, 1.5), -0.5, R.sign() * R.range(10.0, 50.0), -R.range(2.0, 20.0), R.range(0.3, 0.7), st.dust, R.range(1.3, 1.0 + b.s))
			if b.heat > 0.5 and not b.get("dusted", false):
				blazes.add(b.x, -0.25, R.range(1.2, 2.2), 0.45)
		if b.rest:
			b.dusted = true
		if b.get("pts") != null:
			while b.pts.size() and t - b.pts[0].t > 0.45:
				b.pts.pop_front()
	blazes.update(dt)
	ps.update(dt)
	Lib.cull(ps, X0, Y0, X1, Y1)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	Lib.scorch(p, HR, t, 52.0, 3.4, 1.0 - Px.smooth(meta.duration - 1.6, meta.duration - 0.3, t), 3.0)
	var k := t / 0.6
	if k < 1.0:
		Px.band(p, 0.0, 0.5, 132.0 * Px.Ease.outCubic(k), 0.16, maxf(1.0, 6.0 * (1.0 - k)), 1.15 - k, [st.body, st.light, F[3], F[6]], func(g): return sin(g) < 0.0)
	Lib.drawPs(p, ps, "back", FR)
	column.draw(p, top(), FR, SM, 1.0 - t / 1.4, plume.hot())
	plume.draw(p, FR, SM)
	blazes.drawBack(p)


func draw(p: Px.Painter) -> void:
	var k := t / 0.6
	if k < 1.0:
		Px.band(p, 0.0, 0.5, 132.0 * Px.Ease.outCubic(k), 0.16, maxf(1.0, 6.0 * (1.0 - k)), 1.15 - k, [st.body, st.light, F[3], F[6]], func(g): return sin(g) >= 0.0)
	# the first beat: a white hero frame, a dome of white-hot air that cools into the fire, a flare, a shell of light
	if t < 0.04:
		Lib.dome(p, F, 0.0, 44.0, 1.0)
		p.glow(0.0, -30.0, 68.0, WHITE, 0.6)
	elif t < 0.11:
		Lib.dome(p, F, 0.0, 38.0 - (t - 0.04) * 120.0, 1.0 - (t - 0.04) / 0.07)
	for b in rocks.list:
		if b.get("pts") != null:
			Lib.trail(p, b.pts, t, FR, SM, 0.45, 0.6 + b.s * 0.3, b.heat)
		Lib.rock(p, b, st, FR)
	Lib.drawPs(p, ps, "front", FR)
	if t < 0.24:
		Px.flare(p, 0.0, -14.0, 70.0 * pow(1.0 - t / 0.24, 1.4), 1.0 - t / 0.24, F)
	if t < 0.5:
		var u := t / 0.5
		var r := 34.0 + 80.0 * Px.Ease.outCubic(u)
		p.ring(0.0, 0.0, r, maxf(1.0, 3.0 * (1.0 - u) + 0.5), F[6] if u < 0.3 else (F[5] if u < 0.6 else F[3]), func(v: float, a: float): return 0.0 if sin(a) > 0.0 else minf(1.0, (1.0 - u) * 1.6))
		Lib.glowDome(p, 0.0, 0.0, r, 6.0, F[4], 0.35 * (1.0 - u))
	for f in flashes:
		var k2: float = f.life / f.max
		var r: float = f.r * (0.8 + 0.2 * k2)
		p.circle(f.x, f.y, r + 1.2, F[2])
		p.circle(f.x, f.y, r, F[6] if k2 > 0.45 else F[5])
		p.circle(f.x, f.y, r * 0.6, WHITE if k2 > 0.45 else F[6])
	for r in rings:
		var k2: float = r.life / r.max
		var e := 1.0 - pow(k2, 3.0)
		p.ring(r.x, r.y, r.r0 + (r.r1 - r.r0) * e, maxf(1.0, r.thick * k2 + 0.4), r.c, minf(1.0, k2 * 1.6))
	# the fireball lights the floor under it while it burns
	var hot := plume.hot()
	var flash := maxf(0.0, 1.0 - t / 0.9)
	Lib.pool(p, 0.0, 1.0, 150.0, 22.0, F[3], 0.24 * hot + 0.5 * flash * flash)
	lights.draw(p)
