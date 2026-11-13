# The spark, star and light recipes are adapted from Sprite Fusion's open-source explosion and sparkle
# (https://www.spritefusion.com/pixel-art-vfx/explosion), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/projectiles/flare.js@12e06947eed1751bdc0efd88e6b849b5f04d4e31
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Signal flare",
	"desc": "A signal flare streaks up off the ground trailing sparks and smoke, bursts, and hangs as a pulsing red star that drips sparks under its own red-lit smoke, then gutters out.",
	"tags": ["projectile", "flare", "signal", "fire", "smoke", "light", "one-shot"],
	"size": [152, 232],
	"origin": [76, 226],
	"duration": 5,
	"loop": false,
	"fps": 30,
	"bg": "sky",
	"options": {
		"palette": ["#2a0610", "#5c0d1c", "#9a1428", "#d8243a", "#ff4d5e", "#ff8a94", "#ffd0d4", "#ffffff"],
		"smoke": ["#1e1a26", "#2e2938", "#433d4d", "#5b5466", "#77707f", "#958e9c", "#b3acb9"],
		"height": 150,
		"seed": 2,
	},
}

const RISE := 0.85
const BURN := 3.1


# JS imports the core's flare as rays (this effect is itself called flare)
static func rays(p: Px.Painter, x: float, y: float, L: float, k: float, rmp: Variant) -> void:
	Px.flare(p, x, y, L, k, rmp)


var C: Array
var SM: Array
var H: float
var R: Px.Rng
var ps: Px.Particles
var smoke: Lib.Smoke
var lights: Px.Lights
var WR: Array
var t := 0.0
var burst := false
var emit := 0.0
var drip := 0.0


# the rise: fast off the ground, slowing to the top; then the star hangs, sways and sinks slowly
func rise(tt: float) -> Array:
	return [sin(tt * 3.0) * 2.0 * (tt / RISE), -H * Px.Ease.outCubic(Px.clamp(tt / RISE))]


func star(tt: float) -> Array:
	var u := tt - RISE
	return [sin(u * 1.6) * 3.0 + rise(RISE)[0], -H + u * 9.0 + sin(u * 2.3) * 1.5]


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	SM = Px.fit(o.smoke, 7)
	H = o.height
	R = Px.Rng.new(o.seed)
	ps = Px.Particles.new({"rng": R, "ground": func(): return 0.0, "sparks": [WHITE, C[6], C[4], C[2]]})
	smoke = Lib.Smoke.new(R)
	lights = Px.Lights.new()
	WR = [C[0], C[1], Px.mix(C[2], SM[2], 0.45), Px.mix(C[3], SM[3], 0.35), C[4], C[5], C[6]]
	t = 0.0
	burst = false
	emit = 0.0
	drip = 0.0
	lights.add(0.0, -3.0, 26.0, C[4], 0.8, 0.25)
	for i in 5:
		smoke.add({"x": R.range(-3.0, 3.0), "y": -2.0, "vx": R.range(-25.0, 25.0), "vy": -R.range(5.0, 20.0), "r0": 2.0, "r1": R.range(4.0, 6.0), "life": R.range(1.0, 1.6), "a": 0.5, "warm": 0.8, "rise": 6.0})


func update(dt: float) -> void:
	t += dt
	if t < RISE:
		var xy := rise(t)
		var pxy := rise(maxf(0.0, t - dt))
		var x: float = xy[0]
		var y: float = xy[1]
		var px: float = pxy[0]
		var py: float = pxy[1]
		emit += Px.hypot(x - px, y - py) / 1.5
		while emit > 1.0:
			smoke.add({"x": x + R.range(-0.6, 0.6), "y": y + 4.0, "vx": R.range(-6.0, 6.0), "vy": R.range(0.0, 8.0), "r0": 1.3, "r1": R.range(3.0, 4.8), "life": R.range(1.4, 2.1), "a": 0.5, "b": 0.95, "warm": 0.9, "rise": 3.0, "drag": 2.0, "grow": 1.4})
			emit -= 1.0
		if R.chance(0.5):
			ps.spawn(P.SPARK, x, y + 3.0, R.range(-40.0, 40.0), R.range(20.0, 90.0), R.range(0.2, 0.45))
	elif not burst:
		burst = true
		var xy := star(t)
		var x: float = xy[0]
		var y: float = xy[1]
		lights.add(x, y, 64.0, C[4], 0.9, 0.5)
		lights.add(x, y, 24.0, WHITE, 0.8, 0.12)
		for i in 30:
			var a := R.range(0.0, TAU)
			var sp := R.range(70.0, 190.0)
			ps.spawn(P.SPARK, x, y, cos(a) * sp, sin(a) * sp - 30.0, R.range(0.25, 0.7))
		for i in 10:
			smoke.add({"x": x + R.range(-3.0, 3.0), "y": y + R.range(-3.0, 3.0), "vx": R.range(-40.0, 40.0), "vy": R.range(-40.0, 10.0), "r0": 2.5, "r1": R.range(6.0, 9.0), "life": R.range(1.6, 2.4), "a": 0.55, "warm": 1.0, "rise": 10.0, "drag": 2.5})
	elif t < RISE + BURN:
		# the star burns: sparks drip off it, smoke boils up off it into a plume it lights from below
		var xy := star(t)
		var x: float = xy[0]
		var y: float = xy[1]
		var k := (t - RISE) / BURN
		var power := 1.0 - Px.smooth(0.75, 1.0, k)
		drip += dt * 26.0 * power
		while drip > 1.0:
			ps.spawn(P.SPARK, x + R.range(-1.5, 1.5), y + 2.0, R.range(-30.0, 30.0), R.range(10.0, 60.0), R.range(0.35, 0.8))
			drip -= 1.0
		if R.chance(dt * 18.0 * power):
			smoke.add({"x": x + R.range(-1.5, 1.5), "y": y - 2.0, "vx": R.range(-8.0, 8.0), "vy": -R.range(15.0, 30.0), "r0": 2.0, "r1": R.range(6.0, 10.0), "life": R.range(1.6, 2.4) * (1.0 - 0.4 * k), "a": 0.5, "b": 0.85, "warm": 1.0, "rise": 14.0, "drag": 1.6, "grow": 1.2})
	ps.update(dt)
	smoke.update(dt)
	lights.update(dt)


func draw(p: Px.Painter) -> void:
	# the smoke lit red by the star, more the closer and the brighter it burns
	var list := smoke.puffs()
	var lit := 1.0 - Px.smooth(0.75, 1.0, (t - RISE) / BURN) if (t > RISE and t < RISE + BURN) else 0.0
	if lit > 0.0:
		var sxy := star(t)
		var sx: float = sxy[0]
		var sy: float = sxy[1]
		for q: Dictionary in list:
			q.w = maxf(q.w, lit * exp(-Px.hypot(q.x - sx, q.y - sy) / 26.0))
	Lib.cloud(p, list, SM, WR, {"dens": 1.4, "max": 0.8, "lit": 1.3})
	ps.draw(p)
	if t < RISE:
		# the rising flare: a white-hot head, a short red flame under it
		var xy := rise(t)
		var x: float = xy[0]
		var y: float = xy[1]
		p.line(x, y + 1.0, x, y + 5.0, func(u): return C[6] if u < 0.3 else (C[4] if u < 0.7 else C[3]))
		p.px(x, y, WHITE)
		p.px(x, y - 1.0, C[6])
		p.glow(x, y, 14.0, C[4], 0.6)
		p.glow(x, y, 4.0, WHITE, 0.4)
	elif t < RISE + BURN:
		var xy := star(t)
		var x: float = xy[0]
		var y: float = xy[1]
		var u := t - RISE
		var k := u / BURN
		var fr := floorf(t * 30.0)
		var fl := 0.8 + 0.2 * Px.rand(fr, 3) + 0.08 * sin(u * 19.0)
		var die := 1.0 - Px.smooth(0.78, 1.0, k)
		# the burst: a flash of white and rays for a moment
		if u < 0.25:
			var e := u / 0.25
			rays(p, x, y, 22.0 * (1.0 - e) + 3.0, 1.0 - e, C)
			if e < 0.25:
				p.circle(x, y, 5.0 * (1.0 - e * 3.0) + 1.0, WHITE)
		# the star: a hot ball with a long cross of light that pulses, guttering at the end
		var r := (2.0 + 0.6 * fl) * (0.4 + 0.6 * die)
		p.circle(x, y, r + 1.2, C[3])
		p.circle(x, y, r, C[5] if die > 0.4 else C[4])
		if die > 0.25:
			p.circle(x - 0.3, y - 0.3, r * 0.55, WHITE if die > 0.6 else C[6])
		if die > 0.15 and Px.rand(fr, 9) > 0.15:
			Px.sparkle(p, x, y, Px.round((5.0 + 3.0 * fl) * die), C[6], C[4], 0.5 * die)
		p.glow(x, y, 70.0 * (0.6 + 0.4 * die), C[3], 0.55 * fl * die)
		p.glow(x, y, 22.0, C[4], 0.5 * fl * die)
		p.glow(x, y, 6.0, WHITE, 0.35 * die)
	lights.draw(p)
