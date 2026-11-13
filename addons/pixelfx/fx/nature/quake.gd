# The ground's part (grit thrown up that bounces and settles, stones that tumble and kick up dust where they land,
# dust rolling out along the floor and climbing) is adapted from Sprite Fusion's open-source explosion
# (https://www.spritefusion.com/pixel-art-vfx/explosion), MIT License, Copyright (c) 2026 Hugo Duprez.
# port-of: src/fx/nature/quake.js@6fc162d3ec14caca1b85916579ee36b633ad3383
extends "../../core/effect.gd"

const Px := preload("../../core/px.gd")
const Lib := preload("_lib.gd")
const P := Px.P
const PF := Px.PF
const B := Px.B
const WHITE := Px.WHITE

static var meta := {
	"name": "Quake",
	"desc": "The ground jolts three times: a rift tears out along the floor glowing deep inside, slabs of floor heave up and drop back askew, pebbles hop and dust bursts out of the split.",
	"tags": ["nature", "earth", "quake", "rift", "aoe", "ground", "one-shot"],
	"size": [288, 104],
	"origin": [144, 88],
	"duration": 3.1,
	"loop": false,
	"fps": 30,
	"bg": "ground",
	"options": {
		"palette": ["#0e0c14", "#1a1724", "#211d2d", "#2b2639", "#3a3450", "#4a4263", "#6a6088", "#8e86a8"],
		"glow": ["#4a1a0c", "#a8401a", "#ff8a2a", "#ffd27a", "#fff4d0"],
		"reach": 118,
		"seed": 12,
	},
}

const JOLTS := [0.06, 0.5, 0.92]
const CLOSE := 2.2

var S: Array
var G: Array
var R: Px.Rng
var REACH: float
var DUST: int
var DUST2: int
var ps: Px.Particles
var bits: Px.Bits
var lights: Px.Lights
var rift: Array
var slabs: Array
var t := 0.0
var j := 0


func create(o: Dictionary) -> void:
	S = Px.fit(o.palette, 8)
	G = Px.fit(o.glow, 5)
	R = Px.Rng.new(o.seed)
	var floor_ := func(): return 0.0
	REACH = o.reach
	DUST = Px.mix(S[6], Px.hex("#8c8494"), 0.4)
	DUST2 = Px.mix(S[5], Px.hex("#6c6474"), 0.35)
	ps = Px.Particles.new({"rng": R, "ground": floor_, "sparks": [G[4], G[3], G[2], G[1]]})
	bits = Px.Bits.new({"ground": floor_})
	lights = Px.Lights.new()
	# the rift: a jagged line out both ways, its depth into the floor at each step
	rift = []
	var x := -REACH
	while x <= REACH:
		rift.append([x, float(R.int_(0, 2))])
		x += R.range(2.5, 5.0)
	slabs = []
	x = -REACH + 8.0
	while x < REACH - 6.0:
		slabs.append({"x": x + R.range(-2.0, 2.0), "y": 0.0, "vy": 0.0, "a": 0.0, "va": 0.0, "rest": true, "s": R.range(4.5, 6.0), "side": R.sign(), "pts": [[-1.0, -0.38], [1.0, -0.42], [1.02, 0.4], [-0.98, 0.38]]})
		x += R.range(12.0, 17.0)
	t = 0.0
	j = 0


func open() -> float:
	return Px.Ease.outCubic(Px.clamp((t - JOLTS[0]) / 0.45)) * REACH * (0.55 + 0.45 * Px.smooth(JOLTS[1], JOLTS[1] + 0.3, t))


func gap(x: float) -> float:
	return (1.0 - Px.smooth(CLOSE, CLOSE + 0.5, t)) * (1.0 + 2.6 * (1.0 - absf(x) / REACH)) * (0.6 + 0.4 * Px.smooth(JOLTS[1], JOLTS[2] + 0.2, t))


func heat() -> float:
	return Px.smooth(0.0, 0.3, t) * (1.0 - Px.smooth(1.4, CLOSE + 0.3, t)) * (0.8 + 0.2 * sin(t * 17.0))


func shake() -> float:
	var s := 0.0
	for i in JOLTS.size():
		var tj: float = JOLTS[i]
		s = s + Px.exp(-(t - tj) * 9.0) * sin((t - tj) * 80.0) * (1.6 - i * 0.3) if t > tj else s
	return s


func update(dt: float) -> void:
	t += dt
	var f := minf(1.0, dt * 120.0)
	while j < JOLTS.size() and t >= JOLTS[j]:
		var k := 1.0 - j * 0.2
		var L := open() + 10.0
		j += 1
		lights.add(0.0, -2.0, 60.0, G[2], 0.5 * k, 0.5)
		lights.add(0.0, -2.0, 26.0, WHITE, 0.4 * k, 0.07)
		# the floor heaves: slabs along the split jump and twist, pebbles and stones hop, dust bursts out
		for s: Dictionary in slabs:
			var d: float = absf(s.x) / REACH
			if absf(s.x) > L or R.chance(0.25 + d * 0.3):
				continue
			s.rest = false
			s.vy = -R.range(70.0, 170.0) * k * (1.0 - d * 0.5)
			s.va = s.side * R.range(3.0, 8.0)
		var i := 0
		while i < 70.0 * k:
			var x := R.range(-L, L)
			var a := -PI / 2.0 + R.range(-0.6, 0.6)
			var sp := R.range(40.0, 200.0) * k
			ps.spawn(P.GRIT, x, -1.0, cos(a) * sp, sin(a) * sp, R.range(0.6, 1.2), R.pick([S[7], S[6], S[5], S[4]]), 2.0 if R.chance(0.35) else 1.0)
			i += 1
		i = 0
		while i < 8.0 * k:
			var x := R.range(-L, L) * 0.8
			var a := -PI / 2.0 + R.range(-0.9, 0.9)
			var sp := R.range(100.0, 230.0) * k
			bits.add({"kind": B.CHUNK, "x": x, "y": -2.0, "vx": cos(a) * sp, "vy": sin(a) * sp, "g": 1.0, "drag": 0.5, "bounce": 0.3, "life": minf(R.range(1.1, 1.6), meta.duration - 0.1 - t), "a": R.range(0.0, TAU), "va": R.range(-14.0, 14.0), "s": R.range(1.6, 3.2), "pts": Lib.stoneShape(R)})
			i += 1
		i = 0
		while i < 14.0 * k:
			var x := R.range(-L, L) * 0.9
			ps.spawn(P.SMOKE, x, -R.range(1.0, 4.0), R.range(-40.0, 40.0), -R.range(15.0, 55.0) * k, R.range(1.0, 1.7), DUST if R.chance(0.5) else DUST2, R.range(4.0, 7.0) * k, R.range(0.0, 0.15), PF.BIG)
			i += 1
		i = 0
		while i < 10.0 * k:
			var x := R.range(-L, L) * 0.7
			var a := -PI / 2.0 + R.range(-1.0, 1.0)
			var sp := R.range(120.0, 300.0)
			ps.spawn(P.SPARK, x, -1.0, cos(a) * sp, sin(a) * sp, R.range(0.12, 0.3))
			i += 1
	# between jolts the split keeps breathing grit and wisps of dust, embers float up out of it
	if t > JOLTS[0] and t < CLOSE and R.chance(0.3 * f):
		var x := R.range(-1.0, 1.0) * open()
		ps.spawn(P.GRIT, x, -1.0, R.range(-20.0, 20.0), -R.range(20.0, 70.0), R.range(0.5, 0.8), R.pick([S[6], S[5]]), 1.0)
		if R.chance(0.3):
			ps.spawn(P.EMBER, x, -1.0, R.range(-10.0, 10.0), -R.range(20.0, 45.0), minf(R.range(0.6, 1.2), meta.duration - 0.1 - t), G[3], 1.0)
		if R.chance(0.25):
			ps.spawn(P.DUST, x, -1.0, R.range(-15.0, 15.0), -R.range(4.0, 14.0), R.range(0.5, 0.8), DUST2, R.range(2.0, 3.5))
	for s: Dictionary in slabs:
		if s.rest:
			continue
		s.vy += 950.0 * dt
		s.y += s.vy * dt
		s.a += s.va * dt
		if s.y >= 0.0 and s.vy > 0.0:
			s.y = 0.0
			s.a = Px.clamp(s.a, -0.45, 0.45)
			if s.vy > 160.0:
				s.vy *= -0.25
				s.va *= -0.4
			else:
				s.rest = true
				for i in 3:
					ps.spawn(P.DUST, s.x + R.range(-5.0, 5.0), -0.5, R.sign() * R.range(10.0, 40.0), -R.range(2.0, 12.0), R.range(0.4, 0.7), DUST2, R.range(1.5, 3.0))
	bits.update(dt)
	for b: Dictionary in bits.list:
		if b.rest and not b.get("dusted", false):
			b.dusted = true
			ps.spawn(P.DUST, b.x, -0.5, R.sign() * R.range(8.0, 30.0), -R.range(2.0, 10.0), minf(R.range(0.3, 0.6), meta.duration - 0.1 - t), DUST2, R.range(1.3, 2.4))
	ps.update(dt)
	lights.update(dt)


func drawBack(p: Px.Painter) -> void:
	# the rift: lit along its upper lip, dark inside with a deep glow, opening out from the middle
	var L := open()
	var hk := heat()
	var jx := shake()
	var fade := 1.0 - Px.smooth(CLOSE + 0.3, CLOSE + 0.7, t)
	if t > JOLTS[0]:
		for i in range(1, rift.size()):
			var x0: float = rift[i - 1][0]
			var d0: float = rift[i - 1][1]
			var x1: float = rift[i][0]
			var d1: float = rift[i][1]
			if absf(x0) > L:
				continue
			var x := ceili(x0)
			while x < x1:
				var u := (x - x0) / (x1 - x0)
				var d := Px.round(d0 + (d1 - d0) * u)
				var w := gap(x)
				var X := x + jx
				if w < 0.4:
					p.dot(X, d, S[1], fade)
					x += 1
					continue
				p.dot(X, d - 1.0, S[6], fade)
				var deep := Px.rand(floori(x / 3.0), 41) + (w - 1.5) * 0.35
				var hot := hk * Px.clamp(deep - 0.35, 0.0, 1.0) * 1.6
				var y := 0
				while y < w:
					p.dot(X, d + y, ((G[3] if (hot > 0.9 and Px.rand(x, floori(t * 12.0)) < 0.6) else G[2]) if (y > w / 2.0 - 1.0 and hot > 0.25) else (G[1] if (y > w / 2.0 - 1.0 and hot > 0.08) else S[0])), fade)
					y += 1
				p.dot(X, d + ceilf(w), S[2], fade)
				x += 1
			if i % 3 == 0 and hk > 0.0:
				p.glow(x1 + jx, d1 + 1.0, 9.0, G[2], 0.35 * hk * (1.0 - absf(x1) / (REACH * 1.2)))
	ps.draw(p, "back")


func draw(p: Px.Painter) -> void:
	# slabs of floor heaved up out of it, tilted, sinking back as it closes
	var jx := shake()
	var sink := Px.smooth(CLOSE, CLOSE + 0.6, t)
	for s: Dictionary in slabs:
		if not (s.rest and s.a == 0.0 and s.y == 0.0) and sink < 1.0:
			Lib.drawRock(p, s.x + jx, s.y - 1.5 + sink * 4.0, s.s, s.a, s.pts, S, 1.0 - sink)
	for b: Dictionary in bits.list:
		Lib.drawRock(p, b.x, b.y, b.s, b.a, b.pts, S, minf(1.0, b.life / 0.4))
	ps.draw(p, "front")
	lights.draw(p)
