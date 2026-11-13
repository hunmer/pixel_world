# port-of: src/fx/ice/frost-nova.js@ed3ad0e118a720f167f779bb81d5cb2b2623aab2
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const P := Px.P
const B := Px.B
const WHITE := Px.WHITE

static var meta := {
	"name": "Frost nova",
	"desc": "Frost spirals into a spinning snowflake, then a wave blooms three rings of ice crystals round the caster; snow drifts, frost creeps, and the ice melts back into the floor.",
	"tags": ["ice", "nova", "aoe", "frost", "magic", "one-shot"],
	"size": [288, 192],
	"origin": [144, 150],
	"duration": 3.4,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {"palette": ["#151a3d", "#212f6b", "#2c58aa", "#3a8bd8", "#62c8f4", "#a6ecff", "#dcfbff", "#ffffff"], "reach": 104, "seed": 4},
}

static var HIGH := {"turn": 1.15, "crouch": 0, "fx": -7, "fy": -44, "bx": 8, "by": -44, "ffx": -5, "fbx": 6}
static var SLAM := {"turn": 1.15, "crouch": 8, "lean": 3, "fx": -9, "fy": -8, "bx": 11, "by": -8, "ffx": -8, "fbx": 9}
static var EASE := {"turn": 1, "crouch": 2, "fx": -8, "fy": -17, "bx": 9, "by": -17, "ffx": -4, "fbx": 5}
static var act := {
	"target": {"x": 76},
	"poses": [
		[-0.34, Px.READY],
		[-0.04, Px.merge(HIGH, {"crouch": 2, "fy": -36, "by": -36})],
		[0.36, HIGH],
		[0.42, SLAM, "snap"],
		[0.9, Px.merge(SLAM, {"crouch": 7})],
		[1.9, Px.merge(SLAM, {"crouch": 6})],
		[2.6, EASE],
		[3.4, Px.READY],
	],
	"hits": [
		{"t": 0.42, "stop": 0.1, "shake": 0.26, "amp": 2, "target": false},
		{"t": 0.66, "push": 0.9, "straw": 6, "y": -10, "skin": "ice", "shiver": 1.7},
		{"t": 2.9, "push": 0.2, "straw": 0, "flash": 0, "skin": null},
	],
	"dust": [{"t": 0.42, "x": 10, "n": 5, "dir": 1, "c": "#d8f2ff"}, {"t": 0.42, "x": -10, "n": 5, "dir": -1, "c": "#d8f2ff"}],
}

const CHARGE := 0.42
const SPREAD := 0.62
const HOLD := 1.95
const MELT := 0.7
const CORE_Y := -24.0
# three rings of crystals: tall ones hugging the caster, smaller ones further out
const RINGS := [
	{"q": [0.15, 0.24], "h": [24.0, 32.0], "w": [10.0, 13.0], "n": 2, "kids": 2},
	{"q": [0.36, 0.52], "h": [13.0, 19.0], "w": [7.0, 9.0], "n": 3, "kids": 1},
	{"q": [0.62, 0.9], "h": [5.0, 10.0], "w": [4.0, 6.0], "n": 4, "kids": 0},
]


# frost on the floor: a white crust, little tufts, a dithered bloom under the surface
static func frost(p: Px.Painter, C: Array, x0: float, x1: float, reach: float, a: float, edge: float) -> void:
	var x := floorf(x0)
	while x <= ceilf(x1):
		var d := absf(x + 0.5)
		var q := d / reach
		var k := Px.clamp((a * 1.15 - q) / 0.15)
		if k <= 0.0:
			x += 1.0
			continue
		var h := Px.rand(x, 17)
		var fresh := edge > 0.0 and d > edge - 3.0
		var tuft := Px.round((1.0 + Px.rand(x, 5) * 3.0) * (1.0 - q * 0.6)) if h < 0.45 else 0.0
		var D := (4.0 + Px.rand(x, 11) * 4.0) * (1.0 - q * 0.5)
		p.dot(x, 0.0, WHITE if (fresh or h < 0.25) else C[6], k)
		var j := 1.0
		while j <= tuft:
			p.dot(x, -j, WHITE if j == tuft else C[5], k)
			j += 1.0
		if tuft > 1.0 and Px.rand(x, 9) < 0.5:
			p.dot(x + (-1.0 if Px.rand(x, 3) < 0.5 else 1.0), -tuft + 1.0, C[6], k)
		j = 1.0
		while j <= D:
			var v := j / D
			p.dot(x, j, WHITE if Px.rand(x * 31.0 + j, 7) < 0.06 else (C[6] if v < 0.25 else (C[5] if v < 0.55 else C[4])), k * (1.1 - v) * (1.3 if fresh else 1.0))
			j += 1.0
		x += 1.0


# the snowflake the cold gathers into: six arms with side branches, spinning, pulsing
static func snowflake(p: Px.Painter, C: Array, x: float, y: float, L: float, spin: float, k: float) -> void:
	if L < 0.8:
		return
	for i in 6:
		var a := spin + (i * TAU) / 6.0
		var ca := cos(a)
		var sa := sin(a)
		var d := 0.0
		while d <= L:
			p.dot(x + ca * d, y + sa * d, WHITE if d < L * 0.4 else C[6], k + 0.2)
			d += 0.5
		if L > 3.0:
			for s: int in [-1, 1]:
				var bx := x + ca * L * 0.6
				var by := y + sa * L * 0.6
				var ba := a + s * 0.9
				d = 0.0
				while d <= L * 0.35:
					p.dot(bx + cos(ba) * d, by + sin(ba) * d, C[5], k)
					d += 0.5
	p.px(x, y, WHITE)
	p.glow(x, y, 10.0 + L * 3.0, C[5], 0.35 + 0.5 * k)


var C: Array
var DIM: Array
var REACH: float
var R: Px.Rng
var ps: Px.Particles
var bits: Px.Bits
var lights: Px.Lights
var sites: Array = []
var t := 0.0
var released := false


func front(tt: float) -> float:
	return 0.0 if tt < CHARGE else REACH * (1.0 - pow(1.0 - Px.clamp((tt - CHARGE) / SPREAD), 3.0))


func reachedAt(d: float) -> float:
	return CHARGE + SPREAD * (1.0 - Px.cbrt(1.0 - minf(1.0, d / REACH)))


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	DIM = [C[0], C[0], C[1], C[2], C[3], C[4], C[5], C[6]]
	REACH = o.reach
	R = Px.Rng.new(o.seed)
	var floor_ := func(): return 0.0
	ps = Px.Particles.new({"rng": R, "ground": floor_, "sparks": [C[7], C[6], C[5], C[4]], "haze": C[5]})
	bits = Px.Bits.new({"ground": floor_})
	lights = Px.Lights.new()
	# lay out the crystals: both sides, three rings, alternating back and front rows
	sites = []
	for side: int in [-1, 1]:
		for ri in RINGS.size():
			var rg: Dictionary = RINGS[ri]
			for i in rg.n:
				var q: float = rg.q[0] + ((rg.q[1] - rg.q[0]) * (i + R.range(0.2, 0.8))) / rg.n
				var h := R.range(rg.h[0], rg.h[1])
				var w := R.range(rg.w[0], rg.w[1])
				var parts := [{"dx": 0.0, "h": h, "w": w, "lean": side * h * R.range(0.1, 0.28)}]
				for k in rg.kids:
					var s: int = -side if k % 2 else side
					var kh := h * R.range(0.4, 0.62)
					parts.push_front({"dx": s * R.range(0.3, 0.5) * w, "h": kh, "w": w * 0.62, "lean": s * kh * R.range(0.35, 0.6)})
				sites.append({"x": side * q * REACH, "d": q * REACH, "h": h, "back": (i + ri + (1 if side > 0 else 0)) % 2 == 1, "t0": reachedAt(q * REACH) + R.range(0.0, 0.03), "up": false, "parts": parts, "phase": R.next()})


func sink(tt: float) -> float:
	return Px.smooth(HOLD, HOLD + MELT, tt)


func drawCrystals(p: Px.Painter, back: bool) -> void:
	var m := sink(t)
	for s: Dictionary in sites:
		if not s.up or s.back != back or m >= 1.0:
			continue
		var g := Px.Ease.outBack(Px.clamp((t - s.t0) / 0.1), 2.6)
		var white: bool = t < s.t0 + 0.03
		var sw: float = fmod((t - s.t0) * 0.7 + s.phase * 3.0, 1.6) / 0.5
		for q: Dictionary in s.parts:
			Px.crystal(p, s.x + q.dx, -1.0 if back else 0.0, q.h * g * (1.0 - m), q.w * (1.0 - m * 0.3), q.lean * g * (1.0 - m), DIM if back else C, {"white": white, "glint": sw if sw <= 1.0 else -1.0})


func ring(p: Px.Painter, back: bool) -> void:
	if t < CHARGE:
		return
	var u := Px.clamp((t - CHARGE) / (SPREAD + 0.15))
	if u >= 1.0:
		return
	Px.band(p, 0.0, 0.0, front(t) + 2.0, 0.16, maxf(2.0, 10.0 * pow(1.0 - u, 0.7)), 1.0 if u < 0.75 else (1.0 - u) / 0.25, C, func(g: float) -> bool: return (sin(g) < 0.0) == back, t - CHARGE < 0.1)
	if not back:
		for s: int in [-1, 1]:
			p.glow(s * (front(t) + 2.0), -2.0, 22.0, C[5], 0.55 * (1.0 - u))


func update(dt: float) -> void:
	t += dt
	if t < CHARGE - 0.06:
		# the cold gathers: streaks spiral in to the core, vapour slides in along the floor
		if R.chance(0.9):
			var a := R.range(0.0, TAU)
			var D := R.range(26.0, 58.0)
			var T := R.range(0.2, 0.3)
			var v := (D * 3.0) / (exp(3.0 * T) - 1.0)
			var x := cos(a) * D
			var y := minf(CORE_Y + sin(a) * D * 0.8, -2.0)
			var l := Px.hypot(x, y - CORE_Y)
			if not l:
				l = 1.0
			ps.spawn(P.STREAK, x, y, (-x / l) * v, ((CORE_Y - y) / l) * v, T, C[6] if R.chance(0.5) else C[5])
		if R.chance(0.14):
			var s := R.sign()
			ps.spawn(P.VAPOUR, s * R.range(28.0, 60.0), -R.range(0.0, 2.0), -s * R.range(35.0, 70.0), -R.range(0.0, 3.0), R.range(0.35, 0.5), C[6], R.range(2.0, 3.0))
	if t >= CHARGE and not released:
		released = true
		lights.add(0.0, CORE_Y, 84.0, C[4], 0.8, 0.55)
		lights.add(0.0, CORE_Y, 45.0, WHITE, 0.7, 0.12)
		for i in 22:
			var a := R.range(-PI, 0.25)
			var sp := R.range(110.0, 280.0)
			bits.add({"kind": B.SHARD, "x": R.range(-3.0, 3.0), "y": CORE_Y, "vx": cos(a) * sp, "vy": sin(a) * sp, "g": 0.7, "drag": 0.6, "bounce": 0.3, "life": R.range(0.9, 1.5), "a": R.range(0.0, TAU), "va": R.range(-20.0, 20.0), "s": R.range(1.5, 3.5), "c": R.pick([C[7], C[6], C[5]])})
		for i in 14:
			var a := R.range(-PI, 0.0)
			var sp := R.range(40.0, 160.0)
			ps.spawn(P.FLAKE, 0.0, CORE_Y, cos(a) * sp, sin(a) * sp, R.range(1.2, 1.8), WHITE if R.chance(0.6) else C[6], R.range(0.5, 1.6))
	var fr := front(t)
	if t > CHARGE and t < CHARGE + SPREAD:
		for s: int in [-1, 1]:
			ps.spawn(P.VAPOUR, s * fr + R.range(-2.0, 2.0), -R.range(0.0, 5.0), s * R.range(15.0, 75.0), -R.range(2.0, 15.0), R.range(0.6, 1.0), C[6] if R.chance(0.7) else C[5], R.range(3.0, 5.5) * (1.0 - 0.4 * (fr / REACH)))
			if R.chance(0.45):
				ps.spawn(P.FLAKE, s * fr, -2.0, s * R.range(10.0, 45.0), -R.range(30.0, 85.0), R.range(1.1, 1.9), WHITE if R.chance(0.5) else C[6], R.range(0.5, 1.2))
	for s: Dictionary in sites:
		if not s.up and t >= s.t0:
			s.up = true
			# each crystal punches up with a spray of shards, a puff and a glint
			var i := 0
			while i < 2 + Px.round(s.h / 8.0):
				var a := -PI / 2.0 + R.range(-1.3, 1.3)
				var sp: float = R.range(60.0, 200.0) * (0.5 + s.h / 40.0)
				bits.add({"kind": B.SHARD, "x": s.x + R.range(-3.0, 3.0), "y": 0.0, "vx": cos(a) * sp, "vy": sin(a) * sp, "g": 0.8, "drag": 0.6, "bounce": 0.3, "life": R.range(0.9, 1.6), "a": R.range(0.0, TAU), "va": R.range(-18.0, 18.0), "s": R.range(1.5, 3.0), "c": R.pick([C[7], C[6], C[5]])})
				i += 1
			ps.spawn(P.VAPOUR, s.x, -1.0, R.range(-30.0, 30.0), -R.range(2.0, 8.0), R.range(0.5, 0.9), C[6], R.range(2.5, 4.0))
			if s.h > 10.0:
				ps.spawn(P.STAR, s.x + R.range(-3.0, 3.0), -R.range(4.0, s.h * 0.8), 0.0, -3.0, R.range(0.3, 0.6), C[6], R.range(1.0, 2.4))
	# while it holds: glints run over the crystals, snow drifts down
	if t > CHARGE + 0.2 and t < HOLD + 0.2:
		if R.chance(0.5):
			var s: Dictionary = R.pick(sites)
			if s.up:
				ps.spawn(P.STAR, s.x + R.range(-3.0, 3.0), -R.range(2.0, s.h * 0.9), 0.0, -3.0, R.range(0.3, 0.6), C[6] if R.chance(0.6) else WHITE, R.range(0.6, 2.2))
		if t < HOLD - 0.3 and R.chance(0.16):
			ps.spawn(P.FLAKE, R.range(-1.0, 1.0) * fr, -R.range(40.0, 90.0), R.range(-5.0, 5.0), R.range(3.0, 10.0), R.range(1.1, 1.5), WHITE if R.chance(0.5) else C[6], R.range(0.5, 1.4))
	# melting: drips run off the crystals, vapour lifts off the floor
	if t > HOLD and t < HOLD + MELT:
		if R.chance(0.5):
			var s: Dictionary = R.pick(sites)
			bits.add({"kind": B.DRIP, "x": s.x + R.range(-3.0, 3.0), "y": -R.range(3.0, s.h * 0.6 * (1.0 - sink(t))), "vy": 10.0, "g": 0.6, "life": 1.0, "c": C[5]})
		if R.chance(0.25):
			ps.spawn(P.VAPOUR, R.range(-1.0, 1.0) * REACH * 0.8, -R.range(0.0, 3.0), R.range(-10.0, 10.0), -R.range(6.0, 16.0), R.range(0.6, 1.0), C[5], R.range(3.0, 5.0))
	ps.update(dt)
	bits.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	var out := 1.0 - Px.smooth(HOLD + 0.2, HOLD + MELT + 0.6, t)
	var fr := front(t)
	if out > 0.0 and t > CHARGE:
		frost(p, C, -maxf(12.0, fr + 1.0), maxf(12.0, fr + 1.0), REACH, out, fr)
	ring(p, true)
	drawCrystals(p, true)
	ps.draw(p, "back")


func draw(p: Px.Painter) -> void:
	ring(p, false)
	drawCrystals(p, false)
	if t < CHARGE:
		var k := t / CHARGE
		var beat := 1.0 + 0.25 * exp(-pow(t - CHARGE * 0.55, 2.0) / 0.002) + 0.3 * exp(-pow(t - CHARGE * 0.85, 2.0) / 0.002)
		snowflake(p, C, 0.0, CORE_Y, (2.0 + 5.5 * k * k) * beat, t * 4.0, k)
	elif t < CHARGE + 0.22:
		var a := (t - CHARGE) / 0.22
		Px.flare(p, 0.0, CORE_Y, 36.0 * pow(1.0 - a, 1.5), 1.0 - a, C)
		p.glow(0.0, CORE_Y, 46.0, WHITE, 0.6 * (1.0 - a))
	# the frosted floor gives off a cold light while the ice stands
	if t > CHARGE:
		var k := (1.0 - Px.smooth(HOLD, HOLD + MELT + 0.3, t)) * (0.85 + 0.15 * sin(t * 2.4))
		var fr := front(t)
		for i in range(-3, 4):
			p.glow((i / 3.5) * fr, -4.0, 26.0, C[4], 0.16 * k)
	bits.draw(p)
	ps.draw(p, "front")
	lights.draw(p)
