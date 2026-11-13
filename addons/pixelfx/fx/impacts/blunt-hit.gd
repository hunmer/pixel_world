# The clods and the dust they kick up are adapted from Sprite Fusion's open-source explosion
# (https://www.spritefusion.com/pixel-art-vfx/explosion), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/impacts/blunt-hit.js@f21317155d505cf1a7e923da26bff062a062edeb
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const B := Px.B
const WHITE := Px.WHITE

static var meta := {
	"name": "Blunt hit",
	"desc": "A heavy, soft thud: a white-hot lumpy blob cools to cream in a warm pool of light, inked wedges jab out and snap back, a squashed ring of dust puffs swells and drifts, clods drop.",
	"tags": ["impact", "hit", "blunt", "punch", "club", "thump", "dust", "comic", "one-shot"],
	"size": [128, 88],
	"origin": [64, 72],
	"duration": 0.9,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": ["#1d1620", "#4a3a3c", "#7d6a66", "#b09c90", "#dccab4", "#f6ead2", "#ffffff"], "warm": "#ffc98a", "dust": "#b7a8a6", "clod": "#6e5a5a", "height": 22, "seed": 9},
}


# a lumpy outline: radius at angle a for a blob of radius r
static func lump(r: float, a: float, ph: float) -> float:
	return r * (1.0 + 0.15 * sin(5.0 * a + ph) + 0.08 * sin(9.0 * a + ph * 2.3))


var C: Array
var R: Px.Rng
var X := 0.0
var Y: float
var PH: float
var WARM: int
var DUST: int
var st: Dictionary
var lights: Px.Lights
var bits: Px.Bits
var wedges: Array
var puffs: Array
var kicks: Array
var t := 0.0


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 7)
	R = Px.Rng.new(o.seed)
	Y = -o.height
	PH = R.range(0.0, TAU)
	var floor_ := func(): return 0.0
	WARM = Px.hex(o.warm)
	DUST = Px.hex(o.dust)
	st = Lib.stone(o.clod)
	lights = Px.Lights.new()
	bits = Px.Bits.new({"ground": floor_})
	# a warm pool of light, a white-hot heart, and a glow on the floor below
	lights.add(X, Y, 48.0, WARM, 0.6, 0.4)
	lights.add(X, Y, 16.0, WHITE, 0.6, 0.07)
	lights.add(X, -2.0, 36.0, WARM, 0.25, 0.4)
	# inked wedges: each jabs out at its own length and pace, then snaps back
	wedges = Px.arr(9, func(i: int): return {"a": (i / 9.0) * TAU + R.range(-0.2, 0.2), "len": R.range(6.0, 15.0), "w": R.range(3.2, 5.0), "r0": R.range(13.0, 16.0), "t0": R.range(0.015, 0.04), "out": R.range(0.04, 0.06), "back": R.range(0.09, 0.14)})
	# the squash ring: soft puffs flung out from the blob's rim, wider than tall, each its own size, pace and life
	puffs = Px.arr(30, func(i: int):
		var a := (i / 30.0) * TAU + R.range(-0.12, 0.12)
		var side := absf(cos(a))
		var v := R.range(40.0, 140.0) * (0.6 + 0.5 * side)
		return {"x": X + cos(a) * 9.0, "y": Y + sin(a) * 6.0, "vx": cos(a) * v, "vy": sin(a) * v * 0.5, "r": R.range(2.4, 6.2) * (0.75 + 0.35 * side), "life": R.range(0.35, 0.85), "max": 0.0, "t0": R.range(0.03, 0.1), "lift": R.range(4.0, 16.0)})
	# and a few that billow up off the top and hang longer
	for i in 5:
		puffs.append({"x": X + R.range(-6.0, 6.0), "y": Y - R.range(3.0, 6.0), "vx": R.range(-30.0, 30.0), "vy": -R.range(20.0, 45.0), "r": R.range(3.5, 5.5), "life": R.range(0.6, 0.85), "max": 0.0, "t0": R.range(0.05, 0.1), "lift": R.range(14.0, 24.0)})
	for q: Dictionary in puffs:
		q.max = q.life
	# heavier clods knocked loose: they arc out, drop to the floor, bounce once and settle
	for i in 5:
		var s := R.sign()
		var a := -PI / 2.0 + s * R.range(0.5, 1.3)
		var v := R.range(70.0, 140.0)
		bits.add({"kind": B.CHUNK, "x": X + s * R.range(4.0, 8.0), "y": Y + R.range(-3.0, 3.0), "vx": cos(a) * v, "vy": sin(a) * v, "g": 1.0, "drag": 0.6, "bounce": 0.28, "life": R.range(0.65, 0.85), "a": R.range(0.0, TAU), "va": s * R.range(8.0, 16.0), "s": 2.0 if R.chance(0.4) else 1.0, "pts": Lib.rockShape(R), "pvy": 0.0})
	kicks = []


func update(dt: float) -> void:
	t += dt
	for q: Dictionary in puffs:
		if t < q.t0:
			continue
		q.life -= dt
		q.vx -= q.vx * 4.5 * dt
		q.vy -= q.vy * 4.5 * dt + (q.lift if q.get("lift") != null else 6.0) * dt # they slow, and lift a little as they thin
		q.x += q.vx * dt
		q.y += q.vy * dt
	for b: Dictionary in bits.list:
		b.pvy = b.vy
	bits.update(dt)
	# a clod hitting the floor kicks a little dust
	for b: Dictionary in bits.list:
		if b.pvy > 60.0 and b.vy <= 0.0:
			for i in 2:
				kicks.append({"x": b.x, "y": -1.0, "vx": R.sign() * R.range(8.0, 22.0), "vy": -R.range(3.0, 10.0), "r": R.range(1.2, 2.0), "life": 0.4, "max": 0.4, "t0": 0.0})
			b.pvy = 0.0
	for q: Dictionary in kicks:
		q.life -= dt
		q.vx -= q.vx * 4.0 * dt
		q.vy -= q.vy * 4.0 * dt
		q.x += q.vx * dt
		q.y += q.vy * dt
	lights.update(dt)


func draw(p: Px.Painter) -> void:
	# dust: each puff swells and thins, warm-lit at first, its top catching the light
	for q: Dictionary in puffs + kicks:
		var k: float = q.life / q.max
		if t < q.t0 or k <= 0.0:
			continue
		var r: float = q.r * (0.7 + (1.0 - k) * 0.85)
		var a: float = pow(k, 1.25) * minf(1.0, (t - q.t0) / 0.03)
		var c := Px.mix(DUST, WARM, Px.clamp(1.0 - (t - 0.03) / 0.25) * 0.55)
		p.disc(q.x, q.y, r, c, func(d): return 0.58 * a * (1.0 - d * d * 0.75))
		p.disc(q.x - r * 0.22, q.y - r * 0.32, r * 0.58, Px.mix(c, WHITE, 0.55), func(d): return 0.48 * a * (1.0 - d * d))
	for b: Dictionary in bits.list:
		Lib.rock(p, b, st)
	# the blob: white-hot and lumpy for a frame, then cream and a little bigger, then gone into the dust
	if t < 0.058:
		var f := 0 if t < 0.025 else 1
		var R0 := 13.5 if f else 11.5
		p.shade(X - R0 * 1.4, Y - R0 * 1.4, X + R0 * 1.4, Y + R0 * 1.4, func(x, y):
			var dx: float = x - X
			var dy: float = (y - Y) * (1.25 if f else 1.1)
			var d := Px.hypot(dx, dy)
			var ro := lump(R0, atan2(dy, dx), PH + f * 0.6)
			if d > ro:
				return
			var q := d / ro
			return (WHITE if q < 0.55 else (C[5] if q < 0.86 else C[4])) if f == 0 else (WHITE if q < 0.3 else (C[5] if q < 0.72 else (C[4] if q < 0.9 else C[3]))))
	# inked wedges jab out from the blob and snap back
	for w: Dictionary in wedges:
		var u: float = t - w.t0
		if u < 0.0 or u > w.out + w.back:
			continue
		var s: float = Px.Ease.outCubic(u / w.out) if u < w.out else 1.0 - Px.Ease.inQuad((u - w.out) / w.back)
		var L: float = w.len * s
		if L < 1.5:
			continue
		var ca := cos(w.a)
		var sa := sin(w.a)
		var r0: float = w.r0 + 2.0 * s
		var hw: float = (w.w * (0.6 + 0.4 * s)) / 2.0
		var tip := [X + ca * r0, Y + sa * r0]
		var end := [X + ca * (r0 + L), Y + sa * (r0 + L)]
		var n := [-sa * hw, ca * hw]
		p.poly(wedge(tip, end, n, ca, sa, 1.0), C[1])
		p.poly(wedge(tip, end, n, ca, sa, 0.0), WHITE if u < w.out + 0.02 else C[5])
	var pop := exp(-t / 0.06)
	if pop > 0.02:
		p.glow(X, Y, 28.0, WARM, 0.5 * pop)
	lights.draw(p)


static func wedge(tip: Array, end: Array, n: Array, ca: float, sa: float, g: float) -> Array:
	return [[tip[0] - ca * g, tip[1] - sa * g], [end[0] + n[0] * (1.0 + g * 0.45) + ca * g, end[1] + n[1] * (1.0 + g * 0.45) + sa * g], [end[0] - n[0] * (1.0 + g * 0.45) + ca * g, end[1] - n[1] * (1.0 + g * 0.45) + sa * g]]
