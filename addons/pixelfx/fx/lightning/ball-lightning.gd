# The layered ball, its tapering wake and the zap to the floor with stars where it lands follow Sprite Fusion's
# open-source energy orb and bolt (https://www.spritefusion.com/pixel-art-vfx/energy),
# MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/lightning/ball-lightning.js@4c7331701d630b3d58746c470764cc60c4459a03
extends RefCounted

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Ball lightning",
	"desc": "A crackling ball of plasma drifts on a wandering loop, spitting arcs off its skin and leaving a wake of fading motes, and zaps the floor when it dips low.",
	"tags": ["lightning", "electric", "plasma", "orb", "wisp", "ambient", "loop"],
	"size": [136, 104],
	"origin": [68, 92],
	"duration": 4.0,
	"loop": true,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": Lib.VOLT, "sparks": Lib.PLASMA, "seed": 9},
}

const FPS := 30.0
const N := 120
const P := 4.0
const ZAP := 62
# where the ball is: a closed, wandering path that dips toward the floor once a loop
static func at(t: float) -> Array:
	var a := (t / P) * TAU
	return [38.0 * sin(a) + 9.0 * sin(2.0 * a + 1.0), -42.0 + 13.0 * sin(2.0 * a + 0.4) + 6.0 * sin(3.0 * a + 0.5)]


static func draw(p: Px.Painter, t: float, o: Dictionary) -> void:
	var C := Px.fit(o.palette, 8)
	var S := Px.ramp(o.sparks)
	var f := floori(t * FPS + 1e-6) % N
	var r := Px.rng(o.seed, 1, f)
	var xy := at(t)
	var x: float = xy[0]
	var y: float = xy[1]
	# light under the ball on the floor, stronger as it comes low
	p.glow(x, -2.0, 30.0, C[3], 0.12 + 0.3 * Px.clamp((y + 60.0) / 40.0))
	# the wake: where it has been, shrinking and cooling, and motes shed along it, drifting and dying
	var i := 14
	while i >= 1:
		var w := at(t - i * 0.034)
		var wx: float = w[0]
		var wy: float = w[1]
		var u := i / 14.0
		var rr := 3.0 * (1.0 - u) + 0.3
		if u > 0.6 and (i + f) % 2:
			i -= 1
			continue
		p.circle(wx, wy, rr + 0.8, C[3] if u < 0.35 else C[2])
		p.circle(wx, wy, rr, C[6] if u < 0.35 else (C[5] if u < 0.7 else C[4]))
		p.glow(wx, wy, 7.0 * (1.0 - u) + 3.0, C[4], 0.25 * (1.0 - u))
		i -= 1
	Px.cycle(t, P, 40, o.seed + 5, func(g): return g.range(0.5, 1.0), func(age, life, q):
		var born: float = t - age
		var bxy := at(born)
		var bx: float = bxy[0]
		var by: float = bxy[1]
		var k: float = 1.0 - age / life
		var a: float = q.range(0.0, TAU)
		var sp: float = q.range(4.0, 14.0)
		var mx: float = bx + cos(a) * sp * age + q.range(-3.0, 3.0)
		var my: float = by + sin(a) * sp * age + 6.0 * age + q.range(-3.0, 3.0)
		if k > 0.25 or f % 2:
			p.px(mx, my, C[6] if k > 0.6 else (C[4] if k > 0.3 else C[3]))
		p.glow(mx, my, 3.0, C[4], 0.3 * k))
	# the ball: a churning skin with hot spots rolling round it, a white heart, corona bristling off it
	var R0 := 5.2 + 0.6 * sin(t * 9.0) + 0.4 * r.range(-1.0, 1.0)
	p.circle(x, y, R0 + 1.3, C[2])
	p.circle(x, y, R0, C[4])
	p.circle(x - 0.4, y - 0.4, R0 * 0.72, C[5])
	for j in 3:
		var a := t * (5.0 + j * 2.3) + j * 2.1
		var d := R0 * 0.6
		p.circle(x + cos(a) * d, y + sin(a) * d * 0.8, 1.2, C[6] if j else WHITE)
	p.circle(x - 0.6, y - 0.6, R0 * 0.32, WHITE)
	for j in 8:
		if r.next() < 0.35:
			continue
		var a := (j / 8.0) * TAU + t * 2.0 + r.range(-0.2, 0.2)
		var l := r.range(1.5, 4.0)
		p.line(x + cos(a) * (R0 + 1.0), y + sin(a) * (R0 + 1.0), x + cos(a) * (R0 + 1.0 + l), y + sin(a) * (R0 + 1.0 + l), C[5] if j % 2 else C[4])
	p.glow(x, y, 30.0, C[4], 0.3)
	p.glow(x, y, 9.0, C[6], 0.1)
	# arcs spat off its skin, re-struck every frame
	var j := 0
	while j < 2 + (1 if r.next() < 0.4 else 0):
		var a := r.range(0.0, TAU)
		var l := r.range(5.0, 11.0)
		var x0 := x + cos(a) * (R0 + 1.0)
		var y0 := y + sin(a) * (R0 + 1.0)
		var b := a + r.range(-0.7, 0.7)
		Lib.crackle(p, Lib.zigzag(r, x0, y0, x0 + cos(b) * l, y0 + sin(b) * l, 0.4, 0.3), r.range(0.4, 0.7), C, 0.25)
		j += 1
	# once a loop, low over the floor, it zaps down: a bolt, the floor lit, sparks kicked up
	var za := f - ZAP
	var zx: float = at(ZAP / FPS)[0]
	var gx := zx + Px.rng(o.seed, 3).range(-10.0, 10.0)
	if za >= 0 and za < 4:
		var k: float = [1.0, 0.6, 0.9, 0.4][za]
		Lib.stroke(p, Lib.zigzag(Px.rng(o.seed, 4, f), x, y + R0, gx, 0.0, 0.28, 0.4), k, C, 0.7, {"hero": za == 0})
		p.circle(gx, -1.0, 2.5 * k + 1.0, C[5])
		p.px(gx, -1.0, WHITE)
		p.glow(gx, -4.0, 34.0, C[4], 0.6 * k)
	var sa := Px.wrap(t - ZAP / FPS, P)
	for jj in 14:
		var q := Px.rng(o.seed, 7, jj)
		var life := q.range(0.25, 0.55)
		if sa >= life:
			continue
		var a := -PI / 2.0 + q.range(-1.3, 1.3)
		var sp := q.range(50.0, 170.0)
		var fl := Lib.flight(gx, -1.0, cos(a) * sp, sin(a) * sp, sa, {"floor": 0.0})
		Lib.spark(p, fl[0], fl[1], fl[2], fl[3], 1.0 - sa / life, S)
