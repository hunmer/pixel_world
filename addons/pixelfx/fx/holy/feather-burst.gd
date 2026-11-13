# port-of: src/fx/holy/feather-burst.js@16c0cd2393b027c12a763e9d722193efca1bf675
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Feather burst",
	"desc": "A white puff pops and throws feathers that brake hard, then rock from side to side as they sink and fade, with down drifting after them.",
	"tags": ["holy", "feather", "burst", "poof", "angel", "bird", "one-shot"],
	"size": [160, 160],
	"origin": [80, 60],
	"duration": 3,
	"loop": false,
	"fps": 30,
	"bg": "dark",
	"options": {"palette": ["#4a4560", "#7a7494", "#aaa5c2", "#d6d3e6", "#f4f3fa", "#ffffff"], "glow": "#fff0c0", "seed": 4},
}

var F: Array
var G: int
var R: Px.Rng
var ps: Px.Particles
var lights: Px.Lights
var loose: Lib.Feathers
var lobes: Array
var t := 0.0


func create(o: Dictionary) -> void:
	F = Px.fit(o.palette, 6)
	G = Px.hex(o.glow)
	R = Px.Rng.new(o.seed)
	ps = Px.Particles.new({"rng": R, "ground": func(): return INF, "sparks": [WHITE, F[4], F[3], F[2]]})
	lights = Px.Lights.new()
	loose = Lib.Feathers.new(R, 1e6)
	# the puff: soft lobes thrown out from the pop, swelling and thinning
	lobes = Px.arr(11, func(i: int):
		var a := (i / 11.0) * TAU + R.range(-0.25, 0.25)
		var d := R.range(5.0, 14.0)
		return {"x": cos(a) * d, "y": sin(a) * d * 0.8, "r0": R.range(2.5, 4.0), "r1": R.range(6.0, 9.5), "life": R.range(0.45, 0.8)})
	for i in 20:
		var a := (i / 20.0) * TAU + R.range(-0.15, 0.15)
		var sp := R.range(110.0, 230.0)
		var up := 0.7 if sin(a) < 0.0 else 0.9
		loose.add({"x": cos(a) * 3.0, "y": sin(a) * 3.0, "vx": cos(a) * sp, "vy": sin(a) * sp * up - 20.0, "a": a + R.range(-0.5, 0.5), "len": R.range(10.0, 14.0), "wid": R.range(2.6, 3.4), "life": R.range(1.9, 2.6), "delay": R.range(0.0, 0.03), "sink": R.range(26.0, 38.0), "amp": R.range(8.0, 13.0)})
	# small feathers and down, slower
	for i in 10:
		var a := R.range(0.0, TAU)
		var sp := R.range(50.0, 130.0)
		loose.add({"x": 0.0, "y": 0.0, "vx": cos(a) * sp, "vy": sin(a) * sp - 20.0, "a": R.range(0.0, TAU), "len": R.range(6.0, 8.0), "wid": R.range(1.8, 2.2), "life": R.range(1.6, 2.4), "back": true, "sink": R.range(18.0, 28.0)})
	for i in 26:
		var a := R.range(0.0, TAU)
		var sp := R.range(30.0, 140.0)
		ps.spawn(P.FLAKE, R.range(-3.0, 3.0), R.range(-3.0, 3.0), cos(a) * sp, sin(a) * sp - 15.0, R.range(1.4, 2.6), WHITE if R.chance(0.6) else F[4], R.range(0.6, 1.6))
	for i in 10:
		var a := R.range(0.0, TAU)
		var sp := R.range(60.0, 160.0)
		ps.spawn(P.STAR, 0.0, 0.0, cos(a) * sp, sin(a) * sp, R.range(0.3, 0.6), WHITE if R.chance(0.5) else G, R.range(0.8, 2.2))
	lights.add(0.0, 0.0, 50.0, G, 0.75, 0.45)
	lights.add(0.0, 0.0, 20.0, WHITE, 0.7, 0.1)


func puff(p: Px.Painter) -> void:
	for l: Dictionary in lobes:
		var u: float = t / l.life
		if u >= 1.0:
			continue
		var e := Px.Ease.outCubic(u)
		var x: float = l.x * (0.4 + e * 1.3)
		var y: float = l.y * (0.4 + e * 1.3) - u * 5.0
		var r: float = (l.r0 + (l.r1 - l.r0) * Px.Ease.outCubic(minf(1.0, u * 3.0))) * (1.0 - Px.Ease.inQuad(u))
		if r < 0.6:
			continue
		p.circle(x, y, r + 0.8, F[2])
		p.circle(x, y, r, func(d, a): return F[3] if (d > 0.55 and sin(a + 0.8) > 0.3) else (WHITE if (d < 0.45 and sin(a + 0.8) < -0.2) else F[4]))


func update(dt: float) -> void:
	t += dt
	# feathers catch the light as they turn
	if t > 0.3 and t < 2.2 and loose.count and R.chance(0.14):
		var q: Dictionary = R.pick(loose.list)
		if q.delay <= 0:
			ps.spawn(P.STAR, q.x + R.range(-2.0, 2.0), q.y + R.range(-1.0, 1.0), 0.0, 0.0, R.range(0.2, 0.4), WHITE if R.chance(0.5) else G, R.range(1.0, 2.2))
	ps.update(dt)
	loose.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	loose.draw(p, F, "back")
	ps.draw(p, "back")
	puff(p)


func draw(p: Px.Painter) -> void:
	# the pop: a white flash and a ring of air
	if t < 0.07:
		p.circle(0.0, 0.0, 9.0 * (1.0 - t / 0.14), WHITE)
	if t < 0.25:
		var u := t / 0.25
		p.ring(0.0, 0.0, 6.0 + 24.0 * Px.Ease.outCubic(u), maxf(1.0, 2.5 * (1.0 - u)), func(v): return WHITE if v > 0.5 else Px.mix(F[4], G, 0.4), 1.1 - u)
	if t < 0.2:
		Px.sparkle(p, 0.0, 0.0, 10.0 * (1.0 - t / 0.2), WHITE, G, 0.6)
	# the burst's warmth lingers a moment
	p.glow(0.0, 4.0, 46.0, G, 0.28 * (1.0 - Px.smooth(0.0, 1.3, t)))
	loose.draw(p, F, "front")
	ps.draw(p, "front")
	lights.draw(p)
