# The arrival (bits converging, a line of light that opens into the silhouette, a ring on the floor, a burst of
# stars) is adapted from Sprite Fusion's open-source blink (https://www.spritefusion.com/pixel-art-vfx/movement),
# MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/arcane/blink-in.js@ae7ec5071adacf19538e28d2d6022cd00315d1b6
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const WHITE := Px.WHITE

const LINE := 0.26
const GROW := 0.1
const OPEN := 0.12
const ARRIVE := LINE + GROW + OPEN

static var meta := {
	"name": "Blink in",
	"desc": "Glittering bits spiral in to a point of light that opens into a line, then into a white silhouette that cools into the caster.",
	"tags": ["arcane", "blink", "teleport", "appear", "movement", "magic", "one-shot"],
	"size": [136, 96],
	"origin": [68, 80],
	"duration": 1.4,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"actor": 2,
	"options": {"palette": Px.PAL.arcane, "seed": 12},
}

static var LANDED := {"crouch": 7, "lean": 3, "fx": 9, "fy": -12, "bx": 12, "by": -12, "ffx": 8, "fbx": -6}
static var act := {
	"onBody": true,
	"poses": [
		[0, LANDED],
		[0.48, LANDED],
		[0.56, Px.merge(LANDED, {"crouch": 6}), "snap"],
		[0.95, Px.READY],
		[1.4, Px.READY],
	],
	"hits": [{"t": 0.48, "stop": 0.03, "shake": 0.1, "amp": 1}],
	"dust": [{"t": 0.48, "x": 0, "n": 7}],
}

## The stand-in character appears once the silhouette has opened.
static func actorAlpha(t: float, _o: Dictionary) -> float:
	return 0.0 if t < ARRIVE else 1.0


var C: Array
var R: Px.Rng
var A: Dictionary
var sh: PackedByteArray
var ps: Px.Particles
var lights: Px.Lights
var mx: float
var my: float
var COLS: Array
var bits: Array
var t := 0.0
var arrived := false


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
	# the bits: each spirals in from its own spot to a point on the line, arriving as the line forms
	bits = Px.arr(230, func(_i):
		var a := R.range(0.0, TAU)
		var d := R.range(16.0, 46.0)
		var ty: float = A.y + R.range(3.0, A.h - 2.0)
		var oy := sin(a) * d * 0.8 - 6.0
		if ty + oy > -2.0:
			oy = -absf(oy) - 2.0  # none start under the floor
		return {"tx": mx + R.range(-1.0, 1.0), "ty": ty, "ox": cos(a) * d, "oy": oy, "t0": R.range(0.0, 0.1), "t1": LINE + R.range(-0.02, GROW), "spin": R.range(0.8, 1.8) * R.sign(), "c": R.pick(COLS)})


static func at(b: Dictionary, tt: float) -> Array:
	var k := Px.clamp((tt - b.t0) / (b.t1 - b.t0))
	var e := Px.Ease.outCubic(k)
	var r := 1.0 - e
	var sp: float = b.spin * r * 1.2
	var ox: float = b.ox * cos(sp) - b.oy * sin(sp)
	var oy: float = b.ox * sin(sp) + b.oy * cos(sp)
	return [b.tx + ox * r, minf(-1.0, b.ty + oy * r), k]


func update(dt: float) -> void:
	t += dt
	if t < LINE and R.chance(0.6):
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
	if not arrived and t >= ARRIVE:
		arrived = true
		lights.add(mx, my - 6.0, 56.0, C[5], 0.9, 0.35)
		lights.add(mx, my, 24.0, WHITE, 0.8, 0.1)
		for i in 30:
			var a := R.range(0.0, TAU)
			var sp := R.range(35.0, 110.0)
			ps.spawn(P.STAR if R.chance(0.6) else P.MOTE, mx, my, cos(a) * sp, sin(a) * sp * 0.7 - 30.0, R.range(0.4, 0.85), R.pick(COLS), R.range(0.6, 1.6))
		for i in 12:
			var s := R.sign()
			ps.spawn(P.SPARK, mx + s * R.range(2.0, 8.0), -1.0, s * R.range(60.0, 180.0), -R.range(20.0, 110.0), R.range(0.2, 0.45))
	ps.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	var k := (t - ARRIVE + 0.03) / 0.5
	if k >= 0.0 and k < 1.0:
		Px.band(p, 0.0, 0.0, 4.0 + 30.0 * Px.Ease.outCubic(k), 0.2, maxf(1.0, 3.0 * (1.0 - k)), 1.15 - k, [C[3], C[5], C[6], WHITE], func(g: float) -> bool: return sin(g) < 0.0, k < 0.25)
	p.glow(0.0, -1.0, 26.0, C[5], 0.3 * (t / ARRIVE if t < ARRIVE else 1.0 - Px.clamp((t - ARRIVE) / 0.5)))


func draw(p: Px.Painter) -> void:
	var Aw: int = A.w
	var Ah: int = A.h
	# the bits rushing in, streaking as they speed up, white as they land
	for b: Dictionary in bits:
		if t < b.t0 or t > b.t1 + 0.02:
			continue
		var xyk := at(b, t)
		var x: float = xyk[0]
		var y: float = xyk[1]
		var k: float = xyk[2]
		p.dot(x, y, WHITE if k > 0.75 else b.c, minf(1.0, 0.35 + k * 2.0))
		# a short tail once they're rushing
		if k > 0.55:
			var pp := at(b, t - 0.015)
			p.dot((x + pp[0]) / 2.0, (y + pp[1]) / 2.0, C[5], 0.8)
		if k > 0.8:
			p.glow(x, y, 3.0, C[6], 0.3)
	if t >= LINE - 0.04 and t < LINE:
		# a point of light where it gathers
		var q := (t - LINE + 0.04) / 0.04
		Px.sparkle(p, mx, my, 2.0 + 3.0 * q, C[6], C[5], 0.6)
	elif t >= LINE and t < LINE + GROW:
		# it opens into a line, top to bottom
		var q := Px.Ease.outCubic((t - LINE) / GROW)
		var hh := (Ah / 2.0 + 3.0) * q
		var y := -hh - 2.0
		while y <= hh + 2.0:
			p.dot(mx, my + y, WHITE if absf(y) < hh else C[6], 1.0 if absf(y) < hh else 0.7)
			y += 1.0
		y = -hh * 0.7
		while y <= hh * 0.7:
			p.dot(mx - 1.0, my + y, C[5], 0.6)
			p.dot(mx + 1.0, my + y, C[5], 0.6)
			y += 1.0
		p.glow(mx, my, 30.0, C[5], 0.9)
		p.glow(mx, my, 8.0, WHITE, 0.5)
	elif t >= LINE + GROW and t < ARRIVE:
		# the line opens sideways into the silhouette, white hot
		var q := Px.Ease.outCubic((t - LINE - GROW) / OPEN)
		Lib.squeezed(p, A, sh, q, WHITE, C[6])
		p.glow(mx, my, 36.0, C[5], 0.8)
	elif t >= ARRIVE and t < ARRIVE + 0.42:
		# the caster cools out of the white: its body full of light, an outline crackling round it, both fading
		var kc := 1.0 - (t - ARRIVE) / 0.42
		var f := floori(t * 30.0)
		if kc > 0.86:
			Lib.squeezed(p, A, sh, 1.0, WHITE, C[6])
		for y in Ah:
			for x in Aw:
				if inside(x, y):
					p.light(A.x + x, A.y + y, C[6], kc * kc * (0.3 if sh[y * Aw + x] == 1 else 0.8))
				elif (inside(x - 1, y) or inside(x + 1, y) or inside(x, y - 1) or inside(x, y + 1)) and Px.rand(x, y, f) < 0.85 * kc:
					p.px(A.x + x, A.y + y, WHITE if (kc > 0.5 and Px.rand(x, y, 7) < 0.5) else C[6])
		p.glow(mx, my, 34.0, C[5], 0.6 * kc)
	if t >= ARRIVE and t < ARRIVE + 0.2:
		var q := (t - ARRIVE) / 0.2
		Px.flare(p, mx, my - 4.0, 18.0 * pow(1.0 - q, 1.5) + 2.0, 1.0 - q, C)
	var k := (t - ARRIVE + 0.03) / 0.5
	if k >= 0.0 and k < 1.0:
		Px.band(p, 0.0, 0.0, 4.0 + 30.0 * Px.Ease.outCubic(k), 0.2, maxf(1.0, 3.0 * (1.0 - k)), 1.15 - k, [C[3], C[5], C[6], WHITE], func(g: float) -> bool: return sin(g) >= 0.0, k < 0.25)
	ps.draw(p)
	lights.draw(p)
