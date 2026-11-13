# The star's key frames and the spark spray are adapted from Sprite Fusion's open-source impact
# (https://www.spritefusion.com/pixel-art-vfx/impact), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/impacts/parry.js@4c9960eb8015112b20dd8118240c9920c8300b15
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Parry",
	"desc": "Two blades clash: their edges flash in an X, a white four-point star rings out, a ring breaks into arcs and a fan of gold sparks sprays up and rains down.",
	"tags": ["impact", "parry", "block", "clash", "sword", "metal", "sparks", "one-shot"],
	"size": [200, 112],
	"origin": [100, 96],
	"duration": 1,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": ["#2a1a08", "#6a4410", "#b07a1a", "#e8b030", "#ffe066", "#fff6c4", "#ffffff"], "height": 30, "seed": 11},
}


var C: Array
var R: Px.Rng
var X := 0.0
var Y: float
var ps: Px.Particles
var lights: Px.Lights
var sp: Array
var segs: Array
var edges: Array
var t := 0.0


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 7)
	R = Px.Rng.new(o.seed)
	Y = -o.height
	var floor_ := func(): return 0.0
	ps = Px.Particles.new({"rng": R, "ground": floor_, "sparks": [C[4], C[4], C[3], C[2]]})
	lights = Px.Lights.new()
	# a hard four-point star: long arms on the axes, short ones between
	sp = []
	for i in 8:
		sp.append({"a": (i * PI) / 4.0 + R.range(-0.04, 0.04), "len": R.range(6.0, 8.0) if i % 2 else (R.range(19.0, 22.0) if i % 4 == 0 else R.range(14.0, 17.0)), "w": 1.2 if i % 2 else 2.2})
	segs = Px.arr(6, func(i: int): return {"a": (i / 6.0) * TAU + R.range(-0.1, 0.1), "gap": R.range(0.55, 0.8), "dr": R.range(0.1, 0.35)})
	# the two edges that met: lines crossing in an X
	edges = [-0.62 + R.range(-0.08, 0.08), PI + 0.62 + R.range(-0.08, 0.08)]

	lights.add(X, Y, 60.0, C[4], 0.65, 0.4)
	lights.add(X, Y, 22.0, WHITE, 0.8, 0.08)
	# the fan: sparks thrown up and out to both sides, arcing over and raining down to bounce on the floor
	for i in 24:
		var s := 1.0 if i % 2 else -1.0
		var a := -PI / 2.0 + s * R.range(0.3, 1.3)
		var v := R.range(130.0, 290.0)
		ps.spawn(P.SPARK, X + s * R.range(1.0, 3.0), Y, cos(a) * v, sin(a) * v, R.range(0.45, 0.85), WHITE, 1.0, R.range(0.02, 0.07) if i > 17 else 0.0)
	for i in 8:
		var a := R.range(0.0, TAU)
		var v := R.range(40.0, 110.0)
		ps.spawn(P.MOTE, X, Y, cos(a) * v, sin(a) * v - 20.0, R.range(0.3, 0.55), R.pick([C[5], C[6]]), 0.6, R.range(0.0, 0.04))
	for i in 3:
		var a := R.range(0.0, TAU)
		var d := R.range(12.0, 26.0)
		ps.spawn(P.STAR, X + cos(a) * d, Y + sin(a) * d, 0.0, -3.0, R.range(0.22, 0.34), WHITE, R.range(1.6, 2.6), R.range(0.1, 0.3))


func update(dt: float) -> void:
	t += dt
	ps.update(dt)
	lights.update(dt)


func draw(p: Px.Painter) -> void:
	# the ring: rings out off the star and breaks into arcs that fly on and cool
	var u := (t - 0.03) / 0.36
	if u >= 0.0 and u < 1.0:
		var r := 8.0 + 24.0 * Px.Ease.outCubic(u)
		var brk := Px.smooth(0.15, 0.6, u)
		var i := 6 if u < 0.15 else (5 if u < 0.35 else (4 if u < 0.6 else 3))
		Lib.brokenRing(p, X, Y, r, maxf(1.0, 2.6 * pow(1.0 - u, 1.2)), segs, brk, C[i], C[maxi(2, i - 2)], 1.0 if u < 0.6 else (1.0 - u) / 0.4, 1.0, 0.0)
		if u < 0.5:
			p.glowRing(X, Y, r, 5.0, C[4], 0.3 * (1.0 - u / 0.5))
	ps.draw(p)
	# the edges flash where they met
	if t < 0.058:
		for a: float in edges:
			var ca := cos(a)
			var sa := sin(a)
			var L := 26.0 if t < 0.025 else 32.0
			var k := 1.0 if t < 0.025 else 0.6
			var d := -L
			while d <= L:
				var q := absf(d) / L
				p.dot(X + ca * d, Y + sa * d, WHITE if q < 0.4 else (C[5] if q < 0.75 else C[4]), 1.0 if q < 0.6 else k * (1.3 - q))
				d += 0.5
			p.glowLine(X - ca * L, Y - sa * L, X + ca * L, Y + sa * L, 4.0, C[5], 0.35 * k)
	# the star: white, then bigger and gold as it thins, then just a glint
	if t < 0.025:
		Lib.star(p, X, Y, sp, 1.0, 1.0, [C[4], WHITE, WHITE, WHITE], 1.0, 2.6)
	elif t < 0.058:
		Lib.star(p, X, Y, sp, 1.25, 0.65, [C[2], C[5], C[6], WHITE], 1.0, 2.6)
	elif t < 0.092:
		Lib.star(p, X, Y, sp, 1.4, 0.3, [C[2], C[4], C[5], C[6]], 1.0, 2.0)
	var pop := exp(-t / 0.05)
	if pop > 0.02:
		p.glow(X, Y, 30.0, C[4], 0.5 * pop)
		p.glow(X, Y, 10.0, WHITE, 0.4 * pop)
	lights.draw(p)
