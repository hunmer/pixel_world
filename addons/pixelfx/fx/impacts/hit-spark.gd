# The two-tone spark spray and the light pop are adapted from Sprite Fusion's open-source impact
# (https://www.spritefusion.com/pixel-art-vfx/impact), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/impacts/hit-spark.js@970f6a183cf1f0c4c46415b634f283ffe71469db
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const P := Px.P
const WHITE := Px.WHITE

static var meta := {
	"name": "Hit spark",
	"desc": "The everyday hit: a sharp, lopsided cross flare with one long ray along the blow round a white diamond core, then a cone of sparks and hot chips that fall and bounce.",
	"tags": ["impact", "hit", "spark", "combat", "directional", "one-shot"],
	"size": [136, 80],
	"origin": [44, 64],
	"duration": 0.5,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": ["#4a1712", "#c9281f", "#f2561d", "#ff8a2a", "#ffe26b", "#fff3a6", "#ffffff"], "height": 20, "aim": 0.1, "seed": 4},
}


# one ray of the cross: fat at the root, a hair at the tip, white cooling outward; from..to draws a stretch of it
static func ray(p: Px.Painter, x: float, y: float, a: float, L: float, w: float, C: Array, from: float = 0.0) -> void:
	var c := cos(a)
	var s := sin(a)
	var d := from * L
	while d <= L:
		var u := d / L
		var hw := w * pow(1.0 - u, 1.6)
		var col: int = WHITE if u < 0.3 else (C[5] if u < 0.62 else (C[4] if u < 0.88 else C[3]))
		p.px(x + c * d, y + s * d, col)
		if hw > 0.45:
			var o := 0.5
			while o <= hw:
				for e in [-o, o]:
					p.px(x + c * d - s * e, y + s * d + c * e, C[5] if (u < 0.3 and o < 1.0) else C[4])
				o += 0.5
		d += 0.5


# the core: a crisp white diamond with a pale rim
static func diamond(p: Px.Painter, x: float, y: float, r: int, C: Array) -> void:
	for dy in range(-r - 1, r + 2):
		for dx in range(-r - 1, r + 2):
			var m := absi(dx) + absi(dy)
			if m <= r:
				p.px(x + dx, y + dy, WHITE)
			elif m == r + 1:
				p.px(x + dx, y + dy, C[3])


var C: Array
var R: Px.Rng
var X := 0.0
var Y: float
var A: float
var ps: Px.Particles
var lights: Px.Lights
var rays: Array
var t := 0.0


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 7)
	R = Px.Rng.new(o.seed)
	Y = -o.height
	A = o.aim
	var floor_ := func(): return 0.0
	ps = Px.Particles.new({"rng": R, "ground": floor_, "sparks": [C[6], C[5], C[4], C[2]]})
	lights = Px.Lights.new()
	# the cross: a long thin ray along the blow, a stub behind, two unequal arms across, and a glint between
	var tilt := R.range(-0.08, 0.08)
	rays = [
		{"a": A + tilt, "L": R.range(33.0, 37.0), "w": 2.2},
		{"a": A + PI + tilt, "L": R.range(8.0, 10.0), "w": 2.2},
		{"a": A - PI / 2.0 + tilt, "L": R.range(15.0, 18.0), "w": 2.6},
		{"a": A + PI / 2.0 + tilt, "L": R.range(10.0, 12.0), "w": 2.3},
		{"a": A - PI / 4.0 + tilt, "L": R.range(5.0, 7.0), "w": 1.0},
	]

	lights.add(X, Y, 38.0, C[4], 0.35, 0.18)
	lights.add(X + cos(A) * 10.0, Y + sin(A) * 10.0, 22.0, C[5], 0.45, 0.1)
	lights.add(X, -2.0, 26.0, C[3], 0.22, 0.22)
	# a cone of sparks sprayed on along the blow: they fall, bounce off the floor and die
	for i in 9:
		var a := A + R.range(-0.6, 0.6) - 0.15
		var v := R.range(170.0, 360.0)
		ps.spawn(P.SPARK, X + 1.0, Y, cos(a) * v, sin(a) * v - 40.0, R.range(0.25, 0.45), WHITE, 1.0, R.range(0.01, 0.03) if i > 6 else 0.0)
	# hot pixel chips knocked off, tumbling down to tick off the floor
	for i in 6:
		var a := A + R.range(-1.1, 0.5) - 0.3
		var v := R.range(70.0, 170.0)
		ps.spawn(P.GRIT, X + 1.0, Y, cos(a) * v, sin(a) * v - R.range(30.0, 80.0), R.range(0.35, 0.45), R.pick([C[5], C[4], C[4], C[3]]), 1.0)


func update(dt: float) -> void:
	t += dt
	ps.update(dt)
	lights.update(dt)


func draw(p: Px.Painter) -> void:
	ps.draw(p)
	if t < 0.025:
		# the flash: the whole cross round the diamond
		for r: Dictionary in rays:
			ray(p, X, Y, r.a, r.L, r.w, C)
		diamond(p, X, Y, 4, C)
	elif t < 0.058:
		# reaching further and thinning, the diamond still crisp
		for r: Dictionary in rays:
			ray(p, X, Y, r.a, r.L * 1.2, r.w * 0.55, C, 0.12)
		diamond(p, X, Y, 3, C)
	elif t < 0.092:
		# only the long ray lingers, its root burning away
		var r: Dictionary = rays[0]
		ray(p, X, Y, r.a, r.L * 1.3, 0.6, [C[0], C[1], C[2], C[3], C[3], C[4]], 0.4)
	var pop := exp(-t / 0.045)
	if pop > 0.02:
		p.glow(X, Y, 22.0, C[4], 0.3 * pop)
		p.glow(X, Y, 7.0, WHITE, 0.15 * pop)
		p.glowLine(X, Y, X + cos(A) * 26.0, Y + sin(A) * 26.0, 4.0, C[5], 0.25 * pop)
	lights.draw(p)
