# The open-sided star, the spark cone off the surface, the chips, dust and smoke are adapted from Sprite Fusion's
# open-source impact (https://www.spritefusion.com/pixel-art-vfx/impact), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/impacts/bullet-impact.js@88ac95432599715b51462367f11203cff207ea95
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Bullet impact",
	"desc": "A bullet hits a wall on the right: a hot half-star, sparks sprayed back in a cone, a puff of grit, chips that fall and bounce, a pock mark cooling to soot.",
	"tags": ["impact", "bullet", "gun", "wall", "sparks", "debris", "directional", "one-shot"],
	"size": [152, 100],
	"origin": [116, 84],
	"duration": 1.4,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": ["#4a1712", "#c9281f", "#f2561d", "#ff8a2a", "#ffe26b", "#fff3a6", "#ffffff"], "stone": "#5b5079", "height": 24, "seed": 6},
}


var C: Array
var st: Dictionary
var R: Px.Rng
var X := 0.0
var Y: float
var D: float
var ps: Px.Particles
var lights: Px.Lights
# the wall's face looks left (N); the bullet came in level, a touch downward, and the spray bounces back off it
const N := PI
const IN := 0.08
const B := PI - IN
var sp: Array
var rim: Array
var cracks: Array
var t := 0.0


func open(a: float) -> bool:
	return cos(a - N) > -0.25


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 7)
	st = Lib.stone(o.stone)
	R = Px.Rng.new(o.seed)
	Y = -o.height
	var floor_ := func(): return 0.0
	D = meta.duration
	ps = Px.Particles.new({"rng": R, "ground": floor_, "sparks": [C[6], C[5], C[4], C[2]]})
	lights = Px.Lights.new()
	sp = Lib.spikes(R, 9, B, {"len": [7.0, 10.5], "w": [1.6, 2.1], "fwd": 1.8, "back": 0.4})
	for s: Dictionary in sp:
		if cos(s.a - N) < -0.2:
			s.len *= 0.3
	# the pock mark: a ragged hole with a rim that glows and cools
	rim = []
	for y in range(-2, 3):
		for x in range(0, 4):
			var d := Px.hypot((x - 1) / 1.6, y / 2.1) + Px.rand(x, y, o.seed) * 0.35
			if d < 0.75:
				rim.append([x, y, 0])
			elif d < 1.25:
				rim.append([x, y, 1])
	cracks = Px.arr(3, func(_i):
		var a := R.range(-1.2, 1.2)
		var L := R.range(2.0, 4.5)
		return [cos(a) * 2.2 + 1.0, sin(a) * 2.2, cos(a) * (2.2 + L) + 1.0, sin(a) * (2.2 + L)])

	lights.add(X - 4.0, Y, 40.0, C[4], 0.6, 0.22)
	lights.add(X - 2.0, Y, 14.0, WHITE, 0.6, 0.06)
	# sparks bounce back off the wall in a cone
	for i in 18:
		var a := B + R.range(-1.0, 1.0) * 0.8
		var v := R.range(170.0, 450.0)
		ps.spawn(P.SPARK, X - 1.0, Y, cos(a) * v, sin(a) * v - 30.0, R.range(0.12, 0.4), WHITE, 1.0, R.range(0.01, 0.04) if i > 13 else 0.0)
	# chips of the wall: flung out, falling, bouncing once and settling
	for i in 8:
		var a := N + R.range(-0.8, 0.6)
		var v := R.range(60.0, 190.0)
		ps.spawn(P.GRIT, X - 1.0, Y + R.range(-1.0, 1.0), cos(a) * v, sin(a) * v - R.range(20.0, 70.0), R.range(0.9, 1.3), R.pick([st.light, st.body, st.body, st.lip]), 2.0 if i < 3 else 1.0)
	# a puff of grit dust and a wisp of smoke drifting off
	for i in 9:
		var a := N + R.range(-1.1, 1.1)
		var v := R.range(15.0, 60.0)
		ps.spawn(P.DUST, X - 2.0, Y + R.range(-1.5, 1.5), cos(a) * v, sin(a) * v, R.range(0.3, 0.55), st.dust if R.chance(0.5) else Px.mix(st.dust, WHITE, 0.25), R.range(1.2, 2.3))
	ps.spawn(P.SMOKE, X - 4.0, Y, R.range(-10.0, -4.0), R.range(-16.0, -8.0), R.range(0.8, 1.2), st.dust, R.range(1.8, 2.4), 0.05)


func update(dt: float) -> void:
	t += dt
	ps.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	ps.draw(p, "back")


func draw(p: Px.Painter) -> void:
	# the pock mark: white-hot, cooling through the ramp to a dark rim, fading at the very end
	var heat := pow(Px.clamp(1.0 - t / 0.9), 1.3)
	var fade := 1.0 - Px.smooth(D - 0.45, D - 0.1, t)
	if fade > 0.0:
		for cr: Array in cracks:
			p.line(X + cr[0], Y + cr[1], X + cr[2], Y + cr[3], C[3] if heat > 0.5 else st.shade, fade * (1.0 if heat > 0.5 else 0.85))
		for rk: Array in rim:
			var x: int = rk[0]
			var y: int = rk[1]
			var k: int = rk[2]
			var h := heat * (0.85 if k else 1.15)
			p.dot(X + x, Y + y, Lib.SOOT if (k == 0 and h < 0.75) else (WHITE if h > 0.85 else (C[5] if h > 0.6 else (C[4] if h > 0.4 else (C[3] if h > 0.22 else (C[2] if h > 0.1 else st.shade))))), fade)
		if heat > 0.0:
			p.glow(X + 1.0, Y, 6.0 + 6.0 * heat, C[3], 0.5 * heat)
	# a half ring opening away from the wall
	var u := (t - 0.03) / 0.18
	if u >= 0.0 and u < 1.0:
		var r := 5.0 + 12.0 * Px.Ease.outCubic(u)
		var c: int = C[5] if u < 0.3 else (C[4] if u < 0.6 else C[3])
		var n := ceilf(r * TAU * 1.3)
		var j := 0.0
		while j < n:
			var g := (j / n) * TAU
			if open(g):
				p.dot(X + cos(g) * r, Y + sin(g) * r, c, 1.15 - u)
			j += 1.0
	ps.draw(p, "front")
	if t < 0.03:
		Lib.star(p, X, Y, sp, 1.0, 1.0, [C[2], C[5], C[4], WHITE], 1.0, 2.2)
	elif t < 0.06:
		Lib.star(p, X, Y, sp, 1.25, 0.55, [C[1], C[4], C[3], C[5]], 1.0, 2.2)
	var pop := exp(-t / 0.045)
	if pop > 0.02:
		p.glow(X - 2.0, Y, 22.0, C[3], 0.6 * pop)
		p.glow(X - 1.0, Y, 8.0, WHITE, 0.5 * pop)
		p.glowLine(X + 1.0, Y - 16.0, X + 1.0, Y + 16.0, 4.0, C[4], 0.4 * pop) # light grazing the wall's face
	lights.draw(p)
