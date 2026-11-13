# port-of: src/fx/holy/heal-aoe.js@5e7c9d9fa3dccdc9a73c541397f1dcc06a43f75c
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Healing ring",
	"desc": "A seed of green light sinks into the floor and a soft ring rolls out from it; the floor glows where it passes and plus signs sprout and float up.",
	"tags": ["holy", "heal", "aoe", "ring", "plus", "ground", "one-shot"],
	"size": [256, 136],
	"origin": [128, 104],
	"duration": 2.9,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": Lib.GREEN, "reach": 104, "seed": 6},
}

const SY := 0.2
const SEED := 0.3
const ROLL := 1.0

var C: Array
var REACH: float
var R: Px.Rng
var ps: Px.Particles
var lights: Px.Lights
var sites: Array
var riders: Array
var t := 0.0
var released := false


func front(tt: float) -> float:
	return 0.0 if tt < SEED else REACH * Px.Ease.outCubic(Px.seg(tt, SEED, SEED + ROLL))


func passed(d: float) -> float:
	return SEED + ROLL * (1.0 - Px.cbrt(1.0 - minf(0.999, d / REACH)))


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	REACH = o.reach
	R = Px.Rng.new(o.seed)
	ps = Px.Particles.new({"rng": R, "ground": func(): return 0.0, "sparks": [WHITE, C[6], C[5], C[4]]})
	lights = Px.Lights.new()
	# where plus signs sprout: scattered over the floor, each waiting for the ring to reach it
	sites = Px.arr(26, func(i: int):
		var a := R.range(0.0, TAU)
		var d := REACH * sqrt(R.range(0.04, 0.92))
		var big := i % 5 < 2
		return {"x": cos(a) * d, "z": sin(a) * d, "t0": passed(d) + R.range(0.0, 0.06), "rise": R.range(18.0, 34.0), "life": R.range(0.9, 1.3), "sway": R.range(0.0, TAU), "L": (3.0 + (1.0 if i % 5 == 0 else 0.0)) if big else (1.0 if i % 5 == 2 else 2.0), "thick": 3.0 if big else 1.0, "popped": false})
	# the rolling ring carries little lights round with it
	riders = Px.arr(14, func(i: int): return {"a": (i / 14.0) * TAU + R.range(-0.2, 0.2), "w": R.range(0.6, 1.1) * (1.0 if i % 2 else -1.0)})


func wash(p: Px.Painter) -> void:
	# the floor glows behind the front and fades after it
	var fr := front(t)
	if fr < 2.0 or t > 2.6:
		return
	p.shade(-fr - 1.0, -fr * SY - 1.0, fr + 1.0, fr * SY + 1.0, func(x: float, y: float, out) -> void:
		var d := Px.hypot(x, y / SY)
		if d > fr:
			return
		var age := t - passed(d)
		var k := exp(-age / 0.35) * Px.smooth(fr, fr - 6.0, d) * (1.0 - Px.smooth(1.4, 1.9, t))
		if k < 0.04:
			return
		out.l = C[4]
		out.k = 0.32 * k)


func ring(p: Px.Painter, back: bool) -> void:
	if t < SEED:
		return
	var u := Px.seg(t, SEED, SEED + ROLL + 0.25)
	var fr := front(t)
	var k := 1.0 if u < 0.7 else (1.0 - u) / 0.3
	if k <= 0.0:
		return
	var keep: Callable = (func(g): return sin(g) < 0.0) if back else (func(g): return sin(g) >= 0.0)
	Px.band(p, 0.0, 0.0, fr, SY, maxf(2.0, 7.0 * (1.0 - u * 0.7)), k, C.slice(2), keep, t < SEED + 0.08)
	var CC := C
	Lib.oval(p, 0.0, 0.0, fr + 1.0, (fr + 1.0) * SY, func(g): return WHITE if sin(g) > 0.3 else CC[6], k * (0.7 if back else 1.0), keep)
	# a crest of light blades flickers up along the front as it rolls
	var n := ceilf(fr * 0.9)
	var j := 0
	while j < n:
		var g := (j / n) * TAU
		var near := sin(g) >= 0.0
		if near == back or Px.rand(j, floorf(t * 20.0)) > 0.45:
			j += 1
			continue
		var x := cos(g) * fr
		var y := sin(g) * fr * SY
		var h := (1.0 + Px.rand(j, 7) * 4.0) * k * (1.0 if near else 0.6)
		var i := 1
		while i <= h:
			p.dot(x, y - i, WHITE if i > h - 1.0 else C[6], k * (1.2 - i / (h + 1.0)))
			i += 1
		j += 1
	# lights riding round the ring as it rolls
	for r: Dictionary in riders:
		var g: float = r.a + r.w * (t - SEED) * 2.2
		var near := sin(g) >= 0.0
		if near == back:
			continue
		var x := cos(g) * fr
		var y := sin(g) * fr * SY
		if near:
			Px.sparkle(p, x, y - 1.0, 2.0 + (1.0 if sin(t * 9.0 + r.a * 5.0) > 0.3 else 0.0), WHITE, C[6], 0.35 * k)
		else:
			p.dot(x, y, C[6], k)
	if not back:
		for i in 8:
			var g := (i / 8.0) * TAU
			p.glow(cos(g) * fr, sin(g) * fr * SY - 2.0, 16.0, C[4], 0.22 * k)


func sprouts(p: Px.Painter, back: bool) -> void:
	for s: Dictionary in sites:
		var a: float = t - s.t0
		if a < 0.0 or a > s.life or (s.z < 0.0) != back:
			continue
		var u: float = a / s.life
		var h: float = s.rise * Px.Ease.outCubic(u)
		var x: float = s.x + sin(a * 4.0 + s.sway) * 1.5 * u
		var y: float = s.z * SY - 2.0 - h
		var pop := Px.Ease.outBack(Px.clamp(a / 0.12), 2.6)
		var end: float = s.life - 0.15
		var L := maxf(1.0, Px.round(s.L * pop - (1.0 if back else 0.0)))
		if a < 0.04:
			Px.sparkle(p, x, y, 3.0, WHITE, C[6], 0.5)
		elif a < end:
			Lib.plus(p, x, y, L, 1.0 if (back and L < 3.0) else s.thick, C.slice(0, 7) if back else C, 0.8 if back else 1.0, not back and sin(a * 12.0 + s.sway * 3.0) > 0.8)
		else:
			var v := (a - end) / 0.15
			for dd: Array in [[1, 1], [1, -1], [-1, 1], [-1, -1]]:
				var dx: int = dd[0]
				var dy: int = dd[1]
				p.dot(x + dx * (2.0 + v * 5.0), y + dy * (2.0 + v * 5.0) - v * 2.0, WHITE if v < 0.4 else C[6], 1.0 - v)
		# a thread of light still ties it to the floor while it rises
		if u < 0.5:
			var j := 1.0
			while j < h * (1.0 - u * 2.0):
				p.dot(s.x, s.z * SY - 2.0 - h + j + 3.0, C[5], (1.0 - j / h) * (1.0 - u * 2.0) * (0.5 if back else 0.8))
				j += 1.5
		p.glow(x, y, 7.0 + L * 2.0, C[5], (0.2 if back else 0.34) * (1.0 if a < end else 1.0 - (a - end) / 0.15))


func update(dt: float) -> void:
	t += dt
	# the seed gathers: motes slide in over the floor to a point that brightens
	if t < SEED - 0.04 and R.chance(0.7):
		var a := R.range(0.0, TAU)
		var D := R.range(24.0, 48.0)
		var x := cos(a) * D
		var y := sin(a) * D * SY - R.range(1.0, 8.0)
		var T := R.range(0.16, 0.24)
		var l := Px.hypot(x, y + 3.0)
		if not l:
			l = 1.0
		var v := (l * 3.0) / (exp(3.0 * T) - 1.0)
		ps.spawn(P.STREAK, x, y, (-x / l) * v, ((-3.0 - y) / l) * v, T, C[6] if R.chance(0.5) else C[5])
	if not released and t >= SEED:
		released = true
		lights.add(0.0, -16.0, 76.0, C[5], 0.85, 0.55)
		lights.add(0.0, -6.0, 28.0, WHITE, 0.8, 0.12)
		for i in 10:
			ps.spawn(P.MOTE, R.range(-2.0, 2.0), -R.range(2.0, 10.0), R.range(-25.0, 25.0), -R.range(80.0, 170.0), R.range(0.3, 0.6), WHITE if R.chance(0.5) else C[6], R.range(0.6, 1.0))
		for i in 16:
			var a := R.range(PI * 1.05, PI * 1.95)
			var sp := R.range(40.0, 120.0)
			ps.spawn(P.STAR, 0.0, -3.0, cos(a) * sp, sin(a) * sp, R.range(0.4, 0.8), WHITE if R.chance(0.5) else C[6], R.range(0.6, 2.0))
	for s: Dictionary in sites:
		if not s.popped and t >= s.t0:
			s.popped = true
			# a splash of dew where each one breaks the floor
			for i in 3:
				ps.spawn(P.STAR, s.x + R.range(-3.0, 3.0), s.z * SY - 1.0, R.range(-10.0, 10.0), -R.range(15.0, 40.0), R.range(0.3, 0.6), WHITE if R.chance(0.5) else C[6], R.range(0.5, 1.2), 0.0, 4 if s.z < 0.0 else 0)
	# dew rising off the glowing floor behind the ring
	if t > SEED + 0.1 and t < 1.9 and R.chance(0.35):
		var fr := front(t)
		var a := R.range(0.0, TAU)
		var d := fr * sqrt(R.next())
		ps.spawn(P.EMBER, cos(a) * d, sin(a) * d * SY - 1.0, R.range(-5.0, 5.0), -R.range(10.0, 30.0), R.range(0.5, 1.0), C[5], 1.0, 0.0, 4 if sin(a) < 0.0 else 0)
	ps.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	wash(p)
	ring(p, true)
	sprouts(p, true)
	ps.draw(p, "back")


func draw(p: Px.Painter) -> void:
	ring(p, false)
	# the seed: a point of light pulsing on the floor, then a flare as it lets go
	if t < SEED:
		var k := t / SEED
		Px.sparkle(p, 0.0, -3.0, 2.0 + 4.0 * k * k, WHITE, C[6], 0.3 + 0.4 * k)
		p.glow(0.0, -3.0, 10.0 + 16.0 * k, C[4], 0.5 * k)
	elif t < SEED + 0.2:
		Px.flare(p, 0.0, -3.0, 22.0 * pow(1.0 - (t - SEED) / 0.2, 1.5), 1.0 - (t - SEED) / 0.2, C.slice(3))
	# as it lets go, a jet of light leaps out of the floor, lets go of it and dissolves upward
	var g := Px.seg(t, SEED, SEED + 0.5)
	if g > 0.0 and g < 1.0:
		var top := -4.0 - 46.0 * Px.Ease.outCubic(minf(1.0, g * 2.2)) - 10.0 * g
		var bot := -2.0 - 50.0 * Px.Ease.inQuad(Px.seg(g, 0.35, 1.0))
		var w := 1.0 + 2.4 * (1.0 - g)
		if bot - top > 2.0:
			var CC := C
			p.beam(0.0, bot, 0.0, top, w * 2.0, func(u, v): return WHITE if v < 0.45 else (CC[5] if u > 0.8 else CC[6]))
			p.glowLine(0.0, bot, 0.0, top, 12.0, C[5], 0.55 * (1.0 - g))
			Px.sparkle(p, 0.0, top, 4.0 * (1.0 - g) + 1.0, WHITE, C[6], 0.5 * (1.0 - g))
	sprouts(p, false)
	ps.draw(p, "front")
	lights.draw(p)
