# The flame-puff, smoke and spark recipe and the floor ring are adapted from Sprite Fusion's open-source explosion
# (https://www.spritefusion.com/pixel-art-vfx/explosion), and the tongue from its fire
# (https://www.spritefusion.com/pixel-art-vfx/fire), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/fire/fire-ring.js@94591eab6f9e00c1b3bcfc5cf23bb6af0574d6f9
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const PF := Px.PF
const WHITE := Px.WHITE
const READY := Px.READY
const LAYERS := Lib.LAYERS
const BACK_LAYERS := Lib.BACK_LAYERS

static var meta := {
	"name": "Fire ring",
	"desc": "A white flash at the feet, then flames race outward along the floor in a ring, flaring as the front passes and burning down behind it over a smouldering scorch.",
	"tags": ["fire", "ring", "nova", "aoe", "spell", "ground", "one-shot"],
	"size": [224, 128],
	"origin": [112, 92],
	"duration": 3.9,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {
		"palette": ["#4a1712", "#8a1f17", "#c9281f", "#f2561d", "#ff8a2a", "#ffc23d", "#ffe26b", "#fff3a6", "#ffffff"],
		"reach": 92,
		"seed": 6,
	},
}

const HIGH := {"turn": 1.15, "crouch": 0, "fx": -7, "fy": -44, "bx": 8, "by": -44, "ffx": -5, "fbx": 6}
const SLAM := {"turn": 1.15, "crouch": 8, "lean": 3, "fx": -9, "fy": -8, "bx": 11, "by": -8, "ffx": -8, "fbx": 9}
const EASE := {"turn": 1, "crouch": 2, "fx": -8, "fy": -17, "bx": 9, "by": -17, "ffx": -4, "fbx": 5}
static var act := {
	"target": {"x": 70},
	"poses": [
		[-0.32, READY],
		[0.02, HIGH],
		[0.27, Px.merge(HIGH, {"y": -1})],
		[0.32, SLAM, "snap"],
		[0.85, Px.merge(SLAM, {"crouch": 7})],
		[1.5, EASE],
		[2.4, READY],
		[3.9, READY],
	],
	"hits": [
		{"t": 0.32, "stop": 0.1, "shake": 0.28, "amp": 3, "target": false},
		{"t": 0.6, "push": 1.2, "straw": 10, "y": -8, "skin": "char"},
		{"t": 3.5, "push": 0, "straw": 0, "flash": 0, "skin": null},
	],
	"dust": [{"t": 0.32, "x": 10, "n": 6, "dir": 1}, {"t": 0.32, "x": -10, "n": 6, "dir": -1}],
}

const SY := 0.2
const CHARGE := 0.32
const SPREAD := 0.75
static var SOOT := Px.hex("#0d0a12")
static var SOOT2 := Px.hex("#17121d")
static var WARM := Px.rgb(255, 176, 96)
# the dying flames: deep orange and red, no white heart
const EMBER_LAYERS := [[1.0, 1.0, 7], [0.7, 0.8, 6], [0.4, 0.55, 5]]


var H: Array
var REACH: float
var R: Px.Rng
var S: float
var ps: Px.Particles
var lights: Px.Lights
var GLOW: int
var sites := []
var t := 0.0
var burst := false


func front(tt: float) -> float:
	return REACH * Px.Ease.outCubic(Px.clamp((tt - CHARGE) / SPREAD))


func reachedAt(d: float) -> float:
	return CHARGE + SPREAD * (1.0 - Px.cbrt(1.0 - minf(1.0, d / REACH)))


func create(o: Dictionary) -> void:
	var F := Px.fit(o.palette, 9)
	H = Lib.hotFirst(F)
	REACH = o.reach
	R = Px.Rng.new(o.seed)
	var floor_ := func(): return 0.0
	S = o.seed * 7.0
	ps = Px.Particles.new({"rng": R, "ground": floor_, "sparks": [H[1], H[2], H[4], H[5]]})
	lights = Px.Lights.new()
	GLOW = Px.mix(Px.mix(H[3], H[4], 0.5), WHITE, 0.25)
	# the flames: rings of tongues on the floor, each lit as the front reaches it, flaring then burning down
	var r := 10
	while r <= REACH:
		var per := TAU * sqrt((r * r + pow(r * SY, 2.0)) / 2.0)
		var n := maxf(5.0, Px.round(per / 8.5))
		var k := 0
		while k < n:
			var a := ((k + R.range(0.15, 0.85)) / n) * TAU
			var rr := r + R.range(-3.0, 3.0)
			var q := minf(1.0, rr / REACH)
			# near the middle they flash and go out as the front passes; the rim, where it stops, burns on and down
			sites.append({"x": cos(a) * rr, "y": sin(a) * rr * SY, "back": sin(a) < 0.0, "t0": reachedAt(rr) + R.range(0.0, 0.04), "life": (0.3 + 1.0 * q * q) * R.range(0.85, 1.2), "h": R.range(9.0, 15.0) * (0.6 + 0.55 * q), "w": R.range(1.8, 2.7) * (0.75 + 0.3 * q), "n": R.int_(0, 1e5)})
			k += 1
		r += 9
	Px.sort(sites, func(a, b): return a.y - b.y)


func flames(p: Px.Painter, back: bool) -> void:
	var NZ := func(rate: float, seed: Variant = 0, off: float = 0.0) -> float: return Px.noise(t * rate + off, seed)
	for s: Dictionary in sites:
		if s.back != back:
			continue
		var age: float = t - s.t0
		if age < 0.0 or age > s.life:
			continue
		var u: float = age / s.life
		var rise := Px.Ease.outBack(Px.clamp(age / 0.08), 2.0)
		var fade := 1.0 - pow(maxf(0.0, (u - 0.1) / 0.9), 1.3)
		var h: float = s.h * rise * fade * (0.85 + 0.15 * Px.noise(t * 3.3, s.n)) * (1.0 + 0.5 * maxf(0.0, Px.noise(t * 2.6, s.n + 70) - 0.55))
		if h < 1.0:
			continue
		# fresh flames white-hot, then cooling as they burn down; the far ones a step dimmer
		var L: Array = (BACK_LAYERS if back else LAYERS) if u < 0.3 else (BACK_LAYERS if u < 0.65 else EMBER_LAYERS)
		Lib.flameTongue(p, s.x, s.y, h, s.w * (0.6 + 0.4 * fade), NZ.call(2.2, s.n + 40) * 1.5 - s.x * 0.02, NZ, s.n, H, L)


# the scorch: a translucent stain of soot where the fire has crossed, sparse embers cooling in it
func scorch(p: Px.Painter) -> void:
	var fr := front(t)
	var end := 1.0 - Px.smooth(meta.duration - 1.2, meta.duration - 0.15, t)
	if fr < 1.0 or end <= 0.0:
		return
	for y in range(floori(-fr * SY), ceili(fr * SY) + 1):
		for x in range(floori(-fr), ceili(fr) + 1):
			var d := Px.hypot(x + 0.5, (y + 0.5) / SY)
			if d > fr:
				continue
			var since := t - reachedAt(d)
			var h := Px.rand(x, y, S)
			var hot := 1.0 - since / (1.2 + h * 0.9)
			if hot > 0.0 and h < 0.03 + 0.06 * hot:
				p.px(x, y, H[3] if hot > 0.7 else (H[4] if hot > 0.45 else (H[5] if hot > 0.2 else H[6])))
				p.light(x, y, H[4], 0.3 * hot)
				continue
			p.blend(x, y, SOOT if h < 0.5 else SOOT2, minf(1.0, since * 3.0) * (0.55 - (d / REACH) * 0.25) * end)


func ring(p: Px.Painter, back: bool) -> void:
	var k := (t - CHARGE) / (SPREAD + 0.1)
	if k < 0.0 or k >= 1.0:
		return
	Px.band(p, 0.0, 0.0, front(t) + 1.5, SY, maxf(1.5, 6.0 * (1.0 - k)), 1.0 if k < 0.75 else (1.0 - k) / 0.25, [H[6], H[4], H[2], H[1]], func(g): return (sin(g) < 0.0) == back, k < 0.12)


func update(dt: float) -> void:
	t += dt
	# the charge: streaks of fire spiral in to the feet, heat building there
	if t < CHARGE - 0.05 and R.chance(0.9 * dt * 60.0):
		var a := R.range(0.0, TAU)
		var d := R.range(26.0, 54.0)
		var T := R.range(0.18, 0.26)
		var v := (d * 3.0) / (exp(3.0 * T) - 1.0)
		var x := cos(a) * d
		var y := minf(-2.0, -6.0 + sin(a) * d * 0.45)
		var l := Px.hypot(x, y + 4.0)
		if not l:
			l = 1.0
		ps.spawn(P.STREAK, x, y, (-x / l) * v, ((-4.0 - y) / l) * v, T, H[2] if R.chance(0.5) else H[3])
	if t < CHARGE and R.chance(0.5 * dt * 60.0 * (t / CHARGE)):
		ps.spawn(P.FIRE, R.range(-4.0, 4.0), -1.0, R.range(-8.0, 8.0), -R.range(20.0, 40.0), R.range(0.12, 0.24), 0, R.range(1.0, 2.2))
	if not burst and t >= CHARGE:
		burst = true
		lights.add(0.0, -18.0, 64.0, WARM, 0.85, 0.5)
		lights.add(0.0, -6.0, 30.0, WHITE, 0.8, 0.08)
		for i in 40:
			var a := R.range(0.0, TAU)
			var sp := R.range(80.0, 220.0)
			ps.spawn(P.SPARK, cos(a) * 3.0, -2.0, cos(a) * sp, sin(a) * sp * 0.4 - R.range(40.0, 120.0), R.range(0.2, 0.5))
	# fire shed off the burning ring: puffs that rise and some cool into smoke, and embers
	if t > CHARGE and t < CHARGE + SPREAD + 1.2:
		for i in 3:
			if not R.chance(0.75 * dt * 60.0):
				continue
			var s: Dictionary = R.pick(sites)
			var age: float = t - s.t0
			if age < 0.0 or age > s.life * 0.7:
				continue
			ps.spawn(P.FIRE, s.x + R.range(-1.0, 1.0), s.y - s.h * 0.6, R.range(-5.0, 5.0), -R.range(20.0, 40.0), R.range(0.2, 0.4), 0, R.range(1.2, 2.4), 0.0, (PF.SMOKES | (PF.BACK if s.back else 0)) if R.chance(0.5) else (PF.BACK if s.back else 0))
			if R.chance(0.12):
				ps.spawn(P.EMBER, s.x, s.y - s.h * 0.5, R.range(-15.0, 15.0), -R.range(30.0, 70.0), R.range(0.6, 1.3), H[3], 1.0, 0.0, PF.BACK if s.back else 0)
	ps.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	scorch(p)
	ring(p, true)
	flames(p, true)
	Lib.simDraw(p, ps, H, "back")
	# light on the floor running with the front
	var fr := front(t)
	var k := 0.0 if t < CHARGE else 1.0 - Px.smooth(CHARGE + SPREAD, CHARGE + SPREAD + 1.4, t)
	if k > 0.0:
		for i in 16:
			p.glow(cos((i / 16.0) * TAU) * fr, sin((i / 16.0) * TAU) * fr * SY - 3.0, 16.0, GLOW, 0.2 * k)


func draw(p: Px.Painter) -> void:
	ring(p, false)
	flames(p, false)
	Lib.simDraw(p, ps, H, "front")
	# the charge glowing at the feet, then the white flash as it goes
	if t < CHARGE:
		p.glow(0.0, -3.0, 8.0 + 22.0 * (t / CHARGE), GLOW, 0.6 * (t / CHARGE))
	if t >= CHARGE and t < CHARGE + 0.1:
		var kf := 1.0 - (t - CHARGE) / 0.1
		p.ellipse(0.0, -1.0, 14.0 * (0.6 + 0.4 * kf), 4.0, H[2])
		p.ellipse(0.0, -1.0, 9.0 * (0.6 + 0.4 * kf), 2.6, WHITE if kf > 0.5 else H[1])
	var k := Px.smooth(CHARGE - 0.05, CHARGE, t) * (1.0 - Px.smooth(CHARGE + SPREAD * 0.5, CHARGE + SPREAD + 1.2, t))
	if k > 0.0:
		p.glow(0.0, -6.0, 92.0, GLOW, 0.3 * k)
	lights.draw(p)
