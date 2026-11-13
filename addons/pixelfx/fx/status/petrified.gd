# The creeping front, the branching cracks and the burst of the body into chunks, grit and dust are
# adapted from Sprite Fusion's open-source ice freeze and shatter (https://www.spritefusion.com/pixel-art-vfx/ice),
# MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/status/petrified.js@5f7d7600c79fc1497d9702aa7d2f66f9575996c0
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const B := Px.B
const WHITE := Px.WHITE

static var meta := {
	"name": "Petrified",
	"desc": "Turned to stone: grey creeps up from the feet behind a crackling edge that spits grit, the statue holds, cracks run through it, and it bursts into tumbling chunks and dust.",
	"tags": ["status", "stone", "petrify", "petrified", "debuff", "death", "one-shot"],
	"size": [120, 74],
	"origin": [60, 64],
	"duration": 3.8,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {"palette": ["#16141c", "#2a2733", "#433f4d", "#5f5a6a", "#7d7889", "#a29dab", "#cdc8d2", "#f0edf3"], "seed": 3},
}

static var REACH_ := {"lean": 3, "crouch": 2, "fx": 14, "fy": -29, "bx": -4, "by": -22, "ffx": 8, "fbx": -7, "toeB": true}
static var act := {
	"onBody": true,
	"poses": [[-0.16, Px.READY], [0.08, {"turn": 0.9, "lean": -1, "crouch": 2, "fx": -8, "fy": -24, "bx": 9, "by": -24}, "snap"], [0.5, REACH_], [0.95, REACH_], [3.8, REACH_]],
	"hits": [{"t": 2.2, "stop": 0.08, "shake": 0.24, "amp": 2}],
}

const CREEP := 0.95
const CRACK := 1.75
const SHATTER := 2.2

## The stand-in character is gone once the stone covers it (the statue is drawn in its place).
static func actorAlpha(t: float, _o: Dictionary) -> float:
	return 1.0 if t < CREEP else 0.0

# how far up the stone has crept (0 at the feet, past 1 over the head), stuttering as it climbs
static func level(t: float) -> float:
	return 1.2 if t >= CREEP else 1.2 * Px.smooth(0.0, CREEP, t) + 0.025 * sin((t / CREEP) * TAU * 3.0)


var C: Array
var a: Dictionary
var S: Dictionary
var H: int
var R: Px.Rng
var seed: float
var ps: Px.Particles
var bits: Px.Bits
var lights: Px.Lights
var stone: Array
var cracks := []
var ox: float
var oy: float
var t := 0.0
var broke := false
var settled := false


func front(mx: float) -> float:
	return level(t) + 0.06 * Px.tileFbm(mx * 0.4, 0.5, 0.0, 0.0, seed, 2)


# cracks: random walks through the statue from a point on its chest
func walk(x: float, y: float, ang: float, len: float) -> void:
	var pts := [[x, y]]
	var s := 0
	while s < len:
		ang += R.range(-0.55, 0.55)
		x += cos(ang) * R.range(1.4, 2.4)
		y += sin(ang) * R.range(1.4, 2.4)
		if not S.on.call(floorf(x), floorf(y)):
			break
		pts.append([x, y])
		if pts.size() > 3 and cracks.size() < 16 and R.chance(0.14):
			walk(x, y, ang + R.sign() * R.range(0.6, 1.2), len / 2.0)
		s += 1
	cracks.append(pts)


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	a = o.actor
	S = Lib.shape(a)
	H = S.h
	R = Px.Rng.new(o.seed)
	seed = o.seed
	var floor_ := func(): return 0.0
	ps = Px.Particles.new({"rng": R, "ground": floor_, "sparks": [C[7], C[6], C[5], C[4]]})
	bits = Px.Bits.new({"ground": floor_})
	lights = Px.Lights.new()
	# each pixel's stone: its own shading walked down a grey ramp, grained, lit on the top left
	stone = S.body.map(func(xy):
		var x: int = xy[0]
		var y: int = xy[1]
		var tone := Px.clamp((Px.luma(Lib.colorAt(a, x, y)) - 0.06) / 0.78)
		var mottle := Px.tileFbm(x * 0.32, y * 0.32, 0.0, 0.0, o.seed + 5.0, 2)
		var i := 1.0 + Px.round(tone * 4.6 + mottle * 1.1)
		if not S.on.call(x - 1, y) or not S.on.call(x, y - 1):
			i += 1.0
		elif not S.on.call(x + 1, y) or not S.on.call(x, y + 1):
			i -= 1.0
		return {"x": x, "y": y, "up": 1.0 - (y + 0.5) / H, "c": C[int(Px.clamp(i, 1.0, 6.0))]})
	ox = Px.round(S.w * 0.55)
	oy = Px.round(H * 0.42)
	for i in 7:
		walk(ox, oy, (i / 7.0) * TAU + R.range(-0.3, 0.3), 14.0)


func update(dt: float) -> void:
	t += dt
	# the creeping edge spits grit and dust and the odd spark
	if t < CREEP:
		var rate := 60.0 * dt
		var n := 0
		while n < rate:
			n += 1
			if not R.chance(0.5):
				continue
			var b: Array = S.body[R.int_(0, S.body.size() - 1)]
			var mx: int = b[0]
			var my: int = b[1]
			if absf(1.0 - (my + 0.5) / H - front(mx)) > 0.04:
				continue
			var x: float = a.x + mx + 0.5
			var y: float = a.y + my
			var side := -1.0 if mx < S.w / 2.0 else 1.0
			ps.spawn(P.GRIT, x, y, side * R.range(15.0, 60.0), -R.range(30.0, 90.0), R.range(0.6, 1.1), R.pick([C[4], C[5], C[6]]), 2.0 if R.chance(0.3) else 1.0)
			if R.chance(0.3):
				ps.spawn(P.DUST, x + side * 2.0, y, side * R.range(10.0, 30.0), -R.range(4.0, 14.0), R.range(0.4, 0.7), C[4], R.range(1.5, 2.6))
			if R.chance(0.25):
				ps.spawn(P.MOTE, x, y, side * R.range(40.0, 90.0), -R.range(20.0, 70.0), R.range(0.15, 0.3), C[7], 0.5)
	if not settled and t >= CREEP:
		settled = true
		lights.add(0.0, a.y + H * 0.5, 34.0, C[6], 0.35, 0.3)
		for i in 8:
			ps.spawn(P.DUST, R.range(-8.0, 8.0), -R.range(0.0, 2.0), R.sign() * R.range(20.0, 50.0), -R.range(2.0, 10.0), R.range(0.6, 1.0), C[3], R.range(2.0, 3.5))
	# while it holds a pebble or two drops off
	if t > CREEP + 0.2 and t < SHATTER and R.chance(1.6 * dt):
		var b: Array = S.body[R.int_(0, S.body.size() - 1)]
		var mx: int = b[0]
		var my: int = b[1]
		if not S.on.call(mx, my + 1):
			ps.spawn(P.GRIT, a.x + mx + 0.5, a.y + my + 1, R.range(-8.0, 8.0), 0.0, R.range(0.8, 1.2), C[3], 1.0)
	# the cracks pop chips off as they run
	if t >= CRACK and t < SHATTER and R.chance(12.0 * dt):
		var pts: Array = R.pick(cracks)
		var xy: Array = pts[floori(R.next() * pts.size())]
		ps.spawn(P.GRIT, a.x + xy[0], a.y + xy[1], R.range(-40.0, 40.0), -R.range(30.0, 80.0), R.range(0.5, 0.9), R.pick([C[5], C[6]]), 1.0)
	if not broke and t >= SHATTER:
		broke = true
		lights.add(0.0, a.y + H * 0.45, 46.0, C[6], 0.7, 0.5)
		lights.add(0.0, a.y + H * 0.45, 30.0, WHITE, 0.7, 0.12)
		# the statue bursts: chunks tumble out, grit sprays, dust rolls along the floor
		var cx: float = a.x + ox
		var cy: float = a.y + oy
		for i in 18:
			var q: Dictionary = stone[R.int_(0, stone.size() - 1)]
			var x: float = a.x + q.x + 0.5
			var y: float = a.y + q.y + 0.5
			var dx := x - cx
			var dy := y - cy
			var d := Px.hypot(dx, dy)
			if not d:
				d = 1.0
			var sp := R.range(35.0, 110.0)
			bits.add({"kind": B.CHUNK, "x": x, "y": y, "vx": (dx / d) * sp, "vy": (dy / d) * sp * 0.6 - R.range(60.0, 160.0), "g": 1.0, "drag": 0.4, "bounce": 0.3, "life": R.range(1.1, 1.5), "a": R.range(0.0, TAU), "va": R.range(-14.0, 14.0), "s": R.range(1.3, 2.8), "ramp": [C[0], C[2], C[3], C[5], C[6]]})
		for q: Dictionary in stone:
			if Px.rand(q.x, q.y, 9) > 0.22:
				continue
			var x: float = a.x + q.x + 0.5
			var y: float = a.y + q.y + 0.5
			var dx := x - cx
			var dy := y - cy
			var d := Px.hypot(dx, dy)
			if not d:
				d = 1.0
			var sp := R.range(40.0, 130.0)
			ps.spawn(P.GRIT, x, y, (dx / d) * sp, (dy / d) * sp * 0.6 - R.range(40.0, 140.0), R.range(0.9, 1.4), q.c, 2.0 if R.chance(0.35) else 1.0)
		# pale flakes of the skin of it, tumbling, and glints in the dust
		for i in 16:
			var an := -PI / 2.0 + R.range(-1.4, 1.4)
			var sp := R.range(50.0, 120.0)
			bits.add({"kind": B.SHARD, "x": cx + R.range(-5.0, 5.0), "y": cy + R.range(-8.0, 8.0), "vx": cos(an) * sp, "vy": sin(an) * sp, "g": 0.8, "drag": 0.6, "bounce": 0.3, "life": R.range(0.9, 1.4), "a": R.range(0.0, TAU), "va": R.range(-18.0, 18.0), "s": R.range(1.5, 3.0), "c": R.pick([C[5], C[6], C[7]])})
		for i in 6:
			ps.spawn(P.STAR, cx + R.range(-12.0, 12.0), cy + R.range(-10.0, 14.0), R.range(-10.0, 10.0), -R.range(5.0, 20.0), R.range(0.4, 0.9), C[6], R.range(1.0, 2.2), R.range(0.05, 0.4))
		for i in 12:
			var side := R.sign()
			ps.spawn(P.SMOKE, side * R.range(0.0, 8.0), -R.range(1.0, 6.0), side * R.range(20.0, 60.0), -R.range(4.0, 16.0), R.range(0.9, 1.4), C[4], R.range(2.4, 4.0), R.range(0.0, 0.08), 0)
		for i in 6:
			ps.spawn(P.SMOKE, R.range(-6.0, 6.0), a.y + H * R.range(0.3, 0.8), R.range(-20.0, 20.0), -R.range(10.0, 30.0), R.range(1.0, 1.5), C[3], R.range(3.0, 4.5), R.range(0.0, 0.1), 0)
	bits.update(dt)
	# chunks that hit hard kick up a little dust
	for b: Dictionary in bits.list:
		if b.rest and not b.get("dusted"):
			b.dusted = true
			ps.spawn(P.DUST, b.x, -0.5, R.range(-20.0, 20.0), -R.range(2.0, 10.0), R.range(0.3, 0.6), C[3], R.range(1.2, 2.2))
	ps.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	ps.draw(p, "back")


func draw(p: Px.Painter) -> void:
	if t < SHATTER:
		# the shudder before it breaks
		var sh := Px.round(sin(t * 90.0) * minf(1.0, (t - CRACK) / (SHATTER - CRACK)) * 1.2) if t >= CRACK else 0.0
		var white := t > SHATTER - 0.035
		for q: Dictionary in stone:
			var f := front(q.x)
			var d: float = f - q.up
			if d < 0.0:
				continue
			var x: float = a.x + q.x + sh
			var y: float = a.y + q.y
			# the crackling edge: bright, flickering
			if d < 0.035 and t < CREEP:
				p.px(x, y, C[7] if Px.rand(q.x, q.y, floorf(t * 24.0)) < 0.5 else C[6])
			elif d < 0.07 and t < CREEP:
				p.px(x, y, C[5])
			else:
				p.px(x, y, WHITE if white else q.c)
		if t < CREEP:
			var mx := 0
			while mx < S.w:
				var my := floori((1.0 - front(mx)) * H)
				if S.on.call(mx, my):
					p.glow(a.x + mx, a.y + my, 5.0, C[6], 0.18)
				mx += 2
		# the cracks running through it, fresh tips white
		if t >= CRACK:
			var k := Px.clamp((t - CRACK) / 0.3)
			for pts: Array in cracks:
				var n := floori(pts.size() * k)
				for i in n:
					var x: float = pts[i][0]
					var y: float = pts[i][1]
					var px := floorf(a.x + x) + sh
					var py := floorf(a.y + y)
					var fresh := i > n - 3
					p.px(px, py, WHITE if fresh else C[0])
					if not fresh:
						p.px(px, py - 1.0, C[6])
			p.glow(a.x + ox, a.y + oy, 12.0, C[6], 0.25 * k)
	bits.draw(p)
	ps.draw(p, "front")
	lights.draw(p)
