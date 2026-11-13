# port-of: src/fx/explosions/smoke-bomb.js@e6b0cad38117f632250654efdd7e528425229d99
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Smoke bomb",
	"desc": "A round canister clinks down, fuse sparking, and pops: thick grey-violet smoke gushes out, rolls along the floor, billows into a cloud that hides all, then thins to wisps.",
	"tags": ["smoke", "smoke-bomb", "ninja", "vanish", "escape", "ground", "one-shot"],
	"size": [260, 176],
	"origin": [130, 156],
	"duration": 5,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"options": {
		"palette": ["#0e0b14", "#1e1828", "#30283e", "#463c58", "#62567a", "#867a9e", "#aea4c4"],
		"canister": ["#16121e", "#2a2434", "#443c52", "#686078", "#9c94ac"],
		"sparks": ["#fff3a6", "#ffe26b", "#ff8a2a", "#f2561d"],
		"seed": 3,
	},
}

const POP := 0.95
const R0 := 4.0
static var BAND := [Px.hex("#3a1418"), Px.hex("#7a2a24"), Px.hex("#b84a34")]
static var GRIT := [Px.hex("#5a4f6b"), Px.hex("#3e3650"), Px.hex("#776c88")]


# the canister's flight: it arcs down, bounces with a clink, rolls and stops. hit(x, speed) on each bounce
static func step(c: Dictionary, dt: float, hit: Variant = null) -> void:
	if c.rest:
		return
	c.vy += 900.0 * dt
	c.x += c.vx * dt
	c.y += c.vy * dt
	if c.y >= -R0 and c.vy > 0.0:
		c.y = -R0
		if c.vy > 80.0:
			if hit != null:
				hit.call(c.x, c.vy)
			c.vy = -c.vy * 0.38
			c.vx *= 0.78
		else:
			c.vy = 0.0
	if c.vy == 0.0 and c.y >= -R0 - 0.01:
		c.vx -= c.vx * 3.0 * dt
		if absf(c.vx) < 2.0:
			c.vx = 0.0
			c.rest = true
	c.a += (c.vx / R0 if c.vy == 0.0 else c.va) * dt


var o: Dictionary
var C: Array
var K: Array
var R: Px.Rng
var SM: Array
var W: int
var H: int
var OX: int
var OY: int
var X0: float
var X1: float
var Y0: float
var Y1: float
var ps: Px.Particles
var lights: Px.Lights
var can: Dictionary
var N := 52
var lobes: Array
var t := 0.0
var popped := false


func create(o_: Dictionary) -> void:
	o = o_
	C = Px.fit(o.palette, 7)
	K = Px.fit(o.canister, 5)
	R = Px.Rng.new(o.seed)
	var floor_ := func(): return 0.0
	SM = [C[5], C[4], C[3], C[2], C[1]]
	W = meta.size[0]
	H = meta.size[1]
	OX = meta.origin[0]
	OY = meta.origin[1]
	X0 = -OX + 3
	X1 = W - OX - 3
	Y0 = -OY + 3
	Y1 = H - OY - 3
	ps = Px.Particles.new({"rng": R, "ground": floor_, "sparks": o.sparks})
	lights = Px.Lights.new()
	# thrown in from the left so that it comes to rest on the anchor: run its path once to see where it stops
	var start := {"x": -70.0, "y": -60.0, "vx": 125.0, "vy": -80.0, "va": 7.0, "a": 0.0, "rest": false}
	var sim := start.duplicate()
	var i := 0
	while i < 2400 and not sim.rest:
		step(sim, 1.0 / 240.0)
		i += 1
	can = Px.merge(start, {"x": start.x - sim.x})
	# the smoke, gushing out front-loaded: rollers that slide out low along the floor, a fat core that stays over the
	# canister, a plume driven up, and a low trickle that keeps the base filled; they rise as they billow
	lobes = []
	for j in N:
		var kind: int = [0, 0, 1, 1, 2, 3][j % 6]
		var side := R.sign()
		var ang := ((-R.range(0.0, 0.25) if side > 0 else PI + R.range(0.0, 0.25)) if (kind == 0 or kind == 3) else -PI / 2.0 + R.range(-0.6, 0.6))
		var sp: float = [R.range(70.0, 170.0), R.range(0.0, 25.0), R.range(45.0, 95.0), R.range(20.0, 60.0)][kind]
		var r1: float = [R.range(12.0, 17.0), R.range(16.0, 22.0), R.range(13.0, 18.0), R.range(14.0, 19.0)][kind]
		var t0 := POP + R.range(0.45, 1.5) if kind == 3 else POP + 0.6 * pow(j / float(N - 1), 1.6) + R.range(0.0, 0.03)
		lobes.append({"kind": kind, "t0": t0, "vx": cos(ang) * sp, "vh": -sin(ang) * sp, "d": R.range(-1.0, 1.0), "r0": R.range(5.0, 8.0), "r1": r1, "f": R.range(-0.45, 0.4), "wob": R.range(0.0, TAU), "on": false, "x": 0.0, "h": 0.0, "age": 0.0})


func fuseTip() -> Array:
	return [can.x + sin(can.a) * (R0 + 2.5), can.y - cos(can.a) * (R0 + 2.5)]


func radius(b: Dictionary) -> float:
	return (b.r0 + (b.r1 - b.r0) * (1.0 - exp(-b.age / 0.28))) * (1.0 + 0.05 * sin(t * 3.0 + b.wob)) * (1.0 + 0.35 * thin(b))


func thin(b: Dictionary) -> float:
	return Px.smooth(2.5 + b.f, 3.9 + b.f * 0.6, t)


func update(dt: float) -> void:
	t += dt
	step(can, dt, func(x, sp):
		# a clink: a few bright specks and a puff of dust
		for i in 3:
			ps.spawn(P.SPARK, x, -1.0, R.range(-70.0, 70.0), -R.range(40.0, 110.0), R.range(0.06, 0.14))
		for i in 3:
			ps.spawn(P.DUST, x + R.range(-2.0, 2.0), -0.5, R.sign() * R.range(10.0, 40.0), -R.range(4.0, 14.0), R.range(0.3, 0.55), GRIT[2], R.range(1.4, 2.4)))
	if t < POP:
		# the fuse: sparks spitting off its tip, quicker as it burns down, and a thread of smoke
		var ft := fuseTip()
		var fx: float = ft[0]
		var fy: float = ft[1]
		var hurry := Px.smooth(POP - 0.4, POP, t)
		if R.chance((26.0 + 50.0 * hurry) * dt):
			ps.spawn(P.SPARK, fx, fy, R.range(-50.0, 50.0), -R.range(30.0, 100.0), R.range(0.08, 0.18))
		if R.chance(8.0 * dt):
			ps.spawn(P.VAPOUR, fx, fy - 1.0, R.range(-4.0, 4.0), -R.range(10.0, 18.0), R.range(0.5, 0.8), C[5], R.range(1.0, 1.8))
	elif not popped:
		popped = true
		# the pop: a flash, a soft light that dies fast, sparks and grit, the canister jolted
		lights.add(can.x, -9.0, 64.0, C[6], 0.75, 0.22)
		lights.add(can.x, -5.0, 22.0, WHITE, 0.7, 0.06)
		for i in 30:
			var a := R.range(-PI - 0.35, 0.35)
			var sp := R.range(120.0, 300.0)
			ps.spawn(P.SPARK, can.x, -5.0, cos(a) * sp, sin(a) * sp - 40.0, R.range(0.15, 0.4))
		for i in 26:
			var u := R.range(-1.0, 1.0)
			var a := -PI / 2.0 + u * 0.9
			var sp := R.range(80.0, 220.0) * (1.0 - 0.35 * absf(u))
			ps.spawn(P.GRIT, can.x + u * 4.0, -1.0, cos(a) * sp, sin(a) * sp, R.range(0.9, 1.6), R.pick(GRIT), 2.0 if R.chance(0.35) else 1.0)
		can.merge({"vy": -95.0, "vx": R.range(-25.0, 25.0), "va": R.sign() * 9.0, "rest": false}, true)
	# the cloud: lobes slide out low, slow, then rise as they billow; a breeze takes them late on
	var wind := 6.0 * Px.smooth(1.8, 3.2, t)
	for b in lobes:
		if not b.on:
			if t < b.t0:
				continue
			b.on = true
			b.x = can.x + R.range(-2.0, 2.0)
			b.h = 1.0
		b.age += dt
		b.vx -= b.vx * 2.4 * dt
		# rollers hug the floor for a while; everything rises as it billows, gently
		b.vh += [14.0 * Px.smooth(0.7, 1.6, b.age), 3.0 + 9.0 * Px.smooth(0.8, 1.8, b.age), 6.0 + 12.0 * Px.smooth(0.3, 1.4, b.age), 10.0 * Px.smooth(0.8, 1.6, b.age)][b.kind] * dt
		b.vh -= b.vh * 1.6 * dt
		b.x += (b.vx + wind) * dt
		b.h = maxf(0.0, b.h + b.vh * dt)
		# thinning, it sheds wisps that drift off
		var k := thin(b)
		if k > 0.12 and k < 0.85 and R.chance(1.8 * dt):
			var r := radius(b)
			var life := minf(R.range(1.0, 1.6), meta.duration - 0.15 - t)
			if life > 0.3:
				ps.spawn(P.VAPOUR, b.x + R.range(-r, r) * 0.5, -(b.h + r * 1.4), wind + R.range(-6.0, 10.0), -R.range(8.0, 20.0), life, C[4], r * R.range(0.3, 0.45))
	# the spent canister keeps smoking a little
	if t > POP + 0.5 and t < 4.1 and R.chance(4.0 * dt):
		ps.spawn(P.VAPOUR, can.x, can.y - 3.0, R.range(-3.0, 3.0), -R.range(8.0, 16.0), R.range(0.6, 0.9), C[4], R.range(1.5, 2.5))
	ps.update(dt)
	Lib.cull(ps, X0, Y0, X1, Y1)
	Lib.fadeEdges(ps, X0, X1, 20.0, Y1)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	ps.draw(p, "back")
	clouds(p, true)


func draw(p: Px.Painter) -> void:
	# the canister: live with its fuse burning, then spent; it fades as the last smoke clears
	var fade := 1.0 - Px.smooth(4.3, 4.8, t)
	if fade > 0.0:
		drawCanister(p, K, can, t < POP, fade)
	if t < POP:
		var ft := fuseTip()
		p.px(ft[0], ft[1], WHITE if sin(t * 50.0) > 0.0 else Px.hex(o.sparks[1]))
		p.glow(ft[0], ft[1], 6.0, Px.hex(o.sparks[2]), 0.45 + 0.2 * sin(t * 37.0))
	clouds(p, false)
	ps.draw(p, "front")
	# the flash of the pop
	var u := t - POP
	if u >= 0.0 and u < 0.067:
		p.circle(can.x, -5.0, 6.5, C[5])
		p.circle(can.x, -5.0, 4.5, WHITE)
	if u >= 0.0 and u < 0.16:
		Px.flare(p, can.x, -5.0, 22.0 * (1.0 - u / 0.16), 1.0 - u / 0.16, [C[3], C[4], C[5], C[6]])
	if u >= 0.0 and u < 0.35:
		Lib.pool(p, can.x, 1.0, 50.0, 8.0, C[6], 0.5 * (1.0 - u / 0.35))
	lights.draw(p)


# far lobes behind, near ones in front; each a cel-shaded ball: a lit crescent on top, a mid tone, a dark underside.
# The cloud is lit from above, so lobes low in it sit in its shadow a step darker; anything nearing the top of the
# canvas thins out
func clouds(p: Px.Painter, back: bool) -> void:
	var on := lobes.filter(func(b): return b.on)
	if not on.size():
		return
	var top := 0.0
	for b in on:
		top = minf(top, -(b.h + radius(b) * 1.92))
	for b in Px.sort(on.filter(func(b): return (b.d < -0.35) == back), func(a, b): return a.d - b.d):
		var r := radius(b)
		var y: float = -(b.h + r * 0.92) + b.d * 2.5
		var k := thin(b)
		var a := minf(1.0, b.age / 0.05) * pow(1.0 - k, 1.4) * 0.97 * (1.0 - Px.smooth(-OY + 34, -OY + 6, y - r))
		if a <= 0.01:
			continue
		var shade := 1 if (y - top) / maxf(20.0, -top) > 0.55 else 0
		Lib.lobe(p, b.x, y, r, SM, SM, 0.0, 0.0, a, b.d, mini(2, shade + (1 if k > 0.6 else 0)), 1)


# a round canister turned by its roll: dark metal lit from the top left, a red band, an outline, and a fuse on top
# while it's live (spent, its cap is blown off)
static func drawCanister(p: Px.Painter, K_: Array, c: Dictionary, live: bool, a: float) -> void:
	var ca: float = cos(c.a)
	var sa: float = sin(c.a)
	var cxx: float = c.x
	var cyy: float = c.y
	p.shade(cxx - R0 - 2.0, cyy - R0 - 2.0, cxx + R0 + 2.0, cyy + R0 + 2.0, func(px: float, py: float, out):
		var dx := px - cxx
		var dy := py - cyy
		var d := Px.hypot(dx, dy)
		if d > R0 + 1.0:
			return null
		out.a = a
		if d > R0:
			return Lib.OUTLINE
		var v := -dx * sa + dy * ca
		var lit := -(dx * 0.6 + dy * 0.8) / R0
		if absf(v) < 0.9:
			return BAND[2 if lit > 0.3 else (1 if lit > -0.4 else 0)]
		if d < R0 * 0.5 and lit > 0.45:
			return K_[4]
		return K_[3 if lit > 0.5 else (2 if lit > 0.0 else (1 if lit > -0.5 else 0))])
	var cx := cxx + sa * R0
	var cy := cyy - ca * R0
	if live:
		p.line(cx, cy, cx + sa * 2.5, cy - ca * 2.5, Px.hex("#8a6a48"), a)
	else:
		p.dot(cx, cy, K_[0], a)
