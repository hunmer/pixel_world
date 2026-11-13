# The flare, the twinkling crosses and the glitter are adapted from Sprite Fusion's open-source sparkle
# (https://www.spritefusion.com/pixel-art-vfx/sparkle), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/explosions/firework-burst.js@dc7475a501431e83fef1792620f86f87b72a6dcd
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Firework burst",
	"desc": "A shell climbs, slows and bursts into a sphere of coloured trailing stars round a gold core; they droop, crackle into white pops and fade, leaving glitter.",
	"tags": ["firework", "celebration", "sparkle", "sky", "burst", "one-shot"],
	"size": [240, 248],
	"origin": [120, 100],
	"duration": 3.6,
	"loop": false,
	"fps": 30,
	"bg": "sky",
	"options": {
		"palette": ["#3d0a33", "#701560", "#b0228f", "#f53cd1", "#ff86e6", "#ffd2f6", "#ffffff"],
		"core": ["#4a2c08", "#86520c", "#c48412", "#f0b424", "#ffe066", "#fff6c4", "#ffffff"],
		"seed": 9,
	},
}

const RISE := 0.42
const Y0 := 72.0
const DRAG := 2.6
const G := 88.0
const TRAIL := 0.34
const TURN := 0.22


var C: Array
var K: Array
var R: Px.Rng
var ps: Px.Particles
var lights: Px.Lights
var stars := []
var pops := []
var t := 0.0
var burst := false


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 7)
	K = Px.fit(o.core, 7)
	R = Px.Rng.new(o.seed)
	ps = Px.Particles.new({"rng": R, "sparks": [K[6], K[5], K[4], K[3]]})
	lights = Px.Lights.new()


# a shell of stars thrown over a sphere: seen side-on, the ones flying at us or away look slower
# the outer stars burn gold for a beat, then turn to their color
func shell(n: int, speed: float, ramp: Array, life: Array, first: Array) -> void:
	for i in n:
		var z := R.range(-1.0, 1.0)
		var a := R.range(0.0, TAU)
		var s := sqrt(1.0 - z * z)
		var v := speed * R.range(0.93, 1.05)
		stars.append({"x": 0.0, "y": 0.0, "vx": cos(a) * s * v, "vy": sin(a) * s * v, "life": R.range(life[0], life[1]), "age": 0.0, "ramp": ramp, "first": first, "big": R.chance(0.2), "pts": [], "acc": R.next(), "seed": R.range(0.0, 100.0)})


func update(dt: float) -> void:
	t += dt
	# the shell climbs, slowing, shedding a fizz of gold sparks
	if t < RISE:
		var y := Y0 * (1.0 - Px.Ease.outCubic(t / RISE))
		if R.chance(50.0 * dt):
			ps.spawn(P.SPARK, R.range(-0.5, 0.5), y + 2.0, R.range(-25.0, 25.0), R.range(20.0, 70.0), R.range(0.15, 0.35))
		if R.chance(14.0 * dt):
			ps.spawn(P.VAPOUR, R.range(-1.0, 1.0), y + 3.0, R.range(-3.0, 3.0), R.range(5.0, 15.0), R.range(0.5, 0.8), Px.hex("#4a4458"), R.range(1.5, 2.5))
	if not burst and t >= RISE:
		burst = true
		lights.add(0.0, 0.0, 110.0, C[4], 0.6, 1.5)
		lights.add(0.0, 0.0, 30.0, WHITE, 0.5, 0.07)
		shell(66, 236.0, C, [1.35, 1.9], K)
		shell(26, 120.0, K, [1.0, 1.4], K)
		# the burst charge's smoke, drifting where the shell broke
		for i in 7:
			var a := R.range(0.0, TAU)
			var d := R.range(0.0, 8.0)
			ps.spawn(P.VAPOUR, cos(a) * d, sin(a) * d, cos(a) * R.range(10.0, 30.0), sin(a) * R.range(10.0, 30.0), R.range(2.2, 3.0), Px.hex("#4a4458"), R.range(6.0, 11.0))
		for i in 24:
			var a := R.range(0.0, TAU)
			var sp := R.range(40.0, 140.0)
			ps.spawn(P.SPARK, 0.0, 0.0, cos(a) * sp, sin(a) * sp, R.range(0.15, 0.35))
	var i := stars.size() - 1
	while i >= 0:
		var s: Dictionary = stars[i]
		i -= 1
		s.age += dt
		var k: float = s.age / s.life
		if k >= 1.0:
			# the star crackles out in a few white pops
			for j in 2 + (1 if s.big else 0):
				pops.append({"x": s.x + R.range(-3.0, 3.0), "y": s.y + R.range(-3.0, 3.0), "t0": t + R.range(0.0, 0.18), "life": R.range(0.06, 0.12), "c": WHITE if R.chance(0.6) else s.ramp[5]})
			stars.remove_at(i + 1)
			continue
		s.vx -= s.vx * DRAG * dt
		s.vy -= s.vy * DRAG * dt - G * dt
		s.x += s.vx * dt
		s.y += s.vy * dt
		s.pts.append(s.x)
		s.pts.append(s.y)
		s.pts.append(t)
		while s.pts.size() > 3 and t - s.pts[2] > TRAIL:
			s.pts.pop_front()
			s.pts.pop_front()
			s.pts.pop_front()
		# glitter shed along the way: specks that hang, twinkle and fall
		s.acc += dt * (4.0 if k < 0.25 else 11.0)
		while s.acc > 1.0:
			ps.spawn(P.STAR, s.x, s.y, s.vx * 0.15 + R.range(-6.0, 6.0), s.vy * 0.15 + R.range(0.0, 10.0), R.range(0.35, 0.8), K[5] if R.chance(0.5) else WHITE, R.range(1.0, 1.6) if R.chance(0.15) else 0.5)
			s.acc -= 1.0
	var j := pops.size() - 1
	while j >= 0:
		if t > pops[j].t0 + pops[j].life:
			pops.remove_at(j)
		j -= 1
	ps.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	ps.draw(p, "back")


func draw(p: Px.Painter) -> void:
	if t < RISE:
		# the shell: a hot dot with a short tail
		var u := t / RISE
		var y := Y0 * (1.0 - Px.Ease.outCubic(u))
		p.line(0.0, y, 0.0, y + 3.0 + 6.0 * (1.0 - u), func(q: float): return K[5] if q < 0.3 else K[3])
		p.px(0.0, y, WHITE)
		p.glow(0.0, y, 7.0, K[4], 0.5)
	for s in stars:
		var k: float = s.age / s.life
		var P2: Array = s.pts
		var n := floori(P2.size() / 3.0)
		# the trail: a 1 px line from the head back along where it has been, cooling and dithering out; the part
		# laid while the star burned gold stays gold
		var j := n - 1
		while j > 0:
			var u: float = (t - P2[j * 3 + 2]) / TRAIL
			if u >= 1.0:
				break
			var ramp: Array = s.first if s.age - (t - P2[j * 3 + 2]) < TURN else s.ramp
			var c: int = ramp[5] if u < 0.3 else (ramp[4] if u < 0.6 else ramp[3])
			p.line(P2[j * 3], P2[j * 3 + 1], P2[j * 3 - 3], P2[j * 3 - 2], c, pow(1.0 - u, 0.8) * (1.3 - k * 0.6))
			j -= 1
		# the head: white-hot, then its color; late on it flickers before it crackles out
		if k > 0.72 and sin(t * 60.0 + s.seed) < -0.2:
			continue
		# white only on the burst frame; the glow comes in as the stars spread, so the heart never blooms into a blob
		var ramp: Array = s.first if s.age < TURN else s.ramp
		var head: int = WHITE if s.age < 0.04 else (ramp[5 if s.age < TURN else 6] if k < 0.55 else ramp[5])
		p.px(s.x, s.y, head)
		if s.big and k < 0.6 and s.age > 0.06:
			for dd in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
				p.px(s.x + dd[0], s.y + dd[1], ramp[5])
		p.glow(s.x, s.y, 7.0 if s.big else 5.0, ramp[4], (0.7 if s.big else 0.5) * (1.0 - k * 0.6) * minf(1.0, s.age / 0.2))
	for q in pops:
		var u: float = (t - q.t0) / q.life
		if u < 0.0 or u > 1.0:
			continue
		Px.sparkle(p, q.x, q.y, 2.6 * sin(PI * u), q.c, Px.mix(q.c, C[3], 0.5), 0.5)
	# the burst: a flare and a white heart, the sky lit up behind it
	var b := t - RISE
	if b >= 0.0 and b < 0.28:
		var u := b / 0.28
		var L := 32.0 * pow(1.0 - u, 1.3)
		flareRays(p, 0.0, 0.0, L, u * 0.6, C, K)
		if b < 0.07:
			p.circle(0.0, 0.0, 2.6 - b * 20.0, WHITE)
	ps.draw(p, "front")
	lights.draw(p)


# an 8-ray flare: long rays on the axes with a white core and tinted ends, short gold diagonals, turning slowly
static func flareRays(p: Px.Painter, x: float, y: float, L: float, ang: float, C: Array, K: Array) -> void:
	if L < 1.0:
		return
	for i in 8:
		var diag := i % 2 == 1
		var an := ang + (i * TAU) / 8.0
		var len := L * 0.42 if diag else L
		var ca := cos(an)
		var sa := sin(an)
		var d := 0.0
		while d <= len:
			var u := d / len
			p.dot(x + ca * d, y + sa * d, (K[5] if u < 0.5 else K[4]) if diag else (WHITE if u < 0.3 else (C[5] if u < 0.65 else C[4])), 1.0 if u < 0.7 else 1.0 - (u - 0.7) / 0.35)
			d += 0.5
	p.glow(x, y, 4.0 + L * 1.2, C[4], 0.3)
	p.glow(x, y, 2.0 + L * 0.3, WHITE, 0.25)
