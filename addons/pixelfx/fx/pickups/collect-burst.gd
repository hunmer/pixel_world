# The pop (a white flash, a ring snapping out, star sparks with short trails) follows Sprite Fusion's
# open-source pickup (https://www.spritefusion.com/pixel-art-vfx/pickup), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/pickups/collect-burst.js@8c5771f6c5125f133a103c4643cc0d1d6af5fbee
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const WHITE := Px.WHITE

static var meta := {
	"name": "Collect burst",
	"desc": "The moment of pickup: a white flash and a cross of light, a thin ring snapping out ahead of a softer one, twinkles thrown wide on curving paths that brake, hang and wink out.",
	"tags": ["pickup", "collect", "burst", "sparkle", "reward", "one-shot"],
	"size": [112, 108],
	"origin": [56, 94],
	"duration": 1.35,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"options": {"palette": ["#1a0516", "#3d0a33", "#701560", "#b0228f", "#f53cd1", "#ff86e6", "#ffd2f6", "#ffffff"], "seed": 3},
}

const CY := -30.0

var C: Array
var R: Px.Rng
var lights: Px.Lights
var stars: Array
var motes: Array
var t := 0.0


func create(o: Dictionary) -> void:
	C = Px.fit(o.palette, 8)
	R = Px.Rng.new(o.seed)
	lights = Px.Lights.new()
	lights.add(0.0, CY, 36.0, C[5], 0.85, 0.32)
	lights.add(0.0, CY, 14.0, WHITE, 0.75, 0.08)
	# twinkles thrown out on curving paths: each one's heading turns as it flies, and drag brakes it
	stars = Px.arr(14, func(i: int) -> Dictionary:
		var a := (i / 14.0) * TAU + R.range(-0.2, 0.2)
		var sp := R.range(145.0, 225.0) * (1.12 if i % 3 == 0 else 0.85)
		return {"x": 0.0, "y": CY, "a": a, "sp": sp, "turn": (1.0 if i % 2 else -1.0) * R.range(2.5, 5.0), "life": R.range(0.75, 1.15), "age": 0.0, "size": 2.6 if i % 3 == 0 else R.range(1.2, 2.0), "tr": [], "c": WHITE if i % 4 == 0 else (C[6] if i % 2 else C[5]), "ph": R.range(0.0, TAU)})
	motes = Px.arr(7, func(_i: int) -> Dictionary: return {"x": R.range(-8.0, 8.0), "y": CY + R.range(-4.0, 6.0), "vy": -R.range(12.0, 30.0), "life": R.range(0.5, 0.9), "d": R.range(0.05, 0.25), "w": R.range(0.0, TAU)})


func update(dt: float) -> void:
	t += dt
	for s: Dictionary in stars:
		if s.age > s.life:
			continue
		s.age += dt
		s.tr.push_front([s.x, s.y])
		if s.tr.size() > 4:
			s.tr.pop_back()
		s.a += s.turn * dt * maxf(0.0, 1.0 - s.age * 1.5)
		s.sp -= s.sp * 4.3 * dt
		s.x += cos(s.a) * s.sp * dt
		s.y += sin(s.a) * s.sp * dt + 6.0 * s.age * dt
		# the floor turns them back up
		if s.y > -2.0:
			s.y = -2.0
			s.a = -absf(s.a)
			s.sp *= 0.5
	lights.update(dt)


func draw(p: Px.Painter) -> void:
	# the flash: a white disc and a cross of light, gone in a few frames
	if t < 0.07:
		p.circle(0.0, CY, 5.5 * (1.0 - t / 0.07) + 1.0, WHITE)
	if t < 0.16:
		var k := 1.0 - t / 0.16
		var L := 26.0 * Px.Ease.outCubic(minf(1.0, t / 0.03 + 0.4)) * k
		for e: Array in [[1.0, 0.0, 1.0], [-1.0, 0.0, 1.0], [0.0, 1.0, 0.6], [0.0, -1.0, 0.6]]:
			var dx: float = e[0]
			var dy: float = e[1]
			var l: float = e[2]
			p.line(0.0, CY, dx * L * l, CY + dy * L * l, func(u: float) -> int: return WHITE if u < 0.3 else (C[6] if u < 0.65 else C[5]), func(u: float) -> float: return (1.0 if u < 0.5 else (1.0 - u) * 2.0) * (0.5 + k))
		p.glow(0.0, CY, 20.0 * k + 4.0, C[5], 0.6 * k)
	# a thin ring snapping out fast, a softer ring following
	var u1 := t / 0.32
	if u1 < 1.0:
		var r := 3.0 + 23.0 * Px.Ease.outExpo(u1)
		p.ring(0.0, CY, r, 1.0, WHITE if u1 < 0.3 else C[6], 1.3 - u1 * 1.2)
		p.glowRing(0.0, CY, r, 4.0, C[5], 0.4 * (1.0 - u1))
	var u2 := (t - 0.04) / 0.5
	if u2 > 0.0 and u2 < 1.0:
		var r := 2.0 + 16.0 * Px.Ease.outCubic(u2)
		p.ring(0.0, CY, r, maxf(1.0, 2.6 * (1.0 - u2)), C[5], 1.0 - u2)
	# the twinkles, with short trails, flickering as they hang and wink out
	for s: Dictionary in stars:
		if s.age > s.life:
			continue
		var k: float = 1.0 - s.age / s.life
		var tw: float = 0.65 + 0.35 * sin(s.age * 26.0 + s.ph)
		for i in s.tr.size():
			if i > 0:
				p.dot(s.tr[i][0], s.tr[i][1], C[5] if i < 2 else C[4], (1.0 - i / 4.0) * k * 1.4)
		if k < 0.3 and sin(s.age * 40.0 + s.ph) < 0.0:
			continue
		Lib.glint(p, s.x, s.y, Px.round(s.size * tw * minf(1.0, k * 2.5)), s.c, 0.45 * k)
	# motes drifting up after
	for m: Dictionary in motes:
		var a: float = t - m.d
		if a < 0.0 or a > m.life:
			continue
		var k: float = 1.0 - a / m.life
		var x: float = m.x + sin(a * 6.0 + m.w) * 1.5
		var y: float = m.y + m.vy * a
		p.dot(x, y, C[6] if k > 0.5 else C[5], k * 1.5)
		p.glow(x + 0.5, y + 0.5, 3.0, C[5], 0.3 * k)
	lights.draw(p)
