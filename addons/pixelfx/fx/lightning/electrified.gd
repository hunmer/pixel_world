# Arcs leaping between points of the silhouette's edge, re-struck every other frame, grounding to the floor, and
# the periodic jolt that throws sparks follow Sprite Fusion's open-source lightning crackle
# (https://www.spritefusion.com/pixel-art-vfx/lightning), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/lightning/electrified.js@e79222e69e8344f1fd0d3bb6f40afc4ab8757692
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")

static var meta := {
	"name": "Electrified",
	"desc": "Current runs through a character: arcs crawl over and leap across the body, sparks spit off, the body flares to an electric silhouette on each jolt, and the feet ground out.",
	"tags": ["lightning", "electric", "status", "shock", "stun", "actor", "loop"],
	"size": [108, 92],
	"origin": [54, 76],
	"duration": 2.0,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {"palette": Lib.VOLT, "sparks": Lib.PLASMA, "seed": 5},
}

static var TENSE := {"turn": 0.9, "crouch": 3, "fx": -8, "fy": -17, "bx": 9, "by": -17, "ffx": -3, "fbx": 4}
static var JOLT_A := {"turn": 1.1, "crouch": 0, "y": -1, "fx": -13, "fy": -36, "bx": 13, "by": -17, "ffx": -4, "fbx": 5}
static var JOLT_B := {"turn": 0.7, "crouch": 1, "y": -1, "fx": -13, "fy": -16, "bx": 13, "by": -36, "ffx": -4, "fbx": 5}
static var act := {
	"onBody": true,
	"poses": [
		[0, TENSE],
		[0.1, JOLT_A, "snap"],
		[0.17, JOLT_B, "snap"],
		[0.3, TENSE, "snap"],
		[0.733, TENSE],
		[0.733, JOLT_B, "snap"],
		[0.8, JOLT_A, "snap"],
		[0.93, TENSE, "snap"],
		[1.367, TENSE],
		[1.367, JOLT_A, "snap"],
		[1.45, JOLT_B, "snap"],
		[1.58, TENSE, "snap"],
		[2, TENSE],
	],
}

const FPS := 30.0
const N := 60
const P := 2.0
const JOLTS := [[3, 1.0], [22, 0.7], [41, 0.9]]
static var edges := {}
# the silhouette's edge pixels, in local space
static func edgeOf(A: Dictionary) -> Array:
	var e: Variant = edges.get(A.mask.id)
	if e:
		return e
	var m: Dictionary = A.mask
	var on := func(x: int, y: int) -> bool: return x >= 0 and y >= 0 and x < m.w and y < m.h and m.data[y * m.w + x]
	e = []
	for y in m.h:
		for x in m.w:
			if on.call(x, y) and (not on.call(x - 1, y) or not on.call(x + 1, y) or not on.call(x, y - 1) or not on.call(x, y + 1)):
				e.append([A.x + x + 0.5, A.y + y + 0.5])
	edges[A.mask.id] = e
	return e


static func jolt(f: int) -> Variant:
	for jk: Array in JOLTS:
		var f0: int = jk[0]
		if f >= f0 and f < f0 + 3:
			return {"a": f - f0, "k": jk[1]}
	return null


static func drawBack(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var A: Dictionary = o.actor
	var f := floori(t * FPS + 1e-6) % N
	var j: Variant = jolt(f)
	var r := Px.rng(o.seed, 4, f)
	# a cold aura: a broken outline that flickers round the body, light pooling at the feet
	p.outline(A.mask, A.x, A.y, C[4] if j else (C[2] if r.next() < 0.5 else C[1]))
	p.glow(0.0, -18.0, 30.0, C[3], (0.55 * j.k if j else 0.16 + 0.1 * r.next()))
	p.glow(0.0, -2.0, 22.0, C[4], 0.18)


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var S := Px.ramp(o.sparks)
	var A: Dictionary = o.actor
	var E := edgeOf(A)
	var f := floori(t * FPS + 1e-6) % N
	var j: Variant = jolt(f)
	# the jolt: the body flares to an electric silhouette, then fades back through its own shading
	if j:
		var lift: float = [1.1, 0.6, -0.2][j.a] * j.k
		var ramp := [C[1], C[2], C[3], C[4], C[5], C[6], C[7]]
		var aw: int = A.w
		var pix: PackedInt32Array = A.pixels
		for y in int(A.h):
			for x in aw:
				var c := pix[y * aw + x]
				if c:
					p.px(A.x + x, A.y + y, ramp[int(Px.clamp(Px.round(0.4 + Px.luma(c) * 6.0 + lift), 0.0, 6.0))])
		p.glow(0.0, -19.0, 26.0, C[5], 0.5 * j.k * (1.0 - j.a / 3.0))
	# arcs: two or three at a time, re-struck every other frame, leaping between nearby points of the edge
	var r := Px.rng(o.seed, 7, f >> 1)
	var n := 2 + (2 if j else r.int_(0, 1))
	for i in n:
		var a: Array = r.pick(E)
		var ang := r.range(0.0, TAU)
		var d := r.range(6.0, 14.0)
		var b: Array = [a[0] + cos(ang) * d, a[1] + sin(ang) * d]
		for kk in 10:
			var c: Array = r.pick(E)
			if Px.hypot(c[0] - b[0], c[1] - b[1]) < 5.0 and Px.hypot(c[0] - a[0], c[1] - a[1]) > 4.0:
				b = c
		var k := (0.75 if f & 1 else 0.95) * r.range(0.6, 1.0)
		Lib.crackle(p, Lib.zigzag(Px.rng(o.seed, 8, f, i), a[0], a[1], b[0], b[1], 0.42, 0.35), k, C, 0.4)
		# the edge catches the light where an arc touches it
		for e: Array in E:
			var x: float = e[0]
			var y: float = e[1]
			if Px.hypot(x - a[0], y - a[1]) < 3.5 or Px.hypot(x - b[0], y - b[1]) < 3.0:
				p.px(x - 0.5, y - 0.5, C[5])
	# the feet ground out to the floor now and then
	if r.next() < (0.9 if j else 0.35):
		var s := r.sign()
		var x0 := s * r.range(3.0, 8.0)
		Lib.crackle(p, Lib.zigzag(Px.rng(o.seed, 9, f), x0, -1.5, x0 + s * r.range(5.0, 12.0), -0.5, 0.45, 0.3), 0.7, C, 0.35)
		p.glow(x0, -1.0, 10.0, C[5], 0.35)
	# sparks: a spray off the edge with every jolt, and a few spat out between them
	for jk: Array in JOLTS:
		var f0: int = jk[0]
		var k: float = jk[1]
		var age := Px.wrap(t - f0 / FPS, P)
		for i in 9:
			var q := Px.rng(o.seed, 21, f0, i)
			var life := q.range(0.18, 0.4)
			if age >= life:
				continue
			var e0: Array = E[floori(q.next() * E.size())]
			var x0: float = e0[0]
			var y0: float = e0[1]
			var ang := atan2(y0 + 19.0, x0) + q.range(-0.7, 0.7)
			var sp := q.range(60.0, 150.0) * k
			var fl := Lib.flight(x0, y0, cos(ang) * sp, sin(ang) * sp - 30.0, age, {"floor": 0.0})
			Lib.spark(p, fl[0], fl[1], fl[2], fl[3], 1.0 - age / life, S)
	Px.cycle(t, P, 8, o.seed + 3, func(g): return g.range(0.15, 0.3), func(age, life, q):
		var e0: Array = E[floori(q.next() * E.size())]
		var x0: float = e0[0]
		var y0: float = e0[1]
		var ang: float = atan2(y0 + 19.0, x0) + q.range(-0.6, 0.6)
		var sp: float = q.range(50.0, 110.0)
		var fl := Lib.flight(x0, y0, cos(ang) * sp, sin(ang) * sp - 20.0, age, {"floor": 0.0})
		Lib.spark(p, fl[0], fl[1], fl[2], fl[3], 1.0 - age / life, S))
