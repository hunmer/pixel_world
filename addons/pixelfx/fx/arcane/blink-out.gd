# The blink (a crackling outline as it gathers, a white flash, the silhouette squeezed into a line, a ring on the
# floor, a fading afterimage) is adapted from Sprite Fusion's open-source blink
# (https://www.spritefusion.com/pixel-art-vfx/movement), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/arcane/blink-out.js@d905aa3977e9461ec92b829d19a005dbdae43b71
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE

const OUT := 0.32
const SQUEEZE := 0.12
const COLLAPSE := 0.08
const POP := OUT + SQUEEZE + COLLAPSE

static var meta := {
	"name": "Blink out",
	"desc": "The caster crackles with gathering light, flashes white, squeezes into a line of light that collapses and pops away in sparks.",
	"tags": ["arcane", "blink", "teleport", "vanish", "movement", "magic", "one-shot"],
	"size": [136, 96],
	"origin": [68, 80],
	"duration": 1.6,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {"palette": Px.PAL.arcane, "seed": 11},
}

static var IN := {"turn": 1, "crouch": 4, "fx": -2, "fy": -25, "bx": 2, "by": -25, "armsFront": true, "ffx": 0, "fbx": 2}
static var act := {
	"onBody": true,
	"poses": [
		[-0.36, Px.READY],
		[-0.1, IN],
		[0.2, Px.merge(IN, {"crouch": 5})],
		[0.32, Px.merge(IN, {"crouch": 0}), "snap"],
		[1.6, Px.merge(IN, {"crouch": 0})],
	],
}

## The stand-in character is hidden from the flash on: the effect draws it from then.
static func actorAlpha(t: float, _o: Dictionary) -> float:
	return 1.0 if t < OUT else 0.0


var C: Array
var R: Px.Rng
var A: Dictionary
var sh: PackedByteArray
var ps: Px.Particles
var lights: Px.Lights
var mx: float
var my: float
var COLS: Array
var t := 0.0
var out := false
var popped := false


func inside(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < A.w and y < A.h and A.mask.data[y * A.w + x]


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	R = Px.Rng.new(o.seed)
	A = o.actor
	sh = Lib.shades(A)
	ps = Px.Particles.new({"rng": R, "ground": func(): return 0.0, "sparks": [WHITE, C[6], C[5], C[4]]})
	lights = Px.Lights.new()
	mx = A.x + A.w / 2.0
	my = A.y + A.h * 0.55
	COLS = [WHITE, C[6], C[6], C[5], C[4]]


func update(dt: float) -> void:
	t += dt
	# gathering: streaks rush in to the chest
	if t < OUT - 0.04 and R.chance(0.7):
		var a := R.range(0.0, TAU)
		var D := R.range(22.0, 44.0)
		var T := R.range(0.12, 0.18)
		var v := (D * 3.0) / (exp(3.0 * T) - 1.0)
		var x := mx + cos(a) * D
		var y := minf(-2.0, my + sin(a) * D)
		var l := Px.hypot(x - mx, y - my)
		if not l:
			l = 1.0
		ps.spawn(P.STREAK, x, y, ((mx - x) / l) * v, ((my - y) / l) * v, T, C[6] if R.chance(0.5) else C[5])
	if not out and t >= OUT:
		out = true
		lights.add(mx, my - 6.0, 54.0, C[5], 0.9, 0.3)
		lights.add(mx, my, 26.0, WHITE, 0.8, 0.1)
	if not popped and t >= POP:
		popped = true
		lights.add(mx, my - 6.0, 58.0, C[5], 0.9, 0.35)
		lights.add(mx, my, 24.0, WHITE, 0.9, 0.08)
		# the line bursts: bits of the character fly off and drift up, sparks and stars scatter
		for i in 110:
			var y: float = A.y + R.range(2.0, A.h - 2.0)
			var s := R.sign()
			ps.spawn(P.EMBER, mx + R.range(-1.0, 1.0), y, s * R.range(25.0, 105.0), R.range(-70.0, 10.0), R.range(0.5, 0.95), R.pick(COLS), 2.0 if R.chance(0.3) else 1.0)
		for i in 18:
			var a := R.range(0.0, TAU)
			var sp := R.range(80.0, 240.0)
			ps.spawn(P.SPARK, mx, my, cos(a) * sp, sin(a) * sp - 40.0, R.range(0.2, 0.5))
		for i in 14:
			var a := R.range(0.0, TAU)
			var sp := R.range(20.0, 110.0)
			ps.spawn(P.STAR if i % 2 else P.MOTE, mx, my, cos(a) * sp, sin(a) * sp * 0.8 - 20.0, R.range(0.4, 0.9), R.pick([WHITE, C[6], C[5]]), R.range(0.8, 1.8))
	ps.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	var Aw: int = A.w
	var Ah: int = A.h
	# the afterimage it leaves, and the far half of the ring
	# the afterimage it leaves: a translucent violet ghost that thins away
	if t > POP and t < POP + 0.6:
		var ka := 0.5 * (1.0 - (t - POP) / 0.6)
		for y in Ah:
			for x in Aw:
				if sh[y * Aw + x]:
					p.blend(A.x + x, A.y + y, C[3] if sh[y * Aw + x] == 1 else C[4], ka)
	var k := (t - POP) / 0.5
	if k >= 0.0 and k < 1.0:
		Px.band(p, 0.0, 0.0, 4.0 + 30.0 * Px.Ease.outCubic(k), 0.2, maxf(1.0, 3.0 * (1.0 - k)), 1.15 - k, [C[3], C[5], C[6], WHITE], func(g: float) -> bool: return sin(g) < 0.0, k < 0.25)
	if t < POP + 0.3:
		p.glow(0.0, -1.0, 26.0, C[5], 0.3 * (t / OUT if t < OUT else 1.0 - Px.clamp((t - POP) / 0.3)))


func draw(p: Px.Painter) -> void:
	var Aw: int = A.w
	var Ah: int = A.h
	var f := floori(t * 30.0)
	if t < OUT:
		# the body brightens and an outline of light crackles round it, thicker as it gathers
		var kb := t / OUT
		for y in Ah:
			for x in Aw:
				if inside(x, y):
					# the body fills with light: its lit pixels most
					p.light(A.x + x, A.y + y, C[6], kb * kb * (0.3 if sh[y * Aw + x] == 1 else 0.75))
				elif (inside(x - 1, y) or inside(x + 1, y) or inside(x, y - 1) or inside(x, y + 1)) and Px.rand(x, y, f) < 0.25 + 0.65 * kb:
					p.px(A.x + x, A.y + y, WHITE if (kb > 0.6 and Px.rand(x, y, 7) < 0.5) else C[6])
		p.glow(mx, my, 30.0, C[5], 0.5 * kb)
	elif t < OUT + 0.05:
		Lib.squeezed(p, A, sh, 1.0, WHITE, C[6])
		p.glow(mx, my, 40.0, C[5], 0.8)
	elif t < OUT + SQUEEZE:
		# squeezed into a line
		var q := Px.Ease.inCubic((t - OUT - 0.05) / (SQUEEZE - 0.05))
		Lib.squeezed(p, A, sh, 1.0 - q, WHITE, C[6])
		p.glow(mx, my, 34.0, C[5], 0.8)
	elif t < POP:
		# the line shrinks to a point
		var q := (t - OUT - SQUEEZE) / COLLAPSE
		var hh := (Ah / 2.0 + 2.0) * (1.0 - Px.Ease.inQuad(q))
		var y := -hh - 3.0
		while y <= hh + 3.0:
			p.dot(mx, my + y, WHITE if absf(y) < hh else C[6], 1.0 if absf(y) < hh else 0.7)
			y += 1.0
		if hh > 4.0:
			y = -hh * 0.7
			while y <= hh * 0.7:
				p.dot(mx - 1.0, my + y, C[5], 0.6)
				p.dot(mx + 1.0, my + y, C[5], 0.6)
				y += 1.0
		p.glow(mx, my, 30.0, C[5], 0.9)
		p.glow(mx, my, 8.0, WHITE, 0.5)
	if t >= POP and t < POP + 0.22:
		var q := (t - POP) / 0.22
		Px.flare(p, mx, my, 22.0 * pow(1.0 - q, 1.5) + 2.0, 1.0 - q, C)
		if q < 0.3:
			p.circle(mx, my, 4.0 * (1.0 - q / 0.3) + 1.0, WHITE)
	var k := (t - POP) / 0.5
	if k >= 0.0 and k < 1.0:
		Px.band(p, 0.0, 0.0, 4.0 + 30.0 * Px.Ease.outCubic(k), 0.2, maxf(1.0, 3.0 * (1.0 - k)), 1.15 - k, [C[3], C[5], C[6], WHITE], func(g: float) -> bool: return sin(g) >= 0.0, k < 0.25)
	if t > POP and t < POP + 0.3:
		Px.sparkle(p, mx, my - 1.0, 3.0, C[6], C[5], 0.3 * (1.0 - (t - POP) / 0.3))
	ps.draw(p)
	lights.draw(p)
