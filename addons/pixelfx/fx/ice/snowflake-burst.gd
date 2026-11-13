# The pop recipe (a gathering, a white flash with a ring and flares, twinkling motes that linger and fade) is
# adapted from Sprite Fusion's open-source sparkle (https://www.spritefusion.com/pixel-art-vfx/sparkle),
# MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/ice/snowflake-burst.js@26d60c74a7b850479cca215709d76e5c1514dc55
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Snowflake burst",
	"desc": "A cold pop: frost gathers and flashes white in a ring, then crisp six-armed snowflakes spin out, slow, twinkle and drift down to settle and melt.",
	"tags": ["ice", "snow", "snowflake", "burst", "magic", "one-shot"],
	"size": [140, 120],
	"origin": [70, 106],
	"duration": 3.2,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": ["#151a3d", "#212f6b", "#2c58aa", "#3a8bd8", "#62c8f4", "#a6ecff", "#dcfbff", "#ffffff"], "count": 9, "seed": 8},
}

const POP := 0.16
const CY := -48.0
const SIZES := [2, 0, 1, 0, 2, 0, 1, 0, 1]

var C: Array
var R: Px.Rng
var ps: Px.Particles
var lights: Px.Lights
# the flakes: two big, a few middling, the rest small; small ones fly further
var flakes: Array = []
var t := 0.0
var popped := false


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	R = Px.Rng.new(o.seed)
	var floor_ := func(): return 0.0
	ps = Px.Particles.new({"rng": R, "ground": floor_, "sparks": [C[7], C[6], C[5], C[4]], "haze": C[5]})
	lights = Px.Lights.new()
	flakes = []
	var i := 0
	while i < o.count:
		var z: int = SIZES[i % SIZES.size()]
		var r := R.range(9.5, 11.5) if z == 2 else (R.range(6.0, 7.5) if z == 1 else R.range(3.0, 4.5))
		var a: float = (i / o.count) * TAU + R.range(-0.3, 0.3) + 0.4
		var sp := R.range(80.0, 120.0) * (1.4 - r / 14.0)
		flakes.append({
			"x": 0.0, "y": CY, "vx": cos(a) * sp, "vy": sin(a) * sp * 0.85 - 20.0, "r": r, "rot": R.range(0.0, TAU), "w0": R.sign() * R.range(7.0, 12.0), "w1": R.sign() * R.range(0.4, 1.0),
			"d": Lib.flakeDesign(R), "life": R.range(2.1, 2.8), "age": 0.0, "ph": R.range(0.0, TAU), "tw": R.range(0.5, 0.85), "tw0": R.range(0.15, 0.6), "rest": false, "popped": false,
		})
		i += 1


func sz(f: Dictionary) -> float:
	return f.r * minf(1.0, Px.Ease.outBack(Px.clamp(f.age / 0.18), 2.0)) * minf(1.0, (f.life - f.age) / 0.35)


func update(dt: float) -> void:
	t += dt
	# the cold gathers: streaks of frost spiral in, snow motes drift in
	if t < POP - 0.03 and R.chance(0.8):
		var a := R.range(0.0, TAU)
		var D := R.range(22.0, 44.0)
		var T := R.range(0.12, 0.16)
		var v := (D * 3.0) / (exp(3.0 * T) - 1.0)
		ps.spawn(P.STREAK, cos(a) * D, CY + sin(a) * D, -cos(a) * v, -sin(a) * v, T, C[6] if R.chance(0.5) else C[5])
	if not popped and t >= POP:
		popped = true
		lights.add(0.0, CY, 44.0, WHITE, 0.8, 0.1)
		lights.add(0.0, CY, 72.0, C[4], 0.5, 0.6)
		# frost thrown out: streaking motes, snow, glints that come and go round it
		for i in 22:
			var a := R.range(0.0, TAU)
			var sp := R.range(80.0, 150.0)
			ps.spawn(P.MOTE, 0.0, CY, cos(a) * sp, sin(a) * sp, R.range(0.25, 0.5), C[6] if R.chance(0.5) else C[5], R.range(0.6, 1.0))
		for i in 18:
			var a := R.range(-PI, 0.2)
			var sp := R.range(30.0, 110.0)
			ps.spawn(P.FLAKE, 0.0, CY, cos(a) * sp, sin(a) * sp, R.range(1.0, 1.6), WHITE if R.chance(0.6) else C[6], R.range(0.5, 1.5))
		for i in 12:
			var a := R.range(0.0, TAU)
			var d := R.range(10.0, 44.0)
			ps.spawn(P.STAR, cos(a) * d, CY + sin(a) * d * 0.85, 0.0, R.range(2.0, 6.0), R.range(0.3, 0.6), WHITE if R.chance(0.5) else C[6], R.range(0.8, 2.2), R.range(0.08, 1.6))
	if popped:
		for f: Dictionary in flakes:
			f.age += dt
			if f.age >= f.life:
				continue
			if not f.rest:
				f.vx -= f.vx * 2.8 * dt
				f.vy -= f.vy * 2.8 * dt - 26.0 * dt
				f.x += f.vx * dt + sin(t * 1.8 + f.ph) * 5.0 * dt
				f.y += f.vy * dt
				f.rot += (f.w1 + (f.w0 - f.w1) * exp(-f.age * 2.5)) * dt
				# it settles on the floor, flat and still, and melts there
				if f.y > -sz(f) * 0.3:
					f.rest = true
					f.y = -1.0
					f.life = minf(f.life, f.age + 0.6)
			# a melted or spent flake goes out with a glint or two
			if not f.popped and f.life - f.age < 0.1:
				f.popped = true
				for i in 2:
					ps.spawn(P.STAR, f.x + R.range(-2.0, 2.0), f.y + R.range(-2.0, 2.0), R.range(-6.0, 6.0), -R.range(2.0, 8.0), R.range(0.2, 0.4), WHITE if R.chance(0.5) else C[6], R.range(0.8, 1.6))
	ps.update(dt)
	lights.update(dt)
	Lib.endBy(t, meta.duration, ps)


func draw(p: Px.Painter) -> void:
	# the gathering: a tiny flake spins up at the heart, faster and brighter
	if t < POP:
		var k := t / POP
		Lib.snowflake(p, 0.0, CY, 1.0 + 3.2 * k * k, t * 20.0, flakes[0].d, C, {"hot": k})
		p.glow(0.0, CY, 8.0 + 14.0 * k, C[5], 0.3 + 0.4 * k)
	# the pop: a white flash, a flare and a ring of frost running out
	var q := t - POP
	if q >= 0.0 and q < 0.4:
		if q < 0.07:
			p.circle(0.0, CY, 6.0 * (1.0 - q / 0.07) + 1.0, WHITE)
		Px.flare(p, 0.0, CY, 28.0 * pow(maxf(0.0, 1.0 - q / 0.26), 1.5), 1.0 - q / 0.26, C)
		var e := Px.Ease.outCubic(q / 0.4)
		var r := 5.0 + 34.0 * e
		p.ring(0.0, CY, r, maxf(1.0, 2.4 * (1.0 - e)), WHITE if q < 0.08 else (C[6] if q < 0.2 else C[5]), 1.15 - e)
		p.glowRing(0.0, CY, r, 5.0, C[5], 0.4 * (1.0 - e))
	# the cold light left where it burst, fading
	if popped:
		p.glow(0.0, CY, 46.0, C[4], 0.3 * (1.0 - Px.smooth(POP, POP + 1.6, t)))
	# the flakes: spinning out, twinkling now and then, landing and melting
	for f: Dictionary in flakes:
		if not popped or f.age >= f.life:
			continue
		var r := sz(f)
		var tw: float = pow(maxf(0.0, sin(((f.age - f.tw0) / f.tw) * TAU)), 8.0) * (1.0 if f.age > f.tw0 else 0.0)
		if f.rest:
			# lying on the floor: flattened to a sparkling smear that shrinks away
			var L := maxf(1.0, Px.round(r * 1.2 * ((f.life - f.age) / 0.6)))
			var i := -L
			while i <= L:
				p.px(f.x + i, -1.0, C[5] if absf(i) == L else (WHITE if i == 0.0 else C[6]))
				i += 1.0
			p.glow(f.x, -1.0, 3.0 + L, C[4], 0.3)
			continue
		Lib.snowflake(p, f.x, f.y, r, f.rot, f.d, C, {"hot": maxf(tw, 1.0 - Px.clamp(f.age / 0.12))})
		p.glow(f.x, f.y, 6.0 + r * 1.4, C[4], 0.12)
		if tw > 0.5:
			Px.flare(p, f.x, f.y, (3.0 + r * 0.7) * tw, tw, C)
	ps.draw(p)
	lights.draw(p)
