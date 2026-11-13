# The hold-then-break (it closes round the character, holds with glints, cracks, then bursts into tumbling
# pieces, mist and light) is adapted from Sprite Fusion's open-source ice freeze (https://www.spritefusion.com/pixel-art-vfx/ice),
# MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/nature/root-snare.js@e5516f80b0ce27b1cc30fe10dde750b526be1864
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Root snare",
	"desc": "The floor cracks and roots burst up round the character, spiralling round its legs; they cinch tight with a snap, hold, then crack and crumble into bark and dust.",
	"tags": ["nature", "roots", "plant", "snare", "root", "status", "actor", "one-shot"],
	"size": [128, 96],
	"origin": [64, 78],
	"duration": 2.7,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {
		"palette": ["#140c08", "#2a1a10", "#46301e", "#64462a", "#86623a", "#a8824e", "#ccaa70", "#ecd6a0"],
		"glow": ["#123818", "#2f7a2a", "#6cb83a", "#c8f070"],
		"seed": 7,
	},
}

static var GRAB := {"turn": 0.9, "crouch": 3, "fx": -12, "fy": -34, "bx": 12, "by": -28, "ffx": -2, "fbx": 3}
static var act := {
	"poses": [
		[-0.24, Px.merge(Px.READY, {"ffx": -2, "fbx": 3})],
		[0.3, {"turn": 0.9, "lean": -1, "crouch": 2, "fx": -10, "fy": -24, "bx": 11, "by": -24, "ffx": -2, "fbx": 3}],
		[0.62, GRAB, "snap"],
		[0.86, Px.merge(GRAB, {"lean": -3, "fy": -37, "by": -27})],
		[1.1, Px.merge(GRAB, {"lean": 3, "fy": -27, "by": -37})],
		[1.34, Px.merge(GRAB, {"lean": -3, "fy": -37, "by": -27})],
		[1.58, Px.merge(GRAB, {"lean": 3, "fy": -27, "by": -37})],
		[1.75, Px.merge(GRAB, {"crouch": 6})],
		[1.8, {"turn": 1.1, "crouch": -1, "y": -3, "fx": -14, "fy": -36, "bx": 15, "by": -36, "ffx": -3, "ffy": -6, "fbx": 4, "fby": -6}, "snap"],
		[2.05, Px.merge(Px.READY, {"y": 0, "crouch": 5})],
		[2.7, Px.merge(Px.READY, {"ffx": -2, "fbx": 3})],
	],
	"hits": [{"t": 0.62, "stop": 0.05, "shake": 0.1, "amp": 1}, {"t": 1.75, "stop": 0.04, "shake": 0.14, "amp": 2}],
}

const SY := 0.34
const CINCH := 0.62
const BREAK := 1.75
const NP := 48


# one root: from the floor outside the feet it spirals in round the legs and climbs, thinning to its tip
static func path(r: Dictionary, cinch: float) -> Array:
	var pts := []
	for i in NP + 1:
		var s := i / float(NP)
		var th: float = r.th0 + r.dir * TAU * r.turns * s
		var rad := Px.lerp(r.r0, r.leg - cinch * 1.6, Px.Ease.outCubic(minf(1.0, s * 3.5)))
		pts.append({"x": cos(th) * rad, "y": -r.h * pow(s, 1.05) + sin(th) * rad * SY, "z": sin(th), "s": s})
	return pts


# a stroke of bark along the path: lit on its upper side, dark beneath, a ridge of grain, rootlet hairs
static func root(p: Px.Painter, pts: Array, g: float, C: Array, back: bool, a: float) -> void:
	var n := floori(NP * g)
	for i in n:
		var A: Dictionary = pts[i]
		var Bp: Dictionary = pts[i + 1]
		var front: bool = (A.z + Bp.z) / 2.0 >= 0.0
		if front == back:
			continue
		var dx: float = Bp.x - A.x
		var dy: float = Bp.y - A.y
		var L := Px.hypot(dx, dy)
		if not L:
			L = 1.0
		var nx := -dy / L
		var ny := dx / L
		var up := 1 if nx * -0.6 + ny * -0.8 > 0.0 else -1
		var w := (1.4 + 3.6 * pow(1.0 - A.s, 0.8)) / 2.0 + 0.35
		var dim := 1 if back else 0
		for y in range(floori(minf(A.y, Bp.y) - w - 1.0), ceili(maxf(A.y, Bp.y) + w + 1.0) + 1):
			for x in range(floori(minf(A.x, Bp.x) - w - 1.0), ceili(maxf(A.x, Bp.x) + w + 1.0) + 1):
				if y > 0:
					continue
				var px: float = x + 0.5 - A.x
				var py: float = y + 0.5 - A.y
				var u := (px * dx + py * dy) / (L * L)
				if u < -0.2 or u > 1.2:
					continue
				var d := px * nx + py * ny
				if absf(d) > w:
					continue
				var side := Px.sign(d) * up
				var q := absf(d) / w
				var i2 := (7 if side > 0.0 else 1) if q > 0.72 else ((6 if q > 0.3 else 5) if side > 0.0 else (2 if q > 0.35 else 3))
				if q < 0.25 and Px.rand(Px.round(A.s * 40.0), 3) < 0.4:
					i2 = 4
				p.dot(x, y, C[maxi(1, i2 - dim)], a)
		# rootlet hairs off its underside now and then
		if i % 7 == 3 and w > 1.2:
			p.dot(A.x - nx * up * (w + 1.0), A.y - ny * up * (w + 1.0), C[2 - dim], a)


var C: Array
var G: Array
var R: Px.Rng
var ps: Px.Particles
var lights: Px.Lights
var chips: Array
var roots: Array
var cracks: Array
var t := 0.0
var cinched := false
var broken := false


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	G = Px.fit(o.glow, 4)
	R = Px.Rng.new(o.seed)
	var floor_ := func(): return 0.0
	ps = Px.Particles.new({"rng": R, "ground": floor_, "sparks": [G[3], G[2], G[1], G[0]]})
	lights = Px.Lights.new()
	chips = []
	roots = Px.arr(5, func(i: int) -> Dictionary: return {
		"th0": (i / 5.0) * TAU + R.range(-0.3, 0.3), "dir": 1.0 if i % 2 else -1.0, "turns": R.range(1.1, 1.6), "r0": R.range(14.0, 19.0), "leg": R.range(8.0, 10.0),
		"h": R.range(13.0, 21.0), "at": 0.16 + i * 0.07 + R.range(0.0, 0.04), "buds": [R.range(0.35, 0.55), R.range(0.6, 0.85)],
	})
	cracks = [Lib.floorCrack(R, -1.0, R.range(18.0, 26.0)), Lib.floorCrack(R, 1.0, R.range(18.0, 26.0))]
	t = 0.0
	cinched = false
	broken = false


func grow(r: Dictionary) -> float:
	return Px.Ease.outCubic(Px.clamp((t - r.at) / 0.32))


func squeeze() -> float:
	return Px.smooth(CINCH - 0.03, CINCH + 0.05, t) * (1.0 - 0.4 * Px.smooth(CINCH + 0.05, CINCH + 0.25, t))


func update(dt: float) -> void:
	t += dt
	var f := minf(1.0, dt * 120.0)
	if t < 0.4 and R.chance(0.3 * f):
		var sd := R.sign()
		ps.spawn(P.GRIT, sd * R.range(4.0, 22.0), -1.0, R.range(-20.0, 20.0), -R.range(30.0, 90.0), R.range(0.5, 0.9), R.pick([C[5], C[4]]), 1.0)
	for r: Dictionary in roots:
		if not r.get("burst", false) and t >= r.at:
			r.burst = true
			var x: float = cos(r.th0) * r.r0
			for i in 4:
				chips.append({"x": x, "y": -1.0, "vx": R.range(-60.0, 60.0), "vy": -R.range(60.0, 160.0), "a": R.range(0.0, TAU), "va": R.range(-15.0, 15.0), "s": R.range(1.2, 2.0), "pts": Lib.stoneShape(R), "life": R.range(0.6, 0.9)})
			for i in 3:
				ps.spawn(P.DUST, x, -1.0, R.range(-25.0, 25.0), -R.range(4.0, 18.0), R.range(0.4, 0.8), C[5], R.range(2.0, 3.5))
			lights.add(x, -4.0, 20.0, G[2], 0.35, 0.3)
	if not cinched and t >= CINCH:
		cinched = true
		lights.add(0.0, -10.0, 40.0, G[3], 0.5, 0.3)
		lights.add(0.0, -10.0, 16.0, WHITE, 0.4, 0.06)
		for i in 8:
			ps.spawn(P.DUST, R.range(-12.0, 12.0), -R.range(0.0, 4.0), R.sign() * R.range(20.0, 60.0), -R.range(4.0, 14.0), R.range(0.5, 0.9), C[5], R.range(2.0, 3.5))
		for i in 6:
			ps.spawn(P.STAR, R.range(-9.0, 9.0), -R.range(4.0, 20.0), 0.0, -4.0, R.range(0.25, 0.5), G[3], R.range(0.8, 1.8), R.range(0.0, 0.1))
	# while it holds, motes of green rise off the roots
	if t > CINCH and t < BREAK and R.chance(0.06 * f):
		ps.spawn(P.MOTE, R.range(-9.0, 9.0), -R.range(3.0, 18.0), R.range(-6.0, 6.0), -R.range(14.0, 30.0), R.range(0.5, 0.9), G[3], 0.6)
	if not broken and t >= BREAK:
		broken = true
		lights.add(0.0, -10.0, 36.0, G[2], 0.4, 0.25)
		# every root crumbles into bark chunks and splinters along its length
		for r: Dictionary in roots:
			var pts := path(r, 1.0)
			var i := 2
			while i < NP:
				var q: Dictionary = pts[i]
				var w: float = 1.4 + 3.6 * pow(1.0 - q.s, 0.8)
				var sg := Px.sign(q.x)
				chips.append({"x": q.x, "y": minf(q.y, -1.0), "vx": (sg if sg else 1.0) * R.range(25.0, 85.0) + q.x * 3.0, "vy": -R.range(50.0, 150.0), "a": R.range(0.0, TAU), "va": R.range(-10.0, 10.0), "s": Px.clamp(w * 0.75, 1.5, 3.0), "pts": Lib.stoneShape(R), "life": minf(R.range(0.7, 0.95), meta.duration - 0.05 - t)})
				if i % 10 == 2:
					ps.spawn(P.GRIT, q.x, minf(q.y, -1.0), R.range(-40.0, 40.0), -R.range(20.0, 80.0), minf(R.range(0.6, 0.9), meta.duration - 0.05 - t), R.pick([C[4], C[3], C[2]]), 2.0 if R.chance(0.3) else 1.0)
				i += 4
		for i in 10:
			ps.spawn(P.SMOKE, R.range(-12.0, 12.0), -R.range(2.0, 16.0), R.range(-25.0, 25.0), -R.range(5.0, 20.0), minf(R.range(0.6, 0.9), meta.duration - 0.05 - t), C[5], R.range(3.0, 5.0), 0.0, 0)
	var i := chips.size() - 1
	while i >= 0:
		var c: Dictionary = chips[i]
		c.life -= dt
		if c.life <= 0.0:
			chips.remove_at(i)
		c.vy += 950.0 * dt
		c.x += c.vx * dt
		c.y += c.vy * dt
		c.a += c.va * dt
		if c.y > 0.0 and c.vy > 0.0:
			if c.vy > 110.0:
				c.y = 0.0
				c.vy *= -0.3
				c.vx *= 0.5
			else:
				c.y = 0.0
				c.va = 0.0
				c.vx = 0.0
				c.vy = 0.0
		i -= 1
	ps.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	# cracks run out from the feet, a mossy light seeping up from them
	var open := Px.Ease.outCubic(Px.clamp(t / 0.25))
	var hot := Px.smooth(0.0, 0.3, t) * (1.0 - Px.smooth(0.5, 1.4, t))
	var fade: float = 1.0 - Px.smooth(meta.duration - 0.6, meta.duration - 0.15, t)
	for c: Array in cracks:
		var m := maxi(2, ceili(c.size() * open))
		for k in range(1, m):
			var x0: float = c[k - 1][0]
			var y0: float = c[k - 1][1]
			var x1: float = c[k][0]
			var y1: float = c[k][1]
			p.line(x0, y0 + 1.0, x1, y1 + 1.0, C[0], fade)
			p.line(x0, y0, x1, y1, G[3] if hot > 0.5 else (G[2] if hot > 0.2 else C[1]), fade)
			if k % 2 == 0:
				p.glow(x1, y1, 6.0, G[2], 0.3 * hot)
	var hold := Px.smooth(0.3, CINCH, t) * (1.0 - Px.smooth(BREAK, BREAK + 0.3, t)) * (0.8 + 0.2 * sin(t * 8.0))
	if hold > 0.0:
		p.glow(0.0, -12.0, 30.0, G[2], 0.3 * hold)
		p.glow(0.0, -1.0, 22.0, G[3], 0.16 * hold)
	if t < BREAK:
		for r: Dictionary in roots:
			if t > r.at:
				root(p, path(r, squeeze()), grow(r), C, true, 1.0)
	ps.draw(p, "back")


func draw(p: Px.Painter) -> void:
	if t < BREAK:
		for r: Dictionary in roots:
			if t <= r.at:
				continue
			var pts := path(r, squeeze())
			var g := grow(r)
			root(p, pts, g, C, false, 1.0)
			# buds open into small leaves once it has hold of them
			for b: float in r.buds:
				var q: Dictionary = pts[floori(b * NP)]
				var lk := Px.clamp((t - CINCH - 0.1 - b * 0.2) / 0.25)
				if b > g or lk <= 0.0 or q.z < 0.0:
					continue
				Lib.drawLeaf(p, q.x + 2.0, q.y - 2.0, 5.0 * lk, 1.6, -0.6 + sin(t * 5.0 + b * 9.0) * 0.2, 0.3, [G[0], G[1], G[2], G[3]])
		# the snap as they cinch
		var e := t - CINCH
		if e > 0.0 and e < 0.12:
			for xy: Array in [[-8.0, -6.0], [8.0, -10.0], [-7.0, -15.0]]:
				Px.sparkle(p, xy[0], xy[1], 5.0 * (1.0 - e / 0.12), C[7], G[3], 0.4)
		# the white flash just before they go
		var w := BREAK - t
		if w > 0.0 and w < 0.05:
			for r: Dictionary in roots:
				for q: Dictionary in path(r, 1.0):
					if q.z >= 0.0:
						p.px(q.x, q.y, WHITE)
	var BARK := [C[0], C[1], C[2], C[2], C[3], C[4], C[5]]
	for c: Dictionary in chips:
		Lib.drawRock(p, c.x, c.y, c.s, c.a, c.pts, BARK, minf(1.0, c.life / 0.25))
	ps.draw(p, "front")
	lights.draw(p)
