# The star, its key frames and the spark spray are adapted from Sprite Fusion's open-source impact
# (https://www.spritefusion.com/pixel-art-vfx/impact), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/impacts/crit-hit.js@53c1bff8401b3348561b9b158044370c45e82d0c
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const B := Px.B
const WHITE := Px.WHITE

static var meta := {
	"name": "Critical hit",
	"desc": "A critical hit: a jagged starburst slams in white and overshoots, a ring breaks into flying arcs, sparks streak off, shards tumble to the floor under a big flare.",
	"tags": ["impact", "hit", "crit", "critical", "combat", "directional", "one-shot"],
	"size": [216, 136],
	"origin": [84, 106],
	"duration": 0.9,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": ["#2a0510", "#5c0a1c", "#a3142a", "#e0302c", "#ff7a2a", "#ffc23d", "#fff09a", "#ffffff"], "height": 26, "aim": 0.12, "seed": 3},
}

# the star's key frames: [from t, scale, thickness, alpha, colors (rim, body, inner, core) as steps of the ramp]
const KEYS := [
	[0.0, 1.0, 1.0, 1.0, [6, 7, 7, 7]],
	[0.025, 1.3, 1.0, 1.0, [2, 5, 6, 7]],
	[0.058, 1.05, 0.72, 1.0, [2, 4, 5, 6]],
	[0.092, 1.22, 0.3, 1.0, [1, 2, 3, 4]],
	[0.125],
]


# a lens flare: a long level streak, thick and white at the heart, a shorter upright one, on a bed of light
static func flare(p: Px.Painter, x: float, y: float, L: float, k: float, C: Array) -> void:
	for arm: Array in [[1.0, 0.0, L], [0.0, 1.0, L * 0.45], [0.7, 0.7, L * 0.16], [0.7, -0.7, L * 0.16]]:
		var dx: float = arm[0]
		var dy: float = arm[1]
		var len_: float = arm[2]
		for s: float in [-1.0, 1.0]:
			var d := 1.0
			while d <= len_:
				var u := d / len_
				var a := 1.0 if u < 0.7 else k * (1.6 - u)
				p.dot(x + s * dx * d, y + s * dy * d, WHITE if u < 0.35 else (C[6] if u < 0.7 else C[5]), a)
				if dy == 0.0 and u < 0.42:
					for e: float in [-1.0, 1.0]:
						p.dot(x + s * d, y + e, C[6] if u < 0.2 else C[5], 1.0 if u < 0.3 else k)
				d += 1.0
	p.glowLine(x - L, y, x + L, y, 6.0, C[6], 0.5 * k)
	p.glowLine(x, y - L * 0.45, x, y + L * 0.45, 4.0, C[6], 0.3 * k)


var C: Array
var R: Px.Rng
var X := 0.0
var Y: float
var A: float
var ps: Px.Particles
var bits: Px.Bits
var lights: Px.Lights
var sp: Array
var segs: Array
var t := 0.0


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	R = Px.Rng.new(o.seed)
	Y = -o.height
	A = o.aim
	var floor_ := func(): return 0.0
	ps = Px.Particles.new({"rng": R, "ground": floor_, "sparks": [C[7], C[6], C[5], C[3]]})
	bits = Px.Bits.new({"ground": floor_})
	lights = Px.Lights.new()
	sp = Lib.spikes(R, 14, A, {"len": [11.0, 15.0], "w": [1.8, 2.5], "fwd": 1.4, "back": 0.6, "jag": 0.5})
	for s: Dictionary in Px.sort(sp.duplicate(), func(a, b): return b.len - a.len).slice(0, 2):
		s.len *= 1.3
	segs = Px.arr(7, func(i: int):
		var a := A + (i / 7.0) * TAU
		return {"a": a, "gap": R.range(0.55, 0.85), "dr": R.range(0.08, 0.4) + 0.15 * maxf(0.0, cos(a - A)), "w": 0.7 + 0.5 * maxf(0.0, cos(a - A))})

	lights.add(X, Y, 84.0, C[5], 0.6, 0.5)
	lights.add(X, Y, 30.0, WHITE, 0.7, 0.1)
	lights.add(X, -4.0, 44.0, C[4], 0.3, 0.45)
	# sparks: most sprayed on along the blow, a few kicked back
	for i in 36:
		var back := R.chance(0.22)
		var a := (A + PI if back else A) + R.range(-1.0, 1.0) * (0.6 if back else 0.8)
		var v := R.range(170.0, 430.0) * (0.6 if back else 1.0)
		ps.spawn(P.SPARK, X, Y, cos(a) * v, sin(a) * v - 50.0, R.range(0.15, 0.5), WHITE, 1.0, R.range(0.0, 0.04) if R.chance(0.3) else 0.0)
	# shards: bright splinters that tumble down, bounce and settle
	for i in 10:
		var a := A + R.range(-1.0, 1.0) * 1.1 - 0.35
		var v := R.range(110.0, 280.0)
		bits.add({"kind": B.SHARD, "x": X, "y": Y, "vx": cos(a) * v, "vy": sin(a) * v - 40.0, "g": 0.8, "drag": 0.7, "bounce": 0.35, "life": R.range(0.55, 0.85), "a": R.range(0.0, TAU), "va": R.range(-25.0, 25.0), "s": R.range(2.0, 4.5), "c": R.pick([C[7], C[6], C[6], C[5]])})
	# embers of light drifting up and off, and glints that pop round the ring after the hit
	for i in 12:
		var a := A - PI / 2.0 + R.range(-1.4, 1.4)
		var v := R.range(35.0, 110.0)
		ps.spawn(P.MOTE, X + cos(a) * 4.0, Y + sin(a) * 4.0, cos(a) * v, sin(a) * v - 15.0, R.range(0.35, 0.7), R.pick([C[6], C[5], C[5]]), 0.6, R.range(0.0, 0.05))
	for i in 5:
		var a := R.range(0.0, TAU)
		var d := R.range(14.0, 34.0)
		ps.spawn(P.STAR, X + cos(a) * d, Y + sin(a) * d * 0.8, 0.0, -4.0, R.range(0.22, 0.38), C[6] if R.chance(0.5) else WHITE, R.range(1.6, 3.0), R.range(0.08, 0.32))


func update(dt: float) -> void:
	t += dt
	ps.update(dt)
	bits.update(dt)
	lights.update(dt)


func draw(p: Px.Painter) -> void:
	# the ring: it swells off the star, then breaks into arcs that fly on and cool
	var u := Px.clamp((t - 0.03) / 0.37)
	if t >= 0.03 and u < 1.0:
		var r := 10.0 + 30.0 * Px.Ease.outCubic(u)
		var brk := Px.smooth(0.12, 0.6, u)
		var th := maxf(1.0, 3.6 * pow(1.0 - u, 1.2))
		var i := 7 if u < 0.12 else (6 if u < 0.3 else (5 if u < 0.5 else (4 if u < 0.75 else 3)))
		Lib.brokenRing(p, X, Y, r, th, segs, brk, C[i], C[maxi(2, i - 2)], 1.0 if u < 0.6 else (1.0 - u) / 0.4, 1.0, 0.0)
		if u < 0.6:
			p.glowRing(X, Y, r, 6.0, C[5], 0.35 * pow(1.0 - u / 0.6, 2.0))
	bits.draw(p)
	ps.draw(p)
	# the flare blooms as the star collapses
	var f := (t - 0.04) / 0.28
	if f > 0.0 and f < 1.0:
		flare(p, X, Y, 64.0 * pow(1.0 - f, 1.3), 1.0 - f, C)
		p.glow(X, Y, 56.0, C[5], 0.4 * (1.0 - f))
	# the starburst slams in: a white frame, an overshoot, a settle, then it breaks up
	for i in KEYS.size() - 1:
		if t >= KEYS[i][0] and t < KEYS[i + 1][0]:
			var key: Array = KEYS[i]
			var sc: float = key[1]
			var th: float = key[2]
			var a: float = key[3]
			var cols: Array = key[4]
			Lib.star(p, X, Y, sp, sc, th, cols.map(func(j): return C[j]), a, 2.6)
	var pop := exp(-t / 0.05)
	if pop > 0.02:
		p.glow(X, Y, 44.0, C[5], 0.4 * pop)
		p.glow(X, Y, 12.0, WHITE, 0.6 * pop)
	lights.draw(p)
