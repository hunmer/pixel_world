# The glancing star, the tracer that streaks off, the skid on the surface and the spark spray are adapted from
# Sprite Fusion's open-source impact (https://www.spritefusion.com/pixel-art-vfx/impact), MIT License,
# Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/impacts/ricochet.js@1bc4202629dcd6399dc32e914e423e7c68e4f90a
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Ricochet",
	"desc": "A tracer streaks down onto the floor, glances off with a white-hot star and skips away at an angle, leaving a glowing skid while sparks skitter along the ground.",
	"tags": ["impact", "ricochet", "bullet", "tracer", "sparks", "ground", "directional", "one-shot"],
	"size": [232, 84],
	"origin": [64, 60],
	"duration": 1.1,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": ["#4a1712", "#c9281f", "#f2561d", "#ff8a2a", "#ffe26b", "#fff3a6", "#ffffff"], "stone": "#5b5079", "seed": 8},
}

# when it lands, how fast it flies, the angles in and out
const HIT := 0.05
const SPEED := 760.0
const IN := 0.32
const OUT := -0.21


# a tracer: a white head, a hot body cooling to a dim tail, from (hx, hy) back along angle a for L px
static func tracer(p: Px.Painter, hx: float, hy: float, a: float, L: float, C: Array, k: float = 1.0) -> void:
	var c := cos(a)
	var s := sin(a)
	var d := 0.0
	while d <= L:
		var u := d / L
		p.dot(hx - c * d, hy - s * d, WHITE if u < 0.12 else (C[5] if u < 0.45 else (C[4] if u < 0.75 else C[2])), 1.0 if u < 0.45 else k * (1.25 - u))
		d += 0.5
	p.glow(hx, hy, 9.0, C[4], 0.6 * k)


var C: Array
var st: Dictionary
var R: Px.Rng
var D: float
var ps: Px.Particles
var lights: Px.Lights
var sp: Array
var t := 0.0
var hit := false


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 7)
	st = Lib.stone(o.stone)
	R = Px.Rng.new(o.seed)
	var floor_ := func(): return 0.0
	D = meta.duration
	ps = Px.Particles.new({"rng": R, "ground": floor_, "sparks": [C[6], C[5], C[4], C[2]]})
	lights = Px.Lights.new()
	# the star leans hard along the way out, and barely digs into the floor
	sp = Lib.spikes(R, 9, OUT, {"len": [6.0, 9.0], "w": [1.4, 1.9], "fwd": 2.6, "back": 0.6})
	for s: Dictionary in sp:
		if sin(s.a) > 0.2:
			s.len *= 0.3
		if absf(sin(s.a - OUT)) > 0.6:
			s.len *= 0.65


func update(dt: float) -> void:
	t += dt
	if not hit and t >= HIT:
		hit = true
		lights.add(0.0, -2.0, 44.0, C[4], 0.65, 0.25)
		lights.add(0.0, -1.0, 14.0, WHITE, 0.6, 0.06)
		# sparks skitter on along the floor, skipping, and a few spray higher
		for i in 18:
			var low := i < 12
			var a := OUT + (R.range(-0.22, 0.12) if low else R.range(-0.7, 0.25))
			var v := R.range(260.0, 520.0) * (1.0 if low else 0.7)
			ps.spawn(P.SPARK, R.range(-1.0, 2.0), -1.0, cos(a) * v, sin(a) * v, R.range(0.15, 0.42) * (1.3 if low else 1.0), WHITE, 1.0, R.range(0.0, 0.05) if low else 0.0)
		# grit kicked up and a scuff of dust
		for i in 7:
			var a := -PI / 2.0 + R.range(-0.2, 0.9)
			var v := R.range(60.0, 170.0)
			ps.spawn(P.GRIT, R.range(0.0, 4.0), -1.0, cos(a) * v, sin(a) * v, R.range(0.6, 0.95), R.pick([st.light, st.body, st.lip]), 2.0 if i < 2 else 1.0)
		for i in 4:
			ps.spawn(P.DUST, R.range(0.0, 8.0), -1.0, R.range(20.0, 70.0), -R.range(4.0, 16.0), R.range(0.25, 0.45), Px.mix(st.dust, WHITE, R.range(0.1, 0.3)), R.range(1.2, 2.0))
	ps.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	# the skid: a gouge along the floor that glows where the round dragged, cooling from its far end
	var u := t - HIT
	if u >= 0.0:
		var heat := pow(Px.clamp(1.0 - u / 0.85), 1.2)
		var fade := 1.0 - Px.smooth(D - 0.4, D - 0.05, t)
		var L := 12.0 * minf(1.0, u / 0.03)
		var x := -3
		while x <= L:
			var q := (x + 3) / 15.0
			var h := heat * (1.15 - q * 0.6)
			p.dot(x, 0.0, WHITE if h > 0.8 else (C[5] if h > 0.55 else (C[4] if h > 0.35 else (C[3] if h > 0.18 else (C[2] if h > 0.08 else Lib.SOOT)))), fade)
			if x > -2 and x < L - 2.0 and (x & 1) == 0:
				p.dot(x, 1.0, C[3] if h > 0.4 else Lib.SOOT, fade * 0.7)
			x += 1
		if heat > 0.0:
			p.glowLine(-3.0, 0.0, L, 0.0, 5.0, C[3], 0.45 * heat)
	ps.draw(p, "back")


func draw(p: Px.Painter) -> void:
	ps.draw(p, "front")
	if t < HIT:
		# incoming: the tracer races down to the floor
		var d := (HIT - t) * SPEED
		tracer(p, -cos(IN) * d, -sin(IN) * d, IN, 22.0, C)
	else:
		var u := t - HIT
		# glancing off: a stretched star, then the round skips away, its tail stretching out behind it
		if u < 0.03:
			Lib.star(p, 0.0, -1.0, sp, 1.0, 1.0, [C[2], C[5], C[4], WHITE], 1.0, 2.0)
		elif u < 0.06:
			Lib.star(p, 0.0, -1.0, sp, 1.25, 0.55, [C[1], C[4], C[3], C[5]], 1.0, 2.0)
		if u < 0.2:
			var head := 4.0 + u * SPEED
			var k := 1.0 - u / 0.2
			tracer(p, cos(OUT) * head, -1.0 + sin(OUT) * head, OUT, minf(head - 2.0, 18.0 + u * 200.0), C, k)
		# a thin half ring hugging the floor, swelling and cooling
		var g := (u - 0.02) / 0.2
		if g >= 0.0 and g < 1.0:
			var r := 5.0 + 12.0 * (1.0 - pow(1.0 - g, 3.0))
			var c: int = C[5] if g < 0.3 else (C[4] if g < 0.6 else C[3])
			var n := ceilf(r * PI * 1.3)
			var j := 0.0
			while j <= n:
				var a := -PI + (j / n) * PI
				p.dot(cos(a) * r, -1.0 + sin(a) * r, c, 1.15 - g)
				j += 1.0
		var pop := exp(-u / 0.045)
		if pop > 0.02:
			p.glow(0.0, -2.0, 22.0, C[3], 0.75 * pop)
			p.glow(0.0, -1.0, 8.0, WHITE, 0.5 * pop)
	lights.draw(p)
