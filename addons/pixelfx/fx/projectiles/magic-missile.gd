# The gathering motes, star particles and burst flare follow Sprite Fusion's open-source energy bolt
# (https://www.spritefusion.com/pixel-art-vfx/energy), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/projectiles/magic-missile.js@f82a9e8405efda2e78f2288d3cb6a5480dca3256
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Magic missile",
	"desc": "Motes gather into an arcane orb at a hand `height` px above the floor (the origin); it weaves to its target trailing a twisting ribbon and bursts into a star of light.",
	"tags": ["projectile", "magic", "arcane", "missile", "spell", "directional", "one-shot"],
	"size": [208, 112],
	"origin": [24, 104],
	"duration": 1.9,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": ["#140a26", "#2b1252", "#481c88", "#6b2cc0", "#9a48ec", "#c684ff", "#ecc8ff", "#ffffff"], "height": 26, "reach": 112, "seed": 6},
}

const CHARGE := 0.2
const FLY := 0.62

var C: Array
var H: float
var X1: float
var R: Px.Rng
var ps: Px.Particles
var lights: Px.Lights
var t := 0.0
var burst := false
var trail: Array = []


# the path: out of the hand, weaving up and down twice, homing in on the target at the same height
func pos(u: float) -> Array:
	return [X1 * Px.Ease.inOutSine(u) + sin(u * PI) * 6.0, -H + sin(u * TAU * 1.5) * 9.0 * sin(u * PI)]


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	H = o.height
	X1 = o.reach
	R = Px.Rng.new(o.seed)
	ps = Px.Particles.new({"rng": R, "ground": func(): return 0.0, "sparks": [WHITE, C[6], C[5], C[4]]})
	lights = Px.Lights.new()
	t = 0.0
	burst = false
	trail = []


func update(dt: float) -> void:
	t += dt
	if t < CHARGE:
		# motes spiral in to the hand
		if R.chance(0.8):
			var a := R.range(0.0, TAU)
			var d := R.range(12.0, 26.0)
			var sp := d / 0.14
			ps.spawn(P.MOTE, cos(a) * d, -H + sin(a) * d, -cos(a) * sp - sin(a) * sp * 0.5, -sin(a) * sp + cos(a) * sp * 0.5, 0.14, R.pick([C[5], C[6], WHITE]), 0.8)
	elif t < CHARGE + FLY:
		var u := (t - CHARGE) / FLY
		var xy := pos(u)
		var x: float = xy[0]
		var y: float = xy[1]
		trail.append({"x": x, "y": y, "t": t})
		if R.chance(0.6):
			ps.spawn(P.MOTE, x, y, R.range(-50.0, 50.0), R.range(-50.0, 50.0), R.range(0.2, 0.4), R.pick([C[4], C[5], C[6]]), 0.7)
		if R.chance(0.25):
			ps.spawn(P.STAR, x + R.range(-3.0, 3.0), y + R.range(-3.0, 3.0), R.range(-10.0, 10.0), R.range(-10.0, 10.0), R.range(0.25, 0.5), C[6], R.range(0.6, 1.6))
	elif not burst:
		burst = true
		var y := -H
		lights.add(X1, y, 52.0, C[4], 0.95, 0.55)
		lights.add(X1, y, 22.0, WHITE, 0.8, 0.12)
		for i in 26:
			var a := R.range(0.0, TAU)
			var sp := R.range(60.0, 150.0) * (1.0 - 0.65 * maxf(0.0, sin(a)))
			ps.spawn(P.MOTE if i % 3 else P.STAR, X1, y, cos(a) * sp, sin(a) * sp, R.range(0.25, 0.45), R.pick([C[5], C[6], WHITE]), R.range(0.8, 1.8))
		for i in 18:
			var a := R.range(0.0, TAU)
			var sp := R.range(110.0, 240.0) * (1.0 - 0.5 * maxf(0.0, sin(a)))
			ps.spawn(P.SPARK, X1, y, cos(a) * sp, sin(a) * sp - 30.0, R.range(0.12, 0.3))
		for i in 14:
			var a := R.range(0.0, TAU)
			var d := R.range(4.0, 22.0)
			ps.spawn(P.STAR, X1 + cos(a) * d, y + sin(a) * d * 0.8, 0.0, -R.range(2.0, 8.0), R.range(0.5, 1.1), R.pick([C[6], WHITE, C[5]]), R.range(0.8, 2.6), R.range(0.05, 0.45))
	ps.update(dt)
	lights.update(dt)


func draw(p: Px.Painter) -> void:
	# the ribbon: a strip that twists as it trails the orb, its bright face and its dark back taking turns,
	# fading from the tail
	var now := t
	var keep := trail.filter(func(q): return now - q.t < 0.32)
	for i in range(1, keep.size()):
		var a: Dictionary = keep[i - 1]
		var b: Dictionary = keep[i]
		var dx: float = b.x - a.x
		var dy: float = b.y - a.y
		var l := Px.hypot(dx, dy)
		if not l:
			l = 1.0
		var nx := -dy / l
		var ny := dx / l
		var f := 0.0
		while f < 1.0:
			var tt: float = a.t + (b.t - a.t) * f
			var k := 1.0 - (now - tt) / 0.32
			var tw := sin(tt * 26.0)
			var w := 3.2 * k * absf(tw) + 0.4
			var face := tw > 0.0
			var x: float = a.x + dx * f
			var y: float = a.y + dy * f
			var s := -w
			while s <= w:
				var edge := absf(s) > w - 0.8
				var c: int = ((C[6] if edge else (C[5] if k > 0.6 else C[4])) if face else (C[4] if edge else C[2]))
				p.dot(x + nx * s, y + ny * s, c, 1.0 if k > 0.35 else k / 0.35)
				s += 0.5
			f += 0.5 / l
		if i % 3 == 0:
			p.glow(b.x, b.y, 6.0, C[4], 0.25 * (1.0 - (now - b.t) / 0.32))
	ps.draw(p)
	# the orb: gathering at the hand, then flying, its heart white, a ring of light turning round it
	if t < CHARGE + FLY:
		var k := t / CHARGE if t < CHARGE else 1.0
		var xy := [0.0, -H] if t < CHARGE else pos((t - CHARGE) / FLY)
		var x: float = xy[0]
		var y: float = xy[1]
		var r := 1.0 + 3.0 * Px.Ease.outBack(k)
		p.circle(x, y, r + 1.4, C[3])
		p.circle(x, y, r + 0.4, C[5])
		p.circle(x - 0.4, y - 0.4, r * 0.55, WHITE)
		for i in 3:
			var a := t * 14.0 + (i * TAU) / 3.0
			p.px(x + cos(a) * (r + 3.0), y + sin(a) * (r + 3.0) * 0.6, C[6] if i else WHITE)
		p.glow(x, y, 20.0, C[4], 0.65 * k)
		p.glow(x, y, 7.0, C[6], 0.5 * k)
	# the burst: a star flare and a ring that open out and fade
	var q := t - CHARGE - FLY
	if q >= 0.0 and q < 0.5:
		var e := q / 0.5
		if e < 0.5:
			Px.flare(p, X1, -H, 26.0 * pow(1.0 - e * 2.0, 1.2) + 2.0, 1.0 - e * 2.0, C)
		if e < 0.12:
			p.circle(X1, -H, 6.0 * (1.0 - e / 0.12) + 1.0, WHITE)
		p.ring(X1, -H, 4.0 + 20.0 * Px.Ease.outCubic(e), maxf(1.0, 2.5 * (1.0 - e)), C[6] if e < 0.3 else C[5], minf(1.0, (1.0 - e) * 1.5))
		if e < 0.4:
			Px.sparkle(p, X1, -H, 7.0 * (1.0 - e / 0.4), C[6], C[4], 0.6 * (1.0 - e / 0.4))
	lights.draw(p)
