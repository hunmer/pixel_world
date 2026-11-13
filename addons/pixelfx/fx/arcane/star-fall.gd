# The slanted streaks landing with a ring and a kick of bits follow Sprite Fusion's open-source rain
# (https://www.spritefusion.com/pixel-art-vfx/rain), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/arcane/star-fall.js@cb62831324b95e0ffcbdd2aa718fabe8c5bf0f0e
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const P := Px.P
const WHITE := Px.WHITE

const N := 11
const SPREAD := 46.0
const H := 124.0
const SLANT := 0.38
const TRAIL := 0.17

static var meta := {
	"name": "Star fall",
	"desc": "Stars streak down on long trails across an area, each landing with a white flash, a ring across the floor and a kick of sparks.",
	"tags": ["arcane", "star", "meteor", "rain", "aoe", "magic", "ground", "one-shot"],
	"size": [232, 172],
	"origin": [124, 150],
	"duration": 2.5,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": Px.PAL.arcane, "seed": 13},
}


var C: Array
var R: Px.Rng
var ps: Px.Particles
var lights: Px.Lights
var stars: Array
var hits := []
var t := 0.0


static func at(s: Dictionary, tt: float) -> Array:
	var q := Px.clamp((tt - s.t0) / s.T)
	var e := q * (0.35 + 0.65 * q)
	return [s.sx + (s.x - s.sx) * e, s.sy + (s.y - s.sy) * e, q]


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	R = Px.Rng.new(o.seed)
	ps = Px.Particles.new({"rng": R, "ground": func(): return 0.0, "sparks": [WHITE, C[6], C[5], C[4]]})
	lights = Px.Lights.new()
	# where they land: spread over the area in a shuffled order, a little in front of or behind the line
	var xs := Px.arr(N, func(i): return -SPREAD + ((i + R.range(0.2, 0.8)) * 2.0 * SPREAD) / N)
	var i := N - 1
	while i > 0:
		var j := R.int_(0, i)
		var tmp: Variant = xs[i]
		xs[i] = xs[j]
		xs[j] = tmp
		i -= 1
	stars = []
	for k in xs.size():
		var x: float = xs[k]
		var y := R.range(-3.0, 2.0)
		var h := H * R.range(0.85, 1.0)
		stars.append({"x": x, "y": y, "sx": x - h * SLANT, "sy": y - h, "t0": 0.04 + k * 0.105 + R.range(0.0, 0.05), "T": R.range(0.3, 0.4), "landed": false, "big": R.chance(0.35), "ph": R.range(0.0, TAU)})


func star(p: Px.Painter, s: Dictionary) -> float:
	var xyq := at(s, t)
	var x: float = xyq[0]
	var y: float = xyq[1]
	var q: float = xyq[2]
	# the trail: a long tapered streak back up its path, white at the head, thinning into violet
	var n := 20
	var k := n
	while k >= 1:
		var a := at(s, t - (k * TRAIL) / n)
		var b := at(s, t - ((k - 1) * TRAIL) / n)
		var ax: float = a[0]
		var ay: float = a[1]
		var bx: float = b[0]
		var by: float = b[1]
		var u := float(k) / n
		if t - (k * TRAIL) / n < s.t0:
			k -= 1
			continue
		var c: int = WHITE if u < 0.15 else (C[6] if u < 0.4 else (C[5] if u < 0.7 else C[4]))
		# a second line beside the first near the head gives it body; the tail thins to a dithered thread
		if u < (0.55 if s.big else 0.35):
			p.line(ax + 1.0, ay, bx + 1.0, by, C[6] if u < 0.2 else C[5], 1.1 - u * 1.4)
		p.line(ax, ay, bx, by, c, 1.3 - u)
		if k % 3 == 0:
			p.glow(ax, ay, 7.0 * (1.0 - u) + 2.0, C[5], 0.3 * (1.0 - u))
		k -= 1
	# the head: a twinkling four-point star
	if s.big:
		Px.flare(p, x, y, 7.0 + 1.5 * sin(t * 40.0 + s.ph), 0.8, C)
	else:
		Px.sparkle(p, x, y, 3.5 + sin(t * 40.0 + s.ph), C[6], C[5], 0.6)
	p.circle(x, y, 1.6 if s.big else 1.1, WHITE)
	p.glow(x, y, 18.0 if s.big else 13.0, C[5], 0.6)
	p.glow(x, y, 5.0, WHITE, 0.35)
	return q


func hit(p: Px.Painter, h: Dictionary, far: bool) -> void:
	var k: float = (t - h.t) / 0.45
	if k < 0.0 or k >= 1.0:
		return
	Px.band(p, h.x, h.y, 3.0 + (22.0 if h.big else 16.0) * Px.Ease.outCubic(k), 0.26, maxf(1.0, 2.5 * (1.0 - k)), 1.15 - k, [C[3], C[5], C[6], WHITE], func(g: float) -> bool: return (sin(g) < 0.0) == far, k < 0.2)


func update(dt: float) -> void:
	t += dt
	for s: Dictionary in stars:
		if t < s.t0 or s.landed:
			continue
		var xyq := at(s, t)
		var x: float = xyq[0]
		var y: float = xyq[1]
		var q: float = xyq[2]
		if R.chance(0.55):
			ps.spawn(P.STAR, x + R.range(-1.5, 1.5), y + R.range(-1.5, 1.5), R.range(-12.0, 12.0), R.range(-8.0, 4.0), R.range(0.35, 0.7), R.pick([WHITE, C[6], C[5]]), R.range(0.4, 0.9) if R.chance(0.7) else R.range(1.2, 1.8))
		if q >= 1.0:
			s.landed = true
			hits.append({"x": s.x, "y": s.y, "t": t, "big": s.big})
			lights.add(s.x, s.y - 12.0, 46.0 if s.big else 38.0, C[5], 0.9, 0.32)
			lights.add(s.x, s.y - 3.0, 16.0, WHITE, 0.8, 0.08)
			for i in (14 if s.big else 9):
				var a := -PI / 2.0 + R.range(-1.35, 1.35)
				var sp := R.range(50.0, 150.0)
				ps.spawn(P.SPARK, s.x, minf(-1.0, s.y - 1.0), cos(a) * sp, sin(a) * sp, R.range(0.2, 0.5))
			for i in 4:
				ps.spawn(P.STAR, s.x + R.range(-4.0, 4.0), s.y - R.range(2.0, 8.0), R.range(-15.0, 15.0), -R.range(10.0, 35.0), R.range(0.4, 0.8), R.pick([WHITE, C[6]]), R.range(0.8, 2.0))
	ps.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	# the area lit beneath while they fall
	var k := Px.clamp(t / 0.3) * (1.0 - Px.clamp((t - 1.7) / 0.7))
	if k > 0.0:
		for x in [-36.0, 0.0, 36.0]:
			p.glow(x, -1.0, 40.0, C[4], 0.14 * k)
	for h: Dictionary in hits:
		hit(p, h, true)
	# a glowing mark where each landed, cooling away
	for h: Dictionary in hits:
		var k2: float = 1.0 - (t - h.t) / 0.7
		if k2 <= 0.0:
			continue
		p.dot(h.x, h.y, WHITE if k2 > 0.6 else C[6], k2 * 1.5)
		for dx in [-1.0, 1.0]:
			p.dot(h.x + dx, h.y, C[5], k2 * 1.2)
		p.glow(h.x, h.y - 1.0, 10.0, C[5], 0.35 * k2)
	ps.draw(p, "back")


func draw(p: Px.Painter) -> void:
	for s: Dictionary in stars:
		if t >= s.t0 and not s.landed:
			star(p, s)
	for h: Dictionary in hits:
		hit(p, h, false)
		var k: float = (t - h.t) / 0.22
		if k < 0.0 or k >= 1.0:
			continue
		if k < 0.35:
			p.circle(h.x, h.y - 2.0, 5.0 * (1.0 - k / 0.35) + 1.0, WHITE)
		Px.flare(p, h.x, h.y - 2.0, (16.0 if h.big else 12.0) * pow(1.0 - k, 1.5) + 2.0, 1.0 - k, C)
	ps.draw(p, "front")
	lights.draw(p)
