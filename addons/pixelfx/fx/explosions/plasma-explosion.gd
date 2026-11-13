# The release (flash, rings, flare, light) and the arcs are adapted from Sprite Fusion's open-source energy
# (https://www.spritefusion.com/pixel-art-vfx/energy), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/explosions/plasma-explosion.js@5ab1c800b2a6785f63d41e6e5a1c8bb7d075dfef
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Plasma explosion",
	"desc": "A blue-violet energy blast with no smoke: a white flash, a ball of plasma swelling into a thinning shell, shock rings in and out of depth, lightning arcs crackling off it.",
	"tags": ["explosion", "plasma", "energy", "electric", "magic", "sci-fi", "one-shot"],
	"size": [224, 200],
	"origin": [112, 100],
	"duration": 1.7,
	"loop": false,
	"fps": 30,
	"bg": "dark",
	"options": {
		"palette": ["#0a0828", "#1a1c6e", "#2c3cc0", "#4a7cf0", "#7cc0ff", "#c8ecff", "#ffffff"],
		"accent": ["#1c0a30", "#4a1a8c", "#8a3ce0", "#c48cff", "#f0d8ff"],
		"seed": 7,
	},
}

const BALL := 0.55


var o: Dictionary
var C: Array
var V: Array
var R: Px.Rng
var ps: Px.Particles
var lights: Px.Lights
var t := 0.0


func create(o_: Dictionary) -> void:
	o = o_
	C = Px.fit(o.palette, 7)
	V = Px.fit(o.accent, 5)
	R = Px.Rng.new(o.seed)
	ps = Px.Particles.new({"rng": R, "sparks": [C[6], C[5], C[4], V[3]]})
	lights = Px.Lights.new()
	lights.add(0.0, 0.0, 96.0, C[4], 1.0, 0.6)
	lights.add(0.0, 0.0, 40.0, WHITE, 0.9, 0.1)
	lights.add(0.0, 0.0, 70.0, V[2], 0.5, 1.1)
	for i in 46:
		var a := R.range(0.0, TAU)
		var sp := R.range(140.0, 360.0)
		ps.spawn(P.MOTE, cos(a) * 4.0, sin(a) * 4.0, cos(a) * sp, sin(a) * sp, R.range(0.2, 0.42), R.pick([C[6], C[5], C[4], V[3]]), R.range(0.7, 1.1))
	for i in 26:
		var a := R.range(0.0, TAU)
		var sp := R.range(40.0, 140.0)
		ps.spawn(P.FLAKE, cos(a) * 10.0, sin(a) * 10.0, cos(a) * sp, sin(a) * sp, R.range(0.8, 1.5), R.pick([C[5], V[3], V[4]]), R.range(0.6, 1.6))
	t = 0.0


func update(dt: float) -> void:
	t += dt
	# the shell sheds sparkles and motes as it thins
	if t > 0.12 and t < 0.9 and R.chance(30.0 * dt):
		var a := R.range(0.0, TAU)
		var r := shell(t)
		ps.spawn(P.STAR, cos(a) * r, sin(a) * r, cos(a) * R.range(10.0, 40.0), sin(a) * R.range(10.0, 40.0), R.range(0.3, 0.6), C[5] if R.chance(0.5) else V[4], R.range(0.5, 1.8))
	ps.update(dt)
	Lib.cull(ps, -meta.origin[0] + 3, -meta.origin[1] + 3, meta.size[0] - meta.origin[0] - 3, meta.size[1] - meta.origin[1] - 3)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	# the tilted ring's far half, behind the ball
	tilted(p, t, C, V, true)


func draw(p: Px.Painter) -> void:
	# the ball: a white heart, cyan and blue bands, a violet rim boiling at the edge; it swells, then hollows out
	if t < BALL:
		var u := t / BALL
		var r := shell(t)
		var hollow := Px.smooth(0.35, 1.0, u)
		var boil := floorf(t * 20.0)
		var tt := t
		p.shade(-r - 3.0, -r - 3.0, r + 3.0, r + 3.0, func(x: float, y: float, out):
			var d := Px.hypot(x, y)
			var a := atan2(y, x)
			var edge := r * (1.0 + 0.1 * Px.noise(a * 3.0 + boil * 0.7, 3))
			if d > edge:
				return null
			var v := d / edge
			if v < hollow * 0.92:
				return null
			# turbulent bands swirling round the heart, and bright filaments twisting through them
			var n := Px.noise(a * 4.0 + d * 0.25 + boil * 0.5, 5)
			var w := v + n * 0.14
			var fil := absf(sin(a * 5.0 + d * 0.32 - tt * 14.0 + n * 2.5)) < 0.1
			out.k = 0.25 * (1.0 - u)
			if v > 0.9:
				return V[2]
			if fil and v > 0.3:
				return WHITE if u < 0.5 else C[5]
			return WHITE if w < 0.32 - u * 0.25 else (C[5] if w < 0.52 else (C[4] if w < 0.72 else ((C[3] if u < 0.5 else V[3]) if w < 0.86 else V[2]))))
		p.glow(0.0, 0.0, r * 1.6 + 6.0, C[4], 0.6 * (1.0 - u))
	if t < 0.07:
		p.circle(0.0, 0.0, 9.0 - t * 60.0, WHITE)
	if t < 0.25:
		Px.flare(p, 0.0, 0.0, 52.0 * pow(1.0 - t / 0.25, 1.3), 1.0 - t / 0.25, C)
	# shock rings: a fast bright one, a slower violet one
	var u1 := t / 0.42
	if u1 < 1.0:
		p.ring(0.0, 0.0, 8.0 + 84.0 * Px.Ease.outCubic(u1), maxf(1.0, 3.0 * (1.0 - u1)), WHITE if u1 < 0.25 else C[5], 1.15 - u1)
		p.glowRing(0.0, 0.0, 8.0 + 84.0 * Px.Ease.outCubic(u1), 5.0, C[4], 0.35 * (1.0 - u1))
	var u2 := (t - 0.06) / 0.6
	if u2 > 0.0 and u2 < 1.0:
		p.ring(0.0, 0.0, 6.0 + 60.0 * Px.Ease.outCubic(u2), maxf(1.0, 2.0 * (1.0 - u2)), V[3], 1.1 - u2)
	# arcs: lightning crackling out of the heart, re-struck every few frames, shorter as the charge runs out
	var left := 1.0 - Px.smooth(0.15, 0.85, t)
	var strike := floorf(t * 18.0)
	if left > 0.0:
		var r := Px.rng(o.seed, strike, 17)
		var n := 2 + Px.roundi(4.0 * left)
		for i in n:
			var a := r.range(0.0, TAU)
			var L := r.range(26.0, 58.0) * (0.45 + 0.55 * left)
			var path := Px.bolt(r, 0.0, 0.0, cos(a) * L, sin(a) * L, {"jag": 0.28, "depth": 4})
			arc(p, path, C, V, 0.8 * left)
			if r.chance(0.5):
				for f in Px.forks(r, path, {"count": 1, "len": 14.0, "jag": 0.35}):
					arc(p, f, C, V, 0.5 * left)
		# and little arcs crawling over the shell
		var rs := shell(t)
		for i in 3:
			var a := r.range(0.0, TAU)
			var b := a + r.range(0.3, 0.6)
			arc(p, Px.bolt(r, cos(a) * rs, sin(a) * rs, cos(b) * rs, sin(b) * rs, {"jag": 0.4, "depth": 3}), C, V, 0.6 * left)
	tilted(p, t, C, V, false)
	ps.draw(p)
	lights.draw(p)


# the ball's radius: punched out fast, then easing
static func shell(tt: float) -> float:
	return 5.0 + 30.0 * Px.Ease.outCubic(Px.clamp(tt / BALL))


# a ring on a tilted plane racing out round the blast: far half behind, near half in front
static func tilted(p: Px.Painter, tt: float, C: Array, V: Array, back: bool) -> void:
	var u := (tt - 0.03) / 0.5
	if u <= 0.0 or u >= 1.0:
		return
	Px.band(p, 0.0, 4.0, 12.0 + 86.0 * Px.Ease.outCubic(u), 0.28, maxf(1.0, 4.0 * (1.0 - u)), 1.15 - u, [V[1], V[2], C[4], C[5]], func(g): return (sin(g) < 0.0) == back, u < 0.15)


# one arc: a soft glow along it, a cyan halo line, a white core
static func arc(p: Px.Painter, path: Array, C: Array, V: Array, k: float) -> void:
	if k <= 0.05:
		return
	for i in range(1, path.size()):
		var ax: float = path[i - 1][0]
		var ay: float = path[i - 1][1]
		var bx: float = path[i][0]
		var by: float = path[i][1]
		p.glowLine(ax, ay, bx, by, 5.0, V[2], 0.18 * k)
		p.line(ax + 1.0, ay, bx + 1.0, by, C[4], k * 0.8)
		p.line(ax, ay, bx, by, WHITE if i < path.size() * 0.6 else C[5], minf(1.0, k * 1.4))
