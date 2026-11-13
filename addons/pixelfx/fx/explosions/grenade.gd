# The blast (fire puffs that cool into smoke, sparks, grit, scorch, rings, lights) is adapted from Sprite Fusion's
# open-source explosion (https://www.spritefusion.com/pixel-art-vfx/explosion), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/explosions/grenade.js@9445937985bf8cbf63fcb1d708cc634c463bcea9
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const PF := Px.PF
const B := Px.B
const WHITE := Px.WHITE

static var meta := {
	"name": "Grenade",
	"desc": "A grenade is lobbed in, bounces, rolls to a stop with its fuse fizzing, shudders, then blows: a white flash, shrapnel streaks, sparks, a small fireball and a scorch.",
	"tags": ["explosion", "grenade", "shrapnel", "fire", "smoke", "ground", "one-shot"],
	"size": [300, 200],
	"origin": [160, 170],
	"duration": 4.2,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"options": {
		"palette": ["#4a1712", "#c9281f", "#f2561d", "#ff8a2a", "#ffc23d", "#ffe26b", "#fff3a6", "#ffffff"],
		"body": ["#141a10", "#2c3a1e", "#4a5c30", "#6e8446", "#9ab06a"],
		"seed": 6,
	},
}

const BLOW := 1.62
const RB := 6.2


var F: Array
var FR: Array
var HR: Array
var G: Array
var R: Px.Rng
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
var bits: Px.Bits
var DUST: int
var METAL: Array
# the grenade: lobbed from the left, it bounces, rolls and settles
var g := {"x": -140.0, "y": -70.0, "vx": 168.0, "vy": -150.0, "a": 0.0, "va": -9.0, "rest": false}
var t := 0.0
var blown := false
var bx := 0.0


func create(o: Dictionary) -> void:
	F = Px.fit(o.palette, 8)
	FR = Lib.fireRamp(F)
	HR = Lib.heatRamp(FR)
	G = Px.fit(o.body, 5)
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
	ps = Px.Particles.new({"rng": R, "ground": floor_, "sparks": [F[6], F[5], F[3], F[2]]})
	lights = Px.Lights.new()
	bits = Px.Bits.new({"ground": floor_})
	DUST = Px.hex("#7d7280")
	METAL = [Px.hex("#3a3c46"), Px.hex("#6a6e7c"), Px.hex("#a8acb8")]


func blast() -> void:
	blown = true
	bx = g.x
	var y := -5.0
	lights.add(bx, y - 10.0, 70.0, Px.mix(F[3], F[6], 0.45), 0.85, 0.5)
	lights.add(bx, y, 30.0, WHITE, 0.7, 0.07)
	# shrapnel: hot streaks flying straight and far, sparks that fall and bounce
	for i in 38:
		var a := R.range(-PI + 0.04, -0.04)
		var sp := R.range(380.0, 640.0)
		ps.spawn(P.MOTE, bx, y, cos(a) * sp, sin(a) * sp, R.range(0.12, 0.26), R.pick([F[7], F[6], F[5]]), R.range(0.6, 0.9))
	for i in 60:
		var a := R.range(0.0, TAU)
		var sp := R.range(140.0, 360.0)
		ps.spawn(P.SPARK, bx, y, cos(a) * sp, sin(a) * sp - 60.0, R.range(0.2, 0.55))
	# a small fireball that cools into smoke
	for i in 4:
		ps.spawn(P.FIRE, bx + R.range(-2.0, 2.0), y + R.range(-2.0, 2.0), R.range(-15.0, 15.0), R.range(-30.0, -8.0), R.range(0.16, 0.26), 0, R.range(6.0, 8.0))
	for i in 16:
		var a := R.range(-PI - 0.2, 0.2)
		var d := R.range(0.0, 6.0)
		var sp := R.range(40.0, 150.0)
		ps.spawn(P.FIRE, bx + cos(a) * d, y + sin(a) * d, cos(a) * sp, sin(a) * sp * 0.8 - 30.0, R.range(0.45, 0.9), 0, R.range(3.5, 7.0), 0.0, PF.SMOKES if R.chance(0.5) else 0)
	for i in 9:
		var a := R.range(-PI, 0.0)
		var d := R.range(2.0, 10.0)
		ps.spawn(P.SMOKE, bx + cos(a) * d, y + sin(a) * d, cos(a) * 25.0, -R.range(20.0, 60.0), R.range(1.4, 2.1), 0, R.range(6.0, 10.0), R.range(0.05, 0.3), PF.BIG)
	for i in 30:
		var a := R.range(0.0, TAU)
		var sp := R.range(30.0, 120.0)
		ps.spawn(P.EMBER, bx, y, cos(a) * sp, sin(a) * sp - 50.0, R.range(0.8, 1.8), F[3])
	# the casing in pieces, and the floor's grit and dust
	for i in 12:
		var a := R.range(-PI + 0.2, -0.2)
		var sp := R.range(150.0, 330.0)
		bits.add({"kind": B.SHARD, "x": bx, "y": y, "vx": cos(a) * sp, "vy": sin(a) * sp, "g": 1.0, "drag": 0.5, "bounce": 0.3, "life": R.range(1.4, 2.1), "a": R.range(0.0, TAU), "va": R.range(-24.0, 24.0), "s": R.range(2.0, 3.5), "c": R.pick(METAL)})
	for i in 70:
		var u := R.range(-1.0, 1.0)
		var a := -PI / 2.0 + u * 0.8
		var sp := R.range(100.0, 300.0) * (1.0 - 0.4 * absf(u))
		ps.spawn(P.GRIT, bx + u * 4.0, -1.0, cos(a) * sp, sin(a) * sp, R.range(1.0, 1.8), R.pick([Px.hex("#5a4f6b"), Px.hex("#3e3650"), Px.hex("#776c88")]), 2.0 if R.chance(0.35) else 1.0)
	for i in 10:
		var s := R.sign()
		ps.spawn(P.SMOKE, bx + s * R.range(0.0, 6.0), -R.range(1.0, 4.0), s * R.range(60.0, 180.0), -R.range(2.0, 10.0), R.range(1.0, 1.7), DUST, R.range(5.0, 8.0), R.range(0.0, 0.05), PF.BIG)


func update(dt: float) -> void:
	t += dt
	if not blown:
		# the lob, the bounces, the roll
		if not g.rest:
			g.vy += 900.0 * dt
			g.x += g.vx * dt
			g.y += g.vy * dt
			if g.y >= -RB and g.vy > 0.0:
				g.y = -RB
				if g.vy > 90.0:
					# a clink, a puff of dust
					for i in 4:
						ps.spawn(P.DUST, g.x + R.range(-2.0, 2.0), -0.5, R.sign() * R.range(10.0, 40.0), -R.range(4.0, 16.0), R.range(0.3, 0.6), DUST, R.range(1.5, 2.6))
					for i in 3:
						ps.spawn(P.SPARK, g.x, -1.0, R.range(-60.0, 60.0), -R.range(40.0, 120.0), R.range(0.08, 0.16))
					g.vy = -g.vy * 0.36
					g.vx *= 0.8
				else:
					g.vy = 0.0
			if g.y >= -RB - 0.01 and g.vy == 0.0:
				g.vx -= g.vx * 2.4 * dt
				g.va = -g.vx / RB
				if absf(g.vx) < 3.0:
					g.rest = true
					g.vx = 0.0
			g.a += g.va * dt
		# the fuse: sparks spitting off its tip, a thread of smoke, faster as it runs down
		var tip := fuse(g)
		var hurry := Px.smooth(BLOW - 0.5, BLOW, t)
		if R.chance((24.0 + 50.0 * hurry) * dt):
			ps.spawn(P.SPARK, tip[0], tip[1], R.range(-50.0, 50.0), -R.range(30.0, 110.0), R.range(0.08, 0.2))
		if R.chance(9.0 * dt):
			ps.spawn(P.VAPOUR, tip[0], tip[1] - 1.0, R.range(-4.0, 4.0), -R.range(10.0, 20.0), R.range(0.5, 0.9), Px.hex("#8a8494"), R.range(1.2, 2.0))
		if t >= BLOW:
			blast()
	bits.update(dt)
	var i := bits.list.size() - 1
	while i >= 0:
		if bits.list[i].x < X0 + 3.0 or bits.list[i].x > X1 - 3.0 or bits.list[i].y < Y0 + 3.0:
			bits.list.remove_at(i)
		i -= 1
	ps.update(dt)
	Lib.cull(ps, X0, Y0, X1, Y1)
	Lib.fadeEdges(ps, X0, X1, 24.0, Y1)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	if blown:
		var u := t - BLOW
		Lib.scorch(p, HR, u, 22.0, 1.6, 1.0 - Px.smooth(meta.duration - BLOW - 0.8, meta.duration - BLOW - 0.15, u), 2.0)
		var k := u / 0.4
		if k < 1.0:
			Px.band(p, bx, 0.5, 70.0 * Px.Ease.outCubic(k), 0.16, maxf(1.0, 3.5 * (1.0 - k)), 1.15 - k, [Px.hex("#4a3f69"), Px.hex("#6e6390"), F[3], F[6]], func(g2): return sin(g2) < 0.0)
	Lib.drawPs(p, ps, "back", FR)


func draw(p: Px.Painter) -> void:
	if not blown:
		# the grenade, shuddering in its last half second, the fuse glowing
		var shake := Px.smooth(BLOW - 0.45, BLOW, t)
		var jx := shake * sin(t * 90.0) * 0.8
		drawGrenade(p, G, g.x + jx, g.y, g.a)
		var tip := fuse(Px.merge(g, {"x": g.x + jx}))
		p.px(tip[0], tip[1], F[6] if sin(t * 50.0) > 0.0 else F[5])
		p.glow(tip[0], tip[1], 6.0 + 3.0 * shake, F[4], 0.5 + 0.3 * sin(t * 37.0))
	else:
		var u := t - BLOW
		var k := u / 0.4
		if k < 1.0:
			Px.band(p, bx, 0.5, 70.0 * Px.Ease.outCubic(k), 0.16, maxf(1.0, 3.5 * (1.0 - k)), 1.15 - k, [Px.hex("#4a3f69"), Px.hex("#6e6390"), F[3], F[6]], func(g2): return sin(g2) >= 0.0)
	bits.draw(p)
	Lib.drawPs(p, ps, "front", FR)
	if blown:
		var u := t - BLOW
		# the flash: a hot disc for two frames, a flare, a ring of light
		if u < 0.07:
			var k2 := 1.0 - u / 0.07
			var r := 11.0 * (0.8 + 0.2 * k2)
			p.circle(bx, -6.0, r + 1.2, F[2])
			p.circle(bx, -6.0, r, F[6] if k2 > 0.45 else F[5])
			p.circle(bx, -6.0, r * 0.6, WHITE if k2 > 0.45 else F[6])
		if u < 0.2:
			Px.flare(p, bx, -6.0, 40.0 * pow(1.0 - u / 0.2, 1.4), 1.0 - u / 0.2, F)
		if u < 0.3:
			var k3 := u / 0.3
			var e := 1.0 - pow(1.0 - k3, 3.0)
			var r := 8.0 + 40.0 * e
			p.ring(bx, -6.0, r, maxf(1.0, 2.5 * (1.0 - k3) + 0.4), F[5], func(v: float, an: float): return 0.0 if sin(an) * r > 9.0 else minf(1.0, (1.0 - k3) * 1.6))
		Lib.pool(p, bx, 1.0, 70.0, 12.0, F[3], 0.55 * maxf(0.0, 1.0 - u / 0.6))
	lights.draw(p)


# where the fuse's tip is: on top of the grenade, turning with it
static func fuse(g_: Dictionary) -> Array:
	var ca: float = cos(g_.a)
	var sa: float = sin(g_.a)
	return [g_.x + sa * 10.4, g_.y - ca * 10.4]


# a pineapple grenade turned by a (about 11 x 15 px): an oval body with grooves, lit from the top left, an
# outline, a metal cap with a ring pin, a lever down its side
static func drawGrenade(p: Px.Painter, G_: Array, x: float, y: float, a: float) -> void:
	var ca := cos(a)
	var sa := sin(a)
	var M := [Px.hex("#2a2c36"), Px.hex("#5e6270"), Px.hex("#9a9eac"), Px.hex("#d0d4de")]
	p.shade(x - 13.0, y - 13.0, x + 13.0, y + 13.0, func(px: float, py: float):
		var dx := px - x
		var dy := py - y
		var u := dx * ca + dy * sa
		var v := -dx * sa + dy * ca  # u across, v along (cap at v < 0)
		# the cap, its ring, and the lever pressed down the side
		if v < -5.0 and v > -10.2 and absf(u) < 2.4:
			return M[0] if (v < -9.4 or absf(u) > 1.7) else (M[3] if u < -0.6 else M[2])
		if Px.hypot(u + 3.4, v + 8.0) < 1.9 and Px.hypot(u + 3.4, v + 8.0) > 0.9:
			return M[2]
		if u > 2.2 and u < 3.6 and v > -8.6 and v < 2.0:
			return M[0] if u > 3.0 else M[1]
		var e := pow(u / 5.1, 2.0) + pow((v - 0.6) / 6.4, 2.0)
		if e > 1.2:
			return null
		if e > 1.0:
			return Lib.OUTLINE
		# grooves cut the body into knobbly segments; light from the top left in world space
		var lit := -(dx * 0.6 + dy * 0.8) / 6.0
		var gv := absf(fmod(v + 30.0, 3.1) - 1.55) < 0.45
		var gu := absf(fmod(u + 30.0, 3.4) - 1.7) < 0.45
		var i := int(maxf(0.0, minf(4.0, Px.round(2.0 + lit * 1.7 - (1.0 if (gv or gu) else 0.0) + (1.0 if (e < 0.3 and lit > 0.3) else 0.0)))))
		return G_[i])
